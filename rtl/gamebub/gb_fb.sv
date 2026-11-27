// Game Bub Minimig: the picture's two frames, kept by the core in the
// board's asynchronous SRAM and block RAM, and shown through the
// framework's external picture (patches/framework 0003, 0005: ownFrames).
//
// A frame is 720 x 256, or with `wide` (Picture: 800 x 480) 800 x 240,
// shown one to one across all 800 columns of the panel.
//
// Why: two frames of 720 x 256 in the FPGA's block RAM leave 9 bits for a
// pixel. Two are needed: the handheld's panel is scanned in columns of the
// landscape picture while the Amiga draws it in rows, so a single frame
// written while it is shown has a diagonal seam between the old and the new
// picture on everything that moves. The SRAM (512 KiB, 262,144 words of 16
// bits, used by nothing else) and 83 block RAMs hold both frames at 18 bits
// a pixel (6 + 6 + 6; gb_video dithers the two bits below). Two frames of
// 800 x 256 would need some 20 block RAMs more than the FPGA has left, so
// the wide frame has 240 lines (the panel's 480 rows, two each).
//
// Where a pixel is: q = frame * 192,000 + line * 720 (800) + column
// (0..383,999; a frame's 192,000 pixels are the 800 x 240 of the wide one,
// 720 x 256 takes 184,320 of them).
//   q < 262,144   bits 17:2 in the SRAM word q, bits 1:0 in a block RAM of
//                 262,144 x 2 (frame 0, and the first 70,144 pixels of
//                 frame 1)
//   otherwise     all 18 bits in block RAM of 122,880 x 18 (four memories
//                 of 65,536, 32,768, 16,384 and 8,192: Vivado rounds a
//                 memory's depth up to a power of two)
//
// Writing (clk_sys): the pixel stream gb_video sends the framework, counted
// as the framework counts it (a line ends when hblank rises, the frame while
// vblank is high; pixels beyond a line's 720 (800) are dropped). The framework still decides which frame a picture goes
// to and whether it is thrown away because that frame is on the screen
// (wr_frame, wr_drop), and which frame is shown (av_frame). A pixel comes
// every other clk_sys clock at most (eight clk_114 clocks).
//
// The SRAM (clk_114, a 4 x clk_sys of the same MMCM) as the Game Bub 3DO
// core drives it, at the slower of its two timings, three clocks a word:
//   - every pin from a register in its I/O block, WE from an ODDR, the data
//     bus direction from one register;
//   - write: address, data and byte enables for three clocks, WE low from
//     the middle of the first to the end of the second (13 ns);
//   - read: address with OE low for three clocks, the data taken at the
//     edge that ends them (26 ns after the address leaves the I/O block);
//   - one idle clock (OE high, the FPGA not driving) wherever a write
//     follows a read or a read a write.
// Pixels in block RAM only take the same three clocks, with WE kept high.
// Writes wait in a queue of eight: reads go on until four are waiting, then
// all of them are written (a write, a read and their two idle clocks take
// exactly the eight clocks between two pixels; in fours, six reads fit).
//
// Showing (clk_av, the pixel clock of the screen shown): the framework
// names a pixel in every clock (av_x, av_y) and takes its colour 12 clocks
// later (VideoV0.externalLatency). No screen can be fed from the SRAM pixel
// by pixel (HDMI's clock is too fast, and neither clock is the SRAM's), so
// the lines of the screen's scan are read ahead into four line buffers
// (one block RAM pair, written in clk_114, read in clk_av):
//   - the handheld's panel (av_hdmi low): a scan line is a column of the
//     picture, av_x (0..719), of 256 pixels, a column every 25 us; the row
//     av_y (0..479) shows line y / 2, or with `fit` line y * 256 / 480.
//     The framework names column x of the panel as av_x = x - PANEL_X0 (a
//     720 wide picture's place, in 10 bits); the wide picture's column
//     wx + x is the panel's column x, av_x + PANEL_X0, 240 pixels each,
//     with wx = wide_dx - PANEL_X0 (0 at the least; wide_dx: gb_video,
//     the wide frame's column that is the 720 one's column 0, kept with
//     each frame): a screen is on the same columns of the panel with
//     either picture (a standard screen's 640 pixels, at the wide
//     picture's 99 .. 738, wide_dx 59, wx 47: at the panel's 52 .. 691,
//     as the 720 picture's 40 .. 679 are; the Game Bub's glass shows the
//     panel's columns 0 .. about 730, as measured with a ruler); the
//     picture's first wx columns, border, are not shown, its last ones
//     are followed by black;
//     each frame is shown as it was written (its own `wide`, kept with it:
//     a frame written before the setting changed is not read as the other
//     size);
//   - HDMI: a scan line is a line of the picture, shown on two or three
//     lines of the 720 (line y / 3, or with `fit` y * 256 / 720); column x
//     of the 1280 shows pixel x * 9 / 16 (wide: wide_dx + x * 9 / 16, the
//     same 720 columns, so the screen is in the middle as the 720
//     picture has it; narrow: 40 + x / 2, the 640 pixels twice each).
// As the framework's own frame buffers were shown (patches/framework 0001,
// 0004). At av_sync (a frame of the screen begins) the frame to show is
// taken and its first four scan lines are fetched; a line is fetched once
// the line four before it is no longer needed. Line L is in buffer L mod 4.
//
// SPDX-License-Identifier: GPL-3.0-or-later

module gb_fb
#(
	parameter W = 720,           // pixels of a line
	parameter H = 256,           // lines
	parameter WW = 800,          // wide: pixels of a line
	parameter HW = 240,          // wide: lines
	parameter PANEL_X0 = 12      // the panel's column the framework names av_x 0
)
(
	// the pixel stream (clk_sys)
	input             clk_sys,
	input             reset,
	input             px_de,
	input      [17:0] px_data,       // red 17:12, green 11:6, blue 5:0
	input             px_hblank,
	input             px_vblank,
	input             fit,           // all 256 lines over the screen's height (changes between frames)
	input             wide,          // 800 x 240 (changes between frames)
	input       [6:0] wide_dx,       // wide: the frame's column that is the 720 one's column 0 (changes between frames)
	input             narrow,        // 640 pixels at the frame's 40 .. 679: HDMI shows these, twice each (changes between frames)
	input             wr_frame,      // the framework: the frame these pixels belong to
	input             wr_drop,       // and whether they are thrown away

	// the SRAM (clk_114; framework SramV0)
	input             clk_114,
	input             reset_114,     // reset, in clk_114
	output            sram_ceN,
	output            sram_weN,
	output            sram_oeN,
	output      [1:0] sram_writeMaskN,
	output     [17:0] sram_address,
	input      [15:0] sram_dataIn,
	output     [15:0] sram_dataOut,
	output            sram_dataDir,

	// the framework's external picture (clk_av)
	input             clk_av,
	input             av_hdmi,
	input             av_sync,
	input             av_frame,
	input      [10:0] av_x,
	input       [9:0] av_y,
	output reg [23:0] av_color = 24'd0,

	// observation (bench, debug registers)
	output reg [15:0] dbg_lines = 16'd0,     // scan lines fetched
	output reg [15:0] dbg_late = 16'd0,      // scan lines needed before they were fetched
	output reg        dbg_overflow = 1'b0    // a pixel found the write queue full
);

localparam [18:0] FRAME = (WW * HW > W * H) ? WW * HW : W * H;   // pixels from frame 0 to frame 1

// ===========================================================================
// the pixel stream (clk_sys): where each pixel goes
// ===========================================================================
reg        hb_d = 1'b1;
reg [18:0] w_row = 19'd0;        // the line's first pixel
reg [18:0] w_a = 19'd0;          // this pixel
reg        w_tgl = 1'b0;         // flips with every pixel handed over
reg [18:0] w_q = 19'd0;
reg [17:0] w_d = 18'd0;
reg  [1:0] f_wide = 2'b00;       // each frame's size as it was written
reg  [6:0] f_wx0 = 7'd0;         // and, wide, its column that is the 720 one's column 0
reg  [6:0] f_wx1 = 7'd0;
reg  [1:0] f_narrow = 2'b00;     // and whether it is the 640 pixel one
// a line holds its first 720 (800) pixels and a frame its first 256 (240)
// lines: what comes beyond them (the Amiga's sync gone astray: a line that
// does not end) is not kept
wire [18:0] w_w   = wide ? WW[18:0] : W[18:0];
wire [18:0] w_lim = wide ? 19'(WW * HW) : 19'(W * H);
wire       w_in = (w_row < w_lim) && (w_a < w_row + w_w);

always @(posedge clk_sys) begin
	hb_d <= px_hblank;
	if (reset || px_vblank) begin
		w_row <= 19'd0;
		w_a   <= 19'd0;
	end
	else if (px_hblank) begin
		if (!hb_d && w_row < w_lim) begin
			w_row <= w_row + w_w;
			w_a   <= w_row + w_w;
		end
	end
	else if (px_de && w_in) w_a <= w_a + 1'd1;

	if (!reset && px_de && !wr_drop && w_in) begin
		w_q   <= wr_frame ? w_a + FRAME : w_a;
		w_d   <= px_data;
		w_tgl <= ~w_tgl;
		f_wide[wr_frame] <= wide;
		if (wr_frame) f_wx1 <= wide_dx; else f_wx0 <= wide_dx;
		f_narrow[wr_frame] <= narrow;
	end
end

// ===========================================================================
// the request from the screen's side (clk_av registers, read in clk_114
// after the toggle)
// ===========================================================================
// (kept as they are: the constraints name them, and q_hdmi is the same
// register as a_hdmi to a synthesis that may merge them)
reg        q_tgl = 1'b0;
(* dont_touch = "true" *) reg        q_new = 1'b0;         // a frame of the screen begins
(* dont_touch = "true" *) reg        q_hdmi = 1'b0;
(* dont_touch = "true" *) reg        q_frame = 1'b0;
(* dont_touch = "true" *) reg        q_wide = 1'b0;
(* dont_touch = "true" *) reg  [9:0] q_need = 10'd0;       // the first scan line still needed

// ===========================================================================
// the memories and the SRAM pins (clk_114)
// ===========================================================================
// write queue
reg  [1:0] w_ts = 2'b00;
reg        w_seen = 1'b0;
reg [36:0] fifo [0:7];
reg  [3:0] f_wp = 4'd0, f_rp = 4'd0;
wire [3:0] f_level = f_wp - f_rp;
wire [36:0] f_head = fifo[f_rp[2:0]];
reg        draining = 1'b0;

// block RAM: the two low bits of the pixels in the SRAM, and the pixels
// that are not
reg  [1:0] bx [0:262143];
reg [17:0] bh0 [0:65535];        // pixels 262,144 on: the first 65,536,
reg [17:0] bh1 [0:32767];        // the next 32,768,
reg [17:0] bh2 [0:16383];        // the next 16,384,
reg [17:0] bh3 [0:8191];         // the last 8,192
reg        bx_we = 1'b0, bh_we = 1'b0;
reg [17:0] bx_wa, bx_ra;
reg [16:0] bh_wa, bh_ra;
reg [17:0] b_wd;
reg  [1:0] bx_q;
reg [17:0] bh0_q, bh1_q, bh2_q, bh3_q;
// (bh_ra as the memories took it: bx_ra1 and the rest are a clock later)
wire [17:0] bh_q = !bh_ra[16] ? bh0_q : !bh_ra[15] ? bh1_q : !bh_ra[14] ? bh2_q : bh3_q;
// Each memory behind registers of its own for address, data and write
// enable (a clock later than the SRAM's plan registers): 16, 32, 16, 8 and
// 4 block RAMs each, spread over the FPGA's columns.
reg [17:0] bx_wa1, bx_ra1;
reg  [1:0] bx_wd1;
reg        bx_we1 = 1'b0;
reg [15:0] bh0_wa1, bh0_ra1;
reg [14:0] bh1_wa1, bh1_ra1;
reg [13:0] bh2_wa1, bh2_ra1;
reg [12:0] bh3_wa1, bh3_ra1;
reg [17:0] bh0_wd1, bh1_wd1, bh2_wd1, bh3_wd1;
reg        bh0_we1 = 1'b0, bh1_we1 = 1'b0, bh2_we1 = 1'b0, bh3_we1 = 1'b0;
always @(posedge clk_114) begin
	bx_wa1  <= bx_wa;         bx_ra1  <= bx_ra;         bx_wd1  <= b_wd[1:0];
	bh0_wa1 <= bh_wa[15:0];   bh0_ra1 <= bh_ra[15:0];   bh0_wd1 <= b_wd;
	bh1_wa1 <= bh_wa[14:0];   bh1_ra1 <= bh_ra[14:0];   bh1_wd1 <= b_wd;
	bh2_wa1 <= bh_wa[13:0];   bh2_ra1 <= bh_ra[13:0];   bh2_wd1 <= b_wd;
	bh3_wa1 <= bh_wa[12:0];   bh3_ra1 <= bh_ra[12:0];   bh3_wd1 <= b_wd;
	bx_we1  <= bx_we;
	bh0_we1 <= bh_we && !bh_wa[16];
	bh1_we1 <= bh_we && (bh_wa[16:15] == 2'b10);
	bh2_we1 <= bh_we && (bh_wa[16:14] == 3'b110);
	bh3_we1 <= bh_we && (bh_wa[16:13] == 4'b1110);
end
always @(posedge clk_114) begin
	if (bx_we1) bx[bx_wa1] <= bx_wd1;
	bx_q <= bx[bx_ra1];
end
always @(posedge clk_114) begin
	if (bh0_we1) bh0[bh0_wa1] <= bh0_wd1;
	bh0_q <= bh0[bh0_ra1];
end
always @(posedge clk_114) begin
	if (bh1_we1) bh1[bh1_wa1] <= bh1_wd1;
	bh1_q <= bh1[bh1_ra1];
end
always @(posedge clk_114) begin
	if (bh2_we1) bh2[bh2_wa1] <= bh2_wd1;
	bh2_q <= bh2[bh2_ra1];
end
always @(posedge clk_114) begin
	if (bh3_we1) bh3[bh3_wa1] <= bh3_wd1;
	bh3_q <= bh3[bh3_ra1];
end

// the line buffers: line L mod 4, pixel of the scan line
reg [17:0] lbuf [0:4095];
reg        lb_we = 1'b0;
reg [11:0] lb_wa;
reg [17:0] lb_wd;
always @(posedge clk_114) if (lb_we) lbuf[lb_wa] <= lb_wd;

// SRAM pins: plan registers, then the registers in the I/O blocks
reg [17:0] p_addr = 18'd0;
reg [15:0] p_data = 16'd0;
reg  [1:0] p_mask = 2'b11;
reg        p_oe_n = 1'b1, p_dir = 1'b0, p_we1 = 1'b1, p_we2 = 1'b1;

(* IOB = "TRUE" *) reg [17:0] o_addr = 18'd0;
(* IOB = "TRUE" *) reg [15:0] o_data = 16'd0;
(* IOB = "TRUE" *) reg  [1:0] o_mask = 2'b11;
(* IOB = "TRUE" *) reg        o_oe_n = 1'b1;
(* IOB = "TRUE" *) reg [15:0] i_data = 16'd0;
reg        o_dir = 1'b0;
always @(posedge clk_114) begin
	o_addr <= p_addr;
	o_data <= p_data;
	o_mask <= p_mask;
	o_oe_n <= p_oe_n;
	o_dir  <= p_dir;
	i_data <= sram_dataIn;
end
ODDR #(
	.DDR_CLK_EDGE("SAME_EDGE"),
	.INIT(1'b1),
	.SRTYPE("SYNC")
) we_oddr (
	.Q (sram_weN),
	.C (clk_114),
	.CE(1'b1),
	.D1(p_we1),
	.D2(p_we2),
	.R (1'b0),
	.S (1'b0)
);
assign sram_ceN        = 1'b0;
assign sram_oeN        = o_oe_n;
assign sram_writeMaskN = o_mask;
assign sram_address    = o_addr;
assign sram_dataOut    = o_data;
assign sram_dataDir    = o_dir;

// the fetcher: scan lines of the frame shown, in order
(* ASYNC_REG = "TRUE" *) reg [2:0] r_ts = 3'd0;
reg        g_valid = 1'b0;       // a frame to fetch from
reg        g_hdmi = 1'b0;
reg        g_frame = 1'b0;
reg        g_wide = 1'b0;
reg  [9:0] g_need = 10'd0;
reg  [9:0] g_line = 10'd0;       // the scan line being fetched
reg  [9:0] g_k = 10'd0;          // its next pixel
reg [18:0] g_a = 19'd0;          // that pixel in the frame
reg [18:0] g_rowbase = 19'd0;    // HDMI: the line's first pixel
reg        g_setup = 1'b0;       // the next scan line's first address is being made

wire [9:0] g_w     = g_wide ? WW[9:0] : W[9:0];        // pixels of a line
wire [9:0] g_h     = g_wide ? HW[9:0] : H[9:0];        // lines
wire [9:0] g_lines = g_hdmi ? g_h : g_w;              // scan lines of a frame
wire [9:0] g_count = g_hdmi ? g_w : g_h;              // pixels of a scan line
wire       rd_work = g_valid && !g_setup && (g_line < g_lines) &&
                     ({1'b0, g_line} < {1'b0, g_need} + 11'd4);

// one word at a time, three clocks each
localparam [1:0] S_IDLE = 2'd0, S_GAP = 2'd1, S_OP = 2'd2;
reg  [1:0] st = S_IDLE;
reg  [1:0] ph = 2'd0;
reg        cur_wr = 1'b0;        // the word in progress is written to the SRAM
reg        last_we = 1'b0;       // the bus as the last word left it: 1 written

wire       boundary = (st != S_OP) || (ph == 2'd2);
wire       want_wr  = (f_level != 4'd0) && (f_level >= 4'd4 || draining || !rd_work);
wire       want_rd  = rd_work && !want_wr;
wire [18:0] rd_q    = g_frame ? g_a + FRAME : g_a;

// a read's way to the line buffer: the block RAM's part held three clocks
// after it starts (its address through the memory's own register), the
// SRAM's taken five clocks after
reg  [4:0] due = 5'd0;
reg [12:0] tag [0:4];            // not in the SRAM, buffer, pixel
reg  [1:0] hold_bx;
reg [17:0] hold_bh;

always @(posedge clk_114) begin
	reg start_rd;
	start_rd = 1'b0;

	// ---- pixels from the stream into the queue
	w_ts <= {w_ts[0], w_tgl};
	if (w_ts[1] != w_seen) begin
		w_seen <= w_ts[1];
		if (f_level == 4'd8) dbg_overflow <= 1'b1;
		else begin
			fifo[f_wp[2:0]] <= {w_q, w_d};
			f_wp <= f_wp + 1'd1;
		end
	end
	if (f_level >= 4'd4) draining <= 1'b1;
	else if (f_level == 4'd0) draining <= 1'b0;

	// ---- the word in progress
	bx_we <= 1'b0;
	bh_we <= 1'b0;
	if (g_setup) begin
		g_a     <= g_hdmi ? g_rowbase : {9'd0, g_line};
		g_setup <= 1'b0;
	end

	if (st == S_OP && ph == 2'd0) begin
		ph <= 2'd1;
		if (cur_wr) begin p_we1 <= 1'b0; p_we2 <= 1'b0; end   // low through the second clock
	end
	else if (st == S_OP && ph == 2'd1) begin
		ph <= 2'd2;
		p_we1 <= 1'b1; p_we2 <= 1'b1;                          // up at the start of the third
	end
	else if (boundary) begin
		p_we1 <= 1'b1; p_we2 <= 1'b1;
		if (!want_wr && !want_rd) st <= S_IDLE;
		else if (st != S_GAP && want_wr != last_we) begin
			// the bus turns: nobody drives it for a clock
			st     <= S_GAP;
			p_dir  <= 1'b0;
			p_oe_n <= 1'b1;
			p_mask <= 2'b11;
		end
		else begin
			st      <= S_OP;
			ph      <= 2'd0;
			last_we <= want_wr;
			if (want_wr) begin
				f_rp   <= f_rp + 1'd1;
				cur_wr <= !f_head[36];
				p_addr <= f_head[35:18];
				p_data <= f_head[17:2];
				p_mask <= f_head[36] ? 2'b11 : 2'b00;
				p_dir  <= 1'b1;
				p_oe_n <= 1'b1;
				p_we1  <= 1'b1;
				p_we2  <= f_head[36];          // falls in the middle of the first clock
				b_wd   <= f_head[17:0];
				bx_wa  <= f_head[35:18];
				bh_wa  <= f_head[34:18];
				bx_we  <= !f_head[36];
				bh_we  <= f_head[36];
			end
			else begin
				cur_wr <= 1'b0;
				p_addr <= rd_q[17:0];
				p_mask <= 2'b00;
				p_dir  <= 1'b0;
				p_oe_n <= 1'b0;
				bx_ra  <= rd_q[17:0];
				bh_ra  <= rd_q[16:0];
				start_rd = 1'b1;
				tag[0] <= {rd_q[18], g_line[1:0], g_k};
				if (g_k == g_count - 1'd1) begin
					g_k       <= 10'd0;
					g_line    <= g_line + 1'd1;
					g_rowbase <= g_rowbase + {9'd0, g_w};
					g_setup   <= 1'b1;
					dbg_lines <= dbg_lines + 1'd1;
				end
				else begin
					g_k <= g_k + 1'd1;
					g_a <= g_a + (g_hdmi ? 19'd1 : {9'd0, g_w});
				end
			end
		end
	end

	// ---- reads on their way
	due <= {due[3:0], start_rd};
	for (int i = 1; i < 5; i++) tag[i] <= tag[i - 1];
	if (due[2]) begin
		hold_bx <= bx_q;
		hold_bh <= bh_q;
	end
	lb_we <= due[4];
	lb_wa <= tag[4][11:0];
	lb_wd <= tag[4][12] ? hold_bh : {i_data, hold_bx};

	// ---- the screen's requests
	r_ts <= {r_ts[1:0], q_tgl};
	if (r_ts[2] != r_ts[1]) begin
		if (q_new) begin
			// a frame of the screen: from its first scan line (a read on
			// its way still lands in its buffer, before the new line's)
			g_valid   <= 1'b1;
			g_hdmi    <= q_hdmi;
			g_frame   <= q_frame;
			g_wide    <= q_wide;
			// (the wide picture on the panel: from its column wx)
			g_need    <= q_need;
			g_line    <= q_need;
			g_k       <= 10'd0;
			g_a       <= {9'd0, q_need};
			g_rowbase <= 19'd0;
			g_setup   <= 1'b0;
		end
		else begin
			g_need <= q_need;
			if (g_valid && !(g_line > q_need) && ~&dbg_late) dbg_late <= dbg_late + 1'd1;
		end
	end

	if (reset_114) begin
		st       <= S_IDLE;
		p_oe_n   <= 1'b1;
		p_dir    <= 1'b0;
		p_mask   <= 2'b11;
		p_we1    <= 1'b1;
		p_we2    <= 1'b1;
		last_we  <= 1'b0;
		due      <= 5'd0;
		lb_we    <= 1'b0;
		bx_we    <= 1'b0;
		bh_we    <= 1'b0;
		f_wp     <= 4'd0;
		f_rp     <= 4'd0;
		w_seen   <= w_ts[1];
		draining <= 1'b0;
		g_valid  <= 1'b0;
	end
end

// ===========================================================================
// the screen (clk_av)
// ===========================================================================
(* ASYNC_REG = "TRUE" *) reg [1:0] fit_s = 2'b00;
(* ASYNC_REG = "TRUE" *) reg [1:0] wide0_s = 2'b00;   // f_wide, frame 0
(* ASYNC_REG = "TRUE" *) reg [1:0] wide1_s = 2'b00;   // and frame 1
(* ASYNC_REG = "TRUE" *) reg [6:0] wx0_m = 7'd0, wx0_s = 7'd0;   // f_wx0 (steady long before the frame is shown)
(* ASYNC_REG = "TRUE" *) reg [6:0] wx1_m = 7'd0, wx1_s = 7'd0;   // f_wx1
(* ASYNC_REG = "TRUE" *) reg [1:0] narrow0_s = 2'b00;   // f_narrow, frame 0
(* ASYNC_REG = "TRUE" *) reg [1:0] narrow1_s = 2'b00;   // and frame 1
reg  [6:0] a_wx = 7'd0;          // the frame shown: its column at the panel's column 0
reg  [6:0] a_dx = 7'd0;          // and its column that is the 720 one's column 0
reg        a_narrow = 1'b0;
reg [10:0] x1 = 11'd0;
reg  [9:0] y1 = 10'd0;
reg        sync_d = 1'b0;
reg        a_hdmi = 1'b0;
reg        a_fit = 1'b0;
reg        a_wide = 1'b0;
reg  [9:0] need = 10'd0;         // the scan line being shown
reg        q_go = 1'b0;

// HDMI: the line of the picture that line y1 of the screen shows
reg [25:0] s_prod;
reg  [9:0] s_line = 10'd0;
reg        s_ok = 1'b0;
reg        s_ok1 = 1'b0;

// the panel: the picture's column (the wide one's: a_wx from the panel's
// first)
wire [9:0] pcol      = a_wide ? x1[9:0] + 10'(PANEL_X0) + {3'd0, a_wx} : x1[9:0];
// a frame's first scan line
wire [6:0] sel_dx    = av_frame ? wx1_s : wx0_s;
wire [6:0] sel_wx    = (sel_dx > 7'(PANEL_X0)) ? sel_dx - 7'(PANEL_X0) : 7'd0;
wire [9:0] first_av  = (!av_hdmi && (av_frame ? wide1_s[1] : wide0_s[1])) ? {3'd0, sel_wx} : 10'd0;
wire       pcol_ok   = a_wide ? (pcol < WW[9:0]) : (x1 < W);
wire       adv_panel = !a_hdmi && pcol_ok && (pcol == need + 10'd1);
wire       adv_hdmi  = a_hdmi && s_ok && (s_line == need + 10'd1);

always @(posedge clk_av) begin
	x1     <= av_x;
	y1     <= av_y;
	sync_d <= av_sync;
	fit_s  <= {fit_s[0], fit};
	wide0_s <= {wide0_s[0], f_wide[0]};
	wide1_s <= {wide1_s[0], f_wide[1]};
	narrow0_s <= {narrow0_s[0], f_narrow[0]};
	narrow1_s <= {narrow1_s[0], f_narrow[1]};
	wx0_m  <= f_wx0;
	wx0_s  <= wx0_m;
	wx1_m  <= f_wx1;
	wx1_s  <= wx1_m;
	q_go   <= 1'b0;
	if (q_go) q_tgl <= ~q_tgl;

	// y * 256 / 720 = (y * 23302) >> 16 and y / 3 = (y * 683) >> 11, exact
	// for every line of the 720
	s_prod <= a_fit ? 26'(y1 * 26'd23302) : {21'(y1 * 21'd683), 5'd0};
	s_ok1  <= (y1 < 10'd720);
	s_line <= s_prod[25:16];
	s_ok   <= s_ok1 && (y1 < 10'd720);

	if (av_sync && !sync_d) begin
		a_hdmi  <= av_hdmi;
		a_fit   <= fit_s[1];
		a_wide  <= av_frame ? wide1_s[1] : wide0_s[1];
		a_wx    <= sel_wx;
		a_dx    <= sel_dx;
		a_narrow <= av_frame ? narrow1_s[1] : narrow0_s[1];
		need    <= first_av;
		s_ok    <= 1'b0;
		s_ok1   <= 1'b0;
		q_new   <= 1'b1;
		q_hdmi  <= av_hdmi;
		q_frame <= av_frame;
		q_wide  <= av_frame ? wide1_s[1] : wide0_s[1];
		q_need  <= first_av;
		q_go    <= 1'b1;
	end
	else if (!q_go && (adv_panel || adv_hdmi)) begin
		need   <= need + 1'd1;
		q_new  <= 1'b0;
		q_need <= need + 1'd1;
		q_go   <= 1'b1;
	end
end

// the pixels: 12 registers from av_x / av_y to av_color
// y * 256 / 480 = (y * 34953) >> 16, exact for every row of the 480
wire [24:0] row_fit = y1[8:0] * 16'd34953;
wire [14:0] col_fit = x1 * 4'd9;            // x * 9 / 16
// wide: the 720 columns the 720 picture would have, from the frame's a_dx
// (the screen in HDMI's middle, as with the 720 picture; the frame's other
// 80 columns are the panel's); the 640 pixel picture: its 640, from the
// frame's 40, twice each
wire  [9:0] col_w   = col_fit[13:4] + {3'd0, a_dx};
wire  [9:0] col_n   = x1[10:1] + 10'd40;
reg  [11:0] p2_a;
reg         p2_in;
reg  [17:0] p3_q, p4_q;
reg         p3_in, p4_in;
reg  [23:0] p_c [5:11];

always @(posedge clk_av) begin
	if (a_hdmi) begin
		p2_a  <= {s_line[1:0], a_wide ? col_w : a_narrow ? col_n : col_fit[13:4]};
		p2_in <= s_ok && (x1 < 11'd1280);
	end
	else begin
		p2_a  <= {pcol[1:0], 2'b00, a_fit ? row_fit[23:16] : y1[8:1]};
		p2_in <= pcol_ok && (y1 < 10'd480);
	end
	p3_q  <= lbuf[p2_a];
	p3_in <= p2_in;
	p4_q  <= p3_q;
	p4_in <= p3_in;
	p_c[5] <= !p4_in ? 24'd0 :
	          {p4_q[17:12], p4_q[17:16], p4_q[11:6], p4_q[11:10], p4_q[5:0], p4_q[5:4]};
	for (int i = 6; i < 12; i++) p_c[i] <= p_c[i - 1];
	av_color <= p_c[11];
end

endmodule
