/* Use this package's threshold-configurable bitstream.
 * Add main.c and ONE dataset's neural_data.c/h from this directory.
 * The same program supports Always-on and Event-driven hardware.
 */
#include "xparameters.h"
#include "xil_io.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "sleep.h"
#include "neural_data.h"
#include <string.h>

#ifndef BASE
#if defined(XPAR_TOP_1_S_AXI_BASEADDR)
#define BASE XPAR_TOP_1_S_AXI_BASEADDR
#elif defined(XPAR_TOP_1_S00_AXI_BASEADDR)
#define BASE XPAR_TOP_1_S00_AXI_BASEADDR
#elif defined(XPAR_TOP_1_BASEADDR)
#define BASE XPAR_TOP_1_BASEADDR
#elif defined(XPAR_TOP_0_S_AXI_BASEADDR)
#define BASE XPAR_TOP_0_S_AXI_BASEADDR
#elif defined(XPAR_TOP_0_S00_AXI_BASEADDR)
#define BASE XPAR_TOP_0_S00_AXI_BASEADDR
#elif defined(XPAR_TOP_0_BASEADDR)
#define BASE XPAR_TOP_0_BASEADDR
#elif defined(XPAR_TOP_1MHZ_0_S_AXI_BASEADDR)
#define BASE XPAR_TOP_1MHZ_0_S_AXI_BASEADDR
#elif defined(XPAR_TOP_1MHZ_0_BASEADDR)
#define BASE XPAR_TOP_1MHZ_0_BASEADDR
#else
#error "Set BASE using the custom IP address in xparameters.h"
#endif
#endif

#define CONTROL 0x00U
#define STATUS 0x04U
#define INPUT_ADDR 0x08U
#define INPUT_ROWS 0x0cU
#define OUTPUT_ADDR 0x10U
#define RESULT_COUNT 0x14U
#define FEATURE 0x18U
#define THRESHOLD 0x1cU
#define THRESHOLD_STATUS 0x20U
static uint64_t output[NEURAL_OUTPUT_CAPACITY*8] __attribute__((aligned(64)));
static void wr(uint32_t r,uint32_t v) { Xil_Out32((UINTPTR)BASE+r,v); }
static uint32_t rd(uint32_t r) { return Xil_In32((UINTPTR)BASE+r); }

int main(void)
{
    uint32_t status=0, count, errors=0;
    xil_printf("Threshold-configurable Neural test: %s\r\n",NEURAL_DATASET);
    if(rd(STATUS)&1U) { xil_printf("ERROR hardware is already running\r\n"); return 1; }

    wr(THRESHOLD,NEURAL_THRESHOLD);
    /* FIFO write acknowledgement is not enough: wait until SD receives it. */
    for(uint32_t i=0;i<100000;i++) {
        status=rd(THRESHOLD_STATUS);
        if(status&1U) break;
        usleep(1);
    }
    if(!(status&1U)) { xil_printf("ERROR threshold application timeout\r\n"); return 1; }
    for(uint32_t i=0;i<112;i++) wr(FEATURE,neural_feature[i]);
    /* Existing config FIFO applies ready backpressure; allow final CDC drain. */
    usleep(100);

    memset(output,0,sizeof(output));
    Xil_DCacheFlushRange((INTPTR)neural_input,sizeof(neural_input));
    Xil_DCacheFlushRange((INTPTR)output,sizeof(output));
    wr(INPUT_ADDR,(uint32_t)(UINTPTR)neural_input);
    wr(INPUT_ROWS,NEURAL_INPUT_ROWS);
    wr(OUTPUT_ADDR,(uint32_t)(UINTPTR)output);
    wr(CONTROL,1);
    status=0;
    for(uint32_t i=0;i<10000;i++) {
        status=rd(STATUS);
        if(status&2U) break;
        usleep(1000);
    }
    count=rd(RESULT_COUNT);
    xil_printf("threshold=%u input=%u result=%u status=0x%08x\r\n",
               NEURAL_THRESHOLD,NEURAL_INPUT_ROWS,count,status);
    if(!(status&2U) || (status&4U) || count!=NEURAL_EXPECTED_EVENTS) {
        xil_printf("FAIL completion/count/status\r\n"); return 1;
    }
    Xil_DCacheInvalidateRange((INTPTR)output,sizeof(output));
    for(uint32_t i=0;i<NEURAL_EXPECTED_EVENTS*8;i++) {
        if(output[i]!=neural_golden[i]) {
            if(errors<8) xil_printf("mismatch event=%u word=%u\r\n",i/8,i%8);
            errors++;
        }
    }
    if(errors) { xil_printf("FAIL mismatched words=%u\r\n",errors); return 1; }
    xil_printf("PASS all %u event records match Golden\r\n",count);
    return 0;
}
