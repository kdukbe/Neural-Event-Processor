# Read-only checks of the average clock model on the same board placement.
set mode $::env(NEURAL_MODE)
set case_dir $::env(NEURAL_OUT)
set out [file join $case_dir audit]
set core $::env(NEURAL_IP)/inst/u_NeuralCore
file mkdir $out
open_checkpoint $::env(NEURAL_DCP)
if {[llength [get_cells -quiet $core]] != 1} {error "Missing Core"}
set_units -power uW
read_saif -no_strip [file join $case_dir mapped.saif]
report_clocks -file [file join $out implemented_clocks.rpt]
report_power -hier all -hierarchical_depth 0 -file [file join $out native_uW.rpt]
set nets [get_nets -hier -filter "NAME =~ $core/*"]
set f [open [file join $out native_activity.txt] w]
puts $f [report_switching_activity -return_string -signal_rate -static_probability $nets]
close $f
if {$mode eq "event_driven_8mhz"} {
    set gate $core/u_MainPath/g_event_driven.u_SFEClockControl/u_sfe_bufgce
    set ce [get_pins $gate/CE0]
    set op [get_pins $gate/O]
    if {[llength $ce] != 1 || [llength $op] != 1} {error "Missing gate pins"}
    set_case_analysis 1 $ce
    report_power -hier all -hierarchical_depth 0 -file [file join $out forced_on_uW.rpt]
    set_case_analysis 0 $ce
    report_power -hier all -hierarchical_depth 0 -file [file join $out forced_off_uW.rpt]
    set_case_analysis 1 $ce
    source [file join $case_dir clock_activity.tcl]
    if {$observed_clock_edges <= 0} {error "No measured clock pulses in workload"}
    create_clock -name observed_gated_clock -period $observed_clock_period_ns \
        -waveform [list 0 $observed_clock_high_ns] $op
    set f [open [file join $out affected_clock_pins.txt] w]
    foreach pin [lsort [get_pins -of_objects [get_nets -segments -of_objects $op] \
                      -filter {DIRECTION == IN && IS_CLOCK == 1}]] {
        puts $f "$pin | [get_clocks -of_objects [get_pins $pin]]"
    }
    close $f
}
report_power -hier all -hierarchical_depth 0 -file [file join $out modeled_uW.rpt]
report_clocks -file [file join $out analysis_clocks.rpt]
set f [open [file join $out modeled_activity.txt] w]
puts $f [report_switching_activity -return_string -signal_rate -static_probability $nets]
close $f
puts "AUDIT_POWER_COMPLETE mode=$mode core=$core"
close_design
exit
