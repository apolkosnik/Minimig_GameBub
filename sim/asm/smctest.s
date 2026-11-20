; Code changed in chip RAM, test ROM (256 KB at $FC0000) for the Game Bub
; Minimig bench: a routine in chip RAM is run with the CPU's instruction
; cache on, changed, and run again at once, with no word to the CPU about
; it. The core fetches chip RAM's code through the SDRAM controller's CPU
; port and its cache there (the TG68K's, or the AP68040 variant's code
; cache), and the AP68040 keeps it in its own instruction cache too: every
; write to chip RAM is to reach both, the CPU's over the chip bus (a word,
; a byte, a long word in one 32-bit cycle with the AGA chipset) and the
; blitter's.
;
; Seven instructions and three jumps lie between a write and the routine's
; call. (A pipelined CPU has the instructions right behind a write in
; execution before the write is on the bus: smcdist.s measures how close
; the changed code may be.)
;
; The routine at $20000, one 16-byte line:
;   $20000  moveq #n,d0      (the line's first half)
;   $20002  nop (four)
;   $2000A  moveq #m,d1      (its second half)
;   $2000C  rts
;
;   1  the routine as copied there: d0 = 1, d1 = $11 (run three times)
;   2  a word written at $20000: d0 = 2
;   3  a word written at $2000A: d1 = $12
;   4  a byte written at $20001: d0 = 3
;   5  a long word written at $20000: d0 = 4
;   6  a word blitted to $20000: d0 = 5
;   7  a word blitted to $2000A: d1 = $16
;   8  another routine copied over it: d0 = 7, d1 = $17
;
;   $100  the step being run, $600D when all are done
;   $102  the step that failed, $104 d0 and $108 d1 as the routine left them,
;         $10C and $10E the routine's two MOVEQs as chip RAM holds them
;
; COLOR00 is green at the end, red after a failure.
; SPDX-License-Identifier: GPL-3.0-or-later

	machine	68020

CODE	equ	$20000
SRC	equ	$21000			; the words the blitter copies

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
	move.w	#$7005,SRC
	move.w	#$7216,SRC+2

	; ---- 1: the routine as copied
	move.w	#1,$100
	lea	rout1(pc),a0
	bsr	copy
	moveq	#2,d7
.r1:	moveq	#1,d2
	moveq	#$11,d3
	bsr	check
	dbra	d7,.r1

	; ---- 2: a word, the line's first half
	move.w	#2,$100
	move.w	#$7002,CODE
	moveq	#2,d2
	moveq	#$11,d3
	bsr	check3

	; ---- 3: a word, its second half
	move.w	#3,$100
	move.w	#$7212,CODE+10
	moveq	#2,d2
	moveq	#$12,d3
	bsr	check3

	; ---- 4: a byte
	move.w	#4,$100
	move.b	#3,CODE+1
	moveq	#3,d2
	moveq	#$12,d3
	bsr	check3

	; ---- 5: a long word
	move.w	#5,$100
	move.l	#$70044E71,CODE
	moveq	#4,d2
	moveq	#$12,d3
	bsr	check3

	; ---- 6: the blitter, the first half
	move.w	#6,$100
	lea	SRC,a0
	lea	CODE,a1
	bsr	blit
	moveq	#5,d2
	moveq	#$12,d3
	bsr	check3

	; ---- 7: the blitter, the second half
	move.w	#7,$100
	lea	SRC+2,a0
	lea	CODE+10,a1
	bsr	blit
	moveq	#5,d2
	moveq	#$16,d3
	bsr	check3

	; ---- 8: another routine over it
	move.w	#8,$100
	lea	rout2(pc),a0
	bsr	copy
	moveq	#7,d2
	moveq	#$17,d3
	bsr	check3

	move.w	#$600D,$100
	move.w	#$00F0,$180(a6)		; green
.done:	bra.s	.done

; the routine run once: d0 must be d2, d1 must be d3
check:
	moveq	#-1,d0
	moveq	#-1,d1
	jsr	CODE
	cmp.l	d2,d0
	bne.s	bad
	cmp.l	d3,d1
	bne.s	bad
	rts
; and three times (the changed line is in the cache again after the first)
check3:
	bsr.s	check
	bsr.s	check
	bra.s	check

bad:	move.w	$100,$102
	move.l	d0,$104
	move.l	d1,$108
	move.w	CODE,$10C		; (the routine's two words as data)
	move.w	CODE+10,$10E
	move.w	#$0F00,$180(a6)		; red
.stop:	bra.s	.stop

; 16 bytes from (a0) to the routine's place
copy:
	lea	CODE,a1
	moveq	#3,d0
.c:	move.l	(a0)+,(a1)+
	dbra	d0,.c
	rts

; one word from (a0) to (a1) with the blitter (D = A)
blit:
	bsr.s	bwait
	move.w	#$8240,$96(a6)		; DMACON: set, DMAEN, BLTEN
	move.l	#$09F00000,$40(a6)	; BLTCON0 (A and D, D = A), BLTCON1
	move.l	#$FFFFFFFF,$44(a6)	; BLTAFWM, BLTALWM
	move.l	a0,$50(a6)		; BLTAPT
	move.l	a1,$54(a6)		; BLTDPT
	clr.w	$64(a6)			; BLTAMOD
	clr.w	$66(a6)			; BLTDMOD
	move.w	#$0041,$58(a6)		; BLTSIZE: one line of one word; go
bwait:	btst	#6,$02(a6)		; DMACONR: BBUSY
	bne.s	bwait
	btst	#6,$02(a6)
	bne.s	bwait
	rts

rout1:	moveq	#1,d0
	nop
	nop
	nop
	nop
	moveq	#$11,d1
	rts
	nop
rout2:	moveq	#7,d0
	nop
	nop
	nop
	nop
	moveq	#$17,d1
	rts
	nop
