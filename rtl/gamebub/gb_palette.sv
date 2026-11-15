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
// A colour keeps its entry while it is in use. An entry is given to a new
// colour only when no pixel has used it for four frames, so that no frame
// buffer still on screen holds its index. When a new colour finds no such
// entry (more than 768 colours in five frames: HAM pictures, colour ramps
// that change every frame) it is shown as the nearest of 256 fixed colours
// instead (3 bits red, 3 green, 2 blue, dithered; the indices 768..1023,
// which the framework decodes itself).
//
// Finding a colour's entry: two hash tables give two candidates, and the
// palette's own copy here says whether one of them holds the colour (an
// entry that was given to another colour since simply does not match).
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

	output reg        out_de,      // three clocks after in_de
	output reg  [9:0] out_index,

	// palette writes for the framework
	output reg        pal_we,
	output reg  [9:0] pal_index,
	output reg [23:0] pal_color,

	output reg [19:0] fixed_pixels // pixels of the last whole frame shown in a fixed colour
);

localparam [9:0] ENTRIES = 10'd768;

// the palette as the framework has it (port A: first candidate and writes,
// port B: second candidate)
reg [23:0] pal [0:1023];
reg  [9:0] a_addr;
reg        a_we;
reg [23:0] a_q, b_q;
reg  [9:0] b_addr;

// colour -> entry, two ways
reg  [9:0] ht1 [0:2047];
reg  [9:0] ht2 [0:2047];
// frame an entry was last used in
reg  [2:0] stamp [0:1023];

integer i;
initial begin
	for (i = 0; i < 1024; i = i + 1) begin pal[i] = 24'd0; stamp[i] = 3'd0; end
	for (i = 0; i < 2048; i = i + 1) begin ht1[i] = 10'd0; ht2[i] = 10'd0; end
end

// stage 1: the pixel's colour, its two candidates
reg        v1, v2;
reg [23:0] c1, c2;
reg  [1:0] bayer1, bayer2;
wire [10:0] h1 = c1[10:0] ^ c1[21:11] ^ {9'd0, c1[23:22]};
wire [10:0] h2 = {c1[4:0], c1[23:18]} ^ {c1[12:5], c1[15:13]} ^ {c1[17:16], 9'd0};
wire  [9:0] cand1 = ht1[h1];
wire  [9:0] cand2 = ht2[h2];
reg  [10:0] h1_2, h2_2;
reg   [9:0] cand1_2, cand2_2;

// frames, and an entry free to be given away
reg  [2:0] fcount;
reg  [9:0] scan;
reg  [9:0] free_idx;
reg        free_valid;
reg        way;              // which table the next new colour goes into
reg [19:0] fixed_count;
wire [2:0] scan_age = fcount - stamp[scan];

// stage 2: which entry
wire hit1 = (a_q == c2) && (cand1_2 < ENTRIES);
wire hit2 = (b_q == c2) && (cand2_2 < ENTRIES);
wire hit  = hit1 | hit2;
wire [9:0] hit_idx = hit1 ? cand1_2 : cand2_2;
wire alloc = v2 & ~hit & free_valid;

// the fixed colours: 3 + 3 + 2 bits with an ordered dither
wire  [7:0] thr = {bayer2, 6'd24};                 // 24, 88, 152, 216
wire [10:0] qr = c2[23:16] * 3'd7 + {3'd0, thr};
wire [10:0] qg = c2[15:8]  * 3'd7 + {3'd0, thr};
wire  [9:0] qb = c2[7:0]   * 2'd3 + {2'd0, ~bayer2, 6'd24};
wire  [9:0] fixed_idx = {2'b11, qr[10:8], qg[10:8], qb[9:8]};

always @* begin
	a_we   = alloc;
	a_addr = alloc ? free_idx : cand1;
	b_addr = cand2;
end

always @(posedge clk) begin
	if (a_we) pal[a_addr] <= c2;
	a_q <= pal[a_addr];
end
always @(posedge clk) b_q <= pal[b_addr];

always @(posedge clk) begin
	out_de <= 1'b0;
	pal_we <= 1'b0;

	// stage 1
	v1 <= in_de;
	if (in_de) begin
		c1     <= {in_r, in_g, in_b};
		bayer1 <= in_bayer;
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

	// the entry scan: one entry a clock while none is at hand
	if (!free_valid) begin
		// (not the entry a pixel is using in this very clock)
		if (scan_age[2] && !(v2 && hit && hit_idx == scan)) begin
			free_idx   <= scan;
			free_valid <= 1'b1;
		end
		scan <= (scan == ENTRIES - 10'd1) ? 10'd0 : scan + 10'd1;
	end

	if (v2) begin
		out_de <= 1'b1;
		if (hit) begin
			out_index      <= hit_idx;
			stamp[hit_idx] <= fcount;
			// (the entry at hand is in use after all)
			if (free_valid && hit_idx == free_idx) free_valid <= 1'b0;
		end
		else if (free_valid) begin
			out_index       <= free_idx;
			stamp[free_idx] <= fcount;
			if (way) ht2[h2_2] <= free_idx; else ht1[h1_2] <= free_idx;
			way        <= ~way;
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
		fcount       <= fcount + 3'd1;
		fixed_pixels <= fixed_count;
		fixed_count  <= 20'd0;
		// (ages are counted from the new frame: look again)
		free_valid   <= 1'b0;
	end

	if (reset) begin
		v1           <= 1'b0;
		v2           <= 1'b0;
		fcount       <= 3'd4;
		scan         <= 10'd0;
		free_valid   <= 1'b0;
		way          <= 1'b0;
		fixed_count  <= 20'd0;
		fixed_pixels <= 20'd0;
		out_index    <= 10'd0;
	end
end

endmodule
