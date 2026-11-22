; ROM read test ROM (256 KB at $FC0000) for the Game Bub Minimig, the 68040
; (the AP68040 variant): the ROM checksummed as data, the ways Kickstart and
; programs read it. sim/asm/build.sh sets the long at $FFFFF8 so that the
; 64K longs of the ROM add up to zero (with carries dropped). Run with the
; "2M + 32M Z3 fast" memory preset (method 5).
;
; Each method runs eight times; the first that does not add up to zero
; shows as COLOR00 and the test stops:
;   1  red      move.l, the data cache off
;   2  orange   move.w (pairs of words), the data cache off
;   3  magenta  move.b (fours of bytes), the data cache off
;   4  blue     move.l with the data cache on (copyback, line fills; the
;               cache invalidated before each round)
;   5  cyan     the ROM copied with MOVE16 to Zorro III RAM, read back
;               there with move.l (the data cache off)
; green: all of them added up, every round.
;
;   $100  method being run, $600D when everything is done
;   $102  the method that failed, $104 the round, $108 the sum it got
; SPDX-License-Identifier: GPL-3.0-or-later

	machine	68040

ROM	equ	$FC0000
Z3	equ	$40100000
LONGS	equ	$10000			; 256 KB

	org	$FC0000
	dc.l	$11114EF9
	dc.l	start

start:
	lea	$DFF000,a6
	move.w	#$7FFF,$9A(a6)		; INTENA off
	move.w	#$7FFF,$96(a6)		; DMACON off
	move.b	#3,$BFE201		; CIA-A DDRA: OVL and LED out
	move.b	#2,$BFE001		; OVL off: chip RAM at 0
	lea	$7FFF0,sp
	move.w	#$0FF0,$180(a6)		; yellow: running
	clr.w	$102
	move.b	#$E9,$E80048		; the Toccata sound card, first in the chain: $E90000
	move.w	#$4000,$E80044		; Zorro III RAM board at $40000000
	move.w	#$5000,$E80044		; RTG board
	move.l	#$0000C040,d0		; DTT0: $00xxxxxx noncacheable ...
	movec	d0,dtt0
	moveq	#0,d0
	movec	d0,dtt1
	move.l	#$00FFC000,d0		; ITT0: everything cacheable (the code)
	movec	d0,itt0
	cinva	bc
	move.l	#$00008000,d0		; the instruction cache on
	movec	d0,cacr

	; ---- 1: longs
	move.w	#1,$100
	moveq	#7,d6
.m1:	lea	ROM,a0
	bsr	sum_l
	bsr	check
	dbf	d6,.m1

	; ---- 2: words
	move.w	#2,$100
	moveq	#7,d6
.m2:	lea	ROM,a0
	move.l	#LONGS-1,d7
	moveq	#0,d1
.w:	move.w	(a0)+,d0
	swap	d0
	move.w	(a0)+,d0
	add.l	d0,d1
	subq.l	#1,d7
	bpl.s	.w
	bsr	check
	dbf	d6,.m2

	; ---- 3: bytes
	move.w	#3,$100
	moveq	#7,d6
.m3:	lea	ROM,a0
	move.l	#LONGS-1,d7
	moveq	#0,d1
.b:	move.b	(a0)+,d0
	lsl.l	#8,d0
	move.b	(a0)+,d0
	lsl.l	#8,d0
	move.b	(a0)+,d0
	lsl.l	#8,d0
	move.b	(a0)+,d0
	add.l	d0,d1
	subq.l	#1,d7
	bpl.s	.b
	bsr	check
	dbf	d6,.m3

	; ---- 4: longs, the data cache on: $00xxxxxx copyback for this
	; method (the bridge inhibits all but the ROM and the fast RAM)
	move.w	#4,$100
	move.l	#$0000C020,d0		; DTT0: $00xxxxxx copyback
	movec	d0,dtt0
	cinva	bc
	move.l	#$80008000,d0
	movec	d0,cacr
	moveq	#7,d6
.m4:	cinva	dc
	lea	ROM,a0
	bsr	sum_l
	bsr	check
	dbf	d6,.m4
	move.l	#$00008000,d0		; the data cache off again
	movec	d0,cacr
	cinva	dc
	move.l	#$0000C040,d0
	movec	d0,dtt0

	; ---- 5: MOVE16 to Zorro III RAM, summed there
	move.w	#5,$100
	moveq	#7,d6
.m5:	lea	ROM,a0
	lea	Z3,a1
	move.l	#LONGS/4-1,d7
.c:	move16	(a0)+,(a1)+
	subq.l	#1,d7
	bpl.s	.c
	lea	Z3,a0
	bsr	sum_l
	bsr	check
	dbf	d6,.m5

	move.w	#$600D,$100
	move.w	#$00F0,$180(a6)		; green
.done:	bra.s	.done

; the LONGS longs at a0 added up -> d1
sum_l:
	move.l	#LONGS-1,d7
	moveq	#0,d1
.l:	add.l	(a0)+,d1
	subq.l	#1,d7
	bpl.s	.l
	rts

; d1 must be zero; else the method's colour, and stop
check:
	tst.l	d1
	bne.s	.bad
	rts
.bad:	move.w	$100,$102
	move.w	d6,$104
	move.l	d1,$108
	move.w	$100,d0
	add.w	d0,d0
	lea	colours-2(pc),a0
	move.w	(a0,d0.w),$180(a6)
.stop:	bra.s	.stop

colours:
	dc.w	$0F00,$0F80,$0F0F,$000F,$00FF
