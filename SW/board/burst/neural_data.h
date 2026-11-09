#ifndef NEURAL_DATA_H
#define NEURAL_DATA_H
#include <stdint.h>
#define NEURAL_DATASET "burst"
#define NEURAL_THRESHOLD 24962U
#define NEURAL_INPUT_ROWS 33280U
#define NEURAL_EXPECTED_EVENTS 504U
#define NEURAL_OUTPUT_CAPACITY 544U
extern const uint64_t neural_input[NEURAL_INPUT_ROWS];
extern const uint64_t neural_golden[NEURAL_EXPECTED_EVENTS*8];
extern const uint32_t neural_feature[112];
#endif
