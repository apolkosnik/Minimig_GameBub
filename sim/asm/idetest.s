; Hard disk test ROM (256 KB at $FC0000) for the Game Bub Minimig bench.
;
; Drives the Gayle IDE registers at $DA2000 the way scsi.device does (PIO,
; whole blocks read after DRQ) and leaves what it read in chip RAM for the
; bench (sim_main.cpp --ide-test) to compare with the image file:
;
;   $F0   (from the bench) drive select: $00 master, $10 slave
;   $F4   (from the bench) long: LBA of the last sector of the drive
;   $100  step being run, $600D when everything is done
;   $102  the step that failed, 0 when none did
;   $104  status after the identify data was read
;   $106  Gayle INTREQ ($DA9000) seen after the identify command
;   $110  sector, cylinder low, cylinder high, device/head, count after step 3
;   $118  the same after step 4
;   $120  status, error after an unknown command
;   $130  16 bit sum of the words of 256 sectors from LBA 300
;   $1000 identify data          $1200 identify data after step 13
;   $2000 LBA 0, 1 (read sectors)
;   $3000 LBA 100..102 (read sectors, command $21)
;   $4000 40 sectors from cylinder 1, head 0, sector 1 (read multiple, CHS)
;   $9000 the last sector of the drive and the one after it
;   $A000 LBA 200, 201 read back (written in step 5 with write sectors)
;   $B000 20 sectors read back (written in step 6 with write multiple, CHS
;         cylinder 2, head 0, sector 3)
;
; COLOR00 is green at the end, red after a failure or timeout.
; SPDX-License-Identifier: GPL-3.0-or-later

IDE	equ	$DA2000
DATA	equ	0
ERR	equ	4
COUNT	equ	8
SECT	equ	12
CYLL	equ	16
CYLH	equ	20
DEVH	equ	24
STAT	equ	28

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
	move.w	#$0FF0,$180(a6)		; yellow: running
	lea	IDE,a5
	clr.w	$102
	move.w	$F0,d7			; drive select

	; ---- 1: identify, data read word by word, each after a status check
	move.w	#1,$100
	bsr	waitbsy
	bsr	seldrv
	move.b	#$EC,STAT(a5)
	move.l	#400000,d1
.irq:	move.w	$DA9000,d0		; Gayle INTREQ: bit 15 IDE interrupt
	bmi.s	.gotirq
	subq.l	#1,d1
	bne.s	.irq
	bra	fail
.gotirq:
	move.w	d0,$106
	lea	$1000,a0
	move.l	#256,d2
	bsr	readwords
	bsr	waitbsy
	move.b	d0,$104
	clr.b	$105

	; ---- 2: read sectors, LBA 0, 2 sectors
	move.w	#2,$100
	bsr	waitbsy
	moveq	#0,d1
	moveq	#2,d2
	bsr	setlba
	move.b	#$20,STAT(a5)
	lea	$2000,a0
	move.l	#512,d2
	move.l	#256,d5
	bsr	readblk

	; ---- 3: read sectors (no retry), LBA 100, 3 sectors
	move.w	#3,$100
	bsr	waitbsy
	moveq	#100,d1
	moveq	#3,d2
	bsr	setlba
	move.b	#$21,STAT(a5)
	lea	$3000,a0
	move.l	#768,d2
	move.l	#256,d5
	bsr	readblk
	bsr	waitbsy
	lea	$110,a1
	bsr	saveregs

	; ---- 4: read multiple, CHS 1/0/1, 40 sectors (blocks of 16, 16, 8)
	move.w	#4,$100
	bsr	waitbsy
	moveq	#1,d1
	moveq	#0,d3
	moveq	#1,d4
	moveq	#40,d2
	bsr	setchs
	move.b	#$C4,STAT(a5)
	lea	$4000,a0
	move.l	#40*256,d2
	move.l	#16*256,d5
	bsr	readblk
	bsr	waitbsy
	lea	$118,a1
	bsr	saveregs

	; ---- 5: write sectors, LBA 200, 2 sectors: words $A500, $A501, ...
	move.w	#5,$100
	bsr	waitbsy
	move.l	#200,d1
	moveq	#2,d2
	bsr	setlba
	move.b	#$30,STAT(a5)
	move.l	#512,d2
	move.w	#$A500,d3
	moveq	#1,d4
	move.l	#256,d5
	bsr	writegen
	bsr	waitbsy
	btst	#0,d0
	bne	fail

	; ---- 6: write multiple, CHS 2/0/3, 20 sectors: words $1234, +7, ...
	move.w	#6,$100
	bsr	waitbsy
	moveq	#2,d1
	moveq	#0,d3
	moveq	#3,d4
	moveq	#20,d2
	bsr	setchs
	move.b	#$C5,STAT(a5)
	move.l	#20*256,d2
	move.w	#$1234,d3
	moveq	#7,d4
	move.l	#16*256,d5
	bsr	writegen
	bsr	waitbsy
	btst	#0,d0
	bne	fail

	; ---- 7: set multiple: 8 sectors per block
	move.w	#7,$100
	bsr	waitbsy
	bsr	seldrv
	move.b	#8,COUNT(a5)
	move.b	#$C6,STAT(a5)
	bsr	waitbsy
	btst	#0,d0
	bne	fail

	; ---- 8: read multiple, LBA 200, 2 sectors, compare with step 5
	move.w	#8,$100
	bsr	waitbsy
	move.l	#200,d1
	moveq	#2,d2
	bsr	setlba
	move.b	#$C4,STAT(a5)
	lea	$A000,a0
	move.l	#512,d2
	move.l	#8*256,d5
	bsr	readblk
	lea	$A000,a0
	move.l	#512,d2
	move.w	#$A500,d3
	moveq	#1,d4
	bsr	compare

	; ---- 9: read multiple by LBA what step 6 wrote by CHS (blocks of 8, 8, 4)
	move.w	#9,$100
	bsr	waitbsy
	moveq	#0,d0
	move.b	$1006,d0		; identify word 3: heads (low byte first)
	moveq	#0,d1
	move.b	$100D,d1		; identify word 6: sectors per track
	lsl.w	#8,d1
	move.b	$100C,d1
	mulu	d0,d1
	add.l	d1,d1
	addq.l	#2,d1			; cylinder 2, head 0, sector 3
	moveq	#20,d2
	bsr	setlba
	move.b	#$C4,STAT(a5)
	lea	$B000,a0
	move.l	#20*256,d2
	move.l	#8*256,d5
	bsr	readblk
	lea	$B000,a0
	move.l	#20*256,d2
	move.w	#$1234,d3
	moveq	#7,d4
	bsr	compare

	; ---- 10: read multiple, LBA 300, count 0 = 256 sectors, summed
	move.w	#10,$100
	bsr	waitbsy
	move.l	#300,d1
	moveq	#0,d2
	bsr	setlba
	move.b	#$C4,STAT(a5)
	moveq	#0,d6
	moveq	#32-1,d3		; 32 blocks of 8 sectors
.blk:	bsr	waitdrq
	move.w	#8*256-1,d0
.sum:	add.w	(a5),d6
	dbra	d0,.sum
	dbra	d3,.blk
	move.w	d6,$130
	bsr	waitbsy
	btst	#0,d0
	bne	fail

	; ---- 11: the last sector of the drive and the one after it
	move.w	#11,$100
	bsr	waitbsy
	move.l	$F4,d1
	moveq	#2,d2
	bsr	setlba
	move.b	#$20,STAT(a5)
	lea	$9000,a0
	move.l	#512,d2
	move.l	#256,d5
	bsr	readblk

	; ---- 12: a command the drive does not have: error, aborted
	move.w	#12,$100
	bsr	waitbsy
	bsr	seldrv
	move.b	#$B0,STAT(a5)
	bsr	waitbsy
	move.b	d0,$120
	move.b	ERR(a5),$121

	; ---- 13: initialize device parameters: 4 heads, 17 sectors; identify
	move.w	#13,$100
	bsr	waitbsy
	move.b	d7,d0
	or.b	#$A3,d0
	move.b	d0,DEVH(a5)
	move.b	#17,COUNT(a5)
	move.b	#$91,STAT(a5)
	bsr	waitbsy
	btst	#0,d0
	bne	fail
	bsr	seldrv
	move.b	#$EC,STAT(a5)
	lea	$1200,a0
	move.l	#256,d2
	move.l	#256,d5
	bsr	readblk

	move.w	#$600D,$100
	move.w	#$00F0,$180(a6)		; green
.loop:	bra.s	.loop

fail:	move.w	$100,$102
	move.w	#$0F00,$180(a6)		; red
.loop:	bra.s	.loop

; device/head: the drive, CHS mode, head 0
seldrv:	move.b	d7,d0
	or.b	#$A0,d0
	move.b	d0,DEVH(a5)
	rts

; wait until the drive is not busy; d0 = status
waitbsy:
	move.l	#400000,d1
.w:	move.b	STAT(a5),d0
	bpl.s	.ok
	subq.l	#1,d1
	bne.s	.w
	bra	fail
.ok:	rts

; wait for a data request; an error ends the test
waitdrq:
	move.l	#400000,d1
.w:	move.b	STAT(a5),d0
	bmi.s	.n
	btst	#0,d0
	bne	fail
	btst	#3,d0
	bne.s	.ok
.n:	subq.l	#1,d1
	bne.s	.w
	bra	fail
.ok:	rts

; d1 = LBA, d2 = sector count
setlba:	move.b	d2,COUNT(a5)
	move.b	d1,SECT(a5)
	move.l	d1,d0
	lsr.l	#8,d0
	move.b	d0,CYLL(a5)
	lsr.l	#8,d0
	move.b	d0,CYLH(a5)
	lsr.l	#8,d0
	and.b	#$0F,d0
	or.b	#$E0,d0
	or.b	d7,d0
	move.b	d0,DEVH(a5)
	rts

; d1 = cylinder, d3 = head, d4 = sector, d2 = sector count
setchs:	move.b	d2,COUNT(a5)
	move.b	d4,SECT(a5)
	move.b	d1,CYLL(a5)
	move.w	d1,d0
	lsr.w	#8,d0
	move.b	d0,CYLH(a5)
	move.b	d3,d0
	or.b	#$A0,d0
	or.b	d7,d0
	move.b	d0,DEVH(a5)
	rts

; the task file to (a1)
saveregs:
	move.b	SECT(a5),(a1)+
	move.b	CYLL(a5),(a1)+
	move.b	CYLH(a5),(a1)+
	move.b	DEVH(a5),(a1)+
	move.b	COUNT(a5),(a1)+
	clr.b	(a1)+
	rts

; d2 words to (a0), the status checked before every word
readwords:
.l:	bsr	waitdrq
	move.w	(a5),(a0)+
	subq.l	#1,d2
	bne.s	.l
	rts

; d2 words to (a0) in blocks of d5 words, each read after one DRQ
readblk:
.b:	bsr	waitdrq
	move.l	d5,d0
	cmp.l	d2,d0
	bls.s	.n
	move.l	d2,d0
.n:	sub.l	d0,d2
	subq.w	#1,d0
.l:	move.w	(a5),(a0)+
	dbra	d0,.l
	tst.l	d2
	bne.s	.b
	rts

; d2 words d3, d3 + d4, ... written in blocks of d5 words
writegen:
.b:	bsr	waitdrq
	move.l	d5,d0
	cmp.l	d2,d0
	bls.s	.n
	move.l	d2,d0
.n:	sub.l	d0,d2
	subq.w	#1,d0
.l:	move.w	d3,(a5)
	add.w	d4,d3
	dbra	d0,.l
	tst.l	d2
	bne.s	.b
	rts

; d2 words at (a0) must be d3, d3 + d4, ...
compare:
.l:	cmp.w	(a0)+,d3
	bne	fail
	add.w	d4,d3
	subq.l	#1,d2
	bne.s	.l
	rts
