`timescale 1ns/1ps
module jls_demo_top #(
    parameter integer N_E   = 2,
    parameter integer N_H   = 2,
    parameter integer N_V   = 1,
    parameter integer IMG_W = 64,
    parameter integer IMG_H = 64
)(
    input  wire              rstn,
    input  wire              clk_in1_p,
    input  wire              clk_in1_n,
    output wire              clk,
    output wire [N_E-1:0]    o_e,
    output wire [N_E-1:0]    o_last,
    output wire [N_E*16-1:0] o_data
);
    wire        sys_rdy;
    wire [15:0] src_w;
    wire [13:0] src_h;
    wire        src_sof;
    wire [7:0]  src_tdata;
    wire        src_tvalid;
    wire        src_tready;
    wire        src_tlast;

    axis_image_source #(.IMG_W(IMG_W), .IMG_H(IMG_H), .HEXFILE("rom_image.hex")) u_src (
        .clk(clk), .rstn(sys_rdy),
        .i_w(src_w), .i_h(src_h), .i_sof(src_sof),
        .s_axis_tdata(src_tdata), .s_axis_tvalid(src_tvalid),
        .s_axis_tready(src_tready), .s_axis_tlast(src_tlast)
    );

    jls_encoder_axis #(.N_E(N_E), .N_H(N_H), .N_V(N_V)) u_ip (
        .rstn(rstn), .clk(clk), .clk_in1_p(clk_in1_p), .clk_in1_n(clk_in1_n),
        .sys_rdy(sys_rdy),
        .i_sof(src_sof), .i_w(src_w), .i_h(src_h),
        .s_axis_tdata(src_tdata), .s_axis_tvalid(src_tvalid),
        .s_axis_tready(src_tready), .s_axis_tlast(src_tlast),
        .m_axis_tdata(o_data), .m_axis_tvalid(o_e),
        .m_axis_tready({N_E{1'b1}}), .m_axis_tlast(o_last)
    );
endmodule
