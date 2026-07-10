`timescale 1ps/1ps

module splitter_block #(
    parameter integer N_H = 3,
    parameter integer N_V = 3,
    parameter integer N_E = 3
)(
    input  wire                 sys_rdy,
    input  wire                 clk,
    input  wire                 i_sof,       // SOF pulse
    input  wire [N_E-1:0]      i_sof_st,    // <<< FROM IMAGE GENERATOR
    input  wire                 i_e,
    input  wire [N_E*8-1:0]    i_x,
    input  wire [15:0]          i_w,
    input  wire [13:0]          i_h,

    output reg  [N_E-1:0]       o_last_enc,
    output reg  [N_E-1:0]       o_e,
    output reg  [N_E*8-1:0]     o_x,
    output reg  [N_E*16-1:0]    o_w,
    output reg  [N_E*14-1:0]    o_h,

    output reg [$clog2(N_E)-1:0] encoder_sel_d,
    output reg  [15:0]          x_cnt_d,
    output reg  [13:0]          y_cnt_d,
    output wire [$clog2(N_E)-1:0] encoder_sel_comb
);

    integer i, k;

    // per-lane sub-image is stripW x swathH (grid geometry).
    wire [15:0] stripW = i_w / N_H;
    wire [13:0] swathH = i_h / N_V;
    reg  [15:0] xs;   // intra-strip x: 0..stripW-1
    reg  [13:0] ys;   // intra-swath y: 0..swathH-1

    // -------------------------------------------------------
    // Detect falling edge of i_sof_st
    // -------------------------------------------------------
    reg [N_E-1:0] i_sof_st_d;
    always @(posedge clk or negedge sys_rdy) begin
        if(!sys_rdy)
            i_sof_st_d <= {N_E{1'b0}};
        else
            i_sof_st_d <= i_sof_st;
    end

    wire stretch_done_falling = (i_sof_st_d != 0) && (i_sof_st == 0);

    // -------------------------------------------------------
    // Latch to start frame streaming after stretch ends
    // -------------------------------------------------------
    reg frame_active_after_stretch;
    always @(posedge clk or negedge sys_rdy) begin
        if(!sys_rdy)
            frame_active_after_stretch <= 1'b0;
        else if(stretch_done_falling)
            frame_active_after_stretch <= 1'b1;
        else if(xs == stripW-1 && ys == swathH-1)
            frame_active_after_stretch <= 1'b0;
    end

    // Include stretch_done_falling combinatorially so the first pixel (arriving
    // on the same clock edge that clears i_sof_st) is not dropped.
    wire frame_active = frame_active_after_stretch | stretch_done_falling;

    // -------------------------------------------------------
    // Intra-strip pixel counters
    // -------------------------------------------------------
    always @(posedge clk) begin
        if (!sys_rdy || i_sof) begin
            xs <= 0; ys <= 0;
        end else if (i_e && frame_active) begin
            if (xs == stripW-1) begin
                xs <= 0;
                if (ys < swathH-1) ys <= ys + 1;
            end else xs <= xs + 1;
        end
    end

    assign encoder_sel_comb = {$clog2(N_E){1'b0}};

    // -------------------------------------------------------
    // Wide DATA routing — all lanes get a pixel every valid cycle
    // -------------------------------------------------------
    always @(posedge clk) begin
        if (!sys_rdy) begin
            o_e <= 0; o_x <= 0; o_w <= 0; o_h <= 0; o_last_enc <= 0;
        end else begin
            o_e <= 0; o_x <= 0; o_last_enc <= 0;
            for (k=0; k<N_E; k=k+1) begin
                o_w[k*16 +:16] <= i_w;   // full width; encoder_wrapper derives col_w = i_w/N_H
                o_h[k*14 +:14] <= i_h;
            end
            if (i_e && frame_active) begin
                for (k=0; k<N_E; k=k+1) begin
                    o_e[k] <= 1'b1;
                    o_x[k*8 +:8] <= i_x[k*8 +:8];     // lane k <- strip k's pixel
                    if (xs == stripW-1 && ys == swathH-1)
                        o_last_enc[k] <= 1'b1;
                end
            end
        end
    end

    always @(posedge clk) begin
        x_cnt_d <= {1'b0, xs}; y_cnt_d <= ys; encoder_sel_d <= {$clog2(N_E){1'b0}};
    end

endmodule
