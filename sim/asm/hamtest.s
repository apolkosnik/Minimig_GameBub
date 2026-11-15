; HAM test ROM (256 KB at $FC0000) for the Game Bub Minimig bench.
;
; A still HAM6 picture (OCS, 320 x 256, 6 bitplanes) of pseudo-random data:
; almost every pixel a different colour, thousands of colours, like a HAM
; painting. The bench (sim_main.cpp) checks every pixel the core sends: in
; palette mode its colour must be the one the chipset produced, exactly, or
; for pixels in the fixed colours, the nearest of those.
; SPDX-License-Identifier: GPL-3.0-or-later

PLANES	equ	$20000
PLANESZ	equ	40*256
COPPER	equ	$30000

	org	$FC0000
	dc.l	$11114EF9
	dc.l	start

start:
	lea	$DFF000,a6
	move.w	#$7FFF,$9A(a6)		; INTENA off
	move.w	#$7FFF,$9C(a6)
	move.w	#$7FFF,$96(a6)		; DMACON off
	move.b	#3,$BFE201		; CIA-A DDRA: OVL and LED out
	move.b	#2,$BFE001		; OVL off
	lea	$7FFF0,sp

	; bitplanes: xorshift32
	lea	PLANES,a0
	move.l	#$2545F491,d0
	moveq	#13,d2
	moveq	#17,d3
	move.w	#6*PLANESZ/4-1,d4
.fill:	move.l	d0,d1
	lsl.l	d2,d1
	eor.l	d1,d0
	move.l	d0,d1
	lsr.l	d3,d1
	eor.l	d1,d0
	move.l	d0,d1
	lsl.l	#5,d1
	eor.l	d1,d0
	move.l	d0,(a0)+
	dbra	d4,.fill

	; 16 colours, from the same generator
	lea	$180(a6),a0
	moveq	#16-1,d4
.col:	move.l	d0,d1
	lsl.l	d2,d1
	eor.l	d1,d0
	move.l	d0,d1
	lsr.l	d3,d1
	eor.l	d1,d0
	move.l	d0,d1
	lsl.l	#5,d1
	eor.l	d1,d0
	move.w	d0,(a0)+
	dbra	d4,.col

	; copper: the bitplane pointers every frame
	lea	COPPER,a0
	move.l	#PLANES,d0
	move.w	#$00E0,d1
	moveq	#6-1,d4
.cop:	move.w	d1,(a0)+
	swap	d0
	move.w	d0,(a0)+
	addq.w	#2,d1
	move.w	d1,(a0)+
	swap	d0
	move.w	d0,(a0)+
	addq.w	#2,d1
	add.l	#PLANESZ,d0
	dbra	d4,.cop
	move.l	#$FFFFFFFE,(a0)+

	move.w	#$6A00,$100(a6)		; BPLCON0: 6 planes, HAM, colour
	move.w	#0,$102(a6)
	move.w	#0,$104(a6)
	move.w	#$2C81,$8E(a6)		; DIWSTRT
	move.w	#$2CC1,$90(a6)		; DIWSTOP
	move.w	#$0038,$92(a6)		; DDFSTRT
	move.w	#$00D0,$94(a6)		; DDFSTOP
	move.w	#0,$108(a6)		; BPL1MOD
	move.w	#0,$10A(a6)		; BPL2MOD
	move.l	#COPPER,$80(a6)		; COP1LC
	move.w	d0,$88(a6)		; COPJMP1
	move.w	#$8380,$96(a6)		; DMACON: DMAEN, BPLEN, COPEN
	move.w	#$600D,$100
.loop:	bra.s	.loop
