`timescale 1ns/1ps
`default_nettype wire
// ---------------------------------------------------------------------------
// jls_serial_demo_top — synthesizable serial-in harness (the ISERDES analogue of
// jls_demo_top). Real HW receiver:
//
//   12 serial data pins ─IBUF─▶ iserdes_byte_in (ISERDESE2 1:8) ─▶ 12 bytes @ 45 MHz
//     ─▶ BITSLIP align + sentinel framing ─▶ gearbox_afifo (async CDC, 45→enc wr_clk,
//        deep enough to absorb the encoder SOF stretch) ─▶ jls_encoder_axis (N_E=12,
//        vertical 12×1) ─▶ 12 compressed lanes ─▶ axis_sink (checksum/done → pins).
//
// Clocks: an MMCME2_BASE turns the 200 MHz board diff clock into clk_bit (360 MHz, the
// ISERDES line clock) and clk_div (45 MHz). Note: unlike jls_demo_top there is no on-chip
// pixel source — ISERDESE2 inputs must come from device pads, so the 12 lanes are real
// input pins driven by an external serialiser (in sim, tb_jls_serial_demo). Verified
// end-to-end lossless (== the parallel path) in that testbench. A production link adds
// per-bit IDELAYE2 eye-centering; here clk_bit also samples (system-synchronous).
// ---------------------------------------------------------------------------
module jls_serial_demo_top #(
    parameter integer N     = 12,
    parameter integer IMG_W = 300,
    parameter integer IMG_H = 300
)(
    input  wire        rstn,
    input  wire        clk_in1_p,
    input  wire        clk_in1_n,     // 200 MHz board diff clock
    input  wire [N-1:0] ser_d,        // 12 serial pixel lanes (360 Mb/s, one per enc lane)
    output wire        clk,           // encoder wr_clk (observable)
    output wire        done,
    output wire [30:0] status         // checksum (anti-prune)
);
    wire rst = ~rstn;

    // ---- board diff clock -> single-ended 200 MHz ----
    wire clk200;
    IBUFDS u_ibufds (.I(clk_in1_p), .IB(clk_in1_n), .O(clk200));

    // ---- MMCM: 200 MHz -> clk_bit 360 MHz + clk_div 45 MHz (VCO 900) ----
    // Integer feedback (M=9) + a single fractional output (CLKOUT0=2.5) keeps every
    // divider on the 0.125 hardware grid (AVAL-139 clean). Fpfd = 200/2 = 100 MHz.
    wire clkfb, clk_bit_i, clk_div_i, mmcm_locked;
    MMCME2_BASE #(
        .CLKIN1_PERIOD   (5.000),   // 200 MHz
        .DIVCLK_DIVIDE   (2),       // Fpfd = 100 MHz
        .CLKFBOUT_MULT_F (9.000),   // VCO = 100*9 = 900 MHz  (integer feedback)
        .CLKOUT0_DIVIDE_F(2.500),   // 900/2.5 = 360 MHz  (clk_bit; sole fractional output)
        .CLKOUT1_DIVIDE  (20)       // 900/20  = 45 MHz   (clk_div)
    ) u_mmcm (
        .CLKIN1(clk200), .CLKFBIN(clkfb), .CLKFBOUT(clkfb),
        .CLKOUT0(clk_bit_i), .CLKOUT1(clk_div_i),
        .CLKOUT2(), .CLKOUT3(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
        .CLKOUT0B(), .CLKOUT1B(), .CLKFBOUTB(),
        .LOCKED(mmcm_locked), .PWRDWN(1'b0), .RST(rst)
    );
    wire clk_bit, clk_div;
    BUFG u_bg_bit (.I(clk_bit_i), .O(clk_bit));
    BUFG u_bg_div (.I(clk_div_i), .O(clk_div));

    // ---- serial input pins -> ISERDES ----
    wire [N-1:0] d_in;
    genvar ip;
    generate for (ip = 0; ip < N; ip = ip + 1) begin : g_ibuf
        IBUF u_ib (.I(ser_d[ip]), .O(d_in[ip]));
    end endgenerate

    wire         is_rst = ~mmcm_locked | rst;
    reg  [N-1:0] bitslip_r = 0;
    wire [N*8-1:0] is_word;
    wire           is_valid;
    iserdes_byte_in #(.N(N)) u_is (
        .clk_bit(clk_bit), .clk_div(clk_div), .rst(is_rst),
        .d_in(d_in), .bitslip(bitslip_r), .o_word(is_word), .o_valid(is_valid)
    );

    // ---- receiver framing FSM (clk_div): BITSLIP-align on 0x01 preamble, then start
    //      forwarding on the 0xAA sentinel ----
    localparam [7:0] PRE = 8'h01, SNT = 8'hAA;
    reg       aligned = 0, pix_wr = 0;
    reg [3:0] slips = 0, wcnt = 8;
    wire      fifo_wr = is_valid & pix_wr;
    always @(posedge clk_div or negedge mmcm_locked) begin
        if (!mmcm_locked) begin aligned<=0; pix_wr<=0; slips<=0; wcnt<=8; bitslip_r<=0; end
        else begin
            bitslip_r <= {N{1'b0}};
            if (!aligned) begin
                if (wcnt != 0) wcnt <= wcnt - 1'b1;
                else if (is_word[7:0] == PRE) aligned <= 1'b1;
                else if (slips < 8) begin bitslip_r <= {N{1'b1}}; slips <= slips+1; wcnt <= 8; end
            end else if (!pix_wr && is_word[7:0] == SNT)
                pix_wr <= 1'b1;                       // next words are pixels
        end
    end

    // ---- async CDC FIFO (clk_div -> encoder wr_clk); deep to absorb SOF stretch ----
    wire clk_enc, sys_rdy;
    wire [N*8-1:0]  s_tdata;  wire s_tvalid, s_tready;
    wire cdc_rempty;
    gearbox_afifo #(.DW(N*8), .AW(12)) u_cdc (
        .arstn(rstn),
        .wclk(clk_div), .winc(fifo_wr),          .wdata(is_word), .wfull(),
        .rclk(clk_enc), .rinc(s_tvalid&s_tready), .rdata(s_tdata), .rempty(cdc_rempty)
    );
    assign s_tvalid = ~cdc_rempty;
    assign clk = clk_enc;

    // ---- one-shot SOF + fixed dims, generated on the encoder clock after sys_rdy ----
    reg [1:0] sof_state = 0;  reg i_sof = 0;
    always @(posedge clk_enc or negedge rstn) begin
        if (!rstn) begin sof_state <= 0; i_sof <= 0; end
        else case (sof_state)
            2'd0: if (sys_rdy) sof_state <= 2'd1;
            2'd1: begin i_sof <= 1'b1; sof_state <= 2'd2; end
            2'd2: begin i_sof <= 1'b0; sof_state <= 2'd3; end
            default: ;
        endcase
    end

    wire [N*16-1:0] m_tdata;  wire [N-1:0] m_tvalid, m_tlast, m_tready;
    // Encoder takes its 45 MHz from the top MMCM (EXT_CLK=1) — the board's single diff
    // clock is buffered once (u_ibufds) for the MMCM, so the encoder must NOT re-buffer it.
    jls_encoder_axis #(.N_E(N), .N_H(N), .N_V(1), .EXT_CLK(1)) u_enc (
        .rstn(rstn), .clk(clk_enc), .clk_in1_p(1'b0), .clk_in1_n(1'b0),
        .ext_clk(clk_div), .ext_locked(mmcm_locked),
        .sys_rdy(sys_rdy), .i_sof(i_sof), .i_w(IMG_W[15:0]), .i_h(IMG_H[13:0]),
        .s_axis_tdata(s_tdata), .s_axis_tvalid(s_tvalid), .s_axis_tready(s_tready),
        .s_axis_tlast(1'b0),
        .m_axis_tdata(m_tdata), .m_axis_tvalid(m_tvalid), .m_axis_tready(m_tready),
        .m_axis_tlast(m_tlast)
    );

    wire [31:0] total_words, checksum;
    axis_sink #(.N_E(N)) u_sink (
        .clk(clk_enc), .rstn(sys_rdy),
        .m_axis_tdata(m_tdata), .m_axis_tvalid(m_tvalid),
        .m_axis_tready(m_tready), .m_axis_tlast(m_tlast),
        .total_words(total_words), .checksum(checksum), .done(done));
    assign status = checksum[30:0];
endmodule
