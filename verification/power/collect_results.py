"""Validate SAIF, Golden and Vivado reports, then summarize Core/SFE power."""
import argparse
from collections import Counter
from contextlib import contextmanager
import hashlib
import json
import math
from pathlib import Path
import re
from tempfile import TemporaryDirectory
from zipfile import ZipFile
from clock_activity import clock_statistics
from portable_manifest import PROJECT, RESULTS, EVIDENCE, load_manifest

ROOT = RESULTS
MODES = ['always_on_8mhz', 'event_driven_8mhz', 'always_on_1mhz']
DATASETS = ['burst', 'real1', 'real2', 'real3']


def load(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


@contextmanager
def case_files(mode, dataset):
    """Read a working directory or unpack one completed experiment temporarily."""
    folder = EVIDENCE/dataset/mode
    if folder.is_dir():
        yield folder, False
        return
    archive = folder.with_suffix('.zip')
    with TemporaryDirectory(prefix='neural_power_') as temp, ZipFile(archive) as z:
        root = Path(temp).resolve()
        for entry in z.infolist():
            target = (root/entry.filename).resolve()
            require(target.is_relative_to(root), f'Invalid archive path: {entry.filename}')
            require((entry.external_attr >> 16) & 0o170000 != 0o120000,
                    f'Symbolic link in archive: {entry.filename}')
        z.extractall(root)
        yield root, True


def display_path(path):
    try:
        return path.relative_to(PROJECT).as_posix()
    except ValueError:
        return path.as_posix()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(ok, message):
    if not ok:
        raise ValueError(message)


def near(a, b, label):
    require(a is not None and b is not None and abs(a-b) <= 0.000003,
            f'{label}: {a} vs {b} mW')


def power_row(text, name):
    rows = [[x.strip() for x in line.split('|')[1:-1]] for line in text.splitlines()]
    rows = [r for r in rows if len(r) == 14 and r[0] == name]
    require(len(rows) == 1, f'Expected one detailed power row: {name}, got {len(rows)}')
    unit = re.search(r'\|\s*Power \((W|mW|uW|µW)\)\s*\|', text)
    require(unit, 'Power unit missing')
    scale = {'W': 1000, 'mW': 1, 'uW': .001, 'µW': .001}[unit[1]]
    result, bounds = {}, {}
    for key, i in [('dynamic_mw', 1), ('clock_mw', 3), ('signal_mw', 5),
                   ('logic_mw', 7), ('bram_mw', 9), ('dsp_mw', 11)]:
        s = rows[0][i]
        if s.startswith('<'):
            result[key] = None
            bounds[key] = float(s[1:])*scale
        else:
            result[key] = float(s)*scale
    if bounds:
        result['strict_upper_bounds_mw'] = bounds
    return result


def activities(path):
    pattern = r'^(.*):\s+static probability = (\S+) \((\w)\)\s+signal rate = (\S+) \((\w)\)'
    found = {m[1]: (float(m[2]), m[3], float(m[4]), m[5])
             for m in re.finditer(pattern, path.read_text(), re.M)}
    require(found, f'No switching activity in {path}')
    return found


def coverage(path):
    values = activities(path)
    c = Counter()
    for sp, sp_source, rate, rate_source in values.values():
        c['entries'] += 1
        if sp_source == rate_source == 'S':
            c['both_direct_saif'] += 1
        elif 'D' in (sp_source, rate_source):
            c['default_constant' if rate == 0 and sp in (0, 1) else 'default_nonconstant'] += 1
        else:
            c['propagated_or_constrained'] += 1
    return dict(c, direct_saif_percent=100*c['both_direct_saif']/c['entries'])


def clocks(path):
    return {m[1]: float(m[2]) for m in re.finditer(
        r'^(clk_fpga_[0-3]|observed_gated_clock)\s+(\d+\.\d+)\s+\{', path.read_text(), re.M)}


def validate(mode, dataset, persist=True):
    with case_files(mode, dataset) as (out, archived):
        return validate_files(mode, dataset, out, persist and not archived)


def validate_files(mode, dataset, out, persist):
    manifest = load_manifest()
    system, workload = manifest['systems'][mode], manifest['workloads'][dataset]
    audit = out/'audit'
    require(sha(Path(system['dcp'])) == system['dcp_sha256'], 'DCP changed')
    data = Path(workload['data_dir'])
    for name, expected in workload['file_sha256'].items():
        require(sha(data/name) == expected, f'Input/config changed: {name}')
    captured = load(out/'activity_inputs.json')
    require(captured['dcp_sha256'] == system['dcp_sha256'], 'Activity checkpoint mismatch')
    require(captured['threshold'] == workload['threshold'] and
            captured['observation_ns'] == workload['observation_ns'], 'Activity settings mismatch')
    for name in ('input.hex', 'feature.hex', 'golden.hex', 'sd_threshold.csv', 'sfe_feature.csv'):
        require(captured['file_sha256'][name] == sha(data/name), f'Activity input mismatch: {name}')
    require(captured['file_sha256']['metadata.json'] in
            {workload['file_sha256']['metadata.json'], workload['original_metadata_sha256']},
            'Activity metadata version mismatch')
    sim = (out/'simulation.log').read_text(errors='replace')
    m = re.search(r'^PASS routed IP: input=(\d+) result=(\d+) Golden=(\d+) status=(\w+) threshold=(\d+)', sim, re.M)
    require(m and not re.search(r'^(Fatal:|ERROR:|ERROR record)', sim, re.M), 'Routed simulation failed')
    require([int(m[i]) for i in (1, 2, 3, 5)] == [workload['input_rows'],
            workload['expected_events'], workload['expected_events'], workload['threshold']], 'Wrong simulation settings/counts')
    actual = [int(x, 16) for x in (out/'result_records.hex').read_text().split()]
    expected = [int(x, 16) for x in (data/'golden.hex').read_text().split()]
    require(actual == expected, 'Saved result records do not match Golden')
    measured = clock_statistics(out/'activity.saif', 1 if mode == 'always_on_1mhz' else 8)
    require(measured == load(out/'clock_activity.json'), 'Clock activity record changed')
    require(abs(measured['observation_s']*1e9-workload['observation_ns']) < .1, 'SAIF observation duration mismatch')
    raw = (out/'activity.saif').read_text(encoding='ascii')
    ip = system['ip_scope'].split('/')
    mapped, a = re.subn(r'(\(INSTANCE\s+)tb_RoutedPower(?=\s)', lambda m: m[1]+ip[0], raw, count=1)
    mapped, b = re.subn(r'(\(INSTANCE\s+)DUT(?=\s)', lambda m: m[1]+ip[1], mapped, count=1)
    require(a == b == 1 and mapped == (out/'mapped.saif').read_text(encoding='ascii'), 'SAIF changed beyond root mapping')
    text = (audit/'modeled_uW.rpt').read_text()
    native = (audit/'native_uW.rpt').read_text()
    require('POWER_ANALYSIS_COMPLETE' in (out/'power.log').read_text(errors='replace'), 'Power job incomplete')
    require('AUDIT_POWER_COMPLETE' in (out/'audit.log').read_text(errors='replace'), 'Audit job incomplete')
    core, sfe = power_row(text, 'u_NeuralCore'), power_row(text, 'u_SFE')
    near(core['dynamic_mw'], power_row((out/'power_modeled_uW.rpt').read_text(), 'u_NeuralCore')['dynamic_mw'], 'Repeated Core report')
    physical = clocks(audit/'implemented_clocks.rpt')
    modeled = clocks(audit/'analysis_clocks.rpt')
    periods = {'clk_fpga_0': 10., 'clk_fpga_1': 2500., 'clk_fpga_2': 75.,
               'clk_fpga_3': 1000. if mode == 'always_on_1mhz' else 125.}
    require(physical == periods and {k: modeled.get(k) for k in periods} == periods, 'Physical source clocks changed')
    activity = {'core_net_segments': coverage(out/'core_switching_before_power.txt'),
                'register_outputs': coverage(out/'activity_register.txt'),
                'lut_outputs': coverage(out/'activity_lut.txt')}
    for name in ('register_outputs', 'lut_outputs'):
        require(activity[name]['direct_saif_percent'] == 100, f'Incomplete direct SAIF: {name}')
    before, after = activities(audit/'native_activity.txt'), activities(audit/'modeled_activity.txt')
    require(before.keys() == after.keys(), 'Activity node set changed')
    def same(a, b):
        return a[1] == b[1] and a[3] == b[3] and math.isclose(a[0], b[0], rel_tol=1e-5, abs_tol=1e-14) and math.isclose(a[2], b[2], rel_tol=1e-5, abs_tol=1e-14)
    changed = [n for n in before if not same(before[n], after[n])]
    if mode == 'event_driven_8mhz':
        require(not [n for n in changed if n.rsplit('/', 1)[-1] not in {'sfe_run_clk', 'rclk', 'sfe_clk', 'clk'}], 'Unexpected nonclock activity changed')
        on_text = (audit/'forced_on_uW.rpt').read_text()
        on, off = power_row(on_text, 'u_NeuralCore'), power_row((audit/'forced_off_uW.rpt').read_text(), 'u_NeuralCore')
        near(power_row(native, 'u_NeuralCore')['dynamic_mw'], on['dynamic_mw'], 'Native vs forced-on')
        predicted = off['clock_mw'] + measured['clock_delivery_fraction']*(on['clock_mw']-off['clock_mw'])
        near(core['clock_mw'], predicted, 'Clock interpolation check')
        for component in ('signal_mw', 'logic_mw', 'bram_mw', 'dsp_mw'):
            near(core[component], on[component], 'Nonclock power unchanged: '+component)
            near(off[component], on[component], 'Off test changes clocks only: '+component)
        for module in ('u_SD', 'u_IFIFO', 'u_PendingEventQueue', 'u_WindowBuffer', 'u_WindowController'):
            near(power_row(text, module)['dynamic_mw'], power_row(on_text, module)['dynamic_mw'], module)
        require(abs(modeled['observed_gated_clock']/measured['average_period_ns_for_power_only']-1) < 1e-6, 'Mean clock rate mismatch')
        pins = (audit/'affected_clock_pins.txt').read_text().splitlines()
        allowed = ('/u_MainPath/u_SFE/', '/u_MainPath/u_OFIFO/', '/u_MainPath/u_WindowFIFO/', '/u_MainPath/g_event_driven.u_SFEClockControl/')
        require(pins and all(any(s in line for s in allowed) and line.endswith(' | observed_gated_clock') for line in pins), 'Mean clock reached wrong cells')
        require(abs(measured['enable_fraction']-measured['clock_delivery_fraction']) < 1e-8, 'CE/clock delivery mismatch')
    else:
        require(not changed and modeled == physical, 'Always-on clock/activity changed')
        near(core['dynamic_mw'], power_row(native, 'u_NeuralCore')['dynamic_mw'], 'Always-on repeatability')
    util = (out/'core_utilization.rpt').read_text()
    resources = {}
    for key, label in [('lut', 'Slice LUTs'), ('ff', 'Slice Registers'), ('bram_tiles', 'Block RAM Tile'), ('dsp', 'DSPs')]:
        match = re.search(r'\|\s*'+label+r'\s*\|\s*([\d.]+)', util)
        require(match, 'Missing utilization '+label)
        resources[key] = float(match[1])
    confidence = re.search(r'\|\s*Overall confidence level\s*\|\s*(\w+)', text)
    result = dict(mode=mode, dataset=dataset, status='validated', core=core, sfe=sfe,
        native_clock_core=power_row(native, 'u_NeuralCore'), resources=resources,
        clock_activity=measured, activity=activity, confidence=confidence[1] if confidence else 'not reported',
        input_rows=workload['input_rows'], output_events=workload['expected_events'], threshold=workload['threshold'],
        dcp_sha256=system['dcp_sha256'], result_records_sha256=sha(out/'result_records.hex'),
        changed_activity_nodes=changed, power_report=display_path(audit/'modeled_uW.rpt'),
        power_report_sha256=sha(audit/'modeled_uW.rpt'),
        label='Board post-route SAIF-based dynamic power estimate; ED clock model uses observed mean pulse rate')
    if persist:
        (out/'result.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'VALIDATED {mode}/{dataset}: Core={core["dynamic_mw"]} mW SFE={sfe["dynamic_mw"]} mW', flush=True)
    return result


def publish():
    results = []
    for dataset in DATASETS:
        for mode in MODES:
            folder = EVIDENCE/dataset/mode
            archive = folder.with_suffix('.zip')
            if (folder/'result.json').is_file():
                result = load(folder/'result.json')
            elif archive.is_file():
                with ZipFile(archive) as z:
                    result = json.loads(z.read('result.json').decode('utf-8-sig'))
                result['power_report'] = display_path(archive)+'!audit/modeled_uW.rpt'
            else:
                continue
            result['label'] = 'Board post-route SAIF-based dynamic power estimate; ED clock model uses observed mean pulse rate'
            results.append(result)
    comparisons = []
    for ds in DATASETS:
        cases = {r['mode']: r for r in results if r['dataset'] == ds}
        if len(cases) != 3:
            continue
        require(len({r['result_records_sha256'] for r in cases.values()}) == 1, 'Different output records across systems')
        comparison = {'dataset': ds}
        for unit in ('core', 'sfe'):
            ao8, ed8, ao1 = [cases[m][unit]['dynamic_mw'] for m in MODES]
            if all(v is not None and v > 0 for v in (ao8, ed8, ao1)):
                comparison[unit] = {'ed8_vs_ao8_reduction_percent': 100*(1-ed8/ao8),
                                    'ed8_vs_ao1_reduction_percent': 100*(1-ed8/ao1)}
        comparisons.append(comparison)
    (ROOT/'comparison.json').write_text(json.dumps(dict(completed=len(results), expected=12,
        results=results, comparisons=comparisons), ensure_ascii=False, indent=2), encoding='utf-8')
    lines = ['NeuralCore / SFE 전력 비교', '', f'검사 완료: {len(results)}/12', '',
        '단위 mW. 실제 보드 구현 DCP와 SAIF 기반 동적 전력 추정.',
        'Event-driven은 SAIF의 실제 클럭 전달 횟수를 반영한 평균 클럭 모델.',
        '전력 분석 방법: docs/Neural_Event_Processor_Report.pdf', '',
        '데이터  시스템                Core(mW)     SFE(mW)    클럭전달(%)  Golden']
    for r in results:
        sfe = r['sfe']['dynamic_mw']
        lines.append(f'{r["dataset"]:6} {r["mode"]:22} {r["core"]["dynamic_mw"]:.6f}  '
                     f'{str(round(sfe,6)) if sfe is not None else "미표시":>10}  '
                     f'{100*r["clock_activity"]["clock_delivery_fraction"]:10.5f}  {r["output_events"]} PASS')
    lines += ['', '감소율: 양수는 Event-driven 전력이 더 낮음을 뜻함.']
    for c in comparisons:
        for unit in ('core', 'sfe'):
            if unit in c:
                v = c[unit]
                lines.append(f'{c["dataset"]} {unit}: vs AO8 {v["ed8_vs_ao8_reduction_percent"]:+.2f}% / vs AO1 {v["ed8_vs_ao1_reduction_percent"]:+.2f}%')
    lines += ['', 'Core 자원: LUT / FF / BRAM / DSP (실제 보드 배치 결과의 해당 hierarchy)']
    for mode in MODES:
        r = next((r for r in results if r['mode'] == mode), None)
        if r:
            lines.append(mode+': '+' / '.join(str(r['resources'][k]) for k in ('lut','ff','bram_tiles','dsp')))
    lines += ['', f'원본 자료: {display_path(EVIDENCE)}/<데이터>/<구조>.zip (새 실행은 같은 이름의 폴더)',
              '재현 코드: verification/power']
    (ROOT/'comparison.txt').write_text('\n'.join(lines)+'\n', encoding='utf-8')
    print(f'Saved comparison: {len(results)}/12 validated', flush=True)


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--case', nargs=2, metavar=('MODE', 'DATASET'))
    args = p.parse_args()
    if args.case:
        validate(*args.case)
    else:
        publish()
