; 68030 MMU test ROM (256 KB at $FC0000) for the Game Bub Minimig bench.
; Run with the 68030 and the "2M + 16M Z3 fast" memory preset. The TG68K's MMU translates with
; 1 KB pages (as AmigaOS 3.2's mmu.library sets it up): TC $80A87700, IS 8,
; TIA 7, TIB 7. Table A ($10000) maps every 128 KB one to one with early
; termination page descriptors, except $200000-$21FFFF (LOG): table B
; ($10200) maps its 128 pages of 1 KB to the 128 KB at PHYS ($40000)
; scattered: logical page j to physical page perm(j) = (j * 37 + 11) & 127.
; Each long of physical page p holds $5A000000 | p << 16 | its offset.
;
;   1  physical pages filled, tables built, code written (MMU off)
;   2  MMU on: four rounds of reads over pages 0..119 in scattered orders,
;      every read checked (the micro-TLB's four entries for data reads,
;      chosen by bits 11:10 of the page, kept evicting each other)
;   3  reads whose base register is in another page than the address:
;      4(An) from a page's last long, -4(An) from a page's first, (An,Dn.l)
;      and (8,An,Dn.l) from LOG (the entry is chosen by a guess from the
;      base; a wrong guess must miss, never translate wrongly)
;   4  writes to the even pages (long at 512 by -8(An), word at 600 by
;      (An,Dn.l)), read back through the MMU; MMU off: the physical pages
;      hold them, the odd pages their pattern; table B's descriptors have
;      U set for every page read and M set exactly for the pages written
;   5  write protection: page 5 (read before: a read entry in the
;      micro-TLB) made write protected; a read works, a write takes the
;      access fault and leaves memory as it was; unprotected again, the
;      write lands
;   6  remapping: page 9 read, its descriptor pointed at page 10's
;      physical page, PFLUSHA: page 9 reads page 10's data; put back, page
;      9 its own
;   7  code: subroutines in pages 120..123 (bits 11:10 0..3, at offsets 0
;      and 1020) and one that starts with a NOP in the last word of page
;      124 and goes on in page 125, called in turn between data reads
;   8  timing: rounds of reads from four pages (one in each micro-TLB
;      entry), in raster lines (information, not checked): $10A 1024 rounds
;      in chip RAM (LOG pages 0..3); $10C 8192 rounds in Zorro III RAM
;      through the MMU (LOG2, $220000: table C ($10400) maps its pages to
;      Z3 + j * 1024; checked first: each page's first long), $10E the same
;      with the MMU off. Needs the "2M + 16M Z3 fast" memory preset.
;
;   $100  step being run, $600D when everything is done
;   $102  the step that failed, 0 when none did ($8000 | step: an
;         unexpected exception)
;   $10A  step 8's raster lines (chip RAM), $10C (Z3 RAM, MMU), $10E
;         (Z3 RAM, no MMU)
;   $120  failing address, $124 value read, $128 value expected
;
; COLOR00 is green at the end, red after a failure.
; SPDX-License-Identifier: GPL-3.0-or-later

	machine	68030

LOG	equ	$200000
PHYS	equ	$40000
TBLA	equ	$10000
TBLB	equ	$10200
TBLC	equ	$10400
LOG2	equ	$220000
Z3	equ	$40000000
CODEP	equ	120			; the code pages: 120..125
FAULT	equ	$140			; word: access faults taken
SAVSP	equ	$144			; where an expected access fault goes on
SAVPC	equ	$148

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
	clr.w	$10A
	clr.l	$10C
	clr.w	FAULT
	clr.l	SAVPC
	move.l	#buserr,$08		; access fault
	move.l	#unexp,$0C		; address error
	move.l	#unexp,$10		; illegal instruction
	move.l	#unexp,$2C		; F-line
	move.l	#unexp,$38		; MMU configuration error

	; ---- 1: pages, tables and code, MMU off
	move.w	#1,$100
	lea	PHYS,a0
	moveq	#0,d6			; physical page
.fp:	moveq	#0,d5			; offset
.fo:	move.l	d6,d0
	swap	d0
	or.w	d5,d0
	or.l	#$5A000000,d0
	move.l	d0,(a0)+
	addq.w	#4,d5
	cmp.w	#1024,d5
	bne.s	.fo
	addq.w	#1,d6
	cmp.w	#128,d6
	bne.s	.fp

	lea	TBLA,a0
	moveq	#0,d6
.ta:	cmp.w	#LOG>>17,d6
	bne.s	.ta2
	move.l	#TBLB|2,d0		; table descriptor, 4 byte descriptors
	bra.s	.tas
.ta2:	cmp.w	#LOG2>>17,d6
	bne.s	.et
	move.l	#TBLC|2,d0
	bra.s	.tas
.et:	move.l	d6,d0
	swap	d0
	add.l	d0,d0			; i << 17
	or.w	#1,d0			; early termination page descriptor
.tas:	move.l	d0,(a0)+
	addq.w	#1,d6
	cmp.w	#128,d6
	bne.s	.ta

	lea	TBLB,a1
	moveq	#0,d6
.tb:	move.l	d6,d0
	bsr	physpage		; a0: perm(j)'s physical page
	move.l	a0,d0
	or.w	#1,d0			; page descriptor
	move.l	d0,(a1)+
	addq.w	#1,d6
	cmp.w	#128,d6
	bne.s	.tb

	lea	TBLC,a1			; LOG2 page j: Z3 + j * 1024
	move.l	#Z3|1,d0
	move.w	#127,d6
.tc:	move.l	d0,(a1)+
	add.l	#1024,d0
	dbra	d6,.tc
	move.w	#(Z3>>16),$E80044	; autoconfig: the Zorro III board at Z3
	lea	Z3,a0			; first long of pages 0..3: $7E00000j
	move.l	#$7E000000,(a0)
	move.l	#$7E000001,1024(a0)
	move.l	#$7E000002,2048(a0)
	move.l	#$7E000003,3072(a0)

	; code: page 120 + i: moveq #i+1,d0 / rts at 0, moveq #i+$11,d0 /
	; rts at 1020; page 124: nop in its last word; page 125: moveq
	; #$21,d0 / rts at 0
	moveq	#0,d6
.code:	moveq	#CODEP,d0
	add.w	d6,d0
	bsr	physpage
	move.w	d6,d0
	add.w	#$7001,d0
	move.w	d0,(a0)
	move.w	#$4E75,2(a0)
	add.w	#$10,d0
	move.w	d0,1020(a0)
	move.w	#$4E75,1022(a0)
	addq.w	#1,d6
	cmp.w	#4,d6
	bne.s	.code
	moveq	#CODEP+4,d0
	bsr	physpage
	move.w	#$4E71,1022(a0)		; nop
	moveq	#CODEP+5,d0
	bsr	physpage
	move.w	#$7021,(a0)		; moveq #$21,d0
	move.w	#$4E75,2(a0)

	; ---- 2: MMU on, scattered reads
	move.w	#2,$100
	bsr	mmuon
	moveq	#0,d7			; round
.r2:	moveq	#0,d6			; k
.k2:	move.w	d6,d0
	mulu.w	#45,d0
	move.w	d7,d1
	mulu.w	#7,d1
	add.w	d1,d0
	and.w	#127,d0			; j
	cmp.w	#CODEP,d0
	bhs.s	.n2
	move.w	d6,d4
	mulu.w	#13,d4
	add.w	d7,d4
	and.w	#255,d4
	lsl.w	#2,d4			; offset
	bsr	expect			; d2: expected, a0: logical address
	move.l	(a0),d1
	cmp.l	d2,d1
	bne	fail
.n2:	addq.w	#1,d6
	cmp.w	#128,d6
	bne.s	.k2
	addq.w	#1,d7
	cmp.w	#4,d7
	bne.s	.r2

	; ---- 3: base register in another page
	move.w	#3,$100
	moveq	#0,d6			; j
.k3:	move.l	d6,d0
	addq.w	#1,d0
	moveq	#0,d4
	bsr	expect			; page j + 1, offset 0
	lea	-4(a0),a1		; page j's last long
	move.l	4(a1),d1
	lea	4(a1),a0
	cmp.l	d2,d1
	bne	fail
	move.l	d6,d0
	move.w	#1020,d4
	bsr	expect			; page j, offset 1020
	lea	4(a0),a1		; page j + 1's first long
	move.l	-4(a1),d1
	cmp.l	d2,d1
	bne	fail
	move.l	d6,d0
	moveq	#8,d4
	bsr	expect			; page j, offset 8, from LOG
	lea	LOG,a1
	move.l	a0,d3
	sub.l	a1,d3
	move.l	(a1,d3.l),d1
	cmp.l	d2,d1
	bne	fail
	move.l	d6,d0
	moveq	#16,d4
	bsr	expect			; page j, offset 16
	move.l	8(a1,d3.l),d1		; d3: page j's offset 8 from LOG
	cmp.l	d2,d1
	bne	fail
	addq.w	#1,d6
	cmp.w	#CODEP-1,d6
	bne	.k3

	; ---- 4: writes to the even pages
	move.w	#4,$100
	moveq	#0,d6			; j
.k4:	move.l	d6,d0
	lsl.l	#8,d0
	lsl.l	#2,d0
	lea	LOG+520,a1
	add.l	d0,a1			; page j, offset 520
	move.l	d6,d2
	lsl.w	#8,d2
	or.l	#$C3000077,d2
	move.l	d2,-8(a1)		; offset 512
	lea	LOG,a2
	move.l	d0,d3
	add.l	#600,d3
	move.w	d6,d1
	or.w	#$B000,d1
	move.w	d1,(a2,d3.l)		; offset 600
	lea	-8(a1),a0
	move.l	(a0),d1
	cmp.l	d2,d1
	bne	fail
	lea	(a2,d3.l),a0
	move.w	d6,d2
	or.w	#$B000,d2
	move.w	(a0),d1
	cmp.w	d2,d1
	bne	fail
	addq.w	#2,d6
	cmp.w	#CODEP,d6
	bne.s	.k4
	bsr	mmuoff
	moveq	#0,d6
.c4:	move.l	d6,d0
	bsr	physpage
	lea	512(a0),a0
	move.l	d6,d2
	btst	#0,d6
	bne.s	.odd4
	lsl.w	#8,d2
	or.l	#$C3000077,d2
	move.l	(a0),d1
	cmp.l	d2,d1
	bne	fail
	lea	600-512(a0),a0
	move.w	d6,d2
	or.w	#$B000,d2
	move.w	(a0),d1
	cmp.w	d2,d1
	bne	fail
	bra.s	.desc4
.odd4:	move.l	a0,d2			; the pattern: page's address bits
	sub.l	#PHYS+512,d2
	lsl.l	#6,d2			; page << 16
	or.l	#$5A000200,d2
	move.l	(a0),d1
	cmp.l	d2,d1
	bne	fail
.desc4:	lea	TBLB,a0
	move.l	d6,d0
	lsl.w	#2,d0
	add.w	d0,a0			; page j's descriptor
	move.l	(a0),d1
	and.l	#$18,d1			; M, U
	moveq	#$08,d2			; read: U
	btst	#0,d6
	bne.s	.du4
	moveq	#$18,d2			; written: M and U
.du4:	cmp.l	d2,d1
	bne	fail
	addq.w	#1,d6
	cmp.w	#CODEP,d6
	bne	.c4

	; ---- 5: write protection
	move.w	#5,$100
	or.l	#4,TBLB+5*4		; WP
	bsr	mmuon
	moveq	#5,d0
	moveq	#16,d4
	bsr	expect
	move.l	(a0),d1			; a read entry for page 5
	cmp.l	d2,d1
	bne	fail
	move.l	sp,SAVSP
	move.l	#.af5,SAVPC
	clr.w	FAULT
	move.l	#$DEADBEEF,(a0)		; must take the access fault
	clr.l	SAVPC
	moveq	#1,d2			; no fault: FAULT 0, expected 1
	moveq	#0,d1
	bra	fail
.af5:	clr.l	SAVPC
	moveq	#5,d0
	moveq	#16,d4
	bsr	expect
	move.w	FAULT,d1
	cmp.w	#1,d1
	beq.s	.f5
	moveq	#1,d2
	bra	fail
.f5:	move.l	(a0),d1			; unchanged
	cmp.l	d2,d1
	bne	fail
	and.l	#~4,TBLB+5*4
	pflusha
	move.l	#$600DF00D,d2
	move.l	d2,(a0)
	move.l	(a0),d1
	cmp.l	d2,d1
	bne	fail
	cmp.w	#1,FAULT		; still the one fault
	beq.s	.g5
	moveq	#1,d2
	move.w	FAULT,d1
	bra	fail
.g5:

	; ---- 6: remapping
	move.w	#6,$100
	moveq	#9,d0
	moveq	#32,d4
	bsr	expect
	move.l	(a0),d1			; page 9 in the ATC and the micro-TLB
	cmp.l	d2,d1
	bne	fail
	moveq	#10,d0
	bsr	physpage
	move.l	a0,d0
	or.w	#1,d0
	move.l	TBLB+9*4,d5		; page 9's descriptor
	move.l	d0,TBLB+9*4		; now page 10's physical page
	pflusha
	moveq	#10,d0
	moveq	#32,d4
	bsr	expect			; page 10's data
	sub.l	#1024,a0		; read at page 9
	move.l	(a0),d1
	cmp.l	d2,d1
	bne	fail
	move.l	d5,TBLB+9*4
	pflusha
	moveq	#9,d0
	moveq	#32,d4
	bsr	expect
	move.l	(a0),d1
	cmp.l	d2,d1
	bne	fail

	; ---- 7: code in the translated pages
	move.w	#7,$100
	moveq	#0,d7			; round
.r7:	moveq	#0,d6			; i
.i7:	move.l	d6,d0
	add.w	#CODEP,d0
	lsl.l	#8,d0
	lsl.l	#2,d0
	lea	LOG,a0
	add.l	d0,a0
	moveq	#0,d0
	jsr	(a0)			; page 120 + i at 0
	moveq	#1,d2
	add.w	d6,d2
	move.l	d0,d1
	cmp.l	d2,d1
	bne	fail
	move.l	d7,d0			; a data read between
	add.w	d6,d0
	and.w	#63,d0
	moveq	#64,d4
	move.l	a0,-(sp)
	bsr	expect
	move.l	(a0),d1
	cmp.l	d2,d1
	bne	fail
	move.l	(sp)+,a0
	moveq	#0,d0
	jsr	1020(a0)		; page 120 + i at 1020
	moveq	#$11,d2
	add.w	d6,d2
	move.l	d0,d1
	cmp.l	d2,d1
	bne	fail
	moveq	#0,d0
	jsr	LOG+(CODEP+4)*1024+1022	; nop, then page 125
	moveq	#$21,d2
	move.l	d0,d1
	cmp.l	d2,d1
	bne	fail
	addq.w	#1,d6
	cmp.w	#4,d6
	bne.s	.i7
	addq.w	#1,d7
	cmp.w	#16,d7
	bne.s	.r7

	; ---- 8: timing (pages 0..3, one in each entry)
	move.w	#8,$100
	lea	LOG,a0
	move.w	#1023,d7
	bsr	timing
	move.w	d4,$10A
	lea	LOG2,a0			; Z3 RAM through the MMU: check, then time
	moveq	#0,d6
.z8:	move.l	d6,d2
	or.l	#$7E000000,d2
	move.l	(a0),d1
	cmp.l	d2,d1
	bne	fail
	lea	1024(a0),a0
	addq.w	#1,d6
	cmp.w	#4,d6
	bne.s	.z8
	lea	LOG2,a0
	move.w	#8191,d7
	bsr	timing
	move.w	d4,$10C
	bsr	mmuoff
	lea	Z3,a0
	move.w	#8191,d7
	bsr	timing
	move.w	d4,$10E

	move.w	#$600D,$100
	move.w	#$00F0,$180(a6)		; green
.done:	bra.s	.done

; reads from a0, a0 + 1024, + 2048, + 3072, d7 + 1 rounds -> d4: raster
; lines taken
timing:
	lea	1024(a0),a1
	lea	2048(a0),a2
	lea	3072(a0),a3
	move.l	$04(a6),d3		; VPOSR, VHPOSR
.t:	move.l	(a0),d0
	move.l	(a1),d0
	move.l	(a2),d0
	move.l	(a3),d0
	dbra	d7,.t
	move.l	$04(a6),d4
	lsr.l	#8,d3
	and.w	#$1FF,d3
	lsr.l	#8,d4
	and.w	#$1FF,d4
	sub.w	d3,d4
	bpl.s	.p
	add.w	#312,d4
.p:	rts

; d0: logical page j -> a0: its physical page (PHYS + perm(j) * 1024)
physpage:
	move.l	d1,-(sp)
	move.l	d0,d1
	mulu.w	#37,d1
	add.w	#11,d1
	and.l	#127,d1
	lsl.l	#8,d1
	lsl.l	#2,d1
	add.l	#PHYS,d1
	move.l	d1,a0
	move.l	(sp)+,d1
	rts

; d0: logical page j, d4: offset -> a0: logical address, d2: the long
; there ($5A000000 | perm(j) << 16 | offset)
expect:
	move.l	d1,-(sp)
	move.l	d0,d1
	mulu.w	#37,d1
	add.w	#11,d1
	and.l	#127,d1
	swap	d1
	or.w	d4,d1
	or.l	#$5A000000,d1
	move.l	d1,d2
	move.l	d0,d1
	and.l	#$FFFF,d1
	lsl.l	#8,d1
	lsl.l	#2,d1
	add.l	#LOG,d1
	add.w	d4,d1
	move.l	d1,a0
	move.l	(sp)+,d1
	rts

mmuon:
	lea	crpval(pc),a0
	pmove	(a0),crp
	lea	tcval(pc),a0
	pmove	(a0),tc
	pflusha
	rts

mmuoff:
	lea	tcoff(pc),a0
	pmove	(a0),tc
	rts

	cnop	0,4
crpval:	dc.l	$7FFF0002,TBLA		; no lower limit, 4 byte descriptors
tcval:	dc.l	$80A87700		; E, PS 1 KB, IS 8, TIA 7, TIB 7
tcoff:	dc.l	0

fail:	move.l	a0,$120
	move.l	d1,$124
	move.l	d2,$128
	move.w	$100,$102
	lea	tcoff(pc),a0
	pmove	(a0),tc
	move.w	#$0F00,$DFF180		; red
.f:	bra.s	.f

buserr:	tst.l	SAVPC
	beq.s	unexp
	addq.w	#1,FAULT
	move.l	SAVSP,sp
	move.l	SAVPC,a0
	jmp	(a0)

unexp:	move.w	$100,d0
	or.w	#$8000,d0
	move.w	d0,$102
	lea	tcoff(pc),a0
	pmove	(a0),tc
	move.w	#$0F00,$DFF180
.u:	bra.s	.u
