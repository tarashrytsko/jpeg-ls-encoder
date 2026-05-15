//--------------------------------------------------------------------------------------------------------
// Module  : splitter_horizontal
// Type    : synthesizable
// Function: Horizontal image splitter for parallel JPEG-LS encoders (Fixed array ports)
//--------------------------------------------------------------------------------------------------------

module splitter_horizontal #(
    parameter integer NUM_ENCODERS = 2,
    parameter integer LINES_PER_ENCODER = 64
)(
    input  wire        rstn,
    input  wire        clk,

    // AXI-Stream Input
    input  wire        i_sof,
    input  wire        i_e,
    input  wire [7:0]  i_x,
    input  wire [13:0] i_w,
    input  wire [13:0] i_h,

    // AXI-Stream Outputs (Flattened Arrays)
    output reg  [NUM_ENCODERS-1:0]     o_sof,
    output reg  [NUM_ENCODERS-1:0]     o_e,
    output reg  [NUM_ENCODERS*8-1:0]   o_x,
    output reg  [NUM_ENCODERS*14-1:0]  o_w,
    output reg  [NUM_ENCODERS*14-1:0]  o_h
);

reg [13:0] x_cnt, y_cnt;
reg [1:0] encoder_sel;
reg [13:0] line_count;

// Pixel counters
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        x_cnt <= 14'd0;
        y_cnt <= 14'd0;
        encoder_sel <= 2'd0;
        line_count <= 14'd0;
    end else if (i_e) begin
        if (x_cnt == i_w - 1) begin
            x_cnt <= 14'd0;
            y_cnt <= y_cnt + 14'd1;
            line_count <= line_count + 14'd1;

            if (line_count == LINES_PER_ENCODER - 1) begin
                line_count <= 14'd0;
                if (encoder_sel == NUM_ENCODERS - 1)
                    encoder_sel <= 2'd0;
                else
                    encoder_sel <= encoder_sel + 2'd1;
            end
        end else begin
            x_cnt <= x_cnt + 14'd1;
        end
    end
end

integer i;
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        o_sof <= {NUM_ENCODERS{1'b0}};
        o_e   <= {NUM_ENCODERS{1'b0}};
        o_x   <= {NUM_ENCODERS*8{1'b0}};
        o_w   <= {NUM_ENCODERS*14{1'b0}};
        o_h   <= {NUM_ENCODERS*14{1'b0}};
    end else begin
        o_sof <= {NUM_ENCODERS{1'b0}};
        o_e   <= {NUM_ENCODERS{1'b0}};
        for (i = 0; i < NUM_ENCODERS; i = i + 1) begin
            if (i == encoder_sel) begin
                o_e[i]         <= i_e;
                o_x[i*8 +: 8]  <= i_x;
                o_sof[i]       <= i_sof & (x_cnt == 14'd0) & (line_count == 14'd0);
                o_w[i*14 +: 14] <= i_w;
                o_h[i*14 +: 14] <= i_h;
            end
        end
    end
end

endmodule

