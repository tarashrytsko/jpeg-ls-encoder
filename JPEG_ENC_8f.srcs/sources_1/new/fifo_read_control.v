`timescale 1ns/1ps
// fifo_read_control for 6-encoder streaming architecture.
// Processes 4 swaths sequentially. Each swath: 3 encoders active.
// Reads col_w * CHUNK_H pixels per active encoder per swath.
module fifo_read_control #(
    parameter integer NUM_ENCODERS = 6,
    parameter integer NUM_COLS     = 3,
    parameter integer NUM_SWATHS   = 4,
    parameter integer CHUNK_H      = 1250,
    parameter integer SOF_CYCLES   = 3000,
    parameter integer GAP_CYCLES   = 5
)(
    input  wire                       rd_clk,
    input  wire                       sys_rdy,
    input  wire [NUM_ENCODERS*14-1:0] i_w_r,
    input  wire [13:0]                i_h_r,

    input  wire [NUM_ENCODERS-1:0]    fifo_empty,
    input  wire [NUM_ENCODERS-1:0]    fifo_valid,

    output reg  [NUM_ENCODERS-1:0]    rd_en,
    output reg                        i_sof_st_enc,
    output reg  [32*NUM_ENCODERS-1:0] read_count_flat
);

    // Latch per-encoder widths from clk domain
    reg [NUM_ENCODERS*14-1:0] i_w_bus;
    always @(posedge rd_clk) begin
        if (!sys_rdy)
            i_w_bus <= 0;
        else
            i_w_bus <= i_w_r;
    end

    // Pixels per encoder per swath = per_encoder_width * CHUNK_H
    // Even swaths (0,2): enc 0,1,2 active; Odd swaths (1,3): enc 3,4,5 active
    reg [31:0] block_pixels [0:NUM_SWATHS-1][0:NUM_ENCODERS-1];
    integer s, e;
    always @(*) begin
        for (s = 0; s < NUM_SWATHS; s = s + 1)
            for (e = 0; e < NUM_ENCODERS; e = e + 1) begin
                if ((s % 2) == (e / NUM_COLS))
                    block_pixels[s][e] = i_w_bus[e*14 +: 14] * CHUNK_H;
                else
                    block_pixels[s][e] = 0;
            end
    end

    // FSM
    localparam S_SOF  = 2'd0;
    localparam S_READ = 2'd1;
    localparam S_GAP  = 2'd2;
    localparam S_DONE = 2'd3;

    reg [1:0]  state;
    reg [2:0]  swath_idx;
    reg [31:0] sof_cnt;
    reg [2:0]  gap_cnt;
    reg [31:0] rd_cnt [0:NUM_ENCODERS-1];
    reg [NUM_ENCODERS-1:0] rd_active;

    always @(posedge rd_clk) begin
        if (!sys_rdy) begin
            state        <= S_SOF;
            swath_idx    <= 0;
            sof_cnt      <= 0;
            gap_cnt      <= 0;
            rd_en        <= 0;
            rd_active    <= 0;
            i_sof_st_enc <= 0;
            for (e = 0; e < NUM_ENCODERS; e = e + 1) begin
                rd_cnt[e] <= 0;
                read_count_flat[e*32 +: 32] <= 0;
            end
        end else begin
            rd_en        <= 0;
            i_sof_st_enc <= 0;

            case (state)
                S_SOF: begin
                    if (swath_idx >= NUM_SWATHS) begin
                        state <= S_DONE;
                    end else begin
                        i_sof_st_enc <= 1'b1;
                        if (sof_cnt < SOF_CYCLES - 1)
                            sof_cnt <= sof_cnt + 1;
                        else begin
                            sof_cnt <= 0;
                            for (e = 0; e < NUM_ENCODERS; e = e + 1) begin
                                rd_cnt[e] <= 0;
                                rd_active[e] <= (block_pixels[swath_idx][e] != 0);
                            end
                            state <= S_READ;
                        end
                    end
                end

                S_READ: begin
                    for (e = 0; e < NUM_ENCODERS; e = e + 1) begin
                        if (rd_active[e] && !fifo_empty[e])
                            rd_en[e] <= 1'b1;

                        if (rd_active[e] && !fifo_empty[e]) begin
                            rd_cnt[e] <= rd_cnt[e] + 1;
                            read_count_flat[e*32 +: 32] <= rd_cnt[e] + 1;
                            if ((rd_cnt[e] + 1) == block_pixels[swath_idx][e])
                                rd_active[e] <= 0;
                        end
                    end

                    if (rd_active == 0) begin
                        swath_idx <= swath_idx + 1;
                        gap_cnt   <= 0;
                        state     <= S_GAP;
                    end
                end

                S_GAP: begin
                    if (gap_cnt < GAP_CYCLES - 1)
                        gap_cnt <= gap_cnt + 1;
                    else begin
                        gap_cnt <= 0;
                        state   <= S_SOF;
                    end
                end

                S_DONE: begin
                end
            endcase
        end
    end

endmodule
