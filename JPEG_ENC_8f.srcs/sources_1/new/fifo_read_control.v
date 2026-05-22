`timescale 1ns/1ps
// Continuous-drain FIFO read control with encoder-completion gating.
// Drains all encoder FIFOs whenever data is available.
// Only advances to next chunk SOF after ALL encoders emit o_last (EOI).
module fifo_read_control #(
    parameter integer NUM_ENCODERS = 5,
    parameter integer NUM_COLS     = 5,
    parameter integer NUM_SWATHS   = 4,
    parameter integer CHUNK_H      = 1250,
    parameter integer SOF_CYCLES   = 100,
    parameter integer GAP_CYCLES   = 5
)(
    input  wire                       rd_clk,
    input  wire                       sys_rdy,
    input  wire [NUM_ENCODERS*14-1:0] i_w_r,
    input  wire [13:0]                i_h_r,

    input  wire [NUM_ENCODERS-1:0]    fifo_empty,
    input  wire [NUM_ENCODERS-1:0]    fifo_valid,
    input  wire [NUM_ENCODERS-1:0]    enc_done,    // from encoder o_last/my_last

    output reg  [NUM_ENCODERS-1:0]    rd_en,
    output reg                        i_sof_st_enc,
    output reg  [32*NUM_ENCODERS-1:0] read_count_flat
);

    // Latch per-encoder widths
    reg [NUM_ENCODERS*14-1:0] i_w_bus;
    reg dims_valid;
    always @(posedge rd_clk) begin
        if (!sys_rdy) begin
            i_w_bus <= 0;
            dims_valid <= 0;
        end else begin
            i_w_bus <= i_w_r;
            if (i_w_r[13:0] != 0)
                dims_valid <= 1;
        end
    end

    // Per-encoder pixels per chunk
    reg [31:0] chunk_pixels [0:NUM_ENCODERS-1];
    integer ci;
    always @(*) begin
        for (ci = 0; ci < NUM_ENCODERS; ci = ci + 1)
            chunk_pixels[ci] = i_w_bus[ci*14 +: 14] * CHUNK_H;
    end

    // State
    reg [3:0]  chunk_idx;
    reg        all_done;
    reg [15:0] sof_cnt;
    reg        sof_active;
    reg [NUM_ENCODERS-1:0] enc_finished; // tracks which encoders emitted o_last this chunk

    integer e;

    always @(posedge rd_clk) begin
        if (!sys_rdy) begin
            rd_en          <= 0;
            i_sof_st_enc   <= 0;
            sof_cnt        <= 0;
            sof_active     <= 1; // start with SOF
            chunk_idx      <= 0;
            all_done       <= 0;
            enc_finished   <= 0;
            for (e = 0; e < NUM_ENCODERS; e = e + 1) begin
                read_count_flat[e*32 +: 32] <= 0;
            end
        end else if (all_done) begin
            rd_en        <= 0;
            i_sof_st_enc <= 0;
        end else begin
            rd_en        <= 0;
            i_sof_st_enc <= 0;

            // Track encoder completions
            for (e = 0; e < NUM_ENCODERS; e = e + 1)
                if (enc_done[e])
                    enc_finished[e] <= 1'b1;

            // SOF phase
            if (sof_active && dims_valid) begin
                i_sof_st_enc <= 1;
                sof_cnt <= sof_cnt + 1;
                if (sof_cnt >= SOF_CYCLES - 1) begin
                    sof_active <= 0;
                    sof_cnt    <= 0;
                end
            end

            // Continuous drain (after SOF)
            else if (!sof_active) begin
                for (e = 0; e < NUM_ENCODERS; e = e + 1) begin
                    if (!fifo_empty[e] && !enc_finished[e])
                        rd_en[e] <= 1;
                end

                // Check if ALL encoders finished this chunk
                if (enc_finished == {NUM_ENCODERS{1'b1}}) begin
                    if (chunk_idx >= NUM_SWATHS - 1) begin
                        all_done <= 1;
                    end else begin
                        chunk_idx    <= chunk_idx + 1;
                        enc_finished <= 0;
                        sof_active   <= 1;
                    end
                end
            end
        end
    end

endmodule
