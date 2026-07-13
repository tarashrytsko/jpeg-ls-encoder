// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2024.2 (win64) Build 5239630 Fri Nov 08 22:35:27 MST 2024
// Date        : Mon Jul 13 22:03:16 2026
// Host        : DESKTOP-PHB4K70 running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               d:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f/JPEG_ENC_8f.gen/sources_1/ip/jls_encoder_ip/jls_encoder_ip_stub.v
// Design      : jls_encoder_ip
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7a200tfbg676-2
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* CHECK_LICENSE_TYPE = "jls_encoder_ip,jls_encoder,{}" *) (* DowngradeIPIdentifiedWarnings = "yes" *) (* IP_DEFINITION_SOURCE = "package_project" *) 
(* X_CORE_INFO = "jls_encoder,Vivado 2024.2" *) 
module jls_encoder_ip(rstn, clk, is_last_encoder, cur_enc, i_sof, i_w, i_h, 
  i_e, i_x, o_e, o_last, o_data, my_last)
/* synthesis syn_black_box black_box_pad_pin="rstn,is_last_encoder[2:0],cur_enc[1:0],i_sof,i_w[13:0],i_h[13:0],i_e,i_x[7:0],o_e,o_last,o_data[15:0],my_last" */
/* synthesis syn_force_seq_prim="clk" */;
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rstn RST" *) (* X_INTERFACE_MODE = "slave" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME rstn, POLARITY ACTIVE_LOW, INSERT_VIP 0" *) input rstn;
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *) (* X_INTERFACE_MODE = "slave" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME clk, ASSOCIATED_RESET rstn, FREQ_HZ 100000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, INSERT_VIP 0" *) input clk /* synthesis syn_isclock = 1 */;
  input [2:0]is_last_encoder;
  input [1:0]cur_enc;
  input i_sof;
  input [13:0]i_w;
  input [13:0]i_h;
  input i_e;
  input [7:0]i_x;
  output o_e;
  output o_last;
  output [15:0]o_data;
  output my_last;
endmodule
