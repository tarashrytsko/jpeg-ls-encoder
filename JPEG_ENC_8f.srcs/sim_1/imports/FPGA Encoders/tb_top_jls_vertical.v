`timescale 1ps/1ps
`default_nettype wire

module tb_top_jls_vertical;

    // ------------------------------------------------------------
    // Clock & Reset
    // ------------------------------------------------------------
    reg rstn = 0;
    reg clk_in1_p = 0;
    reg clk_in1_n = 1;
    integer i;

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

    wire        o_e0,    o_e1,    o_e2;
    wire        o_last0, o_last1, o_last2;
    wire [15:0] o_data0, o_data1, o_data2;

    // ------------------------------------------------------------
    // Pulse i_sof briefly
    // ------------------------------------------------------------
    initial begin
        wait(sys_rdy);
        @(posedge clk);
        i_sof = 1;
        @(posedge clk);
        i_sof = 0;
    end

    // ------------------------------------------------------------
    // DUT instance
    // ------------------------------------------------------------
    top_jls_vertical #(.N_E(3)) dut (
        .rstn       (rstn),
        .clk_in1_p  (clk_in1_p),
        .clk_in1_n  (clk_in1_n),
        .clk        (clk),

        .i_sof      (i_sof),
        .i_e        (i_e),
        .i_x        (i_x),
        .i_w        (i_w),
        .i_h        (i_h),

        .o_e0       (o_e0),
        .o_e1       (o_e1),
        .o_e2       (o_e2),

        .o_last0    (o_last0),
        .o_last1    (o_last1),
        .o_last2    (o_last2),

        .o_data0    (o_data0),
        .o_data1    (o_data1),
        .o_data2    (o_data2),

        .sys_rdy    (sys_rdy)
    );

    // ------------------------------------------------------------
    // Slice letter function
    // ------------------------------------------------------------
    function [7:0] slice_letter(input [1:0] idx);
        begin
            case(idx)
                0: slice_letter = "a";
                1: slice_letter = "b";
                2: slice_letter = "c";
                default: slice_letter = "a";
            endcase
        end
    endfunction

    // ------------------------------------------------------------
    // File handles, slice counters, marker detection
    // ------------------------------------------------------------
    integer f0, f1, f2;
    reg [1:0] slice0, slice1, slice2;
    reg closed0, closed1, closed2;
    reg prev_last0, prev_last1, prev_last2;
    reg [8*256-1:0] basepath;

    // per-file counters
    integer word0, word1, word2;
    integer byte0, byte1, byte2;

    // totals
    integer tw0, tw1, tw2;
    integer tb0, tb1, tb2;

    // marker detection for current file
    reg [7:0] lastb0, lastb1, lastb2;
    reg saw_soi0, saw_soi1, saw_soi2;
    reg saw_eoi0, saw_eoi1, saw_eoi2;
    integer soi_pos0, soi_pos1, soi_pos2;
    integer eoi_pos0, eoi_pos1, eoi_pos2;
    reg [7:0] first0_0, first1_0, first2_0, first3_0;
    reg [7:0] first0_1, first1_1, first2_1, first3_1;
    reg [7:0] first0_2, first1_2, first2_2, first3_2;

    task reset_stats_enc0;
        begin
            word0=0; byte0=0; lastb0=8'h00;
            saw_soi0=0; saw_eoi0=0; soi_pos0=-1; eoi_pos0=-1;
            first0_0=0; first1_0=0; first2_0=0; first3_0=0;
        end
    endtask
    task reset_stats_enc1;
        begin
            word1=0; byte1=0; lastb1=8'h00;
            saw_soi1=0; saw_eoi1=0; soi_pos1=-1; eoi_pos1=-1;
            first0_1=0; first1_1=0; first2_1=0; first3_1=0;
        end
    endtask
    task reset_stats_enc2;
        begin
            word2=0; byte2=0; lastb2=8'h00;
            saw_soi2=0; saw_eoi2=0; soi_pos2=-1; eoi_pos2=-1;
            first0_2=0; first1_2=0; first2_2=0; first3_2=0;
        end
    endtask

    task process_byte_enc0(input [7:0] b);
        begin
            if (byte0==0) first0_0=b;
            else if (byte0==1) first1_0=b;
            else if (byte0==2) first2_0=b;
            else if (byte0==3) first3_0=b;

            if (!saw_soi0 && (lastb0==8'hFF) && (b==8'hD8)) begin
                saw_soi0=1; soi_pos0=byte0-1;
            end
            if (!saw_eoi0 && (lastb0==8'hFF) && (b==8'hD9)) begin
                saw_eoi0=1; eoi_pos0=byte0-1;
            end
            lastb0 = b;
        end
    endtask

    task process_byte_enc1(input [7:0] b);
        begin
            if (byte1==0) first0_1=b;
            else if (byte1==1) first1_1=b;
            else if (byte1==2) first2_1=b;
            else if (byte1==3) first3_1=b;

            if (!saw_soi1 && (lastb1==8'hFF) && (b==8'hD8)) begin
                saw_soi1=1; soi_pos1=byte1-1;
            end
            if (!saw_eoi1 && (lastb1==8'hFF) && (b==8'hD9)) begin
                saw_eoi1=1; eoi_pos1=byte1-1;
            end
            lastb1 = b;
        end
    endtask

    task process_byte_enc2(input [7:0] b);
        begin
            if (byte2==0) first0_2=b;
            else if (byte2==1) first1_2=b;
            else if (byte2==2) first2_2=b;
            else if (byte2==3) first3_2=b;

            if (!saw_soi2 && (lastb2==8'hFF) && (b==8'hD8)) begin
                saw_soi2=1; soi_pos2=byte2-1;
            end
            if (!saw_eoi2 && (lastb2==8'hFF) && (b==8'hD9)) begin
                saw_eoi2=1; eoi_pos2=byte2-1;
            end
            lastb2 = b;
        end
    endtask

    // ------------------------------------------------------------
    // Open initial files
    // ------------------------------------------------------------
    initial begin
basepath = "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f/JPEG_ENC_8f.sim/output_block/";

        slice0=0; slice1=0; slice2=0;
        closed0=0; closed1=0; closed2=0;
        prev_last0=0; prev_last1=0; prev_last2=0;
        tw0=0; tw1=0; tw2=0;
        tb0=0; tb1=0; tb2=0;

        reset_stats_enc0();
        reset_stats_enc1();
        reset_stats_enc2();

        f0 = $fopen({basepath,"enc","0",slice_letter(slice0),".jls"},"wb");
        f1 = $fopen({basepath,"enc","1",slice_letter(slice1),".jls"},"wb");
        f2 = $fopen({basepath,"enc","2",slice_letter(slice2),".jls"},"wb");

        if (!f0 || !f1 || !f2) begin
            $display("*** ERROR: Cannot open one or more output files");
            $finish;
        end

        $display("[%0t] OPEN enc0%c, enc1%c, enc2%c", $time, slice_letter(slice0), slice_letter(slice1), slice_letter(slice2));
    end

    // ------------------------------------------------------------
    // WRITE: only when o_e==1 (never force writes on o_last)
    // Also: detect and PRINT when o_last rises while o_e==0 (missing last word!)
    // ------------------------------------------------------------
    always @(posedge clk) begin
        // -------- ENC0 --------
        if (!closed0) begin
            if (o_e0) begin
                // Write MSB then LSB (this matches what you are doing now).
                // If you want the opposite, swap the two fwrite blocks.
                $fwrite(f0, "%c", o_data0[15:8]); process_byte_enc0(o_data0[15:8]); byte0=byte0+1; tb0=tb0+1;
                $fwrite(f0, "%c", o_data0[7:0 ]); process_byte_enc0(o_data0[7:0 ]); byte0=byte0+1; tb0=tb0+1;
                word0=word0+1; tw0=tw0+1;
            end

            // rising edge detection (uses prev_last*)
            if (o_last0 && !prev_last0) begin
                // IMPORTANT: If o_last rises but o_e0 is 0 in this same cycle, you LOST the final word.
                if (!o_e0) begin
                    $display("[%0t] ERROR enc0%c: o_last rose while o_e0=0 (final word NOT written!). o_data0=%04X",
                             $time, slice_letter(slice0), o_data0);
                end

                $display("[%0t] CLOSE enc0%c.jls words=%0d bytes=%0d first4=%02X %02X %02X %02X SOI=%0d@%0d EOI=%0d@%0d",
                         $time, slice_letter(slice0), word0, byte0,
                         first0_0, first1_0, first2_0, first3_0,
                         saw_soi0, soi_pos0, saw_eoi0, eoi_pos0);

                $fclose(f0);
                slice0 = slice0 + 1;

                if (slice0 < 3) begin
                    reset_stats_enc0();
                    f0 = $fopen({basepath,"enc","0",slice_letter(slice0),".jls"},"wb");
                    if (!f0) begin $display("*** ERROR: cannot open next enc0 file"); $finish; end
                    $display("[%0t] OPEN enc0%c.jls", $time, slice_letter(slice0));
                end else begin
                    closed0 = 1;
                    $display("[%0t] DONE enc0 total_words=%0d total_bytes=%0d", $time, tw0, tb0);
                end
            end
        end

        // -------- ENC1 --------
        if (!closed1) begin
            if (o_e1) begin
                $fwrite(f1, "%c", o_data1[15:8]); process_byte_enc1(o_data1[15:8]); byte1=byte1+1; tb1=tb1+1;
                $fwrite(f1, "%c", o_data1[7:0 ]); process_byte_enc1(o_data1[7:0 ]); byte1=byte1+1; tb1=tb1+1;
                word1=word1+1; tw1=tw1+1;
            end

            if (o_last1 && !prev_last1) begin
                if (!o_e1) begin
                    $display("[%0t] ERROR enc1%c: o_last rose while o_e1=0 (final word NOT written!). o_data1=%04X",
                             $time, slice_letter(slice1), o_data1);
                end

                $display("[%0t] CLOSE enc1%c.jls words=%0d bytes=%0d first4=%02X %02X %02X %02X SOI=%0d@%0d EOI=%0d@%0d",
                         $time, slice_letter(slice1), word1, byte1,
                         first0_1, first1_1, first2_1, first3_1,
                         saw_soi1, soi_pos1, saw_eoi1, eoi_pos1);

                $fclose(f1);
                slice1 = slice1 + 1;

                if (slice1 < 3) begin
                    reset_stats_enc1();
                    f1 = $fopen({basepath,"enc","1",slice_letter(slice1),".jls"},"wb");
                    if (!f1) begin $display("*** ERROR: cannot open next enc1 file"); $finish; end
                    $display("[%0t] OPEN enc1%c.jls", $time, slice_letter(slice1));
                end else begin
                    closed1 = 1;
                    $display("[%0t] DONE enc1 total_words=%0d total_bytes=%0d", $time, tw1, tb1);
                end
            end
        end

        // -------- ENC2 --------
        if (!closed2) begin
            if (o_e2) begin
                $fwrite(f2, "%c", o_data2[15:8]); process_byte_enc2(o_data2[15:8]); byte2=byte2+1; tb2=tb2+1;
                $fwrite(f2, "%c", o_data2[7:0 ]); process_byte_enc2(o_data2[7:0 ]); byte2=byte2+1; tb2=tb2+1;
                word2=word2+1; tw2=tw2+1;
            end

            if (o_last2 && !prev_last2) begin
                if (!o_e2) begin
                    $display("[%0t] ERROR enc2%c: o_last rose while o_e2=0 (final word NOT written!). o_data2=%04X",
                             $time, slice_letter(slice2), o_data2);
                end

                $display("[%0t] CLOSE enc2%c.jls words=%0d bytes=%0d first4=%02X %02X %02X %02X SOI=%0d@%0d EOI=%0d@%0d",
                         $time, slice_letter(slice2), word2, byte2,
                         first0_2, first1_2, first2_2, first3_2,
                         saw_soi2, soi_pos2, saw_eoi2, eoi_pos2);

                $fclose(f2);
                slice2 = slice2 + 1;

                if (slice2 < 3) begin
                    reset_stats_enc2();
                    f2 = $fopen({basepath,"enc","2",slice_letter(slice2),".jls"},"wb");
                    if (!f2) begin $display("*** ERROR: cannot open next enc2 file"); $finish; end
                    $display("[%0t] OPEN enc2%c.jls", $time, slice_letter(slice2));
                end else begin
                    closed2 = 1;
                    $display("[%0t] DONE enc2 total_words=%0d total_bytes=%0d", $time, tw2, tb2);
                end
            end
        end

        // update prev_last AFTER checks (blocking assignment not needed; use nonblocking here)
        prev_last0 <= o_last0;
        prev_last1 <= o_last1;
        prev_last2 <= o_last2;
    end

    // ------------------------------------------------------------
    // End simulation
    // ------------------------------------------------------------
    initial begin
        while (!(closed0 && closed1 && closed2))
            @(posedge clk);
        repeat (50) @(posedge clk);
        $display("=== All encoder slices complete (9 files total) ===");
        $finish;
    end

endmodule
