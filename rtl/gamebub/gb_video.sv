// Game Bub Minimig: Amiga video -> VideoV0 (320 x 240).
//
// Denise produces a new colour every 28 MHz clock (super hires grid). The
// Game Bub framework stores what the core sends into a 320 x 240 frame
// buffer and scales it by 2 onto the 640 x 480 area of the panel (or HDMI).
// This module:
//   - counts 28 MHz clocks from the start of _hsync and lines from the start
//     of _vsync,
//   - keeps a 320 low resolution pixel (1280 clock) window starting at
//     H_START, and 240 lines: in PAL 240 of the 256 lines of the standard
//     display window ($2C81), from its line vpos (0: its top 240 lines, 16:
//     its bottom 240); in NTSC its 200 lines with 20 lines above and below,
//   - outputs one pixel per low resolution pixel (every 4 clocks) as the
//     average of its two high resolution halves (lores: the same colour
//     twice; hires: both pixels blended so 640 wide screens stay legible),
//   - drives dataEnable for one clock per pixel, hblank outside the 320
//     pixels and vblank outside the 240 lines (vblank changes only while
//     hblank is high).
//
// H_START: a low resolution pixel is four clocks long, and the two clocks
// sampled (the first and the third after H_START + 4k) must both be inside
// it. With AGA selected Denise's picture comes one clock later than with
// OCS / ECS: 413 is inside the pixel for all three (the second and fourth
// clock of an OCS pixel, the first and third of an AGA one). At 412 every
// AGA pixel was blended with its neighbour.
//
// SPDX-License-Identifier: GPL-3.0-or-later

module gb_video
#(
	parameter        H_START      = 12'd413,  // 28 MHz clocks from _hsync to the first pixel
	parameter        V_START      = 9'd41,    // lines from _vsync to the first line of the PAL display window
	parameter        V_START_NTSC = 9'd21,
	parameter        R_BITS       = 5,
	parameter        G_BITS       = 6,
	parameter        B_BITS       = 5
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

reg  [7:0] ar, ag, ab;

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
			case (hrel[1:0])
				2'd0: begin ar <= r_in; ag <= g_in; ab <= b_in; end
				2'd2: begin
					r  <= ({1'b0, ar} + {1'b0, r_in}) >> (9 - R_BITS);
					g  <= ({1'b0, ag} + {1'b0, g_in}) >> (9 - G_BITS);
					b  <= ({1'b0, ab} + {1'b0, b_in}) >> (9 - B_BITS);
					de <= 1'b1;
				end
				default: ;
			endcase
		end
		else if (!hs_start && hcnt >= H_START + 12'd1280) hblank <= 1'b1;
	end
end

endmodule
