; How soon after a write to code in chip RAM can the CPU run it? Test ROM
; (256 KB at $FC0000) for the Game Bub Minimig bench, a measurement, not in
; sim/run_tests.sh: a MOVEQ in chip RAM is changed by a byte write and
; called after K NOPs, K = 0, 1, 2, 4, 8, 16, 32, 64, sixteen rounds each
; (the value changing every round).
;
;   $200 + 2 * i  the rounds of the i-th K in which the old code ran
;   $100          $600D at the end
;
; The 68030 core: 0 everywhere. The AP68040 variant: 15 of 16 with no NOP (the
; JSR and its target are in execution before the write is on the bus), 0 with
; one NOP or more (the 68040's NOP waits for the writes).
;   sim/obj_dir/Vtb_top --kick asm/smcdist.rom --ms 700 --set 1044=2 \
;       --set 1048=4 --set 104C=8 --dump 100:8
; SPDX-License-Identifier: GPL-3.0-or-later
	machine	68020
CODE	equ	$20000
	org	$FC0000
	dc.l	$11114EF9
	dc.l	start
start:
	lea	$DFF000,a6
	move.w	#$7FFF,$9A(a6)
	move.w	#$7FFF,$96(a6)
	move.b	#3,$BFE201
	move.b	#2,$BFE001
	lea	$7FFF0,sp
	move.l	#$00008001,d0
	movec	d0,cacr
	move.l	#$70014E75,CODE		; moveq #1,d0 / rts
	lea	$200,a5
T	macro
	moveq	#15,d7
	moveq	#0,d5			; stale rounds
	moveq	#1,d4			; the value to write next
.r\@:	addq.b	#1,d4
	and.b	#$3F,d4
	move.b	d4,CODE+1		; the write
	rept	\1
	nop
	endr
	jsr	CODE
	cmp.b	d4,d0
	beq.s	.ok\@
	addq.w	#1,d5
.ok\@:	dbra	d7,.r\@
	move.w	d5,(a5)+
	endm
	T	0
	T	1
	T	2
	T	4
	T	8
	T	16
	T	32
	T	64
	move.w	#$600D,$100
.done:	bra.s	.done
