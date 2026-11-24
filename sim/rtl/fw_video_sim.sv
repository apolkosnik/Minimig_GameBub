// The framework's video side for the benches, as HandheldTop (with
// patches/framework) and its rev 4 display driver (ILI9806E) have it, for a
// core that keeps the frames itself (VideoV0.ownFrames):
//
//   - the frame bookkeeping in the core's clock: which of the two frames
//     the core's pixels go to (wr_frame), whether a whole frame is thrown
//     away because the panel shows the frame it would go to (wr_drop), the
//     last frame completed;
//   - the screen: the panel (480 x 800, scanned in columns of the landscape
//     picture, a frame started when the core has completed one, as the
//     driver does it), or with `hdmi` the 1650 x 750 frame of 720p; and
//     from it the external picture's inputs: x, y, sync, frame;
//   - a check of what is shown: the core's colour (ext_color) in every
//     pixel of the screen against the frames as the bench keeps them from
//     the core's pixel stream (the pixels counted as the framework counts
//     them): on the panel line y / 2 (with `fit` y * 256 / 480) of the
//     frame the driver shows, column x - 12 of the 800 (black outside the
//     720); on HDMI line y / 3 (y * 256 / 720), column x * 9 / 16, of the
//     frame that was the last completed when the screen's frame began.
//     With `wide` (the core's 800 x 240 frames, gb_fb) a frame is 800 x
//     240, the panel's column x is its column x (all 800), and HDMI's
//     column x * 5 / 8; the external picture's x is the same (x - 12).
//     Each frame is compared as it was written (its own size: a frame
//     written before `wide` changed keeps the size it had; on HDMI the size
//     taken as the screen's frame begins, as the core does). A pixel of the
//     memory never written (a line that did not end leaves the next as it
//     was: after the size changed it may never have been) is not compared,
//     and counted (unwritten). On
//     the panel the frame shown is not written (wr_drop), so every pixel
//     must be the frame's; on HDMI it may be written while it is shown, and
//     a pixel may also be what it was before its last write.
//
// SPDX-License-Identifier: GPL-3.0-or-later

module fw_video_sim
#(
	parameter W = 720,
	parameter H = 256,
	parameter WW = 800,              // wide: a frame of 800 x 240
	parameter HW = 240,
	// ILI9806E at clockHz 25,952,381 (908.33 MHz / 35) for a source frame of
	// 16.7 ms at least (MinimigCore.scala: NTSC's; PAL's 20 ms is 970 lines)
	parameter TW = 536,              // clocks of a scan line
	parameter HS = 4, HBP = 50, HACT = 480,
	parameter VS = 4, VBP = 2, VACT = 800,
	parameter THMIN = 808, THMAX = 1061,
	parameter OFFX = 12,             // the picture's first column on the panel
	parameter LATENCY = 12
)
(
	input             clk_sys,
	input             reset,
	input             hdmi,          // HDMI is shown (steady)
	input             de,
	input             hblank,
	input             vblank,
	input      [17:0] data,
	input             fit,
	input             wide,          // (steady)
	output            wr_frame,
	output            wr_drop,

	input             clk_av,
	output            ext_hdmi,
	output reg [10:0] ext_x = 11'd0,
	output reg  [9:0] ext_y = 10'd0,
	output reg        ext_sync = 1'b0,
	output            ext_frame,
	input      [23:0] ext_color,

	input             check,         // compare what is shown
	output reg [31:0] errors = 32'd0,
	output reg [63:0] pixels = 64'd0,        // pixels compared
	output reg [31:0] screens = 32'd0,       // whole frames of the screen compared
	output reg [31:0] frames_done = 32'd0,   // frames the core completed
	output reg [31:0] frames_dropped = 32'd0,
	output reg [63:0] old_pixels = 64'd0,    // HDMI: pixels shown as they were before their last write
	output reg [31:0] shown_written = 32'd0, // pixels written to the frame the panel showed
	output reg [31:0] unwritten = 32'd0      // pixels shown from memory never written (not compared)
);

// ---------------------------------------------------------------------------
// the core's clock: frames written (HandheldTop, "Framebuffer writes")
// ---------------------------------------------------------------------------
reg        lastComplete = 1'b0;
reg        writeIndex = 1'b1;
reg        frameStarted = 1'b0;
reg        dropReg = 1'b0;
reg        vb_d = 1'b0, hb_d = 1'b0;
reg [10:0] fx = 11'd0;           // (the core keeps a line's first 720 (800) pixels and a frame's first
reg  [8:0] fy = 9'd0;            // 256 (240) lines: gb_fb)
// a frame's pixels (from frame 0 to frame 1: the larger of the two sizes)
localparam FS = (WW * HW > W * H) ? WW * HW : W * H;
wire [10:0] lw = wide ? 11'(WW) : 11'(W);
wire  [8:0] lh = wide ? 9'(HW) : 9'(H);
reg   [1:0] fwide = 2'b00;      // each frame's size as written
reg  [1:0] disp_s = 2'b00;
wire       displayReadingFrame;
// (the panel's driver, below: the frame it shows, its scan line)
reg        currentFrame = 1'b0;
reg [11:0] dy = 12'd0;

wire frameConflict = !hdmi && (writeIndex == disp_s[1]);
wire dropFrame     = !frameStarted ? frameConflict : dropReg;
assign wr_frame = writeIndex;
assign wr_drop  = dropFrame;

// the frames as written, and each pixel before its last write
reg [17:0] mem  [0:2*FS-1];
reg [17:0] prev [0:2*FS-1];
reg        seen [0:2*FS-1];
initial for (int i = 0; i < 2*FS; i++) seen[i] = 1'b0;
initial for (int i = 0; i < 2*FS; i++) begin mem[i] = 18'h3FFFF ^ i[17:0]; prev[i] = 18'h3FFFF ^ i[17:0]; end

wire [18:0] waddr = (writeIndex ? 19'(FS) : 19'd0) + fy * lw + fx;

always @(posedge clk_sys) begin
	vb_d   <= vblank;
	hb_d   <= hblank;
	disp_s <= {disp_s[0], displayReadingFrame};

	if (!vblank && de && !frameStarted) begin
		frameStarted <= 1'b1;
		dropReg      <= frameConflict;
	end
	if (de && !dropFrame && fx < lw && fy < lh) begin
		prev[waddr] <= mem[waddr];
		mem[waddr]  <= data;
		seen[waddr] <= 1'b1;
		fwide[writeIndex] <= wide;
		// the framework's rules keep a frame the panel shows from being written
		if (!hdmi && writeIndex == currentFrame && !reset) begin
			shown_written <= shown_written + 1'd1;
			if (shown_written < 4)
				$display("[video] at %0t: a pixel written to frame %0d while the panel shows it: line %0d pixel %0d, started %0d, the display's frame as the writer sees it %0d, panel line %0d, last completed %0d",
				         $time, writeIndex, fy, fx, frameStarted, disp_s[1], dy, lastComplete);
		end
	end
	if (vblank && !vb_d) begin
		if (!dropReg) begin
			lastComplete <= writeIndex;
			writeIndex   <= !writeIndex;
			frames_done  <= frames_done + 1'd1;
		end
		else frames_dropped <= frames_dropped + 1'd1;
		frameStarted <= 1'b0;
		dropReg      <= 1'b0;
	end

	if (vblank) begin
		fx <= 11'd0;
		fy <= 9'd0;
	end
	else if (hblank) begin
		if (!hb_d) begin
			fx <= 11'd0;
			if (fy < lh) fy <= fy + 1'd1;
		end
	end
	else if (de && fx < lw) fx <= fx + 1'd1;

	if (reset) begin
		lastComplete <= 1'b0;
		writeIndex   <= 1'b1;
		frameStarted <= 1'b0;
		dropReg      <= 1'b0;
	end
end

// ---------------------------------------------------------------------------
// the screen (clk_av)
// ---------------------------------------------------------------------------
reg  [1:0] last_s = 2'b00;
reg  [1:0] fit_s = 2'b00;
always @(posedge clk_av) begin
	last_s <= {last_s[0], lastComplete};
	fit_s  <= {fit_s[0], fit};
end
wire lastRendered = last_s[1];

// the panel's driver (ILI9806E.scala)
reg        locked = 1'b1;
reg        resyncReady = 1'b0;
reg        resyncWait = 1'b0;
reg        d_vsync = 1'b1;
reg        d_active = 1'b0;
reg  [9:0] dx = 10'd0;
wire       newFrameReady = (lastRendered != currentFrame);
wire [8:0] pixelX = 9'(dx - 10'(HS + HBP));
wire [9:0] pixelY = 10'(dy - 12'(VS + VBP));
wire       isVActive = (dy >= VS + VBP) && (dy < VS + VBP + VACT);

always @(posedge clk_av) begin
	reg startFrame;
	startFrame = 1'b0;
	if (reset || hdmi) begin
		// (HandheldTop holds the driver in reset while HDMI is shown)
		currentFrame <= 1'b0;
		locked       <= 1'b1;
		resyncReady  <= 1'b0;
		resyncWait   <= 1'b0;
		d_vsync      <= 1'b1;
		d_active     <= 1'b0;
		dx           <= 10'd0;
		dy           <= 12'd0;
	end
	else if (dx == TW - 1) begin
		dx <= 10'd0;
		dy <= dy + 1'd1;
		if (dy == VS - 1) d_vsync <= 1'b0;
		else if (dy >= THMIN - 1 && newFrameReady) begin
			if (resyncReady) begin
				resyncReady  <= 1'b0;
				resyncWait   <= 1'b1;
				currentFrame <= lastRendered;
			end
			else begin
				startFrame = 1'b1;
				resyncWait <= 1'b0;
				locked     <= 1'b1;
			end
		end
		else if (resyncWait) begin
			if (dy == THMAX * 2) begin
				locked     <= 1'b0;
				startFrame = 1'b1;
				resyncWait <= 1'b0;
			end
		end
		else if (!locked && dy >= THMIN - 1) startFrame = 1'b1;
		else if (dy == THMAX - 1) begin
			locked     <= 1'b0;
			startFrame = 1'b1;
		end
		if (dy < THMIN - 1 && newFrameReady) resyncReady <= 1'b1;
		if (startFrame) begin
			d_vsync      <= 1'b1;
			dy           <= 12'd0;
			currentFrame <= lastRendered;
		end
	end
	else begin
		dx <= dx + 1'd1;
		if (dx == HS + HBP - 1 && isVActive) d_active <= 1'b1;
		if (dx == HS + HBP + HACT - 1) d_active <= 1'b0;
	end
end

// HDMI: 1650 x 750
reg [10:0] cx = 11'd0;
reg  [9:0] cy = 10'd0;
reg        hdmiFrame = 1'b0;
reg        pulse_d = 1'b0;
wire [10:0] videoX = (cx >= 11'd1280) ? cx + 11'd398 : cx;
wire  [9:0] videoY = (cx >= 11'd1280) ? ((cy == 10'd749) ? 10'd0 : cy + 1'd1) : cy;
always @(posedge clk_av) begin
	cx <= (cx == 11'd1649) ? 11'd0 : cx + 1'd1;
	if (cx == 11'd1649) cy <= (cy == 10'd749) ? 10'd0 : cy + 1'd1;
	pulse_d <= (cy == 10'd749);
	if (cy == 10'd749 && !pulse_d) hdmiFrame <= lastRendered;
end

assign displayReadingFrame = hdmi ? hdmiFrame : currentFrame;

// the external picture's inputs
wire [9:0] dpiX = pixelY;            // the landscape picture: the panel's lines are its columns
wire [8:0] dpiY = pixelX;
assign ext_hdmi  = hdmi;
assign ext_frame = hdmi ? lastRendered : currentFrame;
always @(posedge clk_av) begin
	if (hdmi) begin
		ext_x    <= videoX + 11'(LATENCY);
		ext_y    <= videoY;
		ext_sync <= (cy >= 10'd720);
	end
	else begin
		ext_x    <= {1'b0, 10'(dpiX - 10'(OFFX))};
		ext_y    <= {1'b0, 9'(dpiY + 9'(LATENCY + 1))};
		ext_sync <= d_vsync;
	end
end

// ---------------------------------------------------------------------------
// what is shown
// ---------------------------------------------------------------------------
function automatic [23:0] rgb24(input [17:0] p);
	rgb24 = {p[17:12], p[17:16], p[11:6], p[11:10], p[5:0], p[5:4]};
endfunction

// HDMI: the frame taken as the screen's frame began (the clock ext_sync rises)
reg        sync_d = 1'b0;
reg        shownFrame = 1'b0;
reg        shownFit = 1'b0;
reg        shownWide = 1'b0;
reg        screen_ok = 1'b0;         // a whole frame of the screen is being compared
reg [31:0] screen_px = 32'd0;
reg        check_d = 1'b0;

task automatic bad(input string what, input int x, input int y, input [23:0] got, input [23:0] want);
	begin
		errors <= errors + 1'd1;
		if (errors < 16) $display("[video] ERROR %s (%0d,%0d): shown %06x, the frame has %06x", what, x, y, got, want);
	end
endtask

always @(posedge clk_av) begin
	int line, col, a;
	sync_d <= ext_sync;
	if (ext_sync && !sync_d) begin
		shownFrame <= ext_frame;
		shownFit   <= fit_s[1];
		shownWide  <= fwide[ext_frame];
		// the screen's frame that ends here
		if (screen_ok && check_d) begin
			if (screen_px == (hdmi ? 32'd1280 * 32'd720 : 32'd800 * 32'd480)) screens <= screens + 1'd1;
			else begin
				errors <= errors + 1'd1;
				$display("[video] ERROR a frame of the screen with %0d pixels", screen_px);
			end
		end
		screen_ok <= check;
		check_d   <= check;
		screen_px <= 32'd0;
	end
	else if (!check) screen_ok <= 1'b0;

	if (screen_ok && check && !reset) begin
		if (hdmi) begin
			// the hdmi module takes rgb one clock before the pixel's own
			if (cx >= 11'd1 && cx <= 11'd1280 && cy < 10'd720) begin
				line = shownFit ? (int'(cy) * 256) / 720 : int'(cy) / 3;
				col  = shownWide ? ((int'(cx) - 1) * 5) / 8 : ((int'(cx) - 1) * 9) / 16;
				a    = (shownFrame ? FS : 0) + line * (shownWide ? WW : W) + col;
				pixels    <= pixels + 1'd1;
				screen_px <= screen_px + 1'd1;
				if (!seen[a]) unwritten <= unwritten + 1'd1;
				else if (ext_color == rgb24(mem[a])) ;
				else if (ext_color == rgb24(prev[a])) old_pixels <= old_pixels + 1'd1;
				else bad("HDMI pixel", int'(cx) - 1, int'(cy), ext_color, rgb24(mem[a]));
			end
		end
		else if (d_active) begin
			line = shownFit ? (int'(dpiY) * 256) / 480 : int'(dpiY) / 2;
			col  = fwide[currentFrame] ? int'(dpiX) : int'(dpiX) - OFFX;
			a    = (currentFrame ? FS : 0) + line * (fwide[currentFrame] ? WW : W) + col;
			pixels    <= pixels + 1'd1;
			screen_px <= screen_px + 1'd1;
			if (col < 0 || col >= (fwide[currentFrame] ? WW : W)) begin
				if (ext_color != 24'd0) bad("panel pixel outside the picture", int'(dpiX), int'(dpiY), ext_color, 24'd0);
			end
			else if (!seen[a]) unwritten <= unwritten + 1'd1;
			else if (ext_color != rgb24(mem[a])) bad("panel pixel", int'(dpiX), int'(dpiY), ext_color, rgb24(mem[a]));
		end
	end
end

endmodule
