; System test ROM (512 KB at $F80000, Kickstart's own format) for the Game
; Bub Minimig, the 68040 (the AP68040 variant): what Kickstart does and the
; other test ROMs do not -- the whole 512 KB ROM read as data, exceptions
; (also through a vector table in fast RAM), interrupts with STOP, and chip
; RAM shared with copper, bitplane and blitter DMA. sim/asm/build.sh sets the
; long at $FFFFF8 so that the ROM's longs add up to zero (carries dropped).
; Run with the "2M + 32M Z3 fast" memory preset. -DROM256 (systest256.rom):
; the same as a 256 KB ROM at $FC0000, its checksum over those 256 KB.
;
; COLOR00 through the setup: grey, white (the boards configured), pink (the
; control registers set), light green (the vectors set);
; while a step runs, a dim colour of its own
; (a hang shows it: dark red, brown, dark magenta, dark purple, dark blue,
; dark cyan); green when every step passed; else the step that failed:
;   1  red      the ROM's checksum, move.l, the data cache off
;   2  orange   the same with the data cache on (copyback, line fills)
;   3  magenta  exceptions, the vectors at 0: TRAP #0, ILLEGAL, F-line,
;               A-line, zero divide, CHK, privilege violation (from user
;               mode, back by TRAP #1): each taken once, through its own
;               vector, returning where it should
;   4  purple   the same with VBR in Zorro III RAM, the data cache on
;   5  blue     interrupts: 50 vertical blanks (level 3) and 20 CIA-A timer
;               A underflows (level 2), each waited for with STOP (a hang
;               shows dark blue)
;   6  cyan     chip RAM with copper, 4 bitplanes and the blitter running:
;               a CPU pattern written and read back, a blitter clear and a
;               blitter copy checked
; An exception no step expects shows the colour of the step it hit.
;
;   $100  step being run, $600D when everything is done
;   $102  the step that failed, $104 what (see each step), $10A the vector
;         offset of an unexpected exception
; SPDX-License-Identifier: GPL-3.0-or-later

	machine	68040

	ifd	ROM256
ROM	equ	$FC0000			; -DROM256: a 256 KB ROM at $FC0000
LONGS	equ	$10000
	else
ROM	equ	$F80000
LONGS	equ	$20000			; 512 KB
	endc
VEC	equ	$40000000		; step 4's vector table (Zorro III RAM)
USPTOP	equ	$7E000			; the user stack
EXPV	equ	$140			; the vector offset expected
SKIP	equ	$144			; bytes the handler adds to the stacked PC
COUNT	equ	$148			; exceptions taken
GOTV	equ	$14C			; the vector offset taken
VBLS	equ	$150
TICKS	equ	$154
COPL	equ	$20000			; copper list
PLANES	equ	$30000			; 4 bitplanes
CPUBUF	equ	$50000			; the CPU's pattern
BLTSRC	equ	$58000
BLTDST	equ	$5C000

	org	ROM
	ifd	ROM256
	dc.l	$11114EF9
	else
	dc.l	$11144EF9
	endc
	dc.l	start

start:
	lea	$DFF000,a6
	move.w	#$7FFF,$9A(a6)		; INTENA off
	move.w	#$7FFF,$9C(a6)
	move.w	#$7FFF,$96(a6)		; DMACON off
	move.b	#3,$BFE201		; CIA-A DDRA: OVL and LED out
	move.b	#2,$BFE001		; OVL off: chip RAM at 0
	lea	$7FFF0,sp
	move.w	#$0888,$180(a6)		; grey: running
	clr.w	$102
	clr.w	$104
	clr.w	$10A
	move.b	#$E9,$E80048		; the Toccata sound card, first in the chain: $E90000
	move.w	#$4000,$E80044		; Zorro III RAM board at $40000000
	move.w	#$5000,$E80044		; RTG board
	move.w	#$0FFF,$180(a6)		; white: the boards configured
	moveq	#0,d0
	movec	d0,vbr
	move.l	#$0000C040,d0		; DTT0: $00xxxxxx noncacheable, serialized
	movec	d0,dtt0
	moveq	#0,d0
	movec	d0,dtt1
	move.l	#$00FFC000,d0		; ITT0: the code cacheable
	movec	d0,itt0
	cinva	bc
	move.l	#$00008000,d0		; the instruction cache on
	movec	d0,cacr
	move.w	#$0F8F,$180(a6)		; pink: the control registers set
	lea	8,a0			; vectors 2-63: unexpected
	moveq	#61,d7
.v:	move.l	#unexp,(a0)+
	dbf	d7,.v
	move.w	#$08F8,$180(a6)		; light green: the vectors set

	; ---- 1: the checksum, the data cache off
	move.w	#1,$100
	move.w	#$0500,$180(a6)		; running (dim)
	bsr	checksum

	; ---- 2: the checksum, the data cache on ($00xxxxxx copyback: the
	; bridge inhibits all but the ROM and the fast RAM)
	move.w	#2,$100
	move.w	#$0530,$180(a6)		; running (dim)
	move.l	#$0000C020,d0
	movec	d0,dtt0
	cinva	bc
	move.l	#$80008000,d0
	movec	d0,cacr
	bsr	checksum
	cinva	dc			; (nothing dirty: the ROM is only read)
	bsr	checksum
	move.l	#$00008000,d0
	movec	d0,cacr
	cinva	dc
	move.l	#$0000C040,d0
	movec	d0,dtt0

	; ---- 3: exceptions, the vectors at 0
	move.w	#3,$100
	move.w	#$0505,$180(a6)		; running (dim)
	bsr	setvec
	bsr	exceptions

	; ---- 4: exceptions, VBR in Zorro III RAM, the data cache on
	move.w	#4,$100
	move.w	#$0305,$180(a6)		; running (dim)
	lea	0,a0
	lea	VEC,a1
	move.w	#255,d7
.cv:	move.l	(a0)+,(a1)+
	dbf	d7,.cv
	move.l	#$401FC020,d0		; DTT1: $40-$5F copyback
	movec	d0,dtt1
	cinva	bc
	move.l	#$80008000,d0
	movec	d0,cacr
	move.l	#VEC,d0
	movec	d0,vbr
	bsr	exceptions
	moveq	#0,d0
	movec	d0,vbr
	cpusha	dc
	move.l	#$00008000,d0
	movec	d0,cacr
	cinva	dc
	moveq	#0,d0
	movec	d0,dtt1

	; ---- 5: interrupts
	move.w	#5,$100
	move.l	#vbl,$6C		; level 3
	move.l	#cia,$68		; level 2
	clr.l	VBLS
	clr.l	TICKS
	move.w	#$0008,$180(a6)		; dark blue: waiting for interrupts
	move.w	#$C020,$9A(a6)		; INTENA: master, VERTB
	move.w	#$2000,sr
	moveq	#49,d7
.vb:	stop	#$2000
	dbf	d7,.vb
	move.w	#$2700,sr
	move.w	#$0020,$9A(a6)
	move.w	#1,$104
	cmp.l	#50,VBLS
	blo	fail
	; CIA-A timer A, continuous, about 10 ms
	move.b	#$7F,$BFED01		; ICR: all off
	tst.b	$BFED01
	move.b	#$B5,$BFE401		; TA latch low
	move.b	#$1B,$BFE501		; TA latch high (7093)
	move.b	#$11,$BFEE01		; CRA: load, start, continuous
	move.b	#$81,$BFED01		; ICR: TA on
	move.w	#$0008,$9C(a6)
	move.w	#$C008,$9A(a6)		; INTENA: master, PORTS
	move.w	#$2000,sr
	moveq	#19,d7
.tk:	stop	#$2000
	cmp.l	#20,TICKS
	bhs.s	.tkd
	dbf	d7,.tk
.tkd:	move.w	#$2700,sr
	move.w	#$0008,$9A(a6)
	move.b	#$00,$BFEE01		; timer stopped
	move.b	#$7F,$BFED01
	move.w	#2,$104
	cmp.l	#20,TICKS
	blo	fail

	; ---- 6: chip RAM under DMA
	move.w	#6,$100
	move.w	#$0055,$180(a6)		; running (dim)
	bsr	dma
	move.w	#$7FFF,$96(a6)

	move.w	#$600D,$100
	move.w	#$00F0,$180(a6)		; green
.done:	bra.s	.done

; the ROM's 128K longs added up must be zero (the build sets $FFFFF8)
checksum:
	lea	ROM,a0
	move.l	#LONGS-1,d7
	moveq	#0,d1
.l:	add.l	(a0)+,d1
	subq.l	#1,d7
	bpl.s	.l
	move.w	#1,$104
	tst.l	d1
	bne	fail
	rts

; the expected exceptions' vectors at VBR 0 (step 4 copies them)
setvec:
	move.l	#hexc,$80		; TRAP #0
	move.l	#hsup,$84		; TRAP #1: back to supervisor mode
	move.l	#hexc,$10		; illegal instruction
	move.l	#hexc,$2C		; F-line
	move.l	#hexc,$28		; A-line
	move.l	#hexc,$14		; zero divide
	move.l	#hexc,$18		; CHK
	move.l	#hexc,$20		; privilege violation
	rts

; each exception taken once, through its own vector, returning past it
exceptions:
	move.w	#$80,EXPV		; TRAP #0
	clr.l	SKIP
	bsr	expect_begin
	trap	#0
	moveq	#1,d6
	bsr	expect_end
	move.w	#$10,EXPV		; ILLEGAL
	move.l	#2,SKIP
	bsr	expect_begin
	illegal
	moveq	#2,d6
	bsr	expect_end
	move.w	#$2C,EXPV		; F-line (coprocessor 7)
	move.l	#2,SKIP
	bsr	expect_begin
	dc.w	$FE00
	moveq	#3,d6
	bsr	expect_end
	move.w	#$28,EXPV		; A-line
	move.l	#2,SKIP
	bsr	expect_begin
	dc.w	$A000
	moveq	#4,d6
	bsr	expect_end
	move.w	#$14,EXPV		; zero divide
	clr.l	SKIP
	bsr	expect_begin
	moveq	#0,d1
	move.l	#1234,d0
	divu.w	d1,d0
	moveq	#5,d6
	bsr	expect_end
	move.w	#$18,EXPV		; CHK
	clr.l	SKIP
	bsr	expect_begin
	moveq	#10,d0
	moveq	#5,d1
	chk.w	d1,d0
	moveq	#6,d6
	bsr	expect_end
	move.w	#$20,EXPV		; privilege violation, from user mode
	move.l	#4,SKIP
	bsr	expect_begin
	lea	USPTOP,a0
	move.l	a0,usp
	andi.w	#$DFFF,sr		; user mode
	move.w	#$2700,sr		; privileged: the exception, skipped
	trap	#1			; back to supervisor mode
	moveq	#7,d6
	bsr	expect_end
	rts

expect_begin:
	clr.l	COUNT
	clr.w	GOTV
	rts
; exactly one exception, the one expected; d6: which (into $104)
expect_end:
	move.w	d6,$104
	cmp.l	#1,COUNT
	bne	fail
	move.w	GOTV,d0
	cmp.w	EXPV,d0
	bne	fail
	rts

; an expected exception: note it, step the stacked PC past the instruction
hexc:
	addq.l	#1,COUNT
	move.w	6(sp),d0
	and.w	#$0FFF,d0
	move.w	d0,GOTV
	move.l	SKIP,d0
	add.l	d0,2(sp)
	rte

; TRAP #1: return in supervisor mode
hsup:
	or.w	#$2000,(sp)
	rte

vbl:
	move.w	#$0020,$DFF09C
	move.w	#$0020,$DFF09C
	addq.l	#1,VBLS
	rte

cia:
	tst.b	$BFED01			; ICR read: cleared
	move.w	#$0008,$DFF09C
	move.w	#$0008,$DFF09C
	addq.l	#1,TICKS
	rte

; an exception nothing expected: its vector offset into $10A, the step's
; colour
unexp:
	move.w	6(sp),d0
	and.w	#$0FFF,d0
	move.w	d0,$10A
	move.w	#$FFFF,$104
	bra	fail

; d0 trashed; the step in $100 failed: its colour, and stop
fail:
	move.w	#$2700,sr
	move.w	#$7FFF,$DFF096		; DMA off: the copper paints COLOR00 in step 6
	move.w	#$7FFF,$DFF09A
	move.w	$100,$102
	move.w	$100,d0
	add.w	d0,d0
	lea	colours-2(pc),a0
	move.w	(a0,d0.w),$DFF180
.stop:	bra.s	.stop

colours:
	dc.w	$0F00,$0F80,$0F0F,$080F,$000F,$00FF

; ---- 6: copper, 4 lowres bitplanes and the blitter running while the CPU
; and the blitter work in chip RAM
dma:
	; the copper list: the bitplane pointers each frame, a colour change
	lea	COPL,a0
	move.l	#PLANES,d0
	move.w	#$00E0,d1		; BPL1PTH
	moveq	#3,d7
.cp:	move.w	d1,(a0)+
	swap	d0
	move.w	d0,(a0)+
	addq.w	#2,d1
	move.w	d1,(a0)+
	swap	d0
	move.w	d0,(a0)+
	addq.w	#2,d1
	add.l	#10240,d0
	dbf	d7,.cp
	move.l	#$01800055,(a0)+	; COLOR00 dark cyan (step 6 running)
	move.l	#$FFFFFFFE,(a0)+	; the end
	move.l	#COPL,$80(a6)		; COP1LC
	move.w	#$4200,$100(a6)		; BPLCON0: 4 planes, colour
	move.w	#$2C81,$8E(a6)		; DIWSTRT
	move.w	#$2CC1,$90(a6)		; DIWSTOP
	move.w	#$0038,$92(a6)		; DDFSTRT
	move.w	#$00D0,$94(a6)		; DDFSTOP
	clr.w	$108(a6)
	clr.w	$10A(a6)
	move.w	#$0000,$88(a6)		; COPJMP1
	move.w	#$83C0,$96(a6)		; DMACON: set, DMAEN, BPLEN, COPEN, BLTEN
	; the CPU's pattern, twice over
	moveq	#1,d5
.rep:	lea	CPUBUF,a0
	move.w	#4095,d7
	move.l	#$A5C30F1E,d0
.w:	move.l	d0,(a0)+
	rol.l	#3,d0
	addq.l	#7,d0
	dbf	d7,.w
	lea	CPUBUF,a0
	move.w	#4095,d7
	move.l	#$A5C30F1E,d0
.r:	move.w	#1,$104
	cmp.l	(a0)+,d0
	bne	fail
	rol.l	#3,d0
	addq.l	#7,d0
	dbf	d7,.r
	dbf	d5,.rep
	; the blitter: BLTSRC filled by the CPU, BLTDST cleared by a blit,
	; then BLTSRC copied over BLTDST (A -> D), both checked
	lea	BLTSRC,a0
	move.w	#2047,d7
	move.l	#$12345678,d0
.f:	move.l	d0,(a0)+
	add.l	#$01010101,d0
	dbf	d7,.f
	lea	BLTDST,a0
	move.w	#2047,d7
.g:	move.l	#$FFFFFFFF,(a0)+
	dbf	d7,.g
	bsr	bltwait
	move.l	#$01000000,$40(a6)	; BLTCON0: D only, minterm 0; BLTCON1 0
	move.l	#BLTDST,$54(a6)		; BLTDPT
	clr.w	$66(a6)			; BLTDMOD
	move.w	#(128<<6)|32,$58(a6)	; BLTSIZE: 128 rows of 32 words (8 KB)
	bsr	bltwait
	lea	BLTDST,a0
	move.w	#2047,d7
.z:	move.w	#2,$104
	tst.l	(a0)+
	bne	fail
	dbf	d7,.z
	move.l	#$09F00000,$40(a6)	; BLTCON0: A and D, D = A
	move.l	#$FFFFFFFF,$44(a6)	; BLTAFWM, BLTALWM
	move.l	#BLTSRC,$50(a6)		; BLTAPT
	move.l	#BLTDST,$54(a6)
	clr.w	$64(a6)			; BLTAMOD
	clr.w	$66(a6)
	move.w	#(128<<6)|32,$58(a6)
	bsr	bltwait
	lea	BLTDST,a0
	move.w	#2047,d7
	move.l	#$12345678,d0
.c:	move.w	#3,$104
	cmp.l	(a0)+,d0
	bne	fail
	add.l	#$01010101,d0
	dbf	d7,.c
	rts

bltwait:
	tst.w	$02(a6)			; (one access first, as on an A1000)
.bw:	btst	#14,$02(a6)		; DMACONR BBUSY
	bne.s	.bw
	rts
