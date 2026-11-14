// Game Bub Minimig: Game Bub host (MCU) interface.
//
// Host memory map (byte addresses on the HostV0 memory interface):
//
//   0x0000_0000           ID, read only: "MMIG"
//   0x0000_0004           version, read only
//   0x0000_0010..20       debug, read only: floppy sectors read / written,
//                         last floppy error, boot state, first word of the
//                         Kickstart as received
//   0x0000_0024..3C       debug, read only: hard disk state, sectors read /
//                         written, geometry and size of the two drives
//   0x0000_1000, 1004     statistics: clocks the Amiga was paused / ran since
//                         the last write (the Game Bub firmware's convention
//                         for every core: it reads and clears them on pause)
//   0x0000_1030           mouse motion {dy, dx}, signed 16 bit each, right
//                         and down positive (written by the firmware fork for
//                         a USB/Bluetooth mouse, as for the 3DO core)
//   0x0000_1034           mouse buttons: bit 0 left, 1 right, 2 middle
//   0x0000_1040..107C     settings (metadata/settings.json), read/write
//   0x1000_0000 + n<<20   disk image slot n (0..3, files.json ids 0..3),
//                         up to 1 MB each -> SDRAM
//   0x2000_0000           Kickstart ROM image (files.json id 4), up to
//                         1 MB -> SDRAM staging area
//   0x3000_0000..3FFF     sector buffer of the hard disk server (gb_ide):
//                         the firmware's FileRead / FileWrite of the hard
//                         disk images (files.json ids 5, 6, on demand) go
//                         through it
//   0xF000_0000..0C       HostV0 command parameters / results
//   0xF000_1000..14       core -> host command and its parameters (read),
//                         results (write): on-demand file I/O of gb_ide
//
// File data arrives as 32 bit words with byte 0 of the file in bits 7:0
// (the MCU's little endian words; the 3DO core found the same on hardware).
// The SDRAM keeps Amiga byte order: a 16 bit word holds file bytes 2k
// (bits 15:8) and 2k+1 (bits 7:0).
//
// Saving (FileReadStart): the answer is the size of the image as loaded
// for a slot that holds one, 0 for a slot that does not. A loaded image is
// never answered with 0: the release firmware (1.1.0-beta3) creates the
// file anew and writes as many bytes as the answer says. Before answering,
// the floppy server is allowed to finish the sector it is on and the Amiga
// is then held in reset until FileReadEnd, so that the SDRAM host port gets
// nearly every slot: the firmware's SPI reads cannot wait for the core.
// After FileReadEnd the Amiga starts again from reset.
//
// CoreHalt (the firmware sends it before saving on exit) likewise lets a
// sector being written into an image finish before the Amiga is held in
// reset.
//
// SPDX-License-Identifier: GPL-3.0-or-later

module gb_host
#(
	parameter [24:1] SLOT_BASE  = 24'h800000,  // SDRAM word address of slot 0
	parameter [24:1] SLOT_WORDS = 24'h080000,  // 1 MB per slot
	parameter [24:1] KICK_STAGE = 24'hB80000,  // SDRAM word address of the ROM
	parameter        NUM_SLOTS  = 4,
	parameter [15:0] KICK_ID    = 16'd4,       // files.json id of the Kickstart
	parameter [24:0] EJECT_TIME = 25'd14000000 // ~0.5 s at 28 MHz
)
(
	input             clk,
	input             reset,

	// HostV0 memory interface
	input      [31:0] mem_address,
	input             mem_enable,
	input             mem_write,
	output reg [31:0] mem_dataRead,
	input      [31:0] mem_dataWrite,
	output reg        mem_done,

	// HostV0 host -> core command channel
	input             cmd_request,
	output            cmd_busy,
	output            cmd_done,
	output            cmd_error,

	// SDRAM client (gb_sdram_bridge)
	output reg        sd_req,
	output reg        sd_we,
	output reg [24:1] sd_addr,
	output reg [15:0] sd_wdata,
	input             sd_ack,
	input      [15:0] sd_rdata,

	// core control
	output            core_reset,     // hold the Amiga in reset
	output reg        focus,
	output reg        boot_start,     // pulse: run the configuration sequence
	output reg        boot_reload,    // with boot_start: upload the Kickstart
	input             boot_busy,
	input             boot_done,
	input             floppy_busy,    // the floppy server is writing a sector to SDRAM

	// configuration (userio encodings)
	output reg  [5:0] cfg_chipset,
	output reg  [7:0] cfg_cpu,
	output reg  [7:0] cfg_memory,
	output reg  [4:0] cfg_floppy,
	output reg  [1:0] cfg_audmix,
	output reg [20:0] kick_size,

	// drives
	output reg  [3:0] drv_present,
	output      [3:0] drv_writable,
	output reg [11:0] drv_slot,
	output reg [31:0] drv_tracks,

	// front end settings
	output reg        audio_filter,
	output reg  [7:0] key_x,
	output reg  [7:0] key_y,
	output reg  [7:0] key_start,
	output reg  [7:0] key_select,
	output reg  [3:0] video_vpos,

	// mouse from the host (firmware)
	output reg        hmouse_valid,   // one clock per motion write
	output reg [15:0] hmouse_dx,
	output reg [15:0] hmouse_dy,
	output reg  [2:0] hmouse_btn,

	// core -> host command words and results (gb_ide)
	input      [31:0] hc_cmd,
	input      [31:0] hc_p1, hc_p2, hc_p3, hc_p4, hc_p5,
	output reg [31:0] hc_res0, hc_res1, hc_res2,

	// sector buffer of gb_ide
	output reg [11:0] hb_addr,
	output reg        hb_we,
	output reg [31:0] hb_wdata,
	input      [31:0] hb_rdata,

	// statistics
	input             stat_run,       // the Amiga ran this clock
	input             stat_stall,     // the Amiga was paused this clock

	// debug inputs
	input       [7:0] fdd_error,
	input      [15:0] fdd_sectors_read,
	input      [15:0] fdd_sectors_written,
	input      [31:0] ide_state,
	input      [31:0] ide_sectors_read,
	input      [31:0] ide_sectors_written,
	input      [31:0] ide_chs0, ide_chs1,
	input      [31:0] ide_total0, ide_total1
);

localparam [15:0] CMD_GET_STATUS     = 16'h0000;
localparam [15:0] CMD_CORE_RUN       = 16'h0100;
localparam [15:0] CMD_CORE_HALT      = 16'h0101;
localparam [15:0] CMD_SETUP_COMPLETE = 16'h0102;
localparam [15:0] CMD_NOTIFY_FOCUS   = 16'h0200;
localparam [15:0] CMD_FILE_WR_START  = 16'h0300;
localparam [15:0] CMD_FILE_WR_END    = 16'h0301;
localparam [15:0] CMD_FILE_RD_START  = 16'h0302;
localparam [15:0] CMD_FILE_RD_END    = 16'h0303;

localparam [2:0] STATUS_SETUP = 3'd2, STATUS_CORE_HALT = 3'd3, STATUS_CORE_RUN = 3'd4;

localparam [20:0] MAX_IMAGE = 21'h100000;

// ------------------------------------------------------------- settings
reg  [7:0] set_chipset;   // 0 OCS, 1 ECS, 2 AGA
reg  [7:0] set_cpu;       // 0 68000, 1 68010, 2 68EC020
reg  [7:0] set_memory;    // preset 0..7
reg  [7:0] set_video;     // 0 PAL, 1 NTSC
reg  [7:0] set_drives;    // number of drives - 1
reg  [7:0] set_fspeed;    // 0 normal, 1 turbo
reg  [7:0] set_df0;       // slot, >= NUM_SLOTS = empty
reg  [7:0] set_df1;
reg  [7:0] set_filter;
reg  [7:0] set_stereo;
reg  [7:0] set_vpos;

// memory presets: XHFFSSCC
function automatic [7:0] mem_preset(input [2:0] p);
	case (p)
		3'd0: mem_preset = 8'h00;   // 512K chip
		3'd1: mem_preset = 8'h04;   // 512K chip + 512K slow
		3'd2: mem_preset = 8'h01;   // 1M chip
		3'd3: mem_preset = 8'h05;   // 1M chip + 512K slow
		3'd4: mem_preset = 8'h03;   // 2M chip
		3'd5: mem_preset = 8'h13;   // 2M chip + 2M fast
		3'd6: mem_preset = 8'h23;   // 2M chip + 4M fast
		3'd7: mem_preset = 8'h33;   // 2M chip + 8M fast
	endcase
endfunction

always @* begin
	// XXGEANT: G AGA, E ECS, A A1000 boot ROM, N NTSC, T turbo
	cfg_chipset  = {1'b0, set_chipset == 8'd2, set_chipset == 8'd1, 1'b0, set_video[0], 1'b0};
	// SSPCCCTT: 68EC020 = TT 11 with P (A1200 speed)
	cfg_cpu      = (set_cpu == 8'd2) ? 8'h23 : (set_cpu == 8'd1) ? 8'h01 : 8'h00;
	cfg_memory   = mem_preset(set_memory[2:0]);
	cfg_floppy   = {2'b00, set_drives[1:0], set_fspeed[0]};
	cfg_audmix   = set_stereo[1:0];
	audio_filter = set_filter[0];
	video_vpos   = set_vpos[3:0];
end

// --------------------------------------------------------------- files
reg [20:0] slot_size   [0:NUM_SLOTS-1];
reg  [7:0] slot_tracks [0:NUM_SLOTS-1];
reg        kick_loaded;
reg        kick_dirty;     // a new Kickstart image has to be uploaded
reg [31:0] kick_first;     // first host word of the Kickstart (debug)

// tracks = size / 5632 (11 sectors of 512 bytes), at most 166 (MAX_TRACKS)
reg        div_busy;
reg  [1:0] div_slot;
reg [20:0] div_rem;
reg  [7:0] div_q;

function automatic [20:0] clamp_size(input [31:0] s);
	clamp_size = (s > {11'd0, MAX_IMAGE}) ? MAX_IMAGE : s[20:0];
endfunction

// --------------------------------------------------------------- drives
reg  [7:0] eff_slot [0:3];
reg [24:0] eject_cnt [0:1];
reg  [7:0] prev_df0, prev_df1;

assign drv_writable = 4'b1111;

integer i;
always @* begin
	eff_slot[0] = set_df0;
	eff_slot[1] = set_df1;
	eff_slot[2] = 8'd2;
	eff_slot[3] = 8'd3;
	for (i = 0; i < 4; i = i + 1) begin
		drv_slot[i*3 +: 3]   = (eff_slot[i] < NUM_SLOTS) ? eff_slot[i][2:0] : 3'd0;
		drv_present[i]       = (eff_slot[i] < NUM_SLOTS) && (slot_size[eff_slot[i][1:0]] != 21'd0)
		                       && (i > 1 || eject_cnt[i[0]] == 25'd0);
		drv_tracks[i*8 +: 8] = (eff_slot[i] < NUM_SLOTS) ? slot_tracks[eff_slot[i][1:0]] : 8'd0;
	end
end

// ------------------------------------------------------ command channel
reg [31:0] reg_p0, reg_p1, reg_p2, reg_p3;
reg  [1:0] cmd_state;    // 0 idle, 1 busy, 2 done, 3 error
reg  [2:0] status;
reg        setup_done;
reg        ever_run;
reg        halted;       // CoreHalt or before the first CoreRun
reg        halt_wait;    // CoreHalt waits for the floppy server
reg        freeze;       // a file is being read back (FileReadStart..End)
reg        freeze_wait;  // FileReadStart waits for the floppy server
reg        reset_req;    // the "Reset" action
reg        boot_pending, boot_pending_reload;

assign cmd_busy  = (cmd_state == 2'd1);
assign cmd_done  = (cmd_state == 2'd2);
assign cmd_error = (cmd_state == 2'd3);

assign core_reset = halted | freeze;

// ---------------------------------------------------------- statistics
reg [31:0] stat_stalls, stat_cycles;
reg  [1:0] stat_clr;
always @(posedge clk) begin
	if (reset || stat_clr[0]) stat_stalls <= 32'd0;
	else if (stat_stall && stat_stalls != 32'hFFFFFFFF) stat_stalls <= stat_stalls + 32'd1;
	if (reset || stat_clr[1]) stat_cycles <= 32'd0;
	else if (stat_run && stat_cycles != 32'hFFFFFFFF) stat_cycles <= stat_cycles + 32'd1;
end

// ------------------------------------------------------- memory access
localparam M_IDLE = 3'd0, M_W0 = 3'd1, M_W1 = 3'd2, M_R0 = 3'd3, M_R1 = 3'd4, M_DONE = 3'd5,
           M_B0 = 3'd6, M_B1 = 3'd7;
reg  [2:0] mstate;
reg [24:1] m_base;
reg [31:0] m_wdata;
reg [15:0] m_r0;

wire        is_reg   = (mem_address[31:16] == 16'h0000);
wire        is_disk  = (mem_address[31:28] == 4'h1) && (mem_address[27:22] == 6'd0) && (mem_address[21:20] < NUM_SLOTS);
wire        is_kick  = (mem_address[31:20] == 12'h200);
wire        is_cmd   = (mem_address[31:4] == 28'hF000000);
wire        is_ccmd  = (mem_address[31:5] == 27'h7800080);     // 0xF000_1000..1F
wire        is_buf   = (mem_address[31:14] == 18'h0C000);      // 0x3000_0000..3FFF
wire [24:1] disk_adr = SLOT_BASE + SLOT_WORDS * mem_address[21:20] + {5'd0, mem_address[19:1]};
wire [24:1] kick_adr = KICK_STAGE + {5'd0, mem_address[19:1]};

function automatic [31:0] reg_read(input [15:0] a);
	case (a)
		16'h0000: reg_read = 32'h4D4D4947;   // "MMIG"
		16'h0004: reg_read = 32'h00010001;   // version 1.1
		16'h0010: reg_read = {16'd0, fdd_sectors_read};
		16'h0014: reg_read = {16'd0, fdd_sectors_written};
		16'h0018: reg_read = {24'd0, fdd_error};
		16'h001C: reg_read = {27'd0, freeze, halted, kick_loaded, boot_busy, boot_done};
		16'h0020: reg_read = kick_first;
		16'h0024: reg_read = ide_state;
		16'h0028: reg_read = ide_sectors_read;
		16'h002C: reg_read = ide_sectors_written;
		16'h0030: reg_read = ide_chs0;
		16'h0034: reg_read = ide_chs1;
		16'h0038: reg_read = ide_total0;
		16'h003C: reg_read = ide_total1;
		16'h1000: reg_read = stat_stalls;
		16'h1004: reg_read = stat_cycles;
		16'h1030: reg_read = {hmouse_dy, hmouse_dx};
		16'h1034: reg_read = {29'd0, hmouse_btn};
		16'h1040: reg_read = 32'd0;          // Reset (action)
		16'h1044: reg_read = {24'd0, set_chipset};
		16'h1048: reg_read = {24'd0, set_cpu};
		16'h104C: reg_read = {24'd0, set_memory};
		16'h1050: reg_read = {24'd0, set_video};
		16'h1054: reg_read = {24'd0, set_drives};
		16'h1058: reg_read = {24'd0, set_fspeed};
		16'h105C: reg_read = {24'd0, set_df0};
		16'h1060: reg_read = {24'd0, set_df1};
		16'h1064: reg_read = {24'd0, set_filter};
		16'h1068: reg_read = {24'd0, set_stereo};
		16'h106C: reg_read = {24'd0, key_x};
		16'h1070: reg_read = {24'd0, key_y};
		16'h1074: reg_read = {24'd0, key_start};
		16'h1078: reg_read = {24'd0, key_select};
		16'h107C: reg_read = {24'd0, set_vpos};
		default:  reg_read = 32'd0;
	endcase
endfunction

always @(posedge clk) begin
	mem_done     <= 1'b0;
	boot_start   <= 1'b0;
	hmouse_valid <= 1'b0;
	stat_clr     <= 2'b00;
	hb_we        <= 1'b0;

	if (reset) begin
		hc_res0      <= 32'd0;
		hc_res1      <= 32'd0;
		hc_res2      <= 32'd0;
		mstate       <= M_IDLE;
		sd_req       <= 1'b0;
		sd_we        <= 1'b0;
		cmd_state    <= 2'd0;
		status       <= STATUS_SETUP;
		setup_done   <= 1'b0;
		ever_run     <= 1'b0;
		halted       <= 1'b1;
		halt_wait    <= 1'b0;
		freeze       <= 1'b0;
		freeze_wait  <= 1'b0;
		focus        <= 1'b1;
		reset_req    <= 1'b0;
		boot_pending <= 1'b0;
		boot_pending_reload <= 1'b0;
		boot_reload  <= 1'b0;
		kick_loaded  <= 1'b0;
		kick_dirty   <= 1'b0;
		kick_size    <= 21'd0;
		kick_first   <= 32'd0;
		div_busy     <= 1'b0;
		set_chipset  <= 8'd0;
		set_cpu      <= 8'd0;
		set_memory   <= 8'd1;
		set_video    <= 8'd0;
		set_drives   <= 8'd0;
		set_fspeed   <= 8'd0;
		set_df0      <= 8'd0;
		set_df1      <= 8'd7;
		set_filter   <= 8'd1;
		set_stereo   <= 8'd2;
		key_x        <= 8'h40;   // Space
		key_y        <= 8'h44;   // Return
		key_start    <= 8'h50;   // F1
		key_select   <= 8'h45;   // Esc
		set_vpos     <= 8'd8;
		hmouse_dx    <= 16'd0;
		hmouse_dy    <= 16'd0;
		hmouse_btn   <= 3'd0;
		prev_df0     <= 8'd0;
		prev_df1     <= 8'd7;
		eject_cnt[0] <= 25'd0;
		eject_cnt[1] <= 25'd0;
		for (i = 0; i < NUM_SLOTS; i = i + 1) begin
			slot_size[i]   <= 21'd0;
			slot_tracks[i] <= 8'd0;
		end
	end
	else begin
		// ---------------------------------------------- disk swaps
		// a changed DF0/DF1 setting removes the disk for EJECT_TIME, so the
		// Amiga sees the disk change
		prev_df0 <= set_df0;
		prev_df1 <= set_df1;
		if (prev_df0 != set_df0) eject_cnt[0] <= EJECT_TIME;
		else if (eject_cnt[0] != 25'd0) eject_cnt[0] <= eject_cnt[0] - 25'd1;
		if (prev_df1 != set_df1) eject_cnt[1] <= EJECT_TIME;
		else if (eject_cnt[1] != 25'd0) eject_cnt[1] <= eject_cnt[1] - 25'd1;

		// ---------------------------------------------- tracks of a slot
		if (div_busy) begin
			if (div_rem >= 21'd5632 && div_q != 8'd166) begin
				div_rem <= div_rem - 21'd5632;
				div_q   <= div_q + 8'd1;
			end
			else begin
				slot_tracks[div_slot] <= div_q;
				div_busy <= 1'b0;
			end
		end

		// ---------------------------------------------- boot requests
		if (boot_pending && !boot_busy && !boot_start && !core_reset) begin
			boot_start   <= 1'b1;
			boot_reload  <= boot_pending_reload;
			boot_pending <= 1'b0;
			if (boot_pending_reload) kick_dirty <= 1'b0;
		end
		if (reset_req && status == STATUS_CORE_RUN && !boot_pending) begin
			reset_req           <= 1'b0;
			boot_pending        <= 1'b1;
			boot_pending_reload <= kick_dirty;
		end

		// ---------------------------------------------- memory interface
		case (mstate)
		// The framework (SpiReceiverFifo) keeps enable high from one request
		// to the next, also in the clock that done is high: the request seen
		// then is the one just completed, so a new one starts only after it.
		M_IDLE:
			if (mem_enable && !mem_done) begin
				if (is_disk || is_kick) begin
					if (mem_write && is_kick && mem_address[19:0] == 20'd0) kick_first <= mem_dataWrite;
					m_base  <= is_disk ? disk_adr : kick_adr;
					m_wdata <= mem_dataWrite;
					mstate  <= mem_write ? M_W0 : M_R0;
				end
				else if (is_buf) begin
					hb_addr  <= mem_address[13:2];
					hb_wdata <= mem_dataWrite;
					hb_we    <= mem_write;
					mstate   <= M_B0;
				end
				else begin
					if (mem_write) begin
						if (is_cmd) case (mem_address[3:2])
							2'd0: reg_p0 <= mem_dataWrite;
							2'd1: reg_p1 <= mem_dataWrite;
							2'd2: reg_p2 <= mem_dataWrite;
							2'd3: reg_p3 <= mem_dataWrite;
						endcase
						else if (is_ccmd) case (mem_address[4:2])
							3'd0: hc_res0 <= mem_dataWrite;
							3'd1: hc_res1 <= mem_dataWrite;
							3'd2: hc_res2 <= mem_dataWrite;
							default: ;
						endcase
						else if (is_reg) case (mem_address[15:0])
							16'h1000: stat_clr[0] <= 1'b1;
							16'h1004: stat_clr[1] <= 1'b1;
							16'h1030: begin
								hmouse_valid <= 1'b1;
								hmouse_dx    <= mem_dataWrite[15:0];
								hmouse_dy    <= mem_dataWrite[31:16];
							end
							16'h1034: hmouse_btn  <= mem_dataWrite[2:0];
							16'h1040: if (mem_dataWrite != 32'd0) reset_req <= 1'b1;
							16'h1044: set_chipset <= mem_dataWrite[7:0];
							16'h1048: set_cpu     <= mem_dataWrite[7:0];
							16'h104C: set_memory  <= mem_dataWrite[7:0];
							16'h1050: set_video   <= mem_dataWrite[7:0];
							16'h1054: set_drives  <= mem_dataWrite[7:0];
							16'h1058: set_fspeed  <= mem_dataWrite[7:0];
							16'h105C: set_df0     <= mem_dataWrite[7:0];
							16'h1060: set_df1     <= mem_dataWrite[7:0];
							16'h1064: set_filter  <= mem_dataWrite[7:0];
							16'h1068: set_stereo  <= mem_dataWrite[7:0];
							16'h106C: key_x       <= mem_dataWrite[7:0];
							16'h1070: key_y       <= mem_dataWrite[7:0];
							16'h1074: key_start   <= mem_dataWrite[7:0];
							16'h1078: key_select  <= mem_dataWrite[7:0];
							16'h107C: set_vpos    <= mem_dataWrite[7:0];
							default: ;
						endcase
					end
					else begin
						if (is_cmd) case (mem_address[3:2])
							2'd0: mem_dataRead <= reg_p0;
							2'd1: mem_dataRead <= reg_p1;
							2'd2: mem_dataRead <= reg_p2;
							2'd3: mem_dataRead <= reg_p3;
						endcase
						else if (is_ccmd) case (mem_address[4:2])
							3'd0: mem_dataRead <= hc_cmd;
							3'd1: mem_dataRead <= hc_p1;
							3'd2: mem_dataRead <= hc_p2;
							3'd3: mem_dataRead <= hc_p3;
							3'd4: mem_dataRead <= hc_p4;
							3'd5: mem_dataRead <= hc_p5;
							default: mem_dataRead <= 32'd0;
						endcase
						else if (is_reg) mem_dataRead <= reg_read(mem_address[15:0]);
						else mem_dataRead <= 32'd0;
					end
					mstate <= M_DONE;
				end
			end

		// writes: two SDRAM words, Amiga byte order
		M_W0:
			if (!sd_req) begin
				sd_req   <= 1'b1;
				sd_we    <= 1'b1;
				sd_addr  <= m_base;
				sd_wdata <= {m_wdata[7:0], m_wdata[15:8]};
			end
			else if (sd_ack) begin
				sd_req <= 1'b0;
				mstate <= M_W1;
			end
		M_W1:
			if (!sd_req) begin
				sd_req   <= 1'b1;
				sd_we    <= 1'b1;
				sd_addr  <= m_base + 24'd1;
				sd_wdata <= {m_wdata[23:16], m_wdata[31:24]};
			end
			else if (sd_ack) begin
				sd_req <= 1'b0;
				mstate <= M_DONE;
			end

		M_R0:
			if (!sd_req) begin
				sd_req  <= 1'b1;
				sd_we   <= 1'b0;
				sd_addr <= m_base;
			end
			else if (sd_ack) begin
				sd_req <= 1'b0;
				m_r0   <= sd_rdata;
				mstate <= M_R1;
			end
		M_R1:
			if (!sd_req) begin
				sd_req  <= 1'b1;
				sd_we   <= 1'b0;
				sd_addr <= m_base + 24'd1;
			end
			else if (sd_ack) begin
				sd_req       <= 1'b0;
				mem_dataRead <= {sd_rdata[7:0], sd_rdata[15:8], m_r0[7:0], m_r0[15:8]};
				mstate       <= M_DONE;
			end

		// sector buffer of gb_ide (block RAM: the read data follows the address)
		M_B0: mstate <= M_B1;
		M_B1: begin
			mem_dataRead <= hb_rdata;
			mstate       <= M_DONE;
		end

		// done is high for one clock; the next access may start right after
		M_DONE: begin
			mem_done <= 1'b1;
			mstate   <= M_IDLE;
		end
		default: mstate <= M_IDLE;
		endcase

		// ---------------------------------------------- CoreHalt
		if (halt_wait && !floppy_busy) begin
			halt_wait <= 1'b0;
			halted    <= 1'b1;
		end

		// ---------------------------------------------- FileReadStart wait
		if (freeze_wait && !floppy_busy) begin
			freeze_wait <= 1'b0;
			freeze      <= 1'b1;
			cmd_state   <= 2'd2;
		end

		// ---------------------------------------------- command channel
		if (cmd_request) begin
			if (cmd_state == 2'd0) begin
				cmd_state <= 2'd2;
				reg_p0    <= 32'd0;
				case (reg_p0[15:0])
					CMD_GET_STATUS: reg_p0 <= {29'd0, status};

					CMD_SETUP_COMPLETE: begin
						setup_done <= 1'b1;
						if (status == STATUS_SETUP) status <= STATUS_CORE_HALT;
					end

					CMD_CORE_RUN:
						if (!setup_done) cmd_state <= 2'd3;
						else if (status != STATUS_CORE_RUN) begin
							status    <= STATUS_CORE_RUN;
							halted    <= 1'b0;
							halt_wait <= 1'b0;
							// first run, or after a halt: full configuration
							// (the Kickstart when one arrived since the last upload)
							boot_pending        <= 1'b1;
							boot_pending_reload <= kick_loaded && (kick_dirty || !ever_run);
							reset_req <= 1'b0;
							ever_run  <= 1'b1;
						end

					CMD_CORE_HALT: begin
						if (setup_done) status <= STATUS_CORE_HALT;
						halt_wait <= 1'b1;   // halted once no sector is being written
					end

					CMD_NOTIFY_FOCUS: focus <= reg_p1[0];

					CMD_FILE_WR_START:
						if (reg_p1[15:0] == KICK_ID) begin
							kick_loaded <= 1'b0;
						end
						else if (reg_p1[15:0] < NUM_SLOTS) begin
							// the drive is empty while its image arrives
							slot_size[reg_p1[1:0]]   <= 21'd0;
							slot_tracks[reg_p1[1:0]] <= 8'd0;
						end

					CMD_FILE_WR_END:
						if (reg_p1[15:0] == KICK_ID) begin
							kick_size   <= clamp_size(reg_p2);
							kick_loaded <= (reg_p2 != 32'd0);
							kick_dirty  <= 1'b1;
						end
						else if (reg_p1[15:0] < NUM_SLOTS) begin
							slot_size[reg_p1[1:0]] <= clamp_size(reg_p2);
							div_busy <= 1'b1;
							div_slot <= reg_p1[1:0];
							div_rem  <= clamp_size(reg_p2);
							div_q    <= 8'd0;
						end
						else cmd_state <= 2'd3;

					CMD_FILE_RD_START:
						if (reg_p1[15:0] < NUM_SLOTS && slot_size[reg_p1[1:0]] != 21'd0) begin
							reg_p0 <= {11'd0, slot_size[reg_p1[1:0]]};
							if (freeze) cmd_state <= 2'd2;
							else begin
								// answered once no sector is being written
								cmd_state   <= 2'd1;
								freeze_wait <= 1'b1;
							end
						end
						else reg_p0 <= 32'd0;   // nothing to save

					CMD_FILE_RD_END:
						if (freeze) begin
							freeze <= 1'b0;
							// the Amiga starts again from reset
							if (status == STATUS_CORE_RUN) begin
								boot_pending        <= 1'b1;
								boot_pending_reload <= kick_dirty;
							end
						end

					default: cmd_state <= 2'd3;
				endcase
			end
		end
		else cmd_state <= 2'd0;   // also ends a busy command the host gave up on
	end
end

endmodule
