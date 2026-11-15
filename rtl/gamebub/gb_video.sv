// Game Bub Minimig: Amiga video -> VideoV0 (640 x 256, palette indices).
//
// Denise produces a new colour every 28 MHz clock (super hires grid). The
// Game Bub framework stores what the core sends into a 640 x 256 frame
// buffer and shows it one to one across, and down either its first 240
// lines twice each or, with `fit`, all 256 lines over the 480 rows (seven
// lines of eight twice, one once), on the 800 x 480 panel or HDMI's 720 x
// 480; patches/framework makes the framework scale that way. This module:
//   - counts 28 MHz clocks from the start of _hsync and lines from the start
//     of _vsync,
//   - keeps a 640 high resolution pixel (1280 clock) window starting at
//     H_START, and in PAL either all 256 lines of the standard display
//     window ($2C81) (fit_height) or 240 of them, from its line vpos (0:
//     its top 240 lines, 16: its bottom 240); in NTSC its 200 lines with 20
//     lines above and below,
//   - takes one pixel per high resolution pixel (every 2 clocks): a 640
//     pixel wide screen as it is, a low resolution pixel twice, every other
//     pixel of a super high resolution one,
//   - sends each pixel as 10 bits (the block RAM holds two 640 x 256 frame
//     buffers of 10 bits per pixel, not of 24), by palette_mode either
//     the index of its colour in a palette that gb_palette builds from the
//     colours that appear (exact colours while there are no more than 768
//     at a time), or the colour itself in 3 + 4 + 3 bits with an ordered
//     dither (any number of colours, approximate),
//   - drives dataEnable for one clock per pixel, hblank outside the 640
//     pixels and vblank outside the lines (vblank changes only while
//     hblank is high).
//
// H_START: the clock sampled (H_START + 2k) must be inside high resolution
// pixel k. With AGA selected Denise's picture comes one clock later than
// with OCS / ECS: 413 is the second clock of an OCS / ECS pixel and the
// first of an AGA one.
//
// SPDX-License-Identifier: GPL-3.0-or-later

module gb_video
#(
	parameter        H_START      = 12'd413,  // 28 MHz clocks from _hsync to the first pixel
	parameter        V_START      = 9'd41,    // lines from _vsync to the first line of the PAL display window
	parameter        V_START_NTSC = 9'd21
)
(
	input                   clk,          // 28 MHz
	input                   reset,
	input                   ntsc,
	input             [4:0] vpos,         // PAL: first of the window's 256 lines shown, 0..16
	input                   fit_height,   // PAL: all 256 lines, fitted to the screen by the framework
	input                   palette_mode, // 1: palette indices, 0: dithered colours
	input             [7:0] r_in,
	input             [7:0] g_in,
	input             [7:0] b_in,
	input                   hsync_n,
	input                   vsync_n,

	output            [9:0] index,        // palette index, or dithered 3 + 4 + 3 bit colour
	output                  de,
	output                  hblank,
	output                  vblank,
	output reg              fit,          // to the framework: show all 256 lines
	output reg              palette_on,   // to the framework: the pixels are palette indices

	// palette writes for the framework
	output                  pal_we,
	output            [9:0] pal_index,
	output           [23:0] pal_color,

	output           [19:0] fixed_pixels  // pixels of the last frame not in the palette
);

// the pixel stream before the palette: hblank_i / vblank_i / de_i
reg        de_i, hblank_i, vblank_i;
reg  [7:0] pr, pg, pb;
reg  [1:0] pbayer;

reg        hs_d, vs_d;
reg [11:0] hcnt;
reg  [8:0] vcnt;
reg        frame_seen;

wire hs_start = hs_d & ~hsync_n;
wire vs_start = vs_d & ~vsync_n;

wire  [8:0] v_first = ntsc ? V_START_NTSC : fit ? V_START : V_START + {4'd0, (vpos > 5'd16) ? 5'd16 : vpos};
wire  [8:0] v_lines = fit ? 9'd256 : 9'd240;
wire        line_on = frame_seen && (vcnt >= v_first) && (vcnt < v_first + v_lines);
wire [11:0] hrel    = hcnt - H_START;
wire        h_on    = (hcnt >= H_START) && (hcnt < H_START + 12'd1280);

// dither threshold for colours that find no palette entry: by the pixel's
// and the line's parity (a 2 x 2 Bayer matrix)
wire  [1:0] bayer  = {vcnt[0], hrel[1]} == 2'b00 ? 2'd0 :
                     {vcnt[0], hrel[1]} == 2'b01 ? 2'd2 :
                     {vcnt[0], hrel[1]} == 2'b10 ? 2'd3 : 2'd1;

always @(posedge clk) begin
	hs_d <= hsync_n;
	vs_d <= vsync_n;
	de_i <= 1'b0;

	if (reset) begin
		hcnt       <= 12'd0;
		vcnt       <= 9'd0;
		frame_seen <= 1'b0;
		hblank_i   <= 1'b1;
		vblank_i   <= 1'b1;
		fit        <= 1'b0;
		palette_on <= 1'b0;
	end
	else begin
		if (hs_start) begin
			hcnt   <= 12'd0;
			hblank_i <= 1'b1;
			if (vs_start) begin
				vcnt       <= 9'd0;
				frame_seen <= 1'b1;
				fit        <= fit_height & ~ntsc;   // only changes between frames
				palette_on <= palette_mode;
			end
			else if (vcnt != 9'h1FF) vcnt <= vcnt + 9'd1;
			// lines are counted at the start of _hsync: vblank only moves here
			vblank_i <= !(frame_seen && ((vs_start ? 9'd0 : vcnt + 9'd1) >= v_first) &&
			            ((vs_start ? 9'd0 : vcnt + 9'd1) < v_first + v_lines));
		end
		else begin
			if (hcnt != 12'hFFF) hcnt <= hcnt + 12'd1;
			if (vs_start) begin
				// _vsync starting away from _hsync (interlace): restart the count
				vcnt       <= 9'd0;
				frame_seen <= 1'b1;
				vblank_i   <= 1'b1;
			end
		end

		if (line_on && !vblank_i && h_on) begin
			hblank_i <= 1'b0;
			if (!hrel[0]) begin
				pr     <= r_in;
				pg     <= g_in;
				pb     <= b_in;
				pbayer <= bayer;
				de_i   <= 1'b1;
			end
		end
		else if (!hs_start && hcnt >= H_START + 12'd1280) hblank_i <= 1'b1;
	end
end

// colours -> palette indices (three clocks from de_i to de); the blanking
// goes with them
reg [2:0] hb_d, vb_d;
always @(posedge clk) begin
	hb_d <= reset ? 3'b111 : {hb_d[1:0], hblank_i};
	vb_d <= reset ? 3'b111 : {vb_d[1:0], vblank_i};
end
assign hblank = hb_d[2];
assign vblank = vb_d[2];

reg vb_prev;
always @(posedge clk) vb_prev <= vblank_i;

wire       pal_de;
wire [9:0] pal_out;

// dithered colours, three clocks like the palette's indices: a component c
// (0..255) becomes (c * levels + t) >> 8 with levels 7 (red, blue) or 15
// (green) and t one of 24, 88, 152, 216 by the pixel's and the line's
// parity (a 2 x 2 Bayer matrix), blue taking the thresholds in the opposite
// order to red (where a grey's red goes up a level its blue goes down, so
// the pattern is in the hue, not the brightness). Black and white are exact,
// and the green of every 12 bit colour.
function automatic [3:0] quant(input [7:0] c, input [3:0] levels, input [7:0] t);
	reg [11:0] v;
	begin
		v = c * levels + {4'd0, t};
		quant = v[11:8];
	end
endfunction
wire [3:0] dq_r = quant(pr, 4'd7,  {pbayer, 6'd24});
wire [3:0] dq_g = quant(pg, 4'd15, {pbayer, 6'd24});
wire [3:0] dq_b = quant(pb, 4'd7,  {~pbayer, 6'd24});
reg  [2:0] dd_de;
reg  [9:0] dd1, dd2, dd3;
always @(posedge clk) begin
	dd_de <= reset ? 3'd0 : {dd_de[1:0], de_i};
	dd1   <= {dq_r[2:0], dq_g, dq_b[2:0]};
	dd2   <= dd1;
	dd3   <= dd2;
end

assign de    = palette_on ? pal_de  : dd_de[2];
assign index = palette_on ? pal_out : dd3;

gb_palette palette
(
	.clk          (clk),
	.reset        (reset),
	.in_de        (de_i),
	.in_r         (pr),
	.in_g         (pg),
	.in_b         (pb),
	.in_bayer     (pbayer),
	.frame        (vblank_i & ~vb_prev),
	.out_de       (pal_de),
	.out_index    (pal_out),
	.pal_we       (pal_we),
	.pal_index    (pal_index),
	.pal_color    (pal_color),
	.fixed_pixels (fixed_pixels)
);

endmodule
