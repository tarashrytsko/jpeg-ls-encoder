`timescale 1ns/1ps

module image_generator #(
    parameter ADDR_WIDTH   = 17,
    parameter DATA_WIDTH   = 8,
    parameter NUM_ENCODERS = 3,
    parameter IMG_W        = 462,
    parameter IMG_H        = 237,
    parameter SOF_STRETCH  = 3000
)(
    input  wire                    clk,
    input  wire                    rstn,
    input  wire                    i_sof,       // global frame start

    output wire [DATA_WIDTH-1:0]    pixel_out,
    output reg                     pixel_valid,
    output reg [13:0]              i_w,
    output reg [13:0]              i_h,
    output reg [NUM_ENCODERS-1:0]  i_sof_st
);

    // ----------------------------------------
    // BRAM
    // ----------------------------------------
    reg [ADDR_WIDTH-1:0] addra;
  //  wire [DATA_WIDTH-1:0] douta;

    // ----------------------------------------
    // SOF stretch and frame control
    // ----------------------------------------
    reg [31:0] sof_cnt;
    reg frame_active;
    reg [1:0] stage; // 0 = first, 1 = second, 2 = third

   // New generic calculation
localparam integer TOTAL_PIXELS  = IMG_W * IMG_H;

// Divide frame into 3 stages
localparam integer STAGE1_ADDR = 0;
localparam integer STAGE2_ADDR = TOTAL_PIXELS / 3;       // 1/3 of total pixels 36498;
localparam integer STAGE3_ADDR = (TOTAL_PIXELS * 2) / 3; // 2/3 of total pixels 72996 

    // ----------------------------------------
    // Main logic
    // ----------------------------------------
    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            addra       <= 0;
            i_w         <= 0;
            i_h         <= 0;
            frame_active<= 0;
            i_sof_st    <= 0;
            sof_cnt     <= 0;
            stage       <= 0;
        end else begin
            if(i_sof) begin
                // Frame start
                addra       <= 0;
                i_w         <= IMG_W;
                i_h         <= IMG_H;
                frame_active<= 1'b1;
                stage       <= 0;
                sof_cnt     <= 0;
                i_sof_st    <= {NUM_ENCODERS{1'b1}}; // first SOF stretch
            end
            else if(|i_sof_st) begin
                // SOF stretch active
                if(sof_cnt < SOF_STRETCH-1) begin
                    sof_cnt <= sof_cnt + 1;
                    i_sof_st <= {NUM_ENCODERS{1'b1}};
                end else begin
                    sof_cnt <= 0;
                    i_sof_st <= 0; // end current stretch
                end
            end
            else if(frame_active) begin
                // Pixel streaming
                if(addra < TOTAL_PIXELS - 1)
                    addra <= addra + 1;

                // Trigger next SOF stage at specific addresses
                if(addra == STAGE2_ADDR && stage==0) begin
                    i_sof_st <= {NUM_ENCODERS{1'b1}};
                    sof_cnt  <= 0;
                    stage    <= 1;
                end
                else if(addra == STAGE3_ADDR && stage==1) begin
                    i_sof_st <= {NUM_ENCODERS{1'b1}};
                    sof_cnt  <= 0;
                    stage    <= 2;
                end

                // End of frame
                if(addra == TOTAL_PIXELS - 1)
                    frame_active <= 0;
            end
        end
    end

    // ----------------------------------------
    // BRAM instance
    // ----------------------------------------
    // Enable only when pixels are being read (frame active AND no SOF stretch)
    wire bram_enable = frame_active && (~|i_sof_st);

    blk_mem_gen_0 u_bram (
        .clka(clk),
        .ena(bram_enable),
        .wea(1'b0),
        .addra(addra),
        .dina({DATA_WIDTH{1'b0}}),
        .douta(pixel_out)
    );

    // ----------------------------------------
    // Pixel output aligned with BRAM
reg valid_delay;

always @(posedge clk or negedge rstn) begin
    if(!rstn) begin
  //      pixel_out   <= 0;
        pixel_valid <= 0;
        valid_delay <= 0;
    end else begin
        // Capture BRAM output
      //  pixel_out <= douta;

        // 1-cycle delay for BRAM enable
        valid_delay <= bram_enable;
        pixel_valid <= valid_delay;  // delayed by 1 cycle
    end
end



endmodule
