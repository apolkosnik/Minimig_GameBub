// Game Bub Minimig: configuration and Kickstart upload over IO_UIO.
//
// Replays what Main_MiSTer's ApplyConfiguration() (minimig_config.cpp)
// sends to userio.v:
//
//   (the hard disk images are looked at first: gb_ide, hdd_ready)
//   CPU, CHIP, FLP, FLPEX01, FLPEX23           (pre-configuration)
//   RST(HLT), HDD, MEM, CPU, CHIP, FLP, FLPEX   (CPU halted)
//   [reload] RST(HLT|CPU), "discard residents", Kickstart upload
//   RST(HLT|CPU|USR), RST(0 or HLT)
//   VID, AUD, JOY, USRPORT
//
// The Kickstart image is read from its SDRAM staging area (written there by
// gb_host from the Game Bub file loader) and uploaded through the userio
// memory write command (UIO_MM2_WR) exactly as UploadKickstart() does,
// including the mirrors for 8 KB, 256 KB, 512 KB and 1 MB images.
//
// After the sequence, "halt" requests (pause while the Game Bub menu has
// focus) are sent as RST(HLT) / RST(0).
//
// SPDX-License-Identifier: GPL-3.0-or-later

module gb_boot
#(
	parameter [24:1] KICK_STAGE = 24'hB80000   // word address of the staged ROM
)
(
	input             clk,
	input             reset,

	input             start,        // run the sequence (pulse)
	input             reload_kick,  // with start: upload the Kickstart
	output            busy,         // owns the IO bus (sequence running)
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
localparam K_CMD = 2'd0, K_RESIDENTS = 2'd1, K_KICK = 2'd2, K_END = 2'd3;

reg  [4:0] step;
reg        reload;
reg  [1:0] k_kind;
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
		5'd7:  begin k_cmd = UIO_MM2_MEM;     k_val = cfg_memory; end
		5'd8:  begin k_cmd = UIO_MM2_CPU;     k_val = cfg_cpu; end
		5'd9:  begin k_cmd = UIO_MM2_CHIP;    k_val = cfg_chipset; end
		5'd10: begin k_cmd = UIO_MM2_FLP;     k_val = cfg_floppy; end
		5'd11: begin k_cmd = UIO_MM2_FLPEX01; k_val = 16'h0000; end
		5'd12: begin k_cmd = UIO_MM2_FLPEX23; k_val = 16'h0000; end
		5'd13: begin k_cmd = UIO_MM2_RST;     k_val = SPI_RST_CPU | SPI_CPU_HLT; k_skip = !reload; end
		5'd14: begin k_kind = K_RESIDENTS; k_skip = !reload; end
		5'd15: begin k_kind = K_KICK;      k_skip = !reload; end
		5'd16: begin k_cmd = UIO_MM2_RST;     k_val = SPI_RST_USR | SPI_RST_CPU | SPI_CPU_HLT; end
		5'd17: begin k_cmd = UIO_MM2_RST;     k_val = halt ? SPI_CPU_HLT : 3'd0; end
		5'd18: begin k_cmd = UIO_MM2_VID;     k_val = 16'h0000; end
		5'd19: begin k_cmd = UIO_MM2_AUD;     k_val = cfg_audmix; end
		5'd20: begin k_cmd = UIO_MM2_JOY;     k_val = 16'h0000; end
		5'd21: begin k_cmd = UIO_MM2_USRPORT; k_val = 16'h0000; end
		default: k_kind = K_END;
	endcase
end

// Kickstart regions: {source byte offset, Amiga address, length in bytes}
// as in UploadKickstart()
reg  [1:0] region;
reg  [2:0] nregions;
reg [20:0] r_src;
reg [23:0] r_dst;
reg [20:0] r_len;
always @* begin
	r_src = 21'd0; r_dst = 24'hF80000; r_len = 21'h080000;
	if (kick_size == 21'h002000) begin            // 8 KB A1000 boot ROM
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

assign busy = (state != S_IDLE);

// region parameters are latched with the region header (region already
// advanced in S_RD at the same edge, so this takes the current one)
reg [20:0] r_src_q, r_len_q;
always @(posedge clk) begin
	if (state == S_RD && region != nregions[1:0]) begin
		r_src_q <= r_src;
		r_len_q <= r_len;
	end
end


always @(posedge clk) begin
	if (reset) begin
		state    <= S_IDLE;
		io_sel   <= 2'b00;
		io_req   <= 1'b0;
		mem_req  <= 1'b0;
		done     <= 1'b0;
		halt_now <= 1'b0;
	end
	else case (state)
	S_IDLE: begin
		if (start) begin
			reload <= reload_kick;
			step   <= 5'd0;
			state  <= S_WAITBUS;
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
			halt_now <= halt;
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
				default: begin // K_KICK
					region   <= 2'd0;
					tagclear <= 1'b0;
					nregions <= (kick_size == 21'h002000) ? 3'd2 : 3'd2;
					state    <= S_RD;   // S_RD sets up the region header
					io_sel   <= 2'b00;
				end
			endcase
		end
	end

	// ---------------------------------------------- Kickstart region setup
	S_RD: begin
		if (region == nregions[1:0]) begin
			step  <= step + 5'd1;
			state <= S_STEP;
		end
		else begin
			tagclear  <= (kick_size == 21'h002000) && region == 2'd1;
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
				// header sent: ROM data follows for Kickstart regions
				if (next_after == S_RD) begin
					in_data <= 1'b1;
					state   <= tagclear ? S_SEND : S_RD_W;
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
				state   <= (lo_byte && !tagclear) ? S_RD_W : S_SEND;
			end
		end

	// fetch the ROM word at boff from the staging area
	S_RD_W:
		if (boff == r_len_q) state <= S_END;
		else if (!mem_req) begin
			mem_req  <= 1'b1;
			mem_addr <= KICK_STAGE + {4'd0, r_src_q[20:1]} + {4'd0, boff[20:1]};
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
