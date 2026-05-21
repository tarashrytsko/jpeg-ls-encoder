`timescale 1ps/1ps
// Streaming chunk-based pixel splitter.
// Accepts an infinite raster-order pixel stream (only image width needed).
// Routes pixels to N_E encoder FIFOs based on column position and swath index.
// Signals chunk_done when each CHUNK_H-line swath completes.
module splitter_block #(
    parameter integer N_H     = 3,      // horizontal columns
    parameter integer N_E     = 6,      // total encoders (2 groups of N_H)
    parameter integer CHUNK_H = 1250    // lines per swath
)(
    input  wire                          clk,
    input  wire                          rstn,

    // Pixel input (raster order)
    input  wire                          i_e,
    input  wire [7:0]                    i_x,
    input  wire [13:0]                   i_w,     // image width

    // SOF stretch interface (from image_generator)
    input  wire [N_E-1:0]                i_sof_st,

    // Per-encoder pixel output
    output reg  [N_E-1:0]                o_e,
    output reg  [N_E*8-1:0]              o_x,

    // Chunk boundary signal
    output reg  [N_E-1:0]                chunk_done,

    // Status outputs (for write control compatibility)
    output reg  [$clog2(N_E)-1:0]        encoder_sel_d,
    output reg  [13:0]                   x_cnt_d,
    output reg  [13:0]                   y_cnt_d,

    // Width/height broadcast (for downstream compatibility)
    output reg  [N_E*14-1:0]             o_w,
    output reg  [N_E*14-1:0]             o_h
);

    // -------------------------------------------------------
    // Position tracking
    // -------------------------------------------------------
    reg [13:0] x_cnt;       // column within current row (0 to i_w-1)
    reg [13:0] y_local;     // row within current chunk (0 to CHUNK_H-1)
    reg [3:0]  swath_idx;   // which swath we're in (0, 1, 2, ...)

    // SOF stretch detection
    reg [N_E-1:0] i_sof_st_d;
    wire stretch_done_falling = (i_sof_st_d != 0) && (i_sof_st == 0);
    reg frame_active;

    always @(posedge clk or negedge rstn) begin
        if (!rstn)
            i_sof_st_d <= 0;
        else
            i_sof_st_d <= i_sof_st;
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn)
            frame_active <= 0;
        else if (stretch_done_falling)
            frame_active <= 1;
    end

    // -------------------------------------------------------
    // Column width (derived from image width)
    // -------------------------------------------------------
    reg [13:0] chunk_w [0:N_H-1];
    integer ci;
    always @(*) begin
        for (ci = 0; ci < N_H-1; ci = ci + 1)
            chunk_w[ci] = i_w / N_H;
        chunk_w[N_H-1] = i_w - (i_w / N_H) * (N_H - 1);
    end

    // Column boundaries
    reg [13:0] col_start [0:N_H-1];
    reg [13:0] col_end   [0:N_H-1];
    always @(*) begin
        col_start[0] = 0;
        for (ci = 1; ci < N_H; ci = ci + 1)
            col_start[ci] = col_start[ci-1] + chunk_w[ci-1];
        for (ci = 0; ci < N_H; ci = ci + 1)
            col_end[ci] = col_start[ci] + chunk_w[ci] - 1;
    end

    // -------------------------------------------------------
    // Determine which column current pixel belongs to
    // -------------------------------------------------------
    reg [$clog2(N_H)-1:0] col_idx;
    always @(*) begin
        col_idx = 0;
        for (ci = 0; ci < N_H; ci = ci + 1)
            if (x_cnt >= col_start[ci] && x_cnt <= col_end[ci])
                col_idx = ci[$clog2(N_H)-1:0];
    end

    // -------------------------------------------------------
    // Encoder select: group A (enc 0,1,2) for even swaths, group B (enc 3,4,5) for odd
    // -------------------------------------------------------
    wire [$clog2(N_E)-1:0] encoder_sel = (swath_idx[0] == 0) ?
                                          col_idx :
                                          (N_H + col_idx);

    // -------------------------------------------------------
    // Pixel counter FSM
    // -------------------------------------------------------
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            x_cnt     <= 0;
            y_local   <= 0;
            swath_idx <= 0;
        end else if (i_e && frame_active) begin
            if (x_cnt == i_w - 1) begin
                x_cnt <= 0;
                if (y_local == CHUNK_H - 1) begin
                    y_local   <= 0;
                    swath_idx <= swath_idx + 1;
                end else begin
                    y_local <= y_local + 1;
                end
            end else begin
                x_cnt <= x_cnt + 1;
            end
        end
    end

    // -------------------------------------------------------
    // Output routing
    // -------------------------------------------------------
    integer k;

    // Always broadcast dimensions (combinational, not gated by i_e)
    always @(*) begin
        for (k = 0; k < N_E; k = k + 1) begin
            o_w[k*14 +: 14] = chunk_w[k % N_H];
            o_h[k*14 +: 14] = CHUNK_H;
        end
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            o_e        <= 0;
            o_x        <= 0;
            chunk_done <= 0;
        end else begin
            o_e        <= 0;
            o_x        <= 0;
            chunk_done <= 0;

            if (i_e && frame_active) begin
                o_e[encoder_sel]          <= 1'b1;
                o_x[encoder_sel*8 +: 8]   <= i_x;


                // Signal chunk_done at last pixel of each swath
                if (x_cnt == i_w - 1 && y_local == CHUNK_H - 1)
                    chunk_done <= (swath_idx[0] == 0) ?
                                  {{N_H{1'b0}}, {N_H{1'b1}}} :  // group A done (enc 0,1,2)
                                  {{N_H{1'b1}}, {N_H{1'b0}}};   // group B done (enc 3,4,5)
            end
        end
    end

    // -------------------------------------------------------
    // Delayed status outputs
    // -------------------------------------------------------
    always @(posedge clk) begin
        x_cnt_d       <= x_cnt;
        y_cnt_d       <= y_local;
        encoder_sel_d <= encoder_sel;
    end

endmodule
