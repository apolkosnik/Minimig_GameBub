; The cartridge (HRTmon or the Action Replay), test ROM (256 KB at $FC0000)
; for the Game Bub Minimig bench. The core takes a cartridge image as a file
; of its own, uploads it with the CPU halted (HRTmon to $A10000 with its
; configuration block, the Action Replay to $A80000) and fits it; the Help
; key freezes the Amiga: level 7, the vector taken from the cartridge.
;
; The bench loads one of the two stubs as the cartridge (hrtstub.s,
; arstub.s: they count their entries and copy what they see to chip RAM)
; and presses Help twice. This ROM waits for the entries, and with the
; Action Replay (-DAR) its loop also makes the cartridge's other freezes:
;
;   HRTmon          entries 1 and 2: the Help key. Its memory is hidden
;                   until the first, and stays there after it.
;   Action Replay   entry 1: the first word written to chip RAM after a
;                   reset (cause 3). Then a loop reads CIA-A PRA and writes
;                   CIA-B PRB, which freeze nothing (mode 0), until entry 2:
;                   Help (cause 0), which leaves mode 2: the loop's next
;                   read of PRA is entry 3 (cause 1), which leaves mode 1:
;                   its next write of PRB is entry 4 (cause 2), which leaves
;                   mode 0: neither freezes again. Entry 5: Help again. The
;                   cartridge is hidden outside its entries.
;
; -DCACHE turns the instruction cache on (68020 and up) and runs the test
; from chip RAM: the 68040 (the AP68040 variant) caches code there, and a
; fetch its cache answers is not on the bus, where the Action Replay looks
; for the first instruction fetched outside it to hide again: the loop,
; all of it in the cache when Help comes, must still make entry 3. (Without
; -DCACHE the test runs from the ROM, which no cache holds.)
;
;   $100  the step being run, $600D when all are done
;   $102  the step that failed (0: none)
;   $104  the cartridge's entries (the stub counts)
;   $106  level 7 interrupts taken through the vector in RAM (must be none:
;         the cartridge gives its own)
;   $108  the long word at the cartridge's signature before the first
;         freeze, $10C after the last
;   $110  the same as the stub read it (the stub), $114 $600D when a word
;         the stub wrote to the cartridge's RAM read back, $116 COLOR00 in
;         the cartridge's copy of the custom registers ($0ABC)
;   $118  the Action Replay's causes, a byte an entry
;   $120  rounds of the waiting loops (the program goes on)
;   $130  HRTmon's configuration as the stub found it: 22 bytes, then
;         maxchip (4 bytes)
;   $170  the modes the Action Replay stub leaves, a byte an entry
;   $17E  the first word written to chip RAM
;
; COLOR00 is green at the end, red after a failure.
; SPDX-License-Identifier: GPL-3.0-or-later

	ifd	CACHE
	machine	68020
	endc

STEP	equ	$100
FAILED	equ	$102
COUNT	equ	$104
PLAIN	equ	$106
PRE	equ	$108
POST	equ	$10C
LOOPS	equ	$120
MODES	equ	$170
FIRSTW	equ	$17E

	ifd	AR
CARTSIG	equ	$A80004
SIG	equ	'ARST'
	else
CARTSIG	equ	$A10004
SIG	equ	'HRT!'
	endc

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
	ifd	CACHE
	move.l	#$00008001,d0		; the instruction cache on (bit 15: the
	movec	d0,cacr			; 68040's; bit 0: the 68020's and 68030's)
	; the test to chip RAM, a byte at a time (no word there yet), and on there
	lea	body(pc),a0
	lea	$20000,a1
	move.w	#bodyend-body-1,d0
.cp:	move.b	(a0)+,(a1)+
	dbra	d0,.cp
	jmp	$20000
	endc

; (position independent: it runs where it is, or copied)
body:
	move.w	#$0ABC,$180(a6)		; COLOR00, for the cartridge's copy

	; Bytes only so far: the Action Replay freezes at the first word
	; written to chip RAM, and its stub counts in these.
	lea	$100,a0
	moveq	#$7F,d0
.clr:	clr.b	(a0)+
	dbra	d0,.clr
	move.b	#2,MODES+1		; the modes the Action Replay's entries leave:
	move.b	#1,MODES+2		; 0, 2 (PRA), 1 (PRB), 0, 0
	lea	plain7(pc),a1		; the level 7 vector in RAM, a byte at a time
	move.l	a1,d1
	lea	$7C,a0
	moveq	#3,d0
.vec:	rol.l	#8,d1
	move.b	d1,(a0)+
	dbra	d0,.vec

	move.l	CARTSIG,d7		; the cartridge's memory, hidden

	; ---- the first word written to chip RAM
	clr.w	FIRSTW
	move.l	d7,PRE

	ifd	AR
	; ---- 1: that word froze the Amiga (cause 3)
	move.w	#1,STEP
	moveq	#1,d0
	bsr	wait
	; ---- 2: the loop; Help (cause 0), its PRA read (1), its PRB write (2)
	move.w	#2,STEP
.poll:	addq.l	#1,LOOPS
	move.b	$BFE001,d1
	move.b	#$FF,$BFD100
	cmp.w	#4,COUNT
	bcs.s	.poll
	; ---- 3: mode 0 again, neither freezes
	move.w	#3,STEP
	move.w	#2000,d2
.idle:	addq.l	#1,LOOPS
	move.b	$BFE001,d1
	move.b	#$FF,$BFD100
	dbra	d2,.idle
	cmp.w	#4,COUNT
	bne	bad
	; ---- 4: the Help key again
	move.w	#4,STEP
	moveq	#5,d0
	bsr	waitkey
	; ---- 5: what the stub saw, and the cartridge hidden again
	move.w	#5,STEP
	move.l	CARTSIG,d0
	move.l	d0,POST
	cmp.l	#SIG,d0
	beq	bad
	cmp.l	#SIG,PRE
	beq	bad
	cmp.l	#$03000102,$118		; the causes
	bne	bad
	tst.b	$11C
	bne	bad
	else
	; ---- 1: the Help key
	move.w	#1,STEP
	moveq	#1,d0
	bsr	waitkey
	; ---- 2: and again
	move.w	#2,STEP
	moveq	#2,d0
	bsr	waitkey
	; ---- 3: what the stub saw; HRTmon's memory is there after its first entry
	move.w	#3,STEP
	move.l	CARTSIG,d0
	move.l	d0,POST
	cmp.l	#SIG,d0
	bne	bad
	cmp.l	#SIG,PRE
	beq	bad
	endc

	move.w	#6,STEP
	cmp.l	#SIG,$110		; the stub read its own signature
	bne	bad
	cmp.w	#$600D,$114		; and its RAM
	bne	bad
	cmp.w	#$0ABC,$116		; and COLOR00 in its copy of the registers
	bne	bad
	tst.w	PLAIN			; no level 7 through the vector in RAM
	bne	bad

	move.w	#$600D,STEP
	move.w	#$00F0,$180(a6)		; green
.done:	addq.l	#1,LOOPS
	bra.s	.done

bad:	move.w	STEP,FAILED
	move.w	#$0F00,$180(a6)		; red
.stop:	bra.s	.stop

; until the cartridge has been entered d0 times: at once (a freeze the
; program made itself: the CPU takes it within a few instructions)
wait:	move.l	#20000,d2
.w:	cmp.w	COUNT,d0
	beq.s	.ok
	addq.l	#1,LOOPS
	subq.l	#1,d2
	bne.s	.w
	addq.l	#4,sp
	bra	bad
.ok:	rts

; the same, for as long as it takes (the bench presses the key)
waitkey:
.w:	addq.l	#1,LOOPS
	cmp.w	COUNT,d0
	bne.s	.w
	rts

; level 7 through the vector in RAM: the cartridge did not give its own
plain7:	addq.w	#1,PLAIN
	rte
bodyend:
