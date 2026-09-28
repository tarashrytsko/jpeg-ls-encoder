`timescale 1ns/1ps
// AXIS slave -> splitter adapter. Reproduces image_generator's control FSM exactly
// (S_IDLE -> S_SOF stretch -> S_PIXEL), but sources pixels from an AXI4-Stream slave
// instead of $fgetc, and takes image dimensions from sideband ports. Lossless only.
module axis_pixel_in #(
    parameter integer N_E         = 2,
    parameter integer SOF_STRETCH = 3000,
    parameter integer PW          = 8     // pixel lane width (8, or 16 for BPP>8)
)(
    input  wire                  clk,            // wr_clk domain
    input  wire                  rstn,           // = sys_rdy
    input  wire                  i_sof,          // sideband start-of-frame pulse
    input  wire [15:0]           i_w_in,         // sideband image width
    input  wire [13:0]           i_h_in,         // sideband image height
    input  wire [N_E-1:0]        fifo_overflow,  // backpressure (= fifo_full masked)

    // AXI4-Stream slave (pixels in)
    input  wire [N_E*PW-1:0]     s_axis_tdata,
    input  wire                  s_axis_tvalid,
    output wire                  s_axis_tready,
    input  wire                  s_axis_tlast,   // accepted; framing driven by i_w/i_h

    // to splitter_block (same signals image_generator produced)
    output reg  [N_E*PW-1:0]     pixel_out,
    output reg                   pixel_valid,
    output reg  [15:0]           i_w,
    output reg  [13:0]           i_h,
    output reg  [N_E-1:0]        i_sof_st
);
    localparam S_IDLE = 2'd0, S_SOF = 2'd1, S_PIXEL = 2'd2, S_DONE = 2'd3;

    reg  [1:0]  state;
    reg  [31:0] sof_cnt;
    reg  [31:0] pix_cnt;
    reg  [31:0] total_pixels;
    wire        backpressure = |fifo_overflow;

    // Accept a pixel only while actively streaming and not backpressured.
    assign s_axis_tready = (state == S_PIXEL) && (pix_cnt < total_pixels) && !backpressure;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= S_IDLE; sof_cnt <= 0; pix_cnt <= 0; total_pixels <= 0;
            pixel_out <= 0; pixel_valid <= 0; i_w <= 0; i_h <= 0; i_sof_st <= 0;
        end else begin
            pixel_valid <= 1'b0;          // default low (registered), like image_generator
            i_sof_st    <= {N_E{1'b0}};
            case (state)
                S_IDLE: if (i_sof) begin
                    i_w          <= i_w_in;
                    i_h          <= i_h_in;
                    total_pixels <= i_w_in * i_h_in;
                    sof_cnt      <= 0;
                    pix_cnt      <= 0;
                    state        <= S_SOF;
                end
                S_SOF: begin
                    i_sof_st <= {N_E{1'b1}};
                    if (sof_cnt < SOF_STRETCH - 1) sof_cnt <= sof_cnt + 1;
                    else begin sof_cnt <= 0; state <= S_PIXEL; end
                end
                S_PIXEL: begin
                    if (pix_cnt < total_pixels) begin
                        if (s_axis_tvalid && s_axis_tready) begin
                            pixel_out   <= s_axis_tdata;
                            pixel_valid <= 1'b1;
                            pix_cnt     <= pix_cnt + N_E;
                        end
                    end else begin
                        state <= S_DONE;
                    end
                end
                S_DONE: ;
            endcase
        end
    end
endmodule
