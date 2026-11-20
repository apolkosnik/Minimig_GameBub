// Game Bub Minimig, AP68040 variant: cpu_cache_new without the cache, with a
// buffer of the last line read.
//
// The AP68040 has its own instruction and data caches (4 KB each), so the
// variant drops the controller's CPU cache (rtl/minimig/cpu_cache_new.sv:
// block RAM the AP68040 needs). This module takes its place with the same
// ports and the same handshakes:
//   - a read asks the SDRAM for its burst (sdr_read_req while in READ /
//     FILL1 without an acknowledge): from SDRAM chip 0 four words,
//     sequential from the word asked for and wrapping in its aligned 8
//     bytes (gb_sdram_ctrl's LOAD MODE); from chip 1 (cpu_adr[25]) eight,
//     the 16 bytes of the 68040's line (gb_sdram_ctrl with CPU_LINE16: the
//     word asked for and the rest of its 8 bytes, then the other 8 bytes from
//     the same word on). All of them are kept, and a later read of the same
//     8 or 16 bytes is answered from them without the SDRAM: the 68040's
//     line transfers (four long words in address order through the bus
//     adapter) take one SDRAM slot on chip 1, two on chip 0;
//   - a long word (cpu_long: cpu_wrapper's ramlong1, aligned) is answered
//     whole (cpu_dat_hi, cpu_dat_r, cpu_ack_l with cpu_ack): from the kept
//     words, or as soon as its second word arrives;
//   - the kept words are dropped on a CPU write into their 16 bytes, a
//     chipset write there (snoop_act / snoop_adr, as the cache's snoop) or
//     a reset; a burst that such a write meets while it arrives is not
//     kept;
//   - a write enables the write buffer (wb_en) as the cache does on a miss,
//     once per access and again while cpu_cs stays up after a gap-free
//     first cycle (WRITE, WB); a long word is one access (the controller's
//     write buffer takes both words);
//   - a line (cpu_line: the bus adapter's line read, aligned to its first
//     long word) is answered whole when the kept words hold its 16 bytes
//     (cpu_dat_line, cpu_ack_line with cpu_ack and cpu_ack_l), from them or
//     at the end of a chip 1 burst; from chip 0 (8 bytes a burst) the long
//     word is answered and the adapter goes on long by long;
//   - the next line is read ahead (pf_req, pf_adr: gb_sdram_ctrl's
//     CPU_LINE16) after a chip 1 line has been filled or taken from the
//     read-ahead buffer, while nothing else is asked (once asked for, it is
//     waited for: the controller may have taken it a clock before pf_ack;
//     a CPU request waits), into one of two read-ahead buffers of 16 bytes
//     (two streams, a copy's source and destination: a stream's next line
//     goes to the buffer it was read from, a new stream's to the one used
//     least recently): a read that hits one is answered from it (whole,
//     for a line) and its line becomes the kept one. CPU and chipset writes
//     into them drop them, as the kept words;
//   - chip RAM's code (reads below 2 MB of chip 0: cpu_wrapper sends the
//     CPU's fetches from chip RAM here, its data goes over the chip bus) has
//     a cache of its own, 2^CLB lines of 16 bytes in block RAM, direct
//     mapped. The 68040 does not cache chip RAM (the bridge's TCI: the
//     chipset writes there and old programs change their code without a
//     word to the CPU), so with its instruction cache on it asks for a
//     whole line at every jump: two bursts of chip 0, in the slots the
//     chipset leaves, 0.86 us on average, and a short loop read two lines
//     on every pass. A line enters the cache once both its halves have been
//     read with no write meeting them, and leaves it with any write to chip
//     RAM that has its index (the chipset's and the CPU's over the chip
//     bus: snoop_act; the index alone is compared, so a write elsewhere
//     costs a line now and then, never a stale one). A read that finds its
//     line is answered from it, whole for a line; it is not made the kept
//     line. A read that misses starts a clock later for the look-up. After
//     a reset the valid bits are cleared one by one, the cache off
//     meanwhile.
//   - LINE_TAKE and the line buffer port are not used.
// SPDX-License-Identifier: GPL-3.0-or-later

module cpu_cache_new
#(parameter LINE_TAKE = 0,
  parameter CLB       = 9)     // chip RAM's code cache: 2^CLB lines (0: none)
(
	input             clk,
	input             rst,
	input       [3:0] cpu_cache_ctrl,
	input             dcache_sw_en,
	input             cache_inhibit,
	input             cpu_cs,
	input      [28:1] cpu_adr,
	input       [1:0] cpu_bs,
	input             cpu_we,
	input             cpu_ir,
	input             cpu_dr,
	input      [15:0] cpu_dat_w,
	output reg [15:0] cpu_dat_r,
	output reg        cpu_ack,
	output reg        wb_en,
	output            cpu_idle,
	input      [15:0] sdr_dat_r,
	output reg        sdr_read_req,
	input             sdr_read_ack,
	input             snoop_act,
	input      [28:1] snoop_adr,
	input      [15:0] snoop_dat_w,
	input       [1:0] snoop_bs,
	input             buf_ok,
	input      [63:0] buf_dat,
	output reg        buf_take,
	input             cpu_long,
	input      [15:0] cpu_dat_w_lo,
	output reg [15:0] cpu_dat_hi,
	output reg        cpu_ack_l,
	input             cpu_line,
	output reg [127:0] cpu_dat_line,  // long word 0 in 127:96
	output reg        cpu_ack_line,
	output reg        pf_req,
	output reg [28:4] pf_adr,
	input             pf_ack
);

localparam [3:0]
	S_IDLE  = 4'd0,
	S_WRITE = 4'd1,
	S_WB    = 4'd2,
	S_READ  = 4'd3,
	S_FILL  = 4'd4,
	S_LACK  = 4'd5,
	S_FILLW = 4'd6,
	S_PF    = 4'd7,       // the read ahead: asked for, then arriving (pf_on)
	S_CLK   = 4'd8;       // chip RAM's code cache looked up (c_q)

reg  [3:0] st;
reg        gap;

// the kept words: b_w[{a[3], a[2:1]}] for the 16 bytes at {b_adr, 4'h0};
// b_vh[h]: the 8 bytes with a[3] = h are kept
reg        b_line;       // the burst arriving is a line (chip 1): eight words
reg  [1:0] b_vh;
reg [28:4] b_adr;
reg [15:0] b_w [0:7];
reg  [2:0] f_cnt;        // words of the burst arriving so far
reg        f_h;          // the half (a[3]) of the word asked for
reg  [1:0] f_w;          // and its word (a[2:1])
reg        f_ok;         // no write met the burst arriving
reg        f_long;       // a long word asked for: answered at the second word
reg        f_done;       // the CPU has been answered
reg        f_whole;      // a line asked for from chip 1: answered whole at the burst's end

// the read ahead: two buffers, the 16 bytes at {n_adr[k], 4'h0}
reg        n_v   [0:1];
reg [28:4] n_adr [0:1];
reg [15:0] n_w   [0:1][0:7];
reg        n_lru;        // the buffer a new stream takes
reg        pf_slot;      // the buffer the read ahead goes to
reg        pf_pend;      // the line after the kept one is to be read ahead
reg        pf_on;        // taken (pf_ack): its eight words arriving
reg  [2:0] pf_cnt;
reg        pf_ok;        // no write met it arriving

wire [2:0] f_idx  = {f_h ^ f_cnt[2], f_w + f_cnt[1:0]};
wire       lng    = cpu_long && !cpu_adr[1];
wire       whole  = cpu_line && !cpu_we;
wire [127:0] b_line_dat = {b_w[0], b_w[1], b_w[2], b_w[3], b_w[4], b_w[5], b_w[6], b_w[7]};
wire       hit    = (cpu_adr[28:4] == b_adr) && b_vh[cpu_adr[3]];
wire       n_hit0 = n_v[0] && (cpu_adr[28:4] == n_adr[0]);
wire       n_hit1 = n_v[1] && (cpu_adr[28:4] == n_adr[1]);
wire       n_hit  = n_hit0 || n_hit1;
wire       n_sel  = n_hit1;
wire [127:0] n_line_dat = {n_w[n_sel][0], n_w[n_sel][1], n_w[n_sel][2], n_w[n_sel][3],
                           n_w[n_sel][4], n_w[n_sel][5], n_w[n_sel][6], n_w[n_sel][7]};
wire       snoop_n0  = snoop_act && (snoop_adr[28:4] == n_adr[0]);
wire       snoop_n1  = snoop_act && (snoop_adr[28:4] == n_adr[1]);
wire       cpu_wr_n0 = cpu_cs && cpu_we && (cpu_adr[28:4] == n_adr[0]);
wire       cpu_wr_n1 = cpu_cs && cpu_we && (cpu_adr[28:4] == n_adr[1]);
wire [28:4] pf_next = b_adr + 1'd1;
wire       pf_have = (n_v[0] && n_adr[0] == pf_next) || (n_v[1] && n_adr[1] == pf_next);
wire       cpu_wr_p = cpu_cs && cpu_we && (cpu_adr[28:4] == pf_adr);   // into the line being read ahead
// a write into the kept 16 bytes, or the 16 bytes of the burst arriving
// (b_adr from the miss on: the CPU may ask for its next transfer while the
// burst still arrives)
wire       snoop_b  = snoop_act && (snoop_adr[28:4] == b_adr);
wire       cpu_wr_b = cpu_cs && cpu_we && (cpu_adr[28:4] == b_adr);
wire [2:0] f_last = b_line ? 3'd7 : 3'd3;

// ---- chip RAM's code cache
// a line of chip RAM: cpu_adr[28:21] zero (chip 0, below 2 MB); its index
// cpu_adr[CLB+3:4], its tag the bits above up to 20
localparam CLN = (CLB > 0) ? (1 << CLB) : 2;
localparam CLI = (CLB > 0) ? CLB : 1;
localparam CLT = 17 - CLI;                 // tag bits: cpu_adr[20:CLI+4]
(* ram_style = "block" *)       reg [CLT+127:0] c_mem [0:CLN-1];
(* ram_style = "distributed" *) reg             c_v   [0:CLN-1];
reg [CLT+127:0] c_q;          // the entry at the address of the clock before
reg             c_vq;
reg     [28:4]  c_la;         // that address
reg             c_coll;       // its valid bit was written in that clock
reg             c_clr;        // the valid bits are being cleared (after a reset)
reg  [CLI-1:0]  c_sw;
reg             c_ins;        // a chip 0 burst has ended: its line may enter
reg             c_wpend;      // a CPU write to chip RAM on this port: its index to be cleared
reg  [CLI-1:0]  c_widx;
wire            c_reg_cpu = (cpu_adr[28:21] == 8'd0);
wire            c_reg_snp = (snoop_adr[28:21] == 8'd0);
wire            c_try  = (CLB > 0) && c_reg_cpu && !c_clr && !c_wpend;
wire            c_hit  = c_vq && !c_coll && (c_la == cpu_adr[28:4]) && (c_q[CLT+127:128] == cpu_adr[20:CLI+4]) &&
                         !c_clr && !c_wpend;
wire [127:0]    c_line = c_q[127:0];
wire  [15:0]    c_w [0:7];
genvar ci;
generate for (ci = 0; ci < 8; ci = ci + 1) begin : c_words
	assign c_w[ci] = c_line[127 - 16 * ci -: 16];
end endgenerate
// the valid bits' one write port: the clearing after a reset first, then a
// write to chip RAM (the chipset's, the CPU's), then a line entering (which
// waits for no write: it is given up if one comes in its clock)
wire            c_snp   = snoop_act && c_reg_snp;
wire            c_cwr   = cpu_cs && cpu_we && c_reg_cpu;
wire            c_enter = c_ins && !b_line && (b_vh == 2'b11) && (b_adr[28:21] == 8'd0) &&
                          !snoop_act && !c_cwr && !c_clr && !c_wpend && (CLB > 0);
wire            c_vwe   = c_clr || c_snp || c_wpend || c_enter;
wire [CLI-1:0]  c_vwa   = c_clr ? c_sw : c_snp ? snoop_adr[CLI+3:4] : c_wpend ? c_widx : b_adr[CLI+3:4];
wire            c_vwd   = !c_clr && !c_snp && !c_wpend;
always @(posedge clk) begin
	if (c_enter) c_mem[b_adr[CLI+3:4]] <= {b_adr[20:CLI+4], b_line_dat};
	c_q <= c_mem[cpu_adr[CLI+3:4]];
end
always @(posedge clk) begin
	if (c_vwe) c_v[c_vwa] <= c_vwd;
	c_vq   <= c_v[cpu_adr[CLI+3:4]];
	c_la   <= cpu_adr[28:4];
	c_coll <= c_vwe && (c_vwa == cpu_adr[CLI+3:4]);
end
always @(posedge clk) begin
	if (rst) begin
		c_clr   <= 1'b1;
		c_sw    <= {CLI{1'b0}};
		c_wpend <= 1'b0;
	end
	else begin
		if (c_clr) begin
			c_sw <= c_sw + 1'd1;
			if (&c_sw) c_clr <= 1'b0;
		end
		// (chip RAM is not written through this port; if it is, the line
		// leaves once the port is free, the cache off until then)
		if (c_cwr) begin
			c_wpend <= 1'b1;
			c_widx  <= cpu_adr[CLI+3:4];
		end
		else if (c_wpend && !c_clr && !c_snp) c_wpend <= 1'b0;
	end
end

assign cpu_idle = (st == S_IDLE);

wire req_next = (st == S_READ) ? cpu_cs && !hit && !n_hit && !c_try :
                (st == S_CLK)  ? cpu_cs && !c_hit :
                                 (st == S_FILL) && (f_cnt == 3'd0) && !sdr_read_ack;
always @(posedge clk) sdr_read_req <= !rst && req_next;

always @(posedge clk) begin
	if (rst) begin
		st         <= S_IDLE;
		cpu_ack    <= 1'b0;
		cpu_ack_l  <= 1'b0;
		cpu_ack_line <= 1'b0;
		wb_en      <= 1'b0;
		buf_take   <= 1'b0;
		gap        <= 1'b0;
		f_whole    <= 1'b0;
		b_vh       <= 2'b00;
		b_line     <= 1'b0;
		f_cnt      <= 3'd0;
		f_ok       <= 1'b0;
		f_long     <= 1'b0;
		f_done     <= 1'b0;
		n_v[0]     <= 1'b0;
		n_v[1]     <= 1'b0;
		n_lru      <= 1'b0;
		pf_slot    <= 1'b0;
		pf_pend    <= 1'b0;
		pf_on      <= 1'b0;
		pf_req     <= 1'b0;
		pf_cnt     <= 3'd0;
		pf_ok      <= 1'b0;
		c_ins      <= 1'b0;
	end
	else begin
		wb_en    <= 1'b0;
		buf_take <= 1'b0;
		c_ins    <= 1'b0;
		case (st)
			S_IDLE:
				if (cpu_cs) st <= cpu_we ? S_WRITE : S_READ;
				else if (pf_pend) begin
					// read the next line ahead (not if it is already here)
					pf_pend <= 1'b0;
					// (in chip 1 only: the controller reads ahead there)
					if (!pf_have && pf_next >> 21 == b_adr >> 21 && b_adr[25]) begin
						n_v[pf_slot] <= 1'b0;
						n_lru  <= ~pf_slot;
						pf_adr <= pf_next;
						pf_req <= 1'b1;
						pf_ok  <= 1'b1;
						st     <= S_PF;
					end
				end
			S_PF:
				if (pf_ack) begin
					pf_req <= 1'b0;
					pf_on  <= 1'b1;
					pf_cnt <= 3'd0;
					n_adr[pf_slot] <= pf_adr;
				end
				else if (pf_on) begin
					if (sdr_read_ack) begin
						n_w[pf_slot][pf_cnt] <= sdr_dat_r;   // from the line's word 0 (its column a multiple of 8)
						pf_cnt      <= pf_cnt + 3'd1;
						if (pf_cnt == 3'd7) begin
							n_v[pf_slot] <= pf_ok && !(pf_slot ? snoop_n1 || cpu_wr_n1 : snoop_n0 || cpu_wr_n0);
							pf_on <= 1'b0;
							st    <= S_IDLE;
						end
					end
				end

			S_WRITE: begin
				gap   <= !cpu_cs;
				wb_en <= 1'b1;
				st    <= cpu_cs ? S_WB : S_IDLE;
			end
			S_WB:
				if (!cpu_cs || gap) st <= S_IDLE;
				else wb_en <= 1'b1;
			S_READ:
				if (!cpu_cs) st <= S_IDLE;
				else if (!hit && n_hit) begin
					// the line read ahead: answered from it, kept from now on
					cpu_dat_r  <= n_w[n_sel][lng ? {cpu_adr[3:2], 1'b1} : cpu_adr[3:1]];
					cpu_dat_hi <= n_w[n_sel][{cpu_adr[3:2], 1'b0}];
					cpu_dat_line <= n_line_dat;
					cpu_ack    <= 1'b1;
					cpu_ack_l  <= lng;
					cpu_ack_line <= whole;
					for (int k = 0; k < 8; k++) b_w[k] <= n_w[n_sel][k];
					b_adr      <= n_adr[n_sel];
					b_line     <= 1'b1;
					b_vh       <= 2'b11;
					n_v[n_sel] <= 1'b0;
					pf_slot    <= n_sel;     // the stream's next line: its own buffer
					pf_pend    <= 1'b1;
					st         <= S_FILLW;
				end
				else if (hit) begin
					cpu_dat_r  <= b_w[lng ? {cpu_adr[3:2], 1'b1} : cpu_adr[3:1]];
					cpu_dat_hi <= b_w[{cpu_adr[3:2], 1'b0}];
					cpu_dat_line <= b_line_dat;
					cpu_ack    <= 1'b1;
					cpu_ack_l  <= lng;
					cpu_ack_line <= whole && (b_vh == 2'b11);
					st         <= S_FILLW;
				end
				else if (c_try) st <= S_CLK;   // chip RAM: its code cache first
				else begin
					// (chip 0: the other half of the same line stays)
					b_vh   <= (!cpu_adr[25] && !b_line && cpu_adr[28:4] == b_adr) ? (b_vh & (cpu_adr[3] ? 2'b01 : 2'b10)) : 2'b00;
					b_adr  <= cpu_adr[28:4];
					b_line <= cpu_adr[25];
					f_h    <= cpu_adr[3];
					f_w    <= cpu_adr[2:1];
					f_cnt  <= 3'd0;
					f_ok   <= 1'b1;
					f_long <= lng;
					f_done <= 1'b0;
					f_whole <= whole && cpu_adr[25];
					st     <= S_FILL;
				end
			S_CLK:
				if (!cpu_cs) st <= S_IDLE;
				else if (c_hit) begin
					// from chip RAM's code cache (not made the kept line: a
					// write to it in this very clock would not be seen there)
					cpu_dat_r  <= c_w[lng ? {cpu_adr[3:2], 1'b1} : cpu_adr[3:1]];
					cpu_dat_hi <= c_w[{cpu_adr[3:2], 1'b0}];
					cpu_dat_line <= c_line;
					cpu_ack    <= 1'b1;
					cpu_ack_l  <= lng;
					cpu_ack_line <= whole;
					st         <= S_FILLW;
				end
				else begin
					b_vh   <= (!b_line && cpu_adr[28:4] == b_adr) ? (b_vh & (cpu_adr[3] ? 2'b01 : 2'b10)) : 2'b00;
					b_adr  <= cpu_adr[28:4];
					b_line <= 1'b0;
					f_h    <= cpu_adr[3];
					f_w    <= cpu_adr[2:1];
					f_cnt  <= 3'd0;
					f_ok   <= 1'b1;
					f_long <= lng;
					f_done <= 1'b0;
					f_whole <= 1'b0;
					st     <= S_FILL;
				end
			S_FILL:
				if (sdr_read_ack) begin
					b_w[f_idx] <= sdr_dat_r;
					f_cnt      <= f_cnt + 3'd1;
					// the word asked for, or (a long word) the one after it;
					// a whole line at the burst's end (S_LACK)
					if (f_cnt == 3'd0 && !f_long && !f_whole) begin
						cpu_dat_r <= sdr_dat_r;
						cpu_ack   <= 1'b1;
						f_done    <= 1'b1;
					end
					if (f_cnt == 3'd0) cpu_dat_hi <= sdr_dat_r;
					if (f_cnt == 3'd1 && f_long && !f_whole) begin
						cpu_dat_r <= sdr_dat_r;
						cpu_ack   <= 1'b1;
						cpu_ack_l <= 1'b1;
						f_done    <= 1'b1;
					end
					if (f_cnt == f_last) begin
						// both halves of a line, the asked for half of a burst
						// (beside the other half, if that is kept)
						b_vh <= (f_ok && !snoop_b && !cpu_wr_b) ? (b_line ? 2'b11 : (b_vh | (f_h ? 2'b10 : 2'b01))) : 2'b00;
						c_ins <= !b_line;
						pf_pend <= b_line;   // a chip 1 line: read the next ahead
						pf_slot <= n_lru;    // (a new stream)
						st   <= f_whole ? S_LACK : S_FILLW;
					end
				end
			S_LACK: begin
				// the whole line (its last word written into b_w on the
				// clock before); the CPU still waits for it
				cpu_dat_line <= b_line_dat;
				cpu_dat_hi   <= b_w[{f_h, f_w[1], 1'b0}];
				cpu_dat_r    <= b_w[{f_h, f_w[1], 1'b1}];
				cpu_ack      <= 1'b1;
				cpu_ack_l    <= 1'b1;
				cpu_ack_line <= 1'b1;
				f_whole      <= 1'b0;
				st           <= S_FILLW;
			end
			S_FILLW:
				if (!cpu_ack || (!cpu_cs && !sdr_read_ack)) st <= S_IDLE;
			default:
				st <= S_IDLE;
		endcase
		// a write into the kept 16 bytes, or into the burst arriving
		if (snoop_b || cpu_wr_b) b_vh <= 2'b00;
		if (snoop_n0 || cpu_wr_n0) n_v[0] <= 1'b0;
		if (snoop_n1 || cpu_wr_n1) n_v[1] <= 1'b0;
		if (st == S_PF && (cpu_wr_p || (snoop_act && snoop_adr[28:4] == pf_adr)))
			pf_ok <= 1'b0;
		if (st == S_FILL && (snoop_b || cpu_wr_b)) f_ok <= 1'b0;
		// the CPU lowers its request: the acknowledge goes too
		if (!cpu_cs) begin
			cpu_ack   <= 1'b0;
			cpu_ack_l <= 1'b0;
			cpu_ack_line <= 1'b0;
		end
	end
end

endmodule
