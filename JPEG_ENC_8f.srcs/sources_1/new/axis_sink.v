`timescale 1ns/1ps
// On-chip 16-lane AXIS sink: ties tready high, counts output words across all
// lanes, accumulates a rolling XOR checksum of the compressed words, and raises
// `done` when every lane has signaled tlast. Keeps the lanes from being pruned by
// synthesis (status depends on the encoded data) and makes completion observable.
module axis_sink #(parameter integer N_E = 16, parameter integer DW = 16)(
    input  wire              clk,
    input  wire              rstn,
    input  wire [N_E*DW-1:0] m_axis_tdata,
    input  wire [N_E-1:0]    m_axis_tvalid,
    output wire [N_E-1:0]    m_axis_tready,
    input  wire [N_E-1:0]    m_axis_tlast,
    output reg  [31:0]       total_words,
    output reg  [31:0]       checksum,
    output reg               done
);
    assign m_axis_tready = {N_E{1'b1}};
    reg [N_E-1:0] lane_done;
    integer k;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            total_words <= 0; checksum <= 0; done <= 0; lane_done <= 0;
        end else begin
            for (k = 0; k < N_E; k = k + 1) begin
                if (m_axis_tvalid[k]) begin
                    total_words <= total_words + 1'b1;
                    checksum    <= checksum ^ m_axis_tdata[k*DW +: DW];
                    if (m_axis_tlast[k]) lane_done[k] <= 1'b1;
                end
            end
            done <= &lane_done;
        end
    end
endmodule
