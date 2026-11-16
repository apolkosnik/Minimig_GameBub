// Game Bub Minimig: 24 bit colours -> 10 bit palette indices.
//
// Two 640 x 256 frame buffers fit the FPGA's block RAM at 10 bits per
// pixel, not at the 12 bits of an OCS / ECS colour or the 24 of an AGA one.
// An Amiga picture has few colours at a time, though: this module gives
// every colour that appears a place in a palette of 768 entries of 24 bits
// and puts out the entry's index; the framework (patches/framework) keeps
// the indices in its frame buffers and looks the colour up as it shows
// them. The colours on screen are then exact.
//
// A colour keeps its entry while it is in use. Every entry has an age: 0
// when a pixel uses it, one more at the start of every frame (all entries
// are gone through then, in the vertical blanking), up to 7. An entry is
// given to a new colour only at age 5 or more, when no pixel has used it
// for four whole frames, so that no frame buffer still on screen holds its
// index. When a new colour finds no such
// entry (more than 768 colours in five frames: HAM pictures, colour ramps
// that change every frame) it is shown as the nearest of 256 fixed colours
// instead (3 bits red, 3 green, 2 blue, dithered; the indices 768..1023,
// which the framework decodes itself).
//
// Finding a colour's entry: two hash tables give two candidates, and the
// palette's own copy here says whether one of them holds the colour (an
// entry that was given to another colour since simply does not match). A
// new colour is put into both tables: it loses its entry only when new
// colours have taken both its places. (With one table per colour, colours
// that shared a place took it from each other every frame and kept taking
// new entries; putting a colour found through one table back into the
// other did the same through chains of three colours. Either way still
// pictures of a few hundred colours ran out of entries.)
// A pixel takes two clocks: the tables and the palette are read in the
// first, compared and updated in the second; pixels come at least two
// clocks apart, so each sees the tables as the one before left them.
//
// SPDX-License-Identifier: GPL-3.0-or-later

module gb_palette
(
	input             clk,
	input             reset,

	input             in_de,       // one clock per pixel, pixels at least two clocks apart
	input       [7:0] in_r,
	input       [7:0] in_g,
	input       [7:0] in_b,
	input       [1:0] in_bayer,    // dither threshold for the fixed colours (2 x 2 pattern)
	input             frame,       // one clock per frame
	input             no_reuse,    // test: an entry once given to a colour is never given to another

	output reg        out_de,      // three clocks after in_de
	output reg  [9:0] out_index,

	// palette writes for the framework
	output reg        pal_we,
	output reg  [9:0] pal_index,
	output reg [23:0] pal_color,

	output reg [19:0] fixed_pixels // pixels of the last whole frame shown in a fixed colour
);

localparam [9:0] ENTRIES = 10'd768;

// the palette as the framework has it, twice: one copy for each candidate,
// each a block RAM with one write port (new entries) and one read port.
// (One RAM with a port that wrote new entries and read the first
// candidate, its address chosen between the two: Vivado 2018.3 left the
// choice out and wrote new colours over the candidate's entry, so on the
// FPGA no colour was found again and the entries ran out at once; every
// simulation of the RTL was right. sim/gls/run_palette_gls.sh compares the
// netlist with the RTL.)
reg [23:0] pal1 [0:1023];
reg [23:0] pal2 [0:1023];
reg [23:0] a_q, b_q;

// colour -> entry, two ways
reg  [9:0] ht1 [0:2047];
reg  [9:0] ht2 [0:2047];
// frames since an entry was last used (7: that many or more)
reg  [2:0] age [0:1023];

integer i;
initial begin
	for (i = 0; i < 1024; i = i + 1) begin pal1[i] = 24'd0; pal2[i] = 24'd0; age[i] = 3'd7; end
	for (i = 0; i < 2048; i = i + 1) begin ht1[i] = 10'd0; ht2[i] = 10'd0; end
end

// stage 1: the pixel's colour, its two candidates. The tables are block
// RAM, read as the pixel comes in (by hashes of the incoming colour).
reg        v1, v2;
reg [23:0] c1, c2;
reg  [1:0] bayer1, bayer2;
wire [23:0] cin = {in_r, in_g, in_b};
wire [10:0] h1_in = cin[10:0] ^ cin[21:11] ^ {9'd0, cin[23:22]};
wire [10:0] h2_in = {cin[4:0], cin[23:18]} ^ {cin[12:5], cin[15:13]} ^ {cin[17:16], 9'd0};
reg  [10:0] h1, h2;
reg   [9:0] ht1_q, ht2_q;      // the tables' read registers
reg         fwd1, fwd2;        // ... or the entry given away as they were read
reg   [9:0] fwd_idx;
wire  [9:0] cand1 = fwd1 ? fwd_idx : ht1_q;
wire  [9:0] cand2 = fwd2 ? fwd_idx : ht2_q;
reg  [10:0] h1_2, h2_2;
reg   [9:0] cand1_2, cand2_2;

// an entry free to be given away, and the pass over all ages
reg  [9:0] scan;
reg  [9:0] free_idx;
reg        free_valid;
reg        sweep;            // every entry's age goes up by one
reg  [9:0] sweep_idx;
reg [19:0] fixed_count;
// the ages have one write port (a pixel's entry, else the pass) and one
// read port (the pass, else the search for a free entry)
wire [9:0] age_raddr = sweep ? sweep_idx : scan;
wire [2:0] age_q     = age[age_raddr];
wire       scan_old  = (age_q >= 3'd5);

// stage 2: which entry
wire hit1 = (a_q == c2) && (cand1_2 < ENTRIES);
wire hit2 = (b_q == c2) && (cand2_2 < ENTRIES);
wire hit  = hit1 | hit2;
wire [9:0] hit_idx = hit1 ? cand1_2 : cand2_2;
wire alloc = v2 & ~hit & free_valid;

// the fixed colours: 3 + 3 + 2 bits with an ordered dither, the same
// threshold for the three components, so that a colour is shown a little
// lighter or darker, never in another hue
wire  [7:0] thr = {bayer2, 6'd24};                 // 24, 88, 152, 216
wire [10:0] qr = c2[23:16] * 3'd7 + {3'd0, thr};
wire [10:0] qg = c2[15:8]  * 3'd7 + {3'd0, thr};
wire  [9:0] qb = c2[7:0]   * 2'd3 + {2'd0, thr};
wire  [9:0] fixed_idx = {2'b11, qr[10:8], qg[10:8], qb[9:8]};

always @(posedge clk) begin
	if (alloc) pal1[free_idx] <= c2;
	a_q <= pal1[cand1];
end
always @(posedge clk) begin
	if (alloc) pal2[free_idx] <= c2;
	b_q <= pal2[cand2];
end

always @(posedge clk) begin
	out_de <= 1'b0;
	pal_we <= 1'b0;

	// stage 1
	v1 <= in_de;
	if (in_de) begin
		c1     <= cin;
		bayer1 <= in_bayer;
		h1     <= h1_in;
		h2     <= h2_in;
		// the tables as they are after this clock: an entry given away in
		// this very clock (stage 2 below) is passed on to the new pixel
		ht1_q   <= ht1[h1_in];
		ht2_q   <= ht2[h2_in];
		fwd1    <= alloc && h1_2 == h1_in;
		fwd2    <= alloc && h2_2 == h2_in;
		fwd_idx <= free_idx;
	end

	// stage 2: registered with the palette's read
	v2 <= v1;
	if (v1) begin
		c2      <= c1;
		bayer2  <= bayer1;
		h1_2    <= h1;
		h2_2    <= h2;
		cand1_2 <= cand1;
		cand2_2 <= cand2;
	end

	// the search for a free entry: one entry a clock while none is at hand
	// (the pass over the ages has the read port first)
	if (!sweep && !free_valid) begin
		// (not the entry a pixel is using in this very clock)
		if (scan_old && !(v2 && hit && hit_idx == scan)) begin
			free_idx   <= scan;
			free_valid <= 1'b1;
		end
		scan <= (scan == ENTRIES - 10'd1) ? 10'd0 : scan + 10'd1;
	end

	// the pass: a clock an entry, in the clocks no pixel writes an age
	if (sweep && !v2) begin
		// (no_reuse: entries in use stay young; only the never used are free)
		if (age_q != 3'd7 && !no_reuse) age[sweep_idx] <= age_q + 3'd1;
		if (sweep_idx == ENTRIES - 10'd1) sweep <= 1'b0;
		sweep_idx <= sweep_idx + 10'd1;
	end

	if (v2) begin
		out_de <= 1'b1;
		if (hit) begin
			out_index    <= hit_idx;
			age[hit_idx] <= 3'd0;
			// (the entry at hand is in use after all)
			if (free_valid && hit_idx == free_idx) free_valid <= 1'b0;
		end
		else if (free_valid) begin
			out_index     <= free_idx;
			age[free_idx] <= 3'd0;
			ht1[h1_2] <= free_idx;
			ht2[h2_2] <= free_idx;
			free_valid <= 1'b0;
			pal_we     <= 1'b1;
			pal_index  <= free_idx;
			pal_color  <= c2;
		end
		else begin
			out_index   <= fixed_idx;
			if (fixed_count != 20'hFFFFF) fixed_count <= fixed_count + 20'd1;
		end
	end

	if (frame) begin
		fixed_pixels <= fixed_count;
		fixed_count  <= 20'd0;
		sweep        <= 1'b1;
		sweep_idx    <= 10'd0;
	end

	if (reset) begin
		v1           <= 1'b0;
		v2           <= 1'b0;
		sweep        <= 1'b0;
		sweep_idx    <= 10'd0;
		scan         <= 10'd0;
		free_valid   <= 1'b0;
		fixed_count  <= 20'd0;
		fixed_pixels <= 20'd0;
		out_index    <= 10'd0;
	end
end

endmodule
