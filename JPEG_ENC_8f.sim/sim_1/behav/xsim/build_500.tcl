# build_500.tcl  —  run: vivado -mode batch -source build_500.tcl
# TEST ONLY: target 500 MB/s (= 4 Gb/s = 500 Mpix/s at 1 byte/cycle) by setting
# clk_wiz to wr=500 MHz / rd=250 MHz, then run synthesis and report timing. The
# encoder logic Fmax is ~40-46 MHz (input ~93 MHz), so this is expected to FAIL
# timing badly; the point is to quantify the negative slack. clk_wiz is restored
# to the committed 60/30 afterward (outside this script, via git).
set root "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f"
open_project $root/JPEG_ENC_8f.xpr

config_ip_cache -disable_cache
# VCO = 200*5 = 1000 MHz (valid). clk_out1 = 1000/2 = 500, clk_out2 = 1000/4 = 250.
set_property -dict [list \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {500.000} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {250.000} \
    CONFIG.MMCM_DIVCLK_DIVIDE {1} \
    CONFIG.MMCM_CLKFBOUT_MULT_F {5.000} \
    CONFIG.MMCM_CLKOUT0_DIVIDE_F {2.000} \
    CONFIG.MMCM_CLKOUT1_DIVIDE {4} ] [get_ips clk_wiz_0]
reset_target -quiet all [get_ips clk_wiz_0]
generate_target all [get_ips clk_wiz_0]
catch { reset_run clk_wiz_0_synth_1 }
catch { synth_ip [get_ips clk_wiz_0] }
puts "CLK500_RECONFIGURED"

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    puts "TEST500_SYNTH_FAILED"
} else {
    open_run synth_1
    report_timing_summary -file $root/test500_timing.rpt
    puts "TEST500_SYNTH_DONE"
    foreach c [get_clocks] { puts "CLOCK $c period=[get_property PERIOD $c] MHz=[expr {1000.0/[get_property PERIOD $c]}]" }
}
