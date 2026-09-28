`timescale 1ns/1ps
// Wide 16-lane bitstream top: on-chip 128-bit ROM source -> jls_encoder_axis (16
// lanes) -> on-chip sink. Only real I/O is the diff clock, reset, and status pins
// (done + checksum), so the design is self-contained and synthesis-prunable-proof.
module jls_demo_top #(
    parameter integer N_E   = 16,
    parameter integer N_H   = 16,
    parameter integer N_V   = 1,
    parameter integer IMG_W = 256,
    parameter integer IMG_H = 256,
    parameter integer BPP   = 8        // sample precision (8..16); BPP>8 -> 16-bit lanes, 32-bit words
)(
    input  wire        rstn,
    input  wire        clk_in1_p,
    input  wire        clk_in1_n,
    output wire        clk,
    output wire        done,
    output wire [30:0] status     // checksum[30:0] (observable; prevents pruning)
);
    wire        sys_rdy;
    wire [15:0] src_w;  wire [13:0] src_h;  wire src_sof;
    localparam integer PW = (BPP > 8) ? 16 : 8;
    localparam integer OW = (BPP > 8) ? 32 : 16;
    wire [N_E*PW-1:0] src_tdata;  wire src_tvalid, src_tready, src_tlast;
    wire [N_E*OW-1:0] m_tdata;    wire [N_E-1:0] m_tvalid, m_tready, m_tlast;
    wire [31:0] total_words, checksum;

    axis_image_source #(.N_E(N_E), .IMG_W(IMG_W), .IMG_H(IMG_H), .PW(PW)) u_src (
        .clk(clk), .rstn(sys_rdy), .i_w(src_w), .i_h(src_h), .i_sof(src_sof),
        .s_axis_tdata(src_tdata), .s_axis_tvalid(src_tvalid),
        .s_axis_tready(src_tready), .s_axis_tlast(src_tlast));

    jls_encoder_axis #(.N_E(N_E), .N_H(N_H), .N_V(N_V), .BPP(BPP)) u_ip (
        .rstn(rstn), .clk(clk), .clk_in1_p(clk_in1_p), .clk_in1_n(clk_in1_n),
        .sys_rdy(sys_rdy), .i_sof(src_sof), .i_w(src_w), .i_h(src_h),
        .s_axis_tdata(src_tdata), .s_axis_tvalid(src_tvalid),
        .s_axis_tready(src_tready), .s_axis_tlast(src_tlast),
        .m_axis_tdata(m_tdata), .m_axis_tvalid(m_tvalid),
        .m_axis_tready(m_tready), .m_axis_tlast(m_tlast));

    axis_sink #(.N_E(N_E), .DW(OW)) u_sink (
        .clk(clk), .rstn(sys_rdy), .m_axis_tdata(m_tdata), .m_axis_tvalid(m_tvalid),
        .m_axis_tready(m_tready), .m_axis_tlast(m_tlast),
        .total_words(total_words), .checksum(checksum), .done(done));

    assign status = checksum[30:0];
endmodule
