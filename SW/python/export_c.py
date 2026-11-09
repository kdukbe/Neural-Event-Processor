"""이미 생성된 입력·설정·Golden을 보드용 C 배열로 변환.

입력: --config-dir 폴더의 input.hex, feature.hex, golden.hex, metadata.json.
출력: --output-dir 폴더의 neural_data.c, neural_data.h.
Threshold와 데이터 크기는 metadata.json과 HEX에서 읽는다.

프로젝트 최상위 폴더에서 실행:
python SW/python/export_c.py real1 --config-dir data/prepared/real1 --output-dir data/generated/real1_c
"""
import argparse
import csv
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]

def read_golden(path: Path) -> list[int]:
    words: list[int] = []
    with path.open(newline="", encoding="utf-8-sig") as file:
        for row in csv.DictReader(file):
            record = int(row["event_id"]) & 0xFFFFFFFF
            record |= (int(row["timestamp"]) & 0xFFFFFFFF) << 32
            record |= (int(row["channel_id"]) & 0xF) << 64
            record |= (int(row["event_sample"]) & 0xFFFF) << 68
            record |= (int(row["feature_flag"]) & 0x7F) << 84
            record |= (int(row["max_slope_index"]) & 0x3F) << 91

            for feature in range(7):
                value = int(row[f"feature{feature}"]) & ((1 << 36) - 1)
                record |= value << (97 + feature * 36)

            for word in range(8):
                words.append((record >> (word * 64)) & 0xFFFFFFFFFFFFFFFF)
    return words


def array(f,name,words):
    f.write(f'const uint64_t {name}[{len(words)}] __attribute__((aligned(64))) = {{\n')
    for i in range(0,len(words),4):
        f.write('    '+', '.join(f'UINT64_C(0x{v:016x})' for v in words[i:i+4])+',\n')
    f.write('};\n')

def export_dataset(dataset, src, out):
    """Serialize prepared settings and Golden into board arrays."""
    src, out = Path(src), Path(out)
    out.mkdir(parents=True,exist_ok=True)
    m=json.loads((src/'metadata.json').read_text(encoding='utf-8'))
    inputs=[int(x,16) for x in (src/'input.hex').read_text().splitlines()]
    records=[int(x,16) for x in (src/'golden.hex').read_text().splitlines()]
    words=[(r>>(64*j))&((1<<64)-1) for r in records for j in range(8)]
    cfg=[int(x,16) for x in (src/'feature.hex').read_text().splitlines()]
    capacity=16*((len(inputs)//16+63)//64+1)
    (out/'neural_data.h').write_text(
        '#ifndef NEURAL_DATA_H\n#define NEURAL_DATA_H\n#include <stdint.h>\n'
        f'#define NEURAL_DATASET "{dataset}"\n'
        f'#define NEURAL_THRESHOLD {m["threshold"]}U\n'
        f'#define NEURAL_INPUT_ROWS {len(inputs)}U\n'
        f'#define NEURAL_EXPECTED_EVENTS {len(records)}U\n'
        f'#define NEURAL_OUTPUT_CAPACITY {capacity}U\n'
        'extern const uint64_t neural_input[NEURAL_INPUT_ROWS];\n'
        'extern const uint64_t neural_golden[NEURAL_EXPECTED_EVENTS*8];\n'
        'extern const uint32_t neural_feature[112];\n#endif\n',encoding='ascii')
    with (out/'neural_data.c').open('w',encoding='ascii') as f:
        f.write('#include "neural_data.h"\n')
        array(f,'neural_input',inputs)
        array(f,'neural_golden',words)
        f.write('const uint32_t neural_feature[112] = {\n')
        for i in range(0,112,7):
            f.write('    '+', '.join(f'0x{v:08x}U' for v in cfg[i:i+7])+',\n')
        f.write('};\n')
    assert len(cfg) == 112 and len(records) <= capacity
    print(f'{dataset}: threshold={m["threshold"]}, input={len(inputs)}, Golden={len(records)}, output capacity={capacity}')
    print(out)
    return dict(threshold=m['threshold'], input_rows=len(inputs), expected_events=len(records),
                output_capacity=capacity)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__,formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('dataset',choices=['burst','real1','real2','real3'],help='C 프로그램에 표시할 데이터 이름')
    p.add_argument('--config-dir',type=Path,help='입력 HEX와 metadata.json 폴더 (기본: data/prepared/<데이터>)')
    p.add_argument('--output-dir',type=Path,help='C 파일을 저장할 폴더 (기본: data/generated/<데이터>_c)')
    a=p.parse_args()
    export_dataset(a.dataset, a.config_dir or ROOT/'data/prepared'/a.dataset,
                   a.output_dir or ROOT/'data/generated'/(a.dataset+'_c'))
