`timescale 1ns/1ps
// On-chip AXIS pixel source for the bitstream harness. A $readmemh ROM streams a
// fixed image; self-starts after rstn. Drives the sideband dims + i_sof. Synthesizable
// (inferred block ROM).
module axis_image_source #(
    parameter integer IMG_W   = 64,
    parameter integer IMG_H   = 64,
    parameter         HEXFILE = "rom_image.hex"
)(
    input  wire        clk,
    input  wire        rstn,           // = sys_rdy
    output reg  [15:0] i_w,
    output reg  [13:0] i_h,
    output reg         i_sof,
    output reg  [7:0]  s_axis_tdata,
    output reg         s_axis_tvalid,
    input  wire        s_axis_tready,
    output reg         s_axis_tlast
);
    localparam integer N = IMG_W * IMG_H;
    (* rom_style = "block" *) reg [7:0] rom [0:N-1];
    initial $readmemh(HEXFILE, rom);

    localparam S_IDLE=2'd0, S_SOF=2'd1, S_RUN=2'd2, S_DONE=2'd3;
    reg [1:0]  state;
    reg [31:0] addr;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= S_IDLE; addr <= 0; i_sof <= 0;
            i_w <= 0; i_h <= 0; s_axis_tdata <= 0; s_axis_tvalid <= 0; s_axis_tlast <= 0;
        end else begin
            i_sof <= 1'b0;
            case (state)
                S_IDLE: begin
                    i_w <= IMG_W[15:0]; i_h <= IMG_H[13:0];
                    i_sof <= 1'b1;                 // one-shot SOF
                    addr  <= 0; state <= S_SOF;
                end
                S_SOF: begin                       // wait until the IP is ready for pixels
                    s_axis_tdata  <= rom[0];
                    s_axis_tvalid <= 1'b1;
                    s_axis_tlast  <= (N == 1);
                    if (s_axis_tvalid && s_axis_tready) begin
                        addr  <= 1;
                        state <= S_RUN;
                    end
                end
                S_RUN: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        if (addr == N) begin
                            s_axis_tvalid <= 1'b0; s_axis_tlast <= 1'b0; state <= S_DONE;
                        end else begin
                            s_axis_tdata <= rom[addr];
                            s_axis_tlast <= (addr == N-1);
                            addr <= addr + 1;
                        end
                    end
                end
                S_DONE: s_axis_tvalid <= 1'b0;
            endcase
        end
    end
endmodule
