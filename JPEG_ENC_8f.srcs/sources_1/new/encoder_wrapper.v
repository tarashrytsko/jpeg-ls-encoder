`timescale 1ns/1ps
module encoder_wrapper #(
    parameter integer N_E      = 2,
    parameter integer N_H      = 2,   // horizontal blocks (cols)
    parameter integer N_V      = 2,   // vertical swaths
    parameter integer nr       = 0,
    parameter integer L        = 64
)(
    input  wire              rd_clk,
    input  wire              sys_rdy,
    input  wire [15:0]       i_w,
    input  wire [13:0]       i_h,
    input  wire [N_E-1:0]    rd_en_gated,
    input  wire [N_E-1:0]    enc_i_sofx,   // per-encoder SOF from fifo_read_control
    input  wire [N_E*8-1:0]  dout,
    output wire [N_E-1:0]    o_last,
    output wire [N_E-1:0]    my_last,
    output wire [N_E-1:0]    e_e,
    output wire [N_E*16-1:0] e_data,
    output wire [31:0]       last_enc_id
);

    localparam ENC_ID_WIDTH = ($clog2(N_E) > 0) ? $clog2(N_E) : 1;

    // Per-column width (combinatorial from i_w directly)
    reg [15:0] col_w [0:N_H-1];
    integer ci;
    always @(*) begin
        for (ci = 0; ci < N_H-1; ci = ci + 1)
            col_w[ci] = i_w / N_H;
        col_w[N_H-1] = i_w - (i_w / N_H) * (N_H - 1);
    end

    // Per-swath (row) height — like col_w, the LAST swath takes the remainder so
    // images whose height isn't divisible by N_V still feed each encoder the exact
    // block it expects. (swath_h kept for debug/back-compat only.)
    wire [13:0] swath_h = i_h[13:0] / N_V;
    reg [13:0] row_h [0:N_V-1];
    integer ri;
    always @(*) begin
        for (ri = 0; ri < N_V-1; ri = ri + 1)
            row_h[ri] = i_h[13:0] / N_V;
        row_h[N_V-1] = i_h[13:0] - (i_h[13:0] / N_V) * (N_V - 1);
    end

    assign last_enc_id = N_E - 1;

    genvar g_enc;
    generate
        for (g_enc = 0; g_enc < N_E; g_enc = g_enc + 1) begin : ENC_INST
            wire [ENC_ID_WIDTH-1:0] curr_enc_sig = 0;

            jls_encoder #(
                .NEAR(nr),
                .N_E(1),
                .LB_DEPTH(1024)
            ) u_encoder (
                .rstn     (sys_rdy),
                .clk      (rd_clk),
                .i_sof    (enc_i_sofx[g_enc]),
                .i_w      (col_w[g_enc % N_H]),
                .i_h      (row_h[g_enc / N_H]),
                .i_e      (rd_en_gated[g_enc]),
                .i_x      (dout[g_enc*8 +: 8]),
                .my_last  (my_last[g_enc]),
                .o_e      (e_e[g_enc]),
                .o_data   (e_data[g_enc*16 +: 16]),
                .o_last   (o_last[g_enc]),
                .is_last_encoder(g_enc == N_E-1),
                .cur_enc  (curr_enc_sig)
            );
        end
    endgenerate

endmodule
