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
    input  wire [7:0]           i_x,
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
reg [15:0] x_cnt, y_cnt;
wire [$clog2(N_E)-1:0] encoder_sel;

    // -------------------------------------------------------
    // BLOCK GEOMETRY
    // -------------------------------------------------------
    reg [15:0] blk_w_arr [0:N_H-1];
    reg [13:0] blk_h_arr [0:N_V-1];
    reg [15:0] blk_x_start [0:N_H-1];
    reg [15:0] blk_x_end   [0:N_H-1];
    reg [13:0] blk_y_start [0:N_V-1];
    reg [13:0] blk_y_end   [0:N_V-1];

    always @(*) begin
        for (i=0; i<N_H; i=i+1)
            blk_w_arr[i] = (i < N_H-1) ? (i_w / N_H) :
                                         (i_w - (i_w/N_H)*(N_H-1));

        for (i=0; i<N_V; i=i+1)
            blk_h_arr[i] = (i < N_V-1) ? (i_h / N_V) :
                                         (i_h - (i_h/N_V)*(N_V-1));

        blk_x_start[0] = 0;
        for (i=1; i<N_H; i=i+1)
            blk_x_start[i] = blk_x_start[i-1] + blk_w_arr[i-1];
        for (i=0; i<N_H; i=i+1)
            blk_x_end[i] = blk_x_start[i] + blk_w_arr[i] - 1;

        blk_y_start[0] = 0;
        for (i=1; i<N_V; i=i+1)
            blk_y_start[i] = blk_y_start[i-1] + blk_h_arr[i-1];
        for (i=0; i<N_V; i=i+1)
            blk_y_end[i] = blk_y_start[i] + blk_h_arr[i] - 1;
    end

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
        else if(x_cnt == i_w-1 && y_cnt == i_h-1)
            frame_active_after_stretch <= 1'b0;
    end

    // Include stretch_done_falling combinatorially so the first pixel (arriving
    // on the same clock edge that clears i_sof_st) is not dropped.
    wire frame_active = frame_active_after_stretch | stretch_done_falling;

    // -------------------------------------------------------
    // Pixel counters
    // -------------------------------------------------------
    always @(posedge clk) begin
        if (!sys_rdy || i_sof) begin
            x_cnt <= 0;
            y_cnt <= 0;
        end else if (i_e && frame_active) begin
            if (x_cnt == i_w-1) begin
                x_cnt <= 0;
                if (y_cnt < i_h-1)
                    y_cnt <= y_cnt + 1;
            end else
                x_cnt <= x_cnt + 1;
        end
    end

    // -------------------------------------------------------
    // BLOCK index → encoder select
    // -------------------------------------------------------
    function integer clog2;
        input integer value;
        integer v;
        begin
            v = value-1;
            for(clog2=0; v>0; clog2=clog2+1)
                v = v>>1;
        end
    endfunction

    reg [clog2(N_H)-1:0] x_block_idx;
    reg [clog2(N_V)-1:0] y_block_idx;
    reg [clog2(N_H*N_V)-1:0] block_idx;

    always @(*) begin
        x_block_idx = 0;
        y_block_idx = 0;

        for (i=0; i<N_H; i=i+1)
            if (x_cnt >= blk_x_start[i] && x_cnt <= blk_x_end[i])
                x_block_idx = i;

        for (i=0; i<N_V; i=i+1)
            if (y_cnt >= blk_y_start[i] && y_cnt <= blk_y_end[i])
                y_block_idx = i;

        block_idx = y_block_idx*N_H + x_block_idx;
    end

    assign encoder_sel = block_idx % N_E;
    assign encoder_sel_comb = encoder_sel;

    // -------------------------------------------------------
    // DATA routing
    // -------------------------------------------------------
    always @(posedge clk) begin
        if (!sys_rdy) begin
            o_e <= 0;
            o_x <= 0;
            o_w <= 0;
            o_h <= 0;
            o_last_enc <= 0;
        end else begin
            o_e <= 0;
            o_x <= 0;
            o_last_enc <= 0;

            // broadcast width/height
            for (k=0; k<N_E; k=k+1) begin
                o_w[k*16 +:16] <= i_w;
                o_h[k*14 +:14] <= i_h;
            end

            // output valid pixel only after stretch done
            if (i_e && frame_active) begin
                o_e[encoder_sel] <= 1'b1;
                o_x[encoder_sel*8 +:8] <= i_x;

                if (x_cnt == i_w-1 && y_cnt == i_h-1)
                    o_last_enc[encoder_sel] <= 1'b1;
            end
        end
    end

always @(posedge clk) begin
    x_cnt_d <= x_cnt;
    y_cnt_d <= y_cnt;
    encoder_sel_d <=encoder_sel;
end

endmodule
