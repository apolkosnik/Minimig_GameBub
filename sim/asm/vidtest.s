; Video path test ROM (256 KB at $FC0000) for the Game Bub Minimig bench.
;
; Builds a 320 x 256, 1 bitplane picture in chip RAM and shows it in the
; standard PAL display window (DIWSTRT $2C81, DIWSTOP $2CC1, DDFSTRT $38,
; DDFSTOP $D0) with the copper: colour 0 blue, colour 1 yellow.
;   - every word of a line is $F0F0 (vertical stripes, 4 pixels wide),
;   - the first and the last word of every line are $FFFF (solid columns at
;     the left and right edges of the display window),
;   - lines 0, 16, 32, ... 240 and 255 are solid.
; Then it loops; COLOR00 never changes.
; DIWH and DDF (assembler symbols, -D) move the display window and the
; data fetch: DIWH low resolution pixels from $81 (0: the standard window),
; DDF the DDFSTRT ($38 standard; a fetch starts DDF * 2 + $11, so DIWH / 2
; from $38 keeps the picture in the same place in the window). The core
; centres its 720 pixels on the window.
	ifnd	DIWH
DIWH	equ	0
	endif
	ifnd	DDF
DDF	equ	$38
	endif
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
	move.l	#$01001200,(a0)+	; BPLCON0: 1 plane, colour
	move.l	#$01020000,(a0)+	; BPLCON1
	move.l	#$01040000,(a0)+	; BPLCON2
	move.l	#$01080000,(a0)+	; BPL1MOD
	move.l	#$008E2C81+DIWH,(a0)+	; DIWSTRT
	move.l	#$00902CC1+DIWH,(a0)+	; DIWSTOP
	move.l	#$00920000+DDF,(a0)+	; DDFSTRT
	move.l	#$00940098+DDF,(a0)+	; DDFSTOP
	move.l	#$0180000F,(a0)+	; COLOR00 blue
	move.l	#$01820FF0,(a0)+	; COLOR01 yellow
	move.l	#$FFFFFFFE,(a0)+	; end

	move.l	#$10000,$80(a6)		; COP1LC
	move.w	d0,$88(a6)		; COPJMP1
	move.w	#$8380,$96(a6)		; DMAEN, BPLEN, COPEN
.loop:	bra.s	.loop
