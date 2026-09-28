`timescale 1ns/1ps
module encoder_wrapper #(
    parameter integer N_E      = 2,
    parameter integer N_H      = 2,   // horizontal blocks (cols)
    parameter integer N_V      = 2,   // vertical swaths
    parameter integer nr       = 0,
    parameter integer L        = 64,
    parameter integer LB_DEPTH = 1024,// line-buffer depth = max per-lane strip width (i_w/N_H);
                                      // horizontal (N_H=1) needs LB_DEPTH >= image width
    parameter integer BPP      = 8,   // sample precision (8..16)
    parameter integer PW       = (BPP > 8) ? 16 : 8,   // pixel lane width in dout
    parameter integer OW       = (BPP > 8) ? 32 : 16   // compressed word width per lane
)(
    input  wire              rd_clk,
    input  wire              sys_rdy,
    input  wire [15:0]       i_w,
    input  wire [13:0]       i_h,
    input  wire [N_E-1:0]    rd_en_gated,
    input  wire [N_E-1:0]    enc_i_sofx,   // per-encoder SOF from fifo_read_control
    input  wire [N_E*PW-1:0] dout,
    output wire [N_E-1:0]    o_last,
    output wire [N_E-1:0]    my_last,
    output wire [N_E-1:0]    e_e,
    output wire [N_E*OW-1:0] e_data,
    output wire [31:0]       last_enc_id
);

    localparam ENC_ID_WIDTH = ($clog2(N_E) > 0) ? $clog2(N_E) : 1;

    // Per-column width — UNIFORM floor for every lane. The wide lockstep splitter
    // advances one shared (xs,ys) counter over stripW=i_w/N_H, swathH=i_h/N_V and
    // delivers exactly stripW*swathH pixels to EVERY lane, so all lanes must use the
    // same floor count (i_w must be divisible by N_H — enforced by make_strided_hex.py
    // and documented as a hard requirement). A last-lane remainder would mismatch the
    // splitter's delivery and hang the read FSM. (Divisible => floor == exact.)
    reg [15:0] col_w [0:N_H-1];
    integer ci;
    always @(*) begin
        for (ci = 0; ci < N_H; ci = ci + 1)
            col_w[ci] = i_w / N_H;
    end

    // Per-swath (row) height — uniform floor, same lockstep rationale as col_w.
    wire [13:0] swath_h = i_h[13:0] / N_V;
    reg [13:0] row_h [0:N_V-1];
    integer ri;
    always @(*) begin
        for (ri = 0; ri < N_V; ri = ri + 1)
            row_h[ri] = i_h[13:0] / N_V;
    end

    assign last_enc_id = N_E - 1;

    genvar g_enc;
    generate
        for (g_enc = 0; g_enc < N_E; g_enc = g_enc + 1) begin : ENC_INST
            wire [ENC_ID_WIDTH-1:0] curr_enc_sig = 0;

            // Canonical config (lossless, LB_DEPTH=1024) uses the packaged IP core
            // (user.org:user:jls_encoder:1.0, fixed NEAR=0/N_E=1/LB_DEPTH=1024). Wide
            // builds (LB_DEPTH>1024, e.g. full-width horizontal) keep the parameterized
            // RTL, since a Vivado IP instance has a fixed LB_DEPTH. BPP>8 always uses
            // the parameterized RTL (the packaged IP core is the 8-bit build).
            if (LB_DEPTH == 1024 && nr == 0 && BPP == 8) begin : g_ip
                jls_encoder_ip u_encoder (
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
            end else begin : g_rtl
                jls_encoder #(
                    .NEAR(nr),
                    .N_E(1),
                    .LB_DEPTH(LB_DEPTH),
                    .BPP(BPP)
                ) u_encoder (
                    .rstn     (sys_rdy),
                    .clk      (rd_clk),
                    .i_sof    (enc_i_sofx[g_enc]),
                    .i_w      (col_w[g_enc % N_H]),
                    .i_h      (row_h[g_enc / N_H]),
                    .i_e      (rd_en_gated[g_enc]),
                    .i_x      (dout[g_enc*PW +: BPP]),
                    .my_last  (my_last[g_enc]),
                    .o_e      (e_e[g_enc]),
                    .o_data   (e_data[g_enc*OW +: OW]),
                    .o_last   (o_last[g_enc]),
                    .is_last_encoder(g_enc == N_E-1),
                    .cur_enc  (curr_enc_sig)
                );
            end
        end
    endgenerate

endmodule
