from portable_manifest import load_manifest
"""Map only the simulation roots, using the new archived DCP scope."""
import argparse
from portable_manifest import EVIDENCE
import hashlib
import json
import re
from pathlib import Path

p=argparse.ArgumentParser()
p.add_argument('mode',choices=['always_on_8mhz','event_driven_8mhz','always_on_1mhz'])
p.add_argument('dataset',choices=['burst','real1','real2','real3'])
a=p.parse_args()
manifest=load_manifest()
ip=manifest['systems'][a.mode]['ip_scope'].split('/')
assert len(ip)==2
out=EVIDENCE/a.dataset/a.mode
source=out/'activity.saif'
text=source.read_text(encoding='ascii')
mapped,n=re.subn(r'(\(INSTANCE\s+)tb_RoutedPower(?=\s)',lambda m:m[1]+ip[0],text,count=1)
assert n==1, 'Missing simulation root'
mapped,n=re.subn(r'(\(INSTANCE\s+)DUT(?=\s)',lambda m:m[1]+ip[1],mapped,count=1)
assert n==1, 'Missing DUT root'
(out/'mapped.saif').write_text(mapped,encoding='ascii')
(out/'saif_mapping.json').write_text(json.dumps(dict(
    source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
    mapping='tb_RoutedPower/DUT -> '+'/'.join(ip),scope_body_unchanged=True),indent=2)+'\n',encoding='utf-8')
