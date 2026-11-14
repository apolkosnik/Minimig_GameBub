// Portable replacement for denise_colortable_ram_mf (an altsyncram
// megafunction in the MiSTer tree): 256 x 32 bit simple dual port RAM,
// byte enables on the write port, read address registered under the
// clock enable, unregistered output, old data on a read of the address
// being written.
//
// SPDX-License-Identifier: GPL-3.0-or-later

module denise_colortable_ram_mf
(
	input  [3:0]  byteena_a,
	input         clock,
	input  [31:0] data,
	input         enable,
	input  [7:0]  rdaddress,
	input  [7:0]  wraddress,
	input         wren,
	output [31:0] q
);

reg [31:0] mem [0:255];

integer i;
initial for (i = 0; i < 256; i = i + 1) mem[i] = 32'd0;

reg [31:0] q_r = 32'd0;

always @(posedge clock) begin
	if (enable) begin
		for (int b = 0; b < 4; b = b + 1)
			if (wren & byteena_a[b]) mem[wraddress][b*8 +: 8] <= data[b*8 +: 8];
		q_r <= mem[rdaddress];
	end
end

assign q = q_r;

endmodule
