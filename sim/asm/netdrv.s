; netdrv: runs the real a2065.device (SANA-II) against the core's A2065, as
; a network stack does: opens unit 0, asks what the device is, takes the
; station address, configures the interface with it, sends a broadcast frame
; and reads a frame; then takes the device offline and online again, as a
; stack that is shut down and started does, and sends and reads once more. An AmigaDOS program (hunk executable) for a boot disk
; with the driver in Devs:Networks (sim/run_netdrv.sh); the bench is the MCU
; (sim_main --net-drv).
;
; Results in the unused user vectors of chip memory:
;   $100       step: 1 open, 2 query, 3 address, 4 configure, 5 send,
;              then read (the bench brings a frame at 5), 6 offline,
;              7 online, 8 send, 9 read (a frame again), $600D at the end,
;              $BAxx if request xx could not even be made
;   $102..$10C io_Error of each request in that order (open, query,
;              address, configure, send, read); $FFFF: not answered yet
;   $10E       the length of the data read
;   $110       the station address the driver gave (6 bytes)
;   $116       ios2_WireError of the configure request (long)
;   $11A       the query's address size in bits and the MTU (words)
;   $120       "ND" while the program runs
;   $122..$128 io_Error of offline, online, the second send and read
;   $12A       the length of the data read the second time
;   $130       the data read (first 48 bytes)
;   $160       the data read the second time (first 48 bytes)
; SPDX-License-Identifier: GPL-3.0-or-later

OpenDevice      equ -444
CloseDevice     equ -450
DoIO            equ -456
CreateIORequest equ -654
CreateMsgPort   equ -666

S2_DEVICEQUERY       equ 9
S2_GETSTATIONADDRESS equ 10
S2_CONFIGINTERFACE   equ 11
S2_BROADCAST         equ 17
S2_ONLINE            equ 25
S2_OFFLINE           equ 26
CMD_READ             equ 2

io_Command  equ 28
io_Error    equ 31
ios2_WireError  equ 32
ios2_PacketType equ 36
ios2_SrcAddr    equ 40
ios2_DstAddr    equ 56
ios2_DataLength equ 72
ios2_Data       equ 76
ios2_StatData   equ 80
ios2_BufferManagement equ 84
IOS2_SIZE   equ 88

STEP    equ $100
ERRS    equ $102
RDLEN   equ $10E
ADDR    equ $110
WIRE    equ $116
QUERY   equ $11A
MAGIC   equ $120
ERRS2   equ $122
RDLEN2  equ $12A
RDDATA  equ $130
RDDATA2 equ $160

	section code,code
start:
	move.l  4.w,a6
	lea     ERRS.w,a0
	moveq   #5,d0
.fill:
	move.w  #$FFFF,(a0)+
	dbra    d0,.fill
	lea     ERRS2.w,a0
	moveq   #3,d0
.fill2:
	move.w  #$FFFF,(a0)+
	dbra    d0,.fill2
	clr.w   RDLEN.w
	clr.w   RDLEN2.w
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

	; open: the buffer functions of a stack that keeps flat buffers
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
	bne     done

	move.w  #2,STEP.w
	lea     query(pc),a0
	move.l  #30,(a0)
	move.l  a0,ios2_StatData(a4)
	moveq   #S2_DEVICEQUERY,d0
	bsr     doio
	move.w  d0,ERRS+2.w
	lea     query(pc),a0
	move.w  16(a0),QUERY+0.w        ; AddrFieldSize
	move.w  20(a0),QUERY+2.w        ; MTU (low word)

	move.w  #3,STEP.w
	moveq   #S2_GETSTATIONADDRESS,d0
	bsr     doio
	move.w  d0,ERRS+4.w
	move.l  ios2_DstAddr(a4),ADDR.w ; the board's own address
	move.w  ios2_DstAddr+4(a4),ADDR+4.w

	move.w  #4,STEP.w
	move.l  ios2_DstAddr(a4),ios2_SrcAddr(a4)
	move.w  ios2_DstAddr+4(a4),ios2_SrcAddr+4(a4)
	moveq   #S2_CONFIGINTERFACE,d0
	bsr     doio
	move.w  d0,ERRS+6.w
	move.l  ios2_WireError(a4),WIRE.w
	tst.w   d0
	bne     done

	; a broadcast of 46 bytes, type $0806
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
	moveq   #S2_BROADCAST,d0
	bsr     doio
	move.w  d0,ERRS+8.w

	; read a frame of type $0800 (the bench brings it now)
	move.l  #$0800,ios2_PacketType(a4)
	move.l  #rxdata,ios2_Data(a4)
	move.w  #5,STEP.w
	moveq   #CMD_READ,d0
	bsr     doio
	move.w  d0,ERRS+10.w
	move.w  ios2_DataLength+2(a4),RDLEN.w
	lea     rxdata,a0
	lea     RDDATA.w,a1
	moveq   #47,d0
.rxcopy:
	move.b  (a0)+,(a1)+
	dbra    d0,.rxcopy

	; offline and online again, then a broadcast of 50 bytes and a read
	move.w  #6,STEP.w
	moveq   #S2_OFFLINE,d0
	bsr     doio
	move.w  d0,ERRS2+0.w
	move.w  #7,STEP.w
	moveq   #S2_ONLINE,d0
	bsr     doio
	move.w  d0,ERRS2+2.w

	move.w  #8,STEP.w
	lea     txdata,a0
	moveq   #49,d0
	moveq   #$33,d1
.txfill2:
	move.b  d1,(a0)+
	addq.b  #3,d1
	dbra    d0,.txfill2
	move.l  #$0806,ios2_PacketType(a4)
	move.l  #50,ios2_DataLength(a4)
	move.l  #txdata,ios2_Data(a4)
	moveq   #S2_BROADCAST,d0
	bsr     doio
	move.w  d0,ERRS2+4.w

	move.l  #$0800,ios2_PacketType(a4)
	move.l  #rxdata,ios2_Data(a4)
	move.w  #9,STEP.w
	moveq   #CMD_READ,d0
	bsr     doio
	move.w  d0,ERRS2+6.w
	move.w  ios2_DataLength+2(a4),RDLEN2.w
	lea     rxdata,a0
	lea     RDDATA2.w,a1
	moveq   #47,d0
.rxcopy2:
	move.b  (a0)+,(a1)+
	dbra    d0,.rxcopy2

	move.l  a4,a1
	jsr     CloseDevice(a6)
done:
	move.w  #$600D,d0
	lea     ERRS.w,a0
	moveq   #5,d1
.any:
	tst.w   (a0)+
	beq.s   .next
	move.w  STEP.w,d0               ; the step that failed stays
.next:
	dbra    d1,.any
	lea     ERRS2.w,a0
	moveq   #3,d1
.any2:
	tst.w   (a0)+
	beq.s   .next2
	move.w  STEP.w,d0
.next2:
	dbra    d1,.any2
	move.w  d0,STEP.w
	moveq   #0,d0
	rts
cant:
	move.w  STEP.w,d0
	or.w    #$BA00,d0
	move.w  d0,STEP.w
	moveq   #20,d0
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
; S2_CopyToBuff, S2_CopyFromBuff (S2_Dummy = TAG_USER + $B0000)
tags:
	dc.l    $800B0001,0
	dc.l    $800B0002,0
	dc.l    0,0
query:
	dcb.l   8,0

	section data,bss
txdata:
	ds.b    64
rxdata:
	ds.b    1600
