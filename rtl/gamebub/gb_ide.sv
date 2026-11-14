// Game Bub Minimig: hard disk images for the Gayle IDE port.
//
// On MiSTer the ARM (Main_MiSTer ide.cpp) serves the drives of rtl/minimig
// ide.sv: it watches the request lines, reads the task file through the
// "management" port, moves sectors between the image file and the buffer
// of ide.sv and writes the task file back. This module is that part in
// hardware, for the two drives of the primary port (master and slave):
//
//   ide_io()             the poll loop (requests 4 command, 5 data, 6 reset)
//   ide_get/set_regs()   task file through management addresses 0..5
//   handle_hdd()         identify, read (multiple), write (multiple), set
//                        multiple, recalibrate, verify, seek, standby,
//                        diagnostic, initialize device parameters
//   ide_open(), guess_geometry(), calc_geometry(), ide_set_geometry(),
//   ide_img_set()        mounting: an image with a Rigid Disk Block uses
//                        the geometry in it; an image without one (a
//                        single partition "hardfile") gets a virtual RDB
//                        and PART block in front of it (fill_fake_rdb())
//
// The image files stay on the SD card. Sectors are fetched and stored with
// the framework's on-demand file commands (core -> host, v1.1.0-beta4):
// FileGetSize, FileRead, FileWrite, FileFlush. The firmware moves the data
// through the HostV0 memory interface from / to a 16 KB buffer (32
// sectors, the largest block of a read / write multiple) at BUF_ADDR, of
// which gb_host has the other port.
//
// Byte order: a host word holds file byte 4k in bits 7:0. ide.sv takes 16
// bit words with byte 2k in bits 7:0, the low half of a host word first.
//
// Differences from ide.cpp, on purpose:
//  * every block is fetched by its own position (ide.cpp reads on from the
//    file position, which is wrong after a block of the virtual RDB);
//  * a short read is padded with zeros; later blocks are still read;
//  * set multiple with 0 sectors leaves the block size as it was (ide.cpp
//    would then transfer blocks of 0 sectors);
//  * command FA (mount an image by name, used by ao486) is not built.
//
// SPDX-License-Identifier: GPL-3.0-or-later

module gb_ide
#(
	parameter [15:0] FILE_ID0   = 16'd5,          // files.json id of the master's image, the slave's follows
	parameter [31:0] BUF_ADDR   = 32'h3000_0000,  // host address of the sector buffer
	parameter [26:0] HOST_TIME  = 27'h7FFFFFF,    // clocks to wait for the first answer of the host (4.7 s)
	parameter [24:0] FLUSH_TIME = 25'd28000000    // idle clocks before written data is flushed (1 s)
)
(
	input             clk,
	input             reset,

	input             enable,        // the Amiga is configured and runs
	input             start,         // pulse: look at the image files again (before the Amiga boots)
	output            mount_busy,    // the images are being looked at
	output      [1:0] present,       // drive has an image {slave, master}

	// management port of gayle / ide.sv
	input       [2:0] ide_req,
	output reg  [4:0] ide_address,
	output reg        ide_write,
	output reg [15:0] ide_writedata,
	output reg        ide_read,
	input      [15:0] ide_readdata,

	// HostV0 core -> host command (words read by the host through gb_host)
	output reg        hc_request,
	output reg [31:0] hc_cmd,
	output reg [31:0] hc_p1, hc_p2, hc_p3, hc_p4, hc_p5,
	input             hc_done,
	input             hc_error,
	input      [31:0] hc_res0, hc_res1, hc_res2,

	// sector buffer, host side
	input      [11:0] hb_addr,
	input             hb_we,
	input      [31:0] hb_wdata,
	output reg [31:0] hb_rdata,

	// debug
	output reg [31:0] dbg_sectors_read,
	output reg [31:0] dbg_sectors_written,
	output     [31:0] dbg_chs0,      // {cylinders, heads[6:0], sectors per track[8:0]}
	output     [31:0] dbg_chs1,
	output     [31:0] dbg_total0,    // sectors of the image
	output     [31:0] dbg_total1,
	output     [31:0] dbg_state      // {no host, mounted, dirty, xnull, port state, state}
);

localparam [31:0] CMD_FILE_GET_SIZE = 32'h0400, CMD_FILE_READ = 32'h0402,
                  CMD_FILE_WRITE = 32'h0403, CMD_FILE_FLUSH = 32'h0404;

localparam [7:0] ST_BSY = 8'h80, ST_RDY = 8'h40, ST_RDP = 8'h20, ST_DSC = 8'h10,
                 ST_DRQ = 8'h08, ST_IRQ = 8'h04, ST_END = 8'h02, ST_ERR = 8'h01;
localparam [7:0] ERR_ABRT = 8'h04;

localparam [1:0] P_IDLE = 2'd0, P_RESET = 2'd1, P_WAIT_RD = 2'd2, P_WAIT_WR = 2'd3;

// ------------------------------------------------------- sector buffer
// true dual port: the host on one side, this module on the other
reg [31:0] buf_mem [0:4095];
reg [11:0] eb_addr;
reg        eb_we;
reg [31:0] eb_wdata;
reg [31:0] eb_rdata;

always @(posedge clk) begin
	if (hb_we) buf_mem[hb_addr] <= hb_wdata;
	hb_rdata <= buf_mem[hb_addr];
end
always @(posedge clk) begin
	if (eb_we) buf_mem[eb_addr] <= eb_wdata;
	eb_rdata <= buf_mem[eb_addr];
end

function automatic [31:0] bswap(input [31:0] v);
	bswap = {v[7:0], v[15:8], v[23:16], v[31:24]};
endfunction

// -------------------------------------------------------------- drives
reg  [1:0] drv_present;
reg [15:0] drv_cyl    [0:1];
reg  [7:0] drv_heads  [0:1];
reg  [8:0] drv_spt    [0:1];
reg [31:0] drv_total  [0:1];
reg [12:0] drv_offset [0:1];   // sectors of the virtual RDB in front of the image
reg  [5:0] drv_spb    [0:1];   // sectors per block (set multiple)
reg  [1:0] drv_dirty;          // written to since the last flush

assign present    = drv_present;
assign dbg_chs0   = {drv_cyl[0], drv_heads[0][6:0], drv_spt[0]};
assign dbg_chs1   = {drv_cyl[1], drv_heads[1][6:0], drv_spt[1]};
assign dbg_total0 = drv_total[0];
assign dbg_total1 = drv_total[1];

// ------------------------------------------------- task file (regs_t)
reg        r_io_fast;
reg  [7:0] r_features;
reg  [7:0] r_sector_count;
reg  [7:0] r_sector;
reg [15:0] r_cylinder;
reg  [3:0] r_head;
reg        r_drv;
reg        r_lba;
reg  [7:0] r_cmd;
reg  [7:0] r_io_size;
reg  [7:0] r_error;
reg  [7:0] r_status;

reg  [1:0] pstate;        // ide_config.state
reg [31:0] xfer_lba;
reg  [5:0] xfer_cnt;
reg        xfer_multi;
reg        xfer_irq;
reg        xnull;          // the image could not be read / written: zeros

wire [15:0] d_cyl    = drv_cyl[r_drv];
wire  [7:0] d_heads  = drv_heads[r_drv];
wire  [8:0] d_spt    = drv_spt[r_drv];
wire [31:0] d_total  = drv_total[r_drv];
wire [12:0] d_offset = drv_offset[r_drv];
wire  [5:0] d_spb    = drv_spb[r_drv];

// get_cnt(): sectors of the next block
wire  [5:0] get_cnt  = (r_sector_count == 8'd0 || r_sector_count > {2'd0, d_spb}) ? d_spb : r_sector_count[5:0];
wire  [5:0] next_cnt = xfer_multi ? get_cnt : 6'd1;

// ide_set_regs(): the six words of the task file
wire  [7:0] status_out = (r_status & (ST_BSY | ST_ERR)) != 8'd0 ? r_status : (r_status | ST_DSC);
function automatic [15:0] regs_word(input [2:0] i);
	case (i)
		3'd0: regs_word = {r_error, r_io_size};
		3'd1: regs_word = {r_sector, r_sector_count};
		3'd2: regs_word = r_cylinder;
		3'd5: regs_word = {status_out, r_lba ? 3'b111 : 3'b101, r_drv, r_head};
		default: regs_word = 16'h0000;
	endcase
endfunction

// ------------------------------------------------ identify (drive->id)
localparam [8*40-1:0] MODEL = "Game Bub Minimig hard disk image        ";
function automatic [15:0] idword(input [7:0] i);
	reg [5:0] k;
	begin
		idword = 16'h0000;
		k = 6'd0;
		case (i)
			8'd0:   idword = 16'h0040;
			8'd1:   idword = d_cyl;
			8'd3:   idword = {8'd0, d_heads};
			8'd4:   idword = {d_spt[6:0], 9'd0};       // bytes per track
			8'd5:   idword = 16'd512;
			8'd6:   idword = {7'd0, d_spt};
			8'd10:  idword = 16'h414F;                 // "AO"
			8'd11:  idword = 16'h4844;                 // "HD"
			8'd12:  idword = 16'h3030;
			8'd13:  idword = 16'h3030;
			8'd14:  idword = 16'h3020;
			8'd15, 8'd16, 8'd17, 8'd18, 8'd19: idword = 16'h2020;
			8'd20:  idword = 16'd3;
			8'd21:  idword = 16'd512;
			8'd22:  idword = 16'd4;
			8'd47:  idword = 16'h8020;                 // max multiple sectors
			8'd48:  idword = 16'd1;
			8'd49:  idword = 16'h0200;                 // LBA
			8'd50:  idword = 16'h4001;
			8'd51:  idword = 16'h0200;
			8'd52:  idword = 16'h0200;
			8'd53:  idword = 16'h0007;
			8'd54:  idword = d_cyl;
			8'd55:  idword = {8'd0, d_heads};
			8'd56:  idword = {7'd0, d_spt};
			8'd57:  idword = d_total[15:0];
			8'd58:  idword = d_total[31:16];
			8'd59:  idword = 16'h0110;
			8'd60:  idword = d_total[15:0];
			8'd61:  idword = d_total[31:16];
			8'd65, 8'd66, 8'd67, 8'd68: idword = 16'd120;
			8'd80:  idword = 16'h007E;
			8'd82:  idword = 16'h4200;
			8'd83:  idword = 16'h7000;
			8'd84:  idword = 16'h4000;
			8'd85:  idword = 16'h4200;
			8'd86:  idword = 16'h7000;
			8'd87:  idword = 16'h4000;
			8'd93:  idword = 16'h630B;
			8'd100: idword = d_total[15:0];
			8'd101: idword = d_total[31:16];
			default:
				if (i >= 8'd27 && i <= 8'd46) begin    // model: two characters per word
					k = i[5:0] - 6'd27;
					idword = MODEL[8*(38 - 2*k) +: 16];
				end
		endcase
	end
endfunction

// ----------------------------------- virtual RDB (fill_fake_rdb())
// long idx of block 0 (RDSK) or 1 (PART), as the big endian value; the
// checksum (long 2) is put in afterwards
function automatic [31:0] rdb_long(input blk, input [5:0] idx);
	begin
		rdb_long = 32'd0;
		if (!blk) case (idx)
			6'd0:  rdb_long = 32'h5244534B;            // "RDSK"
			6'd1:  rdb_long = 32'h00000040;
			6'd3:  rdb_long = 32'h00000007;            // host id
			6'd4:  rdb_long = 32'h00000200;            // block bytes
			6'd5:  rdb_long = 32'h00000012;            // flags
			6'd6:  rdb_long = 32'hFFFFFFFF;            // bad block list
			6'd7:  rdb_long = 32'h00000001;            // partition list
			6'd8, 6'd9, 6'd10, 6'd11, 6'd12, 6'd13, 6'd14, 6'd15: rdb_long = 32'hFFFFFFFF;
			6'd16: rdb_long = {16'd0, d_cyl};
			6'd17: rdb_long = {23'd0, d_spt};
			6'd18: rdb_long = {24'd0, d_heads};
			6'd19: rdb_long = 32'd1;                   // interleave
			6'd20: rdb_long = {16'd0, d_cyl};          // park
			6'd24: rdb_long = {16'd0, d_cyl};          // write precomp
			6'd25: rdb_long = {16'd0, d_cyl};          // reduced write
			6'd26: rdb_long = 32'd3;                   // step rate
			6'd33: rdb_long = 32'd1;                   // RDB blocks high
			6'd34: rdb_long = 32'd1;                   // low cylinder
			6'd35: rdb_long = {16'd0, d_cyl} - 32'd1;  // high cylinder
			6'd36: rdb_long = {19'd0, d_offset};       // blocks per cylinder (heads * sectors)
			6'd38: rdb_long = 32'd1;                   // highest RDSK block
			6'd40: rdb_long = 32'h444F4E27;            // "DON'T   REPARTITION!    0.00"
			6'd41: rdb_long = 32'h54202020;
			6'd42: rdb_long = 32'h52455041;
			6'd43: rdb_long = 32'h52544954;
			6'd44: rdb_long = 32'h494F4E21;
			6'd45: rdb_long = 32'h20202020;
			6'd46: rdb_long = 32'h302E3030;
			default: ;
		endcase
		else case (idx)
			6'd0:  rdb_long = 32'h50415254;            // "PART"
			6'd1:  rdb_long = 32'h00000040;
			6'd3:  rdb_long = 32'h00000007;
			6'd4:  rdb_long = 32'hFFFFFFFF;            // next
			6'd5:  rdb_long = 32'h00000001;            // bootable
			6'd9:  rdb_long = {24'h034448, 7'b0011000, r_drv};   // BCPL "DH0" / "DH1"
			6'd32: rdb_long = 32'h00000010;            // table size
			6'd33: rdb_long = 32'h00000080;            // longs per block
			6'd35: rdb_long = {24'd0, d_heads};        // surfaces
			6'd36: rdb_long = 32'd1;                   // sectors per block
			6'd37: rdb_long = {23'd0, d_spt};          // blocks per track
			6'd38: rdb_long = 32'd2;                   // reserved blocks
			6'd41: rdb_long = 32'd1;                   // low cylinder
			6'd42: rdb_long = {16'd0, d_cyl} - 32'd1;  // high cylinder
			6'd43: rdb_long = 32'd30;                  // buffers
			6'd45: rdb_long = 32'h00FFFFFF;            // max transfer
			6'd46: rdb_long = 32'h7FFFFFFE;            // mask
			6'd48: rdb_long = 32'h444F5301;            // DOS\1
			default: ;
		endcase
	end
endfunction

// ------------------------------------------------- multiplier, divider
reg [31:0] mul_a;
reg [16:0] mul_b;
reg [31:0] mul_p;
always @(posedge clk) mul_p <= mul_a * mul_b;

reg [31:0] dv_n, dv_q;
reg [16:0] dv_d;
reg [17:0] dv_r;
reg  [5:0] dv_i;
wire [17:0] dv_t = {dv_r[16:0], dv_n[31]};

// ----------------------------------------------------------- the engine
typedef enum logic [6:0] {
	S_POLL,
	// word level: these return to ret1
	S_MW0, S_MW1, S_MW2,                 // management write
	S_MR0, S_MR1, S_MR2,                 // management read
	S_HC0, S_HC1, S_HC2,                 // host command
	S_DIV,
	S_ZF0,                               // zero the buffer words xi .. xn-1
	// these return to ret2
	S_SR0, S_SR1,                        // ide_set_regs
	S_GR0, S_GR1, S_GR2,                 // ide_get_regs
	S_SD0, S_SD1, S_SD2, S_SD3, S_SD4,   // buffer -> ide.sv
	S_RV0, S_RV1, S_RV2, S_RV3,          // ide.sv -> buffer
	S_GL0, S_GL1, S_GL2, S_GL3, S_GL4,   // get_lba
	S_PL0, S_PL1, S_PL2, S_PL3, S_PL4, S_PL5,   // put_lba
	S_LB0, S_LB1, S_FK0, S_FK1, S_FK2, S_FK3,   // readhdd
	// commands
	S_CMD, S_ERR, S_SG0, S_SG1, S_SG2, S_SG3, S_C91,
	S_ID0, S_ID1,
	S_READ0, S_READ1, S_READ2, S_RSB0, S_RSB1, S_RSB2, S_RSB3, S_RSB4,
	S_WRITE0, S_WRITE1, S_WRB0, S_WRB1, S_WCB0, S_WCB1, S_WCB2, S_WCB3, S_WCB4,
	S_RST0, S_RST1,
	S_FL0, S_FL1,
	// mounting
	S_MNT0, S_MNT1, S_MNT2, S_MNT3, S_MNT4, S_MNT5, S_MNT6, S_MNT7, S_MNT8,
	S_MR_0, S_MR_1, S_MR_2, S_MR_3, S_MR_4, S_MR_5,
	S_CG0, S_CG1, S_CG2, S_CG3, S_CG4,
	S_MG0, S_MG1, S_MNTN, S_MP0, S_MP1, S_MP2, S_MNTE
} state_t;

state_t state, ret1, ret2, sg_ret;

reg  [4:0] mw_addr;
reg [15:0] mw_data;
reg  [4:0] mr_addr;
reg [15:0] mr_data;
reg  [2:0] wcnt;
reg        hc_fail;
reg        hc_use_to;
reg [26:0] hc_to;
reg        no_host;       // the host did not answer the first command
reg        mounted;
reg        mount_pending, mounting;
reg  [2:0] ri;            // task file word
reg [12:0] xi, xn;        // buffer word counters
reg [15:0] sd_hi, rv_lo;
reg [31:0] glba, plba, pl_t;
reg [31:0] lb_lba;
reg  [5:0] lb_cnt;
reg  [5:0] fk_s;
reg        fk_blk;
reg  [5:0] fk_i;
reg [31:0] fk_sum;
reg [24:0] idle_cnt;
reg        fl_d;

// mounting
reg        md;            // drive being mounted
reg  [4:0] nsec;          // sectors of the image's start in the buffer
reg        flg;           // something other than zeros in them
reg [31:0] g_spt, g_heads;
reg [12:0] g_off;
reg  [1:0] cg_s;
reg  [4:0] cg_h;
reg        sgd;           // drive of ide_set_geometry

assign mount_busy = mount_pending | mounting;
assign dbg_state  = {17'd0, no_host, mounted, drv_dirty, xnull, pstate, 1'b0, state};

wire [31:0] lb_file  = lb_lba - {19'd0, d_offset};     // sector in the image file
wire [31:0] wr_file  = xfer_lba - {19'd0, d_offset};
wire [15:0] file_id  = FILE_ID0 + {15'd0, r_drv};

// calc_geometry(): sectors per track tried in turn
function automatic [8:0] sptt(input [1:0] s);
	sptt = (s == 2'd0) ? 9'd63 : (s == 2'd1) ? 9'd127 : 9'd255;
endfunction
wire [31:0] cg_total = drv_total[md];
wire        cg_ok    = (cg_total <= 32'd1048576) ? (dv_q <= 32'd1023)
                       : (dv_q < 32'd16383 || (dv_q < 32'd32767 && cg_h >= 5'd5) || dv_q <= 32'd65536);

// guess_geometry() without an RDB: sectors * heads = 32 .. 2048 per
// cylinder, the first that gives fewer than 65536 cylinders
reg  [8:0] v_spt;
reg  [7:0] v_heads;
always @* begin
	v_spt = 9'd128; v_heads = 8'd16;
	if      ((cg_total >>  5) < 32'd65535) begin v_spt = 9'd32;  v_heads = 8'd1;  end
	else if ((cg_total >>  6) < 32'd65535) begin v_spt = 9'd64;  v_heads = 8'd1;  end
	else if ((cg_total >>  7) < 32'd65535) begin v_spt = 9'd128; v_heads = 8'd1;  end
	else if ((cg_total >>  8) < 32'd65535) begin v_spt = 9'd128; v_heads = 8'd2;  end
	else if ((cg_total >>  9) < 32'd65535) begin v_spt = 9'd128; v_heads = 8'd4;  end
	else if ((cg_total >> 10) < 32'd65535) begin v_spt = 9'd128; v_heads = 8'd8;  end
end

always @(posedge clk) begin
	eb_we <= 1'b0;

	if (reset) begin
		state         <= S_POLL;
		ide_address   <= 5'd0;
		ide_write     <= 1'b0;
		ide_read      <= 1'b0;
		ide_writedata <= 16'd0;
		hc_request    <= 1'b0;
		hc_use_to     <= 1'b0;
		no_host       <= 1'b0;
		mounted       <= 1'b0;
		mount_pending <= 1'b0;
		mounting      <= 1'b0;
		drv_present   <= 2'b00;
		drv_dirty     <= 2'b00;
		pstate        <= P_RESET;
		xnull          <= 1'b0;
		idle_cnt      <= 25'd0;
		r_drv         <= 1'b0;
		dbg_sectors_read    <= 32'd0;
		dbg_sectors_written <= 32'd0;
	end
	else begin
		if (start) begin
			mount_pending <= 1'b1;
			mounting      <= 1'b1;
		end

		case (state)
		// ================================================== ide_io()
		S_POLL: begin
			idle_cnt <= 25'd0;
			if (mount_pending) begin
				mount_pending <= 1'b0;
				state <= S_MNT0;
			end
			else if (enable && mounted && ide_req == 3'd4) begin          // command
				pstate <= P_IDLE;
				ret2   <= S_CMD;
				state  <= S_GR0;
			end
			else if (enable && mounted && ide_req == 3'd5) begin          // data
				if (pstate == P_WAIT_RD) state <= S_RSB0;
				else if (pstate == P_WAIT_WR) state <= S_WCB0;
				else begin pstate <= P_IDLE; state <= S_ERR; end
			end
			else if (enable && mounted && ide_req == 3'd6) state <= S_RST0;   // reset
			else if (enable && mounted && ide_req == 3'd0 && pstate == P_RESET) begin
				pstate   <= P_IDLE;
				r_status <= ST_RDY;
				ret2     <= S_POLL;
				state    <= S_SR0;
			end
			else if (drv_dirty != 2'b00) begin
				// written data is flushed when nothing happened for a while
				if (idle_cnt == FLUSH_TIME) state <= S_FL0;
				else idle_cnt <= idle_cnt + 25'd1;
			end
		end

		// =========================================== management write
		S_MW0: begin
			ide_address   <= mw_addr;
			ide_writedata <= mw_data;
			ide_write     <= 1'b1;
			state         <= S_MW1;
		end
		S_MW1: begin ide_write <= 1'b0; state <= S_MW2; end
		S_MW2: state <= ret1;

		// ============================================ management read
		// ide.sv registers the word for the address; after a data word its
		// counter moves on with the falling edge of the read strobe
		S_MR0: begin
			ide_address <= mr_addr;
			wcnt        <= 3'd4;
			state       <= S_MR1;
		end
		S_MR1:
			if (wcnt != 3'd0) wcnt <= wcnt - 3'd1;
			else begin
				mr_data  <= ide_readdata;
				ide_read <= 1'b1;
				state    <= S_MR2;
			end
		S_MR2: begin ide_read <= 1'b0; state <= ret1; end

		// ================================================ host command
		S_HC0: begin
			hc_request <= 1'b1;
			hc_to      <= 27'd0;
			state      <= S_HC1;
		end
		S_HC1:
			if (hc_done || hc_error) begin
				hc_fail    <= hc_error;
				hc_request <= 1'b0;
				wcnt       <= 3'd7;
				state      <= S_HC2;
			end
			else if (hc_use_to && hc_to == HOST_TIME) begin
				hc_fail    <= 1'b1;
				no_host    <= 1'b1;
				hc_request <= 1'b0;
				wcnt       <= 3'd7;
				state      <= S_HC2;
			end
			else hc_to <= hc_to + 27'd1;
		// the framework clears done / error once the request is low
		S_HC2:
			if (wcnt != 3'd0) wcnt <= wcnt - 3'd1;
			else if (!hc_done && !hc_error) state <= ret1;

		// ===================================================== divider
		// dv_n / dv_d -> dv_q, remainder dv_r (set dv_r, dv_q to 0, dv_i to 31)
		S_DIV: begin
			if (dv_t >= {1'b0, dv_d}) begin
				dv_r <= dv_t - {1'b0, dv_d};
				dv_q <= {dv_q[30:0], 1'b1};
			end
			else begin
				dv_r <= dv_t;
				dv_q <= {dv_q[30:0], 1'b0};
			end
			dv_n <= {dv_n[30:0], 1'b0};
			dv_i <= dv_i - 6'd1;
			if (dv_i == 6'd0) state <= ret1;
		end

		// ================================================= zero buffer
		S_ZF0:
			if (xi >= xn) state <= ret1;
			else begin
				eb_addr  <= xi[11:0];
				eb_wdata <= 32'd0;
				eb_we    <= 1'b1;
				xi       <= xi + 13'd1;
			end

		// ============================================== ide_set_regs()
		S_SR0: begin ri <= 3'd0; state <= S_SR1; end
		S_SR1:
			if (ri == 3'd6) state <= ret2;
			else begin
				mw_addr <= {2'b00, ri};
				mw_data <= regs_word(ri);
				ri      <= ri + 3'd1;
				ret1    <= S_SR1;
				state   <= S_MW0;
			end

		// ============================================== ide_get_regs()
		S_GR0: begin ri <= 3'd0; state <= S_GR1; end
		S_GR1:
			if (ri == 3'd6) state <= ret2;
			else begin
				mr_addr <= {2'b00, ri};
				ret1    <= S_GR2;
				state   <= S_MR0;
			end
		S_GR2: begin
			case (ri)
				3'd0: begin r_io_fast <= mr_data[1]; r_features <= mr_data[15:8]; end
				3'd1: begin r_sector_count <= mr_data[7:0]; r_sector <= mr_data[15:8]; end
				3'd2: r_cylinder <= mr_data;
				3'd5: begin
					r_head   <= mr_data[3:0];
					r_drv    <= mr_data[4];
					r_lba    <= mr_data[6];
					r_cmd    <= mr_data[15:8];
					r_error  <= 8'd0;
					r_status <= 8'd0;
				end
				default: ;
			endcase
			ri    <= ri + 3'd1;
			state <= S_GR1;
		end

		// =========================== buffer words 0 .. xn-1 -> ide.sv
		S_SD0: begin xi <= 13'd0; state <= S_SD1; end
		S_SD1:
			if (xi == xn) state <= ret2;
			else begin eb_addr <= xi[11:0]; state <= S_SD2; end
		S_SD2: state <= S_SD3;
		S_SD3: begin
			mw_addr <= 5'd15;
			mw_data <= eb_rdata[15:0];
			sd_hi   <= eb_rdata[31:16];
			ret1    <= S_SD4;
			state   <= S_MW0;
		end
		S_SD4: begin
			mw_data <= sd_hi;
			xi      <= xi + 13'd1;
			ret1    <= S_SD1;
			state   <= S_MW0;
		end

		// =========================== ide.sv -> buffer words 0 .. xn-1
		S_RV0: begin xi <= 13'd0; state <= S_RV1; end
		S_RV1:
			if (xi == xn) state <= ret2;
			else begin
				mr_addr <= 5'd15;
				ret1    <= S_RV2;
				state   <= S_MR0;
			end
		S_RV2: begin
			rv_lo <= mr_data;
			ret1  <= S_RV3;
			state <= S_MR0;
		end
		S_RV3: begin
			eb_addr  <= xi[11:0];
			eb_wdata <= {mr_data, rv_lo};
			eb_we    <= 1'b1;
			xi       <= xi + 13'd1;
			state    <= S_RV1;
		end

		// ==================================================== get_lba()
		S_GL0:
			if (r_lba) begin
				glba  <= {4'd0, r_head, r_cylinder, r_sector};
				state <= ret2;
			end
			else begin
				mul_a <= {16'd0, r_cylinder};
				mul_b <= {9'd0, d_heads};
				state <= S_GL1;
			end
		S_GL1: state <= S_GL2;
		S_GL2: begin
			mul_a <= mul_p + {28'd0, r_head};
			mul_b <= {8'd0, d_spt};
			state <= S_GL3;
		end
		S_GL3: state <= S_GL4;
		S_GL4: begin
			glba  <= mul_p + {24'd0, r_sector} - 32'd1;
			state <= ret2;
		end

		// ================================================ put_lba(plba)
		S_PL0: begin pl_t <= plba - 32'd1; state <= S_PL1; end
		S_PL1:
			if (r_lba) begin
				r_sector   <= pl_t[7:0];
				r_cylinder <= pl_t[23:8];
				r_head     <= pl_t[27:24];
				state      <= ret2;
			end
			else begin
				mul_a <= {24'd0, d_heads};
				mul_b <= {8'd0, d_spt};
				state <= S_PL2;
			end
		S_PL2: state <= S_PL3;
		S_PL3: begin
			dv_n <= pl_t; dv_d <= mul_p[16:0]; dv_r <= 18'd0; dv_q <= 32'd0; dv_i <= 6'd31;
			ret1 <= S_PL4; state <= S_DIV;
		end
		S_PL4: begin
			r_cylinder <= dv_q[15:0];
			dv_n <= {14'd0, dv_r}; dv_d <= {8'd0, d_spt}; dv_r <= 18'd0; dv_q <= 32'd0; dv_i <= 6'd31;
			ret1 <= S_PL5; state <= S_DIV;
		end
		S_PL5: begin
			r_head   <= dv_q[3:0];
			r_sector <= dv_r[7:0] + 8'd1;
			state    <= ret2;
		end

		// ====================== readhdd(): lb_cnt sectors from lb_lba
		S_LB0:
			if (xnull) begin
				xi <= 13'd0; xn <= {lb_cnt, 7'd0};
				ret1 <= ret2; state <= S_ZF0;
			end
			else if (lb_lba < {19'd0, d_offset}) begin
				// the virtual RDB in front of the image
				xi <= 13'd0; xn <= {lb_cnt, 7'd0};
				ret1 <= S_FK0; state <= S_ZF0;
			end
			else begin
				hc_cmd <= CMD_FILE_READ;
				hc_p1  <= {16'd0, file_id};
				hc_p2  <= BUF_ADDR;
				hc_p3  <= {lb_file[22:0], 9'd0};
				hc_p4  <= {23'd0, lb_file[31:23]};
				hc_p5  <= {17'd0, lb_cnt, 9'd0};
				ret1   <= S_LB1;
				state  <= S_HC0;
			end
		S_LB1: begin
			// what the file did not have reads as zeros
			if (hc_fail || hc_res0 != 32'd0) begin
				xnull <= 1'b1;
				xi   <= 13'd0;
			end
			else if (hc_res1 >= {17'd0, lb_cnt, 9'd0}) xi <= {lb_cnt, 7'd0};
			else xi <= hc_res1[14:2] + {12'd0, |hc_res1[1:0]};
			xn   <= {lb_cnt, 7'd0};
			dbg_sectors_read <= dbg_sectors_read + {26'd0, lb_cnt};
			ret1 <= ret2; state <= S_ZF0;
		end

		// fill_fake_rdb(): sector 0 RDSK, sector 1 PART, zeros after them
		S_FK0: begin fk_s <= 6'd0; state <= S_FK1; end
		S_FK1:
			if (fk_s == lb_cnt || (lb_lba + {26'd0, fk_s}) > 32'd1) state <= ret2;
			else begin
				fk_blk <= lb_lba[0] ^ fk_s[0];
				fk_i   <= 6'd0;
				fk_sum <= 32'd0;
				state  <= S_FK2;
			end
		S_FK2: begin
			eb_addr  <= {fk_s[4:0], 7'd0} + {6'd0, fk_i};
			eb_wdata <= bswap(rdb_long(fk_blk, fk_i));
			eb_we    <= 1'b1;
			fk_sum   <= fk_sum + rdb_long(fk_blk, fk_i);
			if (fk_i == 6'd63) state <= S_FK3;
			else fk_i <= fk_i + 6'd1;
		end
		S_FK3: begin
			eb_addr  <= {fk_s[4:0], 7'd2};
			eb_wdata <= bswap(32'd0 - fk_sum);
			eb_we    <= 1'b1;
			fk_s     <= fk_s + 6'd1;
			state    <= S_FK1;
		end

		// ================================================= handle_hdd()
		S_CMD:
			if (!drv_present[r_drv]) state <= S_ERR;
			else casez (r_cmd)
				8'hEC: state <= S_ID0;                                    // identify
				8'hC4: begin xfer_multi <= 1'b1; state <= S_READ0; end    // read multiple
				8'h20, 8'h21: begin xfer_multi <= 1'b0; state <= S_READ0; end
				8'hC5: begin xfer_multi <= 1'b1; state <= S_WRITE0; end   // write multiple
				8'h30, 8'h31: begin xfer_multi <= 1'b0; state <= S_WRITE0; end
				8'hC6:                                                    // set multiple
					if (r_sector_count > 8'd32) state <= S_ERR;
					else begin
						if (r_sector_count != 8'd0) drv_spb[r_drv] <= r_sector_count[5:0];
						r_status <= ST_RDY | ST_IRQ;
						ret2 <= S_POLL; state <= S_SR0;
					end
				8'h1?: begin                                              // recalibrate
					r_status   <= ST_RDY | ST_IRQ;
					r_cylinder <= 16'd0;
					ret2 <= S_POLL; state <= S_SR0;
				end
				8'h40, 8'h70, 8'hE3: begin                                // verify, seek, standby
					r_error  <= 8'd0;
					r_status <= ST_RDY | ST_DSC | ST_IRQ;
					ret2 <= S_POLL; state <= S_SR0;
				end
				8'h90: begin                                              // device diagnostic
					r_error  <= 8'h01;
					r_status <= ST_RDY | ST_DSC | ST_IRQ;
					ret2 <= S_POLL; state <= S_SR0;
				end
				8'h91: begin                                              // initialize device parameters
					drv_heads[r_drv] <= {4'd0, r_head} + 8'd1;
					drv_spt[r_drv]   <= (r_sector_count == 8'd0) ? 9'd256 : {1'b0, r_sector_count};
					sgd    <= r_drv;
					sg_ret <= S_C91;
					state  <= S_SG0;
				end
				default: state <= S_ERR;
			endcase
		S_C91: begin
			r_status <= ST_RDY | ST_IRQ;
			ret2 <= S_POLL; state <= S_SR0;
		end
		S_ERR: begin
			r_status <= ST_RDY | ST_ERR | ST_IRQ;
			r_error  <= ERR_ABRT;
			ret2 <= S_POLL; state <= S_SR0;
		end

		// ide_set_geometry() of drive sgd: cylinders from the image size
		S_SG0: begin
			mul_a <= {24'd0, drv_heads[sgd]};
			mul_b <= {8'd0, drv_spt[sgd]};
			state <= S_SG1;
		end
		S_SG1: state <= S_SG2;
		S_SG2: begin
			dv_n <= drv_total[sgd]; dv_d <= mul_p[16:0]; dv_r <= 18'd0; dv_q <= 32'd0; dv_i <= 6'd31;
			ret1 <= S_SG3; state <= S_DIV;
		end
		S_SG3: begin
			if (drv_offset[sgd] != 13'd0) begin
				drv_cyl[sgd]    <= (dv_q >= 32'd65535) ? 16'd65535 : dv_q[15:0] + 16'd1;
				drv_offset[sgd] <= mul_p[12:0];
			end
			else drv_cyl[sgd] <= (dv_q > 32'd65535) ? 16'd65535 : dv_q[15:0];
			state <= sg_ret;
		end

		// identify: the task file is cleared but for the drive
		S_ID0: begin
			r_io_fast <= 1'b0; r_features <= 8'd0; r_sector_count <= 8'd0; r_sector <= 8'd0;
			r_cylinder <= 16'd0; r_head <= 4'd0; r_lba <= 1'b0; r_cmd <= 8'd0; r_error <= 8'd0;
			r_io_size <= 8'd1;
			r_status  <= ST_RDY | ST_DRQ | ST_IRQ | ST_END;
			xi        <= 13'd0;
			state     <= S_ID1;
		end
		S_ID1:
			if (xi == 13'd256) begin ret2 <= S_POLL; state <= S_SR0; end
			else begin
				mw_addr <= 5'd15;
				mw_data <= idword(xi[7:0]);
				xi      <= xi + 13'd1;
				ret1    <= S_ID1;
				state   <= S_MW0;
			end

		// process_read()
		S_READ0: begin ret2 <= S_READ1; state <= S_GL0; end
		S_READ1: begin
			xfer_lba <= glba;
			xfer_cnt <= next_cnt;
			xnull     <= 1'b0;
			state    <= S_READ2;
		end
		S_READ2: begin
			lb_lba <= xfer_lba; lb_cnt <= xfer_cnt;
			ret2 <= S_RSB0; state <= S_LB0;
		end
		// read_send_block(): the block in the buffer goes to the Amiga, the
		// next one is fetched meanwhile
		S_RSB0: begin
			xfer_lba       <= xfer_lba + {26'd0, xfer_cnt};
			r_sector_count <= r_sector_count - {2'd0, xfer_cnt};
			plba           <= xfer_lba + {26'd0, xfer_cnt};
			ret2 <= S_RSB1; state <= S_PL0;
		end
		S_RSB1: begin
			r_io_size <= {2'd0, xfer_cnt};
			r_status  <= ST_RDP | ST_RDY | ST_DRQ | ST_IRQ | ((r_sector_count == 8'd0) ? ST_END : 8'd0);
			ret2 <= S_RSB2; state <= S_SR0;
		end
		S_RSB2: begin
			xn   <= {xfer_cnt, 7'd0};
			ret2 <= S_RSB3; state <= S_SD0;
		end
		S_RSB3:
			if (r_sector_count == 8'd0) begin
				pstate <= P_IDLE;
				state  <= S_POLL;
			end
			else begin
				xfer_cnt <= next_cnt;
				state    <= S_RSB4;
			end
		S_RSB4: begin
			lb_lba <= xfer_lba; lb_cnt <= xfer_cnt;
			pstate <= P_WAIT_RD;
			ret2 <= S_POLL; state <= S_LB0;
		end

		// process_write()
		S_WRITE0: begin ret2 <= S_WRITE1; state <= S_GL0; end
		S_WRITE1: begin
			xfer_lba <= glba;
			xnull     <= 1'b0;
			xfer_irq <= 1'b0;
			state    <= S_WRB0;
		end
		// write_request_block()
		S_WRB0: begin xfer_cnt <= next_cnt; state <= S_WRB1; end
		S_WRB1: begin
			r_status  <= ST_RDY | ST_DRQ | (xfer_irq ? ST_IRQ : 8'd0);
			xfer_irq  <= 1'b1;
			r_io_size <= {2'd0, xfer_cnt};
			pstate    <= P_WAIT_WR;
			ret2 <= S_POLL; state <= S_SR0;
		end
		// write_recv_block()
		S_WCB0: begin
			xn   <= {xfer_cnt, 7'd0};
			ret2 <= S_WCB1; state <= S_RV0;
		end
		S_WCB1:
			if (!xnull && xfer_lba >= {19'd0, d_offset}) begin
				hc_cmd <= CMD_FILE_WRITE;
				hc_p1  <= {16'd0, file_id};
				hc_p2  <= BUF_ADDR;
				hc_p3  <= {wr_file[22:0], 9'd0};
				hc_p4  <= {23'd0, wr_file[31:23]};
				hc_p5  <= {17'd0, xfer_cnt, 9'd0};
				ret1   <= S_WCB2;
				state  <= S_HC0;
			end
			else state <= S_WCB3;
		S_WCB2: begin
			if (hc_fail || hc_res0 != 32'd0) xnull <= 1'b1;
			else begin
				drv_dirty[r_drv] <= 1'b1;
				dbg_sectors_written <= dbg_sectors_written + {26'd0, xfer_cnt};
			end
			state <= S_WCB3;
		end
		S_WCB3: begin
			xfer_lba       <= xfer_lba + {26'd0, xfer_cnt};
			r_sector_count <= r_sector_count - {2'd0, xfer_cnt};
			plba           <= xfer_lba + {26'd0, xfer_cnt};
			ret2 <= S_WCB4; state <= S_PL0;
		end
		S_WCB4:
			if (r_sector_count == 8'd0) begin
				pstate   <= P_IDLE;
				r_status <= ST_RDY | ST_IRQ;
				ret2 <= S_POLL; state <= S_SR0;
			end
			else state <= S_WRB0;

		// request 6: reset
		S_RST0: begin ret2 <= S_RST1; state <= S_GR0; end
		S_RST1: begin
			r_head         <= 4'd0;
			r_error        <= 8'd0;
			r_sector       <= 8'd1;
			r_sector_count <= 8'd1;
			r_cylinder     <= drv_present[r_drv] ? 16'h0000 : 16'hFFFF;
			r_status       <= ST_BSY;
			pstate         <= P_RESET;
			ret2 <= S_POLL; state <= S_SR0;
		end

		// flush a drive that was written to
		S_FL0: begin
			fl_d   <= ~drv_dirty[0];
			hc_cmd <= CMD_FILE_FLUSH;
			hc_p1  <= {16'd0, FILE_ID0 + {15'd0, ~drv_dirty[0]}};
			hc_p2  <= 32'd0; hc_p3 <= 32'd0; hc_p4 <= 32'd0; hc_p5 <= 32'd0;
			ret1   <= S_FL1;
			state  <= S_HC0;
		end
		S_FL1: begin
			drv_dirty[fl_d] <= 1'b0;
			state <= S_POLL;
		end

		// ================================= ide_open() for both drives
		S_MNT0: begin
			md      <= 1'b0;
			mounted <= 1'b0;
			state   <= S_MNT1;
		end
		S_MNT1: begin
			drv_present[md] <= 1'b0;
			drv_offset[md]  <= 13'd0;
			drv_spb[md]     <= 6'd16;
			r_drv           <= md;            // file_id and the d_* values follow the drive
			if (no_host) state <= S_MNTN;
			else begin
				hc_cmd    <= CMD_FILE_GET_SIZE;
				hc_p1     <= {16'd0, FILE_ID0 + {15'd0, md}};
				hc_p2     <= 32'd0; hc_p3 <= 32'd0; hc_p4 <= 32'd0; hc_p5 <= 32'd0;
				hc_use_to <= ~md;             // only the first command can show that there is no host
				ret1      <= S_MNT2;
				state     <= S_HC0;
			end
		end
		S_MNT2: begin
			hc_use_to <= 1'b0;
			// sectors of the file
			drv_total[md] <= (hc_res2[31:9] != 23'd0) ? 32'hFFFFFFFF : {hc_res2[8:0], hc_res1[31:9]};
			if (hc_fail || hc_res0 != 32'd0 || (hc_res2 == 32'd0 && hc_res1[31:9] == 23'd0)) state <= S_MNTN;
			else state <= S_MNT3;
		end
		// guess_geometry(): the first 16 sectors
		S_MNT3: begin
			hc_cmd <= CMD_FILE_READ;
			hc_p1  <= {16'd0, file_id};
			hc_p2  <= BUF_ADDR;
			hc_p3  <= 32'd0;
			hc_p4  <= 32'd0;
			hc_p5  <= 32'd8192;
			ret1   <= S_MNT4;
			state  <= S_HC0;
		end
		S_MNT4: begin
			nsec  <= (hc_fail || hc_res0 != 32'd0) ? 5'd0 : (hc_res1 >= 32'd8192) ? 5'd16 : {1'b0, hc_res1[12:9]};
			xi    <= 13'd0;
			flg   <= 1'b0;
			state <= S_MNT5;
		end
		S_MNT5:
			if (xi == {1'b0, nsec, 7'd0}) state <= S_MNT8;
			else begin eb_addr <= xi[11:0]; state <= S_MNT6; end
		S_MNT6: state <= S_MNT7;
		S_MNT7:
			if (xi[6:0] == 7'd0 && eb_rdata == 32'h4B534452) state <= S_MR_0;   // "RDSK"
			else begin
				if (eb_rdata != 32'd0) flg <= 1'b1;
				xi    <= xi + 13'd1;
				state <= S_MNT5;
			end
		// get_rdb_geometry(): rdb_Sectors and rdb_Heads
		S_MR_0: begin eb_addr <= xi[11:0] + 12'd17; state <= S_MR_1; end
		S_MR_1: begin eb_addr <= xi[11:0] + 12'd18; state <= S_MR_2; end
		S_MR_2: begin g_spt <= bswap(eb_rdata); state <= S_MR_3; end
		S_MR_3: begin g_heads <= bswap(eb_rdata); g_off <= 13'd0; state <= S_MR_4; end
		S_MR_4:
			if (g_spt > 32'd255 || g_heads > 32'd16) begin
				if (!g_spt[0] && g_spt < 32'd512 && g_heads <= 32'd8) begin
					g_spt   <= {1'b0, g_spt[31:1]};
					g_heads <= {g_heads[30:0], 1'b0};
					state   <= S_MG0;
				end
				else state <= S_CG0;
			end
			else state <= S_MG0;
		S_MR_5: state <= S_MG0;
		// no RDB: a partition image (virtual RDB) or an empty disk
		S_MNT8:
			if (flg) begin
				g_spt   <= {23'd0, v_spt};
				g_heads <= {24'd0, v_heads};
				g_off   <= v_spt * v_heads;
				state   <= S_MG0;
			end
			else begin
				g_off <= 13'd0;
				state <= S_CG0;
			end
		// calc_geometry()
		S_CG0: begin cg_s <= 2'd0; cg_h <= 5'd4; state <= S_CG1; end
		S_CG1: begin
			mul_a <= {27'd0, cg_h};
			mul_b <= {8'd0, sptt(cg_s)};
			state <= S_CG2;
		end
		S_CG2: state <= S_CG3;
		S_CG3: begin
			dv_n <= cg_total; dv_d <= mul_p[16:0]; dv_r <= 18'd0; dv_q <= 32'd0; dv_i <= 6'd31;
			ret1 <= S_CG4; state <= S_DIV;
		end
		S_CG4:
			if (cg_ok) begin
				g_spt   <= {23'd0, sptt(cg_s)};
				g_heads <= {27'd0, cg_h};
				state   <= S_MG0;
			end
			else if (cg_h == 5'd16) begin
				if (cg_s == 2'd2) begin
					g_spt   <= 32'd255;
					g_heads <= 32'd17;
					state   <= S_MG0;
				end
				else begin cg_s <= cg_s + 2'd1; cg_h <= 5'd4; state <= S_CG1; end
			end
			else begin cg_h <= cg_h + 5'd1; state <= S_CG1; end
		// ide_img_set()
		S_MG0: begin
			drv_heads[md] <= (g_heads[7:0] == 8'd0) ? 8'd16 : g_heads[7:0];
			drv_spt[md]   <= (g_spt[8:0] == 9'd0) ? 9'd256 : g_spt[8:0];
			sgd    <= md;
			sg_ret <= S_MG1;
			state  <= S_SG0;
		end
		S_MG1: begin
			if (g_off != 13'd0 && drv_cyl[md] != 16'd65535) drv_cyl[md] <= drv_cyl[md] + 16'd1;
			drv_offset[md]  <= g_off;
			drv_present[md] <= 1'b1;
			state <= S_MP0;
		end
		S_MNTN: begin
			drv_present[md] <= 1'b0;
			state <= S_MP0;
		end
		// ide.sv: drive present or not, no wait states
		S_MP0: begin
			mw_addr <= 5'd6;
			mw_data <= md ? {8'd0, 3'b100, drv_present[1], 4'd0} : {12'd0, 3'b100, drv_present[0]};
			ret1    <= S_MP1;
			state   <= S_MW0;
		end
		S_MP1:
			if (!md) begin md <= 1'b1; state <= S_MNT1; end
			else begin
				mw_addr <= 5'd6;
				mw_data <= 16'h0200;
				ret1    <= S_MNTE;
				state   <= S_MW0;
			end
		S_MNTE: begin
			pstate   <= P_RESET;
			xnull     <= 1'b0;
			mounted  <= 1'b1;
			mounting <= mount_pending;   // asked again meanwhile
			state    <= S_POLL;
		end

		default: state <= S_POLL;
		endcase
	end
end

endmodule
