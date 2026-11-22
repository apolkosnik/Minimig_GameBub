; RTG test ROM (256 KB at $FC0000) for the Game Bub Minimig bench: the
; MiSTer RTG board (rtg.sv registers through fastchip, gb_rtg's picture on
; the framework's external picture). Run with the 68030 and the "2M + 32M
; Z3 fast" memory preset and --rtg-check.
;
;   1  autoconfig: the Zorro III memory board at $40000000, the RTG board at
;      $50000000 (its memory: $50000000-$507FFFFF, registers $50800100)
;   2  the board ID $5001 at $B8010E (the driver's fixed address) and at
;      $5080010E (the board's register window)
;   3  the palette: entry i = 00 / i / 3i / 255-i, written as longs at
;      $B80400 + 4i (as the driver's SetColorArray), three read back
;   4  nine modes, each: a region of the board's memory filled with
;      pseudo-random longs, the registers set (base $27000000 + offset, as
;      the driver's SetPanning), enabled, word $100 = $0100 + mode; the
;      bench checks a whole HDMI frame and writes the mode to word $102
;   5  the registers read back, the picture disabled
;
;   $100  $0100 + mode while a mode is shown, $600D at the end
;   $102  the mode the bench has checked
;   $104  the step that failed, 0 when none did
;   $120  failing address, $124 value read, $128 value expected
; SPDX-License-Identifier: GPL-3.0-or-later

	machine	68030

Z3BASE	equ	$40000000
RTGBASE	equ	$50000000
REG	equ	$B80100
PAL	equ	$B80400
FBBASE	equ	$27000000

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
	clr.w	$100
	clr.w	$102
	clr.w	$104
	ifd	CACHE040
	; rtgtest040.rom (the AP68040 variant): the 68040's instruction cache
	; on, as Kickstart's exec turns it on (a 68040 with its caches off
	; fetches every instruction word from the bus)
	machine	68040
	cinva	bc
	move.l	#$00008000,d0		; CACR IE
	movec	d0,cacr
	machine	68030
	endif

	; ---- 1: autoconfig
	move.w	#1,d7
	move.b	#$E9,$E80048		; the Toccata sound card, first in the chain: $E90000
	move.w	#(Z3BASE>>16),$E80044	; Zorro III memory board: base
	move.w	#(RTGBASE>>16),$E80044	; RTG board: base

	; ---- 2: board ID at both addresses
	move.w	#2,d7
	lea	REG+$E,a1
	moveq	#0,d0
	move.w	(a1),d0
	move.l	#$5001,d1
	bsr	checkv
	lea	RTGBASE+$800100+$E,a1
	moveq	#0,d0
	move.w	(a1),d0
	bsr	checkv

	; ---- 3: palette
	move.w	#3,d7
	lea	PAL,a0
	moveq	#0,d2
.pal:	bsr	palval
	move.l	d1,(a0)+
	addq.w	#1,d2
	cmp.w	#256,d2
	bne.s	.pal
	moveq	#0,d2
	bsr	palchk
	moveq	#77,d2
	bsr	palchk
	move.w	#255,d2
	bsr	palchk

	; ---- 4: the modes
	move.w	#4,d7
	lea	modes(pc),a2
	moveq	#1,d6			; mode number
.mode:	move.l	(a2)+,d3		; offset in the board's memory
	bmi	.modes_done
	move.w	(a2)+,d4		; format
	move.w	(a2)+,REG+$8		; hsize
	move.w	(a2)+,d5		; vsize
	moveq	#0,d1
	move.w	(a2)+,d1		; stride
	; fill stride * vsize + 16 bytes from the long holding the first byte
	mulu.w	d5,d1
	add.l	#16+3,d1
	lsr.l	#2,d1			; longs
	move.l	d3,d0
	and.l	#$FFFFFFFC,d0
	add.l	#RTGBASE,d0
	movea.l	d0,a0
	move.l	d6,d0
	mulu.w	#$1234,d0
	add.l	#$9E3779B9,d0		; seed
.fill:	move.l	d0,(a0)+
	mulu.l	#1664525,d0
	add.l	#1013904223,d0
	subq.l	#1,d1
	bne.s	.fill
	; registers
	move.l	d3,d0
	add.l	#FBBASE,d0
	move.l	d0,REG			; base (a long, as the driver writes it)
	move.w	d4,REG+$4		; format
	move.w	d5,REG+$A		; vsize
	move.w	-2(a2),REG+$C		; stride
	move.w	#1,REG+$6		; enable
	; base read back
	lea	REG,a1
	move.l	(a1),d0
	move.l	d3,d1
	add.l	#FBBASE,d1
	bsr	checkv
	; shown: wait for the bench
	move.w	d6,d0
	or.w	#$0100,d0
	move.w	d0,$100
.wait:	cmp.w	$102,d6
	bne.s	.wait
	addq.w	#1,d6
	bra	.mode
.modes_done:

	; ---- 5: registers, off
	move.w	#5,d7
	lea	REG+$8,a1
	moveq	#0,d0
	move.w	(a1),d0
	move.l	#2100,d1		; the last mode's hsize
	bsr	checkv
	move.w	#0,REG+$6
	lea	REG+$6,a1
	moveq	#0,d0
	move.w	(a1),d0
	moveq	#0,d1
	bsr	checkv

	move.w	#$600D,$100
	move.w	#$00F0,$180(a6)		; green
done:	bra.s	done

; d1 = palette entry d2: 00 / d2 / 3 d2 / 255 - d2
palval:
	moveq	#0,d1
	move.b	d2,d1
	lsl.l	#8,d1
	move.w	d2,d0
	mulu.w	#3,d0
	move.b	d0,d1
	lsl.l	#8,d1
	move.w	#255,d0
	sub.w	d2,d0
	move.b	d0,d1
	rts

; palette entry d2 read back as a long
palchk:
	bsr.s	palval
	move.l	d2,d0
	lsl.l	#2,d0
	add.l	#PAL,d0
	movea.l	d0,a1
	move.l	(a1),d0
	and.l	#$00FFFFFF,d0
	; falls through to checkv

; d0 must be d1
checkv:
	cmp.l	d1,d0
	bne.s	fail
	rts

fail:
	move.l	a1,$120
	move.l	d0,$124
	move.l	d1,$128
	move.w	d7,$104
	move.w	#$0F00,$180(a6)		; red
.stop:	bra.s	.stop

; offset, format, hsize, vsize, stride
	cnop	0,4
modes:
	dc.l	$000000
	dc.w	$23,640,480,640		; CLUT (the driver's code 3+32)
	dc.l	$100006
	dc.w	$34,320,240,704		; R5G6B5PC (4+16+32), base not aligned
	dc.l	$200003
	dc.w	$35,333,111,1001	; B8G8R8 (5+16+32), odd width, base, stride
	dc.l	$300000
	dc.w	$26,640,480,2560	; R8G8B8A8 (6+32)
	dc.l	$500000
	dc.w	$0C,1024,768,2048	; 15 bit 1555 (4+8), scaled down
	dc.l	$6A0000
	dc.w	$03,1100,300,1100	; CLUT, wider than 1024
	dc.l	$100000
	dc.w	$23,1280,720,1280	; CLUT, the HDMI picture's size: one to one
	dc.l	$400000
	dc.w	$23,1920,1080,1920	; CLUT, scaled down to the whole screen
	dc.l	$700002
	dc.w	$23,2100,150,2100	; CLUT, wider than 2048 (cut)
	dc.l	-1
