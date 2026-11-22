; envram: an AmigaDOS program for the boot disks of the tests with real
; software: ENV: and ENVARC: assigned to RAM: (a lock on it, which starts the
; RAM disk here and not from inside another process's DOS call), as
; a Workbench disk's Startup-Sequence does with C:Assign, so that a program
; looking for its settings gets "not found" and no requester.
; SPDX-License-Identifier: GPL-3.0-or-later
OpenLibrary  equ -552
CloseLibrary equ -414
Lock         equ -84
DupLock      equ -96
AssignLock   equ -612

	section code,code
start:
	move.l  4.w,a6
	lea     dosname(pc),a1
	moveq   #36,d0
	jsr     OpenLibrary(a6)
	tst.l   d0
	beq.s   .none
	move.l  d0,a6
	; a lock on RAM: (this starts the RAM disk, from this process)
	lea     ram(pc),a0
	move.l  a0,d1
	moveq   #-2,d2                  ; ACCESS_READ
	jsr     Lock(a6)
	move.l  d0,d4
	beq.s   .close
	move.l  d4,d1
	jsr     DupLock(a6)
	move.l  d0,d5
	lea     env(pc),a0
	move.l  a0,d1
	move.l  d4,d2
	jsr     AssignLock(a6)
	tst.l   d5
	beq.s   .close
	lea     envarc(pc),a0
	move.l  a0,d1
	move.l  d5,d2
	jsr     AssignLock(a6)
.close:
	move.l  a6,a1
	move.l  4.w,a6
	jsr     CloseLibrary(a6)
	moveq   #0,d0
	rts
.none:
	moveq   #20,d0
	rts

dosname: dc.b "dos.library",0
env:     dc.b "ENV",0
envarc:  dc.b "ENVARC",0
ram:     dc.b "RAM:",0
	even
