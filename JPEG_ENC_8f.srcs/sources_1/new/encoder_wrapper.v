`timescale 1ns/1ps
module encoder_wrapper #(
    parameter integer N_E = 6,
    parameter integer NUM_COLS = 3,
    parameter integer NUM_SWATHS = 4,
    parameter integer nr  = 0,
    parameter integer L   = 64
)(
    input  wire              rd_clk,
    input  wire              sys_rdy,
    input  wire [13:0]       i_w,          // full image width
    input  wire [13:0]       i_h,          // full image height
    input  wire [N_E-1:0]    rd_en_gated,
    input  wire              enc_i_sofx,
    input  wire [N_E*8-1:0]  dout,
    output wire [N_E-1:0]    o_last,
    output wire [N_E-1:0]    my_last,
    output wire [N_E-1:0]    e_e,
    output wire [N_E*16-1:0] e_data,
    output wire [31:0]       last_enc_id
);

    localparam ENC_ID_WIDTH = ($clog2(N_E) > 0) ? $clog2(N_E) : 1;

    reg [13:0] s_w, s_h;
    always @(posedge rd_clk) begin
        if (!sys_rdy) begin
            s_w <= 0;
            s_h <= 0;
        end else if (s_w == 0 && s_h == 0) begin
            s_w <= i_w;
            s_h <= i_h;
        end
    end

    // Per-column width
    reg [13:0] col_w [0:NUM_COLS-1];
    integer ci;
    always @(*) begin
        for (ci = 0; ci < NUM_COLS-1; ci = ci + 1)
            col_w[ci] = s_w / NUM_COLS;
        col_w[NUM_COLS-1] = s_w - (s_w / NUM_COLS) * (NUM_COLS - 1);
    end

    // Swath height
    wire [13:0] swath_h = s_h / NUM_SWATHS;

    assign last_enc_id = N_E - 1;

    genvar g_enc;
    generate
        for (g_enc = 0; g_enc < N_E; g_enc = g_enc + 1) begin : ENC_INST
            wire [ENC_ID_WIDTH-1:0] curr_enc_sig = 0;

            jls_encoder #(
                .NEAR(nr),
                .N_E(1)
            ) u_encoder (
                .rstn     (sys_rdy),
                .clk      (rd_clk),
                .i_sof    (enc_i_sofx),
                .i_w      (col_w[g_enc % NUM_COLS]),
                .i_h      (swath_h),
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
