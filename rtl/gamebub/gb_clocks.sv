// Game Bub Minimig: clock generation.
//
// 50 MHz * 54.5 / 3 = 908.333 MHz VCO (PFD 16.67 MHz)
//   CLKOUT0  /8   113.542 MHz  SDRAM controller        (4 x clk_sys, aligned)
//   CLKOUT1  /32   28.385 MHz  Amiga / system clock    (PAL 28.375 +0.036 %)
//   CLKOUT2  /5   181.667 MHz  host SPI (>= 160 MHz required)
//   CLKOUT3  /N   display clock (N from MinimigCore.scala)
//   CLKOUT4  /8   113.542 MHz  SDRAM clock, clk_114 delayed by 39.375 deg
//                 (0.963 ns, 7 steps of 1/8 VCO period): drives only the ODDR
//                 that forwards it (inverted) to the SDRAM pins; the delay
//                 centres the command and read data windows (minimig.xdc)
//
// SPDX-License-Identifier: GPL-3.0-or-later

module gb_clocks
#(
	parameter integer DISPLAY_DIVIDER = 35
)
(
	input  wire clk_in_50mhz,
	output wire clk_114,
	output wire clk_sys,
	output wire clk_sdram,
	output wire clk_display,
	output wire clk_spi,
	output wire locked
);

wire clk_fb, clk_fb_buf;
wire clk_114_u, clk_sys_u, clk_sdram_u;

MMCME2_BASE #(
	.BANDWIDTH          ("OPTIMIZED"),
	.CLKIN1_PERIOD      (20.000),
	.DIVCLK_DIVIDE      (3),
	.CLKFBOUT_MULT_F    (54.500),
	.CLKFBOUT_PHASE     (0.0),

	.CLKOUT0_DIVIDE_F   (8.000),
	.CLKOUT1_DIVIDE     (32),
	.CLKOUT2_DIVIDE     (5),
	.CLKOUT3_DIVIDE     (DISPLAY_DIVIDER),
	.CLKOUT4_DIVIDE     (8),

	.CLKOUT0_PHASE      (0.0),
	.CLKOUT1_PHASE      (0.0),
	.CLKOUT2_PHASE      (0.0),
	.CLKOUT3_PHASE      (0.0),
	.CLKOUT4_PHASE      (39.375),

	.CLKOUT0_DUTY_CYCLE (0.5),
	.CLKOUT1_DUTY_CYCLE (0.5),
	.CLKOUT2_DUTY_CYCLE (0.5),
	.CLKOUT3_DUTY_CYCLE (0.5),
	.CLKOUT4_DUTY_CYCLE (0.5),

	.STARTUP_WAIT       ("FALSE")
) mmcm (
	.CLKOUT0   (clk_114_u),
	.CLKOUT0B  (),
	.CLKOUT1   (clk_sys_u),
	.CLKOUT1B  (),
	.CLKOUT2   (clk_spi),
	.CLKOUT2B  (),
	.CLKOUT3   (clk_display),
	.CLKOUT3B  (),
	.CLKOUT4   (clk_sdram_u),
	.CLKOUT5   (),
	.CLKOUT6   (),
	.CLKFBOUT  (clk_fb),
	.CLKFBOUTB (),
	.CLKFBIN   (clk_fb_buf),
	.LOCKED    (locked),
	.CLKIN1    (clk_in_50mhz),
	.PWRDWN    (1'b0),
	.RST       (1'b0)
);

// feedback through a BUFG keeps CLKOUT0/1 phase aligned with the input
// across the global clock tree, as both are used on BUFGs
BUFG bufg_fb  (.I(clk_fb),    .O(clk_fb_buf));
BUFG bufg_114 (.I(clk_114_u), .O(clk_114));
BUFG bufg_sys (.I(clk_sys_u), .O(clk_sys));
BUFG bufg_sdram (.I(clk_sdram_u), .O(clk_sdram));

endmodule
