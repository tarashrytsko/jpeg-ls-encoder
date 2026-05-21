`timescale 1ns/1ps

module image_generator #(
    parameter ADDR_WIDTH   = 22,
    parameter DATA_WIDTH   = 8,
    parameter NUM_ENCODERS = 6,
    parameter IMG_W        = 0,
    parameter IMG_H        = 0,
    parameter SOF_STRETCH  = 3000,
    parameter PGM_FILE     = "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f/JPEG_ENC_8f.sim/images/world_gray_5000x5000.pgm"
)(
    input  wire                    clk,
    input  wire                    rstn,
    input  wire                    i_sof,
    input  wire [NUM_ENCODERS-1:0] fifo_overflow,

    output reg  [DATA_WIDTH-1:0]   pixel_out,
    output reg                     pixel_valid,
    output reg  [13:0]             i_w,
    output reg  [13:0]             i_h,
    output reg  [NUM_ENCODERS-1:0] i_sof_st
);

`ifndef SYNTHESIS
    integer fp;
    integer file_w, file_h, file_depth;
    integer scanf_ret;
    integer total_pixels;
    reg [8*256-1:0] hdr_line;
    integer hdr_len;
    integer img_w_int, img_h_int;

    initial begin
        fp = $fopen(PGM_FILE, "rb");
        if (fp == 0) begin
            $display("image_generator: ERROR cannot open %s", PGM_FILE);
            $finish;
        end
        hdr_len = $fgets(hdr_line, fp);
        hdr_len = $fgets(hdr_line, fp);
        while (hdr_line[8*(hdr_len-1) +: 8] == 8'h0A && hdr_line[8*(hdr_len-2) +: 8] == 8'h23)
            hdr_len = $fgets(hdr_line, fp);
        scanf_ret = $sscanf(hdr_line, "%d %d", file_w, file_h);
        if (scanf_ret < 2) begin
            scanf_ret = $sscanf(hdr_line, "%d", file_w);
            hdr_len = $fgets(hdr_line, fp);
            scanf_ret = $sscanf(hdr_line, "%d", file_h);
        end
        hdr_len = $fgets(hdr_line, fp);
        scanf_ret = $sscanf(hdr_line, "%d", file_depth);
        img_w_int = (IMG_W > 0) ? IMG_W : file_w;
        img_h_int = (IMG_H > 0) ? IMG_H : file_h;
        total_pixels = img_w_int * img_h_int;
        $display("image_generator: opened %s  %0dx%0d depth=%0d  streaming %0dx%0d",
                 PGM_FILE, file_w, file_h, file_depth, img_w_int, img_h_int);
    end

    localparam S_IDLE  = 2'd0;
    localparam S_SOF   = 2'd1;
    localparam S_PIXEL = 2'd2;
    localparam S_DONE  = 2'd3;

    reg [1:0]  state;
    reg [31:0] sof_cnt;
    reg [31:0] pix_cnt;

    wire backpressure = |fifo_overflow;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state       <= S_IDLE;
            sof_cnt     <= 0;
            pix_cnt     <= 0;
            pixel_out   <= 0;
            pixel_valid <= 0;
            i_w         <= 0;
            i_h         <= 0;
            i_sof_st    <= 0;
        end else begin
            pixel_valid <= 0;
            i_sof_st    <= 0;

            case (state)
                S_IDLE: begin
                    if (i_sof) begin
                        i_w         <= img_w_int[13:0];
                        i_h         <= img_h_int[13:0];
                        sof_cnt     <= 0;
                        pix_cnt     <= 0;
                        state       <= S_SOF;
                    end
                end
                S_SOF: begin
                    i_sof_st <= {NUM_ENCODERS{1'b1}};
                    if (sof_cnt < SOF_STRETCH - 1)
                        sof_cnt <= sof_cnt + 1;
                    else begin
                        sof_cnt <= 0;
                        state   <= S_PIXEL;
                    end
                end
                S_PIXEL: begin
                    if (pix_cnt < total_pixels) begin
                        if (!backpressure) begin
                            pixel_out   <= $fgetc(fp);
                            pixel_valid <= 1;
                            pix_cnt     <= pix_cnt + 1;
                        end
                    end else begin
                        $fclose(fp);
                        $display("image_generator: done streaming %0d pixels", total_pixels);
                        state <= S_DONE;
                    end
                end
                S_DONE: begin
                end
            endcase
        end
    end

`else
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            pixel_out   <= 0;
            pixel_valid <= 0;
            i_w         <= 0;
            i_h         <= 0;
            i_sof_st    <= 0;
        end
    end
`endif

endmodule
