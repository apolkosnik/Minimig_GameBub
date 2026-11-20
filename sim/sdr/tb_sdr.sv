// Directed random test of gb_sdram_ctrl (with its cpu_cache_new) and the
// two SDRAM chip models (sim/rtl/sdram_sim.sv): every port at once.
//
// - chipset: one random access per two windows (as the Amiga's chip bus at
//   most), read, write, 32 bit read or write, inputs changing at a clk_sys
//   edge (the start of state 15) like Agnus's;
// - CPU: random word reads and writes (byte masks too) to chip 0 and chip 1
//   RAM through the cache, inputs changing at clk_sys edges, with the
//   cache on or off (+cache); long words offered in one transfer
//   (cpuLong1, as cpu_wrapper's ramlong1): taken whole (ramready_l) both
//   words are written / checked, otherwise the first word only, as the
//   TG68K continues with the second as a word of its own. Built with
//   -DLINE16 (a build variant's tree with its own cpu_cache_new, run_sdr.sh)
//   the controller reads the CPU's 16-byte lines from chip 1 (CPU_LINE16)
//   and line reads (cpuLine, as the AP68040's bus adapter) answered whole
//   are checked in all eight words,
//   and with -DWQN_N=n queues n CPU writes (WQN), the reads after them
//   checked against the writes still queued; and (as on the hardware, where
//   the CPU's select reaches the controller over a two-cycle path) the
//   select sometimes still up for one controller clock after a transfer
//   ends, the next transfer's write state and another address already
//   there: nothing may be written from it;
// - host: random word reads and writes to chip 0;
// - burst port: random 8 word reads of chip 1, held until taken, with
//   burstUrgent at random.
// Each port has its own address region. A shadow copy of both memories
// gives the expected value of every word read; the SDRAM models check the
// command protocol and timing, the bench the data bus between the chips
// and the FPGA (one driver per SDRAM clock edge, an idle edge between
// different drivers), as tb_top does.
// SPDX-License-Identifier: GPL-3.0-or-later

`timescale 1ns/1ps

module tb_sdr;

reg clk_114 = 0, clk_28 = 0, mmcm_locked = 1;   // (xilinx_sim.sv's TB_TOP)
always #4.4 clk_114 = ~clk_114;

integer seed = 1;
int unsigned seed_junk;
integer windows_run = 4000;
bit     cache_on = 0;
integer fails = 0;

// c_7m: rises every 16 clk_114 cycles (the controller's state 0 starts two
// cycles after the edge that sees it)
reg [3:0] ph = 0;
reg c_7m = 0;
always @(posedge clk_114) begin
	ph   <= ph + 1'd1;
	c_7m <= (ph >= 4'd7) && (ph < 4'd15);
end

reg reset_n = 0;

// the controller's window state, kept here as the controller keeps it (from
// c_7m): the stimulus is timed by it, on the netlist too (GLS:
// sim/gls/run_sdr_gls.sh), where the controller's own is not to be found
reg [3:0] win_state = 0;
reg       win_old7 = 0;
always @(posedge clk_114) begin
	win_state <= win_state + 1'd1;
	win_old7  <= c_7m;
	if (~win_old7 & c_7m) win_state <= 0;
end
`ifdef GLS
localparam GLS = 1;
`else
localparam GLS = 0;
integer win_diff = 0;
always @(posedge clk_114) if (reset_n && win_state !== dut.sdram_state) win_diff++;
`endif

// ----------------------------------------------------------------- DUT
wire        chipwr_tgl;
wire [20:4] chipwr_line;
wire        sd_clk, sd_ras, sd_cas, sd_we, sd_oe;
wire  [1:0] sd_cke, sd_cs, sd_dqm, sd_ba;
wire [12:0] sd_a;
wire [15:0] sd_dout, sd_din, m0_dout, m1_dout;
wire        m0_oe, m1_oe;

reg  [24:1] chipAddr = 0;
reg         chipL = 1, chipU = 1, chipRW = 1, chipDMA = 1, chip32 = 0;
reg  [15:0] chipWR = 0, chipWR2 = 0;
wire [15:0] chipRD, chipRD2;
wire [47:0] chip48;

reg  [25:1] cpuAddr = 0;
reg         cpuCS = 0, cpuL = 1, cpuU = 1;
reg   [1:0] cpustate = 2'b01;
reg  [15:0] cpuWR = 0;
wire [15:0] cpuRD;
wire        ramready;
reg         cpuLong1 = 0;
reg  [15:0] cpuWR_lo = 0;
wire [15:0] cpuRD_hi;
wire        ramready_l;
reg         cpuLine = 0;
wire [127:0] cpuRD_line;
wire        ramready_line;

reg  [24:1] hostAddr = 0;
reg         hostReq = 0, hostWE = 0;
reg   [1:0] hostDQM = 0;
reg  [15:0] hostWR = 0;
wire [15:0] hostRD;
wire        hostAck;

reg  [24:4] burstAddr = 0;
reg         burstReq = 0, burstUrgent = 0;
wire        burstAck, burstValid;
wire [15:0] burstData;

`ifdef LINE16
localparam LINE16 = 1;
`else
localparam LINE16 = 0;
`endif
`ifdef WQN_N
localparam WQN = `WQN_N;
`else
localparam WQN = 1;
`endif

gb_sdram_ctrl
`ifndef GLS
#(.CPU_LINE16(LINE16), .WQN(WQN))
`endif
dut
(
	.sysclk(clk_114), .sdclk(clk_114), .c_7m(c_7m), .reset_n(reset_n),
	.cache_rst(reset_n), .cache_inhibit(1'b0),
	.cpu_cache_ctrl(cache_on ? 4'b1111 : 4'b0000), .dcache_sw_en(cache_on),
	.sd_addr(sd_a), .sd_ba(sd_ba), .sd_cs(sd_cs), .sd_we(sd_we), .sd_ras(sd_ras), .sd_cas(sd_cas),
	.sd_dqm(sd_dqm), .sd_data_in(sd_din), .sd_data_out(sd_dout), .sd_data_oe(sd_oe),
	.sd_clk(sd_clk), .sd_cke(sd_cke),
	.chipAddr(chipAddr), .chipL(chipL), .chipU(chipU), .chipRW(chipRW), .chipDMA(chipDMA),
	.chipWR(chipWR), .chipRD(chipRD), .chip48(chip48), .chip32(chip32), .chipWR2(chipWR2), .chipRD2(chipRD2),
	.cpuAddr(cpuAddr), .cpuCS(cpuCS), .cpustate(cpustate), .cpuL(cpuL), .cpuU(cpuU),
	.cpuWR(cpuWR), .cpuRD(cpuRD), .ramready(ramready),
	.cpuLong1(cpuLong1), .cpuWR_lo(cpuWR_lo), .cpuRD_hi(cpuRD_hi), .ramready_l(ramready_l),
	.cpuLine(cpuLine), .cpuRD_line(cpuRD_line), .ramready_line(ramready_line),
	.chipwr_tgl(chipwr_tgl), .chipwr_line(chipwr_line),
	.hostAddr(hostAddr), .hostReq(hostReq), .hostWE(hostWE), .hostDQM(hostDQM), .hostWR(hostWR),
	.hostRD(hostRD), .hostAck(hostAck),
	.burstAddr(burstAddr), .burstReq(burstReq), .burstUrgent(burstUrgent),
	.burstAck(burstAck), .burstData(burstData), .burstValid(burstValid)
);

sdram_sim sdram (.clk(sd_clk), .cke(sd_cke[0]), .cs_n(sd_cs[0]), .ras_n(sd_ras), .cas_n(sd_cas), .we_n(sd_we),
	.ba(sd_ba), .a(sd_a), .dqm(sd_dqm), .dq_in(sd_dout), .dq_in_en(sd_oe), .dq_out(m0_dout), .dq_out_en(m0_oe));
sdram_sim sdram1 (.clk(sd_clk), .cke(sd_cke[1]), .cs_n(sd_cs[1]), .ras_n(sd_ras), .cas_n(sd_cas), .we_n(sd_we),
	.ba(sd_ba), .a(sd_a), .dqm(sd_dqm), .dq_in(sd_dout), .dq_in_en(sd_oe), .dq_out(m1_dout), .dq_out_en(m1_oe));

assign sd_din = m0_oe ? m0_dout : m1_oe ? m1_dout : sd_oe ? sd_dout : 16'hFFFF;

// the data bus, edge by edge (as tb_top)
reg [2:0] bus_prev = 3'b000;
integer bus_errors = 0;
integer edges_c0 = 0, edges_c1 = 0, edges_fpga = 0, edges_total = 0;
always @(posedge sd_clk) begin
	reg [2:0] drv;
	drv = {sd_oe, sdram1.beat_v, sdram.beat_v};
	edges_total++;
	if (drv == 3'b001) edges_c0++;
	if (drv == 3'b010) edges_c1++;
	if (drv == 3'b100) edges_fpga++;
	if (drv != 3'b000 && drv != 3'b001 && drv != 3'b010 && drv != 3'b100) begin
		bus_errors++;
		if (bus_errors <= 10) $display("ERROR %0t: data bus driven by %b (FPGA, chip 1, chip 0)", $time, drv);
	end
	else if (drv != 3'b000 && bus_prev != 3'b000 && drv != bus_prev) begin
		bus_errors++;
		if (bus_errors <= 10) $display("ERROR %0t: data bus passes from %b to %b without an idle clock", $time, bus_prev, drv);
	end
	bus_prev <= drv;
end

// ----------------------------------------------------------- memories
// regions (word addresses): chipset 0x000000-0x00FFFF of chip 0, CPU 0x400000+
// of chip 0 and 0x000000+ of chip 1, host 0x200000+ of chip 0, bursts
// 0x400000+ of chip 1; each spread over all four banks
function automatic [15:0] init_val(input int chip, input int unsigned wa);
	return 16'(wa * 2654435761 ^ (chip ? 32'h5A5A1234 : 32'h0F0F7777) ^ (wa >> 7));
endfunction

int unsigned shadow0 [int unsigned];
int unsigned shadow1 [int unsigned];
function automatic [15:0] sh_get(input int chip, input int unsigned wa);
	if (chip) return shadow1.exists(wa) ? 16'(shadow1[wa]) : init_val(1, wa);
	return shadow0.exists(wa) ? 16'(shadow0[wa]) : init_val(0, wa);
endfunction
// (chip 0: what a word held before its last write, and when that was, for
// the reads that a write may meet: the variant's code fetches from chip RAM)
int unsigned     shadow0_prev [int unsigned];
longint unsigned shadow0_t    [int unsigned];
function automatic longint unsigned now10();
	return longint'($realtime * 10.0);
endfunction
task automatic sh_put(input int chip, input int unsigned wa, input [15:0] d, input [1:0] mask_n /* {U,L} 1 = written */);
	reg [15:0] o;
	o = sh_get(chip, wa);
	if (!chip) begin shadow0_prev[wa] = o; shadow0_t[wa] = now10(); end
	if (mask_n[1]) o[15:8] = d[15:8];
	if (mask_n[0]) o[7:0]  = d[7:0];
	if (chip) shadow1[wa] = o; else shadow0[wa] = o;
endtask

// region address: n words spread over the banks (bits 23:22 of the word
// address are the bank)
function automatic int unsigned region(input int unsigned base, input int unsigned r, input int unsigned n);
	int unsigned w;
	w = r % n;
	return base | ((w & 3) << 22) | (w >> 2);
endfunction

localparam int unsigned N_CHIP = 4096, N_CPU = 2048, N_HOST = 1024, N_BURST = 1024;

initial begin
	int unsigned i, wa;
	for (i = 0; i < N_CHIP; i++) begin wa = region(32'h000000, i, N_CHIP); sdram.mem[wa]  = init_val(0, wa); end
	for (i = 0; i < N_CHIP; i++) begin wa = region(32'h000000, i, N_CHIP) ^ 1; sdram.mem[wa]  = init_val(0, wa); end
	for (i = 0; i < N_CPU;  i++) begin wa = region(32'h010000, i, N_CPU);  sdram.mem[wa]  = init_val(0, wa); sdram1.mem[wa] = init_val(1, wa); end
	for (i = 0; i < N_HOST; i++) begin wa = region(32'h020000, i, N_HOST); sdram.mem[wa]  = init_val(0, wa); end
	for (i = 0; i < N_BURST * 8; i++) begin wa = region(32'h030000, i, N_BURST * 8); sdram1.mem[wa] = init_val(1, wa); end
end

// ------------------------------------------------------------- chipset
integer chip_reads = 0, chip_writes = 0, chipwr_events = 0;
initial begin : chipset
	int unsigned wa, r;
	reg rd, c32;
	reg [1:0] m;
	reg tgl0;
	@(posedge reset_n);
	repeat (2000) @(posedge clk_114);
	forever begin
		tgl0 = chipwr_tgl;
		// the start of state 15: the controller's state is 15 when ph is 0
		do @(posedge clk_114); while (win_state != 4'd14);
		@(posedge clk_114); #0.1;
		r = $urandom % 4;
		if (r == 0) begin
			chipDMA = 1; chipRW = 1; chip32 = 0;
			repeat (16) @(posedge clk_114);
		end else begin
			rd  = (r != 3);
			c32 = ($urandom % 3) == 0;
			wa  = region(32'h000000, $urandom, N_CHIP) & ~32'h1;
			m   = c32 ? 2'b00 : ($urandom % 4 == 0) ? 2'(1 + $urandom % 2) : 2'b00;   // active low byte masks
			chipAddr = wa[23:0];
			chipU = m[1]; chipL = m[0];
			chip32 = c32;
			chipRW = rd; chipDMA = !rd;
			chipWR = $urandom; chipWR2 = $urandom;
			// the slot this window; inputs held over it, as the chip bus does
			repeat (14) @(posedge clk_114);
			if (!rd) begin
				sh_put(0, wa, chipWR, ~m);
				if (c32) sh_put(0, wa + 1, chipWR2, 2'b11);
				chip_writes++;
				// a write to chip RAM (below 2 MB: word address bits 23:20
				// zero) flips chipwr_tgl once, its line beside it
				if (wa[23:20] == 4'd0) begin
					if (chipwr_tgl === tgl0 || chipwr_line !== wa[19:3]) begin
						fails++; if (fails <= 20) $display("FAIL %0t: chip write %06X: chipwr_tgl %b (was %b), line %05X", $time, wa, chipwr_tgl, tgl0, chipwr_line);
					end
					chipwr_events++;
				end
				else if (chipwr_tgl !== tgl0) begin
					fails++; if (fails <= 20) $display("FAIL %0t: chip write %06X outside chip RAM flipped chipwr_tgl", $time, wa);
				end
			end
			else if (chipwr_tgl !== tgl0) begin
				fails++; if (fails <= 20) $display("FAIL %0t: chipwr_tgl flipped with no chip write", $time);
			end
			repeat (2) @(posedge clk_114);
			#0.1;
			chipDMA = 1; chipRW = 1; chip32 = 0;
			if (rd) begin
				// chipRD (state 9), chipRD2 / chip48 (states 11-15)
				if (chipRD !== sh_get(0, wa)) begin
					fails++; if (fails <= 20) $display("FAIL %0t: chip read %06X = %04X, expected %04X", $time, wa, chipRD, sh_get(0, wa));
				end
				if (c32 && chipRD2 !== sh_get(0, wa + 1)) begin
					fails++; if (fails <= 20) $display("FAIL %0t: chip read2 %06X = %04X, expected %04X", $time, wa + 1, chipRD2, sh_get(0, wa + 1));
				end
				if (chip48[47:32] !== sh_get(0, wa + 1) && ((wa & 3) == 0)) begin
					fails++; if (fails <= 20) $display("FAIL %0t: chip48 word 1 of %06X = %04X, expected %04X", $time, wa, chip48[47:32], sh_get(0, wa + 1));
				end
				chip_reads++;
			end
			// an idle window after each access (the chip bus's other half)
			repeat (16) @(posedge clk_114);
		end
	end
end

// ----------------------------------------------------------------- CPU
integer cpu_reads = 0, cpu_writes = 0, cpu_long_reads = 0, cpu_long_writes = 0, cpu_line_reads = 0;
integer stray_cs = 0;

`ifdef LINE16
// The variant's code fetches from chip RAM (cpu_wrapper's sel_chipram: the
// chipset's words of bank 0, which it writes meanwhile): a line read as the
// bus adapter's, from one of the line's long words, answered whole (the
// code cache of the variant's cpu_cache_new) or with its first word, the
// other seven words then asked for one by one, wrapping in the line. A word
// must be what the memory holds; one written after the fetch began may
// still be what it held before.
integer code_fetches = 0, code_whole = 0, code_words = 0, code_port_writes = 0;
int unsigned code_last = 0;
function automatic bit code_ok(input int unsigned wa, input [15:0] got, input longint unsigned t0);
	if (got === sh_get(0, wa)) return 1;
	if (shadow0_t.exists(wa) && shadow0_t[wa] >= t0 && got === 16'(shadow0_prev[wa])) return 1;
	return 0;
endfunction
task automatic code_word(input int unsigned wa, input bit ln, output bit whole);
	longint unsigned t0;
	cpuAddr  = {1'b0, wa[23:0]};
	cpuU = 0; cpuL = 0;
	cpustate = 2'd0;
	cpuLong1 = 0;
	cpuLine  = ln;
	cpuCS    = 1;
	t0 = now10();
	do @(posedge clk_114); while (!ramready);
	#0.1;
	whole = ln && ramready_line;
	if (ramready_l) begin
		fails++; if (fails <= 20) $display("FAIL %0t: ramready_l for a fetched word", $time);
	end
	if (ramready_line && !ln) begin
		fails++; if (fails <= 20) $display("FAIL %0t: ramready_line for no line read (code)", $time);
	end
	if (whole) begin
		for (int k = 0; k < 8; k++)
			if (!code_ok((wa & ~32'd7) + k, cpuRD_line[127 - 16 * k -: 16], t0)) begin
				fails++; if (fails <= 20) $display("FAIL %0t: code line %06X word %0d = %04X, memory holds %04X",
				                                  $time, wa & ~32'd7, k, cpuRD_line[127 - 16 * k -: 16], sh_get(0, (wa & ~32'd7) + k));
			end
		code_whole++;
	end
	else begin
		if (!code_ok(wa, cpuRD, t0)) begin
			fails++; if (fails <= 20) $display("FAIL %0t: code word %06X = %04X, memory holds %04X", $time, wa, cpuRD, sh_get(0, wa));
		end
		code_words++;
	end
	// the end of the bus cycle at the next clk_sys edge
	do @(posedge clk_114); while ((win_state & 3) != 2);
	@(posedge clk_114); #0.1;
	cpuCS = 0; cpustate = 2'b01; cpuLong1 = 0; cpuLine = 0;
endtask
task automatic code_fetch;
	int unsigned la, k0;
	bit whole, w2;
	// a loop's line again, the line after it, or any of the 128
	case ($urandom % 4)
		0:       la = code_last;
		1:       la = (code_last + 8) % 1024;
		default: la = ($urandom % 128) * 8;
	endcase
	code_last = la;
	k0 = ($urandom % 4) * 2;
	code_word(la + k0, 1, whole);
	if (!whole)
		for (int j = 1; j < 8; j++) begin
			// (the adapter's next sub-cycle: at the clk_sys edge after a
			// controller clock without the select)
			do @(posedge clk_114); while ((win_state & 3) != 2);
			@(posedge clk_114); #0.1;
			code_word(la + ((k0 + j) % 8), 0, w2);
		end
	code_fetches++;
	// now and then a word of the line written through the CPU's port (the
	// core's CPU writes chip RAM over the chip bus; the port must still
	// not answer with the line as it was), and the line fetched again
	if (($urandom % 8) == 0) begin
		int unsigned ww;
		reg [15:0] wd;
		ww = la + ($urandom % 8);
		wd = $urandom;
		do @(posedge clk_114); while ((win_state & 3) != 2);
		@(posedge clk_114); #0.1;
		cpuAddr  = {1'b0, ww[23:0]};
		cpuU = 0; cpuL = 0;
		cpustate = 2'd3;
		cpuWR    = wd;
		cpuLong1 = 0;
		cpuLine  = 0;
		cpuCS    = 1;
		do @(posedge clk_114); while (!ramready);
		#0.1;
		sh_put(0, ww, wd, 2'b11);
		code_port_writes++;
		do @(posedge clk_114); while ((win_state & 3) != 2);
		@(posedge clk_114); #0.1;
		cpuCS = 0; cpustate = 2'b01;
		do @(posedge clk_114); while ((win_state & 3) != 2);
		@(posedge clk_114); #0.1;
		code_word(la + k0, 1, whole);
		if (!whole)
			for (int j = 1; j < 8; j++) begin
				do @(posedge clk_114); while ((win_state & 3) != 2);
				@(posedge clk_114); #0.1;
				code_word(la + ((k0 + j) % 8), 0, w2);
			end
		code_fetches++;
	end
endtask
`endif
initial begin : cpu
	int unsigned wa;
	int chip;
	reg wr, lng, ln;
	int unsigned last_wa = 0;
	int unsigned r_cpu = 0, last_r = 0;
	int prev_chip = 0;
	int last_chip = 0;
	reg last_wr = 0;
	reg [1:0] m;
	reg [15:0] d, d2, exp, exp2;
	@(posedge reset_n);
	repeat (2000) @(posedge clk_114);
	forever begin
		// a clk_sys edge: states 3, 7, 11, 15
		do @(posedge clk_114); while ((win_state & 3) != 2);
		@(posedge clk_114); #0.1;
`ifdef LINE16
		if (($urandom % 3) == 0) begin
			code_fetch();
			repeat ($urandom % 12) @(posedge clk_114);
			continue;
		end
`endif
		// often the next 16 bytes after the last access on its chip (a
		// stream: the variant's read ahead), else anywhere in the region
		if (LINE16 && ($urandom % 2)) begin
			r_cpu = last_r + 32;
			chip  = prev_chip;
		end else begin
			r_cpu = $urandom % N_CPU;
			chip  = $urandom % 2;
		end
		last_r = r_cpu % N_CPU;
		wa   = region(32'h010000, r_cpu, N_CPU);
		wr   = ($urandom % 3) == 0;
		lng  = ($urandom % 3) == 0;   // an aligned long word, data (as the TG68K's long_cand)
		if (last_wr && ($urandom % 3) == 0) begin
			// read back what was just written (behind a queued write)
			chip = last_chip;
			wa   = last_wa;
			wr   = 0;
		end
		if (lng) wa = wa & ~32'd1;
		ln   = LINE16 && lng && !wr && ($urandom % 2);   // a line read (the adapter's: its first long word)
		m    = wr && !lng && ($urandom % 4 == 0) ? 2'(1 + $urandom % 2) : 2'b00;
		d    = $urandom;
		d2   = $urandom;
		cpuAddr  = {chip[0], wa[23:0]};
		cpuU = m[1]; cpuL = m[0];
		cpustate = wr ? 2'd3 : (lng || ($urandom % 2)) ? 2'd2 : 2'd0;
		cpuWR = d;
		cpuWR_lo = d2;
		cpuLong1 = lng;
		cpuLine  = ln;
		cpuCS = 1;
		exp  = sh_get(chip, wa);
		exp2 = sh_get(chip, wa + 1);
		do @(posedge clk_114); while (!ramready);
		#0.1;
		if (ramready_l && !lng) begin
			fails++; if (fails <= 20) $display("FAIL %0t: ramready_l for a word", $time);
		end
		if (ramready_line && !ln) begin
			fails++; if (fails <= 20) $display("FAIL %0t: ramready_line for no line read", $time);
		end
		if (ln && ramready_line) begin
			for (int k = 0; k < 8; k++)
				if (cpuRD_line[127 - 16 * k -: 16] !== sh_get(chip, (wa & ~32'd7) + k)) begin
					fails++; if (fails <= 20) $display("FAIL %0t: CPU line read chip %0d %06X word %0d = %04X, expected %04X",
					                                  $time, chip, wa & ~32'd7, k, cpuRD_line[127 - 16 * k -: 16], sh_get(chip, (wa & ~32'd7) + k));
				end
			cpu_line_reads++;
		end
		if (wr) begin
			sh_put(chip, wa, d, ~m);
			cpu_writes++;
			if (lng && !ramready_l) begin
				fails++; if (fails <= 20) $display("FAIL %0t: a long word write not taken whole", $time);
			end
			if (lng && ramready_l) begin
				sh_put(chip, wa + 1, d2, 2'b11);
				cpu_long_writes++;
			end
		end else if (lng && ramready_l) begin
			if (cpuRD_hi !== exp || cpuRD !== exp2) begin
				fails++; if (fails <= 20) $display("FAIL %0t: CPU long read chip %0d %06X = %04X %04X, expected %04X %04X",
				                                  $time, chip, wa, cpuRD_hi, cpuRD, exp, exp2);
			end
			cpu_long_reads++;
		end else begin
			if (cpuRD !== exp) begin
				fails++; if (fails <= 20) $display("FAIL %0t: CPU read chip %0d %06X = %04X, expected %04X", $time, chip, wa, cpuRD, exp);
			end
			cpu_reads++;
		end
		// the end of the bus cycle at the next clk_sys edge
		do @(posedge clk_114); while ((win_state & 3) != 2);
		@(posedge clk_114); #0.1;
		cpuCS = 0; cpustate = 2'b01; cpuLong1 = 0; cpuLine = 0;
		if ($urandom % 3 == 0) begin
			// the select a controller clock late: low for the clock of the
			// clk_sys edge (ram_cs's drop with cyc), then up for one clock
			// with the next transfer (a write elsewhere, on the chip bus)
			// already on the address and state
			@(posedge clk_114); #0.1;
			cpuCS    = 1;
			cpustate = 2'd3;
			cpuAddr  = {1'($urandom), region(32'h010000, $urandom, N_CPU)};
			cpuWR    = $urandom;
			cpuWR_lo = $urandom;
			cpuLong1 = $urandom;
			@(posedge clk_114); #0.1;
			cpuCS = 0; cpustate = 2'b01; cpuLong1 = 0;
			stray_cs++;
		end
		last_wr = wr; last_wa = wa; last_chip = chip; prev_chip = chip;
		// writes often back to back (filling a write queue)
		if (!(wr && ($urandom % 2))) repeat ($urandom % 12) @(posedge clk_114);
	end
end

// ---------------------------------------------------------------- host
integer host_reads = 0, host_writes = 0;
initial begin : host
	int unsigned wa;
	reg [15:0] exp;
	@(posedge reset_n);
	repeat (2000) @(posedge clk_114);
	forever begin
		repeat ($urandom % 64) @(posedge clk_114);
		#0.1;
		wa = region(32'h020000, $urandom, N_HOST);
		hostAddr = wa[23:0];
		hostWE  = $urandom % 2;
		hostDQM = ($urandom % 4 == 0) ? 2'(1 + $urandom % 2) : 2'b00;
		hostWR  = $urandom;
		hostReq = 1;
		exp = sh_get(0, wa);
		do @(posedge clk_114); while (!hostAck);
		#0.1;
		hostReq = 0;
		if (hostWE) begin
			sh_put(0, wa, hostWR, ~hostDQM);
			host_writes++;
		end else begin
			if (hostRD !== exp) begin
				fails++; if (fails <= 20) $display("FAIL %0t: host read %06X = %04X, expected %04X", $time, wa, hostRD, exp);
			end
			host_reads++;
		end
	end
end

// --------------------------------------------------------------- burst
integer bursts = 0, burst_words = 0;
int unsigned bq [$];   // word addresses of the bursts taken, in order
initial begin : burst_req
	int unsigned wa;
	@(posedge reset_n);
	repeat (2000) @(posedge clk_114);
	forever begin
		repeat ($urandom % 24) @(posedge clk_114);
		#0.1;
		wa = region(32'h030000, $urandom, N_BURST * 8) & ~32'h7;
		wa = wa & ~32'h7;
		burstAddr   = wa[23:3];
		burstUrgent = ($urandom % 4) == 0;
		burstReq    = 1;
		do @(posedge clk_114); while (!burstAck);
		bq.push_back(wa);
		#0.1;
		burstReq = 0;
	end
end
integer bw = 0;
always @(posedge clk_114) if (burstValid) begin
	int unsigned wa;
	if (bq.size() == 0) begin
		fails++; $display("FAIL %0t: burst word without a burst", $time);
	end else begin
		wa = bq[0] + bw;
		if (burstData !== sh_get(1, wa)) begin
			fails++; if (fails <= 20) $display("FAIL %0t: burst %06X word %0d = %04X, expected %04X", $time, bq[0], bw, burstData, sh_get(1, wa));
		end
		burst_words++;
		if (bw == 7) begin bw = 0; void'(bq.pop_front()); bursts++; end
		else bw = bw + 1;
	end
end

// ---------------------------------------------------------------- write queue
// (WQN > 1) its fullest, and the controller clocks a CPU read waited for a
// queued write to its 16 bytes
integer wq_max = 0, wq_held = 0, pf_hits = 0, pf_reads = 0;
`ifndef GLS
`ifdef LINE16
// the read ahead: lines read, and CPU reads answered from it
always @(posedge clk_114) begin
	if (dut.pf_ack) pf_reads++;
	if (dut.cpu_cache.st == 3'd3 && dut.cpu_cache.cpu_cs && !dut.cpu_cache.hit && dut.cpu_cache.n_hit) pf_hits++;
end
`endif
`ifdef WQN_N
always @(posedge clk_114) begin
	if (dut.wbufq.q_n > wq_max) wq_max = dut.wbufq.q_n;
	if (dut.cache_req && dut.wq_hit) wq_held++;
end
`endif
`endif

// ---------------------------------------------------------------- run
initial begin
	if ($value$plusargs("seed=%d", seed)) ;
	if ($value$plusargs("windows=%d", windows_run)) ;
	cache_on = $test$plusargs("cache");
	seed_junk = $urandom(seed);   // (a function call: xsim has no $urandom task)
	repeat (20) @(posedge clk_114);
	reset_n = 1;
	repeat (windows_run * 16) @(posedge clk_114);
	$display("windows %0d: chip %0d reads %0d writes, CPU %0d reads %0d writes (long words: %0d reads %0d writes), host %0d reads %0d writes, %0d bursts (%0d words)%s",
	         windows_run, chip_reads, chip_writes, cpu_reads, cpu_writes, cpu_long_reads, cpu_long_writes,
	         host_reads, host_writes, bursts, burst_words, LINE16 ? ", CPU lines of 16 bytes from chip 1" : "");
	$display("windows: %0d one-clock CPU selects after a transfer (nothing written from them)", stray_cs);
	$display("windows: %0d chip RAM writes announced (chipwr_tgl, its line)", chipwr_events);
	if (chipwr_events < 50) fails++;
	// (on the netlist the read ahead and the write queue are not looked into)
	if (LINE16 && GLS) $display("windows: %0d CPU line reads answered whole", cpu_line_reads);
	if (LINE16 && !GLS) $display("windows: %0d CPU line reads answered whole; %0d lines read ahead, %0d reads answered from them",
	                             cpu_line_reads, pf_reads, pf_hits);
	if (WQN > 1 && !GLS) $display("windows: CPU write queue of %0d, at most %0d queued, reads held %0d clocks for a queued write",
	                              WQN, wq_max, wq_held);
`ifdef LINE16
	$display("windows: %0d code lines fetched from chip RAM under the chipset's writes, %0d answered whole from the code cache, %0d words one by one; %0d lines written through the CPU's port and fetched again",
	         code_fetches, code_whole, code_words, code_port_writes);
	if (code_fetches < 200 || code_whole < 50 || code_words < 400 || code_port_writes < 20) fails++;
`endif
	$display("data bus: chip 0 %0d, chip 1 %0d, FPGA %0d of %0d edges; refreshes chip 0 %0d, chip 1 %0d",
	         edges_c0, edges_c1, edges_fpga, edges_total, sdram.refreshes, sdram1.refreshes);
`ifndef GLS
	if (win_diff) begin fails++; $display("FAIL: the bench's window state was not the controller's in %0d clocks", win_diff); end
`endif
	$display("SDRAM model errors: chip 0 %0d, chip 1 %0d; data bus errors %0d; data mismatches %0d",
	         sdram.errors, sdram1.errors, bus_errors, fails);
	if (sdram.errors || sdram1.errors || bus_errors || fails ||
	    chip_reads < 100 || cpu_reads < 100 || host_reads < 20 || bursts < 100 || cpu_writes < 50 ||
	    cpu_long_writes < 50 || ((cache_on || LINE16) && cpu_long_reads < 50) ||
	    (!GLS && WQN > 1 && (wq_max < 2 || wq_held == 0)) || (LINE16 && (cpu_line_reads < 50 || (!GLS && pf_hits < 50))))
		$display("TEST FAILED");
	else
		$display("TEST PASSED");
	$finish;
end

endmodule
