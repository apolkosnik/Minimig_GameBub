; A cartridge image in the Action Replay's layout (AR5, DeMoN v2), for the
; Game Bub Minimig bench (carttest.s): the ROM at $A80000 with the control
; register's long word first and the level 7 vector at +$7C, the RAM at
; $AC0000, the custom registers as they were at the freeze at $ACF000. The
; core uploads the image to $A80000; anything without HRTmon's "HRT!" in
; its bytes 4 to 7 is taken for an Action Replay.
;
; At every entry it counts ($104), and copies to chip RAM what it sees: the
; cause of the freeze ($118 on, a byte an entry), its signature ($110), a
; word written to its RAM and read back ($114), COLOR00 in the snapshot
; ($116). It leaves through the control register, with the mode chip RAM
; has for this entry at $170 on, a byte an entry (bit 1: reads of CIA-A PRA
; freeze, bit 0: writes of CIA-B PRB): the cartridge hides at the first
; instruction fetched outside it.
; SPDX-License-Identifier: GPL-3.0-or-later

COUNT	equ	$104
INSIDE	equ	$110
RAMCHK	equ	$114
SNAP	equ	$116
CAUSES	equ	$118
MODES	equ	$170

	org	$A80000
rom:	dc.l	0			; the control register
	dc.b	'ARST'
	dcb.b	$7C-8,0
	dc.l	entry			; +$7C: the level 7 vector
	dcb.b	$100-$80,0

entry:	movem.l	d0-d2/a0,-(sp)
	move.w	COUNT,d1
	addq.w	#1,COUNT
	lea	MODES,a0
	move.b	(a0,d1.w),d2		; the mode to leave
	move.b	rom+1,d0		; the cause, in D1-D0
	and.b	#3,d0
	lea	CAUSES,a0
	move.b	d0,(a0,d1.w)
	move.l	rom+4,INSIDE
	clr.w	RAMCHK
	move.w	#$600D,$AC1000		; its RAM
	move.w	$AC1000,RAMCHK
	move.w	$ACF180,SNAP		; the snapshot of the custom registers: COLOR00
	move.b	d2,rom+1		; the mode; hide at the next fetch outside
	movem.l	(sp)+,d0-d2/a0
	rte
	even
