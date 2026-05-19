
//--------------------------------------------------------------------------------------------------------
// Module  : tb_jls_encoder
// Type    : simulation, top
// Standard: Verilog 2001 (IEEE1364-2001)
// Function: testbench for jls_encoder,
//           load some .pgm files (uncompressed image file), and push them to jls_encoder.
//           get output JPEG-LS stream from jls_encoder, and write them to .jls files (JPEG-LS image file)
//--------------------------------------------------------------------------------------------------------

`timescale 1ps/1ps

`define NEAR            0    // NEAR can be 0~7

`define FILE_NO_SINGLE  1    // << single file

// bubble numbers that insert between pixels
//    when = 0, do not insert bubble
//    when > 0, insert BUBBLE_CONTROL bubbles
//    when < 0, insert random 0~(-BUBBLE_CONTROL) bubbles
`define BUBBLE_CONTROL  (-1)

// the input and output file names' format
`define FILE_NAME_FORMAT  "world_gray_1000x1000"

// input file (uncompressed .pgm file) directory
`define INPUT_PGM_DIR     "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f/JPEG_ENC_8f.sim/images"

// output file (compressed .jls file) directory
`define OUTPUT_JLS_DIR    "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f/JPEG_ENC_8f.sim/output"

module tb_jls_encoder ();

// -------------------------------------------------------------------------------------------------------------------
//   generate clock and reset
// -------------------------------------------------------------------------------------------------------------------
reg          rstn = 1'b0;
reg          clk  = 1'b0;
always #50000 clk = ~clk;  // 10MHz
initial begin repeat(4) @(posedge clk); rstn <= 1'b1; end


// -------------------------------------------------------------------------------------------------------------------
//   signals for jls_encoder_i module
// -------------------------------------------------------------------------------------------------------------------
reg        i_sof = 0;
reg [13:0] i_w = 0;
reg [13:0] i_h = 0;
reg        i_e = 0;
reg [7:0]  i_x = 0;
wire       o_e;
wire       o_last;
wire [15:0] o_data;

reg [7:0] img [16000*10800-1:0];
integer w = 0, h = 0;

task load_img;
    input [256*8:1] fname;
    reg [256*8-1:0] line;
    integer linelen, depth, scanf_num, fp, i;
begin
    depth = 0;
    $display("*** file name %s", fname);
    fp = $fopen(fname, "rb");
    if (fp==0) begin
        $display("*** error: could not open file %s", fname);
        $finish;
    end
    linelen = $fgets(line, fp);
    if (line[8*(linelen-2)+:16] != 16'h5035) begin
        $display("*** error: the first line must be P5");
        $fclose(fp);
        $finish;
    end
    scanf_num = $fgets(line, fp);
    scanf_num = $sscanf(line, "%d%d", w, h);
    if(scanf_num == 1) begin
        scanf_num = $fgets(line, fp);
        scanf_num = $sscanf(line, "%d", h);
    end
    scanf_num = $fgets(line, fp);
    scanf_num = $sscanf(line, "%d", depth);
    if (depth!=255) begin
        $display("*** error: images depth must be 255");
        $fclose(fp);
        $finish;
    end
    for (i=0; i<h*w; i=i+1)
        img[i] = $fgetc(fp);
    $fclose(fp);
end
endtask

integer input_bytes = 0;
integer output_bytes = 0;
integer start_time = 0;
integer end_time = 0;

initial $sformat(log_file_format, "%s\\%s.log", `OUTPUT_JLS_DIR, `FILE_NAME_FORMAT);

// -------------------------------------------------------------------------------------------------------------------
//   task: feed image pixels to jls_encoder_i module
//   arguments:
//         w   : image width
//         h   : image height
//         bubble_control : bubble numbers that insert between pixels
//              when = 0, do not insert bubble
//              when > 0, insert bubble_control bubbles
//              when < 0, insert random 0~bubble_control bubbles
// -------------------------------------------------------------------------------------------------------------------
task feed_img;
    input integer bubble_control;
    integer       num_bubble, i;
begin
    // start feeding a image by assert i_sof for 368 cycles
    //new:     repeat(368) @(posedge clk) begin
    repeat(368) begin
        @(posedge clk)
        i_sof <= 1'b1;
        i_w   <= w - 1;
        i_h   <= h - 1;
        {i_e, i_x} <= 0;
    end

    // for all pixels of the image
    for (i=0; i<h*w; i=i+1) begin

        // calculate how many bubbles to insert
        if (bubble_control<0) begin
            num_bubble = $random % (1-bubble_control);
            if (num_bubble<0)
                num_bubble = -num_bubble;
        end else begin
            num_bubble = bubble_control;
        end

        // insert bubbles
        repeat(num_bubble) @(posedge clk) {i_sof, i_w, i_h, i_e, i_x} <= 0;

        // assert i_e to input a pixel
//        @(posedge clk) begin
        @(posedge clk)
            {i_sof, i_w, i_h} <= 0;
            i_e <= 1'b1;
            i_x <= img[i];
            input_bytes = input_bytes + 1;
        end
// new:    end

    // 32 cycles idle between images
    repeat(32) @(posedge clk) {i_sof, i_w, i_h, i_e, i_x} <= 0;
end
endtask


// -------------------------------------------------------------------------------------------------------------------
//   jls_encoder_i module
// -------------------------------------------------------------------------------------------------------------------
jls_encoder #(
    .NEAR (`NEAR)
) u_jls_encoder (
    .rstn   (rstn),
    .clk    (clk),
    .i_sof  (i_sof),
    .i_w    (i_w),
    .i_h    (i_h),
    .i_e    (i_e),
    .i_x    (i_x),
    .o_e    (o_e),
    .o_last (o_last),
    .o_data (o_data)
);

// -------------------------------------------------------------------------------------------------------------------
//  read images, feed them to jls_encoder_i module
// -------------------------------------------------------------------------------------------------------------------
integer file_no;    // file number
reg [256*8:1] input_file_name;
reg [256*8:1] input_file_format;

initial begin
    $sformat(input_file_format , "%s\\%s.pgm", `INPUT_PGM_DIR, `FILE_NAME_FORMAT);

    while (~rstn) @(posedge clk);

    $sformat(input_file_name, input_file_format , `FILE_NO_SINGLE);

    load_img(input_file_name);
    $display("%100s (%5dx%5d)", input_file_name, w, h);

    if (w < 5 || w > 16384 || h < 1 || h > 16384) // image size not supported
        $display("  *** image size not supported ***");
    else
    begin
        start_time = $time;
        feed_img(`BUBBLE_CONTROL);
    end

    repeat(100) @(posedge clk);

  //  $finish;
end


// -------------------------------------------------------------------------------------------------------------------
//  write output stream to .jls files
// -------------------------------------------------------------------------------------------------------------------
reg [256*8:1] output_file_format;
initial $sformat(output_file_format, "%s\\%s.jls", `OUTPUT_JLS_DIR, `FILE_NAME_FORMAT);
reg [256*8:1] output_file_name;
integer opened = 0;
integer jls_file = 0;
integer log_file;
reg [256*8:1] log_file_format;
initial $sformat(log_file_format, "%s\\%s.log", `OUTPUT_JLS_DIR, `FILE_NAME_FORMAT);
reg [256*8:1] log_file_name;
initial $sformat(log_file_name, log_file_format, `FILE_NO_SINGLE);

// Save compressed output
always @(posedge clk)
    if (o_e) begin
        output_bytes = output_bytes + 2;
        // the first data of an output stream, open a new file.
        if (opened == 0) begin
            opened = 1;
            $sformat(output_file_name, output_file_format, `FILE_NO_SINGLE);
//          $sformat(output_file_name, output_file_format, file_no);
            jls_file = $fopen(output_file_name , "wb");
        end

        // write data to file.
        if (opened != 0 && jls_file != 0)
            $fwrite(jls_file, "%c%c", o_data[7:0], o_data[15:8]);

        // if it is the last data of an output stream, close the file.
        if (o_last) begin
            end_time = $time;
            opened = 0;
            $fclose(jls_file);
            log_file = $fopen(log_file_name, "w");
            if (log_file != 0) begin
                $fwrite(log_file, "=== COMPRESSION COMPLETE ===\n");
                $fwrite(log_file, "File: %s\n", output_file_name);
                $fwrite(log_file, "Width: %0d px\n", w);
                $fwrite(log_file, "Height: %0d px\n", h);
                $fwrite(log_file, "Input Bytes: %0d\n", input_bytes);
                $fwrite(log_file, "Output Bytes: %0d\n", output_bytes);
                if (output_bytes != 0)
                    $fwrite(log_file, "Compression Ratio: %.2f\n", (input_bytes * 1.0) / (output_bytes * 1.0));
                else
                    $fwrite(log_file, "Compression Ratio: N/A\n");
                $fwrite(log_file, "Time: %0d ns\n", end_time - start_time);
                $fclose(log_file);
            end
        end
    end

endmodule
