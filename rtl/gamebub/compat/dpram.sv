// Portable replacement for the dpram entity of the MiSTer bram.vhd
// (altsyncram, BIDIR_DUAL_PORT, single clock).
//
// Behaviour kept from the original:
//  - both ports read and write synchronously
//  - a read on the port that writes returns the new data (write first)
//  - the memory starts at zero
//
// The original's clock enable and chip select ports are not used by any
// module in this core (cpu_cache_new, ide) and are left out, so nothing
// depends on SystemVerilog input port defaults.
//
// Written in the true dual port template from Vivado UG901 so that it maps
// onto block RAM.
//
// SPDX-License-Identifier: GPL-3.0-or-later

module dpram
#(
	parameter addr_width    = 8,
	parameter data_width    = 8,
	parameter mem_init_file = " "
)
(
	input                       clock,

	input      [addr_width-1:0] address_a,
	input      [data_width-1:0] data_a,
	input                       wren_a,
	output reg [data_width-1:0] q_a,

	input      [addr_width-1:0] address_b,
	input      [data_width-1:0] data_b,
	input                       wren_b,
	output reg [data_width-1:0] q_b
);

(* ram_style = "block" *)
reg [data_width-1:0] mem [0:(1<<addr_width)-1];

integer i;
initial begin
	for (i = 0; i < (1<<addr_width); i = i + 1) mem[i] = {data_width{1'b0}};
	q_a = {data_width{1'b0}};
	q_b = {data_width{1'b0}};
end

always @(posedge clock) begin
	if (wren_a) begin
		mem[address_a] <= data_a;
		q_a <= data_a;
	end
	else q_a <= mem[address_a];
end

always @(posedge clock) begin
	if (wren_b) begin
		mem[address_b] <= data_b;
		q_b <= data_b;
	end
	else q_b <= mem[address_b];
end

endmodule
