// The AP68040 variant's CPU as Vivado synthesized it (the netlist of
// ap68040_minimig: the core, its FPU and the bridge) replayed against the
// RTL simulation: a trace of the module's inputs and outputs before every
// CPU clock edge (sim/tb/tb_top.sv, +cputrace) drives the netlist's inputs,
// and its outputs must be the RTL's at every clock. Run by run_cpu_gls.sh.
//   +trace=<file>   the trace
//   +maxrst=<n>     a run of more than n equal clocks in reset is cut to n
//                   (the reset before the ROM is loaded: 27 million clocks)
// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
module tb;

reg          clk = 1'b0;
reg  [200:0] in_v = 201'd0;
wire [301:0] out_v;

wire         mem_req, mem_write, mem_instr, mem_ci, mem_line, nmi_ack_toggle, nresetout;
wire         cache_maint_toggle, debug_halted;
wire   [1:0] mem_size;
wire   [2:0] mem_tm;
wire  [31:0] mem_addr, mem_wdata, cacr_out, vbr_out, debug_pc;
wire [127:0] mem_wline;

ap68040_minimig dut
(
	.clk               (clk),
	.ar_on             (in_v[200]),
	.nreset            (in_v[199]),
	.chipcode          (in_v[198]),
	.cw_tgl            (in_v[197]),
	.cw_line           (in_v[196:180]),
	.z2ram_ena         (in_v[179]),
	.z3ram_base0       (in_v[178:171]),
	.z3ram_ena0        (in_v[170]),
	.z3ram_base1       (in_v[169:166]),
	.z3ram_ena1        (in_v[165]),
	.mem_ack           (in_v[164]),
	.mem_rdata         (in_v[163:132]),
	.mem_rline         (in_v[131:4]),
	.mem_berr          (in_v[3]),
	.ipl_n             (in_v[2:0]),
	.mem_req           (mem_req),
	.mem_write         (mem_write),
	.mem_instr         (mem_instr),
	.mem_size          (mem_size),
	.mem_addr          (mem_addr),
	.mem_wdata         (mem_wdata),
	.mem_tm            (mem_tm),
	.mem_ci            (mem_ci),
	.mem_line          (mem_line),
	.mem_wline         (mem_wline),
	.nmi_ack_toggle    (nmi_ack_toggle),
	.nresetout         (nresetout),
	.cacr_out          (cacr_out),
	.vbr_out           (vbr_out),
	.cache_maint_toggle(cache_maint_toggle),
	.debug_halted      (debug_halted),
	.debug_pc          (debug_pc)
);

assign out_v = {mem_req, mem_write, mem_instr, mem_size, mem_addr, mem_wdata, mem_tm, mem_ci,
                mem_line, mem_wline, nmi_ack_toggle, nresetout, cacr_out, vbr_out,
                cache_maint_toggle, debug_halted, debug_pc};

integer      f, r, run, k, maxrst, bad, lines;
longint      n;
reg  [200:0] in_n;
reg  [301:0] out_n;
reg [1023:0] name;

task automatic field(input [159:0] nm, input [127:0] e, input [127:0] g);
	if (e !== g) $display("    %0s: RTL %0h, netlist %0h", nm, e, g);
endtask

initial begin
	if (!$value$plusargs("trace=%s", name)) begin $display("no +trace"); $finish; end
	maxrst = 0;
	if ($value$plusargs("maxrst=%d", maxrst)) begin end
	f = $fopen(name, "r");
	if (f == 0) begin $display("cannot open the trace"); $finish; end
	n = 0; bad = 0; lines = 0;
	#200;                           // the netlist's global set/reset is over
	while (!$feof(f) && bad < 8) begin
		r = $fscanf(f, "%d %h %h\n", run, in_n, out_n);
		if (r != 3) break;
		lines = lines + 1;
		if (maxrst != 0 && !in_n[199] && run > maxrst) run = maxrst;
		for (k = 0; k < run && bad < 8; k = k + 1) begin
			in_v = in_n;
			#4;
			// (not before the first clock: a register's value at power-up is
			// the tool's choice where the RTL gives none)
			if (n != 0 && out_v !== out_n) begin
				bad = bad + 1;
				$display("MISMATCH at clock %0d (trace line %0d), inputs %h:", n, lines, in_n);
				field("mem_req",   out_n[301],     out_v[301]);
				field("mem_write", out_n[300],     out_v[300]);
				field("mem_instr", out_n[299],     out_v[299]);
				field("mem_size",  out_n[298:297], out_v[298:297]);
				field("mem_addr",  out_n[296:265], out_v[296:265]);
				field("mem_wdata", out_n[264:233], out_v[264:233]);
				field("mem_tm",    out_n[232:230], out_v[232:230]);
				field("mem_ci",    out_n[229],     out_v[229]);
				field("mem_line",  out_n[228],     out_v[228]);
				field("mem_wline", out_n[227:100], out_v[227:100]);
				field("nmi_ack_toggle", out_n[99], out_v[99]);
				field("nresetout", out_n[98],      out_v[98]);
				field("cacr_out",  out_n[97:66],   out_v[97:66]);
				field("vbr_out",   out_n[65:34],   out_v[65:34]);
				field("cache_maint_toggle", out_n[33], out_v[33]);
				field("debug_halted", out_n[32],   out_v[32]);
				field("debug_pc",  out_n[31:0],    out_v[31:0]);
			end
			#1 clk = 1'b1;
			#5 clk = 1'b0;
			n = n + 1;
			if (n % 250000 == 0) begin $display("... %0d clocks", n); $fflush; end
		end
	end
	$display("RESULT: %0d clocks replayed, %0d trace lines, %0d clocks with a mismatch%s",
	         n, lines, bad, bad >= 8 ? " (stopped)" : "");
	if (bad == 0) $display("TEST PASSED"); else $display("TEST FAILED");
	$finish;
end

endmodule
