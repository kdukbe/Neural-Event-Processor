# Apply verified SAIF and clock activity to the matching routed DCP.
set root [file dirname [file normalize [info script]]]
set mode $::env(NEURAL_MODE)
set out $::env(NEURAL_OUT)
set core $::env(NEURAL_IP)/inst/u_NeuralCore
open_checkpoint $::env(NEURAL_DCP)
if {[llength [get_cells -quiet $core]] != 1} {error "Missing core: $core"}
set_units -power uW
report_clocks -file [file join $out implemented_clocks.rpt]
read_saif -no_strip -out_file [file join $out unmatched.rpt] [file join $out mapped.saif]
set nets [get_nets -hier -filter "NAME =~ $core/*"]
set f [open [file join $out core_switching_before_power.txt] w]
puts $f [report_switching_activity -return_string -signal_rate -static_probability $nets]
close $f
report_power -hier all -hierarchical_depth 12 -file [file join $out power_native_clock_uW.rpt]
if {$mode eq "event_driven_8mhz"} {
    set gate $core/u_MainPath/g_event_driven.u_SFEClockControl/u_sfe_bufgce
    set ce [get_pins -quiet $gate/CE0]
    if {[llength $ce] != 1} {error "Gated-clock CE0 not found; inspect primitive before continuing"}
    set gate_out [get_pins -quiet $gate/O]
    if {[llength $gate_out] != 1} {error "Gated-clock output not found"}
    source [file join $out clock_activity.tcl]
    # Average-power model based on observed pulses; not a new hardware clock.
    if {$observed_clock_edges > 0} {
        set_case_analysis 1 $ce
        create_clock -name observed_gated_clock -period $observed_clock_period_ns \
            -waveform [list 0 $observed_clock_high_ns] $gate_out
    } else {
        set_case_analysis 0 $ce
    }
}
report_power -hier all -hierarchical_depth 12 -file [file join $out power_modeled_uW.rpt]
report_power -xpe [file join $out power.xpe]
foreach type {register lut lut_ram dsp bram_enable bram_wr_enable} {
    report_switching_activity -signal_rate -static_probability -hier -type $type \
        -file [file join $out activity_${type}.txt] [get_cells $core]
}
report_utilization -cells [get_cells $core] -file [file join $out core_utilization.rpt]
report_clocks -file [file join $out power_model_clocks.rpt]
set f [open [file join $out operating_conditions.txt] w]
puts $f [report_operating_conditions]
close $f
puts "POWER_ANALYSIS_COMPLETE mode=$mode core=$core"
close_design
exit
