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
	input         clk_57,            // CLKOUT5: 2 x clk_28 (the AP68040 variant's CPU clock)
	input         clk_av,            // the pixel clock of the screen shown (the framework's clock_av)
	input         hdmi,              // HDMI is shown, not the handheld's panel (steady)
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
	output [17:0] video_data,        // the pixel sent (gb_video): 6 + 6 + 6 bits
	output        video_de,
	output        video_hblank,
	output        video_vblank,
	output        video_fit,
	output        video_wide,        // 800 x 240 frames (Picture: 800 x 480)
	output [23:0] dbg_pixel_color,   // the chipset's colour of the pixel sent, with video_de

	// the screen (sim/rtl/fw_video_sim.sv: the framework's side, every
	// pixel shown compared with the frames written) and the SRAM
	// (sim/rtl/sram_sim.sv: the pins' timing)
	output [31:0] disp_errors,
	output [63:0] disp_pixels,
	output [31:0] disp_screens,
	output [63:0] disp_old,
	output [31:0] disp_unwritten,    // pixels shown from memory no frame wrote (not compared)
	output [31:0] disp_frames,
	output [31:0] disp_dropped,
	output [31:0] sram_errors,
	output [31:0] sram_writes,
	output [31:0] sram_reads,
	output [31:0] store_errors,      // pixels handed to the core's memory or found in it that are not as sent
	output [31:0] dbg_hdd_ahead,     // hard disk sectors that came out of the buffer read ahead
	output [15:0] fb_lines,
	output [15:0] fb_late,
	output        fb_overflow,
	output [15:0] audio_left,
	output [15:0] audio_right,

	// observation
	output        dbg_cpu_rst,       // CPU reset (active low, minimig _cpu_reset)
	output [23:1] dbg_chip_addr,
	output        dbg_chip_as,
	output        dbg_chip_rw,
	output        dbg_chip_long,     // a 32-bit CPU chip bus cycle (cpu_wrapper chip_long)
	output        dbg_ram_long,      // the CPU takes a long word from / to its RAM in one transfer
	output  [3:0] dbg_sd_state,      // gb_sdram_ctrl: the window's state
	output  [2:0] dbg_sd_c0,         // and the slots' types (CPU_RD 2, CPU_WR 3)
	output  [2:0] dbg_sd_c1,
	output        dbg_sd_c0_l2,      // a CPU write slot with the long word's second word
	output        dbg_sd_c1_l2,
	output        dbg_line,          // the AP68040's bridge: a line request answered (else 0)
	output        dbg_line_busy,     // and a line request outstanding
	output        dbg_line_hi,       // its address above the 24-bit space (Zorro III, RTG)
	output        dbg_req,           // the bridge's request to the adapter
	output        dbg_ack,           // and its acknowledge
	output        dbg_ram_wait,      // the RAM port selected, not ready
	output [31:0] dbg_pc,            // where the CPU is: the AP68040's PC; the TG68K's last fetch address
	output  [2:0] dbg_ipl,           // the interrupt level at the CPU (active low)
	output [14:0] dbg_intreq,        // Paula INTREQ and INTENA
	output [14:0] dbg_intena,
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
	output [39:0] dbg_sd_bus,

	// RTG picture: the pixel (x, y) whose colour comes out now
	output        rtg_enable,
	output [10:0] rtg_x,
	output  [9:0] rtg_y,
	output [23:0] rtg_color,
	output [15:0] rtg_lines,
	output [15:0] rtg_late,
	output [11:0] rtg_hsize,
	output [11:0] rtg_vsize,
	output  [4:0] rtg_format,
	output [31:0] rtg_base,
	output [13:0] rtg_stride
);

// The framework's video side (sim/rtl/fw_video_sim.sv): the frames'
// bookkeeping, the screen shown (the panel, or with `hdmi` the 1650 x 750
// frame of 720p) and the external picture's inputs made from it, as
// HandheldTop does with patches/framework. The colour of the pixel named
// must come 12 clocks (externalLatency) later: for the RTG check the
// coordinates are delayed by as much (HDMI).
localparam EXT_LATENCY = 12;
wire        fw_frame, fw_drop;
wire        ext_hdmi, ext_sync, ext_frame;
wire [10:0] ext_x;
wire  [9:0] ext_y;
fw_video_sim fw
(
	.clk_sys        (clk_28),
	.reset          (reset),
	.hdmi           (hdmi),
	.de             (video_de),
	.hblank         (video_hblank),
	.vblank         (video_vblank),
	.data           (video_data),
	.fit            (video_fit),
	.wide           (video_wide),
	.wr_frame       (fw_frame),
	.wr_drop        (fw_drop),
	.clk_av         (clk_av),
	.ext_hdmi       (ext_hdmi),
	.ext_x          (ext_x),
	.ext_y          (ext_y),
	.ext_sync       (ext_sync),
	.ext_frame      (ext_frame),
	.ext_color      (rtg_color),
	// once both frames have a picture; not the RTG board's picture
	.check          (disp_frames >= 32'd3 && !(rtg_enable && hdmi)),
	.errors         (disp_errors),
	.pixels         (disp_pixels),
	.screens        (disp_screens),
	.frames_done    (disp_frames),
	.frames_dropped (disp_dropped),
	.old_pixels     (disp_old),
	.unwritten      (disp_unwritten)
);
// The frames in the core's memory against the frames as the framework's
// side has them: every pixel of a frame, a few lines after its last pixel
// (the write queue empty by then).
reg  [31:0] st_errors = 32'd0, ck_errors = 32'd0;
assign store_errors = st_errors + ck_errors;
reg         st_vb_d = 1'b1;
reg   [9:0] st_wait = 10'd0;
reg         st_idx = 1'b0;
reg         st_kept = 1'b0;
always @(posedge clk_28) begin
	st_vb_d <= video_vblank;
	if (video_vblank && !st_vb_d) begin
		st_wait <= 10'd1000;
		st_idx  <= fw.writeIndex;
		st_kept <= !fw.dropReg && fw.frameStarted && (disp_frames >= 32'd2);
	end
	else if (st_wait != 10'd0) begin
		st_wait <= st_wait - 1'd1;
		if (st_wait == 10'd1 && st_kept && !reset) begin
			int bad;
			bad = 0;
			// (the lines sent: 256 with fit, else 240; 800 pixels each wide)
			for (int i = 0; i < int'(fw.lw) * (video_fit ? 256 : 240); i++) begin
				int q;
				reg [17:0] have;
				q = (st_idx ? fw.FS : 0) + i;
				if (q < 262144) have = {sram.mem[q], dut.fb.bx[q]};
				else if (q < 262144 + 65536) have = dut.fb.bh0[q - 262144];
				else if (q < 262144 + 98304) have = dut.fb.bh1[q - 262144 - 65536];
				else if (q < 262144 + 114688) have = dut.fb.bh2[q - 262144 - 98304];
				else have = dut.fb.bh3[q - 262144 - 114688];
				if (have !== fw.mem[q]) begin
					bad++;
					if (st_errors < 8 && bad <= 4)
						$display("[store] ERROR at %0t: frame %0d (the core's %0d), line %0d, pixel %0d: the memory has %05x, sent %05x",
						         $time, st_idx, disp_frames, i / int'(fw.lw), i % int'(fw.lw), have, fw.mem[q]);
				end
			end
			if (bad != 0) st_errors <= st_errors + bad;
		end
	end
end

// Every pixel as the core hands it to its memory against the framework's
// side: the same place, the same value
reg        ck_v = 1'b0;
reg [18:0] ck_a;
reg [17:0] ck_d;
reg        ck_tgl = 1'b0;
integer    ck_bad = 0;
always @(posedge clk_28) begin
	ck_v <= video_de && !fw_drop && !reset && fw.fx < fw.lw && fw.fy < fw.lh;
	ck_a <= fw.waddr;
	ck_d <= video_data;
	ck_tgl <= dut.fb.w_tgl;
	if (ck_v && (dut.fb.w_tgl == ck_tgl || dut.fb.w_q != ck_a || dut.fb.w_d != ck_d)) ck_errors <= ck_errors + 1'd1;
	if (ck_v && (dut.fb.w_tgl == ck_tgl || dut.fb.w_q != ck_a || dut.fb.w_d != ck_d) && ck_bad < 12) begin
		ck_bad = ck_bad + 1;
		$display("[store] ERROR pixel handed over wrongly at %0t: framework %05x = %05x, core %05x = %05x (handed %0d); line %0d pixel %0d, hblank %b vblank %b, core row %05x",
		         $time, ck_a, ck_d, dut.fb.w_q, dut.fb.w_d, dut.fb.w_tgl != ck_tgl, fw.fy, fw.fx, video_hblank, video_vblank, dut.fb.w_row);
	end
end

reg  [10:0] dly_x [0:EXT_LATENCY-1];
reg   [9:0] dly_y [0:EXT_LATENCY-1];
always @(posedge clk_av) begin
	dly_x[0] <= ext_x;
	dly_y[0] <= ext_y;
	for (int i = 1; i < EXT_LATENCY; i++) begin
		dly_x[i] <= dly_x[i - 1];
		dly_y[i] <= dly_y[i - 1];
	end
end
assign rtg_x = dly_x[EXT_LATENCY - 1];
assign rtg_y = dly_y[EXT_LATENCY - 1];
assign rtg_lines  = dut.rtg_lines;
assign rtg_late   = dut.rtg_late;
assign rtg_hsize  = dut.rtg.r_hsize;
assign rtg_vsize  = dut.rtg.r_vsize;
assign rtg_format = dut.rtg.r_format;
assign rtg_base   = dut.rtg.r_base;
assign rtg_stride = dut.rtg.r_stride;

wire        sd_clk, sd_ras, sd_cas, sd_we, sd_oe;
wire  [1:0] sd_cke, sd_cs;      // one per chip
wire  [1:0] sd_dqm, sd_ba;
wire [12:0] sd_a;
wire [15:0] sd_dout, sd_din, mdl_dout;
wire        mdl_oe;
wire [15:0] mdl1_dout;
wire        mdl1_oe;

wire        sram_ce, sram_we, sram_oe, sram_dir;
wire  [1:0] sram_mask;
wire [17:0] sram_a;
wire [15:0] sram_q, sram_d;
sram_sim sram
(
	.clk    (clk_114),
	.ce_n   (sram_ce),
	.we_n   (sram_we),
	.oe_n   (sram_oe),
	.mask_n (sram_mask),
	.a      (sram_a),
	.din    (sram_d),
	.dir    (sram_dir),
	.dout   (sram_q),
	.errors (sram_errors),
	.writes (sram_writes),
	.reads  (sram_reads)
);

assign video_wide = dut.video_wide;
minimig_gamebub #(.DISPLAY_DIVIDER(35)) dut
(
	.clock                   (clk_28),
	.reset                   (reset),
	.clocks_clockIn50M       (1'b0),
	.clocks_clockOutSystem   (),
	.clocks_clockOutDisplay  (),
	.clocks_clockOutSpi      (),
	.clocks_locked           (),
	.video_data_r            (),
	.video_data_g            (),
	.video_data_b            (),
	.video_dataEnable        (video_de),
	.video_vblank            (video_vblank),
	.video_hblank            (video_hblank),
	.video_fit               (video_fit),
	.video_external_clock    (clk_av),
	.video_external_active   (1'b1),
	.video_external_hdmi     (ext_hdmi),
	.video_external_x        (ext_x),
	.video_external_y        (ext_y),
	.video_external_sync     (ext_sync),
	.video_external_frame    (ext_frame),
	.video_external_color    (rtg_color),
	.video_external_enable   (),
	.video_frames_write      (fw_frame),
	.video_frames_drop       (fw_drop),
	.sram_ceN                (sram_ce),
	.sram_weN                (sram_we),
	.sram_oeN                (sram_oe),
	.sram_writeMaskN         (sram_mask),
	.sram_address            (sram_a),
	.sram_dataIn             (sram_q),
	.sram_dataOut            (sram_d),
	.sram_dataDir            (sram_dir),
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

// the two SDRAM chips on the one bus: chip 0 (sdram) and chip 1 (sdram1)
sdram_sim sdram
(
	.clk       (sd_clk),
	.cke       (sd_cke[0]),
	.cs_n      (sd_cs[0]),
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

sdram_sim sdram1
(
	.clk       (sd_clk),
	.cke       (sd_cke[1]),
	.cs_n      (sd_cs[1]),
	.ras_n     (sd_ras),
	.cas_n     (sd_cas),
	.we_n      (sd_we),
	.ba        (sd_ba),
	.a         (sd_a),
	.dqm       (sd_dqm),
	.dq_in     (sd_dout),
	.dq_in_en  (sd_oe),
	.dq_out    (mdl1_dout),
	.dq_out_en (mdl1_oe)
);

// The data bus, edge by edge (counted as errors of chip 0): the beat of an
// SDRAM clock edge comes from one device at most (the FPGA: sd_oe in the
// clk_114 cycle around the edge; a chip: the beat it drives for the edge),
// and between beats of different devices there is an edge with none (the
// time a chip takes to stop driving after its last beat, tHZ, is most of
// an 8.8 ns clock; the next device starts driving a clock before its beat).
reg [2:0] bus_prev = 3'b000;
always @(posedge sd_clk) begin
	reg [2:0] drv;
	drv = {sd_oe, sdram1.beat_v, sdram.beat_v};
	if (drv != 3'b000 && drv != 3'b001 && drv != 3'b010 && drv != 3'b100) begin
		sdram.errors = sdram.errors + 1;
		if (sdram.errors <= 20) $display("[sdram] ERROR at %0t: data bus driven by %b (FPGA, chip 1, chip 0)", $time, drv);
	end
	else if (drv != 3'b000 && bus_prev != 3'b000 && drv != bus_prev) begin
		sdram.errors = sdram.errors + 1;
		if (sdram.errors <= 20) $display("[sdram] ERROR at %0t: data bus passes from %b to %b without an idle clock", $time, bus_prev, drv);
	end
	bus_prev <= drv;
end

// the bus as the pins see it: what the SDRAM drives, else what the FPGA
// drives (the framework's top level makes the tri-state buffer)
assign sd_din = mdl_oe ? mdl_dout : mdl1_oe ? mdl1_dout : sd_oe ? sd_dout : 16'hFFFF;

`ifdef RAMTRACE
// (debug) the CPU's RAM port accesses to the second SDRAM chip, at the end
// of each (ramready while the port is selected)
always @(posedge dut.clk_sys)
	if (dut.ram_sel && dut.ram_ready && dut.cpu_sdram_addr[25])
		$display("RAM %07X %s st%0d uds%b lds%b din %04X dout %04X", {dut.cpu_sdram_addr, 1'b0},
		         (dut.cpu_state == 3) ? "W" : "R", dut.cpu_state, dut.ram_uds, dut.ram_lds, dut.ram_din, dut.ram_dout);
`endif

assign dbg_cpu_rst   = dut.cpu_rst;
assign dbg_pixel_color = dut.video.dbg_color;
assign video_data    = dut.video_data;
assign rtg_enable    = dut.rtg_on;
assign fb_lines      = dut.fb_lines;
assign dbg_hdd_ahead = dut.ide_server.dbg_ahead;
assign fb_late       = dut.fb_late;
assign fb_overflow   = dut.fb_overflow;
assign dbg_chip_addr = dut.chip_addr;
assign dbg_chip_as   = dut.chip_as;
assign dbg_chip_rw   = dut.chip_rw;
assign dbg_chip_long = dut.chip_long;
assign dbg_ram_long = dut.cpu_wrapper.long_ack & dut.cpu_wrapper.clkena_p_throttled;
assign dbg_ram_wait = dut.ram_sel & ~dut.ram_ready;
assign dbg_sd_state = dut.ram1.sdram_state;
assign dbg_sd_c0    = dut.ram1.c0_type;
assign dbg_sd_c1    = dut.ram1.c1_type;
assign dbg_sd_c0_l2 = dut.ram1.c0_l2;
assign dbg_sd_c1_l2 = dut.ram1.c1_l2;
reg [31:0] fetch_q = 32'd0;
always @(posedge dut.cpu_wrapper.clk)
	if (dut.cpu_wrapper.clkena_p_throttled && dut.cpu_wrapper.cpu_req && dut.cpu_wrapper.cpustate == 2'd0)
		fetch_q <= dut.cpu_wrapper.cpu_addr_m;
assign dbg_ipl    = dut.cpu_wrapper.cpu_ipl;
assign dbg_intreq = dut.minimig.PAULA1.pi1.intreq[14:0];
assign dbg_intena = dut.minimig.PAULA1.pi1.intena[14:0];
`ifdef AP68040
// (the core's dbg_pc output is zero unless it is built with DEBUG: the PC of
// the instruction last in its writeback stage)
reg [31:0] pc040_q = 32'd0;
always @(posedge dut.cpu_wrapper.cpu_inst_p.clk)
	if (dut.cpu_wrapper.cpu_inst_p.core.be.wb_v) pc040_q <= dut.cpu_wrapper.cpu_inst_p.core.be.wb_u.pc;
assign dbg_pc       = pc040_q;
assign dbg_line     = dut.cpu_wrapper.mem_ack & dut.cpu_wrapper.mem_line;
assign dbg_line_busy = dut.cpu_wrapper.mem_req & dut.cpu_wrapper.mem_line;
assign dbg_line_hi  = |dut.cpu_wrapper.mem_addr[31:24];
assign dbg_req      = dut.cpu_wrapper.mem_req;
assign dbg_ack      = dut.cpu_wrapper.mem_ack;
`else
assign dbg_pc       = fetch_q;
assign dbg_line_hi  = 1'b0;
assign dbg_req      = 1'b0;
assign dbg_ack      = 1'b0;
assign dbg_line     = 1'b0;
assign dbg_line_busy = 1'b0;
`endif
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

`ifdef AP68040
// +cputrace=<file> [+cputrace_n=<clocks>]: the inputs and the outputs of the
// AP68040 behind its bridge (ap68040_minimig) as they are before every CPU
// clock edge, for the netlist test (sim/gls/run_cpu_gls.sh): one line per
// run of equal clocks, "<clocks> <inputs> <outputs>" (hexadecimal; the
// signals in the order of sim/gls/cpu_tb.sv). The count of clocks starts
// when the reset ends (default 2000000).
integer      ct_f = 0;
integer      ct_max = 2000000;
integer      ct_n = 0, ct_run = 0;
reg          ct_live = 1'b0;
reg  [200:0] ct_i;
reg  [301:0] ct_o;
string       ct_name;
wire [200:0] ct_in = {dut.cpu_wrapper.cpu_inst_p.ar_on,
	dut.cpu_wrapper.cpu_inst_p.nreset, dut.cpu_wrapper.cpu_inst_p.chipcode,
	dut.cpu_wrapper.cpu_inst_p.cw_tgl, dut.cpu_wrapper.cpu_inst_p.cw_line,
	dut.cpu_wrapper.cpu_inst_p.z2ram_ena,
	dut.cpu_wrapper.cpu_inst_p.z3ram_base0, dut.cpu_wrapper.cpu_inst_p.z3ram_ena0,
	dut.cpu_wrapper.cpu_inst_p.z3ram_base1, dut.cpu_wrapper.cpu_inst_p.z3ram_ena1,
	dut.cpu_wrapper.cpu_inst_p.mem_ack, dut.cpu_wrapper.cpu_inst_p.mem_rdata,
	dut.cpu_wrapper.cpu_inst_p.mem_rline,
	dut.cpu_wrapper.cpu_inst_p.mem_berr, dut.cpu_wrapper.cpu_inst_p.ipl_n};
wire [301:0] ct_out = {dut.cpu_wrapper.cpu_inst_p.mem_req, dut.cpu_wrapper.cpu_inst_p.mem_write,
	dut.cpu_wrapper.cpu_inst_p.mem_instr, dut.cpu_wrapper.cpu_inst_p.mem_size,
	dut.cpu_wrapper.cpu_inst_p.mem_addr, dut.cpu_wrapper.cpu_inst_p.mem_wdata,
	dut.cpu_wrapper.cpu_inst_p.mem_tm, dut.cpu_wrapper.cpu_inst_p.mem_ci,
	dut.cpu_wrapper.cpu_inst_p.mem_line, dut.cpu_wrapper.cpu_inst_p.mem_wline,
	dut.cpu_wrapper.cpu_inst_p.nmi_ack_toggle, dut.cpu_wrapper.cpu_inst_p.nresetout,
	dut.cpu_wrapper.cpu_inst_p.cacr_out, dut.cpu_wrapper.cpu_inst_p.vbr_out,
	dut.cpu_wrapper.cpu_inst_p.cache_maint_toggle, dut.cpu_wrapper.cpu_inst_p.debug_halted,
	dut.cpu_wrapper.cpu_inst_p.debug_pc};
initial if ($value$plusargs("cputrace=%s", ct_name)) begin
	ct_f = $fopen(ct_name, "w");
	if ($value$plusargs("cputrace_n=%d", ct_max)) begin end
	ct_live = 1'b1;
end
always @(posedge dut.cpu_wrapper.cpu_inst_p.clk) if (ct_live) begin
	if (ct_run != 0 && (ct_in != ct_i || ct_out != ct_o)) begin
		$fwrite(ct_f, "%0d %h %h\n", ct_run, ct_i, ct_o);
		ct_run <= 1;
	end
	else
		ct_run <= ct_run + 1;
	ct_i <= ct_in;
	ct_o <= ct_out;
	if (ct_in[199]) ct_n <= ct_n + 1;
	if (ct_n == ct_max) begin
		// the last line: this clock with the run it belongs to, or (the run
		// before it written above) on its own
		if (ct_run != 0 && (ct_in != ct_i || ct_out != ct_o))
			$fwrite(ct_f, "1 %h %h\n", ct_in, ct_out);
		else
			$fwrite(ct_f, "%0d %h %h\n", ct_run + 1, ct_i, ct_o);
		$fclose(ct_f);
		ct_live <= 1'b0;
	end
end
// (the run ended before that many clocks: the last run of equal clocks too)
final if (ct_live) begin
	$fwrite(ct_f, "%0d %h %h\n", ct_run, ct_i, ct_o);
	$fclose(ct_f);
end

`endif

// +busmon=<n>: the CPU's first <n> bus cycles after every reset, as
// cpu_wrapper completes them (state 0 fetch, 2 read, 3 write): the data, what
// answered (the RAM port or the chip bus), and whether the chip bus took it
// as half of a 32-bit access (c32)
integer bm_max = 0, bm_n = 0;
initial if ($value$plusargs("busmon=%d", bm_max)) begin end
always @(posedge dut.cpu_wrapper.clk) begin
	if (!dut.cpu_wrapper.reset) bm_n <= 0;
	else if (bm_n < bm_max && dut.cpu_wrapper.clkena_p_throttled && dut.cpu_wrapper.cpu_req) begin
		bm_n <= bm_n + 1;
		$display("busmon %0d: state %0d addr %08X %s%s%s din %04X hi %04X | ram %b (chip %b kick %b zram %b) dat_sel %0d ready: chip %b ram %b ram_l %b fastchip %b | long %b cand %b ack %b | chip32_en %b c32 %b ovl %b",
		         bm_n, dut.cpu_wrapper.cpustate, dut.cpu_wrapper.cpu_addr_m,
		         dut.cpu_wrapper.wr ? "R" : "W", dut.cpu_wrapper.uds_in ? "-" : "U", dut.cpu_wrapper.lds_in ? "-" : "L",
		         dut.cpu_wrapper.cpu_din, dut.cpu_wrapper.ramdout_hi_s,
		         dut.cpu_wrapper.ramsel_i, dut.cpu_wrapper.sel_chipram, dut.cpu_wrapper.sel_kickram, dut.cpu_wrapper.sel_zram,
		         dut.cpu_wrapper.ramdat_sel, dut.cpu_wrapper.chipready, dut.cpu_wrapper.ramready, dut.cpu_wrapper.ramready_l,
		         dut.cpu_wrapper.fastchip_ready, dut.cpu_wrapper.longword, dut.cpu_wrapper.long_cand, dut.cpu_wrapper.long_ack,
		         dut.cpu_wrapper.chip32_en, dut.cpu_wrapper.c32, dut.minimig.ovl);
	end
end

longint   rm_t = 0;      // clk_28 cycles since the start (+rstmon, +smcmon)

// +smcmon=<ms>: from then on, the CPU's writes to words it has fetched as
// code since the core's start (chip RAM and the first 16 MB of a Zorro III
// board at $40000000): the write, where the CPU was (its last fetch on the
// bus) and how many fetches ago the word was fetched last. Consecutive
// writes are printed as one range. (A variable right behind an RTS shows up
// too: the CPU has fetched that word once.)
integer    sm_from = -1;
bit        sm_chip [0:1048575];
bit        sm_z3   [0:8388607];
integer    sm_when_chip [0:1048575];
integer    sm_n = 0, sm_lines = 0, sm_run = 0;
reg [31:0] sm_pc = 32'd0, sm_a0 = 32'd0, sm_a1 = 32'd0, sm_pc0 = 32'd0;
integer    sm_age0 = 0;
initial if ($value$plusargs("smcmon=%d", sm_from)) begin end
wire [31:0] sm_a = dut.cpu_wrapper.cpu_addr_m;
wire        sm_inchip = (sm_a[31:21] == 11'd0);
wire        sm_inz3   = (sm_a[31:24] == 8'h40);
always @(posedge dut.cpu_wrapper.clk) if (sm_from >= 0 && dut.cpu_wrapper.clkena_p_throttled && dut.cpu_wrapper.cpu_req) begin
	if (dut.cpu_wrapper.cpustate == 2'd0) begin
		sm_n  <= sm_n + 1;
		sm_pc <= sm_a;
		if (sm_inchip) begin sm_chip[sm_a[20:1]] = 1'b1; sm_when_chip[sm_a[20:1]] = sm_n; end
		if (sm_inz3)   sm_z3[sm_a[23:1]] = 1'b1;
	end
	else if (dut.cpu_wrapper.cpustate == 2'd3 && rm_t >= sm_from * 28375 &&
	         ((sm_inchip && sm_chip[sm_a[20:1]]) || (sm_inz3 && sm_z3[sm_a[23:1]]))) begin
		if (sm_run != 0 && sm_a == sm_a1 + 32'd2) begin
			sm_a1  <= sm_a;
			sm_run <= sm_run + 1;
		end
		else begin
			if (sm_run != 0 && sm_lines < 20000) begin
				sm_lines <= sm_lines + 1;
				$display("smcmon %0d us: %08X..%08X written (%0d words) from %08X, first fetched %0d fetches before", rm_t * 10 / 284,
				         sm_a0, sm_a1, sm_run, sm_pc0, sm_age0);
			end
			sm_a0  <= sm_a;
			sm_a1  <= sm_a;
			sm_pc0 <= sm_pc;
			sm_age0 <= sm_inchip ? sm_n - sm_when_chip[sm_a[20:1]] : -1;
			sm_run <= 1;
		end
	end
end

// +rstmon: the reset sequence (the menu's Reset action: gb_host's boot
// request, gb_boot's sequence, the resets it sends through userio)
reg       rstmon = 1'b0;
reg [7:0] rm_q = 8'd0;
wire [7:0] rm_d = {dut.f_idle, dut.hdd_mount_busy, dut.boot_start, dut.boot_busy, dut.minimig.cpuhlt, dut.minimig.cpurst,
                   dut.minimig.usrrst, dut.cpu_rst};
initial if ($test$plusargs("rstmon")) rstmon = 1'b1;
always @(posedge clk_28) begin
	rm_q <= rm_d;
	rm_t <= rm_t + 1;
	if (rstmon && rm_d[6:0] != rm_q[6:0])   // (the floppy server's polls alone are not printed)
		$display("rstmon %0d us: floppy idle %b, hdd mount busy %b, boot_start %b busy %b, cpuhlt %b cpurst %b usrrst %b, cpu_rst(n) %b",
		         rm_t * 10 / 284, rm_d[7], rm_d[6], rm_d[5], rm_d[4], rm_d[3], rm_d[2], rm_d[1], rm_d[0]);
end

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

// +toctrace: every access of the CPU to the Toccata sound card (the
// address in the board, what was written or what the board gave), its
// interrupt's edges and its select's, each with the system clock's count
reg         toc_tr = 1'b0;
reg         toc_p = 1'b0, toc_w = 1'b0, toc_i = 1'b0, toc_s = 1'b0;
reg  [39:0] toc_n = 40'd0;
reg  [15:0] toc_a, toc_d, toc_q;
reg   [1:0] toc_be;
initial toc_tr = $test$plusargs("toctrace") != 0;
always @(posedge dut.clk_sys) if (toc_tr) begin : toc_trace
	reg act;
	toc_n <= toc_n + 40'd1;
	toc_s <= dut.minimig.sel_toccata;
	if (toc_s != dut.minimig.sel_toccata) $display("TOC %0d select %b", toc_n, dut.minimig.sel_toccata);
	act = dut.minimig.sel_toccata & (dut.minimig.cpu_rd | dut.minimig.cpu_hwr | dut.minimig.cpu_lwr);
	if (act) begin
		toc_a  <= {dut.minimig.cpu_address_out[15:1], 1'b0};
		toc_w  <= ~dut.minimig.cpu_rd;
		toc_d  <= dut.minimig.cpu_data_out;
		toc_be <= {dut.minimig.cpu_hwr, dut.minimig.cpu_lwr};
		if (dut.minimig.toccata_out != 16'h0000) toc_q <= dut.minimig.toccata_out;
	end
	else toc_q <= dut.minimig.toccata_out;
	if (toc_p && !act) begin
		if (toc_w) $display("TOC %0d W %04X %04X hl%b", toc_n, toc_a, toc_d, toc_be);
		else       $display("TOC %0d R %04X %04X", toc_n, toc_a, toc_q);
	end
	if (!toc_p && act) toc_q <= dut.minimig.toccata_out;
	toc_p <= act;
	toc_i <= dut.minimig.int6_toccata;
	if (toc_i != dut.minimig.int6_toccata) $display("TOC %0d interrupt %b", toc_n, dut.minimig.int6_toccata);
end

endmodule
