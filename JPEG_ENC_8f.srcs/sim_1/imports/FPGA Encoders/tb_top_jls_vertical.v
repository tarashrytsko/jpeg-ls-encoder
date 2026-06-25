`timescale 1ps/1ps
`default_nettype wire

// Splitting mode is selected purely by the (N_H, N_V) geometry:
//   block      : N_H>1, N_V>1   (e.g. 5 x 4)
//   vertical   : N_V=1          (cut along X only,  e.g. 20 x 1)
//   horizontal : N_H=1          (cut along Y only,  e.g.  1 x 20)
// All three keep N_E encoders and (N_H*N_V)/N_E slices each for an
// apples-to-apples comparison. Override via xelab -generic_top.
module tb_top_jls_vertical #(
    parameter integer N_E        = 2,   // known-good default (block 2x2, 2 slices/enc)
    parameter integer N_H        = 2,
    parameter integer N_V        = 2,
    parameter integer NUM_SLICES = (N_H * N_V) / N_E,
    parameter integer MAX_BYTES_PER_SLICE = 25000000
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

    // ------------------------------------------------------------
    // DUT I/O
    // ------------------------------------------------------------
    reg i_sof = 0;
    wire i_e;
    wire [7:0]  i_x;
    wire [15:0] i_w;
    wire [13:0] i_h;
    wire clk;
    wire sys_rdy;

    wire [N_E-1:0]    o_e;
    wire [N_E-1:0]    o_last;
    wire [N_E*16-1:0] o_data;

    // ------------------------------------------------------------
    // Pulse i_sof
    // ------------------------------------------------------------
    initial begin
        wait(sys_rdy);
        @(posedge clk);
        i_sof = 1;
        @(posedge clk);
        i_sof = 0;
    end

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------
    top_jls_vertical #(.N_E(N_E), .N_H(N_H), .N_V(N_V)) dut (
        .rstn       (rstn),
        .clk_in1_p  (clk_in1_p),
        .clk_in1_n  (clk_in1_n),
        .clk        (clk),
        .i_sof      (i_sof),
        .i_e        (i_e),
        .i_x        (i_x),
        .i_w        (i_w),
        .i_h        (i_h),
        .o_e        (o_e),
        .o_last     (o_last),
        .o_data     (o_data),
        .sys_rdy    (sys_rdy)
    );

    // ------------------------------------------------------------
    // Output capture: buffer all slices in memory, write single file
    // (MAX_BYTES_PER_SLICE is now a module parameter — override for large images)
    // ------------------------------------------------------------
    reg [7:0] slice_buf [0:N_E-1][0:NUM_SLICES-1][0:MAX_BYTES_PER_SLICE-1];
    integer   slice_len [0:N_E-1][0:NUM_SLICES-1];

    reg [15:0] slice  [0:N_E-1];   // was [1:0] — overflowed for NUM_SLICES>=4
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
            if (!closed[wi] && o_e[wi]) begin
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
    // Watchdog: once the read FSM reaches S_DONE (state==3) the encoders
    // should flush their final slice within a few hundred cycles. If they
    // don't, bound the hang and dump per-encoder status for diagnosis.
    // ------------------------------------------------------------
    integer drain_cnt; integer di;
    initial drain_cnt = 0;
    always @(posedge clk) begin
        if (dut.u_fifo_read_control.state == 2'd3 && !all_done)
            drain_cnt = drain_cnt + 1;
        else
            drain_cnt = 0;
        if (drain_cnt == 3000000) begin
            $display("*** WATCHDOG: read FSM DONE but not all slices closed after %0d cycles", drain_cnt);
            for (di = 0; di < N_E; di = di + 1)
                $display("    enc%0d: slice=%0d/%0d closed=%0d total_bytes=%0d",
                         di, slice[di], NUM_SLICES, closed[di], total_bytes[di]);
            $finish;
        end
    end

    // Write concatenated output.jls then finish
    initial begin
        wait(all_done);
        repeat (50) @(posedge clk);

        // Geometry-tagged name so block/vertical/horizontal runs don't clobber
        $sformat(outpath, "%0soutput_h%0dv%0d_%0dx%0d.jls", basepath, N_H, N_V, i_w, i_h);
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
                 N_H, N_V, i_w, i_h, N_E, NUM_SLICES, total_out);
        $finish;
    end

    // Debug: log first SOF and monitor key signals
    reg sof_logged;
    initial sof_logged = 0;
    always @(posedge dut.rd_clk) begin
        if (dut.u_encoder_wrapper.enc_i_sofx[0] && !sof_logged) begin
            sof_logged <= 1;
            $display("[%0t] FIRST SOF enc0: iw=%0d swath_h=%0d col0=%0d",
                $time, dut.u_encoder_wrapper.i_w,
                dut.u_encoder_wrapper.swath_h,
                dut.u_encoder_wrapper.col_w[0]);
        end
    end

    // Log first e_e output
    reg ee_logged;
    initial ee_logged = 0;
    always @(posedge dut.rd_clk) begin
        if (dut.e_e[0] && !ee_logged) begin
            ee_logged <= 1;
            $display("[%0t] FIRST e_e[0]: rd_cnt=%0d a_ii=%0d j_sof=%0d j_e=%0d a_wl=%0d",
                $time,
                dut.u_fifo_read_control.rd_cnt[0],
                dut.u_encoder_wrapper.ENC_INST[0].u_encoder.a_ii,
                dut.u_encoder_wrapper.ENC_INST[0].u_encoder.j_sof,
                dut.u_encoder_wrapper.ENC_INST[0].u_encoder.j_e,
                dut.u_encoder_wrapper.ENC_INST[0].u_encoder.a_wl);
        end
    end

    initial begin
        forever begin
            repeat(100000) @(posedge clk);
            $display("[%0t] DBG rd=%0d/%0d st=%0d e_e=%b wr=%0d/%0d full=%b pix=%0d",
                $time,
                dut.u_fifo_read_control.rd_cnt[0], dut.u_fifo_read_control.rd_cnt[1],
                dut.u_fifo_read_control.state,
                dut.e_e,
                dut.u_fifo_write_control.wr_cnt[0], dut.u_fifo_write_control.wr_cnt[1],
                dut.fifo_full,
                dut.u_image_generator.pix_cnt);
        end
    end

endmodule
