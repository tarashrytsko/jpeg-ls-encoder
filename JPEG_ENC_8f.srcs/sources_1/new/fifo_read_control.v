`timescale 1ns/1ps
module fifo_read_control #(
    parameter integer NUM_ENCODERS = 2,
    parameter integer N_H          = 2,   // horizontal blocks (cols)
    parameter integer N_V          = 2,   // vertical blocks (rows)
    parameter integer SOF_CYCLES   = 3000
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

    // Per-lane sub-image dims — use i_w_r/i_h_r directly so counts are valid as soon
    // as dimensions arrive. (i_w_r/i_h_r are held stable for the whole frame by the
    // upstream dimension source, so no registered copy is needed here.)
    reg [15:0] col_w [0:N_H-1];
    integer a;
    always @(*) begin
        for (a = 0; a < N_H-1; a = a + 1)
            col_w[a] = i_w_r / N_H;
        col_w[N_H-1] = i_w_r - (i_w_r / N_H) * (N_H - 1);
    end

    reg [15:0] swath_h [0:N_V-1];
    integer b;
    always @(*) begin
        for (b = 0; b < N_V-1; b = b + 1)
            swath_h[b] = i_h_r / N_V;
        swath_h[N_V-1] = i_h_r - (i_h_r / N_V) * (N_V - 1);
    end

    // WIDE LOCKSTEP: all NUM_ENCODERS lanes run concurrently in a single pass — the
    // wide splitter feeds one pixel per lane per cycle for every lane at once, so
    // there is no sequential swath ordering. Lane e occupies grid block
    // (bx=e%N_H, by=e/N_H) and drains col_w[bx]*swath_h[by] pixels. For N_V=1 this
    // reduces to col_w[e]*swath_h[0] = the previous per-swath count (vertical
    // behavior unchanged).
    reg [31:0] enc_pix [0:NUM_ENCODERS-1];
    integer e;
    always @(*) begin
        for (e = 0; e < NUM_ENCODERS; e = e + 1)
            enc_pix[e] = col_w[e % N_H] * swath_h[e / N_H];
    end

    // FSM: SOF stretch -> READ (all lanes concurrently) -> DONE.
    localparam S_SOF  = 2'd0;
    localparam S_READ = 2'd1;
    localparam S_DONE = 2'd2;

    reg [1:0]  state;
    reg [31:0] sof_cnt;
    reg [31:0] rd_cnt [0:NUM_ENCODERS-1];
    reg [NUM_ENCODERS-1:0] rd_active;

    always @(posedge rd_clk) begin
        if (!sys_rdy) begin
            state           <= S_SOF;
            sof_cnt         <= 0;
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
                    i_sof_st_enc <= {NUM_ENCODERS{1'b1}};
                    if (sof_cnt < SOF_CYCLES - 1 || i_w_r == 0 || i_h_r == 0) begin
                        if (i_w_r != 0 && i_h_r != 0)
                            sof_cnt <= sof_cnt + 1;
                    end else begin
                        sof_cnt <= 0;
                        for (e = 0; e < NUM_ENCODERS; e = e + 1) begin
                            rd_cnt[e] <= 0;
                            rd_active[e] <= (enc_pix[e] != 0);
                        end
                        state <= S_READ;
                    end
                end

                S_READ: begin
                    // Count DELIVERED pixels (fifo_valid), not rd_en assertions — the
                    // async FIFO empty flag can lag, so some rd_en pulses return no
                    // valid ("phantom reads"). Counting valids drains each FIFO fully;
                    // rd_en[e] (registered last-cycle value) is the single read in
                    // flight, so gate new reads on rd_cnt+in_flight < enc_pix.
                    for (e = 0; e < NUM_ENCODERS; e = e + 1) begin
                        if (rd_active[e] && fifo_valid[e]) begin
                            rd_cnt[e] <= rd_cnt[e] + 1;
                            read_count_flat[e*32 +: 32] <= rd_cnt[e] + 1;
                            if ((rd_cnt[e] + 1) == enc_pix[e])
                                rd_active[e] <= 0;
                        end
                        if (rd_active[e] && !fifo_empty[e] &&
                            ((rd_cnt[e] + rd_en[e]) < enc_pix[e]))
                            rd_en[e] <= 1'b1;
                        else
                            rd_en[e] <= 1'b0;
                    end

                    if (rd_active == 0)
                        state <= S_DONE;
                end

                S_DONE: begin
                    rd_en        <= 0;
                    i_sof_st_enc <= 0;
                end

                default: ; // state 2'b11 unreachable — explicit for lint
            endcase
        end
    end

endmodule
