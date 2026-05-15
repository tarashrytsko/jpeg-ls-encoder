//--------------------------------------------------------------------------------------------------------
// Module  : top_jls_horizontal
// Type    : synthesizable top
// Function: JPEG-LS Parallel Image Stream Compressor using Horizontal Splitting (Fixed array ports)
//--------------------------------------------------------------------------------------------------------

module top_jls_horizontal #(
    parameter integer NUM_ENCODERS = 3, //3
    parameter integer LINES_PER_ENCODER = 64,
    parameter [2:0]   NEAR = 3'd0
)(
    input  wire        rstn,
    input  wire        clk,

    // AXI-Stream Input
    input  wire        i_sof,   // start of image
    input  wire [13:0] i_w,     // image_width-1 , range: 4~16383, that is, image_width range: 5~16384
    input  wire [13:0] i_h,     // image_height-1, range: 0~16382, that is, image_height range: 1~16383
    input  wire        i_e,     // input pixel enable
    input  wire [ 7:0] i_x,     // input pixel

    // AXI-Stream Output
    output wire        o_e,     // output data enable
    output wire        o_last,  // indicate the last output data of a image
    output wire [15:0] o_data   // output data
);

wire [NUM_ENCODERS-1:0]     s_sof;
wire [NUM_ENCODERS-1:0]     s_e;
wire [NUM_ENCODERS*8-1:0]   s_x;
wire [NUM_ENCODERS*14-1:0]  s_w;
wire [NUM_ENCODERS*14-1:0]  s_h;

wire [NUM_ENCODERS-1:0]     e_e;
wire [NUM_ENCODERS-1:0]     e_last;
wire [NUM_ENCODERS*16-1:0]  e_data;

// Instantiate Horizontal Splitter
splitter_horizontal #(
    .NUM_ENCODERS(NUM_ENCODERS),
    .LINES_PER_ENCODER(LINES_PER_ENCODER)
) u_splitter_horizontal (
    .rstn   (rstn),
    .clk    (clk),
    .i_sof  (i_sof),
    .i_e    (i_e),
    .i_x    (i_x),
    .i_w    (i_w),
    .i_h    (i_h),
    .o_sof  (s_sof),
    .o_e    (s_e),
    .o_x    (s_x),
    .o_w    (s_w),
    .o_h    (s_h)
);

// Instantiate JPEG-LS Encoders
genvar i;
generate
    for (i = 0; i < NUM_ENCODERS; i = i + 1) begin : ENC_INST
        jls_encoder #(
            .NEAR(NEAR)
        ) u_encoder (
            .rstn  (rstn),
            .clk   (clk),
            .i_sof (s_sof[i]),
            .i_w   (s_w[i*14 +: 14]),
            .i_h   (s_h[i*14 +: 14]),
            .i_e   (s_e[i]),
            .i_x   (s_x[i*8 +: 8]),
            .o_e   (e_e[i]),
            .o_last(e_last[i]),
            .o_data(e_data[i*16 +: 16])
        );
    end
endgenerate

// Instantiate Output Merger
merger #(
    .NUM_ENCODERS(NUM_ENCODERS)
) u_merger (
    .rstn   (rstn),
    .clk    (clk),
    .i_e    (e_e),
    .i_last (e_last),
    .i_data (e_data),
    .o_e    (o_e),
    .o_last (o_last),
    .o_data (o_data)
);

endmodule

