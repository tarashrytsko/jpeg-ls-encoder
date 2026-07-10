# ooc_gearbox.tcl — out-of-context synth+P&R of byte_gearbox_12 to measure whether the
# fast (540 MHz) domain closes timing on xc7a200tfbg676-2, with the slow side at 45 MHz.
#   vivado -mode batch -source ooc_gearbox.tcl
set part [expr {$argc > 0 ? [lindex $argv 0] : "xc7a200tfbg676-2"}]
set root "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f"
puts "OOC_PART=$part"
set_param general.maxThreads 1   ;# single-threaded synth: avoids the flaky helper-process spawn
read_verilog "$root/JPEG_ENC_8f.srcs/sources_1/new/byte_gearbox_12.v"
synth_design -top byte_gearbox_12 -part $part -mode out_of_context

create_clock -name clk_fast -period 1.852 [get_ports clk_fast]   ;# 540 MHz
create_clock -name clk_slow -period 22.222 [get_ports clk_slow]  ;# 45 MHz
set_clock_groups -asynchronous -group [get_clocks clk_fast] -group [get_clocks clk_slow]

opt_design
place_design
route_design
report_timing_summary -file $root/gearbox_ooc_timing.rpt

set worst_all  [get_property SLACK [lindex [get_timing_paths -setup -max_paths 1 -nworst 1] 0]]
set worst_fast [get_property SLACK [lindex [get_timing_paths -setup -max_paths 1 -to [get_clocks clk_fast]] 0]]
set worst_slow [get_property SLACK [lindex [get_timing_paths -setup -max_paths 1 -to [get_clocks clk_slow]] 0]]
puts "GEARBOX_OOC WNS_ALL=$worst_all  WNS_CLKFAST=$worst_fast  WNS_CLKSLOW=$worst_slow"
# implied fast-domain Fmax = 1/(period - slack)
if {$worst_fast ne ""} {
    set fmax_fast [expr {1000.0 / (1.852 - $worst_fast)}]
    puts "GEARBOX_OOC FAST_FMAX_MHz=[format %.1f $fmax_fast]"
}
report_utilization -file $root/gearbox_ooc_util.rpt
puts "GEARBOX_OOC_DONE"
