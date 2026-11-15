; Colour test ROM (256 KB at $FC0000) for the Game Bub Minimig bench.
;
; No bitplanes: every line of the PAL display window ($2C..$12B) gets its
; own background colour from the copper, 256 colours in a frame, more than
; any colour table holds: line L has COLOR00 = (L * 17 + F * 2731) & $FFF.
;
;   - For the first 60 frames F is 0: the picture does not change, and the
;     bench (sim_main.cpp --check-coltest) expects every pixel's colour
;     exact (the palette of gb_palette has room for them).
;   - Then F goes up by one every frame: 256 colours a frame, most of them
;     new. The palette runs out of entries that no frame on screen uses,
;     and the bench checks that it never gives one away too early.
;
; $100 holds F.
; SPDX-License-Identifier: GPL-3.0-or-later

COPPER	equ	$20000
SPLIT	equ	256-$2C			; the first line past raster line 255

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

	; the copper list: for every line a WAIT and a MOVE to COLOR00
	lea	COPPER,a0
	moveq	#0,d0			; line
.build:	cmp.w	#SPLIT,d0
	bne.s	.nosplit
	move.l	#$FFDFFFFE,(a0)+	; wait for the end of raster line 255
.nosplit:
	move.w	d0,d1
	add.w	#$2C,d1
	lsl.w	#8,d1
	or.w	#$0007,d1
	move.w	d1,(a0)+		; WAIT line, horizontal position 6
	move.w	#$FFFE,(a0)+
	move.w	#$0180,(a0)+		; MOVE COLOR00
	clr.w	(a0)+
	addq.w	#1,d0
	cmp.w	#256,d0
	bne.s	.build
	move.l	#$FFFFFFFE,(a0)+

	moveq	#0,d7			; F
	bsr	colours
	move.w	#$0200,$100(a6)		; BPLCON0: no bitplanes
	move.w	#$2C81,$8E(a6)		; DIWSTRT
	move.w	#$2CC1,$90(a6)		; DIWSTOP
	move.l	#COPPER,$80(a6)		; COP1LC
	move.w	d0,$88(a6)		; COPJMP1
	move.w	#$8280,$96(a6)		; DMACON: DMAEN, COPEN

	moveq	#60,d6			; frames with F = 0
.frame:	btst	#5,$1F(a6)		; INTREQR VERTB
	beq.s	.frame
	move.w	#$0020,$9C(a6)
	tst.w	d6
	beq.s	.move
	subq.w	#1,d6
	bra.s	.frame
.move:	addq.w	#1,d7
	bsr	colours
	bra.s	.frame

; the colours of frame d7 into the copper list
colours:
	move.w	d7,$100
	lea	COPPER+6,a0
	move.w	d7,d1
	mulu	#2731,d1		; F * 2731
	moveq	#0,d0
.c:	cmp.w	#SPLIT,d0
	bne.s	.n
	addq.l	#4,a0
.n:	move.w	d1,d2
	and.w	#$0FFF,d2
	move.w	d2,(a0)
	addq.l	#8,a0
	add.w	#17,d1
	addq.w	#1,d0
	cmp.w	#256,d0
	bne.s	.c
	rts
