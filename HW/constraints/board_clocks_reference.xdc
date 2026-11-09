
set_input_jitter [get_clocks clk_fpga_0] 0.300
set_input_jitter [get_clocks clk_fpga_1] 0.300
set_input_jitter [get_clocks clk_fpga_2] 0.300
set_input_jitter [get_clocks clk_fpga_3] 0.300

set_clock_groups -asynchronous \
    -group [get_clocks clk_fpga_0] \
    -group [get_clocks clk_fpga_1] \
    -group [get_clocks clk_fpga_2] \
    -group [get_clocks clk_fpga_3]