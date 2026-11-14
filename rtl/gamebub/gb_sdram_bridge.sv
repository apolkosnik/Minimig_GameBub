// Game Bub Minimig: shares the SDRAM controller's host port (clk_mem,
// 4 x clk_sys) between several clients in the clk_sys domain.
//
// clk_sys and clk_mem come from the same MMCM with a 1:4 ratio and aligned
// edges, so signals are passed directly; a four phase handshake makes the
// transfer independent of where in the clk_sys period the SDRAM answers.
//
// Client protocol (clk_sys): raise req[i] with we/addr/dqm/wdata and hold
// all of them until ack[i] (one clock). rdata is valid with ack.
// Lower index = higher priority.
//
// SPDX-License-Identifier: GPL-3.0-or-later

module gb_sdram_bridge
#(
	parameter N = 3
)
(
	input                 clk_sys,
	input                 clk_mem,
	input                 reset,      // clk_sys
	input                 reset_mem,  // the same, synchronous to clk_mem

	input       [N-1:0]   c_req,
	input       [N-1:0]   c_we,
	input       [N*24-1:0] c_addr,   // word address [24:1] per client
	input       [N*2-1:0] c_dqm,     // 1 = byte not written
	input       [N*16-1:0] c_wdata,
	output reg  [N-1:0]   c_ack,
	output reg  [15:0]    c_rdata,

	// sdram_ctrl host port (clk_mem)
	output reg  [24:1]    hostAddr,
	output reg            hostReq,
	output reg            hostWE,
	output reg  [1:0]     hostDQM,
	output reg  [15:0]    hostWR,
	input       [15:0]    hostRD,
	input                 hostAck
);

// ---------------- clk_sys side ----------------
localparam S_IDLE = 2'd0, S_WAIT = 2'd1, S_DROP = 2'd2;

reg  [1:0]  state;
reg         start;
reg  [24:1] a_addr;
reg         a_we;
reg  [1:0]  a_dqm;
reg  [15:0] a_wdata;
reg  [$clog2(N > 1 ? N : 2)-1:0] cur;

reg         done_m;     // clk_mem
reg  [15:0] rd_m;       // clk_mem

integer i;
reg found;
reg [$clog2(N > 1 ? N : 2)-1:0] pick;
always @* begin
	found = 1'b0;
	pick  = '0;
	for (i = N-1; i >= 0; i = i - 1)
		if (c_req[i]) begin
			found = 1'b1;
			pick  = i[$clog2(N > 1 ? N : 2)-1:0];
		end
end

always @(posedge clk_sys) begin
	c_ack <= '0;
	if (reset) begin
		state <= S_IDLE;
		start <= 1'b0;
	end
	else case (state)
		S_IDLE:
			if (found && !done_m) begin
				cur     <= pick;
				a_addr  <= c_addr[pick*24 +: 24];
				a_we    <= c_we[pick];
				a_dqm   <= c_dqm[pick*2 +: 2];
				a_wdata <= c_wdata[pick*16 +: 16];
				start   <= 1'b1;
				state   <= S_WAIT;
			end

		S_WAIT:
			if (done_m) begin
				c_rdata    <= rd_m;
				c_ack[cur] <= 1'b1;
				start      <= 1'b0;
				state      <= S_DROP;
			end

		S_DROP:
			if (!done_m) state <= S_IDLE;

		default: state <= S_IDLE;
	endcase
end

// ---------------- clk_mem side ----------------
reg busy_m;
always @(posedge clk_mem) begin
	if (reset_mem || !start) begin
		hostReq <= 1'b0;
		busy_m  <= 1'b0;
		done_m  <= 1'b0;
	end
	else if (!busy_m && !done_m) begin
		hostAddr <= a_addr;
		hostWE   <= a_we;
		hostDQM  <= a_dqm;
		hostWR   <= a_wdata;
		hostReq  <= 1'b1;
		busy_m   <= 1'b1;
	end
	else if (busy_m && hostAck) begin
		hostReq <= 1'b0;
		busy_m  <= 1'b0;
		rd_m    <= hostRD;
		done_m  <= 1'b1;
	end
end

endmodule
