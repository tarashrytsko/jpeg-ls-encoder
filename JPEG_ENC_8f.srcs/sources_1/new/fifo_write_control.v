`timescale 1ns/1ps
module fifo_write_control #(
    parameter integer NUM_ENCODERS = 3, // Number of horizontal blocks / encoders
    parameter integer NUM_SLICES   = 3  // Number of vertical slices
)(
    input  wire                         wr_clk,          // Write clock (synchronous domain for FIFO writes)
    input  wire                         rstn,            // Active low reset
    input  wire [NUM_ENCODERS-1:0]      s_e,             // Encoder pixel valid signals from splitter (1 = valid)
    input  wire [NUM_ENCODERS-1:0]      fifo_overflow,   // Overflow signal for each encoder FIFO
    input  wire [13:0]                  x_cnt,           // Current pixel X-coordinate
    input  wire [13:0]                  y_cnt,           // Current pixel Y-coordinate
    input  wire [13:0]                  total_lines,     // Image height (236)
    input  wire [13:0]                  image_width,     // Image width (460)
    input  wire [$clog2(NUM_ENCODERS)-1:0] encoder_sel, // Encoder select, currently unused

    output reg  [NUM_ENCODERS-1:0]      wr_en,           // Write enable signals for each encoder FIFO
    output reg  [32*NUM_ENCODERS-1:0]   wr_count_flat,   // Flattened write counters for all encoders
    output reg  [NUM_ENCODERS-1:0]      frame_done       // High when encoder has received all its pixels
);

    integer i, s; // Loop variables

    // ----------------------------
    // Block geometry arrays
    // ----------------------------
    reg [15:0] blk_w       [0:NUM_ENCODERS-1]; // Width of each encoder block
    reg [13:0] blk_x_start [0:NUM_ENCODERS-1]; // X-coordinate where each encoder block starts
    reg [13:0] blk_x_end   [0:NUM_ENCODERS-1]; // X-coordinate where each encoder block ends
    reg [15:0] blk_h       [0:NUM_SLICES-1];   // Height of each vertical slice
    reg [31:0] block_pixels[0:NUM_ENCODERS*NUM_SLICES-1]; // Pixels per slice per encoder
    reg [31:0] total_pixels_per_encoder[0:NUM_ENCODERS-1]; // Total pixels each encoder should receive

    reg [31:0] wr_cnt      [0:NUM_ENCODERS-1]; // Canonical write counter per encoder

    // ----------------------------
    // Combinational geometry calculation
    // ----------------------------
    always @(*) begin
        // --- Compute block widths ---
        for(i=0;i<NUM_ENCODERS-1;i=i+1)
            blk_w[i] = image_width / NUM_ENCODERS; // integer division: 460 / 3 = 153
        blk_w[NUM_ENCODERS-1] = image_width - (image_width / NUM_ENCODERS) * (NUM_ENCODERS-1); 
        // Last block width: 460 - (153*2) = 154 (encoder 2)

        // --- Compute X start positions ---
        blk_x_start[0] = 14'd0; // first block starts at 0
        for(i=1;i<NUM_ENCODERS;i=i+1)
            blk_x_start[i] = blk_x_start[i-1] + blk_w[i-1];
        // Results:
        // blk_x_start[0]=0, blk_x_start[1]=153, blk_x_start[2]=306

        // --- Compute X end positions ---
        for(i=0;i<NUM_ENCODERS;i=i+1)
            blk_x_end[i] = blk_x_start[i] + blk_w[i] - 1;
        // Results:
        // blk_x_end[0]=152, blk_x_end[1]=305, blk_x_end[2]=459

        // --- Compute slice heights ---
        for(s=0;s<NUM_SLICES-1;s=s+1)
            blk_h[s] = total_lines / NUM_SLICES; 
        // 236 / 3 = 78
        blk_h[NUM_SLICES-1] = total_lines - (total_lines / NUM_SLICES) * (NUM_SLICES-1);
        // Last slice height = 236 - 78*2 = 80
        // blk_h[0]=78, blk_h[1]=78, blk_h[2]=80

        // --- Compute pixels per slice per encoder ---
        for (s=0;s<NUM_SLICES;s=s+1) begin
            for (i=0;i<NUM_ENCODERS;i=i+1) begin
                block_pixels[s*NUM_ENCODERS + i] = blk_w[i] * blk_h[s];
            end
        end
        // Example values:
        // slice0: [153*78, 153*78, 154*78] = [11934, 11934, 12012]
        // slice1: same
        // slice2: [153*80, 153*80, 154*80] = [12240, 12240, 12320]

        // --- Compute total pixels per encoder ---
        for(i=0;i<NUM_ENCODERS;i=i+1) begin
            total_pixels_per_encoder[i] = 32'd0;
            for(s=0;s<NUM_SLICES;s=s+1)
                total_pixels_per_encoder[i] = total_pixels_per_encoder[i] + block_pixels[s*NUM_ENCODERS + i];
        end
        // Results:
        // Encoder0: 11934+11934+12240=36108
        // Encoder1: 11934+11934+12240=36108
        // Encoder2: 12012+12012+12320=36344
    end

    // ----------------------------
    // Combinational write request
    // ----------------------------
    reg [NUM_ENCODERS-1:0] write_req;
    always @(*) begin
        write_req = {NUM_ENCODERS{1'b0}}; // default: no write
        for (i=0; i<NUM_ENCODERS; i=i+1) begin
            if (!fifo_overflow[i] &&          // FIFO not full
                s_e[i] &&                     // Pixel valid for this encoder
                (x_cnt >= blk_x_start[i]) && (x_cnt <= blk_x_end[i]) && // x in block
                (y_cnt < total_lines) &&      // y in image
                (frame_done[i] == 1'b0)       // encoder still active
               ) begin
                write_req[i] = 1'b1;         // request write to this encoder FIFO
            end else begin
                write_req[i] = 1'b0;
            end
        end
        // Example at first pixel (x_cnt=0, y_cnt=0):
        // write_req = 3'b001 (only encoder 0)
        // At x_cnt=153, write_req = 3'b010 (encoder1)
        // At x_cnt=306, write_req = 3'b100 (encoder2)
    end

    // ----------------------------
    // Sequential logic: update counters and outputs
    // ----------------------------
    always @(posedge wr_clk or negedge rstn) begin
        if (!rstn) begin
            // Reset everything
            for (i=0;i<NUM_ENCODERS;i=i+1) begin
                wr_en[i] <= 1'b0;         // no writes
                wr_cnt[i] <= 32'd0;       // counters zero
                frame_done[i] <= 1'b0;    // frame not done
            end
            wr_count_flat <= {(32*NUM_ENCODERS){1'b0}}; // flattened counters zero
        end else begin
            // Update wr_en and counters atomically
            for (i=0;i<NUM_ENCODERS;i=i+1) begin
                wr_en[i] <= write_req[i];  // enable write if request is valid

                if (write_req[i]) begin
                    wr_cnt[i] <= wr_cnt[i] + 1; // increment counter
                    if (wr_cnt[i] + 1 >= total_pixels_per_encoder[i])
                        frame_done[i] <= 1'b1; // mark frame done when last pixel written
                end
            end

            // Update flattened counter vector from canonical counters
            for (i=0;i<NUM_ENCODERS;i=i+1)
                wr_count_flat[i*32 +:32] <= wr_cnt[i];
            // Example after first line (y_cnt=0, x_cnt=0→459):
            // wr_cnt[0]=153, wr_cnt[1]=153, wr_cnt[2]=154, wr_count_flat updated
        end
    end

endmodule
