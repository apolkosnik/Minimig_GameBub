; The CIA's time of day counter under writes to the CIA's other registers,
; test ROM (256 KB at $FC0000) for the Game Bub Minimig bench. CIA-B's
; counter counts the lines (HSYNC). It is set to $000FF0 at line 40 of a
; frame and read at line 40 of the next one, the CPU writing CIA-B's timer
; A latch (a register that is not the counter's) all the while: it must
; have counted every line of the frame (PAL: 312 or 313, with one more or
; less for where in the line it was set and read), through the carry from
; its low 12 bits into the high ones. Then (step 4) 96 times: the counter
; set to $000FFE, the CPU writing chip RAM (a write that is not to a CIA at
; all) for four lines, each time a little later in the line: the counter's
; high 12 bits must be 1 every time. (Upstream's cia_timerd up to e559717
; took any write of the CPU's as one to the counter: the carry into the high
; 12 bits, which comes a clock after the count, was lost when it fell on a
; write, and the counter was 4096 short.)
;
;   $100  the step being run, $600D when all are done
;   $102  the step that failed (0: none)
;   $104  the counter as read (long)
;   $108  the lines it counted
;   $10A  step 4: the carries lost, of 96
;   $10C  step 4: the last counter read whose high part was not 1 (long)
;
; COLOR00 is green at the end, red after a failure.
; SPDX-License-Identifier: GPL-3.0-or-later

TALO	equ	$BFD400
TDLO	equ	$BFD800
TDME	equ	$BFD900
TDHI	equ	$BFDA00
CRA	equ	$BFDE00
CRB	equ	$BFDF00

STEP	equ	$100
FAILED	equ	$102
TOD	equ	$104
LINES	equ	$108
LOST	equ	$10A
LASTBAD	equ	$10C

START	equ	$000FF0

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
	lea	$7FFF0,sp
	move.w	#$0FF0,$180(a6)
	clr.w	FAILED
	clr.l	TOD
	clr.w	LINES
	move.w	#1,STEP
	move.b	#$7F,$BFDD00		; CIA-B: no interrupts
	move.b	#0,CRA			; its timers stopped
	move.b	#0,CRB			; (bit 7 clear: writes go to the counter, not the alarm)

	moveq	#40,d2
	bsr	waitline
	move.b	#(START>>16)&$FF,TDHI	; (stops the counter)
	move.b	#(START>>8)&$FF,TDME
	move.b	#START&$FF,TDLO		; (and it counts again)

	move.w	#2,STEP
	move.w	#200,d2			; to line 200, then to line 40 of the next frame
	bsr	hammer
	moveq	#40,d2
	bsr	hammer

	moveq	#0,d0
	move.b	TDHI,d0			; (latches the counter)
	swap	d0
	move.b	TDME,d0
	lsl.w	#8,d0
	move.b	TDLO,d0
	move.l	d0,TOD
	sub.l	#START,d0
	move.w	d0,LINES
	move.w	#3,STEP
	cmp.l	#311,d0
	blo	bad
	cmp.l	#314,d0
	bhi	bad

	; ---- 4: the carry under the CPU's writes elsewhere
	move.w	#4,STEP
	clr.w	LOST
	clr.l	LASTBAD
	moveq	#96-1,d7
.carry:	bsr	line
	move.w	d0,d2
	addq.w	#1,d2			; the next line's start
	cmp.w	#300,d2
	bhs.s	.carry			; (not across the frame's end)
	bsr	waitline
	move.w	d7,d0			; a little later every time
	and.w	#31,d0
.late:	dbra	d0,.late
	move.b	#0,TDHI
	move.b	#$0F,TDME
	move.b	#$FE,TDLO
	addq.w	#4,d2
.wr:	move.w	d1,$200.w
	move.w	d1,$202.w
	move.w	d1,$200.w
	addq.w	#1,d1
	bsr	line
	cmp.w	d2,d0
	bne.s	.wr
	moveq	#0,d0
	move.b	TDHI,d0
	swap	d0
	move.b	TDME,d0
	lsl.w	#8,d0
	move.b	TDLO,d0
	move.l	d0,d3
	lsr.l	#8,d3
	lsr.l	#4,d3
	cmp.w	#1,d3
	beq.s	.kept
	addq.w	#1,LOST
	move.l	d0,LASTBAD
.kept:	dbra	d7,.carry
	tst.w	LOST
	bne.s	bad
	move.w	#$600D,STEP
	move.w	#$00F0,$180(a6)
.done:	bra.s	.done

bad:	move.w	STEP,FAILED
	move.w	#$0F00,$180(a6)
.stop:	bra.s	.stop

; ---- the beam's line in d0
line:	move.l	4(a6),d0
	lsr.l	#8,d0
	and.w	#$1FF,d0
	rts

; ---- waits for line d2
waitline:
	bsr.s	line
	cmp.w	d2,d0
	bne.s	waitline
	rts

; ---- writes CIA-B's timer A latch until the beam is in line d2
hammer:	move.b	d1,TALO
	move.b	d1,TALO
	move.b	d1,TALO
	move.b	d1,TALO
	move.b	d1,TALO
	move.b	d1,TALO
	move.b	d1,TALO
	move.b	d1,TALO
	addq.b	#1,d1
	bsr.s	line
	cmp.w	d2,d0
	bne.s	hammer
	rts
