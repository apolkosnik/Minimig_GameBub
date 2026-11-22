/********************************************/
/* toccata_volume.v                         */
/* Toccata sound volume attenuation         */
/*                                          */
/* 2022-2023, ranzbak@gmail.com             */
/********************************************/

module toccata_volume (
    input  wire                clk,
    input  wire                rst,
    input  wire signed  [15:0] audio_in_left,
    input  wire signed  [15:0] audio_in_right,
    input  wire         [5:0]  attenuation_left,
    input  wire                mute_left,
    input  wire         [5:0]  attenuation_right,
    input  wire                mute_right,
    output logic signed [15:0] audio_out_left,
    output logic signed [15:0] audio_out_right
);

// Fixed-point representation of the attenuation factor
parameter FIXED_ATTEN_FACTOR   = 16'sd27553; // Fixed-point representation of 0.8409
parameter FIXED_ONE            = 32'sd32768; // Fixed-point representation of 1.0 or 2^15

parameter integer ATTEN_LEVELS = 64; // 6 bits for attenuation level

// LUT for attenuation factors
logic signed [31:0] attenuation_factors[ATTEN_LEVELS];

// Initialize the LUT
// Game Bub port: the values written out. Vivado 2018.3 ignores an initial
// block's assignment that is not a constant ("ignoring non-constant
// assignment in initial block"), which left every level but the first
// without a value. They are what the loop made:
//   attenuation_factors[0] = FIXED_ONE (0 dB), and
//   attenuation_factors[i] = (attenuation_factors[i - 1] * FIXED_ATTEN_FACTOR) >>> 15
initial begin
    attenuation_factors[0] = 32'sd32768;
    attenuation_factors[1] = 32'sd27553;
    attenuation_factors[2] = 32'sd23167;
    attenuation_factors[3] = 32'sd19479;
    attenuation_factors[4] = 32'sd16378;
    attenuation_factors[5] = 32'sd13771;
    attenuation_factors[6] = 32'sd11579;
    attenuation_factors[7] = 32'sd9736;
    attenuation_factors[8] = 32'sd8186;
    attenuation_factors[9] = 32'sd6883;
    attenuation_factors[10] = 32'sd5787;
    attenuation_factors[11] = 32'sd4866;
    attenuation_factors[12] = 32'sd4091;
    attenuation_factors[13] = 32'sd3439;
    attenuation_factors[14] = 32'sd2891;
    attenuation_factors[15] = 32'sd2430;
    attenuation_factors[16] = 32'sd2043;
    attenuation_factors[17] = 32'sd1717;
    attenuation_factors[18] = 32'sd1443;
    attenuation_factors[19] = 32'sd1213;
    attenuation_factors[20] = 32'sd1019;
    attenuation_factors[21] = 32'sd856;
    attenuation_factors[22] = 32'sd719;
    attenuation_factors[23] = 32'sd604;
    attenuation_factors[24] = 32'sd507;
    attenuation_factors[25] = 32'sd426;
    attenuation_factors[26] = 32'sd358;
    attenuation_factors[27] = 32'sd301;
    attenuation_factors[28] = 32'sd253;
    attenuation_factors[29] = 32'sd212;
    attenuation_factors[30] = 32'sd178;
    attenuation_factors[31] = 32'sd149;
    attenuation_factors[32] = 32'sd125;
    attenuation_factors[33] = 32'sd105;
    attenuation_factors[34] = 32'sd88;
    attenuation_factors[35] = 32'sd73;
    attenuation_factors[36] = 32'sd61;
    attenuation_factors[37] = 32'sd51;
    attenuation_factors[38] = 32'sd42;
    attenuation_factors[39] = 32'sd35;
    attenuation_factors[40] = 32'sd29;
    attenuation_factors[41] = 32'sd24;
    attenuation_factors[42] = 32'sd20;
    attenuation_factors[43] = 32'sd16;
    attenuation_factors[44] = 32'sd13;
    attenuation_factors[45] = 32'sd10;
    attenuation_factors[46] = 32'sd8;
    attenuation_factors[47] = 32'sd6;
    attenuation_factors[48] = 32'sd5;
    attenuation_factors[49] = 32'sd4;
    attenuation_factors[50] = 32'sd3;
    attenuation_factors[51] = 32'sd2;
    attenuation_factors[52] = 32'sd1;
    attenuation_factors[53] = 32'sd0;
    attenuation_factors[54] = 32'sd0;
    attenuation_factors[55] = 32'sd0;
    attenuation_factors[56] = 32'sd0;
    attenuation_factors[57] = 32'sd0;
    attenuation_factors[58] = 32'sd0;
    attenuation_factors[59] = 32'sd0;
    attenuation_factors[60] = 32'sd0;
    attenuation_factors[61] = 32'sd0;
    attenuation_factors[62] = 32'sd0;
    attenuation_factors[63] = 32'sd0;
end

// Apply volume control using LUT and clock
always_ff @(posedge clk) begin
    if (rst) begin
        // Hold the output nutral during reset
        audio_out_left <= 'h0000;
        audio_out_right <= 'h0000;
    end else begin
        // Using inferred DSP blocks to do volume calculations
        if (mute_left) begin
            audio_out_left <= 'h0000;
        end else begin
            audio_out_left <= 16'(($signed(audio_in_left) * attenuation_factors[attenuation_left]) >>> 15);
        end
        if (mute_right) begin
            audio_out_right <= 'h0000;
        end else begin
            audio_out_right <= 16'(($signed(audio_in_right) * attenuation_factors[attenuation_right]) >>> 15);
        end
    end
end

endmodule
