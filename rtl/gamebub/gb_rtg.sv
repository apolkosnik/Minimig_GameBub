// Game Bub Minimig: the RTG board's picture (MiSTer's RTG registers, its
// P96 driver MiSTer.card), shown on HDMI through the framework's external
// picture (patches/framework 0003).
//
// The board's registers are upstream's rtg.sv (rtl/minimig), reached as on
// MiSTer through cpu_wrapper's fastchip port: at $B80100 (the driver's
// fixed address) and in the autoconfigured board's register window
// (rtg_reg_sel). The palette is a block RAM: the CPU writes and reads it
// (clk_sys), the picture reads it (clk_av). The board's 8 MB of memory is
// the first 8 MB of the second SDRAM chip; the CPU writes it through
// cpu_wrapper, which swaps the bytes of each word for the RTG board as it
// does on MiSTer, so a word of the SDRAM holds the byte at the lower
// address in bits 7:0 and the next in 15:8: the memory is in the byte
// order MiSTer's scaler (ascal) reads its frame buffer in.
//
// Registers (rtg.sv): base (MiSTer address: the driver adds $27000000 to
// the offset in the board's memory; bits 22:0 are that offset), format,
// enable, hsize, vsize, stride (bytes per line). Pixel formats as ascal
// decodes them (the driver's codes):
//   format[2:0]  3: 8 bits, palette (256 entries of 00 RR GG BB)
//                4: 16 bits, the word u = byte 1 << 8 | byte 0;
//                   format[3] 0: r u[4:0], g u[10:5], b u[15:11]
//                             1: r u[4:0], g u[9:5],  b u[14:10]
//                5: 24 bits, 6 (and any other): 32 bits;
//                   r byte 0, g byte 1, b byte 2
//   format[4]    red and blue swapped (all formats)
// Channels of fewer than 8 bits repeat their top bits (ascal).
//
// The picture: the framework names a pixel of the 1650 x 750 HDMI frame
// (1280 x 720 shown) in every clk_av clock (av_x / av_y) and takes its
// colour 12 clocks later (VideoV0.externalLatency). The RTG picture is
// scaled to fit 1280 x 720 keeping its shape (nearest pixel, the same
// factor across and down: step = source size << 16 / shown size of the
// limiting direction), centred, black around it. At most 2048 pixels of a
// line are shown (wider pictures are cut on the right).
//
// Lines come from the SDRAM through the controller's burst port (clk_114,
// eight words per window, ahead of the CPU) into two line buffers of 2048
// pixels: as a line of the HDMI frame starts, the source line after the
// one it shows (or the one the next HDMI line shows, if that is further
// on) is fetched into the buffer it does not show. Settings are taken at
// the first blank line of every HDMI frame; the buffers are then empty.
//
// SPDX-License-Identifier: GPL-3.0-or-later

module gb_rtg
#(
	parameter        SCREEN_W = 1280,
	parameter        SCREEN_H = 720,
	parameter        FRAME_H  = 750,
	parameter        MAX_W    = 2048
)
(
	// CPU (clk_sys): cpu_wrapper's fastchip port
	input             clk_sys,
	input             reset,
	input             sel,           // fastchip_sel
	input             rtg_reg_sel,   // the autoconfigured board's registers
	input      [23:1] addr,
	input      [15:0] din,
	input             uds,           // active high
	input             lds,
	input             rnw,
	output            sel_ack,
	output            ready,
	output     [15:0] dout,
	output reg        enable = 1'b0, // the RTG picture is on (to the framework)

	// SDRAM burst port (clk_114)
	input             clk_114,
	output reg [24:4] burstAddr = 21'd0,
	output reg        burstReq = 1'b0,
	output reg        burstUrgent = 1'b0,
	input             burstAck,
	input      [15:0] burstData,
	input             burstValid,

	// the framework's external picture (clk_av, the HDMI pixel clock)
	input             clk_av,
	input      [10:0] av_x,
	input       [9:0] av_y,
	output reg [23:0] av_color = 24'd0,

	// observation (bench)
	output reg [15:0] dbg_lines = 16'd0,     // lines fetched
	output reg [15:0] dbg_late = 16'd0       // shown lines whose buffer was not there
);

// ===========================================================================
// registers and palette (clk_sys)
// ===========================================================================
wire        sel_rtg = sel && (rtg_reg_sel || addr[23:12] == 12'hB80);
wire        r_ena;
wire [11:0] r_hsize, r_vsize;
wire  [4:0] r_format;
wire [31:0] r_base;
wire [13:0] r_stride;
wire  [7:0] pal_a;
wire [23:0] pal_dw;
reg  [23:0] pal_dr;
wire        pal_wr;

rtg rtg
(
	.clk      (clk_sys),
	.aen      (sel_rtg),
	.rd       (rnw),
	.wr       (~rnw & (lds | uds)),
	.reset    (reset),
	.rs       (addr[11:1]),
	.ready    (ready),
	.data_in  (din),
	.data_out (dout),
	.ena      (r_ena),
	.hsize    (r_hsize),
	.vsize    (r_vsize),
	.format   (r_format),
	.base     (r_base),
	.stride   (r_stride),
	.pal_clk  (),
	.pal_dw   (pal_dw),
	.pal_dr   (pal_dr),
	.pal_a    (pal_a),
	.pal_wr   (pal_wr)
);
assign sel_ack = sel_rtg;

always @(posedge clk_sys) enable <= r_ena && r_hsize != 12'd0 && r_vsize != 12'd0;

reg  [23:0] palette [0:255];
always @(posedge clk_sys) begin
	if (pal_wr) palette[pal_a] <= pal_dw;
	pal_dr <= palette[pal_a];
end

// ===========================================================================
// the picture (clk_av)
// ===========================================================================
// settings, quasi-static (they change by CPU writes, and are taken once a
// frame): two registers into clk_av
(* ASYNC_REG = "TRUE" *) reg [11:0] s_hsize [0:1];
(* ASYNC_REG = "TRUE" *) reg [11:0] s_vsize [0:1];
(* ASYNC_REG = "TRUE" *) reg  [4:0] s_format [0:1];
(* ASYNC_REG = "TRUE" *) reg [22:0] s_base [0:1];
(* ASYNC_REG = "TRUE" *) reg [13:0] s_stride [0:1];
always @(posedge clk_av) begin
	s_hsize[0]  <= r_hsize;  s_hsize[1]  <= s_hsize[0];
	s_vsize[0]  <= r_vsize;  s_vsize[1]  <= s_vsize[0];
	s_format[0] <= r_format; s_format[1] <= s_format[0];
	s_base[0]   <= r_base[22:0]; s_base[1] <= s_base[0];
	s_stride[0] <= r_stride; s_stride[1] <= s_stride[0];
end

// the frame's settings
reg  [11:0] f_hs = 12'd0;        // pixels shown of a line (at most MAX_W)
reg  [10:0] f_vs = 11'd0;        // lines
reg   [4:0] f_format = 5'd0;
reg  [22:0] f_base = 23'd0;
reg  [13:0] f_stride = 14'd0;
reg   [2:0] f_bpp = 3'd1;        // bytes per pixel
reg         f_ok = 1'b0;         // scaling computed, the picture can be shown
reg  [17:0] step = 18'd0;        // source pixels per shown pixel, 16 fraction bits
reg  [10:0] off_x = 11'd0, end_x = 11'd0;
reg   [9:0] off_y = 10'd0, end_y = 10'd0;

// scaling: two divisions after the settings are taken (restoring divider)
reg   [2:0] div_state = 3'd0;    // 0 idle, 1-2 first division, 3-4 second, 5 done
reg  [31:0] div_n, div_q;
reg  [11:0] div_d;
reg  [12:0] div_r;
reg   [5:0] div_i;
reg         wide;                // the width limits the shown size
reg  [10:0] shown;               // shown size in the other direction

wire  [9:0] y_next = (av_y == FRAME_H - 1) ? 10'd0 : av_y + 1'd1;
reg   [9:0] y_d = 10'd0;
wire        new_line = (av_y != y_d);
wire        take_settings = new_line && (av_y == SCREEN_H);

// the line buffers' tags: the source line each holds
reg  [10:0] tag [0:1];
reg   [1:0] tag_v = 2'b00;
reg         last_buf = 1'b0;

// the request to the fetcher (clk_114): payload, then the toggle
reg  [10:0] q_line;
reg         q_buf;
reg  [22:0] q_base;
reg  [13:0] q_stride;
reg  [11:0] q_hs;
reg   [2:0] q_bpp;
reg         q_tgl = 1'b0;
reg         q_go = 1'b0;

// the line being shown
reg         row_ok = 1'b0;       // source line known and in a buffer
reg         row_buf = 1'b0;

// line computation: a few clocks after the line starts
reg   [3:0] lstate = 4'd0;
reg   [9:0] l_y;
reg  [10:0] cur_sy, nx_sy;
reg         cur_in, nx_in;
reg  [27:0] l_prod;

function automatic [10:0] clamp_sy(input [27:0] p, input [10:0] vs);
	clamp_sy = (p[26:16] >= vs) ? vs - 1'd1 : p[26:16];
endfunction

always @(posedge clk_av) begin
	y_d  <= av_y;
	q_go <= 1'b0;
	if (q_go) q_tgl <= ~q_tgl;

	// ---- settings and scaling, at the first blank line
	if (take_settings) begin
		f_hs     <= (s_hsize[1] > MAX_W) ? MAX_W[11:0] : s_hsize[1];
		f_vs     <= (s_vsize[1] > 12'd2047) ? 11'd2047 : s_vsize[1][10:0];
		f_format <= s_format[1];
		f_base   <= s_base[1];
		f_stride <= s_stride[1];
		f_bpp    <= (s_format[1][2:0] == 3'd3) ? 3'd1 : (s_format[1][2:0] == 3'd4) ? 3'd2 :
		            (s_format[1][2:0] == 3'd5) ? 3'd3 : 3'd4;
		f_ok     <= 1'b0;
		tag_v    <= 2'b00;
		div_state <= 3'd1;
	end
	else case (div_state)
		3'd1: begin
			if (f_hs == 0 || f_vs == 0) div_state <= 3'd0;
			else begin
				wide  <= (f_hs * SCREEN_H) >= (f_vs * SCREEN_W);
				// step = size << 16 / shown size of the limiting direction
				div_n <= ((f_hs * SCREEN_H) >= (f_vs * SCREEN_W)) ? {4'd0, f_hs, 16'd0} : {5'd0, f_vs, 16'd0};
				div_d <= ((f_hs * SCREEN_H) >= (f_vs * SCREEN_W)) ? SCREEN_W[11:0] : SCREEN_H[11:0];
				div_r <= 13'd0;
				div_i <= 6'd32;
				div_state <= 3'd2;
			end
		end
		3'd2, 3'd4: begin
			if (div_i != 0) begin
				// restoring division, one bit a clock
				if ({div_r[11:0], div_n[31]} >= {1'b0, div_d}) begin
					div_r <= {div_r[11:0], div_n[31]} - {1'b0, div_d};
					div_q <= {div_q[30:0], 1'b1};
				end
				else begin
					div_r <= {div_r[11:0], div_n[31]};
					div_q <= {div_q[30:0], 1'b0};
				end
				div_n <= {div_n[30:0], 1'b0};
				div_i <= div_i - 1'd1;
			end
			else if (div_state == 3'd2) begin
				step  <= div_q[17:0];
				// the other direction: its size * limiting screen size / limiting size
				div_n <= wide ? f_vs * SCREEN_W : f_hs * SCREEN_H;
				div_d <= wide ? f_hs : {1'b0, f_vs};
				div_r <= 13'd0;
				div_i <= 6'd32;
				div_state <= 3'd4;
			end
			else begin
				shown <= div_q[10:0];
				div_state <= 3'd5;
			end
		end
		3'd5: begin
			if (wide) begin
				off_x <= 11'd0;
				end_x <= SCREEN_W[10:0];
				off_y <= (SCREEN_H - shown) >> 1;
				end_y <= ((SCREEN_H - shown) >> 1) + shown;
			end
			else begin
				off_x <= (SCREEN_W - shown) >> 1;
				end_x <= ((SCREEN_W - shown) >> 1) + shown;
				off_y <= 10'd0;
				end_y <= SCREEN_H[9:0];
			end
			f_ok <= 1'b1;
			div_state <= 3'd0;
		end
		default: ;
	endcase

	// ---- every line: what it shows, and what to fetch
	if (new_line) begin
		l_y    <= av_y;
		row_ok <= 1'b0;
		lstate <= 4'd1;
	end
	else case (lstate)
		4'd1: begin
			cur_in <= f_ok && l_y >= off_y && l_y < end_y;
			l_prod <= (l_y - off_y) * step;
			lstate <= 4'd2;
		end
		4'd2: begin
			cur_sy <= clamp_sy(l_prod, f_vs);
			l_prod <= (((l_y == FRAME_H - 1) ? 10'd0 : l_y + 1'd1) - off_y) * step;
			nx_in  <= f_ok && ((l_y == FRAME_H - 1) ? 10'd0 : l_y + 1'd1) >= off_y &&
			          ((l_y == FRAME_H - 1) ? 10'd0 : l_y + 1'd1) < end_y;
			lstate <= 4'd3;
		end
		4'd3: begin
			nx_sy  <= clamp_sy(l_prod, f_vs);
			lstate <= 4'd4;
		end
		4'd4: begin
			// the buffer this line shows
			if (cur_in && tag_v[0] && tag[0] == cur_sy) begin row_ok <= 1'b1; row_buf <= 1'b0; end
			else if (cur_in && tag_v[1] && tag[1] == cur_sy) begin row_ok <= 1'b1; row_buf <= 1'b1; end
			else if (cur_in) dbg_late <= dbg_late + 1'd1;
			// the line to fetch: the next one shown, or the one after this
			// line's if the next line shows this one again
			q_line <= !nx_in ? 11'd0 : (cur_in && nx_sy == cur_sy) ? cur_sy + 1'd1 : nx_sy;
			lstate <= 4'd5;
		end
		4'd5: begin
			lstate <= 4'd0;
			if (f_ok && q_line < f_vs &&
			    !(tag_v[0] && tag[0] == q_line) && !(tag_v[1] && tag[1] == q_line)) begin
				// into the buffer this line does not show
				q_buf    <= row_ok ? ~row_buf : ~last_buf;
				last_buf <= row_ok ? ~row_buf : ~last_buf;
				tag[row_ok ? ~row_buf : ~last_buf] <= q_line;
				tag_v[row_ok ? ~row_buf : ~last_buf] <= 1'b1;
				q_base   <= f_base;
				q_stride <= f_stride;
				q_hs     <= f_hs;
				q_bpp    <= f_bpp;
				q_go     <= 1'b1;
			end
		end
		default: ;
	endcase
end

// ---- the pixels: 12 registers from av_x to av_color
reg  [47:0] lbuf [0:2047];       // two lines of 1024 pixel pairs
reg  [10:0] p1_x;
reg  [11:0] p2_dx;
reg         p2_in;
reg  [28:0] p3_m, p4_m;
reg         p3_in, p4_in;
reg  [10:0] p5_a;
reg   [3:0] p5_h;                // pixel of the pair, then delayed
reg         p5_in, p6_in, p7_in, p8_in, p9_in, p10_in;
reg  [47:0] p6_q, p7_q;
reg  [23:0] p8_px;
reg  [23:0] p9_pal, p10_pal;
reg  [23:0] p9_dir, p10_dir;
reg  [23:0] p11_c;

function automatic [23:0] direct(input [23:0] px, input [4:0] fmt);
	reg [7:0] b0, b1, b2;
	reg [15:0] u;
	reg [7:0] r, g, b;
	begin
		b0 = px[23:16]; b1 = px[15:8]; b2 = px[7:0];
		u  = {b1, b0};
		if (fmt[2:0] == 3'd4) begin
			r = {u[4:0], u[4:2]};
			if (fmt[3]) begin
				g = {u[9:5], u[9:7]};
				b = {u[14:10], u[14:12]};
			end
			else begin
				g = {u[10:5], u[10:9]};
				b = {u[15:11], u[15:13]};
			end
		end
		else begin
			r = b0; g = b1; b = b2;
		end
		direct = {r, g, b};
	end
endfunction

wire [10:0] src_x = (p4_m[27:16] >= f_hs) ? 11'(f_hs - 1'd1) : p4_m[26:16];
wire        clut  = (f_format[2:0] == 3'd3);

always @(posedge clk_av) begin
	p1_x   <= av_x;
	p2_dx  <= {1'b0, p1_x} - {1'b0, off_x};
	p2_in  <= row_ok && p1_x >= off_x && p1_x < end_x;
	p3_m   <= p2_dx[10:0] * step;
	p3_in  <= p2_in;
	p4_m   <= p3_m;
	p4_in  <= p3_in;
	p5_a   <= {row_buf, src_x[10:1]};
	p5_h   <= {p5_h[2:0], src_x[0]};
	p5_in  <= p4_in;
	p6_q   <= lbuf[p5_a];
	p6_in  <= p5_in;
	p7_q   <= p6_q;
	p7_in  <= p6_in;
	p8_px  <= p5_h[2] ? p7_q[47:24] : p7_q[23:0];
	p8_in  <= p7_in;
	p9_pal <= palette[p8_px[23:16]];
	p9_dir <= direct(p8_px, f_format);
	p9_in  <= p8_in;
	p10_pal <= p9_pal;
	p10_dir <= p9_dir;
	p10_in  <= p9_in;
	p11_c  <= !p10_in ? 24'd0 : clut ? p10_pal : p10_dir;
	av_color <= f_format[4] ? {p11_c[7:0], p11_c[15:8], p11_c[23:16]} : p11_c;
end

// ===========================================================================
// the line fetcher (clk_114)
// ===========================================================================
(* ASYNC_REG = "TRUE" *) reg [2:0] m_tgl = 3'd0;
reg         m_pend = 1'b0;
reg  [10:0] m_line;
reg         m_buf;
reg  [22:0] m_base;
reg  [13:0] m_stride;
reg  [11:0] m_hs;
reg   [2:0] m_bpp;

reg   [1:0] g_state = 2'd0;      // 0 idle, 1 address, 2 sizes, 3 fetching
reg  [24:0] g_prod;
reg  [22:0] g_base;
reg  [22:0] g_addr;
reg  [13:0] g_bytes;             // bytes of the line
reg   [9:0] g_bursts;            // bursts still to request
reg  [13:0] g_words;             // words still to come
reg   [3:0] g_skip;              // bytes to drop at the start
reg  [11:0] g_left;              // pixels still to write
reg   [9:0] g_pair;              // next pair in the buffer
reg         g_buf;
reg   [2:0] g_bpp;

reg   [7:0] acc [0:9];           // bytes received, not yet written
reg   [3:0] acc_n;

// A fetch goes ahead of the CPU's chip 1 accesses only as late as it can
// still finish within an HDMI line (1650 clocks of 74.25 MHz: about 157
// windows of 16 clk_114 cycles; 140 leaves room for refreshes): while the
// windows it has used and the bursts it still needs reach URGENT_WINDOWS.
// Even then every fourth window is left to the CPU, so a picture too
// large for the bandwidth cannot shut the CPU out of chip 1.
localparam URGENT_WINDOWS = 140;
reg  [12:0] g_elapsed = 13'd0;   // clk_114 cycles since the fetch started
reg   [5:0] g_win = 6'd0;
always @(posedge clk_114) begin
	g_win <= g_win + 1'd1;
	burstUrgent <= (g_state == 2'd3) && (g_elapsed[12:4] + g_bursts >= URGENT_WINDOWS) &&
	               (g_win[5:4] != 2'b11);
end

// one pixel pair from the oldest bytes (the last pixel of an odd line alone)
wire  [3:0] pair_bytes = {g_bpp, 1'b0};
wire        emit = (g_state == 2'd3) && g_left != 0 &&
                   (acc_n >= pair_bytes || (g_left == 12'd1 && acc_n >= {1'b0, g_bpp}));
wire [23:0] px0 = {acc[0], g_bpp > 3'd1 ? acc[1] : 8'd0, g_bpp > 3'd2 ? acc[2] : 8'd0};
reg  [23:0] px1;
always @(*) begin
	case (g_bpp)
		3'd1:    px1 = {acc[1], 16'd0};
		3'd2:    px1 = {acc[2], acc[3], 8'd0};
		3'd3:    px1 = {acc[3], acc[4], acc[5]};
		default: px1 = {acc[4], acc[5], acc[6]};
	endcase
end

always @(posedge clk_114) begin
	reg [7:0] nb [0:9];
	reg [3:0] n;
	reg [9:0] bursts;

	m_tgl <= {m_tgl[1:0], q_tgl};
	if (m_tgl[2] != m_tgl[1]) begin
		m_pend   <= 1'b1;
		m_line   <= q_line;
		m_buf    <= q_buf;
		m_base   <= q_base;
		m_stride <= q_stride;
		m_hs     <= q_hs;
		m_bpp    <= q_bpp;
	end

	case (g_state)
		2'd0: if (m_pend) begin
			m_pend  <= 1'b0;
			g_prod  <= m_line * m_stride;
			g_base  <= m_base;
			g_bytes <= m_hs * m_bpp;
			g_buf   <= m_buf;
			g_bpp   <= m_bpp;
			g_left  <= m_hs;
			g_pair  <= 10'd0;
			g_state <= 2'd1;
		end
		2'd1: begin
			g_addr  <= g_base + g_prod[22:0];
			g_state <= 2'd2;
		end
		2'd2: begin
			// bursts of 16 bytes from the one holding the first byte
			bursts    = (g_bytes + g_addr[3:0] + 14'd15) >> 4;
			g_skip   <= g_addr[3:0];
			g_bursts <= bursts;
			g_words  <= {1'b0, bursts, 3'b000};
			burstAddr <= {2'b00, g_addr[22:4]};
			burstReq <= 1'b1;
			acc_n    <= 4'd0;
			g_elapsed <= 13'd0;
			g_state  <= 2'd3;
			dbg_lines <= dbg_lines + 1'd1;
		end
		2'd3: begin
			if (~&g_elapsed) g_elapsed <= g_elapsed + 1'd1;
			// requests: one burst taken per burstAck
			if (burstAck) begin
				burstAddr <= burstAddr + 1'd1;
				g_bursts  <= g_bursts - 1'd1;
				if (g_bursts == 10'd1) burstReq <= 1'b0;
			end

			// the bytes: the oldest pair out, the word's bytes in
			for (int i = 0; i < 10; i++) nb[i] = acc[i];
			n = acc_n;
			if (emit) begin
				for (int i = 0; i < 10; i++) nb[i] = (i < 10 - pair_bytes) ? acc[(i + pair_bytes) % 10] : 8'd0;
				n = (acc_n >= pair_bytes) ? acc_n - pair_bytes : 4'd0;
				g_left <= (g_left == 12'd1) ? 12'd0 : g_left - 12'd2;
				g_pair <= g_pair + 1'd1;
			end
			if (burstValid && g_words != 0) begin
				g_words <= g_words - 1'd1;
				if (g_left != 0) begin
					if (g_skip >= 4'd2) g_skip <= g_skip - 4'd2;
					else if (g_skip == 4'd1) begin
						nb[n] = burstData[15:8];
						n = n + 1'd1;
						g_skip <= 4'd0;
					end
					else begin
						nb[n] = burstData[7:0];
						nb[n + 1] = burstData[15:8];
						n = n + 2'd2;
					end
				end
			end
			for (int i = 0; i < 10; i++) acc[i] <= nb[i];
			acc_n <= n;
			if (g_words == 0 && g_bursts == 0) g_state <= 2'd0;
		end
	endcase
end

always @(posedge clk_114) begin
	if (emit) lbuf[{g_buf, g_pair}] <= {px1, px0};
end

endmodule
