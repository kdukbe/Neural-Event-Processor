# ONLY for standalone top OOC synthesis, not the Zynq block design.
create_clock -name axi_clk -period 10 [get_ports AXI_CLK]
create_clock -name sample_clk -period 2500 [get_ports SAMPLE_CLK]
create_clock -name main_clk -period 75 [get_ports MAIN_CLK]
create_clock -name sfe_clk -period 125 [get_ports SFE_CLK]
set_clock_groups -asynchronous -group [get_clocks axi_clk] -group [get_clocks sample_clk] -group [get_clocks main_clk] -group [get_clocks sfe_clk]

