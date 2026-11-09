"""Reproduce the 12 power cases using the preserved board implementations.

Uses existing routed checkpoints. Each stage records completion for resuming.
Run with --start; new files stay under build.
"""
import argparse
import concurrent.futures
from datetime import datetime, timezone
import hashlib
import json
import os
import shutil
from pathlib import Path
import subprocess
import sys
import threading
import time

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT.parent))
from tool_paths import build_root, vivado_bin
from portable_manifest import load_manifest

LOCK = threading.Lock()
RUN_MANIFEST = None
MODES = ['always_on_8mhz', 'event_driven_8mhz', 'always_on_1mhz']
DATASETS = ['burst', 'real1', 'real2', 'real3']


def now():
    return datetime.now(timezone.utc).isoformat()


def save(path, data):
    temp = path.with_suffix(path.suffix + '.tmp')
    temp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    temp.replace(path)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def mark(mode, dataset, stage, message=''):
    with LOCK:
        m = json.loads(RUN_MANIFEST.read_text(encoding='utf-8'))
        for job in m['jobs']:
            if job['system'] == mode and job['dataset'] == dataset:
                job.update(status=stage, message=message, updated_utc=now())
        if stage == 'Activity_running':
            m['simulation_started'] = True
            m['saif_started'] = True
        if stage == 'Power_running':
            m['power_started'] = True
        m['status'] = 'power_comparison_in_progress'
        save(RUN_MANIFEST, m)
    print(f'{now()} {mode}/{dataset} {stage} {message}', flush=True)


def execute(mode, dataset, stage, signature, skip_compile=False):
    out = Path(load_manifest()['systems'][mode]['build_directory']) / 'run_state' / dataset
    out.mkdir(parents=True, exist_ok=True)
    stamp = out / f'{stage.lower()}_completed.json'
    if stamp.exists():
        record = json.loads(stamp.read_text(encoding='utf-8'))
        if record.get('signature') == signature:
            print(f'REUSE {mode}/{dataset} {stage}', flush=True)
            return
    mark(mode, dataset, stage + '_running')
    args = [shutil.which('pwsh.exe') or 'powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
            str(ROOT / 'run_case.ps1'), '-Mode', mode, '-Dataset', dataset,
            '-Stage', stage, '-Start']
    if skip_compile:
        args.append('-SkipCompile')
    started = time.time()
    with (out / f'{stage.lower()}_console.log').open('w', encoding='utf-8') as f:
        process = subprocess.Popen(args, stdout=f, stderr=subprocess.STDOUT)
        save(out / 'running_process.json', dict(pid=process.pid, mode=mode,
             dataset=dataset, stage=stage, started_utc=now()))
        result = process.wait()
    if result:
        raise RuntimeError(f'{stage} exit={result}; see {out / (stage.lower()+"_console.log")}')
    save(stamp, dict(signature=signature, finished_utc=now(),
                     elapsed_seconds=round(time.time()-started, 2)))
    mark(mode, dataset, stage + '_complete')


def worker(mode, datasets):
    manifest = load_manifest()
    source = manifest['systems'][mode]
    assert sha(Path(source['dcp'])) == source['dcp_sha256'], 'DCP changed'
    script_names = ('run_case.ps1', 'export_netlist.tcl', 'tb_RoutedPower.sv',
                    'capture.tcl', 'apply_power.tcl', 'clock_activity.py', 'map_saif.py',
                    'audit_power.tcl', 'collect_results.py')
    scripts = {name: sha(ROOT / name) for name in script_names}
    compiled = False
    for dataset in datasets:
        signature = dict(dcp=source['dcp_sha256'],
                         workload=manifest['workloads'][dataset], scripts=scripts,
                         output_dir=os.environ['NEURAL_POWER_RESULTS'],
                         vivado_bin=os.environ['NEURAL_VIVADO_BIN'])
        try:
            if not compiled:
                execute(mode, dataset, 'Export', dict(dcp=signature['dcp'],
                        export_script=scripts['export_netlist.tcl'],
                        vivado_bin=signature['vivado_bin']))
            execute(mode, dataset, 'Activity', signature, skip_compile=compiled)
            compiled = True
            execute(mode, dataset, 'Power', signature)
            mark(mode, dataset, 'complete', 'Golden, Core coverage and clock-model audit passed')
            with LOCK:
                subprocess.run([sys.executable, str(ROOT/'collect_results.py')], check=True)
        except Exception as exc:
            mark(mode, dataset, 'failed', str(exc))
            return False
    return True


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--start', action='store_true')
    p.add_argument('--workers', type=int, choices=[1, 2, 3], default=3)
    p.add_argument('--modes', nargs='+', choices=MODES, default=MODES)
    p.add_argument('--datasets', nargs='+', choices=DATASETS, default=DATASETS)
    p.add_argument('--vivado-bin', help='Vivado installation bin directory; otherwise discover from environment/PATH')
    p.add_argument('--build-dir', help='Build root (default: project/build)')
    p.add_argument('--output-dir', help='New evidence directory (default: build/power/results)')
    p.add_argument('--dry-run', action='store_true', help='Check paths and show cases without running tools')
    args = p.parse_args()
    try:
        bin_dir = vivado_bin(args.vivado_bin)
    except ValueError as exc:
        p.error(str(exc))
    build = build_root(args.build_dir)
    output = Path(args.output_dir).resolve() if args.output_dir else build / 'power/results'
    os.environ.update(NEURAL_VIVADO_BIN=str(bin_dir), NEURAL_BUILD_DIR=str(build),
                      NEURAL_POWER_RESULTS=str(output), NEURAL_PYTHON=sys.executable)
    manifest = load_manifest()
    for mode in args.modes:
        if not Path(manifest['systems'][mode]['dcp']).is_file():
            p.error(f'Missing DCP: {manifest["systems"][mode]["dcp"]}')
    for name in args.datasets:
        for filename in manifest['workloads'][name]['file_sha256']:
            path = Path(manifest['workloads'][name]['data_dir']) / filename
            if not path.is_file():
                p.error(f'Missing input: {path}')
    if args.dry_run:
        print(json.dumps(dict(vivado_bin=str(bin_dir), build_dir=str(build),
            output_dir=str(output), modes=args.modes, datasets=args.datasets,
            dcp={mode: manifest['systems'][mode]['dcp'] for mode in args.modes}), indent=2))
        raise SystemExit(0)
    if not args.start:
        raise SystemExit('Use --dry-run to check paths or --start to begin.')
    RUN_MANIFEST = build / 'power/run_manifest.json'
    RUN_MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    if not RUN_MANIFEST.exists():
        for job in manifest['jobs']:
            job.update(status='pending', message='')
            job.pop('updated_utc', None)
        manifest.update(status='prepared', simulation_started=False,
                        saif_started=False, power_started=False)
        save(RUN_MANIFEST, manifest)
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        result = list(pool.map(lambda mode: worker(mode, args.datasets), args.modes))
    manifest = json.loads(RUN_MANIFEST.read_text(encoding='utf-8'))
    manifest['status'] = ('complete' if all(j['status'] == 'complete' for j in manifest['jobs'])
                          else 'selected_cases_complete' if all(result)
                          else 'incomplete_check_job_status')
    save(RUN_MANIFEST, manifest)
    print(f'COMPLETE success={all(result)}; results={output}', flush=True)
    raise SystemExit(0 if all(result) else 1)
