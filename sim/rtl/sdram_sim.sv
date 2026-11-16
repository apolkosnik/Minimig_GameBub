// Behavioural SDR SDRAM (16 bit, 4 banks x 8192 rows x 512 columns = 32 MB)
// with protocol and timing checks, for the Game Bub Minimig simulation.
//
// - Commands are sampled on the rising edge of clk (the SDRAM clock that
//   gb_sdram_ctrl forwards: clk_114 inverted), chip select active low.
// - The mode register sets CAS latency (2 or 3, at least MIN_CL), burst
//   length (1/2/4/8, sequential) and the write burst mode; reads and writes
//   before the first LOAD MODE are errors.
// - Rows must be opened (ACTIVE) before READ/WRITE, a bank must be
//   precharged before ACTIVE, REFRESH and LOAD MODE need all banks idle.
//   A10 with READ/WRITE is auto precharge: it starts BL edges after a READ,
//   T_WR edges after a (single word) WRITE.
// - Timing, in SDRAM clocks (defaults: 113.54 MHz, 8.81 ns, for the slowest
//   common 133 MHz parts, tRCD / tRP 20 ns, tRAS 45 ns, tRC / tRFC 70 ns,
//   tWR 2 clocks, tRRD 15 ns, tMRD 2 clocks): ACTIVE to READ/WRITE T_RCD,
//   precharge to ACTIVE / REFRESH / LOAD MODE T_RP, ACTIVE to precharge
//   T_RAS, ACTIVE to ACTIVE of a bank T_RC and of any two banks T_RRD,
//   REFRESH to the next command T_RFC, LOAD MODE to the next T_MRD.
// - Refresh: one REFRESH is owed every T_REFI clocks (7.8125 us) from the
//   first LOAD MODE; more than 8 owed is an error.
// - Read data of a READ at edge n is the data of edges n+CL..n+CL+BL-1. The
//   beat of edge e is driven from edge e to edge e+1 here: gb_sdram_ctrl
//   takes it at the clk_114 edge half an SDRAM clock after edge e (the
//   forwarded clock's delay and the pad delays put the real data window
//   around that point; rtl/gamebub/minimig.xdc times it). A READ or
//   PRECHARGE ends the burst in progress at its own data edge.
// - The bench (tb_top) checks the data bus between the chips and the FPGA
//   (beat_v: the model drives the beat of this edge).
//
// Errors are counted in `errors` and printed (the bench fails on any).
// SPDX-License-Identifier: GPL-3.0-or-later

module sdram_sim
#(
	parameter integer MIN_CL = 3,
	parameter integer T_RCD  = 3,
	parameter integer T_RP   = 3,
	parameter integer T_RAS  = 6,
	parameter integer T_RC   = 8,
	parameter integer T_RFC  = 8,
	parameter integer T_WR   = 2,
	parameter integer T_RRD  = 2,
	parameter integer T_MRD  = 2,
	parameter integer T_REFI = 887
)
(
	input         clk,
	input         cke,
	input         cs_n,
	input         ras_n,
	input         cas_n,
	input         we_n,
	input   [1:0] ba,
	input  [12:0] a,
	input   [1:0] dqm,       // {udqm, ldqm}
	input  [15:0] dq_in,     // controller -> SDRAM
	input         dq_in_en,  // controller drives the bus
	output [15:0] dq_out,    // SDRAM -> controller
	output        dq_out_en
);

reg [15:0] mem [0:(1<<24)-1];

reg        mode_set = 1'b0;
reg  [2:0] cl = 3'd2;
reg  [3:0] bl = 4'd4;
reg        wb_single = 1'b1;

reg        open_r [0:3];
reg [12:0] row_r  [0:3];

// timing state, in edges
longint    edge_n = 0;
longint    t_act   [0:3];   // last ACTIVE of the bank
longint    t_idle  [0:3];   // the bank is precharged from this edge
longint    t_pre   [0:3];   // a pending auto precharge starts at this edge (0: none)
longint    t_act_any = -1000, t_ref_done = 0, t_mrd_done = 0;
longint    refi_n = 0;
integer    ref_owed = 0;

integer errors = 0;
integer reads = 0, writes = 0, refreshes = 0, activates = 0;

// read pipeline: pipe_*[k] is the beat of edge edge_n + k
reg [15:0] pipe_d  [0:15];
reg        pipe_v  [0:15];
reg [15:0] dq_o = 16'h0000;
reg        dq_oe = 1'b0;
assign dq_out    = dq_o;
assign dq_out_en = dq_oe;
wire       beat_v = pipe_v[0];

integer k;
initial begin
	for (k = 0; k < 4; k = k + 1) begin
		open_r[k] = 1'b0; row_r[k] = 13'd0;
		t_act[k] = -1000; t_idle[k] = 0; t_pre[k] = 0;
	end
	for (k = 0; k < 16; k = k + 1) begin pipe_v[k] = 1'b0; pipe_d[k] = 16'h0; end
end

task automatic err(input string msg);
	errors = errors + 1;
	if (errors <= 20) $display("[sdram] ERROR %0d at %0t (edge %0d): %s", errors, $time, edge_n, msg);
endtask

// a bank is idle (precharged, tRP elapsed) at edge n
function automatic bit bank_idle(input integer b, input longint n);
	return !open_r[b] && n >= t_idle[b];
endfunction

// start a precharge of an open bank at edge n
task automatic precharge(input integer b, input longint n);
	if (n - t_act[b] < T_RAS) err($sformatf("bank %0d precharged %0d clocks after ACTIVE (tRAS %0d)", b, n - t_act[b], T_RAS));
	t_idle[b] = n + T_RP;
	t_pre[b]  = 0;
endtask

always @(posedge clk) begin
	integer b;
	reg [23:0] base;
	reg [8:0]  col;

	// auto precharges that start at this edge
	for (b = 0; b < 4; b = b + 1)
		if (t_pre[b] != 0 && t_pre[b] <= edge_n) begin
			precharge(b, t_pre[b]);
			open_r[b] <= 1'b0;
		end

	// drive this edge's beat, shift the read pipeline
	dq_oe <= pipe_v[0];
	dq_o  <= pipe_d[0];
	for (b = 0; b < 15; b = b + 1) begin
		pipe_v[b] <= pipe_v[b+1];
		pipe_d[b] <= pipe_d[b+1];
	end
	pipe_v[15] <= 1'b0;

	// refresh rate
	if (mode_set) begin
		refi_n = refi_n + 1;
		if (refi_n >= T_REFI) begin
			refi_n = 0;
			ref_owed = ref_owed + 1;
			if (ref_owed > 8) err($sformatf("%0d refreshes owed", ref_owed));
		end
	end

	if (cke && !cs_n) begin
		if ({ras_n, cas_n, we_n} != 3'b111) begin
			if (edge_n < t_ref_done) err("command during tRFC");
			if (edge_n < t_mrd_done) err("command during tMRD");
		end
		case ({ras_n, cas_n, we_n})
			3'b000: begin // LOAD MODE REGISTER
				for (b = 0; b < 4; b = b + 1) if (!bank_idle(b, edge_n)) err("LOAD MODE with a bank not idle");
				cl        <= a[6:4];
				bl        <= (a[2:0] == 3'd0) ? 4'd1 : (a[2:0] == 3'd1) ? 4'd2 : (a[2:0] == 3'd2) ? 4'd4 : 4'd8;
				wb_single <= a[9];
				mode_set  <= 1'b1;
				if (a[6:4] != 3'd2 && a[6:4] != 3'd3) err("unsupported CAS latency");
				if (a[6:4] < MIN_CL) err($sformatf("CAS latency %0d below %0d", a[6:4], MIN_CL));
				if (a[3]) err("interleaved burst not modelled");
				t_mrd_done = edge_n + T_MRD;
			end
			3'b001: begin // AUTO REFRESH
				for (b = 0; b < 4; b = b + 1) if (!bank_idle(b, edge_n)) err("REFRESH with a bank not idle");
				refreshes = refreshes + 1;
				if (mode_set && ref_owed > -8) ref_owed = ref_owed - 1;
				t_ref_done = edge_n + T_RFC;
			end
			3'b010: begin // PRECHARGE
				for (b = 0; b < 4; b = b + 1)
					if ((a[10] || ba == b) && open_r[b]) begin
						precharge(b, edge_n);
						open_r[b] <= 1'b0;
					end
				for (b = cl - 1; b < 16; b = b + 1) pipe_v[b] <= 1'b0;
			end
			3'b011: begin // ACTIVE
				if (open_r[ba]) err("ACTIVE on an open bank");
				else if (edge_n < t_idle[ba]) err($sformatf("ACTIVE on bank %0d %0d clocks before tRP has passed", ba, t_idle[ba] - edge_n));
				if (edge_n - t_act[ba] < T_RC) err($sformatf("ACTIVE on bank %0d %0d clocks after the last (tRC %0d)", ba, edge_n - t_act[ba], T_RC));
				if (edge_n - t_act_any < T_RRD) err("ACTIVE within tRRD of another");
				open_r[ba] <= 1'b1;
				row_r[ba]  <= a;
				t_act[ba]  = edge_n;
				t_act_any  = edge_n;
				activates = activates + 1;
			end
			3'b101: begin // READ
				if (!mode_set) err("READ before LOAD MODE");
				if (!open_r[ba] || t_pre[ba] != 0) err("READ from a closed bank");
				else if (edge_n - t_act[ba] < T_RCD) err($sformatf("READ %0d clocks after ACTIVE (tRCD %0d)", edge_n - t_act[ba], T_RCD));
				col  = a[8:0];
				base = {ba, row_r[ba], 9'd0};
				// ends the burst in progress at its first data edge
				for (b = cl - 1; b < 16; b = b + 1) pipe_v[b] <= 1'b0;
				for (b = 0; b < bl; b = b + 1) begin
					// sequential burst within the burst length boundary
					pipe_v[cl - 1 + b] <= 1'b1;
					pipe_d[cl - 1 + b] <= mem[base | ((col & ~(bl - 1)) | ((col + b) & (bl - 1)))];
				end
				if (a[10]) t_pre[ba] = edge_n + bl;
				reads = reads + 1;
			end
			3'b100: begin // WRITE (single location or burst of one word here)
				if (!mode_set) err("WRITE before LOAD MODE");
				if (!open_r[ba] || t_pre[ba] != 0) err("WRITE to a closed bank");
				else if (edge_n - t_act[ba] < T_RCD) err($sformatf("WRITE %0d clocks after ACTIVE (tRCD %0d)", edge_n - t_act[ba], T_RCD));
				if (!wb_single) err("burst writes not modelled");
				if (!dq_in_en) err("WRITE without the controller driving the data bus");
				base = {ba, row_r[ba], a[8:0]};
				if (!dqm[1]) mem[base][15:8] <= dq_in[15:8];
				if (!dqm[0]) mem[base][7:0]  <= dq_in[7:0];
				if (a[10]) t_pre[ba] = edge_n + T_WR;
				writes = writes + 1;
			end
			default: ; // NOP, BURST TERMINATE
		endcase
	end

	edge_n = edge_n + 1;
end

// backdoor for the bench (word address {bank, row, column})
export "DPI-C" function sdram_poke16;
export "DPI-C" function sdram_peek16;
export "DPI-C" function sdram_errors;
function void sdram_poke16(input int unsigned waddr, input int unsigned data);
	mem[waddr[23:0]] = data[15:0];
endfunction
function int unsigned sdram_peek16(input int unsigned waddr);
	return {16'd0, mem[waddr[23:0]]};
endfunction
function int sdram_errors();
	return errors;
endfunction

endmodule
