// gb_fb (the picture's two frames in the SRAM and block RAM, shown through
// the framework's external picture) with the SRAM model and the
// framework's video side (sim/rtl/sram_sim.sv, fw_video_sim.sv).
//
// A pixel stream timed as gb_video's (a pixel every other 28 MHz clock, 720
// of them in a line of 1820 clocks, 256 or with +nofit 240 lines of 312)
// carries a different picture every frame (a hash of frame, line and
// column). The framework's side decides where each frame goes and shows
// the panel (or with +hdmi HDMI); every pixel it shows is compared with the
// frames as it kept them, the SRAM model checks the pins' timing. In the
// middle the stream stops for some frames (the menu's pause) and goes on,
// and one line of one frame does not end (two lines' pixels in one).
// The clocks: clk_114 and clk_28 as the MMCM's, the screen's clock (25.95
// MHz, or 74.22 MHz for HDMI) with a phase of its own (+seed).
// SPDX-License-Identifier: GPL-3.0-or-later

`timescale 1ns/1ps

module tb_fb;

reg clk_114 = 0, clk_28 = 0, clk_57 = 0, mmcm_locked = 1;   // (xilinx_sim.sv's TB_TOP)
always #4.4035 clk_114 = ~clk_114;
reg [1:0] ckdiv = 0;
always @(posedge clk_114) begin
	ckdiv  <= ckdiv + 1'd1;
	clk_28 <= (ckdiv == 2'd3) || (ckdiv == 2'd0);
end

integer seed = 1;
integer frames_run = 14;
bit     hdmi = 0;
bit     fit = 1;
bit     ntsc = 0;         // frames of 262 lines (16.8 ms), 240 of them the picture's
real    av_half;
reg     clk_av = 0;
initial begin
	void'($value$plusargs("seed=%d", seed));
	void'($value$plusargs("frames=%d", frames_run));
	hdmi = $test$plusargs("hdmi");
	ntsc = $test$plusargs("ntsc");
	fit  = !$test$plusargs("nofit") && !ntsc;
	av_half = hdmi ? 6.7368 : 19.2664;
	#(0.37 * seed + 1.0);
	forever #(av_half) clk_av = ~clk_av;
end

reg reset = 1;
initial begin
	repeat (40) @(posedge clk_28);
	reset = 0;
end

// ---- the pixel stream
localparam LINE = 1820, H0 = 300;
wire [8:0] LINES = ntsc ? 9'd262 : 9'd312;
wire [8:0] V0    = ntsc ? 9'd20 : 9'd41;
reg [11:0] h = 0;
reg  [8:0] l = 0;
integer    frame = 0;
reg        stalled = 0;
reg        de = 0, hblank = 1, vblank = 1;
reg [17:0] data = 0;
wire [8:0] nlines = fit ? 9'd256 : 9'd240;

function automatic [17:0] pix(input integer f, input integer y, input integer x);
	reg [31:0] v;
	begin
		v = (f * 32'h9E3779B1) ^ (y * 32'h85EBCA6B) ^ (x * 32'hC2B2AE35);
		v = v ^ (v >> 15);
		v = v * 32'h2C1B3C6D;
		v = v ^ (v >> 12);
		pix = v[17:0];
	end
endfunction

always @(posedge clk_28) begin
	de <= 0;
	if (reset) begin h <= 0; l <= 0; hblank <= 1; vblank <= 1; end
	else begin
		if (h == LINE - 1) begin
			h <= 0;
			if (l == LINES - 1) begin
				l <= 0;
				frame <= frame + 1;
				// frames 7 to 9: no picture (the Amiga held)
				stalled <= (frame + 1 >= 7 && frame + 1 < 10);
			end
			else l <= l + 1'd1;
		end
		else h <= h + 1'd1;

		// vblank moves at a line's start, while hblank is high
		if (h == 0) vblank <= stalled || !(l >= V0 && l < V0 + nlines);
		if (!vblank && h >= H0 && h < H0 + 1440) begin
			hblank <= 0;
			if (!((h - H0) & 1)) begin
				de   <= 1;
				data <= pix(frame, l - V0, (h - H0) >> 1);
			end
		end
		// (frame 5, the line before the last: it does not end, as when the
		// Amiga's sync goes astray; its 720 pixels are kept, the last line's,
		// which come as more of it, are not, and the frame's last line stays
		// as it was)
		else if (h >= H0 + 1440 && !(frame == 5 && l == V0 + nlines - 2)) hblank <= 1;
	end
end

// ---- the framework's side, the SRAM, gb_fb
wire        wr_frame, wr_drop;
wire        ext_hdmi, ext_sync, ext_frame;
wire [10:0] ext_x;
wire  [9:0] ext_y;
wire [23:0] ext_color;
wire [31:0] v_errors, v_screens, v_frames, v_dropped;
wire [63:0] v_pixels, v_old;
wire        check;

fw_video_sim fw
(
	.clk_sys (clk_28), .reset (reset), .hdmi (hdmi),
	.de (de), .hblank (hblank), .vblank (vblank), .data (data), .fit (fit),
	.wr_frame (wr_frame), .wr_drop (wr_drop),
	.clk_av (clk_av), .ext_hdmi (ext_hdmi), .ext_x (ext_x), .ext_y (ext_y),
	.ext_sync (ext_sync), .ext_frame (ext_frame), .ext_color (ext_color),
	.check (check), .errors (v_errors), .pixels (v_pixels), .screens (v_screens),
	.frames_done (v_frames), .frames_dropped (v_dropped), .old_pixels (v_old)
);
// from the third frame completed: both frames have a picture
assign check = (v_frames >= 3);

wire        s_ce, s_we, s_oe, s_dir;
wire  [1:0] s_mask;
wire [17:0] s_a;
wire [15:0] s_din, s_dout;
wire [31:0] s_errors, s_writes, s_reads;
sram_sim sram
(
	.clk (clk_114), .ce_n (s_ce), .we_n (s_we), .oe_n (s_oe), .mask_n (s_mask), .a (s_a),
	.din (s_dout), .dir (s_dir), .dout (s_din),
	.errors (s_errors), .writes (s_writes), .reads (s_reads)
);

wire [15:0] dbg_lines, dbg_late;
wire        dbg_overflow;
gb_fb dut
(
	.clk_sys (clk_28), .reset (reset),
	.px_de (de), .px_data (data), .px_hblank (hblank), .px_vblank (vblank), .fit (fit),
	.wr_frame (wr_frame), .wr_drop (wr_drop),
	.clk_114 (clk_114), .reset_114 (reset),
	.sram_ceN (s_ce), .sram_weN (s_we), .sram_oeN (s_oe), .sram_writeMaskN (s_mask),
	.sram_address (s_a), .sram_dataIn (s_din), .sram_dataOut (s_dout), .sram_dataDir (s_dir),
	.clk_av (clk_av), .av_hdmi (ext_hdmi), .av_sync (ext_sync), .av_frame (ext_frame),
	.av_x (ext_x), .av_y (ext_y), .av_color (ext_color),
	.dbg_lines (dbg_lines), .dbg_late (dbg_late), .dbg_overflow (dbg_overflow)
);

// the write queue's deepest (not on the netlist: sim/gls/run_fb_gls.sh)
reg [3:0] q_max = 0;
`ifndef GLS
always @(posedge clk_114) if (dut.f_level > q_max) q_max <= dut.f_level;
`endif

integer want_screens;
initial begin
	wait (frame == frames_run);
	repeat (2000) @(posedge clk_28);
	$display("frames: %0d sent, %0d kept, %0d dropped; screen: %0d frames, %0d pixels compared, %0d as before their last write",
	         frame, v_frames, v_dropped, v_screens, v_pixels, v_old);
	$display("SRAM: %0d words written, %0d read, %0d timing errors; scan lines read %0d (mod 65536), late %0d; write queue up to %0d of 8%s",
	         s_writes, s_reads, s_errors, dbg_lines, dbg_late, q_max, dbg_overflow ? ", OVERFLOWED" : "");
	// the screen shows a frame for every one the core completes (the panel),
	// or 60 a second
	// (NTSC on the panel: every frame must be shown, none dropped for the
	// panel still showing the other; two are, around the frames without a
	// picture, as with PAL's)
	want_screens = hdmi ? (frames_run - 4) : (frames_run - 8);
	if (ntsc && !hdmi && v_dropped > 2) begin
		$display("FAIL: %0d frames dropped", v_dropped);
		want_screens = 1 << 30;
	end
	if (want_screens < 1) want_screens = 1;
	if (v_errors != 0 || s_errors != 0 || dbg_late != 0 || dbg_overflow || $signed(v_screens) < want_screens ||
	    (!hdmi && v_old != 0) || s_writes == 0 || s_reads == 0) begin
		$display("FAIL: %0d wrong pixels, %0d SRAM timing errors, %0d screen frames (at least %0d wanted)",
		         v_errors, s_errors, v_screens, want_screens);
		$display("TEST FAILED");
	end
	else $display("TEST PASSED");
	$finish;
end

endmodule
