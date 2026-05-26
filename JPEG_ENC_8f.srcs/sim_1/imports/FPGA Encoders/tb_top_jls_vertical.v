`timescale 1ps/1ps
`default_nettype wire

module tb_top_jls_vertical;

    localparam N_E = 2;
    localparam NUM_SLICES = 2;

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
    wire [13:0] i_w;
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
    top_jls_vertical #(.N_E(N_E)) dut (
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
    // Output capture: 6 encoders x 2 slices = 12 files
    // ------------------------------------------------------------
    integer f [0:N_E-1];
    reg [1:0] slice [0:N_E-1];
    reg closed [0:N_E-1];
    reg prev_last [0:N_E-1];
    integer word_cnt [0:N_E-1];
    integer byte_cnt [0:N_E-1];
    integer total_bytes [0:N_E-1];

    reg [8*256-1:0] basepath;
    reg [8*256-1:0] fname;

    function [7:0] slice_letter(input [1:0] idx);
        begin
            case(idx)
                0: slice_letter = "a";
                1: slice_letter = "b";
                default: slice_letter = "a";
            endcase
        end
    endfunction

    integer ei;

    // ------------------------------------------------------------
    // Open initial files
    // ------------------------------------------------------------
    initial begin
        basepath = "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f/JPEG_ENC_8f.sim/output_block/";

        for (ei = 0; ei < N_E; ei = ei + 1) begin
            slice[ei] = 0;
            closed[ei] = 0;
            prev_last[ei] = 0;
            word_cnt[ei] = 0;
            byte_cnt[ei] = 0;
            total_bytes[ei] = 0;
        end

        // Open first slice file for each encoder
        for (ei = 0; ei < N_E; ei = ei + 1) begin
            $sformat(fname, "%0senc%0d%c.jls", basepath, ei, slice_letter(0));
            f[ei] = $fopen(fname, "wb");
            if (!f[ei]) begin
                $display("*** ERROR: Cannot open %s", fname);
                $finish;
            end
        end
        $display("[%0t] OPEN all encoder files (enc0a..enc5a)", $time);
    end

    // ------------------------------------------------------------
    // Write + slice management
    // ------------------------------------------------------------
    // Detect slice boundary by EOI marker (FFD9) at byte level
    // Track previous byte to catch FFD9 spanning across word boundaries
    integer wi;
    reg [7:0] last_byte [0:N_E-1];

    initial begin
        for (wi = 0; wi < N_E; wi = wi + 1)
            last_byte[wi] = 0;
    end

    task do_close(input integer enc_idx);
        begin
            $display("[%0t] CLOSE enc%0d%c.jls words=%0d bytes=%0d",
                     $time, enc_idx, slice_letter(slice[enc_idx]), word_cnt[enc_idx], byte_cnt[enc_idx]);
            $fclose(f[enc_idx]);
            slice[enc_idx] = slice[enc_idx] + 1;
            if (slice[enc_idx] < NUM_SLICES) begin
                word_cnt[enc_idx] = 0;
                byte_cnt[enc_idx] = 0;
                $sformat(fname, "%0senc%0d%c.jls", basepath, enc_idx, slice_letter(slice[enc_idx]));
                f[enc_idx] = $fopen(fname, "wb");
                if (!f[enc_idx]) begin
                    $display("*** ERROR: cannot open %s", fname);
                    $finish;
                end
                $display("[%0t] OPEN enc%0d%c.jls", $time, enc_idx, slice_letter(slice[enc_idx]));
            end else begin
                closed[enc_idx] = 1;
                $display("[%0t] DONE enc%0d total_bytes=%0d", $time, enc_idx, total_bytes[enc_idx]);
            end
        end
    endtask

    always @(posedge clk) begin
        for (wi = 0; wi < N_E; wi = wi + 1) begin
            if (!closed[wi] && o_e[wi]) begin
                // Each word has MSB (byte 1) and LSB (byte 0)
                // Written as: MSB first, then LSB
                $fwrite(f[wi], "%c", o_data[wi*16+8 +: 8]);
                $fwrite(f[wi], "%c", o_data[wi*16 +: 8]);
                word_cnt[wi] = word_cnt[wi] + 1;
                byte_cnt[wi] = byte_cnt[wi] + 2;
                total_bytes[wi] = total_bytes[wi] + 2;

                // Check EOI: FF D9 can be:
                // Case 1: MSB=FF, LSB=D9 (within this word)
                // Case 2: prev LSB=FF, this MSB=D9 (spanning words)
                if ((o_data[wi*16+8 +: 8] == 8'hFF && o_data[wi*16 +: 8] == 8'hD9) ||
                    (last_byte[wi] == 8'hFF && o_data[wi*16+8 +: 8] == 8'hD9)) begin
                    do_close(wi);
                end

                last_byte[wi] <= o_data[wi*16 +: 8]; // track LSB for cross-word detection
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

    initial begin
        wait(all_done);
        repeat (50) @(posedge clk);
        $display("=== All %0d encoder slices complete (%0d files total) ===", N_E, N_E * NUM_SLICES);
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
            repeat(100000) @(posedge clk); // ~1ms at 100MHz
            $display("[%0t] DBG rd=%0d/%0d st=%0d e_e=%b wr=%0d/%0d full=%b empty=%b pix=%0d s_e=%b wr_en=%b xcnt=%0d ycnt=%0d fa=%0d",
                $time,
                dut.u_fifo_read_control.rd_cnt[0], dut.u_fifo_read_control.rd_cnt[1],
                dut.u_fifo_read_control.state,
                dut.e_e,
                dut.u_fifo_write_control.wr_cnt[0], dut.u_fifo_write_control.wr_cnt[1],
                dut.fifo_full,
                dut.u_fifo_wrapper_input.GEN_FIFO[0].u_fifo_inst.empty,
                dut.u_image_generator.pix_cnt,
                dut.s_e,
                dut.u_fifo_write_control.wr_en,
                dut.u_splitter_block.x_cnt,
                dut.u_splitter_block.y_cnt,
                dut.u_splitter_block.frame_active);
        end
    end

endmodule
