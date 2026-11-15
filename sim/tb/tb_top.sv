// Full-system simulation of the Game Bub Minimig core: minimig_gamebub
// (the top level the framework binds, with all of its real RTL, the TG68K
// converted from VHDL by GHDL) and a model of the SDRAM chip.
//
// The C++ bench (sim_main.cpp) drives the clocks (the MMCM model in
// sim/rtl/xilinx_sim.sv hands clk_114 and clk_28 to gb_clocks), plays the
// Game Bub MCU on the HostV0 memory interface and command channel the way
// the framework's SPI receiver presents them, presses buttons and captures
// the video and audio outputs as the framework does.
//
// SPDX-License-Identifier: GPL-3.0-or-later

module tb_top
(
	input         clk_114,
	input         clk_28,
	input         mmcm_locked,
	input         reset,

	// HostV0
	input         host_mem_enable,
	input         host_mem_write,
	output        host_mem_done,
	input  [31:0] host_mem_address,
	output [31:0] host_mem_dataRead,
	input  [31:0] host_mem_dataWrite,
	input         host_cmd_request,
	output        host_cmd_busy,
	output        host_cmd_done,
	output        host_cmd_error,
	output        host_core_request,
	input         host_core_busy,
	input         host_core_done,
	input         host_core_error,

	// InputExtendedV0 slot 0 and 1 buttons, in the order
	// {select, start, r1, l1, right, left, down, up, y, x, b, a}
	input  [11:0] buttons,
	input         slot1_active,
	input  [11:0] buttons1,
	// sticks {slot 1 left Y, left X, slot 0 right Y, right X, left Y, left X}
	input  [47:0] sticks,

	// VideoV0 / AudioV0
	output  [2:0] video_r,
	output  [3:0] video_g,
	output  [2:0] video_b,
	output        video_de,
	output        video_hblank,
	output        video_vblank,
	output        video_fit,
	output        video_pal_we,
	output  [9:0] video_pal_index,
	output [23:0] video_pal_color,
	output [15:0] audio_left,
	output [15:0] audio_right,

	// observation
	output        dbg_cpu_rst,       // CPU reset (active low, minimig _cpu_reset)
	output [23:1] dbg_chip_addr,
	output        dbg_chip_as,
	output        dbg_chip_rw,
	output [15:0] dbg_chip_dout,     // CPU write data
	output        dbg_cpuhlt,
	output        dbg_boot_busy,
	output        dbg_boot_done,
	output        dbg_ntsc,
	output        dbg_fdd_idle,
	output        dbg_motor,         // some drive motor on (_motor of ciab, inverted)

	// the SDRAM pins: clock, and every other output the controller drives
	// {cs, ras, cas, we, dqm, ba, a, oe, dout}
	output        dbg_hs_n,          // minimig _hsync / _vsync
	output        dbg_vs_n,
	output [15:0] dbg_beamcon0,
	output  [8:0] dbg_video_vcnt,    // gb_video line counter
	output        dbg_lace,
	output        dbg_ersy,          // Agnus external resync (BPLCON0 bit 1)
	output [12:0] dbg_dmacon,
	output [20:1] dbg_cop_addr,      // copper's chip address pointer
	output        dbg_sd_clk,
	output [38:0] dbg_sd_bus
);

wire        sd_clk, sd_cke, sd_cs, sd_ras, sd_cas, sd_we, sd_oe;
wire  [1:0] sd_dqm, sd_ba;
wire [12:0] sd_a;
wire [15:0] sd_dout, sd_din, mdl_dout;
wire        mdl_oe;

minimig_gamebub #(.DISPLAY_DIVIDER(35)) dut
(
	.clock                   (clk_28),
	.reset                   (reset),
	.clocks_clockIn50M       (1'b0),
	.clocks_clockOutSystem   (),
	.clocks_clockOutDisplay  (),
	.clocks_clockOutSpi      (),
	.clocks_locked           (),
	.video_data_r            (video_r),
	.video_data_g            (video_g),
	.video_data_b            (video_b),
	.video_dataEnable        (video_de),
	.video_vblank            (video_vblank),
	.video_hblank            (video_hblank),
	.video_fit               (video_fit),
	.video_palette_write     (video_pal_we),
	.video_palette_index     (video_pal_index),
	.video_palette_color     (video_pal_color),
	.audio_left              (audio_left),
	.audio_right             (audio_right),
	.host_mem_enable         (host_mem_enable),
	.host_mem_write          (host_mem_write),
	.host_mem_done           (host_mem_done),
	.host_mem_address        (host_mem_address),
	.host_mem_dataRead       (host_mem_dataRead),
	.host_mem_dataWrite      (host_mem_dataWrite),
	.host_commandHost_request(host_cmd_request),
	.host_commandHost_busy   (host_cmd_busy),
	.host_commandHost_done   (host_cmd_done),
	.host_commandHost_error  (host_cmd_error),
	.host_commandCore_request(host_core_request),
	.host_commandCore_busy   (host_core_busy),
	.host_commandCore_done   (host_core_done),
	.host_commandCore_error  (host_core_error),
	.input_slots_0_active      (1'b1),
	.input_slots_0_deviceType  (4'd1),
	.input_slots_0_buttons_a      (buttons[0]),
	.input_slots_0_buttons_b      (buttons[1]),
	.input_slots_0_buttons_x      (buttons[2]),
	.input_slots_0_buttons_y      (buttons[3]),
	.input_slots_0_buttons_up     (buttons[4]),
	.input_slots_0_buttons_down   (buttons[5]),
	.input_slots_0_buttons_left   (buttons[6]),
	.input_slots_0_buttons_right  (buttons[7]),
	.input_slots_0_buttons_l1     (buttons[8]),
	.input_slots_0_buttons_r1     (buttons[9]),
	.input_slots_0_buttons_start  (buttons[10]),
	.input_slots_0_buttons_select (buttons[11]),
	.input_slots_0_buttons_l2     (1'b0),
	.input_slots_0_buttons_r2     (1'b0),
	.input_slots_0_buttons_l3     (1'b0),
	.input_slots_0_buttons_r3     (1'b0),
	.input_slots_0_analog_leftX  (sticks[7:0]),
	.input_slots_0_analog_leftY  (sticks[15:8]),
	.input_slots_0_analog_rightX (sticks[23:16]),
	.input_slots_0_analog_rightY (sticks[31:24]),
	.input_slots_0_analog_leftTrigger  (8'd0),
	.input_slots_0_analog_rightTrigger (8'd0),
	.input_slots_1_active      (slot1_active),
	.input_slots_1_deviceType  (slot1_active ? 4'd2 : 4'd0),
	.input_slots_1_buttons_a      (buttons1[0]),
	.input_slots_1_buttons_b      (buttons1[1]),
	.input_slots_1_buttons_x      (buttons1[2]),
	.input_slots_1_buttons_y      (buttons1[3]),
	.input_slots_1_buttons_up     (buttons1[4]),
	.input_slots_1_buttons_down   (buttons1[5]),
	.input_slots_1_buttons_left   (buttons1[6]),
	.input_slots_1_buttons_right  (buttons1[7]),
	.input_slots_1_buttons_l1     (buttons1[8]),
	.input_slots_1_buttons_r1     (buttons1[9]),
	.input_slots_1_buttons_start  (buttons1[10]),
	.input_slots_1_buttons_select (buttons1[11]),
	.input_slots_1_buttons_l2     (1'b0),
	.input_slots_1_buttons_r2     (1'b0),
	.input_slots_1_buttons_l3     (1'b0),
	.input_slots_1_buttons_r3     (1'b0),
	.input_slots_1_analog_leftX  (sticks[39:32]),
	.input_slots_1_analog_leftY  (sticks[47:40]),
	.input_slots_1_analog_rightX (8'd0),
	.input_slots_1_analog_rightY (8'd0),
	.input_slots_1_analog_leftTrigger  (8'd0),
	.input_slots_1_analog_rightTrigger (8'd0),
	.sdram_clock             (sd_clk),
	.sdram_cke               (sd_cke),
	.sdram_cs                (sd_cs),
	.sdram_ras               (sd_ras),
	.sdram_cas               (sd_cas),
	.sdram_we                (sd_we),
	.sdram_dqm               (sd_dqm),
	.sdram_bank              (sd_ba),
	.sdram_address           (sd_a),
	.sdram_dataIn            (sd_din),
	.sdram_dataOut           (sd_dout),
	.sdram_dataDir           (sd_oe)
);

sdram_sim sdram
(
	.clk       (sd_clk),
	.cke       (sd_cke),
	.cs_n      (sd_cs),
	.ras_n     (sd_ras),
	.cas_n     (sd_cas),
	.we_n      (sd_we),
	.ba        (sd_ba),
	.a         (sd_a),
	.dqm       (sd_dqm),
	.dq_in     (sd_dout),
	.dq_in_en  (sd_oe),
	.dq_out    (mdl_dout),
	.dq_out_en (mdl_oe)
);

// the bus as the pins see it: what the SDRAM drives, else what the FPGA
// drives (the framework's top level makes the tri-state buffer)
assign sd_din = mdl_oe ? mdl_dout : sd_oe ? sd_dout : 16'hFFFF;

assign dbg_cpu_rst   = dut.cpu_rst;
assign dbg_chip_addr = dut.chip_addr;
assign dbg_chip_as   = dut.chip_as;
assign dbg_chip_rw   = dut.chip_rw;
assign dbg_chip_dout = dut.chip_din;    // the CPU's write data (cpu_wrapper chip_din)
assign dbg_cpuhlt    = dut.minimig.cpuhlt;
assign dbg_boot_busy = dut.boot_busy;
assign dbg_boot_done = dut.boot_done;
assign dbg_ntsc      = dut.ntsc;
assign dbg_fdd_idle  = dut.f_idle;
assign dbg_motor     = ~dut.minimig._motor;
assign dbg_sd_clk    = sd_clk;
assign dbg_hs_n      = dut.hs;
assign dbg_vs_n      = dut.vs;
assign dbg_beamcon0  = dut.minimig.AGNUS1.bc1.beamcon0_reg;
assign dbg_video_vcnt= dut.video.vcnt;
assign dbg_lace      = dut.lace;
assign dbg_ersy      = dut.minimig.AGNUS1.bc1.ersy;
assign dbg_dmacon    = dut.minimig.AGNUS1.dmacon;
assign dbg_cop_addr  = dut.minimig.AGNUS1.cp1.address_out;
assign dbg_sd_bus    = {sd_cs, sd_ras, sd_cas, sd_we, sd_dqm, sd_ba, sd_a, sd_oe, sd_dout};

// custom register writes as Agnus takes them (copper location, COPJMP1,
// DMACON), for +regmon
reg regmon = 1'b0;
initial if ($test$plusargs("regmon")) regmon = 1'b1;
always @(posedge clk_28) if (regmon && dut.clk7_en) begin
	if (dut.minimig.reg_address == 8'h40 || dut.minimig.reg_address == 8'h41 ||
	    dut.minimig.reg_address == 8'h42 || dut.minimig.reg_address == 8'h43 ||
	    dut.minimig.reg_address == 8'h44 || dut.minimig.reg_address == 8'h4B)
		$display("regmon: reg %03X <= %04X", {dut.minimig.reg_address, 1'b0}, dut.minimig.custom_data_in);
end
// copper state once per frame (+regmon)
always @(posedge clk_28) if (regmon && dut.clk7_en && dut.minimig.AGNUS1.cp1.sof)
	$display("copmon: sof cop1lc %06X pointer %06X state %0d strobe1 %0d dma_ack %0d",
	         {dut.minimig.AGNUS1.cp1.cop1lch, dut.minimig.AGNUS1.cp1.cop1lcl, 1'b0},
	         {dut.minimig.AGNUS1.cp1.address_out, 1'b0}, dut.minimig.AGNUS1.cp1.copper_state,
	         dut.minimig.AGNUS1.cp1.strobe1, dut.minimig.AGNUS1.cp1.dma_ack);

endmodule
