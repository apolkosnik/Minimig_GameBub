; netdown: the real a2065.device (SANA-II) against the core's A2065 with no
; network at first (the handheld not on its dock): what the driver and a
; stack see of that, and that it works once the network is there. An
; AmigaDOS program (hunk executable) for a boot disk with the driver in
; Devs:Networks; the bench is the MCU (sim_main --net-down).
;
;   1  the device opened, 2 the station address taken, 3 the interface
;      configured (all as with a network: the chip is started)
;   4  a request to be told when the device goes offline (S2_ONEVENT), and
;      a broadcast. The driver ends a transmit request before it looks at
;      the chip's error, so this one may still be answered as sent; but the
;      frame must not reach the MCU, the event must come, and a second
;      broadcast must be refused
;   5  the bench brings the network up now. S2_ONLINE and a broadcast, again
;      until one is sent ($118 counts them, at most 200)
;   6  a frame read (the bench brings it)
;
; Results in the unused user vectors of chip memory:
;   $100       the step, $600D at the end, $BAxx if request xx could not
;              even be made
;   $102..$10C io_Error of open, address, configure, the second broadcast
;              without a network, the last broadcast with one, the read
;   $10E       the length of the data read
;   $110       ios2_WireError of that second broadcast (long)
;   $114       1: the offline event came, $116 io_Error of the first
;              broadcast without a network
;   $118       broadcasts tried in step 5
;   $120       "ND" while the program runs
;   $130       the data read (first 48 bytes)
; SPDX-License-Identifier: GPL-3.0-or-later

OpenDevice      equ -444
CloseDevice     equ -450
DoIO            equ -456
SendIO          equ -462
CheckIO         equ -468
CreateIORequest equ -654
CreateMsgPort   equ -666

S2_GETSTATIONADDRESS equ 10
S2_CONFIGINTERFACE   equ 11
S2_BROADCAST         equ 17
S2_ONEVENT           equ 23
S2_ONLINE            equ 25
CMD_READ             equ 2
S2EVENT_OFFLINE      equ $10

io_Device   equ 20
io_Unit     equ 24
io_Command  equ 28
io_Error    equ 31
ios2_WireError  equ 32
ios2_PacketType equ 36
ios2_SrcAddr    equ 40
ios2_DstAddr    equ 56
ios2_DataLength equ 72
ios2_Data       equ 76
ios2_BufferManagement equ 84
IOS2_SIZE   equ 88

STEP    equ $100
ERRS    equ $102
RDLEN   equ $10E
WIRE    equ $110
EVENT   equ $114
EVERR   equ $116
TRIES   equ $118
MAGIC   equ $120
RDDATA  equ $130

	section code,code
start:
	move.l  4.w,a6
	lea     ERRS.w,a0
	moveq   #5,d0
.fill:
	move.w  #$FFFF,(a0)+
	dbra    d0,.fill
	clr.w   RDLEN.w
	clr.l   WIRE.w
	clr.w   EVENT.w
	move.w  #$FFFF,EVERR.w
	clr.w   TRIES.w
	move.w  #1,STEP.w
	move.w  #$4E44,MAGIC.w

	jsr     CreateMsgPort(a6)
	move.l  d0,d6
	beq     cant
	move.l  d0,a0
	moveq   #IOS2_SIZE,d0
	jsr     CreateIORequest(a6)
	move.l  d0,a4
	tst.l   d0
	beq     cant
	move.l  d6,a0
	moveq   #IOS2_SIZE,d0
	jsr     CreateIORequest(a6)
	move.l  d0,a3                   ; the event's request
	tst.l   d0
	beq     cant

	lea     tags(pc),a0
	lea     copyto(pc),a1
	move.l  a1,4(a0)
	lea     copyfrom(pc),a1
	move.l  a1,12(a0)
	move.l  a0,ios2_BufferManagement(a4)
	lea     devname(pc),a0
	moveq   #0,d0
	move.l  a4,a1
	moveq   #0,d1
	jsr     OpenDevice(a6)
	moveq   #0,d0
	move.b  io_Error(a4),d0
	move.w  d0,ERRS+0.w
	bne     bad

	move.w  #2,STEP.w
	moveq   #S2_GETSTATIONADDRESS,d0
	bsr     doio
	move.w  d0,ERRS+2.w
	bne     bad

	move.w  #3,STEP.w
	move.l  ios2_DstAddr(a4),ios2_SrcAddr(a4)
	move.w  ios2_DstAddr+4(a4),ios2_SrcAddr+4(a4)
	moveq   #S2_CONFIGINTERFACE,d0
	bsr     doio
	move.w  d0,ERRS+4.w
	bne     bad

	; ---- 4: told when the device goes offline; a broadcast without a network
	move.w  #4,STEP.w
	move.l  io_Device(a4),io_Device(a3)
	move.l  io_Unit(a4),io_Unit(a3)
	move.l  ios2_BufferManagement(a4),ios2_BufferManagement(a3)
	move.w  #S2_ONEVENT,io_Command(a3)
	move.l  #S2EVENT_OFFLINE,ios2_WireError(a3)
	move.l  a3,a1
	jsr     SendIO(a6)
	bsr     fillbroadcast
	moveq   #S2_BROADCAST,d0
	bsr     doio
	move.w  d0,EVERR.w
	; the event (the driver's interrupt has it out by now; a little time all the same)
	move.l  #200000,d5
.event:
	move.l  a3,a1
	jsr     CheckIO(a6)
	tst.l   d0
	bne.s   .came
	subq.l  #1,d5
	bne.s   .event
	bra     bad                     ; the event must have come
.came:
	move.w  #1,EVENT.w
	; offline now: the next broadcast is refused
	bsr     fillbroadcast
	moveq   #S2_BROADCAST,d0
	bsr     doio
	move.w  d0,ERRS+6.w
	move.l  ios2_WireError(a4),WIRE.w
	tst.w   d0
	beq     bad

	; ---- 5: the network comes (the bench): online and a broadcast, until sent
	move.w  #5,STEP.w
.retry:
	addq.w  #1,TRIES.w
	cmp.w   #200,TRIES.w
	bhi     bad
	move.l  #60000,d0               ; (a pause: the bench has to see the step)
.pause:
	subq.l  #1,d0
	bne.s   .pause
	moveq   #S2_ONLINE,d0
	bsr     doio
	bsr     fillbroadcast
	moveq   #S2_BROADCAST,d0
	bsr     doio
	move.w  d0,ERRS+8.w
	bne.s   .retry

	; ---- 6: a frame of type $0800 read (the bench brings it now)
	move.l  #$0800,ios2_PacketType(a4)
	move.l  #rxdata,ios2_Data(a4)
	move.w  #6,STEP.w
	moveq   #CMD_READ,d0
	bsr     doio
	move.w  d0,ERRS+10.w
	bne.s   bad
	move.w  ios2_DataLength+2(a4),RDLEN.w
	lea     rxdata,a0
	lea     RDDATA.w,a1
	moveq   #47,d0
.rxcopy:
	move.b  (a0)+,(a1)+
	dbra    d0,.rxcopy

	move.l  a4,a1
	jsr     CloseDevice(a6)
	move.w  #$600D,STEP.w
	moveq   #0,d0
	rts
bad:
	; (the step that failed stays, marked)
	or.w    #$FA00,STEP.w
	moveq   #10,d0
	rts
cant:
	move.w  STEP.w,d0
	or.w    #$BA00,d0
	move.w  d0,STEP.w
	moveq   #20,d0
	rts

; a broadcast of 46 bytes, type $0806, into the request
fillbroadcast:
	lea     txdata,a0
	moveq   #45,d0
	moveq   #$51,d1
.txfill:
	move.b  d1,(a0)+
	addq.b  #5,d1
	dbra    d0,.txfill
	move.l  #$0806,ios2_PacketType(a4)
	move.l  #46,ios2_DataLength(a4)
	move.l  #txdata,ios2_Data(a4)
	rts

; d0: command; returns io_Error in d0
doio:
	move.w  d0,io_Command(a4)
	move.l  a4,a1
	jsr     DoIO(a6)
	moveq   #0,d0
	move.b  io_Error(a4),d0
	rts

; BOOL CopyToBuff(a0: to (ios2_Data), a1: from, d0: bytes)
copyto:
; BOOL CopyFromBuff(a0: to, a1: from (ios2_Data), d0: bytes)
copyfrom:
	tst.l   d0
	beq.s   .ok
.byte:
	move.b  (a1)+,(a0)+
	subq.l  #1,d0
	bne.s   .byte
.ok:
	moveq   #1,d0
	rts

devname:
	dc.b    "networks/a2065.device",0
	even
tags:
	dc.l    $800B0001,0
	dc.l    $800B0002,0
	dc.l    0,0

	section data,bss
txdata:
	ds.b    64
rxdata:
	ds.b    1600
