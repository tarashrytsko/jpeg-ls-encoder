# build_n12_45.tcl  —  run: vivado -mode batch -source build_n12_45.tcl
# 12-lane (N_E=12) jls_demo_top timing-closed build at 45/45 MHz (1:1).
# Proves the 12-chunk config closes timing at 45 MHz -> throughput 12 x 45 = 540 MB/s.
# Uses vertical 12x1 @ 300x300 (tightest-slack mode, small div-by-12 ROM fits BRAM:
# 300*300/12 = 7500 words x 96 bit = 90 KB). clk_wiz set to 45 MHz: VCO=900
# (MULT=4.5, DIVCLK=1), CLKOUT0=CLKOUT1=20 -> 45 MHz.
set root "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f"
open_project $root/JPEG_ENC_8f.xpr

# --- clk_wiz -> 45/45 ---
config_ip_cache -disable_cache
set_property -dict [list \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {45.000} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {45.000} \
    CONFIG.MMCM_DIVCLK_DIVIDE {1} \
    CONFIG.MMCM_CLKFBOUT_MULT_F {4.500} \
    CONFIG.MMCM_CLKOUT0_DIVIDE_F {20.000} \
    CONFIG.MMCM_CLKOUT1_DIVIDE {20} ] [get_ips clk_wiz_0]
reset_target -quiet all [get_ips clk_wiz_0]
generate_target all [get_ips clk_wiz_0]
catch { reset_run clk_wiz_0_synth_1 }
catch { synth_ip [get_ips clk_wiz_0] }
puts "N12_CLK45_SET out1=[get_property CONFIG.CLKOUT1_REQUESTED_OUT_FREQ [get_ips clk_wiz_0]]"

# --- ROM + generics (N_E=12, vertical 12x1, 300x300) ---
file copy -force $root/JPEG_ENC_8f.sim/images/vert12x1_300.hex $root/JPEG_ENC_8f.srcs/sources_1/new/rom_wide.hex
set_property top jls_demo_top [get_filesets sources_1]
set_property generic "N_E=12 N_H=12 N_V=1 IMG_W=300 IMG_H=300" [get_filesets sources_1]
update_compile_order -fileset sources_1
puts "N12_GENERIC_SET: [get_property generic [get_filesets sources_1]]"

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { puts "N12_SYNTH_FAILED"; exit 1 }

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
set ip [get_property PROGRESS [get_runs impl_1]]
puts "N12_IMPL_PROGRESS: $ip STATUS: [get_property STATUS [get_runs impl_1]]"
if {$ip ne "100%"} { puts "N12_IMPL_FAILED"; exit 1 }

open_run impl_1
report_utilization    -file $root/n12_45_util.rpt
report_timing_summary -file $root/n12_45_timing.rpt
set wns [get_property STATS.WNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
puts "N12_45_DONE WNS=$wns WHS=$whs THROUGHPUT_MBps=[expr {12*45}]"
