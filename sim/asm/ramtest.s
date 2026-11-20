; Fast RAM test ROM (256 KB at $FC0000) for the Game Bub Minimig bench: the
; CPU's transfers to its RAM in the SDRAM, every size and alignment, read
; back and compared, with the long word moved in one transfer (cpu_wrapper's
; ramlong1 / ramready_l) and, on the AP68040 variant, the data cache's line
; pushes and fills. Assembled four ways (sim/asm/build.sh):
;
;   ramtest       68030, "2M + 16M Z3 fast": the Zorro III RAM and the RTG
;                 board's memory (SDRAM chip 1)
;   ramtest_z2    68030, "2M + 8M fast": the Zorro II RAM (SDRAM chip 0)
;                 and the RTG board's memory
;   ramtest040    the AP68040 variant, Zorro III, its instruction cache on
;   ramtest040_z2 (as Kickstart has it; the data cache off); each region
;                 also run with the data cache in copyback (DTT0) and pushed
;                 and invalidated (CPUSHA, CINVA) between the writes and the
;                 reads: every read a line fill, every write in a line push
;
; For each region (64 KB in from the board's start):
;   2  longs written (address xor $5A5AA5A5), read back as longs, words
;      and bytes
;   3  words written, read back as longs
;   4  bytes written, read back as longs
;   5  mixed: the same sequence of byte / word / long writes at every
;      alignment, reads of what was just written folded into later
;      writes, MOVEM blocks, run on the region and on a buffer in chip RAM
;      (REF: the chip bus, not the SDRAM's CPU port); the two compared byte
;      by byte
;   6  timing (information, not checked; first region, raster lines): $10A
;      16 KB written by longs, $10C read by longs, $10E copied (long by
;      long) within the region; the 68040 with its data cache on: $110,
;      $112, $114 the same, from an invalidated cache, the dirty lines
;      pushed (CPUSHA) before the time is taken
;
;   $100  step being run, $600D when everything is done
;   $102  the step that failed, 0 when none did ($8000 | step: an
;         unexpected exception)
;   $104  the region being tested: 1 Zorro III, 2 Zorro II, 3 RTG; | $10
;         with the 68040's data cache on
;   $120  failing address, $124 value read, $128 value expected
;
; COLOR00 is green at the end, red after a failure.
; SPDX-License-Identifier: GPL-3.0-or-later

	ifd	CPU040
	machine	68040
	else
	machine	68030
	endc

Z2BASE	equ	$200000
Z3BASE	equ	$40000000
RTGBASE	equ	$50000000
REF	equ	$40000			; chip RAM reference buffer
SIZE	equ	$2000			; 8 KB per pattern (twice the 68040's data cache)
MIX	equ	$400			; the mixed sequence's area

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
	clr.w	$104
	clr.l	$10A
	clr.l	$10E
	clr.l	$112
	lea	$8,a0			; exception vectors 2-47 (bus error to TRAP #15)
	moveq	#45,d7
.vec:	move.l	#except,(a0)+
	dbf	d7,.vec
	ifd	CPU040
	cinva	bc
	move.l	#$00008000,d0		; CACR: the instruction cache on
	movec	d0,cacr
	endc

	; ---- 1: autoconfig
	move.w	#1,$100
	ifd	ZTWO
	move.w	#$2000,$E80048		; Zorro II RAM board ($200000)
	else
	move.w	#(Z3BASE>>16),$E80044	; Zorro III RAM board
	endc
	move.w	#(RTGBASE>>16),$E80044	; RTG board

	; ---- the regions, caches off
	ifd	ZTWO
	lea	Z2BASE+$10000,a1
	move.w	#2,$104
	else
	lea	Z3BASE+$10000,a1
	move.w	#1,$104
	endc
	moveq	#0,d6
	bsr	region
	bsr	timing
	lea	RTGBASE+$10000,a1
	move.w	#3,$104
	bsr	region

	ifd	CPU040
	; ---- the 68040's caches on: everything copyback (DTT0, ITT0 match
	; every address; the bridge inhibits all but the fast RAM and the ROM)
	move.l	#$00FFC020,d0
	movec	d0,dtt0
	move.l	#$00FFC000,d0
	movec	d0,itt0
	cinva	bc
	move.l	#$80008000,d0
	movec	d0,cacr
	moveq	#1,d6
	ifd	ZTWO
	lea	Z2BASE+$20000,a1
	move.w	#$12,$104
	else
	lea	Z3BASE+$20000,a1
	move.w	#$11,$104
	endc
	bsr	region
	bsr	timing
	lea	RTGBASE+$20000,a1
	move.w	#$13,$104
	bsr	region
	cpusha	dc			; the caches stay on (the loop below runs from them)
	endc

	move.w	#$600D,$100
	move.w	#$00F0,$180(a6)		; green
.done:	bra.s	.done

; the 68040 with its data cache on (d6 = 1): dirty lines pushed and the
; cache invalidated, so the reads that follow come from memory
flush	macro
	ifd	CPU040
	tst.b	d6
	beq.s	.nf\@
	cpusha	dc
	cinva	dc
.nf\@:
	endc
	endm

; ---- one region at a1
region:
	; ---- 2: longs
	move.w	#2,$100
	move.l	a1,a0
	move.w	#SIZE/4-1,d7
.w2:	move.l	a0,d0
	eor.l	#$5A5AA5A5,d0
	move.l	d0,(a0)+
	dbf	d7,.w2
	flush
	move.l	a1,a0			; as longs
	move.w	#SIZE/4-1,d7
.r2l:	move.l	a0,d2
	eor.l	#$5A5AA5A5,d2
	move.l	(a0),d1
	bsr	cmpl
	addq.l	#4,a0
	dbf	d7,.r2l
	flush
	move.l	a1,a0			; as words
	move.w	#SIZE/4-1,d7
.r2w:	move.l	a0,d3
	eor.l	#$5A5AA5A5,d3
	move.l	d3,d2
	swap	d2
	moveq	#0,d1
	move.w	(a0),d1
	and.l	#$FFFF,d2
	bsr	cmpl
	addq.l	#2,a0
	move.l	d3,d2
	and.l	#$FFFF,d2
	moveq	#0,d1
	move.w	(a0),d1
	bsr	cmpl
	addq.l	#2,a0
	dbf	d7,.r2w
	flush
	move.l	a1,a0			; as bytes
	move.w	#SIZE/4-1,d7
.r2b:	move.l	a0,d3
	eor.l	#$5A5AA5A5,d3
	moveq	#3,d5
.r2b1:	rol.l	#8,d3
	moveq	#0,d2
	move.b	d3,d2
	moveq	#0,d1
	move.b	(a0),d1
	bsr	cmpl
	addq.l	#1,a0
	dbf	d5,.r2b1
	dbf	d7,.r2b

	; ---- 3: words
	move.w	#3,$100
	move.l	a1,a0
	move.w	#SIZE/2-1,d7
.w3:	move.l	a0,d0
	eor.l	#$C3A55A3C,d0
	move.w	d0,(a0)+
	dbf	d7,.w3
	flush
	move.l	a1,a0
	move.w	#SIZE/4-1,d7
.r3:	move.l	a0,d2
	eor.l	#$C3A55A3C,d2
	swap	d2			; the first word's pattern in the high half
	move.l	a0,d0
	addq.l	#2,d0
	eor.l	#$C3A55A3C,d0
	move.w	d0,d2
	move.l	(a0),d1
	bsr	cmpl
	addq.l	#4,a0
	dbf	d7,.r3

	; ---- 4: bytes
	move.w	#4,$100
	move.l	a1,a0
	move.w	#SIZE-1,d7
.w4:	move.l	a0,d0
	eor.l	#$96E1F00F,d0
	move.b	d0,(a0)+
	dbf	d7,.w4
	flush
	move.l	a1,a0
	move.w	#SIZE/4-1,d7
.r4:	moveq	#3,d5
	moveq	#0,d2
	move.l	a0,d0
.r4b:	move.l	d0,d3
	eor.l	#$96E1F00F,d3
	lsl.l	#8,d2
	move.b	d3,d2
	addq.l	#1,d0
	dbf	d5,.r4b
	move.l	(a0),d1
	bsr	cmpl
	addq.l	#4,a0
	dbf	d7,.r4

	; ---- 5: the mixed sequence, on the region and on REF
	move.w	#5,$100
	move.l	a1,a0
	bsr	mixed
	lea	REF,a0
	bsr	mixed
	flush
	move.l	a1,a0
	lea	REF,a2
	move.w	#MIX-1,d7
.c5:	moveq	#0,d1
	moveq	#0,d2
	move.b	(a0),d1
	move.b	(a2)+,d2
	bsr	cmpl
	addq.l	#1,a0
	dbf	d7,.c5
	rts

; the mixed sequence at a0 (MIX bytes): a background of longs, then writes
; of every size at every alignment, each followed by reads of what it
; wrote (and of its neighbours) whose values the next writes carry on.
; Uses d0-d5, d7, a3-a5
mixed:
	move.l	a0,a3
	move.l	#$01234567,d0
	move.w	#MIX/4-1,d7
.bg:	move.l	d0,(a3)+
	add.l	#$11111111,d0
	dbf	d7,.bg
	move.l	a0,a3
	move.l	#$A5C3E187,d4		; the running value
	moveq	#47,d7			; 48 rounds of 20 bytes
.mx:	move.l	d4,1(a3)		; longs at offsets 1, 2, 3, 0
	move.l	2(a3),d0
	add.l	d0,d4
	move.l	d4,6(a3)
	move.w	8(a3),d0
	add.w	d0,d4
	move.l	d4,11(a3)
	move.b	12(a3),d0
	add.b	d0,d4
	move.l	d4,16(a3)
	move.l	16(a3),d0
	eor.l	d0,d4
	move.w	d4,13(a3)		; words at odd and even offsets
	move.w	12(a3),d0
	add.w	d0,d4
	move.w	d4,4(a3)
	move.l	4(a3),d0
	sub.l	d0,d4
	move.b	d4,7(a3)		; bytes
	move.b	d4,9(a3)
	move.l	6(a3),d0
	add.l	d0,d4
	rol.l	#5,d4
	lea	20(a3),a3
	dbf	d7,.mx
	; MOVEM blocks: eight longs out, read back at an odd offset, summed
	; into the next block
	move.l	a0,a3
	lea	$100(a3),a3
	moveq	#7,d7
.mm:	move.l	d4,d0
	move.l	d4,d1
	not.l	d1
	move.l	d4,d2
	swap	d2
	move.l	d4,d3
	rol.l	#7,d3
	move.l	d7,d5
	move.l	d4,a4
	move.l	d1,a5
	movem.l	d0-d5/a4-a5,(a3)
	movem.l	1(a3),d0-d5/a4-a5
	add.l	d0,d4
	add.l	d1,d4
	add.l	d2,d4
	add.l	d3,d4
	add.l	d5,d4
	add.l	a4,d4
	add.l	a5,d4
	lea	36(a3),a3
	dbf	d7,.mm
	move.l	d4,$3FC(a0)
	rts

; d1 read at a0, d2 expected: equal or the test fails
cmpl:
	cmp.l	d2,d1
	bne.s	fail
	rts
fail:
	move.l	a0,$120
	move.l	d1,$124
	move.l	d2,$128
	move.w	$100,$102
	move.w	#$0F00,$180(a6)		; red
.f:	bra.s	.f

except:
	move.w	$100,d0
	or.w	#$8000,d0
	move.w	d0,$102
	move.w	#$0F00,$180(a6)
.e:	bra.s	.e

; ---- 6: timing in the region at a1 (raster lines, under one frame each);
; d6 = 1 (the 68040's data cache on): from an invalidated cache, the dirty
; lines pushed before the time is taken, into $110..$114
timing:
	move.w	#6,$100
	lea	$10A,a4
	tst.b	d6
	beq.s	.t0
	lea	$110,a4
.t0:	flush
	move.l	a1,a0
	bsr	tstart
	move.w	#4095,d7
.tw:	move.l	d0,(a0)+
	dbf	d7,.tw
	flush
	bsr	tstop
	move.w	d4,(a4)+
	move.l	a1,a0
	bsr	tstart
	move.w	#4095,d7
.tr:	move.l	(a0)+,d0
	dbf	d7,.tr
	bsr	tstop
	move.w	d4,(a4)+
	flush
	move.l	a1,a0
	lea	$8000(a1),a2
	bsr	tstart
	move.w	#4095,d7
.tc:	move.l	(a0)+,(a2)+
	dbf	d7,.tc
	flush
	bsr	tstop
	move.w	d4,(a4)+
	rts

tstart:
	move.l	$04(a6),d3		; VPOSR, VHPOSR
	rts
tstop:
	move.l	$04(a6),d4
	lsr.l	#8,d3
	and.w	#$1FF,d3
	lsr.l	#8,d4
	and.w	#$1FF,d4
	sub.w	d3,d4
	bpl.s	.p
	add.w	#312,d4
.p:	rts
