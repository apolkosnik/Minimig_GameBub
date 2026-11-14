// Game Bub Minimig: Game Bub buttons -> Amiga joystick, mouse and keyboard.
//
//   D-pad          joystick (port 2) directions
//   A / B          joystick fire 1 / fire 2
//   L (held)       D-pad moves the mouse (port 1), A = left, B = right button
//   R              left mouse button (for dragging while L is held)
//   host mouse     a USB/Bluetooth mouse reported by the firmware fork
//                  (gb_host 0x1030/0x1034) moves the port 1 mouse too
//   X, Y, Start,   Amiga keys (raw key codes from the settings,
//   Select         defaults Space, Return, F1, Esc)
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

	input       [7:0] key_x,
	input       [7:0] key_y,
	input       [7:0] key_start,
	input       [7:0] key_select,

	input             hmouse_valid,  // one clock per host mouse report
	input      [15:0] hmouse_dx,     // signed, right positive
	input      [15:0] hmouse_dy,     // signed, down positive
	input       [2:0] hmouse_btn,    // {middle, right, left}

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

wire mouse_mode = btn_l;

// joystick bits: 0 right, 1 left, 2 down, 3 up, 4 fire 1, 5 fire 2
assign joy_port2 = mouse_mode ? 16'd0 :
                   {10'd0, btn_b, btn_a, btn_up & ~btn_down, btn_down, btn_left & ~btn_right, btn_right};
assign joy_port1 = 16'd0;
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
	end
	else begin
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
			reg               send_key, send_x, send_y;
			cx = chunk(acc_x);
			cy = chunk(acc_y);
			ax = {{2{acc_x[15]}}, acc_x};
			ay = {{2{acc_y[15]}}, acc_y};

			if (mtick != '0) mtick <= mtick - 1'd1;
			else begin
				mtick <= MOUSE_TICK[$bits(mtick)-1:0];
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
			send_key = (evgap == 9'd0) && !y_next && found && kgap == '0;
			send_x   = (evgap == 9'd0) && !y_next && !send_key && (acc_x != 16'sd0 || acc_y != 16'sd0);
			send_y   = (evgap == 9'd0) && y_next;

			if (evgap != 9'd0) evgap <= evgap - 9'd1;
			if (send_key) begin
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
