// Game Bub Minimig: configuration and Kickstart upload over IO_UIO.
//
// Replays what Main_MiSTer's ApplyConfiguration() (minimig_config.cpp)
// sends to userio.v:
//
//   (the hard disk images are looked at first: gb_ide, hdd_ready)
//   CPU, CHIP, FLP, FLPEX01, FLPEX23           (pre-configuration)
//   RST(HLT), HDD, MEM, CPU, CHIP, FLP, FLPEX   (CPU halted)
//   [cartridge] its image upload (UploadActionReplay())
//   [reload] RST(HLT|CPU), "discard residents", Kickstart upload
//   RST(HLT|CPU|USR), RST(0 or HLT)
//   VID, AUD, JOY, USRPORT
//
// The Kickstart image is read from its SDRAM staging area (written there by
// gb_host from the Game Bub file loader) and uploaded through the userio
// memory write command (UIO_MM2_WR) exactly as UploadKickstart() does,
// including the mirrors for 8 KB, 256 KB, 512 KB and 1 MB images.
//
// The cartridge (a file of its own, optional; gb_host stages it and tells
// its kind) is fitted while its image is there: MEM's bit 6, and its image
// goes up in every sequence, as Main_MiSTer sends it with every
// configuration:
//   HRTmon                      to $A10000, then its configuration block
//                               (22 bytes at +20, maxchip at +68)
//   the Action Replay (AR5,     to $A80000: the ROM and the RAM's image, no
//   DeMoN v2)                   configuration
// Which of the two it is goes to the core (cart_ar) with MEM, the CPU
// halted, before the image: the upload needs the cartridge's memory decoded.
//
// After the sequence, "halt" requests (pause while the Game Bub menu has
// focus) are sent as RST(HLT) / RST(0).
//
// SPDX-License-Identifier: GPL-3.0-or-later

module gb_boot
#(
	parameter [24:1] KICK_STAGE = 24'hB80000,  // word address of the staged ROM
	parameter [24:1] CART_STAGE = 24'hB00000   // word address of the staged cartridge image
)
(
	input             clk,
	input             reset,

	input             start,        // run the sequence (pulse)
	input             reload_kick,  // with start: upload the Kickstart
	output            busy,         // a sequence is wanted or running: no new floppy poll
	output            own,          // has the IO bus (the floppy server had finished)
	output reg        done,         // the sequence has run at least once

	input             halt,         // keep the CPU halted (level)

	// configuration (userio encodings)
	input       [5:0] cfg_chipset,  // XXGEANT: G AGA, E ECS, A A1000, N NTSC, T turbo
	input       [7:0] cfg_cpu,      // SSPCCCTT
	input       [7:0] cfg_memory,   // XHFFSSCC
	input       [4:0] cfg_floppy,   // XXXZFFXS (FF drives-1, S speed)
	input       [1:0] cfg_audmix,
	input      [20:0] kick_size,    // bytes
	input       [5:0] cfg_hdd,      // IDE: bit 0 Gayle on, 1 master, 2 slave, 5 not the fast port
	input             hdd_ready,    // cfg_hdd is valid (the images have been looked at)

	// the cartridge (gb_host: as staged; taken when a sequence starts)
	input             cart_loaded,  // an image is staged
	input             cart_is_ar,   // it is the Action Replay, not HRTmon
	input      [19:0] cart_size,    // bytes
	output reg        cart_on,      // as sent to the Amiga: a cartridge is fitted ...
	output reg        cart_ar,      // ... and it is the Action Replay

	input             bus_free,     // the floppy server is idle and stopped

	// IO_UIO master
	output reg  [1:0] io_sel,
	output reg        io_req,
	output reg [15:0] io_wdata,
	input             io_ack,

	// SDRAM client (reads the staged Kickstart)
	output reg        mem_req,
	output reg [24:1] mem_addr,
	input             mem_ack,
	input      [15:0] mem_rdata
);

localparam [7:0]
	UIO_MM2_WR      = 8'hF0,
	UIO_MM2_RST     = 8'hF1,
	UIO_MM2_AUD     = 8'hF2,
	UIO_MM2_CHIP    = 8'hF3,
	UIO_MM2_CPU     = 8'hF4,
	UIO_MM2_MEM     = 8'hF5,
	UIO_MM2_VID     = 8'hF6,
	UIO_MM2_FLP     = 8'hF7,
	UIO_MM2_HDD     = 8'hF8,
	UIO_MM2_JOY     = 8'hF9,
	UIO_MM2_FLPEX01 = 8'hFA,
	UIO_MM2_FLPEX23 = 8'hFB,
	UIO_MM2_USRPORT = 8'hFC;

localparam [2:0] SPI_RST_USR = 3'd1, SPI_RST_CPU = 3'd2, SPI_CPU_HLT = 3'd4;
localparam [1:0] SEL_UIO = 2'b01;

// sequence steps: {kind, command, value}
localparam K_CMD = 3'd0, K_RESIDENTS = 3'd1, K_KICK = 3'd2, K_END = 3'd3, K_CART = 3'd4;
localparam [4:0] STEP_MEM = 5'd7, STEP_RUN = 5'd18;

reg  [4:0] step;
reg        reload;
reg        c_on, c_ar;    // the cartridge of this sequence
reg [19:0] c_size;        // (even)
reg  [2:0] k_kind;
reg  [7:0] k_cmd;
reg [15:0] k_val;
reg        k_skip;
reg        halt_now;

always @* begin
	k_kind = K_CMD;
	k_cmd  = 8'h00;
	k_val  = 16'h0000;
	k_skip = 1'b0;
	case (step)
		5'd0:  begin k_cmd = UIO_MM2_CPU;     k_val = cfg_cpu; end
		5'd1:  begin k_cmd = UIO_MM2_CHIP;    k_val = cfg_chipset; end
		5'd2:  begin k_cmd = UIO_MM2_FLP;     k_val = cfg_floppy; end
		5'd3:  begin k_cmd = UIO_MM2_FLPEX01; k_val = 16'h0000; end
		5'd4:  begin k_cmd = UIO_MM2_FLPEX23; k_val = 16'h0000; end
		5'd5:  begin k_cmd = UIO_MM2_RST;     k_val = SPI_CPU_HLT; end
		5'd6:  begin k_cmd = UIO_MM2_HDD;     k_val = {10'd0, cfg_hdd}; end
		STEP_MEM: begin k_cmd = UIO_MM2_MEM;  k_val = {8'd0, cfg_memory[7], c_on, cfg_memory[5:0]}; end
		5'd8:  begin k_cmd = UIO_MM2_CPU;     k_val = cfg_cpu; end
		5'd9:  begin k_cmd = UIO_MM2_CHIP;    k_val = cfg_chipset; end
		5'd10: begin k_cmd = UIO_MM2_FLP;     k_val = cfg_floppy; end
		5'd11: begin k_cmd = UIO_MM2_FLPEX01; k_val = 16'h0000; end
		5'd12: begin k_cmd = UIO_MM2_FLPEX23; k_val = 16'h0000; end
		5'd13: begin k_kind = K_CART;      k_skip = !c_on; end
		5'd14: begin k_cmd = UIO_MM2_RST;     k_val = SPI_RST_CPU | SPI_CPU_HLT; k_skip = !reload; end
		5'd15: begin k_kind = K_RESIDENTS; k_skip = !reload; end
		5'd16: begin k_kind = K_KICK;      k_skip = !reload; end
		5'd17: begin k_cmd = UIO_MM2_RST;     k_val = SPI_RST_USR | SPI_RST_CPU | SPI_CPU_HLT; end
		STEP_RUN: begin k_cmd = UIO_MM2_RST;  k_val = halt ? SPI_CPU_HLT : 3'd0; end
		5'd19: begin k_cmd = UIO_MM2_VID;     k_val = 16'h0000; end
		5'd20: begin k_cmd = UIO_MM2_AUD;     k_val = cfg_audmix; end
		5'd21: begin k_cmd = UIO_MM2_JOY;     k_val = 16'h0000; end
		5'd22: begin k_cmd = UIO_MM2_USRPORT; k_val = 16'h0000; end
		default: k_kind = K_END;
	endcase
end

// Kickstart regions: {source byte offset, Amiga address, length in bytes}
// as in UploadKickstart(); the cartridge's as in UploadActionReplay(): its
// image, and for HRTmon its configuration (bytes given here, not staged)
reg        cart;          // the regions are the cartridge's
reg  [1:0] region;
reg  [2:0] nregions;
reg [20:0] r_src;
reg [23:0] r_dst;
reg [20:0] r_len;
reg        r_lit;
always @* begin
	r_src = 21'd0; r_dst = 24'hF80000; r_len = 21'h080000; r_lit = 1'b0;
	if (cart) begin
		if (c_ar) begin r_dst = 24'hA80000; r_len = {1'b0, c_size}; end
		else case (region)
			2'd0:    begin r_dst = 24'hA10000; r_len = {1'b0, c_size}; end
			2'd1:    begin r_dst = 24'hA10014; r_len = 21'd22; r_lit = 1'b1; end
			default: begin r_dst = 24'hA10044; r_len = 21'd4;  r_lit = 1'b1; end
		endcase
	end
	else if (kick_size == 21'h002000) begin       // 8 KB A1000 boot ROM
		case (region)
			2'd0: begin r_src = 21'd0; r_dst = 24'hF80000; r_len = 21'h002000; end
			default: begin r_src = 21'd0; r_dst = 24'hFC0000; r_len = 21'h000000; end  // tag clear, below
		endcase
	end
	else if (kick_size == 21'h040000) begin       // 256 KB
		r_len = 21'h040000;
		r_dst = region[0] ? 24'hFC0000 : 24'hF80000;
	end
	else if (kick_size == 21'h100000) begin       // 1 MB
		r_src = region[0] ? 21'h080000 : 21'h000000;
		r_dst = region[0] ? 24'hF80000 : 24'hE00000;
	end
	else begin                                    // 512 KB (and anything else)
		r_dst = region[0] ? 24'hE00000 : 24'hF80000;
	end
end

localparam [3:0]
	S_IDLE = 4'd0, S_WAITBUS = 4'd1, S_STEP = 4'd2, S_SEND = 4'd3, S_ACK = 4'd4,
	S_END = 4'd5, S_END_W = 4'd6, S_RD = 4'd7, S_RD_W = 4'd8, S_HALT = 4'd9;

reg  [3:0] state, next_after;
reg  [4:0] wcnt;          // word index inside a transaction header
reg  [3:0] nwords;        // header words of the current transaction
reg [15:0] words [0:12];
reg [20:0] boff;          // byte offset inside the region
reg [15:0] rword;
reg        lo_byte;
reg        in_data;       // streaming ROM data
reg        tagclear;

// The floppy server finishes the poll it is in while the sequence waits in
// S_WAITBUS: the bus (and its acknowledge) is taken only after that. Taken
// with busy, a poll under way never got its acknowledge, the server never
// became idle and the sequence waited for it for ever.
assign busy = (state != S_IDLE);
assign own  = (state != S_IDLE) && (state != S_WAITBUS);

// region parameters are latched with the region header (region already
// advanced in S_RD at the same edge, so this takes the current one)
reg [20:0] r_src_q, r_len_q;
reg        lit_q, blk_q;
always @(posedge clk) begin
	if (state == S_RD && region != nregions[1:0]) begin
		r_src_q <= r_src;
		r_len_q <= r_len;
		lit_q   <= r_lit;
		blk_q   <= region[1];
	end
end

// HRTmon's configuration as UploadActionReplay() writes it: the block at
// +20 (blk 0), byte i, and maxchip at +68 (blk 1)
function automatic [7:0] hrt_cfg(input blk, input [4:0] i);
	if (blk) hrt_cfg = (i[1:0] == 2'd1) ? {2'b00, {1'b0, cfg_memory[1:0]} + 3'd1, 3'b000} : 8'h00;  // (memory & 3) + 1 half megabytes
	else case (i)
		5'd0:  hrt_cfg = 8'h00;   // mon_size: $00800000
		5'd1:  hrt_cfg = 8'h80;
		5'd2:  hrt_cfg = 8'h00;
		5'd3:  hrt_cfg = 8'h00;
		5'd4:  hrt_cfg = 8'h00;   // col0h
		5'd5:  hrt_cfg = 8'h5A;   // col0l
		5'd6:  hrt_cfg = 8'h0F;   // col1h
		5'd7:  hrt_cfg = 8'hFF;   // col1l
		5'd8:  hrt_cfg = 8'hFF;   // right
		5'd9:  hrt_cfg = 8'h00;   // keyboard
		5'd10: hrt_cfg = 8'hFF;   // key
		5'd11: hrt_cfg = cfg_hdd[0] ? 8'hFF : 8'h00;       // ide
		5'd12: hrt_cfg = 8'hFF;   // a1200
		5'd13: hrt_cfg = cfg_chipset[4] ? 8'hFF : 8'h00;   // aga
		5'd14: hrt_cfg = 8'hFF;   // insert
		5'd15: hrt_cfg = 8'h0F;   // delay
		5'd16: hrt_cfg = 8'hFF;   // lview
		5'd17: hrt_cfg = 8'h00;   // cd32
		5'd18: hrt_cfg = cfg_chipset[1] ? 8'h01 : 8'h00;   // screenmode: NTSC
		5'd19: hrt_cfg = 8'hFF;   // novbr
		5'd20: hrt_cfg = 8'h00;   // entered
		5'd21: hrt_cfg = 8'h01;   // hexmode
		default: hrt_cfg = 8'h00;
	endcase
endfunction


always @(posedge clk) begin
	if (reset) begin
		state    <= S_IDLE;
		io_sel   <= 2'b00;
		io_req   <= 1'b0;
		mem_req  <= 1'b0;
		done     <= 1'b0;
		halt_now <= 1'b0;
		cart     <= 1'b0;
		cart_on  <= 1'b0;
		cart_ar  <= 1'b0;
	end
	else case (state)
	S_IDLE: begin
		if (start) begin
			reload <= reload_kick;
			step   <= 5'd0;
			state  <= S_WAITBUS;
			// the cartridge as it is staged now (an odd byte rounded up)
			c_on   <= cart_loaded;
			c_ar   <= cart_is_ar;
			c_size <= {cart_size[19:1] + {18'd0, cart_size[0]}, 1'b0};
		end
		else if (done && halt != halt_now) begin
			state  <= S_WAITBUS;
			step   <= 5'd31;     // only the halt command
		end
	end

	S_WAITBUS:
		if (bus_free && hdd_ready) state <= (step == 5'd31) ? S_HALT : S_STEP;

	S_HALT: begin
		halt_now  <= halt;
		words[0]  <= {8'h00, UIO_MM2_RST};
		words[1]  <= halt ? SPI_CPU_HLT : 16'h0000;
		nwords    <= 4'd2;
		wcnt      <= 5'd0;
		in_data   <= 1'b0;
		io_sel    <= SEL_UIO;
		next_after <= S_IDLE;
		state     <= S_SEND;
	end

	S_STEP: begin
		if (k_kind == K_END) begin
			done  <= 1'b1;
			state <= S_IDLE;
		end
		else if (k_skip) step <= step + 5'd1;
		else begin
			wcnt       <= 5'd0;
			in_data    <= 1'b0;
			io_sel     <= SEL_UIO;
			next_after <= S_STEP;
			case (k_kind)
				K_CMD: begin
					words[0] <= {8'h00, k_cmd};
					words[1] <= k_val;
					nwords   <= 4'd2;
					step     <= step + 5'd1;
					state    <= S_SEND;
					// the halt state this step sends (a change after it,
					// before the end of the sequence, is sent from S_IDLE)
					if (step == STEP_RUN) halt_now <= halt;
					// the cartridge's kind with MEM (the CPU is halted)
					if (step == STEP_MEM) begin
						cart_on <= c_on;
						cart_ar <= c_on & c_ar;
					end
				end
				K_RESIDENTS: begin
					// "discard from possible residents": address 0, 00000000 01010101
					words[0]  <= {8'h00, UIO_MM2_WR};
					words[1]  <= 16'h0000; words[2]  <= 16'h0000; words[3]  <= 16'h0000; words[4]  <= 16'h0000;
					words[5]  <= 16'h0000; words[6]  <= 16'h0000; words[7]  <= 16'h0000; words[8]  <= 16'h0000;
					words[9]  <= 16'h0001; words[10] <= 16'h0001; words[11] <= 16'h0001; words[12] <= 16'h0001;
					nwords   <= 4'd13;
					step     <= step + 5'd1;
					state    <= S_SEND;
				end
				K_CART: begin
					cart     <= 1'b1;
					region   <= 2'd0;
					tagclear <= 1'b0;
					nregions <= c_ar ? 3'd1 : 3'd3;
					state    <= S_RD;
					io_sel   <= 2'b00;
				end
				default: begin // K_KICK
					cart     <= 1'b0;
					region   <= 2'd0;
					tagclear <= 1'b0;
					nregions <= (kick_size == 21'h002000) ? 3'd2 : 3'd2;
					state    <= S_RD;   // S_RD sets up the region header
					io_sel   <= 2'b00;
				end
			endcase
		end
	end

	// ----------------------------- Kickstart or cartridge region setup
	S_RD: begin
		if (region == nregions[1:0]) begin
			step  <= step + 5'd1;
			state <= S_STEP;
		end
		else begin
			tagclear  <= !cart && (kick_size == 21'h002000) && region == 2'd1;
			words[0]  <= {8'h00, UIO_MM2_WR};
			words[1]  <= {8'h00, r_dst[7:0]};
			words[2]  <= {8'h00, r_dst[15:8]};
			words[3]  <= {8'h00, r_dst[23:16]};
			words[4]  <= 16'h0000;
			nwords    <= 4'd5;
			wcnt      <= 5'd0;
			boff      <= 21'd0;
			lo_byte   <= 1'b0;
			in_data   <= 1'b0;
			io_sel    <= SEL_UIO;
			next_after <= S_RD;
			region    <= region + 2'd1;
			state     <= S_SEND;
		end
	end

	// ---------------------------------------------------- word transfers
	S_SEND: begin
		if (!in_data) begin
			if (wcnt == {1'b0, nwords}) begin
				// header sent: the region's data follows
				if (next_after == S_RD) begin
					in_data <= 1'b1;
					state   <= (tagclear || lit_q) ? S_SEND : S_RD_W;
				end
				else state <= S_END;
			end
			else begin
				io_wdata <= words[wcnt[3:0]];
				io_req   <= 1'b1;
				state    <= S_ACK;
			end
		end
		else begin
			if (tagclear) begin
				// clear the tag at $FC0000 (two zero bytes)
				if (boff == 21'd2) state <= S_END;
				else begin
					io_wdata <= 16'h0000;
					io_req   <= 1'b1;
					state    <= S_ACK;
				end
			end
			else if (boff == r_len_q) state <= S_END;
			else if (lit_q) begin
				io_wdata <= {8'h00, hrt_cfg(blk_q, boff[4:0])};
				io_req   <= 1'b1;
				state    <= S_ACK;
			end
			else if (!lo_byte) begin
				io_wdata <= {8'h00, rword[15:8]};
				io_req   <= 1'b1;
				state    <= S_ACK;
			end
			else begin
				io_wdata <= {8'h00, rword[7:0]};
				io_req   <= 1'b1;
				state    <= S_ACK;
			end
		end
	end

	S_ACK:
		if (io_ack) begin
			io_req <= 1'b0;
			if (!in_data) begin
				wcnt  <= wcnt + 5'd1;
				state <= S_SEND;
			end
			else begin
				boff    <= boff + 21'd1;
				lo_byte <= ~lo_byte;
				// after the low byte the next ROM word is needed
				state   <= (lo_byte && !tagclear && !lit_q) ? S_RD_W : S_SEND;
			end
		end

	// fetch the ROM word at boff from the staging area
	S_RD_W:
		if (boff == r_len_q) state <= S_END;
		else if (!mem_req) begin
			mem_req  <= 1'b1;
			mem_addr <= (cart ? CART_STAGE : KICK_STAGE) + {4'd0, r_src_q[20:1]} + {4'd0, boff[20:1]};
		end
		else if (mem_ack) begin
			mem_req <= 1'b0;
			rword   <= mem_rdata;
			state   <= S_SEND;
		end

	S_END:   begin io_sel <= 2'b00; state <= S_END_W; end
	S_END_W: state <= next_after;

	default: state <= S_IDLE;
	endcase
end

endmodule
