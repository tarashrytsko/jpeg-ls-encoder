`timescale 1ps/1ps

//-------------------------------------------------------------------------------------------------------
// Module  : fifo_wrapper
// Type    : synthesizable
// Function: Multi-FIFO wrapper for parallel encoders with external fifo_count
//--------------------------------------------------------------------------------------------------------

module fifo_wrapper_input #(
    parameter N_E = 3,
    parameter DATA_WIDTH = 8
)(
    input  wire               rst,             // reset
    input  wire               wr_clk,          // write clock
    input  wire               rd_clk,          // read clock
   // input wire                o_last_enc,
    input  wire [N_E*DATA_WIDTH-1:0] din_flat,  // write data
    input  wire [N_E-1:0]     wr_en,           // write enable
    input  wire [N_E-1:0]     rd_en,           // read enable
    output wire [N_E*DATA_WIDTH-1:0] dout_flat,// read data
    output wire [N_E-1:0]     full,            // FIFO full
    output wire [N_E-1:0]     wr_ack,          // write acknowledge
    output wire [N_E-1:0]     overflow,        // FIFO overflow
    output wire [N_E-1:0]     empty,           // FIFO empty
    output wire [N_E-1:0]     almost_empty,           // FIFO empty
//   output wire [N_E-1:0]     almost_empty, 
    output wire [N_E-1:0]     valid,           // read valid
    output wire [N_E-1:0]     wr_rst_busy,     // write reset busy
    output wire [N_E-1:0]     rd_rst_busy,    // read reset busy
    output wire [N_E*18-1:0]  fifo_count_flat // external fifo count (18 bits each)
  

);
wire [16*3-1:0] rd_data_count_flat; // 3 FIFOs, 16 bits each
wire [16*3-1:0] wr_data_count_flat;
wire [N_E-1:0] underflow;
reg [N_E*DATA_WIDTH-1:0] din_flatx;  // write data

always @(posedge wr_clk)
begin
din_flatx <=din_flat;
end
    // Each lane is DATA_WIDTH/8 byte-wide fifo_generator_0 slices run in lockstep
    // (DATA_WIDTH=8: one slice, identical to the original). With >1 slice, reads and
    // writes are gated by the COMBINED empty/full so every slice sees exactly the same
    // op sequence even if their independent CDC synchronizers resolve a cycle apart.
    localparam integer NS = DATA_WIDTH / 8;
    genvar i, sl;
    generate
        for (i = 0; i < N_E; i = i + 1) begin : GEN_FIFO
            wire [NS-1:0] s_full, s_wr_ack, s_ovf, s_empty, s_aempty, s_valid, s_wbusy, s_rbusy, s_udf;
            if (NS == 1) begin : g_one
            //------------------------------------------------------------------------------------------------
            // Async FIFO instance
            //------------------------------------------------------------------------------------------------
            fifo_generator_0 u_fifo_inst(
                .rst(rst),
                .wr_clk(wr_clk),
                .rd_clk(rd_clk),
                .din(din_flatx[i*DATA_WIDTH +: DATA_WIDTH]),
                .wr_en(wr_en[i]),
                .rd_en(rd_en[i]),
                .dout(dout_flat[i*DATA_WIDTH +: DATA_WIDTH]),
                .full(full[i]),
                .wr_ack(wr_ack[i]),
                .overflow(overflow[i]),
                .empty(empty[i]),
                .almost_empty(almost_empty[i]),
                .almost_full(),
                .underflow(underflow[i]),
                .valid(valid[i]),
                .wr_rst_busy(wr_rst_busy[i]),
                .rd_rst_busy(rd_rst_busy[i]),
                 .rd_data_count(rd_data_count),  // output wire [16 : 0] rd_data_count
                 .wr_data_count(wr_data_count)  // output wire [16 : 0] wr_data_count
            );
            end else begin : g_multi
            wire any_full  = |s_full;
            wire any_empty = |s_empty;
            wire wr_g = wr_en[i] & ~any_full;
            wire rd_g = rd_en[i] & ~any_empty;
            reg  ovf_r;
            always @(posedge wr_clk or posedge rst)
                if (rst) ovf_r <= 1'b0; else ovf_r <= wr_en[i] & any_full;
            for (sl = 0; sl < NS; sl = sl + 1) begin : GEN_SLICE
                fifo_generator_0 u_fifo_inst(
                    .rst(rst),
                    .wr_clk(wr_clk),
                    .rd_clk(rd_clk),
                    .din(din_flatx[i*DATA_WIDTH + sl*8 +: 8]),
                    .wr_en(wr_g),
                    .rd_en(rd_g),
                    .dout(dout_flat[i*DATA_WIDTH + sl*8 +: 8]),
                    .full(s_full[sl]),
                    .wr_ack(s_wr_ack[sl]),
                    .overflow(s_ovf[sl]),
                    .empty(s_empty[sl]),
                    .almost_empty(s_aempty[sl]),
                    .almost_full(),
                    .underflow(s_udf[sl]),
                    .valid(s_valid[sl]),
                    .wr_rst_busy(s_wbusy[sl]),
                    .rd_rst_busy(s_rbusy[sl]),
                    .rd_data_count(),
                    .wr_data_count()
                );
            end
            assign full[i]         = any_full;
            assign empty[i]        = any_empty;
            assign almost_empty[i] = |s_aempty;
            assign valid[i]        = &s_valid;
            assign wr_ack[i]       = &s_wr_ack;
            assign overflow[i]     = ovf_r;
            assign underflow[i]    = |s_udf;
            assign wr_rst_busy[i]  = |s_wbusy;
            assign rd_rst_busy[i]  = |s_rbusy;
            end

            //------------------------------------------------------------------------------------------------
            // External fifo_count generation (write domain)
            //------------------------------------------------------------------------------------------------
            reg [17:0] fifo_count_wr; // widen to 18 bits
            always @(posedge wr_clk or posedge rst) begin
                if (rst)
                    fifo_count_wr <= 18'd0;
                else begin
                    // Increment on write, decrement on read
                    if (wr_en[i] && !full[i])
                        fifo_count_wr <= fifo_count_wr + 1'b1;
                    else if (rd_en[i] && !almost_empty[i])
                        fifo_count_wr <= fifo_count_wr - 1'b1;
                end
            end

            //------------------------------------------------------------------------------------------------
            // Synchronize to read clock domain (double flop)
            //------------------------------------------------------------------------------------------------
            reg [17:0] fifo_count_rd_sync1, fifo_count_rd_sync2;
            always @(posedge rd_clk or posedge rst) begin
                if (rst) begin
                    fifo_count_rd_sync1 <= 18'd0;
                    fifo_count_rd_sync2 <= 18'd0;
                end else begin
                    fifo_count_rd_sync1 <= fifo_count_wr;
                    fifo_count_rd_sync2 <= fifo_count_rd_sync1;
                end
            end

            assign fifo_count_flat[i*18 +: 18] = fifo_count_rd_sync2; // 18-bit slice per encoder
        end
    endgenerate



endmodule
