; 68040 MMU and data cache test ROM (256 KB at $FC0000) for the Game Bub
; Minimig bench: the AP68040 variant (variants/ap68040), memory "2M + 32M Z3
; fast". 4 KB pages (TC $8000), supervisor root pointer SRP = $10000:
;   - DTT0 / ITT0 ($0000C040) map $00000000-$00FFFFFF one to one, not
;     cached (chip RAM, the chips, the ROM: everything the program uses
;     besides the translated windows)
;   - LOG ($10000000, root entry 8, pointer entry 0, page table $10400):
;     32 pages of 4 KB scattered over PHYS ($40000-$5FFFF): logical page j
;     to physical page perm(j) = (j * 13 + 5) & 31; each long of physical
;     page p holds $5A000000 | p << 16 | its offset
;   - LOG2 ($11000000, root entry 8, pointer entry 64, page table $10500):
;     16 pages of 4 KB to the Zorro III board (Z3 + j * 4096), copyback
;
;   1  physical pages filled, tables built, code written, the Zorro III
;      board configured (MMU off)
;   2  MMU on: four rounds of reads over pages 0..29 in scattered orders
;   3  reads whose base register is in another page than the address:
;      4(An) from a page's last long, -4(An) from a page's first, (An,Dn.l)
;      and (8,An,Dn.l) from LOG
;   4  writes to the even pages (a long at 2048 by -8(An), a word at 3000 by
;      (An,Dn.l)), read back through the MMU; MMU off: the physical pages
;      hold them, the odd pages their pattern; the page descriptors have U
;      set for every page read and M exactly for the pages written
;   5  write protection: page 5 (read) made write protected, PFLUSHA; a
;      read works, a write takes the access fault (vector 2) and leaves
;      memory as it was; unprotected again, the write lands
;   6  remapping: page 9 read, its descriptor pointed at page 10's physical
;      page, PFLUSHA: page 9 reads page 10's data; put back, its own
;   7  code: subroutines in pages 30 and 31 (at 0 and 4092), the last one
;      starting with a NOP in page 30's last word, called in turn between
;      data reads
;   8  data cache (CACR DE and IE), copyback pages in Zorro III RAM (the
;      board filled with $FFFFFFFF in step 1): 1 KB written (one line in
;      each of the 64 sets: the replacement is not LRU, so no more, or a
;      line may be evicted and pushed) and read back; CINVA DC drops the
;      dirty lines without pushing them, so the first and last long read
;      $FFFFFFFF again from the board (a write that went through would be
;      there). Then all 16 KB written (evicting, pushing) and read back
;      through the cache, CPUSHA DC; MMU and caches off: the board holds
;      every long. (The board is not read while its lines are dirty: a
;      non-cached access would push them first, MC68040UM 4.6.2.)
;
;   $100  step being run, $600D when everything is done
;   $102  the step that failed, 0 when none did ($8000 | step: an
;         unexpected exception)
;   $120  failing address, $124 value read, $128 value expected
;
; COLOR00 is green at the end, red after a failure.
; SPDX-License-Identifier: GPL-3.0-or-later

	machine	68040

LOG	equ	$10000000
LOG2	equ	$11000000
PHYS	equ	$40000
ROOT	equ	$10000			; 128 root entries (512 bytes)
PTR	equ	$10200			; 128 pointer entries
PAGE	equ	$10400			; 64 page entries for LOG
PAGE2	equ	$10500			; 64 page entries for LOG2
Z3	equ	$40000000
CODEP	equ	30			; the code pages: 30, 31
FAULT	equ	$140
SAVSP	equ	$144
SAVPC	equ	$148
TTR	equ	$0000C040		; $00xxxxxx, any FC, enabled, not cached

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
	clr.w	FAULT
	clr.l	SAVPC
	move.l	#buserr,$08		; access fault
	move.l	#unexp,$0C		; address error
	move.l	#unexp,$10		; illegal instruction
	move.l	#unexp,$2C		; F-line

	; ---- 1: pages, tables, code, Zorro III board; MMU off
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
	cmp.w	#4096,d5
	bne.s	.fo
	addq.w	#1,d6
	cmp.w	#32,d6
	bne.s	.fp

	lea	ROOT,a0			; root and pointer tables: invalid
	move.w	#255,d0
.clr:	clr.l	(a0)+
	dbra	d0,.clr
	move.l	#PTR|3,ROOT+8*4		; root entry 8 -> pointer table
	move.l	#PAGE|3,PTR		; pointer entry 0 -> LOG's pages
	move.l	#PAGE2|3,PTR+64*4	; pointer entry 64 -> LOG2's pages
	lea	PAGE,a1
	moveq	#0,d6
.tb:	move.l	d6,d0
	bsr	physpage
	move.l	a0,d0
	or.w	#$0041,d0		; resident, CM 10 (not cached)
	move.l	d0,(a1)+
	addq.w	#1,d6
	cmp.w	#64,d6
	bne.s	.tb
	lea	PAGE2,a1
	move.l	#Z3|$0021,d0		; resident, CM 01 (copyback)
	moveq	#63,d6
.tc:	move.l	d0,(a1)+
	add.l	#4096,d0
	dbra	d6,.tc
	move.b	#$E9,$E80048		; the Toccata sound card, first in the chain: $E90000
	move.w	#(Z3>>16),$E80044	; autoconfig: the Zorro III board at Z3
	lea	Z3,a0			; its first 16 KB: $FFFFFFFF
	move.w	#4095,d0
.zf:	move.l	#$FFFFFFFF,(a0)+
	dbra	d0,.zf

	; code: page 30 at 0: moveq #1,d0 / rts; page 31 at 0: moveq #2,d0 /
	; rts; page 31 at 4092: moveq #3,d0 / rts; page 30's last word: nop,
	; going on at page 31's first: moveq #2,d0 / rts
	moveq	#CODEP,d0
	bsr	physpage
	move.l	#$70014E75,(a0)
	move.w	#$4E71,4094(a0)
	moveq	#CODEP+1,d0
	bsr	physpage
	move.l	#$70024E75,(a0)
	move.l	#$70034E75,4092(a0)

	; ---- 2: MMU on, scattered reads
	move.w	#2,$100
	bsr	mmuon
	moveq	#0,d7			; round
.r2:	moveq	#0,d6			; k
.k2:	move.w	d6,d0
	mulu.w	#11,d0
	move.w	d7,d1
	mulu.w	#7,d1
	add.w	d1,d0
	and.w	#31,d0			; j
	cmp.w	#CODEP,d0
	bhs.s	.n2
	move.w	d6,d4
	mulu.w	#77,d4
	add.w	d7,d4
	and.w	#1023,d4
	lsl.w	#2,d4			; offset
	bsr	expect
	move.l	(a0),d1
	cmp.l	d2,d1
	bne	fail
.n2:	addq.w	#1,d6
	cmp.w	#32,d6
	bne.s	.k2
	addq.w	#1,d7
	cmp.w	#4,d7
	bne.s	.r2

	; ---- 3: base register in another page
	move.w	#3,$100
	moveq	#0,d6
.k3:	move.l	d6,d0
	addq.w	#1,d0
	moveq	#0,d4
	bsr	expect			; page j + 1, offset 0
	lea	-4(a0),a1		; page j's last long
	move.l	4(a1),d1
	cmp.l	d2,d1
	bne	fail
	move.l	d6,d0
	move.w	#4092,d4
	bsr	expect			; page j, offset 4092
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
	move.l	8(a1,d3.l),d1
	cmp.l	d2,d1
	bne	fail
	addq.w	#1,d6
	cmp.w	#CODEP-1,d6
	bne	.k3

	; ---- 4: writes to the even pages
	move.w	#4,$100
	moveq	#0,d6
.k4:	move.l	d6,d0
	moveq	#12,d1
	lsl.l	d1,d0
	lea	LOG+2056,a1
	add.l	d0,a1			; page j, offset 2056
	move.l	d6,d2
	lsl.w	#8,d2
	or.l	#$C3000077,d2
	move.l	d2,-8(a1)		; offset 2048
	lea	LOG,a2
	move.l	d0,d3
	add.l	#3000,d3
	move.w	d6,d1
	or.w	#$B000,d1
	move.w	d1,(a2,d3.l)		; offset 3000
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
	lea	2048(a0),a0
	move.l	d6,d2
	btst	#0,d6
	bne.s	.odd4
	lsl.w	#8,d2
	or.l	#$C3000077,d2
	move.l	(a0),d1
	cmp.l	d2,d1
	bne	fail
	lea	3000-2048(a0),a0
	move.w	d6,d2
	or.w	#$B000,d2
	move.w	(a0),d1
	cmp.w	d2,d1
	bne	fail
	bra.s	.desc4
.odd4:	move.l	a0,d2			; the pattern
	sub.l	#PHYS+2048,d2
	lsl.l	#4,d2			; page << 16
	or.l	#$5A000800,d2
	move.l	(a0),d1
	cmp.l	d2,d1
	bne	fail
.desc4:	lea	PAGE,a0
	move.l	d6,d0
	lsl.w	#2,d0
	add.w	d0,a0
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
	or.l	#4,PAGE+5*4		; WP
	bsr	mmuon
	moveq	#5,d0
	moveq	#16,d4
	bsr	expect
	move.l	(a0),d1
	cmp.l	d2,d1
	bne	fail
	move.l	sp,SAVSP
	move.l	#.af5,SAVPC
	clr.w	FAULT
	move.l	#$DEADBEEF,(a0)		; must take the access fault
	nop
	clr.l	SAVPC
	moveq	#1,d2
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
.f5:	move.l	(a0),d1
	cmp.l	d2,d1
	bne	fail
	and.l	#~4,PAGE+5*4
	pflusha
	move.l	#$600DF00D,d2
	move.l	d2,(a0)
	move.l	(a0),d1
	cmp.l	d2,d1
	bne	fail

	; ---- 6: remapping
	move.w	#6,$100
	moveq	#9,d0
	moveq	#32,d4
	bsr	expect
	move.l	(a0),d1
	cmp.l	d2,d1
	bne	fail
	moveq	#10,d0
	bsr	physpage
	move.l	a0,d0
	or.w	#$0041,d0
	move.l	PAGE+9*4,d5
	move.l	d0,PAGE+9*4
	pflusha
	moveq	#10,d0
	moveq	#32,d4
	bsr	expect
	sub.l	#4096,a0		; read at page 9
	move.l	(a0),d1
	cmp.l	d2,d1
	bne	fail
	move.l	d5,PAGE+9*4
	pflusha
	moveq	#9,d0
	moveq	#32,d4
	bsr	expect
	move.l	(a0),d1
	cmp.l	d2,d1
	bne	fail

	; ---- 7: code in the translated pages
	move.w	#7,$100
	moveq	#0,d7
.r7:	moveq	#0,d0
	jsr	LOG+CODEP*4096		; page 30 at 0
	moveq	#1,d2
	move.l	d0,d1
	cmp.l	d2,d1
	bne	fail
	move.l	d7,d0			; a data read between
	and.w	#15,d0
	moveq	#64,d4
	bsr	expect
	move.l	(a0),d1
	cmp.l	d2,d1
	bne	fail
	moveq	#0,d0
	jsr	LOG+(CODEP+1)*4096+4092	; page 31 at 4092
	moveq	#3,d2
	move.l	d0,d1
	cmp.l	d2,d1
	bne	fail
	moveq	#0,d0
	jsr	LOG+CODEP*4096+4094	; nop, then page 31
	moveq	#2,d2
	move.l	d0,d1
	cmp.l	d2,d1
	bne	fail
	addq.w	#1,d7
	cmp.w	#16,d7
	bne.s	.r7

	; ---- 8: the data cache, copyback pages in Zorro III RAM
	move.w	#8,$100
	cinva	bc
	move.l	#$80008000,d0		; DE, IE
	movec	d0,cacr
	; first 1 KB: one line in each of the 64 sets, so none is evicted
	; (the replacement is not LRU): every line stays dirty in the cache
	lea	LOG2,a0
	move.w	#255,d7
	moveq	#0,d6
.w8:	move.l	d6,d0
	eor.l	#$3C5AA5C3,d0
	move.l	d0,(a0)+
	addq.l	#4,d6
	dbra	d7,.w8
	lea	LOG2,a0			; read back: the cache's lines
	move.w	#255,d7
	moveq	#0,d6
.v8:	move.l	d6,d2
	eor.l	#$3C5AA5C3,d2
	move.l	(a0)+,d1
	cmp.l	d2,d1
	bne	fail8
	addq.l	#4,d6
	dbra	d7,.v8
	cinva	dc			; the dirty lines dropped, not pushed
	move.l	#$FFFFFFFF,d2		; the board's own: the first and the last
	lea	LOG2,a0			; long of that 1 KB
	move.l	(a0),d1
	cmp.l	d2,d1
	bne	fail
	lea	LOG2+1020,a0
	move.l	(a0),d1
	cmp.l	d2,d1
	bne	fail
	; all 16 KB, evicting and pushing as it goes, read back through the
	; cache, then pushed
	lea	LOG2,a0
	move.w	#4095,d7
	moveq	#0,d6
.x8:	move.l	d6,d0
	eor.l	#$3C5AA5C3,d0
	move.l	d0,(a0)+
	addq.l	#4,d6
	dbra	d7,.x8
	lea	LOG2,a0
	move.w	#4095,d7
	moveq	#0,d6
.y8:	move.l	d6,d2
	eor.l	#$3C5AA5C3,d2
	move.l	(a0)+,d1
	cmp.l	d2,d1
	bne	fail8
	addq.l	#4,d6
	dbra	d7,.y8
	cpusha	dc			; push the dirty lines
	moveq	#0,d0
	movec	d0,cacr
	bsr	mmuoff
	lea	Z3,a0			; the board itself
	move.w	#4095,d7
	moveq	#0,d6
.p8:	move.l	d6,d2
	eor.l	#$3C5AA5C3,d2
	move.l	(a0)+,d1
	cmp.l	d2,d1
	bne	fail8
	addq.l	#4,d6
	dbra	d7,.p8

	move.w	#$600D,$100
	move.w	#$00F0,$180(a6)		; green
.done:	bra.s	.done

fail8:	subq.l	#4,a0
	bra	fail

; d0: logical page j -> a0: its physical page (PHYS + perm(j) * 4096)
physpage:
	move.l	d1,-(sp)
	move.l	d0,d1
	mulu.w	#13,d1
	addq.w	#5,d1
	and.l	#31,d1
	moveq	#12,d0
	lsl.l	d0,d1
	add.l	#PHYS,d1
	move.l	d1,a0
	move.l	(sp)+,d1
	rts

; d0: logical page j, d4: offset -> a0: logical address, d2: the long
; there ($5A000000 | perm(j) << 16 | offset)
expect:
	move.l	d1,-(sp)
	move.l	d0,d1
	mulu.w	#13,d1
	addq.w	#5,d1
	and.l	#31,d1
	swap	d1
	or.w	d4,d1
	or.l	#$5A000000,d1
	move.l	d1,d2
	move.l	d0,d1
	and.l	#$FFFF,d1
	swap	d1
	lsr.l	#4,d1			; j << 12
	add.l	#LOG,d1
	add.w	d4,d1
	move.l	d1,a0
	move.l	(sp)+,d1
	rts

mmuon:
	move.l	#ROOT,d0
	movec	d0,srp
	movec	d0,urp
	move.l	#TTR,d0
	movec	d0,dtt0
	movec	d0,itt0
	moveq	#0,d0
	movec	d0,dtt1
	movec	d0,itt1
	pflusha
	move.l	#$8000,d0		; E, 4 KB pages
	movec	d0,tc
	rts

mmuoff:
	moveq	#0,d0
	movec	d0,tc
	pflusha
	rts

fail:	move.l	a0,$120
	move.l	d1,$124
	move.l	d2,$128
	move.w	$100,$102
	moveq	#0,d0
	movec	d0,tc
	movec	d0,cacr
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
	moveq	#0,d0
	movec	d0,tc
	move.w	#$0F00,$DFF180
.u:	bra.s	.u
