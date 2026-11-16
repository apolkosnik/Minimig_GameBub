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
//   chip 0   ACTIVE 1, READ 4                 read 7-10
//            or WRITE 6 (and 7, chip32)       write 6 (7)
//   chip 1   ACTIVE 5, READ 9 (and 13)        read 12-15 (16-19 = 0-3 of
//            or WRITE 12                      the next window), write 12
//
// so the command bus never has two commands in one cycle, and between data
// driven by different devices (chip 0, chip 1, the FPGA) there is always at
// least one idle cycle (sim/tb/tb_top.sv checks both on every edge).
// Every access closes its row (auto precharge); the bank is idle again
// before the next window's ACTIVE of the same chip.
//
// Chip 0 serves the chipset, the CPU's chip-0 RAM (cpuAddr[25] = 0) and the
// host port, deciding at state 0 exactly as sdram_ctrl did, and hands the
// chipset, host and cache their data at the same states as sdram_ctrl
// (chipRD at 9, chip48 at 11/13/15, cache words at 9/11/13/15).
// Chip 1 decides at state 4 (two clk_114 cycles after a clk_sys edge, as
// state 0 is) and serves the CPU's chip-1 RAM (cpuAddr[25] = 1) and the
// burst port: eight words (two READs of four, one row) per window, for the
// RTG scan-out. Each chip refreshes in its own ACTIVE slot.
//
// SPDX-License-Identifier: GPL-3.0-or-later

module gb_sdram_ctrl
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
cpu_cache_new cpu_cache
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
	.cpu_long         (1'b0),
	.cpu_dat_w_lo     (16'd0),
	.cpu_dat_hi       (),
	.cpu_ack_l        ()
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

always @ (posedge sysclk) begin
	reg  [1:0] write_state;

	if(~reset_n) begin
		write_req   <= 0;
		write_ena   <= 0;
		write_state <= 0;
	end else begin
		case(write_state)
			default:
				if(~write_ena && ramsel && cpustate == 3) begin
					writeAddr <= cpuAddr;
					writeDat  <= cpuWR;
					write_dqm <= {cpuU, cpuL};
					if(cache_wr_ack) begin
						write_req   <= 1;
						write_ena   <= 1;
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

		if(~ramsel) write_ena <= 0;
	end
end

assign ramready = cache_rd_ack || write_ena;

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
wire        c0_rd    = cache_req & ~cpuAddr[25];
reg         host_busy = 0;  // the request is being served (slot taken)
reg   [3:0] host_wait = 0;
wire        host_go  = hostReq & ~host_busy & ~c0_wr & (~c0_rd | (host_wait >= HOST_STARVE));
wire  [2:0] c0_next  = chip_req       ? CHIP    :
                       (owed0 >= 3)   ? REFRESH :
                       c0_wr          ? CPU_WR  :
                       host_go        ? HOST    :
                       c0_rd          ? CPU_RD  :
                       (owed0 != 0)   ? REFRESH : IDLE;
wire [24:1] c0_addr  = (c0_next == CHIP) ? chipAddr : (c0_next == CPU_WR) ? writeAddr[24:1] :
                       (c0_next == HOST) ? hostAddr : cpuAddr[24:1];

// chip 1, decided at state 4
wire        c1_wr    = write_req & writeAddr[25];
wire        c1_rd    = cache_req & cpuAddr[25];
wire  [2:0] c1_next  = (owed1 >= 3)              ? REFRESH :
                       (burstReq & burstUrgent)  ? BURST   :
                       c1_wr                     ? CPU_WR  :
                       c1_rd                     ? CPU_RD  :
                       burstReq                  ? BURST   :
                       (owed1 != 0)              ? REFRESH : IDLE;
wire [24:1] c1_addr  = (c1_next == CPU_WR) ? writeAddr[24:1] : (c1_next == BURST) ? {burstAddr, 3'b000} :
                       cpuAddr[24:1];

reg   [2:0] c0_type = IDLE, c1_type = IDLE, c1_prev = IDLE;
reg   [9:0] c0_col, c1_col;
reg   [1:0] c0_ba, c1_ba;
reg   [1:0] c0_dqm, c1_dqm;
reg  [15:0] c0_dat, c1_dat;

// write data forwarding to chipset reads (a CPU write to chip 0 still in
// the write buffer), as sdram_ctrl
reg         fwd_en = 1'b0;
reg   [1:0] fwd_pos;
reg  [15:0] fwd_dat;
reg   [1:0] fwd_dqm;

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
		// initialisation, both chips: at state 1 of windows 4 (PRECHARGE
		// all), 8 and 10 (AUTO REFRESH) and 13 (LOAD MODE)
		if(reset && sdram_state == 0) begin
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
			// chip 0: decide, ACTIVE (or REFRESH) at state 1
			0: begin
				c0_type <= c0_next;
				fwd_en  <= 0;
				a_wr2   <= 0;
				a_rd2   <= 0;
				c0_col  <= {1'b0, c0_addr[9:1]};
				c0_ba   <= c0_addr[24:23];
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
							fwd_en  <= 1'b1;
							fwd_pos <= writeAddr[2:1] - chipAddr[2:1];
							fwd_dat <= writeDat;
							fwd_dqm <= write_dqm;
						end
					end
					CPU_WR: begin
						c0_dqm    <= write_dqm;
						c0_dat    <= writeDat;
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

				sd_ba   <= c0_addr[24:23];
				sd_addr <= c0_addr[22:10];
				if(c0_next == REFRESH)   cmd(2'b10, 0, 0, 1);
				else if(c0_next != IDLE) cmd(2'b10, 0, 1, 1);
			end

			// chip 0 READ at state 4 (auto precharge)
			3: if(c0_type == CPU_RD || c0_type == HOST && !hostWE_q || c0_type == CHIP && !c0_write) begin
				cmd(2'b10, 1, 0, 1);
				sd_ba   <= c0_ba;
				sd_addr <= {2'b00, 1'b1, c0_col};
			end

			// chip 1: decide, ACTIVE (or REFRESH) at state 5
			4: begin
				c1_type <= c1_next;
				c1_col  <= {1'b0, c1_addr[9:1]};
				c1_ba   <= c1_addr[24:23];
				c1_dqm  <= write_dqm;
				c1_dat  <= writeDat;
				case(c1_next)
					CPU_WR:  write_ack <= 1;
					BURST:   burstAck  <= 1;
					REFRESH: if(owed1 != 0) owed1 <= owed1 - 1'd1;
				endcase
				sd_ba   <= c1_addr[24:23];
				sd_addr <= c1_addr[22:10];
				if(c1_next == REFRESH)   cmd(2'b01, 0, 0, 1);
				else if(c1_next != IDLE) cmd(2'b01, 0, 1, 1);
			end

			// chip 0 WRITE at state 6 (auto precharge unless a second word
			// follows at 7)
			5: if(c0_type == CPU_WR || c0_type == HOST && hostWE_q || c0_type == CHIP && c0_write) begin
				cmd(2'b10, 1, 0, 0);
				sd_ba       <= c0_ba;
				sd_addr     <= {2'b00, ~a_wr2, c0_col};
				sd_dqm      <= c0_dqm;
				sd_data_out <= c0_dat;
				sd_data_oe  <= 1;
			end
			6: if(a_wr2) begin
				cmd(2'b10, 1, 0, 0);
				sd_ba       <= c0_ba;
				sd_addr     <= {2'b00, 1'b1, c0_col[9:1], 1'b1};
				sd_dqm      <= 2'b00;
				sd_data_out <= datawr2;
				sd_data_oe  <= 1;
			end

			// chip 1 READ at state 9 (auto precharge unless the second READ
			// of a burst follows at 13)
			8: if(c1_type == CPU_RD || c1_type == BURST) begin
				cmd(2'b01, 1, 0, 1);
				sd_ba   <= c1_ba;
				sd_addr <= {2'b00, c1_type != BURST, c1_col};   // a burst's column is a multiple of 8
			end

			// chip 1 WRITE at state 12
			11: if(c1_type == CPU_WR) begin
				cmd(2'b01, 1, 0, 0);
				sd_ba       <= c1_ba;
				sd_addr     <= {2'b00, 1'b1, c1_col};
				sd_dqm      <= c1_dqm;
				sd_data_out <= c1_dat;
				sd_data_oe  <= 1;
			end
			12: if(c1_type == BURST) begin
				cmd(2'b01, 1, 0, 1);
				sd_ba   <= c1_ba;
				sd_addr <= {2'b00, 1'b1, c1_col[9:3], 2'b10, 1'b0};
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

reg [15:0] rd0, rd1, rd2, rd3;    // chip 0's burst
reg [15:0] c1w1, c1w2, c1w3;      // chip 1's four words for the cache
reg [15:0] chip48_1, chip48_2, chip48_3;
assign chip48 = {chip48_1, chip48_2, chip48_3};

wire [15:0] fwd_m;
assign fwd_m[15:8] = (fwd_en && !fwd_dqm[1]) ? fwd_dat[15:8] : sd_in_q[15:8];
assign fwd_m[7:0]  = (fwd_en && !fwd_dqm[0]) ? fwd_dat[7:0]  : sd_in_q[7:0];

always @(posedge sysclk) begin
	cache_fill <= 0;
	hostAck    <= 0;
	burstValid <= 0;
	burstData  <= sd_in_q;

	// chip 0: D0-D3 in sd_in_q during states 8-11
	if(init_done) begin
		case(sdram_state)
			8:  rd0 <= (c0_type == CHIP && fwd_pos == 2'd0) ? fwd_m : sd_in_q;
			9:  rd1 <= (c0_type == CHIP && fwd_pos == 2'd1) ? fwd_m : sd_in_q;
			10: rd2 <= (c0_type == CHIP && fwd_pos == 2'd2) ? fwd_m : sd_in_q;
			11: rd3 <= (c0_type == CHIP && fwd_pos == 2'd3) ? fwd_m : sd_in_q;
		endcase

		if(c0_type == CHIP) begin
			case(sdram_state)
				 9: chipRD   <= rd0;
				11: begin
						chip48_1 <= rd1;
						if(a_rd2) chipRD2 <= rd1;
					end
				13: chip48_2 <= rd2;
				15: chip48_3 <= rd3;
			endcase
		end
		if(c0_type == HOST && sdram_state == 9) begin
			hostRD  <= rd0;
			hostAck <= 1;
		end
		if(c0_type == CPU_RD) begin
			case(sdram_state)
				 8: begin cache_fill <= 1; cache_dat <= sd_in_q; end
				10: begin cache_fill <= 1; cache_dat <= rd1; end
				12: begin cache_fill <= 1; cache_dat <= rd2; end
				14: begin cache_fill <= 1; cache_dat <= rd3; end
			endcase
		end

		// chip 1: D0-D3 in sd_in_q during states 13-15 and 0, D4-D7 during
		// 1-4 of the next window
		if(c1_type == CPU_RD) begin
			case(sdram_state)
				13: begin cache_fill <= 1; cache_dat <= sd_in_q; end
				14: c1w1 <= sd_in_q;
				15: begin c1w2 <= sd_in_q; cache_fill <= 1; cache_dat <= c1w1; end
			endcase
		end
		if(c1_prev == CPU_RD) begin
			case(sdram_state)
				0: c1w3 <= sd_in_q;
				1: begin cache_fill <= 1; cache_dat <= c1w2; end
				3: begin cache_fill <= 1; cache_dat <= c1w3; end
			endcase
		end
		if(c1_type == BURST && (sdram_state == 13 || sdram_state == 14 || sdram_state == 15)) burstValid <= 1;
		if(c1_prev == BURST && sdram_state <= 4) burstValid <= 1;
	end
end

endmodule
