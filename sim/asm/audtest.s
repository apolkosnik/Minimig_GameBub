; Audio test ROM (256 KB at $FC0000) for the Game Bub Minimig bench.
; Plays an 8 byte square wave (+100 / -100) on Paula channel 0 (left) at
; full volume, period 254 (about 14 kHz sample rate, 1.7 kHz tone), with
; channels 1-3 silent.
; SPDX-License-Identifier: GPL-3.0-or-later

	org	$FC0000
	dc.l	$11114EF9
	dc.l	start

start:
	lea	$DFF000,a6
	move.w	#$7FFF,$9A(a6)
	move.w	#$7FFF,$96(a6)
	move.b	#3,$BFE201
	move.b	#2,$BFE001
	lea	$7FFF0,sp
	move.l	#$64646464,$1000	; samples at chip RAM $1000
	move.l	#$9C9C9C9C,$1004
	move.l	#$1000,$A0(a6)		; AUD0LC
	move.w	#4,$A4(a6)		; AUD0LEN (words)
	move.w	#254,$A6(a6)		; AUD0PER
	move.w	#64,$A8(a6)		; AUD0VOL
	move.w	#$8201,$96(a6)		; DMAEN, AUD0EN
.loop:	bra.s	.loop
