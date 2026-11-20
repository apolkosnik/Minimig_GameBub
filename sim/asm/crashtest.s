; Crash display test ROM (256 KB at $FC0000) for the Game Bub Minimig, the
; 68040 (the AP68040 variant): movectest's control register sequence, with
; every exception vector set first, so a crash shows what happened instead
; of a reset: the handler stops DMA and interrupts and has the copper draw,
; top to bottom, most significant bit first,
;   8 bars   the vector number (red 1, dark grey 0)
;   a white bar
;   32 bars  the stacked PC (green 1, dark grey 0)
;   a white bar
;   16 bars  the frame's format and vector offset word (blue 1, dark grey 0)
; Each bar is 3 lines with a black line under it. Without an exception:
; green at the end (each step's colour as in movectest before it).
;
;   $100  the step (1-8), $600D at the end; $120 the vector number, $124 the
;   PC, $128 the format word of an exception
; SPDX-License-Identifier: GPL-3.0-or-later

	machine	68040

COPL	equ	$20000			; the copper list of the crash display

	org	$FC0000
	dc.l	$11114EF9
	dc.l	start

start:
	lea	$DFF000,a6
	move.w	#$7FFF,$9A(a6)		; INTENA off
	move.w	#$7FFF,$9C(a6)
	move.w	#$7FFF,$96(a6)		; DMACON off
	move.b	#3,$BFE201		; CIA-A DDRA: OVL and LED out
	move.b	#2,$BFE001		; OVL off: chip RAM at 0
	lea	$7FFF0,sp
	move.w	#$0888,$180(a6)		; grey
	lea	8,a0			; vectors 2-255: the crash display
	move.w	#253,d7
.v:	move.l	#crash,(a0)+
	dbf	d7,.v
	move.w	#$4000,$E80044		; Zorro III RAM board at $40000000
	move.w	#$5000,$E80044		; RTG board

	move.w	#1,$100
	move.w	#$0FFF,$180(a6)		; white
	moveq	#0,d0
	movec	d0,vbr

	move.w	#2,$100
	move.w	#$0F8F,$180(a6)		; pink
	move.l	#$0000C040,d0
	movec	d0,dtt0

	move.w	#3,$100
	move.w	#$0F80,$180(a6)		; orange
	moveq	#0,d0
	movec	d0,dtt1

	move.w	#4,$100
	move.w	#$0FF0,$180(a6)		; yellow
	move.l	#$00FFC000,d0
	movec	d0,itt0

	move.w	#5,$100
	move.w	#$00FF,$180(a6)		; cyan
	cinva	bc

	move.w	#6,$100
	move.w	#$000F,$180(a6)		; blue
	move.l	#$00008000,d0
	movec	d0,cacr

	move.w	#7,$100
	move.w	#$0F0F,$180(a6)		; magenta
	ifd	FORCE
	illegal				; -DFORCE: the crash display, for a look
	endc
	moveq	#0,d0
	movec	d0,vbr

	move.w	#8,$100
	move.w	#$0F00,$180(a6)		; red
	moveq	#-1,d1
	movec	vbr,d1
	tst.l	d1
	bne.s	.bad

	move.w	#$600D,$100
	move.w	#$00F0,$180(a6)		; green
.done:	bra.s	.done
.bad:	move.w	#$0500,$180(a6)		; dark red: VBR read back not 0
.stop:	bra.s	.stop

; any exception: the vector, the PC and the format word as bars
crash:
	move.w	#$2700,sr
	lea	$DFF000,a6
	move.w	#$7FFF,$96(a6)		; DMA off
	move.w	#$7FFF,$9A(a6)
	move.w	6(sp),d2		; format and vector offset
	move.w	d2,d0
	and.w	#$0FFF,d0
	lsr.w	#2,d0			; the vector number
	move.l	2(sp),d1		; the PC
	move.w	d0,$120
	move.l	d1,$124
	move.w	d2,$128
	lea	COPL,a0
	move.w	#0,a4			; (wait: the line counter not wrapped yet)
	move.w	#$30,d3			; the first bar's line
	move.w	d0,d4
	lsl.w	#8,d4			; the 8 bits at the top of the word
	moveq	#7,d5
	move.w	#$0F00,d6		; red
	bsr.s	bars16
	bsr.s	sep
	move.l	d1,d4
	moveq	#31,d5
	move.w	#$00F0,d6		; green
	bsr.s	bars32
	bsr.s	sep
	move.w	d2,d4
	swap	d4
	moveq	#15,d5
	move.w	#$000F,d6		; blue
	bsr.s	bars32
	move.l	#$FFFFFFFE,(a0)+	; the end
	move.l	#COPL,$80(a6)		; COP1LC
	move.w	#0,$88(a6)		; COPJMP1
	move.w	#$8280,$96(a6)		; DMACON: set, DMAEN, COPEN
.c:	bra.s	.c

; d4's top d5+1 bits (of 16 / 32), d6 the colour of a 1; a3 the bar's
; colour, a4 set once the line counter has wrapped (wait)
bars16:
	swap	d4
bars32:
.b:	move.w	#$0333,a3		; dark grey: 0
	lsl.l	#1,d4
	bcc.s	.z
	move.w	d6,a3
.z:	bsr.s	wait
	move.w	#$0180,(a0)+		; COLOR00
	move.w	a3,(a0)+
	addq.w	#3,d3
	bsr.s	wait
	move.l	#$01800000,(a0)+	; black line
	addq.w	#1,d3
	dbf	d5,.b
	rts

sep:
	bsr.s	wait
	move.l	#$01800FFF,(a0)+	; white
	addq.w	#3,d3
	bsr.s	wait
	move.l	#$01800000,(a0)+
	addq.w	#1,d3
	rts

; a WAIT for line d3 (d7 trashed); past line 255 the copper's vertical
; compare has 8 bits: a WAIT for the end of line 255 first, once (a4)
wait:
	move.w	d3,d7
	cmp.w	#$FF,d7
	bls.s	.w
	cmp.w	#0,a4
	bne.s	.w2
	move.l	#$FFDFFFFE,(a0)+	; the end of line 255
	move.w	#1,a4
.w2:	and.w	#$FF,d7
.w:	lsl.w	#8,d7
	or.w	#$0007,d7
	move.w	d7,(a0)+
	move.w	#$FFFE,(a0)+
	rts
