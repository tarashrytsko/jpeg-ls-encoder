// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2026 Advanced Micro Devices, Inc. All Rights Reserved.
// -------------------------------------------------------------------------------

`timescale 1 ps / 1 ps

(* BLOCK_STUB = "true" *)
module jls_encoder_ip (
  rstn,
  clk,
  is_last_encoder,
  cur_enc,
  i_sof,
  i_w,
  i_h,
  i_e,
  i_x,
  o_e,
  o_last,
  o_data,
  my_last
);

  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rstn RST" *)
  (* X_INTERFACE_MODE = "slave rstn" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME rstn, POLARITY ACTIVE_LOW, INSERT_VIP 0" *)
  input rstn;
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
  (* X_INTERFACE_MODE = "slave clk" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME clk, ASSOCIATED_RESET rstn, FREQ_HZ 100000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, CLK_DOMAIN , ASSOCIATED_BUSIF , ASSOCIATED_PORT , INSERT_VIP 0" *)
  input clk;
  (* X_INTERFACE_IGNORE = "true" *)
  input [2:0]is_last_encoder;
  (* X_INTERFACE_IGNORE = "true" *)
  input [1:0]cur_enc;
  (* X_INTERFACE_IGNORE = "true" *)
  input i_sof;
  (* X_INTERFACE_IGNORE = "true" *)
  input [13:0]i_w;
  (* X_INTERFACE_IGNORE = "true" *)
  input [13:0]i_h;
  (* X_INTERFACE_IGNORE = "true" *)
  input i_e;
  (* X_INTERFACE_IGNORE = "true" *)
  input [7:0]i_x;
  (* X_INTERFACE_IGNORE = "true" *)
  output o_e;
  (* X_INTERFACE_IGNORE = "true" *)
  output o_last;
  (* X_INTERFACE_IGNORE = "true" *)
  output [15:0]o_data;
  (* X_INTERFACE_IGNORE = "true" *)
  output my_last;

  // stub module has no contents

endmodule
