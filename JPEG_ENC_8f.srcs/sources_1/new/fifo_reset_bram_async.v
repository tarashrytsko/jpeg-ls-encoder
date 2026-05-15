`timescale 1ps/1ps
//fifo reset module and system reset  module
module fifo_reset_bram_async #(
    parameter N_E = 3  // FS: Number of encoders/FIFOs
)(
    input  wire clk_rd,
    input  wire rstn_ext,
    input  wire locked,
    input  wire wr_busy,  // FS: vector input
    input  wire rd_busy,
    output reg  fifo_rst,
    output reg  sys_rdy
);

localparam integer RESET_CYCLES = 10;
reg sys_rdyx=0;
reg [3:0] reset_count = 4'b0;
reg reset_active = 1'b0;


    // 
//reg sys_rdy;
always @(posedge clk_rd) begin
    if (~rstn_ext || ~locked) begin
        fifo_rst     <= 1'b0;
        reset_count  <= 4'b0;
        sys_rdyx <= 1'b0;
     end else  if ((rstn_ext && locked==1) && (reset_count < RESET_CYCLES))begin
            reset_count <= reset_count +1;
            fifo_rst <= 1'b1;
            sys_rdyx <= 1'b0;
      end
        else begin
            reset_count <=reset_count;
            fifo_rst <= 1'b0;
            sys_rdyx <= 1'b1;
         end

    end
 
 always @(posedge clk_rd)
    begin
    if (sys_rdyx==1 && wr_busy==0 && rd_busy==0)
    sys_rdy <=1;
    else sys_rdy <=0;
    end
endmodule