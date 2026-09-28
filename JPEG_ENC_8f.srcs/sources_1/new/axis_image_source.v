`timescale 1ns/1ps
// On-chip 128-bit column-strided AXIS pixel source for the wide bitstream harness.
// A $readmemh ROM holds one 128-bit word per (ys,xs); byte k = strip k's pixel.
// Streams N = (IMG_W/N_E) * IMG_H words, one per beat. Self-starts after rstn;
// one-shot i_sof, then presents one ROM word per AXIS beat (combinational read so
// tdata stays aligned with tvalid). Synthesizable (block ROM).
module axis_image_source #(
    parameter integer N_E   = 16,
    parameter integer IMG_W = 256,
    parameter integer IMG_H = 256,
    parameter integer PW    = 8,       // pixel lane width (8, or 16 for BPP>8)
    parameter         HEXFILE = "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f/JPEG_ENC_8f.srcs/sources_1/new/rom_wide.hex"
)(
    input  wire              clk,
    input  wire              rstn,
    output reg  [15:0]       i_w,
    output reg  [13:0]       i_h,
    output reg               i_sof,
    output wire [N_E*PW-1:0] s_axis_tdata,
    output wire              s_axis_tvalid,
    input  wire              s_axis_tready,
    output wire              s_axis_tlast
);
    localparam integer SW = IMG_W / N_E;          // strip width
    localparam integer N  = SW * IMG_H;           // strided words
    (* rom_style = "block" *) reg [N_E*PW-1:0] rom [0:N-1];
    initial $readmemh(HEXFILE, rom);

    localparam S_IDLE = 2'd0, S_RUN = 2'd1, S_DONE = 2'd2;
    reg [1:0]  state;
    reg [31:0] addr;

    assign s_axis_tdata  = rom[addr];
    assign s_axis_tvalid = (state == S_RUN);
    assign s_axis_tlast  = (state == S_RUN) && (addr == N-1);

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= S_IDLE; addr <= 0; i_sof <= 1'b0; i_w <= 0; i_h <= 0;
        end else begin
            i_sof <= 1'b0;
            case (state)
                S_IDLE: begin
                    i_w   <= IMG_W[15:0];
                    i_h   <= IMG_H[13:0];
                    i_sof <= 1'b1;                 // one-shot SOF
                    addr  <= 0;
                    state <= S_RUN;
                end
                S_RUN: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        if (addr == N-1) state <= S_DONE;
                        else             addr  <= addr + 1;
                    end
                end
                S_DONE: ;
            endcase
        end
    end
endmodule
