# clkwiz_3232.tcl  —  run: vivado -mode batch -source clkwiz_3232.tcl
# Wide design runs 1:1 (input N_E px/cycle = lanes' N_E px/cycle consumption).
# Set clk_wiz to wr_clk=32 / rd_clk=32 MHz. VCO=800 (MULT=4.0, DIVCLK=1),
# CLKOUT0=CLKOUT1=25 -> 32/32. 32 MHz x 16 lanes = 512 Mpix/s = the design point.
set root "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f"
open_project $root/JPEG_ENC_8f.xpr
config_ip_cache -disable_cache
set_property -dict [list \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {32.000} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {32.000} \
    CONFIG.MMCM_DIVCLK_DIVIDE {1} \
    CONFIG.MMCM_CLKFBOUT_MULT_F {4.000} \
    CONFIG.MMCM_CLKOUT0_DIVIDE_F {25.000} \
    CONFIG.MMCM_CLKOUT1_DIVIDE {25} ] [get_ips clk_wiz_0]
reset_target -quiet all [get_ips clk_wiz_0]
generate_target all [get_ips clk_wiz_0]
catch { reset_run clk_wiz_0_synth_1 }
catch { synth_ip [get_ips clk_wiz_0] }
puts "CLKWIZ_3232 out1=[get_property CONFIG.CLKOUT1_REQUESTED_OUT_FREQ [get_ips clk_wiz_0]] out2=[get_property CONFIG.CLKOUT2_REQUESTED_OUT_FREQ [get_ips clk_wiz_0]]"
