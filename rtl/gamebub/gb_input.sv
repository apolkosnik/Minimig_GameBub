// Game Bub Minimig: Game Bub controllers -> Amiga joysticks, mouse and
// keyboard (framework InputExtendedV0, two slots).
//
// Slot 0 (the handheld's buttons, or the first dock controller):
//   D-pad, left stick  joystick (port 2) directions (stick beyond +-64)
//   A / B          joystick fire 1 / fire 2
//   right stick    moves the mouse (port 1)
//   L (held)       D-pad moves the mouse (port 1), A = left, B = right button
//   R              left mouse button (for dragging while L is held)
//   host mouse     a USB/Bluetooth mouse reported by the firmware fork
//                  (gb_host 0x1030/0x1034) moves the port 1 mouse too
//   X, Y, Start,   Amiga keys (raw key codes from the settings,
//   Select         defaults Space, Return, F1, Esc)
//   host keyboard  a USB keyboard on the dock, reported by the firmware
//                  fork as key events (gb_host 0x1038: USB HID usage,
//                  pressed / released), is the Amiga's keyboard: the usages
//                  are translated to Amiga raw key codes here. Caps Lock
//                  toggles as on an Amiga keyboard (key down when it goes
//                  on, key up when it goes off). The Windows keys are the
//                  Amiga keys, Insert and F12 are Help, Num Lock and
//                  Scroll Lock the keypad's ( and ).
// Slot 1 (a second dock controller, when present):
//   D-pad, left stick, A, B   the joystick in port 1 (minimig switches port 1
//                  from the mouse to the joystick when its fire button is
//                  pressed, and back on a left mouse click, as on MiSTer)
//
// Mouse and keyboard events go to minimig the way hps_ext.v delivers them
// on MiSTer: kbd_mouse_type 0 = X delta, 1 = Y delta, 2 = Amiga key code
// (bit 7 = key up), each event toggles kbd_mouse_level. Mouse motion is
// always sent as an X event followed by a Y event (either may be 0), as
// Main_MiSTer does: userio takes a second Y event in a row as the wheel.
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
	input signed [7:0] p1_lx, p1_ly,

	input       [7:0] key_x,
	input       [7:0] key_y,
	input       [7:0] key_start,
	input       [7:0] key_select,

	input             hmouse_valid,  // one clock per host mouse report
	input      [15:0] hmouse_dx,     // signed, right positive
	input      [15:0] hmouse_dy,     // signed, down positive
	input       [2:0] hmouse_btn,    // {middle, right, left}

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
localparam KEY_GAP    = CLK_HZ / 100;   // 10 ms between key events
localparam EV_GAP     = 256;            // clocks between any two events
localparam signed [7:0] STICK_ON  = 8'sd64;    // stick as a digital direction
localparam signed [7:0] STICK_DZ  = 8'sd16;    // right stick dead zone (mouse)

wire mouse_mode = btn_l;

// directions with the left stick added
wire s0_up    = btn_up    | (stick_ly < -STICK_ON);
wire s0_down  = btn_down  | (stick_ly >  STICK_ON);
wire s0_left  = btn_left  | (stick_lx < -STICK_ON);
wire s0_right = btn_right | (stick_lx >  STICK_ON);
wire s1_up    = p1_active & (p1_up    | (p1_ly < -STICK_ON));
wire s1_down  = p1_active & (p1_down  | (p1_ly >  STICK_ON));
wire s1_left  = p1_active & (p1_left  | (p1_lx < -STICK_ON));
wire s1_right = p1_active & (p1_right | (p1_lx >  STICK_ON));

// joystick bits: 0 right, 1 left, 2 down, 3 up, 4 fire 1, 5 fire 2
assign joy_port2 = mouse_mode ? 16'd0 :
                   {10'd0, btn_b, btn_a, s0_up & ~s0_down, s0_down, s0_left & ~s0_right, s0_right};
assign joy_port1 = {10'd0, p1_active & p1_b, p1_active & p1_a, s1_up & ~s1_down, s1_down,
                    s1_left & ~s1_right, s1_right};
assign mouse_btn = {hmouse_btn[2], (mouse_mode & btn_b) | hmouse_btn[1], (mouse_mode & btn_a) | btn_r | hmouse_btn[0]};

// ------------------------------------------------------------- mouse
reg [$clog2(MOUSE_TICK+1)-1:0] mtick;
reg  [7:0] held;             // ticks the D-pad has been held (acceleration)
reg signed [15:0] acc_x, acc_y;   // motion not yet sent to the Amiga
reg        y_next;                // the X half of a motion was sent, Y follows

// signed saturation to 16 bits
function automatic signed [15:0] sat16(input signed [17:0] v);
	sat16 = (v > 18'sd32767) ? 16'sd32767 : (v < -18'sd32768) ? -16'sd32768 : v[15:0];
endfunction
// the part of an accumulated motion sent in one event (-127..127)
function automatic signed [7:0] chunk(input signed [15:0] v);
	chunk = (v > 16'sd127) ? 8'sd127 : (v < -16'sd127) ? -8'sd127 : v[7:0];
endfunction

wire       any_dir = btn_up | btn_down | btn_left | btn_right;
wire [7:0] speed   = (held < 8'd8) ? 8'd1 : (held < 8'd24) ? 8'd2 : (held < 8'd48) ? 8'd4 : 8'd6;

// ------------------------------------------------------------- keys
reg  [3:0] kprev;            // {select, start, y, x}
reg  [3:0] kdown_pend, kup_pend;
reg [$clog2(KEY_GAP+1)-1:0] kgap;
reg [8:0]  evgap;

wire [3:0] know = {btn_select, btn_start, btn_y, btn_x};

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
		held            <= 8'd0;
		acc_x           <= 16'sd0;
		acc_y           <= 16'sd0;
		y_next          <= 1'b0;
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

		// mouse movement: D-pad (in mouse mode) and host reports add up in
		// acc_x/acc_y; events take out at most 127 counts at a time
		begin : mouse_events
			reg signed [17:0] ax, ay;
			reg signed  [7:0] cx, cy;
			reg               send_key, send_x, send_y, send_hkey;
			cx = chunk(acc_x);
			cy = chunk(acc_y);
			ax = {{2{acc_x[15]}}, acc_x};
			ay = {{2{acc_y[15]}}, acc_y};

			if (mtick != '0) mtick <= mtick - 1'd1;
			else begin
				mtick <= MOUSE_TICK[$bits(mtick)-1:0];
				// right stick: up to 7 counts per tick, past the dead zone
				if (stick_rx > STICK_DZ || stick_rx < -STICK_DZ) ax = ax + (stick_rx >>> 4);
				if (stick_ry > STICK_DZ || stick_ry < -STICK_DZ) ay = ay + (stick_ry >>> 4);
				if (mouse_mode && any_dir) begin
					if (held != 8'hFF) held <= held + 8'd1;
					if (btn_left ^ btn_right) ax = ax + (btn_right ? {10'd0, speed} : -{10'd0, speed});
					if (btn_up ^ btn_down)    ay = ay + (btn_down  ? {10'd0, speed} : -{10'd0, speed});
				end
				else held <= 8'd0;
			end
			if (hmouse_valid) begin
				ax = ax + {{2{hmouse_dx[15]}}, hmouse_dx};
				ay = ay + {{2{hmouse_dy[15]}}, hmouse_dy};
			end

			if (kgap != '0) kgap <= kgap - 1'd1;

			// one event at a time
			// a motion is an X event and then a Y event, nothing between
			send_hkey = (evgap == 9'd0) && !y_next && !kq_empty && kgap == '0;
			send_key = (evgap == 9'd0) && !y_next && !send_hkey && found && kgap == '0;
			send_x   = (evgap == 9'd0) && !y_next && !send_hkey && !send_key && (acc_x != 16'sd0 || acc_y != 16'sd0);
			send_y   = (evgap == 9'd0) && y_next;

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
				evgap <= EV_GAP[8:0];
			end

			acc_x <= sat16(ax);
			acc_y <= sat16(ay);
		end
	end
end

endmodule
