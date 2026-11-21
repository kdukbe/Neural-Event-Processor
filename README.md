# Event-driven Neural Event Processor

16-channel 신경 신호에서 Spike Detection과 Feature Extraction을 수행하는 FPGA 프로세서이다. 주파수·FIFO 용량·RTL 구조를 최적화하고, Event가 있을 때 SFE Clock을 켜는 Event-driven 구조를 구현하였다. 8 MHz·1 MHz Always-on 구조와 비교하여 자원과 Dynamic Power의 Trade-off를 분석하였다.

## Architecture

```text
Zynq PS / DDR → RDMA → IBuffer → NeuralCore → OBuffer → WDMA → DDR
```

NeuralCore는 Spike Detection, 64-sample Window 구성, Shared SFE를 담당한다. Python에서 계산한 Threshold와 Feature Offset은 PS가 AXI4-Lite로 전달한다.

- **Platform:** Arty Z7-20 / Zynq-7020, Vivado·Vitis 2022.2
- **Input:** 16 channels × 25 ksample/s
- **Clock:** AXI 100 MHz / Sample 0.4 MHz / Main 13.333 MHz
- **OFIFO·WindowFIFO:** 8 MHz 구조는 8 events·512 samples, 1 MHz 구조는 16 events·1,024 samples

## Results

아래는 Burst 입력의 결과이다. 전력은 Routed DCP와 Simulation Activity(SAIF)를 반영한 Vivado 추정값이다.

| Architecture | Core Dynamic Power (mW) | SFE Dynamic Power (mW) | Core LUT | Core FF |
|---|---:|---:|---:|---:|
| Always-on 8 MHz | 1.5484 | 0.6103 | 2,568 | 4,470 |
| Always-on 1 MHz | 1.0971 | 0.1207 | 2,818 | 4,504 |
| Event-driven 8 MHz | 0.9825 | 0.0774 | 2,572 | 4,477 |

- **Core Dynamic Power 감소:** Event-driven이 Always-on 8 MHz 대비 36.55%, Always-on 1 MHz 대비 10.45% 감소.
- **Simulation:** 세 구조 × 네 데이터(Burst 1종·실제 Recording 3종)에서 Python Golden 일치, Event Drop 0.
- **FPGA:** 세 구조 모두 Burst 504개 결과가 Golden과 일치. Post-route Timing 충족.

[프로젝트 보고서](docs/Neural_Event_Processor_Report.pdf)에는 회로 설계와 전력 분석 과정을, [전력 비교 결과](results/power/comparison.txt)에는 입력별 Core·SFE 추정값을 담았다.

블록별 분석에서 Always-on 8 MHz의 SFE는 Core 전력의 38.35–39.41%를 차지했다. Event-driven 적용 후에는 0.63–7.88%로 줄었다. [블록별 전력](results/power/module_breakdown.txt)에 입력별 값을 담았다.

후속 Python 품질 실험에서는 IBL 8개체로 전처리·Threshold·Feature 위치를 비교했다. SD 평균 F1은 53.48%이다. Reference 파형의 SFE 종류 구분 정답률은 같은 평가 파형에서 기존 설정 74.98% → 선정 방식 82.47%(Balanced accuracy 81.30% → 86.17%)였다. 다만 Balanced accuracy로는 균등 간격 7개 86.12%, 조건을 조정한 Laplacian 86.24%도 선정 방식과 비슷하므로, 이 결과는 기존 설정 대비 개선을 보여주며 위치 선정 방식 사이의 우열을 가리는 근거는 아니다([방법별 비교](results/training/sfe_evaluation/method_comparison.csv)). 보드 비교에 사용한 설정은 유지하고, 추가 평가의 방법과 결과는 [보고서 5.5–5.6절](docs/Neural_Event_Processor_Report.pdf)과 [평가 요약](results/training/quality_evaluation.txt)에 담았다.

## Folders

| Folder | 내용 |
|---|---|
| [HW](HW) | Event-driven RTL, FPGA 설계 파일, XSA |
| [comparisons](comparisons) | Always-on 8 MHz·1 MHz 비교군의 변경 RTL과 FPGA 설계 파일, XSA |
| [SW](SW) | 보드 비교에 사용한 Python 설정값 계산·데이터 변환, C 코드 |
| [data](data) | 입력 데이터, Threshold·Feature 설정값, Golden |
| [verification](verification) | Testbench와 Simulation·전력 분석 코드 |
| [results](results) | PPA·보드·Simulation 결과, RTL 탐색, 후속 SD·SFE 품질 평가 |
| [docs](docs) | 프로젝트 보고서와 [하드웨어 사양](docs/hardware_spec.md) |

## 입력 데이터

- **실제 기록(real1–3):** International Brain Laboratory의 [Neuropixels Brainwide Map](https://registry.opendata.aws/ibl-brain-wide-map/)에서 각 기록의 16채널·1초 구간을 추출해 전처리했다. 원자료의 이용 조건은 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)이며, 세션·채널·시간 정보는 [각 기록 폴더](data/recordings)에 담았다.
- **Burst:** Quian Quiroga 등의 [Wave_clus 모의 신호](https://pmc.ncbi.nlm.nih.gov/articles/PMC6230803/)에서 64-sample 파형을 잘라 채널마다 32개씩 이어 붙였다. [입력 구성과 검출 결과](results/training/selection.txt)에 원본 파형과의 대응 방법을 설명했다.

## FPGA 실행

1. Vitis 2022.2에서 `HW/xsa/event_driven_8mhz.xsa`로 Platform과 Standalone Application을 만든다.
2. `SW/board/main.c`와 `SW/board/<데이터>/`의 `neural_data.c`, `neural_data.h`를 추가한다. 데이터는 `burst`, `real1`, `real2`, `real3` 중 하나를 선택한다.
3. XSA의 Bitstream을 보드에 올리고 Application을 실행한다.

Burst 실행 시 `PASS all 504 event records match Golden`을 확인한다. Always-on 비교군은 `comparisons/<구조>/xsa/<구조>.xsa`와 같은 C 코드를 사용한다.

## License

- **코드:** 본 프로젝트에서 작성한 RTL·Testbench·Python·C·스크립트에는 [MIT License](LICENSE)를 적용한다.
- **실제 기록(real1–3) 유래 데이터:** IBL 원자료의 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 조건을 따른다.
- **Burst 유래 데이터:** Quian Quiroga 등의 모의 신호에서 만든 자료로, 원자료의 이용 조건을 따른다.
- **Vivado 산출물:** Block Design·XSA·DCP에 포함된 AMD(Xilinx) IP는 해당 도구의 라이선스 조건을 따른다.
