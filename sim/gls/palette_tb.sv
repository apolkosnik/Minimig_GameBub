`timescale 1ns/1ps
// gb_palette RTL against its Vivado netlist (sim/gls/run_palette_gls.sh),
// reuse mode (no_reuse = 0): a fade of 256 colours over 16 frames (new
// colours every frame), then a still picture of the final 256 colours.
// The still frames must need no fixed colours, and the netlist must match
// the RTL on every clock. (Vivado once mapped the colour tables into block
// RAM with other timing than the RTL's: every simulation of the RTL was
// clean while the FPGA ran out of entries on still pictures.)
module tb;
reg clk = 0, reset = 1;
always #17.6 clk = ~clk;
reg in_de = 0, frame = 0, no_reuse = 0;
reg [7:0] r, g, b;
reg [1:0] bayer;
wire        de_a, de_b, we_a, we_b;
wire  [9:0] ix_a, ix_b, pi_a, pi_b;
wire [23:0] pc_a, pc_b;
wire [19:0] fx_a, fx_b;
gb_palette     rtl (.clk(clk), .reset(reset), .in_de(in_de), .in_r(r), .in_g(g), .in_b(b), .in_bayer(bayer), .frame(frame), .no_reuse(no_reuse),
                    .out_de(de_a), .out_index(ix_a), .pal_we(we_a), .pal_index(pi_a), .pal_color(pc_a), .fixed_pixels(fx_a));
net_gb_palette net (.clk(clk), .reset(reset), .in_de(in_de), .in_r(r), .in_g(g), .in_b(b), .in_bayer(bayer), .frame(frame), .no_reuse(no_reuse),
                    .out_de(de_b), .out_index(ix_b), .pal_we(we_b), .pal_index(pi_b), .pal_color(pc_b), .fixed_pixels(fx_b));
localparam PERIOD = 12000;      // clocks per frame
localparam ACTIVE = 10000;      // clocks with pixels (one pixel every two clocks)
localparam FADE   = 16;
localparam FRAMES = 40;
integer cyc = 0, bad = 0, fnum = 0, fixedpix = 0, statpix = 0, statfixed = 0;
reg [31:0] x = 32'h12345678;
reg [23:0] cols [0:255];
reg [23:0] c;
reg [7:0] k;
integer i, lvl;
initial begin
  for (i = 0; i < 256; i = i + 1) begin
    x = x ^ (x << 13); x = x ^ (x >> 17); x = x ^ (x << 5);
    cols[i] = x[23:0];
  end
  repeat (10) @(posedge clk);
  reset <= 0;
end
always @(posedge clk) if (!reset) begin
  cyc <= cyc + 1;
  in_de <= 0; frame <= 0;
  if (cyc % PERIOD == PERIOD - 100) begin
    frame <= 1;
    if (fnum >= FADE + 6) begin statfixed = statfixed + fixedpix; end
    $display("frame %0d: %0d fixed pixels (core count %0d)", fnum, fixedpix, fx_a);
    fixedpix = 0;
    fnum = fnum + 1;
    if (fnum == FRAMES) begin
      $display("RESULT: static frames %0d fixed pixels, %0d mismatching cycles", statfixed, bad);
      if (statfixed == 0 && bad == 0) $display("TEST PASSED");
      else $display("TEST FAILED");
      $finish;
    end
  end else if (cyc % PERIOD < ACTIVE && cyc[0]) begin
    k = (cyc % PERIOD) / 2;        // pixel 0..4999: colour index from the position
    k = k ^ (k >> 3) * 8'd37;
    lvl = (fnum < FADE) ? fnum + 1 : FADE;
    c = cols[k];
    r <= c[23:16] * lvl / FADE;
    g <= c[15:8] * lvl / FADE;
    b <= c[7:0] * lvl / FADE;
    bayer <= {cyc[1], cyc[2]};
    in_de <= 1;
  end
  if (de_a !== de_b || (de_a && ix_a !== ix_b) || we_a !== we_b || (we_a && (pi_a !== pi_b || pc_a !== pc_b))) begin
    if (bad < 10) $display("MISMATCH cycle %0d: de %b/%b index %h/%h we %b/%b pal %h=%h / %h=%h", cyc, de_a, de_b, ix_a, ix_b, we_a, we_b, pi_a, pc_a, pi_b, pc_b);
    bad = bad + 1;
  end
  if (de_a && ix_a[9:8] == 2'b11) fixedpix = fixedpix + 1;
end
endmodule
