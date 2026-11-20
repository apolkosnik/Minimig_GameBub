; Reset vector test ROM (256 KB at $FC0000) for the Game Bub Minimig bench:
; the start address the CPU takes from the ROM after a reset, with the
; chipset AGA and a 68020 or better, so that the chip bus has its 32-bit
; access (chip32_en).
;
; After a reset the ROM overlays chip RAM at 0 and the CPU reads its stack
; pointer and start address there. The SDRAM hands out a long word's second
; word only from chip RAM, not from the ROM: read as one 32-bit access, the
; start address got as its low half the low word of the last long word read
; from chip RAM ($0000 after the core's start). This ROM makes both cases
; show:
;   - the ROM's first long word (the initial stack pointer) is BRA.S wrong
;     twice: a start address of $FC0000 ends in "wrong";
;   - once started right it reads a long word from chip RAM for ever whose
;     low word is "wrong"'s offset in the ROM: the next reset's start
;     address, if it takes that word, is "wrong" too.
;
;   $100  $600D once started at the right address
;   $102  $BAD0: started at a wrong address
;   $104  the number of starts at the right address (chip RAM keeps it over
;         a reset; $110 marks that it is valid)
;
; COLOR00: green running, red in "wrong".
; SPDX-License-Identifier: GPL-3.0-or-later

	machine	68020

MARK	equ	$56454331		; "VEC1"

	org	$FC0000
	dc.l	$60066006		; initial SP; as code: BRA.S wrong
	dc.l	start

wrong:					; $FC0008
	lea	$DFF000,a6
	move.w	#$7FFF,$9A(a6)		; INTENA off
	move.w	#$7FFF,$96(a6)		; DMACON off
	move.b	#3,$BFE201		; CIA-A DDRA: OVL and LED out
	move.b	#2,$BFE001		; OVL off: chip RAM at 0
	move.w	#$BAD0,$102
	move.w	#$0F00,$180(a6)		; red
.stop:	bra.s	.stop

	cnop	0,$100
start:					; $FC0100
	lea	$DFF000,a6
	move.w	#$7FFF,$9A(a6)		; INTENA off
	move.w	#$7FFF,$9C(a6)
	move.w	#$7FFF,$96(a6)		; DMACON off
	move.b	#3,$BFE201		; CIA-A DDRA: OVL and LED out
	move.b	#2,$BFE001		; OVL off: chip RAM at 0
	lea	$7FFF0,sp
	cmp.l	#MARK,$110
	beq.s	.warm
	move.l	#MARK,$110		; the first start
	clr.w	$102
	clr.w	$104
.warm:	addq.w	#1,$104
	move.l	#$A5A50008,$1000	; (low word: wrong - $FC0000)
	move.w	#$600D,$100
	move.w	#$00F0,$180(a6)		; green
.read:	move.l	$1000,d0		; the long word a reset finds left over
	bra.s	.read
