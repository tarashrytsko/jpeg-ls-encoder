`timescale 1ps/1ps
// tb_saif — post-route functional-netlist simulation of jls_demo_top for activity-based
// (SAIF) power (reviewer Req 5). The on-chip ROM streams the frame at full rate; the SAIF
// window is [first accepted source beat, done], i.e. steady-state streaming + encoding.
module tb_saif;
    reg rstn = 0, clk_p = 0, clk_n = 1;
    always #2500 clk_p = ~clk_p;          // 200 MHz differential board clock
    always #2500 clk_n = ~clk_n;
    wire done; wire clk; wire [30:0] status;
    jls_demo_top dut (.rstn(rstn), .clk_in1_p(clk_p), .clk_in1_n(clk_n), .clk(clk), .done(done), .status(status));
    initial begin repeat (5) @(posedge clk_p); rstn = 1; end
    reg started = 0, finished = 0;
    always @(posedge clk) begin
        if (!started && dut.src_tvalid && dut.src_tready) begin
            started = 1; $display("SAIF_START %0t", $time); $stop;
        end
        if (started && !finished && done) begin
            finished = 1; $display("SAIF_END %0t status=%h", $time, status); $stop;
        end
    end
    initial begin repeat (20) #1000000000; $display("SAIF_TIMEOUT"); $finish; end  // 20 ms
endmodule
