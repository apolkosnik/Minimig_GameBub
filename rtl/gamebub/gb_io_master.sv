// Game Bub Minimig: master side of the Minimig "HPS" I/O bus.
//
// On MiSTer the ARM (Main_MiSTer) talks to the core through hps_io with the
// signals IO_UIO / IO_FPGA (chip selects), IO_STROBE (one clock per 16 bit
// word), IO_DIN, IO_DOUT and IO_WAIT. userio.v (configuration, memory
// upload) listens on IO_UIO and paula_floppy.v on IO_FPGA. This module
// produces exactly that bus for the logic that replaces the ARM.
//
// Client protocol (all on clk):
//   - drive sel = 2'b01 (UIO) or 2'b10 (FPGA) for a whole transaction
//     ("EnableIO()/EnableFpga()"), 2'b00 between transactions;
//   - for every word raise req with wdata and hold both until ack;
//     ack is high for one clock, rdata is the word the target returned.
//   - ready is low while the chip select is settling; req is only taken
//     when ready is high.
//
// Timing kept from hps_io: the chip select is low for at least DESEL
// clocks between transactions (paula_floppy samples it on clk7_en) and
// high for two clocks before the first strobe.
//
// SPDX-License-Identifier: GPL-3.0-or-later

module gb_io_master
#(
	parameter DESEL = 12
)
(
	input             clk,
	input             reset,

	input       [1:0] sel,
	input             req,
	input      [15:0] wdata,
	output reg        ack,
	output reg [15:0] rdata,
	output            ready,

	output reg        IO_UIO,
	output reg        IO_FPGA,
	output reg        IO_STROBE,
	output reg [15:0] IO_DIN,
	input             IO_WAIT,
	input      [15:0] IO_DOUT
);

localparam S_IDLE = 2'd0, S_STROBE = 2'd1, S_WAIT = 2'd2, S_ACK = 2'd3;

reg  [1:0] state;
reg  [1:0] cur_sel;
reg  [4:0] desel_cnt;
reg  [1:0] sel_cnt;
reg  [1:0] hold;

assign ready = (state == S_IDLE) && (sel != 2'b00) && (sel == cur_sel) && (sel_cnt == 2'd2);

always @(posedge clk) begin
	ack       <= 1'b0;
	IO_STROBE <= 1'b0;

	if (reset) begin
		state     <= S_IDLE;
		cur_sel   <= 2'b00;
		IO_UIO    <= 1'b0;
		IO_FPGA   <= 1'b0;
		IO_DIN    <= 16'h0000;
		desel_cnt <= DESEL[4:0];
		sel_cnt   <= 2'd0;
	end
	else begin
		// chip select tracking (only changes between words)
		if (state == S_IDLE) begin
			if (sel != cur_sel) begin
				if (cur_sel != 2'b00) begin
					// end of a transaction: deselect first
					cur_sel   <= 2'b00;
					IO_UIO    <= 1'b0;
					IO_FPGA   <= 1'b0;
					desel_cnt <= 5'd0;
					sel_cnt   <= 2'd0;
				end
				else if (desel_cnt >= DESEL[4:0]) begin
					cur_sel <= sel;
					IO_UIO  <= sel[0];
					IO_FPGA <= sel[1];
					sel_cnt <= 2'd0;
				end
			end
			if (cur_sel == 2'b00 && desel_cnt < DESEL[4:0]) desel_cnt <= desel_cnt + 5'd1;
			if (cur_sel != 2'b00 && sel == cur_sel && sel_cnt != 2'd2) sel_cnt <= sel_cnt + 2'd1;
		end

		case (state)
			S_IDLE:
				if (req && ready) begin
					IO_DIN    <= wdata;
					IO_STROBE <= 1'b1;
					hold      <= 2'd2;
					state     <= S_STROBE;
				end

			// let IO_WAIT (registered in the targets) become visible
			S_STROBE:
				if (hold != 2'd0) hold <= hold - 2'd1;
				else state <= S_WAIT;

			S_WAIT:
				if (!IO_WAIT) begin
					rdata <= IO_DOUT;
					ack   <= 1'b1;
					state <= S_ACK;
				end

			// the client drops req on ack
			S_ACK: state <= S_IDLE;
		endcase
	end
end

endmodule
