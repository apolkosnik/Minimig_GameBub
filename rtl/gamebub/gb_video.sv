// Game Bub Minimig: Amiga video -> VideoV0 (640 x 240).
//
// Denise produces a new colour every 28 MHz clock (super hires grid). The
// Game Bub framework stores what the core sends into a 640 x 240 frame
// buffer and shows it one to one across and doubled down (640 x 480 of the
// 800 x 480 panel, or of HDMI's 720 x 480; patches/framework makes the
// framework scale the two directions separately). This module:
//   - counts 28 MHz clocks from the start of _hsync and lines from the start
//     of _vsync,
//   - keeps a 640 high resolution pixel (1280 clock) window starting at
//     H_START, and 240 lines: in PAL 240 of the 256 lines of the standard
//     display window ($2C81), from its line vpos (0: its top 240 lines, 16:
//     its bottom 240); in NTSC its 200 lines with 20 lines above and below,
//   - outputs one pixel per high resolution pixel (every 2 clocks): a 640
//     pixel wide screen as it is, a low resolution pixel twice, every other
//     pixel of a super high resolution one,
//   - reduces the colour to the frame buffer's 3 + 4 + 3 bits with an
//     ordered dither (the block RAM holds two 640 x 240 buffers of 10 bits),
//   - drives dataEnable for one clock per pixel, hblank outside the 640
//     pixels and vblank outside the 240 lines (vblank changes only while
//     hblank is high).
//
// H_START: the clock sampled (H_START + 2k) must be inside high resolution
// pixel k. With AGA selected Denise's picture comes one clock later than
// with OCS / ECS: 413 is the second clock of an OCS / ECS pixel and the
// first of an AGA one.
//
// Dither: a colour component c (0..255) becomes (c * levels + t) >> 8 with
// levels 7 (red, blue) or 15 (green) and t one of 24, 88, 152, 216 by the
// pixel's and the line's parity (a 2 x 2 Bayer matrix). Black and white are
// exact; so is the green of every 12 bit (OCS / ECS) colour, 0x11 * n giving
// n. Red and blue of a 12 bit colour fall on a 3 bit level or half way
// between two, and then alternate: for a low resolution pixel inside the
// pixel itself, between its two halves.
// Blue takes the thresholds in the opposite order to red.
//
// SPDX-License-Identifier: GPL-3.0-or-later

module gb_video
#(
	parameter        H_START      = 12'd413,  // 28 MHz clocks from _hsync to the first pixel
	parameter        V_START      = 9'd41,    // lines from _vsync to the first line of the PAL display window
	parameter        V_START_NTSC = 9'd21,
	parameter        R_BITS       = 3,
	parameter        G_BITS       = 4,
	parameter        B_BITS       = 3
)
(
	input                   clk,          // 28 MHz
	input                   reset,
	input                   ntsc,
	input             [4:0] vpos,         // PAL: first of the window's 256 lines shown, 0..16
	input             [7:0] r_in,
	input             [7:0] g_in,
	input             [7:0] b_in,
	input                   hsync_n,
	input                   vsync_n,

	output reg [R_BITS-1:0] r,
	output reg [G_BITS-1:0] g,
	output reg [B_BITS-1:0] b,
	output reg              de,
	output reg              hblank,
	output reg              vblank
);

reg        hs_d, vs_d;
reg [11:0] hcnt;
reg  [8:0] vcnt;
reg        frame_seen;

wire hs_start = hs_d & ~hsync_n;
wire vs_start = vs_d & ~vsync_n;

wire  [8:0] v_first = ntsc ? V_START_NTSC : V_START + {4'd0, (vpos > 5'd16) ? 5'd16 : vpos};
wire        line_on = frame_seen && (vcnt >= v_first) && (vcnt < v_first + 9'd240);
wire [11:0] hrel    = hcnt - H_START;
wire        h_on    = (hcnt >= H_START) && (hcnt < H_START + 12'd1280);

// ordered dither: threshold by the pixel's and the line's parity
wire  [1:0] bayer  = {vcnt[0], hrel[1]} == 2'b00 ? 2'd0 :
                     {vcnt[0], hrel[1]} == 2'b01 ? 2'd2 :
                     {vcnt[0], hrel[1]} == 2'b10 ? 2'd3 : 2'd1;
wire  [7:0] thr    = {bayer, 6'd24};                    // 24, 88, 152, 216
function automatic [3:0] quant(input [7:0] c, input [3:0] levels, input [7:0] t);
	reg [11:0] v;
	begin
		v = c * levels + {4'd0, t};
		quant = v[11:8];
	end
endfunction
wire  [3:0] qr = quant(r_in, (5'd1 << R_BITS) - 5'd1, thr);
wire  [3:0] qg = quant(g_in, (5'd1 << G_BITS) - 5'd1, thr);
// (blue against red: where a grey's red goes up a level its blue goes down,
// so the pattern is in the hue, where the eye sees it least, not in the
// brightness)
wire  [3:0] qb = quant(b_in, (5'd1 << B_BITS) - 5'd1, {~bayer, 6'd24});

always @(posedge clk) begin
	hs_d <= hsync_n;
	vs_d <= vsync_n;
	de   <= 1'b0;

	if (reset) begin
		hcnt       <= 12'd0;
		vcnt       <= 9'd0;
		frame_seen <= 1'b0;
		hblank     <= 1'b1;
		vblank     <= 1'b1;
	end
	else begin
		if (hs_start) begin
			hcnt   <= 12'd0;
			hblank <= 1'b1;
			if (vs_start) begin
				vcnt       <= 9'd0;
				frame_seen <= 1'b1;
			end
			else if (vcnt != 9'h1FF) vcnt <= vcnt + 9'd1;
			// lines are counted at the start of _hsync: vblank only moves here
			vblank <= !(frame_seen && ((vs_start ? 9'd0 : vcnt + 9'd1) >= v_first) &&
			            ((vs_start ? 9'd0 : vcnt + 9'd1) < v_first + 9'd240));
		end
		else begin
			if (hcnt != 12'hFFF) hcnt <= hcnt + 12'd1;
			if (vs_start) begin
				// _vsync starting away from _hsync (interlace): restart the count
				vcnt       <= 9'd0;
				frame_seen <= 1'b1;
				vblank     <= 1'b1;
			end
		end

		if (line_on && !vblank && h_on) begin
			hblank <= 1'b0;
			if (!hrel[0]) begin
				r  <= qr[R_BITS-1:0];
				g  <= qg[G_BITS-1:0];
				b  <= qb[B_BITS-1:0];
				de <= 1'b1;
			end
		end
		else if (!hs_start && hcnt >= H_START + 12'd1280) hblank <= 1'b1;
	end
end

endmodule
