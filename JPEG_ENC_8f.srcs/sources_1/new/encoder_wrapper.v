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
    input  wire [N_E*14-1:0] i_w,          // per-encoder width (packed)
    input  wire [13:0]       i_h,          // chunk height (same for all)
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

    // Per-encoder width (packed bus from splitter)
    reg [N_E*14-1:0] s_w_bus;
    reg [13:0] s_h;
    wire dims_valid = (s_w_bus[13:0] != 0);
    always @(posedge rd_clk) begin
        if (!sys_rdy) begin
            s_w_bus <= 0;
            s_h <= 0;
        end else begin
            s_w_bus <= i_w;
            s_h <= i_h;
        end
    end

    assign last_enc_id = N_E - 1;

    // Track which group gets SOF (alternating: group A=enc0-2, group B=enc3-5)
    reg [2:0] sof_count;
    reg enc_i_sof_prev;
    wire sof_rising = enc_i_sofx && !enc_i_sof_prev;
    always @(posedge rd_clk) begin
        if (!sys_rdy) begin
            sof_count <= 0;
            enc_i_sof_prev <= 0;
        end else begin
            enc_i_sof_prev <= enc_i_sofx;
            if (sof_rising)
                sof_count <= sof_count + 1;
        end
    end
    // sof_count: 1=swath0(groupA), 2=swath1(groupB), 3=swath2(groupA), 4=swath3(groupB)
    wire group_a_active = (sof_count == 1) || (sof_count == 3);
    wire group_b_active = (sof_count == 2) || (sof_count == 4);

    genvar g_enc;
    generate
        for (g_enc = 0; g_enc < N_E; g_enc = g_enc + 1) begin : ENC_INST
            wire [ENC_ID_WIDTH-1:0] curr_enc_sig = 0;
            wire enc_in_group_a = (g_enc < NUM_COLS);
            wire enc_sof = enc_i_sofx && dims_valid && (enc_in_group_a ? group_a_active : group_b_active);

            jls_encoder #(
                .NEAR(nr),
                .N_E(1)
            ) u_encoder (
                .rstn     (sys_rdy),
                .clk      (rd_clk),
                .i_sof    (enc_sof),
                .i_w      (s_w_bus[g_enc*14 +: 14]),
                .i_h      (s_h),
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
