`timescale 1ns/1ps

module fifo_wrapper_output #(
    parameter integer N_E = 3,
    parameter integer LEN_WIDTH = 32
)(
    input  wire                     rst,
    input  wire                     wr_clk,
    input  wire                     rd_clk,
    input  wire [N_E*16-1:0]        din_flat,
    input  wire [N_E-1:0]           wr_en,
    input  wire [N_E-1:0]           o_last_enc,

    output wire [N_E*16-1:0]        fifo_dout_flat,
    output reg  [N_E-1:0]           dout_valid,
    output reg  [N_E-1:0]           dout_last,
    output wire [N_E-1:0]           wr_rst_busy,
    output wire [N_E-1:0]           rd_rst_busy
);

    // ------------------------------------------------------------------
    // FIFO signals
    // ------------------------------------------------------------------
    wire [N_E-1:0] fifo_empty;
    wire [N_E-1:0] fifo_valid;
    reg  [N_E-1:0] fifo_rd_en;

    genvar gi;
    generate
        for (gi = 0; gi < N_E; gi = gi + 1) begin : GEN_FIFO
            fifo_output u_fifo (
                .rst         (rst),
                .wr_clk      (wr_clk),
                .rd_clk      (rd_clk),
                .din         (din_flat[gi*16 +: 16]),
                .wr_en       (wr_en[gi]),
                .rd_en       (fifo_rd_en[gi]),
                .dout        (fifo_dout_flat[gi*16 +: 16]),
                .empty       (fifo_empty[gi]),
                .valid       (fifo_valid[gi]),
                .underflow   (),
                .almost_full (),
                .almost_empty(),
                .wr_rst_busy (wr_rst_busy[gi]),
                .rd_rst_busy (rd_rst_busy[gi])
            );
        end
    endgenerate

    // ------------------------------------------------------------------
    // WRITE DOMAIN: absolute write counters
    // ------------------------------------------------------------------
    reg [LEN_WIDTH-1:0] wr_cnt [0:N_E-1];
    reg [LEN_WIDTH-1:0] block_end_cnt_wr [0:N_E-1];
    reg [N_E-1:0]       len_toggle_wr;

    integer wi;
    always @(posedge wr_clk or posedge rst) begin
        if (rst) begin
            for (wi = 0; wi < N_E; wi = wi + 1) begin
                wr_cnt[wi] <= 0;
                block_end_cnt_wr[wi] <= 0;
            end
            len_toggle_wr <= {N_E{1'b0}};
        end else begin
            for (wi = 0; wi < N_E; wi = wi + 1) begin
                if (wr_en[wi])
                    wr_cnt[wi] <= wr_cnt[wi] + 1'b1;

                if (o_last_enc[wi]) begin
                    block_end_cnt_wr[wi] <= wr_cnt[wi];
                    len_toggle_wr[wi]    <= ~len_toggle_wr[wi];
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // CDC: toggle sync + capture block end count
    // ------------------------------------------------------------------
    reg [N_E-1:0] len_toggle_rd_ff1, len_toggle_rd_ff2;
    reg [N_E-1:0] len_toggle_edge;
    reg [LEN_WIDTH-1:0] block_end_cnt_rd [0:N_E-1];

    integer si;
    always @(posedge rd_clk or posedge rst) begin
        if (rst) begin
            len_toggle_rd_ff1 <= 0;
            len_toggle_rd_ff2 <= 0;
            len_toggle_edge  <= 0;
            for (si = 0; si < N_E; si = si + 1)
                block_end_cnt_rd[si] <= 0;
        end else begin
            len_toggle_rd_ff1 <= len_toggle_wr;
            len_toggle_rd_ff2 <= len_toggle_rd_ff1;
            len_toggle_edge  <= len_toggle_rd_ff2 ^ len_toggle_rd_ff1;

            for (si = 0; si < N_E; si = si + 1)
                if (len_toggle_edge[si])
                    block_end_cnt_rd[si] <= block_end_cnt_wr[si];
        end
    end

    // ------------------------------------------------------------------
    // READ DOMAIN: counters + block_pending (SINGLE OWNER)
    // ------------------------------------------------------------------
    reg [LEN_WIDTH-1:0] rd_total_cnt [0:N_E-1];
    reg [N_E-1:0]       block_pending;
    reg [N_E-1:0]       block_pending_clr;

    integer ri;
    always @(posedge rd_clk or posedge rst) begin
        if (rst) begin
            for (ri = 0; ri < N_E; ri = ri + 1)
                rd_total_cnt[ri] <= 0;

            block_pending <= {N_E{1'b0}};
        end else begin
            for (ri = 0; ri < N_E; ri = ri + 1) begin
                if (len_toggle_edge[ri])
                    block_pending[ri] <= 1'b1;
                else if (block_pending_clr[ri])
                    block_pending[ri] <= 1'b0;

                if (fifo_valid[ri])
                    rd_total_cnt[ri] <= rd_total_cnt[ri] + 1'b1;
            end
        end
    end

    // ------------------------------------------------------------------
    // READ + CAPTURE LOGIC
    // ------------------------------------------------------------------
    integer ci;
    always @(posedge rd_clk or posedge rst) begin
        if (rst) begin
            fifo_rd_en        <= {N_E{1'b0}};
            dout_valid        <= {N_E{1'b0}};
            dout_last         <= {N_E{1'b0}};
            block_pending_clr <= {N_E{1'b0}};
        end else begin
            fifo_rd_en        <= {N_E{1'b0}};
            dout_valid        <= {N_E{1'b0}};
            dout_last         <= {N_E{1'b0}};
            block_pending_clr <= {N_E{1'b0}};

            for (ci = 0; ci < N_E; ci = ci + 1) begin
                if (block_pending[ci] && !fifo_empty[ci])
                    fifo_rd_en[ci] <= 1'b1;

                if (fifo_valid[ci]) begin
                    dout_valid[ci] <= 1'b1;

                    // LAST exactly on final word
                    if ((rd_total_cnt[ci] + 1'b1) == block_end_cnt_rd[ci] &&
                        block_pending[ci] &&
                        block_end_cnt_rd[ci] != 0) begin
                        dout_last[ci]         <= 1'b1;
                        block_pending_clr[ci] <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
