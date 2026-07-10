`timescale 1ps/1ps
`default_nettype wire
// tb_iserdes_byte_in — drives 12 serial lanes (360 Mb/s, MSB-first) into iserdes_byte_in,
// performs BITSLIP word-alignment training (as on real hardware), then verifies distinct
// per-lane bytes reconstruct bit-exact. clk_bit = 360 MHz, clk_div = clk_bit/8 = 45 MHz.
module tb_iserdes_byte_in;
    localparam integer N = 12;
    localparam [7:0]   TRAIN = 8'h01;   // rotation-unique alignment marker

    reg clk_bit = 0;
    always #1389 clk_bit = ~clk_bit;                 // 360 MHz

    reg [2:0] bcnt = 0;
    always @(posedge clk_bit) bcnt <= bcnt + 1'b1;
    reg clk_div = 0;
    always @(posedge clk_bit)
        if (bcnt == 3'd7) clk_div <= 1'b1;
        else if (bcnt == 3'd3) clk_div <= 1'b0;

    reg rst = 1'b1;
    initial begin repeat (80) @(posedge clk_bit); @(posedge clk_div); rst <= 1'b0; end

    // per-lane distinct constant byte, sent continuously (no train/data switch, so no
    // window-straddling artifact). dat[0]=0x03 is rotation-unique -> a clean align marker.
    reg [7:0] dat [0:N-1];
    integer d;
    initial for (d = 0; d < N; d = d + 1) dat[d] = (d*16 + 3) & 8'hFF;

    // serialiser: MSB-first (bit 7-bcnt), always the lane's data byte
    wire [N-1:0] d_in;
    genvar gl;
    generate
        for (gl = 0; gl < N; gl = gl + 1) begin : g_ser
            assign d_in[gl] = dat[gl][3'd7 - bcnt];
        end
    endgenerate

    reg  [N-1:0]   bitslip_r = 0;
    wire [N*8-1:0] o_word;
    wire           o_valid;
    iserdes_byte_in #(.N(N)) dut (
        .clk_bit(clk_bit), .clk_div(clk_div), .rst(rst),
        .d_in(d_in), .bitslip(bitslip_r), .o_word(o_word), .o_valid(o_valid)
    );

    // BITSLIP training FSM (clk_div): slip until ALL 12 lanes read their byte, waiting for
    // each slip to fully settle before judging (avoids false-locking on a transient).
    function all_match; input dummy; integer kk; begin
        all_match = 1'b1;
        for (kk = 0; kk < N; kk = kk + 1) if (o_word[kk*8 +: 8] !== dat[kk]) all_match = 1'b0;
    end endfunction

    reg       trained = 0;
    reg [3:0] slips = 0, wcnt = 0, vcnt = 0;
    integer   errors = 0, k;
    always @(posedge clk_div) begin
        bitslip_r <= {N{1'b0}};
        if (rst) begin trained <= 0; slips <= 0; wcnt <= 4'd8; vcnt <= 0; end
        else if (o_valid && !trained) begin
            if (wcnt != 0)               wcnt <= wcnt - 1'b1;             // let slip settle
            else if (all_match(1'b0)) begin
                trained <= 1'b1;
                $display("ISERDES_ALIGNED after %0d bitslips (l0=%02x l1=%02x l5=%02x l11=%02x)",
                         slips, o_word[7:0], o_word[15:8], o_word[47:40], o_word[95:88]);
            end
            else if (slips < 8) begin bitslip_r <= {N{1'b1}}; slips <= slips + 1'b1; wcnt <= 4'd8; end
            else begin
                $display("ISERDES_ALIGN_FAIL (l0=%02x/%02x l1=%02x/%02x)",
                         o_word[7:0], dat[0], o_word[15:8], dat[1]);
                $finish;
            end
        end
        else if (trained) begin
            if (!all_match(1'b0)) errors <= errors + 1;
            if (vcnt < 4'd15) vcnt <= vcnt + 1'b1;
            else begin
                $display("ISERDES_VERIFY errors=%0d  (l0=%02x/%02x l5=%02x/%02x l11=%02x/%02x)  %s",
                         errors, o_word[7:0], dat[0], o_word[47:40], dat[5], o_word[95:88], dat[11],
                         (errors==0) ? "PASS" : "FAIL");
                $finish;
            end
        end
    end

    initial #1200000000 begin $display("ISERDES_TB_TIMEOUT trained=%0d", trained); $finish; end
endmodule
