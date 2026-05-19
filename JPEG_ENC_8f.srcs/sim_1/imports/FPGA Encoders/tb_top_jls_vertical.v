`timescale 1ps/1ps
`default_nettype wire

module tb_top_jls_vertical;

    localparam N_E = 6;
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
    integer wi;
    always @(posedge clk) begin
        for (wi = 0; wi < N_E; wi = wi + 1) begin
            if (!closed[wi]) begin
                if (o_e[wi]) begin
                    $fwrite(f[wi], "%c", o_data[wi*16+8 +: 8]);
                    $fwrite(f[wi], "%c", o_data[wi*16 +: 8]);
                    word_cnt[wi] = word_cnt[wi] + 1;
                    byte_cnt[wi] = byte_cnt[wi] + 2;
                    total_bytes[wi] = total_bytes[wi] + 2;
                end

                if (o_last[wi] && !prev_last[wi]) begin
                    $display("[%0t] CLOSE enc%0d%c.jls words=%0d bytes=%0d",
                             $time, wi, slice_letter(slice[wi]), word_cnt[wi], byte_cnt[wi]);
                    $fclose(f[wi]);
                    slice[wi] = slice[wi] + 1;

                    if (slice[wi] < NUM_SLICES) begin
                        word_cnt[wi] = 0;
                        byte_cnt[wi] = 0;
                        $sformat(fname, "%0senc%0d%c.jls", basepath, wi, slice_letter(slice[wi]));
                        f[wi] = $fopen(fname, "wb");
                        if (!f[wi]) begin
                            $display("*** ERROR: cannot open %s", fname);
                            $finish;
                        end
                        $display("[%0t] OPEN enc%0d%c.jls", $time, wi, slice_letter(slice[wi]));
                    end else begin
                        closed[wi] = 1;
                        $display("[%0t] DONE enc%0d total_bytes=%0d", $time, wi, total_bytes[wi]);
                    end
                end
            end
            prev_last[wi] <= o_last[wi];
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

endmodule
