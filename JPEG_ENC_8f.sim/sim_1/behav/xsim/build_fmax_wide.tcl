# build_fmax_wide.tcl  —  run:
#   vivado -mode batch -source build_fmax_wide.tcl -tclargs <DIV>
# fmax sweep for the wide design. Reconfigures clk_wiz_0 to a 1:1 clock at
# f = 800/DIV MHz (VCO = 200MHz*MULT/DIVCLK = 200*4/1 = 800; both CLKOUT = DIV),
# forces the IP to re-synthesize, then runs synth_1 + impl_1 through route_design
# and reports WNS/WHS. Builds whatever mode the .xpr generic currently selects
# (vertical 16x1 by default — the tightest-slack mode, so its fmax is the floor
# for all three directions). No bitstream (route_design is enough for timing).
#   DIV=20 -> 40.0 MHz,  19 -> 42.1,  18 -> 44.4,  17 -> 47.1,  16 -> 50.0

if {$argc < 1} { puts "USAGE: -tclargs <DIV>"; exit 1 }
set DIV [lindex $argv 0]
set FREQ [expr {800.0 / $DIV}]

set root "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f"
open_project $root/JPEG_ENC_8f.xpr

config_ip_cache -disable_cache
set_property -dict [list \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ [format %.3f $FREQ] \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ [format %.3f $FREQ] \
    CONFIG.MMCM_DIVCLK_DIVIDE {1} \
    CONFIG.MMCM_CLKFBOUT_MULT_F {4.000} \
    CONFIG.MMCM_CLKOUT0_DIVIDE_F [format %.3f $DIV] \
    CONFIG.MMCM_CLKOUT1_DIVIDE $DIV ] [get_ips clk_wiz_0]
reset_target -quiet all [get_ips clk_wiz_0]
generate_target all [get_ips clk_wiz_0]
catch { reset_run clk_wiz_0_synth_1 }
catch { synth_ip [get_ips clk_wiz_0] }
puts "FMAX_CLK_SET DIV=$DIV FREQ=[format %.3f $FREQ]"

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { puts "FMAX_SYNTH_FAILED DIV=$DIV"; exit 1 }

reset_run impl_1
launch_runs impl_1 -to_step route_design -jobs 8
wait_on_run impl_1
set ip [get_property PROGRESS [get_runs impl_1]]
set st [get_property STATUS [get_runs impl_1]]
puts "FMAX_IMPL DIV=$DIV PROGRESS=$ip STATUS=$st"
if {$ip ne "100%"} { puts "FMAX_IMPL_INCOMPLETE DIV=$DIV"; exit 1 }

open_run impl_1
set wns [get_property STATS.WNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
report_timing_summary -file $root/fmax_div${DIV}_timing.rpt
puts "FMAX_RESULT DIV=$DIV FREQ=[format %.3f $FREQ] WNS=$wns WHS=$whs THROUGHPUT_MBps=[format %.1f [expr {$FREQ * 16}]]"
