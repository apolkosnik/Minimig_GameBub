// Game Bub Minimig: SDRAM controller for both SDRAM chips of the board.
//
// Derived from the MiSTer Minimig sdram_ctrl.v (Copyright (c) 2009/2011
// Tobias Gubener, rework (C)2019 Alexey Melnikov), GPL-3.0-or-later. The
// chipset, CPU (cpu_cache_new) and host ports behave as that controller's
// (see rtl/minimig/sdram_ctrl.sv); what differs is how the SDRAM is driven.
//
// The SDRAM clock is the controller clock (clk_114, 113.54 MHz) itself,
// inverted and forwarded by an ODDR, so the SDRAM takes each command half a
// clk_114 period after the I/O block register that drives it changes. CAS
// latency 3, burst length 4 for reads, single-word writes; ACTIVE to
// READ/WRITE and PRECHARGE to ACTIVE take 3 clocks (26.4 ns), which covers
// the slowest common 133 MHz parts (tRCD / tRP 20 ns).
//
// A window is one 7 MHz period: 16 clk_114 cycles, states 0-15, state 0
// starting two clk_114 cycles after the clk_sys edge at which c_7m rises
// (as in sdram_ctrl). A command "at state n" is on the pins during state n
// and taken by the SDRAM at its rising clock edge in the middle of it; read
// data of the edge in state n is taken (sd_in_q) at the clk_114 edge that
// ends state n. The two chips share every pin but the chip selects:
//
//            commands                         data on the bus
//   chip 0   ACTIVE 2, READ 5                 read 8-11
//            or WRITE 7 (and 8, chip32 or     write 7 (8)
//            the CPU's long word)
//   chip 1   ACTIVE 6, READ 10 (and 14,       read 13-15 (16-20 = 0-4 of
//            a burst or the CPU's line)       the next window)
//            or WRITE 13 (and 14, the CPU's   write 13 (14)
//            long word)
//
// so the command bus never has two commands in one cycle, and between data
// driven by different devices (chip 0, chip 1, the FPGA) there is always at
// least one idle cycle (sim/tb/tb_top.sv checks both on every edge).
// Every access closes its row (auto precharge); the bank is idle again
// before the next window's ACTIVE of the same chip.
//
// Chip 0 serves the chipset, the CPU's chip-0 RAM (cpuAddr[25] = 0) and the
// host port, deciding at state 0 exactly as sdram_ctrl did, and hands the
// chipset and host their data at the same states as sdram_ctrl (chipRD at 9,
// chip48 at 11/13/15), the cache its words at 10/12/14/0. The decisions are
// registered and each ACTIVE goes out a clock later from those registers
// (the arbitration does not reach the I/O block registers at the pins).
// Chip 1 decides at state 4 (two clk_114 cycles after a clk_sys edge, as
// state 0 is) and serves the CPU's chip-1 RAM (cpuAddr[25] = 1) and the
// burst port: eight words (two READs of four, one row) per window, for the
// RTG scan-out. Each chip refreshes in its own ACTIVE slot.
//
// The CPU's long words (cpuLong1: cpu_wrapper's ramlong1, the TG68K's
// long_cand on its RAM, the TG68K's ramready_l contract as MiSTer's
// ddram_ctrl has it): a write is one entry of the write buffer, both words
// written in its slot (ramready_l with ramready when the entry is taken); a
// read is answered with both words (cpuRD_hi, cpuRD; ramready_l) where the
// cache (cpu_cache_new with LINE_TAKE: its data in 64-bit lines) has the
// line. With CPU_LINE16 a CPU read of chip 1 takes the 16 bytes around the
// word asked for (eight words, two READs as the burst port's: the word asked
// for and the rest of its 8 bytes, then the other 8 bytes from the same word
// on), every word to the cache (sdr_read_ack) as it arrives; the cache must
// take eight (the AP68040 variant's cpu_cache_new). Its cache may also ask
// for the next line ahead (pf_req, pf_adr): read like the CPU's line in a
// chip 1 slot after the CPU's reads and writes (before the burst port's
// requests that are not urgent: the CPU waits for it), never while a
// queued write is for that line (pf_ack: taken).
//
// With WQN > 1 the CPU's writes queue (WQN entries, in order): a write is
// acknowledged as soon as it is queued, the queue's head goes to the
// SDRAM as the single entry does, and a CPU read waits while an entry for
// its 16 bytes is queued (cache_req is held off: writes of either chip
// may be queued ahead of the read's chip). Chipset reads are forwarded
// the head's words as before; the queue holds only the CPU's RAM (fast
// RAM, the RTG memory), which the chipset does not read.
//
// SPDX-License-Identifier: GPL-3.0-or-later

module gb_sdram_ctrl
#(
	parameter CPU_LINE16 = 0,
	parameter WQN        = 1    // the CPU's write buffer: entries (1, or a power of two)
)
(
	// system
	input             sysclk,
	input             sdclk,      // the clock forwarded (inverted) as the SDRAM clock: sysclk
	input             c_7m,
	input             reset_n,
	input             cache_rst,
	input             cache_inhibit,
	input       [3:0] cpu_cache_ctrl,
	input             dcache_sw_en,
	// sdram
	output reg [12:0] sd_addr,
	output reg  [1:0] sd_ba,
	output reg  [1:0] sd_cs = 2'b11,   // active low, one per chip
	output reg        sd_we  = 1'b1,
	output reg        sd_ras = 1'b1,
	output reg        sd_cas = 1'b1,
	output reg  [1:0] sd_dqm = 2'b11,
	input      [15:0] sd_data_in,
	output reg [15:0] sd_data_out,
	output reg        sd_data_oe = 1'b0,
	output            sd_clk,
	output      [1:0] sd_cke,
	// chip
	input      [24:1] chipAddr,
	input             chipL,
	input             chipU,
	input             chipRW,
	input             chipDMA,
	input      [15:0] chipWR,
	output reg [15:0] chipRD,
	output     [47:0] chip48,
	input             chip32,
	input      [15:0] chipWR2,
	output reg [15:0] chipRD2,
	// cpu
	input      [25:1] cpuAddr,   // bit 25: chip 1
	input             cpuCS,
	input       [1:0] cpustate,
	input             cpuL,
	input             cpuU,
	input      [15:0] cpuWR,
	output     [15:0] cpuRD,
	output            ramready,
	input             cpuLong1,  // a long word in one transfer (cpu_wrapper ramlong1)
	input      [15:0] cpuWR_lo,
	output     [15:0] cpuRD_hi,
	output            ramready_l,
	input             cpuLine,   // CPU_LINE16: a line read, answered whole (the AP68040 variant)
	output    [127:0] cpuRD_line,
	output            ramready_line,
	// every write to chip RAM (chip 0 below 2 MB: the chipset's and the CPU's
	// over the chip bus), for a CPU that keeps chip RAM's code in a cache of
	// its own (the AP68040 variant): chipwr_tgl flips with each, its 16-byte
	// line in chipwr_line from that clock on
	output reg        chipwr_tgl = 1'b0,
	output reg [20:4] chipwr_line = 17'd0,
	// host (chip 0, lowest priority, one word per request)
	input      [24:1] hostAddr,
	input             hostReq,   // hold until hostAck
	input             hostWE,
	input       [1:0] hostDQM,   // byte masks, active high (1 = byte not written)
	input      [15:0] hostWR,
	output reg [15:0] hostRD,
	output reg        hostAck,   // one clock; hostRD is valid with it on reads
	// burst reads of chip 1 (eight words, one row)
	input      [24:4] burstAddr,
	input             burstReq,    // hold until burstAck
	input             burstUrgent, // ahead of the CPU
	output reg        burstAck = 1'b0,   // one clock: the request is taken
	output reg [15:0] burstData,
	output reg        burstValid = 1'b0  // one clock per word, eight in address order
);

assign sd_cke = 2'b11;

// the SDRAM clock: sdclk inverted, through an output DDR register
ODDR #(
	.DDR_CLK_EDGE("OPPOSITE_EDGE"),
	.INIT(1'b0),
	.SRTYPE("SYNC")
) sd_clk_oddr (
	.Q (sd_clk),
	.C (sdclk),
	.CE(1'b1),
	.D1(1'b0),
	.D2(1'b1),
	.R (1'b0),
	.S (1'b0)
);

localparam [2:0]
	IDLE    = 0,
	CHIP    = 1,
	CPU_RD  = 2,
	CPU_WR  = 3,
	HOST    = 4,
	BURST   = 5,
	REFRESH = 6;

localparam HOST_STARVE = 4'd8;

// LOAD MODE value: single-word writes, CAS latency 3, sequential, burst of 4
localparam [12:0] MODE = 13'b000_1_00_011_0_010;

////////////////////////////////////////
// reset
////////////////////////////////////////

reg reset;
reg [3:0] sdram_state;
always @(posedge sysclk) begin
	reg [7:0] reset_cnt;

	if(!reset_n) begin
		reset_cnt     <= 0;
		reset         <= 0;
	end else begin
		if(reset_cnt == 170) begin
			if(sdram_state == 15) reset <= 1;
		end
		else begin
			reset_cnt <= reset_cnt + 8'd1;
		end
	end
end

//// window state ////
reg old_7m;
always @(posedge sysclk) begin
	sdram_state <= sdram_state + 1'd1;
	old_7m <= c_7m;
	if(~old_7m & c_7m) sdram_state <= 0;
end

//// init counter ////
reg [3:0] initstate;
reg       init_done;
always @ (posedge sysclk) begin
	if(!reset) begin
		initstate <= 0;
		init_done <= 0;
	end else begin
		if (sdram_state == 15) begin
			if(~&initstate) initstate <= initstate + 1'd1;
			else init_done <= 1;
		end
	end
end

wire ramsel = cpuCS & (~&cpustate | ~cpuU | ~cpuL);

////////////////////////////////////////
// CPU cache
////////////////////////////////////////
wire cache_rd_ack;
wire cache_rd_ack_l;
wire        pf_req;
wire [28:4] pf_adr;
reg         pf_ack = 1'b0;
wire cache_wr_ack;
wire cache_req;
reg        cache_fill = 0;
reg [15:0] cache_dat;
reg        a_wr2 = 0;
reg        a_rd2 = 0;
reg [15:0] datawr2;
reg        chipWE = 0;
reg        chipWE2 = 0;
reg        snoop2 = 0;

// chip RAM's writes, one flip each (chipWE is up two clocks; a 32-bit write's
// second word is in the same line)
reg chipWE_q = 1'b0;
always @(posedge sysclk) begin
	chipWE_q <= chipWE;
	if (chipWE && !chipWE_q && chipAddr[24:21] == 4'd0) begin
		chipwr_tgl  <= ~chipwr_tgl;
		chipwr_line <= chipAddr[20:4];
	end
end
// (the line ports: the AP68040 variant's cpu_cache_new answers a line
// whole with CPU_LINE16; the upstream one ties them off)
cpu_cache_new
#(.LINE_TAKE(1))
cpu_cache
(
	.clk              (sysclk),                // clock
	.rst              (!reset || !cache_rst),  // cache reset
	.cpu_cache_ctrl   (cpu_cache_ctrl),        // CPU cache control
	.dcache_sw_en     (dcache_sw_en),
	.cache_inhibit    (cache_inhibit),         // cache inhibit
	.cpu_cs           (ramsel),                // cpu activity
	.cpu_adr          (cpuAddr),               // cpu address
	.cpu_bs           ({!cpuU, !cpuL}),        // cpu byte selects
	.cpu_we           (cpustate == 3),         // cpu write
	.cpu_ir           (cpustate == 0),         // cpu instruction read
	.cpu_dr           (cpustate == 2),         // cpu data read
	.cpu_dat_w        (cpuWR),                 // cpu write data
	.cpu_dat_r        (cpuRD),                 // cpu read data
	.cpu_ack          (cache_rd_ack),          // cpu acknowledge
	.wb_en            (cache_wr_ack),          // write enable
	.cpu_idle         (),
	.sdr_dat_r        (cache_dat),             // sdram read data
	.sdr_read_req     (cache_req),             // sdram read request from cache
	.sdr_read_ack     (cache_fill),            // sdram read acknowledge to cache
	.snoop_act        (chipWE | chipWE2),      // snoop act (write only - just update existing data in cache)
	.snoop_adr        (snoop2 ? {chipAddr[24:2], 1'b1} : chipAddr), // snoop address
	.snoop_dat_w      (snoop2 ? chipWR2 : chipWR), // snoop write data
	.snoop_bs         (snoop2 ? 2'b11 : {!chipU, !chipL}), // snoop byte selects
	.buf_ok           (1'b0),
	.buf_dat          (64'd0),
	.buf_take         (),
	.cpu_long         (cpuLong1),
	.cpu_dat_w_lo     (cpuWR_lo),
	.cpu_dat_hi       (cpuRD_hi),
	.cpu_ack_l        (cache_rd_ack_l),
	.cpu_line         (cpuLine),
	.cpu_dat_line     (cpuRD_line),
	.cpu_ack_line     (ramready_line),
	.pf_req           (pf_req),
	.pf_adr           (pf_adr),
	.pf_ack           (pf_ack)
);

////////////////////////////////////////
// write buffer, enables CPU to continue while a write is in progress
////////////////////////////////////////
reg        write_ena;
reg        write_req;
reg        write_ack = 0;
reg  [1:0] write_dqm;
reg [25:1] writeAddr;
reg [15:0] writeDat;
reg        write_l1;     // the entry is a long word: writeDat, then writeDatLo at +2
reg [15:0] writeDatLo;
reg        w_l1 = 0;     // the CPU's long word taken (ramready_l)

wire wq_hit;   // a queued write for the 16 bytes of the CPU's address (WQN > 1)
wire pf_hit;   // a queued write for the line read ahead

generate if (WQN == 1) begin : wbuf1

assign wq_hit = 1'b0;   // (the single entry is written before a read of its chip)
assign pf_hit = write_req && (writeAddr[25:4] == pf_adr[25:4]);

always @ (posedge sysclk) begin
	reg  [1:0] write_state;

	if(~reset_n) begin
		write_req   <= 0;
		write_ena   <= 0;
		w_l1        <= 0;
		write_state <= 0;
	end else begin
		case(write_state)
			default:
				if(~write_ena && ramsel && cpustate == 3) begin
					writeAddr  <= cpuAddr;
					writeDat   <= cpuWR;
					write_dqm  <= {cpuU, cpuL};
					write_l1   <= cpuLong1 & ~cpuAddr[1];
					writeDatLo <= cpuWR_lo;
					if(cache_wr_ack) begin
						write_req   <= 1;
						write_ena   <= 1;
						w_l1        <= cpuLong1 & ~cpuAddr[1];
						write_state <= 1;
					end
				end

			1: if(write_ack) begin
					write_req   <= 0;
					write_state <= 2;
				end

			2: if(!write_ack) begin
					write_state <= 0;
				end
		endcase

		if(~ramsel) begin
			write_ena <= 0;
			w_l1      <= 0;
		end
	end
end

end else begin : wbufq

localparam QB = $clog2(WQN);
reg [25:1] q_a  [0:WQN-1];
reg [15:0] q_d  [0:WQN-1];
reg [15:0] q_dl [0:WQN-1];
reg  [1:0] q_m  [0:WQN-1];
reg        q_l  [0:WQN-1];
reg [WQN-1:0] q_v = 0;
reg  [QB:0] q_n = 0;
reg [QB-1:0] q_h = 0, q_t = 0;
reg        ack_d = 0;
wire       room = (q_n != WQN);
wire       pop  = write_ack & ~ack_d;   // the head taken (state 0 or 4)
// queued once the CPU's select has been up for two controller clocks (not
// after the cache's wb_en, a clock later): the select (ram_cs) and the
// CPU's address, data and state reach this clock domain over two-cycle
// paths (minimig.xdc), so the first clock after a clk_sys edge may still
// show the last transfer's select beside the next one's state and address
// -- a write nobody made. The cache updates or drops its own copy of the
// written bytes meanwhile (cpu_cache_new's WRITE state, the AP68040
// variant's buffer on cpu_cs and cpu_we), and the write's ramready still
// meets the clk_sys edge that ends the transfer.
reg        ramsel_d = 0;
always @(posedge sysclk) ramsel_d <= ramsel;
wire       push = ~write_ena && ramsel && ramsel_d && (cpustate == 3) && room;

always @(posedge sysclk) begin
	ack_d <= write_ack;
	if(~reset_n) begin
		q_v       <= 0;
		q_n       <= 0;
		q_h       <= 0;
		q_t       <= 0;
		write_ena <= 0;
		w_l1      <= 0;
	end else begin
		if(push) begin
			q_a[q_t]  <= cpuAddr;
			q_d[q_t]  <= cpuWR;
			q_dl[q_t] <= cpuWR_lo;
			q_m[q_t]  <= {cpuU, cpuL};
			q_l[q_t]  <= cpuLong1 & ~cpuAddr[1];
			q_t       <= q_t + 1'd1;
			write_ena <= 1;
			w_l1      <= cpuLong1 & ~cpuAddr[1];
		end
		if(pop) q_h <= q_h + 1'd1;
		q_v <= (q_v | (push ? (1 << q_t) : 0)) & ~(pop ? (1 << q_h) : 0);
		q_n <= q_n + push - pop;
		if(~ramsel) begin
			write_ena <= 0;
			w_l1      <= 0;
		end
	end
end

always @* begin
	write_req  = (q_n != 0);
	writeAddr  = q_a[q_h];
	writeDat   = q_d[q_h];
	writeDatLo = q_dl[q_h];
	write_dqm  = q_m[q_h];
	write_l1   = q_l[q_h];
end

reg hit, hit_pf;
integer qi;
always @* begin
	hit    = 1'b0;
	hit_pf = 1'b0;
	for (qi = 0; qi < WQN; qi = qi + 1) begin
		if (q_v[qi] && (q_a[qi][25:4] == cpuAddr[25:4])) hit = 1'b1;
		if (q_v[qi] && (q_a[qi][25:4] == pf_adr[25:4]))  hit_pf = 1'b1;
	end
end
assign wq_hit = hit;
assign pf_hit = hit_pf;

end endgenerate

assign ramready   = cache_rd_ack || write_ena;
assign ramready_l = cache_rd_ack_l || (write_ena && w_l1);

////////////////////////////////////////
// slot decisions
////////////////////////////////////////

// refresh: one owed to each chip every 32 windows (4.5 us, the SDRAM needs
// one per 7.8 us), taken in an idle slot, or ahead of everything but the
// chipset once three are owed
reg  [4:0] ref_timer = 0;
reg  [2:0] owed0 = 0, owed1 = 0;

// chip 0, decided at state 0
wire        chip_req = ~chipDMA | ~chipRW;
wire        c0_wr    = write_req & ~writeAddr[25];
wire        c0_rd    = cache_req & ~cpuAddr[25] & ~wq_hit;
// with a write queue (WQN > 1) a CPU read goes ahead of the queued writes
// (a read of a queued write's 16 bytes waits: wq_hit); they take the slots
// no read wants. The single entry goes first, as in sdram_ctrl.
wire        c0_wq    = c0_wr & ~((WQN > 1) & c0_rd);
reg         host_busy = 0;  // the request is being served (slot taken)
reg   [3:0] host_wait = 0;
wire        host_go  = hostReq & ~host_busy & ~c0_wr & (~c0_rd | (host_wait >= HOST_STARVE));
wire  [2:0] c0_next  = chip_req       ? CHIP    :
                       (owed0 >= 3)   ? REFRESH :
                       c0_wq          ? CPU_WR  :
                       host_go        ? HOST    :
                       c0_rd          ? CPU_RD  :
                       (owed0 != 0)   ? REFRESH : IDLE;
wire [24:1] c0_addr  = (c0_next == CHIP) ? chipAddr : (c0_next == CPU_WR) ? writeAddr[24:1] :
                       (c0_next == HOST) ? hostAddr : cpuAddr[24:1];

// chip 1, decided at state 4
wire        c1_wr    = write_req & writeAddr[25];
wire        c1_rd    = cache_req & cpuAddr[25] & ~wq_hit;
wire        c1_wq    = c1_wr & ~((WQN > 1) & c1_rd);
// the line read ahead (CPU_LINE16): a CPU_RD slot of pf_adr's line
wire        c1_pf    = CPU_LINE16 && pf_req && pf_adr[25] && !pf_hit && !pf_ack;
wire  [2:0] c1_next  = (owed1 >= 3)              ? REFRESH :
                       (burstReq & burstUrgent)  ? BURST   :
                       c1_wq                     ? CPU_WR  :
                       c1_rd                     ? CPU_RD  :
                       c1_pf                     ? CPU_RD  :   // (the CPU waits for it)
                       burstReq                  ? BURST   :
                       (owed1 != 0)              ? REFRESH : IDLE;
wire        c1_pfsel = (c1_next == CPU_RD) && !c1_rd;   // the slot is the read ahead
wire [24:1] c1_addr  = (c1_next == CPU_WR) ? writeAddr[24:1] : (c1_next == BURST) ? {burstAddr, 3'b000} :
                       c1_pfsel ? {pf_adr[24:4], 3'b000} : cpuAddr[24:1];

reg   [2:0] c0_type = IDLE, c1_type = IDLE, c1_prev = IDLE;
reg   [9:0] c0_col, c1_col;
reg   [1:0] c0_ba, c1_ba;
reg  [12:0] c0_row, c1_row;
reg   [1:0] c0_dqm, c1_dqm;
reg  [15:0] c0_dat, c1_dat;
reg         c0_l2 = 0, c1_l2 = 0;   // the CPU's long word: a second WRITE at +2
reg  [15:0] c1_dat2;

// write data forwarding to chipset reads (a CPU write to chip 0 still in
// the write buffer), as sdram_ctrl
reg         fwd_en = 1'b0;
reg   [1:0] fwd_pos;
reg  [15:0] fwd_dat;
reg   [1:0] fwd_dqm;
reg         fwd_l2;     // and the long word's second word, at fwd_pos + 1
reg  [15:0] fwd_dat2;

////////////////////////////////////////
// SDRAM commands
////////////////////////////////////////
reg c0_write, hostWE_q;   // chipRW / hostWE at the decision

task automatic cmd(input [1:0] cs, input ras, input cas, input we);
	sd_cs  <= cs;
	sd_ras <= ras;
	sd_cas <= cas;
	sd_we  <= we;
endtask

always @ (posedge sysclk) begin
	// a NOP to both chips unless a command is given below
	cmd(2'b11, 1, 1, 1);
	sd_dqm     <= init_done ? 2'b00 : 2'b11;
	sd_data_oe <= 0;
	burstAck   <= 0;
	pf_ack     <= 0;

	if(~sdram_state[0]) chipWE <= 0;
	if(sdram_state == 4) begin
		chipWE2 <= a_wr2;
		snoop2  <= a_wr2;
	end
	if(sdram_state == 6) chipWE2 <= 0;
	if(sdram_state == 8) snoop2  <= 0;
	if(sdram_state == 6) write_ack <= 0;   // chip 1 took it at state 4
	if(sdram_state == 2) write_ack <= 0;   // chip 0 took it at state 0
	if(hostAck) host_busy <= 0;

	if(!init_done) begin
		c0_type   <= IDLE;
		c1_type   <= IDLE;
		c1_prev   <= IDLE;
		a_wr2     <= 0;
		a_rd2     <= 0;
		fwd_en    <= 0;
		host_busy <= 0;
		host_wait <= 0;
		owed0     <= 0;
		owed1     <= 0;
		ref_timer <= 0;
		write_ack <= 0;
		// initialisation, both chips: at state 2 of windows 4 (PRECHARGE
		// all), 8 and 10 (AUTO REFRESH) and 13 (LOAD MODE)
		if(reset && sdram_state == 1) begin
			sd_ba <= 2'b00;
			case(initstate)
				4: begin
					cmd(2'b00, 0, 1, 0);
					sd_addr <= 13'b0010000000000;   // all banks
				end
				8, 10: cmd(2'b00, 0, 0, 1);
				13: begin
					cmd(2'b00, 0, 0, 0);
					sd_addr <= MODE;
				end
			endcase
		end
	end else begin
		if(sdram_state == 15) begin
			ref_timer <= ref_timer + 1'd1;
			if(&ref_timer) begin
				if(~&owed0) owed0 <= owed0 + 1'd1;
				if(~&owed1) owed1 <= owed1 + 1'd1;
			end
			c1_prev <= c1_type;
		end

		case(sdram_state)
			// chip 0: decide
			0: begin
				c0_type <= c0_next;
				fwd_en  <= 0;
				a_wr2   <= 0;
				a_rd2   <= 0;
				c0_l2   <= 0;
				c0_col  <= {1'b0, c0_addr[9:1]};
				c0_ba   <= c0_addr[24:23];
				c0_row  <= c0_addr[22:10];
				c0_dqm  <= 2'b00;
				// counts every slot the pending host request does not get
				if(hostReq & ~host_busy & ~&host_wait) host_wait <= host_wait + 1'd1;

				case(c0_next)
					CHIP: begin
						c0_dqm  <= {chipU, chipL};
						c0_dat  <= chipWR;
						datawr2 <= chipWR2;
						chipWE  <= !chipRW;
						a_wr2   <= chip32 & !chipRW;
						a_rd2   <= chip32 &  chipRW;
						if(chipRW & c0_wr & (writeAddr[24:3] == chipAddr[24:3])) begin
							fwd_en   <= 1'b1;
							fwd_pos  <= writeAddr[2:1] - chipAddr[2:1];
							fwd_dat  <= writeDat;
							fwd_dqm  <= write_dqm;
							fwd_l2   <= write_l1;
							fwd_dat2 <= writeDatLo;
						end
					end
					CPU_WR: begin
						c0_dqm    <= write_dqm;
						c0_dat    <= writeDat;
						c0_l2     <= write_l1;
						datawr2   <= writeDatLo;
						write_ack <= 1; // let the write buffer know we're about to write
					end
					HOST: begin
						c0_dqm    <= hostDQM;
						c0_dat    <= hostWR;
						host_busy <= 1;
						host_wait <= 0;
					end
					REFRESH: if(owed0 != 0) owed0 <= owed0 - 1'd1;
				endcase

			end

			// chip 0 ACTIVE (or REFRESH) at state 2
			1: begin
				sd_ba   <= c0_ba;
				sd_addr <= c0_row;
				if(c0_type == REFRESH)   cmd(2'b10, 0, 0, 1);
				else if(c0_type != IDLE) cmd(2'b10, 0, 1, 1);
			end

			// chip 1: decide; chip 0 READ at state 5 (auto precharge)
			4: begin
				if(c0_type == CPU_RD || c0_type == HOST && !hostWE_q || c0_type == CHIP && !c0_write) begin
					cmd(2'b10, 1, 0, 1);
					sd_ba   <= c0_ba;
					sd_addr <= {2'b00, 1'b1, c0_col};
				end
				c1_type <= c1_next;
				c1_col  <= {1'b0, c1_addr[9:1]};
				c1_ba   <= c1_addr[24:23];
				c1_row  <= c1_addr[22:10];
				c1_dqm  <= write_dqm;
				c1_dat  <= writeDat;
				c1_l2   <= write_l1 & (c1_next == CPU_WR);
				c1_dat2 <= writeDatLo;
				case(c1_next)
					CPU_WR:  write_ack <= 1;
					CPU_RD:  if(c1_pfsel) pf_ack <= 1;   // the read ahead taken
					BURST:   burstAck  <= 1;
					REFRESH: if(owed1 != 0) owed1 <= owed1 - 1'd1;
				endcase
			end

			// chip 1 ACTIVE (or REFRESH) at state 6
			5: begin
				sd_ba   <= c1_ba;
				sd_addr <= c1_row;
				if(c1_type == REFRESH)   cmd(2'b01, 0, 0, 1);
				else if(c1_type != IDLE) cmd(2'b01, 0, 1, 1);
			end

			// chip 0 WRITE at state 7 (auto precharge unless a second word
			// follows at 8: chip32's, the CPU's long word's)
			6: if(c0_type == CPU_WR || c0_type == HOST && hostWE_q || c0_type == CHIP && c0_write) begin
				cmd(2'b10, 1, 0, 0);
				sd_ba       <= c0_ba;
				sd_addr     <= {2'b00, ~(a_wr2 | (c0_type == CPU_WR && c0_l2)), c0_col};
				sd_dqm      <= c0_dqm;
				sd_data_out <= c0_dat;
				sd_data_oe  <= 1;
			end
			7: if(a_wr2 || c0_type == CPU_WR && c0_l2) begin
				cmd(2'b10, 1, 0, 0);
				sd_ba       <= c0_ba;
				sd_addr     <= {2'b00, 1'b1, c0_col[9:1], 1'b1};
				sd_dqm      <= 2'b00;
				sd_data_out <= datawr2;
				sd_data_oe  <= 1;
			end

			// chip 1 READ at state 10 (auto precharge unless the second READ
			// of a burst or of the CPU's line follows at 14)
			9: if(c1_type == CPU_RD || c1_type == BURST) begin
				cmd(2'b01, 1, 0, 1);
				sd_ba   <= c1_ba;
				sd_addr <= {2'b00, !(c1_type == BURST || CPU_LINE16), c1_col};   // a burst's column is a multiple of 8
			end

			// chip 1 WRITE at state 13 (auto precharge unless the long
			// word's second word follows at 14)
			12: if(c1_type == CPU_WR) begin
				cmd(2'b01, 1, 0, 0);
				sd_ba       <= c1_ba;
				sd_addr     <= {2'b00, ~c1_l2, c1_col};
				sd_dqm      <= c1_dqm;
				sd_data_out <= c1_dat;
				sd_data_oe  <= 1;
			end
			13: if(c1_type == BURST) begin
				cmd(2'b01, 1, 0, 1);
				sd_ba   <= c1_ba;
				sd_addr <= {2'b00, 1'b1, c1_col[9:3], 2'b10, 1'b0};
			end
			else if(c1_type == CPU_RD && CPU_LINE16) begin
				// the line's other 8 bytes, from the same word on
				cmd(2'b01, 1, 0, 1);
				sd_ba   <= c1_ba;
				sd_addr <= {2'b00, 1'b1, c1_col[9:3], ~c1_col[2], c1_col[1:0]};
			end
			else if(c1_type == CPU_WR && c1_l2) begin
				cmd(2'b01, 1, 0, 0);
				sd_ba       <= c1_ba;
				sd_addr     <= {2'b00, 1'b1, c1_col[9:1], 1'b1};
				sd_dqm      <= 2'b00;
				sd_data_out <= c1_dat2;
				sd_data_oe  <= 1;
			end
		endcase
	end
end

// the access direction of the chip 0 slot
always @(posedge sysclk) if(sdram_state == 0) begin
	c0_write <= !chipRW;
	hostWE_q <= hostWE;
end

////////////////////////////////////////
// read data
////////////////////////////////////////
reg [15:0] sd_in_q;   // I/O block registers: the word of the edge in this state
always @(posedge sysclk) sd_in_q <= sd_data_in;

reg [15:0] rd1, rd2, rd3;         // chip 0's burst
reg [15:0] c1w1, c1w2, c1w3;      // chip 1's four words for the cache
reg [15:0] chip48_1, chip48_2, chip48_3;
assign chip48 = {chip48_1, chip48_2, chip48_3};

wire [15:0] fwd_m;
assign fwd_m[15:8] = (fwd_en && !fwd_dqm[1]) ? fwd_dat[15:8] : sd_in_q[15:8];
assign fwd_m[7:0]  = (fwd_en && !fwd_dqm[0]) ? fwd_dat[7:0]  : sd_in_q[7:0];
// the word at position k of the chipset's burst, with the write buffer's
// words in it
wire  [1:0] fwd_pos2 = fwd_pos + 2'd1;
function [15:0] fwd_word(input [1:0] k);
	fwd_word = (fwd_pos == k) ? fwd_m : (fwd_en && fwd_l2 && fwd_pos2 == k) ? fwd_dat2 : sd_in_q;
endfunction

always @(posedge sysclk) begin
	cache_fill <= 0;
	hostAck    <= 0;
	burstValid <= 0;
	burstData  <= sd_in_q;

	// chip 0: D0-D3 in sd_in_q during states 9-12
	if(init_done) begin
		case(sdram_state)
			10: rd1 <= (c0_type == CHIP) ? fwd_word(2'd1) : sd_in_q;
			11: rd2 <= (c0_type == CHIP) ? fwd_word(2'd2) : sd_in_q;
			12: rd3 <= (c0_type == CHIP) ? fwd_word(2'd3) : sd_in_q;
		endcase

		if(c0_type == CHIP) begin
			case(sdram_state)
				 9: chipRD   <= fwd_word(2'd0);
				11: begin
						chip48_1 <= rd1;
						if(a_rd2) chipRD2 <= rd1;
					end
				13: chip48_2 <= rd2;
				15: chip48_3 <= rd3;
			endcase
		end
		if(c0_type == HOST && sdram_state == 9) begin
			hostRD  <= sd_in_q;
			hostAck <= 1;
		end
		if(c0_type == CPU_RD) begin
			case(sdram_state)
				 9: begin cache_fill <= 1; cache_dat <= sd_in_q; end
				11: begin cache_fill <= 1; cache_dat <= rd1; end
				13: begin cache_fill <= 1; cache_dat <= rd2; end
				15: begin cache_fill <= 1; cache_dat <= rd3; end
			endcase
		end

		// chip 1: D0-D1 in sd_in_q during states 14-15, D2-D7 during 0-5
		// of the next window
		if(CPU_LINE16) begin
			// the line: a word each clock, as it arrives
			if(c1_type == CPU_RD && (sdram_state == 14 || sdram_state == 15) ||
			   c1_prev == CPU_RD && sdram_state <= 5) begin
				cache_fill <= 1;
				cache_dat  <= sd_in_q;
			end
		end
		else if(c1_type == CPU_RD) begin
			case(sdram_state)
				14: begin cache_fill <= 1; cache_dat <= sd_in_q; end
				15: c1w1 <= sd_in_q;
			endcase
		end
		if(c1_prev == CPU_RD && !CPU_LINE16) begin
			case(sdram_state)
				0: begin c1w2 <= sd_in_q; cache_fill <= 1; cache_dat <= c1w1; end
				1: c1w3 <= sd_in_q;
				2: begin cache_fill <= 1; cache_dat <= c1w2; end
				4: begin cache_fill <= 1; cache_dat <= c1w3; end
			endcase
		end
		if(c1_type == BURST && (sdram_state == 14 || sdram_state == 15)) burstValid <= 1;
		if(c1_prev == BURST && sdram_state <= 5) burstValid <= 1;
	end
end

endmodule
