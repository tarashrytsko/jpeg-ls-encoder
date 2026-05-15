//--------------------------------------------------------------------------------------------------------
// Module  : merger
// Type    : synthesizable
// Function: Merge output streams from multiple JPEG-LS encoders into a single output stream (Fixed array ports)
//--------------------------------------------------------------------------------------------------------

module merger #(
    parameter integer NUM_ENCODERS = 3
)(
    input  wire        rstn,
    input  wire        clk,

    // AXI-Stream Inputs from Encoders (Flattened Arrays)
    input  wire [NUM_ENCODERS-1:0]     i_e,
    input  wire [NUM_ENCODERS-1:0]     i_last,
    input  wire [NUM_ENCODERS*16-1:0]  i_data,

    // AXI-Stream Output
    output reg         o_e,
    output reg         o_last,
    output reg [15:0]  o_data
);

reg [1:0] sel;  // Encoder selector

always @(posedge clk or negedge rstn) begin
    if (!rstn)
        sel <= 2'd0;
    else if (i_e[sel])
        sel <= sel;  // Stay until no valid data
    else if (sel == NUM_ENCODERS - 1)
        sel <= 2'd0;
    else
        sel <= sel + 2'd1;
end

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        o_e    <= 1'b0;
        o_last <= 1'b0;
        o_data <= 16'd0;
    end else begin
        if (i_e[sel]) begin
            o_e    <= 1'b1;
            o_data <= i_data[sel*16 +: 16];
            o_last <= i_last[sel];
        end else begin
            o_e    <= 1'b0;
            o_last <= 1'b0;
        end
    end
end

endmodule

