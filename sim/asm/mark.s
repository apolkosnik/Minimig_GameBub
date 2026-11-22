; mark: an AmigaDOS program for the boot disks of the tests with real
; software. It adds one to the word at $100 of chip memory (the bench reads
; it: a Startup-Sequence calls it before and after the program under test)
; and puts "MK" at $102.
; SPDX-License-Identifier: GPL-3.0-or-later
	section code,code
start:
	addq.w  #1,$100.w
	move.w  #$4D4B,$102.w
	moveq   #0,d0
	rts
