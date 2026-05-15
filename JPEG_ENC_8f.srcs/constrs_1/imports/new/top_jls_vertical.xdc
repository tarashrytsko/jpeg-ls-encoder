# Clock Inputs #R3
# -------------------------------------------------------------
# 200 MHz differential system clock (LVDS on AC701)
# -------------------------------------------------------------
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

set_property PACKAGE_PIN R3 [get_ports clk_in1_p]
set_property IOSTANDARD LVDS_25 [get_ports clk_in1_p]

set_property PACKAGE_PIN P3 [get_ports clk_in1_n]
set_property IOSTANDARD LVDS_25 [get_ports clk_in1_n]


#E17
# External 33.33 MHz single-ended clock
# -------------------------------------------------------------
set_property PACKAGE_PIN E17 [get_ports clk]
set_property IOSTANDARD LVCMOS25 [get_ports clk]

#create_clock -name clk -period 30.000 -waveform {0.000 15.000} [get_ports clk]

# =============================================================
# Generated Clocks (from MMCM/PLL)
# Replace "mmcm_inst" with your actual MMCM instance name
# =============================================================

# Reset Input R8
set_property PACKAGE_PIN R8 [get_ports rstn]
set_property IOSTANDARD LVCMOS25 [get_ports rstn]
set_false_path -from [get_ports rstn]
# Control Signals P8
set_property PACKAGE_PIN P8 [get_ports i_sof]
set_property IOSTANDARD LVCMOS25 [get_ports i_sof]
#R7
set_property PACKAGE_PIN R7 [get_ports i_e]
set_property IOSTANDARD LVCMOS25 [get_ports i_e]

# Input Signals: i_x[7:0] G17
set_property PACKAGE_PIN G17 [get_ports i_x[0]]
set_property IOSTANDARD LVCMOS25 [get_ports i_x[0]]
#F17
set_property PACKAGE_PIN F17  [get_ports i_x[1]]
set_property IOSTANDARD LVCMOS25 [get_ports i_x[1]]
#C17
set_property PACKAGE_PIN C17 [get_ports i_x[2]]
set_property IOSTANDARD LVCMOS25 [get_ports i_x[2]]
#B17
set_property PACKAGE_PIN B17  [get_ports i_x[3]]
set_property IOSTANDARD LVCMOS25 [get_ports i_x[3]]
#E20
set_property PACKAGE_PIN E20 [get_ports i_x[4]]
set_property IOSTANDARD LVCMOS25 [get_ports i_x[4]]
#D20
set_property PACKAGE_PIN D20 [get_ports i_x[5]]
set_property IOSTANDARD LVCMOS25 [get_ports i_x[5]]
#E21
set_property PACKAGE_PIN E21  [get_ports i_x[6]]
set_property IOSTANDARD LVCMOS25 [get_ports i_x[6]]
#D21
set_property PACKAGE_PIN D21 [get_ports i_x[7]]
set_property IOSTANDARD LVCMOS25 [get_ports i_x[7]]

# Input Signals: i_w[13:0]
set_property PACKAGE_PIN G19 [get_ports i_w[0]]
set_property IOSTANDARD LVCMOS25 [get_ports i_w[0]]

set_property PACKAGE_PIN F20 [get_ports i_w[1]]
set_property IOSTANDARD LVCMOS25 [get_ports i_w[1]]

set_property PACKAGE_PIN A17 [get_ports i_w[2]]
set_property IOSTANDARD LVCMOS25 [get_ports i_w[2]]

set_property PACKAGE_PIN A18 [get_ports i_w[3]]
set_property IOSTANDARD LVCMOS25 [get_ports i_w[3]]

set_property PACKAGE_PIN C21 [get_ports i_w[4]]
set_property IOSTANDARD LVCMOS25 [get_ports i_w[4]]

set_property PACKAGE_PIN B21 [get_ports i_w[5]]
set_property IOSTANDARD LVCMOS25 [get_ports i_w[5]]

set_property PACKAGE_PIN B20 [get_ports i_w[6]]
set_property IOSTANDARD LVCMOS25 [get_ports i_w[6]]

set_property PACKAGE_PIN H18 [get_ports i_w[7]]
set_property IOSTANDARD LVCMOS25 [get_ports i_w[7]]

set_property PACKAGE_PIN G15 [get_ports i_w[8]]
set_property IOSTANDARD LVCMOS25 [get_ports i_w[8]]

set_property PACKAGE_PIN F15 [get_ports i_w[9]]
set_property IOSTANDARD LVCMOS25 [get_ports i_w[9]]

set_property PACKAGE_PIN E16 [get_ports i_w[10]]
set_property IOSTANDARD LVCMOS25 [get_ports i_w[10]]

set_property PACKAGE_PIN D16 [get_ports i_w[11]]
set_property IOSTANDARD LVCMOS25 [get_ports i_w[11]]

set_property PACKAGE_PIN G20 [get_ports i_w[12]]
set_property IOSTANDARD LVCMOS25 [get_ports i_w[12]]

set_property PACKAGE_PIN G21 [get_ports i_w[13]]
set_property IOSTANDARD LVCMOS25 [get_ports i_w[13]]

# Input Signals: i_h[13:0]
set_property PACKAGE_PIN F23 [get_ports i_h[0]]
set_property IOSTANDARD LVCMOS25 [get_ports i_h[0]]

set_property PACKAGE_PIN E23 [get_ports i_h[1]]
set_property IOSTANDARD LVCMOS25 [get_ports i_h[1]]

set_property PACKAGE_PIN A20 [get_ports i_h[2]]
set_property IOSTANDARD LVCMOS25 [get_ports i_h[2]]

set_property PACKAGE_PIN K21 [get_ports i_h[3]]
set_property IOSTANDARD LVCMOS25 [get_ports i_h[3]]

set_property PACKAGE_PIN J21 [get_ports i_h[4]]
set_property IOSTANDARD LVCMOS25 [get_ports i_h[4]]

set_property PACKAGE_PIN K20 [get_ports i_h[5]]
set_property IOSTANDARD LVCMOS25 [get_ports i_h[5]]

set_property PACKAGE_PIN J20 [get_ports i_h[6]]
set_property IOSTANDARD LVCMOS25 [get_ports i_h[6]]

set_property PACKAGE_PIN J24 [get_ports i_h[7]]
set_property IOSTANDARD LVCMOS25 [get_ports i_h[7]]

set_property PACKAGE_PIN H24 [get_ports i_h[8]]
set_property IOSTANDARD LVCMOS25 [get_ports i_h[8]]

set_property PACKAGE_PIN N16 [get_ports i_h[9]]
set_property IOSTANDARD LVCMOS25 [get_ports i_h[9]]

set_property PACKAGE_PIN D19 [get_ports i_h[10]]
set_property IOSTANDARD LVCMOS25 [get_ports i_h[10]]

set_property PACKAGE_PIN C19 [get_ports i_h[11]]
set_property IOSTANDARD LVCMOS25 [get_ports i_h[11]]

set_property PACKAGE_PIN H14 [get_ports i_h[12]]
set_property IOSTANDARD LVCMOS25 [get_ports i_h[12]]

set_property PACKAGE_PIN H15 [get_ports i_h[13]]
set_property IOSTANDARD LVCMOS25 [get_ports i_h[13]]

# Output Signals
set_property PACKAGE_PIN M26 [get_ports o_e0]
set_property IOSTANDARD LVCMOS25 [get_ports o_e0]
set_property PACKAGE_PIN T24 [get_ports o_e1]
set_property IOSTANDARD LVCMOS25 [get_ports o_e1]
set_property PACKAGE_PIN T25 [get_ports o_e2]
set_property IOSTANDARD LVCMOS25 [get_ports o_e2]

set_property PACKAGE_PIN R26 [get_ports o_last0]
set_property IOSTANDARD LVCMOS25 [get_ports o_last0]
set_property PACKAGE_PIN P26 [get_ports o_last1]
set_property IOSTANDARD LVCMOS25 [get_ports o_last1]
set_property PACKAGE_PIN T22 [get_ports o_last2]
set_property IOSTANDARD LVCMOS25 [get_ports o_last2]

set_property PACKAGE_PIN AD25 [get_ports o_data0[0]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data0[0]]

set_property PACKAGE_PIN AD26 [get_ports o_data0[1]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data0[1]]

set_property PACKAGE_PIN AF19 [get_ports o_data0[2]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data0[2]]

set_property PACKAGE_PIN AF20 [get_ports o_data0[3]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data0[3]]

set_property PACKAGE_PIN AC18 [get_ports o_data0[4]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data0[4]]

set_property PACKAGE_PIN AD18 [get_ports o_data0[5]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data0[5]]

set_property PACKAGE_PIN AE17 [get_ports o_data0[6]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data0[6]]

set_property PACKAGE_PIN AF17 [get_ports o_data0[7]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data0[7]]

set_property PACKAGE_PIN Y16 [get_ports o_data0[8]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data0[8]]

set_property PACKAGE_PIN Y17 [get_ports o_data0[9]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data0[9]]

set_property PACKAGE_PIN AF24 [get_ports o_data0[10]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data0[10]]

set_property PACKAGE_PIN AF25 [get_ports o_data0[11]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data0[11]]

set_property PACKAGE_PIN AD21 [get_ports o_data0[12]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data0[12]]

set_property PACKAGE_PIN AE21 [get_ports o_data0[13]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data0[13]]

set_property PACKAGE_PIN AC19 [get_ports o_data0[14]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data0[14]]

set_property PACKAGE_PIN AD19 [get_ports o_data0[15]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data0[15]]

set_property PACKAGE_PIN H21 [get_ports o_data1[0]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data1[0]]

set_property PACKAGE_PIN H22 [get_ports o_data1[1]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data1[1]]

set_property PACKAGE_PIN D18 [get_ports o_data1[2]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data1[2]]

set_property PACKAGE_PIN C18 [get_ports o_data1[3]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data1[3]]

set_property PACKAGE_PIN AC22 [get_ports o_data1[4]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data1[4]]

set_property PACKAGE_PIN AC23 [get_ports o_data1[5]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data1[5]]

set_property PACKAGE_PIN AD23 [get_ports o_data1[6]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data1[6]]

set_property PACKAGE_PIN AD24 [get_ports o_data1[7]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data1[7]]

set_property PACKAGE_PIN AD20 [get_ports o_data1[8]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data1[8]]

set_property PACKAGE_PIN AE20 [get_ports o_data1[9]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data1[9]]

set_property PACKAGE_PIN AE18 [get_ports o_data1[10]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data1[10]]

set_property PACKAGE_PIN AF18 [get_ports o_data1[11]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data1[11]]

set_property PACKAGE_PIN AA17 [get_ports o_data1[12]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data1[12]]

set_property PACKAGE_PIN AB17 [get_ports o_data1[13]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data1[13]]

set_property PACKAGE_PIN Y15 [get_ports o_data1[14]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data1[14]]

set_property PACKAGE_PIN AA15 [get_ports o_data1[15]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data1[15]]

set_property PACKAGE_PIN AE25 [get_ports o_data2[0]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data2[0]]
set_property PACKAGE_PIN AE26 [get_ports o_data2[1]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data2[1]]

set_property PACKAGE_PIN AE23 [get_ports o_data2[2]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data2[2]]

set_property PACKAGE_PIN AF23 [get_ports o_data2[3]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data2[3]]

set_property PACKAGE_PIN AE22 [get_ports o_data2[4]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data2[4]]

set_property PACKAGE_PIN AF22 [get_ports o_data2[5]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data2[5]]

set_property PACKAGE_PIN AA20 [get_ports o_data2[6]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data2[6]]

set_property PACKAGE_PIN AB20 [get_ports o_data2[7]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data2[7]]

set_property PACKAGE_PIN AB16 [get_ports o_data2[8]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data2[8]]

set_property PACKAGE_PIN AC16 [get_ports o_data2[9]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data2[9]]

set_property PACKAGE_PIN W14 [get_ports o_data2[10]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data2[10]]

set_property PACKAGE_PIN W15 [get_ports o_data2[11]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data2[11]]

set_property PACKAGE_PIN AD17 [get_ports o_data2[12]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data2[12]]

set_property PACKAGE_PIN AC17 [get_ports o_data2[13]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data2[13]]

set_property PACKAGE_PIN AA18 [get_ports o_data2[14]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data2[14]]

set_property PACKAGE_PIN Y18 [get_ports o_data2[15]]
set_property IOSTANDARD LVCMOS25 [get_ports o_data2[15]]

set_property PACKAGE_PIN R6 [get_ports sys_rdy]
set_property IOSTANDARD LVCMOS25 [get_ports sys_rdy]

