; Speed benchmark ROM (256 KB at $FC0000) for the Game Bub Minimig bench: one
; loop, its passes counted in chip RAM ($200, a word), run with the "2M + 32M
; Z3 fast" memory preset. sim/bench.sh runs the loops on the tree's CPU and
; prints passes per 100 ms of the simulation (the count at 600 ms less the
; count at 500 ms, well after the start).
;
; One of (assembled by sim/asm/build.sh):
;   -DRD   16 KB of Zorro III RAM ($40010000) read, long by long
;   -DWR   written, long by long
;   -DCP   copied (to $40020000), long by long
;   -DM16  64 KB copied with MOVE16 (the 68040: a line read and a line
;          written per 16 bytes)
;   -DALU  1024 rounds of a register loop (ALU, shifts, a 32-bit multiply,
;          branches)
;   -DMIX  the same with loads and stores in a 256-byte buffer in Zorro III
;          RAM
;   -DCHIP a loop run from chip RAM (copied to $20000): 1024 rounds of two
;          bytes read from Zorro III RAM and written to chip RAM a line
;          apart (a delta animation's player, as Andromeda's Nexus 7 has
;          in its vertical blank interrupt)
;   -DCHIPALU  the ALU loop run from chip RAM
; -DCPU040: the 68040 (the AP68040 variant): its instruction cache on; with
; -DDC its data cache too, copyback for $40-$5F (DTT1), $00xxxxxx
; noncacheable (DTT0), the dirty lines pushed and the cache invalidated after
; each pass of RD / WR / CP / M16. (The 68030 core's controller cache is
; always on.)
; SPDX-License-Identifier: GPL-3.0-or-later

	ifd	CPU040
	machine	68040
	else
	machine	68030
	endc

	org	$FC0000
	dc.l	$11114EF9
	dc.l	start

start:
	lea	$DFF000,a6
	move.w	#$7FFF,$9A(a6)		; INTENA off
	move.w	#$7FFF,$96(a6)		; DMACON off
	move.b	#3,$BFE201		; CIA-A DDRA: OVL and LED out
	move.b	#2,$BFE001		; OVL off: chip RAM at 0
	lea	$7FFF0,sp
	clr.w	$200
	move.b	#$E9,$E80048		; the Toccata sound card, first in the chain: $E90000
	move.w	#$4000,$E80044		; Zorro III RAM board at $40000000
	move.w	#$5000,$E80044		; RTG board at $50000000

	ifd	CPU040
	move.l	#$0000C040,d0		; DTT0: $00xxxxxx noncacheable, serialized
	movec	d0,dtt0
	move.l	#$401FC020,d0		; DTT1: $40-$5F copyback
	movec	d0,dtt1
	move.l	#$00FFC000,d0		; ITT0: everything cacheable
	movec	d0,itt0
	cinva	bc
	ifd	DC
	move.l	#$80008000,d0		; CACR: both caches
	else
	move.l	#$00008000,d0		; CACR: the instruction cache
	endc
	movec	d0,cacr
	endc

	moveq	#1,d1
	move.l	#$12345678,d2
pass:	lea	$40010000,a0
	lea	$40020000,a1

	ifd	RD
	move.w	#4095,d7
.r:	move.l	(a0)+,d0
	dbf	d7,.r
	endc
	ifd	WR
	move.w	#4095,d7
.r:	move.l	d0,(a0)+
	dbf	d7,.r
	endc
	ifd	CP
	move.w	#4095,d7
.r:	move.l	(a0)+,(a1)+
	dbf	d7,.r
	endc
	ifd	M16
	move.w	#4095,d7
.r:	move16	(a0)+,(a1)+
	dbf	d7,.r
	endc

	ifd	CHIP
INCHIP	set	1
	endc
	ifd	CHIPALU
INCHIP	set	1
LOADS	set	0
	endc
	ifd	INCHIP
	; the loop below, copied to chip RAM and run there
	lea	chipcode(pc),a2
	lea	$20000,a3
	move.w	#(chipend-chipcode)/4,d0
.cc:	move.l	(a2)+,(a3)+
	dbf	d0,.cc
	jmp	$20000
chipcode:
	lea	$40010000,a0
	endc
	ifd	CHIP
	lea	$30000,a2
	move.w	#1023,d7
.r:	move.b	(a0)+,(a2)
	move.b	(a0)+,$58(a2)
	adda.w	#$B0,a2
	dbf	d7,.r
	endc

	ifd	ALU
LOADS	set	0
	endc
	ifd	MIX
LOADS	set	1
	endc
	ifd	LOADS
	move.w	#1023,d7
.r:	add.l	d1,d2
	eor.l	d7,d2
	lsl.l	#3,d1
	addq.l	#7,d1
	move.l	d2,d3
	swap	d3
	mulu.l	d3,d4
	sub.l	d4,d2
	if	LOADS
	move.l	d2,(a0)
	move.l	4(a0),d5
	add.l	d5,d1
	move.l	d1,4(a0)
	moveq	#$3C,d6
	and.w	d7,d6
	move.l	(a0,d6.w),d5
	add.l	d5,d2
	endif
	tst.l	d2
	bpl.s	.p
	neg.l	d2
.p:	dbf	d7,.r
	endc

	ifd	CPU040
	ifd	DC
	ifnd	LOADS
	cpusha	dc			; the dirty lines pushed, the cache emptied
	cinva	dc
	endc
	endc
	endc
	addq.w	#1,$200
	ifd	INCHIP
	jmp	$20000
	cnop	0,4
chipend:
	else
	bra	pass
	endc
