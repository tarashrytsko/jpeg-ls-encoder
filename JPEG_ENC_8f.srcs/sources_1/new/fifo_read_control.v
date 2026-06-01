`timescale 1ns/1ps
module fifo_read_control #(
    parameter integer NUM_ENCODERS = 2,
    parameter integer N_H          = 2,   // horizontal blocks (cols)
    parameter integer N_V          = 2,   // vertical blocks (rows = swaths)
    parameter integer SOF_CYCLES   = 3000,
    parameter integer GAP_CYCLES   = 5
)(
    input  wire                       rd_clk,
    input  wire                       sys_rdy,
    input  wire [15:0]                i_w_r,
    input  wire [13:0]                i_h_r,

    input  wire [NUM_ENCODERS-1:0]    fifo_empty,
    input  wire [NUM_ENCODERS-1:0]    fifo_valid,

    output reg  [NUM_ENCODERS-1:0]    rd_en,
    output reg  [NUM_ENCODERS-1:0]    i_sof_st_enc,
    output reg  [32*NUM_ENCODERS-1:0] read_count_flat
);

    reg [15:0] i_w; reg [13:0] i_h;
    always @(posedge rd_clk) begin
        if (!sys_rdy) begin
            i_w <= 0; i_h <= 0;
        end else begin
            i_w <= i_w_r; i_h <= i_h_r;
        end
    end

    // Column widths — use i_w_r directly so enc_pixels is valid as soon as dimensions arrive
    reg [15:0] col_w [0:N_H-1];
    integer a;
    always @(*) begin
        for (a = 0; a < N_H-1; a = a + 1)
            col_w[a] = i_w_r / N_H;
        col_w[N_H-1] = i_w_r - (i_w_r / N_H) * (N_H - 1);
    end

    // Swath heights
    reg [15:0] swath_h [0:N_V-1];
    integer b;
    always @(*) begin
        for (b = 0; b < N_V-1; b = b + 1)
            swath_h[b] = i_h_r / N_V;
        swath_h[N_V-1] = i_h_r - (i_h_r / N_V) * (N_V - 1);
    end

    // Pixels per encoder for each swath row
    // block_idx = row*N_H + col; encoder = block_idx % NUM_ENCODERS
    // Sum col widths assigned to this encoder in this row
    reg [31:0] enc_pixels [0:N_V-1][0:NUM_ENCODERS-1];
    integer s, e, col;
    always @(*) begin
        for (s = 0; s < N_V; s = s + 1)
            for (e = 0; e < NUM_ENCODERS; e = e + 1)
                enc_pixels[s][e] = 0;
        for (s = 0; s < N_V; s = s + 1)
            for (col = 0; col < N_H; col = col + 1) begin
                // block_idx = s*N_H + col, maps to encoder (s*N_H+col) % NUM_ENCODERS
                e = (s * N_H + col) % NUM_ENCODERS;
                enc_pixels[s][e] = enc_pixels[s][e] + col_w[col] * swath_h[s];
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
            state           <= S_SOF;
            swath_idx       <= 0;
            sof_cnt         <= 0;
            gap_cnt         <= 0;
            rd_en           <= 0;
            rd_active       <= 0;
            i_sof_st_enc    <= 0;
            for (e = 0; e < NUM_ENCODERS; e = e + 1) begin
                rd_cnt[e] <= 0;
                read_count_flat[e*32 +: 32] <= 0;
            end
        end else begin
            rd_en        <= 0;
            i_sof_st_enc <= 0;

            case (state)
                S_SOF: begin
                    if (swath_idx >= N_V) begin
                        state <= S_DONE;
                    end else begin
                        i_sof_st_enc <= {NUM_ENCODERS{1'b1}};
                        if (sof_cnt < SOF_CYCLES - 1 || i_w_r == 0 || i_h_r == 0) begin
                            if (i_w_r != 0 && i_h_r != 0)
                                sof_cnt <= sof_cnt + 1;
                        end else begin
                            sof_cnt <= 0;
                            for (e = 0; e < NUM_ENCODERS; e = e + 1) begin
                                rd_cnt[e] <= 0;
                                rd_active[e] <= (enc_pixels[swath_idx][e] != 0);
                            end
                            state <= S_READ;
                        end
                    end
                end

                S_READ: begin
                    for (e = 0; e < NUM_ENCODERS; e = e + 1) begin
                        if (rd_active[e] && !fifo_empty[e]) begin
                            rd_en[e] <= 1'b1;
                            rd_cnt[e] <= rd_cnt[e] + 1;
                            read_count_flat[e*32 +: 32] <= rd_cnt[e] + 1;
                            if ((rd_cnt[e] + 1) == enc_pixels[swath_idx][e])
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
                    rd_en        <= 0;
                    i_sof_st_enc <= 0;
                end
            endcase
        end
    end

endmodule
