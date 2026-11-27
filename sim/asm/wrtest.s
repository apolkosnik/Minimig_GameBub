; Floppy write test ROM (256 KB at $FC0000) for the Game Bub Minimig bench.
;
; The bench (sim_main.cpp --floppy-write-test) puts an MFM track (11 sectors
; of track 0 in the standard Amiga format, 6000 words) into chip RAM at
; $30000. This program selects DF0, starts its motor, seeks to track 0 on
; the lower head, writes the track with disk DMA (ADKCON MFMPREC | FAST),
; waits for the disk block interrupt and sets COLOR00 green ($0F0); on a
; timeout it sets it red ($F00).
; SPDX-License-Identifier: GPL-3.0-or-later

TRACKBUF	equ	$30000
; the drive: DF0, or with -DDF1 the second drive (wrtest_df1.rom)
	ifd	DF1
SELECT		equ	$6F
	else
SELECT		equ	$77
	endc
TRACKWORDS	equ	6000

	org	$FC0000
	dc.l	$11114EF9
	dc.l	start

start:
	lea	$DFF000,a6
	move.w	#$7FFF,$9A(a6)		; INTENA off
	move.w	#$7FFF,$9C(a6)		; INTREQ clear
	move.w	#$7FFF,$96(a6)		; DMACON off
	move.b	#3,$BFE201		; CIA-A DDRA: OVL and LED out
	move.b	#2,$BFE001		; OVL off
	lea	$7FFF0,sp
	move.w	#$0FF0,$180(a6)		; yellow: running

	lea	$BFD100,a0		; CIA-B PRB: /MTR /SEL3../SEL0 /SIDE DIR /STEP
	move.b	#$FF,$BFD300		; DDRB all out
	move.b	#$FF,(a0)		; nothing selected
	move.b	#$7F,(a0)		; /MTR low
	move.b	#SELECT,(a0)		; select the drive: motor on (latched)
	bsr	delay

	; seek to track 0 (DIR = 1: outwards), lower head (/SIDE = 1)
	moveq	#100,d2
.seek:	btst	#4,$BFE001		; /TK0
	beq.s	.at0
	move.b	#SELECT-1,(a0)		; /STEP low, DIR 1 (bit 1), /SIDE 1
	move.b	#SELECT,(a0)		; /STEP high
	bsr	delay
	dbra	d2,.seek
	bra	fail
.at0:
	; wait for /RDY
	move.l	#200000,d2
.rdy:	btst	#5,$BFE001
	beq.s	.ready
	subq.l	#1,d2
	bne.s	.rdy
	bra	fail
.ready:
	move.w	#$7F00,$9E(a6)		; ADKCON: clear precomp, MFMPREC, WORDSYNC, MSBSYNC, FAST
	move.w	#$9100,$9E(a6)		; ADKCON: MFMPREC, FAST
	move.w	#$8210,$96(a6)		; DMACON: DMAEN, DSKEN
	move.l	#TRACKBUF,$20(a6)	; DSKPT
	move.w	#$4000,$24(a6)		; DSKLEN off (write bit set)
	move.w	#$C000+TRACKWORDS,$24(a6)
	move.w	#$C000+TRACKWORDS,$24(a6)	; start the write

	move.l	#2000000,d2
.wait:	btst	#1,$1F(a6)		; INTREQR DSKBLK
	bne.s	.done
	subq.l	#1,d2
	bne.s	.wait
	bra	fail
.done:	move.w	#$4000,$24(a6)		; DSKLEN off
	move.w	#$0002,$9C(a6)		; clear DSKBLK
	move.w	#$00F0,$180(a6)		; green: written
.loop:	bra.s	.loop

fail:	move.w	#$0F00,$180(a6)		; red
.loop:	bra.s	.loop

delay:	move.w	#4000,d0		; about 3 ms at 7 MHz
.d:	dbra	d0,.d
	rts
