`timescale 1ns/1ps
module encoder_wrapper #(
    parameter integer N_E = 3,   // Number of encoders
    parameter integer nr  = 0,   // NEAR parameter for JPEG-LS
    parameter integer L   = 64   // Slice height per encoder
)(
    input  wire              rd_clk,       // 10MHz
    input  wire              sys_rdy,      // ready signal
    input  wire [13:0]       i_w,          // bytes per line
    input  wire [13:0]       i_h,          // total lines
    input  wire [N_E-1:0]    rd_en_gated,  // input enable per encoder
    input  wire              enc_i_sofx,   // start-of-frame
    input  wire [N_E*8-1:0]  dout,         // pixel input per encoder
    output wire [N_E-1:0]    o_last,
    output wire [N_E-1:0]    my_last,      // per encoder slice done
    output wire [N_E-1:0]    e_e,
    output wire [N_E*16-1:0] e_data,
    output wire [31:0]       last_enc_id
);

    localparam ENC_ID_WIDTH = ($clog2(N_E) > 0) ? $clog2(N_E) : 1;

    reg [13:0] s_w, s_h;
    reg [N_E-1:0] rd_en_gatedx;
    always @(posedge rd_clk) begin
        if (!sys_rdy) begin
            s_w <= 0;
            s_h <= 0;
        end else if (s_w == 0 && s_h == 0) begin
            s_w <= i_w;
            s_h <= i_h;
        end
    end

    always @(posedge rd_clk) begin
        if (!sys_rdy)
            rd_en_gatedx <= 0;
        else
            rd_en_gatedx <= rd_en_gated;
    end

    wire [31:0] total_slices = s_h / N_E;
    wire [3:0]  last_encoder_id = N_E-1;
    wire [13:0] remaining_lines_last_encoder = s_h - (total_slices - 1) * L;
    assign last_enc_id = last_encoder_id;

    reg [15:0] slice_index [0:N_E-1];
    reg [3:0]  slice_global;
    integer i;
    always @(posedge rd_clk) begin
        if (!sys_rdy) begin
            for (i = 0; i < N_E; i = i + 1)
                slice_index[i] <= 0;
            slice_global <= 0;
        end else begin
            for (i = 0; i < N_E; i = i + 1) begin
                if (my_last[i]) begin
                    slice_index[i] <= slice_index[i] + 1;
                    slice_global <= slice_global + 1;
                end
            end
        end
    end

    reg [13:0] full_slices_for_encoder [0:N_E-1];
    always @(*) begin
        for (i = 0; i < N_E; i = i + 1) begin
            full_slices_for_encoder[i] = total_slices / N_E;
            if (i < (total_slices % N_E))
                full_slices_for_encoder[i] = full_slices_for_encoder[i] + 1'b1;
        end
    end

    reg [13:0] total_lines_for_encoder [0:N_E-1];
    always @(*) begin
        for (i = 0; i < N_E; i = i + 1) begin
            if (i == last_encoder_id)
                total_lines_for_encoder[i] = (full_slices_for_encoder[i]-1)*L + remaining_lines_last_encoder;
            else
                total_lines_for_encoder[i] = full_slices_for_encoder[i]*L;
        end
    end

    reg enc_i_sof;
    always @(posedge rd_clk) begin
        if (!sys_rdy)
            enc_i_sof <= 0;
        else
            enc_i_sof <= enc_i_sofx;
    end

    genvar g_enc;
generate
    for (g_enc = 0; g_enc < N_E; g_enc = g_enc + 1) begin : ENC_INST
        wire [ENC_ID_WIDTH-1:0] curr_enc_sig = g_enc;

        jls_encoder #(
            .NEAR(nr),
            .N_E(N_E)
        ) u_encoder (
            .rstn     (sys_rdy),
            .clk      (rd_clk),
            .i_sof    (enc_i_sofx),
            .i_w      (s_w),
            .i_h      (s_h),
            .i_e      (rd_en_gated[g_enc]),
            .i_x      (dout[g_enc*8 +: 8]),
            .my_last  (my_last[g_enc]),
            .o_e      (e_e[g_enc]),
            .o_data   (e_data[g_enc*16 +: 16]),
            .o_last   (o_last[g_enc]),
            .is_last_encoder(g_enc == N_E-1), // parameter inside same encoder
            .cur_enc  (curr_enc_sig)
        );
    end
endgenerate


endmodule
