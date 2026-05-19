`timescale 1ps/1ps
//--------------------------------------------------------------------------------------------------------
// Module  : top_jls_vertical
// Type    : synthesizable top
// Function: JPEG-LS Parallel Image Stream Compressor using vertical Splitting 
//--------------------------------------------------------------------------------------------------------
module top_jls_vertical #(
    parameter integer N_E = 3,   // Number of encoders
    parameter integer L   = 64,
    parameter [2:0]   nr  = 3'd0
)(
    input  wire        rstn,
    output  wire        clk,
    input  wire        clk_in1_p,
    input  wire        clk_in1_n,

    // AXI-Stream Input
    input  wire        i_sof,
    output  wire        i_e,
    output  wire [7:0]  i_x,
    output  wire [13:0] i_w,
    output  wire [13:0] i_h,
    output wire sys_rdy,

    // AXI-Stream Output (Separate per encoder)
    output wire        o_e0,
    output wire        o_e1,
    output wire        o_e2,
    output wire        o_last0,
    output wire        o_last1,
    output wire        o_last2,
    output wire [15:0] o_data0,
    output wire [15:0] o_data1,
    output wire [15:0] o_data2
);
wire  [N_E-1:0]  o_sof_st;
    // Internal signals
    wire [N_E-1:0]     s_e;
    wire [N_E*8-1:0]   s_x;
    wire [N_E*14-1:0]  s_w;
    wire [N_E*14-1:0]  s_h;
    wire [N_E-1:0]     o_last_enc;
    wire [$clog2(N_E)-1:0] encoder_sel;
    wire [N_E-1:0]     e_e;
    wire [N_E-1:0]     e_last;
    wire [N_E*16-1:0]  e_data;
    wire [13:0]        x_cnt, y_cnt;
    wire               rd_clk;

    // =================================================================
    // Clock wizard
    // =================================================================
    wire locked;
    clk_wiz_0 clk_wiz_0 (
        .clk_out1(clk),       // 100 MHz
        .clk_out2(rd_clk), // 33.33 MHz
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
            i_sof_r <= sof_sync1;  // latch 1 clock
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
//    wire sys_rdy;

    fifo_reset_bram_async u_fifo_reset (
        .clk_rd(rd_clk),
        .rstn_ext(rstn),
        .locked(locked),
        .fifo_rst(fifo_rst),
        .wr_busy(wr_busy),
        .rd_busy(rd_busy),
        .sys_rdy(sys_rdy)
    );

      // Image Generator
    // ---------------------------------------------------------
    image_generator #(
        .DATA_WIDTH(8)
    ) u_image_generator (
        .clk           (clk),
        .rstn          (sys_rdy),
        .i_sof         (i_sof_in),
        .fifo_overflow (fifo_full),
        .pixel_out     (i_x),
        .pixel_valid   (i_e),
        .i_w           (i_w),
        .i_h           (i_h),
        .i_sof_st      (o_sof_st)
    ); 
    //---------------------------------------------
// Splitter Vertical Instantiation
//---------------------------------------------
splitter_block #(
    .N_H(3),    // Number of encoders
    .N_V(3),
    .N_E(3)      // Slice height per encoder (optional)
) u_splitter_block (
    .sys_rdy     (rstn),       // System ready signal
    .clk         (clk),           // System clock
    .i_sof       (i_sof),         // Start-of-frame pulse
    .i_e         (i_e),           // Pixel enable
    .i_x         (i_x),           // Pixel data [7:0]
    .i_w         (i_w),           // Image width (1146 for example)
    .i_h         (i_h),           // Image height (609 for example)

    // Outputs to encoder modules
 //   .o_sof       (o_sof),         // Start-of-frame pulse per encoder
    .i_sof_st    (o_sof_st),      // 3000-cycle stretched strobe per encoder
    .o_e         (s_e),           // Pixel enable per encoder
    .o_x         (s_x),           // Pixel data per encoder
    .o_w         (s_w),           // Width per encoder
    .o_h         (s_h),           // Height per encoder

    // Status / control outputs
    .encoder_sel_d (encoder_sel),   // Current encoder index
    .x_cnt_d       (x_cnt),         // Horizontal pixel counter
    .y_cnt_d       (y_cnt)          // Vertical line counter
);

    // =================================================================
    // Input FIFO wrapper
    // =================================================================
    wire [8*N_E-1:0]  din_flat = s_x;
    wire [8*N_E-1:0]  dout_flat;
    wire [N_E-1:0]    valid, fifo_rd_en, empty, overflow, fifo_wr_en, almost_empty;
    wire [N_E-1:0]    fifo_full;
    wire [N_E*18-1:0] fifo_count_flat;

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
   // wire [N_E*18-1:0] read_count_flat;


wire [N_E-1:0] i_sof_st_enc;
wire [32*N_E-1:0] read_count_flat;

fifo_read_control #(
    .NUM_ENCODERS(N_E)
) u_fifo_read_control (
    .rd_clk(rd_clk),             // 50 MHz read clock
    .sys_rdy(sys_rdy),           // system ready
    .i_w_r(s_w),                   // image width
    .i_h_r(s_h),                   // image height
    .fifo_empty(empty),     // from FIFO wrapper
    .fifo_valid(valid),     // from FIFO wrapper
    .rd_en(fifo_rd_en),          // output to encoder read enable
    .read_count_flat(read_count_flat), 
    .i_sof_st_enc(i_sof_st_enc)  // block-level SOF for encoder
);

    // =================================================================
    // Encoder wrapper
    // =================================================================
    wire [N_E-1:0] my_last;
    wire [3:0]     last_enc_id;

   encoder_wrapper #(
    .N_E(N_E),
    .nr(nr),
    .L(L)
) u_encoder_wrapper (
    .rd_clk(rd_clk),           // 50 MHz read clock
    .sys_rdy(sys_rdy),         // system ready
    .i_w(s_w),                 // image width
    .i_h(s_h),                 // image height
    .rd_en_gated(valid),  // FIFO read enable (per encoder)
    .enc_i_sofx(i_sof_st_enc),    // block-level SOF pulse
    .dout(dout_flat),          // pixel data from FIFO
    .o_last(o_last_enc),       // end of encoder signal
    .my_last(my_last),         // ?
    .e_e(e_e),                 // output valid
    .e_data(e_data),           // encoded data
    .last_enc_id(last_enc_id)  // which encoder finished
);


    // =================================================================
    // Output FIFO wrapper (Separate outputs)
    // =================================================================
    fifo_wrapper_output #(
        .N_E(N_E)
      //  .L(L)
    ) u_fifo_wrapper_output (
        .rst         (fifo_rst),
        .wr_clk      (rd_clk),
        .rd_clk      (clk),
        .din_flat    (e_data),
        .wr_en       (e_e),
    //    .my_last     (my_last),
        .o_last_enc  (o_last_enc),
        .fifo_dout_flat   ({o_data2, o_data1, o_data0}),
        .dout_valid  ({o_e2, o_e1, o_e0}),
        .dout_last   ({o_last2, o_last1, o_last0}),
        .wr_rst_busy (wr_rst_busy_output),
        .rd_rst_busy (rd_rst_busy_output)
    );


endmodule
