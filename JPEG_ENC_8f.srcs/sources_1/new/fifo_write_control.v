`timescale 1ns/1ps
module fifo_write_control #(
    parameter integer NUM_ENCODERS = 6
)(
    input  wire                         wr_clk,
    input  wire                         rstn,
    input  wire [NUM_ENCODERS-1:0]      s_e,
    input  wire [NUM_ENCODERS-1:0]      fifo_full,
    input  wire [NUM_ENCODERS-1:0]      fifo_overflow,
    input  wire [15:0]                  x_cnt,
    input  wire [13:0]                  y_cnt,
    input  wire [13:0]                  total_lines,
    input  wire [15:0]                  image_width,
    input  wire [$clog2(NUM_ENCODERS)-1:0] encoder_sel,

    output reg  [NUM_ENCODERS-1:0]      wr_en,
    output reg  [32*NUM_ENCODERS-1:0]   wr_count_flat,
    output reg  [NUM_ENCODERS-1:0]      frame_done
);

    integer i;
    reg [31:0] wr_cnt [0:NUM_ENCODERS-1];

    // Write request: trust the splitter's s_e routing, gate on fifo_full
    reg [NUM_ENCODERS-1:0] write_req;
    always @(*) begin
        for (i = 0; i < NUM_ENCODERS; i = i + 1)
            write_req[i] = s_e[i] && !fifo_full[i] && !frame_done[i];
    end

    // Total pixels per encoder (computed from image dimensions)
    // Each encoder handles (image_width/3) * (total_lines/4) pixels total across 2 passes
    // But simpler: just count until s_e stops coming
    localparam [31:0] MAX_PIXELS = 32'hFFFFFFFF;

    always @(posedge wr_clk or negedge rstn) begin
        if (!rstn) begin
            for (i = 0; i < NUM_ENCODERS; i = i + 1) begin
                wr_en[i] <= 0;
                wr_cnt[i] <= 0;
                frame_done[i] <= 0;
            end
            wr_count_flat <= 0;
        end else begin
            for (i = 0; i < NUM_ENCODERS; i = i + 1) begin
                wr_en[i] <= write_req[i];
                if (write_req[i])
                    wr_cnt[i] <= wr_cnt[i] + 1;
            end
            for (i = 0; i < NUM_ENCODERS; i = i + 1)
                wr_count_flat[i*32 +: 32] <= wr_cnt[i];
        end
    end

endmodule
