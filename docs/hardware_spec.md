# 하드웨어 사양

## 처리 경로

`DDR → RDMA → IBuffer → NeuralCore → OBuffer → WDMA → DDR`

NeuralCore: `IFIFO → SD / WindowBuffer → PendingEventQueue / WindowController → OFIFO / WindowFIFO → SFE`.

- 16채널, signed 16-bit sample. 채널별 25 ksample/s, 전체 400 ksample/s.
- AXI 100 MHz, SAMPLE 0.4 MHz, MAIN 13.333333 MHz, SFE 기본 8 MHz.
- IFIFO 4, PendingEventQueue 16, OFIFO 8, WindowFIFO 512.
- 64-sample window: 이전 32 + event 1 + 이후 31.
- refractory 63: 다음 63개 해당 채널 sample에서 재검출 억제.
- NEO `x[n]^2-x[n-1]*x[n+1] >= threshold`.
- 공통 unsigned 32-bit threshold를 실행 전에 설정.
- FIR `[8,-2,-6,-4]`, 내부 signed 21-bit, 출력 signed 36-bit.
- 최대 raw 양의 기울기 위치 + signed 7-bit offset으로 최대 7개 feature 선택.
- 범위 밖과 disable feature는 0. FIR history 초기값은 0.
- FIR 3단 pipeline, feature read 2+2+2+1, 정상 입력에서 71 SFE cycle/event.
- Pending sample 차이 계산은 8-bit modulo. event age <256 samples/channel의 운용 범위.

## AXI-Lite register

최종 `SW/board/main.c`와 `HW/rtl/interface/controller.v`를 기준으로 한다.

| Offset | 용도 |
|---|---|
| 0x00 | 제어와 시작 |
| 0x04 | 상태 / 완료 |
| 0x08 | 입력 DDR 주소 |
| 0x0C | 입력 word 개수 |
| 0x10 | 결과 DDR 주소 |
| 0x14 | 결과 event 수 |
| 0x18 | feature 설정 word |
| 0x1C | 공통 SD threshold |
| 0x20 | threshold 적용 상태 |

Feature word: `[3:0] channel`, `[6:4] feature slot`, `[13:7] signed offset`, `[14] enable`.

## 입력 및 결과 포장

한 입력은 64-bit: `[63:32] timestamp`, `[19:16] channel`, `[15:0] signed sample`.
나머지 bit는 0. DDR에서 little-endian 64-bit word 순서로 전송한다.

결과는 512-bit record로 저장한다.

| Bit | 필드 |
|---|---|
| 31:0 | event_id |
| 63:32 | timestamp |
| 67:64 | channel |
| 83:68 | signed event sample |
| 90:84 | feature enable flag |
| 96:91 | 최대 기울기 index |
| 132:97부터 36-bit씩 7개 | signed feature0~6 |
| 511:349 | 0 |

Golden HEX는 512-bit record 한 줄, C 배열은 record당 낮은 64-bit부터 8 word이다.

## Event-driven clock 제어

기본 SFE 클럭에서 동작하는 SFEClockControl이 work pending을 2단 동기화한다.
작업 또는 설정 요청으로 BUFGCE를 켜며, active 지연 확인 뒤 설정 handshake를 허용한다.
SFE busy와 result valid가 해제되고 4 idle cycle이 지나면 끈다.
SFE와 OFIFO/WindowFIFO 읽기 측이 gated clock을 사용한다.
reset 동안에는 enable을 유지한다.

## 비교군

- Always-on 8 MHz: 위 데이터 경로·클럭·FIFO를 유지하고 SFE 클럭을 계속 공급.
- Always-on 1 MHz: SFE 1 MHz, OFIFO 16, WindowFIFO 1024. 나머지 설정은 동일.

각 구현의 Timing은 `results/implementation`에서 확인한다. Core 자원은 `results/power/comparison.txt`, 원본은 각 `results/power/evidence/<데이터>/<구조>.zip` 안의 `core_utilization.rpt`에 있다.
