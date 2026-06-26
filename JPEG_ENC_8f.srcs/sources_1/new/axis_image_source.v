`timescale 1ns/1ps
// On-chip AXIS pixel source for the bitstream harness. A $readmemh ROM streams a
// fixed image once; self-starts after rstn. Drives the sideband dims + a one-shot
// i_sof, then presents one ROM byte per AXIS beat. Synthesizable (4096x8 ROM as
// distributed RAM). Combinational ROM read keeps tdata aligned with tvalid so each
// pixel is sent exactly once with tlast on the final pixel.
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
    output wire [7:0]  s_axis_tdata,
    output wire        s_axis_tvalid,
    input  wire        s_axis_tready,
    output wire        s_axis_tlast
);
    localparam integer N = IMG_W * IMG_H;
    (* rom_style = "distributed" *) reg [7:0] rom [0:N-1];
    initial $readmemh(HEXFILE, rom);

    localparam S_IDLE = 2'd0, S_RUN = 2'd1, S_DONE = 2'd2;
    reg [1:0]  state;
    reg [31:0] addr;

    // Combinational data/valid: present rom[addr] while running; advance on transfer.
    assign s_axis_tdata  = rom[addr];
    assign s_axis_tvalid = (state == S_RUN);
    assign s_axis_tlast  = (state == S_RUN) && (addr == N-1);

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= S_IDLE; addr <= 0; i_sof <= 1'b0; i_w <= 0; i_h <= 0;
        end else begin
            i_sof <= 1'b0;                          // i_sof is a one-shot pulse
            case (state)
                S_IDLE: begin
                    i_w   <= IMG_W[15:0];
                    i_h   <= IMG_H[13:0];
                    i_sof <= 1'b1;                  // asserted the same cycle dims are valid
                    addr  <= 0;
                    state <= S_RUN;
                end
                S_RUN: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        if (addr == N-1) state <= S_DONE;   // last pixel just transferred
                        else             addr  <= addr + 1;
                    end
                end
                S_DONE: ;                           // tvalid de-asserts via state != S_RUN
            endcase
        end
    end
endmodule
