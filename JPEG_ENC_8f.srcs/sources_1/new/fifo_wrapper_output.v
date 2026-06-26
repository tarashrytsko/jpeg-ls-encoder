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
    input  wire [N_E-1:0]           m_axis_tready,

    output wire [N_E*16-1:0]        fifo_dout_flat,
    output reg  [N_E-1:0]           dout_valid,
    output reg  [N_E-1:0]           dout_last,
    output wire [N_E-1:0]           wr_rst_busy,
    output wire [N_E-1:0]           rd_rst_busy
);

    wire [N_E-1:0] fifo_empty;
    wire [N_E-1:0] fifo_valid;

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
    // WRITE DOMAIN: track write count and store end positions
    // Use a 2-bit counter (supports up to 4 pending slices) with gray CDC
    // ------------------------------------------------------------------
    reg [LEN_WIDTH-1:0] wr_cnt [0:N_E-1];
    reg [LEN_WIDTH-1:0] end_pos [0:N_E-1][0:3];
    reg [2:0]           wr_ptr [0:N_E-1];

    integer wi;
    always @(posedge wr_clk or posedge rst) begin
        if (rst) begin
            for (wi = 0; wi < N_E; wi = wi + 1) begin
                wr_cnt[wi] <= 0;
                wr_ptr[wi] <= 0;
            end
        end else begin
            for (wi = 0; wi < N_E; wi = wi + 1) begin
                if (wr_en[wi])
                    wr_cnt[wi] <= wr_cnt[wi] + 1'b1;

                if (o_last_enc[wi]) begin
                    end_pos[wi][wr_ptr[wi][1:0]] <= wr_cnt[wi];
                    wr_ptr[wi] <= wr_ptr[wi] + 1'b1;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // CDC: gray-coded write pointer → read domain
    // ------------------------------------------------------------------
    function [2:0] to_gray(input [2:0] b);
        to_gray = b ^ (b >> 1);
    endfunction

    function [2:0] from_gray(input [2:0] g);
        begin
            from_gray[2] = g[2];
            from_gray[1] = g[2] ^ g[1];
            from_gray[0] = g[2] ^ g[1] ^ g[0];
        end
    endfunction

    reg [2:0] wr_ptr_gray [0:N_E-1];
    reg [2:0] wr_ptr_gray_s1 [0:N_E-1];
    reg [2:0] wr_ptr_gray_s2 [0:N_E-1];
    reg [2:0] wr_ptr_rd [0:N_E-1];

    integer gi2;
    always @(posedge wr_clk or posedge rst) begin
        if (rst) begin
            for (gi2 = 0; gi2 < N_E; gi2 = gi2 + 1)
                wr_ptr_gray[gi2] <= 0;
        end else begin
            for (gi2 = 0; gi2 < N_E; gi2 = gi2 + 1)
                wr_ptr_gray[gi2] <= to_gray(wr_ptr[gi2]);
        end
    end

    always @(posedge rd_clk or posedge rst) begin
        if (rst) begin
            for (gi2 = 0; gi2 < N_E; gi2 = gi2 + 1) begin
                wr_ptr_gray_s1[gi2] <= 0;
                wr_ptr_gray_s2[gi2] <= 0;
                wr_ptr_rd[gi2] <= 0;
            end
        end else begin
            for (gi2 = 0; gi2 < N_E; gi2 = gi2 + 1) begin
                wr_ptr_gray_s1[gi2] <= wr_ptr_gray[gi2];
                wr_ptr_gray_s2[gi2] <= wr_ptr_gray_s1[gi2];
                wr_ptr_rd[gi2] <= from_gray(wr_ptr_gray_s2[gi2]);
            end
        end
    end

    // ------------------------------------------------------------------
    // READ DOMAIN: AXIS master with tready backpressure.
    // One outstanding read max (standard FIFO has 1-cycle read latency, so a
    // requested word lands the next cycle). dout_valid/dout_flat are the AXIS
    // tvalid/tdata; reads are gated by tready so no word is dropped when the
    // consumer stalls. With tready held high this matches the prior full-rate drain.
    // ------------------------------------------------------------------
    reg  [LEN_WIDTH-1:0] rd_cnt  [0:N_E-1];
    reg  [2:0]           rd_ptr  [0:N_E-1];
    reg  [N_E-1:0]       pending;          // a read issued last cycle; data on dout now
    reg  [N_E-1:0]       last_pend;        // that pending word is a slice-final word

    wire [N_E-1:0] out_free = ~dout_valid | m_axis_tready;   // output reg free next cycle
    wire [N_E-1:0] fifo_rd_en = (~fifo_empty) & out_free & (~pending);

    // slice-final detection: the word at rd_cnt is the last of slice rd_ptr
    wire [N_E-1:0] read_is_last;
    genvar li;
    generate
        for (li = 0; li < N_E; li = li + 1) begin : GEN_LAST
            assign read_is_last[li] =
                (rd_ptr[li] != wr_ptr_rd[li]) &&
                ((rd_cnt[li] + 1) == end_pos[li][rd_ptr[li][1:0]]);
        end
    endgenerate

    integer ri;
    always @(posedge rd_clk or posedge rst) begin
        if (rst) begin
            dout_valid <= 0;
            dout_last  <= 0;
            pending    <= 0;
            last_pend  <= 0;
            for (ri = 0; ri < N_E; ri = ri + 1) begin
                rd_cnt[ri] <= 0;
                rd_ptr[ri] <= 0;
            end
        end else begin
            for (ri = 0; ri < N_E; ri = ri + 1) begin
                // consumer accepts the currently presented word
                if (dout_valid[ri] && m_axis_tready[ri]) begin
                    dout_valid[ri] <= 1'b0;
                    dout_last[ri]  <= 1'b0;
                end
                // a previously requested word lands now -> present it
                if (pending[ri]) begin
                    dout_valid[ri] <= 1'b1;
                    dout_last[ri]  <= last_pend[ri];
                    if (last_pend[ri]) rd_ptr[ri] <= rd_ptr[ri] + 1'b1;
                end
                // issue a new read
                if (fifo_rd_en[ri]) rd_cnt[ri] <= rd_cnt[ri] + 1'b1;
                pending[ri]   <= fifo_rd_en[ri];
                last_pend[ri] <= read_is_last[ri] & fifo_rd_en[ri];
            end
        end
    end

endmodule
