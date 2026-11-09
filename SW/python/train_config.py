"""16채널 Sample CSV에서 Threshold, Feature 설정, Golden과 보드용 C 파일 생성.

입력: --input으로 지정한 CSV 한 개 (timestamp,channel_id,valid,sample).
출력: --output으로 지정한 새 폴더에 아래 파일을 생성한다.
  sd_threshold.csv, sfe_feature.csv       : Threshold / Feature 설정
  input.hex, feature.hex, golden.hex     : TB 입력 / 설정 / 예상 출력
  mainpath_golden.csv                    : Event별 예상 결과
  metadata.json, training.json           : 실행 정보 / 학습 기록
  board/neural_data.c, board/neural_data.h: Vitis용 데이터와 설정

프로젝트 최상위 폴더에서 실행:
python SW/python/train_config.py --input data/recordings/real1/input.csv --output data/generated/real1
앞 20,000 Sample/Channel로 학습하며, 짧으면 전체를 사용한다.
"""
from pathlib import Path
import argparse, csv, hashlib, json
import numpy as np
from processing import signal_model as model
from processing.threshold import calculate
from processing.features import select_offsets
from export_c import export_dataset, read_golden

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def train(source,out,prefix):
    source=Path(source).resolve();out=Path(out).resolve()
    if out.exists():raise ValueError('Choose a new output directory to preserve existing results')
    if prefix<=0:raise ValueError('prefix must be positive')
    model.set_channel_count(16)
    channels=model.read_input(source)
    lengths=[len(d.values) for d in channels.values()]
    if len(channels)!=16 or len(set(lengths))!=1:raise ValueError('Input needs equally long channels 0..15')
    used=min(prefix,min(lengths))
    threshold=calculate(source,samples_per_channel=used)
    initial={c:model.ChannelSamples(d.timestamps[:used],d.values[:used]) for c,d in channels.items()}
    events,_=model.detect_events(source.stem,initial,threshold['threshold'],63,model.DEFAULT_COEFFICIENTS)
    settings=[];detail=[];cfg={}
    for c in range(16):
        selected,meta=select_offsets([e for e in events if e.channel_id==c])
        offsets=meta['offsets']+[0]*(7-len(selected));flag=(1<<len(selected))-1
        cfg[c]=(flag,offsets)
        settings.append(dict(channel_id=c,feature_count=len(selected),feature_flag=format(flag,'07b'),**{f'offset{i}':v for i,v in enumerate(offsets)}))
        detail.append(dict(channel=c,method='laplacian',**meta))
    # Evaluate the full recording with the prefix-derived settings and a fixed flush.
    extended={c:model.ChannelSamples(np.r_[d.timestamps,d.timestamps[-1]+np.arange(1,33)],np.r_[d.values,np.repeat(d.values[-1],32)]) for c,d in channels.items()}
    results,incomplete=model.detect_events(source.stem,extended,threshold['threshold'],63,model.DEFAULT_COEFFICIENTS)
    if incomplete:raise ValueError('Incomplete windows after flush')
    out.mkdir(parents=True)
    with (out/'sfe_feature.csv').open('w',encoding='utf-8',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(settings[0]));w.writeheader();w.writerows(settings)
    (out/'sd_threshold.csv').write_text(f'threshold\n{threshold["threshold"]}\n',encoding='ascii')
    with (out/'mainpath_golden.csv').open('w',encoding='utf-8',newline='') as f:
        w=csv.writer(f);w.writerow(['event_id','timestamp','channel_id','event_sample','feature_flag']+[f'feature{i}' for i in range(7)]+['max_slope_index'])
        for e in results:
            flag,off=cfg[e.channel_id]
            values=[int(e.fir[e.max_slope_index+r]) if flag&(1<<j) and 0<=e.max_slope_index+r<64 else 0 for j,r in enumerate(off)]
            w.writerow([e.event_id,e.timestamp,e.channel_id,e.event_sample,flag,*values,e.max_slope_index])
    with (out/'input.hex').open('w',encoding='ascii') as f:
        for n in range(len(extended[0].values)):
            for c in range(16):
                d=extended[c];f.write(f'{(int(d.timestamps[n])<<32)|(c<<16)|(int(d.values[n])&65535):016x}\n')
    with (out/'feature.hex').open('w',encoding='ascii') as f:
        for c,(flag,off) in cfg.items():
            for j,r in enumerate(off):f.write(f'{c|(j<<4)|((r&127)<<7)|(((flag>>j)&1)<<14):08x}\n')
    words=read_golden(out/'mainpath_golden.csv')
    with (out/'golden.hex').open('w',encoding='ascii') as f:
        for n in range(0,len(words),8):f.write(f'{sum(words[n+j]<<(64*j) for j in range(8)):0128x}\n')
    meta=dict(dataset=source.parent.name,threshold=threshold['threshold'],method='ceil(14*pooled_MAD_sigma^2)',feature_method='laplacian_no_reference',reference_used=False,source=str(source),source_sha256=sha(source),requested_samples_per_channel=prefix,used_samples_per_channel=used,source_rows=sum(lengths),replay_input_rows=sum(lengths)+512,flush_samples_per_channel=32,events=len(results),refractory=63,input_half_period_ns=1250.0)
    (out/'metadata.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf-8')
    (out/'training.json').write_text(json.dumps(dict(**meta,threshold_details=threshold,channels=detail,code_sha256={p.relative_to(Path(__file__).parent).as_posix():sha(p) for p in [Path(__file__),Path(__file__).parent/'export_c.py',*(Path(__file__).parent/'processing').glob('*.py')]}),ensure_ascii=False,indent=2),encoding='utf-8')
    export_dataset(meta['dataset'],out,out/'board')
    print(f'PASS prepared {len(results)} events; threshold={threshold["threshold"]}; prefix={used}/channel')

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__,formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--input',type=Path,required=True,help='16채널 Sample CSV 경로')
    p.add_argument('--output',type=Path,required=True,help='결과를 저장할 새 폴더 경로')
    p.add_argument('--samples-per-channel',type=int,default=20000,help='학습에 사용할 채널별 앞부분 Sample 수 (기본: 20000)')
    a=p.parse_args();train(a.input,a.output,a.samples_per_channel)
