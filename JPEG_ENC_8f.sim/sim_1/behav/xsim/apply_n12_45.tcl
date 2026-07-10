# apply_n12_45.tcl  —  run: vivado -mode batch -source apply_n12_45.tcl
# Makes N_E=12 @ 45 MHz (vertical 12x1, 300x300) the ACTIVE project configuration:
#   - clk_wiz_0 -> 45/45 MHz (VCO=900: MULT=4.5, DIVCLK=1, CLKOUT0=CLKOUT1=20)
#   - sources_1 generic -> N_E=12 N_H=12 N_V=1 IMG_W=300 IMG_H=300
#   - rom_wide.hex <- vert12x1_300.hex (12-lane vertical strided ROM)
# Regenerates the clk_wiz IP so .gen products match the .xci. No synth/impl.
# (jls_demo_top module defaults stay N_E=16 so build_wide_mode.tcl 16-lane still works.)
set root "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f"
open_project $root/JPEG_ENC_8f.xpr

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

file copy -force $root/JPEG_ENC_8f.sim/images/vert12x1_300.hex $root/JPEG_ENC_8f.srcs/sources_1/new/rom_wide.hex
set_property top jls_demo_top [get_filesets sources_1]
set_property generic "N_E=12 N_H=12 N_V=1 IMG_W=300 IMG_H=300" [get_filesets sources_1]
update_compile_order -fileset sources_1
puts "APPLY_N12_45: clk out1=[get_property CONFIG.CLKOUT1_REQUESTED_OUT_FREQ [get_ips clk_wiz_0]] generic=[get_property generic [get_filesets sources_1]]"
close_project
puts "APPLY_N12_45_DONE"
