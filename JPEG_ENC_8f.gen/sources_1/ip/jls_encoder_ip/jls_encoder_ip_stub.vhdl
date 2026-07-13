-- Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
-- Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2024.2 (win64) Build 5239630 Fri Nov 08 22:35:27 MST 2024
-- Date        : Mon Jul 13 22:03:16 2026
-- Host        : DESKTOP-PHB4K70 running 64-bit major release  (build 9200)
-- Command     : write_vhdl -force -mode synth_stub
--               d:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f/JPEG_ENC_8f.gen/sources_1/ip/jls_encoder_ip/jls_encoder_ip_stub.vhdl
-- Design      : jls_encoder_ip
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xc7a200tfbg676-2
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity jls_encoder_ip is
  Port ( 
    rstn : in STD_LOGIC;
    clk : in STD_LOGIC;
    is_last_encoder : in STD_LOGIC_VECTOR ( 2 downto 0 );
    cur_enc : in STD_LOGIC_VECTOR ( 1 downto 0 );
    i_sof : in STD_LOGIC;
    i_w : in STD_LOGIC_VECTOR ( 13 downto 0 );
    i_h : in STD_LOGIC_VECTOR ( 13 downto 0 );
    i_e : in STD_LOGIC;
    i_x : in STD_LOGIC_VECTOR ( 7 downto 0 );
    o_e : out STD_LOGIC;
    o_last : out STD_LOGIC;
    o_data : out STD_LOGIC_VECTOR ( 15 downto 0 );
    my_last : out STD_LOGIC
  );

  attribute CHECK_LICENSE_TYPE : string;
  attribute CHECK_LICENSE_TYPE of jls_encoder_ip : entity is "jls_encoder_ip,jls_encoder,{}";
  attribute DowngradeIPIdentifiedWarnings : string;
  attribute DowngradeIPIdentifiedWarnings of jls_encoder_ip : entity is "yes";
  attribute IP_DEFINITION_SOURCE : string;
  attribute IP_DEFINITION_SOURCE of jls_encoder_ip : entity is "package_project";
end jls_encoder_ip;

architecture stub of jls_encoder_ip is
  attribute syn_black_box : boolean;
  attribute black_box_pad_pin : string;
  attribute syn_black_box of stub : architecture is true;
  attribute black_box_pad_pin of stub : architecture is "rstn,clk,is_last_encoder[2:0],cur_enc[1:0],i_sof,i_w[13:0],i_h[13:0],i_e,i_x[7:0],o_e,o_last,o_data[15:0],my_last";
  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_INFO of rstn : signal is "xilinx.com:signal:reset:1.0 rstn RST";
  attribute X_INTERFACE_MODE : string;
  attribute X_INTERFACE_MODE of rstn : signal is "slave";
  attribute X_INTERFACE_PARAMETER : string;
  attribute X_INTERFACE_PARAMETER of rstn : signal is "XIL_INTERFACENAME rstn, POLARITY ACTIVE_LOW, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of clk : signal is "xilinx.com:signal:clock:1.0 clk CLK";
  attribute X_INTERFACE_MODE of clk : signal is "slave";
  attribute X_INTERFACE_PARAMETER of clk : signal is "XIL_INTERFACENAME clk, ASSOCIATED_RESET rstn, FREQ_HZ 100000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, INSERT_VIP 0";
  attribute X_CORE_INFO : string;
  attribute X_CORE_INFO of stub : architecture is "jls_encoder,Vivado 2024.2";
begin
end;
