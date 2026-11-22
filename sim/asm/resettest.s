; Reset test ROM (256 KB at $FC0000) for the Game Bub Minimig, the 68040 (the
; AP68040 variant): what the RESET instruction must leave in the RAM. A
; reboot of the system (exec's ColdReboot) pushes the data cache and runs
; RESET at once; RESET resets the chipset and takes the Zorro boards'
; configuration away, and the last writes before it must be in the RAM all
; the same. Run with the "2M + 32M Z3 fast" memory preset.
;
; The ROM starts again after each RESET and goes on from the phase noted in
; chip RAM ($110 a mark, $114 the phase):
;   1  64 KB of Zorro III RAM written through the data cache (copyback),
;      CPUSHA DC, RESET; then compared, the data cache off
;   2  17 long words written to Zorro III RAM with the data cache off, the
;      last right before RESET; compared
;   3  a line copied to Zorro III RAM with MOVE16, RESET; compared
;   4  17 long words written to chip RAM, the last right before RESET;
;      compared
; green: all four kept. Else COLOR00 and stop: red (1), orange (2), magenta
; (3), blue (4).
;
;   $100  the phase being run, $600D when everything is done
;   $102  the phase that failed, $104 the address, $108 what was read there
; SPDX-License-Identifier: GPL-3.0-or-later

	machine	68040

Z3	equ	$40100000
LONGS	equ	$4000			; phase 1: 64 KB
MARK	equ	$52535431		; "RST1"

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
	moveq	#0,d0			; the caches off (RESET leaves them as
	movec	d0,cacr			; they were) and empty
	cinva	bc
	move.b	#$E9,$E80048		; the Toccata sound card, first in the chain: $E90000
	move.w	#$4000,$E80044		; Zorro III RAM board at $40000000
	move.w	#$5000,$E80044		; RTG board
	moveq	#0,d0
	movec	d0,vbr
	move.l	#$0000C040,d0		; DTT0: $00xxxxxx noncacheable, serialized
	movec	d0,dtt0
	move.l	#$4000C020,d0		; DTT1: $40xxxxxx copyback
	movec	d0,dtt1
	move.l	#$00FFC000,d0		; ITT0: the code cacheable
	movec	d0,itt0
	move.l	#$00008000,d0		; the instruction cache on
	movec	d0,cacr

	cmp.l	#MARK,$110
	bne.s	cold
	move.w	$114,d0
	cmp.w	#1,d0
	beq	warm1
	cmp.w	#2,d0
	beq	warm2
	cmp.w	#3,d0
	beq	warm3
	cmp.w	#4,d0
	beq	warm4

cold:
	move.l	#MARK,$110
	clr.w	$102
	; ---- 1: through the data cache, pushed, RESET
	move.w	#1,$114
	move.w	#1,$100
	move.w	#$0500,$180(a6)		; running (dim red)
	move.l	#$80008000,d0		; the data cache on
	movec	d0,cacr
	lea	Z3,a0
	move.l	#LONGS-1,d7
	move.l	#$A5000000,d1
.f:	move.l	d1,(a0)+
	addq.l	#1,d1
	subq.l	#1,d7
	bpl.s	.f
	lea	start(pc),a0
	bra	reboot_push		; exec's ColdReboot: the dirty lines
					; out, then RESET

warm1:
	lea	Z3,a0
	move.l	#LONGS-1,d7
	move.l	#$A5000000,d1
.c:	move.l	(a0)+,d0
	cmp.l	d1,d0
	bne	bad
	addq.l	#1,d1
	subq.l	#1,d7
	bpl.s	.c
	; ---- 2: long words, the data cache off, the last before RESET
	move.w	#2,$114
	move.w	#2,$100
	move.w	#$0530,$180(a6)		; running (dim orange)
	lea	Z3+$20000,a1
	moveq	#15,d7
	move.l	#$5A000000,d1
.f:	move.l	d1,(a1)+
	addq.l	#1,d1
	dbf	d7,.f
	lea	start(pc),a0
	bra	reboot_wr

warm2:
	lea	Z3+$20000,a0
	moveq	#16,d7
	move.l	#$5A000000,d1
.c:	move.l	(a0)+,d0
	cmp.l	d1,d0
	bne	bad
	addq.l	#1,d1
	dbf	d7,.c
	; ---- 3: a line with MOVE16, RESET
	move.w	#3,$114
	move.w	#3,$100
	move.w	#$0505,$180(a6)		; running (dim magenta)
	lea	$1000,a1		; the line in chip RAM
	move.l	#$C3000001,(a1)
	move.l	#$C3000002,4(a1)
	move.l	#$C3000003,8(a1)
	move.l	#$C3000004,12(a1)
	lea	Z3+$30000,a2
	lea	start(pc),a0
	bra	reboot_m16

warm3:
	lea	Z3+$30000,a0
	moveq	#3,d7
	move.l	#$C3000001,d1
.c:	move.l	(a0)+,d0
	cmp.l	d1,d0
	bne	bad
	addq.l	#1,d1
	dbf	d7,.c
	; ---- 4: long words to chip RAM, the last before RESET
	move.w	#4,$114
	move.w	#4,$100
	move.w	#$0005,$180(a6)		; running (dim blue)
	lea	$2000,a1
	moveq	#15,d7
	move.l	#$3C000000,d1
.f:	move.l	d1,(a1)+
	addq.l	#1,d1
	dbf	d7,.f
	lea	start(pc),a0
	bra	reboot_wr

warm4:
	lea	$2000,a0
	moveq	#16,d7
	move.l	#$3C000000,d1
.c:	move.l	(a0)+,d0
	cmp.l	d1,d0
	bne	bad
	addq.l	#1,d1
	dbf	d7,.c
	clr.l	$110			; (a later run starts from the beginning)
	move.w	#$600D,$100
	move.w	#$00F0,$180(a6)		; green
.done:	bra.s	.done

; RESET and the jump in one long word, as exec has them (a0: where to),
; right after the push, the last write or the MOVE16
	cnop	0,4
	nop
reboot_push:
	cpusha	dc
	reset
	jmp	(a0)

	cnop	0,4
	nop
reboot_wr:
	move.l	d1,(a1)
	reset
	jmp	(a0)

	cnop	0,4
reboot_m16:
	move16	(a1)+,(a2)+
	reset
	jmp	(a0)

; (a0) - 4 did not hold d1: d0 read there
bad:	subq.l	#4,a0
	move.w	$114,$102
	move.l	a0,$104
	move.l	d0,$108
	clr.l	$110
	move.w	$114,d0
	add.w	d0,d0
	lea	colours-2(pc),a0
	move.w	(a0,d0.w),$180(a6)
.stop:	bra.s	.stop

colours:
	dc.w	$0F00,$0F80,$0F0F,$000F
