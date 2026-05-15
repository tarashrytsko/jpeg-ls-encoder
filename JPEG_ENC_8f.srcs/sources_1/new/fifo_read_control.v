`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// fifo_read_control (FINAL - COPY READY)
// - Exact pixel count per slice
// - rd_cnt : 0 → block_pixels-1
// - GAP between slices (for b_eof = 2 cycles)
// - SOF only after GAP
// -----------------------------------------------------------------------------
module fifo_read_control #(
    parameter integer NUM_ENCODERS = 3,
    parameter integer NUM_SLICES   = 3,
    parameter integer SOF_CYCLES   = 3000,
    parameter integer GAP_CYCLES   = 5
)(
    input  wire                       rd_clk,
    input  wire                       sys_rdy,
    input  wire [13:0]                i_w_r,
    input  wire [13:0]                i_h_r,

    input  wire [NUM_ENCODERS-1:0]    fifo_empty,
    input  wire [NUM_ENCODERS-1:0]    fifo_valid,

    output reg  [NUM_ENCODERS-1:0]    rd_en,
    output reg                        i_sof_st_enc,
    output reg  [32*NUM_ENCODERS-1:0] read_count_flat
);

    // ------------------------------------------------------------
    // Block geometry
    // ------------------------------------------------------------
    reg [15:0] blk_w [0:NUM_ENCODERS-1];
    integer a,b,e;
reg [13:0] i_w;
reg [13:0] i_h;

always @(posedge rd_clk) begin
    if (!sys_rdy) begin
        i_w <= 14'd0;
        i_h <= 14'd0;
    end else begin
        // latch once; values never change anyway
        i_w <= i_w_r;
        i_h <= i_h_r;
    end
end
    always @(*) begin
        for (a = 0; a < NUM_ENCODERS-1; a = a + 1)
            blk_w[a] = i_w / NUM_ENCODERS;

        blk_w[NUM_ENCODERS-1] =
            i_w - ((i_w / NUM_ENCODERS) * (NUM_ENCODERS - 1));
    end

    // ------------------------------------------------------------
    // Per-slice pixel counts
    // ------------------------------------------------------------
    reg [31:0] block_pixels [0:NUM_SLICES-1][0:NUM_ENCODERS-1];
    reg [31:0] accum;

    always @(*) begin
        for (b = 0; b < NUM_ENCODERS; b = b + 1) begin
            accum = 0;
            for (a = 0; a < NUM_SLICES-1; a = a + 1) begin
                block_pixels[a][b] = blk_w[b] * (i_h / NUM_SLICES);
                accum = accum + block_pixels[a][b];
            end
            block_pixels[NUM_SLICES-1][b] = (blk_w[b] * i_h) - accum;
        end
    end

    // ------------------------------------------------------------
    // FSM
    // ------------------------------------------------------------
    localparam S_SOF  = 2'd0;
    localparam S_READ = 2'd1;
    localparam S_GAP  = 2'd2;
    localparam S_DONE = 2'd3;

    reg [1:0]  state;
    reg [1:0]  slice_idx;
    reg [31:0] sof_cnt;
    reg [2:0]  gap_cnt;

    reg [31:0] rd_cnt     [0:NUM_ENCODERS-1];
    reg [NUM_ENCODERS-1:0] rd_active;

    // ------------------------------------------------------------
    // Main FSM
    // ------------------------------------------------------------
    always @(posedge rd_clk) begin
        if (!sys_rdy) begin
            state        <= S_SOF;
            slice_idx    <= 0;
            sof_cnt      <= 0;
            gap_cnt      <= 0;
            rd_en        <= 0;
            rd_active    <= 0;
            i_sof_st_enc <= 1'b0;

            for (e = 0; e < NUM_ENCODERS; e = e + 1) begin
                rd_cnt[e] <= 32'd0;
                read_count_flat[e*32 +: 32] <= 32'd0;
            end
        end else begin
            // defaults
            rd_en        <= 0;
            i_sof_st_enc <= 1'b0;

            case (state)

                // ------------------------------------------------
                // SOF stretch
                // ------------------------------------------------
                S_SOF: begin
                    if (slice_idx >= NUM_SLICES) begin
                        state <= S_DONE;
                    end else begin
                        i_sof_st_enc <= 1'b1;
                        if (sof_cnt < SOF_CYCLES-1) begin
                            sof_cnt <= sof_cnt + 1'b1;
                        end else begin
                            sof_cnt <= 0;
                            for (e = 0; e < NUM_ENCODERS; e = e + 1) begin
                                rd_cnt[e]    <= 32'd0;
                                rd_active[e] <= (block_pixels[slice_idx][e] != 0);
                            end
                            state <= S_READ;
                        end
                    end
                end

                // ------------------------------------------------
                // READ pixels (EXACT count)
                // ------------------------------------------------
               S_READ: begin
    for (e = 0; e < NUM_ENCODERS; e = e + 1) begin
        if (rd_active[e] && !fifo_empty[e])
            rd_en[e] <= 1'b1;

        if (rd_active[e] && !fifo_empty[e]) begin
            rd_cnt[e] <= rd_cnt[e] + 1'b1;
            read_count_flat[e*32 +: 32] <= rd_cnt[e] + 1'b1;

            // STOP exactly after last rd_en
            if ((rd_cnt[e] + 1) == block_pixels[slice_idx][e])
                rd_active[e] <= 1'b0;
        end
    end

    if (rd_active == 0) begin
        slice_idx <= slice_idx + 1'b1;
        gap_cnt   <= 0;
        state     <= S_GAP;
    end
end

                // ------------------------------------------------
                // GAP (protect EOF)
                // ------------------------------------------------
                S_GAP: begin
                    if (gap_cnt < GAP_CYCLES-1)
                        gap_cnt <= gap_cnt + 1'b1;
                    else begin
                        gap_cnt <= 0;
                        state   <= S_SOF;
                    end
                end

                // ------------------------------------------------
                // DONE
                // ------------------------------------------------
                S_DONE: begin
                    rd_en        <= 0;
                    i_sof_st_enc <= 1'b0;
                end

                default: state <= S_SOF;
            endcase
        end
    end

endmodule
