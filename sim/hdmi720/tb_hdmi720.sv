// The framework's generated HandheldTop (patches/framework, with the
// complete Minimig core in it, build/hdmi720/generated) on both screens:
// what reaches the HDMI encoder's TMDS output, and what reaches the panel's
// pins, against the pictures the core was sent. (From the 3DO core's test
// of the framework's 720p change, 3DO_GameBub sim/tb/tb_hdmi720.sv.)
//
// The core keeps the picture's two frames itself (gb_fb: the board's SRAM,
// here sim/rtl/sram_sim.sv on HandheldTop's SRAM pins, and block RAM) and
// shows them through the framework's external picture (patches/framework
// 0003, 0005). The bench puts a pixel stream timed as gb_video's in place
// of the Amiga's (the core's video outputs forced: 720 pixels a line, 256
// or 240 lines, 50 frames a second, a different picture every frame), and
// keeps the two frames as the framework says they are written
// (framebufferWriteIndex, dropFrame).
//
// HDMI (+mode=0, 1, 2): the framework's hdmi module instantiated exactly as
// in framework/verilog/handheld/top.sv (the instance is extracted from
// top.sv by sim/hdmi720/run_hdmi720.sh into hdmi_inst.svh); the TMDS
// symbols of the three channels are decoded as an HDMI sink would:
//   - control tokens, TERC4 data islands, guard bands and video periods;
//   - the sync timing against CEA-861 VIC 4 (1280x720p60: 1650 x 750 total,
//     hsync 40 after a 110 front porch, back porch 220, vsync 5 lines after
//     a 5-line front porch, back porch 20, both sync pulses active high),
//     with the hdmi module's one-pixel skew of the video period (DE_SKEW);
//   - every active pixel of whole frames: the 720 pixels fitted across all
//     1280 columns (column x shows pixel x * 9 / 16), and by +mode:
//       0: the first 240 lines, each three times;
//       1: the 256 lines spread over the 720 (fit: line y * 256 / 720);
//     of the frame that was the last completed when the screen's frame
//     began (a pixel may also be what it was before its last write: HDMI
//     runs at 60 frames a second and the frame shown may be written);
//       2: the core's external colour is forced to a pattern of the x / y
//          the framework presented VideoV0.externalLatency (12) clocks
//          before: every pixel of the 1280 x 720 screen must be the
//          pattern at its own position;
//     and the 360x240 pause-menu overlay scaled 3x and centred
//     (x 100..1179) over the picture;
//   - the data island packets: the AVI InfoFrame's VIC (must be 4), the
//     audio clock regeneration packets (N 6144, CTS from the real clocks:
//     6144 / 128 x 1546 = 74208 pixel clocks), and the audio samples sent
//     per frame (48 kHz from the 74.21875 MHz pixel clock: 48006 Hz,
//     about 800.6 samples per 59.966 Hz frame, four to a packet).
//
// The panel (+mode=3: all 256 lines fitted to the 480 rows; 4: the first
// 240 lines twice each): the DPI pins of the rev 4 display driver (480 x
// 800, scanned in columns of the landscape picture) and the 24 data pins.
// Every pixel of whole frames of the panel: scan line X, pixel Y of it is
// column X - 12, line Y * 256 / 480 (or Y / 2) of the frame the driver
// shows, which is never written while it is shown; black in the columns
// outside the 720; the overlay, twice its size, on top.
//
// What the test does instead of the firmware and the Amiga:
//   - the MCU's dock register write (docked, external screen; the HDMI
//     modes) is a force of the two HandheldTop control registers it sets;
//   - the core's pixel stream is forced (see above), and the overlay is
//     written directly with a pattern.
// The pixel clocks: 74.21875 MHz for HDMI, the frequency clk_wiz_hdmi.v
// makes (50 MHz / 4 x 59.375 / 10); 25.952 MHz for the panel (the core's
// MMCM: 908.33 MHz / 35).
//
// Plusargs: +frames=<n> frames of the screen to check (default 2),
// +mode=<0..4>.
//
// Copyright (c) 2026 Adam Polkosnik
// SPDX-License-Identifier: GPL-3.0-or-later

`timescale 1ns/1ps

module tb_hdmi720;
	// Core clocks, as the MMCM model (sim/rtl/xilinx_sim.sv) takes them:
	// 113.54 MHz and 28.385 MHz, clk_28 rising with every fourth clk_114
	// rising edge
	localparam real T_114 = 1000.0 / 113.541667;
	reg clk_114 = 0;
	reg clk_28 = 0;
	reg clk_57 = 0;                  // (CLKOUT5: the AP68040 variant's CPU clock)
	reg mmcm_locked = 0;
	integer half_114 = 0;
	always #(T_114 / 2.0) begin
		clk_114 = ~clk_114;
		half_114 = half_114 + 1;
		if (half_114 == 2 || half_114 == 4) clk_57 = ~clk_57;
		if (half_114 == 4) begin
			half_114 = 0;
			clk_28 = ~clk_28;
		end
	end
	initial #1000 mmcm_locked = 1;
	reg clk_in_50mhz = 0;
	always #10 clk_in_50mhz = ~clk_in_50mhz;

	// HDMI clocks: 74.21875 MHz and 5x (371.09375 MHz), edges aligned
	localparam real T_X5 = 1000.0 / 371.09375;
	reg clk_hdmi_x5 = 0;
	reg clk_hdmi = 0;
	integer half_count = 0;
	// clk_hdmi toggles every 5 half periods of clk_hdmi_x5: its rising edges
	// fall on rising edges of clk_hdmi_x5, as from one MMCM
	always #(T_X5 / 2.0) begin
		clk_hdmi_x5 = ~clk_hdmi_x5;
		half_count = half_count + 1;
		if (half_count == 5) begin
			half_count = 0;
			clk_hdmi = ~clk_hdmi;
		end
	end
	// the panel's pixel clock, and the screen under test
	integer mode = 0;
	initial if ($value$plusargs("mode=%d", mode)) ;
	wire panel = (mode >= 3);
	reg clk_dpi = 0;
	always #(1000.0 / 25.952381 / 2.0) clk_dpi = ~clk_dpi;
	wire clk_av = panel ? clk_dpi : clk_hdmi;

	// Names used by the hdmi instance extracted from top.sv
	logic hdmi_reset;
	logic hdmi_audio_clock;
	logic [15:0] hdmi_audio [1:0];
	logic [23:0] hdmi_rgb;
	logic [10:0] hdmi_cx;
	logic [9:0] hdmi_cy;
	logic hdmi_tmds_clock;
	logic [2:0] hdmi_tmds_data;
	pll_reset_generator hdmi_reset_gen(.clk(clk_hdmi), .clk_locked(1'b1), .reset(hdmi_reset));
`include "hdmi_inst.svh"

	// The framework top, with the core
	wire clk_sys_out, clk_sys_locked;
	wire reset;
	pll_reset_generator sys_reset_gen(.clk(clk_sys_out), .clk_locked(clk_sys_locked), .reset(reset));
	wire [1:0] sdram_cke, sdram_cs;
	wire        lcd_vsync, lcd_hsync, lcd_enable;
	wire  [7:0] lcd_r, lcd_g, lcd_b;
	wire        sram_ce, sram_we, sram_oe, sram_dir;
	wire  [1:0] sram_mask;
	wire [17:0] sram_a;
	wire [15:0] sram_q, sram_d;
	wire [31:0] sram_errors, sram_writes, sram_reads;
	sram_sim sram(
		.clk(clk_114), .ce_n(sram_ce), .we_n(sram_we), .oe_n(sram_oe), .mask_n(sram_mask), .a(sram_a),
		.din(sram_d), .dir(sram_dir), .dout(sram_q),
		.errors(sram_errors), .writes(sram_writes), .reads(sram_reads)
	);
	HandheldTop dut(
		.clock(clk_sys_out),
		.reset(reset),
		.io_clockIn50Mhz(clk_in_50mhz),
		.io_clockOutSys(clk_sys_out),
		.io_clockOutDpi(),
		.io_clockOutLocked(clk_sys_locked),
		.io_clock_av(clk_av),
		.io_mcuIrq(),
		.io_mcuSpiChipSelect(1'b1),
		.io_mcuSpiClock(1'b0),
		.io_mcuSpiDataIn(4'h0),
		.io_mcuSpiDataOut(),
		.io_mcuSpiDataDir(),
		.io_hdmiEnable(),
		.io_hdmiClockPowerDown(),
		.io_hdmiAudioClock(hdmi_audio_clock),
		.io_hdmiAudio_0(hdmi_audio[0]),
		.io_hdmiAudio_1(hdmi_audio[1]),
		.io_hdmiRgb(hdmi_rgb),
		.io_hdmiCx(hdmi_cx),
		.io_hdmiCy(hdmi_cy),
		.io_buttons_a(1'b0), .io_buttons_b(1'b0), .io_buttons_x(1'b0), .io_buttons_y(1'b0),
		.io_buttons_up(1'b0), .io_buttons_down(1'b0), .io_buttons_left(1'b0), .io_buttons_right(1'b0),
		.io_buttons_l(1'b0), .io_buttons_r(1'b0), .io_buttons_start(1'b0), .io_buttons_select(1'b0),
		.io_cartridge_switch(1'b0),
		.io_cartridge_bank0In(8'h0), .io_cartridge_bank1In(8'h0), .io_cartridge_bank2In(8'h0),
		.io_cartridge_bank3In(4'h0), .io_cartridge_pin30In(1'b0), .io_cartridge_pin31In(1'b0),
		.io_pmod_in(4'h0),
		.io_link_soIn(1'b0), .io_link_siIn(1'b0), .io_link_sdIn(1'b0), .io_link_scIn(1'b0),
		.io_lcd_vsync(lcd_vsync), .io_lcd_hsync(lcd_hsync), .io_lcd_enable(lcd_enable), .io_lcd_dotclk(),
		.io_lcdDataR(lcd_r), .io_lcdDataG(lcd_g), .io_lcdDataB(lcd_b),
		.io_sram_ceN(sram_ce), .io_sram_weN(sram_we), .io_sram_oeN(sram_oe), .io_sram_writeMaskN(sram_mask),
		.io_sram_address(sram_a), .io_sram_dataIn(sram_q), .io_sram_dataOut(sram_d), .io_sram_dataDir(sram_dir),
		.io_sdram_cke(sdram_cke), .io_sdram_cs(sdram_cs),
		.io_sdram_dataIn(16'h0)
	);

	// ------------------------------------------------------------------
	// Test pattern
	// ------------------------------------------------------------------
	localparam int FB_W = 720, FB_H = 256, OV_W = 360, OV_H = 240;
	localparam int SCALE = 3;                           // the overlay's on HDMI
	localparam int OV_X0 = (1280 - OV_W * SCALE) / 2;  // 100
	localparam int P_X0 = 12;                           // the picture's and the overlay's first column on the panel
	wire fit = (mode == 1 || mode == 3);

	// ---- the pixel stream, as gb_video times it
	// (a PAL line is 227.5 colour clocks: 1820 of the 28 MHz clock, 49.9 frames
	// a second; the panel, built for 50, takes 19.99 ms a frame at least)
	localparam int LINE = 1820, LINES = 312, H0 = 300, V0 = 41;
	reg [11:0] sh = 0;
	reg  [8:0] sl = 0;
	integer    sframe = 0;
	reg        s_de = 0, s_hb = 1, s_vb = 1;
	reg [17:0] s_data = 0;
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
	always @(posedge clk_sys_out) begin
		s_de <= 0;
		if (reset !== 1'b0) begin sh <= 0; sl <= 0; s_hb <= 1; s_vb <= 1; end
		else begin
			if (sh == LINE - 1) begin
				sh <= 0;
				if (sl == LINES - 1) begin sl <= 0; sframe <= sframe + 1; end
				else sl <= sl + 1'd1;
			end
			else sh <= sh + 1'd1;
			if (sh == 0) s_vb <= !(sl >= V0 && sl < V0 + nlines);
			if (!s_vb && sh >= H0 && sh < H0 + 1440) begin
				s_hb <= 0;
				if (!((sh - H0) & 1)) begin
					s_de   <= 1;
					s_data <= pix(sframe, sl - V0, (sh - H0) >> 1);
				end
			end
			else if (sh >= H0 + 1440) s_hb <= 1;
		end
	end

	// ---- the two frames as the framework has them written, and every
	// pixel before its last write
	reg [17:0] fmem  [0:2*FB_W*FB_H-1];
	reg [17:0] fprev [0:2*FB_W*FB_H-1];
	reg  [9:0] fx = 0;
	reg  [8:0] fy = 0;
	reg        fvb_d = 1, fhb_d = 1;
	integer    frames_kept = 0;
	wire [18:0] fa = (dut.framebufferWriteIndex ? FB_W * FB_H : 0) + fy * FB_W + fx;
	always @(posedge clk_sys_out) begin
		fvb_d <= s_vb;
		fhb_d <= s_hb;
		if (s_de && !dut.dropFrame && fy < FB_H && fx < FB_W) begin
			fprev[fa] <= fmem[fa];
			fmem[fa]  <= s_data;
		end
		if (s_vb && !fvb_d && !dut.regDropFrame) frames_kept <= frames_kept + 1;
		if (s_vb) begin fx <= 0; fy <= 0; end
		else if (s_hb) begin if (!fhb_d) begin fx <= 0; if (fy < FB_H) fy <= fy + 1'd1; end end
		else if (s_de && fx < FB_W) fx <= fx + 1'd1;
	end
	// both frames have a picture
	wire pictures = (frames_kept >= 3);

	function automatic [23:0] rgb24(input [17:0] q);
		rgb24 = {q[17:12], q[17:16], q[11:6], q[11:10], q[5:0], q[5:4]};
	endfunction
	// 2-bit overlay: a grid of lines, 0 (transparent) elsewhere
	function automatic [1:0] ov_pixel(input int x, input int y);
		if (x % 37 == 5 || y % 23 == 7) ov_pixel = 2'((x + y) % 3 + 1);
		else ov_pixel = 2'd0;
	endfunction
	function automatic [23:0] ov_rgb(input [1:0] o);
		reg [7:0] lum;
		begin
			lum = o == 2'd1 ? 8'h00 : o == 2'd2 ? 8'h80 : 8'hFF;
			ov_rgb = {lum, lum, lum};
		end
	endfunction
	// mode 2: the core's picture, a colour for every pixel of the frame
	function automatic [23:0] ext_pixel(input int x, input int y);
		ext_pixel = {8'(x * 5 + y * 3), 8'(x ^ (y << 1)), 8'(y * 7 + (x >> 3))};
	endfunction

	// HDMI: the frame taken as the screen's frame began (as the core takes it)
	reg hsync_d = 0;
	reg hdmi_shown = 0;
	always @(posedge clk_av) begin
		hsync_d <= dut.core_io_video_external_sync_REG;
		if (dut.core_io_video_external_sync_REG && !hsync_d) hdmi_shown <= dut._lastFrameComplete_cdc_io_destOutput;
	end
	// pixel (x, y) of the HDMI screen: 1 as the frame has it, 2 as it was
	// before its last write, 0 neither
	integer old_pixels = 0;
	function automatic int hdmi_match(input int x, input int y, input [23:0] got);
		reg [1:0] o;
		int a;
		begin
			hdmi_match = 0;
			o = 2'd0;
			if (x >= OV_X0 && x < OV_X0 + OV_W * SCALE) o = ov_pixel((x - OV_X0) / SCALE, y / SCALE);
			if (o != 0) hdmi_match = (got === ov_rgb(o)) ? 1 : 0;
			else if (mode == 2) hdmi_match = (got === ext_pixel(x, y)) ? 1 : 0;
			else begin
				a = (hdmi_shown ? FB_W * FB_H : 0) + (fit ? y * 256 / 720 : y / 3) * FB_W + x * FB_W / 1280;
				if (got === rgb24(fmem[a])) hdmi_match = 1;
				else if (got === rgb24(fprev[a])) hdmi_match = 2;
			end
		end
	endfunction
	function automatic [23:0] hdmi_want(input int x, input int y);
		int a;
		begin
			a = (hdmi_shown ? FB_W * FB_H : 0) + (fit ? y * 256 / 720 : y / 3) * FB_W + x * FB_W / 1280;
			hdmi_want = (mode == 2) ? ext_pixel(x, y) : rgb24(fmem[a]);
		end
	endfunction

	initial begin
		$display("mode %0d: %s", mode, mode == 0 ? "HDMI, 240 lines" : mode == 1 ? "HDMI, 256 lines fit" :
			mode == 2 ? "HDMI, the core's external colour forced" : mode == 3 ? "the panel, 256 lines fit" : "the panel, 240 lines");
		#1;
		for (int y = 0; y < OV_H; y++)
			for (int x = 0; x < OV_W; x++)
				dut.overlayFramebuffer_sram_ext.Memory[y * OV_W + x] = ov_pixel(x, y);
		// the stream in place of the Amiga's
		force dut.core.extModule.video_dataEnable = s_de;
		force dut.core.extModule.video_hblank = s_hb;
		force dut.core.extModule.video_vblank = s_vb;
		force dut.core.extModule.video_data = s_data;
		force dut.core.extModule.video_fit = fit;
		if (mode == 2) force dut._core_io_video_external_color = ext_color;
	end

	// mode 2: the colour of the pixel the framework named 12 clocks ago
	localparam int EXT_LATENCY = 12;
	reg  [10:0] ext_dx [0:EXT_LATENCY-1];
	reg   [9:0] ext_dy [0:EXT_LATENCY-1];
	always @(posedge clk_av) begin
		ext_dx[0] <= dut.core_io_video_external_x_REG;
		ext_dy[0] <= dut.core_io_video_external_y_REG;
		for (int i = 1; i < EXT_LATENCY - 1; i++) begin
			ext_dx[i] <= ext_dx[i - 1];
			ext_dy[i] <= ext_dy[i - 1];
		end
	end
	// the 12th register: the colour itself
	reg  [23:0] ext_color = 24'd0;
	always @(posedge clk_av)
		ext_color <= ext_pixel(int'(ext_dx[EXT_LATENCY - 2]), int'(ext_dy[EXT_LATENCY - 2]));

	// The MCU's dock register: docked, picture on the external screen
	initial begin
		wait (reset === 1'b0);
		repeat (10) @(posedge clk_sys_out);
		if (!panel) begin
			force dut.controlDock_docked = 1'b1;
			force dut.controlDock_useInternalScreen = 1'b0;
		end
	end

	// ------------------------------------------------------------------
	// TMDS receiver
	// ------------------------------------------------------------------
	localparam [9:0] CTL0 = 10'b1101010100, CTL1 = 10'b0010101011,
		CTL2 = 10'b0101010100, CTL3 = 10'b1010101011;
	localparam [9:0] VGB_02 = 10'b1011001100, VGB_1 = 10'b0100110011, DGB_12 = 10'b0100110011;
	// The hdmi module (hdl-util) starts its video period one pixel after the
	// CEA-861 position against its syncs (the syncs are registered once,
	// the video period twice): active video 261 pixels after the hsync rise,
	// back porch 221, front porch 109, at every VIC (480p too). A sink takes
	// the active picture from the video guard band; its width stays 1280.
	localparam int DE_SKEW = 1;

	function automatic int ctl_decode(input [9:0] s);   // -1: not a control token
		case (s)
			CTL0: ctl_decode = 0;
			CTL1: ctl_decode = 1;
			CTL2: ctl_decode = 2;
			CTL3: ctl_decode = 3;
			default: ctl_decode = -1;
		endcase
	endfunction
	// TERC4, HDMI 1.4b table 5-13
	function automatic int terc4_decode(input [9:0] s);  // -1: not TERC4
		case (s)
			10'b1010011100: terc4_decode = 0;
			10'b1001100011: terc4_decode = 1;
			10'b1011100100: terc4_decode = 2;
			10'b1011100010: terc4_decode = 3;
			10'b0101110001: terc4_decode = 4;
			10'b0100011110: terc4_decode = 5;
			10'b0110001110: terc4_decode = 6;
			10'b0100111100: terc4_decode = 7;
			10'b1011001100: terc4_decode = 8;
			10'b0100111001: terc4_decode = 9;
			10'b0110011100: terc4_decode = 10;
			10'b1011000110: terc4_decode = 11;
			10'b1010001110: terc4_decode = 12;
			10'b1001110001: terc4_decode = 13;
			10'b0101100011: terc4_decode = 14;
			10'b1011000011: terc4_decode = 15;
			default: terc4_decode = -1;
		endcase
	endfunction
	// TMDS video symbol to 8 bits (DVI 1.0 section 3.3.3)
	function automatic [7:0] tmds_decode(input [9:0] q);
		reg [7:0] d;
		d = q[9] ? ~q[7:0] : q[7:0];
		tmds_decode[0] = d[0];
		for (int i = 1; i < 8; i++)
			tmds_decode[i] = q[8] ? d[i] ^ d[i - 1] : ~(d[i] ^ d[i - 1]);
	endfunction

	integer errors = 0;
	integer max_report = 20;
	integer pixel_errors = 0;
	task automatic fail(input string msg);
		errors = errors + 1;
		if (errors <= max_report) $display("ERROR @%0t: %s", $time, msg);
	endtask

	// S_ACQ: until the first control token (the receiver starts mid-stream)
	typedef enum int {S_ACQ, S_CTRL, S_VGUARD, S_VIDEO, S_DGUARD, S_ISLAND, S_DTRAIL} rx_state_t;
	rx_state_t st = S_ACQ;
	integer guard_n = 0;
	integer island_sym = 0;
	reg hs = 0, vs = 0, hs_prev = 0, vs_prev = 0;
	// Positions in symbols
	longint sym = 0;
	longint hs_rise = -1, vs_rise = -1, hs_fall_len = 0;
	longint line_start_sym = -1;
	// Per line and per frame state
	integer line_video = 0;          // video symbols in the current line
	integer frame_lines = 0;         // hsync rises since vsync rise
	integer active_y = -1;           // active line index in the frame (-1: before the first)
	integer active_lines = 0;
	integer video_start_off = -1;    // symbols from hsync rise to the first video symbol of the line
	longint first_active_from_vs = -1;
	integer frames_seen = 0;         // complete frames (vsync rise to vsync rise)
	integer frames_target = 2;
	integer frame_checking = 0;      // frames whose pixels are checked (after the first vsync)
	longint pixels_checked = 0;
	// Packets
	reg [31:0] pk_hdr;
	reg [63:0] pk_sub [4];
	integer avi_count = 0, acr_count = 0, samples_in_frame = 0;
	integer frame_samples [8];
	integer audio_total = 0, audio_frames = 0;
	integer acr_bad = 0;
	integer avi_bad = 0;

	task automatic packet_done();
		reg [7:0] typ;
		reg [19:0] n, cts;
		typ = pk_hdr[7:0];
		if (typ == 8'h82) begin
			avi_count++;
			if (pk_sub[0][38:32] !== 7'd4) begin
				avi_bad++;
				fail($sformatf("AVI InfoFrame VIC %0d, expected 4", pk_sub[0][38:32]));
			end
		end else if (typ == 8'h01) begin
			acr_count++;
			cts = {pk_sub[0][11:8], pk_sub[0][23:16], pk_sub[0][31:24]};
			n = {pk_sub[0][35:32], pk_sub[0][47:40], pk_sub[0][55:48]};
			// The first CTS is measured over a partial period after reset
			if (acr_count > 2 && (n !== 20'd6144 || cts < 20'd74207 || cts > 20'd74209)) begin
				acr_bad++;
				fail($sformatf("ACR N %0d CTS %0d, expected N 6144 CTS 74208 +-1", n, cts));
			end
			if (acr_count == 3) $display("ACR: N %0d CTS %0d", n, cts);
		end else if (typ == 8'h02) begin
			samples_in_frame += $countones(pk_hdr[11:8]);
		end
	endtask

	// On a vsync rise: close the frame
	task automatic frame_end();
		if (vs_rise >= 0) begin
			if (sym - vs_rise != 1650 * 750)
				fail($sformatf("frame length %0d symbols, expected %0d", sym - vs_rise, 1650 * 750));
			if (frame_lines != 750)
				fail($sformatf("%0d lines in the frame, expected 750", frame_lines));
			if (active_lines != 720)
				fail($sformatf("%0d active lines, expected 720", active_lines));
			if (first_active_from_vs != 25 * 1650 + 260 + DE_SKEW)
				fail($sformatf("first active pixel %0d symbols after the vsync rise, expected %0d",
					first_active_from_vs, 25 * 1650 + 260 + DE_SKEW));
			if (frames_seen < 8) frame_samples[frames_seen] = samples_in_frame;
			$display("frame %0d: %0d lines, %0d active, %0d audio samples, %0d pixels checked so far",
				frames_seen, frame_lines, active_lines, samples_in_frame, pixels_checked);
			// The first frame after the receiver locks may start mid-stream.
			// 800.6 samples a frame, sent four to a packet: 800 in most
			// frames and 804 in about one of six (seen at 99 ms whatever
			// the picture is); the total must stay within a packet of the
			// rate
			if (frames_seen > 0) begin
				audio_total += samples_in_frame;
				audio_frames++;
				if (samples_in_frame < 799 || samples_in_frame > 804)
					fail($sformatf("%0d audio samples in the frame, expected 800 to 804", samples_in_frame));
				if (audio_total < audio_frames * 800.64 - 5.0 || audio_total > audio_frames * 800.64 + 5.0)
					fail($sformatf("%0d audio samples in %0d frames, expected 800.64 a frame", audio_total, audio_frames));
			end
			frames_seen++;
		end
		vs_rise = sym;
		frame_lines = 0;
		active_y = -1;
		active_lines = 0;
		first_active_from_vs = -1;
		samples_in_frame = 0;
	endtask

	// Synchronise the receiver to the HDMI module's settled state: once the
	// dock register reached the video clock domain and the hdmi reset ended
	reg rx_enable = 0;
	initial begin
		wait (dut.controlDock_docked === 1'b1);
		repeat (20000) @(posedge clk_hdmi);
		// (the pictures: once both frames have one)
		if (mode != 2) wait (pictures);
		rx_enable = 1;
	end

	always @(posedge clk_hdmi) if (rx_enable) begin
		reg [9:0] s0, s1, s2;
		int c0, t0, t1, t2;
		s0 = hdmi.tmds_internal[0];
		s1 = hdmi.tmds_internal[1];
		s2 = hdmi.tmds_internal[2];
		c0 = ctl_decode(s0);
		t0 = terc4_decode(s0);
		t1 = terc4_decode(s1);
		t2 = terc4_decode(s2);

		// Classify the symbol
		case (st)
		S_ACQ: begin
			if (c0 >= 0) begin
				st = S_CTRL;
				{vs, hs} = 2'(c0);
				hs_prev = hs;
				vs_prev = vs;
			end
		end
		S_CTRL, S_VGUARD, S_DGUARD: begin
			if (s0 == VGB_02 && s1 == VGB_1 && s2 == VGB_02) begin
				if (st != S_VGUARD) guard_n = 0;
				st = S_VGUARD;
				guard_n++;
			end else if (s1 == DGB_12 && s2 == DGB_12 && t0 >= 12) begin
				if (st != S_DGUARD) guard_n = 0;
				st = S_DGUARD;
				guard_n++;
				{vs, hs} = 2'(t0);
			end else if (st == S_VGUARD) begin
				if (guard_n != 2) fail($sformatf("video guard band of %0d symbols", guard_n));
				st = S_VIDEO;
			end else if (st == S_DGUARD) begin
				if (guard_n != 2) fail($sformatf("data island leading guard band of %0d symbols", guard_n));
				st = S_ISLAND;
				island_sym = 0;
			end else if (c0 < 0) begin
				fail($sformatf("unexpected symbols %h %h %h in a control period", s0, s1, s2));
			end
			if (st == S_CTRL && c0 >= 0) {vs, hs} = 2'(c0);
		end
		S_VIDEO: begin
			if (c0 >= 0) begin
				st = S_CTRL;
				{vs, hs} = 2'(c0);
			end
		end
		S_ISLAND: begin
			if (s1 == DGB_12 && s2 == DGB_12 && t0 >= 12) begin
				if (island_sym % 32 != 0) fail($sformatf("data island of %0d symbols", island_sym));
				st = S_DTRAIL;
				guard_n = 1;
				{vs, hs} = 2'(t0);
			end
		end
		S_DTRAIL: begin
			if (s1 == DGB_12 && s2 == DGB_12 && t0 >= 12) begin
				guard_n++;
				{vs, hs} = 2'(t0);
			end else begin
				if (guard_n != 2) fail($sformatf("data island trailing guard band of %0d symbols", guard_n));
				st = S_CTRL;
				if (c0 < 0) fail("no control period after a data island");
				else {vs, hs} = 2'(c0);
			end
		end
		endcase

		// Data island symbols
		if (st == S_ISLAND) begin
			int k;
			if (t0 < 0 || t1 < 0 || t2 < 0)
				fail($sformatf("non-TERC4 symbols %h %h %h in a data island", s0, s1, s2));
			{vs, hs} = 2'(t0);
			k = island_sym % 32;
			if (k == 0) begin
				pk_hdr = 0;
				for (int j = 0; j < 4; j++) pk_sub[j] = 0;
			end
			pk_hdr[k] = 1'((t0 >> 2) & 1);
			for (int j = 0; j < 4; j++) begin
				pk_sub[j][2 * k] = 1'((t1 >> j) & 1);
				pk_sub[j][2 * k + 1] = 1'((t2 >> j) & 1);
			end
			if (k == 31) packet_done();
			island_sym++;
		end

		// Sync edges
		if (hs && !hs_prev) begin
			if (hs_rise >= 0 && sym - hs_rise != 1650)
				fail($sformatf("line of %0d symbols, expected 1650", sym - hs_rise));
			// The previous line's video
			if (line_video != 0 && line_video != 1280)
				fail($sformatf("line with %0d video symbols, expected 1280", line_video));
			hs_rise = sym;
			line_video = 0;
			video_start_off = -1;
			frame_lines++;
		end
		if (!hs && hs_prev && hs_rise >= 0 && sym - hs_rise != 40)
			fail($sformatf("hsync of %0d symbols, expected 40", sym - hs_rise));
		if (vs && !vs_prev) begin
			if (!(hs && !hs_prev)) fail("vsync rise not at an hsync rise");
			frame_end();
			if (frames_seen >= frames_target + 1) begin
				$display("%0d frames, %0d pixels checked, %0d AVI InfoFrames, %0d ACR packets",
					frames_target, pixels_checked, avi_count, acr_count);
				if (pixels_checked != longint'(frames_target) * 1280 * 720)
					fail($sformatf("%0d pixels checked, expected %0d", pixels_checked,
						longint'(frames_target) * 1280 * 720));
				if (avi_count < frames_target) fail("no AVI InfoFrame in every frame");
				if (acr_count < frames_target * 15) fail("too few ACR packets");
				finish_report();
			end
		end
		if (!vs && vs_prev && vs_rise >= 0 && sym - vs_rise != 5 * 1650)
			fail($sformatf("vsync of %0d symbols, expected %0d", sym - vs_rise, 5 * 1650));

		// Video pixels
		if (st == S_VIDEO) begin
			reg [23:0] got, exp;
			if (line_video == 0) begin
				if (hs_rise >= 0 && sym - hs_rise != 260 + DE_SKEW)
					fail($sformatf("active video %0d symbols after the hsync rise, expected %0d", sym - hs_rise, 260 + DE_SKEW));
				active_y++;
				active_lines++;
				if (active_y == 0 && vs_rise >= 0) first_active_from_vs = sym - vs_rise;
			end
			got = {tmds_decode(s2), tmds_decode(s1), tmds_decode(s0)};
			if (frames_seen >= 1 && vs_rise >= 0 && active_y >= 0 && active_y < 720 && line_video < 1280) begin
				int m;
				m = hdmi_match(line_video, active_y, got);
				if (m == 2) old_pixels++;
				if (m == 0) begin
					exp = hdmi_want(line_video, active_y);
					pixel_errors++;
					if (pixel_errors <= 10)
						$display("PIXEL (%0d, %0d): %h, expected %h (x-1: %h, x+1: %h)", line_video, active_y, got, exp,
							hdmi_want(line_video - 1, active_y), hdmi_want(line_video + 1, active_y));
					fail($sformatf("pixel (%0d, %0d): %h, expected %h", line_video, active_y, got, exp));
				end
				pixels_checked++;
			end
			line_video++;
		end

		hs_prev = hs;
		vs_prev = vs;
		sym++;
	end

	// ------------------------------------------------------------------
	// The panel's pins
	// ------------------------------------------------------------------
	reg        lv_d = 1, le_d = 0;
	integer    lcd_line = -1, lcd_px = 0;
	integer    lcd_frames = 0;           // whole frames of the panel compared
	reg        lcd_checking = 0;
	longint    lcd_frame_px = 0;
	always @(posedge clk_dpi) if (panel) begin
		reg [23:0] got, want;
		reg  [1:0] o;
		int col, a;
		lv_d <= lcd_vsync;
		le_d <= lcd_enable;
		if (lcd_vsync && !lv_d) begin
			// a frame of the panel begins: the one before it is complete
			if (lcd_checking) begin
				if (lcd_frame_px != 800 * 480)
					fail($sformatf("a frame of the panel with %0d pixels, expected %0d", lcd_frame_px, 800 * 480));
				lcd_frames++;
				$display("panel frame %0d at %0d ms: %0d pixels checked so far, %0d of the core's frames kept", lcd_frames, $time / 1000000, pixels_checked, frames_kept);
				if (lcd_frames >= frames_target) finish_report();
			end
			lcd_checking <= pictures;
			lcd_line     <= -1;
			lcd_frame_px <= 0;
		end
		else if (lcd_enable) begin
			int x, y;
			x = le_d ? lcd_line : lcd_line + 1;
			y = le_d ? lcd_px : 0;
			if (!le_d) lcd_line <= lcd_line + 1;
			lcd_px <= y + 1;
			if (lcd_checking) begin
				got = {lcd_r, lcd_g, lcd_b};
				col = x - P_X0;
				want = 24'd0;
				if (col >= 0 && col < FB_W) begin
					a = (dut.driver.currentFrame ? FB_W * FB_H : 0) + (fit ? y * 256 / 480 : y / 2) * FB_W + col;
					want = rgb24(fmem[a]);
					o = ov_pixel(col / 2, y / 2);
					if (o != 0) want = ov_rgb(o);
				end
				if (got !== want) begin
					pixel_errors++;
					fail($sformatf("panel pixel (%0d, %0d): %h, expected %h", x, y, got, want));
				end
				pixels_checked++;
				lcd_frame_px <= lcd_frame_px + 1;
			end
		end
	end

	task automatic finish_report();
		$display("%0d pixel errors, %0d pixels as before their last write", pixel_errors, old_pixels);
		$display("SRAM: %0d words written, %0d read, %0d timing errors; scan lines late %0d%s; frames kept %0d",
			sram_writes, sram_reads, sram_errors, dut.core.extModule.fb_late,
			dut.core.extModule.fb_overflow ? ", write queue OVERFLOWED" : "", frames_kept);
		if (sram_errors != 0) fail("SRAM timing errors");
		if (dut.core.extModule.fb_late != 0 || dut.core.extModule.fb_overflow) fail("scan lines late or the write queue full");
		if (panel && old_pixels != 0) fail("the panel showed a frame that was written");
		if (mode != 2 && (sram_writes == 0 || sram_reads == 0)) fail("the SRAM was not used");
		if (errors == 0) $display("PASS");
		else $display("FAIL: %0d errors", errors);
		$finish;
	endtask

	integer timeout_ms = 120;
	initial begin
		if ($value$plusargs("frames=%d", frames_target)) ;
		timeout_ms = 30 + 80 + 45 * (frames_target + 3);
		#(longint'(timeout_ms) * 1000000);
		$display("ERROR: timeout, %0d frames seen", frames_seen);
		$display("FAIL");
		$finish;
	end
endmodule
