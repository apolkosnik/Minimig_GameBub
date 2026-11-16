//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
//                                                                          //
// Copyright (c) 2009/2011 Tobias Gubener                                   //
// Subdesign fAMpIGA by TobiFlex                                            //
//                                                                          //
// This source file is free software: you can redistribute it and/or modify //
// it under the terms of the GNU General Public License as published        //
// by the Free Software Foundation, either version 3 of the License, or     //
// (at your option) any later version.                                      //
//                                                                          //
// This source file is distributed in the hope that it will be useful,      //
// but WITHOUT ANY WARRANTY; without even the implied warranty of           //
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            //
// GNU General Public License for more details.                             //
//                                                                          //
// You should have received a copy of the GNU General Public License        //
// along with this program.  If not, see <http://www.gnu.org/licenses/>.    //
//                                                                          //
//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
//
// Code re-work:
// - Shrink 16 to 12 cycles to work at quarter lower frequency with the same performance.
// - Support for 64MB SDRAM
//
// (C)2019 Alexey Melnikov
//
// Game Bub port:
// - The data bus is split into sd_data_in / sd_data_out / sd_data_oe
//   (the Game Bub framework owns the tri-state buffer).
// - A third, low priority "host" port gives the core's own logic (floppy
//   image server, ROM staging) word access to the SDRAM. It is served in
//   slots the chipset and CPU writes leave free and wins over CPU cache
//   fills after it has waited HOST_STARVE slots.
// - Two SDRAM chips on the one bus, each with its own chip select: the CPU
//   port's address bit 25 picks the chip (chip RAM and the host port use
//   chip 0); initialisation and refresh go to both.
//


module sdram_ctrl
(
	// system
	input             sysclk,
	input             c_7m,
	input             reset_n,
	input             cache_rst,
	input             cache_inhibit,
	input       [3:0] cpu_cache_ctrl,
	input             dcache_sw_en,
	// sdram
	output reg [12:0] sd_addr,
	output reg  [1:0] sd_ba,
	output reg  [1:0] sd_cs,     // active low, one per chip
	output reg        sd_we,
	output reg        sd_ras,
	output reg        sd_cas,
	output reg  [1:0] sd_dqm,
	input      [15:0] sd_data_in,
	output reg [15:0] sd_data_out,
	output reg        sd_data_oe,
	output reg        sd_clk,
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
	// host (lowest priority, one word per request)
	input      [24:1] hostAddr,
	input             hostReq,   // hold until hostAck
	input             hostWE,
	input       [1:0] hostDQM,   // byte masks, active high (1 = byte not written)
	input      [15:0] hostWR,
	output reg [15:0] hostRD,
	output reg        hostAck    // one clock; hostRD is valid with it on reads
);

assign sd_cke = 2'b11;

//// parameters ////
localparam [2:0]
	IDLE = 0,
	CHIP = 1,
	CPU_READCACHE = 2,
	CPU_WRITECACHE = 3,
	HOST = 4;

localparam HOST_STARVE = 4'd8;


////////////////////////////////////////
// reset
////////////////////////////////////////

reg reset;
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

wire ramsel = cpuCS & (~&cpustate | ~cpuU | ~cpuL);

// cpu cache
wire cache_rd_ack;
wire cache_wr_ack;
wire cache_req;
reg        a_wr2 = 0;
reg        a_rd2 = 0;
reg [15:0] datawr2;
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
	.sdr_dat_r        (sdata_reg),             // sdram read data
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

reg cache_fill;
always @ (posedge sysclk) begin
	cache_fill <= 0;

	if(init_done && slot_type == CPU_READCACHE) begin
		case(sdram_state)
		   7, 9, 11, 13: cache_fill <= 1;
		endcase
	end
end

// write buffer, enables CPU to continue while a write is in progress
reg        write_ena;
reg        write_req;
reg        write_ack;
reg  [1:0] write_dqm;
reg [25:1] writeAddr;
reg [15:0] writeDat;
reg        fwd_en = 1'b0;
reg  [1:0] fwd_pos;
reg [15:0] fwd_dat;
reg  [1:0] fwd_dqm;

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

//// chip line read ////
reg [15:0] chip48_1, chip48_2, chip48_3;

always @ (posedge sysclk) begin
	reg [15:0] sdata_chip;
	reg [15:0] m;

	sdata_chip <= sdata_reg;
	m = sdata_chip;
	if(fwd_en) begin
		if(!fwd_dqm[1]) m[15:8] = fwd_dat[15:8];
		if(!fwd_dqm[0]) m[7:0]  = fwd_dat[7:0];
	end
	hostAck <= 0;
	if(slot_type == HOST && sdram_state == 9) begin
		hostRD  <= sdata_chip;
		hostAck <= 1;
	end
	if(slot_type == CHIP) begin
		case(sdram_state)
			 9: chipRD   <= (fwd_en && fwd_pos==2'd0) ? m : sdata_chip;
			11: begin
					chip48_1 <= (fwd_en && fwd_pos==2'd1) ? m : sdata_chip;
					if(a_rd2) chipRD2 <= (fwd_en && fwd_pos==2'd1) ? m : sdata_chip;
				end
			13: chip48_2 <= (fwd_en && fwd_pos==2'd2) ? m : sdata_chip;
			15: chip48_3 <= (fwd_en && fwd_pos==2'd3) ? m : sdata_chip;
		endcase
	end
end

assign chip48 = {chip48_1, chip48_2, chip48_3};


////////////////////////////////////////
// SDRAM control
////////////////////////////////////////


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


//// sdram state ////
reg [3:0] sdram_state;
reg       old_7m;
always @ (posedge sysclk) begin
	sdram_state <= sdram_state + 1'd1;

	old_7m <= c_7m;
	if(~old_7m & c_7m) sdram_state <= 0;
end

wire [3:0] next_state     = (~old_7m & c_7m) ? 4'd0 : sdram_state + 1'd1;
wire       next_init      = reset & (init_done | (sdram_state == 15 && &initstate));
wire [3:0] next_initstate = !reset ? 4'd0 : (sdram_state == 15 && ~&initstate) ? initstate + 1'd1 : initstate;

//// sdram control ////

reg  [2:0] slot_type = IDLE;
reg [15:0] sdata_reg;
reg        chipWE;

reg [12:0] p_addr;
reg  [1:0] p_ba;
reg        p_ras = 1;
reg        p_cas = 1;
reg        p_we  = 1;
reg  [1:0] p_dqm = 3;
reg        p_oe  = 0;
reg [15:0] p_data;
reg        p_act = 0;

wire        chip_req = ~chipDMA | ~chipRW;
// host request: never ahead of the chipset or a CPU write, ahead of the
// cache once it has been passed over HOST_STARVE times
reg         host_busy = 0;  // the request is being served (slot taken)
reg   [3:0] host_wait = 0;
wire        host_go  = hostReq & ~host_busy & ~write_req & (~cache_req | (host_wait >= HOST_STARVE));
wire        act_chip = p_act & chip_req;
wire        act_cpu  = p_act & (write_req | cache_req | host_go);
(* keep *) wire        cpu_slot;
(* keep *) wire [14:0] row_chip;
assign      cpu_slot = p_act & ~chip_req;
assign      row_chip = act_chip ? chipAddr[24:10] : {p_ba, p_addr};
wire [14:0] row      = (cpu_slot & write_req) ? writeAddr[24:10] : (cpu_slot & host_go) ? hostAddr[24:10] : (cpu_slot & cache_req) ? cpuAddr[24:10] : row_chip;
wire        ras      = p_ras & ~act_chip & ~act_cpu;
// the chip of the row (held from the ACTIVE to the READ / WRITE, as the row
// address is), and commands for both chips (initialisation, refresh)
reg         p_chip1 = 0;
reg         p_all   = 1;
wire        chip1    = (cpu_slot & write_req) ? writeAddr[25] : (cpu_slot & host_go) ? 1'b0 :
                       (cpu_slot & cache_req) ? cpuAddr[25] : act_chip ? 1'b0 : p_chip1;
wire        cas      = p_cas | act_chip | act_cpu;

always @ (posedge sysclk) begin
	reg        cas_sd_cas;
	reg        cas_sd_we;
	reg  [1:0] cas_dqm;
	reg [15:0] datawr;
	reg  [9:0] casaddr;
	reg  [3:0] rcnt, rcnt_n;
	
	sd_clk <= sdram_state[0];

	{sd_ba, sd_addr} <= row;
	sd_cs   <= (p_all & ~act_chip & ~act_cpu) ? 2'b00 : chip1 ? 2'b01 : 2'b10;
	sd_ras  <= ras;
	sd_cas  <= cas;
	sd_we   <= p_we;
	sd_dqm  <= p_dqm;
	sd_data_out <= p_data;
	sd_data_oe  <= p_oe;

	if(~sdram_state[0]) chipWE <= 0;

	if(sdram_state == 4) begin
		chipWE2 <= a_wr2;
		snoop2  <= a_wr2;
	end
	if(sdram_state == 6) chipWE2 <= 0;
	if(sdram_state == 8) snoop2  <= 0;

	if(sdram_state[0]) sdata_reg <= sd_data_in;

	if(hostAck) host_busy <= 0;

	rcnt_n = rcnt;
	if(!init_done) begin
		slot_type             <= IDLE;
		casaddr               <= 0;
		rcnt_n                 = 0;
		a_wr2                 <= 0;
		a_rd2                 <= 0;
		host_busy             <= 0;
		host_wait             <= 0;
	end else begin

		case(sdram_state)

			// RAS
			0 : begin
				cas_sd_cas      <= 1;
				cas_sd_we       <= 1;
				cas_dqm         <= 0;
				slot_type       <= IDLE;
				fwd_en          <= 0;
				a_wr2           <= 0;
				a_rd2           <= 0;

				if(~&rcnt) rcnt_n = rcnt + 1'd1;
				// counts every slot the pending host request does not get
				// (the host branch below clears it when it is served)
				if(hostReq & ~host_busy & ~&host_wait) host_wait <= host_wait + 1'd1;

				// we give the chipset first priority
				// (this includes anything on the "motherboard" - chip RAM, slow RAM and Kickstart, turbo modes notwithstanding)
				if(chip_req) begin
					slot_type    <= CHIP;
					casaddr[8:0] <= chipAddr[9:1];
					cas_dqm      <= {chipU,chipL};
					cas_sd_cas   <= 0;
					cas_sd_we    <= chipRW;
					datawr       <= chipWR;
					chipWE       <= !chipRW;
					a_wr2        <= chip32 & !chipRW;
					a_rd2        <= chip32 &  chipRW;
					datawr2      <= chipWR2;
					if(chipRW & write_req & ~writeAddr[25] & (writeAddr[24:3] == chipAddr[24:3])) begin
						fwd_en  <= 1'b1;
						fwd_pos <= writeAddr[2:1] - chipAddr[2:1];
						fwd_dat <= writeDat;
						fwd_dqm <= write_dqm;
					end
				end
				else if(write_req) begin
					slot_type    <= CPU_WRITECACHE;
					casaddr[8:0] <= writeAddr[9:1];
					cas_dqm      <= write_dqm;
					cas_sd_we    <= 0;
					cas_sd_cas   <= 0;
					write_ack    <= 1; // let the write buffer know we're about to write
					datawr       <= writeDat;
				end
				// request from the host port
				else if(host_go) begin
					slot_type    <= HOST;
					casaddr[8:0] <= hostAddr[9:1];
					cas_dqm      <= hostDQM;
					cas_sd_cas   <= 0;
					cas_sd_we    <= ~hostWE;
					datawr       <= hostWR;
					host_busy    <= 1;
					host_wait    <= 0;
				end
				// request from read cache
				else if(cache_req) begin
					slot_type    <= CPU_READCACHE;
					casaddr[8:0] <= cpuAddr[9:1];
					cas_sd_cas   <= 0;
				end
				else if(&rcnt) begin
					// REFRESH
					rcnt_n        = 0;
				end
			end

			// CAS
			2 : write_ack       <= 0; // indicate to write that it's safe to accept the next write
		endcase
	end
	rcnt <= rcnt_n;

	{p_ba, p_addr} <= row;
	p_chip1 <= chip1;
	// an ACTIVE takes the slot of a refresh: its chip, not both, for the
	// rest of the SDRAM clock
	if(act_chip | act_cpu) p_all <= 0;
	p_ras <= ras;
	p_cas <= cas;
	p_act <= 0;
	if(~next_state[0]) begin
		p_ras <= 1;
		p_cas <= 1;
		p_we  <= 1;
		p_oe  <= 0;
		p_all <= 0;   // held for the SDRAM clock, as the command is
	end

	if(!next_init) begin
		p_dqm <= 3;
		p_ba  <= 0;
		p_all <= 1;
		if(next_state == 0) begin
			case(next_initstate)
				4 : begin // PRECHARGE
					p_addr[10]   <= 1; // all banks
					p_ras        <= 0;
					p_cas        <= 1;
					p_we         <= 0;
				end
				8,10 : begin // AUTOREFRESH
					p_ras        <= 0;
					p_cas        <= 0;
					p_we         <= 1;
				end
				13 : begin // LOAD MODE REGISTER
					p_ras        <= 0;
					p_cas        <= 0;
					p_we         <= 0;
					p_addr       <= 13'b0001000100010; // CL=2, BURST=4
				end
			endcase
		end
	end else begin
		case(next_state)

			// RAS
			0 : begin
				p_dqm           <= 3;
				p_act           <= 1;
				if(&rcnt_n) begin
					// REFRESH (both chips)
					p_ras        <= 0;
					p_cas        <= 0;
					p_all        <= 1;
				end
			end

			// CAS
			2 : begin
				p_addr          <= {~a_wr2, casaddr}; // AUTO PRECHARGE
				p_cas           <= cas_sd_cas;
				p_dqm           <= 0;
				if(!cas_sd_we) begin
					p_oe         <= 1;
					p_data       <= datawr;
					p_addr[12:11]<= cas_dqm;
					p_dqm        <= cas_dqm;
					p_we         <= 0;
				end
			end

			4 : if(a_wr2) begin
				p_addr          <= {2'b00, 1'b1, casaddr[9:1], 1'b1};
				p_dqm           <= 0;
				p_oe            <= 1;
				p_data          <= datawr2;
				p_cas           <= 0;
				p_we            <= 0;
			end
		endcase
	end
end

endmodule
