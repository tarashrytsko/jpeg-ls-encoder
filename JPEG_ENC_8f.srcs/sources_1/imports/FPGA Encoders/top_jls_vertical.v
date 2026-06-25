`timescale 1ps/1ps
module top_jls_vertical #(
    parameter integer N_E = 2,
    parameter integer N_H = 2,   // horizontal blocks (columns). N_H=1 => horizontal split
    parameter integer N_V = 2,   // vertical blocks (rows/swaths). N_V=1 => vertical split
    parameter integer L   = 64,
    parameter [2:0]   nr  = 3'd0
)(
    input  wire        rstn,
    output wire        clk,
    input  wire        clk_in1_p,
    input  wire        clk_in1_n,

    input  wire        i_sof,
    output wire        i_e,
    output wire [7:0]  i_x,
    output wire [15:0] i_w,
    output wire [13:0] i_h,
    output wire sys_rdy,

    output wire [N_E-1:0]    o_e,
    output wire [N_E-1:0]    o_last,
    output wire [N_E*16-1:0] o_data
);

wire [N_E-1:0] o_sof_st;
    wire [N_E-1:0]     s_e;
    wire [N_E*8-1:0]   s_x;
    wire [N_E*16-1:0]  s_w;
    wire [N_E*14-1:0]  s_h;
    wire [N_E-1:0]     o_last_enc;
    wire [$clog2(N_E)-1:0] encoder_sel;
    wire [$clog2(N_E)-1:0] encoder_sel_comb;
    wire [N_E-1:0]     e_e;
    wire               fifo_full_cur;
    wire [N_E-1:0]     fifo_overflow_masked;
    wire [N_E*16-1:0]  e_data;
    wire [15:0]        x_cnt, y_cnt;
    wire               rd_clk;

    // =================================================================
    // Clock wizard
    // =================================================================
    wire locked;
    clk_wiz_0 clk_wiz_0 (
        .clk_out1(clk),       // 100 MHz
        .clk_out2(rd_clk),    // 33.33 MHz
        .reset(~rstn),
        .locked(locked),
        .clk_in1_p(clk_in1_p),
        .clk_in1_n(clk_in1_n)
    );

    // ---------------------------------------------------------
    // Synchronize i_sof pulse
    // ---------------------------------------------------------
    reg sof_sync0, sof_sync1;
    reg i_sof_r;
    wire i_sof_in;

    always @(posedge clk) begin
        if (!rstn) begin
            sof_sync0 <= 1'b0;
            sof_sync1 <= 1'b0;
            i_sof_r   <= 1'b0;
        end else begin
            sof_sync0 <= i_sof;
            sof_sync1 <= sof_sync0;
            i_sof_r <= sof_sync1;
        end
    end

    assign i_sof_in = i_sof_r;

    // =================================================================
    // FIFO reset logic
    // =================================================================
    wire fifo_rst;
    wire [N_E-1:0] wr_rst_busy_input, rd_rst_busy_input;
    wire [N_E-1:0] wr_rst_busy_output, rd_rst_busy_output;
    wire wr_busy = |(wr_rst_busy_input | wr_rst_busy_output);
    wire rd_busy = |(rd_rst_busy_input | rd_rst_busy_output);

    fifo_reset_bram_async u_fifo_reset (
        .clk_rd(rd_clk),
        .rstn_ext(rstn),
        .locked(locked),
        .fifo_rst(fifo_rst),
        .wr_busy(wr_busy),
        .rd_busy(rd_busy),
        .sys_rdy(sys_rdy)
    );

    // =================================================================
    // Image Generator
    // =================================================================
    image_generator #(
        .DATA_WIDTH(8),
        .NUM_ENCODERS(N_E)
    ) u_image_generator (
        .clk           (clk),
        .rstn          (sys_rdy),
        .i_sof         (i_sof_in),
        .fifo_overflow (fifo_overflow_masked),
        .pixel_out     (i_x),
        .pixel_valid   (i_e),
        .i_w           (i_w),
        .i_h           (i_h),
        .i_sof_st      (o_sof_st)
    );

    // =================================================================
    // Splitter (N_H columns x N_V rows). Block: N_H>1,N_V>1. Vertical: N_V=1. Horizontal: N_H=1.
    // =================================================================
    splitter_block #(
        .N_H(N_H),
        .N_V(N_V),
        .N_E(N_E)
    ) u_splitter_block (
        .sys_rdy     (rstn),
        .clk         (clk),
        .i_sof       (i_sof),
        .i_e         (i_e),
        .i_x         (i_x),
        .i_w         (i_w),
        .i_h         (i_h),
        .i_sof_st    (o_sof_st),
        .o_e         (s_e),
        .o_x         (s_x),
        .o_w         (s_w),
        .o_h         (s_h),
        .encoder_sel_d    (encoder_sel),
        .x_cnt_d          (x_cnt),
        .y_cnt_d          (y_cnt),
        .encoder_sel_comb (encoder_sel_comb)
    );

    // =================================================================
    // Input FIFO wrapper
    // =================================================================
    wire [8*N_E-1:0]  din_flat = s_x;
    wire [8*N_E-1:0]  dout_flat;
    wire [N_E-1:0]    valid, fifo_rd_en, empty, overflow, fifo_wr_en, almost_empty;
    wire [N_E-1:0]    fifo_full;
    wire [N_E*18-1:0] fifo_count_flat;
    // Per-encoder backpressure: stall only when target encoder's FIFO is full
    assign fifo_full_cur = fifo_full[encoder_sel_comb];
    assign fifo_overflow_masked = {N_E{fifo_full_cur}};

    fifo_wrapper_input #(.N_E(N_E)) u_fifo_wrapper_input (
        .rst(fifo_rst),
        .wr_clk(clk),
        .rd_clk(rd_clk),
        .din_flat(din_flat),
        .wr_en(fifo_wr_en),
        .rd_en(fifo_rd_en),
        .dout_flat(dout_flat),
        .full(fifo_full),
        .overflow(overflow),
        .empty(empty),
        .almost_empty(almost_empty),
        .valid(valid),
        .wr_rst_busy(wr_rst_busy_input),
        .rd_rst_busy(rd_rst_busy_input),
        .fifo_count_flat(fifo_count_flat)
    );

    // =================================================================
    // FIFO write control
    // =================================================================
    wire [N_E*32-1:0] wr_count_flat;

    fifo_write_control #(.NUM_ENCODERS(N_E)) u_fifo_write_control (
        .wr_clk(clk),
        .rstn(~fifo_rst),
        .s_e(s_e),
        .fifo_full(fifo_full),
        .fifo_overflow(overflow),
        .x_cnt(x_cnt),
        .y_cnt(y_cnt),
        .total_lines(s_h),
        .image_width(s_w),
        .encoder_sel(encoder_sel),
        .wr_en(fifo_wr_en),
        .wr_count_flat(wr_count_flat),
        .frame_done()
    );

    // =================================================================
    // FIFO read control
    // =================================================================
    wire [N_E-1:0] i_sof_st_enc;
    wire [32*N_E-1:0] read_count_flat;

    fifo_read_control #(
        .NUM_ENCODERS(N_E),
        .N_H(N_H),
        .N_V(N_V)
    ) u_fifo_read_control (
        .rd_clk(rd_clk),
        .sys_rdy(sys_rdy),
        .i_w_r(s_w),
        .i_h_r(s_h),
        .fifo_empty(empty),
        .fifo_valid(valid),
        .rd_en(fifo_rd_en),
        .read_count_flat(read_count_flat),
        .i_sof_st_enc(i_sof_st_enc)
    );

    // =================================================================
    // Encoder wrapper
    // =================================================================
    wire [N_E-1:0] my_last;
    wire [31:0]    last_enc_id;

    encoder_wrapper #(
        .N_E(N_E),
        .N_H(N_H),
        .N_V(N_V),
        .nr(nr),
        .L(L)
    ) u_encoder_wrapper (
        .rd_clk(rd_clk),
        .sys_rdy(sys_rdy),
        .i_w(s_w),
        .i_h(s_h),
        .rd_en_gated(valid),
        .enc_i_sofx(i_sof_st_enc),
        .dout(dout_flat),
        .o_last(o_last_enc),
        .my_last(my_last),
        .e_e(e_e),
        .e_data(e_data),
        .last_enc_id(last_enc_id)
    );

    // =================================================================
    // Output FIFO wrapper
    // =================================================================
    fifo_wrapper_output #(
        .N_E(N_E)
    ) u_fifo_wrapper_output (
        .rst         (fifo_rst),
        .wr_clk      (rd_clk),
        .rd_clk      (clk),
        .din_flat    (e_data),
        .wr_en       (e_e),
        .o_last_enc  (o_last_enc),
        .fifo_dout_flat (o_data),
        .dout_valid  (o_e),
        .dout_last   (o_last),
        .wr_rst_busy (wr_rst_busy_output),
        .rd_rst_busy (rd_rst_busy_output)
    );

endmodule
