`timescale 1ns/1ps
`default_nettype wire
// ---------------------------------------------------------------------------
// iserdes_byte_in — ISERDES-based high-speed input front-end for the 12-lane model.
//
// Captures N=12 serial pixel lanes in the hard I/O deserializers (ISERDESE2), so NO
// fabric logic runs at the line rate. Each lane carries one encoder lane's pixel bytes
// serialized MSB-first at 360 Mb/s; each ISERDESE2 does a 1:8 SDR deserialize, yielding
// one byte per lane every clk_div (45 MHz) cycle. The 12 bytes assemble directly into
// the 96-bit encoder word (byte k = lane k) — no fabric gearbox, no 540 MHz clock.
//
// Aggregate = 12 lanes x 360 Mb/s = 4.32 Gb/s = 540 MB/s (same as a single 540 MHz byte
// port, but the fast capture is in the IOB SERDES). clk_bit (360 MHz) and clk_div
// (45 MHz = clk_bit/8) come from an MMCM in the top wrapper; d_in are post-IBUF serial
// lines. Word alignment here assumes byte-aligned lanes (source frames on clk_div); a
// real link adds per-lane IDELAY training + BITSLIP, exposed as ports for that.
//
// NOTE: this instantiates real 7-series ISERDESE2 primitives (requires unisims for sim).
// ---------------------------------------------------------------------------
module iserdes_byte_in #(
    parameter integer N = 12          // serial lanes = encoder lanes
)(
    input  wire            clk_bit,   // 360 MHz serial bit clock (BUFIO/BUFG)
    input  wire            clk_div,   // 45 MHz  = clk_bit/8  (BUFR/BUFG, CLKDIV)
    input  wire            rst,       // active-high reset (sync to clk_div deassert)
    input  wire [N-1:0]    d_in,      // N serial data lines (post-IBUF)
    input  wire [N-1:0]    bitslip,   // per-lane BITSLIP request (word alignment)
    output wire [N*8-1:0]  o_word,    // 12 bytes @ clk_div (byte k = lane k)
    output reg             o_valid    // high once deserialisers are streaming
);
    // Small pipeline so o_valid follows reset deassertion by a few clk_div cycles
    // (ISERDESE2 needs a couple of divided cycles after RST before Q is valid).
    reg [2:0] vpipe;
    always @(posedge clk_div) begin
        if (rst) begin vpipe <= 3'b000; o_valid <= 1'b0; end
        else     begin vpipe <= {vpipe[1:0], 1'b1}; o_valid <= vpipe[2]; end
    end

    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : g_lane
            wire [7:0] q;   // Q1..Q8 : Q1 = first (oldest) bit received
            ISERDESE2 #(
                .DATA_RATE       ("SDR"),
                .DATA_WIDTH      (8),
                .INTERFACE_TYPE  ("NETWORKING"),
                .SERDES_MODE     ("MASTER"),
                .NUM_CE          (1),
                .IOBDELAY        ("NONE"),
                .OFB_USED        ("FALSE"),
                .DYN_CLKDIV_INV_EN("FALSE"),
                .DYN_CLK_INV_EN  ("FALSE"),
                .INIT_Q1         (1'b0), .INIT_Q2(1'b0), .INIT_Q3(1'b0), .INIT_Q4(1'b0),
                .SRVAL_Q1        (1'b0), .SRVAL_Q2(1'b0), .SRVAL_Q3(1'b0), .SRVAL_Q4(1'b0)
            ) u_iserdes (
                .Q1(q[0]), .Q2(q[1]), .Q3(q[2]), .Q4(q[3]),
                .Q5(q[4]), .Q6(q[5]), .Q7(q[6]), .Q8(q[7]),
                .O(),
                .SHIFTOUT1(), .SHIFTOUT2(),
                .D(d_in[i]),
                .DDLY(1'b0),
                .CLK(clk_bit), .CLKB(~clk_bit), .CLKDIV(clk_div), .CLKDIVP(1'b0),
                .OCLK(1'b0), .OCLKB(1'b0),
                .RST(rst),
                .CE1(1'b1), .CE2(1'b1),
                .BITSLIP(bitslip[i]),
                .SHIFTIN1(1'b0), .SHIFTIN2(1'b0),
                .OFB(1'b0),
                .DYNCLKDIVSEL(1'b0), .DYNCLKSEL(1'b0)
            );
            // ISERDESE2 presents the OLDEST captured bit on Q8 and newest on Q1. With the
            // source sending MSB-first (bit7 first = oldest), bit7->Q8 … bit0->Q1, so the
            // byte is {Q8,Q7,…,Q1} = {q[7],q[6],…,q[0]}.
            assign o_word[i*8 +: 8] = { q[7], q[6], q[5], q[4], q[3], q[2], q[1], q[0] };
        end
    endgenerate
endmodule
