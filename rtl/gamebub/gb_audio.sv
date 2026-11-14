// Game Bub Minimig: Paula output -> AudioV0.
//
// Paula's 15 bit signed mix is optionally passed through a first order low
// pass at about 4.4 kHz, the fixed output filter of the Amiga 500
// (y += (x - y) / 256 at the 7.09 MHz clock enable: fc = 7.09 MHz / (2 pi 256)),
// then the channels are mixed into each other as MiSTer's audio_out does
// (aud_mix_top): 0 none, 1 1/8, 2 1/4 of the other channel, 3 mono.
// The framework samples the output at 48 kHz.
//
// SPDX-License-Identifier: GPL-3.0-or-later

module gb_audio
(
	input                    clk,
	input                    reset,
	input                    clk7_en,
	input                    filter_en,
	input              [1:0] mix,
	input                    mute,
	input             [14:0] ldata,
	input             [14:0] rdata,
	output reg signed [15:0] left,
	output reg signed [15:0] right
);

reg signed [23:0] yl, yr;   // 16.8 fixed point

wire signed [23:0] xl = {{1{ldata[14]}}, ldata, 8'd0};
wire signed [23:0] xr = {{1{rdata[14]}}, rdata, 8'd0};

always @(posedge clk) begin
	if (reset) begin
		yl <= 24'sd0;
		yr <= 24'sd0;
	end
	else if (clk7_en) begin
		yl <= yl + ((xl - yl) >>> 8);
		yr <= yr + ((xr - yr) >>> 8);
	end
end

// filtered (or not) channels, 16 bit
reg signed [15:0] fl, fr;
always @(posedge clk) begin
	fl <= filter_en ? yl[23:8] : {ldata, 1'b0};
	fr <= filter_en ? yr[23:8] : {rdata, 1'b0};
end

// stereo mix (17 bit sums, the result stays within 16 bits)
function automatic signed [15:0] mixed(input signed [15:0] own, input signed [15:0] other, input [1:0] m);
	reg signed [16:0] o, t, r;
	begin
		o = {own[15], own};
		t = {other[15], other};
		case (m)
			2'd0: r = o;
			2'd1: r = o - (o >>> 3) + (t >>> 3);
			2'd2: r = o - (o >>> 2) + (t >>> 2);
			default: r = (o + t) >>> 1;
		endcase
		mixed = r[15:0];
	end
endfunction

always @(posedge clk) begin
	if (mute) begin
		left  <= 16'sd0;
		right <= 16'sd0;
	end
	else begin
		left  <= mixed(fl, fr, mix);
		right <= mixed(fr, fl, mix);
	end
end

endmodule
