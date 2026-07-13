# =============================================================
# jls_demo_top_wide.xdc
# Pin/timing constraints for jls_demo_top (N_E=16, wide harness)
# Board: Xilinx AC701 (xc7a200tfbg676-2)
#
# Ports:
#   rstn        – input  (1)
#   clk_in1_p   – input  (1)   differential clock +
#   clk_in1_n   – input  (1)   differential clock -
#   clk         – output (1)   MMCM-generated clock brought out
#   done        – output (1)   completion flag
#   status[30:0]– output (31)  checksum bits
#
# Package-pin sources:
#   clk_in1_p/n, clk, rstn – copied verbatim from top_jls_vertical.xdc / jls_demo_top.xdc
#   done + status[0..30]   – the 32 o_data[0..31] pins from jls_demo_top.xdc (known-good
#                            LVCMOS25 output-capable pins on AC701)
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
# done — completion flag
#   Reuses o_data[31] pin (AA15) from jls_demo_top.xdc
# -------------------------------------------------------------
set_property PACKAGE_PIN AA15 [get_ports done]
set_property IOSTANDARD LVCMOS25 [get_ports done]

# -------------------------------------------------------------
# status[30:0] — checksum bits
#   Reuses o_data[0..30] pins from jls_demo_top.xdc (31 pins)
# -------------------------------------------------------------
set_property PACKAGE_PIN AD25 [get_ports {status[0]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[0]}]

set_property PACKAGE_PIN AD26 [get_ports {status[1]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[1]}]

set_property PACKAGE_PIN AF19 [get_ports {status[2]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[2]}]

set_property PACKAGE_PIN AF20 [get_ports {status[3]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[3]}]

set_property PACKAGE_PIN AC18 [get_ports {status[4]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[4]}]

set_property PACKAGE_PIN AD18 [get_ports {status[5]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[5]}]

set_property PACKAGE_PIN AE17 [get_ports {status[6]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[6]}]

set_property PACKAGE_PIN AF17 [get_ports {status[7]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[7]}]

set_property PACKAGE_PIN Y16 [get_ports {status[8]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[8]}]

set_property PACKAGE_PIN Y17 [get_ports {status[9]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[9]}]

set_property PACKAGE_PIN AF24 [get_ports {status[10]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[10]}]

set_property PACKAGE_PIN AF25 [get_ports {status[11]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[11]}]

set_property PACKAGE_PIN AD21 [get_ports {status[12]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[12]}]

set_property PACKAGE_PIN AE21 [get_ports {status[13]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[13]}]

set_property PACKAGE_PIN AC19 [get_ports {status[14]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[14]}]

set_property PACKAGE_PIN AD19 [get_ports {status[15]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[15]}]

set_property PACKAGE_PIN H21 [get_ports {status[16]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[16]}]

set_property PACKAGE_PIN H22 [get_ports {status[17]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[17]}]

set_property PACKAGE_PIN D18 [get_ports {status[18]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[18]}]

set_property PACKAGE_PIN C18 [get_ports {status[19]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[19]}]

set_property PACKAGE_PIN AC22 [get_ports {status[20]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[20]}]

set_property PACKAGE_PIN AC23 [get_ports {status[21]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[21]}]

set_property PACKAGE_PIN AD23 [get_ports {status[22]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[22]}]

set_property PACKAGE_PIN AD24 [get_ports {status[23]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[23]}]

set_property PACKAGE_PIN AD20 [get_ports {status[24]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[24]}]

set_property PACKAGE_PIN AE20 [get_ports {status[25]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[25]}]

set_property PACKAGE_PIN AE18 [get_ports {status[26]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[26]}]

set_property PACKAGE_PIN AF18 [get_ports {status[27]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[27]}]

set_property PACKAGE_PIN AA17 [get_ports {status[28]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[28]}]

set_property PACKAGE_PIN AB17 [get_ports {status[29]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[29]}]

set_property PACKAGE_PIN Y15 [get_ports {status[30]}]
set_property IOSTANDARD LVCMOS25 [get_ports {status[30]}]

# ---- 12 serial pixel-data lanes (ISERDES inputs) ----
# Left unplaced here: auto-placed on ISERDES-capable pins (UCIO downgraded in the build TCL);
# a real board pins these + adds IDELAYE2 calibration. Input capture is source/board-dependent,
# so the raw pad->ISERDES paths are treated as false paths for this demo bitstream.
set_false_path -from [get_ports {ser_d[*]}]
