`timescale 1ps/1ps
`default_nettype wire

// tb_jls_demo_wide — drives the self-contained jls_demo_top end-to-end:
// on-chip axis_image_source (ROM) -> jls_encoder_axis (16 lanes) -> axis_sink.
// Captures the 16 per-lane compressed outputs from the INTERNAL IP->sink wires
// (dut.m_tdata / dut.m_tvalid / dut.m_tlast) via hierarchical reference, using
// the slice/EOI/benchmark capture machinery from tb_jls_wide.v. This proves the
// on-chip axis_image_source feeds the encoder correctly (byte-for-byte vs ref).
module tb_jls_demo_wide #(
    parameter integer N_E        = 16,
    parameter integer NUM_SLICES = 1,
    parameter integer MAX_BYTES_PER_SLICE = 300000
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

    // ---- DUT ----
    wire        clk;
    wire        done;
    wire [30:0] status;

    jls_demo_top #(.N_E(N_E), .N_H(16), .N_V(1), .IMG_W(256), .IMG_H(256)) dut (
        .rstn      (rstn),
        .clk_in1_p (clk_in1_p),
        .clk_in1_n (clk_in1_n),
        .clk       (clk),
        .done      (done),
        .status    (status)
    );

    // capture aliases via hierarchical refs to the internal IP->sink wires.
    // The sink ties m_tready high, so every m_tvalid beat is a transfer:
    // capture on o_e[wi] alone.
    wire [N_E-1:0]    o_e    = dut.m_tvalid;
    wire [N_E*16-1:0] o_data = dut.m_tdata;
    wire [N_E-1:0]    o_last = dut.m_tlast;

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
            if (!closed[wi] && o_e[wi]) begin   // sink ties tready=1, so o_e==transfer
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

        $sformat(outpath, "%0soutput_demo_wide_256x256.jls", basepath);
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
                 16, 1, 256, 256, N_E, NUM_SLICES, total_out);
        $finish;
    end

endmodule
