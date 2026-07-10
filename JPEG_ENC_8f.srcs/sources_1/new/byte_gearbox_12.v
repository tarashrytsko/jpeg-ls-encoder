`timescale 1ns/1ps
`default_nettype wire
// ---------------------------------------------------------------------------
// byte_gearbox_12 — serial-to-parallel input wrapper for the 12-lane model.
//
// Reads ONE pixel byte per clk_fast cycle (target 540 MHz) on i_byte/i_valid,
// collects N=12 consecutive bytes, and presents them as a 12-byte word on clk_slow
// (= clk_fast/12, e.g. 45 MHz): 12 separate 8-bit pins (o_b0..o_b11) and packed
// o_word[95:0] (= jls_encoder_axis s_axis_tdata). 540 MHz x 1B = 45 MHz x 12B = 540 MB/s.
//
// Byte k of each group -> lane k. CDC fast->slow via a gray-coded dual-clock FIFO
// (gearbox_afifo) with REGISTERED full/empty flags and a REGISTERED (pipelined) write.
//
// Fmax: on xc7a200t-2 this closes ~520 MHz (the 96-bit CDC write is routing-bound);
// 540 MHz needs a faster speed grade (-3, whose clock network reaches ~700+ MHz) or an
// ISERDES/GT deserialiser feeding this block. See docs/RTL_HW_IMPLEMENTATION.md §14.
// ---------------------------------------------------------------------------
module byte_gearbox_12 #(
    parameter integer N  = 12,   // bytes per word (= lanes)
    parameter integer AW = 2     // CDC FIFO address width (depth 2^AW words). Depth 4 is
                                 // ample (rates matched 540/12 = 45 MHz; SOF-stretch stall
                                 // absorbed by backpressure) and keeps pointer logic short.
)(
    input  wire            rstn,
    // ---- fast (serial) domain ----
    input  wire            clk_fast,
    input  wire            i_valid,   // a pixel byte is present this cycle
    input  wire  [7:0]     i_byte,    // the pixel byte
    output wire            i_ready,   // 1 = can accept (FIFO not full)
    // ---- slow (parallel) domain ----
    input  wire            clk_slow,
    output wire  [7:0]     o_b0,  o_b1,  o_b2,  o_b3,
    output wire  [7:0]     o_b4,  o_b5,  o_b6,  o_b7,
    output wire  [7:0]     o_b8,  o_b9,  o_b10, o_b11,
    output wire  [N*8-1:0] o_word,    // packed (byte k = lane k) = s_axis_tdata
    output wire            o_valid,   // a 12-byte word is available
    input  wire            o_ready    // downstream accepts (e.g. s_axis_tready)
);
    localparam integer CW = (N > 1) ? $clog2(N) : 1;

    // Shift-register collector (newest byte in col[0]); every register's clock-enable is
    // simply `accept` (no per-register index decode) — keeps the collect path fast.
    reg  [7:0] col [0:N-2];
    reg  [CW-1:0] cnt;
    wire       wfull;
    wire       accept = i_valid & ~wfull;      // consume a byte this cycle
    wire       last   = (cnt == N-1);
    wire       winc   = accept & last;         // push a completed word

    // At the push cycle, byte N-1 = i_byte and col holds the previous N-1 bytes newest-
    // first (col[0]=byte N-2 … col[N-2]=byte 0). So lane k = k-th received byte:
    //   lane k (k<N-1) = col[(N-2)-k];  lane N-1 = i_byte.
    wire [N*8-1:0] word_asm;
    genvar k;
    generate
        for (k = 0; k < N-1; k = k + 1) begin : g_asm
            assign word_asm[k*8 +: 8] = col[(N-2)-k];
        end
    endgenerate
    assign word_asm[(N-1)*8 +: 8] = i_byte;

    integer j;
    always @(posedge clk_fast or negedge rstn) begin
        if (!rstn) begin
            cnt <= 0;
            for (j = 0; j < N-1; j = j + 1) col[j] <= 8'd0;
        end else if (accept) begin
            col[0] <= i_byte;
            for (j = 1; j < N-1; j = j + 1) col[j] <= col[j-1];
            cnt <= last ? {CW{1'b0}} : (cnt + 1'b1);
        end
    end

    assign i_ready = ~wfull;

    wire            rempty;
    wire [N*8-1:0]  rword;
    wire            rinc = o_valid & o_ready;

    gearbox_afifo #(.DW(N*8), .AW(AW)) u_fifo (
        .arstn (rstn),
        .wclk  (clk_fast), .winc (winc), .wdata (word_asm), .wfull (wfull),
        .rclk  (clk_slow), .rinc (rinc), .rdata (rword),   .rempty(rempty)
    );

    assign o_word  = rword;
    assign o_valid = ~rempty;
    assign o_b0  = rword[0*8 +: 8];  assign o_b1  = rword[1*8 +: 8];
    assign o_b2  = rword[2*8 +: 8];  assign o_b3  = rword[3*8 +: 8];
    assign o_b4  = rword[4*8 +: 8];  assign o_b5  = rword[5*8 +: 8];
    assign o_b6  = rword[6*8 +: 8];  assign o_b7  = rword[7*8 +: 8];
    assign o_b8  = rword[8*8 +: 8];  assign o_b9  = rword[9*8 +: 8];
    assign o_b10 = rword[10*8 +: 8]; assign o_b11 = rword[11*8 +: 8];
endmodule

// ---------------------------------------------------------------------------
// gearbox_afifo — dual-clock (async) FIFO, gray-code pointers, 2-FF synchronisers,
// FWFT read. REGISTERED full/empty flags (a combinational full flag oscillates in
// zero time via the `& ~wfull` term when near full). REGISTERED (pipelined) write:
// WE/addr/data are flopped so the LUTRAM is driven by FFs (fast arc), not by the
// combinational winc&~wfull path. Safe because winc pulses at most once per 12 fast
// cycles and the read side only sees a word after the gray sync (>=2 rclk >> 1 wclk).
// ---------------------------------------------------------------------------
module gearbox_afifo #(
    parameter integer DW = 96,
    parameter integer AW = 2
)(
    input  wire           arstn,
    input  wire           wclk,
    input  wire           winc,
    input  wire [DW-1:0]  wdata,
    output reg            wfull,
    input  wire           rclk,
    input  wire           rinc,
    output wire [DW-1:0]  rdata,
    output reg            rempty
);
    localparam integer DEPTH = (1 << AW);
    (* ram_style = "distributed" *) reg [DW-1:0] mem [0:DEPTH-1];

    // ---- write domain ----
    reg  [AW:0] wbin, wgray;
    reg  [AW:0] rgray_w1, rgray_w2;
    wire [AW:0] wbin_nxt  = wbin + (winc & ~wfull);
    wire [AW:0] wgray_nxt = (wbin_nxt >> 1) ^ wbin_nxt;
    wire        wfull_val = (wgray_nxt == {~rgray_w2[AW:AW-1], rgray_w2[AW-2:0]});

    always @(posedge wclk or negedge arstn)
        if (!arstn) begin wbin <= 0; wgray <= 0; wfull <= 1'b0; end
        else        begin wbin <= wbin_nxt; wgray <= wgray_nxt; wfull <= wfull_val; end

    always @(posedge wclk or negedge arstn)
        if (!arstn) begin rgray_w1 <= 0; rgray_w2 <= 0; end
        else        begin rgray_w1 <= rgray; rgray_w2 <= rgray_w1; end

    // pipelined write: FF-sourced WE/addr/data
    (* max_fanout = 16 *) reg  mem_we_q;
    reg [DW-1:0]              wdata_q;
    reg [AW-1:0]             waddr_q;
    always @(posedge wclk or negedge arstn)
        if (!arstn) mem_we_q <= 1'b0;
        else begin
            mem_we_q <= winc & ~wfull;
            wdata_q  <= wdata;
            waddr_q  <= wbin[AW-1:0];
        end
    always @(posedge wclk)
        if (mem_we_q) mem[waddr_q] <= wdata_q;

    // ---- read domain ----
    reg  [AW:0] rbin, rgray;
    reg  [AW:0] wgray_r1, wgray_r2;
    wire [AW:0] rbin_nxt  = rbin + (rinc & ~rempty);
    wire [AW:0] rgray_nxt = (rbin_nxt >> 1) ^ rbin_nxt;
    wire        rempty_val = (rgray_nxt == wgray_r2);

    always @(posedge rclk or negedge arstn)
        if (!arstn) begin rbin <= 0; rgray <= 0; rempty <= 1'b1; end
        else        begin rbin <= rbin_nxt; rgray <= rgray_nxt; rempty <= rempty_val; end

    always @(posedge rclk or negedge arstn)
        if (!arstn) begin wgray_r1 <= 0; wgray_r2 <= 0; end
        else        begin wgray_r1 <= wgray; wgray_r2 <= wgray_r1; end

    assign rdata = mem[rbin[AW-1:0]];   // FWFT combinational read
endmodule
