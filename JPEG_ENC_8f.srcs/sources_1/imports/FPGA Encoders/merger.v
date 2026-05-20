`timescale 1ps/1ps
// Merger: serializes parallel encoder outputs into a single sequential stream.
// Processes in rounds: all encoders once (slice a), then all encoders again (slice b).
// Order within each round: enc0, enc1, ..., enc(N_E-1).
// Detects EOI (FFD9) at byte level to know when each encoder's current slice ends.
module merger #(
    parameter integer N_E = 6,
    parameter integer SLICES_PER_ENC = 2
)(
    input  wire        clk,
    input  wire        rstn,
    input  wire [13:0] i_w,
    input  wire [13:0] i_h,
    input  wire [2:0]  near,

    input  wire [N_E-1:0]    i_e,
    input  wire [N_E-1:0]    i_last,
    input  wire [N_E*16-1:0] i_data,

    output reg         o_e,
    output reg         o_last,
    output reg [15:0]  o_data
);

    reg [$clog2(N_E)-1:0] enc_sel;
    reg [$clog2(SLICES_PER_ENC):0] round;
    reg done;
    reg [7:0] prev_lsb;

    wire [15:0] cur_data = i_data[enc_sel*16 +: 16];
    wire cur_valid = i_e[enc_sel];

    wire eoi_in_word = (cur_data[15:8] == 8'hFF) && (cur_data[7:0] == 8'hD9);
    wire eoi_cross   = (prev_lsb == 8'hFF) && (cur_data[15:8] == 8'hD9);
    wire eoi_detect  = cur_valid && (eoi_in_word || eoi_cross);

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            enc_sel  <= 0;
            round    <= 0;
            done     <= 0;
            o_e      <= 0;
            o_last   <= 0;
            o_data   <= 0;
            prev_lsb <= 0;
        end else begin
            o_e    <= 0;
            o_last <= 0;

            if (!done && cur_valid) begin
                o_e    <= 1;
                o_data <= cur_data;
                prev_lsb <= cur_data[7:0];

                if (eoi_detect) begin
                    prev_lsb <= 0;
                    if (enc_sel == N_E - 1) begin
                        // End of round
                        if (round == SLICES_PER_ENC - 1) begin
                            // All rounds done
                            o_last <= 1;
                            done   <= 1;
                        end else begin
                            // Next round
                            enc_sel <= 0;
                            round   <= round + 1;
                        end
                    end else begin
                        // Next encoder in this round
                        enc_sel <= enc_sel + 1;
                    end
                end
            end
        end
    end

endmodule
