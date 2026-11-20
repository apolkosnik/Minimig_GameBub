; CPU, Zorro III RAM and RTG memory test ROM (256 KB at $FC0000) for the
; Game Bub Minimig bench. Run with the 68020 or 68030 and the "2M + 16M Z3
; fast" memory preset: the Zorro III board and the RTG board's memory are
; in the second SDRAM chip.
;
;   1  CPU: PMOVE TC,(a0) runs on the 68030 (its MMU), takes the F-line
;      exception on the 68020
;   2  autoconfig: the first board is the 16 MB Zorro III memory board,
;      given the base $40000000; the second the RTG board, given $50000000
;   3  a long at the start of every 64 KB of the Zorro III board (and its
;      last long) written with its address xor $5A5AA5A5
;   4  the same over the RTG board's 8 MB of memory ($50000000-$507FFFFF)
;   5  all of them read back (the Zorro III board after the RTG memory was
;      written, so neither overwrites the other), chip RAM written before
;      them unchanged
;   6  bytes and words at both boards, read back as longs
;
;   $100  step being run, $600D when everything is done
;   $102  the step that failed, 0 when none did
;   $104  1: PMOVE ran (68030), 0: F-line exception
;   $10A  the first board's autoconfig words at $E80000 and $E80002
;   $10E  the second board's
;   $120  failing address, $124 value read, $128 value expected
;
; COLOR00 is green at the end, red after a failure (-DDIAG: a colour for
; what failed, see fail).
; SPDX-License-Identifier: GPL-3.0-or-later

	machine	68030

Z3BASE	equ	$40000000
RTGBASE	equ	$50000000
CHIPPAT	equ	$C0FFEE00

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
	move.l	#fline,$2C		; F-line
	move.l	#fline,$10		; illegal instruction

	; ---- 1: CPU
	move.w	#1,$100
	clr.w	$104
	clr.w	$108
	lea	$200,a0
	pmove	tc,(a0)			; four bytes; F-line on a 68020
	tst.w	$108
	bne.s	.no030
	move.w	#1,$104
.no030:

	; ---- 2: autoconfig
	move.w	#2,$100
	move.w	$E80000,$10A
	move.w	$E80002,$10C
	move.w	#(Z3BASE>>16),$E80044	; Zorro III board: base
	move.w	$E80000,$10E
	move.w	$E80002,$110
	move.w	#(RTGBASE>>16),$E80044	; RTG board: base

	; chip RAM pattern, before the boards are written
	move.l	#CHIPPAT,$20000
	move.l	#CHIPPAT+1,$30000

	; ---- 3: the Zorro III board
	move.w	#3,$100
	lea	Z3BASE,a1
	move.w	#255,d7
.wz3:	move.l	a1,d0
	eor.l	#$5A5AA5A5,d0
	move.l	d0,(a1)
	add.l	#$10000,a1
	dbf	d7,.wz3
	lea	Z3BASE+$FFFFFC,a1
	move.l	a1,d0
	eor.l	#$5A5AA5A5,d0
	move.l	d0,(a1)

	; ---- 4: the RTG memory
	move.w	#4,$100
	lea	RTGBASE,a1
	move.w	#127,d7
.wrtg:	move.l	a1,d0
	eor.l	#$5A5AA5A5,d0
	move.l	d0,(a1)
	add.l	#$10000,a1
	dbf	d7,.wrtg
	lea	RTGBASE+$7FFFFC,a1
	move.l	a1,d0
	eor.l	#$5A5AA5A5,d0
	move.l	d0,(a1)

	; ---- 5: read back
	move.w	#5,$100
	lea	Z3BASE,a1
	move.w	#255,d7
.rz3:	bsr	check
	add.l	#$10000,a1
	dbf	d7,.rz3
	lea	Z3BASE+$FFFFFC,a1
	bsr	check
	lea	RTGBASE,a1
	move.w	#127,d7
.rrtg:	bsr	check
	add.l	#$10000,a1
	dbf	d7,.rrtg
	lea	RTGBASE+$7FFFFC,a1
	bsr	check
	lea	$20000,a1
	move.l	#CHIPPAT,d1
	bsr	checkv
	lea	$30000,a1
	move.l	#CHIPPAT+1,d1
	bsr	checkv

	; ---- 6: byte and word lanes
	move.w	#6,$100
	lea	Z3BASE+$1000,a1
	bsr	lanes
	lea	RTGBASE+$1000,a1
	bsr	lanes

	move.w	#$600D,$100
	move.w	#$00F0,$180(a6)		; green
done:	bra.s	done

; the long at a1 must be a1 xor $5A5AA5A5
check:
	move.l	a1,d1
	eor.l	#$5A5AA5A5,d1
; the long at a1 must be d1
checkv:
	move.l	(a1),d0
	cmp.l	d1,d0
	bne.s	fail
	rts

; bytes and words written at a1, read back as longs
lanes:
	move.b	#$11,(a1)
	move.b	#$22,1(a1)
	move.w	#$3344,2(a1)
	move.l	#$11223344,d1
	bsr.s	checkv
	move.w	#$5566,(a1)
	move.b	#$77,2(a1)
	move.b	#$88,3(a1)
	move.l	#$55667788,d1
	bra.s	checkv

fail:
	move.l	a1,$120
	move.l	d0,$124
	move.l	d1,$128
	move.w	$100,$102
	ifd	DIAG
	; -DDIAG (hardware): what failed as COLOR00. Step 6 (lanes): orange in
	; the Zorro III board, white in the RTG memory; step 5: blue in the
	; Zorro III board, magenta in the RTG memory, cyan in chip RAM
	move.l	a1,d0
	rol.l	#8,d0
	and.w	#$F0,d0			; the address's top nibble (4: Z3, 5: RTG)
	cmp.w	#6,$100
	bne.s	.s5
	move.w	#$0F80,d1		; orange: lanes, Zorro III
	cmp.w	#$40,d0
	beq.s	.col
	move.w	#$0FFF,d1		; white: lanes, RTG
	bra.s	.col
.s5:	move.w	#$00FF,d1		; cyan: chip RAM
	cmp.w	#$40,d0
	bne.s	.s5r
	move.w	#$000F,d1		; blue: Zorro III
	bra.s	.col
.s5r:	cmp.w	#$50,d0
	bne.s	.col
	move.w	#$0F0F,d1		; magenta: RTG
.col:	move.w	d1,$180(a6)
	else
	move.w	#$0F00,$180(a6)		; red
	endc
.stop:	bra.s	.stop

; F-line / illegal instruction: note it, skip the four byte instruction
fline:
	move.w	#1,$108
	addq.l	#4,2(sp)
	rte
