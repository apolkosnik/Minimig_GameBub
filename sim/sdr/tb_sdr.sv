// Directed random test of gb_sdram_ctrl (with its cpu_cache_new) and the
// two SDRAM chip models (sim/rtl/sdram_sim.sv): every port at once.
//
// - chipset: one random access per two windows (as the Amiga's chip bus at
//   most), read, write, 32 bit read or write, inputs changing at a clk_sys
//   edge (the start of state 15) like Agnus's;
// - CPU: random word reads and writes (byte masks too) to chip 0 and chip 1
//   RAM through the cache, inputs changing at clk_sys edges, with the
//   cache on or off (+cache);
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

// ----------------------------------------------------------------- DUT
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

gb_sdram_ctrl dut
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
task automatic sh_put(input int chip, input int unsigned wa, input [15:0] d, input [1:0] mask_n /* {U,L} 1 = written */);
	reg [15:0] o;
	o = sh_get(chip, wa);
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
integer chip_reads = 0, chip_writes = 0;
initial begin : chipset
	int unsigned wa, r;
	reg rd, c32;
	reg [1:0] m;
	@(posedge reset_n);
	repeat (2000) @(posedge clk_114);
	forever begin
		// the start of state 15: the controller's state is 15 when ph is 0
		do @(posedge clk_114); while (dut.sdram_state != 4'd14);
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
integer cpu_reads = 0, cpu_writes = 0;
initial begin : cpu
	int unsigned wa;
	int chip;
	reg wr;
	reg [1:0] m;
	reg [15:0] d, exp;
	@(posedge reset_n);
	repeat (2000) @(posedge clk_114);
	forever begin
		// a clk_sys edge: states 3, 7, 11, 15
		do @(posedge clk_114); while ((dut.sdram_state & 3) != 2);
		@(posedge clk_114); #0.1;
		chip = $urandom % 2;
		wa   = region(32'h010000, $urandom, N_CPU);
		wr   = ($urandom % 3) == 0;
		m    = wr && ($urandom % 4 == 0) ? 2'(1 + $urandom % 2) : 2'b00;
		d    = $urandom;
		cpuAddr  = {chip[0], wa[23:0]};
		cpuU = m[1]; cpuL = m[0];
		cpustate = wr ? 2'd3 : (($urandom % 2) ? 2'd2 : 2'd0);
		cpuWR = d;
		cpuCS = 1;
		exp = sh_get(chip, wa);
		do @(posedge clk_114); while (!ramready);
		if (wr) begin
			sh_put(chip, wa, d, ~m);
			cpu_writes++;
		end else begin
			#0.1;
			if (cpuRD !== exp) begin
				fails++; if (fails <= 20) $display("FAIL %0t: CPU read chip %0d %06X = %04X, expected %04X", $time, chip, wa, cpuRD, exp);
			end
			cpu_reads++;
		end
		// the end of the bus cycle at the next clk_sys edge
		do @(posedge clk_114); while ((dut.sdram_state & 3) != 2);
		@(posedge clk_114); #0.1;
		cpuCS = 0; cpustate = 2'b01;
		repeat ($urandom % 12) @(posedge clk_114);
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

// ---------------------------------------------------------------- run
initial begin
	if ($value$plusargs("seed=%d", seed)) ;
	if ($value$plusargs("windows=%d", windows_run)) ;
	cache_on = $test$plusargs("cache");
	void'($urandom(seed));
	repeat (20) @(posedge clk_114);
	reset_n = 1;
	repeat (windows_run * 16) @(posedge clk_114);
	$display("windows %0d: chip %0d reads %0d writes, CPU %0d reads %0d writes, host %0d reads %0d writes, %0d bursts (%0d words)",
	         windows_run, chip_reads, chip_writes, cpu_reads, cpu_writes, host_reads, host_writes, bursts, burst_words);
	$display("data bus: chip 0 %0d, chip 1 %0d, FPGA %0d of %0d edges; refreshes chip 0 %0d, chip 1 %0d",
	         edges_c0, edges_c1, edges_fpga, edges_total, sdram.refreshes, sdram1.refreshes);
	$display("SDRAM model errors: chip 0 %0d, chip 1 %0d; data bus errors %0d; data mismatches %0d",
	         sdram.errors, sdram1.errors, bus_errors, fails);
	if (sdram.errors || sdram1.errors || bus_errors || fails ||
	    chip_reads < 100 || cpu_reads < 100 || host_reads < 20 || bursts < 100 || cpu_writes < 50)
		$display("TEST FAILED");
	else
		$display("TEST PASSED");
	$finish;
end

endmodule
