// Behavioural SDR SDRAM (16 bit, 4 banks x 8192 rows x 512 columns = 32 MB)
// with protocol checks, for the Game Bub Minimig simulation.
//
// - Commands are sampled on the rising edge of clk (the controller's
//   generated SDRAM clock), chip select active low.
// - The mode register sets CAS latency (2 or 3), burst length (1/2/4/8,
//   sequential) and the write burst mode; reads and writes before the first
//   LOAD MODE are errors.
// - Rows must be opened (ACTIVE) before READ/WRITE, a bank must be
//   precharged before ACTIVE, REFRESH needs all banks precharged. A10 with
//   READ/WRITE is auto precharge.
// - Read data of a READ at edge n is driven from edge n+CL-1 so that the
//   controller samples it at edge n+CL (the way sdram_ctrl captures data).
// - The data bus driven by both the controller and the model is an error.
//
// Errors are counted in `errors` and printed (the bench fails on any).
// SPDX-License-Identifier: GPL-3.0-or-later

module sdram_sim
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

integer errors = 0;
integer reads = 0, writes = 0, refreshes = 0, activates = 0;

// read pipeline: up to 8 beats, latency in edges
reg [15:0] pipe_d  [0:15];
reg        pipe_v  [0:15];
reg [15:0] dq_o = 16'h0000;
reg        dq_oe = 1'b0;
assign dq_out    = dq_o;
assign dq_out_en = dq_oe;

integer k;
initial begin
	for (k = 0; k < 4; k = k + 1) begin open_r[k] = 1'b0; row_r[k] = 13'd0; end
	for (k = 0; k < 16; k = k + 1) begin pipe_v[k] = 1'b0; pipe_d[k] = 16'h0; end
end

task automatic err(input string msg);
	errors = errors + 1;
	if (errors <= 20) $display("[sdram] ERROR %0d at %0t: %s", errors, $time, msg);
endtask

always @(posedge clk) begin
	integer b;
	reg [23:0] base;
	reg [8:0]  col;

	// shift the read pipeline, drive this edge's beat
	dq_oe <= pipe_v[0];
	dq_o  <= pipe_d[0];
	for (b = 0; b < 15; b = b + 1) begin
		pipe_v[b] <= pipe_v[b+1];
		pipe_d[b] <= pipe_d[b+1];
	end
	pipe_v[15] <= 1'b0;

	if (cke && !cs_n) begin
		case ({ras_n, cas_n, we_n})
			3'b000: begin // LOAD MODE REGISTER
				for (b = 0; b < 4; b = b + 1) if (open_r[b]) err("LOAD MODE with an open bank");
				cl        <= a[6:4];
				bl        <= (a[2:0] == 3'd0) ? 4'd1 : (a[2:0] == 3'd1) ? 4'd2 : (a[2:0] == 3'd2) ? 4'd4 : 4'd8;
				wb_single <= a[9];
				mode_set  <= 1'b1;
				if (a[6:4] != 3'd2 && a[6:4] != 3'd3) err("unsupported CAS latency");
				if (a[3]) err("interleaved burst not modelled");
			end
			3'b001: begin // AUTO REFRESH
				for (b = 0; b < 4; b = b + 1) if (open_r[b]) err("REFRESH with an open bank");
				refreshes = refreshes + 1;
			end
			3'b010: begin // PRECHARGE
				if (a[10]) for (b = 0; b < 4; b = b + 1) open_r[b] <= 1'b0;
				else open_r[ba] <= 1'b0;
			end
			3'b011: begin // ACTIVE
				if (open_r[ba]) err("ACTIVE on an open bank");
				open_r[ba] <= 1'b1;
				row_r[ba]  <= a;
				activates = activates + 1;
			end
			3'b101: begin // READ
				if (!mode_set) err("READ before LOAD MODE");
				if (!open_r[ba]) err("READ from a closed bank");
				col  = a[8:0];
				base = {ba, row_r[ba], 9'd0};
				for (b = 0; b < bl; b = b + 1) begin
					// sequential burst within the burst length boundary
					pipe_v[cl - 2 + b] <= 1'b1;
					pipe_d[cl - 2 + b] <= mem[base | ((col & ~(bl - 1)) | ((col + b) & (bl - 1)))];
				end
				if (a[10]) open_r[ba] <= 1'b0;
				reads = reads + 1;
			end
			3'b100: begin // WRITE (single location or burst of one word here)
				if (!mode_set) err("WRITE before LOAD MODE");
				if (!open_r[ba]) err("WRITE to a closed bank");
				if (!wb_single) err("burst writes not modelled");
				if (!dq_in_en) err("WRITE without the controller driving the data bus");
				base = {ba, row_r[ba], a[8:0]};
				if (!dqm[1]) mem[base][15:8] <= dq_in[15:8];
				if (!dqm[0]) mem[base][7:0]  <= dq_in[7:0];
				if (a[10]) open_r[ba] <= 1'b0;
				writes = writes + 1;
			end
			default: ; // NOP, BURST TERMINATE
		endcase
	end

	if (dq_oe && dq_in_en) err("data bus driven by both sides");
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
