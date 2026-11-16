; AGA 256 colour test ROM (256 KB at $FC0000) for the Game Bub Minimig bench.
;
; A still 320 x 256 lores picture of 8 bitplanes of pseudo-random data and
; 256 pseudo-random 24 bit colours (AGA colour table, BPLCON3 banks and
; LOCT): 256 colours, almost every pixel another colour than its
; neighbour, like a detailed AGA painting. In palette mode every pixel must
; be its colour exactly (run with --expect-no-fixed: no pixel in the fixed
; colours), on every frame (sim_main.cpp checks every pixel shown).
; SPDX-License-Identifier: GPL-3.0-or-later

PLANES	equ	$20000
PLANESZ	equ	40*256
COPPER	equ	$40000

	org	$FC0000
	dc.l	$11114EF9
	dc.l	start

; xorshift32 in d0 (d2 = 13, d3 = 17)
next	macro
	move.l	d0,d1
	lsl.l	d2,d1
	eor.l	d1,d0
	move.l	d0,d1
	lsr.l	d3,d1
	eor.l	d1,d0
	move.l	d0,d1
	lsl.l	#5,d1
	eor.l	d1,d0
	endm

start:
	lea	$DFF000,a6
	move.w	#$7FFF,$9A(a6)		; INTENA off
	move.w	#$7FFF,$9C(a6)
	move.w	#$7FFF,$96(a6)		; DMACON off
	move.b	#3,$BFE201		; CIA-A DDRA: OVL and LED out
	move.b	#2,$BFE001		; OVL off
	lea	$7FFF0,sp

	lea	PLANES,a0
	move.l	#$9E3779B9,d0
	moveq	#13,d2
	moveq	#17,d3
	move.w	#8*PLANESZ/4-1,d4
.fill:	next
	move.l	d0,(a0)+
	dbra	d4,.fill

	; 256 colours: bank by bank, the high nibbles, then (LOCT) the low
	moveq	#0,d5			; bank
.bank:	move.l	d0,d6			; the generator's state at this bank
	move.w	d5,d7
	ror.w	#3,d7			; bank << 13
	move.w	d7,$106(a6)		; BPLCON3: bank, LOCT 0
	lea	$180(a6),a0
	moveq	#32-1,d4
.hi:	next
	move.l	d0,d1			; colour $RRGGBB in d0[23:0]
	swap	d1			; d1.w = $..RR
	and.w	#$00F0,d1
	lsl.w	#4,d1			; R high nibble at 11:8
	move.w	d0,d7
	lsr.w	#8,d7
	and.w	#$00F0,d7		; G high nibble at 7:4
	or.w	d7,d1
	move.w	d0,d7
	lsr.w	#4,d7
	and.w	#$000F,d7		; B high nibble at 3:0
	or.w	d7,d1
	move.w	d1,(a0)+
	dbra	d4,.hi
	; the same 32 colours again for the low nibbles
	move.l	d6,d0
	move.w	d5,d7
	ror.w	#3,d7
	or.w	#$0200,d7		; LOCT
	move.w	d7,$106(a6)
	lea	$180(a6),a0
	moveq	#32-1,d4
.lo:	next
	move.l	d0,d1
	swap	d1
	and.w	#$000F,d1		; R low nibble
	lsl.w	#8,d1			; at 11:8
	move.w	d0,d7
	lsr.w	#4,d7
	and.w	#$00F0,d7		; G low nibble at 7:4
	or.w	d7,d1
	move.w	d0,d7
	and.w	#$000F,d7		; B low nibble at 3:0
	or.w	d7,d1
	move.w	d1,(a0)+
	dbra	d4,.lo
	addq.w	#1,d5
	cmp.w	#8,d5
	bne	.bank
	move.w	#0,$106(a6)		; BPLCON3: bank 0, LOCT 0

	; copper: the bitplane pointers every frame
	lea	COPPER,a0
	move.l	#PLANES,d0
	move.w	#$00E0,d1
	moveq	#8-1,d4
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

	move.w	#$0210,$100(a6)		; BPLCON0: 8 planes (BPU3), colour
	move.w	#0,$102(a6)
	move.w	#$0024,$104(a6)		; BPLCON2: playfield priorities as the default
	move.w	#0,$1FC(a6)		; FMODE: 16 bit fetches
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
