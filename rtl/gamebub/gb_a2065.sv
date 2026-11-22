// Game Bub Minimig: a Commodore A2065 Ethernet board (Zorro II, 64 KB).
//
// On MiSTer the board's Am7990 LANCE runs on the ARM (Main_MiSTer,
// support/minimig/minimig_a2065_*.cpp, after Amiberry's a2065.cpp): the
// FPGA has the chip's registers and passes them and the board's RAM to it
// through DDR3. Here the LANCE is in the FPGA, as that code has it, and
// only whole Ethernet frames go to the Game Bub's MCU and come from it.
//
// The board (the Amiga's a2065.device needs nothing else):
//   base + $4000   RDP, the register the pointer selects
//   base + $4002   RAP, the register pointer (7 bits)
//   base + $8000   32 KB of RAM: the initialisation block, the two
//                  descriptor rings and the frame buffers, which the LANCE
//                  reads and writes there (two byte lanes of block RAM, a
//                  port each for the CPU and the LANCE)
//   level 2 interrupt while CSR0's INTR and INEA
//
// The LANCE (one state machine, a byte of the board's RAM every three
// clocks):
//   - INIT takes the initialisation block (mode, station address, logical
//     address filter, the rings' addresses and sizes) and sets IDON;
//   - TDMD sends the frames the driver has put in the transmit ring: from
//     the first descriptor it owns that starts a frame, the buffers of the
//     descriptors up to the one that ends it into the frame buffer (padded
//     to 60 bytes), the descriptors given back, TINT. In loopback the frame
//     is received again; else it is offered to the MCU (tx_valid, tx_len:
//     the MCU reads it and answers tx_taken) and the next waits for that.
//     With no network (net_up low: no dock, no adapter on it or its cable
//     out) the frame goes nowhere and the driver is told, in the one way
//     a2065.device passes on to the stack: MERR, the transmitter and the
//     receiver off. The driver then stops the chip, is offline and says so
//     (S2EVENT_OFFLINE), and a stack does not wait for answers that cannot
//     come; S2_ONLINE starts it again;
//   - a frame the MCU has written (rx_commit, rx_len bytes) is received if
//     the receiver is on and the frame is for the station (its address,
//     broadcast, a multicast address the logical address filter has, or
//     all with PROM), and is not the station's own coming back: into the
//     buffers of the descriptors the LANCE owns, with its CRC after it,
//     STP on the first and ENP and the length on the last, RINT. Without a
//     descriptor: MISS, or in the middle of a frame BUFF and OFLO and the
//     receiver off.
//
// The frame buffers are in 32 bit words for the MCU's memory interface
// (byte 0 of a frame in bits 7:0 of word 0).
//
// SPDX-License-Identifier: GPL-3.0-or-later

module gb_a2065
(
	input             clk,           // clk_sys
	input             reset,         // the Amiga's reset: the LANCE stops

	// the chip bus (minimig.sv)
	input             sel,           // the board's 64 KB are addressed
	input      [23:1] addr,
	input      [15:0] wdata,
	input             rw,            // 1: read
	input             uds_n,
	input             lds_n,
	output     [15:0] rdata,         // 0 unless the board is read
	output            irq,

	// frames (the MCU, through gb_host)
	input             net_up,        // the MCU takes and brings frames
	output reg        tx_valid = 1'b0,
	output reg [10:0] tx_len = 11'd0,
	input             tx_taken,
	input       [8:0] tx_raddr,      // the transmit buffer, in words
	output reg [31:0] tx_rdata,
	input             rx_we,         // the receive buffer, in words
	input       [8:0] rx_waddr,
	input      [31:0] rx_wdata,
	input             rx_commit,     // a frame of rx_len bytes is in it
	input      [10:0] rx_len,
	output reg        rx_busy = 1'b0, // until the LANCE has taken it or dropped it

	// observation
	output reg [15:0] dbg_tx = 16'd0,       // frames sent
	output reg [15:0] dbg_rx = 16'd0,       // frames received into the ring
	output reg [15:0] dbg_drop = 16'd0      // frames from the MCU not received
);

// ---------------------------------------------------------------------------
// CSR0 bits, mode bits, descriptor bits
// ---------------------------------------------------------------------------
localparam C_BABL = 14, C_CERR = 13, C_MISS = 12, C_MERR = 11, C_RINT = 10, C_TINT = 9, C_IDON = 8,
           C_INEA = 6, C_RXON = 5, C_TXON = 4, C_TDMD = 3, C_STOP = 2, C_STRT = 1, C_INIT = 0;
localparam M_PROM = 15, M_COLL = 4, M_DTCR = 3, M_LOOP = 2, M_DTX = 1, M_DRX = 0;

// ---------------------------------------------------------------------------
// the board's RAM: byte lanes, port A the CPU, port B the LANCE
// ---------------------------------------------------------------------------
reg  [7:0] ram_hi [0:16383];     // bytes at even addresses
reg  [7:0] ram_lo [0:16383];
reg  [7:0] a_hi, a_lo, b_hi, b_lo;
wire       sel_ram = sel && addr[15];
wire       sel_reg = sel && (addr[15:2] == 14'h1000);
wire       a_we_hi = sel_ram && !rw && !uds_n;
wire       a_we_lo = sel_ram && !rw && !lds_n;
reg [14:1] b_addr = 14'd0;
reg  [7:0] b_din = 8'd0;
reg        b_we_hi = 1'b0, b_we_lo = 1'b0;

always @(posedge clk) begin
	if (a_we_hi) ram_hi[addr[14:1]] <= wdata[15:8];
	a_hi <= ram_hi[addr[14:1]];
end
always @(posedge clk) begin
	if (a_we_lo) ram_lo[addr[14:1]] <= wdata[7:0];
	a_lo <= ram_lo[addr[14:1]];
end
always @(posedge clk) begin
	if (b_we_hi) ram_hi[b_addr] <= b_din;
	b_hi <= ram_hi[b_addr];
end
always @(posedge clk) begin
	if (b_we_lo) ram_lo[b_addr] <= b_din;
	b_lo <= ram_lo[b_addr];
end

// ---------------------------------------------------------------------------
// the frame buffers (32 bit words to the MCU)
// ---------------------------------------------------------------------------
reg [31:0] txb [0:511];
reg [31:0] rxb [0:511];
reg        t_we = 1'b0;
reg [10:0] t_wa = 11'd0;
reg  [7:0] t_wd = 8'd0;
reg [10:0] f_ra = 11'd0;         // the frame being received: byte address
reg [31:0] t_q, r_q;
always @(posedge clk) begin
	for (int i = 0; i < 4; i++)
		if (t_we && t_wa[1:0] == i[1:0]) txb[t_wa[10:2]][8 * i +: 8] <= t_wd;
	tx_rdata <= txb[tx_raddr];
	t_q      <= txb[f_ra[10:2]];
end
always @(posedge clk) begin
	if (rx_we) rxb[rx_waddr] <= rx_wdata;
	r_q <= rxb[f_ra[10:2]];
end

// ---------------------------------------------------------------------------
// registers
// ---------------------------------------------------------------------------
reg  [6:0] rap = 7'd0;
reg [15:0] csr0 = 16'h0004;      // STOP; ERR and INTR are made as it is read
reg [15:0] csr1 = 16'd0;
reg  [7:0] csr2 = 8'd0;
reg  [2:0] csr3 = 3'd0;
reg [15:0] mode = 16'd0;
reg [63:0] ladrf = 64'd0;
reg [47:0] mac = 48'd0;          // the station's address, the first byte in 47:40
reg [14:0] rdra = 15'd0, tdra = 15'd0;
reg  [9:0] rlen = 10'd0, tlen = 10'd0;      // descriptors of each ring (at most 128 from the block)
reg  [8:0] roff = 9'd0, toff = 9'd0;
reg        initialized = 1'b0;

wire       intr     = |{csr0[C_BABL], csr0[C_MISS], csr0[C_MERR], csr0[C_RINT], csr0[C_TINT], csr0[C_IDON]};
wire       err      = |{csr0[C_BABL], csr0[C_CERR], csr0[C_MISS], csr0[C_MERR]};
wire [15:0] csr0_rd = {err, csr0[14:8], intr, csr0[6:0]};
assign irq = intr && csr0[C_INEA];

reg [15:0] reg_q;
always @(*) begin
	if (addr[1]) reg_q = {9'd0, rap};
	else case (rap)
		7'd0:    reg_q = csr0_rd;
		7'd1:    reg_q = csr1;
		7'd2:    reg_q = {8'd0, csr2};
		7'd3:    reg_q = {13'd0, csr3};
		7'd88:   reg_q = 16'h0001;
		7'd89:   reg_q = 16'h3003;
		default: reg_q = 16'h0000;
	endcase
end
reg        rd_ram_d = 1'b0, rd_reg_d = 1'b0;
reg [15:0] reg_q_d;
always @(posedge clk) begin
	rd_ram_d <= sel_ram && rw;
	rd_reg_d <= sel_reg && rw;
	reg_q_d  <= reg_q;
end
assign rdata = (sel_ram && rw && rd_ram_d) ? {a_hi, a_lo} :
               (sel_reg && rw && rd_reg_d) ? reg_q_d : 16'h0000;

// a register write: once in a bus cycle
wire       wr_reg = sel_reg && !rw && !(uds_n && lds_n);
reg        wr_reg_d = 1'b0;
wire       wr_now = wr_reg && !wr_reg_d;

// ---------------------------------------------------------------------------
// CRC-32 (Ethernet's, bit-reflected), a byte a step
// ---------------------------------------------------------------------------
function automatic [31:0] crc_byte(input [31:0] c, input [7:0] d);
	reg [31:0] x;
	begin
		x = c ^ {24'd0, d};
		for (int i = 0; i < 8; i++) x = x[0] ? (32'hEDB88320 ^ (x >> 1)) : (x >> 1);
		crc_byte = x;
	end
endfunction

// ---------------------------------------------------------------------------
// the LANCE
// ---------------------------------------------------------------------------
localparam [5:0]
	S_IDLE    = 6'd0,
	S_INIT    = 6'd1,  S_INIT_W  = 6'd2,  S_INIT_T  = 6'd3,  S_INIT_E  = 6'd4,
	S_TSCAN   = 6'd5,  S_TSCAN_W = 6'd6,  S_TSCAN_T = 6'd7,
	S_TDESC   = 6'd8,  S_TDESC_W = 6'd9,  S_TDESC_T = 6'd10, S_TDESC_E = 6'd11,
	S_TCOPY   = 6'd12, S_TCOPY_W = 6'd13, S_TCOPY_T = 6'd14, S_TPAD    = 6'd15,
	S_TWB     = 6'd16, S_TWB2    = 6'd17, S_TEND    = 6'd18, S_TSEND   = 6'd19,
	S_RHEAD   = 6'd20, S_RHEAD_W = 6'd21, S_RHEAD_T = 6'd22, S_RFILT   = 6'd23,
	S_RDESC   = 6'd24, S_RDESC_W = 6'd25, S_RDESC_T = 6'd26, S_RDESC_E = 6'd27,
	S_RCOPY   = 6'd28, S_RCOPY_W = 6'd29, S_RCOPY_T = 6'd30,
	S_RWB     = 6'd31, S_RWB2    = 6'd32, S_RWB3    = 6'd33, S_REND    = 6'd34,
	S_RMISS   = 6'd35;
reg  [5:0] st = S_IDLE;

reg        init_req = 1'b0;      // INIT was written
reg        strt_after = 1'b0;    // STRT came with it
reg        tx_req = 1'b0;        // TDMD was written
reg        loop_req = 1'b0;      // a frame sent in loopback waits to be received
reg        rx_loop = 1'b0;       // the frame being received is that one
reg  [3:0] wcnt;                 // words of a block, bytes of a descriptor
reg [15:0] w0, w1, w2, w3;       // a descriptor
reg [14:0] bptr;                 // a byte of the board's RAM
reg [12:0] bleft;                // bytes of the buffer still to go
reg [10:0] flen;                 // bytes of the frame so far (transmit), its length (receive)
reg [10:0] fpos;                 // receive: the next byte of the frame and its CRC
reg  [8:0] scan;                 // descriptors looked at
reg        t_fcs;                // the frame's first descriptor has ADD_FCS
reg        t_err;                // the frame cannot be sent
reg        t_keep;               // the ring stays at this descriptor (it was not the LANCE's)
reg        t_last;               // the descriptor ends the frame
reg        r_first;              // no descriptor has been filled for this frame
reg [31:0] crc;
reg [47:0] h_dst, h_src;
reg [10:0] r_total;              // frame and CRC

wire [14:0] tdesc = tdra + {toff[8:0], 3'b000};
wire [14:0] rdesc = rdra + {roff[8:0], 3'b000};
wire  [7:0] b_byte = bptr[0] ? b_lo : b_hi;          // (of the word read two clocks ago)
wire [31:0] f_q    = rx_loop ? t_q : r_q;
wire  [7:0] f_byte = f_q[8 * f_ra[1:0] +: 8];
wire [31:0] crc_out = ~crc;
wire  [7:0] r_byte = (fpos < flen)          ? f_byte :
                     (fpos == flen)         ? crc_out[31:24] :
                     (fpos == flen + 11'd1) ? crc_out[23:16] :
                     (fpos == flen + 11'd2) ? crc_out[15:8]  : crc_out[7:0];
wire        bcast  = &h_dst;
wire  [5:0] hash   = crc[31:26];                     // of the six bytes of the destination (as Main_MiSTer takes it)

task start_on;                   // STRT, or TDMD with the transmitter off
	begin
		csr0[C_STOP] <= 1'b0;
		csr0[C_TXON] <= !mode[M_DTX];
		csr0[C_RXON] <= !mode[M_DRX];
	end
endtask

always @(posedge clk) begin
	wr_reg_d <= wr_reg;
	b_we_hi  <= 1'b0;
	b_we_lo  <= 1'b0;
	t_we     <= 1'b0;
	if (tx_taken) tx_valid <= 1'b0;
	if (rx_commit && !rx_busy) rx_busy <= 1'b1;

	// ---- the LANCE's work
	case (st)
		S_IDLE: begin
			if (init_req) begin
				init_req <= 1'b0;
				bptr <= {csr1[14:1], 1'b0};          // (the block is in the board's RAM)
				wcnt <= 4'd0;
				st   <= S_INIT;
			end
			else if (loop_req) begin
				loop_req <= 1'b0;
				rx_loop  <= 1'b1;
				st       <= S_RHEAD;
				fpos     <= 11'd0;
			end
			else if (tx_req && csr0[C_TXON] && !(tx_valid && net_up)) begin
				tx_req <= 1'b0;
				scan   <= 9'd0;
				st     <= S_TSCAN;
			end
			else if (tx_req && !csr0[C_TXON]) tx_req <= 1'b0;
			else if (rx_busy) begin
				rx_loop <= 1'b0;
				flen    <= rx_len;
				fpos    <= 11'd0;
				st      <= S_RHEAD;
			end
		end

		// ---- the initialisation block: twelve words
		S_INIT:   begin b_addr <= bptr[14:1]; st <= S_INIT_W; end
		S_INIT_W: st <= S_INIT_T;
		S_INIT_T: begin
			case (wcnt)
				4'd0:  mode <= {b_hi, b_lo};
				4'd1:  mac[47:32] <= {b_lo, b_hi};
				4'd2:  mac[31:16] <= {b_lo, b_hi};
				4'd3:  mac[15:0]  <= {b_lo, b_hi};
				4'd4:  ladrf[15:0]  <= {b_hi, b_lo};
				4'd5:  ladrf[31:16] <= {b_hi, b_lo};
				4'd6:  ladrf[47:32] <= {b_hi, b_lo};
				4'd7:  ladrf[63:48] <= {b_hi, b_lo};
				4'd8:  rdra[14:0] <= {b_hi[6:0], b_lo[7:3], 3'b000};
				4'd9:  rlen <= 10'd1 << b_hi[7:5];
				4'd10: tdra[14:0] <= {b_hi[6:0], b_lo[7:3], 3'b000};
				default: tlen <= 10'd1 << b_hi[7:5];
			endcase
			wcnt <= wcnt + 1'd1;
			bptr <= bptr + 15'd2;
			st   <= (wcnt == 4'd11) ? S_INIT_E : S_INIT;
		end
		S_INIT_E: begin
			roff <= 9'd0;
			toff <= 9'd0;
			initialized  <= 1'b1;
			csr0[C_IDON] <= 1'b1;
			if (strt_after) start_on;
			else begin
				csr0[C_RXON] <= 1'b0;
				csr0[C_TXON] <= 1'b0;
				csr0[C_STOP] <= 1'b0;
				csr3 <= 3'd0;
			end
			strt_after <= 1'b0;
			st <= S_IDLE;
		end

		// ---- transmit: the first descriptor the LANCE owns that starts a frame
		S_TSCAN: begin
			if (tlen == 10'd0 || scan == tlen[8:0] && tlen != 10'd512) st <= S_IDLE;   // none
			else begin b_addr <= tdesc[14:1] + 14'd1; st <= S_TSCAN_W; end           // TMD1
		end
		S_TSCAN_W: st <= S_TSCAN_T;
		S_TSCAN_T: begin
			if (b_hi[7] && b_hi[1]) begin            // OWN and STP
				t_fcs <= b_hi[5];
				t_err <= 1'b0;
				t_keep <= 1'b0;
				flen  <= 11'd0;
				wcnt  <= 4'd0;
				st    <= S_TDESC;
			end
			else begin
				toff <= (toff + 9'd1 == tlen[8:0]) ? 9'd0 : toff + 9'd1;
				scan <= scan + 1'd1;
				st   <= (scan == 9'd511) ? S_IDLE : S_TSCAN;
			end
		end
		// a descriptor's four words
		S_TDESC:   begin b_addr <= tdesc[14:1] + {12'd0, wcnt[1:0]}; st <= S_TDESC_W; end
		S_TDESC_W: st <= S_TDESC_T;
		S_TDESC_T: begin
			case (wcnt[1:0])
				2'd0: w0 <= {b_hi, b_lo};
				2'd1: w1 <= {b_hi, b_lo};
				2'd2: w2 <= {b_hi, b_lo};
				2'd3: w3 <= {b_hi, b_lo};
			endcase
			wcnt <= wcnt + 1'd1;
			st   <= (wcnt[1:0] == 2'd3) ? S_TDESC_E : S_TDESC;
		end
		S_TDESC_E: begin
			wcnt <= 4'd0;
			if (!w1[15]) begin
				// not the LANCE's: the frame has no end
				w3[15] <= 1'b1; w3[14] <= 1'b1;      // BUFF, UFLO
				w1[14] <= 1'b1;                      // ERR
				csr0[C_TXON] <= 1'b0;
				t_err  <= 1'b1;
				t_keep <= 1'b1;
				t_last <= 1'b1;
				st     <= S_TWB;
			end
			else begin
				w1[15] <= 1'b0;
				t_last <= w1[8];                     // ENP
				bptr   <= w0[14:0];
				bleft  <= (16'd0 - w2 > 16'd4095) ? 13'd4095 : 13'(16'd0 - w2);
				if ({2'b00, flen} + ((16'd0 - w2 > 16'd4095) ? 13'd4095 : 13'(16'd0 - w2)) > 13'd2047) begin
					// more than a frame: given back as it is, the frame ends here
					t_last <= 1'b1;
					st     <= S_TWB;
				end
				else st <= S_TCOPY;
			end
		end
		// its buffer into the frame buffer
		S_TCOPY: begin
			if (bleft == 13'd0) st <= (t_last && flen < 11'd60 && !mode[M_LOOP]) ? S_TPAD : S_TWB;
			else begin b_addr <= bptr[14:1]; st <= S_TCOPY_W; end
		end
		S_TCOPY_W: st <= S_TCOPY_T;
		S_TCOPY_T: begin
			t_we  <= 1'b1;
			t_wa  <= flen;
			t_wd  <= b_byte;
			flen  <= flen + 1'd1;
			bptr  <= bptr + 1'd1;
			bleft <= bleft - 1'd1;
			st    <= S_TCOPY;
		end
		S_TPAD: begin
			if (flen >= 11'd60) st <= S_TWB;
			else begin
				t_we <= 1'b1;
				t_wa <= flen;
				t_wd <= 8'd0;
				flen <= flen + 1'd1;
			end
		end
		// the descriptor given back: TMD1, then TMD3
		S_TWB: begin
			if (t_last && !t_err) begin
				if (flen < 11'd60 && !mode[M_LOOP]) begin
					w3[15] <= 1'b1; w3[14] <= 1'b1;
					w1[14] <= 1'b1;
					csr0[C_TXON] <= 1'b0;
					t_err <= 1'b1;
				end
				else if (mode[M_COLL] || (!mode[M_LOOP] && h_dst == mac)) begin
					w1[14] <= 1'b1;                  // ERR
					w3[10] <= 1'b1;                  // RTRY
					t_err  <= 1'b1;
				end
			end
			st <= S_TWB2;
		end
		S_TWB2: begin
			b_addr  <= tdesc[14:1] + 14'd1;
			b_din   <= wcnt[0] ? w1[7:0] : w1[15:8];
			b_we_hi <= !wcnt[0];
			b_we_lo <= wcnt[0];
			wcnt    <= wcnt + 1'd1;
			if (wcnt[0]) st <= S_TEND;
		end
		S_TEND: begin
			// TMD3, a byte a clock
			b_addr  <= tdesc[14:1] + 14'd3;
			b_din   <= wcnt[0] ? w3[7:0] : w3[15:8];
			b_we_hi <= !wcnt[0];
			b_we_lo <= wcnt[0];
			wcnt    <= wcnt + 1'd1;
			if (wcnt[0]) begin
				if (!t_keep) toff <= (toff + 9'd1 == tlen[8:0]) ? 9'd0 : toff + 9'd1;
				wcnt <= 4'd0;
				st   <= t_last ? S_TSEND : S_TDESC;
			end
		end
		S_TSEND: begin
			csr0[C_TINT] <= 1'b1;
			if (!t_err) begin
				if (mode[M_LOOP]) loop_req <= 1'b1;
				else if (net_up) begin
					dbg_tx   <= dbg_tx + 1'd1;
					tx_valid <= 1'b1;
					tx_len   <= (mode[M_DTCR] && !t_fcs) ? flen - 11'd4 : flen;
				end
				else begin
					// no network: the driver is told (see above)
					csr0[C_MERR] <= 1'b1;
					csr0[C_TXON] <= 1'b0;
					csr0[C_RXON] <= 1'b0;
				end
			end
			// (the ring is looked through again: the driver may have more)
			tx_req <= !t_err && !mode[M_LOOP] && net_up;
			st     <= S_IDLE;
		end

		// ---- receive: the frame's addresses, the hash of its destination
		S_RHEAD:   begin f_ra <= fpos; st <= S_RHEAD_W; end
		S_RHEAD_W: st <= S_RHEAD_T;
		S_RHEAD_T: begin
			if (fpos == 11'd0) crc <= crc_byte(32'hFFFFFFFF, f_byte);
			else if (fpos < 11'd6) crc <= crc_byte(crc, f_byte);
			if (fpos < 11'd6) h_dst <= {h_dst[39:0], f_byte};
			else h_src <= {h_src[39:0], f_byte};
			fpos <= fpos + 1'd1;
			st   <= (fpos == 11'd11) ? S_RFILT : S_RHEAD;
		end
		S_RFILT: begin
			fpos    <= 11'd0;
			r_first <= 1'b1;
			r_total <= flen + 11'd4;
			if (!csr0[C_RXON] || flen < 11'd20 || flen > 11'd2040 || rlen == 10'd0) st <= S_RMISS;
			else if (rx_loop) st <= S_RDESC;
			else if (h_dst[40] && !mode[M_PROM] && !bcast && !ladrf[hash]) st <= S_RMISS;       // a multicast group not taken
			else if (!h_dst[40] && !mode[M_PROM] && h_dst != mac) st <= S_RMISS;                 // another station's
			else if (h_src == mac && (h_dst == mac || bcast)) st <= S_RMISS;                     // its own
			else st <= S_RDESC;
			wcnt <= 4'd0;
		end
		S_RMISS: begin
			// not received (no interrupt, nothing in the ring)
			if (!rx_loop) begin rx_busy <= 1'b0; dbg_drop <= dbg_drop + 1'd1; end
			st <= S_IDLE;
		end
		// a descriptor's words (RMD3 is only written)
		S_RDESC:   begin b_addr <= rdesc[14:1] + {12'd0, wcnt[1:0]}; st <= S_RDESC_W; end
		S_RDESC_W: st <= S_RDESC_T;
		S_RDESC_T: begin
			case (wcnt[1:0])
				2'd0: w0 <= {b_hi, b_lo};
				2'd1: w1 <= {b_hi, b_lo};
				default: w2 <= {b_hi, b_lo};
			endcase
			wcnt <= wcnt + 1'd1;
			st   <= (wcnt[1:0] == 2'd2) ? S_RDESC_E : S_RDESC;
		end
		S_RDESC_E: begin
			wcnt <= 4'd0;
			if (!w1[15]) begin
				// no descriptor: the frame is lost
				if (r_first) csr0[C_MISS] <= 1'b1;
				else begin
					w1[10] <= 1'b1; w1[12] <= 1'b1;  // BUFF, OFLO
					csr0[C_RXON] <= 1'b0;
				end
				t_err <= 1'b1;
				st    <= S_RWB;
			end
			else begin
				w1[15]  <= 1'b0;
				w1[9]   <= r_first;                  // STP
				r_first <= 1'b0;
				t_err   <= 1'b0;
				bptr    <= w0[14:0];
				bleft   <= (16'd0 - w2 > 16'd4095) ? 13'd4095 : 13'(16'd0 - w2);
				st      <= S_RCOPY;
			end
		end
		// the frame, then its CRC, into the buffer
		S_RCOPY: begin
			if (bleft == 13'd0 || fpos == r_total) begin
				w1[8] <= (fpos == r_total);              // ENP
				st    <= S_RWB;
			end
			else begin f_ra <= fpos; st <= S_RCOPY_W; end
		end
		S_RCOPY_W: st <= S_RCOPY_T;
		S_RCOPY_T: begin
			if (fpos == 11'd0) crc <= crc_byte(32'hFFFFFFFF, f_byte);
			else if (fpos < flen) crc <= crc_byte(crc, f_byte);
			b_addr  <= bptr[14:1];
			b_din   <= r_byte;
			b_we_hi <= !bptr[0];
			b_we_lo <= bptr[0];
			fpos    <= fpos + 1'd1;
			bptr    <= bptr + 1'd1;
			bleft   <= bleft - 1'd1;
			st      <= S_RCOPY;
		end
		// the descriptor given back: RMD1, and RMD3 (the length) on the last
		S_RWB: begin
			b_addr  <= rdesc[14:1] + 14'd1;
			b_din   <= wcnt[0] ? w1[7:0] : w1[15:8];
			b_we_hi <= !wcnt[0];
			b_we_lo <= wcnt[0];
			wcnt    <= wcnt + 1'd1;
			if (wcnt[0]) st <= (t_err || !w1[8]) ? S_REND : S_RWB2;
		end
		S_RWB2: begin
			b_addr  <= rdesc[14:1] + 14'd3;
			b_din   <= {5'd0, r_total[10:8]};
			b_we_hi <= 1'b1;
			st      <= S_RWB3;
		end
		S_RWB3: begin
			b_addr  <= rdesc[14:1] + 14'd3;
			b_din   <= r_total[7:0];
			b_we_lo <= 1'b1;
			st      <= S_REND;
		end
		S_REND: begin
			wcnt <= 4'd0;
			if (t_err) begin
				if (!rx_loop) begin rx_busy <= 1'b0; dbg_drop <= dbg_drop + 1'd1; end
				st <= S_IDLE;
			end
			else begin
				roff <= (roff + 9'd1 == rlen[8:0]) ? 9'd0 : roff + 9'd1;
				if (w1[8]) begin
					csr0[C_RINT] <= 1'b1;
					if (!rx_loop) begin rx_busy <= 1'b0; dbg_rx <= dbg_rx + 1'd1; end
					st <= S_IDLE;
				end
				else st <= S_RDESC;
			end
		end
		default: st <= S_IDLE;
	endcase

	// (transmit: the frame's destination, for the station's own address)
	if (st == S_TCOPY_T && flen < 11'd6) h_dst <= {h_dst[39:0], b_byte};

	// ---- the CPU's register writes (after the LANCE's: an acknowledge
	// does not take a bit set in the same clock)
	if (wr_now) begin
		if (addr[1]) rap <= wdata[6:0];
		else case (rap)
			7'd0: begin
				csr0[C_INEA] <= wdata[C_INEA];
				// write 1 to clear
				for (int i = 8; i < 15; i++)
					if (wdata[i] && !(st == S_INIT_E && i == C_IDON) && !(st == S_TSEND && i == C_TINT) &&
					    !(st == S_REND && i == C_RINT) && !(st == S_RDESC_E && i == C_MISS)) csr0[i] <= 1'b0;
				if (wdata[C_STOP] && !csr0[C_STOP]) begin
					csr0 <= 16'h0004;
					csr3 <= 3'd0;
					init_req <= 1'b0;
					tx_req   <= 1'b0;
					loop_req <= 1'b0;
					strt_after <= 1'b0;
					st       <= S_IDLE;      // what the LANCE was doing is given up
				end
				else begin
					if (wdata[C_INIT] && !csr0[C_INIT] && csr0[C_STOP]) begin
						csr0[C_INIT] <= 1'b1;
						init_req     <= 1'b1;
						if (wdata[C_STRT] && !csr0[C_STRT]) begin
							csr0[C_STRT] <= 1'b1;
							strt_after   <= 1'b1;
						end
					end
					else if (wdata[C_STRT] && !csr0[C_STRT] && (csr0[C_STOP] || csr0[C_INIT])) begin
						csr0[C_STRT] <= 1'b1;
						if (init_req) strt_after <= 1'b1;
						else start_on;
					end
					if (wdata[C_TDMD] && initialized) begin
						if (!csr0[C_TXON] && !init_req) start_on;
						tx_req <= 1'b1;
					end
				end
			end
			7'd1:  if (csr0[C_STOP]) csr1 <= {wdata[15:1], 1'b0};
			7'd2:  if (csr0[C_STOP]) csr2 <= wdata[7:0];
			7'd3:  if (csr0[C_STOP]) csr3 <= wdata[2:0];
			7'd8:  ladrf[63:48] <= wdata;
			7'd9:  ladrf[47:32] <= wdata;
			7'd10: ladrf[31:16] <= wdata;
			7'd11: ladrf[15:0]  <= wdata;
			7'd12: mac[47:32] <= {wdata[7:0], wdata[15:8]};
			7'd13: mac[31:16] <= {wdata[7:0], wdata[15:8]};
			7'd14: mac[15:0]  <= {wdata[7:0], wdata[15:8]};
			7'd15: mode <= wdata;
			default: ;
		endcase
	end

	if (reset) begin
		st          <= S_IDLE;
		rap         <= 7'd0;
		csr0        <= 16'h0004;
		csr1        <= 16'd0;
		csr2        <= 8'd0;
		csr3        <= 3'd0;
		initialized <= 1'b0;
		init_req    <= 1'b0;
		strt_after  <= 1'b0;
		tx_req      <= 1'b0;
		loop_req    <= 1'b0;
		tx_valid    <= 1'b0;
		rx_busy     <= 1'b0;
		roff        <= 9'd0;
		toff        <= 9'd0;
	end
end

endmodule
