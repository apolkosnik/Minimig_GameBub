// Game Bub Minimig: Game Bub controllers -> Amiga joysticks, mouse and
// keyboard (framework InputExtendedV0, two slots).
//
// Slot 0 (the handheld's buttons, or the first dock controller):
//   D-pad, left stick  joystick (port 2) directions (stick beyond +-64)
//   A / B          joystick fire 1 / fire 2, or as the A / B buttons
//                  setting puts them (pad_ab): 1 fire 1 / up, 2 up / fire 1,
//                  3 fire 2 / fire 1
//   right stick    moves the mouse (port 1)
//   L (held)       D-pad moves the mouse (port 1), A = left, B = right button
//   R              left mouse button (for dragging while L is held)
//   host mouse     a USB/Bluetooth mouse reported by the firmware fork
//                  (gb_host 0x1030/0x1034) moves the port 1 mouse too; a
//                  second one (0x1020/0x1024) is the mouse in port 2
//   X, Y, Start,   Amiga keys (raw key codes from the settings,
//   Select         defaults Space, Return, F1, Esc), or with a setting of
//                  8'h80, 8'h81, 8'h82 the joystick's fire 1, fire 2, up
//                  (port 2; no key event)
//   host keyboard  a USB keyboard on the dock, reported by the firmware
//                  fork as key events (gb_host 0x1038: USB HID usage,
//                  pressed / released), is the Amiga's keyboard: the usages
//                  are translated to Amiga raw key codes here. Caps Lock
//                  toggles as on an Amiga keyboard (key down when it goes
//                  on, key up when it goes off). The Windows keys are the
//                  Amiga keys, Insert and F12 are Help, Num Lock and
//                  Scroll Lock the keypad's ( and ).
// Slot 1 (a second dock controller, when present):
//   D-pad, left stick, A, B   the joystick in port 1, A and B as the
//                  setting puts them (pad_ab) (minimig switches port 1
//                  from the mouse to the joystick when its fire button is
//                  pressed, and back on a left mouse click, as on MiSTer)
//   right stick, L + D-pad, R   the mouse in port 2, as slot 0's is the
//                  mouse in port 1
//
// So there are two players: A with the joystick in port 2 and the mouse in
// port 1, B with the joystick in port 1 and the mouse in port 2. Port 2 is
// the joystick while player A's is used and the mouse once player B's is
// (p2_mouse). The Ports setting (ports) swaps the controllers, the host
// mice, or gives both host mice to one player.
//
// Mouse and keyboard events go to minimig the way hps_ext.v delivers them
// on MiSTer: kbd_mouse_type 0 = X delta, 1 = Y delta, 2 = Amiga key code
// (bit 7 = key up), each event toggles kbd_mouse_level. Mouse motion is
// always sent as an X event followed by a Y event (either may be 0), as
// Main_MiSTer does: userio takes a second Y event in a row as the wheel,
// and so the host mouse's wheel is sent, after an X and a Y event (of no
// motion when the mouse stands still).
//
// joy_port2 is the joystick in the Amiga's port 2 (the game port); minimig
// takes it on _joy1 (MiSTer's first joystick), port 1 on _joy2.
//
// SPDX-License-Identifier: GPL-3.0-or-later

module gb_input
#(
	parameter CLK_HZ = 28385416
)
(
	input             clk,
	input             reset,

	input             btn_a, btn_b, btn_x, btn_y,
	input             btn_up, btn_down, btn_left, btn_right,
	input             btn_l, btn_r, btn_start, btn_select,
	input signed [7:0] stick_lx, stick_ly,   // slot 0 sticks, -127..127, right / down positive
	input signed [7:0] stick_rx, stick_ry,

	input             p1_active,              // slot 1: a second controller
	input             p1_a, p1_b,
	input             p1_up, p1_down, p1_left, p1_right,
	input             p1_l, p1_r,
	input signed [7:0] p1_lx, p1_ly,
	input signed [7:0] p1_rx, p1_ry,

	input       [2:0] ports,         // bit 0 the dock mice swapped, bit 1 the controllers swapped, bit 2 the dock mice as one

	input       [1:0] pad_ab,        // A / B: 0 fire 1 / fire 2, 1 fire 1 / up, 2 up / fire 1, 3 fire 2 / fire 1
	input       [7:0] key_x,         // an Amiga key code, or 8'h80 fire 1, 8'h81 fire 2, 8'h82 up
	input       [7:0] key_y,
	input       [7:0] key_start,
	input       [7:0] key_select,

	input             hmouse_valid,  // one clock per host mouse report
	input      [15:0] hmouse_dx,     // signed, right positive
	input      [15:0] hmouse_dy,     // signed, down positive
	input       [2:0] hmouse_btn,    // {middle, right, left}
	input             hwheel_valid,  // one clock per host wheel report
	input       [7:0] hwheel,        // signed, away from the user positive
	input             hmouse2_valid, // the second host mouse, as the first
	input      [15:0] hmouse2_dx,
	input      [15:0] hmouse2_dy,
	input       [2:0] hmouse2_btn,
	input             hwheel2_valid,
	input       [7:0] hwheel2,

	input             hkey_valid,    // one clock per host key event
	input       [7:0] hkey_usage,    // USB HID keyboard usage
	input             hkey_down,

	output     [15:0] joy_port1,     // active high, MiSTer bit order
	output     [15:0] joy_port2,     // active high (the game port)
	output      [2:0] mouse_btn,     // {middle, right, left}
	output reg  [7:0] kbd_mouse_data,
	output reg  [1:0] kbd_mouse_type,
	output reg        kbd_mouse_level
);

localparam MOUSE_TICK = CLK_HZ / 200;   // 5 ms between mouse moves
localparam QUAD_TICK  = CLK_HZ / 5208;  // between two counts of the port 2 mouse (the port 1 mouse's rate in userio)
localparam KEY_GAP    = CLK_HZ / 100;   // 10 ms between key events
localparam EV_GAP     = 256;            // clocks between any two events
localparam signed [7:0] STICK_ON  = 8'sd64;    // stick as a digital direction
localparam signed [7:0] STICK_DZ  = 8'sd16;    // right stick dead zone (mouse)

wire mm0 = btn_l;                  // L held: the D-pad is the player's mouse
wire mm1 = p1_active & p1_l;
wire mouse_swap = ports[0];
wire pad_swap   = ports[1];
wire mice_one   = ports[2];

// directions with the left stick added
wire s0_up    = btn_up    | (stick_ly < -STICK_ON);
wire s0_down  = btn_down  | (stick_ly >  STICK_ON);
wire s0_left  = btn_left  | (stick_lx < -STICK_ON);
wire s0_right = btn_right | (stick_lx >  STICK_ON);
wire s1_up    = p1_active & (p1_up    | (p1_ly < -STICK_ON));
wire s1_down  = p1_active & (p1_down  | (p1_ly >  STICK_ON));
wire s1_left  = p1_active & (p1_left  | (p1_lx < -STICK_ON));
wire s1_right = p1_active & (p1_right | (p1_lx >  STICK_ON));

// A and B as the setting puts them: {up, fire 2, fire 1}
function automatic [2:0] ab_map(input [1:0] m, input a, input b);
	case (m)
		2'd0: ab_map = {1'b0, b, a};          // fire 1 / fire 2
		2'd1: ab_map = {b, 1'b0, a};          // fire 1 / up
		2'd2: ab_map = {a, 1'b0, b};          // up / fire 1
		default: ab_map = {1'b0, a, b};       // fire 2 / fire 1
	endcase
endfunction
// X, Y, Start, Select set to a joystick button (key code 8'h80 up): {up, fire 2, fire 1}
wire [3:0] kbtn = {btn_select, btn_start, btn_y, btn_x};
wire [3:0] kjoy = {key_select[7], key_start[7], key_y[7], key_x[7]};   // a joystick button, not a key
wire [2:0] kj_bits;
function automatic [2:0] kj_one(input [7:0] c, input pressed);
	kj_one = (pressed && c[7]) ? ((c[1:0] == 2'd0) ? 3'b001 : (c[1:0] == 2'd1) ? 3'b010 :
	                              (c[1:0] == 2'd2) ? 3'b100 : 3'b000) : 3'b000;
endfunction
assign kj_bits = kj_one(key_x, btn_x) | kj_one(key_y, btn_y) |
                 kj_one(key_start, btn_start) | kj_one(key_select, btn_select);
wire [2:0] s0_ab = ab_map(pad_ab, btn_a, btn_b) | kj_bits;
wire [2:0] s1_ab = p1_active ? ab_map(pad_ab, p1_a, p1_b) : 3'b000;
wire       s0_upj = s0_up | s0_ab[2];
wire       s1_upj = s1_up | s1_ab[2];

// joystick bits: 0 right, 1 left, 2 down, 3 up, 4 fire 1, 5 fire 2
wire [5:0] j0 = mm0 ? 6'd0 :
                {s0_ab[1], s0_ab[0], s0_upj & ~s0_down, s0_down, s0_left & ~s0_right, s0_right};
wire [5:0] j1 = mm1 ? 6'd0 :
                {s1_ab[1], s1_ab[0], s1_upj & ~s1_down, s1_down, s1_left & ~s1_right, s1_right};
// a controller's mouse buttons {middle, right, left}
wire [2:0] pm0 = {1'b0, mm0 & btn_b, (mm0 & btn_a) | btn_r};
wire [2:0] pm1 = p1_active ? {1'b0, mm1 & p1_b, (mm1 & p1_a) | p1_r} : 3'd0;

// The two players. Player A: joystick in port 2, mouse in port 1; player
// B: joystick in port 1, mouse in port 2. Slot 0 is player A's controller
// and slot 1 player B's, or the other way round (pad_swap); the first host
// mouse is player A's and the second player B's, or the other way round
// (mouse_swap), or both are one player's (mice_one: A's, with mouse_swap
// B's).
wire [5:0] jA  = pad_swap ? j1 : j0;
wire [5:0] jB  = pad_swap ? j0 : j1;
wire [2:0] pmA = pad_swap ? pm1 : pm0;
wire [2:0] pmB = pad_swap ? pm0 : pm1;
wire       m1_a = ~mouse_swap;              // the first host mouse is player A's
wire       m2_a = mice_one ^ mouse_swap;    // the second
wire [2:0] mbA = pmA | (m1_a ? hmouse_btn : 3'd0) | (m2_a ? hmouse2_btn : 3'd0);
wire [2:0] mbB = pmB | (m1_a ? 3'd0 : hmouse_btn) | (m2_a ? 3'd0 : hmouse2_btn);

// Port 2 is the joystick or the mouse, whichever was used last (port 1 is
// switched in userio: the joystick's fire button, the mouse's left
// button). As a mouse its lines are a mouse's: the quadrature pairs
// H / HQ on down / right and V / VQ on up / left (userio counts them into
// JOY1DAT as Denise does), the left button on fire 1, the right on fire 2.
reg        p2_mouse;
reg  [1:0] qx, qy;           // the quadrature phases: JOY1DAT's bits 1:0 and 9:8
wire [5:0] p2_quad = {mbB[1], mbB[0], qy[1] ^ qy[0], qx[1] ^ qx[0], qy[1], qx[1]};

assign joy_port2 = {10'd0, p2_mouse ? p2_quad : jA};
assign joy_port1 = {10'd0, jB};
assign mouse_btn = mbA;

// ------------------------------------------------------------- mouse
reg [$clog2(MOUSE_TICK+1)-1:0] mtick;
reg  [7:0] held0, held1;     // ticks a D-pad has been held (acceleration)
reg signed [15:0] acc_x, acc_y;   // port 1: motion not yet sent to the Amiga
reg signed [15:0] acc2_x, acc2_y; // port 2: motion not yet stepped out
reg [$clog2(QUAD_TICK+1)-1:0] qtick;
reg        y_next;                // the X half of a motion was sent, Y follows
reg signed [7:0] acc_w;           // wheel clicks not yet sent
reg        z_next;                // X and Y were sent, the wheel follows

// signed saturation to 16 bits
function automatic signed [15:0] sat16(input signed [17:0] v);
	sat16 = (v > 18'sd32767) ? 16'sd32767 : (v < -18'sd32768) ? -16'sd32768 : v[15:0];
endfunction
// the part of an accumulated motion sent in one event (-127..127)
function automatic signed [7:0] chunk(input signed [15:0] v);
	chunk = (v > 16'sd127) ? 8'sd127 : (v < -16'sd127) ? -8'sd127 : v[7:0];
endfunction

// signed saturation to -127..127
function automatic signed [7:0] sat8(input signed [8:0] v);
	sat8 = (v > 9'sd127) ? 8'sd127 : (v < -9'sd127) ? -8'sd127 : v[7:0];
endfunction

// a controller as a mouse, counts per tick: the right stick past its dead
// zone (up to 7), and the D-pad while L is held (faster the longer)
function automatic [3:0] dspeed(input [7:0] h);
	dspeed = (h < 8'd8) ? 4'd1 : (h < 8'd24) ? 4'd2 : (h < 8'd48) ? 4'd4 : 4'd6;
endfunction
function automatic signed [8:0] pad_v(input signed [7:0] stick, input mm, input neg, input pos, input [3:0] sp);
	reg signed [8:0] v;
	begin
		v = 9'sd0;
		if (stick > STICK_DZ || stick < -STICK_DZ) v = $signed({stick[7], stick}) >>> 4;
		if (mm && (neg ^ pos)) v = pos ? v + $signed({5'd0, sp}) : v - $signed({5'd0, sp});
		pad_v = v;
	end
endfunction
wire       dir0 = mm0 & (btn_up | btn_down | btn_left | btn_right);
wire       dir1 = mm1 & (p1_up | p1_down | p1_left | p1_right);
wire signed [8:0] v0x = pad_v(stick_rx, mm0, btn_left, btn_right, dspeed(held0));
wire signed [8:0] v0y = pad_v(stick_ry, mm0, btn_up,   btn_down,  dspeed(held0));
wire signed [8:0] v1x = p1_active ? pad_v(p1_rx, mm1, p1_left, p1_right, dspeed(held1)) : 9'sd0;
wire signed [8:0] v1y = p1_active ? pad_v(p1_ry, mm1, p1_up,   p1_down,  dspeed(held1)) : 9'sd0;
wire signed [8:0] vAx = pad_swap ? v1x : v0x;
wire signed [8:0] vAy = pad_swap ? v1y : v0y;
wire signed [8:0] vBx = pad_swap ? v0x : v1x;
wire signed [8:0] vBy = pad_swap ? v0y : v1y;

// what makes port 2 the joystick, and what the mouse: player A's joystick
// (any direction or button, while held), else player B's mouse (a host
// mouse moved, a button, the D-pad with L, the right stick well out)
function automatic far(input signed [7:0] v);
	far = (v > STICK_ON) || (v < -STICK_ON);
endfunction
wire       padB_far = pad_swap ? (far(stick_rx) | far(stick_ry) | dir0)
                               : (p1_active & (far(p1_rx) | far(p1_ry))) | dir1;
wire       hm1_moved = hmouse_valid  && (hmouse_dx  != 16'd0 || hmouse_dy  != 16'd0);
wire       hm2_moved = hmouse2_valid && (hmouse2_dx != 16'd0 || hmouse2_dy != 16'd0);
wire       joyA_act = |jA;
wire       mouseB_act = (|mbB) | padB_far | (hm1_moved & ~m1_a) | (hm2_moved & ~m2_a);

// ------------------------------------------------------------- keys
reg  [3:0] kprev;            // {select, start, y, x}
reg  [3:0] kdown_pend, kup_pend;
reg [$clog2(KEY_GAP+1)-1:0] kgap;
reg [8:0]  evgap;

// (a button set to a joystick button sends no key)
wire [3:0] know = kbtn & ~kjoy;

function automatic [7:0] keycode(input [1:0] k);
	case (k)
		2'd0: keycode = key_x;
		2'd1: keycode = key_y;
		2'd2: keycode = key_start;
		default: keycode = key_select;
	endcase
endfunction

// ------------------------------------------------------ host keyboard
// USB HID usage -> Amiga raw key code (8'hFF: no such key)
function automatic [7:0] hid2amiga(input [7:0] u);
	case (u)
		8'h04: hid2amiga = 8'h20;  // A
		8'h05: hid2amiga = 8'h35;  // B
		8'h06: hid2amiga = 8'h33;  // C
		8'h07: hid2amiga = 8'h22;  // D
		8'h08: hid2amiga = 8'h12;  // E
		8'h09: hid2amiga = 8'h23;  // F
		8'h0A: hid2amiga = 8'h24;  // G
		8'h0B: hid2amiga = 8'h25;  // H
		8'h0C: hid2amiga = 8'h17;  // I
		8'h0D: hid2amiga = 8'h26;  // J
		8'h0E: hid2amiga = 8'h27;  // K
		8'h0F: hid2amiga = 8'h28;  // L
		8'h10: hid2amiga = 8'h37;  // M
		8'h11: hid2amiga = 8'h36;  // N
		8'h12: hid2amiga = 8'h18;  // O
		8'h13: hid2amiga = 8'h19;  // P
		8'h14: hid2amiga = 8'h10;  // Q
		8'h15: hid2amiga = 8'h13;  // R
		8'h16: hid2amiga = 8'h21;  // S
		8'h17: hid2amiga = 8'h14;  // T
		8'h18: hid2amiga = 8'h16;  // U
		8'h19: hid2amiga = 8'h34;  // V
		8'h1A: hid2amiga = 8'h11;  // W
		8'h1B: hid2amiga = 8'h32;  // X
		8'h1C: hid2amiga = 8'h15;  // Y
		8'h1D: hid2amiga = 8'h31;  // Z
		8'h1E: hid2amiga = 8'h01;  // 1
		8'h1F: hid2amiga = 8'h02;
		8'h20: hid2amiga = 8'h03;
		8'h21: hid2amiga = 8'h04;
		8'h22: hid2amiga = 8'h05;
		8'h23: hid2amiga = 8'h06;
		8'h24: hid2amiga = 8'h07;
		8'h25: hid2amiga = 8'h08;
		8'h26: hid2amiga = 8'h09;  // 9
		8'h27: hid2amiga = 8'h0A;  // 0
		8'h28: hid2amiga = 8'h44;  // Return
		8'h29: hid2amiga = 8'h45;  // Esc
		8'h2A: hid2amiga = 8'h41;  // Backspace
		8'h2B: hid2amiga = 8'h42;  // Tab
		8'h2C: hid2amiga = 8'h40;  // Space
		8'h2D: hid2amiga = 8'h0B;  // -
		8'h2E: hid2amiga = 8'h0C;  // =
		8'h2F: hid2amiga = 8'h1A;  // [
		8'h30: hid2amiga = 8'h1B;  // ]
		8'h31: hid2amiga = 8'h0D;  // backslash
		8'h32: hid2amiga = 8'h2B;  // the key beside Return (international)
		8'h33: hid2amiga = 8'h29;  // ;
		8'h34: hid2amiga = 8'h2A;  // '
		8'h35: hid2amiga = 8'h00;  // `
		8'h36: hid2amiga = 8'h38;  // ,
		8'h37: hid2amiga = 8'h39;  // .
		8'h38: hid2amiga = 8'h3A;  // /
		8'h39: hid2amiga = 8'h62;  // Caps Lock
		8'h3A: hid2amiga = 8'h50;  // F1
		8'h3B: hid2amiga = 8'h51;
		8'h3C: hid2amiga = 8'h52;
		8'h3D: hid2amiga = 8'h53;
		8'h3E: hid2amiga = 8'h54;
		8'h3F: hid2amiga = 8'h55;
		8'h40: hid2amiga = 8'h56;
		8'h41: hid2amiga = 8'h57;
		8'h42: hid2amiga = 8'h58;
		8'h43: hid2amiga = 8'h59;  // F10
		8'h45: hid2amiga = 8'h5F;  // F12: Help
		8'h47: hid2amiga = 8'h5B;  // Scroll Lock: keypad )
		8'h49: hid2amiga = 8'h5F;  // Insert: Help
		8'h4C: hid2amiga = 8'h46;  // Delete
		8'h4F: hid2amiga = 8'h4E;  // Right
		8'h50: hid2amiga = 8'h4F;  // Left
		8'h51: hid2amiga = 8'h4D;  // Down
		8'h52: hid2amiga = 8'h4C;  // Up
		8'h53: hid2amiga = 8'h5A;  // Num Lock: keypad (
		8'h54: hid2amiga = 8'h5C;  // keypad /
		8'h55: hid2amiga = 8'h5D;  // keypad *
		8'h56: hid2amiga = 8'h4A;  // keypad -
		8'h57: hid2amiga = 8'h5E;  // keypad +
		8'h58: hid2amiga = 8'h43;  // keypad Enter
		8'h59: hid2amiga = 8'h1D;  // keypad 1
		8'h5A: hid2amiga = 8'h1E;
		8'h5B: hid2amiga = 8'h1F;
		8'h5C: hid2amiga = 8'h2D;
		8'h5D: hid2amiga = 8'h2E;
		8'h5E: hid2amiga = 8'h2F;
		8'h5F: hid2amiga = 8'h3D;
		8'h60: hid2amiga = 8'h3E;
		8'h61: hid2amiga = 8'h3F;  // keypad 9
		8'h62: hid2amiga = 8'h0F;  // keypad 0
		8'h63: hid2amiga = 8'h3C;  // keypad .
		8'h64: hid2amiga = 8'h30;  // the key beside the left Shift (international)
		8'h65: hid2amiga = 8'h67;  // Menu: right Amiga
		8'hE0: hid2amiga = 8'h63;  // left Ctrl
		8'hE1: hid2amiga = 8'h60;  // left Shift
		8'hE2: hid2amiga = 8'h64;  // left Alt
		8'hE3: hid2amiga = 8'h66;  // left GUI: left Amiga
		8'hE4: hid2amiga = 8'h63;  // right Ctrl
		8'hE5: hid2amiga = 8'h61;  // right Shift
		8'hE6: hid2amiga = 8'h65;  // right Alt
		8'hE7: hid2amiga = 8'h67;  // right GUI: right Amiga
		default: hid2amiga = 8'hFF;
	endcase
endfunction

// events wait here for the keyboard channel: {key up, raw key code}
reg  [7:0] kq [0:31];
reg  [5:0] kq_wr, kq_rd;
reg        caps_on;
wire       kq_empty = (kq_wr == kq_rd);
wire       kq_full  = (kq_wr[4:0] == kq_rd[4:0]) && (kq_wr[5] != kq_rd[5]);
wire [7:0] hk_code  = hid2amiga(hkey_usage);
wire       hk_caps  = (hkey_usage == 8'h39);
wire [7:0] kq_out   = kq[kq_rd[4:0]];

integer i;
reg found;
reg [1:0] fk;
reg       fup;

always @* begin
	found = 1'b0; fk = 2'd0; fup = 1'b0;
	for (i = 3; i >= 0; i = i - 1) begin
		if (kup_pend[i])   begin found = 1'b1; fk = i[1:0]; fup = 1'b1; end
		if (kdown_pend[i]) begin found = 1'b1; fk = i[1:0]; fup = 1'b0; end
	end
end

always @(posedge clk) begin
	if (reset) begin
		mtick           <= '0;
		held0           <= 8'd0;
		held1           <= 8'd0;
		acc_x           <= 16'sd0;
		acc_y           <= 16'sd0;
		acc2_x          <= 16'sd0;
		acc2_y          <= 16'sd0;
		qtick           <= '0;
		qx              <= 2'd0;
		qy              <= 2'd0;
		p2_mouse        <= 1'b0;
		y_next          <= 1'b0;
		acc_w           <= 8'sd0;
		z_next          <= 1'b0;
		kprev           <= 4'd0;
		kdown_pend      <= 4'd0;
		kup_pend        <= 4'd0;
		kgap            <= '0;
		evgap           <= '0;
		kbd_mouse_level <= 1'b0;
		kbd_mouse_type  <= 2'd0;
		kbd_mouse_data  <= 8'd0;
		kq_wr           <= 6'd0;
		kq_rd           <= 6'd0;
		caps_on         <= 1'b0;
	end
	else begin
		// host keyboard events into the queue. Caps Lock: pressing it
		// turns the lock on (key down) or off (key up), releasing it does
		// nothing
		if (hkey_valid && hk_code != 8'hFF && !kq_full && !(hk_caps && !hkey_down)) begin
			if (hk_caps) begin
				kq[kq_wr[4:0]] <= {caps_on, hk_code[6:0]};
				caps_on        <= ~caps_on;
			end
			else kq[kq_wr[4:0]] <= {~hkey_down, hk_code[6:0]};
			kq_wr <= kq_wr + 6'd1;
		end

		// key edges
		kprev <= know;
		for (i = 0; i < 4; i = i + 1) begin
			if (know[i] & ~kprev[i]) kdown_pend[i] <= 1'b1;
			if (~know[i] & kprev[i]) kup_pend[i]   <= 1'b1;
		end

		// port 2: the joystick while it is used, the mouse once that is
		if (joyA_act)        p2_mouse <= 1'b0;
		else if (mouseB_act) p2_mouse <= 1'b1;

		// mouse movement: the controllers (right stick, D-pad in mouse
		// mode) and the host reports add up, player A's in acc_x/acc_y
		// (port 1: events take out at most 127 counts at a time), player
		// B's in acc2_x/acc2_y (port 2: one count per axis every QUAD_TICK)
		begin : mouse_events
			reg signed [17:0] ax, ay, bx, by;
			reg signed  [7:0] cx, cy;
			reg signed  [8:0] aw;
			reg               send_key, send_x, send_y, send_z, send_hkey;
			cx = chunk(acc_x);
			cy = chunk(acc_y);
			ax = {{2{acc_x[15]}}, acc_x};
			ay = {{2{acc_y[15]}}, acc_y};
			aw = {acc_w[7], acc_w};
			bx = {{2{acc2_x[15]}}, acc2_x};
			by = {{2{acc2_y[15]}}, acc2_y};
			if (hwheel_valid  && m1_a) aw = aw + {hwheel[7], hwheel};
			if (hwheel2_valid && m2_a) aw = aw + {hwheel2[7], hwheel2};

			if (mtick != '0) mtick <= mtick - 1'd1;
			else begin
				mtick <= MOUSE_TICK[$bits(mtick)-1:0];
				ax = ax + {{9{vAx[8]}}, vAx};
				ay = ay + {{9{vAy[8]}}, vAy};
				bx = bx + {{9{vBx[8]}}, vBx};
				by = by + {{9{vBy[8]}}, vBy};
				if (dir0) begin if (held0 != 8'hFF) held0 <= held0 + 8'd1; end
				else held0 <= 8'd0;
				if (dir1) begin if (held1 != 8'hFF) held1 <= held1 + 8'd1; end
				else held1 <= 8'd0;
			end
			if (hmouse_valid) begin
				if (m1_a) begin
					ax = ax + {{2{hmouse_dx[15]}}, hmouse_dx};
					ay = ay + {{2{hmouse_dy[15]}}, hmouse_dy};
				end
				else begin
					bx = bx + {{2{hmouse_dx[15]}}, hmouse_dx};
					by = by + {{2{hmouse_dy[15]}}, hmouse_dy};
				end
			end
			if (hmouse2_valid) begin
				if (m2_a) begin
					ax = ax + {{2{hmouse2_dx[15]}}, hmouse2_dx};
					ay = ay + {{2{hmouse2_dy[15]}}, hmouse2_dy};
				end
				else begin
					bx = bx + {{2{hmouse2_dx[15]}}, hmouse2_dx};
					by = by + {{2{hmouse2_dy[15]}}, hmouse2_dy};
				end
			end

			// port 2: a count is one step of the quadrature phase (right and
			// down count up, as on port 1); what moved while the joystick
			// has the port is dropped
			if (qtick != '0) qtick <= qtick - 1'd1;
			else begin
				qtick <= QUAD_TICK[$bits(qtick)-1:0];
				if (p2_mouse) begin
					if (bx > 18'sd0)      begin qx <= qx + 2'd1; bx = bx - 18'sd1; end
					else if (bx < 18'sd0) begin qx <= qx - 2'd1; bx = bx + 18'sd1; end
					if (by > 18'sd0)      begin qy <= qy + 2'd1; by = by - 18'sd1; end
					else if (by < 18'sd0) begin qy <= qy - 2'd1; by = by + 18'sd1; end
				end
			end
			// (the phases start at rest, the joystick's idle lines, so the
			// counters do not jump when the mouse takes the port)
			if (!p2_mouse) begin
				qx <= 2'd0;
				qy <= 2'd0;
			end
			if (joyA_act) begin
				bx = 18'sd0;
				by = 18'sd0;
			end
			acc2_x <= sat16(bx);
			acc2_y <= sat16(by);

			if (kgap != '0) kgap <= kgap - 1'd1;

			// one event at a time
			// a motion is an X event and then a Y event, and then with wheel
			// clicks waiting a third for them, nothing between
			send_hkey = (evgap == 9'd0) && !y_next && !z_next && !kq_empty && kgap == '0;
			send_key = (evgap == 9'd0) && !y_next && !z_next && !send_hkey && found && kgap == '0;
			send_x   = (evgap == 9'd0) && !y_next && !z_next && !send_hkey && !send_key
			           && (acc_x != 16'sd0 || acc_y != 16'sd0 || acc_w != 8'sd0);
			send_y   = (evgap == 9'd0) && y_next;
			send_z   = (evgap == 9'd0) && z_next;

			if (evgap != 9'd0) evgap <= evgap - 9'd1;
			if (send_hkey) begin
				kbd_mouse_type  <= 2'd2;
				kbd_mouse_data  <= kq_out;
				kbd_mouse_level <= ~kbd_mouse_level;
				kq_rd <= kq_rd + 6'd1;
				kgap  <= KEY_GAP[$bits(kgap)-1:0];
				evgap <= EV_GAP[8:0];
			end
			else if (send_key) begin
				kbd_mouse_type  <= 2'd2;
				kbd_mouse_data  <= keycode(fk) | (fup ? 8'h80 : 8'h00);
				kbd_mouse_level <= ~kbd_mouse_level;
				if (fup) kup_pend[fk] <= 1'b0; else kdown_pend[fk] <= 1'b0;
				kgap  <= KEY_GAP[$bits(kgap)-1:0];
				evgap <= EV_GAP[8:0];
			end
			else if (send_x) begin
				kbd_mouse_type  <= 2'd0;
				kbd_mouse_data  <= cx;
				kbd_mouse_level <= ~kbd_mouse_level;
				ax = ax - {{10{cx[7]}}, cx};
				y_next <= 1'b1;
				evgap <= EV_GAP[8:0];
			end
			else if (send_y) begin
				kbd_mouse_type  <= 2'd1;
				kbd_mouse_data  <= cy;
				kbd_mouse_level <= ~kbd_mouse_level;
				ay = ay - {{10{cy[7]}}, cy};
				y_next <= 1'b0;
				z_next <= acc_w != 8'sd0;
				evgap <= EV_GAP[8:0];
			end
			else if (send_z) begin
				kbd_mouse_type  <= 2'd1;
				kbd_mouse_data  <= acc_w;
				kbd_mouse_level <= ~kbd_mouse_level;
				aw = aw - {acc_w[7], acc_w};
				z_next <= 1'b0;
				evgap <= EV_GAP[8:0];
			end

			acc_x <= sat16(ax);
			acc_y <= sat16(ay);
			acc_w <= sat8(aw);
		end
	end
end

endmodule
