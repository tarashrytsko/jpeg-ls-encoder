`timescale 1ps/1ps
`default_nettype wire

// tb_jls_wide — drives the wide 16-lane jls_encoder_axis DUT with a
// column-strided 128-bit feed (one word per cycle, byte k = strip k pixel).
// Input side reads a pre-generated strided .hex (see tools/make_strided_hex.py);
// output capture/EOI/benchmark machinery is reused from tb_jls_encoder_axis.
module tb_jls_wide #(
    parameter integer N_E        = 16,
    parameter integer N_H        = 16,
    parameter integer N_V        = 1,
    parameter integer NUM_SLICES = 1,
    parameter integer MAX_BYTES_PER_SLICE = 300000,
    parameter integer LB_DEPTH = 1024,   // line-buffer depth; horizontal (N_H=1) needs >= IMG_W
    parameter HEXFILE = "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f/JPEG_ENC_8f.sim/images/wide_256_strided.hex",
    parameter integer IMG_W = 256,
    parameter integer IMG_H = 256
) ();

    // ------------------------------------------------------------
    // Clock & Reset
    // ------------------------------------------------------------
    reg rstn = 0;
    reg clk_in1_p = 0;
    reg clk_in1_n = 1;

    always #2500 clk_in1_p = ~clk_in1_p;
    always #2500 clk_in1_n = ~clk_in1_n;

    initial begin
        repeat (5) @(posedge clk_in1_p);
        rstn = 1;
    end

    // ---- DUT I/O ----
    reg  i_sof = 0;
    reg  [15:0] i_w = 0;
    reg  [13:0] i_h = 0;
    wire clk;
    wire sys_rdy;

    reg  [N_E*8-1:0] s_axis_tdata  = 0;
    reg              s_axis_tvalid = 0;
    wire             s_axis_tready;
    reg              s_axis_tlast  = 0;

    wire [N_E*16-1:0] m_axis_tdata;
    wire [N_E-1:0]    m_axis_tvalid;
    wire [N_E-1:0]    m_axis_tready_w = {N_E{1'b1}};  // always-ready sink
    wire [N_E-1:0]    m_axis_tlast;

    // capture aliases so the reused capture logic keeps its names
    wire [N_E-1:0]    o_e    = m_axis_tvalid;
    wire [N_E*16-1:0] o_data = m_axis_tdata;
    wire [N_E-1:0]    o_last = m_axis_tlast;

    jls_encoder_axis #(.N_E(N_E), .N_H(N_H), .N_V(N_V), .LB_DEPTH(LB_DEPTH)) dut (
        .rstn          (rstn),
        .clk           (clk),
        .clk_in1_p     (clk_in1_p),
        .clk_in1_n     (clk_in1_n),
        .sys_rdy       (sys_rdy),
        .i_sof         (i_sof),
        .i_w           (i_w),
        .i_h           (i_h),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        .s_axis_tlast  (s_axis_tlast),
        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tready (m_axis_tready_w),
        .m_axis_tlast  (m_axis_tlast)
    );

    // ------------------------------------------------------------
    // Wide strided feed (replaces the PGM byte-streaming driver):
    // load the strided hex into memory and stream one 128-bit word per
    // accepted cycle. Byte k of each word is strip k's pixel.
    // ------------------------------------------------------------
    localparam integer SW     = IMG_W / N_H;     // per-lane strip width
    localparam integer SH     = IMG_H / N_V;     // per-lane strip height
    localparam integer NWORDS = SW * SH;         // strided words (grid-aware; = W*H/N_E)
    reg [N_E*8-1:0] feed [0:NWORDS-1];
    integer p;
    initial $readmemh(HEXFILE, feed);
    initial begin
        wait (sys_rdy);
        @(posedge clk);
        i_w = IMG_W[15:0];
        i_h = IMG_H[13:0];
        @(posedge clk);
        i_sof = 1; @(posedge clk); i_sof = 0;
        for (p = 0; p < NWORDS; p = p + 1) begin
            s_axis_tdata  = feed[p];
            s_axis_tvalid = 1;
            s_axis_tlast  = (p == NWORDS-1);
            @(posedge clk);
            while (!s_axis_tready) @(posedge clk);
        end
        s_axis_tvalid = 0; s_axis_tlast = 0;
    end

    // ------------------------------------------------------------
    // Output capture: buffer all slices in memory, write single file
    // ------------------------------------------------------------
    reg [7:0] slice_buf [0:N_E-1][0:NUM_SLICES-1][0:MAX_BYTES_PER_SLICE-1];
    integer   slice_len [0:N_E-1][0:NUM_SLICES-1];

    reg [15:0] slice  [0:N_E-1];
    reg       closed  [0:N_E-1];
    integer   word_cnt[0:N_E-1];
    integer   total_bytes[0:N_E-1];

    reg [8*256-1:0] basepath;

    integer ei, si, bi;
    integer fout, total_out;
    reg [8*256-1:0] outpath;

    initial begin
        basepath = "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f/JPEG_ENC_8f.sim/output_block/";
        for (ei = 0; ei < N_E; ei = ei + 1) begin
            slice[ei]       = 0;
            closed[ei]      = 0;
            word_cnt[ei]    = 0;
            total_bytes[ei] = 0;
            for (si = 0; si < NUM_SLICES; si = si + 1)
                slice_len[ei][si] = 0;
        end
        $display("[%0t] Output capture ready (in-memory buffers)", $time);
    end

    // ------------------------------------------------------------
    // Write + slice management
    // ------------------------------------------------------------
    integer wi;
    reg [7:0] last_byte [0:N_E-1];

    initial begin
        for (wi = 0; wi < N_E; wi = wi + 1)
            last_byte[wi] = 0;
    end

    task do_close(input integer enc_idx);
        integer cur_sl;
        begin
            cur_sl = slice[enc_idx];
            $display("[%0t] SLICE enc%0d[%0d] done: words=%0d bytes=%0d",
                     $time, enc_idx, cur_sl, word_cnt[enc_idx], slice_len[enc_idx][cur_sl]);
            slice[enc_idx] = slice[enc_idx] + 1;
            if (slice[enc_idx] < NUM_SLICES) begin
                word_cnt[enc_idx] = 0;
            end else begin
                closed[enc_idx] = 1;
                $display("[%0t] DONE enc%0d total_bytes=%0d", $time, enc_idx, total_bytes[enc_idx]);
            end
        end
    endtask

    always @(posedge clk) begin
        for (wi = 0; wi < N_E; wi = wi + 1) begin
            if (!closed[wi] && o_e[wi] && m_axis_tready_w[wi]) begin   // capture on AXIS transfer (tvalid&&tready)
                // Buffer MSB then LSB
                slice_buf[wi][slice[wi]][slice_len[wi][slice[wi]]]   = o_data[wi*16+8 +: 8];
                slice_buf[wi][slice[wi]][slice_len[wi][slice[wi]]+1] = o_data[wi*16    +: 8];
                slice_len[wi][slice[wi]] = slice_len[wi][slice[wi]] + 2;
                word_cnt[wi]    = word_cnt[wi]    + 1;
                total_bytes[wi] = total_bytes[wi] + 2;

                // Detect EOI (FFD9): within word or spanning words
                if (o_data[wi*16+8 +: 8] == 8'hFF && o_data[wi*16 +: 8] == 8'hD9) begin
                    do_close(wi);
                end else if (last_byte[wi] == 8'hFF && o_data[wi*16+8 +: 8] == 8'hD9) begin
                    // FF from prev word, D9 is MSB of this word
                    // LSB of this word is encoder padding (0x00) — trim it
                    slice_len[wi][slice[wi]] = slice_len[wi][slice[wi]] - 1;
                    total_bytes[wi] = total_bytes[wi] - 1;
                    do_close(wi);
                end

                last_byte[wi] <= o_data[wi*16 +: 8];
            end
        end
    end

    // ------------------------------------------------------------
    // End simulation when all encoders done
    // ------------------------------------------------------------
    reg all_done;
    integer ci;
    always @(*) begin
        all_done = 1;
        for (ci = 0; ci < N_E; ci = ci + 1)
            if (!closed[ci]) all_done = 0;
    end

    // ------------------------------------------------------------
    // Watchdog: simple local cycle counter (no probes into dut internals)
    // ------------------------------------------------------------
    integer wd;
    initial wd = 0;
    always @(posedge clk) begin
        wd <= wd + 1;
        if (wd > 5000000) begin
            $display("WATCHDOG");
            $finish;
        end
    end


    // Write concatenated output.jls then finish
    initial begin
        wait(all_done);
        repeat (50) @(posedge clk);

        // Geometry-tagged name (use IMG_W/IMG_H, not i_w probes)
        $sformat(outpath, "%0soutput_h%0dv%0d_%0dx%0d.jls", basepath, N_H, N_V, IMG_W, IMG_H);
        fout = $fopen(outpath, "wb");
        if (!fout) begin
            $display("*** ERROR: cannot open %0s", outpath);
            $finish;
        end
        total_out = 0;
        // Order: swath-major, encoder-minor
        for (si = 0; si < NUM_SLICES; si = si + 1)
            for (ei = 0; ei < N_E; ei = ei + 1)
                for (bi = 0; bi < slice_len[ei][si]; bi = bi + 1) begin
                    $fwrite(fout, "%c", slice_buf[ei][si][bi]);
                    total_out = total_out + 1;
                end
        $fclose(fout);
        $display("[%0t] %0s written: %0d bytes (%0d slices, swath-major enc-minor order)",
                 $time, outpath, total_out, N_E * NUM_SLICES);
        $display("=== All %0d encoder slices complete ===", N_E * NUM_SLICES);
        // Single machine-parseable line for the benchmark sweep script:
        $display("BENCHMARK_RESULT N_H=%0d N_V=%0d W=%0d H=%0d N_E=%0d NUM_SLICES=%0d OUT_BYTES=%0d",
                 N_H, N_V, IMG_W, IMG_H, N_E, NUM_SLICES, total_out);
        $finish;
    end

endmodule
