`timescale 1ps/1ps
`default_nettype wire
// tb_byte_gearbox — feeds a strided byte stream 1 byte/cycle @ 540 MHz into
// byte_gearbox_12 and checks the 12-byte words emitted @ 45 MHz reconstruct the
// reference strided words exactly. clk_fast and clk_slow are INDEPENDENT (the
// async FIFO does the real CDC). Reference = vert12x1_300.hex (7500 12-byte words).
module tb_byte_gearbox #(
    parameter integer N      = 12,
    parameter integer NWORDS = 7500,   // (300/12)*300 for vert12x1_300
    parameter HEXFILE = "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f/JPEG_ENC_8f.sim/images/vert12x1_300.hex"
) ();
    reg clk_fast = 0;   // 540 MHz -> half period 926 ps (~539.9 MHz)
    reg clk_slow = 0;   // 45 MHz  -> half period 11111 ps
    always #926   clk_fast = ~clk_fast;
    always #11111 clk_slow = ~clk_slow;

    reg rstn = 0;
    initial begin repeat (8) @(posedge clk_fast); rstn = 1; end

    // reference strided words
    reg [N*8-1:0] ref_word [0:NWORDS-1];
    initial $readmemh(HEXFILE, ref_word);

    // ---- DUT ----
    reg         i_valid;
    wire [7:0]  i_byte;
    wire        i_ready;
    wire [N*8-1:0] o_word;
    wire        o_valid;
    wire        o_ready = 1'b1;    // downstream always ready

    // feed pointers (fast domain): byte fk of word fw
    reg [31:0] fw, fk;
    assign i_byte = (fw < NWORDS) ? ref_word[fw][fk*8 +: 8] : 8'd0;

    always @(posedge clk_fast or negedge rstn) begin
        if (!rstn) begin
            fw <= 0; fk <= 0; i_valid <= 1'b0;
        end else begin
            i_valid <= (fw < NWORDS);
            if (i_valid & i_ready) begin          // byte accepted this cycle
                if (fk == N-1) begin fk <= 0; fw <= fw + 1; end
                else                 fk <= fk + 1;
            end
        end
    end

    byte_gearbox_12 #(.N(N), .AW(2)) dut (
        .rstn(rstn),
        .clk_fast(clk_fast), .i_valid(i_valid), .i_byte(i_byte), .i_ready(i_ready),
        .clk_slow(clk_slow),
        .o_b0(),.o_b1(),.o_b2(),.o_b3(),.o_b4(),.o_b5(),
        .o_b6(),.o_b7(),.o_b8(),.o_b9(),.o_b10(),.o_b11(),
        .o_word(o_word), .o_valid(o_valid), .o_ready(o_ready)
    );

    // capture (slow domain): compare each emitted word to the reference
    reg [31:0] cw, errors;
    always @(posedge clk_slow or negedge rstn) begin
        if (!rstn) begin
            cw <= 0; errors <= 0;
        end else if (o_valid & o_ready) begin
            if (o_word !== ref_word[cw]) begin
                errors <= errors + 1;
                if (errors < 5)
                    $display("MISMATCH word %0d: got %024x exp %024x", cw, o_word, ref_word[cw]);
            end
            cw <= cw + 1;
        end
    end

    // finish when all words captured (or watchdog)
    integer wd;
    initial wd = 0;
    always @(posedge clk_fast) begin
        wd <= wd + 1;
        if (wd > 4000000) begin $display("WATCHDOG cw=%0d/%0d errors=%0d", cw, NWORDS, errors); $finish; end
    end

    always @(posedge clk_slow) begin
        if (cw == NWORDS) begin
            repeat (5) @(posedge clk_slow);
            $display("GEARBOX_RESULT NWORDS=%0d captured=%0d errors=%0d %s",
                     NWORDS, cw, errors, (errors==0) ? "PASS" : "FAIL");
            $finish;
        end
    end
endmodule
