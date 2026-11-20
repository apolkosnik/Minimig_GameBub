; Code changed in chip RAM, at random: test ROM (256 KB at $FC0000) for the
; Game Bub Minimig bench. Sixteen routines "MOVEQ #v,D0 / RTS" in chip RAM,
; eight of them 1 KB apart (one set of the 68040's instruction cache: its
; four ways are not enough for them, so lines leave the cache by themselves
; too), eight close together (several a line). 3000 rounds, each on a
; random routine:
;   - it is called, and must return its v;
;   - or its v is changed by a byte write, another routine is called, and
;     then it;
;   - or changed by a byte write, with a NOP before its call (the 68040's
;     NOP waits for the writes: enough for code run at once);
;   - or changed by the blitter (a word), and called when the blit is done.
; The instruction cache is on: the AP68040 variant keeps chip RAM's code in
; it and takes a line out for every write there, the CPU's and the
; chipset's; the 68030 core's cache in front of the SDRAM follows them.
;
;   $100  $600D when all rounds are done
;   $102  the round that failed (from 1), $104 the routine, $106 the v
;         expected (high byte) and what it returned (low byte), $108 the
;         kind of round (0 call, 1 write and another call, 2 write and NOP,
;         3 blitter)
;
; COLOR00 is green at the end, red after a failure.
; SPDX-License-Identifier: GPL-3.0-or-later

	machine	68020

CODE	equ	$20000
VTAB	equ	$1000			; the routines' v, a byte each
SRC	equ	$1100			; the word the blitter copies
ROUNDS	equ	3000

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
	move.w	#$0FF0,$180(a6)		; yellow: running
	clr.w	$102
	move.l	#$00008001,d0		; the instruction cache on (bit 15: the
	movec	d0,cacr			; 68040's; bit 0: the 68020's and 68030's)

	; the routines: v = their number
	lea	radr(pc),a4
	lea	VTAB,a5
	moveq	#0,d1
.mk:	move.l	(a4,d1.w*4),a0
	move.w	#$7000,d0
	or.b	d1,d0
	move.w	d0,(a0)			; moveq #v,d0
	move.w	#$4E75,2(a0)		; rts
	move.b	d1,(a5,d1.w)
	addq.w	#1,d1
	cmp.w	#16,d1
	bne.s	.mk

	move.l	#$2545F491,d7		; the random numbers' state
	moveq	#0,d6			; round
round:
	addq.w	#1,d6
	bsr	rnd
	move.l	d0,d5
	moveq	#15,d4
	and.w	d5,d4			; d4: the routine
	move.l	(a4,d4.w*4),a0		; a0: its address
	move.l	d5,d3
	lsr.l	#8,d3
	and.w	#3,d3			; d3: the kind of round
	move.l	d5,d2
	swap	d2
	and.w	#$7F,d2			; d2: a new v
	tst.w	d3
	beq.s	call
	move.b	d2,(a5,d4.w)
	cmp.w	#1,d3
	beq.s	wr_other
	cmp.w	#2,d3
	beq.s	wr_nop
	; ---- 3: the blitter writes the MOVEQ
	move.w	#$7000,d0
	or.b	d2,d0
	move.w	d0,SRC
	bsr	blit
	bra.s	call
	; ---- 1: a byte write, another routine's call, then its own
wr_other:
	move.b	d2,1(a0)
	moveq	#5,d1
	add.w	d4,d1
	and.w	#15,d1
	move.l	(a4,d1.w*4),a1
	moveq	#-1,d0
	jsr	(a1)
	cmp.b	(a5,d1.w),d0
	beq.s	call
	move.w	d1,d4			; (the other routine failed)
	bra.s	bad
	; ---- 2: a byte write, a NOP, its call
wr_nop:
	move.b	d2,1(a0)
	nop
	moveq	#-1,d0
	jsr	(a0)
	cmp.b	(a5,d4.w),d0
	bne.s	bad
	bra.s	next
	; ---- its call
call:	moveq	#-1,d0
	jsr	(a0)
	cmp.b	(a5,d4.w),d0
	bne.s	bad
next:	cmp.w	#ROUNDS,d6
	bne	round

	move.w	#$600D,$100
	move.w	#$00F0,$180(a6)		; green
.done:	bra.s	.done

bad:	move.w	d6,$102
	move.w	d4,$104
	move.b	(a5,d4.w),$106
	move.b	d0,$107
	move.w	d3,$108
	move.w	#$0F00,$180(a6)		; red
.stop:	bra.s	.stop

; d0: the next random number (xorshift; d1 trashed)
rnd:	move.l	d7,d0
	moveq	#13,d1
	lsl.l	d1,d0
	eor.l	d0,d7
	move.l	d7,d0
	moveq	#17,d1
	lsr.l	d1,d0
	eor.l	d0,d7
	move.l	d7,d0
	lsl.l	#5,d0
	eor.l	d0,d7
	move.l	d7,d0
	rts

; the word at SRC to (a0) with the blitter (D = A)
blit:
	bsr.s	bwait
	move.w	#$8240,$96(a6)		; DMACON: set, DMAEN, BLTEN
	move.l	#$09F00000,$40(a6)	; BLTCON0 (A and D, D = A), BLTCON1
	move.l	#$FFFFFFFF,$44(a6)	; BLTAFWM, BLTALWM
	move.l	#SRC,$50(a6)		; BLTAPT
	move.l	a0,$54(a6)		; BLTDPT
	clr.w	$64(a6)			; BLTAMOD
	clr.w	$66(a6)			; BLTDMOD
	move.w	#$0041,$58(a6)		; BLTSIZE: one line of one word; go
bwait:	btst	#6,$02(a6)		; DMACONR: BBUSY
	bne.s	bwait
	btst	#6,$02(a6)
	bne.s	bwait
	rts

; the routines' addresses: eight 1 KB apart, eight 20 bytes apart
radr:	dc.l	CODE,CODE+$400,CODE+$800,CODE+$C00,CODE+$1000,CODE+$1400,CODE+$1800,CODE+$1C00
	dc.l	CODE+$104,CODE+$118,CODE+$12C,CODE+$140,CODE+$154,CODE+$168,CODE+$17C,CODE+$190
