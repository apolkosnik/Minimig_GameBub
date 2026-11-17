; Interlace test ROM (256 KB at $FC0000) for the Game Bub Minimig bench.
;
; The picture of vidtest.s (320 x 256, 1 bitplane, standard PAL display
; window, colour 1 yellow), with BPLCON0's LACE bit set: the chipset sends
; long and short fields in turn. Both fields show the same 256 lines (the
; copper sets the bitplane pointer each field). The CPU sets COLOR00 on
; line 16 of every field by VPOSR's LOF bit: blue in a long field, red in a
; short one. gb_video shows the long fields only, so every frame the core
; completes has a blue border and comes once every two fields.
; SPDX-License-Identifier: GPL-3.0-or-later

	org	$FC0000
	dc.l	$11114EF9		; as a Kickstart (the reset SSP)
	dc.l	start			; reset PC

start:
	lea	$DFF000,a6
	move.w	#$7FFF,$9A(a6)		; INTENA off
	move.w	#$7FFF,$96(a6)		; DMACON off
	move.b	#3,$BFE201		; CIA-A DDRA: OVL and LED out
	move.b	#2,$BFE001		; OVL off: chip RAM at $0
	lea	$7FFF0,sp

	; bitplane at $20000, 40 bytes per line, 256 lines
	lea	$20000,a0
	moveq	#0,d1			; line
.line:	moveq	#19,d2			; 20 words
	move.w	d1,d3
	and.w	#15,d3
	beq.s	.solid
	cmp.w	#255,d1
	beq.s	.solid
	move.w	#$FFFF,(a0)+		; left edge
	moveq	#17,d2
.mid:	move.w	#$F0F0,(a0)+
	dbra	d2,.mid
	move.w	#$FFFF,(a0)+		; right edge
	bra.s	.next
.solid:	move.w	#$FFFF,(a0)+
	dbra	d2,.solid
.next:	addq.w	#1,d1
	cmp.w	#256,d1
	bne.s	.line

	; copper list at $10000
	lea	$10000,a0
	move.l	#$00E00002,(a0)+	; BPL1PTH
	move.l	#$00E20000,(a0)+	; BPL1PTL
	move.l	#$01001204,(a0)+	; BPLCON0: 1 plane, colour, interlace
	move.l	#$01020000,(a0)+	; BPLCON1
	move.l	#$01040000,(a0)+	; BPLCON2
	move.l	#$01080000,(a0)+	; BPL1MOD
	move.l	#$008E2C81,(a0)+	; DIWSTRT
	move.l	#$00902CC1,(a0)+	; DIWSTOP
	move.l	#$00920038,(a0)+	; DDFSTRT
	move.l	#$009400D0,(a0)+	; DDFSTOP
	move.l	#$01820FF0,(a0)+	; COLOR01 yellow
	move.l	#$FFFFFFFE,(a0)+	; end

	move.l	#$10000,$80(a6)		; COP1LC
	move.w	d0,$88(a6)		; COPJMP1
	move.w	#$8380,$96(a6)		; DMAEN, BPLEN, COPEN
	move.w	#$0F00,$180(a6)		; COLOR00 red until the first field is seen

	; on line 16 of each field: COLOR00 by the field (VPOSR bit 15, LOF)
.loop:	move.l	$04(a6),d0		; VPOSR, VHPOSR
	move.l	d0,d1
	and.l	#$0001FF00,d1		; V8..V0
	cmp.l	#$00001000,d1
	bne.s	.loop
	move.w	#$0F00,d2		; short field: red
	tst.l	d0
	bpl.s	.set
	move.w	#$000F,d2		; long field: blue
.set:	move.w	d2,$180(a6)
.wait:	move.l	$04(a6),d1		; until line 16 is over
	and.l	#$0001FF00,d1
	cmp.l	#$00001000,d1
	beq.s	.wait
	bra.s	.loop
