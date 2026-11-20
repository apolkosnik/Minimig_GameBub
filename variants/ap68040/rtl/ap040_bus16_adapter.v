//--------------------------------------------------------------------------//
// AP040 - MC68040 compatible CPU                                           //
//                                                                          //
// ap040_bus16_adapter.v - converts internal 32-bit AP040 transfers to the  //
// existing 16-bit Minimig bus contract (TG68K style).                      //
//                                                                          //
// Contract with cpu_wrapper.v:                                             //
//  - all outputs are registered and change only on clkena_in edges         //
//  - busstate: 00 fetch, 01 idle, 10 data read, 11 data write              //
//  - one stable bus request at a time; exactly one qualified completion    //
//    (clkena_in pulse) advances one 16-bit sub-cycle                       //
//  - split transfers insert a sampled IDLE cycle between sub-cycles (Game  //
//    Bub port: not after one on the RAM port, see present).  The          //
//    Minimig RAM/cache controllers return a level acknowledge and do not   //
//    accept a new address until their chip-select drops.                   //
//  - nwr is 1 for read, 0 for write; nuds/nlds are active low              //
//                                                                          //
// Transaction splitting (big endian):                                      //
//  - byte: one cycle, UDS for even address, LDS for odd address            //
//  - word: one cycle when even; byte + byte when odd                       //
//  - long: two word cycles when even; byte + word + byte when odd          //
//                                                                          //
// Game Bub port: the long word in one transfer, as the TG68K's long_cand / //
// long_ack: an aligned long offers long_cand (with data_write_lo, the low  //
// word to write) on its first sub-cycle; completed with long_ack, both     //
// words have moved (data_in_hi, data_in on a read) and the transfer ends;  //
// completed without it, the first word has, and the second follows as     //
// before.                                                                  //
// Game Bub port: a line (mem_line, 16 bytes: mem_wline / mem_rline, long  //
// word 0 in bits 127:96) is one request: its four long words run here     //
// back to back from the one at mem_addr[3:2], wrapping in the line, each  //
// as a long word above, and mem_ack comes with the last.  A line read     //
// offers line_cand with its first sub-cycle: completed with line_ack,    //
// the RAM port has answered the whole line (data_in_line) and it ends.   //
//                                                                          //
// Core handshake: mem_req is held by the core until mem_ack. mem_ack is a  //
// single-cycle pulse asserted in the same cycle busstate returns to idle,  //
// with mem_rdata valid. The core must drop mem_req in the ack cycle.       //
//--------------------------------------------------------------------------//

// ---- inlined from ap040_defs.svh (tools/import_ap68040.py) ----
//--------------------------------------------------------------------------//
// AP040 - MC68040 compatible CPU                                           //
//                                                                          //
// ap040_defs.svh - common constants shared by all AP040 modules            //
//                                                                          //
// Encodings below follow the existing Minimig cpu_wrapper contract         //
// (TG68K style busstate) and the MC68040 architectural values.             //
//--------------------------------------------------------------------------//

`ifndef AP040_DEFS_SVH
`define AP040_DEFS_SVH

// External bus state, identical to the TG68K/cpu_wrapper contract:
// 0: fetch code, 1: no memaccess, 2: read data, 3: write data
`define AP040_BUS_FETCH   2'b00
`define AP040_BUS_IDLE    2'b01
`define AP040_BUS_READ    2'b10
`define AP040_BUS_WRITE   2'b11

// Internal transfer sizes
`define AP040_SZ_B        2'd0
`define AP040_SZ_W        2'd1
`define AP040_SZ_L        2'd2

// Function codes
`define AP040_FC_USER_DATA   3'd1
`define AP040_FC_USER_PROG   3'd2
`define AP040_FC_SUPER_DATA  3'd5
`define AP040_FC_SUPER_PROG  3'd6
`define AP040_FC_CPU_SPACE   3'd7

// Reset vector locations (VBR does not apply to the reset vectors)
`define AP040_VEC_RESET_ISP  32'h0000_0000
`define AP040_VEC_RESET_PC   32'h0000_0004

// SR bit positions
`define AP040_SR_C   0
`define AP040_SR_V   1
`define AP040_SR_Z   2
`define AP040_SR_N   3
`define AP040_SR_X   4
`define AP040_SR_M   12
`define AP040_SR_S   13
`define AP040_SR_T0  14
`define AP040_SR_T1  15

// SR after reset: T=0, S=1, M=0, IPL=7
`define AP040_SR_RESET  16'h2700

// MC68040 CACR bits
`define AP040_CACR_IE   15
`define AP040_CACR_DE   31

// exception vector numbers
`define AP040_VEC_BUSERR   8'd2
`define AP040_VEC_ADDRERR  8'd3
`define AP040_VEC_ILLEGAL  8'd4
`define AP040_VEC_DIVZERO  8'd5
`define AP040_VEC_CHK      8'd6
`define AP040_VEC_TRAPCC   8'd7
`define AP040_VEC_PRIV     8'd8
`define AP040_VEC_TRACE    8'd9
`define AP040_VEC_ALINE    8'd10
`define AP040_VEC_FLINE    8'd11
`define AP040_VEC_FMTERR   8'd14
`define AP040_VEC_AUTOVEC  8'd24   // + interrupt level
`define AP040_VEC_TRAP     8'd32   // + trap number
`define AP040_VEC_FP_BSUN  8'd48
`define AP040_VEC_FP_INEX  8'd49
`define AP040_VEC_FP_DZ    8'd50
`define AP040_VEC_FP_UNFL  8'd51
`define AP040_VEC_FP_OPERR 8'd52
`define AP040_VEC_FP_OVFL  8'd53
`define AP040_VEC_FP_SNAN  8'd54
`define AP040_VEC_FP_UNSUP 8'd55   // unsupported data type (format $0/$3)

// SR write mask on MC68040: T1 T0 S M IPL2:0 XNZVC
`define AP040_SR_MASK   16'hF71F
`define AP040_CCR_MASK  16'h001F

// ALU operations
`define AP040_ALU_MOVE   6'd0
`define AP040_ALU_ADD    6'd1
`define AP040_ALU_ADDX   6'd2
`define AP040_ALU_SUB    6'd3
`define AP040_ALU_SUBX   6'd4
`define AP040_ALU_CMP    6'd5
`define AP040_ALU_AND    6'd6
`define AP040_ALU_OR     6'd7
`define AP040_ALU_EOR    6'd8
`define AP040_ALU_NOT    6'd9
`define AP040_ALU_NEG    6'd10
`define AP040_ALU_NEGX   6'd11
`define AP040_ALU_CLR    6'd12
`define AP040_ALU_TST    6'd13
`define AP040_ALU_EXT    6'd14
`define AP040_ALU_EXTB   6'd15
`define AP040_ALU_SWAP   6'd16
`define AP040_ALU_TAS    6'd17
`define AP040_ALU_ABCD   6'd18
`define AP040_ALU_SBCD   6'd19
`define AP040_ALU_NBCD   6'd20
`define AP040_ALU_ASL1   6'd21
`define AP040_ALU_ASR1   6'd22
`define AP040_ALU_LSL1   6'd23
`define AP040_ALU_LSR1   6'd24
`define AP040_ALU_ROL1   6'd25
`define AP040_ALU_ROR1   6'd26
`define AP040_ALU_ROXL1  6'd27
`define AP040_ALU_ROXR1  6'd28
`define AP040_ALU_BTST   6'd29
`define AP040_ALU_BCHG   6'd30
`define AP040_ALU_BCLR   6'd31
`define AP040_ALU_BSET   6'd32

`endif // AP040_DEFS_SVH
// ---- end of ap040_defs.svh ----

module ap040_bus16_adapter
(
	input             clk,
	input             nreset,
	input             clkena_in,

	// core side
	input             mem_req,
	input             mem_berr,     // abort the active external sub-cycle
	input             mem_write,
	input             mem_instr,
	input       [1:0] mem_size,     // AP040_SZ_B/W/L
	input      [31:0] mem_addr,
	input      [31:0] mem_wdata,    // right-aligned by size
	input       [2:0] mem_fc,
	output reg        mem_ack,
	output reg [31:0] mem_rdata,    // right-aligned by size, valid at mem_ack
	input             mem_line,     // a line: four long words (Game Bub port)
	input     [127:0] mem_wline,    // held with mem_req
	output reg [127:0] mem_rline,   // valid at mem_ack

	// external bus side (TG68K-like)
	input      [15:0] data_in,
	output reg [31:0] addr_out,
	output reg [15:0] data_write,
	output reg        nwr,
	output reg        nuds,
	output reg        nlds,
	output reg  [1:0] busstate,
	output reg        longword,
	output reg  [2:0] fc,
	output reg        long_cand,
	output reg [15:0] data_write_lo,
	input             long_ack,
	input      [15:0] data_in_hi,
	input             ram_port,     // the sub-cycle is on the RAM port (no IDLE needed after it)
	output reg        line_cand,    // a line read's first sub-cycle: the line may come whole
	input             line_ack,     // with the completion: it did (data_in_line)
	input     [127:0] data_in_line  // long word 0 in 127:96
);

reg        active;
reg        write_r;
reg        instr_r;
reg        subcycle_gap;
reg [31:0] cur_addr;
reg  [2:0] bytes_left;
reg [31:0] wshift;      // write data, left-aligned, consumed MSB first
reg [31:0] rshift;      // read data, assembled by shifting bytes in
reg        line_r;      // the request is a line
reg  [1:0] l_k;         // its long words done
reg  [1:0] l_i;         // the long word in progress (A3:A2)
reg        l_gap;       // the gap before a line's next long word

function [31:0] lw(input [127:0] l, input [1:0] i);
	lw = l[127 - 32 * i -: 32];
endfunction

// number of operand bytes for a request
function [2:0] size_bytes;
	input [1:0] size;
	begin
		case (size)
			`AP040_SZ_B: size_bytes = 3'd1;
			`AP040_SZ_W: size_bytes = 3'd2;
			default:     size_bytes = 3'd4;
		endcase
	end
endfunction

// current in-flight sub-cycle consumes this many bytes
wire [2:0] consumed  = cur_addr[0] ? 3'd1 : (bytes_left >= 3'd2) ? 3'd2 : 3'd1;
wire [31:0] next_addr = cur_addr + {29'd0, consumed};
wire  [2:0] next_left = bytes_left - consumed;
wire [31:0] next_wsh  = (consumed == 3'd2) ? {wshift[15:0], 16'd0} : {wshift[23:0], 8'd0};

// first sub-cycle shape of a new request
wire  [2:0] f_bytes = mem_line ? 3'd4 : size_bytes(mem_size);
wire [31:0] f_addr  = mem_line ? {mem_addr[31:2], 2'b00} : mem_addr;
wire [31:0] f_wd    = mem_line ? lw(mem_wline, mem_addr[3:2]) : mem_wdata;
wire [31:0] f_wsh   = mem_line ? f_wd :
                      (mem_size == `AP040_SZ_B) ? {mem_wdata[7:0], 24'd0} :
                      (mem_size == `AP040_SZ_W) ? {mem_wdata[15:0], 16'd0} :
                                                  mem_wdata;
wire        f_odd  = f_addr[0];
// the long word of a line after l_i
wire  [1:0] l_n    = l_i + 2'd1;
wire [31:0] l_addr = {cur_addr[31:4], l_n, 2'b00};
// the read data of the sub-cycle completing now (the last of its transfer)
wire [31:0] rd_last = cur_addr[0]             ? {rshift[23:0], data_in[7:0]} :
                      (bytes_left >= 3'd2)    ? {rshift[15:0], data_in[15:0]} :
                                                {rshift[23:0], data_in[15:8]};
wire        f_word = !f_odd && (f_bytes >= 3'd2);

// Game Bub port: after a sub-cycle on the RAM port (ram_port) the next one
// (or a line's next long word) is presented on the edge that completes it,
// as the TG68K presents its next bus cycle: the RAM port lowers its chip
// select for a controller clock at that edge (minimig_gamebub.sv: ram_cs
// with cyc), so cpu_cache_new and the write buffer see the transfer end
// before the new address. Elsewhere (the chip bus: Kickstart 1.3 does not
// boot without it) the sampled IDLE cycle stays (advance, below).
task present(input [31:0] a, input [2:0] left, input [31:0] wsh, input lc);
	begin
		busstate   <= instr_r ? `AP040_BUS_FETCH :
		              write_r ? `AP040_BUS_WRITE : `AP040_BUS_READ;
		nwr        <= ~write_r;
		nuds       <= a[0];
		nlds       <= !a[0] && !(left >= 3'd2);
		data_write <= (a[0] || left < 3'd2) ? {wsh[31:24], wsh[31:24]} : wsh[31:16];
		long_cand  <= lc;
		subcycle_gap <= 0;
		l_gap      <= 0;
	end
endtask

// the next sub-cycle: at once on the RAM port, else after a sampled IDLE
task advance(input [31:0] a, input [2:0] left, input [31:0] wsh, input lc);
	begin
		if (ram_port) present(a, left, wsh, lc);
		else begin
			busstate   <= `AP040_BUS_IDLE;
			nwr        <= 1;
			nuds       <= 1;
			nlds       <= 1;
			long_cand  <= 0;
			l_gap      <= lc;
			subcycle_gap <= 1;
		end
	end
endtask

always @(posedge clk) begin
	if (!nreset) begin
		active     <= 0;
		mem_ack    <= 0;
		busstate   <= `AP040_BUS_IDLE;
		nwr        <= 1;
		nuds       <= 1;
		nlds       <= 1;
		longword   <= 0;
		write_r    <= 0;
		instr_r    <= 0;
		subcycle_gap <= 0;
		bytes_left <= 0;
		addr_out   <= 0;
		data_write <= 0;
		fc         <= 0;
		cur_addr   <= 0;
		wshift     <= 0;
		rshift     <= 0;
		mem_rdata  <= 0;
		long_cand  <= 0;
		line_cand  <= 0;
		data_write_lo <= 0;
		line_r     <= 0;
		l_k        <= 0;
		l_i        <= 0;
		l_gap      <= 0;
		mem_rline  <= 0;
	end
	else if (clkena_in) begin
		mem_ack <= 0;

		if (active && mem_berr) begin
			// A physical bus error completes neither the current 16-bit
			// sub-cycle nor the enclosing core transaction.  The core samples
			// berr on this same qualified edge and builds the format-$7 frame;
			// release the TG68K request here so a subsequent exception-vector
			// fetch cannot inherit the failed cycle.
			active   <= 0;
			busstate <= `AP040_BUS_IDLE;
			nwr      <= 1;
			nuds     <= 1;
			nlds     <= 1;
			longword <= 0;
			long_cand <= 0;
			line_cand <= 0;
			subcycle_gap <= 0;
			line_r   <= 0;
		end
		else if (!active) begin
			// idle: busstate is 01, so the wrapper keeps clkena high
			if (mem_req && !mem_ack) begin
				active     <= 1;
				write_r    <= mem_write;
				instr_r    <= mem_instr;
				subcycle_gap <= 0;
				cur_addr   <= f_addr;
				bytes_left <= f_bytes;
				wshift     <= f_wsh;
				rshift     <= 0;
				fc         <= mem_fc;
				line_r     <= mem_line;
				l_k        <= 0;
				l_i        <= mem_addr[3:2];
				longword   <= mem_line || (mem_size == `AP040_SZ_L);
				long_cand  <= mem_line || (mem_size == `AP040_SZ_L) && (mem_addr[1:0] == 2'b00);
				line_cand  <= mem_line && !mem_write;
				data_write_lo <= f_wd[15:0];
				busstate   <= mem_instr ? `AP040_BUS_FETCH :
				              mem_write ? `AP040_BUS_WRITE : `AP040_BUS_READ;
				nwr        <= ~mem_write;
				addr_out   <= f_addr;
				nuds       <= f_odd;
				nlds       <= !f_odd && !f_word;
				data_write <= (f_odd || !f_word) ? {f_wsh[31:24], f_wsh[31:24]}
				                                 : f_wsh[31:16];
			end
		end
		else if (subcycle_gap) begin
			// The external target sampled IDLE on this edge and can now
			// accept the next word of the same internal transfer.  Reassert
			// the saved request without consuming data on the boundary edge.
			subcycle_gap <= 0;
			long_cand  <= l_gap;      // a line's next long word: offered whole
			l_gap      <= 0;
			busstate   <= instr_r ? `AP040_BUS_FETCH :
			              write_r ? `AP040_BUS_WRITE : `AP040_BUS_READ;
			nwr        <= ~write_r;
			nuds       <= cur_addr[0];
			nlds       <= !cur_addr[0] && !(bytes_left >= 3'd2);
			data_write <= (cur_addr[0] || bytes_left < 3'd2)
			              ? {wshift[31:24], wshift[31:24]}
			              : wshift[31:16];
		end
		else if (line_cand && line_ack) begin
			// the whole line in one transfer
			mem_rline <= data_in_line;
			active    <= 0;
			busstate  <= `AP040_BUS_IDLE;
			nwr       <= 1;
			nuds      <= 1;
			nlds      <= 1;
			longword  <= 0;
			long_cand <= 0;
			line_cand <= 0;
			line_r    <= 0;
			subcycle_gap <= 0;
			mem_ack   <= 1;
		end
		else if (long_cand && long_ack) begin
			// the long word in one transfer
			long_cand <= 0;
			line_cand <= 0;
			if (!write_r) mem_rline[127 - 32 * l_i -: 32] <= {data_in_hi, data_in};
			if (line_r && l_k != 2'd3) begin
				// a line's next long word
				l_k          <= l_k + 2'd1;
				l_i          <= l_n;
				cur_addr     <= l_addr;
				addr_out     <= l_addr;
				bytes_left   <= 3'd4;
				wshift       <= lw(mem_wline, l_n);
				data_write_lo <= lw(mem_wline, l_n);
				rshift       <= 0;
				advance(l_addr, 3'd4, lw(mem_wline, l_n), 1'b1);
			end
			else begin
				// complete
				active    <= 0;
				busstate  <= `AP040_BUS_IDLE;
				nwr       <= 1;
				nuds      <= 1;
				nlds      <= 1;
				longword  <= 0;
				line_r    <= 0;
				subcycle_gap <= 0;
				mem_ack   <= 1;
				if (!write_r) mem_rdata <= {data_in_hi, data_in};
			end
		end
		else begin
			// one qualified completion for the in-flight 16-bit sub-cycle
			long_cand <= 0;
			line_cand <= 0;
			if (!write_r) begin
				if (cur_addr[0])              rshift <= {rshift[23:0], data_in[7:0]};
				else if (bytes_left >= 3'd2)  rshift <= {rshift[15:0], data_in[15:0]};
				else                          rshift <= {rshift[23:0], data_in[15:8]};
			end

			if (next_left == 3'd0 && line_r && l_k != 2'd3) begin
				// a line's long word done in two sub-cycles: its next long
				// word
				if (!write_r) mem_rline[127 - 32 * l_i -: 32] <= rd_last;
				l_k          <= l_k + 2'd1;
				l_i          <= l_n;
				cur_addr     <= l_addr;
				addr_out     <= l_addr;
				bytes_left   <= 3'd4;
				wshift       <= lw(mem_wline, l_n);
				data_write_lo <= lw(mem_wline, l_n);
				rshift       <= 0;
				advance(l_addr, 3'd4, lw(mem_wline, l_n), 1'b1);
			end
			else if (next_left == 3'd0) begin
				// transaction complete: return to idle and pulse ack
				if (!write_r && line_r) mem_rline[127 - 32 * l_i -: 32] <= rd_last;
				line_r   <= 0;
				active   <= 0;
				busstate <= `AP040_BUS_IDLE;
				nwr      <= 1;
				nuds     <= 1;
				nlds     <= 1;
				longword <= 0;
				subcycle_gap <= 0;
				mem_ack  <= 1;
				if (!write_r) begin
					if (cur_addr[0])             mem_rdata <= {rshift[23:0], data_in[7:0]};
					else if (bytes_left >= 3'd2) mem_rdata <= {rshift[15:0], data_in[15:0]};
					else                         mem_rdata <= {rshift[23:0], data_in[15:8]};
				end
			end
			else begin
				// the following sub-cycle (see present, advance)
				cur_addr   <= next_addr;
				bytes_left <= next_left;
				wshift     <= next_wsh;
				addr_out   <= next_addr;
				advance(next_addr, next_left, next_wsh, 1'b0);
			end
		end
	end
end

endmodule
