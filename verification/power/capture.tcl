run 1 ms
open_saif $::env(NEURAL_COMPARE_SAIF)
source capture_scopes.tcl
set logged 0
foreach scope $capture_scopes {
 set parts {}
 foreach part [split $scope /] {
  if {$part ne "" && ![regexp {^[A-Za-z_][A-Za-z_0-9]*$} $part]} {set part "\\$part "}
  lappend parts $part
 }
 set pattern [join $parts /]
 current_scope $pattern
 set objects [get_objects]
 if {[llength $objects]==0} {error "SAIF_EMPTY_SCOPE $scope"}
 incr logged [llength $objects]
 log_saif $objects
}
puts "SAIF_CAPTURE netlist_scope_objects=$logged"
current_scope /tb_RoutedPower
run $::env(NEURAL_COMPARE_OBSERVATION_NS) ns
close_saif
run all
quit
