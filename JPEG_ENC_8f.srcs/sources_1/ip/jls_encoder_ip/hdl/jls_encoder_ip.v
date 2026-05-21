`timescale 1ns/1ps
//------------------------------------------------------------------------------
// jls_encoder_ip — AXI-Stream wrapper for JPEG-LS encoder core
// Reusable IP for Vivado IP Catalog
//------------------------------------------------------------------------------
module jls_encoder_ip #(
    parameter integer NEAR = 0,   // 0=lossless, 1-7=near-lossless tolerance
    parameter integer N_E  = 1    // internal encoder geometry (1 for standalone)
)(
    // Clock & Reset
    input  wire        aclk,
    input  wire        aresetn,

    // Control
    input  wire        i_sof,     // start-of-frame pulse
    input  wire [13:0] i_w,       // image/block width
    input  wire [13:0] i_h,       // image/block height

    // AXI-Stream Slave — pixel input
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,

    // AXI-Stream Master — compressed output
    output wire [15:0] m_axis_tdata,
    output wire        m_axis_tvalid,
    output wire        m_axis_tlast,
    input  wire        m_axis_tready
);

    // Internal signals
    wire       enc_o_e;
    wire [15:0] enc_o_data;
    wire       enc_o_last;
    wire       enc_my_last;

    // Encoder is always ready to accept pixels (no backpressure from encoder itself)
    assign s_axis_tready = aresetn;

    // Map AXI-Stream to encoder ports
    wire enc_i_e = s_axis_tvalid & s_axis_tready;

    // Encoder core
    jls_encoder #(
        .NEAR (NEAR),
        .N_E  (N_E)
    ) u_core (
        .rstn           (aresetn),
        .clk            (aclk),
        .i_sof          (i_sof),
        .i_w            (i_w),
        .i_h            (i_h),
        .i_e            (enc_i_e),
        .i_x            (s_axis_tdata),
        .o_e            (enc_o_e),
        .o_data         (enc_o_data),
        .o_last         (enc_o_last),
        .my_last        (enc_my_last),
        .is_last_encoder(1'b1),
        .cur_enc        ({$clog2(N_E){1'b0}})
    );

    // AXI-Stream Master output
    // Simple: always output when encoder has data (no output FIFO in IP, user adds externally)
    assign m_axis_tdata  = enc_o_data;
    assign m_axis_tvalid = enc_o_e;
    assign m_axis_tlast  = enc_o_last;

endmodule
