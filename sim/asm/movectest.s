; MOVEC test ROM (256 KB at $FC0000) for the Game Bub Minimig, the 68040 (the
; AP68040 variant): the setup of systest one control register at a time,
; COLOR00 changed after each, so the colour it stops at names the
; instruction that did not complete (on hardware: systest stopped there):
;   grey     before the boards' autoconfig
;   white    configured; next: MOVEC D0,VBR (VBR 0, the caches off)
;   pink     next: MOVEC D0,DTT0
;   orange   next: MOVEC D0,DTT1
;   yellow   next: MOVEC D0,ITT0
;   cyan     next: CINVA BC
;   blue     next: MOVEC D0,CACR (the instruction cache on)
;   magenta  next: MOVEC D0,VBR again (the instruction cache on)
;   red      next: MOVEC VBR,D1 (read back, must be 0)
;   green    all of them completed; dark red: the read back VBR was not 0
;
;   $100  the step (1-8) about to run, $600D at the end
; SPDX-License-Identifier: GPL-3.0-or-later

	machine	68040

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
