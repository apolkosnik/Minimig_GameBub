// The Toccata sound card (rtl/minimig/fpga-toccata) on its own, for the
// netlist test (run_toccata_gls.sh): the same bench runs on the RTL and on
// the netlist Vivado makes of it, and writes every change of the card's
// outputs with its clock to a file; the two files must be the same.
//
// It drives the card as toccata.library does, in four formats (16 bit
// stereo at 44100 Hz, 8 bit stereo, 16 bit mono and 8 bit mono at 48000
// Hz): the format, the FIFO filled with 800 bytes of noise, playback with
// the half empty interrupt, and at every interrupt the status read, the
// two DACs' attenuation set anew (the left one goes through all 64 levels)
// and 256 bytes more. No unicode in this file.
// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns / 1ps

module tb;

reg         clk = 1'b0;
reg         rst = 1'b1;
reg         hsync = 1'b0;
reg  [15:0] data_in = 16'h0000;
wire [15:0] data_out;
reg  [15:1] addr = 15'd0;
reg         rd = 1'b0, hwr = 1'b0, lwr = 1'b0, sel = 1'b0;
wire        toc_int;
wire [15:0] out_left, out_right;

// (the netlist has the clock's frequency in it)
`ifdef NETLIST
toccata dut (
`else
toccata #(.CLK_FREQUENCY(28_375_160)) dut (
`endif
	.clk(clk), .rst(rst), .hsync(hsync),
	.data_in(data_in), .data_out(data_out), .addr(addr),
	.rd(rd), .hwr(hwr), .lwr(lwr), .sel(sel),
	.toc_int(toc_int), .out_left(out_left), .out_right(out_right)
);

always #5 clk = ~clk;

// a line of 1816 clocks, its sync 134 long
integer hcnt = 0;
always @(negedge clk) begin
	hcnt  <= (hcnt == 1815) ? 0 : hcnt + 1;
	hsync <= hcnt < 134;
end

// the outputs, whenever one changes (sampled before the clock's edge)
integer f, clocks = 0, changes = 0, sounds = 0;
reg [15:0] p_l, p_r, p_d;
reg        p_i, logging = 1'b0;
always @(negedge clk) begin
	clocks = clocks + 1;
	if (logging && (out_left !== p_l || out_right !== p_r || toc_int !== p_i || data_out !== p_d)) begin
		$fdisplay(f, "%0d %h %h %b %h", clocks, out_left, out_right, toc_int, data_out);
		changes = changes + 1;
		if (out_left !== p_l && out_left !== 16'h0000) sounds = sounds + 1;
	end
	p_l = out_left; p_r = out_right; p_i = toc_int; p_d = data_out;
end

localparam [2:0] R_STATUS = 3'b000, R_FIFO = 3'b010, R_INDEX = 3'b110, R_DATA = 3'b111;

task automatic sel_reg(input [2:0] r);
	begin
		addr = 15'd0;
		addr[14] = r[2];
		addr[13] = r[1];
		addr[11] = r[0];
	end
endtask

// a write of the high byte alone (an even address)
task automatic wr_high(input [2:0] r, input [7:0] d);
	begin
		@(negedge clk);
		sel_reg(r);
		data_in = {d, d};
		sel = 1'b1; hwr = 1'b1; lwr = 1'b0;
		repeat (4) @(negedge clk);
		hwr = 1'b0; sel = 1'b0;
		repeat (4) @(negedge clk);
	end
endtask

// a write cycle: the low byte, or with h the whole word
task automatic wr(input [2:0] r, input [15:0] d, input h);
	begin
		@(negedge clk);
		sel_reg(r);
		data_in = d;
		sel = 1'b1; lwr = 1'b1; hwr = h;
		repeat (4) @(negedge clk);
		lwr = 1'b0; hwr = 1'b0; sel = 1'b0;
		repeat (4) @(negedge clk);
	end
endtask

task automatic rdreg(input [2:0] r, output [15:0] d);
	begin
		@(negedge clk);
		sel_reg(r);
		sel = 1'b1; rd = 1'b1;
		repeat (4) @(negedge clk);
		d = data_out;
		rd = 1'b0; sel = 1'b0;
		repeat (4) @(negedge clk);
	end
endtask

task automatic codec(input [3:0] index, input [7:0] value);
	begin
		wr(R_INDEX, {12'd0, index}, 1'b0);
		wr(R_DATA, {8'd0, value}, 1'b0);
	end
endtask

reg [15:0] lfsr = 16'hACE1;
task automatic noise_words(input integer n);
	integer i;
	begin
		for (i = 0; i < n; i = i + 1) begin
			lfsr = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
			wr(R_FIFO, lfsr, 1'b1);
		end
	end
endtask

integer level = 0, irqs = 0, bad = 0;

// What toccata.library 9.10 does to the card when it is loaded (its code
// at $F58, with interrupts off and no limit to its waiting): the card
// reset and made active through the status register's high byte, the index
// register not $80, the data format with the mode change bit, the index
// register's top bit clear, autocalibration asked for in register 9, the
// mode change bit taken away, and then register 11's bit 5 (autocalibration
// in progress) first set and then clear. A wait is given up here after
// 400 lines.
task automatic lib_init(input integer n);
	integer t;
	reg [15:0] d;
	begin
		wr_high(R_STATUS, 8'h02);
		repeat (20000) @(negedge clk);
		wr_high(R_STATUS, 8'h01);
		t = 0; d = 16'h0080;
		while (d[7:0] === 8'h80 && t < 100) begin rdreg(R_INDEX, d); t = t + 1; end
		if (d[7:0] === 8'h80) begin $display("FAIL: init %0d: the index register stays $80", n); bad = bad + 1; end
		wr(R_INDEX, 16'h0048, 1'b0);
		wr(R_DATA, 16'h0006, 1'b0);
		t = 0; d = 16'h0080;
		while (d[7] !== 1'b0 && t < 100) begin rdreg(R_INDEX, d); t = t + 1; end
		if (d[7] !== 1'b0) begin $display("FAIL: init %0d: the index register's top bit stays set", n); bad = bad + 1; end
		wr(R_INDEX, 16'h0049, 1'b0);
		rdreg(R_DATA, d);
		wr(R_DATA, {8'h00, d[7:0] | 8'h08}, 1'b0);
		wr(R_INDEX, 16'h000B, 1'b0);
		t = 0; d = 16'h0000;
		while (d[5] !== 1'b1 && t < 90000) begin rdreg(R_DATA, d); t = t + 1; end
		if (d[5] !== 1'b1) begin $display("FAIL: init %0d: autocalibration does not begin (register 11 reads %h)", n, d); bad = bad + 1; end
		t = 0;
		while (d[5] !== 1'b0 && t < 90000) begin rdreg(R_DATA, d); t = t + 1; end
		if (d[5] !== 1'b0) begin $display("FAIL: init %0d: autocalibration does not end", n); bad = bad + 1; end
		wr(R_INDEX, 16'h000C, 1'b0);
		rdreg(R_DATA, d);
		$display("init %0d done: register 12 reads %h", n, d[7:0]);
	end
endtask
task automatic play(input [7:0] format, input integer n);
	integer i, t;
	reg [15:0] d;
	begin
		codec(4'd8, format);
		rdreg(R_DATA, d);
		if (d[7:0] !== format) begin $display("FAIL: the format register reads %h, written %h", d, format); bad = bad + 1; end
		wr(R_STATUS, 16'h0001, 1'b0);
		rdreg(R_STATUS, d);
		if (d !== 16'h8080) begin $display("FAIL: the status reads %h after the card is made active", d); bad = bad + 1; end
		noise_words(400);
		wr(R_STATUS, 16'h0095, 1'b0);
		for (i = 0; i < n; i = i + 1) begin
			t = 0;
			while (toc_int !== 1'b1 && t < 3000000) begin @(negedge clk); t = t + 1; end
			if (toc_int !== 1'b1) begin $display("FAIL: no interrupt (format %h, %0d taken)", format, i); bad = bad + 1; i = n; end
			else begin
				rdreg(R_STATUS, d);
				if (d !== 16'h0808) begin $display("FAIL: the status reads %h at an interrupt", d); bad = bad + 1; end
				codec(4'd6, level[5:0]);
				codec(4'd7, (level * 5 + 7) % 64);
				level = level + 1;
				irqs = irqs + 1;
				noise_words(128);
			end
		end
		wr(R_STATUS, 16'h0002, 1'b0);
		repeat (2000) @(negedge clk);
	end
endtask

reg [1023:0] out_name;
initial begin
	if (!$value$plusargs("out=%s", out_name)) begin $display("FAIL: +out=<file> is missing"); $finish; end
	f = $fopen(out_name, "w");
	repeat (40) @(negedge clk);
	rst = 1'b0;
	repeat (40) @(negedge clk);
	logging = 1'b1;
	lib_init(1);
	play(8'h5B, 20);   // 16 bit stereo, 44100 Hz
	play(8'h1C, 16);   // 8 bit stereo, 48000 Hz
	play(8'h4C, 16);   // 16 bit mono, 48000 Hz
	play(8'h0C, 16);   // 8 bit mono, 48000 Hz
	// the library loaded again (after it was flushed from memory) without
	// a reset of the Amiga between
	lib_init(2);
	$fclose(f);
	$display("RESULT: %0d clocks, %0d interrupts, %0d changes of the outputs, %0d of them a sample on the left", clocks, irqs, changes, sounds);
	if (bad == 0 && irqs == 68 && sounds > 1000) $display("BENCH DONE");
	else $display("FAIL: %0d faults, %0d interrupts, %0d samples", bad, irqs, sounds);
	$finish;
end

endmodule
