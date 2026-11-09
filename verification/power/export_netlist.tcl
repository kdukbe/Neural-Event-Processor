# Called only by run_case.ps1 -Start. Never modify the archived board DCP.
set dcp $::env(NEURAL_DCP)
set ip $::env(NEURAL_IP)
set build $::env(NEURAL_BUILD)
set core $ip/inst/u_NeuralCore
open_checkpoint $dcp
if {[llength [get_cells -quiet $core]] != 1} {error "Missing core: $core"}
set sfe_period [expr {$::env(NEURAL_MODE) eq "always_on_1mhz" ? 1000.0 : 125.0}]
foreach {pin expected} [list AXI_CLK 10.0 SAMPLE_CLK 2500.0 MAIN_CLK 75.0 SFE_CLK $sfe_period] {
    set clocks [get_clocks -of_objects [get_pins $ip/$pin]]
    if {[llength $clocks] != 1} {error "Expected one implemented clock at $ip/$pin: $clocks"}
    set actual [get_property PERIOD $clocks]
    if {abs($actual-$expected)>0.002} {error "Clock mismatch $pin: $actual vs $expected ns"}
    puts "VERIFIED_CLOCK $pin period_ns=$actual"
}
write_verilog -force -mode funcsim -cell $ip -rename_top BoardIPNetlist [file join $build board_ip_funcsim.v]
report_clocks -file [file join $build implemented_clocks.rpt]
report_utilization -cells [get_cells $core] -file [file join $build core_utilization.rpt]
set f [open [file join $build capture_scopes.tcl] w]
puts $f {set capture_scopes {}}
puts $f [list lappend capture_scopes /tb_RoutedPower/DUT]
foreach c [get_cells -hier -filter "NAME =~ $ip/* && IS_PRIMITIVE == 0"] {
    set name [get_property NAME $c]
    set scope /tb_RoutedPower/DUT[string range $name [string length $ip] end]
    puts $f [list lappend capture_scopes $scope]
}
close $f
close_design
exit
