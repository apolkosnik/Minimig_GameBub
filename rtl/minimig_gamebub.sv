// Minimig (Amiga OCS/ECS/AGA) for the Game Bub.
//
// Top level bound by chisel/src/MinimigCore.scala. It takes the place of
// Minimig.sv (the MiSTer "emu" module) of Minimig-AGA_MiSTer:
//
//   MiSTer                     Game Bub
//   ------                     --------
//   pll (114/28 MHz)           MMCM in this module
//   sdram_ctrl + ddram_ctrl    sdram_ctrl only (fast RAM moved into SDRAM)
//   chipdma_arb, fastchip      not needed (no Akiko/CDTV/RTG/fast IDE)
//   HPS (Main_MiSTer)          gb_boot (configuration, Kickstart upload)
//                              gb_floppy (ADF <-> MFM floppy server)
//                              gb_ide (hard disk images on the Gayle IDE
//                              port, on-demand file commands)
//                              gb_host (Game Bub MCU: files, settings)
//   video_mixer / scaler       gb_video, gb_fb (720 x 256 in 18 bits, two
//                              frames in the SRAM and block RAM)
//   audio filters              gb_audio
//   joysticks, PS/2            gb_input (Game Bub controllers, InputExtendedV0)
//
// SDRAM (32 MB, word addresses [24:1]):
//   0x000000 - 0x3FFFFF   Amiga chip / slow RAM / Kickstart (as on MiSTer)
//   0x400000 - 0x7FFFFF   Zorro II fast RAM (up to 8 MB; DDR3 on MiSTer)
//   0xC00000 - 0xFFFFFF   the last 8 MB of the 32 MB Zorro III board (its
//                         first 24 MB are in the second SDRAM chip)
//   0x800000 - 0x9FFFFF   floppy image slots 0..3, 1 MB each
//   0xB00000 - 0xB3FFFF   cartridge image (HRTmon or the Action Replay) as
//                         loaded from the SD card
//   0xB80000 - 0xBFFFFF   Kickstart image as loaded from the SD card
//
// SPDX-License-Identifier: GPL-3.0-or-later

module minimig_gamebub
#(
	parameter int DISPLAY_DIVIDER = 35
)
(
	input  logic        clock,
	input  logic        reset,
	input  logic        clocks_clockIn50M,
	output logic        clocks_clockOutSystem,
	output logic        clocks_clockOutDisplay,
	output logic        clocks_clockOutSpi,
	output logic        clocks_locked,
	output logic        video_data_r,
	output logic        video_data_g,
	output logic        video_data_b,
	output logic        video_dataEnable,
	output logic        video_vblank,
	output logic        video_hblank,
	output logic        video_fit,
	input  logic        video_external_clock,
	input  logic        video_external_active,
	input  logic        video_external_hdmi,
	input  logic [10:0] video_external_x,
	input  logic [9:0]  video_external_y,
	input  logic        video_external_sync,
	input  logic        video_external_frame,
	output logic [23:0] video_external_color,
	output logic        video_external_enable,
	input  logic        video_frames_write,
	input  logic        video_frames_drop,
	output logic [15:0] audio_left,
	output logic [15:0] audio_right,
	input  logic        host_mem_enable,
	input  logic        host_mem_write,
	output logic        host_mem_done,
	input  logic [31:0] host_mem_address,
	output logic [31:0] host_mem_dataRead,
	input  logic [31:0] host_mem_dataWrite,
	input  logic        host_commandHost_request,
	output logic        host_commandHost_busy,
	output logic        host_commandHost_done,
	output logic        host_commandHost_error,
	output logic        host_commandCore_request,
	input  logic        host_commandCore_busy,
	input  logic        host_commandCore_done,
	input  logic        host_commandCore_error,
	input  logic        input_slots_0_active,
	input  logic [3:0]  input_slots_0_deviceType,
	input  logic        input_slots_0_buttons_a,
	input  logic        input_slots_0_buttons_b,
	input  logic        input_slots_0_buttons_x,
	input  logic        input_slots_0_buttons_y,
	input  logic        input_slots_0_buttons_up,
	input  logic        input_slots_0_buttons_down,
	input  logic        input_slots_0_buttons_left,
	input  logic        input_slots_0_buttons_right,
	input  logic        input_slots_0_buttons_l1,
	input  logic        input_slots_0_buttons_r1,
	input  logic        input_slots_0_buttons_l2,
	input  logic        input_slots_0_buttons_r2,
	input  logic        input_slots_0_buttons_l3,
	input  logic        input_slots_0_buttons_r3,
	input  logic        input_slots_0_buttons_start,
	input  logic        input_slots_0_buttons_select,
	input  logic signed [7:0] input_slots_0_analog_leftX,
	input  logic signed [7:0] input_slots_0_analog_leftY,
	input  logic signed [7:0] input_slots_0_analog_rightX,
	input  logic signed [7:0] input_slots_0_analog_rightY,
	input  logic [7:0]  input_slots_0_analog_leftTrigger,
	input  logic [7:0]  input_slots_0_analog_rightTrigger,
	input  logic        input_slots_1_active,
	input  logic [3:0]  input_slots_1_deviceType,
	input  logic        input_slots_1_buttons_a,
	input  logic        input_slots_1_buttons_b,
	input  logic        input_slots_1_buttons_x,
	input  logic        input_slots_1_buttons_y,
	input  logic        input_slots_1_buttons_up,
	input  logic        input_slots_1_buttons_down,
	input  logic        input_slots_1_buttons_left,
	input  logic        input_slots_1_buttons_right,
	input  logic        input_slots_1_buttons_l1,
	input  logic        input_slots_1_buttons_r1,
	input  logic        input_slots_1_buttons_l2,
	input  logic        input_slots_1_buttons_r2,
	input  logic        input_slots_1_buttons_l3,
	input  logic        input_slots_1_buttons_r3,
	input  logic        input_slots_1_buttons_start,
	input  logic        input_slots_1_buttons_select,
	input  logic signed [7:0] input_slots_1_analog_leftX,
	input  logic signed [7:0] input_slots_1_analog_leftY,
	input  logic signed [7:0] input_slots_1_analog_rightX,
	input  logic signed [7:0] input_slots_1_analog_rightY,
	input  logic [7:0]  input_slots_1_analog_leftTrigger,
	input  logic [7:0]  input_slots_1_analog_rightTrigger,
	output logic        sdram_clock,
	output logic [1:0]  sdram_cke,
	output logic [1:0]  sdram_cs,
	output logic        sdram_ras,
	output logic        sdram_cas,
	output logic        sdram_we,
	output logic [1:0]  sdram_dqm,
	output logic [1:0]  sdram_bank,
	output logic [12:0] sdram_address,
	input  logic [15:0] sdram_dataIn,
	output logic [15:0] sdram_dataOut,
	output logic        sdram_dataDir,
	output logic        sram_ceN,
	output logic        sram_weN,
	output logic        sram_oeN,
	output logic [1:0]  sram_writeMaskN,
	output logic [17:0] sram_address,
	input  logic [15:0] sram_dataIn,
	output logic [15:0] sram_dataOut,
	output logic        sram_dataDir
);

localparam [24:1] SLOT_BASE  = 24'h800000;
localparam [24:1] SLOT_WORDS = 24'h080000;
localparam [24:1] KICK_STAGE = 24'hB80000;
localparam [24:1] CART_STAGE = 24'hB00000;

// ===========================================================================
// Clocks
// ===========================================================================
wire clk_114, clk_sys, clk_sdram, locked;

gb_clocks #(.DISPLAY_DIVIDER(DISPLAY_DIVIDER)) clocks
(
	.clk_in_50mhz (clocks_clockIn50M),
	.clk_114      (clk_114),
	.clk_sys      (clk_sys),
	.clk_sdram    (clk_sdram),
	.clk_display  (clocks_clockOutDisplay),
	.clk_spi      (clocks_clockOutSpi),
	.locked       (locked)
);

assign clocks_clockOutSystem = clk_sys;   // comes back as `clock`
assign clocks_locked         = locked;

// `reset` is the framework's reset, synchronous to clk_sys (= clock)
reg [7:0] rst_sh = 8'hFF;
reg       reset_d = 1'b1;
always @(posedge clk_sys) begin
	rst_sh  <= {rst_sh[6:0], reset | ~locked};
	reset_d <= |rst_sh;
end

// the same reset in the clk_114 domain (sdram_ctrl, the bridge's SDRAM side)
reg [1:0] rst114_sh = 2'b11;
wire      reset_114 = rst114_sh[1];
always @(posedge clk_114) rst114_sh <= {rst114_sh[0], reset_d};

// ===========================================================================
// Game Bub host interface
// ===========================================================================
wire        core_reset, focus;
wire        boot_start, boot_reload, boot_busy, boot_own, boot_done;
wire  [5:0] cfg_chipset;
wire  [7:0] cfg_cpu, cfg_memory;
wire  [4:0] cfg_floppy;
wire  [1:0] cfg_audmix;
wire [20:0] kick_size;
wire        cart_loaded, cart_is_ar;   // the cartridge image as staged (gb_host)
wire [19:0] cart_size;
wire        cart_on, cart_ar;          // the cartridge as fitted (gb_boot): any, the Action Replay
wire  [3:0] drv_present, drv_writable;
wire [11:0] drv_slot;
wire [31:0] drv_tracks;
wire        audio_filter;
wire  [7:0] key_x, key_y, key_start, key_select;
wire  [4:0] video_vpos;
wire        video_fit_set;
wire [15:0] fb_lines, fb_late;
// the A2065's frames (gb_host <-> gb_a2065)
wire        net_board, net_up, net_tx_valid, net_tx_taken, net_rx_we, net_rx_commit, net_rx_busy;
wire [23:0] net_serial;
wire [10:0] net_tx_len, net_rx_len;
wire  [8:0] net_tx_raddr, net_rx_waddr;
wire [31:0] net_tx_rdata, net_rx_wdata;
wire [15:0] net_sent, net_received, net_dropped;
// its place on the chip bus (minimig.sv)
wire        a2065_sel, a2065_rw, a2065_uds_n, a2065_lds_n, a2065_irq;
wire [23:1] a2065_addr;
wire [15:0] a2065_wdata, a2065_rdata;
wire        fb_overflow;
wire  [7:0] fdd_error;
wire [15:0] fdd_sectors_read, fdd_sectors_written;
wire        hmouse_valid;
wire [15:0] hmouse_dx, hmouse_dy;
wire  [2:0] hmouse_btn;
wire        hwheel_valid;
wire  [7:0] hwheel;
wire        hkey_valid, hkey_down;
wire  [7:0] hkey_usage;
wire        f_idle, f_committing;

wire [31:0] hc_cmd, hc_p1, hc_p2, hc_p3, hc_p4, hc_p5, hc_res0, hc_res1, hc_res2;
wire [11:0] hb_addr;
wire        hb_we;
wire [31:0] hb_wdata, hb_rdata;
wire [31:0] ide_state, ide_sectors_read, ide_sectors_written, ide_chs0, ide_chs1, ide_total0, ide_total1;
wire  [1:0] hdd_present;
wire        hdd_mount_busy;
wire  [5:0] ide_req;
wire  [4:0] ide_address;
wire        ide_write, ide_read;
wire [15:0] ide_writedata, ide_readdata;

wire [15:0] bridge_rdata;     // SDRAM host port read data (all clients)
wire        ntsc;             // from minimig (PAL/NTSC configuration)

wire        h_req, h_we, h_ack;
wire [24:1] h_addr;
wire [15:0] h_wdata;

gb_host #(
	.SLOT_BASE (SLOT_BASE),
	.SLOT_WORDS(SLOT_WORDS),
	.KICK_STAGE(KICK_STAGE),
	.CART_STAGE(CART_STAGE)
) host (
	.clk              (clk_sys),
	.reset            (reset_d),
	.mem_address      (host_mem_address),
	.mem_enable       (host_mem_enable),
	.mem_write        (host_mem_write),
	.mem_dataRead     (host_mem_dataRead),
	.mem_dataWrite    (host_mem_dataWrite),
	.mem_done         (host_mem_done),
	.cmd_request      (host_commandHost_request),
	.cmd_busy         (host_commandHost_busy),
	.cmd_done         (host_commandHost_done),
	.cmd_error        (host_commandHost_error),
	.sd_req           (h_req),
	.sd_we            (h_we),
	.sd_addr          (h_addr),
	.sd_wdata         (h_wdata),
	.sd_ack           (h_ack),
	.sd_rdata         (bridge_rdata),
	.core_reset       (core_reset),
	.focus            (focus),
	.boot_start       (boot_start),
	.boot_reload      (boot_reload),
	.boot_busy        (boot_busy),
	.boot_done        (boot_done),
	.floppy_busy      (f_committing),
	.cfg_chipset      (cfg_chipset),
	.cfg_cpu          (cfg_cpu),
	.cfg_memory       (cfg_memory),
	.cfg_floppy       (cfg_floppy),
	.cfg_audmix       (cfg_audmix),
	.kick_size        (kick_size),
	.cart_loaded      (cart_loaded),
	.cart_ar          (cart_is_ar),
	.cart_size        (cart_size),
	.drv_present      (drv_present),
	.drv_writable     (drv_writable),
	.drv_slot         (drv_slot),
	.drv_tracks       (drv_tracks),
	.audio_filter     (audio_filter),
	.key_x            (key_x),
	.key_y            (key_y),
	.key_start        (key_start),
	.key_select       (key_select),
	.video_vpos       (video_vpos),
	.video_fit        (video_fit_set),
	.hmouse_valid     (hmouse_valid),
	.hmouse_dx        (hmouse_dx),
	.hmouse_dy        (hmouse_dy),
	.hmouse_btn       (hmouse_btn),
	.hwheel_valid     (hwheel_valid),
	.hwheel           (hwheel),
	.hkey_valid       (hkey_valid),
	.hkey_usage       (hkey_usage),
	.hkey_down        (hkey_down),
	.stat_run         (~core_reset & focus),
	.stat_stall       (~core_reset & ~focus),
	.fdd_error        (fdd_error),
	.fdd_sectors_read (fdd_sectors_read),
	.fdd_sectors_written(fdd_sectors_written),
	.hc_cmd           (hc_cmd),
	.hc_p1            (hc_p1),
	.hc_p2            (hc_p2),
	.hc_p3            (hc_p3),
	.hc_p4            (hc_p4),
	.hc_p5            (hc_p5),
	.hc_res0          (hc_res0),
	.hc_res1          (hc_res1),
	.hc_res2          (hc_res2),
	.hb_addr          (hb_addr),
	.hb_we            (hb_we),
	.hb_wdata         (hb_wdata),
	.hb_rdata         (hb_rdata),
	.ide_state        (ide_state),
	.ide_sectors_read (ide_sectors_read),
	.ide_sectors_written(ide_sectors_written),
	.ide_chs0         (ide_chs0),
	.ide_chs1         (ide_chs1),
	.ide_total0       (ide_total0),
	.ide_total1       (ide_total1),
	.fb_state         ({fb_overflow, fb_late[14:0], fb_lines}),
	.net_board        (net_board),
	.net_up           (net_up),
	.net_serial       (net_serial),
	.net_tx_valid     (net_tx_valid),
	.net_tx_len       (net_tx_len),
	.net_tx_taken     (net_tx_taken),
	.net_tx_raddr     (net_tx_raddr),
	.net_tx_rdata     (net_tx_rdata),
	.net_rx_we        (net_rx_we),
	.net_rx_waddr     (net_rx_waddr),
	.net_rx_wdata     (net_rx_wdata),
	.net_rx_commit    (net_rx_commit),
	.net_rx_len       (net_rx_len),
	.net_rx_busy      (net_rx_busy),
	.net_counts       ({net_dropped, net_received, net_sent})
);

// ===========================================================================
// HPS replacement: IO bus master shared by the boot sequencer and the
// floppy server
// ===========================================================================
wire        io_uio, io_fpga, io_strobe, io_wait;
wire [15:0] io_din, io_dout;

wire  [1:0] b_sel;   wire b_req;   wire [15:0] b_wdata;
wire  [1:0] f_sel;   wire f_req;   wire [15:0] f_wdata;
wire        m_ack, m_ready;
wire [15:0] m_rdata;

wire        fdd_enable = boot_done & ~boot_busy & ~core_reset;

gb_io_master io_master
(
	.clk       (clk_sys),
	.reset     (reset_d),
	.sel       (boot_own ? b_sel   : f_sel),
	.req       (boot_own ? b_req   : f_req),
	.wdata     (boot_own ? b_wdata : f_wdata),
	.ack       (m_ack),
	.rdata     (m_rdata),
	.ready     (m_ready),
	.IO_UIO    (io_uio),
	.IO_FPGA   (io_fpga),
	.IO_STROBE (io_strobe),
	.IO_DIN    (io_din),
	.IO_WAIT   (io_wait),
	.IO_DOUT   (io_dout)
);

wire        b_mreq, b_mack;
wire [24:1] b_maddr;

gb_boot #(.KICK_STAGE(KICK_STAGE), .CART_STAGE(CART_STAGE)) boot
(
	.clk         (clk_sys),
	.reset       (reset_d | core_reset),
	.start       (boot_start),
	.reload_kick (boot_reload),
	.busy        (boot_busy),
	.own         (boot_own),
	.done        (boot_done),
	.halt        (~focus),
	.cfg_chipset (cfg_chipset),
	.cfg_cpu     (cfg_cpu),
	.cfg_memory  (cfg_memory),
	.cfg_floppy  (cfg_floppy),
	.cfg_audmix  (cfg_audmix),
	.kick_size   (kick_size),
	// Gayle IDE on when a drive has an image; always the port in the
	// chip bus (bit 5), the fast one of the 68020 path is not built
	.cfg_hdd     ((hdd_present != 2'b00) ? {3'b100, hdd_present, 1'b1} : 6'd0),
	.hdd_ready   (~hdd_mount_busy),
	.cart_loaded (cart_loaded),
	.cart_is_ar  (cart_is_ar),
	.cart_size   (cart_size),
	.cart_on     (cart_on),
	.cart_ar     (cart_ar),
	.bus_free    (f_idle),
	.io_sel      (b_sel),
	.io_req      (b_req),
	.io_wdata    (b_wdata),
	.io_ack      (m_ack & boot_own),
	.mem_req     (b_mreq),
	.mem_addr    (b_maddr),
	.mem_ack     (b_mack),
	.mem_rdata   (bridge_rdata)
);

wire        f_mreq, f_mwe, f_mack;
wire [24:1] f_maddr;
wire [15:0] f_mwdata;

gb_floppy #(
	.SLOT_BASE (SLOT_BASE),
	.SLOT_WORDS(SLOT_WORDS)
) floppy (
	.clk            (clk_sys),
	.reset          (reset_d | core_reset),
	.enable         (fdd_enable),
	.idle           (f_idle),
	.committing     (f_committing),
	.drv_present    (drv_present),
	.drv_writable   (drv_writable),
	.drv_slot       (drv_slot),
	.drv_tracks     (drv_tracks),
	.io_sel         (f_sel),
	.io_req         (f_req),
	.io_wdata       (f_wdata),
	.io_ack         (m_ack & ~boot_own),
	.io_rdata       (m_rdata),
	.mem_req        (f_mreq),
	.mem_we         (f_mwe),
	.mem_addr       (f_maddr),
	.mem_wdata      (f_mwdata),
	.mem_ack        (f_mack),
	.mem_rdata      (bridge_rdata),
	.last_error     (fdd_error),
	.sectors_read   (fdd_sectors_read),
	.sectors_written(fdd_sectors_written)
);

// ===========================================================================
// Hard disks: the part of Main_MiSTer's ide.cpp for the Gayle IDE port,
// the images read and written through on-demand file commands
// ===========================================================================
gb_ide ide_server
(
	.clk           (clk_sys),
	.reset         (reset_d),
	.enable        (fdd_enable),
	.start         (boot_start),
	.mount_busy    (hdd_mount_busy),
	.present       (hdd_present),
	.ide_req       (ide_req[2:0]),
	.ide_address   (ide_address),
	.ide_write     (ide_write),
	.ide_writedata (ide_writedata),
	.ide_read      (ide_read),
	.ide_readdata  (ide_readdata),
	.hc_request    (host_commandCore_request),
	.hc_cmd        (hc_cmd),
	.hc_p1         (hc_p1),
	.hc_p2         (hc_p2),
	.hc_p3         (hc_p3),
	.hc_p4         (hc_p4),
	.hc_p5         (hc_p5),
	.hc_done       (host_commandCore_done),
	.hc_error      (host_commandCore_error),
	.hc_res0       (hc_res0),
	.hc_res1       (hc_res1),
	.hc_res2       (hc_res2),
	.hb_addr       (hb_addr),
	.hb_we         (hb_we),
	.hb_wdata      (hb_wdata),
	.hb_rdata      (hb_rdata),
	.dbg_sectors_read   (ide_sectors_read),
	.dbg_sectors_written(ide_sectors_written),
	.dbg_chs0      (ide_chs0),
	.dbg_chs1      (ide_chs1),
	.dbg_total0    (ide_total0),
	.dbg_total1    (ide_total1),
	.dbg_state     (ide_state)
);

// ===========================================================================
// SDRAM host port: MCU file transfers > Kickstart upload > floppy server
// ===========================================================================
wire  [2:0] bridge_ack;
wire [24:1] hp_addr;
wire        hp_req, hp_we, hp_ack;
wire  [1:0] hp_dqm;
wire [15:0] hp_wr, hp_rd;

assign h_ack  = bridge_ack[0];
assign b_mack = bridge_ack[1];
assign f_mack = bridge_ack[2];

gb_sdram_bridge #(.N(3)) sdram_bridge
(
	.clk_sys  (clk_sys),
	.clk_mem  (clk_114),
	.reset    (reset_d),
	.reset_mem(reset_114),
	.c_req    ({f_mreq, b_mreq, h_req}),
	.c_we     ({f_mwe, 1'b0, h_we}),
	.c_addr   ({f_maddr, b_maddr, h_addr}),
	.c_dqm    (6'b000000),
	.c_wdata  ({f_mwdata, 16'h0000, h_wdata}),
	.c_ack    (bridge_ack),
	.c_rdata  (bridge_rdata),
	.hostAddr (hp_addr),
	.hostReq  (hp_req),
	.hostWE   (hp_we),
	.hostDQM  (hp_dqm),
	.hostWR   (hp_wr),
	.hostRD   (hp_rd),
	.hostAck  (hp_ack)
);

// ===========================================================================
// Amiga clocks (as Minimig.sv)
// ===========================================================================
wire       amiga_reset = reset_d | core_reset;
wire       clk7_en, clk7n_en, c1, c3, cck;
wire [9:0] eclk;

amiga_clk amiga_clk
(
	.clk_28   (clk_sys),
	.clk7_en  (clk7_en),
	.clk7n_en (clk7n_en),
	.c1       (c1),
	.c3       (c3),
	.cck      (cck),
	.eclk     (eclk),
	.reset_n  (~reset_d)
);

// ===========================================================================
// CPU (as Minimig.sv)
// ===========================================================================
wire  [4:0] cpucfg;
wire  [2:0] cachecfg;
wire  [6:0] memcfg;
wire        bootrom;

// 68000, 68010, 68EC020, 68020 and 68030 (with its MMU). The 68020 and
// 68030 address 32 bits: Zorro III RAM and the RTG board's memory are in
// the second SDRAM chip (see the SDRAM section).
wire  [4:0] cpucfg_m = cpucfg;

wire cpu_type = cpucfg_m[1];
reg  cpu_ph1;
reg  cpu_ph2;
reg  ram_cs;
reg  cyc;

wire  [1:0] cpu_state;
wire        cpu_nrst_out;
wire  [3:0] cpu_cacr;
wire [31:0] cpu_nmi_addr;
wire        cpu_rst;

wire  [2:0] chip_ipl;
wire        chip_dtack;
wire        chip_as;
wire        chip_uds;
wire        chip_lds;
wire        chip_rw;
wire [15:0] chip_dout;
wire [15:0] chip_din;
wire [23:1] chip_addr;
wire        chip32_en;
wire        chip_long;
wire [15:0] chip_din2;
wire [15:0] chip_rd2;
wire        ram_long;

wire [28:1] ram_addr;
wire        ram_sel;
wire        ram_lds;
wire        ram_uds;
wire [15:0] ram_din;
wire [15:0] ram_dout;
wire        ram_ready;
wire        ram_long1;     // a long word in one RAM transfer (cpu_wrapper ramlong1)
wire [15:0] ram_din_lo;
wire [15:0] ram_dout_hi;
wire        ram_ready_l;
wire        ar_fetch;
wire        dcache_sw_en;
wire        toccata_ena, a2065_ena;
wire [15:0] fastchip_dout;
wire        fastchip_sel, fastchip_lds, fastchip_uds, fastchip_rnw;
wire        fastchip_selack, fastchip_ready;
wire        rtg_reg_sel;
wire [15:0] rtg_lines, rtg_late;
wire  [7:0] toccata_base, a2065_base, cdtv_base;

always @(posedge clk_114) begin
	reg [3:0] div;
	reg       c1d;

	div <= div + 1'd1;

	c1d <= c1;
	if (~c1d & c1) div <= 3;

	if (~cpu_rst) begin
		cyc <= 0;
		cpu_ph1 <= 0;
		cpu_ph2 <= 0;
	end
	else begin
		cyc <= !div[1:0];
		if (div[1] & ~div[0]) begin
			cpu_ph1 <= 0;
			cpu_ph2 <= 0;
			case (div[3:2])
				0: cpu_ph2 <= 1;
				2: cpu_ph1 <= 1;
			endcase
		end
	end

	ram_cs <= ~(ram_ready & cyc & cpu_type) & ram_sel;
end

cpu_wrapper cpu_wrapper
(
	.reset        (cpu_rst         ),
	.reset_out    (cpu_nrst_out    ),

	.clk          (clk_sys         ),
	.ph1          (cpu_ph1         ),
	.ph2          (cpu_ph2         ),

	.chip_addr    (chip_addr       ),
	.chip_dout    (chip_dout       ),
	.chip_din     (chip_din        ),
	.chip_as      (chip_as         ),
	.chip_uds     (chip_uds        ),
	.chip_lds     (chip_lds        ),
	.chip_rw      (chip_rw         ),
	.chip_dtack   (chip_dtack      ),
	.chip_ipl     (chip_ipl        ),
	.chip32_en    (chip32_en       ),
	.chip_long    (chip_long       ),
	.chip_din2    (chip_din2       ),
	.chip_dout2   (chip_rd2        ),

	.fastchip_dout   (fastchip_dout ),
	.fastchip_sel    (fastchip_sel  ),
	.fastchip_lds    (fastchip_lds  ),
	.fastchip_uds    (fastchip_uds  ),
	.fastchip_rnw    (fastchip_rnw  ),
	.fastchip_selack (fastchip_selack),
	.fastchip_ready  (fastchip_ready),
	.fastchip_lw     (             ),

	.cpucfg       (cpucfg_m        ),
	.ntsc         (ntsc            ),
	.cachecfg     (cachecfg        ),
	.fastramcfg   (memcfg[6:4]     ),   // 0-3 Zorro II RAM, 6: Zorro III 16 MB (8 MB Zorro II on a 24 bit CPU)
	.bootrom      (bootrom         ),

	.toccata_ena  (toccata_ena     ),
	.a2065_ena    (a2065_ena       ),
	.a2065_base   (a2065_base      ),
	.a2065_on     (net_board       ),
	.a2065_serial (net_serial      ),
	.toccata_base (toccata_base    ),
	.cdtv_base    (cdtv_base       ),
	.cdtv_mode    (1'b0            ),

	.cdtv_din     (16'h0000        ),
	.cdtv_selack  (1'b0            ),

	.ar_on        (cart_on         ),   // a cartridge is fitted (its file, gb_boot): $A80000-$AFFFFF on the chip bus
	.ar_fetch     (ar_fetch        ),

	.ramsel       (ram_sel         ),
	.ramaddr      (ram_addr        ),
	.ramlds       (ram_lds         ),
	.ramuds       (ram_uds         ),
	.ramdout      (ram_dout        ),
	.ramdout2     (ram_dout        ),   // fast RAM is in the same SDRAM
	.ramdin       (ram_din         ),
	.ramready     (ram_ready       ),
	.ramlong1     (ram_long1       ),
	.ramdin_lo    (ram_din_lo      ),
	.ramdout_hi   (ram_dout_hi     ),
	.ramready_l   (ram_ready_l     ),

	.cpustate     (cpu_state       ),
	.cacr         (cpu_cacr        ),
	.nmi_addr     (cpu_nmi_addr    ),

	.z2ram_ena    (                ),
	.z3ram_base0  (                ),
	.z3ram_ena0   (                ),
	.z3ram_base1  (                ),
	.z3ram_ena1   (                ),
	.rtg_ena      (                ),
	.rtg_base     (                ),
	.rtg_reg_sel  (rtg_reg_sel     ),
	.dcache_sw_en (dcache_sw_en    )
);

// ===========================================================================
// SDRAM
// ===========================================================================
wire [15:0] ram_data;      // sram data bus
wire [15:0] ramdata_in;    // sram data bus in
wire [47:0] chip48;        // big chip read
wire [23:1] ram_address;   // sram address bus
wire        _ram_bhe;      // sram upper byte select
wire        _ram_ble;      // sram lower byte select
wire        _ram_we;       // sram write enable
wire        _ram_oe;       // sram output enable

// CPU RAM. Chip 0: main memory as on MiSTer, Zorro II RAM ($200000-$9FFFFF,
// ramaddr[28] set) in the next 8 MB. Chip 1 (cpu_sdram_addr[25]): the RTG
// board's 8 MB of video memory (ramaddr[28:23] = 001110) at 0. The 32 MB
// Zorro III board (ramaddr[27] set, ramaddr[24:1] its own address): its
// first 16 MB at chip 1's 16 MB, the next 8 MB at chip 1's 8 MB, and its
// last 8 MB in the top 8 MB of chip 0, which shares its slots with the
// chipset (the slower part, at the board's top: exec fills a memory
// region from the bottom).
wire        z3_sel   = ram_addr[27] & ~ram_addr[28];
wire        rtg_sel  = (ram_addr[28:23] == 6'b001110);
// the RTG picture's burst port of the SDRAM controller (gb_rtg below)
wire [24:4] burst_addr;
wire        burst_req, burst_urgent, burst_ack, burst_valid;
wire [15:0] burst_data;

wire        zram_sel = |ram_addr[28:26];
wire [25:1] cpu_sdram_addr = z3_sel  ? (!ram_addr[24]             ? {2'b11,  ram_addr[23:1]} :
                                        !ram_addr[23]             ? {3'b101, ram_addr[22:1]} :
                                                                    {3'b011, ram_addr[22:1]}) :
                             rtg_sel ? {3'b100, ram_addr[22:1]} :
                                       {2'b00, zram_sel, ram_addr[22:1]};

gb_sdram_ctrl ram1
(
	.sysclk       (clk_114         ),
	.sdclk        (clk_sdram       ),
	.reset_n      (~reset_114      ),
	.c_7m         (c1              ),

	.cache_rst    (cpu_rst         ),
	.cache_inhibit(1'b0            ),
	.cpu_cache_ctrl(cpu_cacr       ),
	.dcache_sw_en (dcache_sw_en    ),

	.sd_data_in   (sdram_dataIn    ),
	.sd_data_out  (sdram_dataOut   ),
	.sd_data_oe   (sdram_dataDir   ),
	.sd_addr      (sdram_address   ),
	.sd_dqm       (sdram_dqm       ),
	.sd_cs        (sdram_cs        ),
	.sd_ba        (sdram_bank      ),
	.sd_we        (sdram_we        ),
	.sd_ras       (sdram_ras       ),
	.sd_cas       (sdram_cas       ),
	.sd_cke       (sdram_cke       ),
	.sd_clk       (sdram_clock     ),

	.cpuWR        (ram_din         ),
	.cpuAddr      (cpu_sdram_addr  ),
	.cpuU         (ram_uds         ),
	.cpuL         (ram_lds         ),
	.cpustate     (cpu_state       ),
	.cpuCS        (ram_cs          ),
	.cpuRD        (ram_dout        ),
	.ramready     (ram_ready       ),
	.cpuLong1     (ram_long1       ),
	.cpuWR_lo     (ram_din_lo      ),
	.cpuRD_hi     (ram_dout_hi     ),
	.ramready_l   (ram_ready_l     ),
	.cpuLine      (1'b0            ),   // (the AP68040 variant's line reads)
	.cpuRD_line   (                ),
	.ramready_line(                ),

	.chipWR       (ram_data        ),
	.chipAddr     ({1'b0, ram_address}),
	.chipU        (_ram_bhe        ),
	.chipL        (_ram_ble        ),
	.chipRW       (_ram_we         ),
	.chipDMA      (_ram_oe         ),
	.chipRD       (ramdata_in      ),
	.chip48       (chip48          ),
	.chip32       (ram_long        ),
	.chipWR2      (chip_din2       ),
	.chipRD2      (chip_rd2        ),

	.hostAddr     (hp_addr         ),
	.hostReq      (hp_req          ),
	.hostWE       (hp_we           ),
	.hostDQM      (hp_dqm          ),
	.hostWR       (hp_wr           ),
	.hostRD       (hp_rd           ),
	.hostAck      (hp_ack          ),

	.burstAddr    (burst_addr      ),
	.burstReq     (burst_req       ),
	.burstUrgent  (burst_urgent    ),
	.burstAck     (burst_ack       ),
	.burstData    (burst_data      ),
	.burstValid   (burst_valid     )
);

// ===========================================================================
// RTG: the board's registers and palette (fastchip, as on MiSTer) and its
// picture from the second SDRAM chip on HDMI (gb_rtg)
// ===========================================================================
wire        rtg_on;
wire [23:0] rtg_color;
gb_rtg rtg
(
	.clk_sys     (clk_sys              ),
	.reset       (~cpu_rst | ~cpu_nrst_out),
	.sel         (fastchip_sel         ),
	.rtg_reg_sel (rtg_reg_sel          ),
	.addr        (chip_addr            ),
	.din         (chip_din             ),
	.uds         (~fastchip_uds        ),
	.lds         (~fastchip_lds        ),
	.rnw         (fastchip_rnw         ),
	.sel_ack     (fastchip_selack      ),
	.ready       (fastchip_ready       ),
	.dout        (fastchip_dout        ),
	.enable      (rtg_on               ),

	.clk_114     (clk_114              ),
	.burstAddr   (burst_addr           ),
	.burstReq    (burst_req            ),
	.burstUrgent (burst_urgent         ),
	.burstAck    (burst_ack            ),
	.burstData   (burst_data           ),
	.burstValid  (burst_valid          ),

	.clk_av      (video_external_clock ),
	.av_x        (video_external_x     ),
	.av_y        (video_external_y     ),
	.av_color    (rtg_color            ),
	.dbg_lines   (rtg_lines            ),
	.dbg_late    (rtg_late             )
);

// ===========================================================================
// Minimig
// ===========================================================================
wire [15:0] joy_port1, joy_port2;
wire  [2:0] mouse_btn;
wire  [7:0] kbd_mouse_data;
wire  [1:0] kbd_mouse_type;
wire        kbd_mouse_level;
wire  [7:0] red, green, blue;
wire        hs, vs, hblank, vbl, lace, field1, diw;
wire  [1:0] res;
wire [14:0] ldata, rdata;
wire [15:0] toc_left, toc_right;   // the Toccata sound card's output

minimig minimig
(
	//m68k pins
	.cpu_address  (chip_addr        ),
	.cpu_data     (chip_dout        ),
	.cpudata_in   (chip_din         ),
	._cpu_ipl     (chip_ipl         ),
	._cpu_as      (chip_as          ),
	._cpu_uds     (chip_uds         ),
	._cpu_lds     (chip_lds         ),
	.cpu_r_w      (chip_rw          ),
	.cpu_long     (chip_long        ),
	.chip32_en    (chip32_en        ),
	.ram_long     (ram_long         ),
	._cpu_dtack   (chip_dtack       ),
	._cpu_reset   (cpu_rst          ),
	._cpu_reset_in(cpu_nrst_out     ),
	.nmi_addr     (cpu_nmi_addr     ),
	.ovr          (                 ),
	.cart_ar      (cart_ar          ),
	.ar_fetch     (ar_fetch         ),
	.nmi_ack_toggle(1'b0            ),   // (the TG68K and the fx68k make the acknowledge cycle)

	//sram pins
	.ram_data     (ram_data         ),
	.ramdata_in   (ramdata_in       ),
	.ram_address  (ram_address      ),
	._ram_bhe     (_ram_bhe         ),
	._ram_ble     (_ram_ble         ),
	._ram_we      (_ram_we          ),
	._ram_oe      (_ram_oe          ),
	.chip48       (chip48           ),

	//system pins
	.rst_ext      (amiga_reset      ),
	.rst_out      (                 ),
	.clk          (clk_sys          ),
	.clk7_en      (clk7_en          ),
	.clk7n_en     (clk7n_en         ),
	.c1           (c1               ),
	.c3           (c3               ),
	.cck          (cck              ),
	.eclk         (eclk             ),

	//rs232 pins (not connected)
	.rxd          (1'b1             ),
	.txd          (                 ),
	.cts          (1'b0             ),
	.rts          (                 ),
	.dtr          (                 ),
	.dsr          (1'b0             ),
	.cd           (1'b0             ),
	.ri           (1'b1             ),

	//I/O
	._joy1        (~joy_port2       ),   // MiSTer joystick 1 = Amiga port 2
	._joy2        (~joy_port1       ),
	._joy3        (16'hFFFF         ),
	._joy4        (16'hFFFF         ),
	.joya1        (16'h0000         ),
	.joya2        (16'h0000         ),
	.mouse_btn    (mouse_btn        ),
	.kbd_mouse_data (kbd_mouse_data ),
	.kbd_mouse_type (kbd_mouse_type ),
	.kms_level    (kbd_mouse_level  ),
	.pwr_led      (                 ),
	.fdd_led      (                 ),
	.hdd_led      (                 ),
	.rtc          (65'd0            ),

	//host controller interface
	.IO_UIO       (io_uio           ),
	.IO_FPGA      (io_fpga          ),
	.IO_STROBE    (io_strobe        ),
	.IO_WAIT      (io_wait          ),
	.IO_DIN       (io_din           ),
	.IO_DOUT      (io_dout          ),

	//video
	._hsync       (hs               ),
	._vsync       (vs               ),
	._csync       (                 ),
	.field1       (field1           ),
	.diw          (diw              ),
	.lace         (lace             ),
	.red          (red              ),
	.green        (green            ),
	.blue         (blue             ),
	.hblank       (hblank           ),
	.vblank       (vbl              ),
	.ar           (                 ),
	.scanline     (                 ),
	.ce_pix       (                 ),
	.res          (res              ),
	.ntsc         (ntsc             ),

	//audio
	.ldata        (ldata            ),
	.rdata        (rdata            ),
	.ldata_okk    (                 ),
	.rdata_okk    (                 ),
	.aud_mix      (                 ),

	//expansion cards (not built)
	.toccata_ena  (toccata_ena      ),
	.toccata_base (toccata_base     ),
	.cdtv_base    (cdtv_base        ),
	.toccata_aud_left (toc_left     ),
	.toccata_aud_right(toc_right    ),
	.a2065_ena    (a2065_ena        ),
	.a2065_base   (a2065_base       ),
	.cdtv_mode    (                 ),
	.cdtv_din     (                 ),
	.cdtv_selack  (                 ),
	.cdtv_cs      (1'b0             ),
	.cdtv_cs_sec  (1'b0             ),
	.cdtv_cs_stch (1'b0             ),
	.cdtv_cs_nvr  (1'b0             ),
	.cdtv_cs_card (1'b0             ),
	.cdtv_wr      (1'b0             ),
	.cdtv_rd      (1'b0             ),
	.cdtv_uio_din (16'h0000         ),
	.cdtv_uio_dout(                 ),
	.cdtv_req     (                 ),
	.cdtv_subq_push (1'b0           ),
	.cdtv_subq_byte (8'h00          ),
	.cdtv_sten_pulse(1'b0           ),
	.cdtv_scor_pulse(1'b0           ),
	.cdtv_sbcp_pulse(1'b0           ),
	.cdtv_dma_req (                 ),
	.cdtv_dma_we  (                 ),
	.cdtv_dma_baddr(                ),
	.cdtv_dma_wbyte(                ),
	.cdtv_dma_ack (1'b0             ),
	.cdtv_nvr_dirty (               ),
	.cdtv_card_dirty(               ),
	.cdtv_cdda_volume(              ),
	.cdtv_cdda_volume_valid(        ),

	//user i/o
	.cachecfg     (cachecfg         ),
	.cpucfg       (cpucfg           ),
	.memcfg       (memcfg           ),
	.bootrom      (bootrom          ),

	.ide_fast     (                 ),
	.ide_ext_irq  (1'b0             ),
	.akiko_irq    (1'b0             ),
	.ide_ena      (                 ),
	.ide_req      (ide_req          ),
	.ide_address  (ide_address      ),
	.ide_write    (ide_write        ),
	.ide_writedata(ide_writedata    ),
	.ide_read     (ide_read         ),
	.ide_readdata (ide_readdata     ),

	.a2065_sel    (a2065_sel        ),
	.a2065_addr   (a2065_addr       ),
	.a2065_wdata  (a2065_wdata      ),
	.a2065_rw     (a2065_rw         ),
	.a2065_uds_n  (a2065_uds_n      ),
	.a2065_lds_n  (a2065_lds_n      ),
	.a2065_rdata  (a2065_rdata      ),
	.a2065_irq    (a2065_irq        ),

	.USER_IN      (7'h7F            ),
	.USER_OUT     (                 ),
	.user_port_mode(                ),
	.snac_port    (                 ),
	.snac_af      (                 ),
	.mister_floppy_status(          ),
	.drive_snd    (                 )
);

// ===========================================================================
// The A2065 Ethernet board: the LANCE and its RAM (gb_a2065); its frames go
// to the MCU and come from it through gb_host
// ===========================================================================
gb_a2065 a2065
(
	.clk       (clk_sys),
	.reset     (~cpu_rst),
	.sel       (a2065_sel),
	.addr      (a2065_addr),
	.wdata     (a2065_wdata),
	.rw        (a2065_rw),
	.uds_n     (a2065_uds_n),
	.lds_n     (a2065_lds_n),
	.rdata     (a2065_rdata),
	.irq       (a2065_irq),
	.net_up    (net_up),
	.tx_valid  (net_tx_valid),
	.tx_len    (net_tx_len),
	.tx_taken  (net_tx_taken),
	.tx_raddr  (net_tx_raddr),
	.tx_rdata  (net_tx_rdata),
	.rx_we     (net_rx_we),
	.rx_waddr  (net_rx_waddr),
	.rx_wdata  (net_rx_wdata),
	.rx_commit (net_rx_commit),
	.rx_len    (net_rx_len),
	.rx_busy   (net_rx_busy),
	.dbg_tx    (net_sent),
	.dbg_rx    (net_received),
	.dbg_drop  (net_dropped)
);

// ===========================================================================
// Video, audio, input
// ===========================================================================
wire [17:0] video_data;
gb_video video
(
	.clk     (clk_sys),
	.reset   (reset_d),
	.ntsc    (ntsc),
	.vpos    (video_vpos),
	.diw     (diw),
	.drop_field (field1),
	.fit_height (video_fit_set),
	.fit     (video_fit),
	.r_in    (red),
	.g_in    (green),
	.b_in    (blue),
	.hsync_n (hs),
	.vsync_n (vs),
	.vbl     (vbl),
	.data    (video_data),
	.de      (video_dataEnable),
	.hblank  (video_hblank),
	.vblank  (video_vblank),
	.dbg_color ()
);
// (the framework's own frame buffers are not built: VideoV0.ownFrames)
assign {video_data_r, video_data_g, video_data_b} = 3'b000;

// The two frames (the SRAM and block RAM) and the picture on the screen
// shown: the handheld's panel, or HDMI, where the RTG board's picture
// takes its place while it is on.
wire [23:0] fb_color;
gb_fb fb
(
	.clk_sys         (clk_sys),
	.reset           (reset_d),
	.px_de           (video_dataEnable),
	.px_data         (video_data),
	.px_hblank       (video_hblank),
	.px_vblank       (video_vblank),
	.fit             (video_fit),
	.wr_frame        (video_frames_write),
	.wr_drop         (video_frames_drop),

	.clk_114         (clk_114),
	.reset_114       (reset_114),
	.sram_ceN        (sram_ceN),
	.sram_weN        (sram_weN),
	.sram_oeN        (sram_oeN),
	.sram_writeMaskN (sram_writeMaskN),
	.sram_address    (sram_address),
	.sram_dataIn     (sram_dataIn),
	.sram_dataOut    (sram_dataOut),
	.sram_dataDir    (sram_dataDir),

	.clk_av          (video_external_clock),
	.av_hdmi         (video_external_hdmi),
	.av_sync         (video_external_sync),
	.av_frame        (video_external_frame),
	.av_x            (video_external_x),
	.av_y            (video_external_y),
	.av_color        (fb_color),

	.dbg_lines       (fb_lines),
	.dbg_late        (fb_late),
	.dbg_overflow    (fb_overflow)
);

(* ASYNC_REG = "TRUE" *) reg [1:0] rtg_on_av = 2'b00;
always @(posedge video_external_clock) rtg_on_av <= {rtg_on_av[0], rtg_on};
assign video_external_enable = 1'b1;
assign video_external_color  = (rtg_on_av[1] && video_external_hdmi) ? rtg_color : fb_color;

gb_audio audio
(
	.clk       (clk_sys),
	.reset     (reset_d),
	.clk7_en   (clk7_en),
	.filter_en (audio_filter),
	.mix       (cfg_audmix),
	.mute      (~focus | core_reset),
	.ldata     (ldata),
	.rdata     (rdata),
	.toc_left  (toc_left),
	.toc_right (toc_right),
	.left      (audio_left),
	.right     (audio_right)
);

gb_input input_map
(
	.clk        (clk_sys),
	.reset      (amiga_reset),
	.btn_a      (input_slots_0_buttons_a),
	.btn_b      (input_slots_0_buttons_b),
	.btn_x      (input_slots_0_buttons_x),
	.btn_y      (input_slots_0_buttons_y),
	.btn_up     (input_slots_0_buttons_up),
	.btn_down   (input_slots_0_buttons_down),
	.btn_left   (input_slots_0_buttons_left),
	.btn_right  (input_slots_0_buttons_right),
	.btn_l      (input_slots_0_buttons_l1),
	.btn_r      (input_slots_0_buttons_r1),
	.btn_start  (input_slots_0_buttons_start),
	.btn_select (input_slots_0_buttons_select),
	.stick_lx   (input_slots_0_analog_leftX),
	.stick_ly   (input_slots_0_analog_leftY),
	.stick_rx   (input_slots_0_analog_rightX),
	.stick_ry   (input_slots_0_analog_rightY),
	.p1_active  (input_slots_1_active),
	.p1_a       (input_slots_1_buttons_a),
	.p1_b       (input_slots_1_buttons_b),
	.p1_up      (input_slots_1_buttons_up),
	.p1_down    (input_slots_1_buttons_down),
	.p1_left    (input_slots_1_buttons_left),
	.p1_right   (input_slots_1_buttons_right),
	.p1_lx      (input_slots_1_analog_leftX),
	.p1_ly      (input_slots_1_analog_leftY),
	.key_x      (key_x),
	.key_y      (key_y),
	.key_start  (key_start),
	.key_select (key_select),
	.hmouse_valid(hmouse_valid),
	.hmouse_dx  (hmouse_dx),
	.hmouse_dy  (hmouse_dy),
	.hmouse_btn (hmouse_btn),
	.hwheel_valid(hwheel_valid),
	.hwheel     (hwheel),
	.hkey_valid (hkey_valid),
	.hkey_usage (hkey_usage),
	.hkey_down  (hkey_down),
	.joy_port1  (joy_port1),
	.joy_port2  (joy_port2),
	.mouse_btn  (mouse_btn),
	.kbd_mouse_data (kbd_mouse_data),
	.kbd_mouse_type (kbd_mouse_type),
	.kbd_mouse_level(kbd_mouse_level)
);

endmodule
