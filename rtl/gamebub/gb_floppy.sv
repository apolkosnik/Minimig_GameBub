// Game Bub Minimig: ADF floppy server.
//
// On MiSTer the ARM side (Main_MiSTer support/minimig/minimig_fdd.cpp) reads
// ADF images from the SD card, encodes the requested track to MFM and feeds
// Paula's floppy FIFO over the IO_FPGA channel; on writes it decodes the MFM
// stream back to sectors. This module is a hardware implementation of the
// same functions, working on ADF images held in SDRAM:
//
//   minimig_fdd.cpp          this module
//   ---------------          -----------
//   main loop poll           POLL_*      (status, sync, length words)
//   HandleFDD()              DISPATCH
//   ReadTrack()/SendSector() RT_* / SW_* (sector words, gap)
//   WriteTrack()/FindSync()  WT_* / FS_*
//   GetHeader()              GH_*
//   GetData()                GD_*
//   UpdateDriveStatus()      ST_*
//
// The word sequences, clock bit insertion (ADDCLOCKBITS), checksums, gap
// size, sync word workarounds and error checks follow minimig_fdd.cpp so
// that the Amiga side sees the same data as on MiSTer.
//
// Image layout in SDRAM: slot s, sector lba is at word address
//   SLOT_BASE + s * SLOT_WORDS + lba * 256
// and holds the sector bytes big endian (byte 0 in bits 15:8).
//
// SPDX-License-Identifier: GPL-3.0-or-later

module gb_floppy
#(
	parameter [24:1] SLOT_BASE  = 24'h800000,  // byte 0x1000000
	parameter [24:1] SLOT_WORDS = 24'h080000,  // 1 MB per slot
	parameter        POLL_GAP   = 64           // clocks between polls
)
(
	input             clk,
	input             reset,

	input             enable,      // may start a new poll
	output            idle,        // between polls (the bus is free)
	output            committing,  // writing a decoded sector into the image

	// drives 0..3: image state (from gb_host)
	input       [3:0] drv_present,
	input       [3:0] drv_writable,
	input      [11:0] drv_slot,    // 3 bits per drive
	input      [31:0] drv_tracks,  // 8 bits per drive (ADF size / 5632)

	// IO_FPGA master (gb_io_master)
	output reg  [1:0] io_sel,
	output reg        io_req,
	output reg [15:0] io_wdata,
	input             io_ack,
	input      [15:0] io_rdata,

	// SDRAM client (gb_sdram_bridge)
	output reg        mem_req,
	output reg        mem_we,
	output reg [24:1] mem_addr,
	output reg [15:0] mem_wdata,
	input             mem_ack,
	input      [15:0] mem_rdata,

	// debug / status
	output reg  [7:0] last_error,   // minimig_fdd.cpp "Error" codes
	output reg [15:0] sectors_read,
	output reg [15:0] sectors_written
);

localparam [15:0] SYNC_WORD = 16'h4489;
localparam [1:0]  SEL_FPGA  = 2'b10;

// ---------------------------------------------------------------------------
// MFM helpers

// ADDCLOCKBITS() of minimig_fdd.cpp
function automatic [15:0] acb(input [15:0] value, input [15:0] previous);
	reg [15:0] v, inv;
	begin
		v   = value & 16'h5555;
		inv = (v << 1) | (v >> 1) | (previous << 15);
		acb = v | (inv ^ 16'hAAAA);
	end
endfunction

function automatic [7:0] cks(input [7:0] x);  // x ^ (x >> 1)
	cks = x ^ (x >> 1);
endfunction

// ---------------------------------------------------------------------------
// buffers

reg [15:0] sbuf  [0:255];   // sector to send (big endian words)
reg [15:0] obuf  [0:255];   // decoded odd bits  (write path)
reg [15:0] ebuf  [0:255];   // decoded even bits (write path)
reg  [7:0] buf_ra;
reg [15:0] sbuf_q, obuf_q, ebuf_q;
always @(posedge clk) begin
	sbuf_q <= sbuf[buf_ra];
	obuf_q <= obuf[buf_ra];
	ebuf_q <= ebuf[buf_ra];
end

// ---------------------------------------------------------------------------
// per drive state (adfTYPE)

reg  [7:0] track_prev [0:3];
reg  [3:0] sector_off [0:3];
reg [15:0] last_bit   [0:3];

// ---------------------------------------------------------------------------
// state machine

localparam [6:0]
	POLL_BEGIN = 7'd0,  POLL_1 = 7'd1,  POLL_2 = 7'd2,  POLL_3 = 7'd3,  DISPATCH = 7'd4,
	ST_1 = 7'd5, ST_2 = 7'd6, ST_3 = 7'd7, ST_4 = 7'd8, GAP = 7'd9,
	XFER = 7'd10, TEND = 7'd11, TEND_W = 7'd12,
	RT_START = 7'd13, RT_P1 = 7'd14, RT_P2 = 7'd15, RT_P3 = 7'd16,
	RT_LOAD = 7'd17, RT_LOAD_W = 7'd18,
	RT_T0 = 7'd19, RT_T1 = 7'd20, RT_T2 = 7'd21, RT_T3 = 7'd22,
	SW_ADDR = 7'd23, SW_DATA = 7'd24, SW_NEXT = 7'd25, RT_AFTER = 7'd26, RT_NEXT = 7'd27,
	WT_START = 7'd30,
	FS_0 = 7'd31, FS_1 = 7'd32, FS_2 = 7'd33, FS_3 = 7'd34, FS_4 = 7'd35,
	GH_0 = 7'd40, GH_1 = 7'd41, GH_2 = 7'd42, GH_3 = 7'd43, GH_4 = 7'd44, GH_5 = 7'd45, GH_6 = 7'd46, GH_7 = 7'd47, GH_8 = 7'd48,
	GD_0 = 7'd50, GD_1 = 7'd51, GD_2 = 7'd52, GD_3 = 7'd53, GD_4 = 7'd54, GD_5 = 7'd55, GD_6 = 7'd56,
	WT_COMMIT = 7'd60, WT_COMMIT_A = 7'd61, WT_COMMIT_W = 7'd62, WT_COMMIT_D = 7'd63,
	WT_NEXT = 7'd64;

reg  [6:0] state, ret, tend_ret;
reg [15:0] xr;               // last word read from Paula
reg [15:0] st;               // status word of the poll
reg  [1:0] drv;              // drive being served
reg  [7:0] cur_t;            // drive->track
reg  [3:0] sector;
reg  [7:0] trk2;             // track reported inside the loop
reg [15:0] st2;
reg [15:0] dsksync;
reg [13:0] cnt;
reg  [9:0] w;                // word index inside a sector / gap
reg        in_gap;
reg [15:0] lastbit;          // working copy of drive->lastBit
reg  [7:0] dc0, dc1, dc2, dc3;  // data checksum (read path)
reg  [7:0] k0, k1, k2, k3;      // checksum accumulators (write path)
reg  [7:0] h1, h2, h3, h4;      // decoded header bytes / checksum bytes
reg  [7:0] wt_track, wt_sector;
reg  [7:0] gap_cnt;
reg  [8:0] li;                  // load / commit index

wire [7:0] c1 = st[15:8];
wire [7:0] c2 = st[7:0];

wire [7:0]  tracks_d   = drv_tracks[drv*8 +: 8];
wire [2:0]  slot_d     = drv_slot[drv*3 +: 3];
wire [15:0] max_lba    = tracks_d * 16'd11;
wire [15:0] cur_lba    = cur_t * 16'd11 + sector;
wire [15:0] wt_lba     = cur_t * 16'd11 + wt_sector;
wire [24:1] slot_addr  = SLOT_BASE + SLOT_WORDS * slot_d;

// header bytes of the sector being sent
wire [7:0] s8      = {4'd0, sector};
wire [7:0] s_gap   = 8'd11 - s8;
wire [7:0] hc1     = (cur_t >> 1) ^ cur_t;
wire [7:0] hc2     = (s8 >> 1) ^ s8;
wire [7:0] hc3     = (s_gap >> 1) ^ s_gap;

// word w of SendSector()
reg [15:0] sw_val;
reg        sw_raw;
always @* begin
	sw_raw = 1'b0;
	sw_val = 16'h0000;
	if (in_gap) sw_val = 16'h0000;
	else if (w == 10'd2 || w == 10'd3) begin sw_raw = 1'b1; sw_val = dsksync; end
	else if (w == 10'd4)  sw_val = {8'h55, cur_t >> 1};
	else if (w == 10'd5)  sw_val = {s8 >> 1, s_gap >> 1};
	else if (w == 10'd6)  sw_val = {8'h55, cur_t};
	else if (w == 10'd7)  sw_val = {s8, s_gap};
	else if (w == 10'd26) sw_val = {8'h00, hc1};          // checksum[0] = 0x55 ^ 0x55
	else if (w == 10'd27) sw_val = {hc2, hc3};
	else if (w == 10'd30) sw_val = {dc0, dc1};
	else if (w == 10'd31) sw_val = {dc2, dc3};
	else if (w >= 10'd32 && w < 10'd288) sw_val = {sbuf_q[15:8] >> 1, sbuf_q[7:0] >> 1};
	else if (w >= 10'd288) sw_val = sbuf_q;
end
wire [15:0] sw_word = sw_raw ? sw_val : acb(sw_val, lastbit);
wire  [9:0] sw_last = in_gap ? 10'd349 : 10'd543;   // GAP_SIZE/2 - 1, SECTOR_SIZE/2 - 1
wire  [7:0] sw_bufidx = (w >= 10'd288) ? w - 10'd288 : w - 10'd32;

assign idle = (state == POLL_BEGIN);
assign committing = (state == WT_COMMIT) || (state == WT_COMMIT_A) ||
                    (state == WT_COMMIT_D) || (state == WT_COMMIT_W);

integer i;
initial begin
	for (i = 0; i < 4; i = i + 1) begin
		track_prev[i] = 8'hFF;
		sector_off[i] = 4'd0;
		last_bit[i]   = 16'hAAAA;
	end
end

// start a transfer of word d, continue at r
`define GB_XFER(d, r) begin io_wdata <= (d); io_req <= 1'b1; ret <= (r); state <= XFER; end
// end the transaction (DisableFpga), continue at r
`define GB_TEND(r)    begin io_sel <= 2'b00; tend_ret <= (r); state <= TEND; end

always @(posedge clk) begin
	if (reset) begin
		state           <= POLL_BEGIN;
		io_sel          <= 2'b00;
		io_req          <= 1'b0;
		mem_req         <= 1'b0;
		last_error      <= 8'd0;
		sectors_read    <= 16'd0;
		sectors_written <= 16'd0;
		gap_cnt         <= 8'd0;
		for (i = 0; i < 4; i = i + 1) begin
			track_prev[i] <= 8'hFF;
			sector_off[i] <= 4'd0;
			last_bit[i]   <= 16'hAAAA;
		end
	end
	else case (state)

	// ---------------------------------------------------------------- poll
	POLL_BEGIN:
		if (enable && gap_cnt == 8'd0) begin
			io_sel <= SEL_FPGA;
			`GB_XFER(16'h0000, POLL_1)
		end
		else if (gap_cnt != 8'd0) gap_cnt <= gap_cnt - 8'd1;

	POLL_1: begin st <= xr; `GB_XFER(16'h0000, POLL_2) end   // status, track
	POLL_2: `GB_XFER(16'h0000, POLL_3)                        // disk sync
	POLL_3: `GB_TEND(DISPATCH)                                // mfm words

	// HandleFDD()
	DISPATCH: begin
		drv <= c1[7:6];
		if (c1[3] & c1[2])  state <= ST_1;      // floppy_zero_active
		else if (c1[0])     state <= RT_START;  // CMD_RDTRK
		else if (c1[1])     state <= WT_START;  // CMD_WRTRK
		else                state <= ST_1;
	end

	// ------------------------------------------------- UpdateDriveStatus()
	ST_1: begin io_sel <= SEL_FPGA; `GB_XFER({4'h1, 4'h0, drv_writable, drv_present}, ST_2) end
	ST_2: `GB_TEND(ST_3)
	ST_3: begin io_sel <= SEL_FPGA; `GB_XFER(16'h2000, ST_4) end
	ST_4: `GB_TEND(GAP)
	GAP:  begin gap_cnt <= POLL_GAP[7:0]; state <= POLL_BEGIN; end

	// ------------------------------------------------------- word transfer
	XFER:
		if (io_ack) begin
			io_req <= 1'b0;
			xr     <= io_rdata;
			state  <= ret;
		end

	TEND:   state <= TEND_W;          // chip select low for a clock before going on
	TEND_W: state <= tend_ret;

	// --------------------------------------------------------- ReadTrack()
	RT_START: begin
		if (!drv_present[drv] || tracks_d == 8'd0) state <= ST_1;   // FileSeekLBA() fails
		else begin
			cur_t <= (c2 >= tracks_d) ? tracks_d - 8'd1 : c2;
			state <= RT_P1;
		end
	end

	RT_P1: begin
		if (cur_t != track_prev[drv]) begin
			track_prev[drv] <= cur_t;
			last_bit[drv]   <= 16'hAAAA;
			lastbit         <= 16'hAAAA;
			sector          <= 4'd0;
			sector_off[drv] <= 4'd0;
		end
		else begin
			lastbit <= last_bit[drv];
			sector  <= sector_off[drv];
		end
		io_sel <= SEL_FPGA;
		`GB_XFER(16'h0000, RT_P2)
	end
	RT_P2: `GB_XFER(16'h0000, RT_P3)
	RT_P3: `GB_XFER(16'h0000, RT_LOAD)   // the TEND follows in RT_LOAD

	// FileReadSec(): the sector into sbuf, data checksum on the way
	RT_LOAD: begin
		io_sel  <= 2'b00;
		li      <= 9'd0;
		dc0 <= 8'd0; dc1 <= 8'd0; dc2 <= 8'd0; dc3 <= 8'd0;
		state   <= RT_LOAD_W;
	end

	RT_LOAD_W:
		if (li[8]) begin
			io_sel <= SEL_FPGA;
			`GB_XFER(16'h0000, RT_T1)
		end
		else if (!mem_req) begin
			mem_req  <= 1'b1;
			mem_we   <= 1'b0;
			mem_addr <= slot_addr + {cur_lba, 8'd0} + li[7:0];
		end
		else if (mem_ack) begin
			mem_req      <= 1'b0;
			sbuf[li[7:0]] <= mem_rdata;
			if (!li[0]) begin
				dc0 <= dc0 ^ cks(mem_rdata[15:8]);
				dc1 <= dc1 ^ cks(mem_rdata[7:0]);
			end
			else begin
				dc2 <= dc2 ^ cks(mem_rdata[15:8]);
				dc3 <= dc3 ^ cks(mem_rdata[7:0]);
			end
			li <= li + 9'd1;
		end

	RT_T1: begin
		st2  <= xr;
		trk2 <= (xr[7:0] >= tracks_d) ? tracks_d - 8'd1 : xr[7:0];
		`GB_XFER(16'h0000, RT_T2)
	end
	RT_T2: begin
		// workaround for Copy Lock in Wiz'n'Liz and North&South
		dsksync <= (xr == 16'h0000 || xr == 16'h8914 || xr == 16'hA144) ? SYNC_WORD : xr;
		`GB_XFER(16'h0000, RT_T3)
	end
	RT_T3: begin
		if (trk2 == cur_t && st2[8]) begin   // CMD_RDTRK
			w      <= 10'd0;
			in_gap <= 1'b0;
			state  <= SW_ADDR;
		end
		else `GB_TEND(RT_AFTER)
	end

	// SendSector() / SendGap()
	SW_ADDR: begin buf_ra <= sw_bufidx; state <= SW_DATA; end
	SW_DATA: state <= SW_NEXT;   // sbuf_q valid in SW_NEXT
	SW_NEXT: begin
		lastbit <= sw_word;
		`GB_XFER(sw_word, (w == sw_last) ? RT_NEXT : SW_ADDR)
		if (w != sw_last) w <= w + 10'd1;
	end
	RT_NEXT: begin
		if (!in_gap && sector == 4'd10) begin
			in_gap <= 1'b1;
			w      <= 10'd0;
			state  <= SW_ADDR;
		end
		else begin
			sectors_read <= sectors_read + 16'd1;
			`GB_TEND(RT_AFTER)
		end
	end

	RT_AFTER: begin
		last_bit[drv] <= lastbit;
		if (trk2 != cur_t || !st2[8]) state <= ST_1;
		else begin
			sector          <= (sector == 4'd10) ? 4'd0 : sector + 4'd1;
			sector_off[drv] <= (sector == 4'd10) ? 4'd0 : sector + 4'd1;
			state           <= RT_LOAD;
		end
	end

	// -------------------------------------------------------- WriteTrack()
	WT_START: begin
		cur_t           <= c2;
		track_prev[drv] <= 8'hFF;   // force the next read from the track start
		state           <= FS_0;
	end

	// FindSync()
	FS_0: begin io_sel <= SEL_FPGA; `GB_XFER(16'h0000, FS_1) end
	FS_1:
		if (!xr[9] || xr[7:0] != cur_t) `GB_TEND(ST_1)           // !CMD_WRTRK or other track
		else `GB_XFER(16'h0000, FS_2)
	FS_2: `GB_XFER(16'h0000, FS_3)
	FS_3: begin
		if ((xr & 16'hBFFF) == 16'h0000) `GB_TEND(ST_1)
		else if (xr[13:0] == 14'd0) `GB_TEND(FS_0)
		else begin
			cnt <= xr[13:0];
			`GB_XFER(16'h0000, FS_4)
		end
	end
	FS_4: begin
		if (xr == SYNC_WORD) `GB_TEND(GH_0)
		else if (cnt == 14'd1) `GB_TEND(FS_0)
		else begin
			cnt <= cnt - 14'd1;
			`GB_XFER(16'h0000, FS_4)
		end
	end

	// GetHeader()
	GH_0: begin io_sel <= SEL_FPGA; `GB_XFER(16'h0000, GH_1) end
	GH_1:
		if (!xr[9]) `GB_TEND(WT_NEXT)                            // GetHeader() returns 0
		else `GB_XFER(16'h0000, GH_2)
	GH_2: `GB_XFER(16'h0000, GH_3)
	GH_3: begin
		if (xr[13:8] != 6'd0 || xr[7:0] > 8'd24) `GB_XFER(16'h0000, GH_4)
		else if (!xr[15]) begin last_error <= 8'd20; `GB_TEND(WT_NEXT) end
		else `GB_TEND(GH_0)
	end
	GH_4: begin
		if (xr != SYNC_WORD) begin last_error <= 8'd21; `GB_TEND(WT_NEXT) end
		else begin cnt <= 14'd0; `GB_XFER(16'h0000, GH_5) end
	end
	// four header words: odd, odd, even, even
	GH_5: begin
		case (cnt[1:0])
			2'd0: begin k0 <= xr[15:8]; k1 <= xr[7:0]; h1 <= {xr[14],1'b0,xr[12],1'b0,xr[10],1'b0,xr[8],1'b0}; h2 <= {xr[6],1'b0,xr[4],1'b0,xr[2],1'b0,xr[0],1'b0}; end
			2'd1: begin k2 <= xr[15:8]; k3 <= xr[7:0]; h3 <= {xr[14],1'b0,xr[12],1'b0,xr[10],1'b0,xr[8],1'b0}; h4 <= {xr[6],1'b0,xr[4],1'b0,xr[2],1'b0,xr[0],1'b0}; end
			2'd2: begin k0 <= k0 ^ xr[15:8]; k1 <= k1 ^ xr[7:0]; h1 <= h1 | (xr[15:8] & 8'h55); h2 <= h2 | (xr[7:0] & 8'h55); end
			2'd3: begin k2 <= k2 ^ xr[15:8]; k3 <= k3 ^ xr[7:0]; h3 <= h3 | (xr[15:8] & 8'h55); h4 <= h4 | (xr[7:0] & 8'h55); end
		endcase
		if (cnt[1:0] != 2'd3) begin cnt <= cnt + 14'd1; `GB_XFER(16'h0000, GH_5) end
		else state <= GH_6;
	end
	GH_6: begin
		if      (h1 != 8'hFF)               begin last_error <= 8'd22; `GB_TEND(WT_NEXT) end
		else if (h2 > 8'd159)               begin last_error <= 8'd23; `GB_TEND(WT_NEXT) end
		else if (h3 > 8'd10)                begin last_error <= 8'd24; `GB_TEND(WT_NEXT) end
		else if (h4 > 8'd11 || h4 == 8'd0)  begin last_error <= 8'd25; `GB_TEND(WT_NEXT) end
		else begin
			wt_track  <= h2;
			wt_sector <= h3;
			cnt       <= 14'd0;
			`GB_XFER(16'h0000, GH_7)
		end
	end
	// 16 label words, then 4 header checksum words
	GH_7: begin
		if (cnt < 14'd16) begin
			if (!cnt[0]) begin k0 <= k0 ^ xr[15:8]; k1 <= k1 ^ xr[7:0]; end
			else         begin k2 <= k2 ^ xr[15:8]; k3 <= k3 ^ xr[7:0]; end
		end
		else case (cnt[1:0])
			2'd0: begin h1 <= {xr[14],1'b0,xr[12],1'b0,xr[10],1'b0,xr[8],1'b0}; h2 <= {xr[6],1'b0,xr[4],1'b0,xr[2],1'b0,xr[0],1'b0}; end
			2'd1: begin h3 <= {xr[14],1'b0,xr[12],1'b0,xr[10],1'b0,xr[8],1'b0}; h4 <= {xr[6],1'b0,xr[4],1'b0,xr[2],1'b0,xr[0],1'b0}; end
			2'd2: begin h1 <= h1 | (xr[15:8] & 8'h55); h2 <= h2 | (xr[7:0] & 8'h55); end
			2'd3: begin h3 <= h3 | (xr[15:8] & 8'h55); h4 <= h4 | (xr[7:0] & 8'h55); end
		endcase
		if (cnt != 14'd19) begin cnt <= cnt + 14'd1; `GB_XFER(16'h0000, GH_7) end
		else state <= GH_8;
	end
	GH_8: begin
		if (h1 != (k0 & 8'h55) || h2 != (k1 & 8'h55) || h3 != (k2 & 8'h55) || h4 != (k3 & 8'h55)) begin
			last_error <= 8'd26;
			`GB_TEND(WT_NEXT)
		end
		else if (wt_track != cur_t) begin
			last_error <= 8'd27;
			`GB_TEND(WT_NEXT)
		end
		else if (wt_lba >= max_lba) `GB_TEND(ST_1)                   // FileSeekLBA() fails
		else `GB_TEND(GD_0)
	end

	// GetData()
	GD_0: begin io_sel <= SEL_FPGA; `GB_XFER(16'h0000, GD_1) end
	GD_1:
		if (!xr[9]) `GB_TEND(WT_NEXT)
		else `GB_XFER(16'h0000, GD_2)
	GD_2: `GB_XFER(16'h0000, GD_3)
	GD_3: begin
		if (xr[13:0] >= 14'h204) begin cnt <= 14'd0; `GB_XFER(16'h0000, GD_4) end
		else if (!xr[15]) begin last_error <= 8'd28; `GB_TEND(WT_NEXT) end
		else `GB_TEND(GD_0)
	end
	// data checksum: odd, odd, even, even
	GD_4: begin
		case (cnt[1:0])
			2'd0: begin h1 <= {xr[14],1'b0,xr[12],1'b0,xr[10],1'b0,xr[8],1'b0}; h2 <= 8'h00; end  // (uint8_t)tmp & 0x55
			2'd1: begin h3 <= {xr[14],1'b0,xr[12],1'b0,xr[10],1'b0,xr[8],1'b0}; h4 <= {xr[6],1'b0,xr[4],1'b0,xr[2],1'b0,xr[0],1'b0}; end
			2'd2: begin h1 <= h1 | (xr[15:8] & 8'h55); h2 <= h2 | (xr[7:0] & 8'h55); end
			2'd3: begin h3 <= h3 | (xr[15:8] & 8'h55); h4 <= h4 | (xr[7:0] & 8'h55); end
		endcase
		if (cnt[1:0] != 2'd3) begin cnt <= cnt + 14'd1; `GB_XFER(16'h0000, GD_4) end
		else begin
			k0 <= 8'd0; k1 <= 8'd0; k2 <= 8'd0; k3 <= 8'd0;
			cnt <= 14'd0;
			`GB_XFER(16'h0000, GD_5)
		end
	end
	// 256 odd words, then 256 even words
	GD_5: begin
		if (!cnt[0]) begin k0 <= k0 ^ xr[15:8]; k1 <= k1 ^ xr[7:0]; end
		else         begin k2 <= k2 ^ xr[15:8]; k3 <= k3 ^ xr[7:0]; end
		if (!cnt[8]) obuf[cnt[7:0]] <= {xr[14],1'b0,xr[12],1'b0,xr[10],1'b0,xr[8],1'b0, xr[6],1'b0,xr[4],1'b0,xr[2],1'b0,xr[0],1'b0};
		else         ebuf[cnt[7:0]] <= xr & 16'h5555;
		if (cnt != 14'd511) begin cnt <= cnt + 14'd1; `GB_XFER(16'h0000, GD_5) end
		else state <= GD_6;
	end
	GD_6: begin
		if (h1 != (k0 & 8'h55) || h2 != (k1 & 8'h55) || h3 != (k2 & 8'h55) || h4 != (k3 & 8'h55)) begin
			last_error <= 8'd29;
			`GB_TEND(WT_NEXT)
		end
		else if (!drv_writable[drv]) begin
			last_error <= 8'd30;
			`GB_TEND(WT_NEXT)
		end
		else `GB_TEND(WT_COMMIT)
	end

	// FileWriteSec()
	WT_COMMIT:   begin li <= 9'd0; state <= WT_COMMIT_A; end
	WT_COMMIT_A: begin
		if (li[8]) begin
			sectors_written <= sectors_written + 16'd1;
			state <= WT_NEXT;
		end
		else begin
			buf_ra <= li[7:0];
			state  <= WT_COMMIT_D;
		end
	end
	WT_COMMIT_D: state <= WT_COMMIT_W;   // buffer read latency
	WT_COMMIT_W:
		if (!mem_req) begin
			mem_req   <= 1'b1;
			mem_we    <= 1'b1;
			mem_addr  <= slot_addr + {wt_lba, 8'd0} + li[7:0];
			mem_wdata <= obuf_q | ebuf_q;
		end
		else if (mem_ack) begin
			mem_req <= 1'b0;
			li      <= li + 9'd1;
			state   <= WT_COMMIT_A;
		end

	// while (FindSync(drive))
	WT_NEXT: state <= FS_0;

	default: state <= POLL_BEGIN;
	endcase
end

`undef GB_XFER
`undef GB_TEND

endmodule
