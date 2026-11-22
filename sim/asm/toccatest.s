; The Toccata sound card (rtl/minimig/fpga-toccata: the AD1848 codec and
; the playback FIFO of 1024 bytes), test ROM (256 KB at $FC0000) for the
; Game Bub Minimig bench. It drives the board as toccata.library does.
;
;   1  autoconfig: a Zorro II board of 64 KB, MacroSystems Germany (18260,
;      $4754), product 12; given the base $E90000
;   2  the codec's registers: the index read back, the data format (16 bit
;      stereo at 44100 Hz: $5B) written and read back, the DAC's attenuation
;      0 on both channels; the card made active (status $01: the FIFO empty,
;      no interrupt: status read $80)
;   3  200 stereo frames (800 bytes) into the FIFO: a square wave, eight
;      frames high and eight low, left +-$3000 and right +-$1000
;   4  playback with the half empty interrupt (status $95, level 6): every
;      interrupt reads the status ($08: the FIFO half empty, the interrupt
;      bit low), puts 64 frames (256 bytes) more of the wave in and counts;
;      after 16 with the right status the step is $600D, and it goes on
;
;   $100  the step being run, $600D when all are done
;   $102  the step that failed (0: none)
;   $104  level 6 interrupts taken (it goes on counting: at 44100 Hz, four
;         bytes a frame and 256 bytes an interrupt, 689 in a second)
;   $106  the status read at the last interrupt
;   $108  interrupts whose status was not $08
;   $10A  the data format register read back
;   $120  what was found / $124 what was expected, at a failure
;
; COLOR00 is green at the end, red after a failure.
; SPDX-License-Identifier: GPL-3.0-or-later

BOARD	equ	$E90000
STATUS	equ	BOARD+$0001		; the status register (the low byte)
FIFO	equ	BOARD+$2000		; a word: its low byte first, then its high
INDEX	equ	BOARD+$6001		; the AD1848's index register
DATA	equ	BOARD+$6801		; and its data register

STEP	equ	$100
FAILED	equ	$102
IRQS	equ	$104
LASTST	equ	$106
BADST	equ	$108
FORMAT	equ	$10A
FOUND	equ	$120
WANT	equ	$124

	org	$FC0000
	dc.l	$11114EF9
	dc.l	start

start:
	lea	$DFF000,a6
	move.w	#$7FFF,$9A(a6)
	move.w	#$7FFF,$9C(a6)
	move.w	#$7FFF,$96(a6)
	move.b	#3,$BFE201
	move.b	#2,$BFE001		; OVL off
	move.b	#$7F,$BFDD00		; CIA-B: no interrupts (level 6 is the card's)
	lea	$7FFF0,sp
	move.w	#$0FF0,$180(a6)
	clr.w	FAILED
	clr.w	IRQS
	clr.w	LASTST
	clr.w	BADST
	clr.w	phase
	move.l	#irq6,$78

	; ---- 1: autoconfig
	move.w	#1,STEP
	moveq	#0,d0
	move.b	$E80000,d0		; er_Type: Zorro II, no memory, no ROM
	and.b	#$F0,d0
	moveq	#0,d2
	move.b	#$C0,d2
	bsr	same
	moveq	#0,d0
	move.b	$E80002,d0		; 64 KB
	and.b	#$F0,d0
	moveq	#$10,d2
	bsr	same
	lea	$E80004,a0		; product 12
	bsr	acbyte
	moveq	#$0C,d2
	bsr	same
	lea	$E80010,a0		; manufacturer 18260
	bsr	acbyte
	moveq	#$47,d2
	bsr	same
	lea	$E80014,a0
	bsr	acbyte
	moveq	#$54,d2
	bsr	same
	move.b	#$E9,$E80048		; its base

	; ---- 2: the codec's registers
	move.w	#2,STEP
	move.b	#8,INDEX
	moveq	#0,d0
	move.b	INDEX,d0
	moveq	#8,d2
	bsr	same
	move.b	#$5B,DATA		; 16 bit, stereo, 44100 Hz
	moveq	#0,d0
	move.b	DATA,d0
	move.w	d0,FORMAT
	moveq	#$5B,d2
	bsr	same
	move.b	#6,INDEX		; the left DAC: no attenuation
	move.b	#0,DATA
	move.b	#7,INDEX		; the right DAC
	move.b	#0,DATA
	move.b	#$01,STATUS		; active: the FIFO empty, no interrupt
	moveq	#0,d0
	move.b	STATUS,d0
	moveq	#0,d2
	move.b	#$80,d2
	bsr	same

	; ---- 3: 200 frames into the FIFO
	move.w	#3,STEP
	move.w	#200-1,d3
.fill:	bsr	frame
	dbra	d3,.fill

	; ---- 4: playback, the FIFO filled again at every interrupt
	move.w	#4,STEP
	move.w	#$E000,$9A(a6)		; INTENA: EXTER (level 6)
	move.b	#$95,STATUS		; active, the codec's FIFO, playback, its interrupt
	move.w	#$2000,sr
.wait:	cmp.w	#16,IRQS
	blo.s	.wait
	tst.w	BADST
	bne.s	bad
	move.w	#$600D,STEP
	move.w	#$00F0,$180(a6)
.done:	bra.s	.done

bad:	move.w	STEP,FAILED
	move.w	#$0F00,$180(a6)
.stop:	bra.s	.stop

; ---- d0 must be d2
same:	cmp.l	d2,d0
	beq.s	.ok
	move.l	d0,FOUND
	move.l	d2,WANT
	addq.l	#4,sp
	bra.s	bad
.ok:	rts

; ---- an autoconfig byte from two nibbles at (a0), inverted; a0 += 4
acbyte:	moveq	#0,d0
	move.b	(a0),d0
	and.b	#$F0,d0
	move.b	2(a0),d1
	lsr.b	#4,d1
	or.b	d1,d0
	not.b	d0
	addq.l	#4,a0
	rts

; ---- the wave's next stereo frame into the FIFO (phase: frames so far)
frame:	move.w	phase,d0
	addq.w	#1,phase
	btst	#3,d0			; eight frames high, eight low
	bne.s	.low
	move.w	#$3000,FIFO
	move.w	#$1000,FIFO
	rts
.low:	move.w	#$D000,FIFO
	move.w	#$F000,FIFO
	rts

; ---- level 6: the FIFO is half empty
irq6:	movem.l	d0/d3,-(sp)
	moveq	#0,d0
	move.b	STATUS,d0		; (reading it ends the interrupt)
	move.w	d0,LASTST
	cmp.b	#$08,d0
	beq.s	.ok
	addq.w	#1,BADST
.ok:	moveq	#64-1,d3
.more:	bsr.s	frame
	dbra	d3,.more
	addq.w	#1,IRQS
	move.w	#$2000,$DFF09C		; INTREQ: EXTER
	move.w	#$2000,$DFF09C
	movem.l	(sp)+,d0/d3
	rte

; (the frames put into the FIFO so far: in chip RAM)
phase	equ	$130
