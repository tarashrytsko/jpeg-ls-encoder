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
    wire [7:0] i_x;
    wire [13:0] i_w;
    wire [13:0] i_h;

    wire clk;
    wire sys_rdy;

    wire o_e0, o_e1, o_e2;
    wire o_last0, o_last1, o_last2;
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
        case(idx)
            0: slice_letter = "a";
            1: slice_letter = "b";
            2: slice_letter = "c";
            default: slice_letter = "a";
        endcase
    endfunction

    // ------------------------------------------------------------
    // File handles, slice counters, marker detection
    // ------------------------------------------------------------
    integer f[0:2];
    reg [1:0] slice_idx[0:2];
    reg file_closed[0:2];
    reg prev_last[0:2];
    reg [8*256-1:0] basepath;

    // counts per CURRENT file
    integer word_count[0:2];
    integer byte_count[0:2];

    // totals per encoder (optional)
    integer total_word_count[0:2];
    integer total_byte_count[0:2];

    // header/footer detection per CURRENT file
    reg [7:0] first4_b0[0:2], first4_b1[0:2], first4_b2[0:2], first4_b3[0:2];
    reg [7:0] last_byte[0:2];         // previous written byte
    reg saw_soi[0:2];                 // saw FF D8 anywhere
    reg saw_eoi[0:2];                 // saw FF D9 anywhere
    integer soi_at_bytepos[0:2];
    integer eoi_at_bytepos[0:2];

    // helper: reset per-file stats (called when opening a new slice)
    task reset_file_stats(input integer enc);
        begin
            word_count[enc] = 0;
            byte_count[enc] = 0;

            first4_b0[enc] = 8'h00;
            first4_b1[enc] = 8'h00;
            first4_b2[enc] = 8'h00;
            first4_b3[enc] = 8'h00;

            last_byte[enc] = 8'h00;
            saw_soi[enc] = 0;
            saw_eoi[enc] = 0;
            soi_at_bytepos[enc] = -1;
            eoi_at_bytepos[enc] = -1;
        end
    endtask

    // helper: process a byte for marker detection & first-4 recording
    task process_byte(input integer enc, input [7:0] b);
        begin
            // record first 4 bytes of file
            if (byte_count[enc] == 0) first4_b0[enc] = b;
            else if (byte_count[enc] == 1) first4_b1[enc] = b;
            else if (byte_count[enc] == 2) first4_b2[enc] = b;
            else if (byte_count[enc] == 3) first4_b3[enc] = b;

            // marker detection using previous byte
            if (!saw_soi[enc] && (last_byte[enc] == 8'hFF) && (b == 8'hD8)) begin
                saw_soi[enc] = 1;
                soi_at_bytepos[enc] = byte_count[enc] - 1; // position of 0xFF
            end
            if (!saw_eoi[enc] && (last_byte[enc] == 8'hFF) && (b == 8'hD9)) begin
                saw_eoi[enc] = 1;
                eoi_at_bytepos[enc] = byte_count[enc] - 1;
            end

            last_byte[enc] = b;
        end
    endtask

    // ------------------------------------------------------------
    // Open initial files
    // ------------------------------------------------------------
    initial begin
        basepath = "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_v8c/JPEG_ENC_v8c.sim/output_block/";

        for (i = 0; i < 3; i = i + 1) begin
            slice_idx[i] = 0;
            file_closed[i] = 0;
            prev_last[i] = 0;

            total_word_count[i] = 0;
            total_byte_count[i] = 0;

            reset_file_stats(i);

            f[i] = $fopen({basepath,"enc",8'd48+i,slice_letter(slice_idx[i]),".jls"}, "wb");
            if (!f[i]) begin
                $display("*** ERROR: Cannot open file for encoder %0d", i);
                $finish;
            end
            $display("[%0t] Opened: enc%0d%c.jls", $time, i, slice_letter(slice_idx[i]));
        end
    end

    // ------------------------------------------------------------
    // Write data and handle slices
    // ------------------------------------------------------------
    always @(posedge clk) begin
        // edge detect memories
        prev_last[0] <= o_last0;
        prev_last[1] <= o_last1;
        prev_last[2] <= o_last2;

        for (i = 0; i < 3; i = i + 1) begin : PER_ENC
            reg o_e_tmp;
            reg o_last_tmp;
            reg prev_last_tmp;
            reg [15:0] o_data_tmp;
            reg do_write_word;
            reg last_rise;

            // select signals per encoder
            if (i == 0) begin
                o_e_tmp       = o_e0;
                o_last_tmp    = o_last0;
                prev_last_tmp = prev_last[0];
                o_data_tmp    = o_data0;
            end else if (i == 1) begin
                o_e_tmp       = o_e1;
                o_last_tmp    = o_last1;
                prev_last_tmp = prev_last[1];
                o_data_tmp    = o_data1;
            end else begin
                o_e_tmp       = o_e2;
                o_last_tmp    = o_last2;
                prev_last_tmp = prev_last[2];
                o_data_tmp    = o_data2;
            end

            last_rise    = (o_last_tmp && !prev_last_tmp);

            // KEY FIX:
            // Write on normal valid cycles (o_e) AND also on the o_last rising edge,
            // because many encoders output the final flush/EOI on the last cycle even if o_e drops.
            do_write_word = (!file_closed[i]) && (o_e_tmp || last_rise);

            if (do_write_word) begin
                // NOTE: current byte order = [7:0] then [15:8] (matches your TB)
                // Swap these two lines if your stream is endian-swapped.
                $fwrite(f[i], "%c", o_data_tmp[7:0]);
                process_byte(i, o_data_tmp[7:0]);
                byte_count[i]       = byte_count[i] + 1;
                total_byte_count[i] = total_byte_count[i] + 1;

                $fwrite(f[i], "%c", o_data_tmp[15:8]);
                process_byte(i, o_data_tmp[15:8]);
                byte_count[i]       = byte_count[i] + 1;
                total_byte_count[i] = total_byte_count[i] + 1;

                word_count[i]       = word_count[i] + 1;
                total_word_count[i] = total_word_count[i] + 1;
            end

            // rising edge of o_last → close and switch slice file
            if (last_rise) begin
                $display("[%0t] CLOSE enc%0d%c.jls  words=%0d  bytes=%0d  first4=%02X %02X %02X %02X  SOI=%0d(at %0d)  EOI=%0d(at %0d)",
                         $time, i, slice_letter(slice_idx[i]),
                         word_count[i], byte_count[i],
                         first4_b0[i], first4_b1[i], first4_b2[i], first4_b3[i],
                         saw_soi[i], soi_at_bytepos[i],
                         saw_eoi[i], eoi_at_bytepos[i]);

                $fclose(f[i]);

                slice_idx[i] = slice_idx[i] + 1;

                if (slice_idx[i] < 3) begin
                    reset_file_stats(i);
                    f[i] = $fopen({basepath,"enc",8'd48+i,slice_letter(slice_idx[i]),".jls"}, "wb");
                    if (!f[i]) begin
                        $display("*** ERROR: Cannot open next slice file for encoder %0d", i);
                        $finish;
                    end
                    $display("[%0t] OPEN  enc%0d%c.jls", $time, i, slice_letter(slice_idx[i]));
                end else begin
                    file_closed[i] = 1;
                    $display("[%0t] DONE  enc%0d total_words=%0d total_bytes=%0d",
                             $time, i, total_word_count[i], total_byte_count[i]);
                end
            end
        end
    end

    // ------------------------------------------------------------
    // End simulation
    // ------------------------------------------------------------
    initial begin
        while (!(file_closed[0] && file_closed[1] && file_closed[2]))
            @(posedge clk);
        repeat (50) @(posedge clk);
        $display("=== All encoder slices complete (9 files total) ===");
        $finish;
    end

endmodule
