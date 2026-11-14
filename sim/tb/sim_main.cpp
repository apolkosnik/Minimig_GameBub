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
//   --set ADDR=VALUE     a setting write (hex), after the defaults
//   --ms N               run N ms of Amiga time after CoreRun (default 3000)
//   --frames-dir DIR     write every captured frame as DIR/frame_NNNN.ppm
//   --shot-every N       only every Nth frame (default 1)
//   --press MS:BUTTONS:LEN  press buttons (hex mask, tb_top order) at MS for LEN ms
//   --mouse MS:DX:DY     a host mouse report at MS
//   --swap MS:DF0SLOT    change the DF0 setting at MS
//   --exit               do the firmware's exit sequence at the end and
//                        compare the saved images with the SDRAM contents
//   --save-dir DIR       write the saved images there (with --exit)
//   --expect-sectors N   fail unless at least N floppy sectors were read
//   --expect-written N   fail unless at least N floppy sectors were written
//   --expect-boot-frame  fail unless a non-blank frame was seen
//   --trace-cpu FILE     log every CPU bus write
//
// The exit status is 0 when every check passed.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
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
static int failures = 0;

#define FAIL(...) do { std::fprintf(stderr, "FAIL: " __VA_ARGS__); std::fprintf(stderr, "\n"); failures++; } while (0)

// -------------------------------------------------------------- video
static const int VW = 320, VH = 240;
static std::vector<uint32_t> fb(VW * VH);
static int fb_x = 0, fb_y = 0;
static bool prev_hblank = true, prev_vblank = true;
static int frames = 0;
static uint64_t hs_edges = 0, vs_edges = 0;   // falling edges of _hsync / _vsync
static int nonblank_frames = 0;
static std::string frames_dir;
static int shot_every = 1;
static uint32_t last_frame_hash = 0;
static int frames_changed = 0;

static void save_frame(const std::string &path) {
	FILE *f = std::fopen(path.c_str(), "wb");
	if (!f) return;
	std::fprintf(f, "P6\n%d %d\n255\n", VW, VH);
	for (int i = 0; i < VW * VH; i++) {
		uint8_t px[3] = { uint8_t(fb[i] >> 16), uint8_t(fb[i] >> 8), uint8_t(fb[i]) };
		std::fwrite(px, 1, 3, f);
	}
	std::fclose(f);
}

// called with the values the core presents before a clk_28 rising edge
static void video_sample() {
	bool de = top->video_de, hb = top->video_hblank, vb = top->video_vblank;
	bool vb_edge = vb && !prev_vblank;
	bool hb_edge = hb && !prev_hblank;

	if (de && fb_x < VW && fb_y < VH) {
		uint32_t r = top->video_r, g = top->video_g, b = top->video_b;
		r = (r << 3) | (r >> 2);
		g = (g << 2) | (g >> 4);
		b = (b << 3) | (b >> 2);
		fb[fb_y * VW + fb_x] = (r << 16) | (g << 8) | b;
	}
	if (vb_edge) {
		// a frame completed
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

// The SDRAM pins: sdram_ctrl drives them all from clk_114 registers (put in
// the I/O blocks by rtl/gamebub/minimig.xdc) and makes the SDRAM clock from
// one of them. Its commands, address, DQM and data must only change at the
// clk_114 edges at which the SDRAM clock falls, so that the SDRAM sees them
// stable a whole clk_114 period before and after its rising edge.
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

// one clk_28 cycle: drive the inputs for the coming edge, then 4 clk_114 cycles
static void cycle28() {
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
		if (pvs && !vs) vs_edges++;
		phs = hs; pvs = vs;
	}
	audio_abs_sum += std::abs((int16_t)top->audio_left) + std::abs((int16_t)top->audio_right);
	audio_abs_l += std::abs((int16_t)top->audio_left);
	audio_abs_r += std::abs((int16_t)top->audio_right);
	audio_samples++;

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

	for (int p = 0; p < 4; p++) {
		top->clk_114 = 1;
		if (p == 0) top->clk_28 = 1;
		if (p == 2) top->clk_28 = 0;
		top->eval();
		sdram_pin_check();
		top->clk_114 = 0;
		top->eval();
	}
	cyc28++;

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

// -------------------------------------------------------------- main
int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	std::setvbuf(stdout, nullptr, _IOLBF, 0);
	top.reset(new Vtb_top);

	std::string kick;
	std::string disk[4];
	std::vector<std::pair<uint32_t, uint32_t>> extra_settings;
	double run_ms = 3000;
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
	bool do_exit = false;
	bool slot1 = false;   // a second controller present
	std::string save_dir;
	long expect_sectors = -1, expect_written = -1;
	bool expect_frame = false;
	bool check_vidtest = false;
	bool floppy_write_test = false;
	double expect_lr = -1;   // expected mean |right| / mean |left|
	std::vector<std::pair<uint32_t, uint32_t>> dumps;   // SDRAM word address, words

	for (int i = 1; i < argc; i++) {
		std::string a = argv[i];
		auto next = [&]() -> std::string { if (i + 1 >= argc) { std::fprintf(stderr, "missing value for %s\n", a.c_str()); std::fflush(stdout); std::_Exit(2); } return argv[++i]; };
		if (a == "--kick") kick = next();
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
		else if (a == "--exit") do_exit = true;
		else if (a == "--save-dir") save_dir = next();
		else if (a == "--expect-sectors") expect_sectors = std::atol(next().c_str());
		else if (a == "--expect-written") expect_written = std::atol(next().c_str());
		else if (a == "--expect-boot-frame") expect_frame = true;
		else if (a == "--check-vidtest") check_vidtest = true;
		else if (a == "--floppy-write-test") floppy_write_test = true;
		else if (a == "--expect-audio-ratio") expect_lr = std::atof(next().c_str());
		else if (a == "--dump") { std::string v = next(); auto e = v.find(':'); dumps.push_back({uint32_t(std::stoul(v.substr(0, e), nullptr, 16)), uint32_t(std::stoul(v.substr(e + 1)))}); }
		else if (a == "--trace-cpu") cpu_trace = std::fopen(next().c_str(), "w");
		else if (a == "--trace-from") trace_from = uint64_t(std::atof(next().c_str()) * 28375.0);
		else if (a[0] == '+') ;  // verilator arguments
		else { std::fprintf(stderr, "unknown option %s\n", a.c_str()); return 2; }
	}
	if (kick.empty()) { std::fprintf(stderr, "--kick is required\n"); return 2; }

	// power on: MMCM not locked, framework reset
	top->clk_114 = 0; top->clk_28 = 0; top->mmcm_locked = 0; top->reset = 1;
	top->host_mem_enable = 0; top->host_cmd_request = 0; top->buttons = 0;
	top->buttons1 = 0; top->slot1_active = 0; top->sticks = 0;
	top->eval();
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

	// files in files.json order: Disk 1..4 (ids 0..3), Kickstart (id 4)
	std::vector<FileSpec> files;
	for (int n = 0; n < 4; n++)
		if (!disk[n].empty()) files.push_back({n, 0x10000000u + (uint32_t(n) << 20), disk[n], false, read_file(disk[n])});
	files.push_back({4, 0x20000000u, kick, true, read_file(kick)});

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
		{0x106C, 0x40}, {0x1070, 0x44}, {0x1074, 0x50}, {0x1078, 0x45}, {0x107C, 8},
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
		uint32_t base = (f.id == 4) ? 0xB80000u : 0x800000u + 0x80000u * f.id;
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
	if (!command({0x0100})) FAIL("CoreRun");
	if (!command({0x0200, 1})) FAIL("NotifyFocus");
	if (get_status() != 4) FAIL("core not running after CoreRun");

	// run
	uint64_t run_start = cyc28;
	uint64_t run_end = run_start + uint64_t(run_ms * 28375.0);
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
		for (auto &h : hwrites) if (!h.done && ms >= h.ms) { hwrite(h.addr, h.value); h.done = true; }
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
		if (!boot_seen && top->dbg_boot_done) { boot_seen = true; boot_done_at = cyc28; }
		cycle28();
		int ims = int(ms / 250);
		if (ims != last_ms_print) {
			last_ms_print = ims;
			std::printf("%6.0f ms: frames %d (changed %d), cpu_rst %d hlt %d, sectors read %u written %u, motor %d, "
			            "hsync %llu vsync %llu, beamcon0 %04X ersy %d lace %d vcnt %u, cpu at %06X\n",
			            ms, frames, frames_changed, top->dbg_cpu_rst, top->dbg_cpuhlt,
			            hread(0x10), hread(0x14), top->dbg_motor,
			            (unsigned long long)hs_edges, (unsigned long long)vs_edges,
			            top->dbg_beamcon0, top->dbg_ersy, top->dbg_lace, top->dbg_video_vcnt, top->dbg_chip_addr << 1);
			hs_edges = vs_edges = 0;
			std::fflush(stdout);
		}
	}
	if (!boot_seen) FAIL("the configuration sequence never finished");
	else std::printf("configuration and Kickstart upload done after %.1f ms\n", (boot_done_at - run_start) / 28375.0);

	uint32_t sec_rd = hread(0x10), sec_wr = hread(0x14), ferr = hread(0x18);
	std::printf("floppy: %u sectors read, %u written, last error %u\n", sec_rd, sec_wr, ferr);
	std::printf("video: %d frames, %d not blank, %d changes\n", frames, nonblank_frames, frames_changed);
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
	uint32_t stalls = hread(0x1000), runc = hread(0x1004);
	std::printf("statistics: %u paused, %u run clocks\n", stalls, runc);
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
	// window; the frame shows its lines 8..247 (gb_video V_START), all 320
	// pixels (H_START). Colour 1 yellow, colour 0 blue.
	if (check_vidtest) {
		const uint32_t Y = 0xFFFF00, B = 0x0000FF;
		int bad = 0;
		for (int y = 0; y < VH; y++) for (int x = 0; x < VW; x++) {
			int line = y + 8;
			bool one = (line % 16 == 0) || line == 255 || x < 16 || x >= 304 || ((x - 16) % 8) < 4;
			uint32_t e = one ? Y : B;
			if (fb[y * VW + x] != e && bad++ < 5) FAIL("vidtest pixel (%d,%d) is %06X, expected %06X", x, y, fb[y * VW + x], e);
		}
		if (!bad) std::printf("vidtest picture: all %d pixels as expected\n", VW * VH);
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
	for (auto &d : dumps) {
		std::printf("SDRAM words at %06X:", d.first);
		for (uint32_t i = 0; i < d.second; i++) std::printf("%s%04X", (i % 16) ? " " : "\n  ", sdram_peek16(d.first + i));
		std::printf("\n");
	}

	int sd_err = sdram_errors();
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
