// The Game Bub's asynchronous SRAM (256K x 16) for the benches, with the
// timing a design must keep checked in half periods of the controller's
// clock (clk: the pins are sampled at both of its edges, each sample being
// the half period that ends there).
//
// Read: the data is the word's only when the address, OE low, WE high and
// both byte enables have been the same for the five half periods before
// (an address put out at a clock edge and taken three clocks later; taken
// after two, the bench sees junk). Otherwise the pins give junk.
// Write: the word is stored when WE rises, from the data then on the pins.
// Checked: WE low for at least two half periods; the address and the byte
// enables unchanged from the half period before WE falls to the one after
// it rises; the data driven and unchanged for the two half periods before
// WE rises and the one after.
// The bus: the FPGA must not drive it (dir) in a half period in which the
// SRAM does (OE low, WE high), nor in the two before or after one.
// SPDX-License-Identifier: GPL-3.0-or-later

module sram_sim
(
	input             clk,
	input             ce_n,
	input             we_n,
	input             oe_n,
	input       [1:0] mask_n,
	input      [17:0] a,
	input      [15:0] din,          // from the FPGA
	input             dir,          // the FPGA drives the bus
	output     [15:0] dout,
	output reg [31:0] errors = 32'd0,
	output reg [31:0] writes = 32'd0,
	output reg [31:0] reads = 32'd0     // read words valid for at least one half period
);

reg [15:0] mem [0:262143];
initial for (int i = 0; i < 262144; i++) mem[i] = 16'h5A5A ^ i[15:0];

// the last samples, newest first
reg [17:0] a_h [0:3];
reg  [1:0] m_h [0:3];
reg [15:0] d_h [0:3];
reg        dir_h [0:3];
reg        we_h [0:3];
reg        drv_h [0:3];         // the SRAM drove the bus
reg  [3:0] rd_stable = 4'd0;    // half periods the read has stood
reg  [3:0] we_low = 4'd0;       // half periods WE has been low
reg        rose = 1'b0;         // WE rose in the last half period
reg [17:0] wa;
reg  [1:0] wm;
reg [15:0] wd;
reg  [7:0] junk = 8'd1;

wire drives = !ce_n && !oe_n && we_n;
wire rd_ok  = drives && (rd_stable >= 4'd5);
assign dout = rd_ok ? mem[a_h[0]] : {junk, ~junk};

task automatic fail(input string what);
	begin
		errors <= errors + 1'd1;
		if (errors < 20) $display("[sram] ERROR %s (a %05x)", what, a);
	end
endtask

always @(posedge clk or negedge clk) begin
	junk <= {junk[6:0], junk[7] ^ junk[5] ^ junk[4] ^ junk[3]};

	// read: how long this address has stood
	if (drives && drv_h[0] && a == a_h[0] && mask_n == m_h[0] && mask_n == 2'b00) begin
		if (~&rd_stable) rd_stable <= rd_stable + 1'd1;
		if (rd_stable == 4'd4) reads <= reads + 1'd1;
	end
	else rd_stable <= drives ? 4'd1 : 4'd0;

	// the bus
	if (dir && drives) fail("the FPGA and the SRAM both drive the data bus");
	if (dir && (drv_h[0] || drv_h[1])) fail("the FPGA drives the bus less than a clock after the SRAM");
	if (drives && (dir_h[0] || dir_h[1])) fail("the SRAM drives the bus less than a clock after the FPGA");

	// write
	rose <= 1'b0;
	if (!we_n && !ce_n) begin
		if (we_h[0]) begin
			// WE fell: the address was there the half period before
			if (a != a_h[0] || mask_n != m_h[0]) fail("address or byte enables change as WE falls");
			we_low <= 4'd1;
		end
		else begin
			if (a != a_h[0] || mask_n != m_h[0]) fail("address or byte enables change while WE is low");
			if (~&we_low) we_low <= we_low + 1'd1;
		end
		if (!oe_n) fail("OE low during a write");
	end
	else if (!we_h[0] && !ce_n) begin
		// WE rose: the word is written from the data of the low half periods
		if (we_low < 4'd2) fail("WE low for less than two half periods");
		if (a != a_h[0] || mask_n != m_h[0]) fail("address or byte enables change as WE rises");
		if (!dir_h[0] || !dir_h[1]) fail("data not driven for a clock before WE rises");
		else if (d_h[0] != d_h[1]) fail("data changes in the clock before WE rises");
		if (!dir || din != d_h[0]) fail("data not held after WE rises");
		if (!m_h[0][0]) mem[a_h[0]][7:0]  <= d_h[0][7:0];
		if (!m_h[0][1]) mem[a_h[0]][15:8] <= d_h[0][15:8];
		writes <= writes + 1'd1;
		rose   <= 1'b1;
		wa <= a_h[0]; wm <= m_h[0]; wd <= d_h[0];
		we_low <= 4'd0;
	end
	if (rose && (a != wa || mask_n != wm)) fail("address or byte enables not held after WE rises");

	a_h[0] <= a; m_h[0] <= mask_n; d_h[0] <= din; dir_h[0] <= dir; we_h[0] <= we_n; drv_h[0] <= drives;
	for (int i = 1; i < 4; i++) begin
		a_h[i] <= a_h[i-1]; m_h[i] <= m_h[i-1]; d_h[i] <= d_h[i-1];
		dir_h[i] <= dir_h[i-1]; we_h[i] <= we_h[i-1]; drv_h[i] <= drv_h[i-1];
	end
end

initial begin
	for (int i = 0; i < 4; i++) begin
		a_h[i] = '0; m_h[i] = 2'b11; d_h[i] = '0; dir_h[i] = 1'b0; we_h[i] = 1'b1; drv_h[i] = 1'b0;
	end
end

endmodule
