//--------------------------------------------------------------------------//
// ap68040_minimig.sv - the AP68040 on the Minimig's 16-bit bus              //
//                                                                          //
// The core presents the real 68040 bus (rtl/ap68040/ap68040.sv); this     //
// module is its only slave.  Every transfer becomes one request to         //
// ap040_bus16_adapter, which lives in the system clock domain and runs    //
// the request as 16-bit sub-cycles on the Minimig's chip, fast-chip and   //
// RAM ports under the contract those ports were built around.  The two    //
// clocks come from one PLL with aligned edges (clk is twice the system    //
// clock), so the request and the acknowledge cross as plain registered    //
// signals that the fitter times like any other path.                      //
//                                                                          //
//  * Game Bub port: a line transfer is a burst (TBI negated) and one     //
//    request (mem_line, 16 bytes): a read's four beats are answered on    //
//    four bus clocks running once the adapter has the line, from the long //
//    word asked for on, wrapping in the line (7.4.2); a write's first     //
//    three beats are acknowledged at once to collect the line, the last   //
//    as the line goes to the adapter (posted, below).                    //
//  * Game Bub port: writes to the fast RAM (and lines, which are only    //
//    ever the fast RAM's) are posted: TA as the request goes, the next   //
//    transfer waiting on the bus until the adapter is done.  A bus error //
//    on a posted write is not reported (the fast RAM answers).           //
//  * TCI (MC68040UM 4.3.2) is asserted for every transfer outside the     //
//    configured Zorro II/III fast RAM and the Kickstart ROM ($F80000-     //
//    $FFFFFF, $E00000-$E7FFFF; read only to the CPU, loaded before it     //
//    starts, so never stale): only they enter the caches,                 //
//    whatever the MMU and the TTRs say (with translation off a 68040     //
//    caches everything).  Chip RAM changes under chipset DMA that nothing //
//    snoops, and old programs modify code there without flushing; device  //
//    registers, the ROM and the RTG space stay out too.  A TCI line is   //
//    never allocated, in either cache, so nothing of them is ever hit.   //
//  * Game Bub port: chip RAM's code is let into the instruction cache     //
//    (no TCI for a code access below 2 MB while chipcode says the fetches //
//    there are the RAM's own: without it every long word of chip RAM code //
//    is a line transfer, 5.7.1), and what the bus does not show the       //
//    processor as another master's write is told to it here: the core's   //
//    xinv port takes a line out of the instruction cache as a snooped     //
//    write does, with the refetch of what the front end had run ahead     //
//    into.  Two sources: the processor's own write transfers to chip RAM  //
//    (as they start) and every write the SDRAM controller makes there     //
//    (cw_tgl / cw_line: the chipset's DMA, and the processor's again as   //
//    it lands).  Only writes into a 128-byte block that has given the     //
//    cache a line are passed on (cmap), through a queue of eight; if that //
//    should ever overflow every line goes.  The core lets a line fill end //
//    before it invalidates, so a write that met the fill takes the line   //
//    out after it; the map and the queue are kept over a reset, as the    //
//    cache's lines are.  Data accesses to chip RAM stay inhibited.        //
//  * Game Bub port: a cartridge's code (ar_on: one is fitted; HRTmon's   //
//    512 KB at $A00000, the Action Replay's ROM at $A80000-$ABFFFF) is    //
//    let into the instruction cache too: nothing but the processor       //
//    writes there, a real 68040 caches a cartridge the same, and its      //
//    code would crawl uncached (a line transfer a long word).  Every      //
//    line goes at a reset (the image is uploaded again with the           //
//    processor halted).  The Action Replay hides at the first             //
//    instruction fetched outside it after its control register            //
//    ($A80000-$A80003) is written, and a fetch the instruction cache      //
//    answers is not on the bus: that write takes every line out of the    //
//    cache too, so the first instruction outside is fetched.              //
//  * An interrupt acknowledge (TT = 3) is answered with AVEC, as the       //
//    Amiga autovectors every level; a level-7 acknowledge flips           //
//    nmi_ack_toggle for the cartridge monitor.  A breakpoint acknowledge  //
//    is answered with TA, which makes BKPT an illegal instruction.        //
//  * The bus watchdog's berr ends the transfer in progress with TEA, a    //
//    bus error; a transfer that starts while berr is still being          //
//    withdrawn waits for it to clear.                                     //
//  * Byte and word write data come from the 68040's byte lanes (table     //
//    7-1); read data is replicated on every lane of its size, so the      //
//    core's own lane select finds it wherever it looks.                   //
//  * BG is held asserted and there is no other master: no snooping and no //
//    arbitration.  A locked sequence needs nothing: this slave runs one   //
//    transfer at a time.                                                  //
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

module ap68040_minimig
#(
	parameter logic [7:0] FPU_REVISION = 8'h41,
	parameter bit         FPU_PIPE     = 0,
	parameter bit         LOOP_PRED    = 0,
	parameter bit         EARLY_RES    = 0,
	parameter bit         DC1_ATC      = 1,      // DC1's own ATC port: the engine's stolen lookup off DC1's critical path (+200 ALMs)
	parameter bit         SKID         = 0,
	parameter int         DIV_STEPS    = 2
)
(
	input  logic        clk,            // the processor clock
	input  logic        nreset,

	// the cacheable window: the configured Zorro II/III fast RAM (from the
	// wrapper's autoconfig; changes only while the machine configures)
	input  logic        z2ram_ena,
	input  logic  [7:0] z3ram_base0,    // 32 MB board, base in 16 MB units (Game Bub port)
	input  logic        z3ram_ena0,
	input  logic  [3:0] z3ram_base1,    // 256 MB block
	input  logic        z3ram_ena1,

	// the 16-bit bus adapter (system clock domain, see above)
	output logic        mem_req,        // level, until mem_ack or mem_berr
	output logic        mem_write,
	output logic        mem_instr,
	output logic  [1:0] mem_size,       // AP040_SZ_B/W/L
	output logic [31:0] mem_addr,
	output logic [31:0] mem_wdata,      // right-aligned by size
	output logic  [2:0] mem_tm,         // the transfer's TM2-TM0
	output logic        mem_ci,         // cache inhibited (CIOUT)
	output logic        mem_line,       // a line: 16 bytes (Game Bub port)
	output logic [127:0] mem_wline,     // a line's write data, long word 0 in 127:96
	input  logic        mem_ack,        // one system clock: mem_rdata valid
	input  logic [31:0] mem_rdata,      // right-aligned by size
	input  logic [127:0] mem_rline,     // a line's read data
	input  logic        mem_berr,       // level: the bus watchdog

	// Game Bub port: chip RAM's code in the instruction cache (see above)
	input  logic        chipcode,       // fetches from chip RAM are the RAM's (cpu_wrapper: no overlay)
	input  logic        cw_tgl,         // flips for every write to chip RAM (the SDRAM controller's
	input  logic [20:4] cw_line,        // ... clock: twice this one, edges aligned), its line held
	input  logic        ar_on,          // a cartridge is fitted: its code is cached; a write of the Action Replay's control register empties the instruction cache

	input  logic  [2:0] ipl_n,          // IPL2-IPL0, active low as the pins are
	output logic        nmi_ack_toggle, // flips for every level-7 acknowledge

	output logic        nresetout,      // RSTO: the RESET instruction
	output logic [31:0] cacr_out,
	output logic [31:0] vbr_out,
	output logic        cache_maint_toggle, // flips for every completed CINV/CPUSH
	output logic        debug_halted,
	output logic [31:0] debug_pc
);

//--------------------------------------------------------------------------
// the core
//--------------------------------------------------------------------------
logic [31:0] a_o, d_o, d_i;
logic        ts_n, rw_n, ciout_n, ta_n, tea_n, tci_n, rsto_n, cmaint;
logic        xr = 1'b0, xr_all = 1'b0, xdone;   // the instruction cache invalidation request (below)
logic [20:4] xr_line;
logic  [1:0] siz, tt;
logic  [2:0] tm;

ap68040 #(
	.FPU_REVISION(FPU_REVISION), .FPU_PIPE(FPU_PIPE), .LOOP_PRED(LOOP_PRED),
	.EARLY_RES(EARLY_RES), .DC1_ATC(DC1_ATC), .SKID(SKID), .DIV_STEPS(DIV_STEPS)
) core (
	.clk(clk), .bclk_en(1'b1), .rsti_n(nreset),
	.a_o(a_o), .a_oe(),
	// no other master: nothing to snoop
	.a_i(32'd0), .ts_n_i(1'b1), .rw_n_i(1'b1), .siz_i(2'd0), .tt_i(2'd0), .sc(2'd0),
	.mi_n(), .ta_n_o(), .ta_oe(),
	.d_i(d_i), .d_o(d_o), .d_oe(),
	.rw_n(rw_n), .siz(siz), .tt(tt), .tm(tm), .tln(), .upa(),
	.ciout_n(ciout_n), .lock_n(), .locke_n(),
	.ts_n(ts_n), .tip_n(), .ta_n(ta_n), .tea_n(tea_n),
	.tci_n(tci_n), .tbi_n(1'b1),
	.xinv_req(xr), .xinv_pa({11'd0, xr_line, 4'd0}), .xinv_all(xr_all), .xinv_done(xdone),
	.ipl_n(ipl_n), .avec_n(1'b0),
	.br_n(), .bg_n(1'b0), .bb_n_i(1'b1), .bb_n_o(), .bb_oe(),
	.rsto_n(rsto_n), .cdis_n(1'b1), .mdis_n(1'b1), .ipend_n(), .pst(),
	.dbg_pc(debug_pc), .dbg_retire(), .dbg_halted(debug_halted)
);
// Game Bub port: AP68040 main has no VBR / CACR / cache maintenance
// outputs (the MiSTer copy's local additions): the NMI vector is taken at
// VBR 0 and the controller has no cache of its own to keep in step
assign vbr_out  = 32'd0;
assign cacr_out = 32'd0;
assign cmaint   = 1'b0;

assign nresetout = rsto_n;

always_ff @(posedge clk) begin
	if (!nreset)     cache_maint_toggle <= 1'b0;
	else if (cmaint) cache_maint_toggle <= ~cache_maint_toggle;
end

//--------------------------------------------------------------------------
// the transfer to request conversion
//--------------------------------------------------------------------------
// write data by byte lane (MC68040UM table 7-1), right-aligned for the adapter
function automatic logic [31:0] wlane(input logic [1:0] s, input logic [1:0] a, input logic [31:0] d);
	case (s)
		2'b01:   wlane = {24'd0, a[1] ? (a[0] ? d[7:0] : d[15:8]) : (a[0] ? d[23:16] : d[31:24])};
		2'b10:   wlane = {16'd0, a[1] ? d[15:0] : d[31:16]};
		default: wlane = d;
	endcase
endfunction

// SIZ1-SIZ0 to the adapter's size (a line is its first long word)
function automatic logic [1:0] asz(input logic [1:0] s);
	case (s)
		2'b01:   asz = `AP040_SZ_B;
		2'b10:   asz = `AP040_SZ_W;
		default: asz = `AP040_SZ_L;
	endcase
endfunction

// read data on every lane of its size
function automatic logic [31:0] rlane(input logic [1:0] s, input logic [31:0] d);
	case (s)
		`AP040_SZ_B: rlane = {4{d[7:0]}};
		`AP040_SZ_W: rlane = {2{d[15:0]}};
		default:     rlane = d;
	endcase
endfunction

localparam logic [2:0] C_IDLE = 3'd0,   // waiting for TS
                       C_REQ  = 3'd1,   // the request is with the adapter
                       C_ACK  = 3'd2,   // TA or TEA driven this bus clock
                       C_BERR = 3'd3,   // the watchdog's berr being withdrawn
                       C_LRD  = 3'd4,   // a line read's beats 1-3
                       C_LWR  = 3'd5,   // a line write's beats 0-2 being collected
                       C_PREQ = 3'd6;   // a posted write with the adapter

logic [2:0] st;
logic [1:0] lbeat;      // C_LRD: the beat driven next; C_LWR: the clock of the collection
logic [1:0] la32;       // the line's first long word (A3:A2)

// Game Bub port: the request is raised in the bus clock in which TS is on
// the bus, from the bus itself (the core holds address and data until TA),
// and from the latched copies after it: an adapter clock edge in that bus
// clock takes the transfer one system clock sooner. (Not a line write: its
// beats are collected first; not while berr is being withdrawn.)
logic        req_q, write_q, instr_q, ci_q, line_q;
logic  [1:0] size_q;
logic [31:0] addr_q, wdata_q;
logic  [2:0] tm_q;
logic       pend;       // a transfer arrived while berr was being withdrawn
logic       err_ack;    // the acknowledge being driven is TEA
logic       cach;       // the transfer's address is in the cacheable window

// the configured fast RAM (as cpu_wrapper decodes it for the RAM port)
// Game Bub port: the 32 MB Zorro III board's base in 16 MB units (bit 0 is
// not compared); the Kickstart ROM cacheable too
function automatic logic fastram(input logic [31:0] a, input logic z2, input logic [7:0] b0,
                                 input logic e0, input logic [3:0] b1, input logic e1);
	fastram = ((a[31:25] == b0[7:1]) && e0) || ((a[31:28] == b1) && e1) ||
	          ((a[31:24] == 8'd0) && (a[23] ^ |a[22:21]) && z2) ||
	          ((a[31:24] == 8'd0) && ((a[23:19] == 5'b11111) || (a[23:19] == 5'b11100)));
endfunction

wire ts   = !ts_n;
wire iack = (tt == 2'd3);   // interrupt or breakpoint acknowledge
// Game Bub port: a code access to chip RAM that may enter the instruction cache
logic chipcode_q;
always_ff @(posedge clk) chipcode_q <= chipcode;
logic ar_on_q = 1'b0;
always_ff @(posedge clk) ar_on_q <= ar_on;
wire chipram = (a_o[31:21] == 11'd0);
wire chipc   = chipcode_q && chipram && rw_n && ((tm == 3'd2) || (tm == 3'd6));
// a cartridge's code: $A00000-$ABFFFF (HRTmon's memory, the Action Replay's ROM)
wire cartc   = ar_on_q && (a_o[31:20] == 12'h00A) && (a_o[19:18] != 2'b11) && rw_n && ((tm == 3'd2) || (tm == 3'd6));
wire line = (siz == 2'b11); // SIZ: a line transfer
logic pts;              // a transfer started while a posted write was in flight
wire  ts_e = ts || pts;  // (the core holds it on the bus until its TA)
wire  post = !rw_n && !line && fastram(a_o, z2ram_ena, z3ram_base0, z3ram_ena0, z3ram_base1, z3ram_ena1);
wire start_now = ts_e && !iack && (st == C_IDLE) && !mem_berr && !(line && !rw_n);

assign mem_req   = req_q || start_now;
assign mem_write = start_now ? !rw_n : write_q;
assign mem_instr = start_now ? ((tm == 3'd2) || (tm == 3'd6)) : instr_q;
assign mem_size  = start_now ? asz(siz) : size_q;
assign mem_addr  = start_now ? a_o : addr_q;
assign mem_wdata = start_now ? wlane(siz, a_o[1:0], d_o) : wdata_q;
assign mem_tm    = start_now ? tm : tm_q;
assign mem_ci    = start_now ? !ciout_n : ci_q;
assign mem_line  = start_now ? line : line_q;

function automatic logic [31:0] lword(input logic [127:0] l, input logic [1:0] i);
	lword = l[127 - 32 * i -: 32];
endfunction

always_ff @(posedge clk) begin
	ta_n  <= 1'b1;
	tea_n <= 1'b1;
	tci_n <= 1'b1;
	if (!nreset) begin
		st             <= C_IDLE;
		pend           <= 1'b0;
		err_ack        <= 1'b0;
		req_q        <= 1'b0;
		write_q      <= 1'b0;
		instr_q      <= 1'b0;
		size_q       <= 2'd0;
		addr_q       <= '0;
		wdata_q      <= '0;
		tm_q         <= '0;
		ci_q         <= 1'b0;
		line_q       <= 1'b0;
		mem_wline      <= '0;
		lbeat          <= 2'd0;
		la32           <= 2'd0;
		cach           <= 1'b0;
		pts            <= 1'b0;
		d_i            <= '0;
		nmi_ack_toggle <= 1'b0;
	end
	else begin
		// every memory transfer is latched as it starts (TS lasts one bus
		// clock); the core holds the address and data until TA
		if (ts_e && !iack && st != C_PREQ) begin
			write_q <= !rw_n;
			instr_q <= (tm == 3'd2) || (tm == 3'd6);   // user, supervisor code
			size_q  <= asz(siz);
			addr_q  <= a_o;
			wdata_q <= wlane(siz, a_o[1:0], d_o);
			tm_q    <= tm;
			ci_q    <= !ciout_n;
			line_q  <= line;
			la32      <= a_o[3:2];
			// a line write's first beat (the rest as their TAs go)
			mem_wline[127 - 32 * a_o[3:2] -: 32] <= d_o;
			cach      <= fastram(a_o, z2ram_ena, z3ram_base0, z3ram_ena0, z3ram_base1, z3ram_ena1) || chipc || cartc;
		end
		// an acknowledge cycle is answered at once, in any state
		if (ts && iack) begin
			ta_n <= 1'b0;
			d_i  <= '0;
			if (tm == 3'd7) nmi_ack_toggle <= ~nmi_ack_toggle;
		end

		case (st)
		C_IDLE: begin
			if (ts_e && !iack) begin
				pts <= 1'b0;
				if (mem_berr) begin
					pend <= 1'b1;
					st   <= C_BERR;
				end
				else if (post) begin
					// a write to the fast RAM: TA now, the write behind it
					ta_n  <= 1'b0;
					req_q <= 1'b1;
					st    <= C_PREQ;
				end
				else if (line && !rw_n) begin
					// a line write: beat 0's TA now
					ta_n  <= 1'b0;
					lbeat <= 2'd1;
					st    <= C_LWR;
				end
				else begin
					req_q <= 1'b1;
					st      <= C_REQ;
				end
			end
		end

		C_LWR: begin
			// beats 1 and 2 acknowledged on the next clocks; each beat's data is
			// on the bus from the clock after the core took the previous TA
			lbeat <= lbeat + 2'd1;
			if (lbeat == 2'd1) ta_n <= 1'b0;                        // beat 1
			if (lbeat == 2'd2) begin
				ta_n <= 1'b0;                                          // beat 2
				mem_wline[127 - 32 * (la32 + 2'd1) -: 32] <= d_o;
			end
			if (lbeat == 2'd3) mem_wline[127 - 32 * (la32 + 2'd2) -: 32] <= d_o;
			if (lbeat == 2'd0) begin
				// beat 3's data: the line goes, posted (beat 3's TA now)
				mem_wline[127 - 32 * (la32 + 2'd3) -: 32] <= d_o;
				ta_n  <= 1'b0;
				req_q <= 1'b1;
				st    <= C_PREQ;
			end
		end

		C_REQ: begin
			if (mem_ack) begin
				req_q <= 1'b0;
				d_i     <= line_q ? lword(mem_rline, la32) : rlane(size_q, mem_rdata);
				ta_n    <= 1'b0;
				tci_n   <= cach;      // sampled with the first TA of a line
				err_ack <= 1'b0;
				lbeat   <= 2'd1;
				st      <= (line_q && !write_q) ? C_LRD : C_ACK;
			end
			else if (mem_berr) begin
				req_q <= 1'b0;
				tea_n   <= 1'b0;
				err_ack <= 1'b1;
				st      <= C_ACK;
			end
		end

		C_LRD: begin
			// a line read's beats 1-3, a bus clock each
			d_i   <= lword(mem_rline, la32 + lbeat);
			ta_n  <= 1'b0;
			lbeat <= lbeat + 2'd1;
			if (lbeat == 2'd3) st <= C_ACK;
		end

		C_PREQ: begin
			// the posted write with the adapter; a transfer starting now
			// waits (on the bus) until it is done
			if (ts && !iack) pts <= 1'b1;
			if (mem_ack) begin
				req_q <= 1'b0;
				st    <= C_IDLE;
			end
			else if (mem_berr) begin
				// lost: nothing waits for it. A transfer waiting on the bus
				// (pts) starts from C_IDLE once berr is withdrawn
				req_q <= 1'b0;
				st    <= C_BERR;
			end
		end

		C_ACK: st <= err_ack ? C_BERR : C_IDLE;

		C_BERR: begin
			// the watchdog clears berr once the adapter has dropped the
			// request; a transfer that started meanwhile goes then
			if (ts && !iack) pend <= 1'b1;
			if (!mem_berr && pts) st <= C_IDLE;   // (latched and started there)
			else if (!mem_berr) begin
				if (pend || (ts && !iack)) begin
					pend <= 1'b0;
					// (a transfer starting on this clock is latched on it: its
					// own SIZ and R/W, not yet line_q / write_q)
					if (pend ? (line_q && write_q) : (line && !rw_n)) begin
						ta_n  <= 1'b0;
						lbeat <= 2'd1;
						st    <= C_LWR;
					end
					else begin
						req_q <= 1'b1;
						st      <= C_REQ;
					end
				end
				else st <= C_IDLE;
			end
		end

		default: st <= C_IDLE;
		endcase
	end
end

//--------------------------------------------------------------------------
// Game Bub port: writes to chip RAM's code, to the instruction cache
//--------------------------------------------------------------------------
// the 128-byte blocks of chip RAM that have given the instruction cache a
// line (never cleared: the cache keeps its lines over a reset too)
(* ram_style = "block" *) reg cmap [0:16383];
initial for (int i = 0; i < 16384; i++) cmap[i] = 1'b0;
reg          cmap_q;
wire  [13:0] cmap_ra;
wire         cmap_set = ts_e && !iack && (st != C_PREQ) && chipc;   // (as the transfer is latched)
always @(posedge clk) begin
	if (cmap_set) cmap[a_o[20:7]] <= 1'b1;
	cmap_q <= cmap[cmap_ra];
end

logic        cw_s1 = 1'b0, cw_s2 = 1'b0;   // cw_tgl in this clock
logic        eb_p = 1'b0;                  // a write by the SDRAM controller, to be looked up
logic [20:4] eb_l;
logic        ea_p = 1'b0;                  // the processor's own write transfer
logic [20:4] ea_l;
logic        lk_v = 1'b0;                  // looked up: cmap_q is its block's bit
logic [20:4] lk_l;
logic [20:4] xq [0:7];                     // the lines to invalidate
logic  [2:0] xq_h = 3'd0, xq_t = 3'd0;
logic  [3:0] xq_n = 4'd0;
logic        x_ov = 1'b0;                  // one was lost: every line goes

wire cw_evt = (cw_s1 != cw_s2);
wire ea_evt = ts && !iack && !rw_n && chipram;
wire ar_ctlw = ts && !iack && !rw_n && ar_on_q && (a_o[31:2] == 30'h002A0000);   // $A80000-$A80003
wire lk_b   = eb_p;                        // the controller's first (it cannot wait)
wire lk_a   = ea_p && !eb_p;
assign cmap_ra = lk_b ? eb_l[20:7] : ea_l[20:7];
wire xq_pop  = xr && !xr_all && xdone;
wire xq_push = lk_v && cmap_q && (xq_n != 4'd8 || xq_pop);
assign xr_line = xq[xq_h];

always_ff @(posedge clk) begin
	cw_s1 <= cw_tgl;
	cw_s2 <= cw_s1;

	// the request to the core: every line if one was lost, else the queue's head
	if (!xr) begin
		if (x_ov)               begin xr <= 1'b1; xr_all <= 1'b1; end
		else if (xq_n != 4'd0)  begin xr <= 1'b1; xr_all <= 1'b0; end
	end
	else if (xdone) begin
		xr <= 1'b0;
		if (xr_all) x_ov <= 1'b0;
	end

	// a write waits a clock or two for its look-up; the next comes no sooner
	// (a window of the controller, a bus transfer), or the processor's
	// counts as lost
	if (cw_evt) begin
		eb_p <= 1'b1;            // (one pending is looked up in this clock)
		eb_l <= cw_line;
	end
	else if (lk_b) eb_p <= 1'b0;
	if (ea_evt) begin
		if (ea_p && !lk_a) x_ov <= 1'b1;
		ea_p <= 1'b1;
		ea_l <= a_o[20:4];
	end
	else if (lk_a) ea_p <= 1'b0;
	lk_v <= lk_b || lk_a;
	lk_l <= lk_b ? eb_l : ea_l;

	// the queue
	if (lk_v && cmap_q && !xq_push) x_ov <= 1'b1;
	if (xq_push) begin
		xq[xq_t] <= lk_l;
		xq_t     <= xq_t + 3'd1;
	end
	if (xq_pop) xq_h <= xq_h + 3'd1;
	xq_n <= xq_n + {3'd0, xq_push} - {3'd0, xq_pop};

	// the Action Replay's control register written, or a reset (a
	// cartridge's image may be uploaded anew): every line goes
	if (ar_ctlw || !nreset) x_ov <= 1'b1;
end

endmodule
