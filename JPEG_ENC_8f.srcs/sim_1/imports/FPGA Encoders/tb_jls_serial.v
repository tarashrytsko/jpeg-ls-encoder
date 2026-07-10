`timescale 1ps/1ps
`default_nettype wire
// tb_jls_serial — END-TO-END serial-in demo:
//   strided byte stream (1 byte/cycle @ 540 MHz) -> byte_gearbox_12 -> 12-byte words
//   @ 45 MHz -> jls_encoder_axis (N_E=12, vertical 12x1) -> 12 compressed lanes.
// The gearbox's slow clock IS the DUT's wr_clk (`clk`); its fast clock is an
// independent 540 MHz TB clock, so the async-FIFO CDC is genuinely exercised, and
// the full backpressure chain (s_axis_tready -> o_ready -> FIFO full -> i_ready)
// throttles the serial input. Output is captured/verified exactly like tb_jls_wide;
// it must match the parallel-fed result (lossless).
module tb_jls_serial #(
    parameter integer N_E        = 12,
    parameter integer N_H        = 12,
    parameter integer N_V        = 1,
    parameter integer NUM_SLICES = 1,
    parameter integer MAX_BYTES_PER_SLICE = 1200000,
    parameter HEXFILE = "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f/JPEG_ENC_8f.sim/images/vert12x1_300.hex",
    parameter integer IMG_W = 300,
    parameter integer IMG_H = 300
) ();
    // ---- clocks / reset ----
    reg clk_in1_p = 0, clk_in1_n = 1;   // 200 MHz diff -> DUT clk_wiz -> wr_clk 45 MHz
    reg clk_fast  = 0;                  // 540 MHz serial-byte clock (~539.9 MHz)
    always #2500 clk_in1_p = ~clk_in1_p;
    always #2500 clk_in1_n = ~clk_in1_n;
    always #926  clk_fast  = ~clk_fast;

    reg rstn = 0;
    initial begin repeat (5) @(posedge clk_in1_p); rstn = 1; end

    // ---- DUT I/O ----
    reg  i_sof = 0;
    reg  [15:0] i_w = 0;
    reg  [13:0] i_h = 0;
    wire clk;                            // wr_clk out of the DUT (= gearbox clk_slow)
    wire sys_rdy;

    wire [N_E*8-1:0]  s_axis_tdata;
    wire              s_axis_tvalid;
    wire              s_axis_tready;

    wire [N_E*16-1:0] m_axis_tdata;
    wire [N_E-1:0]    m_axis_tvalid;
    wire [N_E-1:0]    m_axis_tready_w = {N_E{1'b1}};
    wire [N_E-1:0]    m_axis_tlast;

    wire [N_E-1:0]    o_e    = m_axis_tvalid;
    wire [N_E*16-1:0] o_data = m_axis_tdata;

    jls_encoder_axis #(.N_E(N_E), .N_H(N_H), .N_V(N_V)) dut (
        .rstn(rstn), .clk(clk), .clk_in1_p(clk_in1_p), .clk_in1_n(clk_in1_n),
        .sys_rdy(sys_rdy), .i_sof(i_sof), .i_w(i_w), .i_h(i_h),
        .s_axis_tdata(s_axis_tdata), .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready), .s_axis_tlast(1'b0),
        .m_axis_tdata(m_axis_tdata), .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready_w), .m_axis_tlast(m_axis_tlast)
    );

    // ---- serial byte source (strided order) + gearbox ----
    localparam integer SW     = IMG_W / N_H;
    localparam integer SH     = IMG_H / N_V;
    localparam integer NWORDS = SW * SH;              // = IMG_W*IMG_H/N_E
    reg [N_E*8-1:0] feed [0:NWORDS-1];
    initial $readmemh(HEXFILE, feed);

    reg  [31:0] fw, fk;
    reg         gb_i_valid;
    reg         started;              // set once sys_rdy is cleanly high
    wire        gb_i_ready;
    wire [7:0]  gb_i_byte = (fw < NWORDS) ? feed[fw][fk*8 +: 8] : 8'd0;

    // fast-domain serial feed, byte fk of word fw (byte 0 first = lane 0).
    // Reset on the CLEAN rstn (sys_rdy is X->1 with no defined 0, so it cannot
    // be used as an async reset); gate the byte stream on `started` (registered
    // from sys_rdy so it stays 0 until sys_rdy is definitively high).
    always @(posedge clk_fast or negedge rstn) begin
        if (!rstn) begin
            fw <= 0; fk <= 0; gb_i_valid <= 1'b0; started <= 1'b0;
        end else begin
            if (sys_rdy) started <= 1'b1;
            gb_i_valid <= started & (fw < NWORDS);
            if (gb_i_valid & gb_i_ready) begin
                if (fk == N_E-1) begin fk <= 0; fw <= fw + 1; end
                else                  fk <= fk + 1;
            end
        end
    end

    byte_gearbox_12 #(.N(N_E), .AW(4)) u_gb (
        .rstn(rstn),
        .clk_fast(clk_fast), .i_valid(gb_i_valid), .i_byte(gb_i_byte), .i_ready(gb_i_ready),
        .clk_slow(clk),
        .o_b0(),.o_b1(),.o_b2(),.o_b3(),.o_b4(),.o_b5(),
        .o_b6(),.o_b7(),.o_b8(),.o_b9(),.o_b10(),.o_b11(),
        .o_word(s_axis_tdata), .o_valid(s_axis_tvalid), .o_ready(s_axis_tready)
    );

    // ---- sideband (wr_clk domain): set dims, one-shot SOF ----
    initial begin
        wait (sys_rdy);
        @(posedge clk);
        i_w = IMG_W[15:0];
        i_h = IMG_H[13:0];
        @(posedge clk);
        i_sof = 1; @(posedge clk); i_sof = 0;
    end

    // ---- output capture (identical scheme to tb_jls_wide) ----
    reg [7:0]  slice_buf [0:N_E-1][0:NUM_SLICES-1][0:MAX_BYTES_PER_SLICE-1];
    integer    slice_len [0:N_E-1][0:NUM_SLICES-1];
    reg [15:0] slice  [0:N_E-1];
    reg        closed  [0:N_E-1];
    integer    word_cnt[0:N_E-1];
    integer    total_bytes[0:N_E-1];
    reg [8*256-1:0] basepath;
    integer ei, si, bi, fout, total_out;
    reg [8*256-1:0] outpath;
    integer wi;
    reg [7:0] last_byte [0:N_E-1];

    initial begin
        basepath = "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f/JPEG_ENC_8f.sim/output_block/";
        for (ei = 0; ei < N_E; ei = ei + 1) begin
            slice[ei]=0; closed[ei]=0; word_cnt[ei]=0; total_bytes[ei]=0; last_byte[ei]=0;
            for (si = 0; si < NUM_SLICES; si = si + 1) slice_len[ei][si]=0;
        end
    end

    task do_close(input integer enc_idx);
        integer cur_sl;
        begin
            cur_sl = slice[enc_idx];
            slice[enc_idx] = slice[enc_idx] + 1;
            if (slice[enc_idx] < NUM_SLICES) word_cnt[enc_idx] = 0;
            else begin
                closed[enc_idx] = 1;
                $display("[%0t] DONE enc%0d total_bytes=%0d", $time, enc_idx, total_bytes[enc_idx]);
            end
        end
    endtask

    always @(posedge clk) begin
        for (wi = 0; wi < N_E; wi = wi + 1) begin
            if (!closed[wi] && o_e[wi] && m_axis_tready_w[wi]) begin
                slice_buf[wi][slice[wi]][slice_len[wi][slice[wi]]]   = o_data[wi*16+8 +: 8];
                slice_buf[wi][slice[wi]][slice_len[wi][slice[wi]]+1] = o_data[wi*16    +: 8];
                slice_len[wi][slice[wi]] = slice_len[wi][slice[wi]] + 2;
                word_cnt[wi]    = word_cnt[wi] + 1;
                total_bytes[wi] = total_bytes[wi] + 2;
                if (o_data[wi*16+8 +: 8] == 8'hFF && o_data[wi*16 +: 8] == 8'hD9) do_close(wi);
                else if (last_byte[wi] == 8'hFF && o_data[wi*16+8 +: 8] == 8'hD9) begin
                    slice_len[wi][slice[wi]] = slice_len[wi][slice[wi]] - 1;
                    total_bytes[wi] = total_bytes[wi] - 1;
                    do_close(wi);
                end
                last_byte[wi] <= o_data[wi*16 +: 8];
            end
        end
    end

    reg all_done; integer ci;
    always @(*) begin
        all_done = 1;
        for (ci = 0; ci < N_E; ci = ci + 1) if (!closed[ci]) all_done = 0;
    end

    integer wd; initial wd = 0;
    always @(posedge clk_fast) begin
        wd <= wd + 1;
        if (wd % 2000000 == 0)
            $display("[%0t] progress fw=%0d/%0d", $time, fw, NWORDS);
        if (wd > 12*NWORDS*3 + 5000000) begin $display("WATCHDOG fw=%0d/%0d", fw, NWORDS); $finish; end
    end

    initial begin
        wait (all_done);
        repeat (50) @(posedge clk);
        $sformat(outpath, "%0soutput_serial_h%0dv%0d_%0dx%0d.jls", basepath, N_H, N_V, IMG_W, IMG_H);
        fout = $fopen(outpath, "wb");
        total_out = 0;
        for (si = 0; si < NUM_SLICES; si = si + 1)
            for (ei = 0; ei < N_E; ei = ei + 1)
                for (bi = 0; bi < slice_len[ei][si]; bi = bi + 1) begin
                    $fwrite(fout, "%c", slice_buf[ei][si][bi]); total_out = total_out + 1;
                end
        $fclose(fout);
        $display("SERIAL_RESULT N_H=%0d N_V=%0d W=%0d H=%0d N_E=%0d OUT_BYTES=%0d",
                 N_H, N_V, IMG_W, IMG_H, N_E, total_out);
        $finish;
    end
endmodule
