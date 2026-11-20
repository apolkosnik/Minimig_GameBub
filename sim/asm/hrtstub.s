; A cartridge image as HRTmon's, for the Game Bub Minimig bench (carttest.s):
; "HRT!" in its bytes 4 to 7, the entry at +$C, the configuration block the
; core fills in at +20 (22 bytes) and maxchip at +68. The core uploads it to
; $A10000; its 512 KB are RAM, hidden until the first freeze.
;
; At every entry (the freeze key: level 7, the vector given by the
; cartridge) it counts ($104), and copies to chip RAM what it sees: its
; signature ($110), a word written to its own RAM and read back ($114),
; COLOR00 in the mirror of the custom registers at $A9F000 ($116) and its
; configuration ($130: 22 bytes, then maxchip).
; SPDX-License-Identifier: GPL-3.0-or-later

COUNT	equ	$104
INSIDE	equ	$110
RAMCHK	equ	$114
SNAP	equ	$116
CFGCOPY	equ	$130

	org	$A10000
base:	dc.l	0
	dc.b	'HRT!'
	dc.l	0
	bra.w	entry			; +$C: the entry
	nop
	rts
cfg:	dcb.b	22,$EE			; +20: the configuration (the core's)
	dcb.b	68-42,0
maxchip: dc.l	$EEEEEEEE		; +68

entry:	movem.l	d0/a0-a1,-(sp)
	addq.w	#1,COUNT
	move.l	base+4,INSIDE
	lea	cfg(pc),a0
	lea	CFGCOPY,a1
	moveq	#21,d0
.c:	move.b	(a0)+,(a1)+
	dbra	d0,.c
	lea	maxchip(pc),a0
	moveq	#3,d0
.m:	move.b	(a0)+,(a1)+
	dbra	d0,.m
	clr.w	RAMCHK
	move.w	#$600D,base+$F000	; its memory is RAM
	move.w	base+$F000,RAMCHK
	move.w	$A9F180,SNAP		; the mirror of the custom registers: COLOR00
	movem.l	(sp)+,d0/a0-a1
	rte
	even
