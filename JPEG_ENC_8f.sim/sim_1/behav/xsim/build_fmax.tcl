# build_fmax.tcl  —  run: vivado -mode batch -source build_fmax.tcl
# Raises the clk_wiz output clocks to a realistic Artix-7 target (wr 75 MHz / rd
# 37.5 MHz, both under the estimated Fmax: encoder ~40 MHz, input ~83 MHz),
# regenerates the IP, then re-runs synth + impl to a timing-closed bitstream.
set root "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f"
open_project $root/JPEG_ENC_8f.xpr

# Reconfigure clk_wiz_0: clk_out1 (wr_clk) = 75 MHz, clk_out2 (rd_clk) = 37.5 MHz.
set_property -dict [list \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {75.000} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {37.500} ] [get_ips clk_wiz_0]
generate_target all [get_ips clk_wiz_0]
puts "CLKWIZ_RECONFIGURED"

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
set sp [get_property PROGRESS [get_runs synth_1]]
puts "SYNTH_PROGRESS: $sp"
if {$sp ne "100%"} {
    puts "FMAX_SYNTH_FAILED"
} else {
    reset_run impl_1
    launch_runs impl_1 -to_step write_bitstream -jobs 8
    wait_on_run impl_1
    set ip [get_property PROGRESS [get_runs impl_1]]
    set ist [get_property STATUS [get_runs impl_1]]
    puts "IMPL_PROGRESS: $ip  STATUS: $ist"
    if {$ip ne "100%"} {
        puts "FMAX_IMPL_FAILED"
    } else {
        open_run impl_1
        report_utilization    -file $root/fmax_util.rpt
        report_timing_summary -file $root/fmax_timing.rpt
        set wns [get_property STATS.WNS [get_runs impl_1]]
        set whs [get_property STATS.WHS [get_runs impl_1]]
        puts "FMAX_DONE WNS=$wns WHS=$whs"
    }
}
