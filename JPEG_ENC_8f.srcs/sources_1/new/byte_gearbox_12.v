`timescale 1ns/1ps
`default_nettype wire
// ---------------------------------------------------------------------------
// byte_gearbox_12 — serial-to-parallel input wrapper for the 12-lane model.
//
// Accepts ONE pixel byte per clk_fast cycle (target 540 MHz) on i_byte/i_valid,
// collects N=12 consecutive bytes, and presents them as one 12-byte word on
// clk_slow (= clk_fast/12, e.g. 45 MHz) — both as 12 separate 8-bit pins
// (o_b0..o_b11) and as the packed 96-bit o_word (= jls_encoder_axis s_axis_tdata).
//
// Rate match: 540 MHz x 1 byte = 45 MHz x 12 bytes = 540 MB/s. Byte k of each
// group of 12 becomes lane k, so the upstream must send bytes in the model's
// strided lane order (as tools/make_strided_hex.py emits them). CDC fast->slow
// uses a gray-coded dual-clock FIFO (depth 2^AW).
//
// NOTE: 540 MHz exceeds Artix-7 -2 fabric Fmax (~53 MHz here). This RTL is
// behaviourally correct at any clk_fast; a real 540 MHz byte interface would
// deserialise via ISERDES/GT primitives ahead of this collector.
// ---------------------------------------------------------------------------
module byte_gearbox_12 #(
    parameter integer N  = 12,   // bytes per word (= lanes)
    parameter integer AW = 4     // CDC FIFO address width (depth 2^AW words)
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

    // ------------------------------------------------------------------
    // Fast domain: gather N bytes. Bytes 0..N-2 are registered in `col`;
    // byte N-1 is combined straight into the assembled word on the last cycle.
    // ------------------------------------------------------------------
    reg  [7:0] col [0:N-2];
    reg  [CW-1:0] cnt;
    wire       wfull;
    wire       accept = i_valid & ~wfull;      // consume a byte this cycle
    wire       last   = (cnt == N-1);
    wire       winc   = accept & last;         // push a completed word

    wire [N*8-1:0] word_asm;
    genvar k;
    generate
        for (k = 0; k < N-1; k = k + 1) begin : g_asm
            assign word_asm[k*8 +: 8] = col[k];
        end
    endgenerate
    assign word_asm[(N-1)*8 +: 8] = i_byte;

    integer j;
    always @(posedge clk_fast or negedge rstn) begin
        if (!rstn) begin
            cnt <= 0;
            for (j = 0; j < N-1; j = j + 1) col[j] <= 8'd0;
        end else if (accept) begin
            if (!last) col[cnt] <= i_byte;
            cnt <= last ? {CW{1'b0}} : (cnt + 1'b1);
        end
    end

    assign i_ready = ~wfull;

    // ------------------------------------------------------------------
    // CDC FIFO (fast write -> slow read), gray-coded pointers, FWFT read.
    // ------------------------------------------------------------------
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
// gearbox_afifo — classic dual-clock (async) FIFO, gray-code pointers, 2-FF
// synchronisers, first-word-fall-through read. (Cummings style.)
// ---------------------------------------------------------------------------
module gearbox_afifo #(
    parameter integer DW = 96,
    parameter integer AW = 4
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

    // ---- write domain ----  (wfull is REGISTERED — a combinational wfull with the
    // `& ~wfull` term below forms a zero-time oscillating loop near full; registering
    // it breaks the loop, per the standard Cummings dual-clock FIFO.)
    reg  [AW:0] wbin, wgray;
    reg  [AW:0] rgray_w1, rgray_w2;      // read-gray synced into write clock
    wire [AW:0] wbin_nxt  = wbin + (winc & ~wfull);
    wire [AW:0] wgray_nxt = (wbin_nxt >> 1) ^ wbin_nxt;
    wire        wfull_val = (wgray_nxt == {~rgray_w2[AW:AW-1], rgray_w2[AW-2:0]});

    always @(posedge wclk or negedge arstn)
        if (!arstn) begin wbin <= 0; wgray <= 0; wfull <= 1'b0; end
        else        begin wbin <= wbin_nxt; wgray <= wgray_nxt; wfull <= wfull_val; end

    always @(posedge wclk or negedge arstn)
        if (!arstn) begin rgray_w1 <= 0; rgray_w2 <= 0; end
        else        begin rgray_w1 <= rgray; rgray_w2 <= rgray_w1; end

    always @(posedge wclk)
        if (winc & ~wfull) mem[wbin[AW-1:0]] <= wdata;

    // ---- read domain ----  (rempty likewise registered)
    reg  [AW:0] rbin, rgray;
    reg  [AW:0] wgray_r1, wgray_r2;      // write-gray synced into read clock
    wire [AW:0] rbin_nxt  = rbin + (rinc & ~rempty);
    wire [AW:0] rgray_nxt = (rbin_nxt >> 1) ^ rbin_nxt;
    wire        rempty_val = (rgray_nxt == wgray_r2);

    always @(posedge rclk or negedge arstn)
        if (!arstn) begin rbin <= 0; rgray <= 0; rempty <= 1'b1; end
        else        begin rbin <= rbin_nxt; rgray <= rgray_nxt; rempty <= rempty_val; end

    always @(posedge rclk or negedge arstn)
        if (!arstn) begin wgray_r1 <= 0; wgray_r2 <= 0; end
        else        begin wgray_r1 <= wgray; wgray_r2 <= wgray_r1; end

    assign rdata  = mem[rbin[AW-1:0]];   // FWFT combinational read
endmodule
