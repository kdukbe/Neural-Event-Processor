"""Resolve project-relative checkpoint, dataset and build paths."""
from pathlib import Path
import json
import os

PROJECT = Path(__file__).resolve().parents[2]
RESULTS = Path(os.environ.get('NEURAL_POWER_RESULTS', PROJECT / 'results/power')).resolve()
EVIDENCE = RESULTS / 'evidence'
def load_manifest():
    here=Path(__file__).resolve().parent
    root=PROJECT
    m=json.loads((here/'manifest_portable.json').read_text(encoding='utf-8'))
    build = Path(os.environ.get('NEURAL_BUILD_DIR', PROJECT / 'build')).resolve()
    for mode, s in m['systems'].items():
        s['build_directory'] = str(build / 'power' / mode)
        for key in ('dcp','capture_manifest'):
            if not Path(s[key]).is_absolute():s[key]=str(root/s[key])
    for w in m['workloads'].values():
        if not Path(w['data_dir']).is_absolute():w['data_dir']=str(root/w['data_dir'])
    return m
