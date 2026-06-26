# build_fmax2.tcl  —  run: vivado -mode batch -source build_fmax2.tcl
# Reconfigures clk_wiz_0 to wr=60 MHz / rd=30 MHz with EXPLICIT MMCM dividers
# (VCO=1200: MULT=6, DIVCLK=1, CLKOUT0=20 -> 60, CLKOUT1=40 -> 30). The .xci had
# stale user-pinned MMCM params, so REQUESTED_OUT_FREQ alone was ignored; we set
# the dividers directly. We also disable the IP cache and force the IP to
# re-synthesize so the new config is actually built (not served from cache).
# 30 MHz encoder clk is well under the measured ~40 MHz Fmax (24.7 ns path) for a
# reliable first-pass close.
set root "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f"
open_project $root/JPEG_ENC_8f.xpr

config_ip_cache -disable_cache

set_property -dict [list \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {60.000} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {30.000} \
    CONFIG.MMCM_DIVCLK_DIVIDE {1} \
    CONFIG.MMCM_CLKFBOUT_MULT_F {6.000} \
    CONFIG.MMCM_CLKOUT0_DIVIDE_F {20.000} \
    CONFIG.MMCM_CLKOUT1_DIVIDE {40} \
    CONFIG.CLKOUT1_JITTER {120.000} \
    CONFIG.CLKOUT2_JITTER {132.000} ] [get_ips clk_wiz_0]

reset_target -quiet all [get_ips clk_wiz_0]
generate_target all [get_ips clk_wiz_0]
catch { reset_run clk_wiz_0_synth_1 }
catch { synth_ip [get_ips clk_wiz_0] }
puts "CLKWIZ_RECONFIGURED_V2"

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    puts "FMAX2_SYNTH_FAILED"
} else {
    reset_run impl_1
    launch_runs impl_1 -to_step write_bitstream -jobs 8
    wait_on_run impl_1
    set ip [get_property PROGRESS [get_runs impl_1]]
    puts "IMPL_PROGRESS: $ip  STATUS: [get_property STATUS [get_runs impl_1]]"
    if {$ip ne "100%"} {
        puts "FMAX2_IMPL_FAILED"
    } else {
        open_run impl_1
        report_utilization    -file $root/fmax_util.rpt
        report_timing_summary -file $root/fmax_timing.rpt
        puts "FMAX2_DONE WNS=[get_property STATS.WNS [get_runs impl_1]] WHS=[get_property STATS.WHS [get_runs impl_1]]"
        foreach c [get_clocks] { puts "CLOCK $c period=[get_property PERIOD $c]" }
    }
}
