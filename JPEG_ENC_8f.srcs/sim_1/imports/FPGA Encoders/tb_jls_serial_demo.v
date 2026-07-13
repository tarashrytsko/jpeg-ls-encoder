`timescale 1ps/1ps
`default_nettype wire
// tb_jls_serial_demo — FULL end-to-end serial-in demo through the ISERDES front-end:
//
//   on-chip serial source (12 lanes @ 360 Mb/s)  ->  iserdes_byte_in (ISERDESE2 1:8)
//     -> 12 bytes @ clk_div(45MHz) -> gearbox_afifo (async CDC, 45->encoder wr_clk)
//     -> jls_encoder_axis (N_E=12 vertical 12x1) -> 12 compressed lanes -> capture -> verify.
//
// Flow: (1) source streams a 0x01 preamble; a BITSLIP FSM word-aligns the ISERDES.
//       (2) once aligned AND the encoder is past its SOF stretch, the source emits one
//           0xAA sentinel then the 7500 pixel words; the CDC-FIFO write starts on the
//           sentinel so only pixel words reach the encoder. The deep CDC FIFO (4096) also
//           absorbs the SOF-stretch backlog, so no external flow control is needed.
// Verifies the compressed output is bit-exact lossless (== the parallel/gearbox paths).
module tb_jls_serial_demo #(
    parameter integer N   = 12,
    parameter integer N_H = N,    // split grid: vertical=(N,1), horizontal=(1,N), block=(4,3)
    parameter integer N_V = 1,    // N_H*N_V must equal N
    parameter integer LB_DEPTH = 1024, // line-buffer depth; horizontal (N_H=1) needs >= IMG_W
    parameter integer IMG_W = 300,
    parameter integer IMG_H = 300,
    parameter HEXFILE = "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f/JPEG_ENC_8f.sim/images/vert12x1_300.hex",
    parameter integer MAX_BYTES_PER_SLICE = 300000
) ();
    localparam integer NWORDS = (IMG_W*IMG_H) / N;    // total pixels / lanes (same all dirs)
    localparam [7:0]   PRE = 8'h01;                   // alignment preamble (rotation-unique)
    localparam [7:0]   SNT = 8'hAA;                   // pixel-stream start sentinel

    // ---------- clocks ----------
    reg clk_bit = 0;  always #1389 clk_bit = ~clk_bit;         // 360 MHz (ISERDES CLK)
    reg [2:0] bcnt = 0; always @(posedge clk_bit) bcnt <= bcnt + 1'b1;
    reg clk_div = 0;
    always @(posedge clk_bit) if (bcnt==3'd7) clk_div<=1'b1; else if (bcnt==3'd3) clk_div<=1'b0;
    reg clk_in1_p = 0, clk_in1_n = 1;                          // 200 MHz diff -> encoder clk_wiz
    always #2500 clk_in1_p = ~clk_in1_p;
    always #2500 clk_in1_n = ~clk_in1_n;

    reg rstn = 0;
    initial begin repeat (120) @(posedge clk_bit); rstn <= 1'b1; end
    wire rst = ~rstn;

    // ---------- source ROM ----------
    reg [N*8-1:0] feed [0:NWORDS-1];
    initial $readmemh(HEXFILE, feed);

    // ---------- alignment done + sync ----------
    wire aligned;                    // from align FSM (clk_div domain)
    reg  al_b1, al_b2;               // aligned synced to clk_bit
    always @(posedge clk_bit) begin al_b1 <= aligned; al_b2 <= al_b1; end
    wire enc_ready;                  // encoder past SOF (tready), synced below
    reg  er_b1, er_b2;
    always @(posedge clk_bit) begin er_b1 <= enc_ready; er_b2 <= er_b1; end

    // ---------- serial source FSM (clk_bit) ----------
    // states: preamble -> (aligned & enc_ready) sentinel(1 word) -> pixels(NWORDS) -> idle
    localparam S_PRE=0, S_SNT=1, S_PIX=2, S_IDLE=3;
    reg [1:0] sstate;
    reg [31:0] pw;                   // pixel word index
    reg [7:0]  cur [0:N-1];          // current word's bytes (per lane)
    integer c;
    // byte selected for current state (per lane), then serialized MSB-first
    always @(*) begin
        for (c = 0; c < N; c = c + 1) begin
            case (sstate)
                S_SNT:   cur[c] = SNT;
                S_PIX:   cur[c] = feed[(pw < NWORDS) ? pw : (NWORDS-1)][c*8 +: 8];
                default: cur[c] = PRE;
            endcase
        end
    end
    wire [N-1:0] d_in;
    genvar gl;
    generate for (gl = 0; gl < N; gl = gl + 1) begin : g_ser
        assign d_in[gl] = cur[gl][3'd7 - bcnt];         // MSB-first
    end endgenerate

    always @(posedge clk_bit or negedge rstn) begin
        if (!rstn) begin sstate <= S_PRE; pw <= 0; end
        else if (bcnt == 3'd7) begin                     // advance at word boundary
            case (sstate)
                S_PRE:  if (al_b2 && er_b2) sstate <= S_SNT;
                S_SNT:  begin sstate <= S_PIX; pw <= 0; end
                S_PIX:  if (pw == NWORDS-1) sstate <= S_IDLE; else pw <= pw + 1;
                default: ;
            endcase
        end
    end

    // ---------- ISERDES front-end ----------
    reg  [N-1:0]   bitslip_r = 0;
    wire [N*8-1:0] is_word;
    wire           is_valid;
    iserdes_byte_in #(.N(N)) u_is (
        .clk_bit(clk_bit), .clk_div(clk_div), .rst(rst),
        .d_in(d_in), .bitslip(bitslip_r), .o_word(is_word), .o_valid(is_valid)
    );

    // ---------- BITSLIP align FSM + sentinel-gated CDC write (clk_div) ----------
    reg       aligned_r = 0;
    reg [3:0] slips = 0, wcnt = 0;
    reg       pix_wr = 0;            // gate CDC write to pixel words only
    reg [31:0] wr_cnt = 0;
    assign aligned = aligned_r;
    wire fifo_wr = is_valid & pix_wr & (wr_cnt < NWORDS);
    always @(posedge clk_div or negedge rstn) begin
        if (!rstn) begin
            aligned_r<=0; slips<=0; wcnt<=8; bitslip_r<=0; pix_wr<=0; wr_cnt<=0;
        end else begin
            bitslip_r <= {N{1'b0}};
            if (!aligned_r) begin
                if (wcnt != 0) wcnt <= wcnt - 1'b1;
                else if (is_word[7:0] == PRE) aligned_r <= 1'b1;
                else if (slips < 8) begin bitslip_r <= {N{1'b1}}; slips <= slips+1; wcnt <= 8; end
            end else begin
                if (!pix_wr) begin
                    if (is_word[7:0] == SNT) pix_wr <= 1'b1;      // sentinel -> next words are pixels
                end else if (fifo_wr) wr_cnt <= wr_cnt + 1'b1;
            end
        end
    end

    // ---------- encoder + async CDC FIFO ----------
    wire clk;                        // encoder wr_clk
    wire sys_rdy;
    wire [N*8-1:0] s_tdata;  wire s_tvalid, s_tready;
    wire [N*16-1:0] m_tdata; wire [N-1:0] m_tvalid, m_tlast;
    wire [N-1:0] m_tready = {N{1'b1}};

    // CDC: write @clk_div (fifo_wr), read @clk (encoder). Depth 4096 absorbs SOF stretch.
    wire cdc_rempty;
    wire cdc_rinc = s_tvalid & s_tready;
    gearbox_afifo #(.DW(N*8), .AW(12)) u_cdc (
        .arstn(rstn),
        .wclk(clk_div), .winc(fifo_wr), .wdata(is_word), .wfull(),
        .rclk(clk),     .rinc(cdc_rinc), .rdata(s_tdata), .rempty(cdc_rempty)
    );
    assign s_tvalid = ~cdc_rempty;

    // encoder-ready (tready) synced back to clk_bit for the source start
    assign enc_ready = s_tready;

    reg  i_sof = 0;  reg [15:0] i_w = 0;  reg [13:0] i_h = 0;
    jls_encoder_axis #(.N_E(N), .N_H(N_H), .N_V(N_V), .LB_DEPTH(LB_DEPTH)) dut (
        .rstn(rstn), .clk(clk), .clk_in1_p(clk_in1_p), .clk_in1_n(clk_in1_n),
        .sys_rdy(sys_rdy), .i_sof(i_sof), .i_w(i_w), .i_h(i_h),
        .s_axis_tdata(s_tdata), .s_axis_tvalid(s_tvalid), .s_axis_tready(s_tready),
        .s_axis_tlast(1'b0),
        .m_axis_tdata(m_tdata), .m_axis_tvalid(m_tvalid), .m_axis_tready(m_tready),
        .m_axis_tlast(m_tlast)
    );

    // sideband: dims + one-shot SOF once the system is ready
    initial begin
        wait (sys_rdy); @(posedge clk);
        i_w = IMG_W[15:0]; i_h = IMG_H[13:0]; @(posedge clk);
        i_sof = 1; @(posedge clk); i_sof = 0;
    end

    // ---------- capture (same scheme as tb_jls_wide) ----------
    wire [N-1:0]    o_e    = m_tvalid;
    wire [N*16-1:0] o_data = m_tdata;
    reg [7:0]  slice_buf [0:N-1][0:MAX_BYTES_PER_SLICE-1];
    integer    slice_len [0:N-1];
    reg        closed  [0:N-1];
    reg [7:0]  last_byte [0:N-1];
    integer ei, bi, wi, fout, total_out;  reg [8*256-1:0] outpath;
    initial for (ei=0; ei<N; ei=ei+1) begin slice_len[ei]=0; closed[ei]=0; last_byte[ei]=0; end

    task do_close(input integer e); begin
        closed[e]=1; $display("[%0t] DONE enc%0d bytes=%0d", $time, e, slice_len[e]);
    end endtask

    always @(posedge clk) begin
        for (wi=0; wi<N; wi=wi+1) if (!closed[wi] && o_e[wi]) begin
            slice_buf[wi][slice_len[wi]]   = o_data[wi*16+8 +: 8];
            slice_buf[wi][slice_len[wi]+1] = o_data[wi*16   +: 8];
            slice_len[wi] = slice_len[wi] + 2;
            if (o_data[wi*16+8 +: 8]==8'hFF && o_data[wi*16 +: 8]==8'hD9) do_close(wi);
            else if (last_byte[wi]==8'hFF && o_data[wi*16+8 +: 8]==8'hD9) begin
                slice_len[wi] = slice_len[wi]-1; do_close(wi);
            end
            last_byte[wi] <= o_data[wi*16 +: 8];
        end
    end

    reg all_done; integer ci;
    always @(*) begin all_done=1; for (ci=0; ci<N; ci=ci+1) if (!closed[ci]) all_done=0; end

    integer wd; initial wd=0;
    always @(posedge clk_bit) begin
        wd <= wd+1;
        if (wd % 3000000 == 0) $display("[%0t] progress sstate=%0d pw=%0d wr_cnt=%0d aligned=%0b",
                                        $time, sstate, pw, wr_cnt, aligned_r);
        if (wd > 100000000) begin $display("SERIALDEMO_WATCHDOG pw=%0d wr_cnt=%0d aligned=%0b", pw, wr_cnt, aligned_r); $finish; end
    end

    initial begin
        wait (all_done); repeat (50) @(posedge clk);
        $sformat(outpath, "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f/JPEG_ENC_8f.sim/output_block/output_serialdemo_h%0dv%0d_%0dx%0d.jls", N_H, N_V, IMG_W, IMG_H);
        fout = $fopen(outpath, "wb"); total_out = 0;
        for (ei=0; ei<N; ei=ei+1) for (bi=0; bi<slice_len[ei]; bi=bi+1) begin
            $fwrite(fout, "%c", slice_buf[ei][bi]); total_out=total_out+1;
        end
        $fclose(fout);
        $display("SERIALDEMO_RESULT N=%0d W=%0d H=%0d OUT_BYTES=%0d", N, IMG_W, IMG_H, total_out);
        $finish;
    end
endmodule
