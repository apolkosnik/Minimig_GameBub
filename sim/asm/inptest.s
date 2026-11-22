; Input test ROM (256 KB at $FC0000) for the Game Bub Minimig bench.
; Copies the inputs to chip RAM, continuously:
;   $100  JOY1DAT (joystick, port 2)
;   $102  JOY0DAT (mouse counters, port 1)
;   $104  CIA-A PRA in the low byte (bit 7 fire port 2, bit 6 left button port 1)
;   $106  POTGOR (right mouse button: bit 10 low when pressed)
;   $108  the last key: keycode | $80 when released (decoded from CIA-A SDR)
;   $10A  count of keyboard bytes received
;   $10C  the mouse wheel's sum ($DFF1F0, as MiSTer's minimig has it)
;   $110  the same read as a long word ($DFF1F0 and $DFF1F2), which is how
;         MiSTer's WheelDriver reads it: the sum in the low byte of the
;         high word, the low word zero
; The keyboard bytes are acknowledged (SP output low for ~100 us) as the
; Amiga's keyboard.device does.
; SPDX-License-Identifier: GPL-3.0-or-later

	org	$FC0000
	dc.l	$11114EF9
	dc.l	start

start:
	lea	$DFF000,a6
	move.w	#$7FFF,$9A(a6)
	move.w	#$7FFF,$96(a6)
	move.b	#3,$BFE201		; CIA-A DDRA: OVL, LED out (fire buttons in)
	move.b	#2,$BFE001
	lea	$7FFF0,sp
	move.w	#$FFFF,$108
	clr.w	$10A
	move.b	#$7F,$BFED01		; CIA-A ICR: all off
	move.b	$BFED01,d0		; clear
	move.w	#$FF00,$34(a6)		; POTGO: pins as inputs
.loop:
	move.w	$0C(a6),$100		; JOY1DAT
	move.w	$0A(a6),$102		; JOY0DAT
	moveq	#0,d0
	move.b	$BFE001,d0
	move.w	d0,$104
	move.w	$16(a6),$106		; POTGOR
	move.w	$1F0(a6),$10C		; the wheel
	move.l	$1F0(a6),$110		; and as MiSTer's WheelDriver reads it: a long
	move.b	$BFED01,d1		; CIA-A ICR (clears it)
	btst	#3,d1			; SP: a keyboard byte
	beq.s	.loop
	move.b	$BFEC01,d0		; SDR
	not.b	d0
	ror.b	#1,d0			; keycode in bits 6..0, bit 7 = released
	and.w	#$FF,d0
	move.w	d0,$108
	addq.w	#1,$10A
	or.b	#$40,$BFEE01		; CRA SPMODE output: KDAT low (handshake)
	move.w	#200,d2
.hs:	dbra	d2,.hs
	and.b	#$BF,$BFEE01		; SPMODE input
	bra.s	.loop
