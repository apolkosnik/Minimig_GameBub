; The A2065 Ethernet board (gb_a2065: the Am7990 LANCE and the board's RAM
; in the FPGA), test ROM (256 KB at $FC0000) for the Game Bub Minimig
; bench. It drives the board as a2065.device does; the bench plays the
; Game Bub's MCU (--net-test): it takes the frames sent and brings frames,
; one for every frame this ROM reports received or step it reaches.
;
;   1  autoconfig: a Zorro II board of 64 KB, Commodore (514), product 112,
;      its serial number's last three bytes made the station address
;      00:80:10:xx:xx:xx ($110); given the base $EA0000 (the Toccata
;      sound card, before it in the chain, has $E90000)
;   2  the LANCE's registers: RAP read back, CSR0 = STOP, the chip's ID
;   3  the board's RAM: words and bytes
;   4  internal loopback: the initialisation block (INIT, IDON), STRT, a
;      frame of 64 bytes sent (TDMD) and received again with its CRC
;   5  stopped and started again in normal mode with interrupts (level 2):
;      a frame of 64 bytes in two buffers and one of 20 bytes (sent as 60)
;      go to the MCU
;   6  frames from the MCU: for the station, for another station (not
;      received), broadcast, a multicast group the logical address filter
;      has and one it has not (not received), and 600 bytes over three
;      buffers: four received, each checked ($104 counts them)
;   7  no descriptor left: a frame is missed (MISS)
;
;   $100  the step being run, $600D when all are done
;   $102  the step that failed (0: none)
;   $104  frames received and found right
;   $106  level 2 interrupts taken, $108 CSR0 at the last
;   $10A  frames asked of the bench (step 6)
;   $110  the station address
;   $120  what was found / $124 what was expected, at a failure
;
; COLOR00 is green at the end, red after a failure.
; SPDX-License-Identifier: GPL-3.0-or-later

BOARD	equ	$EA0000
RDP	equ	BOARD+$4000
RAP	equ	BOARD+$4002
RAM	equ	BOARD+$8000

STEP	equ	$100
FAILED	equ	$102
GOT	equ	$104
IRQS	equ	$106
LASTCSR	equ	$108
REQ	equ	$10A
MAC	equ	$110
FOUND	equ	$120
WANT	equ	$124

; the board's RAM, as the LANCE addresses it ($8000 on)
IBLK	equ	$0000
RXRING	equ	$0100
TXRING	equ	$0200
RXBUF	equ	$1000			; eight of 256 bytes
TXBUF	equ	$3000			; four of 1 KB
NRX	equ	8

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
	clr.w	GOT
	clr.w	IRQS
	clr.w	REQ
	clr.w	rxnext
	move.l	#irq2,$68

	; ---- 1: autoconfig
	move.w	#1,STEP
	move.b	#$E9,$E80048		; the Toccata sound card is first: $E90000
	move.b	$E80000,d0		; er_Type: Zorro II, no memory, no ROM
	and.b	#$F0,d0
	cmp.b	#$C0,d0
	bne	bad
	move.b	$E80002,d0		; 64 KB
	and.b	#$F0,d0
	cmp.b	#$10,d0
	bne	bad
	lea	$E80004,a0		; product 112
	bsr	acbyte
	cmp.b	#$70,d0
	bne	bad
	lea	$E80010,a0		; manufacturer 514
	bsr	acbyte
	cmp.b	#$02,d0
	bne	bad
	lea	$E80014,a0
	bsr	acbyte
	cmp.b	#$02,d0
	bne	bad
	lea	MAC,a1
	move.b	#$00,(a1)+
	move.b	#$80,(a1)+
	move.b	#$10,(a1)+
	lea	$E8001C,a0		; the serial number's last three bytes
	bsr	acbyte
	move.b	d0,(a1)+
	bsr	acbyte
	move.b	d0,(a1)+
	bsr	acbyte
	move.b	d0,(a1)+
	move.b	#$EA,$E80048		; its base

	; ---- 2: registers
	move.w	#2,STEP
	move.w	#$55,RAP
	move.w	RAP,d0
	cmp.w	#$55,d0
	bne	bad
	moveq	#0,d0
	bsr	rdcsr
	cmp.w	#$0004,d0		; STOP
	bne	bad
	moveq	#88,d0
	bsr	rdcsr
	cmp.w	#$0001,d0
	bne	bad
	moveq	#89,d0
	bsr	rdcsr
	cmp.w	#$3003,d0
	bne	bad

	; ---- 3: the board's RAM
	move.w	#3,STEP
	lea	RAM+$7000,a0
	move.w	#$1234,(a0)
	move.w	#$ABCD,2(a0)
	move.b	#$5A,1(a0)
	move.b	#$C3,2(a0)
	cmp.w	#$125A,(a0)
	bne	bad
	cmp.w	#$C3CD,2(a0)
	bne	bad
	move.l	#$DEADBEEF,RAM+$7FFC
	cmp.l	#$DEADBEEF,RAM+$7FFC
	bne	bad
	cmp.w	#$125A,(a0)
	bne	bad

	; ---- 4: internal loopback
	move.w	#4,STEP
	move.w	#$0004,d7		; mode: LOOP
	moveq	#0,d6			; the logical address filter's first word
	bsr	setup
	moveq	#0,d0			; CSR0 = INIT
	moveq	#$01,d1
	bsr	wrcsr
	bsr	waitidon
	moveq	#0,d0			; STRT
	moveq	#$02,d1
	bsr	wrcsr
	moveq	#0,d0
	bsr	rdcsr
	and.w	#$0033,d0		; RXON, TXON, STRT, INIT
	cmp.w	#$0033,d0
	bne	bad
	; a frame of 64 bytes in the first transmit buffer
	lea	RAM+TXBUF,a0
	moveq	#63,d0
	moveq	#$11,d1
.fill:	move.b	d1,(a0)+
	addq.b	#5,d1
	dbf	d0,.fill
	lea	RAM+TXRING,a0
	move.w	#$8000+TXBUF,(a0)
	move.w	#-64,4(a0)
	clr.w	6(a0)
	move.w	#$8300,2(a0)		; OWN, STP, ENP
	moveq	#0,d0
	moveq	#$08,d1			; TDMD
	bsr	wrcsr
	move.w	#$0600,d2		; RINT and TINT
	bsr	waitcsr
	lea	RAM+TXRING,a0
	move.w	2(a0),d0
	cmp.w	#$0300,d0		; given back
	bne	bad
	lea	RAM+RXRING,a0
	move.w	2(a0),d0
	cmp.w	#$0300,d0		; STP, ENP, the LANCE's no more
	bne	bad
	cmp.w	#68,6(a0)		; the frame and its CRC
	bne	bad
	lea	RAM+TXBUF,a0
	lea	RAM+RXBUF,a1
	moveq	#63,d0
.cmp:	cmpm.b	(a0)+,(a1)+
	bne	bad
	dbf	d0,.cmp
	lea	RAM+TXBUF,a0		; its CRC, the most significant byte first
	moveq	#64,d0
	bsr	crc32
	cmp.l	(a1),d0
	bne	bad
	cmp.w	#$0300,RAM+RXRING+2
	bne	bad
	move.w	RAM+RXRING+8+2,d0	; the second descriptor is still the LANCE's
	cmp.w	#$8000,d0
	bne	bad

	; ---- 5: normal mode, interrupts; two frames to the MCU
	move.w	#5,STEP
	moveq	#0,d0			; STOP
	moveq	#$04,d1
	bsr	wrcsr
	moveq	#0,d7
	moveq	#$20,d6			; the filter: bit 5
	bsr	setup
	move.w	#$C008,$9A(a6)		; INTENA: PORTS
	move.w	#$2000,sr
	moveq	#0,d0			; INIT, STRT, INEA at once
	moveq	#$43,d1
	bsr	wrcsr
	moveq	#1,d3			; the interrupt for IDON
	bsr	waitirq
	move.w	LASTCSR,d0
	and.w	#$0100,d0
	beq	bad
	; frame A: 64 bytes in two buffers (40 and 24): destination, source,
	; type, a pattern
	lea	RAM+TXBUF,a0
	move.l	#$02112233,(a0)+
	move.w	#$4455,(a0)+
	lea	MAC,a1
	move.l	(a1)+,(a0)+
	move.w	(a1)+,(a0)+
	move.w	#$0800,(a0)+
	moveq	#25,d0			; 26 bytes of the pattern here
	move.b	#$A1,d1
.pa:	move.b	d1,(a0)+
	addq.b	#3,d1
	dbf	d0,.pa
	lea	RAM+TXBUF+$400,a0	; and 24 in the second buffer
	moveq	#23,d0
.pb:	move.b	d1,(a0)+
	addq.b	#3,d1
	dbf	d0,.pb
	lea	RAM+TXRING,a0
	move.w	#$8000+TXBUF,(a0)
	move.w	#-40,4(a0)
	clr.w	6(a0)
	move.w	#$8000+TXBUF+$400,8(a0)
	move.w	#-24,12(a0)
	clr.w	14(a0)
	move.w	#$8100,10(a0)		; OWN, ENP
	move.w	#$8200,2(a0)		; OWN, STP
	; frame B: 20 bytes, in the third
	lea	RAM+TXBUF+$800,a1
	moveq	#19,d0
	move.b	#$3C,d1
.pc:	move.b	d1,(a1)+
	addq.b	#7,d1
	dbf	d0,.pc
	move.w	#$8000+TXBUF+$800,16(a0)
	move.w	#-20,20(a0)
	clr.w	22(a0)
	move.w	#$8300,18(a0)
	moveq	#0,d0
	moveq	#$48,d1			; TDMD, INEA
	bsr	wrcsr
	; both given back
.txw:	move.l	#400000,d2
.txl:	move.w	RAM+TXRING+18,d0
	cmp.w	#$0300,d0
	beq.s	.txd
	subq.l	#1,d2
	bne.s	.txl
	bra	bad
.txd:	cmp.w	#$0200,RAM+TXRING+2
	bne	bad
	cmp.w	#$0100,RAM+TXRING+10
	bne	bad
	cmp.w	#2,IRQS			; at least IDON's and one TINT
	bcs	bad

	; ---- 6: frames from the MCU
	move.w	#6,STEP
	; 1: for the station, 100 bytes
	moveq	#100,d4
	moveq	#1,d5
	bsr	rxframe
	; 2: broadcast, 60 bytes
	moveq	#60,d4
	moveq	#3,d5
	bsr	rxframe
	; 3: the multicast group of the filter, 64 bytes
	moveq	#64,d4
	moveq	#5,d5
	bsr	rxframe
	; 4: 600 bytes over three buffers
	move.w	#600,d4
	moveq	#6,d5
	bsr	rxframe

	; ---- 7: no descriptor: MISS
	move.w	#7,STEP
	lea	RAM+RXRING,a0
	moveq	#NRX-1,d0
.own0:	clr.w	2(a0)
	addq.l	#8,a0
	dbf	d0,.own0
	move.w	#$2700,sr		; (polled)
	move.w	#8,STEP			; the bench brings a frame now
	move.w	#$1000,d2
	bsr	waitcsr
	move.w	LASTCSR,d0
	btst	#15,d0			; ERR with it
	beq	bad

	move.w	#$600D,STEP
	move.w	#$00F0,$180(a6)
.done:	bra.s	.done

bad:	move.w	STEP,FAILED
	move.w	#$0F00,$180(a6)
.stop:	bra.s	.stop

; ---- an autoconfig byte from two nibbles at (a0), inverted; a0 += 4
acbyte:	move.b	(a0),d0
	and.b	#$F0,d0
	move.b	2(a0),d1
	lsr.b	#4,d1
	or.b	d1,d0
	not.b	d0
	addq.l	#4,a0
	rts

; ---- CSR d0 read into d0 / written from d1
rdcsr:	move.w	d0,RAP
	move.w	RDP,d0
	rts
wrcsr:	move.w	d0,RAP
	move.w	d1,RDP
	rts

; ---- until CSR0 has all of d2, which are then acknowledged
waitcsr:
	move.l	#400000,d3
.w:	moveq	#0,d0
	bsr	rdcsr
	move.w	d0,d1
	and.w	d2,d1
	cmp.w	d2,d1
	beq.s	.ok
	subq.l	#1,d3
	bne.s	.w
	move.w	d0,FOUND
	move.w	d2,WANT
	addq.l	#4,sp
	bra	bad
.ok:	move.w	d0,LASTCSR
	moveq	#0,d0
	move.w	d2,d1
	bsr	wrcsr
	rts

; ---- IDON, polled, acknowledged
waitidon:
	move.w	#$0100,d2
	bsr	waitcsr
	move.w	LASTCSR,d0
	and.w	#$0080,d0		; INTR was up with it
	beq	.b
	moveq	#0,d0
	bsr	rdcsr
	and.w	#$0180,d0		; and both are gone
	bne.s	.b
	rts
.b:	addq.l	#4,sp
	bra	bad

; ---- until d3 level 2 interrupts have been taken
waitirq:
	move.l	#600000,d2
.w:	cmp.w	IRQS,d3
	bls.s	.ok
	subq.l	#1,d2
	bne.s	.w
	move.w	IRQS,FOUND
	move.w	d3,WANT
	addq.l	#4,sp
	bra	bad
.ok:	rts

; ---- level 2: the LANCE's bits acknowledged, counted
irq2:	movem.l	d0-d1,-(sp)
	move.w	RAP,-(sp)
	clr.w	RAP
	move.w	RDP,d0
	move.w	d0,LASTCSR
	and.w	#$7F00,d0
	or.w	#$0040,d0		; INEA stays
	move.w	d0,RDP
	move.w	(sp)+,RAP
	addq.w	#1,IRQS
	move.w	#$0008,$DFF09C		; INTREQ: PORTS
	move.w	#$0008,$DFF09C
	movem.l	(sp)+,d0-d1
	rte

; ---- the initialisation block (mode d7, the filter's first word d6), the
; rings and CSR1 to CSR3; every receive descriptor the LANCE's
setup:	lea	RAM+IBLK,a0
	move.w	d7,(a0)+
	lea	MAC,a1			; the station address, its bytes in pairs
	moveq	#2,d0
.m:	move.b	(a1)+,d1
	move.b	(a1)+,(a0)+
	move.b	d1,(a0)+
	dbf	d0,.m
	move.w	d6,(a0)+		; the filter
	clr.w	(a0)+
	clr.w	(a0)+
	clr.w	(a0)+
	move.w	#$8000+RXRING,(a0)+	; the receive ring: 8
	move.w	#$6000,(a0)+
	move.w	#$8000+TXRING,(a0)+	; the transmit ring: 4
	move.w	#$4000,(a0)+
	lea	RAM+RXRING,a0
	move.w	#$8000+RXBUF,d1
	moveq	#NRX-1,d0
.r:	move.w	d1,(a0)+
	move.w	#$8000,(a0)+		; OWN
	move.w	#-256,(a0)+
	clr.w	(a0)+
	add.w	#$100,d1
	dbf	d0,.r
	lea	RAM+TXRING,a0
	moveq	#15,d0
.t:	clr.w	(a0)+
	dbf	d0,.t
	moveq	#1,d0
	move.w	#$8000+IBLK,d1
	bsr	wrcsr
	moveq	#2,d0
	moveq	#0,d1
	bsr	wrcsr
	moveq	#3,d0
	moveq	#4,d1			; BSWP
	bsr	wrcsr
	rts

; ---- a frame from the MCU: d4 bytes, its pattern's first byte d5 (after
; the 14 bytes of its header). It starts at the ring's next descriptor
; (rxnext) and takes as many of 256 bytes as it and its CRC need; they are
; given back to the LANCE afterwards.
rxframe:
	move.w	IRQS,d3
	addq.w	#1,d3
	move.w	d4,WANT			; (the bench reads the length it is waited for)
	addq.w	#1,REQ			; "bring the next"
	bsr	waitirq
	move.w	LASTCSR,d0
	and.w	#$0400,d0		; RINT
	beq	.bad
	moveq	#0,d0
	move.w	rxnext,d0
	lsl.w	#3,d0
	lea	RAM+RXRING,a0
	add.l	d0,a0			; the frame's first descriptor
	move.w	d4,d2
	addq.w	#4,d2			; with the CRC
	move.w	d2,d1
	add.w	#255,d1
	lsr.w	#8,d1			; descriptors it takes
	move.w	d1,d7
	subq.w	#1,d1
	; the first has STP, the last ENP and the length, none is the LANCE's
	move.w	2(a0),d0
	btst	#9,d0
	beq	.bad
	move.l	a0,a2
.d:	move.w	2(a2),d0
	btst	#15,d0
	bne	.bad
	tst.w	d1
	bne.s	.mid
	btst	#8,d0
	beq	.bad
	cmp.w	6(a2),d2
	bne	.bad
	bra.s	.nx
.mid:	btst	#8,d0
	bne	.bad
.nx:	addq.l	#8,a2
	dbf	d1,.d
	; the bytes: the buffers follow one another in the board's RAM
	moveq	#0,d0
	move.w	rxnext,d0
	lsl.w	#8,d0
	lea	RAM+RXBUF,a1
	add.l	d0,a1
	move.l	a1,a3
	lea	14(a1),a1
	move.w	d4,d0
	sub.w	#15,d0
	move.b	d5,d1
.b:	cmp.b	(a1)+,d1
	bne	.bad
	addq.b	#7,d1
	dbf	d0,.b
	move.l	a3,a0			; and the CRC after them
	moveq	#0,d0
	move.w	d4,d0
	bsr	crc32
	move.l	d0,d1			; (a1 may be odd: byte by byte)
	rol.l	#8,d1
	cmp.b	(a1)+,d1
	bne	.bad
	rol.l	#8,d1
	cmp.b	(a1)+,d1
	bne	.bad
	rol.l	#8,d1
	cmp.b	(a1)+,d1
	bne	.bad
	rol.l	#8,d1
	cmp.b	(a1)+,d1
	bne	.bad
	; the descriptors back to the LANCE, the ring's next
	moveq	#0,d0
	move.w	rxnext,d0
	lsl.w	#3,d0
	lea	RAM+RXRING,a0
	add.l	d0,a0
	move.w	d7,d1
	subq.w	#1,d1
.g:	move.w	#$8000,2(a0)
	addq.l	#8,a0
	dbf	d1,.g
	add.w	d7,rxnext
	addq.w	#1,GOT
	rts
.bad:	move.w	d0,FOUND
	addq.l	#4,sp
	bra	bad

; ---- CRC-32 of d0 bytes at a0, as the frame's four last bytes hold it
; (complemented, the most significant byte first)
crc32:	movem.l	d1-d3,-(sp)
	moveq	#-1,d1
	subq.w	#1,d0
.by:	moveq	#0,d2
	move.b	(a0)+,d2
	eor.l	d2,d1
	moveq	#7,d3
.bi:	lsr.l	#1,d1
	bcc.s	.n
	eor.l	#$EDB88320,d1
.n:	dbf	d3,.bi
	dbf	d0,.by
	not.l	d1
	move.l	d1,d0
	movem.l	(sp)+,d1-d3
	rts

; (the ring's next receive descriptor: in chip RAM)
rxnext	equ	$130
