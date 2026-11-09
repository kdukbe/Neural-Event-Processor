"""Validate the three RTL architectures against the selected datasets.

Run with Python. RTL compilation, simulation and results stay under build.
"""
import argparse
import concurrent.futures
import hashlib
import json
import re
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path
from tool_paths import build_root, glbl_source, vivado_bin

ROOT = Path(__file__).resolve().parents[1]
ARCHS = {
    'always_on_8mhz': (0, 62.5, 8, 512),
    'event_driven_8mhz': (1, 62.5, 8, 512),
    'always_on_1mhz': (0, 500.0, 16, 1024),
}
DATASETS = ('burst', 'real1', 'real2', 'real3')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, obj):
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding='utf-8')


def command(args, cwd, log):
    # Quoting also protects xsim plusargs containing '=' from cmd.exe splitting.
    cmd = ' '.join('"' + str(a) + '"' for a in args)
    with log.open('w', encoding='utf-8') as f:
        process = subprocess.run(cmd, cwd=cwd, stdout=f,
                                 stderr=subprocess.STDOUT, shell=True)
    if process.returncode:
        raise RuntimeError(f'{args[0]} exit={process.returncode}: {log}')


def rtl_sources(arch):
    sources = sorted((ROOT / 'HW/rtl/mainpath').glob('*.v'))
    sources += sorted((ROOT / 'HW/rtl/interface').glob('*.v'))
    if arch != 'event_driven_8mhz':
        overrides = ROOT / 'comparisons' / arch / 'rtl_overrides'
        sources = [(overrides / p.relative_to(ROOT/'HW/rtl')) if (overrides / p.relative_to(ROOT/'HW/rtl')).exists() else p for p in sources]
    return sources


def worker(arch, datasets, bin_dir, build, output, data_root):
    ed, half, od, wd = ARCHS[arch]
    work, out = build / 'simulation' / arch, output / arch
    work.mkdir(parents=True, exist_ok=True)
    out.mkdir(parents=True, exist_ok=True)
    sources = rtl_sources(arch)
    tb = ROOT / 'verification/tb_ThresholdConfig.sv'
    sources += [tb, glbl_source(bin_dir)]
    source_hashes = {p.as_posix(): sha(p) for p in sources}
    save(out / 'sources.json', source_hashes)
    print(f'COMPILE {arch}', flush=True)
    command([bin_dir / 'xvlog.bat', '-sv', *sources], work, work / 'compile.log')
    command([bin_dir / 'xelab.bat', 'tb_ThresholdConfig', 'glbl', '-L', 'unisims_ver',
             '-mt', '2', '-generic_top', f'EVENT_DRIVEN={ed}',
             '-generic_top', f'SFE_HALF_NS={half}',
             '-generic_top', f'OFIFO_DEPTH={od}',
             '-generic_top', f'WFIFO_DEPTH={wd}', '-s', 'threshold_sim'],
            work, work / 'elaborate.log')
    results = []
    for name in datasets:
        config = data_root / name
        meta = json.loads((config / 'metadata.json').read_text(encoding='utf-8'))
        half_sample = meta.get('input_half_period_ns', 1250.0)
        files = ('metadata.json', 'input.hex', 'golden.hex', 'feature.hex',
                 'sd_threshold.csv', 'sfe_feature.csv')
        hashes = {f: sha(config / f) for f in files}
        log = out / f'{name}.log'
        args = [bin_dir / 'xsim.bat', 'threshold_sim', '-runall',
                '-log', work / f'{name}_xsim.log']
        for key, value in {'DATA_DIR': config.as_posix(),
                           'ROWS': meta['replay_input_rows'], 'EVENTS': meta['events'],
                           'THRESHOLD': meta['threshold'],
                           'SAMPLE_HALF_NS': half_sample}.items():
            args += ['-testplusarg', f'{key}={value}']
        started = time.time()
        print(f'START {arch}/{name}: rows={meta["replay_input_rows"]} '
              f'events={meta["events"]} threshold={meta["threshold"]}', flush=True)
        error = None
        try:
            command(args, work, log)
        except RuntimeError as exc:
            error = str(exc)
        content = log.read_text(encoding='utf-8', errors='replace')
        summaries = [s for s in content.splitlines()
                     if s.startswith(('SUMMARY', 'COUNTERS', 'PASS', 'CONFIG_APPLIED'))]
        counters = {}
        for line in summaries:
            if line.startswith(('SUMMARY', 'COUNTERS')):
                counters.update({k: int(v) for k, v in re.findall(r'(\w+)=(\d+)', line)})
        unchanged = all(sha(config / f) == hashes[f] for f in files)
        passed = (error is None and 'PASS tb_ThresholdConfig:' in content
                  and not re.search(r'\b(?:ERROR|FATAL|FAIL)\b', content)
                  and counters.get('errors') == 0 and counters.get('drop') == 0
                  and counters.get('events') == meta['events']
                  and counters.get('golden') == meta['events']
                  and counters.get('detected') == meta['events'] and unchanged)
        result = dict(architecture=arch, dataset=name, passed=passed, error=error,
                      validation='RTL xsim: AXI configuration + RDMA + Core + WDMA',
                      finished_utc=datetime.now(timezone.utc).isoformat(),
                      elapsed_seconds=round(time.time() - started, 2),
                      threshold=meta['threshold'], expected_events=meta['events'],
                      input_rows=meta['replay_input_rows'],
                      main_mhz=1000/75, sfe_mhz=1000/(2*half),
                      sample_half_ns=half_sample, fifo_depths=[4, 16, od, wd],
                      counters=counters, config_dir=config.as_posix(),
                      data_sha256=hashes, inputs_unchanged=unchanged,
                      summary=summaries, saif_run=False, power_run=False,
                      board_run=False)
        save(out / f'{name}.json', result)
        print(('PASS ' if passed else 'FAIL ') + f'{arch}/{name}: {counters}', flush=True)
        results.append(result)
    if any(sha(Path(p)) != h for p, h in source_hashes.items()):
        raise RuntimeError(f'{arch}: RTL/TB changed while simulations ran')
    return results


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--architectures', nargs='+', choices=list(ARCHS), default=['event_driven_8mhz'])
    p.add_argument('--datasets', nargs='+', choices=DATASETS, default=['burst'])
    p.add_argument('--vivado-bin', help='Vivado installation bin directory; otherwise discover from environment/PATH')
    p.add_argument('--build-dir', help='Build root (default: project/build)')
    p.add_argument('--output-dir', help='Result directory (default: build/simulation/results)')
    p.add_argument('--data-root', type=Path, default=ROOT / 'data/prepared')
    p.add_argument('--dry-run', action='store_true', help='Check paths and show selected sources without running tools')
    args = p.parse_args()
    try:
        bin_dir = vivado_bin(args.vivado_bin)
    except ValueError as exc:
        p.error(str(exc))
    build = build_root(args.build_dir)
    output = Path(args.output_dir).resolve() if args.output_dir else build / 'simulation/results'
    data_root = args.data_root.resolve()
    for name in args.datasets:
        for filename in ('metadata.json', 'input.hex', 'golden.hex', 'feature.hex', 'sd_threshold.csv', 'sfe_feature.csv'):
            if not (data_root / name / filename).is_file():
                p.error(f'Missing input: {data_root / name / filename}')
    if args.dry_run:
        print(json.dumps(dict(vivado_bin=str(bin_dir), build_dir=str(build),
            output_dir=str(output), data_root=str(data_root), datasets=args.datasets,
            rtl={arch: [str(path) for path in rtl_sources(arch)] for arch in args.architectures}), indent=2))
        raise SystemExit(0)
    output.mkdir(parents=True, exist_ok=True)
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        futures = [pool.submit(worker, a, args.datasets, bin_dir, build, output, data_root) for a in args.architectures]
        for future in concurrent.futures.as_completed(futures):
            results.extend(future.result())
            save(output / 'results.json', results)
    results.sort(key=lambda r: (r['architecture'], DATASETS.index(r['dataset'])))
    save(output / 'results.json', results)
    print(f'COMPLETE {sum(r["passed"] for r in results)}/{len(results)} PASS', flush=True)
    raise SystemExit(0 if all(r['passed'] for r in results) else 1)
