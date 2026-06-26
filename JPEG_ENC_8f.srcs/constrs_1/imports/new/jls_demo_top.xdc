# =============================================================
# jls_demo_top.xdc
# Pin/timing constraints for jls_demo_top (N_E=2)
# Reuses board pins from top_jls_vertical.xdc (AC701 board)
# =============================================================

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# -------------------------------------------------------------
# 200 MHz differential system clock (LVDS on AC701)
# -------------------------------------------------------------
set_property PACKAGE_PIN R3 [get_ports clk_in1_p]
set_property IOSTANDARD LVDS_25 [get_ports clk_in1_p]

set_property PACKAGE_PIN P3 [get_ports clk_in1_n]
set_property IOSTANDARD LVDS_25 [get_ports clk_in1_n]

create_clock -name sys_clk_pin -period 5.000 [get_ports clk_in1_p]

# -------------------------------------------------------------
# MMCM-generated clock output (E17, LVCMOS25)
# -------------------------------------------------------------
set_property PACKAGE_PIN E17 [get_ports clk]
set_property IOSTANDARD LVCMOS25 [get_ports clk]

# -------------------------------------------------------------
# Reset input (R8, LVCMOS25, async — false path)
# -------------------------------------------------------------
set_property PACKAGE_PIN R8 [get_ports rstn]
set_property IOSTANDARD LVCMOS25 [get_ports rstn]
set_false_path -from [get_ports rstn]

# -------------------------------------------------------------
# Output: o_e[1:0]  (encoder-enable / data-valid flags)
#   o_e[0] <- old o_e0  (M26)
#   o_e[1] <- old o_e1  (T24)
# -------------------------------------------------------------
set_property PACKAGE_PIN M26 [get_ports {o_e[0]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_e[0]}]

set_property PACKAGE_PIN T24 [get_ports {o_e[1]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_e[1]}]

# -------------------------------------------------------------
# Output: o_last[1:0]  (end-of-slice flags)
#   o_last[0] <- old o_last0  (R26)
#   o_last[1] <- old o_last1  (P26)
# -------------------------------------------------------------
set_property PACKAGE_PIN R26 [get_ports {o_last[0]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_last[0]}]

set_property PACKAGE_PIN P26 [get_ports {o_last[1]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_last[1]}]

# -------------------------------------------------------------
# Output: o_data[31:0]
#   o_data[15:0]  = encoder0  <- old o_data0[15:0]
#   o_data[31:16] = encoder1  <- old o_data1[15:0]
# -------------------------------------------------------------

# encoder0 -> o_data[0..15]
set_property PACKAGE_PIN AD25 [get_ports {o_data[0]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[0]}]

set_property PACKAGE_PIN AD26 [get_ports {o_data[1]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[1]}]

set_property PACKAGE_PIN AF19 [get_ports {o_data[2]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[2]}]

set_property PACKAGE_PIN AF20 [get_ports {o_data[3]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[3]}]

set_property PACKAGE_PIN AC18 [get_ports {o_data[4]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[4]}]

set_property PACKAGE_PIN AD18 [get_ports {o_data[5]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[5]}]

set_property PACKAGE_PIN AE17 [get_ports {o_data[6]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[6]}]

set_property PACKAGE_PIN AF17 [get_ports {o_data[7]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[7]}]

set_property PACKAGE_PIN Y16 [get_ports {o_data[8]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[8]}]

set_property PACKAGE_PIN Y17 [get_ports {o_data[9]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[9]}]

set_property PACKAGE_PIN AF24 [get_ports {o_data[10]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[10]}]

set_property PACKAGE_PIN AF25 [get_ports {o_data[11]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[11]}]

set_property PACKAGE_PIN AD21 [get_ports {o_data[12]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[12]}]

set_property PACKAGE_PIN AE21 [get_ports {o_data[13]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[13]}]

set_property PACKAGE_PIN AC19 [get_ports {o_data[14]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[14]}]

set_property PACKAGE_PIN AD19 [get_ports {o_data[15]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[15]}]

# encoder1 -> o_data[16..31]
set_property PACKAGE_PIN H21 [get_ports {o_data[16]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[16]}]

set_property PACKAGE_PIN H22 [get_ports {o_data[17]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[17]}]

set_property PACKAGE_PIN D18 [get_ports {o_data[18]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[18]}]

set_property PACKAGE_PIN C18 [get_ports {o_data[19]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[19]}]

set_property PACKAGE_PIN AC22 [get_ports {o_data[20]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[20]}]

set_property PACKAGE_PIN AC23 [get_ports {o_data[21]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[21]}]

set_property PACKAGE_PIN AD23 [get_ports {o_data[22]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[22]}]

set_property PACKAGE_PIN AD24 [get_ports {o_data[23]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[23]}]

set_property PACKAGE_PIN AD20 [get_ports {o_data[24]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[24]}]

set_property PACKAGE_PIN AE20 [get_ports {o_data[25]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[25]}]

set_property PACKAGE_PIN AE18 [get_ports {o_data[26]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[26]}]

set_property PACKAGE_PIN AF18 [get_ports {o_data[27]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[27]}]

set_property PACKAGE_PIN AA17 [get_ports {o_data[28]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[28]}]

set_property PACKAGE_PIN AB17 [get_ports {o_data[29]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[29]}]

set_property PACKAGE_PIN Y15 [get_ports {o_data[30]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[30]}]

set_property PACKAGE_PIN AA15 [get_ports {o_data[31]}]
set_property IOSTANDARD LVCMOS25 [get_ports {o_data[31]}]
