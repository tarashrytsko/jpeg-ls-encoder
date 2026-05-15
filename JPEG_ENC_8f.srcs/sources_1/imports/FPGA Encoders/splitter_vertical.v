`timescale 1ps/1ps
module splitter_vertical #(
    parameter integer N_E = 3,   // Number of encoders
    parameter integer L   = 64   // Optional internal slice height
)(
    input  wire        sys_rdy,
    input  wire        clk,
    input  wire        i_sof,      // frame start input (rising edge)
    input  wire        i_e,        // pixel enable (true while pixel valid)
    input  wire [7:0]  i_x,        // pixel data
    input  wire [13:0] i_w,        // image width (pixels per line)
    input  wire [13:0] i_h,        // image height (lines per frame)

    output reg  [N_E-1:0]     o_sof,      // short pulse at start (per encoder)
    output reg  [N_E-1:0]     o_sof_st,   // 3000-cycle stretched strobe per encoder
    output reg  [N_E-1:0]     o_e,        // pixel valid per encoder
    output reg  [N_E*8-1:0]   o_x,
    output reg  [N_E*14-1:0]  o_w,
    output reg  [N_E*14-1:0]  o_h,

    output reg  [$clog2(N_E)-1:0] encoder_sel, // active encoder index
    output reg  [13:0]        x_cnt,           // horizontal pixel counter
    output reg  [13:0]        y_cnt            // vertical line counter
);

    // ----------------------------
    // Internal signals
    // ----------------------------
    reg rstn = 0;
    reg i_sof_d;
    reg frame_active;
    reg o_sof_pulse;

    // Calculate slice width evenly distributed
    localparam integer SLICE_W = 1146 / N_E; // e.g. 382 pixels per encoder (for 1146 width)
    localparam integer Y_BOUNDARY = 608;     // Limit for processing height (if applicable)

    // ----------------------------
    // Reset synchronization
    // ----------------------------
    always @(posedge clk)
        rstn <= sys_rdy;

    // ----------------------------
    // Pixel and line counters
    // ----------------------------
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            i_sof_d      <= 1'b0;
            frame_active <= 1'b0;
            x_cnt        <= 14'd0;
            y_cnt        <= 14'd0;
            encoder_sel  <= 0;
        end else begin
            i_sof_d <= i_sof;

            // Detect start of frame
            if (~i_sof_d & i_sof) begin
                frame_active <= 1'b1;
                x_cnt        <= 14'd0;
                y_cnt        <= 14'd0;
                encoder_sel  <= 0;
            end else if (frame_active && i_e) begin
                // Increment horizontal pixel counter
                if (x_cnt == i_w - 1) begin
                    x_cnt <= 14'd0;

                    // Increment vertical counter
                    if (y_cnt == i_h - 1)
                        y_cnt <= 14'd0;
                    else
                        y_cnt <= y_cnt + 1'b1;
                end else begin
                    x_cnt <= x_cnt + 1'b1;
                end

                // Correct encoder selection (no 1-cycle lag)
               if (frame_active && i_e) begin
        if (x_cnt < 381)
            encoder_sel <= 0;
        else if (x_cnt < 763)
            encoder_sel <= 1;
        else if (x_cnt < 1145)
            encoder_sel <= 2;  // 764-1145
         else
            encoder_sel <=0;
        end
        end
        end
    end

    // ----------------------------
    // o_sof pulse generator
    // ----------------------------
    always @(posedge clk or negedge rstn) begin
        if (!rstn)
            o_sof_pulse <= 1'b0;
        else
            o_sof_pulse <= (~i_sof_d & i_sof);
    end

    // ----------------------------
    // SOF_ST logic: 3000-cycle stretch
    // ----------------------------
    localparam integer SOF_STRETCH = 3000;
    reg [15:0] sof_cnt [0:N_E-1];
    reg        sof_active[0:N_E-1];
    integer gi;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            for (gi = 0; gi < N_E; gi = gi + 1) begin
                sof_cnt[gi]    <= 0;
                sof_active[gi] <= 1'b0;
            end
        end else begin
            for (gi = 0; gi < N_E; gi = gi + 1) begin
                if (gi == encoder_sel && o_sof_pulse) begin
                    sof_active[gi] <= 1'b1;
                    sof_cnt[gi]    <= 0;
                end else if (sof_active[gi]) begin
                    if (sof_cnt[gi] < SOF_STRETCH-1)
                        sof_cnt[gi] <= sof_cnt[gi] + 1'b1;
                    else
                        sof_active[gi] <= 1'b0;
                end
            end
        end
    end

    // ----------------------------
    // Output generation
    // ----------------------------
    integer i;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            o_sof    <= {N_E{1'b0}};
            o_sof_st <= {N_E{1'b0}};
            o_e      <= {N_E{1'b0}};
            o_x      <= {N_E*8{1'b0}};
            o_w      <= {N_E*14{1'b0}};
            o_h      <= {N_E*14{1'b0}};
        end else begin
            o_sof <= {N_E{1'b0}};
            o_e   <= {N_E{1'b0}};

            for (i = 0; i < N_E; i = i + 1) begin
                // Enable current encoder region
                if (i == encoder_sel && y_cnt <= Y_BOUNDARY) begin
                    o_e[i]         <= i_e;
                    o_x[i*8 +: 8]  <= i_x;
                    o_w[i*14 +:14] <= SLICE_W;
                    o_h[i*14 +:14] <= i_h;

                    // SOF pulse at top-left of each slice
                    if (x_cnt == i * SLICE_W && y_cnt == 0)
                        o_sof[i] <= 1'b1;
                end

                // 3000-cycle stretched start signal
                o_sof_st[i] <= sof_active[i];
            end
        end
    end

endmodule
