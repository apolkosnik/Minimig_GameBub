// Game Bub Minimig: Amiga video -> a pixel stream of 720 x 256 in 18 bits.
//
// Denise produces a new colour every 28 MHz clock (super hires grid). The
// core keeps what this module sends in two frames of 720 x 256 (gb_fb: the
// board's SRAM and block RAM) and shows them one to one across the panel's
// 720 visible columns (fitted across HDMI's 1280), and down either the
// first 240 lines twice each or, with `fit`, all 256 lines over the 480
// rows (seven lines of eight twice, one once; on HDMI over its 720). The
// framework takes the stream's dataEnable and blanking too: it decides
// which of the two frames a picture is written to (patches/framework).
// This module:
//   - counts 28 MHz clocks from the start of _hsync and lines from the start
//     of _vsync,
//   - keeps a 720 high resolution pixel (1440 clock) window, centred on
//     the display window (Denise's diw) of the frame before: starting at
//     H_START for the standard display window ($81..$1C1: its 640 pixels
//     and 40 either side), moved with an overscan screen so it is shown
//     whole however Overscan prefs place it (a window wider than 720
//     pixels loses its edges evenly); down, in PAL either all 256
//     lines of the standard display window ($2C81) (fit_height) or 240 of
//     them, from its line vpos (0: its top 240 lines, 16: its bottom 240);
//     in NTSC its 200 lines with 20 lines above and below,
//   - takes one pixel per high resolution pixel (every 2 clocks): a high
//     resolution screen as it is, a low resolution pixel twice, every other
//     pixel of a super high resolution one,
//   - sends each pixel as 18 bits (the two frames hold 18 bits a pixel,
//     not 24): 6 + 6 + 6 with an ordered dither of the two bits below, so
//     that a colour's average over four pixels is the Amiga's 24 bits,
//   - drives dataEnable for one clock per pixel, hblank outside the 720
//     pixels and vblank outside the lines (vblank changes only while
//     hblank is high),
//   - shows only the long fields of an interlaced screen (drop_field: the
//     short one): both fields would go to the same 256 lines, the picture
//     flickering between them at 25 Hz; vblank stays high through a short
//     field, so the framework neither writes it nor swaps its buffers.
//
// H_START: the clock sampled (H_START + 2k) must be inside high resolution
// pixel k. With AGA selected Denise's picture comes one clock later than
// with OCS / ECS: 333 is the second clock of an OCS / ECS pixel and the
// first of an AGA one (413, the standard window's first pixel, less 40
// pixels). The centred window moves in whole pixels (2 clocks), so this
// holds wherever it is. diw opens at clock 412 and closes at 1692 for the
// standard window with every chipset (W_SUM, their sum).
//
// SPDX-License-Identifier: GPL-3.0-or-later

module gb_video
#(
	parameter        H_START      = 12'd333,  // 28 MHz clocks from _hsync to the first pixel
	parameter        V_START      = 9'd41,    // lines from _vsync to the first line of the PAL display window
	parameter        V_START_NTSC = 9'd21,
	parameter        W_SUM        = 14'd2104  // opening + closing clock of the standard display window ($81..$1C1)
)
(
	input                   clk,          // 28 MHz
	input                   reset,
	input                   ntsc,
	input             [4:0] vpos,         // PAL: first of the window's 256 lines shown, 0..16
	input                   diw,          // Denise's horizontal display window, with r_in / g_in / b_in
	input                   drop_field,   // interlace: this field (the short one) is not shown
	input                   fit_height,   // PAL: all 256 lines, fitted to the screen by the framework
	input             [7:0] r_in,
	input             [7:0] g_in,
	input             [7:0] b_in,
	input                   hsync_n,
	input                   vsync_n,

	output           [17:0] data,         // dithered 6 + 6 + 6 bit colour (red 17:12, green 11:6, blue 5:0)
	output                  de,
	output                  hblank,
	output                  vblank,
	output reg              fit,          // show all 256 lines (taken at a frame's start)

	output           [23:0] dbg_color     // the Amiga's colour of the pixel sent (bench)
);

// the pixel stream before the dither: hblank_i / vblank_i / de_i
reg        de_i, hblank_i, vblank_i;
reg  [7:0] pr, pg, pb;
reg  [1:0] pbayer;

reg        hs_d, vs_d;
reg [11:0] hcnt;
reg  [8:0] vcnt;
reg        frame_seen;
reg [11:0] h_start;      // the window's first clock, set at each frame's start
reg [11:0] w_first, w_last;   // the earliest opening and the latest closing of the display window
reg        diw_d;
reg        skip;         // this frame is the dropped field of an interlaced picture

wire hs_start = hs_d & ~hsync_n;
wire vs_start = vs_d & ~vsync_n;

wire  [8:0] v_first = ntsc ? V_START_NTSC : fit ? V_START : V_START + {4'd0, (vpos > 5'd16) ? 5'd16 : vpos};
wire  [8:0] v_lines = fit ? 9'd256 : 9'd240;
wire        line_on = frame_seen && !skip && (vcnt >= v_first) && (vcnt < v_first + v_lines);
wire [11:0] hrel    = hcnt - h_start;
wire        h_on    = (hcnt >= h_start) && (hcnt < h_start + 12'd1440);

// the window centred on the display window seen in the frame: by the
// distance of its middle from the standard one's (W_SUM), in steps of a
// high resolution pixel (2 clocks: H_START's parity stays), kept to
// H_START - 168 .. H_START + 32: the picture comes 44 clocks after the
// beam (diw opens at 412 for $81, 92 low resolution pixels after _hsync
// starts), so Denise's blanking during _hsync ends at clock 160, and the
// line ends (_hsync again) at 1816. Kept as it is when the frame had no
// display window that opened and closed on the lines shown (DIWSTOP past
// the line's end: the window never closes)
wire        [13:0] w_sum   = {2'b00, w_first} + {2'b00, w_last};
wire signed [13:0] w_delta = $signed(w_sum) - $signed(W_SUM);
wire signed [11:0] w_steps = 12'((w_delta + 14'sd2) >>> 2);
wire signed [11:0] w_steps_c = (w_steps < -12'sd84) ? -12'sd84 : (w_steps > 12'sd16) ? 12'sd16 : w_steps;
wire        [11:0] h_start_new = (w_last > w_first) ? H_START + {w_steps_c[10:0], 1'b0} : h_start;

// dither threshold: by the pixel's and the line's parity (a 2 x 2 Bayer
// matrix)
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
		h_start    <= H_START;
		skip       <= 1'b0;
	end
	else begin
		if (hs_start) begin
			hcnt   <= 12'd0;
			hblank_i <= 1'b1;
			if (vs_start) begin
				vcnt       <= 9'd0;
				frame_seen <= 1'b1;
				fit        <= fit_height & ~ntsc;   // only changes between frames
				h_start    <= h_start_new;
				skip       <= drop_field;
			end
			else if (vcnt != 9'h1FF) vcnt <= vcnt + 9'd1;
			// lines are counted at the start of _hsync: vblank only moves here
			vblank_i <= !(frame_seen && !(vs_start ? drop_field : skip) && ((vs_start ? 9'd0 : vcnt + 9'd1) >= v_first) &&
			            ((vs_start ? 9'd0 : vcnt + 9'd1) < v_first + v_lines));
		end
		else begin
			if (hcnt != 12'hFFF) hcnt <= hcnt + 12'd1;
			if (vs_start) begin
				// _vsync starting away from _hsync (interlace): restart the count
				vcnt       <= 9'd0;
				frame_seen <= 1'b1;
				vblank_i   <= 1'b1;
				h_start    <= h_start_new;
				skip       <= drop_field;
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
		else if (!hs_start && hcnt >= h_start + 12'd1440) hblank_i <= 1'b1;
	end
end

// the display window on the lines shown: where it opens first and closes last
wire w_line = frame_seen && (vcnt >= v_first) && (vcnt < v_first + v_lines);
always @(posedge clk) begin
	diw_d <= diw;
	if (reset || vs_start) begin
		w_first <= 12'hFFF;
		w_last  <= 12'd0;
	end
	else if (w_line) begin
		if (diw & ~diw_d && hcnt < w_first) w_first <= hcnt;
		if (~diw & diw_d && hcnt > w_last)  w_last  <= hcnt;
	end
end

// the pixels as sent, three clocks after de_i; the blanking goes with them
reg [2:0] hb_d, vb_d;
always @(posedge clk) begin
	hb_d <= reset ? 3'b111 : {hb_d[1:0], hblank_i};
	vb_d <= reset ? 3'b111 : {vb_d[1:0], vblank_i};
end
assign hblank = hb_d[2];
assign vblank = vb_d[2];

// dithered colours. A 6 bit component k is shown as the 8 bits {k, k[5:4]}
// (gb_fb): those 64 values are sent as they are, in every pixel. A value c
// between two of them, d above the lower one (the two are 4 or 5 apart),
// is sent as the upper one in d of every four pixels: where d is above a
// threshold of 0..3 that the pixel's and the line's parity give (a 2 x 2
// Bayer matrix). Blue takes the thresholds in the opposite order to red
// and green (where a grey's red goes up a step its blue goes down, so the
// pattern is in the hue, not the brightness).
function automatic [5:0] quant(input [7:0] c, input [1:0] b);
	reg signed [2:0] e;      // c above {k0, k0[5:4]}, k0 = c[7:2]
	reg        [2:0] d;
	reg        [5:0] k0;
	begin
		k0 = c[7:2];
		e  = $signed({1'b0, c[1:0]}) - $signed({1'b0, k0[5:4]});
		if (e >= 0) begin
			d = e[2:0];
			quant = k0 + ((d > {1'b0, b}) ? 6'd1 : 6'd0);
		end
		else begin
			// below it: from the value before, 4 away, or 5 where its top
			// two bits differ
			d = e[2:0] + ((k0[3:0] == 4'd0) ? 3'd5 : 3'd4);
			quant = k0 - 6'd1 + ((d > {1'b0, b}) ? 6'd1 : 6'd0);
		end
	end
endfunction
wire [5:0] dq_r = quant(pr, pbayer);
wire [5:0] dq_g = quant(pg, pbayer);
wire [5:0] dq_b = quant(pb, ~pbayer);
reg  [2:0] dd_de;
reg [17:0] dd1, dd2, dd3;
reg [23:0] dc1, dc2, dc3;
always @(posedge clk) begin
	dd_de <= reset ? 3'd0 : {dd_de[1:0], de_i};
	dd1   <= {dq_r, dq_g, dq_b};
	dd2   <= dd1;
	dd3   <= dd2;
	dc1   <= {pr, pg, pb};
	dc2   <= dc1;
	dc3   <= dc2;
end

assign de        = dd_de[2];
assign data      = dd3;
assign dbg_color = dc3;

endmodule
