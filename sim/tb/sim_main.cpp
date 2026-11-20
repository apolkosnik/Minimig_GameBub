// Full-system simulation bench of the Game Bub Minimig core (Verilator).
//
// It plays the parts of the Game Bub around the FPGA core:
//
//  * clocks: clk_114 and clk_28 as the MMCM puts them out (clk_28 rises with
//    every fourth clk_114 rising edge);
//  * the MCU firmware: the load sequence of the release firmware
//    (core/mod.rs, 1.1.0-beta3): GetStatus until Setup, FileWriteStart / the
//    file / FileWriteEnd for each file in files.json order, the settings,
//    SetupComplete, GetStatus until CoreHalt, CoreRun, NotifyFocus(1); and on
//    exit CoreHalt, then FileReadStart / read back / FileReadEnd for each
//    file that is not read only;
//  * the firmware's worker loop serving core requests (core/command.rs,
//    core/files_on_demand.rs of 1.1.0-beta4): the six command words read at
//    0xF000_1000, busy, FileGetSize / FileRead / FileWrite / FileFlush on the
//    on-demand files with the data moved through the memory interface in
//    pieces of 16 KB, the three result words written back, done (and error);
//  * the framework between them: the HostV0 memory interface exactly as
//    SpiReceiverFifo drives it (enable stays high from one queued request to
//    the next, also in the clock done is seen; the address moves on in the
//    clock after done), and the framebuffer writer of HandheldTop (pixels on
//    dataEnable, a line ends on the rising edge of hblank, the frame on the
//    rising edge of vblank).
//
// Host file words carry byte 0 of the file in bits 7:0, as the MCU sends
// them.
//
// Usage: Vtb_top [options]
//   --kick FILE          Kickstart ROM (files.json id 4)
//   --disk N FILE        disk image for slot N (ids 0..3)
//   --cart FILE          cartridge image (files.json id 7): HRTmon or the
//                        Action Replay (AR5, DeMoN v2)
//   --set ADDR=VALUE     a setting write (hex), after the defaults
//   --ms N               run N ms of Amiga time after CoreRun (default 3000)
//   --frames-dir DIR     write every captured frame as DIR/frame_NNNN.ppm
//   --shot-every N       only every Nth frame (default 1)
//   --press MS:BUTTONS:LEN  press buttons (hex mask, tb_top order) at MS for LEN ms
//   --mouse MS:DX:DY     a host mouse report at MS
//   --swap MS:DF0SLOT    change the DF0 setting at MS
//   --hdf N FILE         hard disk image for drive N (0 master, 1 slave;
//                        files.json ids 5, 6, on demand)
//   --focus MS:V         NotifyFocus(V) at MS: 0 as the menu opens (the CPU is
//                        halted), 1 as it closes
//   --hwrite MS:ADDR:VALUE  a host register write (hex) at MS, for example
//                        1040:1, the menu's Reset action
//   --check-halt MS:V    at MS the CPU must be halted (1) or not (0)
//   --check-pc MS1:MS2:LO:HI:MIN:MAX  from MS1 to MS2 the CPU must be at
//                        LO..HI-1 (hex) for MIN to MAX percent of the time
//                        (a cartridge's monitor entered, and left again)
//   --expect-resets N    fail unless the CPU was reset N times after its
//                        first start
//   --fw-latency-us N    time the firmware takes to notice a core request
//   --ide-test           check what sim/asm/idetest.rom read and wrote
//   --expect-hdd-read N  at least N hard disk sectors read
//   --save-hdf DIR       write the hard disk images as left at the end
//   --exit               do the firmware's exit sequence at the end and
//                        compare the saved images with the SDRAM contents
//   --save-dir DIR       write the saved images there (with --exit)
//   --expect-sectors N   fail unless at least N floppy sectors were read
//   --expect-written N   fail unless at least N floppy sectors were written
//   --expect-boot-frame  fail unless a non-blank frame was seen
//   --random-ram SEED    fill both SDRAM chips with noise first, as at power-on
//   --pc-prof MS         sample the CPU's PC every clk_sys period: with every
//                        status line the interrupt state and the 256-byte
//                        blocks it was in most; at the end the addresses it
//                        was at most from MS on
//   --watch ADDR         a chip RAM word (hex address) shown with every status
//                        line
//   --save-ram MS:PREFIX at MS write both SDRAM chips to PREFIX_chip0.bin (chip
//                        RAM from 0, the ROM, the Zorro II RAM) and
//                        PREFIX_chip1.bin (the Zorro III board from 0)
//   --trace-cpu FILE     log every CPU bus write
//
// The exit status is 0 when every check passed.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <map>
#include <string>
#include <vector>
#include <fstream>
#include <memory>

#include "Vtb_top.h"
#include "Vtb_top__Dpi.h"
#include "svdpi.h"
#include "verilated.h"

static std::unique_ptr<Vtb_top> top;
static uint64_t cyc28 = 0;          // clk_28 cycles since start
// --pc-prof: the CPU's PC sampled every clk_sys period
static bool pc_prof = false;
struct PcCheck { double ms1, ms2; uint32_t lo, hi; int minp, maxp; uint64_t c1, c2, in, n; bool done; };
static std::vector<PcCheck> pc_checks;   // --check-pc
static uint64_t pc_from = ~0ull;                 // clk_28 cycle the full profile starts at
static std::map<uint32_t, uint32_t> pc_iv;      // PC >> 8, since the last status line
static std::map<uint32_t, uint64_t> pc_all;     // PC, from pc_from
static int failures = 0;

#define FAIL(...) do { std::fprintf(stderr, "FAIL: " __VA_ARGS__); std::fprintf(stderr, "\n"); failures++; } while (0)
static void rtg_sample();   // RTG picture check, at every rising clk_av edge

// -------------------------------------------------------------- video
static const int VW = 720, VH = 256;   // the frame buffer
static std::vector<uint32_t> fb(VW * VH);        // the last whole frame, as colours
static std::vector<uint16_t> fbi(VW * VH);       // the frame being written: palette indices
static std::vector<uint32_t> fbt(VW * VH);       // the colours the chipset produced for them
static uint64_t pixels_wrong = 0, pixels_fixed_far = 0, pixels_checked = 0;
// The framework's palette (patches/framework): written by the core, looked
// up when a frame buffer is shown. The two frame buffers the framework
// keeps are checked against it: an entry must not change while a frame
// that uses it can still be on screen.
static uint32_t palette[512];
static std::vector<uint16_t> shown_i[2] = { std::vector<uint16_t>(VW * VH), std::vector<uint16_t>(VW * VH) };
static bool shown_pal[2] = { false, false };   // the frame was palette indices
// a frame buffer value as the framework shows it: a palette index, or with
// the palette off a 3 + 3 + 3 bit colour, the bits repeated to 8
static uint32_t direct_color(uint32_t v) {
	uint32_t r = (v >> 6) & 7, g = (v >> 3) & 7, b = v & 7;
	return ((r << 5 | r << 2 | r >> 1) << 16) | ((g << 5 | g << 2 | g >> 1) << 8) | (b << 5 | b << 2 | b >> 1);
}
static std::vector<uint32_t> shown_c[2] = { std::vector<uint32_t>(VW * VH), std::vector<uint32_t>(VW * VH) };
static int shown_n = 0;
static uint64_t palette_writes = 0, palette_stale = 0;
// sim/asm/coltest.s: its F (chip RAM $100) and the pixels in fixed colours
// of every frame
static std::vector<std::pair<uint32_t, uint32_t>> frame_fixed;
static uint32_t sdram_peek16_fwd(uint32_t waddr);
// sim/asm/coltest.s: line L's colour is (L * 17 + O(F)) & 0xFFF
static uint32_t coltest_offset(uint32_t f) { return f <= 12 ? f * 1088 : 12 * 1088 + (f - 12) * 2731; }
static uint32_t palette_color(uint32_t index) {
	if (index >= 384) {   // the fixed colours: 2 + 3 + 2 bits, each repeated to 8
		uint32_t r = (index >> 5) & 3, g = (index >> 2) & 7, b = index & 3;
		return ((r * 0x55) << 16) | ((g << 5 | g << 2 | g >> 1) << 8) | (b * 0x55);
	}
	return palette[index];
}
static int fb_x = 0, fb_y = 0;
static bool prev_hblank = true, prev_vblank = true;
static int frames = 0;
static uint64_t hs_edges = 0, vs_edges = 0;   // falling edges of _hsync / _vsync
static uint64_t vs_total = 0;                  // and of _vsync since the start
// --check-lace (sim/asm/lacetest.s): every frame the core completes must be
// a long field (COLOR00 blue), one every two fields
static bool check_lace = false;
static int lace_frames = 0, lace_short = 0, lace_on = 0;
static uint64_t lace_vs_first = 0, lace_vs_last = 0;
static int nonblank_frames = 0;
static std::string frames_dir;
static int shot_every = 1;
static uint32_t last_frame_hash = 0;
static int frames_changed = 0;

static void save_frame(const std::string &path) {
	FILE *f = std::fopen(path.c_str(), "wb");
	if (!f) return;
	// as the framework shows it on 480 rows (patches/framework): the first
	// 240 lines twice each, or with fit all 256 lines, line = row * 8 / 15
	const int rows = 480;
	bool fit = top->video_fit;
	std::fprintf(f, "P6\n%d %d\n255\n", VW, rows);
	for (int y = 0; y < rows; y++) for (int x = 0; x < VW; x++) {
		uint32_t p = fb[(fit ? y * VH / rows : y / 2) * VW + x];
		uint8_t px[3] = { uint8_t(p >> 16), uint8_t(p >> 8), uint8_t(p) };
		std::fwrite(px, 1, 3, f);
	}
	std::fclose(f);
}

// called with the values the core presents before a clk_28 rising edge
static void video_sample() {
	bool de = top->video_de, hb = top->video_hblank, vb = top->video_vblank;
	bool vb_edge = vb && !prev_vblank;
	bool hb_edge = hb && !prev_hblank;

	if (top->video_pal_we) {
		palette[top->video_pal_index & 511] = top->video_pal_color;
		palette_writes++;
		{
			static std::map<uint32_t, int> written;
			int &n = written[top->video_pal_color];
			n++;
			if (std::getenv("PALLOG")) std::fprintf(stderr, "palwrite frame %d line %d x %d: entry %u = %06X\n", frames, fb_y, fb_x, top->video_pal_index, top->video_pal_color);
			if (n == 2 && std::getenv("PALDEBUG")) std::fprintf(stderr, "palette: colour %06X given a second entry (frame %d, line %d, x %d)\n", top->video_pal_color, frames, fb_y, fb_x);
		}
	}
	if (de && fb_x < VW && fb_y < VH) {
		// the pixel is a palette index: r, g, b are its top, middle and low bits
		uint32_t r = top->video_r, g = top->video_g, b = top->video_b;
		fbi[fb_y * VW + fb_x] = uint16_t((r << 6) | (g << 3) | b);
		fbt[fb_y * VW + fb_x] = top->dbg_pixel_color;
	}
	if (vb_edge) {
		// a frame completed: its colours as the framework would show it now
		const bool pal_on = top->video_pal_on;
		for (int i = 0; i < VW * VH; i++) fb[i] = pal_on ? palette_color(fbi[i]) : direct_color(fbi[i]);
		// palette mode: every pixel shown must be the colour the chipset
		// produced, from a palette entry exactly, or in the fixed colours
		// the nearest of them (the dither moves a component one level)
		if (pal_on && frames >= 2) {
			const int lines = top->video_fit ? VH : 240;
			for (int i = 0; i < VW * lines; i++) {
				uint32_t t = fbt[i], p = fb[i];
				pixels_checked++;
				if (fbi[i] < 384) {
					if (p != t && pixels_wrong++ < 5)
						std::fprintf(stderr, "pixel (%d,%d) frame %d: index %u shows %06X, the chipset's colour %06X\n", i % VW, i / VW, frames, fbi[i], p, t);
				} else {
					int dr = std::abs(int(p >> 16) - int(t >> 16)), dg = std::abs(int((p >> 8) & 255) - int((t >> 8) & 255)), db = std::abs(int(p & 255) - int(t & 255));
					if ((dr > 85 || dg > 37 || db > 85) && pixels_fixed_far++ < 5)
						std::fprintf(stderr, "pixel (%d,%d) frame %d: fixed colour %06X for the chipset's %06X\n", i % VW, i / VW, frames, p, t);
				}
			}
		}
		{
			uint32_t fixed = 0;
			const int lines = top->video_fit ? VH : 240;
			if (pal_on) for (int i = 0; i < VW * lines; i++) if (fbi[i] >= 384) fixed++;
			frame_fixed.push_back({sdram_peek16_fwd(0x100 >> 1), fixed});
		}
		// the two frames before it may still be on screen: their indices
		// must still give the colours they had
		// (the lines the framework shows: all 256 with fit, else the first 240)
		const int shown_lines = top->video_fit ? VH : 240;
		for (int k = 0; k < 2 && k < shown_n; k++) if (shown_pal[k] && pal_on)
			for (int i = 0; i < VW * shown_lines; i++)
				if (palette_color(shown_i[k][i]) != shown_c[k][i]) palette_stale++;
		shown_i[1].swap(shown_i[0]); shown_c[1].swap(shown_c[0]);
		shown_pal[1] = shown_pal[0];
		shown_i[0] = fbi; shown_c[0] = fb; shown_pal[0] = pal_on;
		if (std::getenv("FBTDUMP")) {
			std::map<uint32_t, int> n;
			for (int i = 0; i < VW * VH; i++) n[fbt[i]]++;
			std::fprintf(stderr, "frame %d: %zu chipset colours\n", frames, n.size());
			if (n.size() > 256 && n.size() < 2000) {
				// the pixels with colours seen fewer than 40 times, and their neighbours
				int shown = 0;
				for (int i = 1; i + 1 < VW * VH && shown < 8; i++) if (n[fbt[i]] < 40) {
					std::fprintf(stderr, "  (%d,%d): %06X %06X [%06X] %06X %06X\n", i % VW, i / VW, fbt[i-2 < 0 ? 0 : i-2], fbt[i-1], fbt[i], fbt[i+1], fbt[i+2 < VW*VH ? i+2 : i]);
					shown++;
				}
			}
		}
		if (shown_n < 2) shown_n++;
		// from the third frame completed with the chipset in interlace (the
		// test program has set COLOR00 by the field by then)
		if (check_lace && top->dbg_lace) lace_on++;
		if (check_lace && lace_on > 2) {
			// the border at the top left of the frame: blue in a long field,
			// red in a short one
			if (fb[0] != 0x0000FF && lace_short++ < 5)
				FAIL("lacetest: frame %d has border colour %06X, expected 0000FF (a long field)", frames, fb[0]);
			if (!lace_frames) lace_vs_first = vs_total;
			lace_vs_last = vs_total;
			lace_frames++;
		}
		uint32_t h = 2166136261u;
		bool blank = true;
		for (auto p : fb) { h = (h ^ p) * 16777619u; if (p != fb[0]) blank = false; }
		if (!blank) nonblank_frames++;
		if (h != last_frame_hash) frames_changed++;
		last_frame_hash = h;
		if (!frames_dir.empty() && frames % shot_every == 0) {
			char name[64];
			std::snprintf(name, sizeof name, "/frame_%04d.ppm", frames);
			save_frame(frames_dir + name);
		}
		frames++;
	}
	if (vb) { fb_x = 0; fb_y = 0; }
	else if (hb) { if (hb_edge) { fb_x = 0; fb_y++; } }
	else if (de) fb_x++;
	prev_hblank = hb;
	prev_vblank = vb;
}

// -------------------------------------------------------------- audio
static int64_t audio_abs_sum = 0;
static int64_t audio_abs_l = 0, audio_abs_r = 0;   // sums of |left| and |right|
static uint64_t audio_samples = 0;

// -------------------------------------------------------------- host side
struct Req { bool write; uint32_t addr; uint32_t data; uint32_t *rd; };
static std::deque<Req> hq;
static bool h_busy = false;

static std::FILE *cpu_trace = nullptr;
static uint64_t trace_from = 0;   // clk_28 cycle

// The SDRAM pins: gb_sdram_ctrl drives them all from clk_114 registers (put
// in the I/O blocks by rtl/gamebub/minimig.xdc) and forwards clk_114,
// inverted, as the SDRAM clock (an ODDR). Its commands, address, DQM and
// data must only change at the clk_114 edges at which the SDRAM clock
// falls, so that the SDRAM sees them stable half a clk_114 period before
// and after its rising edge. Checked after both clk_114 edges.
static uint64_t sd_edges = 0, sd_edge_errors = 0;
static bool sd_prev_clk = false;
static uint64_t sd_prev_bus = 0;
static void sdram_pin_check() {
	bool c = top->dbg_sd_clk;
	uint64_t bus = top->dbg_sd_bus;
	if (c && !sd_prev_clk) {
		sd_edges++;
		if (bus != sd_prev_bus && sd_edge_errors++ < 5)
			std::fprintf(stderr, "SDRAM outputs changed with the rising SDRAM clock at clk_28 cycle %llu: %010llX -> %010llX\n",
			             (unsigned long long)cyc28, (unsigned long long)sd_prev_bus, (unsigned long long)bus);
	}
	sd_prev_clk = c;
	sd_prev_bus = bus;
}
static bool prev_as = true;
static uint64_t chip_cycles = 0, chip_long_rd = 0, chip_long_wr = 0;
static uint64_t ram_long = 0;                     // long words the CPU took in one RAM transfer
static uint64_t line_reqs = 0;                    // AP68040: lines passed to the adapter as one request
static uint64_t line_clks = 0;                    // and the clk_sys periods they were outstanding
static uint64_t line_reqs_hi = 0, line_clks_hi = 0;   // those above the 24-bit space (Zorro III, RTG)
// AP68040, requests above the 24-bit space: clk_sys periods from the request
// to its acknowledge (of them waiting for the RAM port), and from an
// acknowledge to the next request (the bridge and the CPU)
static uint64_t hi_reqs = 0, hi_req_clks = 0, hi_wait_clks = 0, hi_gap_clks = 0, hi_gaps = 0;
static uint64_t sd_rd[2] = {0, 0}, sd_wr[2] = {0, 0}, sd_wr2[2] = {0, 0};   // CPU slots per SDRAM chip

// one clk_28 cycle: drive the inputs for the coming edge, then 4 clk_114 cycles
static void cycle28() {
	// framework (HandheldTop): the core command's busy / done / error
	// registers are cleared while the core's request is low
	if (!top->host_core_request) {
		top->host_core_busy = 0;
		top->host_core_done = 0;
		top->host_core_error = 0;
	}
	// framework: SpiReceiverFifo system side (combinational outputs of this
	// clock follow the queue head and regSysMemBusy)
	bool en = false;
	if (!hq.empty()) {
		en = true;
		top->host_mem_enable = 1;
		top->host_mem_write = hq.front().write;
		top->host_mem_address = hq.front().addr;
		top->host_mem_dataWrite = hq.front().data;
	} else {
		top->host_mem_enable = 0;
		top->host_mem_write = 0;
	}
	bool done_now = top->host_mem_done;
	uint32_t rdata = top->host_mem_dataRead;

	video_sample();
	{
		static bool phs = true, pvs = true;
		bool hs = top->dbg_hs_n, vs = top->dbg_vs_n;
		if (phs && !hs) hs_edges++;
		if (pvs && !vs) { vs_edges++; vs_total++; }
		phs = hs; pvs = vs;
	}
	audio_abs_sum += std::abs((int16_t)top->audio_left) + std::abs((int16_t)top->audio_right);
	audio_abs_l += std::abs((int16_t)top->audio_left);
	audio_abs_r += std::abs((int16_t)top->audio_right);
	audio_samples++;

	{
		// CPU cycles on the chip bus (cpu_wrapper's c_as falling) and the
		// 32-bit ones among them (chip_long, chip32_en: AGA, or ECS without
		// the 68020's 24-bit setting)
		static bool cas = true;
		bool as = top->dbg_chip_as;
		if (cas && !as) {
			chip_cycles++;
			if (top->dbg_chip_long) (top->dbg_chip_rw ? chip_long_rd : chip_long_wr)++;
		}
		cas = as;
	}
	if (cpu_trace && cyc28 >= trace_from) {
		// CPU writes on the chip bus to the custom chips and the CIAs
		// logged at the end of the bus cycle, with the data the CPU drove
		static uint32_t wa = 0, wd = 0;
		static bool wr = false;
		bool as = top->dbg_chip_as;
		if (!as) { wa = top->dbg_chip_addr << 1; wd = top->dbg_chip_dout; wr = !top->dbg_chip_rw; }
		if (!prev_as && as && wr && (wa >= 0xDFF000 || (wa >= 0xBF0000 && wa < 0xC00000)))
			std::fprintf(cpu_trace, "%.3f ms W %06X %04X ersy %d\n", cyc28 / 28375.0,
			             wa, wd, top->dbg_ersy);
		prev_as = as;
	}

	// clk_av (HDMI pixel clock): two periods every three clk_114 periods,
	// rising every third clk_114 half period
	static uint32_t av_half = 0;
	for (int p = 0; p < 4; p++) {
		top->clk_114 = 1;
		if (p == 0) top->clk_28 = 1;
		if (p == 2) top->clk_28 = 0;
		top->clk_57 = (p == 0 || p == 2);   // high for clk_114 periods 0 and 2 (CLKOUT5, /16)
		bool av_rise = (av_half % 3) == 0;
		top->clk_av = (av_half % 3) != 2;
		av_half++;
		top->eval();
		sdram_pin_check();
		if (av_rise) rtg_sample();
		if (top->dbg_sd_state == 8) {
			// both chips' slots of the window decided (chip 0 at 0, chip 1 at 4)
			if (top->dbg_sd_c0 == 2) sd_rd[0]++;
			if (top->dbg_sd_c0 == 3) { sd_wr[0]++; if (top->dbg_sd_c0_l2) sd_wr2[0]++; }
			if (top->dbg_sd_c1 == 2) sd_rd[1]++;
			if (top->dbg_sd_c1 == 3) { sd_wr[1]++; if (top->dbg_sd_c1_l2) sd_wr2[1]++; }
		}
		top->clk_114 = 0;
		av_rise = (av_half % 3) == 0;
		top->clk_av = (av_half % 3) != 2;
		av_half++;
		top->eval();
		sdram_pin_check();
		if (av_rise) rtg_sample();
	}
	cyc28++;
	if (pc_prof) {   // where the CPU is, once per clk_sys period
		pc_iv[top->dbg_pc >> 8]++;
		if (cyc28 >= pc_from) pc_all[top->dbg_pc & ~1u]++;
	}
	for (auto &c : pc_checks) if (cyc28 >= c.c1 && cyc28 < c.c2) {
		c.n++;
		if (top->dbg_pc >= c.lo && top->dbg_pc < c.hi) c.in++;
	}
	if (top->dbg_ram_long) ram_long++;   // sampled once per clk_sys period
	if (top->dbg_line) { line_reqs++; if (top->dbg_line_hi) line_reqs_hi++; }
	{
		static bool prev_hi = false, in_gap = false;
		static uint64_t gap = 0;
		bool hi = top->dbg_line_hi;   // the request's address (held from its start)
		if (top->dbg_req && hi) {
			hi_req_clks++;
			if (top->dbg_ram_wait) hi_wait_clks++;
			if (in_gap) { hi_gap_clks += gap; hi_gaps++; in_gap = false; }
		}
		if (top->dbg_ack && hi) { hi_reqs++; in_gap = true; gap = 0; }
		else if (in_gap && !top->dbg_req) { if (++gap > 64) in_gap = false; }   // not a run of transfers
		else if (in_gap && top->dbg_req && !hi) in_gap = false;
		prev_hi = hi;
	}
	if (top->dbg_line_busy) { line_clks++; if (top->dbg_line_hi) line_clks_hi++; }

	// register updates of the framework at that edge
	if (en) {
		if (h_busy) {
			if (done_now) {
				h_busy = false;
				if (!hq.front().write && hq.front().rd) *hq.front().rd = rdata;
				hq.pop_front();
			}
		} else h_busy = true;
	}
}

static void run_until_idle(uint64_t limit = 10000000) {
	uint64_t start = cyc28;
	while (!hq.empty()) {
		cycle28();
		if (cyc28 - start > limit) { FAIL("host access timed out"); std::fflush(stdout); std::_Exit(2); }
	}
}

static void hwrite(uint32_t a, uint32_t d) { hq.push_back({true, a, d, nullptr}); run_until_idle(); }
static uint32_t hread(uint32_t a) { uint32_t v = 0; hq.push_back({false, a, 0, &v}); run_until_idle(); return v; }

// a block of writes queued back to back, as one SPI transfer
static void hwrite_block(uint32_t a, const std::vector<uint32_t> &w) {
	for (size_t i = 0; i < w.size(); i++) {
		hq.push_back({true, a + uint32_t(4 * i), w[i], nullptr});
		if (hq.size() >= 64) { while (hq.size() > 16) cycle28(); }
	}
	run_until_idle();
}
static std::vector<uint32_t> hread_block(uint32_t a, size_t n) {
	std::vector<uint32_t> v(n);
	for (size_t i = 0; i < n; i++) {
		hq.push_back({false, a + uint32_t(4 * i), 0, &v[i]});
		if (hq.size() >= 64) { while (hq.size() > 16) cycle28(); }
	}
	run_until_idle();
	return v;
}

static void run_cycles(uint64_t n) { for (uint64_t i = 0; i < n; i++) cycle28(); }

// command channel: words at 0xF000_0000, request held until done or error
static bool command(std::vector<uint32_t> req, uint32_t *res = nullptr, uint64_t timeout = 50000000) {
	for (size_t i = 0; i < req.size(); i++) hwrite(0xF0000000u + 4 * uint32_t(i), req[i]);
	top->host_cmd_request = 1;
	uint64_t start = cyc28;
	while (!top->host_cmd_done && !top->host_cmd_error) {
		cycle28();
		if (cyc28 - start > timeout) {
			FAIL("command %04X timed out", req[0]);
			top->host_cmd_request = 0;
			run_cycles(4);
			return false;
		}
	}
	bool ok = !top->host_cmd_error;
	if (res) *res = hread(0xF0000000u);
	top->host_cmd_request = 0;
	run_cycles(4);
	if (top->host_cmd_done || top->host_cmd_error || top->host_cmd_busy) FAIL("command channel did not return to idle");
	return ok;
}

static uint32_t get_status() { uint32_t s = 0; command({0x0000}, &s); return s; }

// -------------------------------------------------------------- files
static std::vector<uint8_t> read_file(const std::string &path) {
	std::ifstream f(path, std::ios::binary);
	if (!f) { std::fprintf(stderr, "cannot open %s\n", path.c_str()); std::fflush(stdout); std::_Exit(2); }
	return std::vector<uint8_t>((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
}

static std::vector<uint32_t> to_words(const std::vector<uint8_t> &b) {
	std::vector<uint32_t> w((b.size() + 3) / 4, 0);
	for (size_t i = 0; i < b.size(); i++) w[i / 4] |= uint32_t(b[i]) << (8 * (i % 4));
	return w;
}

struct FileSpec { int id; uint32_t addr; std::string path; bool read_only; std::vector<uint8_t> data; };

// ------------------------------------------------- on-demand files
// The hard disk images (files.json ids 5 and 6). The firmware serves the
// core's requests from its worker loop.
struct OnDemand {
	bool selected = false;
	std::string path;
	std::vector<uint8_t> data, orig;
	unsigned reads = 0, writes = 0, flushes = 0, sizes = 0;
	uint64_t bytes_read = 0, bytes_written = 0;
};
static OnDemand hdf[2];
static uint64_t fw_latency = 14188;      // clk_28 cycles (500 us)
static uint64_t core_req_since = 0;
static unsigned core_bad_requests = 0;
static bool fw_verbose = false;

static void core_service() {
	if (!top->host_core_request) { core_req_since = 0; return; }
	if (top->host_core_done || top->host_core_error) return;   // answered, the core has not dropped it yet
	if (!core_req_since) { core_req_since = cyc28 ? cyc28 : 1; return; }
	if (cyc28 - core_req_since < fw_latency) return;
	core_req_since = 0;

	auto w = hread_block(0xF0001000u, 6);
	top->host_core_busy = 1;
	uint32_t res[3] = {0, 0, 0};
	bool ok = true;
	uint32_t cmd = w[0];
	int id = int(w[1] & 0xFFFF);
	OnDemand *f = (id == 5 || id == 6) && hdf[id - 5].selected ? &hdf[id - 5] : nullptr;
	const size_t SCRATCH = 16 * 1024;
	if (cmd < 0x0400 || cmd > 0x0404) {
		std::printf("fw: unknown core request %04X\n", cmd);
		core_bad_requests++;
		ok = false;
	}
	else if (!f) { res[0] = 1; ok = false; }               // invalid file
	else if (cmd == 0x0400) {                              // FileGetSize
		res[1] = uint32_t(f->data.size());
		res[2] = uint32_t(uint64_t(f->data.size()) >> 32);
		f->sizes++;
	}
	else if (cmd == 0x0401) {                              // FileSetSize
		f->data.resize((uint64_t(w[3]) << 32) | w[2]);
	}
	else if (cmd == 0x0402) {                              // FileRead
		uint32_t address = w[2];
		uint64_t offset = (uint64_t(w[4]) << 32) | w[3];
		size_t length = w[5], transferred = 0;
		while (transferred < length) {
			size_t chunk = std::min(length - transferred, SCRATCH);
			if (offset + transferred >= f->data.size()) break;           // end of the file
			size_t n = std::min<uint64_t>(chunk, f->data.size() - (offset + transferred));
			std::vector<uint8_t> b(f->data.begin() + offset + transferred, f->data.begin() + offset + transferred + n);
			hwrite_block(address + uint32_t(transferred), to_words(b));
			transferred += n;
		}
		res[1] = uint32_t(transferred);
		f->reads++;
		f->bytes_read += transferred;
		if (fw_verbose) std::printf("fw: FileRead id %d offset %llu length %zu -> %zu\n", id, (unsigned long long)offset, length, transferred);
	}
	else if (cmd == 0x0403) {                              // FileWrite
		uint32_t address = w[2];
		uint64_t offset = (uint64_t(w[4]) << 32) | w[3];
		size_t length = w[5], transferred = 0;
		while (transferred < length) {
			size_t chunk = std::min(length - transferred, SCRATCH);
			auto words = hread_block(address + uint32_t(transferred), (chunk + 3) / 4);
			if (f->data.size() < offset + transferred + chunk) f->data.resize(offset + transferred + chunk);
			for (size_t i = 0; i < chunk; i++) f->data[offset + transferred + i] = uint8_t(words[i / 4] >> (8 * (i % 4)));
			transferred += chunk;
		}
		res[1] = uint32_t(transferred);
		f->writes++;
		f->bytes_written += transferred;
		if (fw_verbose) std::printf("fw: FileWrite id %d offset %llu length %zu\n", id, (unsigned long long)offset, length);
	}
	else f->flushes++;                                     // FileFlush

	hwrite_block(0xF0001000u, {res[0], res[1], res[2]});
	top->host_core_busy = 0;
	top->host_core_done = 1;
	top->host_core_error = !ok;
}

// ------------------------------------------- hard disk geometry
// What Main_MiSTer makes of an image (ide.cpp: guess_geometry(),
// calc_geometry(), ide_set_geometry(), ide_img_set()), to check the core.
struct Geo { bool present = false; uint32_t cyl = 0, heads = 0, spt = 0, total = 0, offset = 0; };

static uint32_t be32(const uint8_t *p) { return uint32_t(p[0]) << 24 | uint32_t(p[1]) << 16 | uint32_t(p[2]) << 8 | p[3]; }
static void put32(std::vector<uint8_t> &b, size_t o, uint32_t v) { b[o] = uint8_t(v >> 24); b[o + 1] = uint8_t(v >> 16); b[o + 2] = uint8_t(v >> 8); b[o + 3] = uint8_t(v); }

static void calc_geometry(uint64_t size, uint32_t &heads, uint32_t &sectors) {
	uint32_t head = 0, cyl = 0, spt = 0;
	uint32_t sptt[] = { 63, 127, 255, 0 };
	uint32_t total = uint32_t(size / 512);
	for (int i = 0; sptt[i] != 0; i++) {
		spt = sptt[i];
		for (head = 4; head <= 16; head++) {
			cyl = total / (head * spt);
			if (total <= 1024 * 1024) { if (cyl <= 1023) break; }
			else {
				if (cyl < 16383) break;
				if (cyl < 32767 && head >= 5) break;
				if (cyl <= 65536) break;
			}
		}
		if (head <= 16) break;
	}
	heads = head; sectors = spt;
}

static Geo guess_geometry(const std::vector<uint8_t> &img) {
	Geo g;
	uint64_t size = img.size();
	if (size < 512) return g;
	uint32_t heads = 0, sectors = 0, offset = 0;
	uint8_t flg = 0;
	bool rdb = false;
	for (int i = 0; i < 16 && uint64_t(i + 1) * 512 <= size; i++) {
		const uint8_t *sec = &img[size_t(i) * 512];
		for (int j = 0; j < 512; j++) flg |= sec[j];
		if (!std::memcmp(sec, "RDSK", 4)) {
			sectors = be32(sec + 68);
			heads = be32(sec + 72);
			if (sectors > 255 || heads > 16) {
				if (!(sectors & 1) && sectors < 512 && heads <= 8) { sectors /= 2; heads *= 2; }
				else calc_geometry(size, heads, sectors);
			}
			rdb = true;
			break;
		}
	}
	if (!rdb) {
		if (flg) {
			heads = 16; sectors = 128;
			for (int i = 32; i <= 2048; i <<= 1) {
				uint64_t cylinders = size / (512 * i) + 1;
				if (cylinders < 65536) { sectors = (i < 128) ? i : 128; heads = i / sectors; break; }
			}
			offset = heads * sectors;
		}
		else calc_geometry(size, heads, sectors);
	}
	g.present = true;
	g.total = uint32_t(size / 512);
	g.heads = heads ? heads : 16;
	g.spt = sectors ? sectors : 256;
	uint64_t c = size / (uint64_t(g.heads) * g.spt * 512);
	if (c > 65535) c = 65535;
	if (offset && c < 65535) c++;
	g.cyl = uint32_t(c);
	g.offset = offset;
	return g;
}

// ide_set_geometry() of command 91
static void set_geometry(Geo &g, uint32_t sectors, uint32_t heads) {
	g.heads = heads ? heads : 16;
	g.spt = sectors ? sectors : 256;
	uint64_t c = uint64_t(g.total) / (g.heads * g.spt);
	if (g.offset) { c++; g.offset = g.heads * g.spt; }
	if (c > 65535) c = 65535;
	g.cyl = uint32_t(c);
}

// fill_fake_rdb(): block 0 (RDSK) or 1 (PART) of the virtual RDB
static std::vector<uint8_t> fake_rdb_block(const Geo &g, int drvnum, int block) {
	std::vector<uint8_t> b(512, 0);
	if (block == 0) {
		std::memcpy(&b[0], "RDSK", 4);
		put32(b, 4, 0x40); put32(b, 12, 7); put32(b, 16, 0x200); put32(b, 20, 0x12);
		put32(b, 24, 0xFFFFFFFF); put32(b, 28, 1); put32(b, 32, 0xFFFFFFFF); put32(b, 36, 0xFFFFFFFF);
		for (int i = 0; i < 6; i++) put32(b, 40 + 4 * i, 0xFFFFFFFF);
		put32(b, 64, g.cyl); put32(b, 68, g.spt); put32(b, 72, g.heads); put32(b, 76, 1);
		put32(b, 80, g.cyl);
		put32(b, 96, g.cyl); put32(b, 100, g.cyl); put32(b, 104, 3);
		put32(b, 128, 0); put32(b, 132, 1); put32(b, 136, 1); put32(b, 140, g.cyl - 1);
		put32(b, 144, g.heads * g.spt); put32(b, 148, 0); put32(b, 152, 1);
		std::memcpy(&b[160], "DON'T   REPARTITION!    0.00", 28);
	}
	else {
		std::memcpy(&b[0], "PART", 4);
		put32(b, 4, 0x40); put32(b, 12, 7); put32(b, 16, 0xFFFFFFFF); put32(b, 20, 1);
		b[36] = 3; b[37] = 'D'; b[38] = 'H'; b[39] = uint8_t('0' + drvnum);
		put32(b, 128, 0x10); put32(b, 132, 0x80); put32(b, 140, g.heads); put32(b, 144, 1);
		put32(b, 148, g.spt); put32(b, 152, 2); put32(b, 164, 1); put32(b, 168, g.cyl - 1);
		put32(b, 172, 30); put32(b, 180, 0xFFFFFF); put32(b, 184, 0x7FFFFFFE); put32(b, 192, 0x444F5301);
	}
	uint32_t sum = 0;
	for (int i = 0; i < 64; i++) sum += be32(&b[4 * i]);
	put32(b, 8, 0 - sum);
	return b;
}

// the sector a drive returns for an LBA
static std::vector<uint8_t> drive_sector(const Geo &g, const std::vector<uint8_t> &img, int drvnum, uint32_t lba) {
	if (lba < g.offset) return lba < 2 ? fake_rdb_block(g, drvnum, int(lba)) : std::vector<uint8_t>(512, 0);
	std::vector<uint8_t> b(512, 0);
	uint64_t o = uint64_t(lba - g.offset) * 512;
	for (int i = 0; i < 512; i++) if (o + i < img.size()) b[i] = img[o + i];
	return b;
}

static uint32_t chip16(uint32_t addr);

// ---------------------------------------------------------------------------
// RTG picture check (--rtg-check): the framework's HDMI side is in tb_top;
// every pixel of the 1280 x 720 picture is compared with the colour this
// model expects from the RTG registers, the palette the test ROM writes
// (rtgtest.s) and the board's memory in the chip 1 SDRAM model.
// ---------------------------------------------------------------------------
static bool rtg_check = false;
static int rtg_mode = 0;              // the mode being checked (ROM word $100)
static int rtg_skip = 0;              // whole frames still to skip
static bool rtg_in_frame = false;     // checking the current frame
static bool rtg_frame_done = false;   // a whole frame was checked
static uint64_t rtg_bad = 0, rtg_pixels = 0, rtg_bad_total = 0;
static int rtg_modes_done = 0;
static int rtg_last_acked = 0;        // modes are shown in increasing order
static uint32_t rtg_late_start = 0;
struct RtgFrame {
	uint32_t hs, vs, fmt, base, stride, bpp;
	bool ok, wide;
	uint32_t step, offx, offy, endx, endy;
	std::vector<uint8_t> mem;          // the board's memory from base
} rtg_f;
static uint32_t rtg_pal(uint32_t i) { return (i << 16) | (((i * 3) & 255) << 8) | (255 - i); }
static uint8_t rtg_byte(uint32_t off) {   // a byte of the board's memory (chip 1)
	uint32_t w = sdram_peek16(off >> 1);
	return (off & 1) ? (w >> 8) : (w & 255);
}
static void rtg_take_frame() {
	RtgFrame &f = rtg_f;
	f.hs = std::min<uint32_t>(top->rtg_hsize, 2048); f.vs = std::min<uint32_t>(top->rtg_vsize, 2047);
	f.fmt = top->rtg_format; f.base = top->rtg_base & 0x7FFFFF; f.stride = top->rtg_stride;
	uint32_t b3 = f.fmt & 7;
	f.bpp = b3 == 3 ? 1 : b3 == 4 ? 2 : b3 == 5 ? 3 : 4;
	f.ok = f.hs && f.vs;
	if (!f.ok) return;
	// fitted to 1280 x 720, the same factor both ways, centred
	f.wide = f.hs * 720 >= f.vs * 1280;
	f.step = f.wide ? (f.hs << 16) / 1280 : (f.vs << 16) / 720;
	uint32_t shown = f.wide ? f.vs * 1280 / f.hs : f.hs * 720 / f.vs;
	f.offx = f.wide ? 0 : (1280 - shown) / 2; f.endx = f.wide ? 1280 : f.offx + shown;
	f.offy = f.wide ? (720 - shown) / 2 : 0; f.endy = f.wide ? f.offy + shown : 720;
	svSetScope(svGetScopeFromName("TOP.tb_top.sdram1"));
	size_t n = size_t(f.vs) * f.stride + 8;
	f.mem.resize(n);
	for (size_t i = 0; i < n; i++) f.mem[i] = rtg_byte((f.base + uint32_t(i)) & 0x7FFFFF);
	svSetScope(svGetScopeFromName("TOP.tb_top.sdram"));
}
static uint32_t rtg_expect(uint32_t x, uint32_t y) {
	const RtgFrame &f = rtg_f;
	if (!f.ok || x < f.offx || x >= f.endx || y < f.offy || y >= f.endy) return 0;
	uint32_t sx = std::min<uint32_t>(((x - f.offx) * f.step) >> 16, f.hs - 1);
	uint32_t sy = std::min<uint32_t>(((y - f.offy) * f.step) >> 16, f.vs - 1);
	const uint8_t *p = &f.mem[size_t(sy) * f.stride + size_t(sx) * f.bpp];
	uint32_t r, g, b, b3 = f.fmt & 7;
	if (b3 == 3) {
		uint32_t c = rtg_pal(p[0]);
		r = c >> 16; g = (c >> 8) & 255; b = c & 255;
	} else if (b3 == 4) {
		uint32_t u = p[0] | (p[1] << 8);
		uint32_t r5 = u & 31;
		r = (r5 << 3) | (r5 >> 2);
		if (f.fmt & 8) {
			uint32_t g5 = (u >> 5) & 31, b5 = (u >> 10) & 31;
			g = (g5 << 3) | (g5 >> 2); b = (b5 << 3) | (b5 >> 2);
		} else {
			uint32_t g6 = (u >> 5) & 63, b5 = (u >> 11) & 31;
			g = (g6 << 2) | (g6 >> 4); b = (b5 << 3) | (b5 >> 2);
		}
	} else {
		r = p[0]; g = p[1]; b = p[2];
	}
	if (f.fmt & 16) std::swap(r, b);
	return (r << 16) | (g << 8) | b;
}
// at every rising clk_av edge
static void rtg_sample() {
	if (!rtg_check || !rtg_mode) return;
	uint32_t x = top->rtg_x, y = top->rtg_y;
	if (x == 0 && y == 0) {
		if (rtg_in_frame) { rtg_in_frame = false; rtg_frame_done = true; }
		else if (rtg_skip > 0) rtg_skip--;
		else if (!rtg_frame_done) {
			if (!top->rtg_enable) { FAIL("RTG mode %d: the picture is not enabled", rtg_mode); rtg_frame_done = true; return; }
			rtg_take_frame();
			rtg_in_frame = true;
			rtg_bad = rtg_pixels = 0;
			rtg_late_start = top->rtg_late;
		}
	}
	if (!rtg_in_frame || x >= 1280 || y >= 720) return;
	uint32_t e = rtg_expect(x, y), c = top->rtg_color;
	rtg_pixels++;
	if (c != e && rtg_bad++ < 8)
		FAIL("RTG mode %d: pixel (%u,%u) is %06X, expected %06X", rtg_mode, x, y, c, e);
}

// chip RAM at addr holds these bytes
static int compare_chip(const char *what, uint32_t addr, const std::vector<uint8_t> &e) {
	int bad = 0;
	for (size_t i = 0; i + 1 < e.size(); i += 2) {
		uint32_t w = chip16(addr + uint32_t(i)), x = uint32_t(e[i]) << 8 | e[i + 1];
		if (w != x && bad++ < 4) FAIL("%s: chip RAM %06X holds %04X, expected %04X", what, addr + uint32_t(i), w, x);
	}
	if (!bad) std::printf("ide test: %s as expected (%zu bytes)\n", what, e.size());
	return bad;
}

// -------------------------------------------------------------- MFM
// One track in the standard Amiga format, as trackdisk writes it: 11
// sectors of 544 words (2 gap words, 2 sync words, header info, label,
// header checksum, data checksum, 512 data bytes as odd then even bits),
// clock bits as ADDCLOCKBITS() of Main_MiSTer's minimig_fdd.cpp.
static uint8_t wtest_byte(int s, int i) { return uint8_t(s * 37 + i * 13 + 5); }

static std::vector<uint16_t> mfm_track(int track) {
	std::vector<uint16_t> out;
	uint16_t prev = 0;
	auto raw = [&](uint16_t w) { out.push_back(w); prev = w; };
	auto data16 = [&](uint16_t v) {
		v &= 0x5555;
		uint16_t inv = uint16_t((v << 1) | (v >> 1) | (prev << 15));
		uint16_t w = uint16_t(v | (inv ^ 0xAAAA));
		out.push_back(w); prev = w;
	};
	auto long_ = [&](uint32_t v) { data16(uint16_t(v >> 16)); data16(uint16_t(v)); };
	auto odd = [](uint32_t v) { return (v >> 1) & 0x55555555u; };
	auto even = [](uint32_t v) { return v & 0x55555555u; };
	for (int i = 0; i < 8; i++) data16(0);
	for (int sec = 0; sec < 11; sec++) {
		data16(0); data16(0);
		raw(0x4489); raw(0x4489);
		uint32_t info = 0xFF000000u | uint32_t(track) << 16 | uint32_t(sec) << 8 | uint32_t(11 - sec);
		uint32_t hck = odd(info) ^ even(info);   // the label is zero
		long_(odd(info)); long_(even(info));
		for (int i = 0; i < 8; i++) long_(0);
		long_(odd(hck)); long_(even(hck));
		uint32_t d[128];
		for (int i = 0; i < 128; i++)
			d[i] = uint32_t(wtest_byte(sec, 4 * i)) << 24 | uint32_t(wtest_byte(sec, 4 * i + 1)) << 16 |
			       uint32_t(wtest_byte(sec, 4 * i + 2)) << 8 | wtest_byte(sec, 4 * i + 3);
		uint32_t dck = 0;
		for (int i = 0; i < 128; i++) dck ^= odd(d[i]) ^ even(d[i]);
		long_(odd(dck)); long_(even(dck));
		for (int i = 0; i < 128; i++) long_(odd(d[i]));
		for (int i = 0; i < 128; i++) long_(even(d[i]));
	}
	for (int i = 0; i < 8; i++) data16(0);
	return out;
}

static uint32_t chip16(uint32_t addr) { return sdram_peek16(addr >> 1); }
static uint32_t sdram_peek16_fwd(uint32_t waddr) { return sdram_peek16(waddr); }

// -------------------------------------------------------------- main
int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	std::setvbuf(stdout, nullptr, _IOLBF, 0);
	top.reset(new Vtb_top);

	std::string kick;
	std::string cart;
	std::string disk[4];
	std::vector<std::pair<uint32_t, uint32_t>> extra_settings;
	double run_ms = 3000;
	int rtg_modes_expected = 0;
	struct Press { double ms; uint32_t mask; double len; };
	std::vector<Press> presses, presses2;   // slot 0, slot 1
	struct Stick { double ms; int v[6]; double len; };
	std::vector<Stick> sticks;
	struct Mouse { double ms; int dx, dy; };
	std::vector<Mouse> mice;
	struct Swap { double ms; uint32_t slot; };
	std::vector<Swap> swaps;
	struct CheckWord { double ms; uint32_t addr, mask, value; bool done; };
	std::vector<CheckWord> checks;
	struct CheckMouse { double ms1, ms2; int dx, dy, tol; uint32_t before; int stage; };
	std::vector<CheckMouse> mchecks;
	struct HWrite { double ms; uint32_t addr, value; bool done; };
	std::vector<HWrite> hwrites;
	struct Focus { double ms; uint32_t value; bool done; };
	std::vector<Focus> focuses;
	struct CheckHalt { double ms; uint32_t value; bool done; };
	std::vector<CheckHalt> hchecks;
	long expect_resets = -1;      // CPU resets after the first start
	double pc_prof_ms = -1;       // --pc-prof: the full profile from this time
	std::vector<uint32_t> watches; // --watch: chip RAM words shown with every status line
	struct SaveRam { double ms; std::string prefix; bool done; };
	std::vector<SaveRam> saverams;
	long cpu_resets = 0;
	bool cpu_rst_q = false;
	bool do_exit = false;
	bool slot1 = false;   // a second controller present
	std::string save_dir;
	long expect_sectors = -1, expect_written = -1;
	bool expect_frame = false;
	bool check_vidtest = false;
	int vidtest_data_x = 40;
	bool floppy_write_test = false;
	bool ide_test = false;
	bool expect_no_fixed = false;
	double coltest_ms = -1;       // when to check the still picture of sim/asm/coltest.s
	bool coltest_done = false, coltest_end = false;
	long expect_hdd_read = -1;
	std::string save_hdf;
	double expect_lr = -1;   // expected mean |right| / mean |left|
	std::vector<std::pair<uint32_t, uint32_t>> dumps;   // SDRAM word address, words
	std::vector<std::pair<uint32_t, uint32_t>> dumps1;  // the same in chip 1
	uint32_t random_ram = 0;   // --random-ram SEED: both chips filled with noise first (as at power-on)

	for (int i = 1; i < argc; i++) {
		std::string a = argv[i];
		auto next = [&]() -> std::string { if (i + 1 >= argc) { std::fprintf(stderr, "missing value for %s\n", a.c_str()); std::fflush(stdout); std::_Exit(2); } return argv[++i]; };
		if (a == "--kick") kick = next();
		else if (a == "--cart") cart = next();
		else if (a == "--disk") { int n = std::atoi(next().c_str()); disk[n & 3] = next(); }
		else if (a == "--set") { std::string v = next(); auto e = v.find('='); extra_settings.push_back({uint32_t(std::stoul(v.substr(0, e), nullptr, 16)), uint32_t(std::stoul(v.substr(e + 1), nullptr, 16))}); }
		else if (a == "--ms") run_ms = std::atof(next().c_str());
		else if (a == "--frames-dir") frames_dir = next();
		else if (a == "--shot-every") shot_every = std::atoi(next().c_str());
		else if (a == "--press2") { Press p; std::string v = next(); std::sscanf(v.c_str(), "%lf:%x:%lf", &p.ms, &p.mask, &p.len); presses2.push_back(p); }
		else if (a == "--stick") { Stick t{}; std::string v = next(); std::sscanf(v.c_str(), "%lf:%d:%d:%d:%d:%d:%d:%lf", &t.ms, &t.v[0], &t.v[1], &t.v[2], &t.v[3], &t.v[4], &t.v[5], &t.len); sticks.push_back(t); }
		else if (a == "--slot1") slot1 = true;
		else if (a == "--press") { Press p; std::string v = next(); std::sscanf(v.c_str(), "%lf:%x:%lf", &p.ms, &p.mask, &p.len); presses.push_back(p); }
		else if (a == "--mouse") { Mouse m; std::string v = next(); std::sscanf(v.c_str(), "%lf:%d:%d", &m.ms, &m.dx, &m.dy); mice.push_back(m); }
		else if (a == "--swap") { Swap s; std::string v = next(); std::sscanf(v.c_str(), "%lf:%u", &s.ms, &s.slot); swaps.push_back(s); }
		else if (a == "--check-word") { CheckWord c{}; std::string v = next(); std::sscanf(v.c_str(), "%lf:%x:%x:%x", &c.ms, &c.addr, &c.mask, &c.value); checks.push_back(c); }
		else if (a == "--check-mouse") { CheckMouse c{}; std::string v = next(); std::sscanf(v.c_str(), "%lf:%lf:%d:%d:%d", &c.ms1, &c.ms2, &c.dx, &c.dy, &c.tol); mchecks.push_back(c); }
		else if (a == "--hwrite") { HWrite h{}; std::string v = next(); std::sscanf(v.c_str(), "%lf:%x:%x", &h.ms, &h.addr, &h.value); hwrites.push_back(h); }
		else if (a == "--focus") { Focus f{}; std::string v = next(); std::sscanf(v.c_str(), "%lf:%u", &f.ms, &f.value); focuses.push_back(f); }
		else if (a == "--check-pc") { PcCheck c{}; std::string v = next(); std::sscanf(v.c_str(), "%lf:%lf:%x:%x:%d:%d", &c.ms1, &c.ms2, &c.lo, &c.hi, &c.minp, &c.maxp); c.c1 = c.c2 = ~0ull; pc_checks.push_back(c); }
		else if (a == "--check-halt") { CheckHalt c{}; std::string v = next(); std::sscanf(v.c_str(), "%lf:%u", &c.ms, &c.value); hchecks.push_back(c); }
		else if (a == "--expect-resets") expect_resets = std::atol(next().c_str());
		else if (a == "--hdf") {
			int n = std::atoi(next().c_str()) & 1;
			hdf[n].selected = true; hdf[n].path = next();
			hdf[n].data = read_file(hdf[n].path); hdf[n].orig = hdf[n].data;
		}
		else if (a == "--fw-latency-us") fw_latency = uint64_t(std::atof(next().c_str()) * 28.375);
		else if (a == "--fw-verbose") fw_verbose = true;
		else if (a == "--ide-test") ide_test = true;
		else if (a == "--expect-no-fixed") expect_no_fixed = true;
		else if (a == "--check-coltest") { coltest_ms = std::atof(next().c_str()); coltest_end = true; }
		else if (a == "--expect-hdd-read") expect_hdd_read = std::atol(next().c_str());
		else if (a == "--save-hdf") save_hdf = next();
		else if (a == "--exit") do_exit = true;
		else if (a == "--rtg-check") rtg_check = true;
		else if (a == "--rtg-modes") rtg_modes_expected = std::atoi(next().c_str());
		else if (a == "--save-dir") save_dir = next();
		else if (a == "--expect-sectors") expect_sectors = std::atol(next().c_str());
		else if (a == "--expect-written") expect_written = std::atol(next().c_str());
		else if (a == "--expect-boot-frame") expect_frame = true;
		else if (a == "--check-vidtest") check_vidtest = true;
		else if (a == "--check-lace") check_lace = true;
		else if (a == "--vidtest-data-x") vidtest_data_x = std::atoi(next().c_str());
		else if (a == "--floppy-write-test") floppy_write_test = true;
		else if (a == "--expect-audio-ratio") expect_lr = std::atof(next().c_str());
		else if (a == "--random-ram") random_ram = std::stoul(next());
		else if (a == "--dump1") { std::string v = next(); auto e = v.find(':'); dumps1.push_back({uint32_t(std::stoul(v.substr(0, e), nullptr, 16)), uint32_t(std::stoul(v.substr(e + 1)))}); }
		else if (a == "--dump") { std::string v = next(); auto e = v.find(':'); dumps.push_back({uint32_t(std::stoul(v.substr(0, e), nullptr, 16)), uint32_t(std::stoul(v.substr(e + 1)))}); }
		else if (a == "--pc-prof") { pc_prof = true; pc_prof_ms = std::atof(next().c_str()); }
		else if (a == "--watch") watches.push_back(uint32_t(std::stoul(next(), nullptr, 16)));
		else if (a == "--save-ram") { std::string v = next(); auto e = v.find(':'); saverams.push_back({std::atof(v.substr(0, e).c_str()), v.substr(e + 1), false}); }
		else if (a == "--trace-cpu") cpu_trace = std::fopen(next().c_str(), "w");
		else if (a == "--trace-from") trace_from = uint64_t(std::atof(next().c_str()) * 28375.0);
		else if (a[0] == '+') ;  // verilator arguments
		else { std::fprintf(stderr, "unknown option %s\n", a.c_str()); return 2; }
	}
	if (kick.empty()) { std::fprintf(stderr, "--kick is required\n"); return 2; }

	// power on: MMCM not locked, framework reset
	top->clk_114 = 0; top->clk_28 = 0; top->clk_57 = 0; top->mmcm_locked = 0; top->reset = 1;
	top->host_mem_enable = 0; top->host_cmd_request = 0; top->buttons = 0;
	top->buttons1 = 0; top->slot1_active = 0; top->sticks = 0;
	top->host_core_busy = 0; top->host_core_done = 0; top->host_core_error = 0;
	top->eval();
	if (random_ram) {
		// power-on SDRAM contents: noise in every word of both chips
		uint32_t x = random_ram;
		for (const char *chip : {"TOP.tb_top.sdram1", "TOP.tb_top.sdram"}) {
			svSetScope(svGetScopeFromName(chip));
			for (uint32_t w = 0; w < (1u << 24); w++) {
				x ^= x << 13; x ^= x >> 17; x ^= x << 5;
				sdram_poke16(w, x & 0xFFFF);
			}
		}
	}
	svSetScope(svGetScopeFromName("TOP.tb_top.sdram"));
	run_cycles(16);
	top->mmcm_locked = 1;
	run_cycles(16);
	top->reset = 0;
	run_cycles(64);

	// the firmware: wait for Setup
	{
		uint32_t s = 0;
		for (int t = 0; t < 100 && (s = get_status()) != 2; t++) run_cycles(1000);
		if (s != 2) { FAIL("core never reported Setup (status %u)", s); std::fflush(stdout); std::_Exit(1); }
		uint32_t id = hread(0x00000000);
		if (id != 0x4D4D4947) FAIL("ID register reads %08X", id);
	}

	// files in files.json order: Disk 1..4 (ids 0..3), Kickstart (id 4), the
	// cartridge (id 7; the hard disks, ids 5 and 6, are read on demand)
	std::vector<FileSpec> files;
	for (int n = 0; n < 4; n++)
		if (!disk[n].empty()) files.push_back({n, 0x10000000u + (uint32_t(n) << 20), disk[n], false, read_file(disk[n])});
	files.push_back({4, 0x20000000u, kick, true, read_file(kick)});
	if (!cart.empty()) files.push_back({7, 0x20100000u, cart, true, read_file(cart)});

	for (auto &f : files) {
		uint64_t t0 = cyc28;
		if (!command({0x0300, uint32_t(f.id)})) FAIL("FileWriteStart %d", f.id);
		hwrite_block(f.addr, to_words(f.data));
		if (!command({0x0301, uint32_t(f.id), uint32_t(f.data.size()), 0})) FAIL("FileWriteEnd %d", f.id);
		std::printf("loaded file %d (%zu bytes) in %.1f ms of core time\n", f.id, f.data.size(),
		            (cyc28 - t0) / 28375.0);
	}

	// settings: the defaults of metadata/settings.json, then the extras
	struct Setting { uint32_t addr, value; };
	std::vector<Setting> settings = {
		{0x1044, 0}, {0x1048, 0}, {0x104C, 1}, {0x1050, 0}, {0x1054, 0}, {0x1058, 0},
		{0x105C, 0}, {0x1060, 7}, {0x1064, 1}, {0x1068, 2},
		{0x106C, 0x40}, {0x1070, 0x44}, {0x1074, 0x50}, {0x1078, 0x45}, {0x107C, 0}, {0x1080, 1},
	};
	for (auto &s : settings) hwrite(s.addr, s.value);
	for (auto &s : extra_settings) hwrite(s.first, s.second);
	for (auto &s : settings) {
		uint32_t v = hread(s.addr);
		bool overridden = false;
		for (auto &e : extra_settings) if (e.first == s.addr) overridden = true;
		if (!overridden && v != s.value) FAIL("setting %04X reads %X, wrote %X", s.addr, v, s.value);
	}

	// check the files arrived in SDRAM in Amiga byte order (word address
	// {bank,row,col} = byte address / 2 for this controller)
	for (auto &f : files) {
		uint32_t base = (f.id == 4) ? 0xB80000u : (f.id == 7) ? 0xB00000u : 0x800000u + 0x80000u * f.id;
		int bad = 0;
		for (size_t i = 0; i + 1 < f.data.size(); i += 2) {
			uint32_t w = sdram_peek16(base + uint32_t(i / 2));
			uint32_t e = (uint32_t(f.data[i]) << 8) | f.data[i + 1];
			if (w != e && bad++ < 4) FAIL("file %d word %zu in SDRAM %04X, expected %04X", f.id, i / 2, w, e);
		}
		// and read back through the host interface
		size_t n = std::min<size_t>(f.data.size() / 4, 1024);
		auto rb = hread_block(f.addr, n);
		auto w = to_words(f.data);
		for (size_t i = 0; i < n; i++)
			if (rb[i] != w[i] && bad++ < 8) FAIL("file %d host read word %zu = %08X, expected %08X", f.id, i, rb[i], w[i]);
		if (!bad) std::printf("file %d verified in SDRAM and by host read back\n", f.id);
	}

	if (!command({0x0102})) FAIL("SetupComplete");
	{
		uint32_t s = 0;
		for (int t = 0; t < 100 && (s = get_status()) != 3; t++) run_cycles(1000);
		if (s != 3) FAIL("core never reported CoreHalt after setup (status %u)", s);
	}
	if (floppy_write_test) {
		// the track for sim/asm/wrtest.s at chip RAM $30000
		auto t = mfm_track(0);
		if (t.size() != 6000) FAIL("MFM track is %zu words", t.size());
		for (size_t i = 0; i < t.size(); i++) sdram_poke16(0x18000 + uint32_t(i), t[i]);
	}
	// sim/asm/idetest.s: the drive to test and its last sector
	Geo geo[2];
	for (int n = 0; n < 2; n++) if (hdf[n].selected) geo[n] = guess_geometry(hdf[n].orig);
	int ide_drv = hdf[0].selected ? 0 : 1;
	if (ide_test) {
		if (!hdf[ide_drv].selected) { FAIL("--ide-test needs --hdf"); std::fflush(stdout); std::_Exit(2); }
		uint32_t last = geo[ide_drv].total - 1 + geo[ide_drv].offset;
		sdram_poke16(0xF0 >> 1, ide_drv ? 0x0010 : 0x0000);
		sdram_poke16(0xF4 >> 1, last >> 16);
		sdram_poke16(0xF6 >> 1, last & 0xFFFF);
	}
	if (!command({0x0100})) FAIL("CoreRun");
	if (!command({0x0200, 1})) FAIL("NotifyFocus");
	if (get_status() != 4) FAIL("core not running after CoreRun");

	// run
	uint64_t run_start = cyc28;
	if (pc_prof && pc_prof_ms >= 0) pc_from = run_start + uint64_t(pc_prof_ms * 28375.0);
	uint64_t run_end = run_start + uint64_t(run_ms * 28375.0);
	for (auto &c : pc_checks) { c.c1 = run_start + uint64_t(c.ms1 * 28375.0); c.c2 = run_start + uint64_t(c.ms2 * 28375.0); }
	bool boot_seen = false;
	uint64_t boot_done_at = 0;
	int last_ms_print = -1;
	while (cyc28 < run_end) {
		double ms = (cyc28 - run_start) / 28375.0;
		uint32_t mask = 0;
		for (auto &p : presses) if (ms >= p.ms && ms < p.ms + p.len) mask |= p.mask;
		top->buttons = mask;
		uint32_t mask2 = 0;
		for (auto &p : presses2) if (ms >= p.ms && ms < p.ms + p.len) mask2 |= p.mask;
		top->buttons1 = mask2;
		top->slot1_active = slot1;
		uint64_t st = 0;
		for (auto &t : sticks) if (ms >= t.ms && ms < t.ms + t.len)
			for (int k = 0; k < 6; k++) st |= uint64_t(uint8_t(int8_t(t.v[k]))) << (8 * k);
		top->sticks = st;
		for (auto &m : mice) if (m.ms >= 0 && ms >= m.ms) {
			hwrite(0x1030, (uint32_t(uint16_t(m.dy)) << 16) | uint16_t(m.dx));
			m.ms = -1;
		}
		for (auto &s : swaps) if (s.ms >= 0 && ms >= s.ms) {
			hwrite(0x105C, s.slot);
			std::printf("%.0f ms: DF0 set to slot %u\n", ms, s.slot);
			s.ms = -1;
		}
		for (auto &f : focuses) if (!f.done && ms >= f.ms) {
			if (!command({0x0200, f.value})) FAIL("NotifyFocus");
			std::printf("%.1f ms: NotifyFocus(%u)\n", ms, f.value);
			f.done = true;
		}
		for (auto &h : hwrites) if (!h.done && ms >= h.ms) { hwrite(h.addr, h.value); h.done = true; }
		for (auto &r : saverams) if (!r.done && ms >= r.ms) {
			// both SDRAM chips whole, the bytes in the Amiga's order
			r.done = true;
			for (int chip = 0; chip < 2; chip++) {
				if (chip) svSetScope(svGetScopeFromName("TOP.tb_top.sdram1"));
				std::string name = r.prefix + (chip ? "_chip1.bin" : "_chip0.bin");
				FILE *f = std::fopen(name.c_str(), "wb");
				if (f) {
					for (uint32_t w = 0; w < 0x1000000; w++) { uint32_t v = sdram_peek16(w); std::fputc(int(v >> 8), f); std::fputc(int(v & 0xFF), f); }
					std::fclose(f);
				}
				if (chip) svSetScope(svGetScopeFromName("TOP.tb_top.sdram"));
			}
			std::printf("%.1f ms: SDRAM saved as %s_chip0.bin, _chip1.bin (pc %08X)\n", ms, r.prefix.c_str(), unsigned(top->dbg_pc));
		}
		for (auto &c : hchecks) if (!c.done && ms >= c.ms) {
			c.done = true;
			if (uint32_t(top->dbg_cpuhlt) != c.value) FAIL("%.1f ms: the CPU is %s, expected %s", ms, top->dbg_cpuhlt ? "halted" : "not halted", c.value ? "halted" : "not halted");
			else std::printf("%.1f ms: the CPU is %s\n", ms, c.value ? "halted" : "not halted");
		}
		for (auto &c : pc_checks) if (!c.done && cyc28 >= c.c2) {
			c.done = true;
			double pct = c.n ? 100.0 * double(c.in) / double(c.n) : 0.0;
			if (pct < c.minp || pct > c.maxp) FAIL("%.0f to %.0f ms: the CPU was at %06X..%06X for %.1f %% of the time, expected %d to %d %%", c.ms1, c.ms2, c.lo, c.hi - 1, pct, c.minp, c.maxp);
			else std::printf("%.0f to %.0f ms: the CPU was at %06X..%06X for %.1f %% of the time (%d to %d %% expected)\n", c.ms1, c.ms2, c.lo, c.hi - 1, pct, c.minp, c.maxp);
		}
		// a CPU reset: _cpu_reset going low after the CPU had run
		if (cpu_rst_q && !top->dbg_cpu_rst) { cpu_resets++; std::printf("%.1f ms: CPU reset\n", ms); }
		cpu_rst_q = top->dbg_cpu_rst;
		// RTG: the ROM shows mode n (word $100 = $0100 + n) and waits for $102 = n
		if (rtg_check) {
			uint32_t w = chip16(0x100);
			int m = ((w & 0xFF00) == 0x0100) ? int(w & 0xFF) : 0;
			if (m > rtg_last_acked && m != rtg_mode && !rtg_in_frame) {
				rtg_mode = m; rtg_skip = 2; rtg_frame_done = false;
				std::printf("%.1f ms: RTG mode %d set\n", ms, m);
			}
			if (rtg_mode && rtg_frame_done) {
				uint32_t late = uint32_t(uint16_t(top->rtg_late - rtg_late_start));
				std::printf("%.1f ms: RTG mode %d: %dx%d format %02X: %llu pixels checked, %llu wrong, %u lines late, %u lines fetched\n",
				            ms, rtg_mode, rtg_f.hs, rtg_f.vs, rtg_f.fmt, (unsigned long long)rtg_pixels,
				            (unsigned long long)rtg_bad, late, top->rtg_lines);
				if (rtg_pixels != 1280ull * 720ull) FAIL("RTG mode %d: %llu pixels checked", rtg_mode, (unsigned long long)rtg_pixels);
				if (late) FAIL("RTG mode %d: %u lines shown without their buffer", rtg_mode, late);
				rtg_bad_total += rtg_bad;
				rtg_modes_done++;
				sdram_poke16(0x102 >> 1, rtg_mode);
				rtg_last_acked = rtg_mode;
				rtg_frame_done = false;
				rtg_mode = 0;
			}
		}
		// chip RAM word at a byte address: SDRAM word address / 2
		for (auto &c : checks) if (!c.done && ms >= c.ms) {
			c.done = true;
			uint32_t w = sdram_peek16(c.addr >> 1);
			if ((w & c.mask) != c.value) FAIL("%.0f ms: chip word %06X = %04X, & %04X expected %04X", ms, c.addr, w, c.mask, c.value);
			else std::printf("%.0f ms: chip word %06X = %04X as expected\n", ms, c.addr, w);
		}
		for (auto &c : mchecks) {
			if (c.stage == 0 && ms >= c.ms1) { c.before = sdram_peek16(0x102 >> 1); c.stage = 1; }
			if (c.stage == 1 && ms >= c.ms2) {
				uint32_t after = sdram_peek16(0x102 >> 1);
				int dx = int8_t(uint8_t(after) - uint8_t(c.before));
				int dy = int8_t(uint8_t(after >> 8) - uint8_t(c.before >> 8));
				if (std::abs(dx - c.dx) > c.tol || std::abs(dy - c.dy) > c.tol) FAIL("mouse counters moved by %d, %d; expected %d, %d (JOY0DAT %04X -> %04X)", dx, dy, c.dx, c.dy, c.before, after);
				else std::printf("%.0f ms: mouse counters moved by %d, %d as expected (%d, %d +- %d)\n", ms, dx, dy, c.dx, c.dy, c.tol);
				c.stage = 2;
			}
		}
		// sim/asm/coltest.s, the still picture: line L is one colour,
		// (L * 17) & 0xFFF, each nibble twice
		if (coltest_ms >= 0 && !coltest_done && ms >= coltest_ms) {
			coltest_done = true;
			int bad = 0;
			for (int y = 0; y < VH; y++) {
				uint32_t c = uint32_t(y * 17) & 0xFFF;
				uint32_t e = ((c >> 8) * 0x11) << 16 | (((c >> 4) & 15) * 0x11) << 8 | ((c & 15) * 0x11);
				for (int x = 0; x < VW; x++)
					if (fb[y * VW + x] != e && bad++ < 5) FAIL("coltest pixel (%d,%d) is %06X, expected %06X", x, y, fb[y * VW + x], e);
			}
			uint32_t fixed = hread(0x40);
			if (fixed) FAIL("coltest: %u pixels of the still picture found no palette entry", fixed);
			if (chip16(0x100) != 0) FAIL("coltest: the picture is already moving (F = %u)", chip16(0x100));
			if (!bad) std::printf("%.0f ms: coltest still picture: 256 colours, all %d pixels exact\n", ms, VW * VH);
		}
		if (!boot_seen && top->dbg_boot_done) { boot_seen = true; boot_done_at = cyc28; }
		core_service();
		cycle28();
		int ims = int(ms / 250);
		if (ims != last_ms_print) {
			last_ms_print = ims;
			std::printf("%6.0f ms: frames %d (changed %d), cpu_rst %d hlt %d, sectors read %u written %u, hdd %u/%u, motor %d, "
			            "hsync %llu vsync %llu, beamcon0 %04X ersy %d lace %d vcnt %u, cpu at %06X\n",
			            ms, frames, frames_changed, top->dbg_cpu_rst, top->dbg_cpuhlt,
			            hread(0x10), hread(0x14), hread(0x28), hread(0x2C), top->dbg_motor,
			            (unsigned long long)hs_edges, (unsigned long long)vs_edges,
			            top->dbg_beamcon0, top->dbg_ersy, top->dbg_lace, top->dbg_video_vcnt, top->dbg_chip_addr << 1);
			hs_edges = vs_edges = 0;
			if (!watches.empty()) {
				std::printf("        watch:");
				for (auto w : watches) std::printf(" %06X = %04X", w, chip16(w));
				std::printf("\n");
			}
			if (pc_prof) {
				// the interrupt state and the three 256-byte blocks the PC was in most
				std::vector<std::pair<uint32_t, uint32_t>> v(pc_iv.begin(), pc_iv.end());
				std::sort(v.begin(), v.end(), [](auto &x, auto &y) { return x.second > y.second; });
				uint64_t tot = 0;
				for (auto &e : v) tot += e.second;
				std::printf("        ipl %u intreq %04X intena %04X dmacon %04X, pc %08X; most:", unsigned(top->dbg_ipl), unsigned(top->dbg_intreq),
				            unsigned(top->dbg_intena), unsigned(top->dbg_dmacon), unsigned(top->dbg_pc));
				for (size_t k = 0; k < v.size() && k < 4; k++)
					std::printf(" %06Xxx %.0f%%", v[k].first, 100.0 * v[k].second / double(tot ? tot : 1));
				std::printf("\n");
				pc_iv.clear();
			}
			std::fflush(stdout);
		}
	}
	if (pc_prof && !pc_all.empty()) {
		std::vector<std::pair<uint32_t, uint64_t>> v(pc_all.begin(), pc_all.end());
		uint64_t tot = 0;
		for (auto &e : v) tot += e.second;
		std::sort(v.begin(), v.end(), [](auto &x, auto &y) { return x.second > y.second; });
		std::printf("PC profile from %.0f ms (%llu samples, %zu addresses):\n", pc_prof_ms, (unsigned long long)tot, v.size());
		for (size_t k = 0; k < v.size() && k < 80; k++)
			std::printf("  %08X %6.2f%%\n", v[k].first, 100.0 * double(v[k].second) / double(tot));
	}
	if (!boot_seen) FAIL("the configuration sequence never finished");
	if (expect_resets >= 0 && cpu_resets != expect_resets) FAIL("%ld CPU resets after the first start, expected %ld", cpu_resets, expect_resets);
	if (rtg_check) {
		std::printf("RTG: %d modes checked, %llu pixels wrong\n", rtg_modes_done, (unsigned long long)rtg_bad_total);
		if (rtg_modes_done != rtg_modes_expected) FAIL("RTG: %d modes checked, expected %d", rtg_modes_done, rtg_modes_expected);
		if (rtg_bad_total) FAIL("RTG: %llu pixels wrong", (unsigned long long)rtg_bad_total);
	}
	else std::printf("configuration and Kickstart upload done after %.1f ms\n", (boot_done_at - run_start) / 28375.0);

	uint32_t sec_rd = hread(0x10), sec_wr = hread(0x14), ferr = hread(0x18);
	std::printf("floppy: %u sectors read, %u written, last error %u\n", sec_rd, sec_wr, ferr);
	std::printf("video: %d frames, %d not blank, %d changes\n", frames, nonblank_frames, frames_changed);
	{
		uint32_t fixed = hread(0x40);
		std::printf("palette: %llu entries written, %u pixels of the last frame in fixed colours, %llu pixels of earlier frames changed colour\n",
		            (unsigned long long)palette_writes, fixed, (unsigned long long)palette_stale);
		std::printf("pixels: %llu checked in palette mode, %llu with a wrong palette colour, %llu with a fixed colour not the nearest\n",
		            (unsigned long long)pixels_checked, (unsigned long long)pixels_wrong, (unsigned long long)pixels_fixed_far);
		if (pixels_wrong) FAIL("%llu pixels shown in the wrong palette colour", (unsigned long long)pixels_wrong);
		if (pixels_fixed_far) FAIL("%llu pixels shown in a fixed colour that is not the nearest", (unsigned long long)pixels_fixed_far);
		if (palette_stale) FAIL("palette entries changed while frames that use them could be on screen (%llu pixels)", (unsigned long long)palette_stale);
		if (expect_no_fixed && fixed) FAIL("%u pixels of the last frame found no palette entry", fixed);
		if (coltest_end) {
			// sim/asm/coltest.s at the end: 256 new colours a frame. Every
			// pixel is its line's colour exactly or, where the palette had
			// no entry free, the fixed colour nearest below or above it.
			if (!coltest_done) FAIL("coltest: the still picture was not checked");
			// the twelve steps of seven frames: the palette has room, so
			// no pixel of those frames may be in a fixed colour
			{
				int frames_checked = 0, frames_bad = 0;
				for (auto &ff : frame_fixed) if (ff.first >= 1 && ff.first <= 12) {
					frames_checked++;
					if (ff.second && frames_bad++ < 5) FAIL("coltest: %u pixels in fixed colours in a frame of step %u, with room in the palette", ff.second, ff.first);
				}
				std::printf("coltest steps: %d frames of 12 colour changes, %d with pixels in fixed colours\n", frames_checked, frames_bad);
				if (frames_checked < 70) FAIL("coltest: only %d frames of the twelve steps seen", frames_checked);
			}
			uint32_t f = chip16(0x100);
			if (f < 32) FAIL("coltest: only %u steps", f);
			int bad = 0, exact = 0, fixedpx = 0, tried = 0;
			// the frame captured is one of the last few: find its F
			for (uint32_t ff = f; ff + 6 > f && !tried; ff--) {
				int ok = 0;
				for (int y = 0; y < VH; y += 37) {
					uint32_t c = (uint32_t(y) * 17 + coltest_offset(ff)) & 0xFFF;
					uint32_t e = ((c >> 8) * 0x11) << 16 | (((c >> 4) & 15) * 0x11) << 8 | ((c & 15) * 0x11);
					uint32_t p = fb[y * VW + 320];
					int dr = std::abs(int(p >> 16) - int(e >> 16)), dg = std::abs(int((p >> 8) & 255) - int((e >> 8) & 255)), db = std::abs(int(p & 255) - int(e & 255));
					if (dr <= 85 && dg <= 37 && db <= 85) ok++;
				}
				if (ok == 7) { tried = 1; f = ff; }
			}
			if (!tried) FAIL("coltest: the last frame matches none of the last frames' colours");
			else for (int y = 0; y < VH; y++) {
				uint32_t c = (uint32_t(y) * 17 + coltest_offset(f)) & 0xFFF;
				uint32_t e = ((c >> 8) * 0x11) << 16 | (((c >> 4) & 15) * 0x11) << 8 | ((c & 15) * 0x11);
				for (int x = 0; x < VW; x++) {
					uint32_t p = fb[y * VW + x];
					if (p == e) { exact++; continue; }
					int dr = std::abs(int(p >> 16) - int(e >> 16)), dg = std::abs(int((p >> 8) & 255) - int((e >> 8) & 255)), db = std::abs(int(p & 255) - int(e & 255));
					if (dr <= 85 && dg <= 37 && db <= 85) fixedpx++;
					else if (bad++ < 5) FAIL("coltest moving pixel (%d,%d) is %06X, its colour %06X", x, y, p, e);
				}
			}
			std::printf("coltest moving picture (F = %u): %d pixels exact, %d in fixed colours, %d wrong\n", f, exact, fixedpx, bad);
			if (fixedpx == 0) FAIL("coltest: the palette never ran out, the fixed colours were not used");
		}
	}
	std::printf("audio: mean |sample| %.1f (left %.1f, right %.1f)\n",
	            audio_samples ? double(audio_abs_sum) / audio_samples / 2 : 0.0,
	            audio_samples ? double(audio_abs_l) / audio_samples : 0.0,
	            audio_samples ? double(audio_abs_r) / audio_samples : 0.0);
	if (expect_lr >= 0) {
		double l = double(audio_abs_l), r = double(audio_abs_r);
		if (l < audio_samples * 100.0) FAIL("no sound on the left channel");
		else if (std::abs(r / l - expect_lr) > 0.03) FAIL("right / left = %.3f, expected %.3f", r / l, expect_lr);
		else std::printf("audio: right / left = %.3f as expected\n", r / l);
	}
	// hard disks
	uint32_t hdd_rd = hread(0x28), hdd_wr = hread(0x2C), hdd_state = hread(0x24);
	std::printf("hard disks: state %08X, %u sectors read, %u written; requests not known to the firmware: %u\n",
	            hdd_state, hdd_rd, hdd_wr, core_bad_requests);
	if (core_bad_requests) FAIL("the core sent requests the firmware does not know");
	if (top->host_core_request) std::printf("hard disks: a core request is pending at the end\n");
	for (int n = 0; n < 2; n++) {
		uint32_t chs = hread(0x30 + 4 * n), total = hread(0x38 + 4 * n);
		if (!hdf[n].selected) continue;
		std::printf("hard disk %d: %u cylinders, %u heads, %u sectors, %u sectors in the image; firmware: %u size, %u read, %u write, %u flush commands, %llu bytes read, %llu written\n",
		            n, chs >> 16, (chs >> 9) & 0x7F, chs & 0x1FF, total, hdf[n].sizes, hdf[n].reads, hdf[n].writes, hdf[n].flushes,
		            (unsigned long long)hdf[n].bytes_read, (unsigned long long)hdf[n].bytes_written);
		if (!ide_test) {
			// the geometry Main_MiSTer would give the image
			if ((chs >> 16) != geo[n].cyl || ((chs >> 9) & 0x7F) != geo[n].heads || (chs & 0x1FF) != geo[n].spt || total != geo[n].total)
				FAIL("hard disk %d geometry: expected %u/%u/%u, %u sectors", n, geo[n].cyl, geo[n].heads, geo[n].spt, geo[n].total);
		}
		if (!save_hdf.empty()) {
			std::ofstream o(save_hdf + "/hdf" + std::to_string(n) + ".hdf", std::ios::binary);
			o.write((const char *)hdf[n].data.data(), hdf[n].data.size());
		}
	}
	if (expect_hdd_read >= 0 && long(hdd_rd) < expect_hdd_read) FAIL("%u hard disk sectors read, expected at least %ld", hdd_rd, expect_hdd_read);

	// sim/asm/idetest.s
	if (ide_test) {
		const Geo g = geo[ide_drv];
		const auto &img = hdf[ide_drv].orig;
		const int d = ide_drv;
		std::printf("ide test: drive %d, image %zu bytes: %u/%u/%u, virtual RDB of %u sectors\n", d, img.size(), g.cyl, g.heads, g.spt, g.offset);
		if (chip16(0x100) != 0x600D || chip16(0x102) != 0) FAIL("the test program stopped in step %u (failed step %u)", chip16(0x100), chip16(0x102));
		if (fb[0] != 0x00FF00) FAIL("the test program ended with COLOR00 %06X", fb[0]);
		if (!(chip16(0x106) & 0x8000)) FAIL("no IDE interrupt request in Gayle after identify");
		if ((chip16(0x104) >> 8) != 0x40) FAIL("status after the identify data %02X, expected 40", chip16(0x104) >> 8);

		// identify: words as the drive sends them (low byte first)
		auto idw = [&](uint32_t base, int i) { uint32_t w = chip16(base + 2 * i); return ((w & 0xFF) << 8) | (w >> 8); };
		auto check_id = [&](uint32_t base, const Geo &x, const char *what) {
			struct { int i; uint32_t v; } e[] = {
				{0, 0x0040}, {1, x.cyl}, {3, x.heads}, {4, (512 * x.spt) & 0xFFFF}, {5, 512}, {6, x.spt},
				{10, 0x414F}, {11, 0x4844}, {20, 3}, {21, 512}, {22, 4}, {27, ('G' << 8) | 'a'}, {28, ('m' << 8) | 'e'},
				{46, 0x2020}, {47, 0x8020}, {48, 1}, {49, 0x200}, {50, 0x4001}, {53, 7},
				{54, x.cyl}, {55, x.heads}, {56, x.spt}, {57, x.total & 0xFFFF}, {58, x.total >> 16}, {59, 0x110},
				{60, x.total & 0xFFFF}, {61, x.total >> 16}, {65, 120}, {68, 120}, {69, 0}, {80, 0x7E}, {82, 0x4200},
				{83, 0x7000}, {84, 0x4000}, {85, 0x4200}, {86, 0x7000}, {87, 0x4000}, {93, 0x630B},
				{100, x.total & 0xFFFF}, {101, x.total >> 16}, {102, 0}, {255, 0},
			};
			int bad = 0;
			for (auto &w : e) if (idw(base, w.i) != w.v && bad++ < 6) FAIL("%s word %d is %04X, expected %04X", what, w.i, idw(base, w.i), w.v);
			if (!bad) std::printf("ide test: %s as expected\n", what);
		};
		check_id(0x1000, g, "identify");
		Geo g2 = g;
		set_geometry(g2, 17, 4);
		check_id(0x1200, g2, "identify after initialize device parameters (4 heads, 17 sectors)");
		{
			uint32_t chs = hread(0x30 + 4 * d);
			if ((chs >> 16) != g2.cyl || ((chs >> 9) & 0x7F) != g2.heads || (chs & 0x1FF) != g2.spt)
				FAIL("geometry register %08X, expected %u/%u/%u", chs, g2.cyl, g2.heads, g2.spt);
		}

		auto sectors = [&](uint32_t lba, int n) {
			std::vector<uint8_t> b;
			for (int i = 0; i < n; i++) { auto s1 = drive_sector(g, img, d, lba + i); b.insert(b.end(), s1.begin(), s1.end()); }
			return b;
		};
		uint32_t hspt = g.heads * g.spt;
		compare_chip(g.offset ? "LBA 0, 1 (virtual RDSK and PART blocks)" : "LBA 0, 1", 0x2000, sectors(0, 2));
		compare_chip("LBA 100..102 (read sectors)", 0x3000, sectors(100, 3));
		compare_chip("40 sectors from CHS 1/0/1 (read multiple)", 0x4000, sectors(hspt, 40));
		{
			auto e = sectors(g.total - 1 + g.offset, 1);
			e.resize(1024, 0);
			compare_chip("the last sector and zeros after the end of the image", 0x9000, e);
		}
		// task file after the reads: the address of the last sector
		{
			uint32_t r0 = chip16(0x110), r1 = chip16(0x112), r2 = chip16(0x114);
			if (r0 != ((102u << 8) | 0) || r1 != (uint32_t(0x00) << 8 | (0xE0 | (d << 4))) || (r2 >> 8) != 0)
				FAIL("task file after the LBA read: %04X %04X %04X", r0, r1, r2);
			else std::printf("ide test: task file after the LBA read as expected\n");
			uint32_t last = hspt + 39;
			uint32_t c = last / hspt, h = (last % hspt) / g.spt, sct = (last % hspt) % g.spt + 1;
			uint32_t q0 = chip16(0x118), q1 = chip16(0x11A), q2 = chip16(0x11C);
			if (q0 != ((sct << 8) | (c & 0xFF)) || q1 != (((c >> 8) << 8) | (0xA0 | (d << 4) | h)) || (q2 >> 8) != 0)
				FAIL("task file after the CHS read: %04X %04X %04X, expected %u/%u/%u", q0, q1, q2, c, h, sct);
			else std::printf("ide test: task file after the CHS read as expected (%u/%u/%u)\n", c, h, sct);
		}
		if (chip16(0x120) != 0x4104) FAIL("unknown command: status, error %04X, expected 4104", chip16(0x120));

		// the image as the test leaves it
		std::vector<uint8_t> e = img;
		auto put_words = [&](uint32_t lba, int nwords, uint16_t start, uint16_t inc) {
			uint16_t v = start;
			for (int i = 0; i < nwords; i++, v = uint16_t(v + inc)) {
				if (lba < g.offset) continue;   // the virtual RDB is not written
				uint64_t o = uint64_t(lba - g.offset) * 512 + 2 * uint64_t(i);
				if (o + 1 < e.size()) { e[o] = uint8_t(v >> 8); e[o + 1] = uint8_t(v); }
			}
		};
		put_words(200, 512, 0xA500, 1);
		put_words(2 * hspt + 2, 20 * 256, 0x1234, 7);
		const auto &now = hdf[d].data;
		if (now.size() != e.size()) FAIL("the image is %zu bytes after the test, was %zu", now.size(), e.size());
		else {
			size_t diff = 0, first = 0;
			for (size_t i = 0; i < e.size(); i++) if (now[i] != e[i]) { if (!diff) first = i; diff++; }
			if (diff) FAIL("the image differs from the expected one in %zu bytes, first at %zu", diff, first);
			else std::printf("ide test: the image holds the 2 + 20 written sectors, nothing else changed\n");
		}
		{
			uint16_t sum = 0;
			for (int i = 0; i < 256; i++) {
				uint64_t o = uint64_t(300 + i - g.offset) * 512;
				for (int j = 0; j < 512; j += 2) sum = uint16_t(sum + ((o + j + 1 < e.size()) ? (uint32_t(e[o + j]) << 8 | e[o + j + 1]) : 0));
			}
			if (chip16(0x130) != sum) FAIL("sum of 256 sectors from LBA 300 is %04X, expected %04X", chip16(0x130), sum);
			else std::printf("ide test: sum of 256 sectors (count 0) as expected\n");
		}
		if (hdf[d].flushes == 0) FAIL("the written sectors were never flushed");
		// write sectors: 1 + 1 sectors; write multiple: blocks of 16 and 4
		if (hdf[d].writes != 4) FAIL("%u FileWrite commands, expected 4", hdf[d].writes);
	}

	uint32_t stalls = hread(0x1000), runc = hread(0x1004);
	std::printf("statistics: %u paused, %u run clocks\n", stalls, runc);
	if (line_reqs) std::printf("lines: %llu requests, %.1f clk_sys each; above the 24-bit space %llu, %.1f clk_sys each\n",
	                           (unsigned long long)line_reqs, double(line_clks) / double(line_reqs),
	                           (unsigned long long)line_reqs_hi,
	                           line_reqs_hi ? double(line_clks_hi) / double(line_reqs_hi) : 0.0);
	if (hi_reqs) std::printf("requests above the 24-bit space: %llu, %.1f clk_sys each (%.1f waiting for the RAM port); "
	                         "%.1f clk_sys from an acknowledge to the next request (%llu)\n",
	                         (unsigned long long)hi_reqs, double(hi_req_clks) / double(hi_reqs),
	                         double(hi_wait_clks) / double(hi_reqs),
	                         hi_gaps ? double(hi_gap_clks) / double(hi_gaps) : 0.0, (unsigned long long)hi_gaps);
	std::printf("CPU RAM: %llu long words in one transfer, %llu lines in one request; SDRAM CPU slots: "
	            "chip 0 %llu reads, %llu writes (%llu long), chip 1 %llu reads, %llu writes (%llu long)\n",
	            (unsigned long long)ram_long, (unsigned long long)line_reqs, (unsigned long long)sd_rd[0], (unsigned long long)sd_wr[0],
	            (unsigned long long)sd_wr2[0], (unsigned long long)sd_rd[1], (unsigned long long)sd_wr[1],
	            (unsigned long long)sd_wr2[1]);
	std::printf("chip bus: %llu CPU cycles, 32-bit: %llu reads, %llu writes\n",
	            (unsigned long long)chip_cycles, (unsigned long long)chip_long_rd,
	            (unsigned long long)chip_long_wr);
	if (runc == 0) FAIL("run statistics counter did not count");

	if (expect_sectors >= 0 && long(sec_rd) < expect_sectors) FAIL("%u sectors read, expected at least %ld", sec_rd, expect_sectors);
	if (expect_written >= 0 && long(sec_wr) < expect_written) FAIL("%u sectors written, expected at least %ld", sec_wr, expect_written);
	if (expect_frame && nonblank_frames == 0) FAIL("no picture");
	for (auto &c : checks) if (!c.done) FAIL("check at %.0f ms not reached", c.ms);
	for (auto &c : mchecks) if (c.stage != 2) FAIL("mouse check not reached");

	// sim/asm/wrtest.s: track 0 of the image in slot 0 holds the sectors
	if (floppy_write_test) {
		int bad = 0;
		for (int sec = 0; sec < 11; sec++) for (int i = 0; i < 512; i += 2) {
			uint32_t w = sdram_peek16(0x800000u + uint32_t(sec * 256 + i / 2));
			uint32_t e = uint32_t(wtest_byte(sec, i)) << 8 | wtest_byte(sec, i + 1);
			if (w != e && bad++ < 5) FAIL("written sector %d byte %d: %04X, expected %04X", sec, i, w, e);
		}
		if (!bad) std::printf("floppy write test: the 11 sectors of track 0 are in the image\n");
		if (sec_wr != 11) FAIL("%u sectors written, expected 11", sec_wr);
		if (fb[0] != 0x00FF00) FAIL("the test program ended with COLOR00 %06X (green: written, red: timeout)", fb[0]);
	}

	// sim/asm/vidtest.s: 320 x 256 picture in the standard PAL display
	// window; the frame holds all 256 of its lines (Picture height, 0x1080,
	// 1: the core tells the framework to fit them) or 240 from the one the
	// Picture position setting gives (0x107C, 0..16; gb_video V_START), its
	// 640 pixels at 40..679 of the 720, the border (colour 0) 40 either
	// side: gb_video centres its window on the display window, so also with
	// the window moved (vidtest_l, vidtest_r). The bitplane's first pixel
	// at --vidtest-data-x (40: where the window opens; vidtest_r moves the
	// window and not the fetch). Colour 1 yellow, colour 0 blue.
	if (check_vidtest) {
		const uint32_t Y = 0xFFFF00, B = 0x0000FF;
		int vpos = 0, fit = 1;
		for (auto &e : extra_settings) if (e.first == 0x107C) vpos = int(e.second);
		for (auto &e : extra_settings) if (e.first == 0x1080) fit = int(e.second) & 1;
		const int left = vidtest_data_x;
		if (bool(top->video_fit) != bool(fit)) FAIL("the core's fit output is %d, the setting %d", int(top->video_fit), fit);
		if (fit) vpos = 0;
		const int lines = fit ? 256 : 240;
		int bad = 0;
		for (int y = 0; y < lines; y++) for (int x = 0; x < VW; x++) {
			int line = y + vpos;
			int lx = (x - left) / 2;   // the low resolution pixel, shown twice
			bool one = x >= 40 && x < 680 && x >= left && x < left + 640 &&
			           ((line % 16 == 0) || line == 255 || lx < 16 || lx >= 304 || ((lx - 16) % 8) < 4);
			uint32_t e = one ? Y : B;
			if (fb[y * VW + x] != e && bad++ < 5) FAIL("vidtest pixel (%d,%d) is %06X, expected %06X", x, y, fb[y * VW + x], e);
		}
		if (!bad) std::printf("vidtest picture: all %d pixels as expected (lines %d to %d of the display window)\n", VW * lines, vpos, vpos + lines - 1);
	}
	if (check_lace) {
		std::printf("lacetest: %d frames checked, %d of short fields, %llu fields\n", lace_frames, lace_short,
		            (unsigned long long)(lace_vs_last - lace_vs_first));
		if (lace_frames < 6) FAIL("lacetest: %d frames, expected at least 6", lace_frames);
		if (lace_vs_last - lace_vs_first != 2ull * uint64_t(lace_frames - 1))
			FAIL("lacetest: %llu fields between the first and the last frame, expected %d (one frame every two fields)",
			     (unsigned long long)(lace_vs_last - lace_vs_first), 2 * (lace_frames - 1));
	}

	if (do_exit) {
		// the firmware's exit_core(): CoreHalt, then save every file that
		// is not read only
		if (!command({0x0101})) FAIL("CoreHalt");
		for (auto &f : files) {
			if (f.read_only) continue;
			uint32_t size = 0;
			if (!command({0x0302, uint32_t(f.id)}, &size)) { FAIL("FileReadStart %d", f.id); continue; }
			if (size != f.data.size()) FAIL("FileReadStart %d answered %u, loaded %zu", f.id, size, f.data.size());
			uint64_t t0 = cyc28;
			auto w = hread_block(f.addr, (size + 3) / 4);
			double ms = (cyc28 - t0) / 28375.0;
			if (!command({0x0303, uint32_t(f.id)})) FAIL("FileReadEnd %d", f.id);
			std::vector<uint8_t> saved(size);
			for (size_t i = 0; i < size; i++) saved[i] = uint8_t(w[i / 4] >> (8 * (i % 4)));
			// compare with the image in SDRAM
			uint32_t base = 0x800000u + 0x80000u * f.id;
			int bad = 0;
			for (size_t i = 0; i + 1 < size; i += 2) {
				uint32_t e = sdram_peek16(base + uint32_t(i / 2));
				if (((uint32_t(saved[i]) << 8) | saved[i + 1]) != e && bad++ < 4)
					FAIL("saved image %d differs from SDRAM at byte %zu", f.id, i);
			}
			size_t diff = 0;
			for (size_t i = 0; i < size; i++) if (saved[i] != f.data[i]) diff++;
			std::printf("saved image %d: %u bytes in %.1f ms (%.0f KB/s at the core), %zu bytes differ from the loaded image\n",
			            f.id, size, ms, size / 1024.0 / (ms / 1000.0), diff);
			if (!save_dir.empty()) {
				std::ofstream o(save_dir + "/disk" + std::to_string(f.id) + ".adf", std::ios::binary);
				o.write((const char *)saved.data(), saved.size());
			}
		}
		// a slot without an image is answered with 0 (nothing to save)
		for (int n = 0; n < 4; n++) if (disk[n].empty()) {
			uint32_t size = 1;
			command({0x0302, uint32_t(n)}, &size);
			if (size != 0) FAIL("FileReadStart for empty slot %d answered %u", n, size);
			command({0x0303, uint32_t(n)});
		}
	}

	std::printf("Agnus: DMACON %04X, copper at %06X\n", top->dbg_dmacon, top->dbg_cop_addr << 1);
	if (!dumps1.empty()) {
		svSetScope(svGetScopeFromName("TOP.tb_top.sdram1"));
		for (auto &d : dumps1) {
			std::printf("SDRAM chip 1 words at %06X:", d.first);
			for (uint32_t i = 0; i < d.second; i++) std::printf("%s%04X", (i % 16) ? " " : "\n  ", sdram_peek16(d.first + i));
			std::printf("\n");
		}
		svSetScope(svGetScopeFromName("TOP.tb_top.sdram"));
	}
	for (auto &d : dumps) {
		std::printf("SDRAM words at %06X:", d.first);
		for (uint32_t i = 0; i < d.second; i++) std::printf("%s%04X", (i % 16) ? " " : "\n  ", sdram_peek16(d.first + i));
		std::printf("\n");
	}

	int sd_err = sdram_errors();
	// chip 1's model (the scope is chip 0's everywhere else)
	svSetScope(svGetScopeFromName("TOP.tb_top.sdram1"));
	int sd_err1 = sdram_errors();
	svSetScope(svGetScopeFromName("TOP.tb_top.sdram"));
	if (sd_err1) std::printf("SDRAM chip 1 model: %d errors\n", sd_err1);
	sd_err += sd_err1;
	if (sd_err) FAIL("SDRAM protocol errors: %d", sd_err);
	std::printf("SDRAM pins: %llu clock edges, %llu with outputs changing at the rising edge\n",
	            (unsigned long long)sd_edges, (unsigned long long)sd_edge_errors);
	if (sd_edge_errors) FAIL("SDRAM outputs change at the rising SDRAM clock");
	if (sd_edges == 0) FAIL("no SDRAM clock");

	if (cpu_trace) std::fclose(cpu_trace);
	top->final();
	std::printf("%s\n", failures ? "TEST FAILED" : "TEST PASSED");
	std::fflush(stdout);
	std::fflush(stderr);
	// leave without the static destructors (the Verilated model's teardown
	// can block on its mutex after $stop / with DPI scopes set)
	std::_Exit(failures ? 1 : 0);
}
