// ---- ap68040_pkg.sv ----
//--------------------------------------------------------------------------//
// AP68040 - pipelined MC68040                                            //
//                                                                          //
// ap68040_pkg.sv - shared types and encodings                               //
//--------------------------------------------------------------------------//

package ap68040_pkg;

//--------------------------------------------------------------------------
// Register numbers (5 bits).  A7 never appears here: the decoder maps it
// to USP, ISP or MSP from the S and M bits current at decode time.
//--------------------------------------------------------------------------
localparam logic [4:0] R_D0  = 5'd0;
localparam logic [4:0] R_A0  = 5'd8;
localparam logic [4:0] R_USP = 5'd15;
localparam logic [4:0] R_ISP = 5'd16;
localparam logic [4:0] R_MSP = 5'd17;
localparam logic [4:0] R_T0  = 5'd18;   // T0..T13 = 18..31, microcode temps

//--------------------------------------------------------------------------
// Bus encodings (MC68040UM tables 5-2, 5-3, 7-1)
//--------------------------------------------------------------------------
localparam logic [1:0] SIZ_L    = 2'b00;
localparam logic [1:0] SIZ_B    = 2'b01;
localparam logic [1:0] SIZ_W    = 2'b10;
localparam logic [1:0] SIZ_LINE = 2'b11;

localparam logic [1:0] TT_NORMAL = 2'd0;
localparam logic [1:0] TT_MOVE16 = 2'd1;
localparam logic [1:0] TT_ALT    = 2'd2;
localparam logic [1:0] TT_ACK    = 2'd3;

localparam logic [2:0] TM_PUSH     = 3'd0;
localparam logic [2:0] TM_UDATA    = 3'd1;
localparam logic [2:0] TM_UCODE    = 3'd2;
localparam logic [2:0] TM_TBL_DATA = 3'd3;
localparam logic [2:0] TM_TBL_CODE = 3'd4;
localparam logic [2:0] TM_SDATA    = 3'd5;
localparam logic [2:0] TM_SCODE    = 3'd6;

// One internal bus transaction, as a requester hands it to the BIU.  The
// BIU only runs naturally aligned transfers; requesters split misaligned
// operands (MC68040UM 7.3).  For a line, addr[3:2] names the first long
// word and the slave wraps.
typedef struct packed {
	logic [31:0] addr;
	logic  [1:0] siz;     // SIZ_*
	logic        rd;      // 1 read, 0 write
	logic  [1:0] tt;
	logic  [2:0] tm;
	logic  [1:0] tln;
	logic  [1:0] upa;
	logic        ci;      // CIOUT
	logic        lock;    // LOCK for this transfer
	logic        locke;   // LOCKE: last transfer of the locked sequence
} busreq_t;

//--------------------------------------------------------------------------
// ATC entry (MC68040UM figure 3-21); pa is PA31-12 (PA12 comes from LA12
// with 8 Kbyte pages)
//--------------------------------------------------------------------------
typedef struct packed {
	logic [19:0] pa;
	logic        g;       // global
	logic  [1:0] upa;     // U1 U0
	logic        s;       // supervisor only
	logic  [1:0] cm;      // cache mode
	logic        m;       // modified
	logic        w;       // write protected (accumulated)
	logic        r;       // resident (table search succeeded)
	logic        b;       // the table search took a bus error
} atce_t;

//--------------------------------------------------------------------------
// Operation sizes
//--------------------------------------------------------------------------
localparam logic [1:0] SZ_B = 2'd0;
localparam logic [1:0] SZ_W = 2'd1;
localparam logic [1:0] SZ_L = 2'd2;
localparam logic [1:0] SZ_Q = 2'd3;   // line / double, context dependent

//--------------------------------------------------------------------------
// Micro-operations
//--------------------------------------------------------------------------
// operand sources
localparam logic [1:0] OS_REG  = 2'd0;
localparam logic [1:0] OS_IMM  = 2'd1;
localparam logic [1:0] OS_MEM  = 2'd2;   // the uop's load data
localparam logic [1:0] OS_ZERO = 2'd3;

// memory access of a uop
localparam logic [1:0] M_NONE = 2'd0;
localparam logic [1:0] M_LD   = 2'd1;
localparam logic [1:0] M_ST   = 2'd2;
localparam logic [1:0] M_RMW  = 2'd3;    // load, then store to the same place

// function code of a data access
localparam logic [2:0] MFC_NORM = 3'd0;  // user/supervisor data by S
localparam logic [2:0] MFC_SFC  = 3'd1;  // MOVES read
localparam logic [2:0] MFC_DFC  = 3'd2;  // MOVES write
localparam logic [2:0] MFC_SUP  = 3'd3;  // supervisor data (exception stacking)
localparam logic [2:0] MFC_IACK = 3'd4;  // interrupt acknowledge (TT=3)
localparam logic [2:0] MFC_EAP  = 3'd5;  // microcode: the EA's space (D2 maps it)
localparam logic [2:0] MFC_BKPT = 3'd6;  // breakpoint acknowledge read (TT=3, TM=0, A=0)

// control flow
// internal exception codes of instruction fetch faults (uop.exc); real
// vectors otherwise.  The back end turns them into vector 2.
// fetch BTB: 2**BTB_AW entries indexed by PC[BTB_AW+1:2], tagged PC[31:BTB_AW+2]
localparam int BTB_AW = 8;
localparam int BTB_TW = 30 - BTB_AW;

localparam logic [7:0] EXC_IFS  = 8'd1;    // speculative fetch, bus error
localparam logic [7:0] EXC_IFB  = 8'd2;    // demand fetch, bus error
localparam logic [7:0] EXC_IFSA = 8'hFD;   // speculative fetch, ATC fault
localparam logic [7:0] EXC_IFA  = 8'hFE;   // demand fetch, ATC fault
localparam logic [7:0] EXC_SNR  = 8'hFC;   // refetch: a snoop dropped code the
                                            // front end may have run ahead into

localparam logic [2:0] BR_NONE = 3'd0;
localparam logic [2:0] BR_COND = 3'd1;   // decision from the EX op (Bcc, DBcc, FBcc)
localparam logic [2:0] BR_IMM  = 3'd2;   // always, to uop.target
localparam logic [2:0] BR_EA   = 3'd3;   // always, to the effective address
localparam logic [2:0] BR_A    = 3'd4;   // always, to operand A (RTS: load data)
localparam logic [2:0] BR_B    = 3'd5;   // always, to operand B (JSR)

// EX operations
localparam logic [6:0]
	OP_MOV   = 7'd0,   // res = A                     N Z, V=C=0
	OP_ADD   = 7'd1,   // res = B + A
	OP_ADDX  = 7'd2,
	OP_SUB   = 7'd3,   // res = B - A
	OP_SUBX  = 7'd4,
	OP_CMP   = 7'd5,   // flags of B - A, no result
	OP_AND   = 7'd6,
	OP_OR    = 7'd7,
	OP_EOR   = 7'd8,
	OP_NOT   = 7'd9,   // res = ~B
	OP_NEG   = 7'd10,  // res = 0 - B
	OP_NEGX  = 7'd11,
	OP_CLR   = 7'd12,
	OP_EXT   = 7'd13,  // sz W: byte->word, sz L: word->long
	OP_EXTB  = 7'd14,  // byte->long
	OP_SWAP  = 7'd15,
	OP_TAS   = 7'd16,
	OP_ABCD  = 7'd17,
	OP_SBCD  = 7'd18,
	OP_NBCD  = 7'd19,
	OP_PACK  = 7'd20,  // A = adjustment, B = unpacked word
	OP_UNPK  = 7'd21,  // A = adjustment, B = packed byte
	OP_ASL   = 7'd22,  // B shifted by A[5:0]
	OP_ASR   = 7'd23,
	OP_LSL   = 7'd24,
	OP_LSR   = 7'd25,
	OP_ROL   = 7'd26,
	OP_ROR   = 7'd27,
	OP_ROXL  = 7'd28,
	OP_ROXR  = 7'd29,
	OP_BTST  = 7'd30,  // bit A of B
	OP_BCHG  = 7'd31,
	OP_BCLR  = 7'd32,
	OP_BSET  = 7'd33,
	OP_SCC   = 7'd34,  // res = cond ? $FF : 0
	OP_EA    = 7'd35,  // res = effective address
	OP_BCC   = 7'd36,  // branch decision from cond
	OP_DBCC  = 7'd37,  // res = B.w - 1; taken = !cond && res.w != -1
	OP_TRAPCC= 7'd38,  // exception 7 if cond
	OP_CHK   = 7'd39,  // B against 0..A, exception 6
	OP_CHK2A = 7'd40,  // CHK2/CMP2 step 1: compare B with lower bound A
	OP_CHK2B = 7'd41,  // step 2: compare with upper bound A; cond[0] = trap
	OP_CCRLOG= 7'd42,  // CCR = CCR (cond: 0 AND 1 OR 2 EOR 3 MOVE) A
	OP_SRLOG = 7'd43,  // res = SR (cond as above) A, written to SR at WB
	OP_SPR   = 7'd44,  // res = special register imm[7:0]
	OP_SPW   = 7'd45,  // special register imm[7:0] = A at WB
	OP_LATCH = 7'd46,  // EX latch = A (third operand for CAS and bit fields)
	OP_CAS   = 7'd47,  // compare B with latch; store A if equal
	OP_MUL   = 7'd48,  // cond[0] signed, cond[1] 64-bit
	OP_DIV   = 7'd49,  // cond[0] signed, cond[1] 64-bit dividend, sz W/L
	OP_MDHI  = 7'd50,  // multiply/divide high input = A
	OP_MDRES = 7'd51,  // res = remainder / product high
	OP_BF    = 7'd52,  // bit field, cond = BF op
	OP_BFSET = 7'd53,  // bit field offset/width setup
	OP_MISC  = 7'd54,  // WB-side operation in cond (RESET, STOP, NOP, CINV...)
	OP_FPU   = 7'd55,  // floating point, see the FPU interface
	OP_CHKSR = 7'd56,  // privilege/format checks for RTE etc (cond)
	OP_CAS2C = 7'd57,  // CAS2 compare: cond 0 first pair, 1 second (if equal so far)
	OP_CAS2W = 7'd58,  // CAS2 store: cond 0 A only if equal, 1 equal ? A : B
	OP_CAS2R = 7'd59,  // CAS2 register: B merged with A unless equal
	OP_RTEF  = 7'd60,  // RTE: frame length of format word A (exception 14)
	OP_RTE   = 7'd61,  // RTE: SR = A, jump to B (throwaway frame: this RTE)
	OP_IACKV = 7'd62;  // interrupt vector from the IACK data

// D1's return stack pointer as an instruction found it, and what the
// instruction did to it: a WB redirect puts it back (after the
// instruction, or before it for a refetch), so wrong-path calls and
// returns that D1 decoded leave no trace
typedef struct packed {
	logic        v;
	logic  [1:0] k;         // 1 pushed (BSR/JSR), 2 popped (RTS)
	logic  [2:0] tp;
	logic  [3:0] n;
} ras_snap_t;

typedef struct packed {
	logic [31:0] pc;        // address of the 68040 instruction
	logic  [3:0] ilen;     // the instruction's length in words (npc = pc + 2 ilen)
	ras_snap_t   ras;       // see ras_snap_t
	logic        first;     // first uop of the instruction
	logic        last;      // last uop: the instruction completes with it
	// execution
	logic  [6:0] op;
	logic  [1:0] sz;
	logic  [3:0] cond;
	logic  [4:0] ccr_we;    // X N Z V C
	// operands
	logic  [1:0] a_src;
	logic  [4:0] a_reg;
	logic        a_sxw;     // sign-extend operand A from a word
	logic  [1:0] b_src;
	logic  [4:0] b_reg;
	logic [31:0] imm;       // operand A immediate (or a constant)
	logic [16:0] imm_b;     // operand B immediate: a 16-bit word with its sign
	                        // (the B symbols are 16-bit constants and words,
	                        // sign- or zero-extended: bit 16 extends it)
	// address generation: EA = base + idx*scale + disp
	logic        ag;        // compute an effective address
	logic        base_v;
	logic  [4:0] base;
	logic        idx_v;
	logic  [4:0] idx;
	logic        idx_l;
	logic  [1:0] scale;
	logic [31:0] disp;
	logic        dmv;       // AG adds dma to disp as the uop enters it (a
	logic  [7:0] dma;       // deferred update merged by the sequencer; signed)
	logic        pinc;      // postincrement: EA = base, update = base + amt
	logic        upd_v;     // AG write: upd_reg = pinc ? base + amt : EA
	logic  [4:0] upd_reg;
	logic  [7:0] upd_amt;   // signed: postincrement amount (and a deferred offset)
	logic        upd2_v;    // AG write: upd2_reg += upd2_amt
	logic  [4:0] upd2_reg;
	logic  [7:0] upd2_amt;  // signed
	// memory
	logic  [1:0] mem;
	logic  [1:0] msz;
	logic  [2:0] mfc;
	logic        mlock;
	logic        mlocke;    // last transfer of the locked sequence
	logic        mwi;       // a load checked as a write (write intent)
	logic        mprog;     // program space (PC-relative operand)
	// result
	logic        d_v;
	logic  [4:0] d_reg;
	// control flow
	logic  [2:0] br;
	logic [31:0] target;
	logic        pred;      // the front end followed target
	logic        bst;       // Bcc: static prediction, and the history counter
	logic  [1:0] bhc;       // D1 read (trained in EX)
	// exceptions and control
	logic  [7:0] exc;       // decode-time exception vector, 0 = none
	logic        exr;        // an exception routine's uop: pc/npc are not an
	                        // instruction's (never refetched from them)
	logic        ser;       // serialize: flush and refetch npc after WB
	logic        t0cof;     // the instruction is on the 68040 T0 trace list
	logic        b_upd;     // operand B is this uop's own (An)+/-(An) register:
	                        // it reads the updated value (source EA updates)
	logic        a_upd;     // the same for operand A (MOVES An,(An)+ / -(An))
	logic  [2:0] dyn;       // cancelled at AG by run-time state (FPU transfers)
	logic  [4:0] dynk;      // ... its slot / word index
} uop_t;

//--------------------------------------------------------------------------
// Decoded instruction (D1 -> D2)
//--------------------------------------------------------------------------
// EA mode index, MC68040 order
localparam logic [3:0] EM_DN = 4'd0, EM_AN = 4'd1, EM_AI = 4'd2, EM_AIP = 4'd3,
                       EM_APD = 4'd4, EM_AD16 = 4'd5, EM_AX = 4'd6,
                       EM_ABSW = 4'd7, EM_ABSL = 4'd8, EM_PC16 = 4'd9,
                       EM_PCX = 4'd10, EM_IMM = 4'd11, EM_NONE = 4'd15;

typedef struct packed {
	logic  [3:0] m;       // EM_*
	logic  [2:0] r;       // register field
	logic  [2:0] xoff;    // word offset of the first extension word
	// index modes (brief or full extension word)
	logic        xa;      // index is an address register
	logic  [2:0] xr;
	logic        xl;      // long index
	logic  [1:0] sc;
	logic        bs;      // base suppressed
	logic        is;      // index suppressed
	logic  [1:0] mi;      // 0 none, 1 preindexed, 2 postindexed memory indirect
	logic [31:0] bd;      // displacement / absolute address / immediate
	logic [31:0] od;      // outer displacement
} ea_t;

// predecode of a queue word taken as an operation word (computed as the
// word enters the instruction queue, so D1 never decodes in its loop)
typedef struct packed {
	logic        legal;   // a legal operation word
	logic  [8:0] ent;     // decoder entry
	logic  [1:0] sz;
	logic  [2:0] b;       // operation word + fixed words + immediate (1..5)
	logic  [2:0] p1;      // first extension word of EA1 (b + EA0 words)
	logic  [3:0] tot;     // length assuming brief index extensions
	logic        x0;      // EA0 has an index extension (at b)
	logic        x1;      // EA1 has an index extension (at p1)
	logic        slow;    // parsed in several cycles (FPU immediate)
	logic  [3:0] i0;      // EA0 mode index, EM_NONE when absent
	logic  [3:0] i1;
} pd_t;

typedef struct packed {
	logic [31:0] pc;
	logic  [3:0] ilen;     // the instruction's length in words (npc = pc + 2 ilen)
	logic [15:0] opw;
	logic [15:0] ext1;
	logic [15:0] ext2;
	logic  [9:0] rt;      // first micro-instruction
	logic  [6:0] eop;
	logic  [3:0] econd;
	logic  [4:0] ccr;
	logic  [1:0] sz;
	logic  [7:0] exc;     // decode-time exception vector, 0 none
	logic [31:0] imm;     // immediate field
	ea_t         ea0;
	ea_t         ea1;
	logic [31:0] target;  // PC-relative branch target
	logic        pred;    // the front end followed target
	logic        t0;      // on the 68040 T0 trace list
	logic        bst;     // Bcc: the static prediction (backward taken)
	logic  [1:0] bhc;     // Bcc: its history counter as D1 read it
	ras_snap_t   ras;     // D1's return stack before this instruction
} dinst_t;

endpackage
// ---- ap68040_upkg.sv ----
// generated by tools/ucode.py - do not edit
package ap68040_upkg;
localparam int UW = 121;
typedef struct packed {
	logic [0:0] op_inst;
	logic [6:0] op;
	logic [1:0] sz;
	logic [2:0] msz;
	logic [2:0] cond_inst;
	logic [3:0] cond;
	logic [0:0] ccr_inst;
	logic [4:0] ccr;
	logic [5:0] a;
	logic [5:0] b;
	logic [5:0] d;
	logic [1:0] sxw;
	logic [3:0] ag;
	logic [5:0] agb;
	logic [5:0] agw;
	logic [2:0] dsel;
	logic [15:0] cval;
	logic [1:0] mem;
	logic [2:0] mfc;
	logic [0:0] lock;
	logic [0:0] locke;
	logic [0:0] wi;
	logic [2:0] br;
	logic [0:0] last;
	logic [0:0] ser;
	logic [0:0] noupd;
	logic [0:0] upd2;
	logic [5:0] jc;
	logic [9:0] jt;
	logic [0:0] loop;
	logic [2:0] dyn;
	logic [4:0] dynk;
} uword_t;
localparam logic [5:0] S_NONE = 6'd0;
localparam logic [5:0] S_EA0 = 6'd1;
localparam logic [5:0] S_EA1 = 6'd2;
localparam logic [5:0] S_EA1R = 6'd3;
localparam logic [5:0] S_DX = 6'd4;
localparam logic [5:0] S_DY = 6'd5;
localparam logic [5:0] S_AX = 6'd6;
localparam logic [5:0] S_AY = 6'd7;
localparam logic [5:0] S_IMM = 6'd8;
localparam logic [5:0] S_QUICK = 6'd9;
localparam logic [5:0] S_MOVEQ = 6'd10;
localparam logic [5:0] S_SHCNT = 6'd11;
localparam logic [5:0] S_SP = 6'd12;
localparam logic [5:0] S_SSP = 6'd13;
localparam logic [5:0] S_NPC = 6'd14;
localparam logic [5:0] S_PC = 6'd15;
localparam logic [5:0] S_ZERO = 6'd16;
localparam logic [5:0] S_CONST = 6'd17;
localparam logic [5:0] S_X1R = 6'd18;
localparam logic [5:0] S_X1DL = 6'd19;
localparam logic [5:0] S_X1DH = 6'd20;
localparam logic [5:0] S_X1DU = 6'd21;
localparam logic [5:0] S_X2DC = 6'd22;
localparam logic [5:0] S_X2DU = 6'd23;
localparam logic [5:0] S_X2R = 6'd24;
localparam logic [5:0] S_MVR = 6'd25;
localparam logic [5:0] S_EA0R = 6'd26;
localparam logic [5:0] S_LD = 6'd27;
localparam logic [5:0] S_CREG = 6'd28;
localparam logic [5:0] S_CREGR = 6'd29;
localparam logic [5:0] S_BFO = 6'd30;
localparam logic [5:0] S_BFW = 6'd31;
localparam logic [5:0] S_OPW = 6'd32;
localparam logic [5:0] S_EXT1 = 6'd33;
localparam logic [5:0] S_FPDL = 6'd34;
localparam logic [3:0] AGM_NONE = 4'd0;
localparam logic [3:0] AGM_EA0 = 4'd1;
localparam logic [3:0] AGM_EA1 = 4'd2;
localparam logic [3:0] AGM_PUSH = 4'd3;
localparam logic [3:0] AGM_POP = 4'd4;
localparam logic [3:0] AGM_BASED = 4'd5;
localparam logic [3:0] AGM_BASEDU = 4'd6;
localparam logic [3:0] AGM_VAL0 = 4'd7;
localparam logic [3:0] AGM_ADDV = 4'd8;
localparam logic [3:0] AGM_ADDC = 4'd9;
localparam logic [3:0] AGM_LEA0 = 4'd10;
localparam logic [3:0] AGM_MOVEM = 4'd11;
localparam logic [3:0] AGM_POPR = 4'd12;
localparam logic [3:0] AGM_ADDT0 = 4'd13;
localparam logic [3:0] AGM_FEA = 4'd14;
localparam logic [3:0] AGM_FUPD = 4'd15;
localparam logic [2:0] DS_CONST = 3'd0;
localparam logic [2:0] DS_IMM = 3'd1;
localparam logic [2:0] DS_NIMM = 3'd2;
localparam logic [2:0] DS_QUICK = 3'd3;
localparam logic [2:0] DS_NQUICK = 3'd4;
localparam logic [2:0] DS_IMMC = 3'd5;
localparam logic [2:0] DS_SZB = 3'd6;
localparam logic [5:0] JC_NEVER = 6'd0;
localparam logic [5:0] JC_ALWAYS = 6'd1;
localparam logic [5:0] JC_EA0_MEM = 6'd2;
localparam logic [5:0] JC_EA1_MEM = 6'd3;
localparam logic [5:0] JC_EA0_REG = 6'd4;
localparam logic [5:0] JC_EA0_DN = 6'd5;
localparam logic [5:0] JC_EA0_AN = 6'd6;
localparam logic [5:0] JC_EA0_IMM = 6'd7;
localparam logic [5:0] JC_NOT_EA0_MEM = 6'd8;
localparam logic [5:0] JC_EXT11 = 6'd9;
localparam logic [5:0] JC_SZ_L = 6'd10;
localparam logic [5:0] JC_AY7 = 6'd11;
localparam logic [5:0] JC_BOTH_MEM = 6'd12;
localparam logic [5:0] JC_MASK0 = 6'd13;
localparam logic [5:0] JC_SUPER = 6'd14;
localparam logic [5:0] JC_EXT10 = 6'd15;
localparam logic [5:0] JC_CREG_RF = 6'd16;
localparam logic [5:0] JC_X1A = 6'd17;
localparam logic [5:0] JC_SZ_B = 6'd18;
localparam logic [5:0] JC_FP_OC0 = 6'd19;
localparam logic [5:0] JC_FP_OC2 = 6'd20;
localparam logic [5:0] JC_FP_OC3 = 6'd21;
localparam logic [5:0] JC_FP_OC45 = 6'd22;
localparam logic [5:0] JC_FP_OC67 = 6'd23;
localparam logic [5:0] JC_FMT_1 = 6'd24;
localparam logic [5:0] JC_FMT_2 = 6'd25;
localparam logic [5:0] JC_FMT_8 = 6'd26;
localparam logic [5:0] JC_FMT_12 = 6'd27;
localparam logic [5:0] JC_FMT_7 = 6'd28;
localparam logic [5:0] JC_EA0_APD = 6'd29;
localparam logic [5:0] JC_EA0_AIP = 6'd30;
localparam logic [5:0] JC_EXT13 = 6'd31;
localparam logic [9:0] UA_EXC_FMT0 = 10'd606;
localparam logic [9:0] UA_EXC_FMT2 = 10'd610;
localparam logic [9:0] UA_EXC_FMT7 = 10'd615;
localparam logic [9:0] UA_EXC_RESET = 10'd634;
localparam logic [9:0] UA_EXC_IRQ = 10'd636;
localparam logic [9:0] UA_EXC_IRQM = 10'd642;
localparam logic [9:0] UA_DEC_EXC = 10'd1;
localparam logic [9:0] UA_BCC = 10'd86;
localparam logic [9:0] UA_BSR = 10'd87;
localparam logic [9:0] UA_DBCC = 10'd88;
localparam logic [9:0] UA_FBCC = 10'd480;
localparam logic [9:0] UA_FDBCC = 10'd484;
localparam logic [9:0] UA_FPU_GEN = 10'd228;
localparam logic [9:0] UA_TRAP = 10'd113;
localparam logic [9:0] UA_BKPT = 10'd114;
localparam logic [9:0] UA_ILLEGAL = 10'd0;
localparam logic [9:0] UA_MOVEM_RM = 10'd125;
localparam logic [9:0] UA_MOVEM_MR = 10'd128;
localparam logic [9:0] UA_MOVEC_RD = 10'd119;
localparam logic [9:0] UA_MOVEC_WR = 10'd122;
localparam logic [9:0] UA_JSR = 10'd90;
localparam logic [9:0] UA_JSR_K = 10'd92;
localparam logic [9:0] UA_JMP = 10'd89;
localparam logic [9:0] UA_RTS = 10'd93;
localparam logic [9:0] UA_FPU_K_IND = 10'd259;
localparam logic [9:0] UA_FPU_K_IN1 = 10'd264;
localparam logic [9:0] UA_FPU_K_IN2 = 10'd267;
localparam logic [9:0] UA_FPU_K_IN4 = 10'd261;
localparam logic [9:0] UA_FPU_K_IN8 = 10'd270;
localparam logic [9:0] UA_FPU_K_IN12 = 10'd274;
localparam logic [9:0] UA_FPU_K_OUTD = 10'd304;
localparam logic [9:0] UA_FPU_K_OUT1 = 10'd311;
localparam logic [9:0] UA_FPU_K_OUT2 = 10'd315;
localparam logic [9:0] UA_FPU_K_OUT4 = 10'd307;
localparam logic [9:0] UA_FPU_K_OUT8 = 10'd319;
localparam logic [9:0] UA_FPU_K_OUT12 = 10'd325;
// the predecoder table word (tools/ucode.py emit_pdrom)
typedef struct packed {
	logic [1:0] kind;
	logic [4:0] alt;
	logic [8:0] ent;
	logic [1:0] szc;
	logic [1:0] nfix;
	logic [2:0] immk;
	logic ea0v;
	logic ea1v;
	logic fpg;
	logic leg1;
	logic [4:0] leg0;
} pdw_t;
localparam logic [8:0] PD_NOENT = 9'd511;
endpackage
// ---- ap68040.sv ----
//--------------------------------------------------------------------------//
// AP68040 - pipelined MC68040                                               //
//                                                                          //
// ap68040.sv - top level: the 68040 bus (MC68040UM section 7)               //
//                                                                          //
// clk is the processor clock (PCLK); bclk_en marks the processor clocks    //
// that end a bus clock (BCLK rising edge).  Bidirectional pins are split   //
// into _i/_o/_oe: a_i, ts_n_i, rw_n_i, siz_i and tt_i are the bus as an    //
// alternate master drives it (snooped, with SC1/SC0), d_i the data bus    //
// in either direction, ta_n the bus TA; the 68040 drives TA (ta_n_o,      //
// ta_oe) and D31-D0 only as a snooping slave.                             //
//--------------------------------------------------------------------------//

module ap68040
	import ap68040_pkg::*;
#(
	parameter logic [7:0] FPU_REVISION = 8'h41,  // FSAVE frames: $41, or $40 (44-byte UNIMP)
	// area options (doc/STATUS.md has what each costs in ALMs and cycles)
	parameter bit         FPU_PIPE     = 0,      // the FPU's arithmetic pipeline (0: the state machine alone)
	parameter bit         LOOP_PRED    = 0,      // D1's loop exit predictor
	parameter bit         EARLY_RES    = 0,      // AG's early results for younger uops' base and index
	parameter bit         DC1_ATC      = 0,      // DC1's own ATC port and tag compare (timing)
	parameter bit         SKID         = 0,      // the skid register in front of AG (timing)
	parameter int         DIV_STEPS    = 2,      // divide steps per cycle (2 or 4)
	// system options
	parameter bit         DC_WRITETHROUGH = 0,   // copyback pages cached write-through (DMA reads not snooped)
	// debug
	parameter bit         DEBUG        = 0       // the dbg_* outputs' logic (0: they stay at zero and load nothing;
	                                             // dbg_halted is kept)
)(

	input  logic        clk,
	input  logic        bclk_en,
	input  logic        rsti_n,

	output logic [31:0] a_o,
	output logic        a_oe,
	input  logic [31:0] a_i,
	input  logic        ts_n_i,
	input  logic        rw_n_i,
	input  logic  [1:0] siz_i,
	input  logic  [1:0] tt_i,
	input  logic  [1:0] sc,
	output logic        mi_n,
	output logic        ta_n_o,
	output logic        ta_oe,
	input  logic [31:0] d_i,
	output logic [31:0] d_o,
	output logic        d_oe,
	output logic        rw_n,
	output logic  [1:0] siz,
	output logic  [1:0] tt,
	output logic  [2:0] tm,
	output logic  [1:0] tln,
	output logic  [1:0] upa,
	output logic        ciout_n,
	output logic        lock_n,
	output logic        locke_n,
	output logic        ts_n,
	output logic        tip_n,
	input  logic        ta_n,
	input  logic        tea_n,
	input  logic        tci_n,
	input  logic        tbi_n,
	// Game Bub port: a line of the instruction cache to invalidate (or every
	// line), for a write the bus does not show the processor as another
	// master's: held until xinv_done; handled as a snooped write is
	input  logic        xinv_req,
	input  logic [31:0] xinv_pa,
	input  logic        xinv_all,
	output logic        xinv_done,
	input  logic  [2:0] ipl_n,
	input  logic        avec_n,
	output logic        br_n,
	input  logic        bg_n,
	input  logic        bb_n_i,
	output logic        bb_n_o,
	output logic        bb_oe,
	output logic        rsto_n,
	input  logic        cdis_n,       // CDIS: disable the caches (contents kept)
	input  logic        mdis_n,       // MDIS: disable page translation
	output logic        ipend_n,      // IPEND
	output logic  [3:0] pst,          // PST3-PST0 (MC68040UM table 5-6)

	// debug / test
	output logic [31:0] dbg_pc,
	output logic        dbg_retire,
	output logic [15:0] dbg_rinfo,     // ... the committed uop's {exc, exr, first, last, 5'b0}
	output logic        dbg_xgo,       // debug: exception processing starts,
	output logic  [7:0] dbg_xvec,      // ... its vector and
	output logic [31:0] dbg_xpc,       // ... the PC it stacks
	output logic        dbg_hfgo,      // debug: an exception routine's handler fetch leaves EX,
	output logic [31:0] dbg_hfld,      // ... its load data,
	output logic [31:0] dbg_hfa,       // ... its A operand register value,
	output logic  [7:0] dbg_hff,       // ... {A source, DMU job answer, 5'0}
	output logic [31:0] dbg_hfpc,      // ... and its PC field
	output logic  [2:0] dbg_ev,        // debug: a front-end event this clock: 1 back-end redirect,
	                                   // 2 decoder redirect, 3 BTB redirect, 4 front-end flush
	                                   // without a redirect (exception entry), 5 handler fetch
	output logic [31:0] dbg_evpc,      // ... its target (5: the handler address loaded)
	output logic        dbg_halted
);

// reset synchronizer: two bus clocks, so the reset and the release of the
// bus pins it begins start on a bus clock edge.  Once RSTI negates the
// processor stays in reset for another 128 bus clocks (MC68040UM 7.10.1).
logic [1:0] rst_q = 2'b00;
logic [7:0] rst_hold = 8'd128;
always_ff @(posedge clk) begin
	if (bclk_en) rst_q <= {rst_q[0], rsti_n};
	if (!rst_q[1])                         rst_hold <= 8'd128;
	else if (bclk_en && rst_hold != 8'd0)  rst_hold <= rst_hold - 8'd1;
end
wire nreset = rst_q[1] && (rst_hold == 8'd0);

// CDIS and MDIS act at the next internal boundary: two bus-clock samples
// (the multiplexed bus mode CDIS selects at reset is not provided)
logic [1:0] cdis_s, mdis_s;
always_ff @(posedge clk)
	if (bclk_en) begin
		cdis_s <= {cdis_s[0], !cdis_n};
		mdis_s <= {mdis_s[0], !mdis_n};
	end
wire cdis = cdis_s[1];
wire mdis = mdis_s[1];

// IPEND and PST change on bus clock edges.  PST shows the end of each
// instruction for one bus clock (the last one when several end within
// it), else the present status.
logic        irq_pending, pst_ev, pst_b;
logic  [3:0] pst_code, pst_st, pst_bc;
always_ff @(posedge clk) begin
	if (!nreset) begin
		ipend_n <= 1'b1;
		pst     <= 4'h8;
		pst_b   <= 1'b0;
		pst_bc  <= 4'h8;
	end
	else begin
		if (pst_ev) begin
			pst_b  <= 1'b1;
			pst_bc <= pst_code;
		end
		if (bclk_en) begin
			ipend_n <= !irq_pending;
			pst     <= pst_ev ? pst_code : pst_b ? pst_bc : pst_st;
			pst_b   <= 1'b0;
		end
	end
end

// interrupt level synchronizer: IPL2-IPL0 are sampled on consecutive bus
// clock edges, and a level is valid once two consecutive samples agree
// (MC68040UM 7.8.1: "held constant for two consecutive clock periods")
// -- the three pins settle at different times when the level changes, so
// a single sample can show a level no device raised
logic [2:0] ipl_s1 = 3'd0, ipl_s2 = 3'd0, ipl_v = 3'd0;
always_ff @(posedge clk)
	if (bclk_en) begin
		ipl_s1 <= ~ipl_n;
		ipl_s2 <= ipl_s1;
		if (ipl_s1 == ipl_s2) ipl_v <= ipl_s2;
	end

//--------------------------------------------------------------------------
// BIU: client 0 data (DMU), client 1 instruction fetch
//--------------------------------------------------------------------------
localparam int NC = 2;
logic [NC-1:0] b_req, b_gnt, b_done, b_err;
logic          b_own;
logic [31:0]   b_d_o, sn_d_o;
logic          b_d_oe, sn_d_oe;
busreq_t       b_breq [NC];
logic [127:0]  b_wdata [NC];
logic          b_rvalid;
logic          b_rclient;
logic [31:0]   b_rdata;
logic  [1:0]   b_rbeat;
logic          b_ravec, b_rtci;
logic  [1:0]   b_errbeat;
logic          b_idle;
logic          rsto_req, rsto_busy;
logic          be_fstop;
logic          b_drop;

// (declared before their use: Vivado 2018.3 makes a separate implicit net of a
// signal an instance is connected to ahead of its declaration)
logic        kill_now, adv_ag, lk_abandon;
ap68040_biu #(.NC(NC)) biu (
	.clk(clk), .nreset(nreset), .bclk_en(bclk_en),
	// (client 1, the fetch, is held while stopped, halted or resetting)
	.req(b_req & ~{be_fstop || rsto_busy, 1'b0}), .breq(b_breq), .wdata(b_wdata),
	.gnt(b_gnt), .done(b_done), .err(b_err),
	.rvalid(b_rvalid), .rclient(b_rclient), .rdata(b_rdata), .rbeat(b_rbeat),
	.ravec(b_ravec), .rtci(b_rtci), .errbeat(b_errbeat), .idle(b_idle), .own(b_own),
	.unlock(lk_abandon), .halt(dbg_halted), .more({1'b0, 1'b0}), .drop({1'b0, b_drop}),
	.rsto_req(rsto_req), .rsto_busy(rsto_busy),
	.a_o(a_o), .a_oe(a_oe), .d_i(d_i), .d_o(b_d_o), .d_oe(b_d_oe),
	.rw_n(rw_n), .siz(siz), .tt(tt), .tm(tm), .tln(tln), .upa(upa),
	.ciout_n(ciout_n), .lock_n(lock_n), .locke_n(locke_n),
	.ts_n(ts_n), .tip_n(tip_n), .ta_n(ta_n), .tea_n(tea_n),
	.tci_n(tci_n), .tbi_n(tbi_n), .avec_n(avec_n),
	.br_n(br_n), .bg_n(bg_n), .bb_n_i(bb_n_i), .bb_n_o(bb_n_o), .bb_oe(bb_oe),
	.rsto_n(rsto_n)
);

//--------------------------------------------------------------------------
// bus snooper
//--------------------------------------------------------------------------
logic        sn_req, sn_look, sn_hit, sn_dirty, sn_inv, sn_wr;
logic [31:0] sn_pa;
logic [127:0] sn_line;
logic [31:0] sn_wword;
logic [15:0] sn_wbe;
logic        sn_ic, sn_ic_all, sn_ic_done, sn_ihit;
logic [31:0] sn_ic_pa;

ap68040_snoop snoop (
	.clk(clk), .nreset(nreset), .bclk_en(bclk_en), .own(b_own),
	.a_i(a_i), .ts_n_i(ts_n_i), .rw_n_i(rw_n_i), .siz_i(siz_i), .tt_i(tt_i), .sc(sc),
	.d_i(d_i), .ta_n_i(ta_n), .tea_n_i(tea_n), .tbi_n_i(tbi_n),
	.mi_n(mi_n), .ta_n_o(ta_n_o), .ta_oe(ta_oe), .d_o(sn_d_o), .d_oe(sn_d_oe),
	.dc_req(sn_req), .dc_pa(sn_pa), .dc_look(sn_look), .dc_hit(sn_hit),
	.dc_dirty(sn_dirty), .dc_line(sn_line), .dc_inv(sn_inv), .dc_wr(sn_wr),
	.dc_wbe(sn_wbe), .dc_wword(sn_wword),
	.ic_req(sn_ic), .ic_pa(sn_ic_pa), .ic_all(sn_ic_all), .ic_done(sn_ic_done)
);

assign d_o  = sn_d_oe ? sn_d_o : b_d_o;
assign d_oe = sn_d_oe || b_d_oe;

//--------------------------------------------------------------------------
// back end and front end
//--------------------------------------------------------------------------
logic        redir_v, flush, fe_flush;
logic [31:0] redir_pc;
logic        exc_go, exc_pend;
logic  [3:0] exc_kind;
logic  [4:0] exc_ssp;
logic        ucond_v, ucond;
logic [15:0] sr;
logic [31:0] vbr, cacr;
logic  [2:0] sfc, dfc;
logic [31:0] dtt0, dtt1, itt0, itt1, tc;
logic        q_odd;
logic        dm_hold1, mt_v, mt_ng, mt_wr, mt_done, mt_fault;
logic  [2:0] mt_op, mt_fc;
logic  [1:0] mt_scope, mt_caches;
logic [31:0] mt_addr, mt_mmusr, mt_faddr, urp, srp, dm_st_faddr;
logic [127:0] pb_data;
logic [15:0] mt_fssw;
logic  [2:0] iack_lvl;
logic  [1:0] dm_ack;

logic        dm_req, adv_dc1, adv_dc2, adv_ex, adv_wb;
logic [31:0] dm_va;
logic  [1:0] dm_mem, dm_msz;
logic  [2:0] dm_fc;
logic        dm_lock, dm_locke, dm_wi, dm_super, dm_noalloc, dm_older;
logic        bht_we, tw_busy;
logic  [7:0] bht_wa;
logic        bht_dis;
logic        lp_we, lp_tk, lp_mp;
logic [11:0] lp_wa;
logic        dm_dc2_rdy, dm_fault, dm_st_v, dm_st_rdy, dm_st_fault;
logic        rte_cont;
logic [31:0] dm_ldata, dm_faddr, dm_st_data, dm_ldata_al;
logic        dm_ldata_alv;
logic        dm_ldata_job;
logic  [7:0] dm_fvec;
logic [15:0] dm_fssw, dm_st_fssw;

logic  [1:0] uq_n;
uop_t        uq0;
logic        uo_rdy;

// (declared before their use: Vivado 2018.3 makes a separate implicit net of a
// signal an instance is connected to ahead of its declaration)
logic        ras_rv;
logic  [2:0] ras_rtp;
logic  [3:0] ras_rn;
ap68040_backend #(.FPU_REVISION(FPU_REVISION), .FPU_PIPE(FPU_PIPE), .EARLY_RES(EARLY_RES),
                  .SKID(SKID), .DIV_STEPS(DIV_STEPS), .DEBUG(DEBUG)) be (
	.clk(clk), .nreset(nreset),
	.in_v(uq_n != 2'd0), .in_u(uq0), .in_rdy(uo_rdy),
	.redir_v(redir_v), .redir_pc(redir_pc), .flush(flush), .fe_flush(fe_flush),
	.ras_rv(ras_rv), .ras_rtp(ras_rtp), .ras_rn(ras_rn),
	.exc_go(exc_go), .exc_pend(exc_pend), .exc_kind(exc_kind), .exc_ssp(exc_ssp),
	.ucond_v(ucond_v), .ucond(ucond),
	.sr(sr), .vbr(vbr), .cacr(cacr), .sfc(sfc), .dfc(dfc),
	.dm_req(dm_req), .dm_va(dm_va), .dm_mem(dm_mem), .dm_msz(dm_msz),
	.dm_fc(dm_fc), .dm_lock(dm_lock), .dm_locke(dm_locke), .dm_wi(dm_wi), .dm_super(dm_super), .dm_noalloc(dm_noalloc), .dm_ack(dm_ack), .dm_older(dm_older),
	.bht_we(bht_we), .bht_wa(bht_wa), .bht_dis(bht_dis),
	.lp_we(lp_we), .lp_wa(lp_wa), .lp_tk(lp_tk), .lp_mp(lp_mp), .sn_ihit(sn_ihit),
	.tw_busy(tw_busy), .pst_ev(pst_ev), .pst_code(pst_code), .pst_st(pst_st),
	.irq_pending(irq_pending),
	.adv_dc1(adv_dc1), .adv_dc2(adv_dc2), .adv_ex(adv_ex), .adv_wb(adv_wb),
	.dm_dc2_rdy(dm_dc2_rdy), .dm_ldata(dm_ldata), .dm_ldata_al(dm_ldata_al), .dm_ldata_alv(dm_ldata_alv), .dm_ldata_job(dm_ldata_job), .dm_fault(dm_fault),
	.dm_fvec(dm_fvec), .dm_faddr(dm_faddr), .dm_fssw(dm_fssw),
	.dm_st_v(dm_st_v), .dm_st_data(dm_st_data), .dm_st_rdy(dm_st_rdy), .rte_cont(rte_cont),
	.dm_st_fault(dm_st_fault), .dm_st_fssw(dm_st_fssw),
	.dm_hold1(dm_hold1), .mt_v(mt_v), .mt_op(mt_op), .mt_scope(mt_scope),
	.mt_caches(mt_caches), .mt_addr(mt_addr), .mt_fc(mt_fc), .mt_ng(mt_ng),
	.mt_wr(mt_wr), .mt_done(mt_done), .mt_mmusr(mt_mmusr), .mt_fault(mt_fault),
	.mt_fssw(mt_fssw), .mt_faddr(mt_faddr), .pb_data(pb_data), .dm_st_faddr(dm_st_faddr),
	.urp(urp), .srp(srp),
	.ipl(ipl_v), .iack_lvl(iack_lvl), .rsto_req(rsto_req), .rsto_busy(rsto_busy),
	.kill_now(kill_now), .lk_abandon(lk_abandon), .adv_ag(adv_ag),
	.dtt0(dtt0), .dtt1(dtt1), .itt0(itt0), .itt1(itt1), .tc(tc),
	.dbg_pc(dbg_pc), .dbg_retire(dbg_retire), .dbg_rinfo(dbg_rinfo), .dbg_xgo(dbg_xgo), .dbg_xvec(dbg_xvec), .dbg_xpc(dbg_xpc),
	.dbg_hfgo(dbg_hfgo), .dbg_hfld(dbg_hfld), .dbg_hfa(dbg_hfa), .dbg_hff(dbg_hff), .dbg_hfpc(dbg_hfpc),
	.halted(dbg_halted), .fetch_stop(be_fstop)
);

// (declared before their use: Vivado 2018.3 makes a separate implicit net of a
// signal an instance is connected to ahead of its declaration)
logic        iw_req, iw_fc2, iw_done;
logic [31:0] iw_va;
logic        ic_inv, ic_inv_done;
logic  [1:0] ic_inv_scope;
logic [31:0] ic_inv_pa;
logic        iatc_flush_all, iatc_flush_page, iatc_flush_ng, iatc_flush_fc2;
logic [31:0] iatc_flush_la;
logic        iatc_wr, iatc_wfc2;
logic [31:0] iatc_wla;
atce_t       iatc_went;
ap68040_dmu #(.DC1_ATC(DC1_ATC), .DC_WRITETHROUGH(DC_WRITETHROUGH)) dmu (
	.clk(clk), .nreset(nreset),
	.adv_ag(adv_ag), .dm_req(dm_req), .dm_va(dm_va), .dm_mem(dm_mem),
	.dm_msz(dm_msz), .dm_fc(dm_fc), .dm_lock(dm_lock), .dm_locke(dm_locke), .dm_wi(dm_wi),
	.dm_super(dm_super), .dm_noalloc(dm_noalloc), .dm_ack(dm_ack), .iack_lvl(iack_lvl),
	.dm_older(dm_older),
	.adv_dc1(adv_dc1), .adv_dc2(adv_dc2), .adv_ex(adv_ex), .adv_wb(adv_wb),
	.kill_now(kill_now), .dm_hold1(dm_hold1),
	.dc2_rdy(dm_dc2_rdy), .ldata(dm_ldata), .ldata_al(dm_ldata_al), .ldata_alv(dm_ldata_alv), .ldata_job(dm_ldata_job), .fault(dm_fault), .fvec(dm_fvec),
	.faddr(dm_faddr), .fssw(dm_fssw),
	.st_v(dm_st_v), .st_data(dm_st_data), .st_rdy(dm_st_rdy),
	.st_fault(dm_st_fault), .st_fssw(dm_st_fssw), .st_faddr(dm_st_faddr),
	.mt_v(mt_v), .mt_op(mt_op), .mt_scope(mt_scope), .mt_caches(mt_caches),
	.mt_addr(mt_addr), .mt_fc(mt_fc), .mt_ng(mt_ng), .mt_wr(mt_wr),
	.mt_done(mt_done), .mt_mmusr(mt_mmusr), .mt_fault(mt_fault), .mt_fssw(mt_fssw),
	.mt_faddr(mt_faddr), .pb_data(pb_data),
	.cacr(cacr), .tc(tc), .urp(urp), .srp(srp),
	.dtt0(dtt0), .dtt1(dtt1), .itt0(itt0), .itt1(itt1),
	.cdis(cdis), .mdis(mdis), .tw_busy(tw_busy),
	.iw_req(iw_req), .iw_va(iw_va), .iw_fc2(iw_fc2), .iw_done(iw_done), .iw_ent(),
	.ic_inv(ic_inv), .ic_inv_scope(ic_inv_scope), .ic_inv_pa(ic_inv_pa),
	.ic_inv_done(ic_inv_done),
	.iatc_flush_all(iatc_flush_all), .iatc_flush_page(iatc_flush_page),
	.iatc_flush_ng(iatc_flush_ng), .iatc_flush_la(iatc_flush_la),
	.iatc_flush_fc2(iatc_flush_fc2), .iatc_wr(iatc_wr), .iatc_wla(iatc_wla),
	.iatc_wfc2(iatc_wfc2), .iatc_went(iatc_went),
	.b_req(b_req[0]), .b_breq(b_breq[0]), .b_wdata(b_wdata[0]),
	.b_gnt(b_gnt[0]), .b_done(b_done[0]), .b_err(b_err[0]), .b_drop(b_drop),
	.b_rvalid(b_rvalid && b_rclient == 1'b0), .b_rdata(b_rdata), .b_rbeat(b_rbeat),
	.b_ravec(b_ravec), .b_rtci(b_rtci),
	.sn_req(sn_req), .sn_pa(sn_pa), .sn_look(sn_look), .sn_hit(sn_hit),
	.sn_dirty(sn_dirty), .sn_line(sn_line), .sn_inv(sn_inv), .sn_wr(sn_wr),
	.sn_wbe(sn_wbe), .sn_wword(sn_wword)
);

// instruction side <-> DMU

// front end
logic [15:0] win [8];
logic  [7:0] win_flt, win_fdem, win_fatc, win_bt;
logic [31:0] bt_tgt;
logic        btb_we, btb_wv, btb_wslot;
logic [BTB_AW-1:0] btb_wi;
logic [BTB_TW-1:0] btb_wtag;
logic [30:0] btb_wtgt;
logic  [1:0] btb_wkind;
logic [30:0] d_ras;
logic  [2:0] d_ras_tp;
logic  [3:0] d_ras_n;
pd_t         pd0, pd0_n;
logic  [3:0] qcnt;
logic [31:0] qpc;
logic  [2:0] consume;
logic        d_redir_v;
logic [31:0] d_redir_pc;
logic        dbg_btgo;
logic [31:0] dbg_btpc;
always_comb begin
	dbg_ev = 3'd0; dbg_evpc = 32'd0;
	if (!DEBUG)         begin end
	else if (redir_v)   begin dbg_ev = 3'd1; dbg_evpc = redir_pc; end
	else if (d_redir_v) begin dbg_ev = 3'd2; dbg_evpc = d_redir_pc; end
	else if (dbg_btgo)  begin dbg_ev = 3'd3; dbg_evpc = dbg_btpc; end
	else if (dbg_hfgo)  begin dbg_ev = 3'd5; dbg_evpc = dbg_hfld; end
	else if (fe_flush)  begin dbg_ev = 3'd4; dbg_evpc = 32'd0; end
end
logic  [1:0] rq_n;
dinst_t      rq0, rq1;
logic        rq_pop, rq_pop_e;

ap68040_fetch #(.DEBUG(DEBUG)) fetch (
	.clk(clk), .nreset(nreset),
	.redir_v(redir_v), .redir_pc(redir_pc),
	.d_redir_v(d_redir_v), .d_redir_pc(d_redir_pc),
	.dbg_btgo(dbg_btgo), .dbg_btpc(dbg_btpc),
	// no fetches while stopped or halted, nor while RSTO is asserted
	.stop(be_fstop || rsto_busy), .smode(sr[13] || rte_cont),
	.cacr(cacr), .tc(tc), .itt0(itt0), .itt1(itt1), .cdis(cdis), .mdis(mdis),
	.win(win), .win_flt(win_flt), .win_fdem(win_fdem), .win_fatc(win_fatc),
	.win_bt(win_bt), .bt_tgt(bt_tgt),
	.pd0(pd0), .pd0_n(pd0_n), .qcnt(qcnt), .qpc(qpc), .consume(consume),
	.q_odd(q_odd),
	.btb_we(btb_we), .btb_wi(btb_wi), .btb_wv(btb_wv), .btb_wtag(btb_wtag),
	.btb_wslot(btb_wslot), .btb_wkind(btb_wkind), .btb_wtgt(btb_wtgt),
	.d_ras(d_ras), .d_ras_tp(d_ras_tp), .d_ras_n(d_ras_n),
	.iw_req(iw_req), .iw_va(iw_va), .iw_fc2(iw_fc2), .iw_done(iw_done),
	.iatc_wr(iatc_wr), .iatc_wla(iatc_wla), .iatc_wfc2(iatc_wfc2), .iatc_went(iatc_went),
	.iatc_flush_all(iatc_flush_all), .iatc_flush_page(iatc_flush_page),
	.iatc_flush_ng(iatc_flush_ng), .iatc_flush_la(iatc_flush_la),
	.iatc_flush_fc2(iatc_flush_fc2),
	.ic_inv(ic_inv), .ic_inv_scope(ic_inv_scope), .ic_inv_pa(ic_inv_pa),
	.ic_inv_done(ic_inv_done),
	.sn_inv(sn_ic), .sn_inv_pa(sn_ic_pa), .sn_inv_all(sn_ic_all), .sn_inv_done(sn_ic_done),
	.sn_ihit(sn_ihit),
	.xi_inv(xinv_req), .xi_inv_pa(xinv_pa), .xi_inv_all(xinv_all), .xi_inv_done(xinv_done),
	.b_req(b_req[1]), .b_breq(b_breq[1]),
	.b_gnt(b_gnt[1]), .b_done(b_done[1]), .b_err(b_err[1]),
	.b_rvalid(b_rvalid && b_rclient == 1'b1), .b_rdata(b_rdata), .b_rbeat(b_rbeat),
	.b_rtci(b_rtci)
);
assign b_wdata[1] = '0;

ap68040_decode #(.LOOP_PRED(LOOP_PRED)) dec (
	.clk(clk), .nreset(nreset), .flush(fe_flush),
	.ras_rv(ras_rv), .ras_rtp(ras_rtp), .ras_rn(ras_rn),
	.win(win), .win_flt(win_flt), .win_fdem(win_fdem), .win_fatc(win_fatc),
	.win_bt(win_bt), .bt_tgt(bt_tgt),
	.pd0(pd0), .pd0_n(pd0_n), .qcnt(qcnt), .qpc(qpc), .q_odd(q_odd),
	.smode(sr[13] || rte_cont),
	.consume(consume), .d_redir_v(d_redir_v), .d_redir_pc(d_redir_pc),
	.rq_n(rq_n), .rq0(rq0), .rq1(rq1), .rq_pop(rq_pop), .rq_pop_e(rq_pop_e),
	.bht_we(bht_we), .bht_wa(bht_wa), .bht_dis(bht_dis),
	.lp_we(lp_we), .lp_wa(lp_wa), .lp_tk(lp_tk), .lp_mp(lp_mp),
	.btb_we(btb_we), .btb_wi(btb_wi), .btb_wv(btb_wv), .btb_wtag(btb_wtag),
	.btb_wslot(btb_wslot), .btb_wkind(btb_wkind), .btb_wtgt(btb_wtgt),
	.ras_o(d_ras), .ras_tp_o(d_ras_tp), .ras_n_o(d_ras_n)
);

ap68040_useq useq (
	.clk(clk), .nreset(nreset), .flush(fe_flush),
	.rq_n(rq_n), .rq0(rq0), .rq1(rq1), .rq_pop(rq_pop), .rq_pop_e(rq_pop_e),
	.smode(sr[13]), .master(sr[12]),
	.exc_go(exc_go), .exc_pend(exc_pend), .exc_kind(exc_kind), .exc_ssp(exc_ssp),
	.uq_n(uq_n), .uq0(uq0), .uq_pop(uo_rdy && uq_n != 2'd0)
);

endmodule
// ---- ap68040_alu.sv ----
//--------------------------------------------------------------------------//
// AP68040 - pipelined MC68040                                            //
//                                                                          //
// ap68040_alu.sv - EX-stage single-cycle integer unit: arithmetic, logic,  //
// bit operations, condition codes (shifts and BCD: ap68040_alu_slow)       //
//                                                                          //
// Conventions (same as the 68k "OP src,dst"):                              //
//   a  source operand, b destination operand, res = b OP a                 //
//   res is the full 32-bit register image: for byte and word sizes the     //
//   bits above the operand size are b's (so a data register write merges)  //
//   flags are {X,N,Z,V,C}; flags_out is the complete new CCR, the uop's    //
//   ccr_we mask decides which bits are actually written                    //
//                                                                          //
// Undefined-flag behaviour is the 68040's, as WinUAE's newcpu_common.cpp   //
// models it (verified against the cputest 68040 corpus on the previous     //
// core): BCD leaves N and V unchanged; CHK writes N, and C per             //
// setchkundefinedflags; CHK2/CMP2 write only Z and C.                      //
//--------------------------------------------------------------------------//

module ap68040_alu
	import ap68040_pkg::*;
(
	input  logic  [6:0] op,
	input  logic  [1:0] sz,
	input  logic  [3:0] cond,
	input  logic [31:0] a,
	input  logic [31:0] b,
	input  logic [31:0] ea,
	input  logic  [4:0] flags_in,   // X N Z V C
	output logic [31:0] res,
	output logic  [4:0] flags_out,
	output logic        cc_true,    // cond evaluated on flags_in
	output logic        trap        // CHK / CHK2 / TRAPcc exception
);

wire f_x = flags_in[4];
wire f_n = flags_in[3];
wire f_z = flags_in[2];
wire f_v = flags_in[1];
wire f_c = flags_in[0];

//--------------------------------------------------------------------------
// condition codes (MC68040UM table 3-19 / PRM 3.6)
//--------------------------------------------------------------------------
always_comb begin
	case (cond)
		4'h0: cc_true = 1'b1;                       // T
		4'h1: cc_true = 1'b0;                       // F
		4'h2: cc_true = !f_c && !f_z;               // HI
		4'h3: cc_true = f_c || f_z;                 // LS
		4'h4: cc_true = !f_c;                       // CC
		4'h5: cc_true = f_c;                        // CS
		4'h6: cc_true = !f_z;                       // NE
		4'h7: cc_true = f_z;                        // EQ
		4'h8: cc_true = !f_v;                       // VC
		4'h9: cc_true = f_v;                        // VS
		4'hA: cc_true = !f_n;                       // PL
		4'hB: cc_true = f_n;                        // MI
		4'hC: cc_true = f_n == f_v;                 // GE
		4'hD: cc_true = f_n != f_v;                 // LT
		4'hE: cc_true = !f_z && (f_n == f_v);       // GT
		default: cc_true = f_z || (f_n != f_v);     // LE
	endcase
end

//--------------------------------------------------------------------------
// sized views
//--------------------------------------------------------------------------
logic [31:0] szmask;
logic  [5:0] nbits;
always_comb begin
	case (sz)
		SZ_B:    begin szmask = 32'h0000_00FF; nbits = 6'd8;  end
		SZ_W:    begin szmask = 32'h0000_FFFF; nbits = 6'd16; end
		default: begin szmask = 32'hFFFF_FFFF; nbits = 6'd32; end
	endcase
end

wire [31:0] am = a & szmask;
wire [31:0] bm = b & szmask;

function automatic logic msb_of(input logic [31:0] v, input logic [1:0] s);
	case (s)
		SZ_B:    msb_of = v[7];
		SZ_W:    msb_of = v[15];
		default: msb_of = v[31];
	endcase
endfunction

function automatic logic carry_of(input logic [32:0] v, input logic [1:0] s);
	case (s)
		SZ_B:    carry_of = v[8];
		SZ_W:    carry_of = v[16];
		default: carry_of = v[32];
	endcase
endfunction

wire a_msb = msb_of(a, sz);
wire b_msb = msb_of(b, sz);

// merge a sized result into b's upper bits
function automatic logic [31:0] merge(input logic [31:0] r, input logic [31:0] bb,
                                      input logic [31:0] m);
	merge = (r & m) | (bb & ~m);
endfunction

//--------------------------------------------------------------------------
// adder: one shared add/subtract with optional X-in
//--------------------------------------------------------------------------
logic        is_sub, use_x, b_zero;
always_comb begin
	is_sub = (op == OP_SUB) || (op == OP_SUBX) || (op == OP_CMP) ||
	         (op == OP_NEG) || (op == OP_NEGX);
	use_x  = (op == OP_ADDX) || (op == OP_SUBX) || (op == OP_NEGX);
	b_zero = (op == OP_NEG) || (op == OP_NEGX);
end

// NEG is 0 - b: the subtrahend is b, the minuend zero
wire [31:0] add_l  = b_zero ? 32'd0 : bm;
wire [31:0] add_r  = b_zero ? bm    : am;
wire        cin    = use_x & f_x;
wire [32:0] sum    = is_sub ? ({1'b0, add_l} - {1'b0, add_r} - {32'd0, cin})
                            : ({1'b0, add_l} + {1'b0, add_r} + {32'd0, cin});
wire        sum_c  = carry_of(sum, sz);
wire        sum_n  = msb_of(sum[31:0], sz);
wire        sum_z  = (sum[31:0] & szmask) == 32'd0;
wire        l_msb  = b_zero ? 1'b0  : b_msb;
wire        r_msb  = b_zero ? b_msb : a_msb;
wire        sum_v  = is_sub ? ((l_msb != r_msb) && (sum_n != l_msb))
                            : ((l_msb == r_msb) && (sum_n != l_msb));

//--------------------------------------------------------------------------
// bit operations: a holds the bit number, already reduced mod 32 (register)
// or mod 8 (memory byte) by the size
//--------------------------------------------------------------------------
wire  [4:0] bitn     = (sz == SZ_B) ? {2'b00, a[2:0]} : a[4:0];
wire [31:0] bit_mask = 32'd1 << bitn;
wire        bit_set  = |(b & bit_mask);

//--------------------------------------------------------------------------
// CHK (b = Dn, a = upper bound), sized W or L, signed
//--------------------------------------------------------------------------
wire        chk_dn_neg = b_msb;
wire        chk_ub_neg = a_msb;
wire [32:0] chk_diff   = {1'b0, am} - {1'b0, bm};   // bound - Dn
wire        chk_gt     = (chk_ub_neg != chk_dn_neg) ? chk_ub_neg
                                                    : msb_of(chk_diff[31:0], sz);
wire        chk_trap   = chk_dn_neg || chk_gt;
// setchkundefinedflags (68040): C set on trap per the src/dst relation
wire        chk_c      = (chk_dn_neg && !chk_ub_neg) ||
                         (!chk_ub_neg && !chk_dn_neg && chk_gt) ||
                         (chk_dn_neg && chk_ub_neg && msb_of(chk_diff[31:0], sz));

//--------------------------------------------------------------------------
// CHK2/CMP2: b is the value, a the bound; signedness from cond[1]
// (signed when the instruction's register is an address register or the
// bounds compare signed: the 68040 compares as signed when the bounds are
// signed, i.e. lower > upper as unsigned is the wrap case).  The two steps
// keep the lower-bound result in chk2_lo for the second.
//--------------------------------------------------------------------------
// handled in the back end (needs state across two uops)

//--------------------------------------------------------------------------
// result and flags
//--------------------------------------------------------------------------
always_comb begin
	logic [31:0] r;
	r         = b;
	flags_out = flags_in;
	trap      = 1'b0;
	res       = b;

	case (op)
		OP_MOV: begin
			r = merge(am, b, szmask);
			flags_out = {f_x, msb_of(am, sz), am == 32'd0, 1'b0, 1'b0};
		end

		OP_ADD, OP_SUB: begin
			r = merge(sum[31:0], b, szmask);
			flags_out = {sum_c, sum_n, sum_z, sum_v, sum_c};
		end

		OP_ADDX, OP_SUBX, OP_NEGX: begin
			r = merge(sum[31:0], b, szmask);
			flags_out = {sum_c, sum_n, f_z & sum_z, sum_v, sum_c};
		end

		OP_NEG: begin
			r = merge(sum[31:0], b, szmask);
			flags_out = {sum_c, sum_n, sum_z, sum_v, sum_c};
		end

		OP_CMP: begin
			r = b;
			flags_out = {f_x, sum_n, sum_z, sum_v, sum_c};
		end

		OP_AND, OP_OR, OP_EOR, OP_NOT: begin
			logic [31:0] l;
			case (op)
				OP_AND:  l = bm & am;
				OP_OR:   l = bm | am;
				OP_EOR:  l = bm ^ am;
				default: l = ~bm & szmask;
			endcase
			r = merge(l, b, szmask);
			flags_out = {f_x, msb_of(l, sz), l == 32'd0, 1'b0, 1'b0};
		end

		OP_CLR: begin
			r = merge(32'd0, b, szmask);
			flags_out = {f_x, 1'b0, 1'b1, 1'b0, 1'b0};
		end

		OP_EXT: begin
			if (sz == SZ_W) begin
				r = {b[31:16], {8{b[7]}}, b[7:0]};
				flags_out = {f_x, b[7], b[7:0] == 8'd0, 1'b0, 1'b0};
			end
			else begin
				r = {{16{b[15]}}, b[15:0]};
				flags_out = {f_x, b[15], b[15:0] == 16'd0, 1'b0, 1'b0};
			end
		end

		OP_EXTB: begin
			r = {{24{b[7]}}, b[7:0]};
			flags_out = {f_x, b[7], b[7:0] == 8'd0, 1'b0, 1'b0};
		end

		OP_SWAP: begin
			r = {b[15:0], b[31:16]};
			flags_out = {f_x, b[15], b == 32'd0, 1'b0, 1'b0};
		end

		OP_TAS: begin
			r = {b[31:8], 1'b1, b[6:0]};
			flags_out = {f_x, b[7], b[7:0] == 8'd0, 1'b0, 1'b0};
		end

		OP_BTST: begin
			r = b;
			flags_out = {f_x, f_n, !bit_set, f_v, f_c};
		end
		OP_BCHG: begin
			r = b ^ bit_mask;
			flags_out = {f_x, f_n, !bit_set, f_v, f_c};
		end
		OP_BCLR: begin
			r = b & ~bit_mask;
			flags_out = {f_x, f_n, !bit_set, f_v, f_c};
		end
		OP_BSET: begin
			r = b | bit_mask;
			flags_out = {f_x, f_n, !bit_set, f_v, f_c};
		end

		OP_SCC: r = {b[31:8], {8{cc_true}}};

		OP_EA: r = ea;

		OP_DBCC: r = {b[31:16], b[15:0] - 16'd1};

		OP_TRAPCC: trap = cc_true;

		OP_CHK: begin
			trap = chk_trap;
			flags_out = {f_x, chk_dn_neg, f_z, f_v, chk_trap ? chk_c : 1'b0};
		end

		OP_CCRLOG: begin
			case (cond[1:0])
				2'd0:    flags_out = flags_in & a[4:0];
				2'd1:    flags_out = flags_in | a[4:0];
				2'd2:    flags_out = flags_in ^ a[4:0];
				default: flags_out = a[4:0];
			endcase
		end

		default: r = b;
	endcase
	res = r;
end

endmodule
// ---- ap68040_alu_slow.sv ----
//--------------------------------------------------------------------------//
// AP68040 - pipelined MC68040                                            //
//                                                                          //
// ap68040_alu_slow.sv - EX-stage two-cycle integer unit: shifts and        //
// rotates, BCD, PACK/UNPK.  Its outputs are registered by the back end     //
// before they are used (the op holds EX for a second cycle).               //
//                                                                          //
// Same conventions and 68040 flag rules as ap68040_alu.                    //
//--------------------------------------------------------------------------//

module ap68040_alu_slow
	import ap68040_pkg::*;
(
	input  logic  [6:0] op,
	// the shift's kind, one-hot, decoded from op as the uop enters EX and
	// registered (the funnel's amount and input selects start from these
	// flip-flops, not from a decode of op): ASL LSL ASR LSR ROL ROR ROXL ROXR
	input  logic  [7:0] shk,
	input  logic  [1:0] sz,
	input  logic [31:0] a,
	input  logic [31:0] b,
	input  logic  [5:0] cnt,        // shift count: a[5:0], without a's mux
	input  logic  [5:0] nx_q,       // ROXL/ROXR: the count mod (size + 1), registered
	output logic  [5:0] nx,         // ... formed here from cnt (for that register)
	input  logic  [6:0] nxl_q,      // ROXL: the funnel's amount, size + 1 - nx, registered
	output logic  [6:0] nxl,        // ... formed here from nx (for that register)
	input  logic  [4:0] flags_in,   // X N Z V C
	output logic [31:0] res,
	output logic  [4:0] flags_out,
	output logic        sim_c       // (simulation: the carry as the funnel forms it)
);

wire f_x = flags_in[4];
wire f_n = flags_in[3];
wire f_z = flags_in[2];
wire f_v = flags_in[1];
wire f_c = flags_in[0];

logic [31:0] szmask;
logic  [5:0] nbits;
always_comb begin
	case (sz)
		SZ_B:    begin szmask = 32'h0000_00FF; nbits = 6'd8;  end
		SZ_W:    begin szmask = 32'h0000_FFFF; nbits = 6'd16; end
		default: begin szmask = 32'hFFFF_FFFF; nbits = 6'd32; end
	endcase
end

wire [31:0] am = a & szmask;
wire [31:0] bm = b & szmask;

function automatic logic msb_of(input logic [31:0] v, input logic [1:0] s);
	case (s)
		SZ_B:    msb_of = v[7];
		SZ_W:    msb_of = v[15];
		default: msb_of = v[31];
	endcase
endfunction

function automatic logic [31:0] merge(input logic [31:0] r, input logic [31:0] bb,
                                      input logic [31:0] m);
	merge = (r & m) | (bb & ~m);
endfunction

wire b_msb = msb_of(b, sz);

//--------------------------------------------------------------------------
// BCD (byte).  Decimal corrections apply to the whole byte, so a +/-6
// low-nibble adjust ripples into the high nibble; the carry comes from the
// corrected value (68040 hardware, cputest 68040_default).
//--------------------------------------------------------------------------
wire [4:0] abcd_lo  = {1'b0, b[3:0]} + {1'b0, a[3:0]} + {4'd0, f_x};
wire [9:0] abcd_sum = {2'd0, b[7:0]} + {2'd0, a[7:0]} + {9'd0, f_x}
                    + ((abcd_lo > 5'd9) ? 10'd6 : 10'd0);
wire       abcd_c   = ((abcd_sum & 10'h3F0) > 10'h090);
wire [9:0] abcd_res = abcd_sum + (abcd_c ? 10'h060 : 10'd0);

// SBCD b - a - X and NBCD 0 - b - X share one datapath
wire [7:0] sb_l     = (op == OP_NBCD) ? 8'd0 : b[7:0];
wire [7:0] sb_r     = (op == OP_NBCD) ? b[7:0] : a[7:0];
wire       sbcd_lb  = ({1'b0, sb_l[3:0]} < ({1'b0, sb_r[3:0]} + {4'd0, f_x}));
wire [9:0] sbcd_raw = {2'd0, sb_l} - {2'd0, sb_r} - {9'd0, f_x};
wire [9:0] sbcd_cor = sbcd_raw - (sbcd_lb ? 10'd6 : 10'd0);
wire [9:0] sbcd_res = sbcd_cor - (sbcd_raw[9] ? 10'h060 : 10'd0);
wire       sbcd_c   = sbcd_cor[9];

// PACK: b holds the two unpacked bytes of the word, a the adjustment
wire [15:0] pk_sum  = b[15:0] + a[15:0];
wire  [7:0] pack_r  = {pk_sum[11:8], pk_sum[3:0]};
// UNPK: b holds the packed byte
wire [15:0] unpk_r  = {4'd0, b[7:4], 4'd0, b[3:0]} + a[15:0];

//--------------------------------------------------------------------------
// shifts and rotates: closed forms of the 68040's per-step semantics.
// count = cnt (a[5:0]; register counts are mod 64, immediate counts 1..8).
//--------------------------------------------------------------------------
logic [31:0] sh_r;
logic        sh_c, sh_x, sh_v;
// One right funnel (66 bits) does LSR, ASR, ROR, ROL, ROXR and ROXL; one
// left funnel does LSL and ASL.  The right funnel's input is the operand
// zero- or sign-extended (with a 0 below it: the bit just below the
// result is the last bit shifted out, the carry), or repeated with the
// rotate's period (the size, or the size + 1 with X for ROXR/ROXL), so a
// right shift by the rotate count leaves the rotated value at the bottom.
// A left rotate is a right rotate by the period less the count.
logic  [5:0] sh_n, sh_nm, sh_nx;
logic [65:0] rv, ro;
logic  [6:0] ra;
logic [65:0] lo;
always_comb begin
	logic [31:0] yv, tm;
	logic        vl;
	sh_n  = cnt;
	sh_nm = sh_n & (nbits - 6'd1);
	// n mod (size + 1) for ROXL/ROXR by subtracting multiples (no divider):
	// formed here (nx), registered by the back end in a cycle of its own,
	// and used from that register (nx_q) -- the subtractions stay off the
	// shifter's path
	sh_nx = sh_n;
	case (nbits)
		6'd8: begin
			if (sh_nx >= 6'd36) sh_nx = sh_nx - 6'd36;
			if (sh_nx >= 6'd18) sh_nx = sh_nx - 6'd18;
			if (sh_nx >= 6'd9)  sh_nx = sh_nx - 6'd9;
		end
		6'd16: begin
			if (sh_nx >= 6'd34) sh_nx = sh_nx - 6'd34;
			if (sh_nx >= 6'd17) sh_nx = sh_nx - 6'd17;
		end
		default: if (sh_nx >= 6'd33) sh_nx = sh_nx - 6'd33;
	endcase
	nx    = sh_nx;
	// ROXL's funnel amount, size + 1 - the count, formed with the count
	// (its subtraction in the pre-cycle too, off the funnel's path)
	nxl   = (sh_nx == 6'd0) ? 7'd0 : ({1'b0, nbits} + 7'd1 - {1'b0, sh_nx});
	sh_nx = nx_q;
	// the right funnel's input and count.  A rotate's input repeats its
	// period P from bit 0 ({P, P}): shifted right by k (< the period), its
	// low bits are P rotated right by k
	if (shk[2]) begin               // ASR
		rv = {{34{b_msb}}, bm, 1'b0};
		case (sz)
			SZ_B:    rv[65:9]  = {57{b_msb}};
			SZ_W:    rv[65:17] = {49{b_msb}};
			default: ;
		endcase
		ra = {1'b0, sh_n};
	end
	else if (shk[4] || shk[5]) begin    // ROL, ROR
		case (sz)
			SZ_B:    rv = {50'd0, bm[7:0], bm[7:0]};
			SZ_W:    rv = {34'd0, bm[15:0], bm[15:0]};
			default: rv = {2'd0, bm, bm};
		endcase
		// ROL by k: the doubled operand shifted right by size - 1 - k
		// (the count's complement within the size: no subtraction) and
		// taken one bit up (ro[32:1], as a right shift's result)
		ra = shk[5] ? {1'b0, sh_nm} : {1'b0, ~sh_nm & (nbits - 6'd1)};
	end
	else if (shk[6] || shk[7]) begin    // ROXL, ROXR
		case (sz)
			SZ_B:    rv = {48'd0, f_x, bm[7:0], f_x, bm[7:0]};
			SZ_W:    rv = {32'd0, f_x, bm[15:0], f_x, bm[15:0]};
			default: rv = {f_x, bm, f_x, bm};
		endcase
		ra = shk[7] ? {1'b0, sh_nx} : nxl_q;
	end
	else if (shk[0] || shk[1]) begin    // ASL, LSL
		// a left shift through the same funnel: the operand above 31
		// zeros, shifted right by 31 - n (the count inverted, no
		// subtraction), is the operand shifted left by n; n >= 32
		// shifts everything out (C of a long shifted by 32: below)
		rv = {3'd0, bm, 31'd0};
		ra = sh_n[5] ? 7'd127 : {2'd0, ~sh_n[4:0]};
	end
	else begin                          // LSR
		rv = {33'd0, bm, 1'b0};
		ra = {1'b0, sh_n};
	end
	ro = shk[2] ? 66'($signed(rv) >>> ra) : (rv >> ra);
	lo = ro;                      // (ASL, LSL: the operand shifted left by n)
	// ASL: V when the bits shifted out and the new sign bit are not all
	// equal, i.e. the top count+1 bits of the operand (at the size) differ
	// somewhere: an adjacent pair among them differs.  yv[i] = x[i] ^ x[i-1],
	// tm marks the top count positions; no shifter on the path
	yv = bm ^ {bm[30:0], 1'b0};
	for (int i = 0; i < 32; i++)
		tm[i] = (6'(i) < nbits) && ((nbits - 6'd1 - 6'(i)) < sh_n);
	vl = (yv & tm) != 32'd0;
	sh_r = bm;
	sh_v = 1'b0;
	if (sh_n != 6'd0) begin
		if (shk[0] || shk[1]) begin         // ASL, LSL
			sh_r = lo[31:0] & szmask;
			if (shk[0])
				sh_v = (sh_n >= nbits) ? (bm != 0) : vl;
		end
		else if (shk[3] || shk[2] || shk[4]) sh_r = ro[32:1] & szmask;   // LSR, ASR, ROL
		else sh_r = ro[31:0] & szmask;      // ROR, ROXL, ROXR
	end
	// The carry (the last bit moved out) and X come from the operand bit
	// at that step's index -- one 32:1 multiplexer on the operand, the
	// index a subtraction from the count -- not from the funnel: C and X
	// are needed in the op's first cycle (N and Z come from the registered
	// result in the second), and the funnel with the flag multiplexers
	// behind it does not close at 60 MHz.  The funnel's own carry (sim_c)
	// is checked against it in simulation.
	//   LSL/ASL by n (1..size):  bit size-n;  n > size: 0
	//   LSR by n:                bit n-1;     n > size: 0;  ASR: the sign
	//   ROL by k = n mod size:   bit size-k (k = 0: bit 0)
	//   ROR by k:                bit k-1     (k = 0: bit size-1)
	//   ROXL by m = n mod (size+1): bit size-m;  ROXR: bit m-1;  m = 0: X
	//   count 0: C = 0 (ROXL/ROXR: X); X unchanged (shifts: X = C)
	begin : direct_c
		logic [5:0] ck, ci;
		logic       left, rox, rot, c_bit;
		rox  = shk[6] || shk[7];
		rot  = shk[4] || shk[5];
		left = shk[0] || shk[1] || shk[4] || shk[6];
		ck   = rox ? sh_nx : rot ? sh_nm : sh_n;
		ci   = left ? (nbits - ck) : (ck - 6'd1);
		if (rot && sh_nm == 6'd0) ci = shk[4] ? 6'd0 : (nbits - 6'd1);
		c_bit = bm[ci[4:0]];
		if (sh_n == 6'd0)             sh_c = rox ? f_x : 1'b0;
		else if (rox)                 sh_c = (sh_nx == 6'd0) ? f_x : c_bit;
		else if (rot)                 sh_c = c_bit;
		else if (sh_n > nbits)        sh_c = shk[2] ? b_msb : 1'b0;
		else                          sh_c = c_bit;
		sh_x = (sh_n != 6'd0 && !rot) ? sh_c : f_x;
	end
end
// (simulation) the carry from the funnel, the form the direct one replaces
always_comb begin
	sim_c = 1'b0;
	if (sh_n != 6'd0) begin
		case (op)
			OP_ASL, OP_LSL: sim_c = (sh_n <= nbits) && (sh_n[5] ? bm[0] : lo[nbits]);
			OP_LSR, OP_ASR: sim_c = ro[0];
			OP_ROL:         sim_c = ro[1];
			OP_ROR:         sim_c = ro[nbits - 6'd1];
			default:        sim_c = ro[nbits];   // ROXL, ROXR
		endcase
	end
	else if (op == OP_ROXL || op == OP_ROXR) sim_c = f_x;
end

always_comb begin
	res       = b;
	flags_out = flags_in;
	case (op)
		OP_ABCD: begin
			res = {b[31:8], abcd_res[7:0]};
			flags_out = {abcd_c, f_n, f_z & (abcd_res[7:0] == 8'd0), f_v, abcd_c};
		end
		OP_SBCD, OP_NBCD: begin
			res = {b[31:8], sbcd_res[7:0]};
			flags_out = {sbcd_c, f_n, f_z & (sbcd_res[7:0] == 8'd0), f_v, sbcd_c};
		end
		OP_PACK: res = {b[31:8], pack_r};
		OP_UNPK: res = {b[31:16], unpk_r};
		OP_ASL, OP_ASR, OP_LSL, OP_LSR, OP_ROL, OP_ROR, OP_ROXL, OP_ROXR: begin
			// (N and Z: the back end forms them from the registered result
			// in the op's second cycle; nothing of the funnel reaches the
			// flags here)
			res = merge(sh_r, b, szmask);
			flags_out = {sh_x, 1'b0, 1'b0, sh_v, sh_c};
		end
		default: ;
	endcase
end

endmodule
// ---- ap68040_atc.sv ----
//--------------------------------------------------------------------------//
// AP68040 - pipelined MC68040                                            //
//                                                                          //
// ap68040_atc.sv - address translation cache (MC68040UM 3.3)                //
//                                                                          //
// 64 entries, four-way set associative, 16 sets indexed by LA15-12 (4K     //
// pages) or LA16-13 (8K pages).  The tag is FC2 and the logical page; the  //
// entry holds the physical page and the page attributes.  Valid and global //
// bits are flip-flops (PFLUSHA/PFLUSHAN in one cycle); tags and entries    //
// are MLAB (asynchronous read).                                            //
//                                                                          //
// Lookup: la/fc2 are the caller's registered address; the four ways are   //
// compared here and the hit way's entry returned.  Replacement takes an    //
// existing entry for the same page, else the first invalid way, else the  //
// way a 2-bit counter points to (the counter advances on every miss fill).//
// PFLUSH by page reads the set through the lookup port: the caller holds  //
// the lookup inputs on the page for one cycle while flush_page is high.   //
//--------------------------------------------------------------------------//

module ap68040_atc
	import ap68040_pkg::*;
#(
	// an install looks for its page among the set's entries (a data
	// access's M-bit update rewrites its own entry).  0: no copy for the
	// search -- the caller says whether the page is there (wsame) and in
	// which way (the hit vector of the lookup that started the search)
	parameter bit SAME_SEARCH = 1,
	// the lookup's set from the caller, registered (set_m), not formed from
	// la: no logic between the caller's flip-flops and the entries' read
	// address
	parameter bit EXT_SET = 0
)
(
	input  logic        clk,
	input  logic        nreset,
	input  logic        p8k,           // TC.P: 8 Kbyte pages

	// lookup
	input  logic [31:0] la,
	input  logic        fc2,
	input  logic  [3:0] set_m,         // (EXT_SET) la's set
	output logic        hit,
	output atce_t       ent,
	output logic  [3:0] hv,            // the hit way (one-hot), and every way's
	output logic [19:0] wpa [4],       // physical page: a caller's tag compares
	                                   // run against all four in parallel
	// a second lookup port (the DMU's DC1: its own copy of the entries, so
	// no address multiplexer in front of it): its set is given registered
	input  logic [31:0] la_d,
	input  logic        fc2_d,
	input  logic  [3:0] set_d,
	output logic  [3:0] hv_d,
	output logic [19:0] wpa_d [4],

	// install (one cycle)
	input  logic        wr,
	input  logic [31:0] wla,
	input  logic        wfc2,
	input  atce_t       went,
	input  logic        wsame,         // (SAME_SEARCH 0) the page is in the set ...
	input  logic  [3:0] wsame_hv,      // ... in this way (one-hot)

	// flushes (one cycle each)
	input  logic        flush_all,      // PFLUSHA / PFLUSHAN
	input  logic        flush_page,     // PFLUSH / PFLUSHN (la/fc2 = the page)
	input  logic        flush_nonglobal // the N variants spare global entries
);

typedef struct packed {
	logic        fc2;
	logic [19:0] lpn;     // LA31-12 (bit 12 ignored with 8K pages)
	atce_t       e;
} slot_t;

localparam int SW = $bits(slot_t);

logic [3:0] v   [16];     // valid, per set and way
logic [3:0] g   [16];     // global
logic [1:0] rr;           // replacement counter

wire [3:0] lset = EXT_SET ? set_m : p8k ? la[16:13] : la[15:12];
wire [3:0] wset = p8k ? wla[16:13] : wla[15:12];

slot_t s [4];
slot_t ws [4];
// synthesis translate_off
logic [$bits(slot_t)-1:0] wqs [4];      // SAME_SEARCH 0: the simulation's copy
// synthesis translate_on
slot_t sd [4];

genvar w;
// (declared before their use: Vivado 2018.3 makes a separate implicit net of a
// signal an instance is connected to ahead of its declaration)
logic [1:0] wway;
generate
	for (w = 0; w < 4; w++) begin : g_way
		logic [SW-1:0] q, wq;
		ap68040_lutram #(.AW(4), .DW(SW)) ram (
			.clk(clk), .we(wr && wway == 2'(w)), .waddr(wset),
			.wdata({wfc2, wla[31:12], went}), .raddr(lset), .q(q)
		);
		if (SAME_SEARCH) begin : g_ws
			ap68040_lutram #(.AW(4), .DW(SW)) ram_w (
				.clk(clk), .we(wr && wway == 2'(w)), .waddr(wset),
				.wdata({wfc2, wla[31:12], went}), .raddr(wset), .q(wq)
			);
		end
		else begin : g_nows
			assign wq = '0;
			// synthesis translate_off
			// (the copy, in simulation only: an install that finds its page
			// already there would duplicate it)
			ap68040_lutram #(.AW(4), .DW(SW)) ram_ws (
				.clk(clk), .we(wr && wway == 2'(w)), .waddr(wset),
				.wdata({wfc2, wla[31:12], went}), .raddr(wset), .q(wqs[w])
			);
			// synthesis translate_on
		end
		logic [SW-1:0] dq;
		ap68040_lutram #(.AW(4), .DW(SW)) ram_d (
			.clk(clk), .we(wr && wway == 2'(w)), .waddr(wset),
			.wdata({wfc2, wla[31:12], went}), .raddr(set_d), .q(dq)
		);
		assign s[w]  = q;
		assign ws[w] = wq;
		assign sd[w] = dq;
	end
endgenerate

function automatic logic tag_eq(input slot_t t, input logic [31:0] a, input logic f2,
                                input logic p8);
	tag_eq = (t.fc2 == f2) && (t.lpn[19:1] == a[31:13]) && (p8 || (t.lpn[0] == a[12]));
endfunction

always_comb for (int i = 0; i < 4; i++) wpa[i] = s[i].e.pa;
always_comb
	for (int i = 0; i < 4; i++) begin
		hv_d[i]  = v[set_d][i] && tag_eq(sd[i], la_d, fc2_d, p8k);
		wpa_d[i] = sd[i].e.pa;
	end
always_comb begin
	for (int i = 0; i < 4; i++) hv[i] = v[lset][i] && tag_eq(s[i], la, fc2, p8k);
	hit = |hv;
	// at most one way holds a page (install reuses its way): AND-OR, no
	// priority chain
	ent = '0;
	for (int i = 0; i < 4; i++) ent = ent | (hv[i] ? s[i].e : '0);
end
// synthesis translate_off
always_ff @(posedge clk)
	if (nreset && !$onehot0(hv)) begin
		$display("FAIL: ATC: more than one way hits (set %0d, ways %b)", lset, hv);
		$finish;
	end
// synthesis translate_on

// install way: the same page if present (an M-bit update), else invalid, else rr
always_comb begin
	logic found;
	found = 1'b0;
	wway  = rr;
	if (SAME_SEARCH) begin
		for (int i = 3; i >= 0; i--)
			if (v[wset][i] && tag_eq(ws[i], wla, wfc2, p8k)) begin wway = 2'(i); found = 1'b1; end
	end
	else if (wsame) begin
		found = 1'b1;
		wway  = wsame_hv[3] ? 2'd3 : wsame_hv[2] ? 2'd2 : wsame_hv[1] ? 2'd1 : 2'd0;
	end
	if (!found) begin
		for (int i = 3; i >= 0; i--) if (!v[wset][i]) wway = 2'(i);
	end
end

// synthesis translate_off
always_ff @(posedge clk)
	if (!SAME_SEARCH && wr)
		for (int i = 0; i < 4; i++)
			if ((v[wset][i] && tag_eq(slot_t'(wqs[i]), wla, wfc2, p8k)) != (wsame && wsame_hv[i])) begin
				$display("FAIL: ATC: install of %h: the page %s way %0d, the caller says %b/%b",
				         wla, (v[wset][i] && tag_eq(slot_t'(wqs[i]), wla, wfc2, p8k)) ? "is in" : "is not in",
				         i, wsame, wsame_hv);
				$finish;
			end
// synthesis translate_on

// ATC entries survive RSTI (MC68040UM 3.6.1): only configuration clears them
initial begin
	for (int i = 0; i < 16; i++) begin v[i] = 4'd0; g[i] = 4'd0; end
	rr = 2'd0;
end

always_ff @(posedge clk) begin
	if (wr) begin
		v[wset][wway] <= 1'b1;
		g[wset][wway] <= went.g;
		if (v[wset] == 4'hF) rr <= rr + 2'd1;
	end
	if (flush_all)
		for (int i = 0; i < 16; i++)
			v[i] <= flush_nonglobal ? (v[i] & g[i]) : 4'd0;
	if (flush_page)
		for (int i = 0; i < 4; i++)
			if (v[lset][i] && tag_eq(s[i], la, fc2, p8k) &&
			    !(flush_nonglobal && g[lset][i]))
				v[lset][i] <= 1'b0;
end

endmodule
// ---- ap68040_backend.sv ----
//--------------------------------------------------------------------------//
// AP68040 - pipelined MC68040                                            //
//                                                                          //
// ap68040_backend.sv - AG, DC1, DC2, EX and WB stages                       //
//                                                                          //
//   AG   read the front register file, effective address, (An)+/-(An)     //
//        and LEA-class register updates (written to the front file)       //
//   DC1  data ATC / cache lookup (ap68040_dmu)                             //
//   DC2  way select and operand alignment (ap68040_dmu)                    //
//   EX   ALU, shifter, multiply/divide, branch resolution, front-file      //
//        result write                                                      //
//   WB   back (architectural) register file, CCR/SR, stores, exceptions,  //
//        interrupts, trace, serialization                                  //
//                                                                          //
// Operand values are read at AG.  A result produced by an older uop in EX  //
// is broadcast and captured by every younger uop in AG/DC1/DC2 whose       //
// operand names that register, so EX never forwards; address operands     //
// (base, index, register updates) instead interlock at AG on any older    //
// uop that will write the register in EX.                                  //
//                                                                          //
// Every redirect (branch mispredict, exception, serialization) happens in  //
// WB, from state registered at the end of EX.                              //
//--------------------------------------------------------------------------//

module ap68040_backend
	import ap68040_pkg::*;
#(
	parameter logic [7:0] FPU_REVISION = 8'h41,   // FSAVE frame revision ($40: 44-byte UNIMP)
	parameter bit         FPU_PIPE  = 1,
	parameter bit         EARLY_RES = 1,
	parameter bit         SKID      = 1,      // the skid register in front of AG
	parameter int         DIV_STEPS = 2,      // divide steps per cycle
	parameter bit         DEBUG     = 0       // the debug outputs' logic (0: they stay at zero and load nothing)
)(
	input  logic        clk,
	input  logic        nreset,

	// uops from the sequencer
	input  logic        in_v,
	input  uop_t        in_u,
	output logic        in_rdy,

	// redirect of the front end (registered)
	output logic        redir_v,
	output logic [31:0] redir_pc,
	output logic        flush,          // kill everything younger than WB
	output logic        fe_flush,       // the front end's flush (D1, D2)
	output logic        ras_rv,         // D1's return stack to restore with it
	output logic  [2:0] ras_rtp,
	output logic  [3:0] ras_rn,

	// exception entry for the sequencer
	output logic        exc_go,         // pulse: run the exception routine
	output logic        exc_pend,       // the entry is being prepared: no uop may issue
	output logic  [3:0] exc_kind,       // routine selector (see EK_*)
	output logic  [4:0] exc_ssp,        // supervisor stack register to use

	// micro-branch result back to the sequencer
	output logic        ucond_v,
	output logic        ucond,

	// architectural state the front end needs
	output logic [15:0] sr,
	output logic [31:0] vbr,
	output logic [31:0] cacr,
	output logic  [2:0] sfc,
	output logic  [2:0] dfc,

	// data memory unit (DC1/DC2 lookups; WB stores)
	output logic        dm_req,         // AG -> DC1: a memory uop advances
	output logic [31:0] dm_va,
	output logic  [1:0] dm_mem,
	output logic  [1:0] dm_msz,
	output logic  [2:0] dm_fc,
	output logic        dm_lock,
	output logic        dm_locke,
	output logic        dm_wi,
	output logic        dm_super,
	output logic        dm_older,       // uops older than DC2 are in EX or WB
	input  logic        sn_ihit,        // a snoop dropped valid instruction-cache data
	input  logic        tw_busy,        // the DMU runs a table search
	output logic        pst_ev,         // PST: an instruction ends this cycle...
	output logic  [3:0] pst_code,       // ...with this encoding (MC68040UM table 5-6)
	output logic  [3:0] pst_st,         // the present status otherwise
	output logic        irq_pending,    // IPEND: a request beats the mask
	output logic        bht_we,         // Bcc history training (decode's table)
	output logic  [7:0] bht_wa,
	output logic        bht_dis,        // ... the branch went against the static rule
	output logic        lp_we,          // loop exit training (decode's table)
	output logic [11:0] lp_wa,
	output logic        lp_tk,
	output logic        lp_mp,
	output logic        dm_noalloc,     // exception stacking / vector fetch
	output logic  [1:0] dm_ack,         // acknowledge cycle: 1 IACK, 2 BKPT
	input  logic        dm_hold1,       // the DMU holds DC1
	// WB maintenance (CINV/CPUSH/PFLUSH/PTEST) in the DMU
	output logic        mt_v,
	output logic  [2:0] mt_op,
	output logic  [1:0] mt_scope,
	output logic  [1:0] mt_caches,
	output logic [31:0] mt_addr,
	output logic  [2:0] mt_fc,
	output logic        mt_ng,
	output logic        mt_wr,
	input  logic        mt_done,
	input  logic [31:0] mt_mmusr,       // PTEST: the MMUSR
	input  logic        mt_fault,       // CPUSH: a push ended in TEA (an access error)
	input  logic [15:0] mt_fssw,
	input  logic [31:0] mt_faddr,
	input  logic [127:0] pb_data,       // the line of a push that ended in TEA (DMU)
	output logic        adv_dc1,        // DC1 -> DC2
	output logic        adv_dc2,        // DC2 -> EX
	output logic        adv_ex,         // EX -> WB
	output logic        adv_wb,         // WB completes
	input  logic        dm_dc2_rdy,     // DC2 memory op has its result
	input  logic [31:0] dm_ldata,       // load data, right aligned
	input  logic [31:0] dm_ldata_al,    // the aligned operand (AG's capture)
	input  logic        dm_ldata_alv,   // ... is the load's data
	input  logic        dm_ldata_job,   // debug: the load data is the DMU job's answer
	input  logic        dm_fault,       // DC2 access fault (with info below)
	input  logic  [7:0] dm_fvec,        // 2 access error, 3 address error
	input  logic [31:0] dm_faddr,
	input  logic [15:0] dm_fssw,        // ... its special status word
	output logic        dm_st_v,        // WB store data valid this cycle
	output logic        rte_cont,       // an RTE continues after a throwaway frame (8.4.2): its
	                                    // refetch is supervisor and not privilege-checked
	output logic [31:0] dm_st_data,
	input  logic        dm_st_rdy,      // store accepted (WB may complete)
	input  logic        dm_st_fault,
	input  logic [15:0] dm_st_fssw,
	input  logic [31:0] dm_st_faddr,

	// interrupts (synchronized level, 0-7)
	input  logic  [2:0] ipl,
	output logic  [2:0] iack_lvl,
	output logic        rsto_req,
	input  logic        rsto_busy,

	output logic        kill_now,       // this cycle: younger uops are discarded
	output logic        lk_abandon,     // an open locked sequence is abandoned
	output logic        adv_ag,         // AG -> DC1
	output logic [31:0] dtt0,
	output logic [31:0] dtt1,
	output logic [31:0] itt0,
	output logic [31:0] itt1,
	output logic [31:0] tc,
	output logic [31:0] urp,
	output logic [31:0] srp,

	// debug
	output logic [31:0] dbg_pc,
	output logic        dbg_retire,
	output logic [15:0] dbg_rinfo,      // with dbg_retire: the committed uop's {exc, exr, first, last, 5'b0}
	output logic        dbg_xgo,        // exception processing starts (one clock)
	output logic  [7:0] dbg_xvec,       // ... its vector
	output logic [31:0] dbg_xpc,        // ... the PC it stacks
	output logic        dbg_hfgo,       // an exception routine's handler fetch leaves EX
	output logic [31:0] dbg_hfld,       // ... its load data
	output logic [31:0] dbg_hfa,        // ... its A operand (the register value)
	output logic  [7:0] dbg_hff,        // ... {A source, the DMU job's answer, 5'd0}
	output logic [31:0] dbg_hfpc,       // ... its PC field
	output logic        halted,
	output logic        fetch_stop      // no new instruction fetches: stopped
                                        // (STOP) or halted
);

// the SR bits the 68040 keeps: T1 T0 S M I2-I0 X N Z V C
localparam logic [15:0] SR_MASK = 16'hF71F;

//--------------------------------------------------------------------------
// exception routine kinds (sequencer entry points)
//--------------------------------------------------------------------------
localparam logic [3:0] EK_FMT0  = 4'd0;   // format $0 (PC = exc_pc)
localparam logic [3:0] EK_FMT2  = 4'd1;   // format $2 / $3 (+ address)
localparam logic [3:0] EK_FMT7  = 4'd2;   // access error
localparam logic [3:0] EK_IRQ   = 4'd3;   // interrupt (IACK + format $0)
localparam logic [3:0] EK_RESET = 4'd4;   // reset: SSP/PC from 0/4
localparam logic [3:0] EK_IRQM  = 4'd5;   // interrupt with M set (throwaway frame)

//--------------------------------------------------------------------------
// pipeline registers
//--------------------------------------------------------------------------
logic        ag_v, dc1_v, dc2_v, ex_v, wb_v;
uop_t        ag_u, dc1_u, dc2_u, ex_u, wb_u;
logic [31:0] ex_npc, wb_npc;  // EX's and WB's next instruction (pc + 2 ilen)

// operand values carried with the uop
logic [31:0] dc1_a, dc1_b, dc1_ea;
// early results: a simple register operation computes its result in AG
// as well (ag_er), carried beside the uop (ee: valid) for the base and
// index of younger uops; EX still produces and writes it as always
logic        dc1_ee, dc2_ee, ex_ee;
logic [31:0] dc1_er, dc2_er, ex_er;
logic        erb, erx;         // agb_q / agx_q hold the youngest writer's early result
logic [31:0] dc2_a, dc2_b, dc2_ea;
logic [31:0] ex_a,  ex_b,  ex_ea,  ex_ld;
logic        ex_ldj;           // (debug) ex_ld was the DMU job's answer
logic        ex_fault;
logic  [7:0] ex_fvec;
logic [31:0] ex_faddr;
logic [15:0] ex_fssw;

// results carried into WB
logic [31:0] wb_res;
logic  [4:0] wb_ccr;          // CCR after this uop
logic  [4:0] wb_ccr_ist;      // CCR before this uop's instruction (its restart's)
logic  [4:0] ccr_ist;         // EX: the CCR at the start of the instruction in EX
logic        wb_dwe;          // result register write (after EX kills)
logic [31:0] wb_upd_val, wb_upd2_val;
logic        wb_redir;        // the uop redirects the front end
logic [31:0] wb_redir_pc;
logic  [7:0] wb_exc;          // exception vector, 0 none
logic        wb_exc_pcv;      // the frame PC is wb_exc_pc (odd change of flow)
logic [31:0] wb_exc_pc;
logic        wb_oddrte;       // RTE to an odd PC: its SR is committed first
logic        wb_exc_fmtv;     // the frame format is wb_exc_fmt (FPU exceptions)
logic  [3:0] wb_exc_fmt;
logic        wb_xcommit;      // the uop's address updates stand (FPU unimp/unsupp)
logic [31:0] wb_exc_addr;
logic [15:0] wb_exc_ssw;      // SSW of an access error
logic        wb_st;           // store at WB
logic [31:0] wb_st_data;
logic [15:0] wb_sr_new;       // SR write
logic        wb_sr_we;

// AG register updates travel with the uop for the back file
logic [31:0] dc1_upd, dc1_upd2, dc2_upd, dc2_upd2, ex_upd, ex_upd2;

//--------------------------------------------------------------------------
// register files
//--------------------------------------------------------------------------
// Register files (ap68040_rf, MLAB): the front file holds the newest
// values (AG address updates, EX results), the back file the architectural
// ones (WB).  fv[r] says the front copy of r is current; a redirect or an
// exception clears fv, so every register reads the back file again -- no
// copy.  Five read ports at AG: base, index, upd2 register, A, B.
logic [31:0] fv;
// an FPU uop may act once it is the oldest in flight -- or when the one at
// WB is an earlier uop of its own instruction that commits: no exception
// (a load's fault is known by now), not the last uop (no instruction
// boundary between them: no interrupt or trace), and not a store (a bus
// error on a store comes after WB)
// (ew_same: ex_u.pc == wb_u.pc, kept as the two load -- the compare
// stays off the FPU's hold, and so the stall chain)
logic ew_same;
logic wb_ok;                  // WB's uop has no exception (wb_exc == 0), registered
wire wb_fpchk = wb_v && !wb_u.last && wb_ok &&
                (wb_u.mem == M_NONE || wb_u.mem == M_LD) &&
                ex_v && ex_u.op == OP_FPU && ew_same;
// FPU interface outputs (ap68040_fpif)
logic        fp_hold, fp_dkill, fp_taken, fp_xnext, fp_xcommit, fp_stkill;
logic [31:0] fp_res, fp_xaddr;
logic  [7:0] fp_xvec;
logic  [3:0] fp_xfmt;
logic  [7:0] fp_mvslots;
logic  [2:0] fp_crslots;
logic  [4:0] fp_svwords, fp_rswords;
logic  [2:0] fwe, bwe;
logic  [1:0] fwe_ag;           // fwe[0..1] without the advance (AG holds an update)
logic  [4:0] fwa [3], bwa [3];
logic [31:0] fwd [3], bwd [3];
logic  [4:0] rra [5];
logic [31:0] frd [5], brd [5], rrd [5];
logic  [4:0] ccr_f, ccr_b;

// special registers (architectural, written at WB)
logic [15:0] sr_r;            // T1 T0 S M 0 I2 I1 I0 (CCR lives in ccr_b)
logic [31:0] vbr_r, cacr_r;
logic  [2:0] sfc_r, dfc_r;
logic [31:0] tc_r, itt0_r, itt1_r, dtt0_r, dtt1_r, mmusr_r, urp_r, srp_r;

// exception information for the exception microroutine
logic [31:0] xi_pc, xi_addr;
logic [15:0] xi_sr, xi_vecw, xi_ssw;
logic [31:0] xi_vaddr, xi_ea, xi_w3a, xi_w3d;
logic        xi_f7;           // the frame is format $7: T5-T7 too
logic  [2:0] xw_ph;           // exception entry: back-file writes of T5-T13 (format $7: T0-T3 too)
logic [127:0] xi_pd;          // format $7: PD0-PD3, a failed push's line (else zero)

assign sr   = {sr_r[15:5], ccr_b};
assign dtt0 = dtt0_r;
assign dtt1 = dtt1_r;
assign itt0 = itt0_r;
assign itt1 = itt1_r;
assign tc   = tc_r;
assign urp  = urp_r;
assign srp  = srp_r;
assign vbr  = vbr_r;
assign cacr = cacr_r;
assign sfc  = sfc_r;
assign dfc  = dfc_r;

//--------------------------------------------------------------------------
// stall / advance (bubbles collapse: a stage moves into an empty one)
//--------------------------------------------------------------------------
logic wb_hold, ex_hold, dc2_hold, ag_hold;
logic stall_wb, stall_ex, stall_dc2, stall_dc1, stall_ag;

// EX holds for a multicycle unit; DC2 for memory; WB for stores/serial ops
logic md_busy;                // multiply/divide running (register)
logic ex_md_start;
// DC2 holds until the data memory unit has its result
assign dc2_hold  = dc2_v && (dc2_u.mem != M_NONE) && (dc2_u.exc == 8'd0) && !dm_dc2_rdy;
assign stall_wb  = wb_v  && wb_hold;
assign stall_ex  = ex_v  && (ex_hold  || stall_wb);
assign stall_dc2 = dc2_v && (dc2_hold || stall_ex);
assign stall_dc1 = dc1_v && (stall_dc2 || dm_hold1);
assign stall_ag  = ag_v  && (ag_hold  || stall_dc1);

assign adv_wb  = wb_v  && !stall_wb;
assign adv_ex  = ex_v  && !stall_ex;
assign adv_dc2 = dc2_v && !stall_dc2;
assign adv_dc1 = dc1_v && !stall_dc1;
assign adv_ag  = ag_v  && !stall_ag;

// AG's input: a skid register in front of it, so the sequencer's pop does
// not wait for the stall chain.  The sequencer may pop whenever the skid is
// empty; a uop it pops that AG cannot take waits in the skid, and AG takes
// the skid's first.  The register file is read, and the forwarding formed,
// for the uop entering AG (ain_u), wherever it comes from.
logic        sk_v;
// (a copy of sk_v for the register file's read addresses alone: sk_v
// selects the whole uop, and its fan-out would delay the reads)
(* preserve *) logic sk_vr;
uop_t        sk_u;
wire         ain_v = sk_v || in_v;
uop_t        ain_u;
assign ain_u   = sk_v ? sk_u : in_u;
// (without the skid the sequencer's pop waits for AG: the stall chain)
assign in_rdy  = (SKID ? !sk_v : !stall_ag) && !flush && !stopped && !eredir_pend && !exc_pend;
// (the back-file writes of the routine's operands take several cycles
// after the flush: the sequencer must not issue from the old stream, which
// the fetch queue still holds, before exc_go)
assign exc_pend = (xw_ph != 3'd0);
wire         ag_take = !stall_ag && !stopped && !halted;   // AG loads ain_u

//--------------------------------------------------------------------------
// AG
//--------------------------------------------------------------------------
// interlock: base, index and update registers must not have an older
// writer in DC1/DC2/EX (their value only exists after EX)
function automatic logic pend_w(input logic [4:0] r);
	pend_w = (dc1_v && dc1_u.d_v && dc1_u.d_reg == r) ||
	         (dc2_v && dc2_u.d_v && dc2_u.d_reg == r) ||
	         (ex_v  && ex_u.d_v  && ex_u.d_reg  == r);
endfunction

// a plain load leaving DC2 hands its data to a base or index waiting in
// AG (cap_b/cap_x: the EX-stage writer is then no longer waited for)
logic cap_b, cap_x;
function automatic logic pend_dc(input logic [4:0] r);
	pend_dc = (dc1_v && dc1_u.d_v && dc1_u.d_reg == r) ||
	          (dc2_v && dc2_u.d_v && dc2_u.d_reg == r);
endfunction
wire ex_wr_b = ex_v && ex_u.d_v && ex_u.d_reg == ag_u.base;
wire ex_wr_x = ex_v && ex_u.d_v && ex_u.d_reg == ag_u.idx;
// the youngest older writer of a register, and whether it is early:
// {found, early, stage (1 DC1, 2 DC2, 3 EX)}
function automatic logic [3:0] yw(input logic [4:0] r);
	if (dc1_v && dc1_u.d_v && dc1_u.d_reg == r)      yw = {1'b1, dc1_ee, 2'd1};
	else if (dc2_v && dc2_u.d_v && dc2_u.d_reg == r) yw = {1'b1, dc2_ee, 2'd2};
	else if (ex_v && ex_u.d_v && ex_u.d_reg == r)    yw = {1'b1, ex_ee,  2'd3};
	else                                             yw = 4'd0;
endfunction
function automatic logic [31:0] ywv(input logic [1:0] st);
	ywv = (st == 2'd1) ? dc1_er : (st == 2'd2) ? dc2_er : ex_er;
endfunction
wire [3:0] yw_b = yw(ag_u.base);
wire [3:0] yw_x = yw(ag_u.idx);
// an early youngest writer: AG waits only until its result is loaded
// EX's result reaches AG's base/index a cycle after it is written, from a
// register (exq_*): stale_b/x mark a base/index loaded before that write
// (it entered AG as EX wrote it, or its writer left EX while AG waited);
// AG waits that cycle and reloads it from exq_val
logic        stale_b, stale_x;
logic [31:0] exq_val;
wire ag_interlock = ag_v && (
	(ag_u.base_v && (yw_b[2] ? !erb : (pend_dc(ag_u.base) || (ex_wr_b && !cap_b) || stale_b))) ||
	(ag_u.idx_v  && (yw_x[2] ? !erx : (pend_dc(ag_u.idx)  || (ex_wr_x && !cap_x) || stale_x))) ||
	// a register AG writes waits for every older writer (else the EX write
	// of the captured load could land after this one)
	(ag_u.upd_v  && pend_w(ag_u.upd_reg)) ||
	(ag_u.upd2_v && pend_w(ag_u.upd2_reg)));

// the load whose data can be handed over: its result is the data itself
// (a long MOVE, MOVEA.W sign-extended, a memory-indirect pointer)
// dc2_capd selects the data; it is marked captured only as the load moves
// to EX (adv_dc2): AG is interlocked while such a load is in DC2 (pend_dc),
// so a value taken before the load advances -- not final yet, perhaps -- is
// replaced when it does; the advance, the end of the stall chain, stays off
// the data multiplexers
wire        dc2_capd = dc2_u.d_v && dc2_u.op == OP_MOV && dc2_u.cond == 4'd0 &&
                       dc2_u.mem == M_LD && dc2_u.a_src == OS_MEM && dc2_u.sz == SZ_L &&
                       dc2_u.exc == 8'd0 && dm_ldata_alv && dc2_v;
// (from the DMU's aligned word, not its general byte gather: a short path;
// a misaligned load reaches AG a cycle later, through EX's write)
wire [31:0] dc2_capv = dc2_u.a_sxw ? {{16{dm_ldata_al[15]}}, dm_ldata_al[15:0]} : dm_ldata_al;

assign ag_hold = ag_interlock;

ap68040_rf #(.NR(5)) rff (.clk(clk), .we(fwe), .wa(fwa), .wd(fwd), .ra(rra), .rd(frd));
ap68040_rf #(.NR(5), .NW(2)) rfb (.clk(clk), .we(bwe), .wa(bwa), .wd(bwd), .ra(rra), .rd(brd));
// AG's base and index are read as the uop enters AG (ports 0/1 address
// the incoming uop) and kept in registers, so AG's address adders, and the
// data cache's set index after them, start from flip-flops
assign rra[0] = sk_vr ? sk_u.base : in_u.base;   // (= ain_u's)
assign rra[1] = sk_vr ? sk_u.idx  : in_u.idx;
// synthesis translate_off
always_ff @(posedge clk)
	if (nreset && wb_commit && wb_dwe && wb_u.upd2_v) begin
		$display("FAIL: a uop with both a register result and upd2 (pc %h): the back file has two write ports", wb_u.pc);
		$finish;
	end
always_ff @(posedge clk)
	if (nreset && sk_vr != sk_v) begin
		$display("FAIL: the skid's copy sk_vr %b differs from sk_v %b", sk_vr, sk_v);
		$finish;
	end
// synthesis translate_on
assign rra[2] = ag_u.upd2_reg;
assign rra[3] = ag_u.a_reg;
assign rra[4] = ag_u.b_reg;
always_comb for (int i = 0; i < 5; i++) rrd[i] = fv[rra[i]] ? frd[i] : brd[i];

logic [31:0] agb_q, agx_q;     // the base, and the index sign-extended and scaled
wire  [31:0] ag_base = agb_q;
wire  [31:0] ag_ix   = agx_q;
function automatic logic [31:0] ixf(input logic [31:0] v, input uop_t u);
	ixf = u.idx_v ? ((u.idx_l ? v : {{16{v[15]}}, v[15:0]}) << u.scale) : 32'd0;
endfunction
wire [31:0] ag_ea   = ag_base + ag_ix + ag_u.disp;
wire [31:0] ag_pinc = ag_base + {{24{ag_u.upd_amt[7]}}, ag_u.upd_amt};
wire [31:0] ag_updv = ag_u.pinc ? ag_pinc : ag_ea;
wire [31:0] ag_u2v  = rrd[2] + {{24{ag_u.upd2_amt[7]}}, ag_u.upd2_amt};
// bit field memory transfers sized by the field (see ucode.py _bf_mem_load)
wire        ag_bfh    = (ag_u.mem != M_NONE) && (ag_u.op == OP_MOV) && (ag_u.cond == 4'hE);
wire        ag_bft    = (ag_u.mem != M_NONE) && (ag_u.op == OP_MOV) && (ag_u.cond == 4'hD);
wire        ag_rte7   = (ag_u.mem != M_NONE) && (ag_u.op == OP_MOV) && (ag_u.cond == 4'hB);
// FPU transfers cancelled by run-time state: FMOVEM slots, FSAVE and
// FRESTORE frame words (dyn; the FPU interface latched the state in EX
// before these uops' addresses could be formed)
wire        ag_dyncan = (ag_u.dyn == 3'd1 && !fp_mvslots[ag_u.dynk[2:0]]) ||
                        (ag_u.dyn == 3'd2 && ag_u.dynk >= fp_svwords) ||
                        (ag_u.dyn == 3'd3 && ag_u.dynk >= fp_rswords);
wire        ag_cancel = (ag_bft && !(bf_nb == 3'd3 || bf_nb == 3'd5)) ||
                        (ag_rte7 && !rte_fmt7) || ag_dyncan;
// a continued MOVEM transfers from the stacked EA
logic       cm_hit_q;          // ag_u.pc == cm_pc, registered
wire        ag_cm     = cm_pend && cm_hit_q && (ag_u.mem != M_NONE) &&
                        (ag_u.op == OP_MOV) && (ag_u.cond == 4'hC);
wire  [1:0] ag_msz    = ag_bfh ? ((bf_nb == 3'd1) ? SZ_B : (bf_nb <= 3'd3) ? SZ_W : SZ_L)
                               : ag_u.msz;
// the memory address: the cases are folded into the adder's operands
// (their selects are registers), so nothing follows the sum on its way
// to the data cache's set index
wire [31:0] ag_mbase  = ag_cm ? cm_ea : ag_base;
wire [31:0] ag_mix    = ag_cm ? 32'd0 : ag_ix;
wire [31:0] ag_mdisp  = ag_cm ? ag_u.target :
                        (ag_bft && bf_nb == 3'd3) ? ag_u.disp - 32'd2 : ag_u.disp;
wire [31:0] ag_maddr  = ag_mbase + ag_mix + ag_mdisp;

// operand read with the EX broadcast of this cycle (see the snoop below)
logic        exw_v;           // EX writes the front file this cycle
logic  [4:0] exw_reg;
logic [31:0] exw_val;

function automatic logic [31:0] opnd(input logic [1:0] src, input logic [4:0] r,
                                     input logic [31:0] rv,
                                     input logic [31:0] imm, input logic sxw);
	logic [31:0] v;
	case (src)
		OS_REG:  v = (exw_v && exw_reg == r) ? exw_val : rv;
		OS_IMM:  v = imm;
		default: v = 32'd0;
	endcase
	opnd = v;
endfunction

wire [31:0] ag_a = ag_u.a_upd ? ag_updv : opnd(ag_u.a_src, ag_u.a_reg, rrd[3], ag_u.imm, ag_u.a_sxw);
wire [31:0] ag_immb = {{15{ag_u.imm_b[16]}}, ag_u.imm_b};   // the B immediate extended
wire [31:0] ag_b = ag_u.b_upd ? ag_updv : opnd(ag_u.b_src, ag_u.b_reg, rrd[4], ag_immb, 1'b0);

// AG's early result: MOVE, ADD, SUB, AND, OR, EOR and LSL/ASL by an
// immediate count, from register or immediate operands whose values are
// known here (no older writer still to produce one, or an early one).
// The same function as EX (ap68040_alu, ap68040_alu_slow): checked in
// simulation against what EX writes.
function automatic logic e_op(input uop_t u);
	e_op = u.d_v && (u.mem == M_NONE) && (u.br == BR_NONE) && (u.exc == 8'd0) &&
	       (u.cond == 4'd0) && !u.a_sxw && !u.a_upd && !u.b_upd && !u.upd_v &&
	       !u.upd2_v && (u.dyn == 3'd0) && !u.ser &&
	       (u.a_src != OS_MEM) && (u.b_src != OS_MEM) &&
	       ((u.op == OP_MOV) || (u.op == OP_ADD) || (u.op == OP_SUB) ||
	        (u.op == OP_AND) || (u.op == OP_OR) || (u.op == OP_EOR) ||
	        (((u.op == OP_LSL) || (u.op == OP_ASL)) && (u.a_src == OS_IMM) &&
	         (u.imm[31:4] == 28'd0) && (u.imm[3:0] <= 4'd8)));
endfunction
logic        ea_ok, eb_ok, ag_ee;
logic [31:0] ea_v, eb_v, ag_er;
always_comb begin
	logic [3:0]  w;
	logic [31:0] m, r;
	// (the register file read, not EX's broadcast of this cycle: a
	// writer still in EX that is not early leaves the operand unknown)
	ea_v  = (ag_u.a_src == OS_REG) ? rrd[3] : (ag_u.a_src == OS_IMM) ? ag_u.imm : 32'd0;
	ea_ok = 1'b1;
	if (ag_u.a_src == OS_REG) begin
		w = yw(ag_u.a_reg);
		if (w[3]) begin
			if (w[2]) ea_v = ywv(w[1:0]);
			else ea_ok = 1'b0;
		end
	end
	eb_v  = (ag_u.b_src == OS_REG) ? rrd[4] : (ag_u.b_src == OS_IMM) ? ag_immb : 32'd0;
	eb_ok = 1'b1;
	if (ag_u.b_src == OS_REG) begin
		w = yw(ag_u.b_reg);
		if (w[3]) begin
			if (w[2]) eb_v = ywv(w[1:0]);
			else eb_ok = 1'b0;
		end
	end
	ag_ee = EARLY_RES && ag_v && e_op(ag_u) && ea_ok && eb_ok;
	m  = (ag_u.sz == SZ_B) ? 32'h0000_00FF : (ag_u.sz == SZ_W) ? 32'h0000_FFFF : 32'hFFFF_FFFF;
	// (the size mask applies to the result only: the low bits of each of
	// these depend on the operands' low bits alone)
	case (ag_u.op)
		OP_MOV:  r = ea_v;
		OP_ADD:  r = eb_v + ea_v;
		OP_SUB:  r = eb_v - ea_v;
		OP_AND:  r = eb_v & ea_v;
		OP_OR:   r = eb_v | ea_v;
		OP_EOR:  r = eb_v ^ ea_v;
		default: r = eb_v << ea_v[3:0];               // LSL, ASL
	endcase
	ag_er = (r & m) | (eb_v & ~m);
end

// A snoop dropped instruction-cache data the front end may already have
// run ahead into (it predicts calls and returns, beyond the 68040's
// prefetch): the next instruction to reach AG is refetched, with it
// everything younger.  Instructions already past AG are in execution.
// An exception routine's uops are not instructions (their pc is 0): the
// refetch waits for the handler's first instruction, which the routine's
// final jump fetches afresh anyway.
logic snp_pend;
wire  ag_snref = snp_pend && ag_v && ag_u.first && !ag_u.exr;
always_ff @(posedge clk) begin
	if (!nreset || flush) snp_pend <= 1'b0;
	else if (sn_ihit) snp_pend <= 1'b1;
	else if (adv_ag && ag_snref) snp_pend <= 1'b0;
end

// memory request to the DMU, issued as the uop leaves AG
logic s_bit;
assign s_bit      = sr_r[13];
assign dm_req     = adv_ag && (ag_u.mem != M_NONE) && (ag_u.exc == 8'd0) && !ag_cancel && !ag_snref;
assign dm_va      = ag_maddr;
assign dm_mem     = ag_u.mem;
assign dm_msz     = ag_msz;
assign dm_lock    = ag_u.mlock;
assign dm_locke   = ag_u.mlocke;
assign dm_wi      = ag_u.mwi;
// FC2 of the access selects the root and the supervisor checks: MOVES
// translates its SFC/DFC space (WinUAE: super = (sfc & 4) != 0)
assign dm_super   = dm_fc[2];
assign dm_older   = ex_v || wb_v;



// Bcc history: the counter counts disagreement with the static rule
// (saturating 0..3); trained as the branch leaves EX, written a cycle
// later unless that cycle flushes (the branch was on a wrong path: an
// older uop at WB redirected or trapped as it left EX)
wire        bht_agree = (ex_taken == ex_u.bst);
logic       bht_we_q;
always_ff @(posedge clk) begin
	bht_we_q <= nreset && adv_ex && ex_u.op == OP_BCC && ex_u.br == BR_COND;
	bht_wa   <= ex_u.pc[8:1];
	bht_dis  <= !bht_agree;
end
assign bht_we = bht_we_q && !flush;
// loop exits: every backward Bcc/DBcc, the same way
logic       lp_we_q;
always_ff @(posedge clk) begin
	lp_we_q <= nreset && adv_ex && ex_u.bst &&
	           ((ex_u.op == OP_BCC && ex_u.br == BR_COND) || ex_u.op == OP_DBCC);
	lp_wa   <= ex_u.pc[12:1];
	lp_tk   <= ex_taken;
	lp_mp   <= ex_mispred;
end
assign lp_we = lp_we_q && !flush;
assign dm_noalloc = (ag_u.mfc == MFC_SUP);
// acknowledge cycles (TT=3): 1 interrupt, 2 breakpoint
assign dm_ack     = (ag_u.mfc == MFC_IACK) ? 2'd1 : (ag_u.mfc == MFC_BKPT) ? 2'd2 : 2'd0;
always_comb begin
	case (ag_u.mfc)
		MFC_SFC: dm_fc = sfc_r;
		MFC_DFC: dm_fc = dfc_r;
		MFC_SUP: dm_fc = 3'd5;
		MFC_IACK: dm_fc = 3'd7;
		default: dm_fc = ag_u.mprog ? {s_bit, 2'b10} : {s_bit, 2'b01};
	endcase
end

//--------------------------------------------------------------------------
// EX
//--------------------------------------------------------------------------
// operand values entering EX: A or B may be the load data
wire [31:0] ex_av0 = (ex_u.a_src == OS_MEM) ? ex_ld : ex_a;
wire [31:0] ex_av  = ex_u.a_sxw ? {{16{ex_av0[15]}}, ex_av0[15:0]} : ex_av0;
wire [31:0] ex_bv  = (ex_u.b_src == OS_MEM) ? ex_ld : ex_b;

logic [31:0] alu_res;
logic  [4:0] alu_flags;
logic        alu_cc, alu_trap;

ap68040_alu alu (
	.op(ex_u.op), .sz(ex_u.sz), .cond(ex_u.cond),
	.a(ex_av), .b(ex_bv), .ea(ex_ea),
	.flags_in(ccr_f),
	.res(alu_res), .flags_out(alu_flags),
	.cc_true(alu_cc), .trap(alu_trap)
);

// multiply / divide
logic        md_done, md_ovf;
logic [31:0] md_hi, md_lo;
logic [31:0] md_hiin;         // OP_MDHI latch (64-bit dividend high)
logic [31:0] md_rem;          // remainder / product high, for OP_MDRES
logic [31:0] md_lol;          // quotient / product low, for OP_MDRES
logic        md_ovfl;         // the last divide overflowed
logic        md_go;           // this EX uop has started the unit
logic        md_fin;          // ... and the unit has finished (done is a pulse: EX may
                              // be stalled by WB in that cycle)
logic        md_z;            // ... is a divide by zero (from its second cycle)
wire         ex_is_md   = (ex_u.op == OP_MUL) || (ex_u.op == OP_DIV);
wire         ex_div0    = (ex_u.op == OP_DIV) &&
                          ((ex_u.sz == SZ_W) ? (ex_av[15:0] == 16'd0) : (ex_av == 32'd0));
assign ex_md_start = ex_v && ex_is_md && !md_go && !ex_div0 && !md_busy && !ex_fault;

// word forms: DIVU.W/DIVS.W divide the 32-bit Dn by a 16-bit source;
// MULU.W/MULS.W multiply the low words
wire        md_sign = ex_u.cond[0];
wire [31:0] md_a    = (ex_u.sz == SZ_W) ?
                      (md_sign ? {{16{ex_av[15]}}, ex_av[15:0]} : {16'd0, ex_av[15:0]}) : ex_av;
wire [31:0] md_blo  = (ex_u.op == OP_MUL && ex_u.sz == SZ_W) ?
                      (md_sign ? {{16{ex_bv[15]}}, ex_bv[15:0]} : {16'd0, ex_bv[15:0]}) : ex_bv;
wire [31:0] md_bhi  = (ex_u.op == OP_DIV) ?
                      ((ex_u.cond[1]) ? md_hiin : (md_sign ? {32{ex_bv[31]}} : 32'd0)) : 32'd0;

ap68040_muldiv #(.DSTEPS(DIV_STEPS)) md (
	.clk(clk), .nreset(nreset), .kill(kill_now),
	.start(ex_md_start), .is_div(ex_u.op == OP_DIV), .sign_op(md_sign),
	.op_a(md_a), .op_hi(md_bhi), .op_lo(md_blo),
	.busy(md_busy), .done(md_done), .res_hi(md_hi), .res_lo(md_lo), .ovf(md_ovf)
);

// FPU: OP_FPU uops act once no older uop is in flight (WB empty)
wire         ex_is_fp = (ex_u.op == OP_FPU);
// (declared before their use: Vivado 2018.3 makes a separate implicit net of a
// signal an instance is connected to ahead of its declaration)
logic [31:0] ex_latch;
ap68040_fpif #(.FPU_REVISION(FPU_REVISION), .FPU_PIPE(FPU_PIPE)) fpif (
	.clk(clk), .nreset(nreset),
	.ex_v(ex_v && ex_is_fp && !ex_fault && ex_u.exc == 8'd0), .sub(ex_u.cond),
	.fuse(ex_u.sz == SZ_W), .eal(ex_u.sz == SZ_B),
	.imm(ex_u.imm[7:0]), .immb(ex_u.imm_b[7:0]),
	.av(ex_av), .bv(ex_bv), .aw(ex_a[15:0]), .bw(ex_b[15:0]),
	.dw_a(dc2_a[15:0]), .dw_b(dc2_b[15:0]), .dw_ld(!stall_ex), .latch(ex_latch), .ea(ex_ea), .pc(ex_u.pc),
	.safe(!wb_v || wb_fpchk), .adv(adv_ex), .kill(kill_now),
	.hold(fp_hold), .res(fp_res), .dkill(fp_dkill), .taken(fp_taken),
	.xvec(fp_xvec), .xfmt(fp_xfmt), .xnext(fp_xnext), .xaddr(fp_xaddr),
	.xcommit(fp_xcommit), .st_kill(fp_stkill),
	.mv_slots(fp_mvslots), .cr_slots(fp_crslots),
	.sv_words(fp_svwords), .rs_words(fp_rswords)
);

// EX holds while the unit runs, until the cycle its result is presented
// (a divide by zero holds its first cycle too: the zero test of the
// operand stays off the stall path, and the exception goes a cycle later)
assign ex_hold = (ex_v && ex_is_md && !md_z && !ex_fault && !md_done && !md_fin) ||
                 (ex_v && ex_slow && !ex_ph) ||
                 (ex_v && ex_is_fp && !ex_fault && ex_u.exc == 8'd0 && fp_hold);

// multiply/divide result and flags
logic [31:0] md_res;
logic  [4:0] md_flags;
logic        md_dkill;
always_comb begin
	md_res   = ex_bv;
	md_flags = ccr_f;
	md_dkill = 1'b0;
	if (ex_u.op == OP_MUL) begin
		if (ex_u.sz == SZ_W || !ex_u.cond[1]) begin
			// 32-bit product (MULx.W is 16x16 -> 32)
			md_res   = md_lo;
			md_flags = {ccr_f[4], md_lo[31], md_lo == 32'd0,
			            (ex_u.sz == SZ_L) &&
			            (md_sign ? (md_hi != {32{md_lo[31]}}) : (md_hi != 32'd0)),
			            1'b0};
		end
		else begin
			// 64-bit: this uop writes Dl; OP_MDRES writes Dh
			md_res   = md_lo;
			md_flags = {ccr_f[4], md_hi[31], {md_hi, md_lo} == 64'd0, 1'b0, 1'b0};
		end
	end
	else begin
		// divide
		if (ex_u.sz == SZ_W) begin
			// quotient must fit 16 bits
			logic ovf16;
			ovf16 = md_ovf ||
			        (md_sign ? (md_lo[31:15] != {17{md_lo[15]}}) : (md_lo[31:16] != 16'd0));
			if (ovf16) begin
				md_dkill = 1'b1;
				md_flags = {ccr_f[4], ccr_f[3], ccr_f[2], 1'b1, 1'b0};
			end
			else begin
				md_res   = {md_hi[15:0], md_lo[15:0]};
				md_flags = {ccr_f[4], md_lo[15], md_lo[15:0] == 16'd0, 1'b0, 1'b0};
			end
		end
		else begin
			if (md_ovf) begin
				md_dkill = 1'b1;
				md_flags = {ccr_f[4], ccr_f[3], ccr_f[2], 1'b1, 1'b0};
			end
			else begin
				md_res   = md_lo;
				md_flags = {ccr_f[4], md_lo[31], md_lo == 32'd0, 1'b0, 1'b0};
			end
		end
	end
end

// latch for CAS / bit fields

//--------------------------------------------------------------------------
// bit field unit.  BFSET latched the offset (bf_off) and width (bf_w,
// 1..32).  Register form (cond[3] = 0): the field is in B, numbered from
// bit 31, wrapping.  Memory form: B is the long word at EA + offset/8 and
// ex_latch[7:0] the byte after it; the field starts offset & 7 bits in.
// A is the BFINS source.  Flags come from the field, for BFINS from the
// inserted value.
//--------------------------------------------------------------------------
logic [31:0] bf_off;
logic  [5:0] bf_w;
// derived from the width when BFSET latches it (off the EX paths): 32 - width,
// the field mask at the top, BFEXTS's sign mask
logic  [5:0] bf_wn;
logic [31:0] bf_top, bf_sx;
logic  [2:0] bf_nb;             // memory form: bytes holding the field (1..5)

// MOVEM continuation (MC68040UM 8.4.6.5, SSW CM)
logic        rte_fmt7;          // the RTE's frame is format $7
logic        cm_n_v;            // ... and its SSW has CM set
logic [31:0] cm_n_ea;           // ... its EA
logic        cm_pend;           // the next instruction continues a MOVEM
logic [31:0] cm_ea, cm_pc;
logic [31:0] wb_mv_ea;          // the WB MOVEM transfer's calculated EA

// leading zero count of a nonzero 32-bit value, as a balanced tree
function automatic logic [4:0] clz32(input logic [31:0] v);
	logic [4:0] n;
	logic [31:0] x;
	x = v;
	n[4] = (x[31:16] == 16'd0); if (n[4]) x = {x[15:0], 16'd0};
	n[3] = (x[31:24] == 8'd0);  if (n[3]) x = {x[23:0], 8'd0};
	n[2] = (x[31:28] == 4'd0);  if (n[2]) x = {x[27:0], 4'd0};
	n[1] = (x[31:30] == 2'd0);  if (n[1]) x = {x[29:0], 2'd0};
	n[0] = !x[31];
	clz32 = n;
endfunction
logic  [7:0] bf_lonew;          // memory form: the new byte after the long
logic [31:0] bf_res;
logic  [7:0] bf_lo_out;
// BFINS takes a cycle more: its source left-aligned to the field width
// (ins_top) is registered first (bf_ins_q, in ex_pb's cycle), so the field
// merge starts from flip-flops -- three variable shifts in a row do not
// close at 60 MHz without register retiming
// Every bit field operation takes that cycle: the rotated operand is
// registered (bf_rot_q), and the extraction, flags and merge start from it
// (a rotate and a second variable shift in one cycle do not close at 65 MHz)
logic        ex_pb;
logic [31:0] bf_ins_q, bf_rot, bf_rot_q;
logic [31:0] bf_rr;             // the shared right rotator's output (below)
logic  [5:0] rox_nx, rox_nx_q;  // ROXL/ROXR: their count mod (size + 1), the same way
logic  [6:0] rox_nxl, rox_nxl_q; // ROXL: its funnel amount, the same way (from the registered count)
wire         ex_pre = (ex_u.op == OP_BF) || (ex_u.op == OP_ROXL) || (ex_u.op == OP_ROXR);
wire         ex_bfins = (ex_u.op == OP_BF) && (ex_u.cond[2:0] == 3'd7);
logic  [4:0] bf_flags;
always_comb begin
	logic [4:0]  o;
	logic [31:0] top, rot, fld, ins_top, nrot, nrot_v, nreg, zf;
	logic [39:0] win, mask40, ins40, nwin;
	logic [5:0]  lz;
	logic        nflag, zflag;
	logic [2:0]  t;
	t   = ex_u.cond[2:0];
	top = bf_top;
	ins_top = bf_ins_q;
	if (!ex_u.cond[3]) begin
		o   = bf_off[4:0];
		// rotate left by o: a funnel of B with itself
		rot = 32'(({ex_bv, ex_bv} << o) >> 32);
		win = '0; mask40 = '0; ins40 = '0;
	end
	else begin
		o   = {2'b00, bf_off[2:0]};
		// the bytes read, left justified: B holds the head transfer (byte,
		// word or long), the latch the tail byte
		case (bf_nb)
			3'd1:    win = {ex_bv[7:0], 32'd0};
			3'd2:    win = {ex_bv[15:0], 24'd0};
			3'd3:    win = {ex_bv[15:0], ex_latch[7:0], 16'd0};
			3'd4:    win = {ex_bv, 8'd0};
			default: win = {ex_bv, ex_latch[7:0]};
		endcase
		rot = 32'((win << o) >> 8);
		mask40 = {top, 8'h00} >> o;
		ins40  = {ins_top, 8'h00} >> o;
	end
	bf_rot = rot;
	rot    = bf_rot_q;
	case (t)
		3'd2: nrot_v = rot ^ top;                     // BFCHG
		3'd4: nrot_v = rot & ~top;                    // BFCLR
		3'd6: nrot_v = rot | top;                     // BFSET
		default: nrot_v = (rot & ~top) | (ins_top & top);   // BFINS
	endcase
	// One right rotator for three shifts that never run in the same cycle:
	// the pre-cycle's BFINS source (ex_av << (32 - w): rotated right by w,
	// masked to the field's top bits), and in the main cycle the extracted
	// field (rot >> (32 - w): rotated right by 32 - w, masked to the low w
	// bits) or the register's merged value rotated back (nreg, by the offset)
	begin
		logic [31:0] ri;
		logic  [4:0] ra;
		logic        ext;
		ext = (t == 3'd1) || (t == 3'd3);
		ri  = !ex_pb ? ex_av : ext ? rot : nrot_v;
		ra  = !ex_pb ? bf_w[4:0] : ext ? bf_wn[4:0] : o;
		bf_rr = 32'({ri, ri} >> ra);
	end
	fld = bf_rr & ~bf_sx;
	nrot = nrot_v;
	nreg = bf_rr;
	case (t)
		3'd2: nwin = win ^ mask40;
		3'd4: nwin = win & ~mask40;
		3'd6: nwin = win | mask40;
		default: nwin = (win & ~mask40) | (ins40 & mask40);
	endcase
	// leading zeros of the field (FFO): a log-depth count over the top-
	// aligned field; a zero field gives the width
	zf = rot & top;
	lz = (zf == 32'd0) ? bf_w : {1'b0, clz32(zf)};
	if (t == 3'd7) begin
		nflag = ins_top[31];
		zflag = (ins_top & top) == 32'd0;
	end
	else begin
		nflag = rot[31];
		zflag = zf == 32'd0;
	end
	bf_flags = {ccr_f[4], nflag, zflag, 1'b0, 1'b0};
	// the bytes written back: the head right justified, the tail byte
	bf_lo_out = (bf_nb == 3'd3) ? nwin[23:16] : nwin[7:0];
	case (t)
		3'd1: bf_res = fld;                                            // BFEXTU
		3'd3: bf_res = fld | (rot[31] ? bf_sx : 32'd0);                  // BFEXTS
		3'd5: bf_res = bf_off + {26'd0, lz};                           // BFFFO
		3'd0: bf_res = ex_bv;                                          // BFTST
		default: bf_res = !ex_u.cond[3] ? nreg :
		                  (bf_nb == 3'd1) ? {24'd0, nwin[39:32]} :
		                  (bf_nb == 3'd2 || bf_nb == 3'd3) ? {16'd0, nwin[39:24]} :
		                  nwin[39:8];
	endcase
end


//--------------------------------------------------------------------------
// EX result selection
//--------------------------------------------------------------------------
logic [31:0] ex_res;
logic  [4:0] ex_flags;
logic        ex_dkill;        // suppress the register write
logic  [5:0] ex_kc;           // EX's uop is FPU, DIV, MDRES, DBcc, CHK2B, CAS2R (the ones that can)
logic        ex_dkill_chk;    // (simulation: the case form)
// synthesis translate_off
always_ff @(posedge clk)
	if (nreset && ex_v && ex_u.d_v && (!ex_slow || ex_ph) && ex_dkill != ex_dkill_chk) begin
		$display("FAIL: ex_dkill %b, the case form %b (op %0d, pc %h)", ex_dkill, ex_dkill_chk, ex_u.op, ex_u.pc);
		$finish;
	end
// synthesis translate_on
logic        ex_taken;        // control transfer taken
logic [31:0] ex_target;
logic  [7:0] ex_xvec;         // exception raised in EX
logic [31:0] ex_st;           // store data
logic        ex_sr_we;
logic [15:0] ex_sr_new;

// special register read: the MOVEC numbers as {ext[11], ext[3:0]}
// ($000-$007 -> $00-$07, $800-$807 -> $10-$17; USP, MSP and ISP live in
// the register file), then SR and CCR
function automatic logic [31:0] spr_read(input logic [7:0] n);
	case (n)
		8'h00: spr_read = {29'd0, sfc_r};
		8'h01: spr_read = {29'd0, dfc_r};
		8'h02: spr_read = cacr_r;
		8'h03: spr_read = tc_r;
		8'h04: spr_read = itt0_r;
		8'h05: spr_read = itt1_r;
		8'h06: spr_read = dtt0_r;
		8'h07: spr_read = dtt1_r;
		8'h11: spr_read = vbr_r;
		8'h15: spr_read = mmusr_r;
		8'h16: spr_read = urp_r;
		8'h17: spr_read = srp_r;
		8'h20: spr_read = {16'd0, sr_r[15:5], ccr_f};     // SR
		8'h21: spr_read = {27'd0, ccr_f};                   // CCR
		default: spr_read = 32'd0;
	endcase
endfunction

// slow (two-cycle) operations: computed in EX's first cycle, registered,
// used in the second, so their logic never reaches the result path
function automatic logic is_slow(input logic [6:0] op);
	case (op)
		OP_ASL, OP_ASR, OP_LSL, OP_LSR, OP_ROL, OP_ROR, OP_ROXL, OP_ROXR,
		OP_ABCD, OP_SBCD, OP_NBCD, OP_PACK, OP_UNPK, OP_BF, OP_CHK2B,
		OP_SPR, OP_SRLOG, OP_RTE, OP_RTEF, OP_IACKV, OP_MISC: is_slow = 1'b1;
		default: is_slow = 1'b0;
	endcase
endfunction

typedef struct packed {
	logic [31:0] res;
	logic  [4:0] flags;
	logic        dkill;
	logic        taken;
	logic [31:0] target;
	logic  [7:0] xvec;
	logic        sr_we;
	logic [15:0] sr_new;
} exo_t;

wire  ex_slow = is_slow(ex_u.op);
// shifts and rotates: N and Z are the result's sign and zero test at the
// size, taken in the second cycle from the registered result (the barrel
// shift and a 32-bit zero test do not fit one cycle with the count logic)
wire  ex_shift = (ex_u.op == OP_ASL) || (ex_u.op == OP_ASR) || (ex_u.op == OP_LSL) ||
                 (ex_u.op == OP_LSR) || (ex_u.op == OP_ROL) || (ex_u.op == OP_ROR) ||
                 (ex_u.op == OP_ROXL) || (ex_u.op == OP_ROXR);
logic ex_ph;                    // second cycle of a slow op
// the shift's kind for the slow unit, one-hot, registered with ex_u
function automatic logic [7:0] shk_of(input logic [6:0] o);
	shk_of = {o == OP_ROXR, o == OP_ROXL, o == OP_ROR, o == OP_ROL,
	          o == OP_LSR, o == OP_ASR, o == OP_LSL, o == OP_ASL};
endfunction
logic [7:0] ex_shk;
// synthesis translate_off
always_ff @(posedge clk)
	if (nreset && ex_v && ex_shk != shk_of(ex_u.op)) begin
		$display("FAIL: the registered shift kind %b, the op's %b", ex_shk, shk_of(ex_u.op));
		$finish;
	end
// synthesis translate_on
exo_t xf, xs, xs_q;

logic [31:0] sl_res;
logic  [4:0] sl_flags;
logic        sl_sim_c;
ap68040_alu_slow alu_s (
	.op(ex_u.op), .shk(ex_shk), .sz(ex_u.sz), .a(ex_av), .b(ex_bv), .cnt(ex_a[5:0]), .flags_in(ccr_f),
	.nx_q(rox_nx_q), .nx(rox_nx), .nxl_q(rox_nxl_q), .nxl(rox_nxl),
	.res(sl_res), .flags_out(sl_flags), .sim_c(sl_sim_c)
);
// synthesis translate_off
always_ff @(posedge clk)
	if (nreset && ex_v && ex_shift && (!ex_pre || ex_pb) && sl_flags[0] !== sl_sim_c) begin
		$display("FAIL: the shift's direct carry %b, the funnel's %b (op %0d, sz %0d, count %0d, b %h, pc %h)",
		         sl_flags[0], sl_sim_c, ex_u.op, ex_u.sz, ex_a[5:0], ex_bv, ex_u.pc);
		$finish;
	end
// synthesis translate_on
// synthesis translate_off
always_ff @(posedge clk)
	if (nreset && ex_v && wb_v && ew_same != (ex_u.pc == wb_u.pc)) begin
		$display("FAIL: ew_same %b, the EX and WB PCs %h %h", ew_same, ex_u.pc, wb_u.pc);
		$finish;
	end
// synthesis translate_on
// (the shift count is never a memory operand: a count register or a
// constant, so it comes straight from the operand register)
// synthesis translate_off
always_ff @(posedge clk)
	if (ex_v && ex_u.a_src == OS_MEM &&
	    (ex_u.op == OP_ASL || ex_u.op == OP_ASR || ex_u.op == OP_LSL || ex_u.op == OP_LSR ||
	     ex_u.op == OP_ROL || ex_u.op == OP_ROR || ex_u.op == OP_ROXL || ex_u.op == OP_ROXR)) begin
		$display("FAIL: a shift with its count from memory (pc %h)", ex_u.pc);
		$finish;
	end
// synthesis translate_on

// fast operations
always_comb begin
	xf.res    = alu_res;
	xf.flags  = alu_flags;
	xf.dkill  = 1'b0;
	xf.taken  = 1'b0;
	xf.target = ex_u.target;
	xf.xvec   = 8'd0;
	xf.sr_we  = 1'b0;
	xf.sr_new = {sr_r[15:5], alu_flags};
	case (ex_u.op)
		OP_FPU: begin
			xf.res   = fp_res;
			xf.flags = ccr_f;
			xf.dkill = fp_dkill;
			xf.taken = fp_taken;
			xf.xvec  = fp_xvec;
		end
		OP_MUL, OP_DIV: begin
			xf.res   = md_res;
			xf.flags = md_flags;
			xf.dkill = md_dkill;
			if (ex_div0) begin
				xf.xvec  = 8'd5;
				xf.flags = {ccr_f[4:1], 1'b0};
			end
		end
		OP_MDRES: begin
			xf.res   = ex_u.cond[0] ? md_lol : md_rem;
			xf.dkill = md_ovfl;
		end
		OP_MDHI:   xf.res = ex_av;
		OP_BCC:    xf.taken = alu_cc;
		OP_DBCC: begin
			// (the counter before the decrement: Dn.W - 1 == -1 exactly when
			// Dn.W is 0 -- the adder stays off the branch decision)
			xf.taken = !alu_cc && (ex_bv[15:0] != 16'd0);
			xf.dkill = alu_cc;
		end
		OP_TRAPCC: if (alu_trap) xf.xvec = 8'd7;
		OP_CHK:    if (alu_trap) xf.xvec = 8'd6;
		OP_CCRLOG: xf.res = ex_bv;
		OP_SPW:    xf.res = ex_av;
		OP_LATCH:  xf.res = ex_av;
		OP_CAS2C: begin
			if (!ex_u.cond[0] || cas2_eq) xf.flags = cmp_flags;
			else xf.flags = ccr_f;
		end
		OP_CAS2R: begin
			xf.res   = (ex_av & ex_szm) | (ex_bv & ~ex_szm);
			xf.dkill = cas2_eq;
		end
		OP_BFSET:  xf.res = ex_u.cond[0] ? {24'd0, bf_lonew} : {{3{ex_av[31]}}, ex_av[31:3]};
		OP_CAS: begin
			xf.flags = alu_flags;
			xf.res   = ex_bv;
		end
		default: ;
	endcase
	// control transfers
	case (ex_u.br)
		BR_IMM:  begin xf.taken = 1'b1; xf.target = ex_u.target; end
		BR_EA:   begin xf.taken = 1'b1; xf.target = ex_ea; end
		BR_A:    begin xf.taken = 1'b1; xf.target = ex_av; end
		BR_B:    begin xf.taken = 1'b1; xf.target = ex_bv; end
		default: ;
	endcase
end

// slow operations (first EX cycle)
always_comb begin
	xs.res    = sl_res;
	xs.flags  = ex_shift ? {sl_flags[4], 2'b00, sl_flags[1:0]} : sl_flags;
	xs.dkill  = 1'b0;
	xs.taken  = 1'b0;
	xs.target = ex_u.target;
	xs.xvec   = 8'd0;
	xs.sr_we  = 1'b0;
	xs.sr_new = {sr_r[15:5], ccr_f};
	case (ex_u.op)
		OP_CHK2B: begin
			// WinUAE i_CHK2: signed compares of the sign-extended bounds
			// (lower in ex_latch, upper in A) with B, which is sign-extended
			// only when it is a data register (cond[1]); the 68040 leaves N, V
			logic signed [31:0] lo, up, rg;
			logic z, c;
			case (ex_u.sz)
				SZ_B: begin lo = {{24{ex_latch[7]}}, ex_latch[7:0]}; up = {{24{ex_av[7]}}, ex_av[7:0]};
				            rg = ex_u.cond[1] ? {{24{ex_bv[7]}}, ex_bv[7:0]} : ex_bv; end
				SZ_W: begin lo = {{16{ex_latch[15]}}, ex_latch[15:0]}; up = {{16{ex_av[15]}}, ex_av[15:0]};
				            rg = ex_u.cond[1] ? {{16{ex_bv[15]}}, ex_bv[15:0]} : ex_bv; end
				default: begin lo = ex_latch; up = ex_av; rg = ex_bv; end
			endcase
			z = (up == rg) || (lo == rg);
			c = !z && ((lo <= up) ? ((rg < lo) || (rg > up)) : ((rg > up) && (rg < lo)));
			xs.res   = ex_bv;
			xs.dkill = 1'b1;
			xs.flags = {ccr_f[4], ccr_f[3], z, ccr_f[1], c};
			if (ex_u.cond[0] && c) xs.xvec = 8'd6;
		end
		OP_SRLOG: begin
			logic [15:0] cur, n;
			cur = {sr_r[15:5], ccr_f};
			case (ex_u.cond[1:0])
				2'd0:    n = cur & ex_av[15:0];
				2'd1:    n = cur | ex_av[15:0];
				2'd2:    n = cur ^ ex_av[15:0];
				default: n = ex_av[15:0];
			endcase
			xs.sr_new = n & SR_MASK;
			xs.sr_we  = 1'b1;
			xs.flags  = xs.sr_new[4:0];
		end
		OP_SPR: begin
			logic [31:0] v, m;
			v = spr_read(ex_u.imm[7:0]);
			m = (ex_u.sz == SZ_B) ? 32'h0000_00FF : (ex_u.sz == SZ_W) ? 32'h0000_FFFF : 32'hFFFF_FFFF;
			xs.res = (v & m) | (ex_bv & ~m);
			xs.flags = ccr_f;
		end
		OP_MISC: begin
			xs.flags = ccr_f;
			xs.res   = ex_av;              // maintenance: the address
			if (ex_u.cond == 4'd2) begin
				// STOP #imm: SR = imm, then wait for an interrupt
				xs.sr_new = ex_av[15:0] & SR_MASK;
				xs.sr_we  = 1'b1;
				xs.flags  = xs.sr_new[4:0];
			end
			// BKPT: after its acknowledge cycle, the illegal instruction
			// exception (format $0, the BKPT's PC)
			if (ex_u.cond == 4'd9) xs.xvec = 8'd4;
		end
		OP_IACKV: begin
			// IACK data: [7:0] vector, [8] AVEC, [9] TEA (spurious)
			logic [7:0] v;
			xs.flags = ccr_f;
			if (!ex_u.cond[0]) begin
				v = ex_av[9] ? 8'd24 : ex_av[8] ? (8'd24 + {5'd0, irq_lvl_r}) : ex_av[7:0];
				xs.res = {22'd0, v, 2'b00};                 // format $0 word
			end
			else begin
				v = ex_latch[9] ? 8'd24 : ex_latch[8] ? (8'd24 + {5'd0, irq_lvl_r}) : ex_latch[7:0];
				xs.res = vbr_r + {22'd0, v, 2'b00};         // vector address
			end
		end
		OP_RTEF: begin
			// 68040 frame formats: $0 8, $1 8 (throwaway), $2 12, $3 12,
			// $7 60 bytes; others are a format error -- including $4, which
			// "the MC68040 does not generate or recognize" (MC68040UM 8.4.5;
			// only the LC/EC040 use it)
			xs.flags = ccr_f;
			if (ex_u.cond[0]) begin
				// FRESTORE header (FPU in reset state): only a NULL frame
				// (version byte $00) is compatible, anything else is a
				// format error at the FRESTORE
				xs.res = ex_av;
				if (ex_av[31:24] != 8'd0) xs.xvec = 8'd14;
			end
			else case (ex_av[15:12])
				4'h0, 4'h1: xs.res = 32'd8;
				4'h2, 4'h3: xs.res = 32'd12;
				4'h7:       xs.res = 32'd60;
				default: begin xs.res = 32'd0; xs.xvec = 8'd14; end
			endcase
		end
		OP_RTE: begin
			xs.sr_new = ex_av[15:0] & SR_MASK;
			xs.sr_we  = 1'b1;
			xs.flags  = xs.sr_new[4:0];
			xs.taken  = 1'b1;
			xs.target = rte_fmt1 ? ex_u.pc : ex_bv;
		end
		OP_BF: begin
			xs.res   = bf_res;
			xs.flags = bf_flags;
		end
		default: ;
	endcase
end

// EX outputs: the registered slow result in a slow op's second cycle
always_comb begin
	exo_t x;
	x = ex_slow ? xs_q : xf;
	if (ex_slow && ex_shift) begin
		x.flags[3] = (ex_u.sz == SZ_B) ? xs_q.res[7] : (ex_u.sz == SZ_W) ? xs_q.res[15] : xs_q.res[31];
		x.flags[2] = (ex_u.sz == SZ_B) ? (xs_q.res[7:0] == 8'd0) :
		             (ex_u.sz == SZ_W) ? (xs_q.res[15:0] == 16'd0) : (xs_q.res == 32'd0);
	end
	ex_res    = x.res;
	ex_flags  = x.flags;
	// (the uops that can suppress their write, by flags registered as they
	// enter EX, so the kill is an AND-OR of its sources: no op decode on
	// the way to the forwarding enable; the others never kill, slow ones
	// included)
	ex_dkill  = (ex_kc[0] && fp_dkill) || (ex_kc[1] && md_dkill) ||
	            (ex_kc[2] && md_ovfl) || (ex_kc[3] && alu_cc) ||
	            ex_kc[4] || (ex_kc[5] && cas2_eq);
	// synthesis translate_off
	ex_dkill_chk = x.dkill;
	// synthesis translate_on
	ex_taken  = x.taken;
	ex_target = x.target;
	ex_xvec   = x.xvec;
	ex_sr_we  = x.sr_we;
	ex_sr_new = x.sr_new;
end

// CAS: flags of (memory - Dc) and the equal decision
wire [31:0] cas_dc_m = ex_latch;
logic [31:0] cas_res;
logic  [4:0] cas_flags;
logic        cas_cc, cas_tr;
ap68040_alu cas_alu (
	.op(OP_CMP), .sz(ex_u.sz), .cond(4'd0),
	.a(cas_dc_m), .b(ex_bv), .ea(32'd0), .flags_in(ccr_f),
	.res(cas_res), .flags_out(cas_flags), .cc_true(cas_cc), .trap(cas_tr)
);
wire cas_eq = cas_flags[2];

// compare B - A (CAS2)
logic [31:0] cmp_res;
logic  [4:0] cmp_flags;
logic        cmp_cc, cmp_tr;
ap68040_alu cmp_alu (
	.op(OP_CMP), .sz(ex_u.sz), .cond(4'd0),
	.a(ex_av), .b(ex_bv), .ea(32'd0), .flags_in(ccr_f),
	.res(cmp_res), .flags_out(cmp_flags), .cc_true(cmp_cc), .trap(cmp_tr)
);
logic        cas2_eq;           // CAS2: both pairs equal so far
logic        rte_fmt1;          // RTE: the frame is a throwaway ($1)
// (the RTE then goes on with the next frame on the stack the restored SR
// selects -- USP too: the instruction is refetched, and the refetch is
// the same RTE continuing, fetched as supervisor and not checked for
// privilege; no interrupt or trace comes between its frames)
wire  [31:0] ex_szm = (ex_u.sz == SZ_B) ? 32'h0000_00FF :
                      (ex_u.sz == SZ_W) ? 32'h0000_FFFF : 32'hFFFF_FFFF;

// store data, and stores the EX op cancels
logic ex_stkill;
always_comb begin
	ex_stkill = 1'b0;
	case (ex_u.op)
		OP_CAS:  ex_st = cas_eq ? ex_av : ex_bv;
		OP_CAS2W: begin
			ex_st     = (ex_u.cond[0] && !cas2_eq) ? ex_bv : ex_av;
			ex_stkill = !ex_u.cond[0] && !cas2_eq;
		end
		default: ex_st = ex_res;
	endcase
	// an FPU store whose result is not written (an enabled integer
	// SNAN/OPERR, an unimplemented / unsupported store): its stores go
	if (fp_stkill && ex_u.mem == M_ST && !ex_is_fp) ex_stkill = 1'b1;
end

// a store into the instruction stream just ahead (see EX -> WB).  Code
// the front end fetched elsewhere (a predicted target) is the program's
// to keep coherent: the 68040 prefetches both paths of a branch and
// requires CPUSHA before self-modified code runs (MC68040UM 4.5, 7.7).
wire ex_smc = (ex_u.mem == M_ST || ex_u.mem == M_RMW) &&
              ((ex_ea[31:6] == ex_npc[31:6]) ||
               (ex_ea[31:6] == ex_npc[31:6] + 26'd1));
logic smc_pend;
// mispredict: the actual path differs from the one the front end took
wire        ex_br      = (ex_u.br != BR_NONE) || (ex_u.op == OP_RTE);
wire [31:0] ex_next    = ex_taken ? ex_target : ex_npc;
wire        ex_mispred = ex_br && ((ex_taken != ex_u.pred) ||
                                   (ex_taken && ex_u.pred && ex_target != ex_u.target));
// a mispredicted branch that WB will redirect for no other reason turns
// the front end round as it leaves EX, a cycle early; the stages behind it
// still go at WB (the front end is not flushed again), and AG takes
// nothing in between
logic       eredir_pend, wb_eredir;
wire        ex_early = ex_mispred && !ex_u.ser && !ex_sr_we &&
                       !(ex_u.last && (smc_pend || ex_smc)) && (ex_u.exc == 8'd0) &&
                       !ex_fault && (ex_xvec == 8'd0) && !ex_odd && !kill_now && !flush;

// a change of flow to an odd address is an address error at the
// instruction (format $2, the address with A0 cleared), before any of its
// side effects -- the BSR/JSR push, the RTS/RTR pop -- except that RTE has
// committed its SR and RTR its CCR.  Bcc and DBcc validate their target
// taken or not (DBcc before its condition: Dn is left untouched).
// The frame PC follows gencpu, as the cputest 68040 AE group records it:
// the instruction, except JMP (opcode + 2; + 6 for the indexed modes), JSR
// (the odd target: the fault is the fetch there) and the handler fetch of
// an exception (the vector offset, without VBR).
// (Bcc/DBcc: the decoded target, so the check does not wait for the ALU
// result that decides taken -- that path ends in the register file write
// enable.  Every other change of flow is unconditional or an FPU one.)
// The unconditional transfers (and RTE) are always taken; the others'
// target is the decoded one, and only the FPU's (FBcc FDBcc) can be taken
// besides Bcc and DBcc: its own taken, not EX's selected one.
wire        ex_bdb  = (ex_u.op == OP_BCC) || (ex_u.op == OP_DBCC);
wire        ex_ubr  = (ex_u.br == BR_IMM) || (ex_u.br == BR_EA) ||
                      (ex_u.br == BR_A) || (ex_u.br == BR_B) || (ex_u.op == OP_RTE);
wire [31:0] ex_otgt = (!ex_bdb && ex_ubr) ? ex_target : ex_u.target;
wire        ex_odd  = ex_br && (ex_bdb ? ex_u.target[0] :
                                ex_ubr ? ex_target[0] :
                                ((ex_u.op == OP_FPU) && fp_taken && ex_u.target[0]));
logic [31:0] ex_odd_pc;
always_comb begin
	ex_odd_pc = ex_u.pc;
	if (ex_u.br == BR_EA)
		ex_odd_pc = ex_u.pc + (((ex_u.imm_b[5:3] == 3'd6) ||
		                        (ex_u.imm_b[5:0] == 6'o73)) ? 32'd6 : 32'd2);
	else if ((ex_u.br == BR_B && ex_u.op == OP_MOV) ||
	         (ex_u.br == BR_IMM && ex_u.op == OP_MOV && ex_u.imm_b[15:6] == 10'b0100_1110_10))
		ex_odd_pc = ex_otgt;                 // JSR (JSR_K: the opword in B)
	else if (ex_u.br == BR_A && ex_u.op == OP_MOV && ex_u.cond == 4'hF)
		ex_odd_pc = ex_ea - vbr_r;
end

// front-file write by EX, and its broadcast to younger operands
// (CAS writes Dc either way: on a match the value written -- the
// operand read, over Dc's bits above the size -- is Dc itself, so the
// compare stays off the write enable)
wire ex_d_eff = ex_u.d_v && !ex_dkill;
// (the odd-target check as it concerns a register write: only DBcc and
// FDBcc are branches that write one, so the ALU's taken stays off the
// operand forwarding -- the FPU's own taken, not EX's selected one)
wire ex_odd_w = ex_br && (ex_bdb ? ex_u.target[0] :
                          (ex_u.op == OP_FPU) && fp_taken && ex_target[0]);
assign exw_v   = adv_ex && ex_d_eff && !ex_fault && (ex_xvec == 8'd0) && !ex_odd_w &&
                 (ex_u.exc == 8'd0);
// the same for AG's base/index loads: without EX's exception decision (a
// late signal) -- a uop that takes an exception flushes AG with the rest
wire        exw_ag  = adv_ex && ex_d_eff;
// ... and for the operands of the uops in DC1 and DC2: a uop that takes an
// exception flushes them too, and the flush clears the front file (fv), so
// the forwarding needs only whether EX writes the register (the timing path)
wire        exw_fw  = exw_ag;
assign exw_reg = ex_u.d_reg;
assign exw_val = (ex_u.op == OP_CAS) ? ((ex_bv & ex_szm) | (ex_latch & ~ex_szm)) : ex_res;
// synthesis translate_off
always @(posedge clk)
	if (nreset && exw_v && ex_ee && exw_val != ex_er) begin
		$display("FAIL: early result %h, EX wrote %h (pc %h op %0d)", ex_er, exw_val, ex_u.pc, ex_u.op);
		$finish;
	end
// synthesis translate_on

//--------------------------------------------------------------------------
// WB
//--------------------------------------------------------------------------
// interrupt recognition at instruction boundaries: a level above the mask,
// or a new level 7 (edge triggered, not masked)
logic  [2:0] ipl_q;
logic        nmi_edge;
logic  [2:0] irq_lvl_r;       // level being acknowledged
// the mask in force at the boundary: an instruction that writes SR (MOVE
// to SR, RTE, ANDI/ORI/EORI to SR) decides with its new mask, so a request
// it unmasks is taken at that very boundary (cputest irq/all).  A request
// that already beat the mask holds IPEND (ipend_r) and is taken at the next
// boundary although the instruction raises the mask; IPEND lasts only while
// the request is held at that level or above.
logic        ipend_r;
logic  [2:0] ipend_lvl;
wire  [2:0]  irq_mask = (wb_v && wb_sr_we && wb_ok) ? wb_sr_new[10:8] : sr_r[10:8];
// level 7 is also recognised by level comparison whenever the mask is
// below 7 (MC68040UM 8.2.9, figure 8-3: RTE or MOVE to SR lowering the
// mask with IPL still at 7 takes it again); at mask 7 only its edge
wire         irq_pend = nmi_edge || (ipl_q > irq_mask) ||
                        (ipl_q != 3'd7 && ipend_r && ipl_q >= ipend_lvl);
wire  [2:0]  irq_lvl  = nmi_edge ? 3'd7 : ipl_q;

logic        stopped;         // STOP: waiting for an interrupt
logic [31:0] stop_pc;         // the instruction after STOP
logic        trace_defer;     // a trace held back by an interrupt
logic [31:0] trace_addr;      // its instruction address
logic        rst_issued;      // RESET instruction: RSTO requested
logic        wb_stv;          // WB: a store, and no exception
logic        xstk;            // an exception routine runs (entry to its last uop)
logic        xr_dbl;          // ... and it is an access error's, an address
                              // error's or reset's (a fault in it: halt)
logic        x_first;         // the routine is done, its handler's first
                              // instruction has not completed yet
logic        wb_cof;          // the uop's control transfer was taken

wire wb_is_exc   = wb_v && !wb_ok;
wire wb_commit   = adv_wb && !wb_is_exc;
wire wb_bound    = wb_commit && wb_u.last;
// the mask an IPEND claim is made against: sr_r, or the new mask on the
// cycle an SR write commits (sr_r takes it at the end of that cycle)
wire  [2:0]  claim_mask = (wb_commit && wb_sr_we) ? wb_sr_new[10:8] : sr_r[10:8];
wire [31:0] wb_next = wb_redir_pc;

// trace uses the T bits the instruction started with (sr_r before its own
// SR write): T1 every instruction, T0 taken transfers and the 68040 list
wire tr_now      = sr_r[15] || (sr_r[14] && (wb_u.t0cof || wb_cof));
wire wb_is_stop  = (wb_u.op == OP_MISC) && (wb_u.cond == 4'd2);
// STOP is traced under T1, and under T0 only when it changes the upper SR
// byte (WinUAE MakeFromSR_x); a traced STOP does not stop
wire stop_traced = wb_is_stop && (sr_r[15] || (sr_r[14] && (wb_sr_new[15:8] != sr_r[15:8])));
// an interrupt accepted at a boundary where a trace is also due goes first;
// the trace is held (trace_defer) and taken at the end of the interrupt's
// exception processing, stacking the handler's entry address (MC68040UM
// 8.3: the interrupt's processing follows the other exception's at once)
wire trace_due   = wb_bound && (wb_is_stop ? stop_traced : (tr_now || trace_defer));
// a MOVEM continuation armed by RTE runs before a pending interrupt; no
// interrupt between an RTE's throwaway frame and the frame after it --
// the RTE that pops the last frame ends at a boundary like any other, so
// an interrupt its SR unmasks is taken before the instruction it returns to
wire cm_block    = cm_pend || (wb_v && wb_u.op == OP_RTE && cm_n_v) ||
                   (wb_v && wb_u.op == OP_RTE && rte_fmt1) ||
                   (rte_cont && !(wb_v && wb_u.op == OP_RTE));
wire take_irq    = irq_pend && !cm_block && (wb_bound || (stopped && !wb_v));
// (a throwaway frame's RTE goes on: its trace is the whole RTE's, judged
// at its end with the SR it ends with)
wire take_trace  = trace_due && !take_irq && !(wb_v && wb_u.op == OP_RTE && rte_fmt1);
wire wb_refetch;
// a speculative fetch fault (code 1) is no exception: WB refetches the
// instruction once on demand, and only a second fault there is an access
// error (rt_armed/rt_pc)
// exceptions that stack the next instruction: the instruction completed
wire wb_post_trap = (wb_exc >= 8'd32 && wb_exc < 8'd48) ||
                    wb_exc == 8'd5 || wb_exc == 8'd6 || wb_exc == 8'd7;
assign wb_refetch = adv_wb && wb_v && (wb_exc == EXC_IFS || wb_exc == EXC_IFSA);
logic        rt_armed;
logic [31:0] rt_pc;
// a double bus fault (MC68040UM 8.2.1): an access or address error while
// the routine of an access error, an address error or reset runs (the
// stacking, the vector fetch, an odd handler address), or while the first
// instruction of its handler is fetched (an instruction access error: TM
// is a program space): the processor halts (PST $5) instead of taking it
wire dbl_fault   = xr_dbl && !halted &&
                   (adv_wb && wb_is_exc && !wb_refetch &&
                    ((xstk && (wb_exc == 8'd2 || wb_exc == 8'd3)) ||
                     (x_first && wb_exc == 8'd2 && (wb_exc_ssw[2:0] == 3'd2 || wb_exc_ssw[2:0] == 3'd6))));
wire x_go        = ((adv_wb && wb_is_exc && !wb_refetch) || take_trace || take_irq) &&
                   !dbl_fault && !halted;
// a locked sequence (TAS, CAS, CAS2, a table update) ends with its LOCKE
// write; before that only an exception ends it
assign lk_abandon = x_go || dbl_fault;

// register file write ports.  Front: the AG address updates and the EX
// result.  Back: the WB commit (a result beats an address update), the
// address update of a trap after its instruction, and at exception entry
// the routine's operands (T8-T13, and T5-T7 for a format $7 frame, two
// per cycle).
always_comb begin
	logic wcom, wpost;
	fwe[0] = adv_ag && ag_u.upd_v && !ag_dyncan;  fwa[0] = ag_u.upd_reg;  fwd[0] = ag_updv;
	fwe[1] = adv_ag && ag_u.upd2_v && !ag_dyncan; fwa[1] = ag_u.upd2_reg; fwd[1] = ag_u2v;
	fwe_ag[0] = ag_v && ag_u.upd_v && !ag_dyncan;
	fwe_ag[1] = ag_v && ag_u.upd2_v && !ag_dyncan;
	fwe[2] = exw_v;                 fwa[2] = exw_reg;       fwd[2] = exw_val;
	wcom  = wb_commit;
	wpost = adv_wb && wb_is_exc && (wb_post_trap || wb_xcommit);
	// the back file: two write ports, the later winning on the same
	// register.  Port 0 the address update; port 1 the result, else the
	// second (deferred) update -- a uop with upd2 writes no register result
	// (its destination is memory), and its upd2 yields to its upd on the
	// same register.  So a result beats an update, and upd beats upd2.
	bwe[0] = (wcom || wpost) && wb_u.upd_v;  bwa[0] = wb_u.upd_reg;  bwd[0] = wb_upd_val;
	if (wcom && wb_dwe) begin
		bwe[1] = 1'b1; bwa[1] = wb_u.d_reg; bwd[1] = wb_res;
	end
	else begin
		bwe[1] = (wcom || wpost) && wb_u.upd2_v && !(wb_u.upd_v && wb_u.upd_reg == wb_u.upd2_reg);
		bwa[1] = wb_u.upd2_reg; bwd[1] = wb_upd2_val;
	end
	bwe[2] = 1'b0; bwa[2] = '0; bwd[2] = '0;
	case (xw_ph)
		3'd1: begin
			bwe = 3'b011;
			bwa[0] = R_T0 + 5'd8;  bwd[0] = xi_vaddr;
			bwa[1] = R_T0 + 5'd9;  bwd[1] = xi_pc;
		end
		3'd2: begin
			bwe = 3'b011;
			bwa[0] = R_T0 + 5'd10; bwd[0] = {16'd0, xi_sr};
			bwa[1] = R_T0 + 5'd11; bwd[1] = xi_addr;
		end
		3'd3: begin
			bwe = 3'b011;
			bwa[0] = R_T0 + 5'd12; bwd[0] = {16'd0, xi_vecw};
			bwa[1] = R_T0 + 5'd13; bwd[1] = {16'd0, xi_ssw};
		end
		3'd4: begin
			bwe = 3'b011;
			bwa[0] = R_T0 + 5'd5;  bwd[0] = xi_ea;
			bwa[1] = R_T0 + 5'd6;  bwd[1] = xi_w3a;
		end
		3'd5: begin
			bwe = 3'b011;
			bwa[0] = R_T0 + 5'd7;  bwd[0] = xi_w3d;
			bwa[1] = R_T0;         bwd[1] = xi_pd[127:96];   // PD0 (WB1D)
		end
		3'd6: begin
			bwe = 3'b011;
			bwa[0] = R_T0 + 5'd1;  bwd[0] = xi_pd[95:64];    // PD1
			bwa[1] = R_T0 + 5'd2;  bwd[1] = xi_pd[63:32];    // PD2
		end
		3'd7: begin
			bwe = 3'b001;
			bwa[0] = R_T0 + 5'd3;  bwd[0] = xi_pd[31:0];     // PD3
		end
		default: ;
	endcase
end


// WB holds: store not accepted yet; RESET until RSTO is done
wire wb_reset    = (wb_u.op == OP_MISC) && (wb_u.cond == 4'd1);
wire wb_mt       = (wb_u.op == OP_MISC) && (wb_u.cond >= 4'd3) && (wb_u.cond <= 4'd5);
logic mt_seen;                // the DMU finished this WB uop's maintenance
assign wb_hold = wb_v && (halted || (!wb_is_exc &&
                 ((wb_st && !dm_st_rdy) || (wb_st && dm_st_fault) ||
                  (wb_reset && (!rst_issued || rsto_busy)) ||
                  (wb_mt && !mt_seen))));

assign mt_v      = wb_v && wb_mt && !wb_is_exc && !mt_seen;
assign mt_op     = (wb_u.cond == 4'd3) ? (wb_u.imm_b[5] ? 3'd2 : 3'd1) :
                   (wb_u.cond == 4'd4) ? 3'd3 : 3'd4;
assign mt_scope  = (wb_u.cond == 4'd3) ? wb_u.imm_b[4:3] :
                   (wb_u.cond == 4'd4) ? (wb_u.imm_b[4] ? 2'd3 : 2'd2) : 2'd2;
assign mt_caches = wb_u.imm_b[7:6];
assign mt_addr   = wb_res;
assign mt_fc     = dfc_r;
assign mt_ng     = (wb_u.cond == 4'd4) && !wb_u.imm_b[3];
assign mt_wr     = (wb_u.cond == 4'd5) && !wb_u.imm_b[5];   // PTESTW $F548, PTESTR $F568

logic        rst_seq;         // reset exception pending (first cycles)

// same-cycle kill of every younger uop: WB takes an exception or redirects
assign kill_now = (adv_wb && (wb_is_exc || wb_redir)) || x_go;

// exception entry values
logic  [7:0] x_vec;
logic  [3:0] x_fmt;
logic [31:0] x_pc, x_addr;
logic [15:0] x_osr, x_ssw, x_nsr;
logic  [3:0] x_kind;
logic  [4:0] x_ssp;
logic        x_wfault;
logic        x_cm;             // SSW CM: a MOVEM continues from x_cm_ea
logic [31:0] x_cm_ea;
always_comb begin
	logic [15:0] cur;
	// the SR the exception sees: after this instruction when it completed
	cur = wb_commit ? (wb_sr_we ? (wb_sr_new & SR_MASK) : {sr_r[15:5], wb_ccr})
	                : {sr_r[15:5], wb_ccr};
	if (stopped && !wb_v) cur = {sr_r[15:5], ccr_b};
	if (adv_wb && wb_is_exc && wb_oddrte) cur = wb_sr_new & SR_MASK;
	x_osr  = cur;
	x_ssw  = 16'd0;
	x_addr = wb_u.pc;
	x_pc   = wb_u.pc;
	x_vec  = wb_exc;
	if (adv_wb && wb_is_exc) begin
		x_vec  = wb_exc;
		x_addr = wb_exc_addr;
		x_ssw  = wb_exc_ssw;
		if (x_cm) x_ssw = x_ssw | 16'h1000;
		// TRAP #n, TRAPcc, CHK and divide-by-zero stack the next
		// instruction; faults and illegal opcodes the instruction
		x_pc   = ((wb_exc >= 8'd32 && wb_exc < 8'd48) ||
		          wb_exc == 8'd5 || wb_exc == 8'd6 || wb_exc == 8'd7) ? wb_npc : wb_u.pc;
		if (wb_exc_pcv) x_pc = wb_exc_pc;
	end
	else if (take_irq) begin
		x_vec  = 8'd24 + {5'd0, irq_lvl};   // replaced by the IACK result
		x_pc   = (stopped && !wb_v) ? stop_pc : wb_next;
	end
	else begin
		// trace: format $2, PC = where execution continues, address = the
		// traced instruction
		x_vec  = 8'd9;
		x_pc   = wb_next;
		x_addr = trace_defer ? trace_addr : wb_u.pc;
	end
	// 68040 frames (MC68040UM table 8-?): $7 access error; $2 address
	// error, CHK, TRAPcc/TRAPV, divide by zero, trace; $0 the rest; the FPU
	// brings its own ($0, $2, $3)
	x_fmt  = (x_vec == 8'd2) ? 4'h7 :
	         (x_vec == 8'd3 || x_vec == 8'd5 || x_vec == 8'd6 || x_vec == 8'd7 ||
	          x_vec == 8'd9) ? 4'h2 : 4'h0;
	if (adv_wb && wb_is_exc && wb_exc_fmtv) x_fmt = wb_exc_fmt;
	x_kind = take_irq && !(adv_wb && wb_is_exc) ? (cur[12] ? EK_IRQM : EK_IRQ) :
	         (x_fmt == 4'h7) ? EK_FMT7 : (x_fmt == 4'h2 || x_fmt == 4'h3) ? EK_FMT2 : EK_FMT0;
	x_ssp  = cur[12] ? R_MSP : R_ISP;
	x_wfault = (x_fmt == 4'h7) && !x_ssw[8];

	// the SR inside the handler: S set, T cleared; an interrupt raises the
	// mask to its level and clears M
	x_nsr  = {2'b00, 1'b1, cur[12], cur[11:0]};
	if (take_irq && !(adv_wb && wb_is_exc)) begin
		x_nsr[12]   = 1'b0;
		x_nsr[10:8] = irq_lvl;
	end
end

// an access error of a MOVEM transfer in an indexed or PC-relative mode,
// or of a continued MOVEM (also its refetch), sets CM and stacks the EA
always_comb begin
	x_cm    = adv_wb && wb_is_exc && (wb_exc == 8'd2) &&
	          ((wb_u.op == OP_MOV && wb_u.cond == 4'hC && wb_u.mem != M_NONE) ||
	           (cm_pend && wb_u.pc == cm_pc));
	x_cm_ea = (cm_pend && wb_u.pc == cm_pc) ? cm_ea : wb_mv_ea;
end

// the return stack after the instruction at WB
function automatic logic [6:0] ras_after(input ras_snap_t r);
	case (r.k)
		2'd1:    ras_after = {r.tp + 3'd1, (r.n == 4'd8) ? 4'd8 : r.n + 4'd1};
		2'd2:    ras_after = {r.tp - 3'd1, r.n - 4'd1};
		default: ras_after = {r.tp, r.n};
	endcase
endfunction

always_ff @(posedge clk) begin
	// (AG's uop PC and the continued MOVEM's PC as they will be: their
	// compare is registered, cm_hit_q)
	// (each candidate pair compared in parallel; AG's late take and WB's
	// write of cm_pc select last)
	logic ag_ld, cm_wr, cm_rst;
	ag_ld  = 1'b0;
	cm_wr  = 1'b0;
	cm_rst = 1'b0;
	redir_v <= 1'b0;
	ras_rv  <= 1'b0;
	exc_go  <= 1'b0;
	flush   <= 1'b0;
	fe_flush <= 1'b0;
	ucond_v <= 1'b0;
	dbg_retire <= 1'b0;
	dbg_rinfo  <= 16'd0;

	if (!nreset) begin
		ag_v  <= 1'b0; dc1_v <= 1'b0; dc2_v <= 1'b0; ex_v <= 1'b0; wb_v <= 1'b0;
		sk_v  <= 1'b0;
		sk_vr <= 1'b0;
		eredir_pend <= 1'b0;
		wb_eredir   <= 1'b0;
		fv <= 32'd0;
		xw_ph <= 3'd0;
		ccr_f   <= 5'd0;
		ccr_b   <= 5'd0;
		sr_r    <= 16'h2700;
		vbr_r   <= 32'd0;
		cacr_r  <= 32'd0;
		sfc_r   <= 3'd0;
		dfc_r   <= 3'd0;
		tc_r    <= 32'd0;
		itt0_r  <= 32'd0; itt1_r <= 32'd0; dtt0_r <= 32'd0; dtt1_r <= 32'd0;
		mmusr_r <= 32'd0; urp_r  <= 32'd0; srp_r  <= 32'd0;
		xi_pc   <= 32'd0; xi_addr <= 32'd0; xi_sr <= 16'd0; xi_vecw <= 16'd0; xi_ssw <= 16'd0;
		xi_ea   <= 32'd0; xi_w3a <= 32'd0; xi_w3d <= 32'd0; xi_f7 <= 1'b0;
		md_go   <= 1'b0;
		md_hiin <= 32'd0;
		cas2_eq <= 1'b0;
		rte_fmt1 <= 1'b0;
		rte_cont <= 1'b0;
		rte_fmt7 <= 1'b0;
		cm_n_v   <= 1'b0;
		cm_n_ea  <= 32'd0;
		cm_pend  <= 1'b0;
		cm_ea    <= 32'd0;
		cm_pc    <= 32'd0;
		cm_rst   = 1'b1;
		wb_mv_ea <= 32'd0;
		trace_defer <= 1'b0;
		trace_addr <= 32'd0;
		md_fin  <= 1'b0;
		md_z    <= 1'b0;
		ex_ph   <= 1'b0;
		ex_pb   <= 1'b0;
		xs_q    <= '0;
		md_rem  <= 32'd0;
		md_lol  <= 32'd0;
		md_ovfl <= 1'b0;
		ex_latch <= 32'd0;
		bf_off   <= 32'd0;
		bf_w     <= 6'd32;
		bf_wn    <= 6'd0;
		bf_top   <= 32'hFFFF_FFFF;
		bf_sx    <= 32'd0;
		bf_lonew <= 8'd0;
		ipl_q   <= 3'd0;
		nmi_edge <= 1'b0;
		irq_lvl_r <= 3'd0;
		ipend_r  <= 1'b0;
		ipend_lvl <= 3'd0;
		rt_armed <= 1'b0;
		rt_pc    <= 32'd0;
		smc_pend <= 1'b0;
		stopped <= 1'b0;
		stop_pc <= 32'd0;
		rst_issued <= 1'b0;
		mt_seen <= 1'b0;
		wb_cof  <= 1'b0;
		halted  <= 1'b0;
		rst_seq <= 1'b1;
		exc_kind <= EK_RESET;
		exc_ssp <= R_ISP;
		redir_pc <= 32'd0;
		ras_rtp <= '0;
		ras_rn <= '0;
	end
	else begin
		//------------------------------------------------------------------
		// reset exception: the routine loads ISP and PC from 0 and 4
		//------------------------------------------------------------------
		if (rst_seq) begin
			rst_seq  <= 1'b0;
			exc_go   <= 1'b1;
			exc_kind <= EK_RESET;
			exc_ssp  <= R_ISP;
		end

		ipl_q <= ipl;
		if (ipl_q == 3'd0 || ipl_q == 3'd7 || (ipend_r && ipl_q < ipend_lvl))
			ipend_r <= 1'b0;
		// against the mask in force: on the cycle an SR write commits, sr_r
		// still holds the old mask, and a request rising then must not
		// claim IPEND past a raised mask (it was taken one instruction into
		// Kickstart's dispatcher, after its MOVE #$2700,SR)
		else if (ipl_q > claim_mask && (!ipend_r || ipl_q > ipend_lvl)) begin
			ipend_r   <= 1'b1;
			ipend_lvl <= ipl_q;
		end
		if (ipl == 3'd7 && ipl_q != 3'd7) nmi_edge <= 1'b1;
		else if (ipl != 3'd7) nmi_edge <= 1'b0;

		//------------------------------------------------------------------
		// AG -> DC1
		//------------------------------------------------------------------
		if (adv_ag) begin
			dc1_u   <= ag_u;
			dc1_u.msz <= ag_msz;
			if (ag_snref) begin
				// refetched from here (see snp_pend): no access, no effect
				dc1_u.exc <= EXC_SNR;
				dc1_u.mem <= M_NONE;
			end
			if (ag_cancel) begin
				// no tail byte: a load gives zero, a store nothing; a
				// cancelled FPU transfer also leaves its address registers
				dc1_u.mem   <= M_NONE;
				dc1_u.a_src <= OS_ZERO;
				if (ag_dyncan) begin
					dc1_u.upd_v  <= 1'b0;
					dc1_u.upd2_v <= 1'b0;
				end
			end
			dc1_a   <= ag_a;
			dc1_b   <= ag_b;
			dc1_ee  <= ag_ee && !ag_snref && !ag_cancel;
			dc1_er  <= ag_er;
			dc1_ea  <= ag_u.ag ? ag_maddr : 32'd0;
			dc1_upd <= ag_updv;
			dc1_upd2 <= ag_u2v;
		end
		if (!stall_dc1) dc1_v <= adv_ag;
		else begin
			if (exw_fw && dc1_u.a_src == OS_REG && dc1_u.a_reg == exw_reg) dc1_a <= exw_val;
			if (exw_fw && dc1_u.b_src == OS_REG && dc1_u.b_reg == exw_reg) dc1_b <= exw_val;
		end
		// snoop into the uop entering DC1
		if (adv_ag && exw_fw) begin
			if (ag_u.a_src == OS_REG && ag_u.a_reg == exw_reg) dc1_a <= exw_val;
			if (ag_u.b_src == OS_REG && ag_u.b_reg == exw_reg) dc1_b <= exw_val;
		end

		//------------------------------------------------------------------
		// DC1 -> DC2
		//------------------------------------------------------------------
		if (adv_dc1) begin
			dc2_u    <= dc1_u;
			dc2_ee   <= dc1_ee;
			dc2_er   <= dc1_er;
			dc2_a    <= (exw_fw && dc1_u.a_src == OS_REG && dc1_u.a_reg == exw_reg) ? exw_val : dc1_a;
			dc2_b    <= (exw_fw && dc1_u.b_src == OS_REG && dc1_u.b_reg == exw_reg) ? exw_val : dc1_b;
			dc2_ea   <= dc1_ea;
			dc2_upd  <= dc1_upd;
			dc2_upd2 <= dc1_upd2;
		end
		else if (dc2_v && exw_fw) begin
			if (dc2_u.a_src == OS_REG && dc2_u.a_reg == exw_reg) dc2_a <= exw_val;
			if (dc2_u.b_src == OS_REG && dc2_u.b_reg == exw_reg) dc2_b <= exw_val;
		end
		if (!stall_dc2) dc2_v <= adv_dc1;

		//------------------------------------------------------------------
		// DC2 -> EX
		//------------------------------------------------------------------
		if (adv_dc2) begin
			ex_u     <= dc2_u;
			ex_npc   <= dc2_u.pc + {27'd0, dc2_u.ilen, 1'b0};
			ex_kc    <= {dc2_u.op == OP_CAS2R, dc2_u.op == OP_CHK2B,
			             dc2_u.op == OP_DBCC, dc2_u.op == OP_MDRES, dc2_u.op == OP_DIV,
			             dc2_u.op == OP_FPU};
			ex_shk   <= shk_of(dc2_u.op);
			ex_ee    <= dc2_ee;
			ex_er    <= dc2_er;
			ex_a     <= (exw_v && dc2_u.a_src == OS_REG && dc2_u.a_reg == exw_reg) ? exw_val : dc2_a;
			ex_b     <= (exw_v && dc2_u.b_src == OS_REG && dc2_u.b_reg == exw_reg) ? exw_val : dc2_b;
			ex_ea    <= dc2_ea;
			ex_ld    <= dm_ldata;
			ex_ldj   <= dm_ldata_job;
			ex_upd   <= dc2_upd;
			ex_upd2  <= dc2_upd2;
			ex_fault <= (dc2_u.mem != M_NONE) && dm_fault;
			ex_fvec  <= dm_fvec;
			ex_faddr <= dm_faddr;
			ex_fssw  <= dm_fssw;
			md_go    <= 1'b0;
			md_fin   <= 1'b0;
			md_z     <= 1'b0;
		end
		if (!stall_ex) ex_v <= adv_dc2;
		// EX's next uop against WB's next: EX's own when it moves on
		if (adv_dc2) ew_same <= adv_ex ? (dc2_u.pc == ex_u.pc) : (dc2_u.pc == wb_u.pc);
		else if (adv_ex) ew_same <= 1'b1;
		if (ex_md_start) md_go <= 1'b1;
		if (ex_v && ex_div0) md_z <= 1'b1;
		if (ex_v && ex_pre && !ex_pb) begin
			ex_pb    <= 1'b1;
			bf_ins_q <= bf_rr & bf_top;    // (ex_av << bf_wn)
			bf_rot_q <= bf_rot;
			rox_nx_q <= rox_nx;
			rox_nxl_q <= rox_nxl;
		end
		else if (ex_v && ex_slow && !ex_ph) begin
			ex_ph <= 1'b1;
			xs_q  <= xs;
		end
		if (adv_ex || kill_now) begin ex_ph <= 1'b0; ex_pb <= 1'b0; end

		//------------------------------------------------------------------
		// EX -> WB
		//------------------------------------------------------------------
		if (adv_ex) begin
			wb_u        <= ex_u;
			wb_npc      <= ex_npc;
			wb_res      <= exw_val;
			wb_dwe      <= ex_d_eff;
			wb_upd_val  <= ex_upd;
			wb_upd2_val <= ex_upd2;
			wb_st       <= (ex_u.mem == M_ST || ex_u.mem == M_RMW) && !ex_stkill;
			// (the same, and no exception: the DMU's store valid from a
			// flip-flop -- wb_exc's compare sat on the stall chain)
			wb_stv      <= (ex_u.mem == M_ST || ex_u.mem == M_RMW) && !ex_stkill &&
			               ex_u.exc == 8'd0 && !ex_fault && ex_xvec == 8'd0 && !ex_odd;
			wb_ok       <= ex_u.exc == 8'd0 && !ex_fault && ex_xvec == 8'd0 && !ex_odd;
			wb_st_data  <= ex_st;
			// a store into the instruction stream just ahead (the fetch
			// queue and the instructions in flight) refetches after itself:
			// the 68040 does not promise this, the previous core's AmigaOS
			// boot depended on it (t_integer 192)
			// (a store from a uop before the last one -- MOVEM, a bit
			// field, CAS2 -- defers the refetch to the instruction's end:
			// redirecting there would drop the instruction's remaining uops)
			wb_redir    <= ex_mispred || ex_u.ser || ex_sr_we ||
			               (ex_u.last && (smc_pend || ex_smc));
			wb_eredir   <= ex_early;
			// (the return stack to restore is read only with ras_rv, which
			// pulses with a redirect: it is loaded every advance, so the
			// late early-redirect decision is not its enable; WB's later
			// loads take precedence)
			{ras_rtp, ras_rn} <= ras_after(ex_u.ras);
			if (ex_early) begin
				fe_flush    <= 1'b1;
				redir_v     <= 1'b1;
				redir_pc    <= ex_next;
				ras_rv      <= ex_u.ras.v;
				eredir_pend <= 1'b1;
			end
			if (ex_u.last) smc_pend <= 1'b0;
			else if (ex_smc) smc_pend <= 1'b1;
			// where execution continues, predicted correctly or not
			wb_redir_pc <= ex_br ? ex_next : ex_npc;
			wb_sr_we    <= ex_sr_we;
			wb_cof      <= ex_br && ex_taken;
			wb_sr_new   <= ex_sr_new;
			if (ex_u.op == OP_CAS2C)
				cas2_eq <= ex_u.cond[0] ? (cas2_eq && cmp_flags[2]) : cmp_flags[2];
			if (ex_u.exc == EXC_SNR) begin
				wb_exc      <= EXC_IFS;     // refetched by WB, never an error
				wb_exc_addr <= ex_u.pc;
				wb_exc_ssw  <= 16'd0;
			end
			else if (ex_u.exc != 8'd0) begin
				logic ifs, ifa;
				// instruction fetch faults: a speculative one is refetched
				// once (wb_refetch) and becomes an access error when it
				// faults again at the same instruction
				ifs = (ex_u.exc == EXC_IFS || ex_u.exc == EXC_IFSA);
				ifa = (ex_u.exc == EXC_IFA || ex_u.exc == EXC_IFSA);
				if (ifs && !(rt_armed && rt_pc == ex_u.pc))
					wb_exc <= ex_u.exc;
				else if (ifs || ex_u.exc == EXC_IFB || ex_u.exc == EXC_IFA)
					wb_exc <= 8'd2;
				else
					wb_exc <= ex_u.exc;
				// a faulted instruction fetch: the faulting word's address;
				// SSW ATC for an MMU fault, read, long, TT normal, TM the
				// program space of the instruction's privilege
				if (ifs || ex_u.exc == EXC_IFB || ex_u.exc == EXC_IFA) begin
					wb_exc_addr <= ex_u.target;
					wb_exc_ssw  <= {5'd0, ifa, 1'b0, 1'b1, 3'b000, 2'b00,
					                sr_r[13] ? 3'd6 : 3'd2};
				end
				else begin
					wb_exc_addr <= ex_u.pc;
					wb_exc_ssw  <= 16'd0;
				end
			end
			else if (ex_fault) begin
				wb_exc      <= ex_fvec;
				wb_exc_addr <= ex_faddr;
				wb_exc_ssw  <= ex_fssw;
			end
			else if (ex_xvec == 8'd0 && ex_odd) begin
				wb_exc      <= 8'd3;
				wb_exc_addr <= {ex_otgt[31:1], 1'b0};
				wb_exc_ssw  <= 16'd0;
			end
			else if (ex_is_fp && ex_xvec != 8'd0) begin
				// FPU exceptions bring their frame format, PC and address
				wb_exc      <= ex_xvec;
				wb_exc_addr <= fp_xaddr;
				wb_exc_ssw  <= 16'd0;
			end
			else begin
				wb_exc      <= ex_xvec;
				wb_exc_addr <= ex_u.pc;
				wb_exc_ssw  <= 16'd0;
			end
			wb_exc_pcv <= ex_u.exc == 8'd0 && !ex_fault && ex_xvec == 8'd0 && ex_odd;
			wb_exc_pc  <= ex_odd_pc;
			wb_exc_fmtv <= 1'b0;
			wb_xcommit  <= 1'b0;
			if (ex_u.exc == 8'd0 && !ex_fault && ex_is_fp && ex_xvec != 8'd0) begin
				wb_exc_pcv  <= 1'b1;
				wb_exc_pc   <= fp_xnext ? ex_npc : ex_u.pc;
				wb_exc_fmtv <= 1'b1;
				wb_exc_fmt  <= fp_xfmt;
				wb_xcommit  <= fp_xcommit;
			end
			wb_oddrte  <= ex_u.exc == 8'd0 && !ex_fault && ex_xvec == 8'd0 && ex_odd &&
			              ex_u.op == OP_RTE;
			// CCR after this uop (CHK, CHK2, TRAPcc and divide-by-zero set
			// their flags and then trap: the stacked SR carries them)
			begin
				logic [4:0] nf, c0, ist;
				// the CCR before this instruction: an access error restarts it,
				// so its frame carries that, not flags its earlier uops made
				ist = ex_u.first ? ccr_f : ccr_ist;
				if (ex_u.first) ccr_ist <= ccr_f;
				wb_ccr_ist <= ist;
				nf = (ex_u.op == OP_CAS) ? cas_flags : ex_flags;
				c0 = (ex_u.exc == 8'd0 && !ex_fault) ? ((nf & ex_u.ccr_we) | (ccr_f & ~ex_u.ccr_we)) :
				     ex_fault ? ist : ccr_f;
				wb_ccr <= c0;
				if (ex_u.exc == 8'd0 && !ex_fault)
					ccr_f <= c0;
			end
			if (ex_u.op == OP_MDHI)  md_hiin  <= ex_av;
			if (ex_u.op == OP_LATCH || (ex_u.op == OP_IACKV && !ex_u.cond[0])) ex_latch <= ex_av;
			if (ex_u.op == OP_RTEF && !ex_u.cond[0]) begin
				rte_fmt1 <= (ex_av[15:12] == 4'h1);
				rte_fmt7 <= (ex_av[15:12] == 4'h7);
			end
			if (ex_u.op == OP_MISC && ex_u.cond == 4'd6) begin
				cm_n_v  <= rte_fmt7 && ex_bv[12];
				cm_n_ea <= ex_av;
			end
			wb_mv_ea <= ex_ea - ex_u.target;
			if (ex_u.op == OP_BFSET && !ex_u.cond[0]) begin
				logic [5:0] w;
				logic [6:0] e;
				w = (ex_bv[4:0] == 5'd0) ? 6'd32 : {1'b0, ex_bv[4:0]};
				e = {4'd0, ex_av[2:0]} + {1'b0, w} + 7'd7;
				bf_off <= ex_av;
				bf_w   <= w;
				bf_wn  <= 6'd32 - w;
				bf_top <= ~(32'hFFFF_FFFF >> w);      // (a shift by 32 gives 0)
				bf_sx  <= 32'hFFFF_FFFF << w;
				bf_nb  <= e[5:3];
			end
			if (ex_u.op == OP_BF) bf_lonew <= bf_lo_out;
		end
		// (not when the next uop enters EX this cycle: the reset above is
		// for it, and the done belongs to the one leaving)
		if (md_done && md_go && !adv_dc2) md_fin <= 1'b1;
		if (md_done) begin
			md_rem  <= md_hi;
			md_lol  <= md_lo;
		end
		// overflow of the uop leaving EX (word forms check 16 bits)
		if (adv_ex && (ex_u.op == OP_DIV || ex_u.op == OP_MUL)) md_ovfl <= (ex_u.op == OP_DIV) && md_dkill;
		if (!stall_wb) wb_v <= adv_ex;

		//------------------------------------------------------------------
		// WB commit
		//------------------------------------------------------------------
		if (wb_commit) begin
			if (DEBUG) begin
				dbg_retire <= wb_u.last;
				// (only the uop's own registers: a load on kill_now or exc_pend
				// costs the fit)
				dbg_rinfo  <= {wb_u.exc, wb_u.exr, wb_u.first, wb_u.last, 5'b00000};
			end
			// architectural commit: the back file's write ports (bwe)
			ccr_b <= wb_ccr;
			if (wb_u.op == OP_SPW) begin
				// MOVEC to the 68040's control registers (masks: WinUAE
				// m68k_move2c)
				case (wb_u.imm_b[7:0])
					8'h00: sfc_r  <= wb_res[2:0];
					8'h01: dfc_r  <= wb_res[2:0];
					8'h02: cacr_r <= wb_res & 32'h8000_8000;
					8'h03: tc_r   <= wb_res & 32'h0000_C000;
					8'h04: itt0_r <= wb_res & 32'hFFFF_E364;
					8'h05: itt1_r <= wb_res & 32'hFFFF_E364;
					8'h06: dtt0_r <= wb_res & 32'hFFFF_E364;
					8'h07: dtt1_r <= wb_res & 32'hFFFF_E364;
					8'h11: vbr_r  <= wb_res;
					8'h15: mmusr_r <= wb_res;
					8'h16: urp_r  <= wb_res & 32'hFFFF_FE00;
					8'h17: srp_r  <= wb_res & 32'hFFFF_FE00;
					default: ;
				endcase
			end
			if (wb_sr_we) begin
				sr_r  <= {wb_sr_new[15:5], 5'd0};
				ccr_b <= wb_sr_new[4:0];
			end
			if (wb_is_stop && !stop_traced) begin
				stopped <= 1'b1;
				stop_pc <= wb_npc;
			end
			if (wb_redir) begin
				flush    <= 1'b1;
				if (!wb_eredir) begin
					fe_flush <= 1'b1;
					redir_v  <= 1'b1;
					redir_pc <= wb_redir_pc;
					ras_rv   <= wb_u.ras.v;
					{ras_rtp, ras_rn} <= ras_after(wb_u.ras);
				end
				// the front file restarts from the back one (fv cleared below)
				ccr_f <= wb_sr_we ? wb_sr_new[4:0] : wb_ccr;
			end
			if (wb_bound) trace_defer <= 1'b0;
			if (wb_bound) rt_armed <= 1'b0;
			if (wb_bound) begin
				// RTE of a format $7 frame with CM arms the continuation of
				// the MOVEM it returns to; any other instruction ends it
				cm_pend <= (wb_u.op == OP_RTE) && cm_n_v;
				rte_cont <= (wb_u.op == OP_RTE) && rte_fmt1;
				cm_ea   <= cm_n_ea;
				cm_pc   <= wb_next;
				cm_wr   = 1'b1;
				if (wb_u.op == OP_RTE) cm_n_v <= 1'b0;
			end
		end
		if (wb_refetch) begin
			flush    <= 1'b1;
			fe_flush <= 1'b1;
			redir_v  <= 1'b1;
			redir_pc <= wb_u.pc;
			ras_rv   <= wb_u.ras.v;
			{ras_rtp, ras_rn} <= {wb_u.ras.tp, wb_u.ras.n};
			ccr_f    <= ccr_b;
			rt_armed <= 1'b1;
			rt_pc    <= wb_u.pc;
		end

		//------------------------------------------------------------------
		// exception entry: a faulting/trapping uop (its effects discarded,
		// trap flags kept), a trace after an instruction, or an interrupt
		// at an instruction boundary.  The front file restarts from the
		// back file plus this uop's committed writes; T5..T13 carry the
		// routine's operands.
		//------------------------------------------------------------------
		if (x_go) begin
			logic [15:0] vw;
			rt_armed <= 1'b0;
			cm_pend  <= 1'b0;
			smc_pend <= 1'b0;
			vw = {x_fmt, 2'b00, x_vec, 2'b00};
			flush    <= 1'b1;
			fe_flush <= 1'b1;
			redir_v  <= 1'b0;
			ras_rv   <= 1'b0;
			xw_ph    <= 3'd1;          // T8-T13 (and T5-T7) first, then exc_go
			rte_cont <= 1'b0;
			xi_f7    <= (x_fmt == 4'h7);
			exc_kind <= x_kind;
			exc_ssp  <= x_ssp;
			xi_sr    <= x_osr;
			xi_vecw  <= vw;
			xi_pc    <= x_pc;
			xi_addr  <= x_addr;
			xi_ssw   <= x_ssw;
			sr_r     <= {x_nsr[15:5], 5'd0};
			ccr_b    <= x_osr[4:0];
			ccr_f    <= x_osr[4:0];
			stopped  <= 1'b0;
			if (take_irq && !(adv_wb && wb_is_exc)) begin
				irq_lvl_r <= irq_lvl;
				ipend_r   <= 1'b0;
				if (irq_lvl == 3'd7) nmi_edge <= 1'b0;
				// a trace due at this boundary is taken at the handler
				if (trace_due) begin
					trace_defer <= 1'b1;
					trace_addr  <= wb_u.pc;
				end
			end
			// the routine's operands, written into the back file by the
			// xw sequence: T8 vector address, T9 PC, T10 SR, T11 address,
			// T12 format/vector word, T13 SSW; format $7: T5 the EA field
			// (the MOVEM EA with CM, else FA), T6/T7 WB3A/WB3D of a write
			// fault (WB3S stays clear: the instruction restarts)
			xi_vaddr <= vbr_r + {22'd0, x_vec, 2'b00};
			xi_ea    <= x_cm ? x_cm_ea : x_addr;
			xi_w3a   <= x_wfault ? x_addr : 32'd0;
			xi_w3d   <= x_wfault ? wb_st_data : 32'd0;
			// a push that ended in TEA (SSW: a line write, TT 0, TM 0; LK and
			// CM aside): the frame carries its line in PD0-PD3 (MC68040UM
			// 8.4.6), the handler writes it; anything else, zeros
			xi_pd    <= ((x_fmt == 4'h7) && ((x_ssw & 16'hEDFF) == 16'h0060)) ? pb_data : 128'd0;
		end

		// exception entry, continued: three cycles of back-file writes
		// (five for a format $7 frame)
		if (xw_ph != 3'd0) begin
			xw_ph <= xw_ph + 3'd1;
			if ((xw_ph == 3'd3 && !xi_f7) || xw_ph == 3'd7) begin
				xw_ph  <= 3'd0;
				exc_go <= 1'b1;
			end
		end

		// front-valid bits: a front write makes the register's front copy
		// current; a redirect, a refetch or an exception drops them all
		// (AG's two writes as a mask formed without the advance, which
		// gates the mask last: the stall chain stays off the decode)
		begin
			logic [31:0] m_ag, m_ex;
			m_ag = (fwe_ag[0] ? (32'd1 << fwa[0]) : 32'd0) | (fwe_ag[1] ? (32'd1 << fwa[1]) : 32'd0);
			m_ex = fwe[2] ? (32'd1 << fwa[2]) : 32'd0;
			fv <= fv | (adv_ag ? m_ag : 32'd0) | m_ex;
		end
		if ((wb_commit && wb_redir) || wb_refetch || x_go) fv <= 32'd0;
		// synthesis translate_off
		if (fwe[0] != (adv_ag && fwe_ag[0]) || fwe[1] != (adv_ag && fwe_ag[1])) begin
			$display("FAIL: the front writes %b, the advance %b and AG's %b", fwe, adv_ag, fwe_ag);
			$finish;
		end
		// synthesis translate_on

		// a store that took a bus error at WB becomes an access fault of
		// its instruction (WB holds one cycle, then takes it)
		if (wb_v && wb_st && dm_st_rdy && dm_st_fault && wb_exc == 8'd0) begin
			wb_stv      <= 1'b0;
			wb_ok       <= 1'b0;
			wb_exc      <= 8'd2;
			wb_ccr      <= wb_ccr_ist;   // the restart's flags: the instruction's inputs
			wb_exc_addr <= dm_st_faddr;
			wb_exc_ssw  <= dm_st_fssw;
		end
		// maintenance done: WB completes next cycle; PTEST sets MMUSR; a
		// push of CPUSH's that ended in TEA is an access error (7.6.1)
		if (wb_v && wb_mt && mt_done) begin
			mt_seen <= 1'b1;
			if (wb_u.cond == 4'd5) mmusr_r <= mt_mmusr;
			if (mt_fault && wb_exc == 8'd0) begin
				wb_stv      <= 1'b0;
				wb_ok       <= 1'b0;
				wb_exc      <= 8'd2;
				wb_exc_addr <= mt_faddr;
				wb_exc_ssw  <= mt_fssw;
			end
		end
		if (adv_wb) mt_seen <= 1'b0;

		// RESET instruction: RSTO for 512 bus clocks, WB waits
		if (wb_v && wb_reset && !rst_issued && !wb_is_exc) rst_issued <= 1'b1;
		if (dbl_fault) halted <= 1'b1;
		if (adv_wb) rst_issued <= 1'b0;

		//------------------------------------------------------------------
		// flush: kill every stage (the redirecting/excepting uop has left)
		//------------------------------------------------------------------
		if (flush) begin
			ag_v <= 1'b0; dc1_v <= 1'b0; dc2_v <= 1'b0; ex_v <= 1'b0; wb_v <= 1'b0;
			eredir_pend <= 1'b0;
		end
		else begin
			// D2 (or the skid) -> AG
			if (!stall_ag) ag_v <= ain_v && !stopped && !halted;
			if (ag_take && ain_v) begin
				ag_u      <= ain_u;
				ag_ld     = 1'b1;
				ag_u.disp <= ain_u.dmv ? ain_u.disp + {{24{ain_u.dma[7]}}, ain_u.dma} : ain_u.disp;
			end
			// the skid: emptied when AG takes it; filled by a popped uop AG
			// did not take
			if (sk_v) begin
				if (ag_take) begin sk_v <= 1'b0; sk_vr <= 1'b0; end
			end
			else if (SKID && in_v && in_rdy && !ag_take) begin
				sk_v  <= 1'b1;
				sk_vr <= 1'b1;
				sk_u  <= in_u;
			end
		end
		if (flush || kill_now) begin sk_v <= 1'b0; sk_vr <= 1'b0; end
		if (kill_now) begin
			ag_v <= 1'b0; dc1_v <= 1'b0; dc2_v <= 1'b0; ex_v <= 1'b0; wb_v <= 1'b0;
		end
	end
	cm_hit_q <= cm_rst ? ((ag_ld ? ain_u.pc : ag_u.pc) == 32'd0) :
	            ag_ld  ? (cm_wr ? (ain_u.pc == wb_next) : (ain_u.pc == cm_pc)) :
	                     (cm_wr ? (ag_u.pc  == wb_next) : (ag_u.pc  == cm_pc));
end
// synthesis translate_off
always_ff @(posedge clk)
	if (nreset && cm_hit_q != (ag_u.pc == cm_pc)) begin
		$display("FAIL: the registered MOVEM continuation compare %b, the PCs' %b", cm_hit_q, ag_u.pc == cm_pc);
		$finish;
	end
// synthesis translate_on

assign dm_st_v    = wb_v && wb_stv;
// synthesis translate_off
always_ff @(posedge clk)
	if (nreset && wb_v && (wb_stv != (wb_st && wb_exc == 8'd0) || wb_ok != (wb_exc == 8'd0))) begin
		$display("FAIL: wb_stv %b, the store %b with exception %0d (pc %h)", wb_stv, wb_st, wb_exc, wb_u.pc);
		$finish;
	end
// synthesis translate_on
assign iack_lvl   = irq_lvl_r;
assign rsto_req   = wb_v && wb_reset && !rst_issued && !wb_is_exc;
assign dm_st_data = wb_st_data;
assign dbg_pc     = DEBUG ? wb_u.pc : 32'd0;
// (an interrupt's event waits for its IACK, which resolves the vector --
// autovector, supplied, or spurious 24 -- and carries the PC stacked at
// its entry)
logic        dbg_ig;
logic  [7:0] dbg_iv;
logic [31:0] dbg_ip, dbg_ipc;
wire         dbg_xirq = DEBUG && x_go && take_irq && !(adv_wb && wb_is_exc);
always_ff @(posedge clk) begin
	dbg_ig <= 1'b0;
	if (dbg_xirq) dbg_ip <= x_pc;
	if (DEBUG && adv_ex && ex_u.op == OP_IACKV && !ex_u.cond[0]) begin
		dbg_ig  <= 1'b1;
		dbg_iv  <= ex_av[9] ? 8'd24 : ex_av[8] ? (8'd24 + {5'd0, irq_lvl_r}) : ex_av[7:0];
		dbg_ipc <= dbg_ip;
	end
end
// the handler fetch of an exception routine (its last uop: the vector
// load, the branch to its data) as it leaves EX
assign dbg_hfgo   = DEBUG && adv_ex && ex_u.br == BR_A && ex_u.op == OP_MOV && ex_u.cond == 4'hF;
assign dbg_hfld   = DEBUG ? ex_ld : 32'd0;
assign dbg_hfa    = DEBUG ? ex_a : 32'd0;
assign dbg_hff    = DEBUG ? {ex_u.a_src, ex_ldj, 5'd0} : 8'd0;
assign dbg_hfpc   = DEBUG ? ex_u.pc : 32'd0;
assign dbg_xgo    = DEBUG && ((x_go && !dbg_xirq) || dbg_ig);
assign dbg_xvec   = !DEBUG ? 8'd0 : dbg_ig ? dbg_iv  : x_vec;
assign dbg_xpc    = !DEBUG ? 32'd0 : dbg_ig ? dbg_ipc : x_pc;
assign ucond      = 1'b0;

// processor status (MC68040UM 5.9.1, table 5-6): the end of an instruction
// (branch taken / not taken / other) for one bus clock, else the present
// status.  An exception's stacking (from its entry to the routine's last
// uop) ends as a virtual JMP: supervisor, branch taken.
always_ff @(posedge clk) begin
	if (!nreset) xstk <= 1'b1;               // reset processing
	else if (x_go) xstk <= 1'b1;
	else if (adv_wb && wb_u.last) xstk <= 1'b0;
end
// the handler's first instruction: from the routine's end to that
// instruction's completion (a refetch of it is no completion)
always_ff @(posedge clk) begin
	if (!nreset || x_go || halted) x_first <= 1'b0;
	else if (adv_wb && wb_u.last && xstk) x_first <= 1'b1;
	else if (wb_bound || (adv_wb && wb_is_exc && !wb_refetch)) x_first <= 1'b0;
end
always_ff @(posedge clk)
	if (!nreset) xr_dbl <= 1'b1;             // (reset's routine)
	else if (x_go) xr_dbl <= (x_vec == 8'd2 || x_vec == 8'd3);
// IPEND: a request beats the mask; it negates once the interrupt is
// recognized internally (7.8.1: "can precede the external interrupt
// acknowledge bus cycle")
assign irq_pending = irq_pend;
// no instruction fetch from the moment STOP or RESET is at WB (no fetch
// cycle may run with RSTO asserted), while stopped, or halted
assign fetch_stop  = stopped || halted || (wb_v && (wb_is_stop || wb_reset));
assign pst_ev   = adv_wb && wb_u.last && !wb_is_exc;
assign pst_code = xstk ? 4'hB :
                  {sr_r[13], 1'b0,
                   (wb_cof || wb_redir) ? 2'b11 :
                   ((wb_u.op == OP_BCC || wb_u.op == OP_DBCC) ? 2'b10 : 2'b01)};
assign pst_st   = halted ? 4'h5 : stopped ? 4'hD : xstk ? 4'hF :
                  (wb_v && wb_u.op == OP_RTE) ? 4'hE :
                  tw_busy ? {sr_r[13], 3'b100} : {sr_r[13], 3'b000};

// AG's base and index registers: loaded with the incoming uop (with the
// front-file writes of that cycle bypassed in), then following EX's
// writes while AG holds (an interlocked base or index is written there)
always_ff @(posedge clk) begin
	// a captured EX writer stays captured while it is in EX
	if (adv_ex) begin cap_b <= 1'b0; cap_x <= 1'b0; end
	if (!flush && !stall_ag && ain_v && !stopped) begin
		logic [31:0] b, x;
		logic        cb, cx, eb, ex;
		logic  [3:0] wb, wx;
		b = rrd[0];
		x = rrd[1];
		cb = 1'b0;
		cx = 1'b0;
		eb = 1'b0;
		ex = 1'b0;
		// (AG's own updates: here AG advances, so fwe[0..1] is just whether
		// it holds one -- adv_ag, the end of the stall chain, stays off the
		// data select)
		for (int i = 0; i < 2; i++) begin
			if (fwe_ag[i] && fwa[i] == ain_u.base) b = fwd[i];
			if (fwe_ag[i] && fwa[i] == ain_u.idx)  x = fwd[i];
		end
		// the load entering EX, unless a younger writer is in AG or DC1
		// (it will be waited for in any case)
		if (dc2_capd && dc2_u.d_reg == ain_u.base) begin b = dc2_capv; cb = adv_dc2; end
		if (dc2_capd && dc2_u.d_reg == ain_u.idx)  begin x = dc2_capv; cx = adv_dc2; end
		// the youngest writer's early result (not the uop leaving AG:
		// its result is loaded next cycle)
		wb = yw(ain_u.base);
		wx = yw(ain_u.idx);
		if (!(ag_v && ag_u.d_v && ag_u.d_reg == ain_u.base) && wb[2]) begin
			b = ywv(wb[1:0]); eb = 1'b1; cb = 1'b0;
		end
		if (!(ag_v && ag_u.d_v && ag_u.d_reg == ain_u.idx) && wx[2]) begin
			ex = 1'b1; cx = 1'b0;
		end
		agb_q <= ain_u.base_v ? b : 32'd0;
		// EX writing it this cycle: the register file read is a cycle
		// early (unless a younger load or early result supplied it)
		stale_b <= exw_ag && ain_u.base_v && exw_reg == ain_u.base && !cb && !eb;
		stale_x <= exw_ag && ain_u.idx_v  && exw_reg == ain_u.idx  && !cx && !ex;
		// (the early results are scaled beside the writer search)
		agx_q <= !ex ? ixf(x, ain_u) :
		         (wx[1:0] == 2'd1) ? ixf(dc1_er, ain_u) :
		         (wx[1:0] == 2'd2) ? ixf(dc2_er, ain_u) : ixf(ex_er, ain_u);
		cap_b <= cb;
		cap_x <= cx;
		erb   <= eb;
		erx   <= ex;
	end
	else if (ag_v) begin
		if (yw_b[2]) begin
			if (ag_u.base_v) agb_q <= ywv(yw_b[1:0]);
			erb <= 1'b1;
			stale_b <= 1'b0;
		end
		else begin
			// (an older writer's value is overwritten in time by the
			// youngest's: AG keeps waiting for it)
			if (stale_b && ag_u.base_v) agb_q <= exq_val;
			// (not when the load leaving DC2 is captured this cycle: it is
			// younger than the EX writer, and reloading exq_val next cycle
			// would put that older value back over it -- a JSR (An) took
			// the previous MOVEA's address after a snoop freeze held the
			// older MOVEA in EX until its successor caught up)
			stale_b <= exw_ag && ag_u.base_v && exw_reg == ag_u.base && !cap_b &&
			           !(dc2_capd && dc2_u.d_reg == ag_u.base && adv_dc2);
			if (dc2_capd && ag_u.base_v && dc2_u.d_reg == ag_u.base) begin
				agb_q <= dc2_capv;
				if (adv_dc2) cap_b <= 1'b1;
			end
		end
		if (yw_x[2]) begin
			stale_x <= 1'b0;
			agx_q <= (yw_x[1:0] == 2'd1) ? ixf(dc1_er, ag_u) :
			         (yw_x[1:0] == 2'd2) ? ixf(dc2_er, ag_u) : ixf(ex_er, ag_u);
			erx <= 1'b1;
		end
		else begin
			if (stale_x) agx_q <= ixf(exq_val, ag_u);
			stale_x <= exw_ag && ag_u.idx_v && exw_reg == ag_u.idx && !cap_x &&
			           !(dc2_capd && dc2_u.d_reg == ag_u.idx && adv_dc2);
			if (dc2_capd && dc2_u.d_reg == ag_u.idx) begin
				agx_q <= ixf(dc2_capv, ag_u);
				if (adv_dc2) cap_x <= 1'b1;
			end
		end
	end
	exq_val <= exw_val;
	if (flush || !nreset) begin
		cap_b <= 1'b0; cap_x <= 1'b0; erb <= 1'b0; erx <= 1'b0;
		stale_b <= 1'b0; stale_x <= 1'b0;
	end
end

endmodule
// ---- ap68040_biu.sv ----
//--------------------------------------------------------------------------//
// AP68040 - pipelined MC68040                                               //
//                                                                          //
// ap68040_biu.sv - bus interface unit (MC68040UM section 7)                 //
//                                                                          //
// Runs one internal transaction at a time on the 68040 bus:                //
//   * byte/word/long transfers (the requester has already split a          //
//     misaligned operand into aligned pieces, 7.3)                         //
//   * line transfers as a burst; TBI on the first beat falls back to       //
//     three long-word transfers (7.4.2, 7.4.4); A3:A2 of a burst are       //
//     incremented by the slave and wrap inside the line                   //
//   * TA+TEA retry of a byte/word/long transfer and of the first beat of  //
//     a line; a retry on a later beat is a bus error (7.6.2).  A retry    //
//     with BG negated gives the bus up first and reruns the transfer once //
//     the bus is back (7.6.2, figure 7-33); a locked sequence keeps the   //
//     bus through its retries (7.6.2)                                      //
//   * TEA bus error, reported with the beat it hit (7.6.1)                //
//   * locked sequences (7.4.1): LOCK from the first locked transfer to    //
//     the end of the LOCKE transfer, the arbiter staying with the locking //
//     requester; a bus error on a locked transfer, or the processor       //
//     abandoning the sequence (unlock: an exception), ends it             //
//   * bus arbitration BR/BG/BB (7.8): BR is asserted while an internal    //
//     request is pending and negated as the last one needed starts        //
//     (7.8.1); ownership is taken when BG is asserted and BB is free; a   //
//     negated BG gives the bus up at the end of the transfer in progress, //
//     unless a locked sequence is open                                     //
//   * RSTO for 512 bus clocks (RESET instruction, 7.10), from the end of  //
//     the transfer in progress                                            //
//   * a halted processor (double bus fault, 8.2.1) starts no bus cycle:   //
//     a retry waiting then ends in error, and BR is negated (7.6.2)       //
//                                                                          //
// Every bus output is a flip-flop that changes only in a clk cycle with    //
// bclk_en high; inputs are sampled only in such cycles.                    //
//                                                                          //
// Requester interface (per client c):                                      //
//   req[c]      level; breq[c] must be stable while req[c] is high and    //
//               gnt[c] has not pulsed; wdata[c] from the request until    //
//               done[c] or err[c] (the BIU drives the bus from it)         //
//   gnt[c]      pulse: the transaction is latched, req may drop or change  //
//   rvalid      pulse per read beat for the client in rclient; rdata,      //
//               rbeat (A3:A2 of the long word), avec (AVEC with TA)        //
//   done[c]     pulse: transaction finished without error                  //
//   err[c]      pulse: transaction ended with a bus error; errbeat says    //
//               which long word of a line (0 = the first transferred)      //
//   tci         TCI sampled with the first beat, valid with the first      //
//               rvalid                                                     //
//   more[c]     another transfer of the client waits behind this one (BR) //
//   drop[c]     a retry waiting for the bus is not wanted any more (a     //
//               push whose line a snoop took): done, not rerun            //
// Line write data: wdata[c][127:96] is the long word at A3:A2 = 0, ...,    //
// wdata[c][31:0] at A3:A2 = 3.  Single writes take wdata[c][31:0] already  //
// placed on the byte lanes D31-D0.                                         //
//--------------------------------------------------------------------------//

module ap68040_biu
	import ap68040_pkg::*;
#(
	parameter int NC = 3            // number of requesters, 0 = highest priority
)
(
	input  logic              clk,
	input  logic              nreset,
	input  logic              bclk_en,

	// requesters
	input  logic [NC-1:0]     req,
	input  busreq_t           breq   [NC],
	input  logic [127:0]      wdata  [NC],
	output logic [NC-1:0]     gnt,
	output logic [NC-1:0]     done,
	output logic [NC-1:0]     err,
	output logic              rvalid,
	output logic [$clog2(NC)-1:0] rclient,
	output logic [31:0]       rdata,
	output logic  [1:0]       rbeat,
	output logic              ravec,
	output logic              rtci,
	output logic  [1:0]       errbeat,
	output logic              idle,     // no transaction latched or running
	output logic              own,      // we are the bus master (BB ours)

	input  logic              unlock,   // the processor abandons an open locked sequence
	input  logic              halt,     // the processor halted: no bus cycle, BR negated
	input  logic [NC-1:0]     more,     // another transfer of the client waits behind this one
	input  logic [NC-1:0]     drop,     // a retry waiting for the bus is not wanted any more

	// RESET instruction
	input  logic              rsto_req,  // pulse
	output logic              rsto_busy, // RSTO asserted, or waiting for the transfer to end

	// 68040 bus
	output logic [31:0]       a_o,
	output logic              a_oe,
	input  logic [31:0]       d_i,
	output logic [31:0]       d_o,
	output logic              d_oe,
	output logic              rw_n,
	output logic  [1:0]       siz,
	output logic  [1:0]       tt,
	output logic  [2:0]       tm,
	output logic  [1:0]       tln,
	output logic  [1:0]       upa,
	output logic              ciout_n,
	output logic              lock_n,
	output logic              locke_n,
	output logic              ts_n,
	output logic              tip_n,
	input  logic              ta_n,
	input  logic              tea_n,
	input  logic              tci_n,
	input  logic              tbi_n,
	input  logic              avec_n,
	output logic              br_n,
	input  logic              bg_n,
	input  logic              bb_n_i,
	output logic              bb_n_o,
	output logic              bb_oe,
	output logic              rsto_n
);

localparam int CW = (NC > 1) ? $clog2(NC) : 1;

typedef enum logic [2:0] {
	S_IDLE,     // owner (or not), no transfer
	S_C1,       // TS asserted this bus clock
	S_DATA,     // waiting for TA/TEA, burst beats
	S_GAP,      // a burst-inhibited line restarts the next long word
	S_RETRY     // a retry with the bus given up: rerun once it is back
} state_t;

state_t      st;
busreq_t     cur;
logic [CW-1:0] cur_c;
wire  [127:0] cur_wd = wdata[cur_c];   // stable until done/err (contract)
logic  [1:0] beat;        // beats completed so far in a line
logic        inhibited;   // line continued as long-word transfers
logic        owner;       // we hold BB
logic        locked;      // a locked sequence is open
logic [CW-1:0] lock_c;

//--------------------------------------------------------------------------
// arbitration among requesters: fixed priority, except that an open locked
// sequence belongs to its requester alone
//--------------------------------------------------------------------------
logic          pick_v;
logic [CW-1:0] pick_c;
always_comb begin
	pick_v = 1'b0;
	pick_c = '0;
	if (locked) begin
		pick_v = req[lock_c];
		pick_c = lock_c;
	end
	else begin
		for (int i = NC - 1; i >= 0; i--)
			if (req[i]) begin
				pick_v = 1'b1;
				pick_c = CW'(i);
			end
	end
end

// long-word data for beat number n of the latched line (address order)
function automatic logic [31:0] line_word(input logic [127:0] w, input logic [1:0] a32);
	case (a32)
		2'd0: line_word = w[127:96];
		2'd1: line_word = w[95:64];
		2'd2: line_word = w[63:32];
		default: line_word = w[31:0];
	endcase
endfunction

wire  [1:0] cur_a32  = cur.addr[3:2] + beat;   // long word now on the bus
wire        is_line  = (cur.siz == SIZ_LINE);
wire        first    = (beat == 2'd0) && !inhibited;
wire        ta       = !ta_n;
wire        tea      = !tea_n;
// the termination this bus clock (table 7-5): TA normal, TEA bus error,
// TA with TEA a retry (a bus error after the first beat of a line)
wire        t_err    = tea && !(ta && first);
wire        t_retry  = tea && ta && first;
wire        t_ok     = ta && !tea;

// keep the bus: BG asserted, or a locked sequence open (it keeps the bus
// through its retries too, 7.6.2)
wire        keep_bus = !bg_n || locked;
// ownership: already ours and kept, or BG asserted and the bus free
wire        can_own  = (owner && keep_bus) || (!bg_n && bb_n_i);

logic [9:0] rsto_cnt;
logic       rsto_pend;   // RESET: RSTO once the transfer in progress ends
logic       unlock_pend;

always_ff @(posedge clk) begin
	gnt    <= '0;
	done   <= '0;
	err    <= '0;
	rvalid <= 1'b0;

	if (!nreset) begin
		st        <= S_IDLE;
		cur       <= '0;
		cur_c     <= '0;
		beat      <= 2'd0;
		inhibited <= 1'b0;
		owner     <= 1'b0;
		locked    <= 1'b0;
		lock_c    <= '0;
		rclient   <= '0;
		rdata     <= '0;
		rbeat     <= 2'd0;
		ravec     <= 1'b0;
		rtci      <= 1'b0;
		errbeat   <= 2'd0;
		a_o       <= '0;
		a_oe      <= 1'b0;
		d_o       <= '0;
		d_oe      <= 1'b0;
		rw_n      <= 1'b1;
		siz       <= 2'd0;
		tt        <= 2'd0;
		tm        <= 3'd0;
		tln       <= 2'd0;
		upa       <= 2'd0;
		ciout_n   <= 1'b1;
		lock_n    <= 1'b1;
		locke_n   <= 1'b1;
		ts_n      <= 1'b1;
		tip_n     <= 1'b1;
		br_n      <= 1'b1;
		bb_n_o    <= 1'b1;
		bb_oe     <= 1'b0;
		rsto_n    <= 1'b1;
		rsto_cnt  <= '0;
		rsto_pend <= 1'b0;
		unlock_pend <= 1'b0;
	end
	else begin
		if (rsto_req) rsto_pend <= 1'b1;
		if (unlock) unlock_pend <= 1'b1;
		if ((unlock || unlock_pend) && (st == S_IDLE || st == S_RETRY)) begin
			// an abandoned locked sequence: LOCK and LOCKE go too (the pins
			// change on a bus clock edge: wait for one)
			locked      <= 1'b0;
			unlock_pend <= 1'b0;
			if (bclk_en) begin lock_n <= 1'b1; locke_n <= 1'b1; end
			else unlock_pend <= 1'b1;
		end
		if (bclk_en) begin
			logic start, lk_now;
			start  = 1'b0;
			// the sequence stays open for a transfer starting now unless the
			// processor has just abandoned it
			lk_now = locked && !unlock && !unlock_pend;

			// RESET instruction: RSTO for 512 bus clocks
			if (rsto_cnt != 0) begin
				rsto_cnt <= rsto_cnt - 1'd1;
				if (rsto_cnt == 10'd1) rsto_n <= 1'b1;
			end

			case (st)
			S_IDLE, S_RETRY: begin
				ts_n <= 1'b1;
				if (st == S_RETRY && drop[cur_c]) begin
					st <= S_IDLE;
					done[cur_c] <= 1'b1;
					finish_cycle();
				end
				else if (st == S_RETRY && halt) begin
					// halted: no bus cycle is rerun
					st <= S_IDLE;
					err[cur_c] <= 1'b1;
					errbeat    <= 2'd0;
					finish_cycle();
				end
				else if ((pick_v || st == S_RETRY) && !halt && can_own) begin
					start = 1'b1;
					if (st == S_IDLE) begin
						cur   <= breq[pick_c];
						cur_c <= pick_c;
						gnt[pick_c] <= 1'b1;
						// a locked transfer opens or continues the sequence;
						// the LOCKE transfer keeps it until it terminates
						// normally (finish_cycle), so its retry holds the bus
						if (breq[pick_c].lock) begin
							locked <= 1'b1;
							lock_c <= pick_c;
						end
					end
				end
				else begin
					tip_n <= 1'b1;
					d_oe  <= 1'b0;
					// keep driving the bus only while we own it: BB is driven
					// negated for one bus clock, then released with the rest
					if (owner && (!keep_bus || halt)) begin
						owner  <= 1'b0;
						bb_n_o <= 1'b1;
					end
					else if (!owner) begin
						bb_oe <= 1'b0;
						a_oe  <= 1'b0;
					end
				end
			end

			S_C1: begin
				ts_n <= 1'b1;
				st   <= S_DATA;
			end

			S_GAP: begin
				// next long word of a burst-inhibited line
				a_o   <= {cur.addr[31:4], cur_a32, cur.addr[1:0]};
				siz   <= SIZ_L;
				d_o   <= line_word(cur_wd, cur_a32);
				ts_n  <= 1'b0;
				tip_n <= 1'b0;
				st    <= S_C1;
			end

			S_DATA: begin
				if (t_err) begin
					err[cur_c] <= 1'b1;
					errbeat    <= beat;
					// a bus error on a locked transfer ends the sequence: the
					// requester takes an access error and will not complete it
					if (cur.lock) begin
						locked  <= 1'b0;
						lock_n  <= 1'b1;
						locke_n <= 1'b1;
					end
					d_oe       <= 1'b0;
					st         <= S_IDLE;
					finish_cycle();
				end
				else if (t_retry) begin
					// rerun the transfer from its start; with BG negated (and
					// no locked sequence open) the bus goes first.  A halted
					// processor starts no bus cycle: the transfer ends in
					// error instead (a prefetch nobody uses)
					if (halt) begin
						err[cur_c] <= 1'b1;
						errbeat    <= beat;
						d_oe       <= 1'b0;
						st         <= S_IDLE;
						finish_cycle();
					end
					else if (!keep_bus) begin
						d_oe <= 1'b0;
						st   <= S_RETRY;
					end
					else begin
						a_o   <= cur.addr;
						d_o   <= (cur.siz == SIZ_LINE) ? line_word(cur_wd, cur.addr[3:2]) : cur_wd[31:0];
						ts_n  <= 1'b0;
						st    <= S_C1;
					end
				end
				else if (t_ok) begin
					if (cur.rd) begin
						rvalid  <= 1'b1;
						rclient <= cur_c;
						rdata   <= d_i;
						rbeat   <= cur_a32;
						ravec   <= !avec_n;
						if (beat == 2'd0 && !inhibited) rtci <= !tci_n;
					end
					if (!is_line || beat == 2'd3) begin
						done[cur_c] <= 1'b1;
						d_oe <= 1'b0;
						st   <= S_IDLE;
						finish_cycle();
					end
					else begin
						beat <= beat + 1'd1;
						if ((beat == 2'd0 && !inhibited && !tbi_n) || inhibited) begin
							// TBI with the first TA: the rest as long-word
							// transfers (7.4.2, 7.4.4)
							inhibited <= 1'b1;
							st        <= S_GAP;
						end
						else begin
							// burst: the slave advances A3:A2
							d_o <= line_word(cur_wd, cur_a32 + 2'd1);
						end
					end
				end
			end

			default: st <= S_IDLE;
			endcase

			if (start) begin
				// drive the transfer (S_IDLE: the request picked; S_RETRY: cur)
				busreq_t r;
				logic [127:0] w;
				r = (st == S_RETRY) ? cur : breq[pick_c];
				w = (st == S_RETRY) ? cur_wd : wdata[pick_c];
				owner     <= 1'b1;
				bb_n_o    <= 1'b0;
				bb_oe     <= 1'b1;
				beat      <= 2'd0;
				inhibited <= 1'b0;
				a_o       <= r.addr;
				a_oe      <= 1'b1;
				rw_n      <= r.rd;
				siz       <= r.siz;
				tt        <= r.tt;
				tm        <= r.tm;
				tln       <= r.tln;
				upa       <= r.upa;
				// (an acknowledge cycle -- interrupt, breakpoint -- has CIOUT
				// negated, 7.5.1, 7.5.2)
				ciout_n   <= !r.ci || (r.tt == TT_ACK);
				lock_n    <= !(r.lock || lk_now);
				locke_n   <= !(r.lock && r.locke);
				d_o       <= (r.siz == SIZ_LINE) ? line_word(w, r.addr[3:2]) : w[31:0];
				d_oe      <= !r.rd;
				ts_n      <= 1'b0;
				tip_n     <= 1'b0;
				st        <= S_C1;
			end

			// RESET: RSTO once no transfer is in progress or starting (the
			// fetch is held from the request on)
			if (rsto_pend && st == S_IDLE && !start) begin
				rsto_pend <= 1'b0;
				rsto_n    <= 1'b0;
				rsto_cnt  <= 10'd512;
			end

			// BR (7.8.1): asserted while an internal request waits to start,
			// whoever owns the bus, and negated with the TS of the last one
			// needed; negated while halted
			begin
				logic [NC-1:0] pend;
				pend = (req & ~gnt) | more;      // (a request lasts a clock past its grant)
				if (start && st == S_IDLE) pend[pick_c] = 1'b0;
				br_n <= halt || !((|pend) || (st == S_RETRY && !start && !drop[cur_c]));
			end
		end
	end
end

// a transfer ended (normally or with a bus error): LOCK/LOCKE negate after
// the LOCKE transfer
task automatic finish_cycle();
	if (cur.lock && cur.locke) begin
		locked  <= 1'b0;
		lock_n  <= 1'b1;
		locke_n <= 1'b1;
	end
endtask

assign idle      = (st == S_IDLE);
assign own       = owner;
assign rsto_busy = !rsto_n || rsto_pend;

endmodule
// ---- ap68040_decode.sv ----
//--------------------------------------------------------------------------//
// AP68040 - pipelined MC68040                                            //
//                                                                          //
// ap68040_decode.sv - D1: instruction parse                                 //
//                                                                          //
//   operation word | fixed extension words | immediate | EA0 ext | EA1 ext //
//                                                                          //
// Fast path: one instruction per cycle.  The queue's predecode of slot 0  //
// gives the length assuming brief index extensions; D1 only checks bit 8  //
// of the words at the index extension positions.  Slow path (a full-      //
// format extension, an FPU immediate, or more than seven words): one      //
// phase per part -- operation word with fixed words and immediate, then   //
// EA0's extension, then EA1's -- each sized from the word at the head.    //
//                                                                          //
// Records go to D2 through a two-entry FIFO, so neither side depends on   //
// the other combinationally.  PC-relative displacements, branch targets   //
// and the next PC are added here.  Branches are predicted here (Bcc by    //
// the static rule and a history table, JSR/JMP absolute and PC-relative,  //
// RTS by a return stack) and redirect fetch, unless the fetch BTB already //
// took the same branch; D1 checks every word the BTB flagged.  Illegal,  //
// line A/F, privilege, TRAP #n, odd PC and fetch faults become records    //
// carrying their exception vector.                                        //
//--------------------------------------------------------------------------//

module ap68040_decode
	import ap68040_pkg::*, ap68040_upkg::*;
#(
	parameter bit LOOP_PRED = 1          // the loop exit predictor
)
(
	input  logic        clk,
	input  logic        nreset,
	input  logic        flush,          // back end redirect: drop everything
	input  logic        ras_rv,         // ... with the return stack to restore
	input  logic  [2:0] ras_rtp,
	input  logic  [3:0] ras_rn,

	input  logic [15:0] win [8],
	input  logic  [7:0] win_flt,
	input  logic  [7:0] win_fdem,     // the faulted fetch was a demand fetch
	input  logic  [7:0] win_fatc,     // ... an ATC (MMU) fault
	input  logic  [7:0] win_bt,       // the word ends a branch the fetch BTB took
	input  logic [31:0] bt_tgt,       // its target (the first flagged word's)
	input  pd_t         pd0,
	input  pd_t         pd0_n,         // pd0 next cycle (the attribute ROM's address)
	input  logic  [3:0] qcnt,
	input  logic [31:0] qpc,
	input  logic        q_odd,
	input  logic        smode,

	output logic  [2:0] consume,
	output logic        d_redir_v,
	output logic [31:0] d_redir_pc,

	// record FIFO towards D2: rq0 is the head
	output logic  [1:0] rq_n,
	output dinst_t      rq0,
	output dinst_t      rq1,
	input  logic        rq_pop,
	input  logic        rq_pop_e,       // implies rq_pop, early (room)

	// Bcc history training (from EX)
	input  logic        bht_we,
	input  logic  [7:0] bht_wa,
	input  logic        bht_dis,        // ... the branch went against the static rule
	// loop exit training (from EX): a backward Bcc/DBcc, taken or not
	input  logic        lp_we,
	input  logic [11:0] lp_wa,
	input  logic        lp_tk,
	input  logic        lp_mp,          // ... and it was mispredicted

	// BTB maintenance (the fetch unit's table)
	output logic        btb_we,
	output logic [BTB_AW-1:0] btb_wi,
	output logic        btb_wv,
	output logic [BTB_TW-1:0] btb_wtag,
	output logic        btb_wslot,
	output logic  [1:0] btb_wkind,
	output logic [30:0] btb_wtgt,
	output logic [30:0] ras_o,        // the return stack's top, for the fetch's
	output logic  [2:0] ras_tp_o,
	output logic  [3:0] ras_n_o
);

// ---- inlined from ap68040_dec_pla.svh (tools/import_ap68040.py) ----
// generated by tools/ucode.py - do not edit
// Operation word decoder: every pattern is matched in parallel and
// excluded by the more specific patterns overlapping it, so exactly
// one entry (or none) is selected; attributes are OR trees.
localparam int NENT = 276;
typedef struct packed {
	logic match;
	logic [8:0] ent;
	logic [9:0] rt;
	logic [6:0] eop;
	logic [3:0] econd;
	logic econd_v;
	logic [4:0] ccr;
	logic [1:0] szc;
	logic [11:0] ea0m;
	logic [11:0] ea1m;
	logic [1:0] nfix;
	logic [2:0] immk;
	logic priv;
	logic [5:0] jc0;
	logic [9:0] jt0;
	logic ea0v;
	logic ea1v;
	logic [1:0] fea;
	logic t0;
} pla_t;
function automatic logic [NENT-1:0] dec_sel(input logic [15:0] op);
	logic [NENT-1:0] m, s;
	m[0] = ((op & 16'hffc0) == 16'h0000) && (op[7:6] != 2'b11);  // OR IMM_OP
	m[1] = ((op & 16'hffc0) == 16'h0200) && (op[7:6] != 2'b11);  // AND IMM_OP
	m[2] = ((op & 16'hffc0) == 16'h0400) && (op[7:6] != 2'b11);  // SUB IMM_OP
	m[3] = ((op & 16'hffc0) == 16'h0600) && (op[7:6] != 2'b11);  // ADD IMM_OP
	m[4] = ((op & 16'hffc0) == 16'h0a00) && (op[7:6] != 2'b11);  // EOR IMM_OP
	m[5] = ((op & 16'hffc0) == 16'h0c00) && (op[7:6] != 2'b11);  // CMP IMM_CMP
	m[6] = ((op & 16'hffc0) == 16'h0e00) && (op[7:6] != 2'b11);  // MOVES MOVES
	m[7] = ((op & 16'hffc0) == 16'h0040) && (op[7:6] != 2'b11);  // OR IMM_OP
	m[8] = ((op & 16'hffc0) == 16'h0240) && (op[7:6] != 2'b11);  // AND IMM_OP
	m[9] = ((op & 16'hffc0) == 16'h0440) && (op[7:6] != 2'b11);  // SUB IMM_OP
	m[10] = ((op & 16'hffc0) == 16'h0640) && (op[7:6] != 2'b11);  // ADD IMM_OP
	m[11] = ((op & 16'hffc0) == 16'h0a40) && (op[7:6] != 2'b11);  // EOR IMM_OP
	m[12] = ((op & 16'hffc0) == 16'h0c40) && (op[7:6] != 2'b11);  // CMP IMM_CMP
	m[13] = ((op & 16'hffc0) == 16'h0e40) && (op[7:6] != 2'b11);  // MOVES MOVES
	m[14] = ((op & 16'hffc0) == 16'h0080) && (op[7:6] != 2'b11);  // OR IMM_OP
	m[15] = ((op & 16'hffc0) == 16'h0280) && (op[7:6] != 2'b11);  // AND IMM_OP
	m[16] = ((op & 16'hffc0) == 16'h0480) && (op[7:6] != 2'b11);  // SUB IMM_OP
	m[17] = ((op & 16'hffc0) == 16'h0680) && (op[7:6] != 2'b11);  // ADD IMM_OP
	m[18] = ((op & 16'hffc0) == 16'h0a80) && (op[7:6] != 2'b11);  // EOR IMM_OP
	m[19] = ((op & 16'hffc0) == 16'h0c80) && (op[7:6] != 2'b11);  // CMP IMM_CMP
	m[20] = ((op & 16'hffc0) == 16'h0e80) && (op[7:6] != 2'b11);  // MOVES MOVES
	m[21] = ((op & 16'hffff) == 16'h003c);  // ORSR CCR_LOG
	m[22] = ((op & 16'hffff) == 16'h007c);  // ORSR SR_LOG
	m[23] = ((op & 16'hffff) == 16'h023c);  // ANDSR CCR_LOG
	m[24] = ((op & 16'hffff) == 16'h027c);  // ANDSR SR_LOG
	m[25] = ((op & 16'hffff) == 16'h0a3c);  // EORSR CCR_LOG
	m[26] = ((op & 16'hffff) == 16'h0a7c);  // EORSR SR_LOG
	m[27] = ((op & 16'hffc0) == 16'h00c0);  // CHK2 CHK2
	m[28] = ((op & 16'hffc0) == 16'h02c0);  // CHK2 CHK2
	m[29] = ((op & 16'hffc0) == 16'h04c0);  // CHK2 CHK2
	m[30] = ((op & 16'hffc0) == 16'h0ac0);  // CAS CAS
	m[31] = ((op & 16'hffc0) == 16'h0cc0);  // CAS CAS
	m[32] = ((op & 16'hffc0) == 16'h0ec0);  // CAS CAS
	m[33] = ((op & 16'hffff) == 16'h0cfc);  // CAS2 CAS2
	m[34] = ((op & 16'hffff) == 16'h0efc);  // CAS2 CAS2
	m[35] = ((op & 16'hffc0) == 16'h0800);  // BTST BTST_IMM
	m[36] = ((op & 16'hffc0) == 16'h0840);  // BCHG BIT_IMM
	m[37] = ((op & 16'hffc0) == 16'h0880);  // BCLR BIT_IMM
	m[38] = ((op & 16'hffc0) == 16'h08c0);  // BSET BIT_IMM
	m[39] = ((op & 16'hf1c0) == 16'h0100);  // BTST BTST_DYN
	m[40] = ((op & 16'hf1c0) == 16'h0140);  // BCHG BIT_DYN
	m[41] = ((op & 16'hf1c0) == 16'h0180);  // BCLR BIT_DYN
	m[42] = ((op & 16'hf1c0) == 16'h01c0);  // BSET BIT_DYN
	m[43] = ((op & 16'hf1f8) == 16'h0108);  // MVPMR MOVEP_MR
	m[44] = ((op & 16'hf1f8) == 16'h0148);  // MVPMR MOVEP_MR
	m[45] = ((op & 16'hf1f8) == 16'h0188);  // MVPRM MOVEP_RM
	m[46] = ((op & 16'hf1f8) == 16'h01c8);  // MVPRM MOVEP_RM
	m[47] = ((op & 16'hf000) == 16'h1000);  // MOVE MOVE
	m[48] = ((op & 16'hf000) == 16'h3000);  // MOVE MOVE
	m[49] = ((op & 16'hf000) == 16'h2000);  // MOVE MOVE
	m[50] = ((op & 16'hf1c0) == 16'h3040);  // MOVEA MOVEA
	m[51] = ((op & 16'hf1c0) == 16'h2040);  // MOVEA MOVEA
	m[52] = ((op & 16'hffc0) == 16'h4000) && (op[7:6] != 2'b11);  // NEGX UNARY
	m[53] = ((op & 16'hffc0) == 16'h4200) && (op[7:6] != 2'b11);  // CLR CLR_W
	m[54] = ((op & 16'hffc0) == 16'h4400) && (op[7:6] != 2'b11);  // NEG UNARY
	m[55] = ((op & 16'hffc0) == 16'h4600) && (op[7:6] != 2'b11);  // NOT UNARY
	m[56] = ((op & 16'hffc0) == 16'h4a00) && (op[7:6] != 2'b11);  // TST TST
	m[57] = ((op & 16'hffc0) == 16'h4040) && (op[7:6] != 2'b11);  // NEGX UNARY
	m[58] = ((op & 16'hffc0) == 16'h4240) && (op[7:6] != 2'b11);  // CLR CLR_W
	m[59] = ((op & 16'hffc0) == 16'h4440) && (op[7:6] != 2'b11);  // NEG UNARY
	m[60] = ((op & 16'hffc0) == 16'h4640) && (op[7:6] != 2'b11);  // NOT UNARY
	m[61] = ((op & 16'hffc0) == 16'h4a40) && (op[7:6] != 2'b11);  // TST TST
	m[62] = ((op & 16'hffc0) == 16'h4080) && (op[7:6] != 2'b11);  // NEGX UNARY
	m[63] = ((op & 16'hffc0) == 16'h4280) && (op[7:6] != 2'b11);  // CLR CLR_W
	m[64] = ((op & 16'hffc0) == 16'h4480) && (op[7:6] != 2'b11);  // NEG UNARY
	m[65] = ((op & 16'hffc0) == 16'h4680) && (op[7:6] != 2'b11);  // NOT UNARY
	m[66] = ((op & 16'hffc0) == 16'h4a80) && (op[7:6] != 2'b11);  // TST TST
	m[67] = ((op & 16'hffc0) == 16'h40c0);  // MVSR2 MOVE_FROM_SR
	m[68] = ((op & 16'hffc0) == 16'h42c0);  // MVSR2 MOVE_FROM_CCR
	m[69] = ((op & 16'hffc0) == 16'h44c0);  // MV2SR MOVE_TO_CCR
	m[70] = ((op & 16'hffc0) == 16'h46c0);  // MV2SR MOVE_TO_SR
	m[71] = ((op & 16'hfff8) == 16'h4808);  // LINK LINK
	m[72] = ((op & 16'hffc0) == 16'h4800);  // NBCD UNARY
	m[73] = ((op & 16'hfff8) == 16'h4848);  // BKPT BKPT
	m[74] = ((op & 16'hfff8) == 16'h4840);  // SWAP SWAP
	m[75] = ((op & 16'hffc0) == 16'h4840);  // PEA PEA
	m[76] = ((op & 16'hfff8) == 16'h4880);  // EXT EXT
	m[77] = ((op & 16'hfff8) == 16'h48c0);  // EXT EXT
	m[78] = ((op & 16'hfff8) == 16'h49c0);  // EXT EXTB
	m[79] = ((op & 16'hffc0) == 16'h4880);  // MVMLE MOVEM_RM
	m[80] = ((op & 16'hffc0) == 16'h48c0);  // MVMLE MOVEM_RM
	m[81] = ((op & 16'hffc0) == 16'h4c80);  // MVMEL MOVEM_MR
	m[82] = ((op & 16'hffc0) == 16'h4cc0);  // MVMEL MOVEM_MR
	m[83] = ((op & 16'hffc0) == 16'h4ac0);  // TAS TAS
	m[84] = ((op & 16'hffff) == 16'h4afc);  // ILLG ILLEGAL
	m[85] = ((op & 16'hffc0) == 16'h4c00);  // MULL MULL
	m[86] = ((op & 16'hffc0) == 16'h4c40);  // DIVL DIVL
	m[87] = ((op & 16'hfff0) == 16'h4e40);  // TRAP TRAP
	m[88] = ((op & 16'hfff8) == 16'h4e50);  // LINK LINK
	m[89] = ((op & 16'hfff8) == 16'h4e58);  // UNLK UNLK
	m[90] = ((op & 16'hfff8) == 16'h4e60);  // MVR2USP MOVE_TO_USP
	m[91] = ((op & 16'hfff8) == 16'h4e68);  // MVUSP2R MOVE_FROM_USP
	m[92] = ((op & 16'hffff) == 16'h4e70);  // RESET RESET
	m[93] = ((op & 16'hffff) == 16'h4e71);  // NOP NOP
	m[94] = ((op & 16'hffff) == 16'h4e72);  // STOP STOP
	m[95] = ((op & 16'hffff) == 16'h4e73);  // RTE RTE
	m[96] = ((op & 16'hffff) == 16'h4e74);  // RTD RTD
	m[97] = ((op & 16'hffff) == 16'h4e75);  // RTS RTS
	m[98] = ((op & 16'hffff) == 16'h4e76);  // TRAPV TRAPV
	m[99] = ((op & 16'hffff) == 16'h4e77);  // RTR RTR
	m[100] = ((op & 16'hffff) == 16'h4e7a);  // MOVEC2 MOVEC_RD
	m[101] = ((op & 16'hffff) == 16'h4e7b);  // MOVE2C MOVEC_WR
	m[102] = ((op & 16'hffc0) == 16'h4e80);  // JSR JSR
	m[103] = ((op & 16'hffc0) == 16'h4ec0);  // JMP JMP
	m[104] = ((op & 16'hf1c0) == 16'h4100);  // CHK CHK
	m[105] = ((op & 16'hf1c0) == 16'h4180);  // CHK CHK
	m[106] = ((op & 16'hf1c0) == 16'h41c0);  // LEA LEA
	m[107] = ((op & 16'hf1c0) == 16'h5000) && (op[7:6] != 2'b11);  // ADD QUICK
	m[108] = ((op & 16'hf1c0) == 16'h5100) && (op[7:6] != 2'b11);  // SUB QUICK
	m[109] = ((op & 16'hf1c0) == 16'h5040) && (op[7:6] != 2'b11);  // ADD QUICK
	m[110] = ((op & 16'hf1c0) == 16'h5140) && (op[7:6] != 2'b11);  // SUB QUICK
	m[111] = ((op & 16'hf1c0) == 16'h5080) && (op[7:6] != 2'b11);  // ADD QUICK
	m[112] = ((op & 16'hf1c0) == 16'h5180) && (op[7:6] != 2'b11);  // SUB QUICK
	m[113] = ((op & 16'hf1f8) == 16'h5048);  // ADDA QUICK_A
	m[114] = ((op & 16'hf1f8) == 16'h5088);  // ADDA QUICK_A
	m[115] = ((op & 16'hf1f8) == 16'h5148);  // SUBA QUICK_SA
	m[116] = ((op & 16'hf1f8) == 16'h5188);  // SUBA QUICK_SA
	m[117] = ((op & 16'hf0c0) == 16'h50c0);  // Scc SCC
	m[118] = ((op & 16'hf0f8) == 16'h50c8);  // DBcc DBCC
	m[119] = ((op & 16'hf0ff) == 16'h50fa);  // TRAPcc TRAPCC
	m[120] = ((op & 16'hf0ff) == 16'h50fb);  // TRAPcc TRAPCC
	m[121] = ((op & 16'hf0ff) == 16'h50fc);  // TRAPcc TRAPCC
	m[122] = ((op & 16'hff00) == 16'h6100);  // BSR BSR
	m[123] = ((op & 16'hf000) == 16'h6000);  // Bcc BCC
	m[124] = ((op & 16'hf100) == 16'h7000);  // MOVE MOVEQ
	m[125] = ((op & 16'hf1c0) == 16'h8000) && (op[7:6] != 2'b11);  // OR OP_EA_DN
	m[126] = ((op & 16'hf1c0) == 16'h8100) && (op[7:6] != 2'b11);  // OR OP_DN_EA
	m[127] = ((op & 16'hf1c0) == 16'hc000) && (op[7:6] != 2'b11);  // AND OP_EA_DN
	m[128] = ((op & 16'hf1c0) == 16'hc100) && (op[7:6] != 2'b11);  // AND OP_DN_EA
	m[129] = ((op & 16'hf1c0) == 16'h9000) && (op[7:6] != 2'b11);  // SUB OP_EA_DN
	m[130] = ((op & 16'hf1c0) == 16'h9100) && (op[7:6] != 2'b11);  // SUB OP_DN_EA
	m[131] = ((op & 16'hf1c0) == 16'hd000) && (op[7:6] != 2'b11);  // ADD OP_EA_DN
	m[132] = ((op & 16'hf1c0) == 16'hd100) && (op[7:6] != 2'b11);  // ADD OP_DN_EA
	m[133] = ((op & 16'hf1c0) == 16'hb000) && (op[7:6] != 2'b11);  // CMP CMP_EA_DN
	m[134] = ((op & 16'hf1c0) == 16'hb100) && (op[7:6] != 2'b11);  // EOR OP_DN_EA
	m[135] = ((op & 16'hf1f8) == 16'hb108) && (op[7:6] != 2'b11);  // CMPM CMPM
	m[136] = ((op & 16'hf1f8) == 16'h9100) && (op[7:6] != 2'b11);  // SUBX ADDX_R
	m[137] = ((op & 16'hf1f8) == 16'h9108) && (op[7:6] != 2'b11);  // SUBX ADDX_M
	m[138] = ((op & 16'hf1f8) == 16'hd100) && (op[7:6] != 2'b11);  // ADDX ADDX_R
	m[139] = ((op & 16'hf1f8) == 16'hd108) && (op[7:6] != 2'b11);  // ADDX ADDX_M
	m[140] = ((op & 16'hf1c0) == 16'h8040) && (op[7:6] != 2'b11);  // OR OP_EA_DN
	m[141] = ((op & 16'hf1c0) == 16'h8140) && (op[7:6] != 2'b11);  // OR OP_DN_EA
	m[142] = ((op & 16'hf1c0) == 16'hc040) && (op[7:6] != 2'b11);  // AND OP_EA_DN
	m[143] = ((op & 16'hf1c0) == 16'hc140) && (op[7:6] != 2'b11);  // AND OP_DN_EA
	m[144] = ((op & 16'hf1c0) == 16'h9040) && (op[7:6] != 2'b11);  // SUB OP_EA_DN
	m[145] = ((op & 16'hf1c0) == 16'h9140) && (op[7:6] != 2'b11);  // SUB OP_DN_EA
	m[146] = ((op & 16'hf1c0) == 16'hd040) && (op[7:6] != 2'b11);  // ADD OP_EA_DN
	m[147] = ((op & 16'hf1c0) == 16'hd140) && (op[7:6] != 2'b11);  // ADD OP_DN_EA
	m[148] = ((op & 16'hf1c0) == 16'hb040) && (op[7:6] != 2'b11);  // CMP CMP_EA_DN
	m[149] = ((op & 16'hf1c0) == 16'hb140) && (op[7:6] != 2'b11);  // EOR OP_DN_EA
	m[150] = ((op & 16'hf1f8) == 16'hb148) && (op[7:6] != 2'b11);  // CMPM CMPM
	m[151] = ((op & 16'hf1f8) == 16'h9140) && (op[7:6] != 2'b11);  // SUBX ADDX_R
	m[152] = ((op & 16'hf1f8) == 16'h9148) && (op[7:6] != 2'b11);  // SUBX ADDX_M
	m[153] = ((op & 16'hf1f8) == 16'hd140) && (op[7:6] != 2'b11);  // ADDX ADDX_R
	m[154] = ((op & 16'hf1f8) == 16'hd148) && (op[7:6] != 2'b11);  // ADDX ADDX_M
	m[155] = ((op & 16'hf1c0) == 16'h8080) && (op[7:6] != 2'b11);  // OR OP_EA_DN
	m[156] = ((op & 16'hf1c0) == 16'h8180) && (op[7:6] != 2'b11);  // OR OP_DN_EA
	m[157] = ((op & 16'hf1c0) == 16'hc080) && (op[7:6] != 2'b11);  // AND OP_EA_DN
	m[158] = ((op & 16'hf1c0) == 16'hc180) && (op[7:6] != 2'b11);  // AND OP_DN_EA
	m[159] = ((op & 16'hf1c0) == 16'h9080) && (op[7:6] != 2'b11);  // SUB OP_EA_DN
	m[160] = ((op & 16'hf1c0) == 16'h9180) && (op[7:6] != 2'b11);  // SUB OP_DN_EA
	m[161] = ((op & 16'hf1c0) == 16'hd080) && (op[7:6] != 2'b11);  // ADD OP_EA_DN
	m[162] = ((op & 16'hf1c0) == 16'hd180) && (op[7:6] != 2'b11);  // ADD OP_DN_EA
	m[163] = ((op & 16'hf1c0) == 16'hb080) && (op[7:6] != 2'b11);  // CMP CMP_EA_DN
	m[164] = ((op & 16'hf1c0) == 16'hb180) && (op[7:6] != 2'b11);  // EOR OP_DN_EA
	m[165] = ((op & 16'hf1f8) == 16'hb188) && (op[7:6] != 2'b11);  // CMPM CMPM
	m[166] = ((op & 16'hf1f8) == 16'h9180) && (op[7:6] != 2'b11);  // SUBX ADDX_R
	m[167] = ((op & 16'hf1f8) == 16'h9188) && (op[7:6] != 2'b11);  // SUBX ADDX_M
	m[168] = ((op & 16'hf1f8) == 16'hd180) && (op[7:6] != 2'b11);  // ADDX ADDX_R
	m[169] = ((op & 16'hf1f8) == 16'hd188) && (op[7:6] != 2'b11);  // ADDX ADDX_M
	m[170] = ((op & 16'hf1c0) == 16'h80c0);  // DIVU DIVW
	m[171] = ((op & 16'hf1c0) == 16'h81c0);  // DIVS DIVW
	m[172] = ((op & 16'hf1c0) == 16'hc0c0);  // MULU MULW
	m[173] = ((op & 16'hf1c0) == 16'hc1c0);  // MULS MULW
	m[174] = ((op & 16'hf1f8) == 16'h8100);  // SBCD ADDX_R
	m[175] = ((op & 16'hf1f8) == 16'h8108);  // SBCD ADDX_M
	m[176] = ((op & 16'hf1f8) == 16'hc100);  // ABCD ADDX_R
	m[177] = ((op & 16'hf1f8) == 16'hc108);  // ABCD ADDX_M
	m[178] = ((op & 16'hf1f8) == 16'h8140);  // PACK PACK_R
	m[179] = ((op & 16'hf1f8) == 16'h8148);  // PACK PACK_M
	m[180] = ((op & 16'hf1f8) == 16'h8180);  // UNPK UNPK_R
	m[181] = ((op & 16'hf1f8) == 16'h8188);  // UNPK UNPK_M
	m[182] = ((op & 16'hf1c0) == 16'h90c0);  // SUBA SUBA
	m[183] = ((op & 16'hf1c0) == 16'h91c0);  // SUBA SUBA
	m[184] = ((op & 16'hf1c0) == 16'hd0c0);  // ADDA ADDA
	m[185] = ((op & 16'hf1c0) == 16'hd1c0);  // ADDA ADDA
	m[186] = ((op & 16'hf1c0) == 16'hb0c0);  // CMPA CMPA
	m[187] = ((op & 16'hf1c0) == 16'hb1c0);  // CMPA CMPA
	m[188] = ((op & 16'hf1f8) == 16'hc140);  // EXG EXG_DD
	m[189] = ((op & 16'hf1f8) == 16'hc148);  // EXG EXG_AA
	m[190] = ((op & 16'hf1f8) == 16'hc188);  // EXG EXG_DA
	m[191] = ((op & 16'hf1d8) == 16'he000) && (op[7:6] != 2'b11);  // ASR SHIFT_R
	m[192] = ((op & 16'hf1d8) == 16'he100) && (op[7:6] != 2'b11);  // ASL SHIFT_R
	m[193] = ((op & 16'hf1d8) == 16'he008) && (op[7:6] != 2'b11);  // LSR SHIFT_R
	m[194] = ((op & 16'hf1d8) == 16'he108) && (op[7:6] != 2'b11);  // LSL SHIFT_R
	m[195] = ((op & 16'hf1d8) == 16'he010) && (op[7:6] != 2'b11);  // ROXR SHIFT_R
	m[196] = ((op & 16'hf1d8) == 16'he110) && (op[7:6] != 2'b11);  // ROXL SHIFT_R
	m[197] = ((op & 16'hf1d8) == 16'he018) && (op[7:6] != 2'b11);  // ROR SHIFT_R
	m[198] = ((op & 16'hf1d8) == 16'he118) && (op[7:6] != 2'b11);  // ROL SHIFT_R
	m[199] = ((op & 16'hf1d8) == 16'he040) && (op[7:6] != 2'b11);  // ASR SHIFT_R
	m[200] = ((op & 16'hf1d8) == 16'he140) && (op[7:6] != 2'b11);  // ASL SHIFT_R
	m[201] = ((op & 16'hf1d8) == 16'he048) && (op[7:6] != 2'b11);  // LSR SHIFT_R
	m[202] = ((op & 16'hf1d8) == 16'he148) && (op[7:6] != 2'b11);  // LSL SHIFT_R
	m[203] = ((op & 16'hf1d8) == 16'he050) && (op[7:6] != 2'b11);  // ROXR SHIFT_R
	m[204] = ((op & 16'hf1d8) == 16'he150) && (op[7:6] != 2'b11);  // ROXL SHIFT_R
	m[205] = ((op & 16'hf1d8) == 16'he058) && (op[7:6] != 2'b11);  // ROR SHIFT_R
	m[206] = ((op & 16'hf1d8) == 16'he158) && (op[7:6] != 2'b11);  // ROL SHIFT_R
	m[207] = ((op & 16'hf1d8) == 16'he080) && (op[7:6] != 2'b11);  // ASR SHIFT_R
	m[208] = ((op & 16'hf1d8) == 16'he180) && (op[7:6] != 2'b11);  // ASL SHIFT_R
	m[209] = ((op & 16'hf1d8) == 16'he088) && (op[7:6] != 2'b11);  // LSR SHIFT_R
	m[210] = ((op & 16'hf1d8) == 16'he188) && (op[7:6] != 2'b11);  // LSL SHIFT_R
	m[211] = ((op & 16'hf1d8) == 16'he090) && (op[7:6] != 2'b11);  // ROXR SHIFT_R
	m[212] = ((op & 16'hf1d8) == 16'he190) && (op[7:6] != 2'b11);  // ROXL SHIFT_R
	m[213] = ((op & 16'hf1d8) == 16'he098) && (op[7:6] != 2'b11);  // ROR SHIFT_R
	m[214] = ((op & 16'hf1d8) == 16'he198) && (op[7:6] != 2'b11);  // ROL SHIFT_R
	m[215] = ((op & 16'hffc0) == 16'he0c0);  // ASRW SHIFT_M
	m[216] = ((op & 16'hffc0) == 16'he1c0);  // ASLW SHIFT_M
	m[217] = ((op & 16'hffc0) == 16'he2c0);  // LSRW SHIFT_M
	m[218] = ((op & 16'hffc0) == 16'he3c0);  // LSLW SHIFT_M
	m[219] = ((op & 16'hffc0) == 16'he4c0);  // ROXRW SHIFT_M
	m[220] = ((op & 16'hffc0) == 16'he5c0);  // ROXLW SHIFT_M
	m[221] = ((op & 16'hffc0) == 16'he6c0);  // RORW SHIFT_M
	m[222] = ((op & 16'hffc0) == 16'he7c0);  // ROLW SHIFT_M
	m[223] = ((op & 16'hffc0) == 16'he8c0);  // BFTST BF_TST
	m[224] = ((op & 16'hffc0) == 16'he9c0);  // BFEXTU BF_EXT
	m[225] = ((op & 16'hffc0) == 16'heac0);  // BFCHG BF_MOD
	m[226] = ((op & 16'hffc0) == 16'hebc0);  // BFEXTS BF_EXT
	m[227] = ((op & 16'hffc0) == 16'hecc0);  // BFCLR BF_MOD
	m[228] = ((op & 16'hffc0) == 16'hedc0);  // BFFFO BF_EXT
	m[229] = ((op & 16'hffc0) == 16'heec0);  // BFSET BF_MOD
	m[230] = ((op & 16'hffc0) == 16'hefc0);  // BFINS BF_MOD
	m[231] = ((op & 16'hffc0) == 16'hf200);  // FPP FPU_GEN
	m[232] = ((op & 16'hffc0) == 16'hf240);  // FScc FSCC
	m[233] = ((op & 16'hfff8) == 16'hf248);  // FDBcc FDBCC
	m[234] = ((op & 16'hffff) == 16'hf27a);  // FTRAPcc FTRAPCC
	m[235] = ((op & 16'hffff) == 16'hf27b);  // FTRAPcc FTRAPCC
	m[236] = ((op & 16'hffff) == 16'hf27c);  // FTRAPcc FTRAPCC
	m[237] = ((op & 16'hffc0) == 16'hf280);  // FBcc FBCC
	m[238] = ((op & 16'hffc0) == 16'hf2c0);  // FBcc FBCC
	m[239] = ((op & 16'hffc0) == 16'hf300);  // FSAVE FSAVE
	m[240] = ((op & 16'hffc0) == 16'hf340);  // FRESTORE FRESTORE
	m[241] = ((op & 16'hfff8) == 16'hf408);  // CINVL CACHE_OP
	m[242] = ((op & 16'hfff8) == 16'hf410);  // CINVP CACHE_OP
	m[243] = ((op & 16'hfff8) == 16'hf418);  // CINVA CACHE_OP
	m[244] = ((op & 16'hfff8) == 16'hf428);  // CPUSHL CACHE_OP
	m[245] = ((op & 16'hfff8) == 16'hf430);  // CPUSHP CACHE_OP
	m[246] = ((op & 16'hfff8) == 16'hf438);  // CPUSHA CACHE_OP
	m[247] = ((op & 16'hfff8) == 16'hf448);  // CINVL CACHE_OP
	m[248] = ((op & 16'hfff8) == 16'hf450);  // CINVP CACHE_OP
	m[249] = ((op & 16'hfff8) == 16'hf458);  // CINVA CACHE_OP
	m[250] = ((op & 16'hfff8) == 16'hf468);  // CPUSHL CACHE_OP
	m[251] = ((op & 16'hfff8) == 16'hf470);  // CPUSHP CACHE_OP
	m[252] = ((op & 16'hfff8) == 16'hf478);  // CPUSHA CACHE_OP
	m[253] = ((op & 16'hfff8) == 16'hf488);  // CINVL CACHE_OP
	m[254] = ((op & 16'hfff8) == 16'hf490);  // CINVP CACHE_OP
	m[255] = ((op & 16'hfff8) == 16'hf498);  // CINVA CACHE_OP
	m[256] = ((op & 16'hfff8) == 16'hf4a8);  // CPUSHL CACHE_OP
	m[257] = ((op & 16'hfff8) == 16'hf4b0);  // CPUSHP CACHE_OP
	m[258] = ((op & 16'hfff8) == 16'hf4b8);  // CPUSHA CACHE_OP
	m[259] = ((op & 16'hfff8) == 16'hf4c8);  // CINVL CACHE_OP
	m[260] = ((op & 16'hfff8) == 16'hf4d0);  // CINVP CACHE_OP
	m[261] = ((op & 16'hfff8) == 16'hf4d8);  // CINVA CACHE_OP
	m[262] = ((op & 16'hfff8) == 16'hf4e8);  // CPUSHL CACHE_OP
	m[263] = ((op & 16'hfff8) == 16'hf4f0);  // CPUSHP CACHE_OP
	m[264] = ((op & 16'hfff8) == 16'hf4f8);  // CPUSHA CACHE_OP
	m[265] = ((op & 16'hfff8) == 16'hf500);  // PFLUSHN PFLUSH
	m[266] = ((op & 16'hfff8) == 16'hf508);  // PFLUSH PFLUSH
	m[267] = ((op & 16'hfff8) == 16'hf510);  // PFLUSHAN PFLUSH
	m[268] = ((op & 16'hfff8) == 16'hf518);  // PFLUSHA PFLUSH
	m[269] = ((op & 16'hfff8) == 16'hf548);  // PTESTW PTEST
	m[270] = ((op & 16'hfff8) == 16'hf568);  // PTESTR PTEST
	m[271] = ((op & 16'hfff8) == 16'hf600);  // MOVE16 MOVE16
	m[272] = ((op & 16'hfff8) == 16'hf608);  // MOVE16 MOVE16
	m[273] = ((op & 16'hfff8) == 16'hf610);  // MOVE16 MOVE16
	m[274] = ((op & 16'hfff8) == 16'hf618);  // MOVE16 MOVE16
	m[275] = ((op & 16'hfff8) == 16'hf620);  // MOVE16 MOVE16
	s[0] = m[0] & ~(m[21]);
	s[1] = m[1] & ~(m[23]);
	s[2] = m[2];
	s[3] = m[3];
	s[4] = m[4] & ~(m[25]);
	s[5] = m[5];
	s[6] = m[6];
	s[7] = m[7] & ~(m[22]);
	s[8] = m[8] & ~(m[24]);
	s[9] = m[9];
	s[10] = m[10];
	s[11] = m[11] & ~(m[26]);
	s[12] = m[12];
	s[13] = m[13];
	s[14] = m[14];
	s[15] = m[15];
	s[16] = m[16];
	s[17] = m[17];
	s[18] = m[18];
	s[19] = m[19];
	s[20] = m[20];
	s[21] = m[21];
	s[22] = m[22];
	s[23] = m[23];
	s[24] = m[24];
	s[25] = m[25];
	s[26] = m[26];
	s[27] = m[27];
	s[28] = m[28];
	s[29] = m[29];
	s[30] = m[30];
	s[31] = m[31] & ~(m[33]);
	s[32] = m[32] & ~(m[34]);
	s[33] = m[33];
	s[34] = m[34];
	s[35] = m[35];
	s[36] = m[36];
	s[37] = m[37];
	s[38] = m[38];
	s[39] = m[39] & ~(m[43]);
	s[40] = m[40] & ~(m[44]);
	s[41] = m[41] & ~(m[45]);
	s[42] = m[42] & ~(m[46]);
	s[43] = m[43];
	s[44] = m[44];
	s[45] = m[45];
	s[46] = m[46];
	s[47] = m[47];
	s[48] = m[48] & ~(m[50]);
	s[49] = m[49] & ~(m[51]);
	s[50] = m[50];
	s[51] = m[51];
	s[52] = m[52];
	s[53] = m[53];
	s[54] = m[54];
	s[55] = m[55];
	s[56] = m[56];
	s[57] = m[57];
	s[58] = m[58];
	s[59] = m[59];
	s[60] = m[60];
	s[61] = m[61];
	s[62] = m[62];
	s[63] = m[63];
	s[64] = m[64];
	s[65] = m[65];
	s[66] = m[66];
	s[67] = m[67];
	s[68] = m[68];
	s[69] = m[69];
	s[70] = m[70];
	s[71] = m[71];
	s[72] = m[72] & ~(m[71]);
	s[73] = m[73];
	s[74] = m[74];
	s[75] = m[75] & ~(m[73] | m[74]);
	s[76] = m[76];
	s[77] = m[77];
	s[78] = m[78];
	s[79] = m[79] & ~(m[76]);
	s[80] = m[80] & ~(m[77]);
	s[81] = m[81];
	s[82] = m[82];
	s[83] = m[83] & ~(m[84]);
	s[84] = m[84];
	s[85] = m[85];
	s[86] = m[86];
	s[87] = m[87];
	s[88] = m[88];
	s[89] = m[89];
	s[90] = m[90];
	s[91] = m[91];
	s[92] = m[92];
	s[93] = m[93];
	s[94] = m[94];
	s[95] = m[95];
	s[96] = m[96];
	s[97] = m[97];
	s[98] = m[98];
	s[99] = m[99];
	s[100] = m[100];
	s[101] = m[101];
	s[102] = m[102];
	s[103] = m[103];
	s[104] = m[104];
	s[105] = m[105];
	s[106] = m[106] & ~(m[78]);
	s[107] = m[107];
	s[108] = m[108];
	s[109] = m[109] & ~(m[113]);
	s[110] = m[110] & ~(m[115]);
	s[111] = m[111] & ~(m[114]);
	s[112] = m[112] & ~(m[116]);
	s[113] = m[113];
	s[114] = m[114];
	s[115] = m[115];
	s[116] = m[116];
	s[117] = m[117] & ~(m[118] | m[119] | m[120] | m[121]);
	s[118] = m[118];
	s[119] = m[119];
	s[120] = m[120];
	s[121] = m[121];
	s[122] = m[122];
	s[123] = m[123] & ~(m[122]);
	s[124] = m[124];
	s[125] = m[125];
	s[126] = m[126] & ~(m[174] | m[175]);
	s[127] = m[127];
	s[128] = m[128] & ~(m[176] | m[177]);
	s[129] = m[129];
	s[130] = m[130] & ~(m[136] | m[137]);
	s[131] = m[131];
	s[132] = m[132] & ~(m[138] | m[139]);
	s[133] = m[133];
	s[134] = m[134] & ~(m[135]);
	s[135] = m[135];
	s[136] = m[136];
	s[137] = m[137];
	s[138] = m[138];
	s[139] = m[139];
	s[140] = m[140];
	s[141] = m[141] & ~(m[178] | m[179]);
	s[142] = m[142];
	s[143] = m[143] & ~(m[188] | m[189]);
	s[144] = m[144];
	s[145] = m[145] & ~(m[151] | m[152]);
	s[146] = m[146];
	s[147] = m[147] & ~(m[153] | m[154]);
	s[148] = m[148];
	s[149] = m[149] & ~(m[150]);
	s[150] = m[150];
	s[151] = m[151];
	s[152] = m[152];
	s[153] = m[153];
	s[154] = m[154];
	s[155] = m[155];
	s[156] = m[156] & ~(m[180] | m[181]);
	s[157] = m[157];
	s[158] = m[158] & ~(m[190]);
	s[159] = m[159];
	s[160] = m[160] & ~(m[166] | m[167]);
	s[161] = m[161];
	s[162] = m[162] & ~(m[168] | m[169]);
	s[163] = m[163];
	s[164] = m[164] & ~(m[165]);
	s[165] = m[165];
	s[166] = m[166];
	s[167] = m[167];
	s[168] = m[168];
	s[169] = m[169];
	s[170] = m[170];
	s[171] = m[171];
	s[172] = m[172];
	s[173] = m[173];
	s[174] = m[174];
	s[175] = m[175];
	s[176] = m[176];
	s[177] = m[177];
	s[178] = m[178];
	s[179] = m[179];
	s[180] = m[180];
	s[181] = m[181];
	s[182] = m[182];
	s[183] = m[183];
	s[184] = m[184];
	s[185] = m[185];
	s[186] = m[186];
	s[187] = m[187];
	s[188] = m[188];
	s[189] = m[189];
	s[190] = m[190];
	s[191] = m[191];
	s[192] = m[192];
	s[193] = m[193];
	s[194] = m[194];
	s[195] = m[195];
	s[196] = m[196];
	s[197] = m[197];
	s[198] = m[198];
	s[199] = m[199];
	s[200] = m[200];
	s[201] = m[201];
	s[202] = m[202];
	s[203] = m[203];
	s[204] = m[204];
	s[205] = m[205];
	s[206] = m[206];
	s[207] = m[207];
	s[208] = m[208];
	s[209] = m[209];
	s[210] = m[210];
	s[211] = m[211];
	s[212] = m[212];
	s[213] = m[213];
	s[214] = m[214];
	s[215] = m[215];
	s[216] = m[216];
	s[217] = m[217];
	s[218] = m[218];
	s[219] = m[219];
	s[220] = m[220];
	s[221] = m[221];
	s[222] = m[222];
	s[223] = m[223];
	s[224] = m[224];
	s[225] = m[225];
	s[226] = m[226];
	s[227] = m[227];
	s[228] = m[228];
	s[229] = m[229];
	s[230] = m[230];
	s[231] = m[231];
	s[232] = m[232] & ~(m[233] | m[234] | m[235] | m[236]);
	s[233] = m[233];
	s[234] = m[234];
	s[235] = m[235];
	s[236] = m[236];
	s[237] = m[237];
	s[238] = m[238];
	s[239] = m[239];
	s[240] = m[240];
	s[241] = m[241];
	s[242] = m[242];
	s[243] = m[243];
	s[244] = m[244];
	s[245] = m[245];
	s[246] = m[246];
	s[247] = m[247];
	s[248] = m[248];
	s[249] = m[249];
	s[250] = m[250];
	s[251] = m[251];
	s[252] = m[252];
	s[253] = m[253];
	s[254] = m[254];
	s[255] = m[255];
	s[256] = m[256];
	s[257] = m[257];
	s[258] = m[258];
	s[259] = m[259];
	s[260] = m[260];
	s[261] = m[261];
	s[262] = m[262];
	s[263] = m[263];
	s[264] = m[264];
	s[265] = m[265];
	s[266] = m[266];
	s[267] = m[267];
	s[268] = m[268];
	s[269] = m[269];
	s[270] = m[270];
	s[271] = m[271];
	s[272] = m[272];
	s[273] = m[273];
	s[274] = m[274];
	s[275] = m[275];
	dec_sel = s;
endfunction

function automatic pla_t ent_attr(input logic [8:0] ent, input logic hit);
	ent_attr = '0;
	case (ent)
		9'd0: ent_attr = '{1'b1, 9'd0, 10'd4, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR IMM_OP
		9'd1: ent_attr = '{1'b1, 9'd1, 10'd4, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND IMM_OP
		9'd2: ent_attr = '{1'b1, 9'd2, 10'd4, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB IMM_OP
		9'd3: ent_attr = '{1'b1, 9'd3, 10'd4, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD IMM_OP
		9'd4: ent_attr = '{1'b1, 9'd4, 10'd4, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR IMM_OP
		9'd5: ent_attr = '{1'b1, 9'd5, 10'd5, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'h7fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP IMM_CMP
		9'd6: ent_attr = '{1'b1, 9'd6, 10'd215, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b1, 6'd9, 10'd224, 1'b1, 1'b0, 2'd0, 1'b1};  // MOVES MOVES
		9'd7: ent_attr = '{1'b1, 9'd7, 10'd4, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR IMM_OP
		9'd8: ent_attr = '{1'b1, 9'd8, 10'd4, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND IMM_OP
		9'd9: ent_attr = '{1'b1, 9'd9, 10'd4, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB IMM_OP
		9'd10: ent_attr = '{1'b1, 9'd10, 10'd4, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD IMM_OP
		9'd11: ent_attr = '{1'b1, 9'd11, 10'd4, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR IMM_OP
		9'd12: ent_attr = '{1'b1, 9'd12, 10'd5, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'h7fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP IMM_CMP
		9'd13: ent_attr = '{1'b1, 9'd13, 10'd215, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b1, 6'd9, 10'd224, 1'b1, 1'b0, 2'd0, 1'b1};  // MOVES MOVES
		9'd14: ent_attr = '{1'b1, 9'd14, 10'd4, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR IMM_OP
		9'd15: ent_attr = '{1'b1, 9'd15, 10'd4, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND IMM_OP
		9'd16: ent_attr = '{1'b1, 9'd16, 10'd4, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB IMM_OP
		9'd17: ent_attr = '{1'b1, 9'd17, 10'd4, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD IMM_OP
		9'd18: ent_attr = '{1'b1, 9'd18, 10'd4, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR IMM_OP
		9'd19: ent_attr = '{1'b1, 9'd19, 10'd5, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'h7fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP IMM_CMP
		9'd20: ent_attr = '{1'b1, 9'd20, 10'd215, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b1, 6'd9, 10'd224, 1'b1, 1'b0, 2'd0, 1'b1};  // MOVES MOVES
		9'd21: ent_attr = '{1'b1, 9'd21, 10'd109, 7'd42, 4'd1, 1'b1, 5'h0, 2'd0, 12'h000, 12'h000, 2'd0, 3'd2, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ORSR CCR_LOG
		9'd22: ent_attr = '{1'b1, 9'd22, 10'd110, 7'd42, 4'd1, 1'b1, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // ORSR SR_LOG
		9'd23: ent_attr = '{1'b1, 9'd23, 10'd109, 7'd42, 4'd0, 1'b1, 5'h0, 2'd0, 12'h000, 12'h000, 2'd0, 3'd2, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ANDSR CCR_LOG
		9'd24: ent_attr = '{1'b1, 9'd24, 10'd110, 7'd42, 4'd0, 1'b1, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // ANDSR SR_LOG
		9'd25: ent_attr = '{1'b1, 9'd25, 10'd109, 7'd42, 4'd2, 1'b1, 5'h0, 2'd0, 12'h000, 12'h000, 2'd0, 3'd2, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EORSR CCR_LOG
		9'd26: ent_attr = '{1'b1, 9'd26, 10'd110, 7'd42, 4'd2, 1'b1, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // EORSR SR_LOG
		9'd27: ent_attr = '{1'b1, 9'd27, 10'd197, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'h7e4, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CHK2 CHK2
		9'd28: ent_attr = '{1'b1, 9'd28, 10'd197, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h7e4, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CHK2 CHK2
		9'd29: ent_attr = '{1'b1, 9'd29, 10'd197, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e4, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CHK2 CHK2
		9'd30: ent_attr = '{1'b1, 9'd30, 10'd187, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // CAS CAS
		9'd31: ent_attr = '{1'b1, 9'd31, 10'd187, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // CAS CAS
		9'd32: ent_attr = '{1'b1, 9'd32, 10'd187, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // CAS CAS
		9'd33: ent_attr = '{1'b1, 9'd33, 10'd189, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd2, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CAS2 CAS2
		9'd34: ent_attr = '{1'b1, 9'd34, 10'd189, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd2, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CAS2 CAS2
		9'd35: ent_attr = '{1'b1, 9'd35, 10'd42, 7'd30, 4'd0, 1'b0, 5'h0, 2'd0, 12'h7fd, 12'h000, 2'd0, 3'd2, 1'b0, 6'd5, 10'd44, 1'b1, 1'b0, 2'd0, 1'b0};  // BTST BTST_IMM
		9'd36: ent_attr = '{1'b1, 9'd36, 10'd36, 7'd31, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd2, 1'b0, 6'd5, 10'd38, 1'b1, 1'b0, 2'd0, 1'b0};  // BCHG BIT_IMM
		9'd37: ent_attr = '{1'b1, 9'd37, 10'd36, 7'd32, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd2, 1'b0, 6'd5, 10'd38, 1'b1, 1'b0, 2'd0, 1'b0};  // BCLR BIT_IMM
		9'd38: ent_attr = '{1'b1, 9'd38, 10'd36, 7'd33, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd2, 1'b0, 6'd5, 10'd38, 1'b1, 1'b0, 2'd0, 1'b0};  // BSET BIT_IMM
		9'd39: ent_attr = '{1'b1, 9'd39, 10'd45, 7'd30, 4'd0, 1'b0, 5'h0, 2'd0, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd5, 10'd47, 1'b1, 1'b0, 2'd0, 1'b0};  // BTST BTST_DYN
		9'd40: ent_attr = '{1'b1, 9'd40, 10'd39, 7'd31, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd5, 10'd41, 1'b1, 1'b0, 2'd0, 1'b0};  // BCHG BIT_DYN
		9'd41: ent_attr = '{1'b1, 9'd41, 10'd39, 7'd32, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd5, 10'd41, 1'b1, 1'b0, 2'd0, 1'b0};  // BCLR BIT_DYN
		9'd42: ent_attr = '{1'b1, 9'd42, 10'd39, 7'd33, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd5, 10'd41, 1'b1, 1'b0, 2'd0, 1'b0};  // BSET BIT_DYN
		9'd43: ent_attr = '{1'b1, 9'd43, 10'd133, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // MVPMR MOVEP_MR
		9'd44: ent_attr = '{1'b1, 9'd44, 10'd133, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // MVPMR MOVEP_MR
		9'd45: ent_attr = '{1'b1, 9'd45, 10'd143, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd10, 10'd147, 1'b0, 1'b0, 2'd0, 1'b0};  // MVPRM MOVEP_RM
		9'd46: ent_attr = '{1'b1, 9'd46, 10'd143, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd10, 10'd147, 1'b0, 1'b0, 2'd0, 1'b0};  // MVPRM MOVEP_RM
		9'd47: ent_attr = '{1'b1, 9'd47, 10'd32, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'hffd, 12'h1fd, 2'd0, 3'd0, 1'b0, 6'd12, 10'd34, 1'b1, 1'b1, 2'd0, 1'b0};  // MOVE MOVE
		9'd48: ent_attr = '{1'b1, 9'd48, 10'd32, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hfff, 12'h1fd, 2'd0, 3'd0, 1'b0, 6'd12, 10'd34, 1'b1, 1'b1, 2'd0, 1'b0};  // MOVE MOVE
		9'd49: ent_attr = '{1'b1, 9'd49, 10'd32, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h1fd, 2'd0, 3'd0, 1'b0, 6'd12, 10'd34, 1'b1, 1'b1, 2'd0, 1'b0};  // MOVE MOVE
		9'd50: ent_attr = '{1'b1, 9'd50, 10'd29, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd2, 10'd31, 1'b1, 1'b0, 2'd0, 1'b0};  // MOVEA MOVEA
		9'd51: ent_attr = '{1'b1, 9'd51, 10'd29, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd2, 10'd31, 1'b1, 1'b0, 2'd0, 1'b0};  // MOVEA MOVEA
		9'd52: ent_attr = '{1'b1, 9'd52, 10'd10, 7'd11, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEGX UNARY
		9'd53: ent_attr = '{1'b1, 9'd53, 10'd13, 7'd12, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CLR CLR_W
		9'd54: ent_attr = '{1'b1, 9'd54, 10'd10, 7'd10, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEG UNARY
		9'd55: ent_attr = '{1'b1, 9'd55, 10'd10, 7'd9, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NOT UNARY
		9'd56: ent_attr = '{1'b1, 9'd56, 10'd11, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // TST TST
		9'd57: ent_attr = '{1'b1, 9'd57, 10'd10, 7'd11, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEGX UNARY
		9'd58: ent_attr = '{1'b1, 9'd58, 10'd13, 7'd12, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CLR CLR_W
		9'd59: ent_attr = '{1'b1, 9'd59, 10'd10, 7'd10, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEG UNARY
		9'd60: ent_attr = '{1'b1, 9'd60, 10'd10, 7'd9, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NOT UNARY
		9'd61: ent_attr = '{1'b1, 9'd61, 10'd11, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // TST TST
		9'd62: ent_attr = '{1'b1, 9'd62, 10'd10, 7'd11, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEGX UNARY
		9'd63: ent_attr = '{1'b1, 9'd63, 10'd13, 7'd12, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CLR CLR_W
		9'd64: ent_attr = '{1'b1, 9'd64, 10'd10, 7'd10, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEG UNARY
		9'd65: ent_attr = '{1'b1, 9'd65, 10'd10, 7'd9, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NOT UNARY
		9'd66: ent_attr = '{1'b1, 9'd66, 10'd11, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // TST TST
		9'd67: ent_attr = '{1'b1, 9'd67, 10'd105, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // MVSR2 MOVE_FROM_SR
		9'd68: ent_attr = '{1'b1, 9'd68, 10'd106, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // MVSR2 MOVE_FROM_CCR
		9'd69: ent_attr = '{1'b1, 9'd69, 10'd107, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // MV2SR MOVE_TO_CCR
		9'd70: ent_attr = '{1'b1, 9'd70, 10'd108, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // MV2SR MOVE_TO_SR
		9'd71: ent_attr = '{1'b1, 9'd71, 10'd98, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd4, 1'b0, 6'd11, 10'd102, 1'b0, 1'b0, 2'd0, 1'b0};  // LINK LINK
		9'd72: ent_attr = '{1'b1, 9'd72, 10'd10, 7'd19, 4'd0, 1'b0, 5'h1f, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NBCD UNARY
		9'd73: ent_attr = '{1'b1, 9'd73, 10'd114, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // BKPT BKPT
		9'd74: ent_attr = '{1'b1, 9'd74, 10'd14, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SWAP SWAP
		9'd75: ent_attr = '{1'b1, 9'd75, 10'd27, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e4, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // PEA PEA
		9'd76: ent_attr = '{1'b1, 9'd76, 10'd15, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXT EXT
		9'd77: ent_attr = '{1'b1, 9'd77, 10'd15, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXT EXT
		9'd78: ent_attr = '{1'b1, 9'd78, 10'd16, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXT EXTB
		9'd79: ent_attr = '{1'b1, 9'd79, 10'd125, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h1f4, 12'h000, 2'd1, 3'd0, 1'b0, 6'd13, 10'd127, 1'b1, 1'b0, 2'd0, 1'b0};  // MVMLE MOVEM_RM
		9'd80: ent_attr = '{1'b1, 9'd80, 10'd125, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1f4, 12'h000, 2'd1, 3'd0, 1'b0, 6'd13, 10'd127, 1'b1, 1'b0, 2'd0, 1'b0};  // MVMLE MOVEM_RM
		9'd81: ent_attr = '{1'b1, 9'd81, 10'd128, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h7ec, 12'h000, 2'd1, 3'd0, 1'b0, 6'd13, 10'd130, 1'b1, 1'b0, 2'd0, 1'b0};  // MVMEL MOVEM_MR
		9'd82: ent_attr = '{1'b1, 9'd82, 10'd128, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7ec, 12'h000, 2'd1, 3'd0, 1'b0, 6'd13, 10'd130, 1'b1, 1'b0, 2'd0, 1'b0};  // MVMEL MOVEM_MR
		9'd83: ent_attr = '{1'b1, 9'd83, 10'd17, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // TAS TAS
		9'd84: ent_attr = '{1'b1, 9'd84, 10'd0, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ILLG ILLEGAL
		9'd85: ent_attr = '{1'b1, 9'd85, 10'd67, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hffd, 12'h000, 2'd1, 3'd0, 1'b0, 6'd15, 10'd69, 1'b1, 1'b0, 2'd0, 1'b0};  // MULL MULL
		9'd86: ent_attr = '{1'b1, 9'd86, 10'd72, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hffd, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // DIVL DIVL
		9'd87: ent_attr = '{1'b1, 9'd87, 10'd113, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // TRAP TRAP
		9'd88: ent_attr = '{1'b1, 9'd88, 10'd98, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd11, 10'd102, 1'b0, 1'b0, 2'd0, 1'b0};  // LINK LINK
		9'd89: ent_attr = '{1'b1, 9'd89, 10'd104, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // UNLK UNLK
		9'd90: ent_attr = '{1'b1, 9'd90, 10'd111, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // MVR2USP MOVE_TO_USP
		9'd91: ent_attr = '{1'b1, 9'd91, 10'd112, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // MVUSP2R MOVE_FROM_USP
		9'd92: ent_attr = '{1'b1, 9'd92, 10'd117, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // RESET RESET
		9'd93: ent_attr = '{1'b1, 9'd93, 10'd116, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // NOP NOP
		9'd94: ent_attr = '{1'b1, 9'd94, 10'd118, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // STOP STOP
		9'd95: ent_attr = '{1'b1, 9'd95, 10'd202, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // RTE RTE
		9'd96: ent_attr = '{1'b1, 9'd96, 10'd94, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // RTD RTD
		9'd97: ent_attr = '{1'b1, 9'd97, 10'd93, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // RTS RTS
		9'd98: ent_attr = '{1'b1, 9'd98, 10'd97, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // TRAPV TRAPV
		9'd99: ent_attr = '{1'b1, 9'd99, 10'd212, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // RTR RTR
		9'd100: ent_attr = '{1'b1, 9'd100, 10'd119, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd0, 1'b1, 6'd16, 10'd121, 1'b0, 1'b0, 2'd0, 1'b0};  // MOVEC2 MOVEC_RD
		9'd101: ent_attr = '{1'b1, 9'd101, 10'd122, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd0, 1'b1, 6'd16, 10'd124, 1'b0, 1'b0, 2'd0, 1'b1};  // MOVE2C MOVEC_WR
		9'd102: ent_attr = '{1'b1, 9'd102, 10'd90, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e4, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // JSR JSR
		9'd103: ent_attr = '{1'b1, 9'd103, 10'd89, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e4, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // JMP JMP
		9'd104: ent_attr = '{1'b1, 9'd104, 10'd76, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CHK CHK
		9'd105: ent_attr = '{1'b1, 9'd105, 10'd76, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CHK CHK
		9'd106: ent_attr = '{1'b1, 9'd106, 10'd26, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e4, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // LEA LEA
		9'd107: ent_attr = '{1'b1, 9'd107, 10'd8, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD QUICK
		9'd108: ent_attr = '{1'b1, 9'd108, 10'd8, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB QUICK
		9'd109: ent_attr = '{1'b1, 9'd109, 10'd8, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD QUICK
		9'd110: ent_attr = '{1'b1, 9'd110, 10'd8, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB QUICK
		9'd111: ent_attr = '{1'b1, 9'd111, 10'd8, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD QUICK
		9'd112: ent_attr = '{1'b1, 9'd112, 10'd8, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB QUICK
		9'd113: ent_attr = '{1'b1, 9'd113, 10'd24, 7'd1, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ADDA QUICK_A
		9'd114: ent_attr = '{1'b1, 9'd114, 10'd24, 7'd1, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ADDA QUICK_A
		9'd115: ent_attr = '{1'b1, 9'd115, 10'd25, 7'd3, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SUBA QUICK_SA
		9'd116: ent_attr = '{1'b1, 9'd116, 10'd25, 7'd3, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SUBA QUICK_SA
		9'd117: ent_attr = '{1'b1, 9'd117, 10'd12, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // Scc SCC
		9'd118: ent_attr = '{1'b1, 9'd118, 10'd88, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // DBcc DBCC
		9'd119: ent_attr = '{1'b1, 9'd119, 10'd96, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // TRAPcc TRAPCC
		9'd120: ent_attr = '{1'b1, 9'd120, 10'd96, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // TRAPcc TRAPCC
		9'd121: ent_attr = '{1'b1, 9'd121, 10'd96, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // TRAPcc TRAPCC
		9'd122: ent_attr = '{1'b1, 9'd122, 10'd87, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd5, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // BSR BSR
		9'd123: ent_attr = '{1'b1, 9'd123, 10'd86, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd5, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // Bcc BCC
		9'd124: ent_attr = '{1'b1, 9'd124, 10'd9, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // MOVE MOVEQ
		9'd125: ent_attr = '{1'b1, 9'd125, 10'd2, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_EA_DN
		9'd126: ent_attr = '{1'b1, 9'd126, 10'd3, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_DN_EA
		9'd127: ent_attr = '{1'b1, 9'd127, 10'd2, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_EA_DN
		9'd128: ent_attr = '{1'b1, 9'd128, 10'd3, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_DN_EA
		9'd129: ent_attr = '{1'b1, 9'd129, 10'd2, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_EA_DN
		9'd130: ent_attr = '{1'b1, 9'd130, 10'd3, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_DN_EA
		9'd131: ent_attr = '{1'b1, 9'd131, 10'd2, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_EA_DN
		9'd132: ent_attr = '{1'b1, 9'd132, 10'd3, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_DN_EA
		9'd133: ent_attr = '{1'b1, 9'd133, 10'd6, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP CMP_EA_DN
		9'd134: ent_attr = '{1'b1, 9'd134, 10'd3, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR OP_DN_EA
		9'd135: ent_attr = '{1'b1, 9'd135, 10'd53, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd1, 1'b0};  // CMPM CMPM
		9'd136: ent_attr = '{1'b1, 9'd136, 10'd50, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SUBX ADDX_R
		9'd137: ent_attr = '{1'b1, 9'd137, 10'd51, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // SUBX ADDX_M
		9'd138: ent_attr = '{1'b1, 9'd138, 10'd50, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ADDX ADDX_R
		9'd139: ent_attr = '{1'b1, 9'd139, 10'd51, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // ADDX ADDX_M
		9'd140: ent_attr = '{1'b1, 9'd140, 10'd2, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_EA_DN
		9'd141: ent_attr = '{1'b1, 9'd141, 10'd3, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_DN_EA
		9'd142: ent_attr = '{1'b1, 9'd142, 10'd2, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_EA_DN
		9'd143: ent_attr = '{1'b1, 9'd143, 10'd3, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_DN_EA
		9'd144: ent_attr = '{1'b1, 9'd144, 10'd2, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_EA_DN
		9'd145: ent_attr = '{1'b1, 9'd145, 10'd3, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_DN_EA
		9'd146: ent_attr = '{1'b1, 9'd146, 10'd2, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_EA_DN
		9'd147: ent_attr = '{1'b1, 9'd147, 10'd3, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_DN_EA
		9'd148: ent_attr = '{1'b1, 9'd148, 10'd6, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP CMP_EA_DN
		9'd149: ent_attr = '{1'b1, 9'd149, 10'd3, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR OP_DN_EA
		9'd150: ent_attr = '{1'b1, 9'd150, 10'd53, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd1, 1'b0};  // CMPM CMPM
		9'd151: ent_attr = '{1'b1, 9'd151, 10'd50, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SUBX ADDX_R
		9'd152: ent_attr = '{1'b1, 9'd152, 10'd51, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // SUBX ADDX_M
		9'd153: ent_attr = '{1'b1, 9'd153, 10'd50, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ADDX ADDX_R
		9'd154: ent_attr = '{1'b1, 9'd154, 10'd51, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // ADDX ADDX_M
		9'd155: ent_attr = '{1'b1, 9'd155, 10'd2, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_EA_DN
		9'd156: ent_attr = '{1'b1, 9'd156, 10'd3, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_DN_EA
		9'd157: ent_attr = '{1'b1, 9'd157, 10'd2, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_EA_DN
		9'd158: ent_attr = '{1'b1, 9'd158, 10'd3, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_DN_EA
		9'd159: ent_attr = '{1'b1, 9'd159, 10'd2, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_EA_DN
		9'd160: ent_attr = '{1'b1, 9'd160, 10'd3, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_DN_EA
		9'd161: ent_attr = '{1'b1, 9'd161, 10'd2, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_EA_DN
		9'd162: ent_attr = '{1'b1, 9'd162, 10'd3, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_DN_EA
		9'd163: ent_attr = '{1'b1, 9'd163, 10'd6, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP CMP_EA_DN
		9'd164: ent_attr = '{1'b1, 9'd164, 10'd3, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR OP_DN_EA
		9'd165: ent_attr = '{1'b1, 9'd165, 10'd53, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd1, 1'b0};  // CMPM CMPM
		9'd166: ent_attr = '{1'b1, 9'd166, 10'd50, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SUBX ADDX_R
		9'd167: ent_attr = '{1'b1, 9'd167, 10'd51, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // SUBX ADDX_M
		9'd168: ent_attr = '{1'b1, 9'd168, 10'd50, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ADDX ADDX_R
		9'd169: ent_attr = '{1'b1, 9'd169, 10'd51, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // ADDX ADDX_M
		9'd170: ent_attr = '{1'b1, 9'd170, 10'd66, 7'd49, 4'd0, 1'b0, 5'hf, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // DIVU DIVW
		9'd171: ent_attr = '{1'b1, 9'd171, 10'd66, 7'd49, 4'd1, 1'b1, 5'hf, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // DIVS DIVW
		9'd172: ent_attr = '{1'b1, 9'd172, 10'd65, 7'd48, 4'd0, 1'b0, 5'hf, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // MULU MULW
		9'd173: ent_attr = '{1'b1, 9'd173, 10'd65, 7'd48, 4'd1, 1'b1, 5'hf, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // MULS MULW
		9'd174: ent_attr = '{1'b1, 9'd174, 10'd50, 7'd18, 4'd0, 1'b0, 5'h1f, 2'd0, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SBCD ADDX_R
		9'd175: ent_attr = '{1'b1, 9'd175, 10'd51, 7'd18, 4'd0, 1'b0, 5'h1f, 2'd0, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // SBCD ADDX_M
		9'd176: ent_attr = '{1'b1, 9'd176, 10'd50, 7'd17, 4'd0, 1'b0, 5'h1f, 2'd0, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ABCD ADDX_R
		9'd177: ent_attr = '{1'b1, 9'd177, 10'd51, 7'd17, 4'd0, 1'b0, 5'h1f, 2'd0, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // ABCD ADDX_M
		9'd178: ent_attr = '{1'b1, 9'd178, 10'd55, 7'd20, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // PACK PACK_R
		9'd179: ent_attr = '{1'b1, 9'd179, 10'd57, 7'd20, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // PACK PACK_M
		9'd180: ent_attr = '{1'b1, 9'd180, 10'd60, 7'd21, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // UNPK UNPK_R
		9'd181: ent_attr = '{1'b1, 9'd181, 10'd62, 7'd21, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // UNPK UNPK_M
		9'd182: ent_attr = '{1'b1, 9'd182, 10'd21, 7'd3, 4'd0, 1'b0, 5'h0, 2'd1, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd7, 10'd23, 1'b1, 1'b0, 2'd0, 1'b0};  // SUBA SUBA
		9'd183: ent_attr = '{1'b1, 9'd183, 10'd21, 7'd3, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd7, 10'd23, 1'b1, 1'b0, 2'd0, 1'b0};  // SUBA SUBA
		9'd184: ent_attr = '{1'b1, 9'd184, 10'd18, 7'd1, 4'd0, 1'b0, 5'h0, 2'd1, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd2, 10'd20, 1'b1, 1'b0, 2'd0, 1'b0};  // ADDA ADDA
		9'd185: ent_attr = '{1'b1, 9'd185, 10'd18, 7'd1, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd2, 10'd20, 1'b1, 1'b0, 2'd0, 1'b0};  // ADDA ADDA
		9'd186: ent_attr = '{1'b1, 9'd186, 10'd7, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMPA CMPA
		9'd187: ent_attr = '{1'b1, 9'd187, 10'd7, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMPA CMPA
		9'd188: ent_attr = '{1'b1, 9'd188, 10'd77, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXG EXG_DD
		9'd189: ent_attr = '{1'b1, 9'd189, 10'd80, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXG EXG_AA
		9'd190: ent_attr = '{1'b1, 9'd190, 10'd83, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXG EXG_DA
		9'd191: ent_attr = '{1'b1, 9'd191, 10'd48, 7'd23, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASR SHIFT_R
		9'd192: ent_attr = '{1'b1, 9'd192, 10'd48, 7'd22, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASL SHIFT_R
		9'd193: ent_attr = '{1'b1, 9'd193, 10'd48, 7'd25, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSR SHIFT_R
		9'd194: ent_attr = '{1'b1, 9'd194, 10'd48, 7'd24, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSL SHIFT_R
		9'd195: ent_attr = '{1'b1, 9'd195, 10'd48, 7'd29, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXR SHIFT_R
		9'd196: ent_attr = '{1'b1, 9'd196, 10'd48, 7'd28, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXL SHIFT_R
		9'd197: ent_attr = '{1'b1, 9'd197, 10'd48, 7'd27, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROR SHIFT_R
		9'd198: ent_attr = '{1'b1, 9'd198, 10'd48, 7'd26, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROL SHIFT_R
		9'd199: ent_attr = '{1'b1, 9'd199, 10'd48, 7'd23, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASR SHIFT_R
		9'd200: ent_attr = '{1'b1, 9'd200, 10'd48, 7'd22, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASL SHIFT_R
		9'd201: ent_attr = '{1'b1, 9'd201, 10'd48, 7'd25, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSR SHIFT_R
		9'd202: ent_attr = '{1'b1, 9'd202, 10'd48, 7'd24, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSL SHIFT_R
		9'd203: ent_attr = '{1'b1, 9'd203, 10'd48, 7'd29, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXR SHIFT_R
		9'd204: ent_attr = '{1'b1, 9'd204, 10'd48, 7'd28, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXL SHIFT_R
		9'd205: ent_attr = '{1'b1, 9'd205, 10'd48, 7'd27, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROR SHIFT_R
		9'd206: ent_attr = '{1'b1, 9'd206, 10'd48, 7'd26, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROL SHIFT_R
		9'd207: ent_attr = '{1'b1, 9'd207, 10'd48, 7'd23, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASR SHIFT_R
		9'd208: ent_attr = '{1'b1, 9'd208, 10'd48, 7'd22, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASL SHIFT_R
		9'd209: ent_attr = '{1'b1, 9'd209, 10'd48, 7'd25, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSR SHIFT_R
		9'd210: ent_attr = '{1'b1, 9'd210, 10'd48, 7'd24, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSL SHIFT_R
		9'd211: ent_attr = '{1'b1, 9'd211, 10'd48, 7'd29, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXR SHIFT_R
		9'd212: ent_attr = '{1'b1, 9'd212, 10'd48, 7'd28, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXL SHIFT_R
		9'd213: ent_attr = '{1'b1, 9'd213, 10'd48, 7'd27, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROR SHIFT_R
		9'd214: ent_attr = '{1'b1, 9'd214, 10'd48, 7'd26, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROL SHIFT_R
		9'd215: ent_attr = '{1'b1, 9'd215, 10'd49, 7'd23, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ASRW SHIFT_M
		9'd216: ent_attr = '{1'b1, 9'd216, 10'd49, 7'd22, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ASLW SHIFT_M
		9'd217: ent_attr = '{1'b1, 9'd217, 10'd49, 7'd25, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // LSRW SHIFT_M
		9'd218: ent_attr = '{1'b1, 9'd218, 10'd49, 7'd24, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // LSLW SHIFT_M
		9'd219: ent_attr = '{1'b1, 9'd219, 10'd49, 7'd29, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ROXRW SHIFT_M
		9'd220: ent_attr = '{1'b1, 9'd220, 10'd49, 7'd28, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ROXLW SHIFT_M
		9'd221: ent_attr = '{1'b1, 9'd221, 10'd49, 7'd27, 4'd0, 1'b0, 5'hf, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // RORW SHIFT_M
		9'd222: ent_attr = '{1'b1, 9'd222, 10'd49, 7'd26, 4'd0, 1'b0, 5'hf, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ROLW SHIFT_M
		9'd223: ent_attr = '{1'b1, 9'd223, 10'd154, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd162, 1'b1, 1'b0, 2'd0, 1'b0};  // BFTST BF_TST
		9'd224: ent_attr = '{1'b1, 9'd224, 10'd164, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd172, 1'b1, 1'b0, 2'd0, 1'b0};  // BFEXTU BF_EXT
		9'd225: ent_attr = '{1'b1, 9'd225, 10'd174, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd185, 1'b1, 1'b0, 2'd0, 1'b0};  // BFCHG BF_MOD
		9'd226: ent_attr = '{1'b1, 9'd226, 10'd164, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd172, 1'b1, 1'b0, 2'd0, 1'b0};  // BFEXTS BF_EXT
		9'd227: ent_attr = '{1'b1, 9'd227, 10'd174, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd185, 1'b1, 1'b0, 2'd0, 1'b0};  // BFCLR BF_MOD
		9'd228: ent_attr = '{1'b1, 9'd228, 10'd164, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd172, 1'b1, 1'b0, 2'd0, 1'b0};  // BFFFO BF_EXT
		9'd229: ent_attr = '{1'b1, 9'd229, 10'd174, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd185, 1'b1, 1'b0, 2'd0, 1'b0};  // BFSET BF_MOD
		9'd230: ent_attr = '{1'b1, 9'd230, 10'd174, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd185, 1'b1, 1'b0, 2'd0, 1'b0};  // BFINS BF_MOD
		9'd231: ent_attr = '{1'b1, 9'd231, 10'd228, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h000, 2'd1, 3'd0, 1'b0, 6'd19, 10'd237, 1'b1, 1'b0, 2'd0, 1'b0};  // FPP FPU_GEN
		9'd232: ent_attr = '{1'b1, 9'd232, 10'd482, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // FScc FSCC
		9'd233: ent_attr = '{1'b1, 9'd233, 10'd484, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd1, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // FDBcc FDBCC
		9'd234: ent_attr = '{1'b1, 9'd234, 10'd486, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // FTRAPcc FTRAPCC
		9'd235: ent_attr = '{1'b1, 9'd235, 10'd486, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // FTRAPcc FTRAPCC
		9'd236: ent_attr = '{1'b1, 9'd236, 10'd486, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // FTRAPcc FTRAPCC
		9'd237: ent_attr = '{1'b1, 9'd237, 10'd480, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd7, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // FBcc FBCC
		9'd238: ent_attr = '{1'b1, 9'd238, 10'd480, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd7, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // FBcc FBCC
		9'd239: ent_attr = '{1'b1, 9'd239, 10'd488, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1f4, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // FSAVE FSAVE
		9'd240: ent_attr = '{1'b1, 9'd240, 10'd546, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7ec, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // FRESTORE FRESTORE
		9'd241: ent_attr = '{1'b1, 9'd241, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVL CACHE_OP
		9'd242: ent_attr = '{1'b1, 9'd242, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVP CACHE_OP
		9'd243: ent_attr = '{1'b1, 9'd243, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVA CACHE_OP
		9'd244: ent_attr = '{1'b1, 9'd244, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHL CACHE_OP
		9'd245: ent_attr = '{1'b1, 9'd245, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHP CACHE_OP
		9'd246: ent_attr = '{1'b1, 9'd246, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHA CACHE_OP
		9'd247: ent_attr = '{1'b1, 9'd247, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVL CACHE_OP
		9'd248: ent_attr = '{1'b1, 9'd248, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVP CACHE_OP
		9'd249: ent_attr = '{1'b1, 9'd249, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVA CACHE_OP
		9'd250: ent_attr = '{1'b1, 9'd250, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHL CACHE_OP
		9'd251: ent_attr = '{1'b1, 9'd251, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHP CACHE_OP
		9'd252: ent_attr = '{1'b1, 9'd252, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHA CACHE_OP
		9'd253: ent_attr = '{1'b1, 9'd253, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVL CACHE_OP
		9'd254: ent_attr = '{1'b1, 9'd254, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVP CACHE_OP
		9'd255: ent_attr = '{1'b1, 9'd255, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVA CACHE_OP
		9'd256: ent_attr = '{1'b1, 9'd256, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHL CACHE_OP
		9'd257: ent_attr = '{1'b1, 9'd257, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHP CACHE_OP
		9'd258: ent_attr = '{1'b1, 9'd258, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHA CACHE_OP
		9'd259: ent_attr = '{1'b1, 9'd259, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVL CACHE_OP
		9'd260: ent_attr = '{1'b1, 9'd260, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVP CACHE_OP
		9'd261: ent_attr = '{1'b1, 9'd261, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVA CACHE_OP
		9'd262: ent_attr = '{1'b1, 9'd262, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHL CACHE_OP
		9'd263: ent_attr = '{1'b1, 9'd263, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHP CACHE_OP
		9'd264: ent_attr = '{1'b1, 9'd264, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHA CACHE_OP
		9'd265: ent_attr = '{1'b1, 9'd265, 10'd226, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PFLUSHN PFLUSH
		9'd266: ent_attr = '{1'b1, 9'd266, 10'd226, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PFLUSH PFLUSH
		9'd267: ent_attr = '{1'b1, 9'd267, 10'd226, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PFLUSHAN PFLUSH
		9'd268: ent_attr = '{1'b1, 9'd268, 10'd226, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PFLUSHA PFLUSH
		9'd269: ent_attr = '{1'b1, 9'd269, 10'd227, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PTESTW PTEST
		9'd270: ent_attr = '{1'b1, 9'd270, 10'd227, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PTESTR PTEST
		9'd271: ent_attr = '{1'b1, 9'd271, 10'd131, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd4, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd3, 1'b0};  // MOVE16 MOVE16
		9'd272: ent_attr = '{1'b1, 9'd272, 10'd131, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd4, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd3, 1'b0};  // MOVE16 MOVE16
		9'd273: ent_attr = '{1'b1, 9'd273, 10'd131, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd4, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd3, 1'b0};  // MOVE16 MOVE16
		9'd274: ent_attr = '{1'b1, 9'd274, 10'd131, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd4, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd3, 1'b0};  // MOVE16 MOVE16
		9'd275: ent_attr = '{1'b1, 9'd275, 10'd131, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd3, 1'b0};  // MOVE16 MOVE16
		default: ;
	endcase
	if (!hit) ent_attr = '0;
endfunction

function automatic pla_t ent_attr_oh(input logic [NENT-1:0] s);
	pla_t a;
	a = '0;
	if (s[0]) a = a | {1'b1, 9'd0, 10'd4, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR IMM_OP
	if (s[1]) a = a | {1'b1, 9'd1, 10'd4, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND IMM_OP
	if (s[2]) a = a | {1'b1, 9'd2, 10'd4, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB IMM_OP
	if (s[3]) a = a | {1'b1, 9'd3, 10'd4, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD IMM_OP
	if (s[4]) a = a | {1'b1, 9'd4, 10'd4, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR IMM_OP
	if (s[5]) a = a | {1'b1, 9'd5, 10'd5, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'h7fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP IMM_CMP
	if (s[6]) a = a | {1'b1, 9'd6, 10'd215, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b1, 6'd9, 10'd224, 1'b1, 1'b0, 2'd0, 1'b1};  // MOVES MOVES
	if (s[7]) a = a | {1'b1, 9'd7, 10'd4, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR IMM_OP
	if (s[8]) a = a | {1'b1, 9'd8, 10'd4, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND IMM_OP
	if (s[9]) a = a | {1'b1, 9'd9, 10'd4, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB IMM_OP
	if (s[10]) a = a | {1'b1, 9'd10, 10'd4, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD IMM_OP
	if (s[11]) a = a | {1'b1, 9'd11, 10'd4, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR IMM_OP
	if (s[12]) a = a | {1'b1, 9'd12, 10'd5, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'h7fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP IMM_CMP
	if (s[13]) a = a | {1'b1, 9'd13, 10'd215, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b1, 6'd9, 10'd224, 1'b1, 1'b0, 2'd0, 1'b1};  // MOVES MOVES
	if (s[14]) a = a | {1'b1, 9'd14, 10'd4, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR IMM_OP
	if (s[15]) a = a | {1'b1, 9'd15, 10'd4, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND IMM_OP
	if (s[16]) a = a | {1'b1, 9'd16, 10'd4, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB IMM_OP
	if (s[17]) a = a | {1'b1, 9'd17, 10'd4, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD IMM_OP
	if (s[18]) a = a | {1'b1, 9'd18, 10'd4, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR IMM_OP
	if (s[19]) a = a | {1'b1, 9'd19, 10'd5, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'h7fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP IMM_CMP
	if (s[20]) a = a | {1'b1, 9'd20, 10'd215, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b1, 6'd9, 10'd224, 1'b1, 1'b0, 2'd0, 1'b1};  // MOVES MOVES
	if (s[21]) a = a | {1'b1, 9'd21, 10'd109, 7'd42, 4'd1, 1'b1, 5'h0, 2'd0, 12'h000, 12'h000, 2'd0, 3'd2, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ORSR CCR_LOG
	if (s[22]) a = a | {1'b1, 9'd22, 10'd110, 7'd42, 4'd1, 1'b1, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // ORSR SR_LOG
	if (s[23]) a = a | {1'b1, 9'd23, 10'd109, 7'd42, 4'd0, 1'b1, 5'h0, 2'd0, 12'h000, 12'h000, 2'd0, 3'd2, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ANDSR CCR_LOG
	if (s[24]) a = a | {1'b1, 9'd24, 10'd110, 7'd42, 4'd0, 1'b1, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // ANDSR SR_LOG
	if (s[25]) a = a | {1'b1, 9'd25, 10'd109, 7'd42, 4'd2, 1'b1, 5'h0, 2'd0, 12'h000, 12'h000, 2'd0, 3'd2, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EORSR CCR_LOG
	if (s[26]) a = a | {1'b1, 9'd26, 10'd110, 7'd42, 4'd2, 1'b1, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // EORSR SR_LOG
	if (s[27]) a = a | {1'b1, 9'd27, 10'd197, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'h7e4, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CHK2 CHK2
	if (s[28]) a = a | {1'b1, 9'd28, 10'd197, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h7e4, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CHK2 CHK2
	if (s[29]) a = a | {1'b1, 9'd29, 10'd197, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e4, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CHK2 CHK2
	if (s[30]) a = a | {1'b1, 9'd30, 10'd187, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // CAS CAS
	if (s[31]) a = a | {1'b1, 9'd31, 10'd187, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // CAS CAS
	if (s[32]) a = a | {1'b1, 9'd32, 10'd187, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // CAS CAS
	if (s[33]) a = a | {1'b1, 9'd33, 10'd189, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd2, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CAS2 CAS2
	if (s[34]) a = a | {1'b1, 9'd34, 10'd189, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd2, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CAS2 CAS2
	if (s[35]) a = a | {1'b1, 9'd35, 10'd42, 7'd30, 4'd0, 1'b0, 5'h0, 2'd0, 12'h7fd, 12'h000, 2'd0, 3'd2, 1'b0, 6'd5, 10'd44, 1'b1, 1'b0, 2'd0, 1'b0};  // BTST BTST_IMM
	if (s[36]) a = a | {1'b1, 9'd36, 10'd36, 7'd31, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd2, 1'b0, 6'd5, 10'd38, 1'b1, 1'b0, 2'd0, 1'b0};  // BCHG BIT_IMM
	if (s[37]) a = a | {1'b1, 9'd37, 10'd36, 7'd32, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd2, 1'b0, 6'd5, 10'd38, 1'b1, 1'b0, 2'd0, 1'b0};  // BCLR BIT_IMM
	if (s[38]) a = a | {1'b1, 9'd38, 10'd36, 7'd33, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd2, 1'b0, 6'd5, 10'd38, 1'b1, 1'b0, 2'd0, 1'b0};  // BSET BIT_IMM
	if (s[39]) a = a | {1'b1, 9'd39, 10'd45, 7'd30, 4'd0, 1'b0, 5'h0, 2'd0, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd5, 10'd47, 1'b1, 1'b0, 2'd0, 1'b0};  // BTST BTST_DYN
	if (s[40]) a = a | {1'b1, 9'd40, 10'd39, 7'd31, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd5, 10'd41, 1'b1, 1'b0, 2'd0, 1'b0};  // BCHG BIT_DYN
	if (s[41]) a = a | {1'b1, 9'd41, 10'd39, 7'd32, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd5, 10'd41, 1'b1, 1'b0, 2'd0, 1'b0};  // BCLR BIT_DYN
	if (s[42]) a = a | {1'b1, 9'd42, 10'd39, 7'd33, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd5, 10'd41, 1'b1, 1'b0, 2'd0, 1'b0};  // BSET BIT_DYN
	if (s[43]) a = a | {1'b1, 9'd43, 10'd133, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // MVPMR MOVEP_MR
	if (s[44]) a = a | {1'b1, 9'd44, 10'd133, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // MVPMR MOVEP_MR
	if (s[45]) a = a | {1'b1, 9'd45, 10'd143, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd10, 10'd147, 1'b0, 1'b0, 2'd0, 1'b0};  // MVPRM MOVEP_RM
	if (s[46]) a = a | {1'b1, 9'd46, 10'd143, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd10, 10'd147, 1'b0, 1'b0, 2'd0, 1'b0};  // MVPRM MOVEP_RM
	if (s[47]) a = a | {1'b1, 9'd47, 10'd32, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'hffd, 12'h1fd, 2'd0, 3'd0, 1'b0, 6'd12, 10'd34, 1'b1, 1'b1, 2'd0, 1'b0};  // MOVE MOVE
	if (s[48]) a = a | {1'b1, 9'd48, 10'd32, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hfff, 12'h1fd, 2'd0, 3'd0, 1'b0, 6'd12, 10'd34, 1'b1, 1'b1, 2'd0, 1'b0};  // MOVE MOVE
	if (s[49]) a = a | {1'b1, 9'd49, 10'd32, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h1fd, 2'd0, 3'd0, 1'b0, 6'd12, 10'd34, 1'b1, 1'b1, 2'd0, 1'b0};  // MOVE MOVE
	if (s[50]) a = a | {1'b1, 9'd50, 10'd29, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd2, 10'd31, 1'b1, 1'b0, 2'd0, 1'b0};  // MOVEA MOVEA
	if (s[51]) a = a | {1'b1, 9'd51, 10'd29, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd2, 10'd31, 1'b1, 1'b0, 2'd0, 1'b0};  // MOVEA MOVEA
	if (s[52]) a = a | {1'b1, 9'd52, 10'd10, 7'd11, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEGX UNARY
	if (s[53]) a = a | {1'b1, 9'd53, 10'd13, 7'd12, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CLR CLR_W
	if (s[54]) a = a | {1'b1, 9'd54, 10'd10, 7'd10, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEG UNARY
	if (s[55]) a = a | {1'b1, 9'd55, 10'd10, 7'd9, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NOT UNARY
	if (s[56]) a = a | {1'b1, 9'd56, 10'd11, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // TST TST
	if (s[57]) a = a | {1'b1, 9'd57, 10'd10, 7'd11, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEGX UNARY
	if (s[58]) a = a | {1'b1, 9'd58, 10'd13, 7'd12, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CLR CLR_W
	if (s[59]) a = a | {1'b1, 9'd59, 10'd10, 7'd10, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEG UNARY
	if (s[60]) a = a | {1'b1, 9'd60, 10'd10, 7'd9, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NOT UNARY
	if (s[61]) a = a | {1'b1, 9'd61, 10'd11, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // TST TST
	if (s[62]) a = a | {1'b1, 9'd62, 10'd10, 7'd11, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEGX UNARY
	if (s[63]) a = a | {1'b1, 9'd63, 10'd13, 7'd12, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CLR CLR_W
	if (s[64]) a = a | {1'b1, 9'd64, 10'd10, 7'd10, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEG UNARY
	if (s[65]) a = a | {1'b1, 9'd65, 10'd10, 7'd9, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NOT UNARY
	if (s[66]) a = a | {1'b1, 9'd66, 10'd11, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // TST TST
	if (s[67]) a = a | {1'b1, 9'd67, 10'd105, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // MVSR2 MOVE_FROM_SR
	if (s[68]) a = a | {1'b1, 9'd68, 10'd106, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // MVSR2 MOVE_FROM_CCR
	if (s[69]) a = a | {1'b1, 9'd69, 10'd107, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // MV2SR MOVE_TO_CCR
	if (s[70]) a = a | {1'b1, 9'd70, 10'd108, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // MV2SR MOVE_TO_SR
	if (s[71]) a = a | {1'b1, 9'd71, 10'd98, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd4, 1'b0, 6'd11, 10'd102, 1'b0, 1'b0, 2'd0, 1'b0};  // LINK LINK
	if (s[72]) a = a | {1'b1, 9'd72, 10'd10, 7'd19, 4'd0, 1'b0, 5'h1f, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NBCD UNARY
	if (s[73]) a = a | {1'b1, 9'd73, 10'd114, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // BKPT BKPT
	if (s[74]) a = a | {1'b1, 9'd74, 10'd14, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SWAP SWAP
	if (s[75]) a = a | {1'b1, 9'd75, 10'd27, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e4, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // PEA PEA
	if (s[76]) a = a | {1'b1, 9'd76, 10'd15, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXT EXT
	if (s[77]) a = a | {1'b1, 9'd77, 10'd15, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXT EXT
	if (s[78]) a = a | {1'b1, 9'd78, 10'd16, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXT EXTB
	if (s[79]) a = a | {1'b1, 9'd79, 10'd125, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h1f4, 12'h000, 2'd1, 3'd0, 1'b0, 6'd13, 10'd127, 1'b1, 1'b0, 2'd0, 1'b0};  // MVMLE MOVEM_RM
	if (s[80]) a = a | {1'b1, 9'd80, 10'd125, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1f4, 12'h000, 2'd1, 3'd0, 1'b0, 6'd13, 10'd127, 1'b1, 1'b0, 2'd0, 1'b0};  // MVMLE MOVEM_RM
	if (s[81]) a = a | {1'b1, 9'd81, 10'd128, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h7ec, 12'h000, 2'd1, 3'd0, 1'b0, 6'd13, 10'd130, 1'b1, 1'b0, 2'd0, 1'b0};  // MVMEL MOVEM_MR
	if (s[82]) a = a | {1'b1, 9'd82, 10'd128, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7ec, 12'h000, 2'd1, 3'd0, 1'b0, 6'd13, 10'd130, 1'b1, 1'b0, 2'd0, 1'b0};  // MVMEL MOVEM_MR
	if (s[83]) a = a | {1'b1, 9'd83, 10'd17, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // TAS TAS
	if (s[84]) a = a | {1'b1, 9'd84, 10'd0, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ILLG ILLEGAL
	if (s[85]) a = a | {1'b1, 9'd85, 10'd67, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hffd, 12'h000, 2'd1, 3'd0, 1'b0, 6'd15, 10'd69, 1'b1, 1'b0, 2'd0, 1'b0};  // MULL MULL
	if (s[86]) a = a | {1'b1, 9'd86, 10'd72, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hffd, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // DIVL DIVL
	if (s[87]) a = a | {1'b1, 9'd87, 10'd113, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // TRAP TRAP
	if (s[88]) a = a | {1'b1, 9'd88, 10'd98, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd11, 10'd102, 1'b0, 1'b0, 2'd0, 1'b0};  // LINK LINK
	if (s[89]) a = a | {1'b1, 9'd89, 10'd104, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // UNLK UNLK
	if (s[90]) a = a | {1'b1, 9'd90, 10'd111, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // MVR2USP MOVE_TO_USP
	if (s[91]) a = a | {1'b1, 9'd91, 10'd112, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // MVUSP2R MOVE_FROM_USP
	if (s[92]) a = a | {1'b1, 9'd92, 10'd117, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // RESET RESET
	if (s[93]) a = a | {1'b1, 9'd93, 10'd116, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // NOP NOP
	if (s[94]) a = a | {1'b1, 9'd94, 10'd118, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // STOP STOP
	if (s[95]) a = a | {1'b1, 9'd95, 10'd202, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // RTE RTE
	if (s[96]) a = a | {1'b1, 9'd96, 10'd94, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // RTD RTD
	if (s[97]) a = a | {1'b1, 9'd97, 10'd93, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // RTS RTS
	if (s[98]) a = a | {1'b1, 9'd98, 10'd97, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // TRAPV TRAPV
	if (s[99]) a = a | {1'b1, 9'd99, 10'd212, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // RTR RTR
	if (s[100]) a = a | {1'b1, 9'd100, 10'd119, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd0, 1'b1, 6'd16, 10'd121, 1'b0, 1'b0, 2'd0, 1'b0};  // MOVEC2 MOVEC_RD
	if (s[101]) a = a | {1'b1, 9'd101, 10'd122, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd0, 1'b1, 6'd16, 10'd124, 1'b0, 1'b0, 2'd0, 1'b1};  // MOVE2C MOVEC_WR
	if (s[102]) a = a | {1'b1, 9'd102, 10'd90, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e4, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // JSR JSR
	if (s[103]) a = a | {1'b1, 9'd103, 10'd89, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e4, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // JMP JMP
	if (s[104]) a = a | {1'b1, 9'd104, 10'd76, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CHK CHK
	if (s[105]) a = a | {1'b1, 9'd105, 10'd76, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CHK CHK
	if (s[106]) a = a | {1'b1, 9'd106, 10'd26, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e4, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // LEA LEA
	if (s[107]) a = a | {1'b1, 9'd107, 10'd8, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD QUICK
	if (s[108]) a = a | {1'b1, 9'd108, 10'd8, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB QUICK
	if (s[109]) a = a | {1'b1, 9'd109, 10'd8, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD QUICK
	if (s[110]) a = a | {1'b1, 9'd110, 10'd8, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB QUICK
	if (s[111]) a = a | {1'b1, 9'd111, 10'd8, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD QUICK
	if (s[112]) a = a | {1'b1, 9'd112, 10'd8, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB QUICK
	if (s[113]) a = a | {1'b1, 9'd113, 10'd24, 7'd1, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ADDA QUICK_A
	if (s[114]) a = a | {1'b1, 9'd114, 10'd24, 7'd1, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ADDA QUICK_A
	if (s[115]) a = a | {1'b1, 9'd115, 10'd25, 7'd3, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SUBA QUICK_SA
	if (s[116]) a = a | {1'b1, 9'd116, 10'd25, 7'd3, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SUBA QUICK_SA
	if (s[117]) a = a | {1'b1, 9'd117, 10'd12, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // Scc SCC
	if (s[118]) a = a | {1'b1, 9'd118, 10'd88, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // DBcc DBCC
	if (s[119]) a = a | {1'b1, 9'd119, 10'd96, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // TRAPcc TRAPCC
	if (s[120]) a = a | {1'b1, 9'd120, 10'd96, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // TRAPcc TRAPCC
	if (s[121]) a = a | {1'b1, 9'd121, 10'd96, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // TRAPcc TRAPCC
	if (s[122]) a = a | {1'b1, 9'd122, 10'd87, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd5, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // BSR BSR
	if (s[123]) a = a | {1'b1, 9'd123, 10'd86, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd5, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // Bcc BCC
	if (s[124]) a = a | {1'b1, 9'd124, 10'd9, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // MOVE MOVEQ
	if (s[125]) a = a | {1'b1, 9'd125, 10'd2, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_EA_DN
	if (s[126]) a = a | {1'b1, 9'd126, 10'd3, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_DN_EA
	if (s[127]) a = a | {1'b1, 9'd127, 10'd2, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_EA_DN
	if (s[128]) a = a | {1'b1, 9'd128, 10'd3, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_DN_EA
	if (s[129]) a = a | {1'b1, 9'd129, 10'd2, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_EA_DN
	if (s[130]) a = a | {1'b1, 9'd130, 10'd3, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_DN_EA
	if (s[131]) a = a | {1'b1, 9'd131, 10'd2, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_EA_DN
	if (s[132]) a = a | {1'b1, 9'd132, 10'd3, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_DN_EA
	if (s[133]) a = a | {1'b1, 9'd133, 10'd6, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP CMP_EA_DN
	if (s[134]) a = a | {1'b1, 9'd134, 10'd3, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR OP_DN_EA
	if (s[135]) a = a | {1'b1, 9'd135, 10'd53, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd1, 1'b0};  // CMPM CMPM
	if (s[136]) a = a | {1'b1, 9'd136, 10'd50, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SUBX ADDX_R
	if (s[137]) a = a | {1'b1, 9'd137, 10'd51, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // SUBX ADDX_M
	if (s[138]) a = a | {1'b1, 9'd138, 10'd50, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ADDX ADDX_R
	if (s[139]) a = a | {1'b1, 9'd139, 10'd51, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // ADDX ADDX_M
	if (s[140]) a = a | {1'b1, 9'd140, 10'd2, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_EA_DN
	if (s[141]) a = a | {1'b1, 9'd141, 10'd3, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_DN_EA
	if (s[142]) a = a | {1'b1, 9'd142, 10'd2, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_EA_DN
	if (s[143]) a = a | {1'b1, 9'd143, 10'd3, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_DN_EA
	if (s[144]) a = a | {1'b1, 9'd144, 10'd2, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_EA_DN
	if (s[145]) a = a | {1'b1, 9'd145, 10'd3, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_DN_EA
	if (s[146]) a = a | {1'b1, 9'd146, 10'd2, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_EA_DN
	if (s[147]) a = a | {1'b1, 9'd147, 10'd3, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_DN_EA
	if (s[148]) a = a | {1'b1, 9'd148, 10'd6, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP CMP_EA_DN
	if (s[149]) a = a | {1'b1, 9'd149, 10'd3, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR OP_DN_EA
	if (s[150]) a = a | {1'b1, 9'd150, 10'd53, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd1, 1'b0};  // CMPM CMPM
	if (s[151]) a = a | {1'b1, 9'd151, 10'd50, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SUBX ADDX_R
	if (s[152]) a = a | {1'b1, 9'd152, 10'd51, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // SUBX ADDX_M
	if (s[153]) a = a | {1'b1, 9'd153, 10'd50, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ADDX ADDX_R
	if (s[154]) a = a | {1'b1, 9'd154, 10'd51, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // ADDX ADDX_M
	if (s[155]) a = a | {1'b1, 9'd155, 10'd2, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_EA_DN
	if (s[156]) a = a | {1'b1, 9'd156, 10'd3, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_DN_EA
	if (s[157]) a = a | {1'b1, 9'd157, 10'd2, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_EA_DN
	if (s[158]) a = a | {1'b1, 9'd158, 10'd3, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_DN_EA
	if (s[159]) a = a | {1'b1, 9'd159, 10'd2, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_EA_DN
	if (s[160]) a = a | {1'b1, 9'd160, 10'd3, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_DN_EA
	if (s[161]) a = a | {1'b1, 9'd161, 10'd2, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_EA_DN
	if (s[162]) a = a | {1'b1, 9'd162, 10'd3, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_DN_EA
	if (s[163]) a = a | {1'b1, 9'd163, 10'd6, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP CMP_EA_DN
	if (s[164]) a = a | {1'b1, 9'd164, 10'd3, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR OP_DN_EA
	if (s[165]) a = a | {1'b1, 9'd165, 10'd53, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd1, 1'b0};  // CMPM CMPM
	if (s[166]) a = a | {1'b1, 9'd166, 10'd50, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SUBX ADDX_R
	if (s[167]) a = a | {1'b1, 9'd167, 10'd51, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // SUBX ADDX_M
	if (s[168]) a = a | {1'b1, 9'd168, 10'd50, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ADDX ADDX_R
	if (s[169]) a = a | {1'b1, 9'd169, 10'd51, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // ADDX ADDX_M
	if (s[170]) a = a | {1'b1, 9'd170, 10'd66, 7'd49, 4'd0, 1'b0, 5'hf, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // DIVU DIVW
	if (s[171]) a = a | {1'b1, 9'd171, 10'd66, 7'd49, 4'd1, 1'b1, 5'hf, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // DIVS DIVW
	if (s[172]) a = a | {1'b1, 9'd172, 10'd65, 7'd48, 4'd0, 1'b0, 5'hf, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // MULU MULW
	if (s[173]) a = a | {1'b1, 9'd173, 10'd65, 7'd48, 4'd1, 1'b1, 5'hf, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // MULS MULW
	if (s[174]) a = a | {1'b1, 9'd174, 10'd50, 7'd18, 4'd0, 1'b0, 5'h1f, 2'd0, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SBCD ADDX_R
	if (s[175]) a = a | {1'b1, 9'd175, 10'd51, 7'd18, 4'd0, 1'b0, 5'h1f, 2'd0, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // SBCD ADDX_M
	if (s[176]) a = a | {1'b1, 9'd176, 10'd50, 7'd17, 4'd0, 1'b0, 5'h1f, 2'd0, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ABCD ADDX_R
	if (s[177]) a = a | {1'b1, 9'd177, 10'd51, 7'd17, 4'd0, 1'b0, 5'h1f, 2'd0, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // ABCD ADDX_M
	if (s[178]) a = a | {1'b1, 9'd178, 10'd55, 7'd20, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // PACK PACK_R
	if (s[179]) a = a | {1'b1, 9'd179, 10'd57, 7'd20, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // PACK PACK_M
	if (s[180]) a = a | {1'b1, 9'd180, 10'd60, 7'd21, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // UNPK UNPK_R
	if (s[181]) a = a | {1'b1, 9'd181, 10'd62, 7'd21, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // UNPK UNPK_M
	if (s[182]) a = a | {1'b1, 9'd182, 10'd21, 7'd3, 4'd0, 1'b0, 5'h0, 2'd1, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd7, 10'd23, 1'b1, 1'b0, 2'd0, 1'b0};  // SUBA SUBA
	if (s[183]) a = a | {1'b1, 9'd183, 10'd21, 7'd3, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd7, 10'd23, 1'b1, 1'b0, 2'd0, 1'b0};  // SUBA SUBA
	if (s[184]) a = a | {1'b1, 9'd184, 10'd18, 7'd1, 4'd0, 1'b0, 5'h0, 2'd1, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd2, 10'd20, 1'b1, 1'b0, 2'd0, 1'b0};  // ADDA ADDA
	if (s[185]) a = a | {1'b1, 9'd185, 10'd18, 7'd1, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd2, 10'd20, 1'b1, 1'b0, 2'd0, 1'b0};  // ADDA ADDA
	if (s[186]) a = a | {1'b1, 9'd186, 10'd7, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMPA CMPA
	if (s[187]) a = a | {1'b1, 9'd187, 10'd7, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMPA CMPA
	if (s[188]) a = a | {1'b1, 9'd188, 10'd77, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXG EXG_DD
	if (s[189]) a = a | {1'b1, 9'd189, 10'd80, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXG EXG_AA
	if (s[190]) a = a | {1'b1, 9'd190, 10'd83, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXG EXG_DA
	if (s[191]) a = a | {1'b1, 9'd191, 10'd48, 7'd23, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASR SHIFT_R
	if (s[192]) a = a | {1'b1, 9'd192, 10'd48, 7'd22, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASL SHIFT_R
	if (s[193]) a = a | {1'b1, 9'd193, 10'd48, 7'd25, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSR SHIFT_R
	if (s[194]) a = a | {1'b1, 9'd194, 10'd48, 7'd24, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSL SHIFT_R
	if (s[195]) a = a | {1'b1, 9'd195, 10'd48, 7'd29, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXR SHIFT_R
	if (s[196]) a = a | {1'b1, 9'd196, 10'd48, 7'd28, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXL SHIFT_R
	if (s[197]) a = a | {1'b1, 9'd197, 10'd48, 7'd27, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROR SHIFT_R
	if (s[198]) a = a | {1'b1, 9'd198, 10'd48, 7'd26, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROL SHIFT_R
	if (s[199]) a = a | {1'b1, 9'd199, 10'd48, 7'd23, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASR SHIFT_R
	if (s[200]) a = a | {1'b1, 9'd200, 10'd48, 7'd22, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASL SHIFT_R
	if (s[201]) a = a | {1'b1, 9'd201, 10'd48, 7'd25, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSR SHIFT_R
	if (s[202]) a = a | {1'b1, 9'd202, 10'd48, 7'd24, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSL SHIFT_R
	if (s[203]) a = a | {1'b1, 9'd203, 10'd48, 7'd29, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXR SHIFT_R
	if (s[204]) a = a | {1'b1, 9'd204, 10'd48, 7'd28, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXL SHIFT_R
	if (s[205]) a = a | {1'b1, 9'd205, 10'd48, 7'd27, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROR SHIFT_R
	if (s[206]) a = a | {1'b1, 9'd206, 10'd48, 7'd26, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROL SHIFT_R
	if (s[207]) a = a | {1'b1, 9'd207, 10'd48, 7'd23, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASR SHIFT_R
	if (s[208]) a = a | {1'b1, 9'd208, 10'd48, 7'd22, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASL SHIFT_R
	if (s[209]) a = a | {1'b1, 9'd209, 10'd48, 7'd25, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSR SHIFT_R
	if (s[210]) a = a | {1'b1, 9'd210, 10'd48, 7'd24, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSL SHIFT_R
	if (s[211]) a = a | {1'b1, 9'd211, 10'd48, 7'd29, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXR SHIFT_R
	if (s[212]) a = a | {1'b1, 9'd212, 10'd48, 7'd28, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXL SHIFT_R
	if (s[213]) a = a | {1'b1, 9'd213, 10'd48, 7'd27, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROR SHIFT_R
	if (s[214]) a = a | {1'b1, 9'd214, 10'd48, 7'd26, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROL SHIFT_R
	if (s[215]) a = a | {1'b1, 9'd215, 10'd49, 7'd23, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ASRW SHIFT_M
	if (s[216]) a = a | {1'b1, 9'd216, 10'd49, 7'd22, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ASLW SHIFT_M
	if (s[217]) a = a | {1'b1, 9'd217, 10'd49, 7'd25, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // LSRW SHIFT_M
	if (s[218]) a = a | {1'b1, 9'd218, 10'd49, 7'd24, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // LSLW SHIFT_M
	if (s[219]) a = a | {1'b1, 9'd219, 10'd49, 7'd29, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ROXRW SHIFT_M
	if (s[220]) a = a | {1'b1, 9'd220, 10'd49, 7'd28, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ROXLW SHIFT_M
	if (s[221]) a = a | {1'b1, 9'd221, 10'd49, 7'd27, 4'd0, 1'b0, 5'hf, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // RORW SHIFT_M
	if (s[222]) a = a | {1'b1, 9'd222, 10'd49, 7'd26, 4'd0, 1'b0, 5'hf, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ROLW SHIFT_M
	if (s[223]) a = a | {1'b1, 9'd223, 10'd154, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd162, 1'b1, 1'b0, 2'd0, 1'b0};  // BFTST BF_TST
	if (s[224]) a = a | {1'b1, 9'd224, 10'd164, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd172, 1'b1, 1'b0, 2'd0, 1'b0};  // BFEXTU BF_EXT
	if (s[225]) a = a | {1'b1, 9'd225, 10'd174, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd185, 1'b1, 1'b0, 2'd0, 1'b0};  // BFCHG BF_MOD
	if (s[226]) a = a | {1'b1, 9'd226, 10'd164, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd172, 1'b1, 1'b0, 2'd0, 1'b0};  // BFEXTS BF_EXT
	if (s[227]) a = a | {1'b1, 9'd227, 10'd174, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd185, 1'b1, 1'b0, 2'd0, 1'b0};  // BFCLR BF_MOD
	if (s[228]) a = a | {1'b1, 9'd228, 10'd164, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd172, 1'b1, 1'b0, 2'd0, 1'b0};  // BFFFO BF_EXT
	if (s[229]) a = a | {1'b1, 9'd229, 10'd174, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd185, 1'b1, 1'b0, 2'd0, 1'b0};  // BFSET BF_MOD
	if (s[230]) a = a | {1'b1, 9'd230, 10'd174, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd185, 1'b1, 1'b0, 2'd0, 1'b0};  // BFINS BF_MOD
	if (s[231]) a = a | {1'b1, 9'd231, 10'd228, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h000, 2'd1, 3'd0, 1'b0, 6'd19, 10'd237, 1'b1, 1'b0, 2'd0, 1'b0};  // FPP FPU_GEN
	if (s[232]) a = a | {1'b1, 9'd232, 10'd482, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // FScc FSCC
	if (s[233]) a = a | {1'b1, 9'd233, 10'd484, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd1, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // FDBcc FDBCC
	if (s[234]) a = a | {1'b1, 9'd234, 10'd486, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // FTRAPcc FTRAPCC
	if (s[235]) a = a | {1'b1, 9'd235, 10'd486, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // FTRAPcc FTRAPCC
	if (s[236]) a = a | {1'b1, 9'd236, 10'd486, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // FTRAPcc FTRAPCC
	if (s[237]) a = a | {1'b1, 9'd237, 10'd480, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd7, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // FBcc FBCC
	if (s[238]) a = a | {1'b1, 9'd238, 10'd480, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd7, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // FBcc FBCC
	if (s[239]) a = a | {1'b1, 9'd239, 10'd488, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1f4, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // FSAVE FSAVE
	if (s[240]) a = a | {1'b1, 9'd240, 10'd546, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7ec, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // FRESTORE FRESTORE
	if (s[241]) a = a | {1'b1, 9'd241, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVL CACHE_OP
	if (s[242]) a = a | {1'b1, 9'd242, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVP CACHE_OP
	if (s[243]) a = a | {1'b1, 9'd243, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVA CACHE_OP
	if (s[244]) a = a | {1'b1, 9'd244, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHL CACHE_OP
	if (s[245]) a = a | {1'b1, 9'd245, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHP CACHE_OP
	if (s[246]) a = a | {1'b1, 9'd246, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHA CACHE_OP
	if (s[247]) a = a | {1'b1, 9'd247, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVL CACHE_OP
	if (s[248]) a = a | {1'b1, 9'd248, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVP CACHE_OP
	if (s[249]) a = a | {1'b1, 9'd249, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVA CACHE_OP
	if (s[250]) a = a | {1'b1, 9'd250, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHL CACHE_OP
	if (s[251]) a = a | {1'b1, 9'd251, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHP CACHE_OP
	if (s[252]) a = a | {1'b1, 9'd252, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHA CACHE_OP
	if (s[253]) a = a | {1'b1, 9'd253, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVL CACHE_OP
	if (s[254]) a = a | {1'b1, 9'd254, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVP CACHE_OP
	if (s[255]) a = a | {1'b1, 9'd255, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVA CACHE_OP
	if (s[256]) a = a | {1'b1, 9'd256, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHL CACHE_OP
	if (s[257]) a = a | {1'b1, 9'd257, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHP CACHE_OP
	if (s[258]) a = a | {1'b1, 9'd258, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHA CACHE_OP
	if (s[259]) a = a | {1'b1, 9'd259, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVL CACHE_OP
	if (s[260]) a = a | {1'b1, 9'd260, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVP CACHE_OP
	if (s[261]) a = a | {1'b1, 9'd261, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVA CACHE_OP
	if (s[262]) a = a | {1'b1, 9'd262, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHL CACHE_OP
	if (s[263]) a = a | {1'b1, 9'd263, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHP CACHE_OP
	if (s[264]) a = a | {1'b1, 9'd264, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHA CACHE_OP
	if (s[265]) a = a | {1'b1, 9'd265, 10'd226, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PFLUSHN PFLUSH
	if (s[266]) a = a | {1'b1, 9'd266, 10'd226, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PFLUSH PFLUSH
	if (s[267]) a = a | {1'b1, 9'd267, 10'd226, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PFLUSHAN PFLUSH
	if (s[268]) a = a | {1'b1, 9'd268, 10'd226, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PFLUSHA PFLUSH
	if (s[269]) a = a | {1'b1, 9'd269, 10'd227, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PTESTW PTEST
	if (s[270]) a = a | {1'b1, 9'd270, 10'd227, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PTESTR PTEST
	if (s[271]) a = a | {1'b1, 9'd271, 10'd131, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd4, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd3, 1'b0};  // MOVE16 MOVE16
	if (s[272]) a = a | {1'b1, 9'd272, 10'd131, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd4, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd3, 1'b0};  // MOVE16 MOVE16
	if (s[273]) a = a | {1'b1, 9'd273, 10'd131, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd4, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd3, 1'b0};  // MOVE16 MOVE16
	if (s[274]) a = a | {1'b1, 9'd274, 10'd131, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd4, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd3, 1'b0};  // MOVE16 MOVE16
	if (s[275]) a = a | {1'b1, 9'd275, 10'd131, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd3, 1'b0};  // MOVE16 MOVE16
	ent_attr_oh = a;
endfunction

function automatic logic [8:0] sel_index(input logic [NENT-1:0] s);
	logic [8:0] x;
	x = '0;
	for (int i = 0; i < NENT; i++) if (s[i]) x = x | 9'(i);
	sel_index = x;
endfunction
function automatic pla_t dec_pla(input logic [15:0] op);
	logic [NENT-1:0] s;
	s = dec_sel(op);
	dec_pla = ent_attr(sel_index(s), |s);
endfunction
// ---- end of ap68040_dec_pla.svh ----

//--------------------------------------------------------------------------
// helpers
//--------------------------------------------------------------------------
function automatic logic [2:0] ea_len(input logic [3:0] idx, input logic [15:0] w,
                                      input logic [2:0] immlen);
	logic [2:0] n;
	case (idx)
		EM_AD16, EM_ABSW, EM_PC16: n = 3'd1;
		EM_ABSL: n = 3'd2;
		EM_IMM:  n = immlen;
		EM_AX, EM_PCX: begin
			n = 3'd1;
			if (w[8]) begin
				case (w[5:4])
					2'd2: n = n + 3'd1;
					2'd3: n = n + 3'd2;
					default: ;
				endcase
				case (w[1:0])
					2'd2: n = n + 3'd1;
					2'd3: n = n + 3'd2;
					default: ;
				endcase
			end
		end
		default: n = 3'd0;
	endcase
	ea_len = n;
endfunction

function automatic logic [31:0] sx16(input logic [15:0] v);
	sx16 = {{16{v[15]}}, v};
endfunction

// EA record from its extension words w0.. at instruction word offset p;
// pcb = pc + 2*p (the extension word's address, the PC-relative base),
// already added into bd for PC-relative modes
function automatic ea_t mk_ea(input logic [3:0] idx, input logic [2:0] r,
                              input logic [3:0] p, input logic [2:0] immlen,
                              input logic [31:0] pcb,
                              input logic [15:0] w0, input logic [15:0] w1,
                              input logic [15:0] w2, input logic [15:0] w3,
                              input logic [15:0] w4);
	ea_t e;
	logic [31:0] bdx, pcs;
	// the full-format base displacement (AX/PCX), formed for every mode, so
	// PC16 and PCX (exclusive) add the PC with one adder
	case (w0[5:4])
		2'd2:    bdx = sx16(w1);
		2'd3:    bdx = {w1, w2};
		default: bdx = 32'd0;
	endcase
	if (!w0[8]) bdx = {{24{w0[7]}}, w0[7:0]};
	pcs = pcb + ((idx == EM_PC16) ? sx16(w0) : bdx);
	e = '0;
	e.m    = idx;
	e.r    = r;
	e.xoff = p[2:0];
	case (idx)
		EM_AD16, EM_ABSW: e.bd = sx16(w0);
		EM_PC16: e.bd = pcs;
		EM_ABSL: e.bd = {w0, w1};
		EM_IMM:  e.bd = (immlen == 3'd1) ? {16'd0, w0} : {w0, w1};
		EM_AX, EM_PCX: begin
			e.xa = w0[15];
			e.xr = w0[14:12];
			e.xl = w0[11];
			e.sc = w0[10:9];
			if (w0[8]) begin
				logic [15:0] o0, o1;
				e.bs = w0[7];
				e.is = w0[6];
				case (w0[5:4])
					2'd2: begin o0 = w2; o1 = w3; end
					2'd3: begin o0 = w3; o1 = w4; end
					default: begin o0 = w1; o1 = w2; end
				endcase
				if (w0[1:0] != 2'd0)
					e.mi = (w0[2] && !w0[6]) ? 2'd2 : 2'd1;
				case (w0[1:0])
					2'd2: e.od = sx16(o0);
					2'd3: e.od = {o0, o1};
					default: e.od = 32'd0;
				endcase
			end
			// PC-relative with the base not suppressed: the PC is added here
			e.bd = (idx == EM_PCX && !e.bs) ? pcs : bdx;
		end
		default: ;
	endcase
	mk_ea = e;
endfunction

// effective first micro-instruction given the routine's leading jump
function automatic logic jcond(input logic [4:0] jc, input logic [3:0] e0,
                               input logic [3:0] e1, input logic [15:0] ext1,
                               input logic [1:0] s, input logic [2:0] ry);
	logic m0, m1;
	m0 = (e0 >= EM_AI) && (e0 != EM_IMM) && (e0 != EM_NONE);
	m1 = (e1 >= EM_AI) && (e1 != EM_IMM) && (e1 != EM_NONE);
	case (jc)
		JC_ALWAYS:   jcond = 1'b1;
		JC_EA0_MEM:  jcond = m0;
		JC_EA1_MEM:  jcond = m1;
		JC_EA0_REG:  jcond = (e0 == EM_DN) || (e0 == EM_AN);
		JC_EA0_DN:   jcond = (e0 == EM_DN);
		JC_EA0_AN:   jcond = (e0 == EM_AN);
		JC_EA0_IMM:  jcond = (e0 == EM_IMM);
		JC_NOT_EA0_MEM: jcond = !m0;
		JC_EXT11:    jcond = ext1[11];
		JC_EXT10:    jcond = ext1[10];
		JC_SZ_L:     jcond = (s == SZ_L);
		JC_SZ_B:     jcond = (s == SZ_B);
		JC_AY7:      jcond = (ry == 3'd7);
		JC_BOTH_MEM: jcond = m0 && m1;
		JC_MASK0:    jcond = (ext1 == 16'd0);
		JC_X1A:      jcond = ext1[15];
		JC_CREG_RF:  jcond = (ext1[11:0] == 12'h800) || (ext1[11:0] == 12'h803) ||
		                     (ext1[11:0] == 12'h804);
		JC_FP_OC0:   jcond = (ext1[15:13] == 3'b000);
		default:     jcond = 1'b0;
	endcase
endfunction

// FPU immediate length from the command word's source format
function automatic logic [2:0] fp_immlen(input logic [15:0] cmd);
	logic [2:0] crl;
	crl = (cmd[12:10] == 3'd0) ? 3'b001 : cmd[12:10];
	if (cmd[15:13] == 3'b100)
		// FMOVE(M) #imm to control registers: a long word each
		fp_immlen = {2'(crl[0]) + 2'(crl[1]) + 2'(crl[2]), 1'b0};
	else if (cmd[15:13] != 3'b010)
		fp_immlen = 3'd0;
	else case (cmd[12:10])
		3'd0, 3'd1: fp_immlen = 3'd2;   // L, S
		3'd2, 3'd3: fp_immlen = 3'd6;   // X, P
		3'd4, 3'd6: fp_immlen = 3'd1;   // W, B
		3'd5:       fp_immlen = 3'd4;   // D
		default:    fp_immlen = 3'd0;
	endcase
endfunction

// the 68040's control registers: SFC DFC CACR TC ITT0 ITT1 DTT0 DTT1
// ($000-$007), USP VBR MSP ISP MMUSR URP SRP ($800 $801, $803-$807: no CAAR)
function automatic logic movec_ok(input logic [11:0] r);
	movec_ok = (r[11:3] == 9'h000) || (r[11:3] == 9'h100 && r[2:0] != 3'd2);
endfunction

function automatic logic has_ext(input logic [3:0] i);
	has_ext = (i != EM_NONE) && (i >= EM_AD16);
endfunction

//--------------------------------------------------------------------------
// the instruction at the head: attributes of its decoder entry
//--------------------------------------------------------------------------
// the head's attributes: a ROM (block RAM) read with the head's entry a
// cycle ahead, so it lines up with pd0 -- not a 276-entry table in logic
pla_t a0;
(* romstyle = "M10K" *) logic [$bits(pla_t)-1:0] attr_rom [0:511];
initial begin
// ---- inlined from ap68040_attr_rom.svh (tools/import_ap68040.py) ----
// generated by tools/ucode.py - do not edit
// D1's attribute ROM contents (block RAM initialization)
for (int i = 0; i < 512; i++) attr_rom[i] = '0;
attr_rom[0] = {1'b1, 9'd0, 10'd4, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR IMM_OP
attr_rom[1] = {1'b1, 9'd1, 10'd4, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND IMM_OP
attr_rom[2] = {1'b1, 9'd2, 10'd4, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB IMM_OP
attr_rom[3] = {1'b1, 9'd3, 10'd4, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD IMM_OP
attr_rom[4] = {1'b1, 9'd4, 10'd4, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR IMM_OP
attr_rom[5] = {1'b1, 9'd5, 10'd5, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'h7fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP IMM_CMP
attr_rom[6] = {1'b1, 9'd6, 10'd215, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b1, 6'd9, 10'd224, 1'b1, 1'b0, 2'd0, 1'b1};  // MOVES MOVES
attr_rom[7] = {1'b1, 9'd7, 10'd4, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR IMM_OP
attr_rom[8] = {1'b1, 9'd8, 10'd4, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND IMM_OP
attr_rom[9] = {1'b1, 9'd9, 10'd4, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB IMM_OP
attr_rom[10] = {1'b1, 9'd10, 10'd4, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD IMM_OP
attr_rom[11] = {1'b1, 9'd11, 10'd4, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR IMM_OP
attr_rom[12] = {1'b1, 9'd12, 10'd5, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'h7fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP IMM_CMP
attr_rom[13] = {1'b1, 9'd13, 10'd215, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b1, 6'd9, 10'd224, 1'b1, 1'b0, 2'd0, 1'b1};  // MOVES MOVES
attr_rom[14] = {1'b1, 9'd14, 10'd4, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR IMM_OP
attr_rom[15] = {1'b1, 9'd15, 10'd4, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND IMM_OP
attr_rom[16] = {1'b1, 9'd16, 10'd4, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB IMM_OP
attr_rom[17] = {1'b1, 9'd17, 10'd4, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD IMM_OP
attr_rom[18] = {1'b1, 9'd18, 10'd4, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR IMM_OP
attr_rom[19] = {1'b1, 9'd19, 10'd5, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'h7fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP IMM_CMP
attr_rom[20] = {1'b1, 9'd20, 10'd215, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b1, 6'd9, 10'd224, 1'b1, 1'b0, 2'd0, 1'b1};  // MOVES MOVES
attr_rom[21] = {1'b1, 9'd21, 10'd109, 7'd42, 4'd1, 1'b1, 5'h0, 2'd0, 12'h000, 12'h000, 2'd0, 3'd2, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ORSR CCR_LOG
attr_rom[22] = {1'b1, 9'd22, 10'd110, 7'd42, 4'd1, 1'b1, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // ORSR SR_LOG
attr_rom[23] = {1'b1, 9'd23, 10'd109, 7'd42, 4'd0, 1'b1, 5'h0, 2'd0, 12'h000, 12'h000, 2'd0, 3'd2, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ANDSR CCR_LOG
attr_rom[24] = {1'b1, 9'd24, 10'd110, 7'd42, 4'd0, 1'b1, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // ANDSR SR_LOG
attr_rom[25] = {1'b1, 9'd25, 10'd109, 7'd42, 4'd2, 1'b1, 5'h0, 2'd0, 12'h000, 12'h000, 2'd0, 3'd2, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EORSR CCR_LOG
attr_rom[26] = {1'b1, 9'd26, 10'd110, 7'd42, 4'd2, 1'b1, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // EORSR SR_LOG
attr_rom[27] = {1'b1, 9'd27, 10'd197, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'h7e4, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CHK2 CHK2
attr_rom[28] = {1'b1, 9'd28, 10'd197, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h7e4, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CHK2 CHK2
attr_rom[29] = {1'b1, 9'd29, 10'd197, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e4, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CHK2 CHK2
attr_rom[30] = {1'b1, 9'd30, 10'd187, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // CAS CAS
attr_rom[31] = {1'b1, 9'd31, 10'd187, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // CAS CAS
attr_rom[32] = {1'b1, 9'd32, 10'd187, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // CAS CAS
attr_rom[33] = {1'b1, 9'd33, 10'd189, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd2, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CAS2 CAS2
attr_rom[34] = {1'b1, 9'd34, 10'd189, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd2, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CAS2 CAS2
attr_rom[35] = {1'b1, 9'd35, 10'd42, 7'd30, 4'd0, 1'b0, 5'h0, 2'd0, 12'h7fd, 12'h000, 2'd0, 3'd2, 1'b0, 6'd5, 10'd44, 1'b1, 1'b0, 2'd0, 1'b0};  // BTST BTST_IMM
attr_rom[36] = {1'b1, 9'd36, 10'd36, 7'd31, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd2, 1'b0, 6'd5, 10'd38, 1'b1, 1'b0, 2'd0, 1'b0};  // BCHG BIT_IMM
attr_rom[37] = {1'b1, 9'd37, 10'd36, 7'd32, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd2, 1'b0, 6'd5, 10'd38, 1'b1, 1'b0, 2'd0, 1'b0};  // BCLR BIT_IMM
attr_rom[38] = {1'b1, 9'd38, 10'd36, 7'd33, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd2, 1'b0, 6'd5, 10'd38, 1'b1, 1'b0, 2'd0, 1'b0};  // BSET BIT_IMM
attr_rom[39] = {1'b1, 9'd39, 10'd45, 7'd30, 4'd0, 1'b0, 5'h0, 2'd0, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd5, 10'd47, 1'b1, 1'b0, 2'd0, 1'b0};  // BTST BTST_DYN
attr_rom[40] = {1'b1, 9'd40, 10'd39, 7'd31, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd5, 10'd41, 1'b1, 1'b0, 2'd0, 1'b0};  // BCHG BIT_DYN
attr_rom[41] = {1'b1, 9'd41, 10'd39, 7'd32, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd5, 10'd41, 1'b1, 1'b0, 2'd0, 1'b0};  // BCLR BIT_DYN
attr_rom[42] = {1'b1, 9'd42, 10'd39, 7'd33, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd5, 10'd41, 1'b1, 1'b0, 2'd0, 1'b0};  // BSET BIT_DYN
attr_rom[43] = {1'b1, 9'd43, 10'd133, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // MVPMR MOVEP_MR
attr_rom[44] = {1'b1, 9'd44, 10'd133, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // MVPMR MOVEP_MR
attr_rom[45] = {1'b1, 9'd45, 10'd143, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd10, 10'd147, 1'b0, 1'b0, 2'd0, 1'b0};  // MVPRM MOVEP_RM
attr_rom[46] = {1'b1, 9'd46, 10'd143, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd10, 10'd147, 1'b0, 1'b0, 2'd0, 1'b0};  // MVPRM MOVEP_RM
attr_rom[47] = {1'b1, 9'd47, 10'd32, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'hffd, 12'h1fd, 2'd0, 3'd0, 1'b0, 6'd12, 10'd34, 1'b1, 1'b1, 2'd0, 1'b0};  // MOVE MOVE
attr_rom[48] = {1'b1, 9'd48, 10'd32, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hfff, 12'h1fd, 2'd0, 3'd0, 1'b0, 6'd12, 10'd34, 1'b1, 1'b1, 2'd0, 1'b0};  // MOVE MOVE
attr_rom[49] = {1'b1, 9'd49, 10'd32, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h1fd, 2'd0, 3'd0, 1'b0, 6'd12, 10'd34, 1'b1, 1'b1, 2'd0, 1'b0};  // MOVE MOVE
attr_rom[50] = {1'b1, 9'd50, 10'd29, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd2, 10'd31, 1'b1, 1'b0, 2'd0, 1'b0};  // MOVEA MOVEA
attr_rom[51] = {1'b1, 9'd51, 10'd29, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd2, 10'd31, 1'b1, 1'b0, 2'd0, 1'b0};  // MOVEA MOVEA
attr_rom[52] = {1'b1, 9'd52, 10'd10, 7'd11, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEGX UNARY
attr_rom[53] = {1'b1, 9'd53, 10'd13, 7'd12, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CLR CLR_W
attr_rom[54] = {1'b1, 9'd54, 10'd10, 7'd10, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEG UNARY
attr_rom[55] = {1'b1, 9'd55, 10'd10, 7'd9, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NOT UNARY
attr_rom[56] = {1'b1, 9'd56, 10'd11, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // TST TST
attr_rom[57] = {1'b1, 9'd57, 10'd10, 7'd11, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEGX UNARY
attr_rom[58] = {1'b1, 9'd58, 10'd13, 7'd12, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CLR CLR_W
attr_rom[59] = {1'b1, 9'd59, 10'd10, 7'd10, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEG UNARY
attr_rom[60] = {1'b1, 9'd60, 10'd10, 7'd9, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NOT UNARY
attr_rom[61] = {1'b1, 9'd61, 10'd11, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // TST TST
attr_rom[62] = {1'b1, 9'd62, 10'd10, 7'd11, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEGX UNARY
attr_rom[63] = {1'b1, 9'd63, 10'd13, 7'd12, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CLR CLR_W
attr_rom[64] = {1'b1, 9'd64, 10'd10, 7'd10, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEG UNARY
attr_rom[65] = {1'b1, 9'd65, 10'd10, 7'd9, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NOT UNARY
attr_rom[66] = {1'b1, 9'd66, 10'd11, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // TST TST
attr_rom[67] = {1'b1, 9'd67, 10'd105, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // MVSR2 MOVE_FROM_SR
attr_rom[68] = {1'b1, 9'd68, 10'd106, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // MVSR2 MOVE_FROM_CCR
attr_rom[69] = {1'b1, 9'd69, 10'd107, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // MV2SR MOVE_TO_CCR
attr_rom[70] = {1'b1, 9'd70, 10'd108, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // MV2SR MOVE_TO_SR
attr_rom[71] = {1'b1, 9'd71, 10'd98, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd4, 1'b0, 6'd11, 10'd102, 1'b0, 1'b0, 2'd0, 1'b0};  // LINK LINK
attr_rom[72] = {1'b1, 9'd72, 10'd10, 7'd19, 4'd0, 1'b0, 5'h1f, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NBCD UNARY
attr_rom[73] = {1'b1, 9'd73, 10'd114, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // BKPT BKPT
attr_rom[74] = {1'b1, 9'd74, 10'd14, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SWAP SWAP
attr_rom[75] = {1'b1, 9'd75, 10'd27, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e4, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // PEA PEA
attr_rom[76] = {1'b1, 9'd76, 10'd15, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXT EXT
attr_rom[77] = {1'b1, 9'd77, 10'd15, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXT EXT
attr_rom[78] = {1'b1, 9'd78, 10'd16, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXT EXTB
attr_rom[79] = {1'b1, 9'd79, 10'd125, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h1f4, 12'h000, 2'd1, 3'd0, 1'b0, 6'd13, 10'd127, 1'b1, 1'b0, 2'd0, 1'b0};  // MVMLE MOVEM_RM
attr_rom[80] = {1'b1, 9'd80, 10'd125, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1f4, 12'h000, 2'd1, 3'd0, 1'b0, 6'd13, 10'd127, 1'b1, 1'b0, 2'd0, 1'b0};  // MVMLE MOVEM_RM
attr_rom[81] = {1'b1, 9'd81, 10'd128, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h7ec, 12'h000, 2'd1, 3'd0, 1'b0, 6'd13, 10'd130, 1'b1, 1'b0, 2'd0, 1'b0};  // MVMEL MOVEM_MR
attr_rom[82] = {1'b1, 9'd82, 10'd128, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7ec, 12'h000, 2'd1, 3'd0, 1'b0, 6'd13, 10'd130, 1'b1, 1'b0, 2'd0, 1'b0};  // MVMEL MOVEM_MR
attr_rom[83] = {1'b1, 9'd83, 10'd17, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // TAS TAS
attr_rom[84] = {1'b1, 9'd84, 10'd0, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ILLG ILLEGAL
attr_rom[85] = {1'b1, 9'd85, 10'd67, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hffd, 12'h000, 2'd1, 3'd0, 1'b0, 6'd15, 10'd69, 1'b1, 1'b0, 2'd0, 1'b0};  // MULL MULL
attr_rom[86] = {1'b1, 9'd86, 10'd72, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hffd, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // DIVL DIVL
attr_rom[87] = {1'b1, 9'd87, 10'd113, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // TRAP TRAP
attr_rom[88] = {1'b1, 9'd88, 10'd98, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd11, 10'd102, 1'b0, 1'b0, 2'd0, 1'b0};  // LINK LINK
attr_rom[89] = {1'b1, 9'd89, 10'd104, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // UNLK UNLK
attr_rom[90] = {1'b1, 9'd90, 10'd111, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // MVR2USP MOVE_TO_USP
attr_rom[91] = {1'b1, 9'd91, 10'd112, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // MVUSP2R MOVE_FROM_USP
attr_rom[92] = {1'b1, 9'd92, 10'd117, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // RESET RESET
attr_rom[93] = {1'b1, 9'd93, 10'd116, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // NOP NOP
attr_rom[94] = {1'b1, 9'd94, 10'd118, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // STOP STOP
attr_rom[95] = {1'b1, 9'd95, 10'd202, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // RTE RTE
attr_rom[96] = {1'b1, 9'd96, 10'd94, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // RTD RTD
attr_rom[97] = {1'b1, 9'd97, 10'd93, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // RTS RTS
attr_rom[98] = {1'b1, 9'd98, 10'd97, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // TRAPV TRAPV
attr_rom[99] = {1'b1, 9'd99, 10'd212, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // RTR RTR
attr_rom[100] = {1'b1, 9'd100, 10'd119, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd0, 1'b1, 6'd16, 10'd121, 1'b0, 1'b0, 2'd0, 1'b0};  // MOVEC2 MOVEC_RD
attr_rom[101] = {1'b1, 9'd101, 10'd122, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd0, 1'b1, 6'd16, 10'd124, 1'b0, 1'b0, 2'd0, 1'b1};  // MOVE2C MOVEC_WR
attr_rom[102] = {1'b1, 9'd102, 10'd90, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e4, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // JSR JSR
attr_rom[103] = {1'b1, 9'd103, 10'd89, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e4, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // JMP JMP
attr_rom[104] = {1'b1, 9'd104, 10'd76, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CHK CHK
attr_rom[105] = {1'b1, 9'd105, 10'd76, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CHK CHK
attr_rom[106] = {1'b1, 9'd106, 10'd26, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e4, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // LEA LEA
attr_rom[107] = {1'b1, 9'd107, 10'd8, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD QUICK
attr_rom[108] = {1'b1, 9'd108, 10'd8, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB QUICK
attr_rom[109] = {1'b1, 9'd109, 10'd8, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD QUICK
attr_rom[110] = {1'b1, 9'd110, 10'd8, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB QUICK
attr_rom[111] = {1'b1, 9'd111, 10'd8, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD QUICK
attr_rom[112] = {1'b1, 9'd112, 10'd8, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB QUICK
attr_rom[113] = {1'b1, 9'd113, 10'd24, 7'd1, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ADDA QUICK_A
attr_rom[114] = {1'b1, 9'd114, 10'd24, 7'd1, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ADDA QUICK_A
attr_rom[115] = {1'b1, 9'd115, 10'd25, 7'd3, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SUBA QUICK_SA
attr_rom[116] = {1'b1, 9'd116, 10'd25, 7'd3, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SUBA QUICK_SA
attr_rom[117] = {1'b1, 9'd117, 10'd12, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // Scc SCC
attr_rom[118] = {1'b1, 9'd118, 10'd88, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // DBcc DBCC
attr_rom[119] = {1'b1, 9'd119, 10'd96, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // TRAPcc TRAPCC
attr_rom[120] = {1'b1, 9'd120, 10'd96, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // TRAPcc TRAPCC
attr_rom[121] = {1'b1, 9'd121, 10'd96, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // TRAPcc TRAPCC
attr_rom[122] = {1'b1, 9'd122, 10'd87, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd5, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // BSR BSR
attr_rom[123] = {1'b1, 9'd123, 10'd86, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd5, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // Bcc BCC
attr_rom[124] = {1'b1, 9'd124, 10'd9, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // MOVE MOVEQ
attr_rom[125] = {1'b1, 9'd125, 10'd2, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_EA_DN
attr_rom[126] = {1'b1, 9'd126, 10'd3, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_DN_EA
attr_rom[127] = {1'b1, 9'd127, 10'd2, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_EA_DN
attr_rom[128] = {1'b1, 9'd128, 10'd3, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_DN_EA
attr_rom[129] = {1'b1, 9'd129, 10'd2, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_EA_DN
attr_rom[130] = {1'b1, 9'd130, 10'd3, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_DN_EA
attr_rom[131] = {1'b1, 9'd131, 10'd2, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_EA_DN
attr_rom[132] = {1'b1, 9'd132, 10'd3, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_DN_EA
attr_rom[133] = {1'b1, 9'd133, 10'd6, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP CMP_EA_DN
attr_rom[134] = {1'b1, 9'd134, 10'd3, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR OP_DN_EA
attr_rom[135] = {1'b1, 9'd135, 10'd53, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd1, 1'b0};  // CMPM CMPM
attr_rom[136] = {1'b1, 9'd136, 10'd50, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SUBX ADDX_R
attr_rom[137] = {1'b1, 9'd137, 10'd51, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // SUBX ADDX_M
attr_rom[138] = {1'b1, 9'd138, 10'd50, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ADDX ADDX_R
attr_rom[139] = {1'b1, 9'd139, 10'd51, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // ADDX ADDX_M
attr_rom[140] = {1'b1, 9'd140, 10'd2, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_EA_DN
attr_rom[141] = {1'b1, 9'd141, 10'd3, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_DN_EA
attr_rom[142] = {1'b1, 9'd142, 10'd2, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_EA_DN
attr_rom[143] = {1'b1, 9'd143, 10'd3, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_DN_EA
attr_rom[144] = {1'b1, 9'd144, 10'd2, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_EA_DN
attr_rom[145] = {1'b1, 9'd145, 10'd3, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_DN_EA
attr_rom[146] = {1'b1, 9'd146, 10'd2, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_EA_DN
attr_rom[147] = {1'b1, 9'd147, 10'd3, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_DN_EA
attr_rom[148] = {1'b1, 9'd148, 10'd6, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP CMP_EA_DN
attr_rom[149] = {1'b1, 9'd149, 10'd3, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR OP_DN_EA
attr_rom[150] = {1'b1, 9'd150, 10'd53, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd1, 1'b0};  // CMPM CMPM
attr_rom[151] = {1'b1, 9'd151, 10'd50, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SUBX ADDX_R
attr_rom[152] = {1'b1, 9'd152, 10'd51, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // SUBX ADDX_M
attr_rom[153] = {1'b1, 9'd153, 10'd50, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ADDX ADDX_R
attr_rom[154] = {1'b1, 9'd154, 10'd51, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // ADDX ADDX_M
attr_rom[155] = {1'b1, 9'd155, 10'd2, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_EA_DN
attr_rom[156] = {1'b1, 9'd156, 10'd3, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_DN_EA
attr_rom[157] = {1'b1, 9'd157, 10'd2, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_EA_DN
attr_rom[158] = {1'b1, 9'd158, 10'd3, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_DN_EA
attr_rom[159] = {1'b1, 9'd159, 10'd2, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_EA_DN
attr_rom[160] = {1'b1, 9'd160, 10'd3, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_DN_EA
attr_rom[161] = {1'b1, 9'd161, 10'd2, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_EA_DN
attr_rom[162] = {1'b1, 9'd162, 10'd3, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_DN_EA
attr_rom[163] = {1'b1, 9'd163, 10'd6, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP CMP_EA_DN
attr_rom[164] = {1'b1, 9'd164, 10'd3, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR OP_DN_EA
attr_rom[165] = {1'b1, 9'd165, 10'd53, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd1, 1'b0};  // CMPM CMPM
attr_rom[166] = {1'b1, 9'd166, 10'd50, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SUBX ADDX_R
attr_rom[167] = {1'b1, 9'd167, 10'd51, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // SUBX ADDX_M
attr_rom[168] = {1'b1, 9'd168, 10'd50, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ADDX ADDX_R
attr_rom[169] = {1'b1, 9'd169, 10'd51, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // ADDX ADDX_M
attr_rom[170] = {1'b1, 9'd170, 10'd66, 7'd49, 4'd0, 1'b0, 5'hf, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // DIVU DIVW
attr_rom[171] = {1'b1, 9'd171, 10'd66, 7'd49, 4'd1, 1'b1, 5'hf, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // DIVS DIVW
attr_rom[172] = {1'b1, 9'd172, 10'd65, 7'd48, 4'd0, 1'b0, 5'hf, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // MULU MULW
attr_rom[173] = {1'b1, 9'd173, 10'd65, 7'd48, 4'd1, 1'b1, 5'hf, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // MULS MULW
attr_rom[174] = {1'b1, 9'd174, 10'd50, 7'd18, 4'd0, 1'b0, 5'h1f, 2'd0, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SBCD ADDX_R
attr_rom[175] = {1'b1, 9'd175, 10'd51, 7'd18, 4'd0, 1'b0, 5'h1f, 2'd0, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // SBCD ADDX_M
attr_rom[176] = {1'b1, 9'd176, 10'd50, 7'd17, 4'd0, 1'b0, 5'h1f, 2'd0, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ABCD ADDX_R
attr_rom[177] = {1'b1, 9'd177, 10'd51, 7'd17, 4'd0, 1'b0, 5'h1f, 2'd0, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // ABCD ADDX_M
attr_rom[178] = {1'b1, 9'd178, 10'd55, 7'd20, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // PACK PACK_R
attr_rom[179] = {1'b1, 9'd179, 10'd57, 7'd20, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // PACK PACK_M
attr_rom[180] = {1'b1, 9'd180, 10'd60, 7'd21, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // UNPK UNPK_R
attr_rom[181] = {1'b1, 9'd181, 10'd62, 7'd21, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // UNPK UNPK_M
attr_rom[182] = {1'b1, 9'd182, 10'd21, 7'd3, 4'd0, 1'b0, 5'h0, 2'd1, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd7, 10'd23, 1'b1, 1'b0, 2'd0, 1'b0};  // SUBA SUBA
attr_rom[183] = {1'b1, 9'd183, 10'd21, 7'd3, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd7, 10'd23, 1'b1, 1'b0, 2'd0, 1'b0};  // SUBA SUBA
attr_rom[184] = {1'b1, 9'd184, 10'd18, 7'd1, 4'd0, 1'b0, 5'h0, 2'd1, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd2, 10'd20, 1'b1, 1'b0, 2'd0, 1'b0};  // ADDA ADDA
attr_rom[185] = {1'b1, 9'd185, 10'd18, 7'd1, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd2, 10'd20, 1'b1, 1'b0, 2'd0, 1'b0};  // ADDA ADDA
attr_rom[186] = {1'b1, 9'd186, 10'd7, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMPA CMPA
attr_rom[187] = {1'b1, 9'd187, 10'd7, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMPA CMPA
attr_rom[188] = {1'b1, 9'd188, 10'd77, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXG EXG_DD
attr_rom[189] = {1'b1, 9'd189, 10'd80, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXG EXG_AA
attr_rom[190] = {1'b1, 9'd190, 10'd83, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXG EXG_DA
attr_rom[191] = {1'b1, 9'd191, 10'd48, 7'd23, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASR SHIFT_R
attr_rom[192] = {1'b1, 9'd192, 10'd48, 7'd22, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASL SHIFT_R
attr_rom[193] = {1'b1, 9'd193, 10'd48, 7'd25, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSR SHIFT_R
attr_rom[194] = {1'b1, 9'd194, 10'd48, 7'd24, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSL SHIFT_R
attr_rom[195] = {1'b1, 9'd195, 10'd48, 7'd29, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXR SHIFT_R
attr_rom[196] = {1'b1, 9'd196, 10'd48, 7'd28, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXL SHIFT_R
attr_rom[197] = {1'b1, 9'd197, 10'd48, 7'd27, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROR SHIFT_R
attr_rom[198] = {1'b1, 9'd198, 10'd48, 7'd26, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROL SHIFT_R
attr_rom[199] = {1'b1, 9'd199, 10'd48, 7'd23, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASR SHIFT_R
attr_rom[200] = {1'b1, 9'd200, 10'd48, 7'd22, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASL SHIFT_R
attr_rom[201] = {1'b1, 9'd201, 10'd48, 7'd25, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSR SHIFT_R
attr_rom[202] = {1'b1, 9'd202, 10'd48, 7'd24, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSL SHIFT_R
attr_rom[203] = {1'b1, 9'd203, 10'd48, 7'd29, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXR SHIFT_R
attr_rom[204] = {1'b1, 9'd204, 10'd48, 7'd28, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXL SHIFT_R
attr_rom[205] = {1'b1, 9'd205, 10'd48, 7'd27, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROR SHIFT_R
attr_rom[206] = {1'b1, 9'd206, 10'd48, 7'd26, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROL SHIFT_R
attr_rom[207] = {1'b1, 9'd207, 10'd48, 7'd23, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASR SHIFT_R
attr_rom[208] = {1'b1, 9'd208, 10'd48, 7'd22, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASL SHIFT_R
attr_rom[209] = {1'b1, 9'd209, 10'd48, 7'd25, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSR SHIFT_R
attr_rom[210] = {1'b1, 9'd210, 10'd48, 7'd24, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSL SHIFT_R
attr_rom[211] = {1'b1, 9'd211, 10'd48, 7'd29, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXR SHIFT_R
attr_rom[212] = {1'b1, 9'd212, 10'd48, 7'd28, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXL SHIFT_R
attr_rom[213] = {1'b1, 9'd213, 10'd48, 7'd27, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROR SHIFT_R
attr_rom[214] = {1'b1, 9'd214, 10'd48, 7'd26, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROL SHIFT_R
attr_rom[215] = {1'b1, 9'd215, 10'd49, 7'd23, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ASRW SHIFT_M
attr_rom[216] = {1'b1, 9'd216, 10'd49, 7'd22, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ASLW SHIFT_M
attr_rom[217] = {1'b1, 9'd217, 10'd49, 7'd25, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // LSRW SHIFT_M
attr_rom[218] = {1'b1, 9'd218, 10'd49, 7'd24, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // LSLW SHIFT_M
attr_rom[219] = {1'b1, 9'd219, 10'd49, 7'd29, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ROXRW SHIFT_M
attr_rom[220] = {1'b1, 9'd220, 10'd49, 7'd28, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ROXLW SHIFT_M
attr_rom[221] = {1'b1, 9'd221, 10'd49, 7'd27, 4'd0, 1'b0, 5'hf, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // RORW SHIFT_M
attr_rom[222] = {1'b1, 9'd222, 10'd49, 7'd26, 4'd0, 1'b0, 5'hf, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ROLW SHIFT_M
attr_rom[223] = {1'b1, 9'd223, 10'd154, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd162, 1'b1, 1'b0, 2'd0, 1'b0};  // BFTST BF_TST
attr_rom[224] = {1'b1, 9'd224, 10'd164, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd172, 1'b1, 1'b0, 2'd0, 1'b0};  // BFEXTU BF_EXT
attr_rom[225] = {1'b1, 9'd225, 10'd174, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd185, 1'b1, 1'b0, 2'd0, 1'b0};  // BFCHG BF_MOD
attr_rom[226] = {1'b1, 9'd226, 10'd164, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd172, 1'b1, 1'b0, 2'd0, 1'b0};  // BFEXTS BF_EXT
attr_rom[227] = {1'b1, 9'd227, 10'd174, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd185, 1'b1, 1'b0, 2'd0, 1'b0};  // BFCLR BF_MOD
attr_rom[228] = {1'b1, 9'd228, 10'd164, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd172, 1'b1, 1'b0, 2'd0, 1'b0};  // BFFFO BF_EXT
attr_rom[229] = {1'b1, 9'd229, 10'd174, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd185, 1'b1, 1'b0, 2'd0, 1'b0};  // BFSET BF_MOD
attr_rom[230] = {1'b1, 9'd230, 10'd174, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd185, 1'b1, 1'b0, 2'd0, 1'b0};  // BFINS BF_MOD
attr_rom[231] = {1'b1, 9'd231, 10'd228, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h000, 2'd1, 3'd0, 1'b0, 6'd19, 10'd237, 1'b1, 1'b0, 2'd0, 1'b0};  // FPP FPU_GEN
attr_rom[232] = {1'b1, 9'd232, 10'd482, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // FScc FSCC
attr_rom[233] = {1'b1, 9'd233, 10'd484, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd1, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // FDBcc FDBCC
attr_rom[234] = {1'b1, 9'd234, 10'd486, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // FTRAPcc FTRAPCC
attr_rom[235] = {1'b1, 9'd235, 10'd486, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // FTRAPcc FTRAPCC
attr_rom[236] = {1'b1, 9'd236, 10'd486, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // FTRAPcc FTRAPCC
attr_rom[237] = {1'b1, 9'd237, 10'd480, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd7, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // FBcc FBCC
attr_rom[238] = {1'b1, 9'd238, 10'd480, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd7, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // FBcc FBCC
attr_rom[239] = {1'b1, 9'd239, 10'd488, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1f4, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // FSAVE FSAVE
attr_rom[240] = {1'b1, 9'd240, 10'd546, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7ec, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // FRESTORE FRESTORE
attr_rom[241] = {1'b1, 9'd241, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVL CACHE_OP
attr_rom[242] = {1'b1, 9'd242, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVP CACHE_OP
attr_rom[243] = {1'b1, 9'd243, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVA CACHE_OP
attr_rom[244] = {1'b1, 9'd244, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHL CACHE_OP
attr_rom[245] = {1'b1, 9'd245, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHP CACHE_OP
attr_rom[246] = {1'b1, 9'd246, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHA CACHE_OP
attr_rom[247] = {1'b1, 9'd247, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVL CACHE_OP
attr_rom[248] = {1'b1, 9'd248, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVP CACHE_OP
attr_rom[249] = {1'b1, 9'd249, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVA CACHE_OP
attr_rom[250] = {1'b1, 9'd250, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHL CACHE_OP
attr_rom[251] = {1'b1, 9'd251, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHP CACHE_OP
attr_rom[252] = {1'b1, 9'd252, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHA CACHE_OP
attr_rom[253] = {1'b1, 9'd253, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVL CACHE_OP
attr_rom[254] = {1'b1, 9'd254, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVP CACHE_OP
attr_rom[255] = {1'b1, 9'd255, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVA CACHE_OP
attr_rom[256] = {1'b1, 9'd256, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHL CACHE_OP
attr_rom[257] = {1'b1, 9'd257, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHP CACHE_OP
attr_rom[258] = {1'b1, 9'd258, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHA CACHE_OP
attr_rom[259] = {1'b1, 9'd259, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVL CACHE_OP
attr_rom[260] = {1'b1, 9'd260, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVP CACHE_OP
attr_rom[261] = {1'b1, 9'd261, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVA CACHE_OP
attr_rom[262] = {1'b1, 9'd262, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHL CACHE_OP
attr_rom[263] = {1'b1, 9'd263, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHP CACHE_OP
attr_rom[264] = {1'b1, 9'd264, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHA CACHE_OP
attr_rom[265] = {1'b1, 9'd265, 10'd226, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PFLUSHN PFLUSH
attr_rom[266] = {1'b1, 9'd266, 10'd226, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PFLUSH PFLUSH
attr_rom[267] = {1'b1, 9'd267, 10'd226, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PFLUSHAN PFLUSH
attr_rom[268] = {1'b1, 9'd268, 10'd226, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PFLUSHA PFLUSH
attr_rom[269] = {1'b1, 9'd269, 10'd227, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PTESTW PTEST
attr_rom[270] = {1'b1, 9'd270, 10'd227, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PTESTR PTEST
attr_rom[271] = {1'b1, 9'd271, 10'd131, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd4, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd3, 1'b0};  // MOVE16 MOVE16
attr_rom[272] = {1'b1, 9'd272, 10'd131, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd4, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd3, 1'b0};  // MOVE16 MOVE16
attr_rom[273] = {1'b1, 9'd273, 10'd131, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd4, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd3, 1'b0};  // MOVE16 MOVE16
attr_rom[274] = {1'b1, 9'd274, 10'd131, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd4, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd3, 1'b0};  // MOVE16 MOVE16
attr_rom[275] = {1'b1, 9'd275, 10'd131, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd3, 1'b0};  // MOVE16 MOVE16
// ---- end of ap68040_attr_rom.svh ----
end
logic [$bits(pla_t)-1:0] attr_q;
always_ff @(posedge clk) attr_q <= attr_rom[pd0_n.ent];
always_comb a0 = pd0.legal ? pla_t'(attr_q) : '0;
// synthesis translate_off
always_ff @(posedge clk)
	if (nreset && a0 != ent_attr(pd0.ent, pd0.legal)) begin
		$display("FAIL: decode: the attribute ROM's %h, the table's %h (entry %0d)",
		         a0, ent_attr(pd0.ent, pd0.legal), pd0.ent);
		$finish;
	end
// synthesis translate_on
wire [15:0] opw = win[0];

// An FPU general instruction of opclass 000 (register to register): the
// source is FPm and its EA field is not evaluated, so it has no extension
// words -- the next instruction follows the command word (the 68881
// protocol asks the CPU for no EA, the 68040 the same; WinUAE's
// get_fp_value).  The predecode sized the EA from the operation word
// alone; this one, from the command word, is the decode's.  (Its mode set
// stays FPP's: an invalid mode is still illegal.)
wire  fp_rr = (a0.rt == UA_FPU_GEN) && (win[1][15:13] == 3'b000);
pd_t  pdx;
always_comb begin
	pdx = pd0;
	if (fp_rr) begin
		pdx.i0   = EM_NONE;
		pdx.x0   = 1'b0;
		pdx.slow = 1'b0;
		pdx.p1   = pd0.b;
		pdx.tot  = {1'b0, pd0.b};
	end
end

//--------------------------------------------------------------------------
// state
//--------------------------------------------------------------------------
typedef enum logic [1:0] { PH_IDLE, PH_EA0, PH_EA1 } ph_t;
ph_t         ph;
dinst_t      part;          // record under construction (slow path)
pd_t         part_pd;
logic  [3:0] part_len;      // words consumed so far
logic  [2:0] part_imml;     // EA0 immediate length (slow path)
logic        hold_redir;    // a predicted branch is redirecting fetch

//--------------------------------------------------------------------------
// fast path
//--------------------------------------------------------------------------
wire  [2:0] fb    = pdx.b;
wire  [2:0] fp1   = pdx.p1;
wire        full0 = pdx.x0 && win[fb][8];
wire        full1 = pdx.x1 && win[fp1][8];
wire        fast  = pdx.legal && !pdx.slow && !full0 && !full1 && (pdx.tot <= 4'd7);

//--------------------------------------------------------------------------
// record assembly
//--------------------------------------------------------------------------
dinst_t      nrec;
wire  [31:0] nrec_npc = nrec.pc + {27'd0, nrec.ilen, 1'b0};   // the next instruction
logic        go;            // a record is produced
logic        go_part;       // a slow-path phase completes (no record yet)
logic  [3:0] use_n;
logic        flt;

// A fetch fault is raised for the lowest faulted word of the window (the
// words before it are good, so it is the first faulted word an instruction
// uses).  Codes: EXC_IFB a bus error, EXC_IFA an ATC fault, on a demand
// fetch; EXC_IFS/EXC_IFSA the same on a speculative prefetch, which the
// back end refetches on demand first.  The record's target carries the
// faulting word's address (the format $7 fault address).
logic  [7:0] f_code;
logic [31:0] f_addr;
// A faulted word in the queue is the last one fetch delivers until a
// redirect (it waits in S_HALT), so an instruction that needs more words
// than the queue holds is decoded with what is there: its words reach the
// faulted one, and it takes the fault.  Waiting for the rest would wait
// forever -- an opword fault at an address with A1 set queues ONE word,
// shorter than the two-word instruction its zero word decodes as.
wire   [8:0] q_mask = (9'd1 << qcnt) - 9'd1;
wire         q_flt  = |(win_flt & q_mask[7:0]);
always_comb begin
	logic [2:0] fi;
	fi = 3'd0;
	for (int i = 7; i >= 0; i--) if (win_flt[i]) fi = 3'(i);
	f_addr = qpc + {28'd0, fi, 1'b0};
	f_code = win_fdem[fi] ? (win_fatc[fi] ? EXC_IFA : EXC_IFB)
	                      : (win_fatc[fi] ? EXC_IFSA : EXC_IFS);
end
logic [31:0] ntarget;
// ntarget == bt_tgt without the target adder: a PC-relative target
// qpc + 2 + disp equals bt_tgt exactly when disp == bt_tgt - qpc - 2,
// which is formed from registers alongside the decode (the BTB check
// ends in btb_we and d_redir_v)
logic        teq;
logic        jsr_k;       // a JSR to a known target (see nrec_q)
// a call (BSR, JSR) or a return (RTS), for the return stacks: from the
// decoder's entry (the record's routine is past a first jump D1 resolved,
// which is a longer path), kept from the first part of a multi-part decode
logic        part_call, part_ret, part_fpg;
wire         rcall = (ph == PH_IDLE) ? (a0.rt == UA_BSR || a0.rt == UA_JSR) : part_call;
wire         rret  = (ph == PH_IDLE) ? (a0.rt == UA_RTS) : part_ret;
// an FPU general instruction (the decoder's entry FPU_GEN)
wire         fpg   = (ph == PH_IDLE) ? (a0.rt == UA_FPU_GEN) : part_fpg;
// its straight-line routine for the common forms (FPU_GEN's paths without
// their jump words), else the record's own
function automatic logic [9:0] fpu_k(input logic [15:0] x, input logic [3:0] m,
                                    input logic [9:0] dflt);
	fpu_k = dflt;
	if (x[15:13] == 3'b010 && x[12:10] != 3'd7 && m != EM_AN) begin
		if (m == EM_DN) fpu_k = UA_FPU_K_IND;
		else case (x[12:10])
			3'd0, 3'd1: fpu_k = UA_FPU_K_IN4;
			3'd6:       fpu_k = UA_FPU_K_IN1;
			3'd4:       fpu_k = UA_FPU_K_IN2;
			3'd5:       fpu_k = UA_FPU_K_IN8;
			3'd2, 3'd3: fpu_k = UA_FPU_K_IN12;
			default: ;
		endcase
	end
	else if (x[15:13] == 3'b011 && m != EM_AN) begin
		if (m == EM_DN) fpu_k = UA_FPU_K_OUTD;
		else case (x[12:10])
			3'd0, 3'd1: fpu_k = UA_FPU_K_OUT4;
			3'd6:       fpu_k = UA_FPU_K_OUT1;
			3'd4:       fpu_k = UA_FPU_K_OUT2;
			3'd5:       fpu_k = UA_FPU_K_OUT8;
			3'd2:       fpu_k = UA_FPU_K_OUT12;
			default: ;
		endcase
	end
endfunction
wire  [31:0] bt_d2 = bt_tgt - qpc - 32'd2;
// synthesis translate_off
always @(posedge clk)
	if (nreset && push && ph == PH_IDLE && bt_end && nrec.pred && teq != (ntarget == bt_tgt))
		$display("DECODE: teq %b disagrees with the target compare at %h", teq, qpc);
// synthesis translate_on
ph_t         nph;

// Branch prediction at D1 (the back end verifies every prediction in EX):
//  * Bcc: the static rule (backward taken), overruled by a 256-entry
//    history table of 2-bit counters indexed by PC[8:1].  A counter counts
//    how often the branch disagreed with the static rule, so the power-up
//    zeros mean "static"; at 2 or more the prediction is inverted.
//  * JSR/JMP to an absolute or PC-relative address: the target.
//  * RTS: an 8-entry return stack, pushed by BSR/JSR records, popped by
//    RTS records (not repaired after a redirect: a wrong entry only costs
//    the redirect EX would have made anyway).
logic  [1:0] bht_q;
// (declared before their use: Vivado 2018.3 makes a separate implicit net of a
// signal an instance is connected to ahead of its declaration)
logic        bw_we;
logic  [7:0] bw_wa;
logic  [1:0] bw_wd;
ap68040_lutram #(.AW(8), .DW(2)) bht (
	.clk(clk), .we(bw_we), .waddr(bw_wa), .wdata(bw_wd), .raddr(qpc[8:1]), .q(bht_q)
);
// training counts from the table's current value (a copy read at the
// training address), not from the value D1 read when it decoded the
// branch: two passes of a short loop are often decoded before the first
// one is trained.  The copy is a block RAM: the training request is
// registered with its read address, and the clock after it the counter is
// read, updated and written to both copies.  A write in the clock the RAM
// registered the read (the request just before, to the same counter) is
// not in what it returns: that write's value is taken instead.
logic  [1:0] bht_t, bht_c, bht_nd;
logic        tr_v, tr_dis;           // the training request, a clock on
logic  [7:0] tr_a;
logic        wq_v;                   // the write of the clock before
logic  [7:0] wq_a;
logic  [1:0] wq_d;
ap68040_sdpr #(.AW(8), .DW(2)) bht_tr (
	.clk(clk), .we(bw_we), .waddr(bw_wa), .wdata(bw_wd), .raddr(bht_wa), .q(bht_t)
);
assign bht_c  = (wq_v && wq_a == tr_a) ? wq_d : bht_t;
assign bht_nd = tr_dis ? ((bht_c == 2'd3) ? 2'd3 : bht_c + 2'd1)
                       : ((bht_c == 2'd0) ? 2'd0 : bht_c - 2'd1);
assign bw_we  = tr_v;
assign bw_wa  = tr_a;
assign bw_wd  = bht_nd;
always_ff @(posedge clk) begin
	tr_v   <= nreset && bht_we;
	tr_a   <= bht_wa;
	tr_dis <= bht_dis;
	wq_v   <= bw_we;
	wq_a   <= bw_wa;
	wq_d   <= bw_wd;
end
// (a LUT RAM: one push, one read at the top and one at the pointer the
// fetch resynchronizes to; never cleared -- an entry is read only below
// the count of entries pushed)
// (one read, at the pointer the fetch resynchronizes to: the prediction's
// read at ras_tp is the same unless a redirect restored the pointer, and
// the redirect flushes D1 -- two read addresses kept the stack in logic)
(* ramstyle = "MLAB, no_rw_check" *) logic [31:0] ras [8];
wire [31:0] ras_top = ras[ras_tp_o];
logic  [2:0] ras_tp;           // the top entry
logic  [3:0] ras_n;            // entries held (0..8)

// Loop exits: a backward Bcc/DBcc that has been taken the same number of
// times (the trip) before falling through, twice running, is predicted to
// fall through when its count comes round again.  EX trains the count of
// each entry (lp_cnt: taken since the last exit); D1 counts the same
// branch as it predicts it (lp_sp), ahead of EX by the instances in
// flight, and goes back to EX's count after every flush (lp_sync: until
// the first record after it).  lp_x is registered: confident and lp_sp
// at the trip.  8 entries, tagged with pc[12:1]; a mispredicted exit of a
// branch without an entry takes one (round robin).
localparam int LPN = 8;
logic [11:0] lp_tag  [LPN];
logic        lp_v    [LPN];
logic        lp_cf   [LPN];
logic  [7:0] lp_trip [LPN];
logic  [7:0] lp_cnt  [LPN];
logic  [7:0] lp_sp   [LPN];
logic        lp_x    [LPN];
logic [$clog2(LPN)-1:0] lp_rr;
logic        lp_sync;
logic [LPN-1:0] lp_hit;
logic        lp_exit, lp_br, lp_ovr;
always_comb begin
	for (int i = 0; i < LPN; i++)
		lp_hit[i] = lp_v[i] && (lp_tag[i] == qpc[12:1]);
	lp_exit = 1'b0;
	for (int i = 0; i < LPN; i++)
		if (LOOP_PRED && lp_hit[i] && lp_x[i]) lp_exit = 1'b1;
end

always_comb begin
	logic [31:0] disp;
	logic        nredir;
	logic        pcrel, fdb;          // a PC-relative branch target (FDBcc's base is PC+4)
	nrec    = '0;
	go      = 1'b0;
	go_part = 1'b0;
	use_n   = 4'd0;
	flt     = 1'b0;
	nredir  = 1'b0;
	ntarget = '0;
	teq     = 1'b0;
	lp_br   = 1'b0;
	lp_ovr  = 1'b0;
	jsr_k   = 1'b0;
	disp    = '0;
	pcrel   = 1'b0;
	fdb     = 1'b0;
	nph     = ph;

	if (ph != PH_IDLE) begin
		// slow path: the EA extension at the head
		logic [3:0] i;
		logic [2:0] l, il;
		i  = (ph == PH_EA0) ? part_pd.i0 : part_pd.i1;
		il = (ph == PH_EA0) ? part_imml : 3'd0;
		l  = ea_len(i, win[0], il);
		nrec = part;
		if ({1'b0, l} <= qcnt || q_flt) begin
			use_n = ({1'b0, l} <= qcnt) ? {1'b0, l} : qcnt;   // (q_flt: what is queued)
			flt   = |(win_flt & ((8'd1 << l) - 8'd1));
			begin
				// (one instance for both phases: the same words and base)
				ea_t e;
				e = mk_ea(i, (ph == PH_EA0) ? part.opw[2:0] : part.opw[11:9], part_len, il,
				          part.pc + {27'd0, part_len, 1'b0},
				          win[0], win[1], win[2], win[3], win[4]);
				if (ph == PH_EA0) nrec.ea0 = e; else nrec.ea1 = e;
			end
			// an FPU immediate is read from the instruction stream by the
			// microcode: its address follows the extension word (the
			// operation word says FPU: the record's routine is past the
			// first word D1 resolves)
			if (ph == PH_EA0 && nrec.ea0.m == EM_IMM && part.opw[15:6] == 10'b1111_0010_00)
				nrec.ea0.bd = part.pc + 32'd4;
			if (ph == PH_EA0 && has_ext(part_pd.i1) && !flt) begin
				go_part = 1'b1;
				nph     = PH_EA1;
			end
			else begin
				go  = 1'b1;
				nph = PH_IDLE;
			end
			nrec.ilen = 4'(part_len + {1'b0, l});
			if (flt) begin
				nrec.exc    = f_code;
				nrec.target = f_addr;
				nrec.rt     = UA_DEC_EXC;
			end
		end
	end
	else if (q_odd && qcnt == 4'd0) begin
		// the stream starts at an odd address: address error
		go       = 1'b1;
		nrec.pc  = qpc;
		nrec.ilen = 4'd0;
		nrec.exc = 8'd3;
		nrec.rt  = UA_DEC_EXC;
	end
	else if (qcnt != 4'd0) begin
		logic [2:0] pi, nimm;
		nrec.pc    = qpc;
		nrec.opw   = opw;
		nrec.ext1  = win[1];
		nrec.ext2  = win[2];
		nrec.sz    = pdx.sz;
		nrec.eop   = a0.eop;
		nrec.econd = a0.econd;
		nrec.ccr   = a0.ccr;
		nrec.t0    = a0.t0;
		pi   = 3'd1 + {1'b0, a0.nfix};
		nimm = pdx.b - pi;
		case (nimm)
			3'd1:    nrec.imm = (a0.immk == 3'd2 || (a0.immk == 3'd1 && pdx.sz == SZ_B)) ?
			                    {24'd0, win[pi][7:0]} : sx16(win[pi]);
			3'd2:    nrec.imm = {win[pi], win[3'(pi + 1)]};
			default: nrec.imm = 32'd0;
		endcase
		nrec.ea0 = '0; nrec.ea0.m = EM_NONE;
		nrec.ea1 = '0; nrec.ea1.m = EM_NONE;

		if (!pdx.legal) begin
			// illegal / unimplemented operation word
			use_n    = 4'd1;
			go       = 1'b1;
			flt      = win_flt[0];
			nrec.exc = (opw[15:12] == 4'hA) ? 8'd10 :
			           (opw[15:12] == 4'hF) ? 8'd11 : 8'd4;
		end
		else if (fast) begin
			if (pdx.tot <= qcnt || q_flt) begin
				go    = 1'b1;
				use_n = (pdx.tot <= qcnt) ? pdx.tot : qcnt;
				flt   = |(win_flt & ((9'd1 << pdx.tot) - 9'd1));
				nrec.ea0 = mk_ea(pdx.i0, opw[2:0], {1'b0, fb},
				                 (pdx.sz == SZ_L) ? 3'd2 : 3'd1,
				                 qpc + {28'd0, fb, 1'b0},
				                 win[fb], win[3'(fb + 1)], 16'd0, 16'd0, 16'd0);
				// (EA1 is MOVE's destination, data alterable: never
				// PC-relative, so it takes no PC base and no adder)
				nrec.ea1 = mk_ea(pdx.i1, opw[11:9], {1'b0, fp1}, 3'd0,
				                 32'd0,
				                 win[fp1], win[3'(fp1 + 1)], 16'd0, 16'd0, 16'd0);
			end
		end
		else if ({1'b0, pdx.b} <= qcnt || q_flt) begin
			// slow path, first phase: operation word, fixed words, immediate;
			// the EAs without extension words are complete already
			nrec.ea0 = mk_ea(pdx.i0, opw[2:0], 4'd0, 3'd0, 32'd0,
			                 16'd0, 16'd0, 16'd0, 16'd0, 16'd0);
			nrec.ea1 = mk_ea(pdx.i1, opw[11:9], 4'd0, 3'd0, 32'd0,
			                 16'd0, 16'd0, 16'd0, 16'd0, 16'd0);
			use_n = ({1'b0, pdx.b} <= qcnt) ? {1'b0, pdx.b} : qcnt;
			flt   = |(win_flt & ((8'd1 << pdx.b) - 8'd1));
			if (flt) begin
				go = 1'b1;                   // stop at the faulted part
			end
			else begin
				go_part = 1'b1;
				nph     = has_ext(pdx.i0) ? PH_EA0 : PH_EA1;
			end
		end

		nrec.ilen = use_n;
		nrec.rt  = (jcond(a0.jc0, pdx.i0, pdx.i1, win[1], pdx.sz, opw[2:0])) ? a0.jt0 :
		           (a0.jc0 != JC_NEVER) ? a0.rt + 10'd1 : a0.rt;
		// fixed operand forms: (Ay)+,(Ax)+ and -(Ay),-(Ax); MOVE16
		if (a0.fea == 2'd3) begin
			if (opw[5]) begin
				nrec.ea0.m = EM_AIP; nrec.ea0.r = opw[2:0];
				nrec.ea1.m = EM_AIP; nrec.ea1.r = win[1][14:12];
			end
			else begin
				ea_t ra, aa;
				ra = '0; aa = '0;
				ra.m = opw[4] ? EM_AI : EM_AIP; ra.r = opw[2:0];
				aa.m = EM_ABSL; aa.bd = {win[1], win[2]};
				nrec.ea0 = opw[3] ? aa : ra;
				nrec.ea1 = opw[3] ? ra : aa;
			end
		end
		else if (a0.fea != 2'd0) begin
			nrec.ea0.m = (a0.fea == 2'd1) ? EM_AIP : EM_APD;
			nrec.ea1.m = (a0.fea == 2'd1) ? EM_AIP : EM_APD;
			nrec.ea0.r = opw[2:0];
			nrec.ea1.r = opw[11:9];
		end

		if (pdx.legal) begin
			if (a0.priv && !smode)
				nrec.exc = 8'd8;
			else if (a0.rt == UA_TRAP)
				nrec.exc = 8'd32 + {4'd0, opw[3:0]};
			// a control register number the 68040 does not have: illegal
			// (MC68040UM 8.2.4)
			else if ((a0.rt == UA_MOVEC_RD || a0.rt == UA_MOVEC_WR) && !movec_ok(win[1][11:0]))
				nrec.exc = 8'd4;
			else if (a0.rt == UA_ILLEGAL)
				nrec.exc = 8'd4;
		end
		if (flt) nrec.exc = f_code;
		if (nrec.exc != 8'd0) begin
			nrec.rt = UA_DEC_EXC;
			if (go_part) begin
				// an exception needs no further parsing
				go_part = 1'b0;
				go      = 1'b1;
				nph     = PH_IDLE;
			end
		end

		// PC-relative branches: target and prediction
		if (a0.rt == UA_BCC || a0.rt == UA_BSR) begin
			disp = (opw[7:0] == 8'h00) ? sx16(win[1]) :
			       (opw[7:0] == 8'hFF) ? {win[1], win[2]} :
			       {{24{opw[7]}}, opw[7:0]};
			pcrel   = 1'b1;
			teq     = (disp == bt_d2);
			nrec.bst = disp[31];
			nrec.bhc = bht_q;
			nredir  = (a0.rt == UA_BSR) || (opw[11:8] == 4'h0) || (disp[31] ^ bht_q[1]);
			lp_br   = (a0.rt == UA_BCC) && (opw[11:9] != 3'd0) && disp[31];
			lp_ovr  = lp_br && lp_exit;
			if (lp_ovr) nredir = 1'b0;
		end
		else if ((a0.rt == UA_JSR || a0.rt == UA_JMP) && go && !go_part &&
		         (nrec.ea0.m == EM_ABSW || nrec.ea0.m == EM_ABSL || nrec.ea0.m == EM_PC16)) begin
			ntarget = nrec.ea0.bd;
			teq     = (nrec.ea0.m == EM_ABSL) ? ({win[1], win[2]} == bt_tgt) :
			          (nrec.ea0.m == EM_ABSW) ? (sx16(win[1]) == bt_tgt) :
			                                    (sx16(win[1]) == bt_d2);
			nredir  = 1'b1;
			// the target is known: JSR is a single push (as BSR); the
			// routine is changed as the record enters the FIFO, so the
			// return stack logic sees UA_JSR
			jsr_k = (a0.rt == UA_JSR);
		end
		else if (a0.rt == UA_RTS && ras_n != 4'd0) begin
			ntarget = ras_top;
			teq     = (ras_top == bt_tgt);
			nredir  = 1'b1;
		end
		else if (a0.rt == UA_DBCC) begin
			disp    = sx16(win[1]);
			pcrel   = 1'b1;
			teq     = (disp == bt_d2);
			nrec.bst = disp[31];
			lp_br   = disp[31];
			lp_ovr  = lp_br && lp_exit;
			nredir  = disp[31] && !lp_exit;
		end
		else if (a0.rt == UA_FBCC) begin
			disp    = opw[6] ? {win[1], win[2]} : sx16(win[1]);
			pcrel   = 1'b1;
			teq     = (disp == bt_d2);
			nredir  = (opw[5:0] == 6'h0F) || disp[31];
		end
		else if (a0.rt == UA_FDBCC) begin
			disp    = sx16(win[2]);
			pcrel   = 1'b1;
			fdb     = 1'b1;
			teq     = (disp == bt_d2 - 32'd2);
			nredir  = disp[31];
		end
		// (one adder for every PC-relative branch target)
		if (pcrel) ntarget = qpc + disp + {29'd0, fdb, !fdb, 1'b0};
		if (a0.rt == UA_FPU_GEN && nrec.ea0.m == EM_IMM)
			nrec.ea0.bd = qpc + 32'd4;
		nrec.target = flt ? f_addr : ntarget;
		nrec.pred   = nredir && (nrec.exc == 8'd0) && pdx.legal;
	end
end

// the FIFO has room when it holds at most one record (registered)
// Words the fetch BTB flagged (the end of a branch it took).  A flag on
// the last word of a complete decode is checked against D1's own
// prediction; a flag anywhere else (a stale or aliased entry: the words
// after it came from its target) drops the entry and marks the record
// (or, for a multi-part decode, the instruction's final record) to be
// refetched at WB (EXC_SNR): this check stays off the consume path.
logic [7:0] bt_lm, bt_lb;
logic       bt_any, bt_end, bt_restart, part_bt;
logic [2:0] bt_j;
always_comb begin
	// the consumed words, and the last of them (tables, no arithmetic)
	case (use_n)
		4'd0: begin bt_lm = 8'h00; bt_lb = 8'h00; end
		4'd1: begin bt_lm = 8'h01; bt_lb = 8'h01; end
		4'd2: begin bt_lm = 8'h03; bt_lb = 8'h02; end
		4'd3: begin bt_lm = 8'h07; bt_lb = 8'h04; end
		4'd4: begin bt_lm = 8'h0F; bt_lb = 8'h08; end
		4'd5: begin bt_lm = 8'h1F; bt_lb = 8'h10; end
		4'd6: begin bt_lm = 8'h3F; bt_lb = 8'h20; end
		4'd7: begin bt_lm = 8'h7F; bt_lb = 8'h40; end
		default: begin bt_lm = 8'hFF; bt_lb = 8'h80; end
	endcase
	bt_any  = |(win_bt & bt_lm);
	bt_end  = go && !go_part && (ph == PH_IDLE) && ((win_bt & bt_lm) == bt_lb);
	bt_restart = (go || go_part) && bt_any && !bt_end;
	bt_j = 3'd0;
	for (int i = 7; i >= 0; i--) if (win_bt[i] && bt_lm[i]) bt_j = 3'(i);
end
// the record as it enters the FIFO: refetched at WB if a flag was inside
// the instruction (now, or in an earlier part)
dinst_t nrec_q;
always_comb begin
	nrec_q = nrec;
	if (jsr_k && nrec.exc == 8'd0) nrec_q.rt = UA_JSR_K;
	if (fpg && nrec.exc == 8'd0) nrec_q.rt = fpu_k(nrec.ext1, nrec.ea0.m, nrec.rt);
	nrec_q.ras.v  = 1'b1;
	nrec_q.ras.tp = ras_tp;
	nrec_q.ras.n  = ras_n;
	nrec_q.ras.k  = (nrec.exc != 8'd0) ? 2'd0 :
	                rcall ? 2'd1 :
	                (rret && ras_n != 4'd0) ? 2'd2 : 2'd0;
	if (go && (bt_restart || part_bt)) begin
		nrec_q.exc  = EXC_SNR;
		nrec_q.rt   = UA_DEC_EXC;
		nrec_q.pred = 1'b0;
		nrec_q.ras.k = 2'd0;
	end
end
wire [31:0] lastpc = qpc + {27'd0, use_n - 4'd1, 1'b0};    // the decode's last word
wire        btb_ok = (ntarget[0] == 1'b0) && (nrec.exc == 8'd0);
// the entry's kind: a call pushes the fetch's return stack, a return pops it
wire  [1:0] btb_kind = rcall ? 2'd1 : rret ? 2'd2 : 2'd0;
always_comb begin
	// a back-end redirect resynchronizes the fetch's stack from the
	// restored pointer (its pointer and the top entry)
	ras_tp_o = ras_rv ? ras_rtp : ras_tp;
	ras_n_o  = ras_rv ? ras_rn  : ras_n;
	ras_o    = ras_top[31:1];
end

// (two records; a full FIFO has room in the clock the sequencer pops one,
// or D1 would wait a clock behind every pop: 28% on Dhrystone)
wire room  = (rq_n != 2'd2) || rq_pop_e;
wire stall = flush || hold_redir || d_redir_v || !room;
wire fire  = (go || go_part) && !stall;
wire push  = fire && go;
wire pop   = rq_pop && (rq_n != 2'd0);

// loop exit table updates
wire lp_push = push && (ph == PH_IDLE) && lp_br && (nrec.exc == 8'd0);
logic lp_whit;
always_comb begin
	lp_whit = 1'b0;
	for (int i = 0; i < LPN; i++)
		if (lp_v[i] && lp_tag[i] == lp_wa) lp_whit = 1'b1;
end
always_ff @(posedge clk) begin
	if (!nreset) begin
		lp_rr   <= '0;
		lp_sync <= 1'b0;
		for (int i = 0; i < LPN; i++) begin
			lp_tag[i]  <= '0;
			lp_v[i]    <= 1'b0;
			lp_cf[i]   <= 1'b0;
			lp_trip[i] <= '0;
			lp_cnt[i]  <= '0;
			lp_sp[i]   <= '0;
			lp_x[i]    <= 1'b0;
		end
	end
	else begin
		if (flush) lp_sync <= 1'b1;
		else if (push) lp_sync <= 1'b0;
		if (lp_we && !lp_tk && lp_mp && !lp_whit) lp_rr <= lp_rr + 1'b1;
		for (int i = 0; i < LPN; i++) begin
			logic        v_n, cf_n;
			logic  [7:0] trip_n, cnt_n, base, inc;
			logic [11:0] tag_n;
			v_n    = lp_v[i];
			cf_n   = lp_cf[i];
			trip_n = lp_trip[i];
			cnt_n  = lp_cnt[i];
			tag_n  = lp_tag[i];
			if (lp_we && lp_v[i] && lp_tag[i] == lp_wa) begin
				if (lp_tk)
					cnt_n = (lp_cnt[i] == 8'hFF) ? 8'hFF : lp_cnt[i] + 8'd1;
				else begin
					cf_n   = (lp_cnt[i] == lp_trip[i]) && (lp_cnt[i] != 8'hFF);
					trip_n = lp_cnt[i];
					cnt_n  = 8'd0;
				end
			end
			else if (lp_we && !lp_tk && lp_mp && !lp_whit && lp_rr == $clog2(LPN)'(i)) begin
				v_n    = 1'b1;
				tag_n  = lp_wa;
				cf_n   = 1'b0;
				trip_n = 8'hFF;
				cnt_n  = 8'd0;
			end
			base = (flush || lp_sync) ? cnt_n : lp_sp[i];
			inc  = (base == 8'hFF) ? 8'hFF : base + 8'd1;
			lp_v[i]    <= v_n;
			lp_tag[i]  <= tag_n;
			lp_cf[i]   <= cf_n;
			lp_trip[i] <= trip_n;
			lp_cnt[i]  <= cnt_n;
			if (lp_push && lp_hit[i]) begin
				lp_sp[i] <= nrec.pred ? inc : 8'd0;
				lp_x[i]  <= v_n && cf_n && (nrec.pred ? (inc == trip_n) : (trip_n == 8'd0));
			end
			else begin
				lp_sp[i] <= base;
				lp_x[i]  <= v_n && cf_n && (base == trip_n);
			end
		end
	end
end

assign consume = fire ? use_n[2:0] : 3'd0;

always_ff @(posedge clk) begin
	if (!nreset) begin
		rq_n       <= 2'd0;
		rq0        <= '0;
		rq1        <= '0;
		ph         <= PH_IDLE;
		part       <= '0;
		part_pd    <= '0;
		part_len   <= '0;
		part_imml  <= '0;
		d_redir_v  <= 1'b0;
		d_redir_pc <= '0;
		hold_redir <= 1'b0;
		btb_we     <= 1'b0;
		btb_wi     <= '0;
		btb_wv     <= 1'b0;
		btb_wtag   <= '0;
		btb_wslot  <= 1'b0;
		btb_wkind  <= '0;
		btb_wtgt   <= '0;
		part_bt    <= 1'b0;
		part_call  <= 1'b0;
		part_ret   <= 1'b0;
		part_fpg   <= 1'b0;
		ras_tp     <= '0;
		ras_n      <= '0;
	end
	else begin
		d_redir_v  <= 1'b0;
		hold_redir <= d_redir_v;
		btb_we     <= 1'b0;

		if (bt_restart && fire) begin
			// a flagged word inside an instruction: drop the entry (the
			// record is refetched at WB)
			logic [31:0] fa;
			fa = qpc + {28'd0, bt_j, 1'b0};
			btb_we     <= 1'b1;
			btb_wv     <= 1'b0;
			btb_wi     <= fa[BTB_AW+1:2];
			btb_wtag   <= fa[31:BTB_AW+2];
			btb_wslot  <= fa[1];
		end
		// the flag of an earlier part stays with the instruction
		if (fire) part_bt <= go_part && (part_bt || bt_restart);
		if (flush) part_bt <= 1'b0;

		// the return stack follows the records in program order.  A call
		// writes the slot above the top while it waits in D1, push or not
		// (the write stays off D1's go, a timing path): only the push
		// moves the top.  A call that never pushes (flushed, faulted) can
		// cost the entry it overwrote -- the oldest, or one a recovery
		// would restore -- which only costs a prediction: EX checks every
		// return
		if (rcall) ras[ras_tp + 3'd1] <= nrec_npc;
		if (push && nrec_q.exc == 8'd0) begin
			if (rcall) begin
				ras_tp <= ras_tp + 3'd1;
				if (ras_n != 4'd8) ras_n <= ras_n + 4'd1;
			end
			else if (rret && ras_n != 4'd0) begin
				ras_tp <= ras_tp - 3'd1;
				ras_n  <= ras_n - 4'd1;
			end
		end

		// two records
		case ({push, pop})
			2'b01: begin rq0 <= rq1; rq_n <= rq_n - 2'd1; end
			2'b10: begin
				if (rq_n == 2'd0) rq0 <= nrec_q;
				else              rq1 <= nrec_q;
				rq_n <= rq_n + 2'd1;
			end
			2'b11: begin
				if (rq_n == 2'd1) rq0 <= nrec_q;
				else begin rq0 <= rq1; rq1 <= nrec_q; end
			end
			default: ;
		endcase

		if (fire) begin
			ph <= nph;
			if (go_part) begin
				part <= nrec;
				if (ph == PH_IDLE) begin
					part_call <= rcall;
					part_ret  <= rret;
					part_fpg  <= fpg;
					part_pd   <= pdx;
					part_len  <= use_n;
					part_imml <= (a0.rt == UA_FPU_GEN) ? fp_immlen(win[1]) :
					             (pdx.sz == SZ_L) ? 3'd2 : 3'd1;
				end
				else
					part_len <= part_len + use_n;
			end
			if (push && ph == PH_IDLE && bt_end) begin
				// the fetch already took this branch: fine if D1 agrees
				if (!(nrec.pred && teq)) begin
					d_redir_v  <= 1'b1;
					d_redir_pc <= nrec.pred ? ntarget : nrec_npc;
					// (a loop exit keeps the entry: the next pass takes it)
					btb_we     <= !lp_ovr;
					btb_wv     <= nrec.pred && btb_ok;
					btb_wi     <= lastpc[BTB_AW+1:2];
					btb_wtag   <= lastpc[31:BTB_AW+2];
					btb_wslot  <= lastpc[1];
					btb_wkind  <= btb_kind;
					btb_wtgt   <= ntarget[31:1];
				end
			end
			else if (push && nrec_q.pred && ph == PH_IDLE) begin
				d_redir_v  <= 1'b1;
				d_redir_pc <= ntarget;
				// next time the fetch takes it
				btb_we     <= btb_ok;
				btb_wv     <= 1'b1;
				btb_wi     <= lastpc[BTB_AW+1:2];
				btb_wtag   <= lastpc[31:BTB_AW+2];
				btb_wslot  <= lastpc[1];
				btb_wkind  <= btb_kind;
				btb_wtgt   <= ntarget[31:1];
			end
		end
		if (flush) begin
			rq_n       <= 2'd0;
			if (ras_rv) begin
				ras_tp <= ras_rtp;
				ras_n  <= ras_rn;
			end
			ph         <= PH_IDLE;
			d_redir_v  <= 1'b0;
			hold_redir <= 1'b0;
		end
	end
end

endmodule
// ---- ap68040_dmu.sv ----
//--------------------------------------------------------------------------//
// AP68040 - pipelined MC68040                                            //
//                                                                          //
// ap68040_dmu.sv - data memory unit: D-ATC, data cache, table walker       //
//                                                                          //
// Mirrors the back end's DC1, DC2, EX and WB stages for memory uops.       //
//                                                                          //
// Data cache (MC68040UM section 4): 4 Kbytes, four ways of 64 sets of     //
// 16-byte lines, physically tagged (PA31-10; the set is PA9-4 = LA9-4).    //
// A valid and a dirty bit per line; replacement takes the first invalid   //
// way, else a 2-bit counter.  Copyback and write-through cachable,        //
// serialized and nonserialized cache-inhibited modes.  Read-modify-write  //
// (locked) and cache-inhibited accesses bypass the cache: a line they hit //
// is pushed if dirty and invalidated first (4.3.2, 4.6.2, 7.4.1).         //
//                                                                          //
// DC1  D-ATC and TTR lookup, tag compare of the translated page           //
// DC2  fast path: a load (or unlocked read-modify-write) that hits a      //
//      cachable line, within one line, with no older store to the line    //
//      in flight, is answered from the data RAM's registered output.      //
//      Everything else stalls DC2 and runs in the engine.                 //
// WB   a copyback store that hit writes the data RAM in its WB cycle;     //
//      other stores go through the engine.                                 //
//                                                                          //
// The engine runs one job at a time: the DC2 slow path (table walk, line  //
// fill -- the dirty victim pushed afterwards --, cache-inhibited accesses //
// with a matching line pushed and invalidated first, operands crossing a  //
// line in two parts), WB stores, WB maintenance (CINV, CPUSH, PFLUSH,     //
// PTEST) and the instruction side's table walks.  While it uses the       //
// lookup ports it holds DC1 (dm_hold1), one cycle longer than it uses     //
// them so DC1 re-reads its own address.                                   //
//                                                                          //
// Bus snooping (MC68040UM 4.4, 4.7.2, 7.9) through the sn_* port: the    //
// snooper (ap68040_snoop.sv) asks for the cache; the DMU freezes the      //
// engine, holds DC1 and blocks the WB fast store, looks the physical      //
// line up in the tags, the push buffer and a push waiting for the bus,    //
// and applies the snooper's invalidate or sink write to what it found.    //
// An invalidated line also loses its hit in the DC2/EX/WB records and     //
// the engine's current part, so no store lands in a line that left.      //
// One cycle after the port is released re-reads the lookup address of    //
// DC1 or the engine before they run again.                                //
//                                                                          //
// Table walks (MC68040UM 3.2): root, pointer and page descriptors with    //
// indirect page descriptors, 4K/8K pages, accumulated W, U/M history per  //
// table 3-1 (locked read-modify-write where the table says so: the        //
// descriptor is read again with LOCK and written back with LOCK and       //
// LOCKE).  Descriptor reads see the data cache (cachable write-through,  //
// no allocate, 3.2.5); descriptor updates are noncachable and push and    //
// invalidate a matching line.  Like the 68040 (WinUAE cpummu.cpp), a      //
// failed search still creates an ATC entry, with R clear (B set for a bus //
// error): the access that looks the ATC up again takes the fault.         //
//--------------------------------------------------------------------------//

module ap68040_dmu
	import ap68040_pkg::*;
#(
	// DC1's own ATC read port and tag compare beside xlate (65 MHz timing;
	// 0: DC1's hit and way are xlate's, the port is not built)
	parameter bit DC1_ATC = 0,
	// copyback pages (CM 01, from a TTR or a page descriptor) are cached
	// write-through: for a system whose DMA reads are not snooped (SC 00),
	// where memory must always be current
	parameter bit DC_WRITETHROUGH = 0
)
(
	input  logic        clk,
	input  logic        nreset,

	// back end
	input  logic        adv_ag,
	input  logic        dm_req,
	input  logic [31:0] dm_va,
	input  logic  [1:0] dm_mem,
	input  logic  [1:0] dm_msz,
	input  logic  [2:0] dm_fc,
	input  logic        dm_lock,
	input  logic        dm_locke,
	input  logic        dm_wi,          // a load checked as a write
	input  logic        dm_super,
	input  logic        dm_noalloc,
	input  logic  [1:0] dm_ack,         // acknowledge cycle: 1 IACK, 2 BKPT
	input  logic  [2:0] iack_lvl,
	input  logic        dm_older,       // uops older than DC2 still in EX or WB
	input  logic        adv_dc1,
	input  logic        adv_dc2,
	input  logic        adv_ex,
	input  logic        adv_wb,
	input  logic        kill_now,
	output logic        dm_hold1,       // DC1 must hold (the engine owns its ports)
	output logic        dc2_rdy,
	output logic [31:0] ldata,
	output logic [31:0] ldata_al,       // the aligned long (or word, low half)
	output logic        ldata_alv,      // ... is the load's data
	output logic        ldata_job,      // debug: ldata is the slow-path job's answer
	output logic        fault,
	output logic  [7:0] fvec,
	output logic [31:0] faddr,
	output logic [15:0] fssw,
	input  logic        st_v,
	input  logic [31:0] st_data,
	output logic        st_rdy,
	output logic        st_fault,
	output logic [15:0] st_fssw,
	output logic [31:0] st_faddr,

	// WB maintenance: CINV/CPUSH/PFLUSH/PTEST
	input  logic        mt_v,
	input  logic  [2:0] mt_op,          // MT_*
	input  logic  [1:0] mt_scope,       // 1 line, 2 page, 3 all
	input  logic  [1:0] mt_caches,      // bit 0 DC, bit 1 IC
	input  logic [31:0] mt_addr,
	input  logic  [2:0] mt_fc,          // DFC (PTEST/PFLUSH)
	input  logic        mt_ng,          // PFLUSHN/PFLUSHAN: spare global entries
	input  logic        mt_wr,          // PTESTW
	output logic        mt_done,
	output logic [31:0] mt_mmusr,       // PTEST: the MMUSR
	output logic        mt_fault,       // CPUSH: a push ended in TEA (an access error),
	output logic [15:0] mt_fssw,        // ... its SSW and
	output logic [31:0] mt_faddr,       // ... the push's address
	output logic [127:0] pb_data,       // the line of the last push that ended in TEA (PD0-PD3)

	// control registers
	input  logic [31:0] cacr,
	input  logic [31:0] tc,
	input  logic [31:0] urp,
	input  logic [31:0] srp,
	input  logic [31:0] dtt0,
	input  logic [31:0] dtt1,
	input  logic [31:0] itt0,
	input  logic [31:0] itt1,
	input  logic        cdis,           // CDIS: caches disabled (contents kept)
	input  logic        mdis,           // MDIS: no page translation (TTRs still apply)
	output logic        tw_busy,        // a table search is running (PST)

	// instruction side: table walks for the I-ATC, ATC/cache maintenance
	input  logic        iw_req,
	input  logic [31:0] iw_va,
	input  logic        iw_fc2,
	output logic        iw_done,
	output atce_t       iw_ent,
	output logic        ic_inv,         // invalidate instruction cache lines
	output logic  [1:0] ic_inv_scope,   // 1 line, 2 page, 3 all
	output logic [31:0] ic_inv_pa,
	input  logic        ic_inv_done,
	output logic        iatc_flush_all,
	output logic        iatc_flush_page,
	output logic        iatc_flush_ng,
	output logic [31:0] iatc_flush_la,
	output logic        iatc_flush_fc2,
	output logic        iatc_wr,        // table walk result into the I-ATC
	output logic [31:0] iatc_wla,
	output logic        iatc_wfc2,
	output atce_t       iatc_went,

	// BIU client
	output logic        b_req,
	output busreq_t     b_breq,
	output logic [127:0] b_wdata,
	input  logic        b_gnt,
	input  logic        b_done,
	output logic        b_drop,         // the push the BIU holds for a retry: dropped
	input  logic        b_err,
	input  logic        b_rvalid,
	input  logic [31:0] b_rdata,
	input  logic  [1:0] b_rbeat,
	input  logic        b_ravec,
	input  logic        b_rtci,

	// bus snooper
	input  logic        sn_req,         // level: the snooper wants the cache
	input  logic [31:0] sn_pa,
	output logic        sn_look,        // pulse: sn_hit/sn_dirty/sn_line valid
	output logic        sn_hit,
	output logic        sn_dirty,
	output logic [127:0] sn_line,        // with sn_look: the line found
	input  logic        sn_inv,         // pulse: invalidate what was found
	input  logic        sn_wr,          // pulse: write into what was found
	input  logic [15:0] sn_wbe,         // the bytes, of...
	input  logic [31:0] sn_wword        // ...this long word on every long word
);

localparam logic [2:0] MT_CINV = 3'd1, MT_CPUSH = 3'd2, MT_PFLUSH = 3'd3, MT_PTEST = 3'd4;
// the SSW of a bus error on a line push (figure 8-6): a write, SIZE line,
// TT normal, TM 0 (push)
localparam logic [15:0] SSW_PUSH = 16'h0060;

// MDIS, sampled once here: DC1's registered translation decision (m1_tp)
// is formed from the pin a clock ahead, so the two always agree
logic mdis_q = 1'b0;
always_ff @(posedge clk) mdis_q <= mdis;
wire tc_e   = tc[15] && !mdis_q;
wire tc_e_n = tc[15] && !mdis;      // (tc_e at the next clock)
wire tc_p  = tc[14];
// CACR.DE clear stops allocation only: the cache is still searched, a hit
// is served and written (the MC68040UM 4.3.2 notes a locked access that
// hit "and the data cache was disabled"; cputest on real 68040/68060
// boards pushes a return address through copyback memory, clears DE with
// MOVEC and pops it with RTS, so the hit must still serve it).  CDIS
// bypasses the caches and leaves their contents alone (4.2; an emulator
// feature).  WinUAE's data cache (off by default) bypasses on DE clear:
// a divergence, knowingly.
wire dc_en   = cacr[31] && !cdis;   // allocation
wire dc_look = !cdis;               // hits served

//--------------------------------------------------------------------------
// stage records
//--------------------------------------------------------------------------
typedef struct packed {
	logic        v;
	logic [31:0] a;        // logical address
	logic  [1:0] mem;
	logic  [1:0] msz;
	logic  [2:0] fc;
	logic        lock;
	logic        locke;
	logic        wi;       // write intent: a load translated and walked as a write
	logic        smode;    // FC2
	logic        noalloc;
	logic  [1:0] ack;      // acknowledge cycle (TT=3): 1 IACK, 2 BKPT
} req_t;

// translation and lookup result of one access part
typedef struct packed {
	logic        ok;       // translation known
	logic        flt;      // access fault (ATC/TTR)
	logic        walk;     // needs a table search (ATC miss or M update)
	logic [31:0] pa;
	logic  [1:0] cm;
	logic  [1:0] upa;
	logic        hit;      // the line is in the cache
	logic  [1:0] way;
} xres_t;

typedef struct packed {
	req_t        r;
	xres_t       x;        // part 0 (the only part unless split)
	logic        split;    // crosses a line: part 1 at the next line
	xres_t       x1;
	logic        fast;     // DC2 can answer from the RAM output
	logic        sfast;    // a load across a line whose first part hit:
	                       // DC2's copy holds it, one lookup for the rest
} mrec_t;

req_t  m1;
mrec_t m2, m3, m4;

function automatic logic [2:0] nbytes(input logic [1:0] msz);
	case (msz)
		SZ_B:    nbytes = 3'd1;
		SZ_W:    nbytes = 3'd2;
		SZ_L:    nbytes = 3'd4;
		default: nbytes = 3'd0;     // line
	endcase
endfunction

// MOVES to the instruction spaces is a data reference (MC68040UM table 3-2)
function automatic logic [1:0] fc_tt(input logic [2:0] fc);
	fc_tt = (fc == 3'd1 || fc == 3'd2 || fc == 3'd5 || fc == 3'd6) ? TT_NORMAL : TT_ALT;
endfunction
function automatic logic [2:0] fc_tm(input logic [2:0] fc);
	fc_tm = (fc == 3'd2) ? 3'd1 : (fc == 3'd6) ? 3'd5 : fc;
endfunction

// TTR match on A31-24 with mask, E, and the S field
function automatic logic ttr_hit(input logic [31:0] t, input logic [31:0] a,
                                 input logic s);
	ttr_hit = t[15] && (((a[31:24] ^ t[31:24]) & ~t[23:16]) == 8'd0) &&
	          (t[14] || (t[13] == s));
endfunction

// n bytes at offset o of a line, right aligned
function automatic logic [31:0] take(input logic [127:0] line, input logic [3:0] o,
                                     input logic [2:0] n);
	logic [31:0] v;
	v = '0;
	for (int i = 0; i < 4; i++)
		if (3'(i) < n) v = {v[23:0], line[127 - 8*(o + i) -: 8]};
	take = v;
endfunction

// A write of n bytes from the top of d (left aligned) at offset o of a
// line: the operand rotated onto the byte lanes, as the bus would carry
// it, is replicated over the line's four long words, and the byte enables
// pick the bytes (byte o+i is on lane (o+i) mod 4, which holds byte i).
function automatic logic [31:0] lanes32(input logic [31:0] d, input logic [1:0] o);
	case (o)
		2'd0:    lanes32 = d;
		2'd1:    lanes32 = {d[7:0], d[31:8]};
		2'd2:    lanes32 = {d[15:0], d[31:16]};
		default: lanes32 = {d[23:0], d[31:24]};
	endcase
endfunction
function automatic logic [15:0] bmask(input logic [3:0] o, input logic [2:0] n);
	logic [3:0] m;
	m = 4'b1111 << (3'd4 - n);
	bmask = {m, 12'd0} >> o;
endfunction

function automatic logic [3:0] dmask(input logic [15:0] be);
	dmask = {|be[15:12], |be[11:8], |be[7:4], |be[3:0]};
endfunction

// left-align an operand of msz
function automatic logic [31:0] lalign(input logic [31:0] d, input logic [1:0] msz);
	case (msz)
		SZ_B:    lalign = {d[7:0], 24'd0};
		SZ_W:    lalign = {d[15:0], 16'd0};
		default: lalign = d;
	endcase
endfunction

//--------------------------------------------------------------------------
// storage
//--------------------------------------------------------------------------
// line valid and dirty, per set and way: one word per set, {dirty[3:0],
// valid[3:0]}, in LUT RAMs written as flip-flops were (at the edge) and
// read without a clock.  A LUT RAM is 32 deep whatever its width up to 20,
// so the ways share a word: copies at DC1's set (valid and dirty), at the
// engine's or the snoop's (valid; a snoop freezes the engine), at the
// scan's (dirty), and at the write's set, which forms the word written
// (the ways not written keep their bits).  A clear of every line (CINVA,
// reset) sweeps the 64 sets (E_M_CLR)
(* ramstyle = "MLAB, no_rw_check" *) logic [7:0] lsd [64];    // DC1's set
(* ramstyle = "MLAB, no_rw_check" *) logic [7:0] lse [64];    // lv_ra
(* ramstyle = "MLAB, no_rw_check" *) logic [7:0] lsw [64];    // the write's set
logic  [5:0] lv_ra;                // the engine copy's read: see below
wire   [3:0] lvd_q;                // DC1's set (m1)
wire   [3:0] lve_q;                // the engine's (or the snoop's) set
logic  [5:0] clr_i;                // the clear sweep's set
logic        clr_rst;              // ... after reset (else CINVA: then E_M_IC)
// synthesis translate_off
logic [3:0]  lv  [64];              // (simulation: the flip-flop model, checked)
// synthesis translate_off
initial for (int i = 0; i < 64; i++) lv[i] = 4'd0;
// synthesis translate_on
// synthesis translate_on
// dirty [set][way] (the push writes the whole line): read at the scan's
// set, the snooped set, the walk's descriptor set, else the fill/push set
// (they never read at once: a snoop freezes the engine).  No clear: every
// read is of a valid line, and whatever makes a line valid writes its
// dirty bit
logic  [5:0] ld_ra;
wire   [7:0] lsm_q = lse[lv_ra];
wire   [3:0] ld_q  = lsm_q[7:4];
// the maintenance scan's set, its valid and dirty bits: a copy the write
// port keeps current (the scan's decision reads 4 bits, not 256)
logic  [5:0] sc_set;
logic  [3:0] sc_lv, sc_ld;
logic [1:0]  rrc;                  // replacement counter

// lookup ports: DC1, or the engine while it holds DC1
logic        steal, steal_q;
logic [31:0] st_la;                // engine lookup address (logical, for the ATC)
logic        st_fc2;
logic  [5:0] st_set;               // engine data/tag set

// snoop port phases: A presents the snooped set, B compares, H holds the
// cache for the snooper's action, R re-reads the owner's address
typedef enum logic [2:0] { SN_IDLE, SN_A, SN_B, SN_H, SN_R } snph_t;
snph_t       sn_ph;
wire         sn_frz  = (sn_ph != SN_IDLE);
assign       b_drop  = bo_cancel && bo_ingnt && (e_st == E_BUS_W);
wire         sn_rset = (sn_ph == SN_A) || (sn_ph == SN_B);   // B: the line stays readable in H
logic  [1:0] sn_src;               // found in: 0 a cache way, 1 push buffer, 2 queued push
logic        sn_pvm, sn_bom;       // ... and (whatever sn_src says) the push buffer's
                                   // line, the queued push's line: both go with it
logic  [1:0] sn_way;
logic        bo_cancel;            // the queued push was invalidated by a snoop
logic        bo_ingnt;             // the engine's transfer is the BIU's (granted)
logic  [3:0] bo_got;               // a line read: the long words that arrived

// The lookup set: AG's address (late: register read, address adders)
// passes one LUT; the other choices are registers, merged beforehand.
// Each way's RAMs get their own copy of that LUT (fanout 18, not 72).
wire  [5:0] la_alt   = sn_rset ? sn_pa[9:4] : steal ? st_set : m1.a[9:4];
wire        la_ag    = adv_ag && !sn_rset && !steal;

// tags: port A for lookups (DC1 or stolen), port B for engine reads/writes
logic [21:0] tq_a [4];
// the tags as the RAM read them, without the same-edge write laid over:
// DC1's compare.  Tags are written only by the engine's fill (tw_b), and a
// DC1 lookup with the engine busy is stale (m1_stale) and not used, so the
// bypass's compare and multiplexer stay off DC1's hit
logic [21:0] tq_r [4];
logic        m1_stale;          // DC1's lookup is not to be used (below)
logic [21:0] tq_b [4];
logic        tw_b;
logic  [5:0] tset_b;
logic  [1:0] tway_b;
logic [21:0] twd_b;

// data: write port for stores and fills, read port for DC1 / engine
logic  [63:0] dqc;                 // DC1's two long words, every clock
logic  [63:0] dq2, dqh2;           // DC2's two long words (at its address and
                                   // the next), and its own, held
logic         dq_new;              // DC2 took a new uop at the last edge: dqc
xres_t        x_dc1;               // DC1's translation and lookup
logic [127:0] dq_rn [4];           // unregistered output (engine)
logic         dw;
logic  [5:0]  dw_set;
logic  [1:0]  dw_way;
logic [15:0]  dw_be;
logic  [1:0]  dw_src;              // 0 dw_word on every long word, 1 bo_line, 2 pv_line
logic [31:0]  dw_word;
logic [127:0] dw_wdata;
// the previous cycle's RAM write (it landed at the last edge)
logic         dwq;
logic  [5:0]  dwq_set;
logic  [1:0]  dwq_way, dwq_src;
logic [15:0]  dwq_be;
logic [31:0]  dwq_word;
always_ff @(posedge clk) begin
	dwq <= dw; dwq_set <= dw_set; dwq_way <= dw_way; dwq_src <= dw_src;
	dwq_be <= dw_be; dwq_word <= dw_word;
end
// bytes of a long word (on every long word of a line) merged into a line
function automatic logic [127:0] mrg(input logic [127:0] l, input logic [15:0] be,
                                     input logic [31:0] w);
	for (int i = 0; i < 16; i++) if (be[i]) l[8*i +: 8] = w[8*(i % 4) +: 8];
	mrg = l;
endfunction
// the two long words of a line from long word k (the second wraps): every
// byte DC2 reads -- the operand (at most four bytes from its address) and
// AG's aligned long word -- is in them
function automatic logic [63:0] pair(input logic [127:0] l, input logic [1:0] k);
	pair = {l[127 - 32 * k -: 32], l[127 - 32 * 2'(k + 2'd1) -: 32]};
endfunction
// a write merged into such a pair (be per byte of the line as mrg's)
function automatic logic [63:0] mrg2(input logic [63:0] p, input logic [1:0] k,
                                     input logic [15:0] be, input logic [31:0] w);
	for (int b = 0; b < 8; b++) begin
		logic [3:0] lb;
		lb = 4'(4 * k + b);                       // the byte's offset in the line
		if (be[4'd15 - lb]) p[63 - 8*b -: 8] = w[31 - 8*(b % 4) -: 8];
	end
	mrg2 = p;
endfunction

// the WB fast store of this cycle (its RAM write is dw next cycle): merged
// into DC2's copy now, so a load behind it does not wait for that write
logic         wfm;
logic  [5:0]  wfm_set;
logic  [1:0]  wfm_way;
logic [15:0]  wfm_be;
logic [31:0]  wfm_word;
logic         dwp;            // this cycle's dw was merged a cycle ago (wfm)

genvar gw;
generate
	for (gw = 0; gw < 4; gw++) begin : g_way
		(* keep *) wire [5:0] la_set_n = la_ag ? dm_va[9:4] : la_alt;
		ap68040_tdp #(.AW(6), .DW(22)) tag (
			.clk(clk),
			.addr_a(la_set_n), .we_a(1'b0), .wd_a(22'd0), .q_a(tq_a[gw]),
			.qa_raw(tq_r[gw]), .qa_bv(), .qa_bd(),
			.addr_b(tset_b), .we_b(tw_b && tway_b == 2'(gw)), .wd_b(twd_b), .q_b(tq_b[gw])
		);
		ap68040_sdp_be #(.AW(6), .NB(16), .OREG(0)) dat (
			.clk(clk),
			.we(dw && dw_way == 2'(gw)), .waddr(dw_set), .wbe(dw_be), .wdata(dw_wdata),
			.raddr(la_set_n), .oce(1'b1), .q(dq_rn[gw])
		);
	end
endgenerate

// DC2's copy of the line its lookup hit (only that way is ever read: the
// fast load, a split load's first part, AG's aligned word): byte writes to
// it are merged in (the RAM output misses the writes landing at the last
// edge and this one), so a load after a store to its line stays on the
// fast path
// (Both are captured every clock and the registered advance picks: the
// stall chain behind adv_dc1 is too late for a 128-bit enable.)
// (the line by the one-hot match, AND-OR; the merges that apply to it are
// registered beside it -- their bytes, data, and whether they hit it -- and
// laid over it in DC2, off the hit path: without a match the line is not
// used)
logic [15:0] mc_be [3];
logic [31:0] mc_w  [3];
logic  [2:0] mc_v;
always_ff @(posedge clk) begin
	logic  [63:0] l;
	logic  [63:0] h2;
	// (each way's two long words picked by the registered address, then
	// the hit way: the late match selects 64 bits, not the line)
	l = '0;
	for (int j = 0; j < 4; j++) if (d1_mj[j]) l = l | pair(dq_rn[j], m1.a[3:2]);
	dqc <= l;
	mc_v[0] <= dwq && dwq_src == 2'd0 && dwq_set == m1.a[9:4] && d1_mj[dwq_way];
	mc_v[1] <= dw && dw_src == 2'd0 && dw_set == m1.a[9:4] && d1_mj[dw_way];
	mc_v[2] <= wfm && wfm_set == m1.a[9:4] && d1_mj[wfm_way];
	mc_be[0] <= dwq_be; mc_w[0] <= dwq_word;
	mc_be[1] <= dw_be;  mc_w[1] <= dw_word;
	mc_be[2] <= wfm_be; mc_w[2] <= wfm_word;
	h2 = dq2;
	if (dw && dw_src == 2'd0 && dw_set == m2.r.a[9:4] && dw_way == m2.x.way)
		h2 = mrg2(h2, m2.r.a[3:2], dw_be, dw_word);
	if (wfm && wfm_set == m2.r.a[9:4] && wfm_way == m2.x.way)
		h2 = mrg2(h2, m2.r.a[3:2], wfm_be, wfm_word);
	dqh2 <= h2;
	dq_new <= adv_dc1;
end
// DC2: its two long words of the captured line, with the merges (in the
// order they were made)
logic [63:0] dqc_m2;
always_comb begin
	dqc_m2 = dqc;
	for (int k = 0; k < 3; k++) if (mc_v[k]) dqc_m2 = mrg2(dqc_m2, m2.r.a[3:2], mc_be[k], mc_w[k]);
end
assign dq2 = dq_new ? dqc_m2 : dqh2;

//--------------------------------------------------------------------------
// D-ATC
//--------------------------------------------------------------------------
logic        atc_hit;
atce_t       atc_e;
logic  [3:0] atc_hv, atc_hvd;
logic [19:0] atc_wpa [4], atc_wpad [4];
logic  [3:0] m1_aset;            // DC1's ATC set, registered with its address
// The main ATC port's set, a flip-flop: DC1's (m1_aset) one cycle, the
// stolen address's the cycle after the engine stole the port.  The engine
// reads the port a cycle or more after it sets st_la, and DC1 is held the
// cycle after a steal ends (steal_q): neither uses the lagging cycle.
// (its fanout capped: it reaches every way's entry array, and the
// fitter duplicates it per way rather than routing one copy to all)
(* altera_attribute = "-name MAX_FANOUT 14" *) logic [3:0] atc_set_q;
// ... and the page and FC2 its tags are compared with, registered the same
// way (no multiplexer between the steal flag and the compare)
logic [31:12] atc_la_q;
logic         atc_fc2_q;
logic        atc_wr;
logic [31:0] atc_wla;
logic        atc_wfc2;
atce_t       atc_went;
logic        atc_fall, atc_fpage, atc_fng;

logic        tw_upd;              // the search updates an entry (first write: M)
logic  [3:0] tw_hw;               // ... in this way (the ATC's hit vector then)
ap68040_atc #(.SAME_SEARCH(0), .EXT_SET(1)) datc (
	.clk(clk), .nreset(nreset), .p8k(tc_p),
	.la({atc_la_q, 12'd0}), .fc2(atc_fc2_q), .set_m(atc_set_q),
	.hit(atc_hit), .ent(atc_e), .hv(atc_hv), .wpa(atc_wpa),
	.la_d(m1.a), .fc2_d(m1.smode), .set_d(m1_aset), .hv_d(atc_hvd), .wpa_d(atc_wpad),
	.wr(atc_wr), .wla(atc_wla), .wfc2(atc_wfc2), .went(atc_went),
	.wsame(tw_upd), .wsame_hv(tw_hw),
	.flush_all(atc_fall), .flush_page(atc_fpage), .flush_nonglobal(atc_fng)
);

//--------------------------------------------------------------------------
// translation and cache tag compare of a lookup
//--------------------------------------------------------------------------
// the cache mode used: DC_WRITETHROUGH takes copyback as write-through
function automatic logic [1:0] cm_eff(input logic [1:0] cm);
	cm_eff = (DC_WRITETHROUGH && cm == 2'b01) ? 2'b00 : cm;
endfunction

function automatic xres_t xlate(input logic [31:0] la, input logic s, input logic wr,
                                input logic alt,
                                input logic hitv, input atce_t e,
                                input logic [21:0] t0, input logic [21:0] t1,
                                input logic [21:0] t2, input logic [21:0] t3,
                                input logic [3:0] valid);
	xres_t x;
	logic tt0, tt1;
	logic [21:0] tg;
	x = '0;
	tt0 = ttr_hit(dtt0, la, s);
	tt1 = ttr_hit(dtt1, la, s);
	// (MOVES to an alternate address space, SFC/DFC 0, 3, 4, 7: MC68040UM
	// 3.2.5 calls it a physical access without translation; WinUAE -- the
	// cputest oracle, and the reference this core is validated against --
	// translates every space through the root FC2 selects, and t_mmu
	// 177-180 pin that: alt is ignored here, the bus still shows TT=2, TM=FC)
	if (tt0 || tt1) begin
		x.ok  = 1'b1;
		x.pa  = la;
		x.cm  = cm_eff(tt0 ? dtt0[6:5] : dtt1[6:5]);
		x.upa = tt0 ? dtt0[9:8] : dtt1[9:8];
		x.flt = wr && (tt0 ? dtt0[2] : dtt1[2]);
	end
	else if (!tc_e) begin
		// translation disabled, no TTR match: cachable/write-through, not
		// write protected, UPA 0 (MC68040UM 3.1.2)
		x.ok = 1'b1;
		x.pa = la;
		x.cm = 2'b00;
	end
	else if (hitv) begin
		x.pa  = {e.pa[19:1], tc_p ? la[12] : e.pa[0], la[11:0]};
		x.cm  = e.cm;
		x.upa = e.upa;
		if (!e.r || (e.s && !s) || (wr && e.w)) begin
			x.flt = 1'b1;      // nonresident, supervisor only, write protected
			x.ok  = 1'b1;
		end
		else if (wr && !e.m) x.walk = 1'b1;   // first write: set M (3.3)
		else x.ok = 1'b1;
	end
	else x.walk = 1'b1;
	tg = x.pa[31:10];
	if (x.ok && !x.flt) begin
		if (valid[0] && t0 == tg) begin x.hit = 1'b1; x.way = 2'd0; end
		if (valid[1] && t1 == tg) begin x.hit = 1'b1; x.way = 2'd1; end
		if (valid[2] && t2 == tg) begin x.hit = 1'b1; x.way = 2'd2; end
		if (valid[3] && t3 == tg) begin x.hit = 1'b1; x.way = 2'd3; end
	end
	xlate = x;
endfunction

// DC1
// (a locked read -- TAS, CAS, CAS2 -- is a write for protection, MC68040UM
// 8.4.6; a write-intent load (wi) too: the stores after it must not fault)
wire        m1_wr  = (m1.mem == M_ST) || (m1.mem == M_RMW) || m1.lock || m1.wi;
// DC1's cache tag compare in parallel with the translation (the timing
// path): each way's tag against the untranslated address and against the
// physical page of each of the ATC's four ways; the ATC's hit vector, not
// its selected entry, then picks.  Whether the access may use the hit (a
// translation that is valid and does not fault) still comes from xlate.
logic       d1_hit;
logic [1:0] d1_way;
xres_t      x_dc1r;            // xlate's own result for DC1
always_comb x_dc1r = xlate(m1.a, m1.smode, m1_wr, fc_tt(m1.fc) == TT_ALT, atc_hit, atc_e,
                          tq_a[0], tq_a[1], tq_a[2], tq_a[3], lvd_q);
logic [3:0] d1_mj;            // the matching way, one-hot (for the line select)
// whether DC1's address is used untranslated (alternate space, a TTR,
// translation off, CPU space): registered with the address, and again
// every clock DC1 holds, so the compare select starts from a flip-flop
logic       m1_tp;
function automatic logic transp_of(input logic [31:0] a, input logic s, input logic [2:0] fc,
                                   input logic [1:0] ack);
	transp_of = ttr_hit(dtt0, a, s) || ttr_hit(dtt1, a, s) ||
	            !tc_e_n || (ack != 2'd0);
endfunction
always_comb begin
	logic        transp;
	logic [21:0] tq [4];
	logic  [3:0] mj;
	tq[0] = tq_r[0]; tq[1] = tq_r[1]; tq[2] = tq_r[2]; tq[3] = tq_r[3];
	transp = m1_tp;
	for (int j = 0; j < 4; j++) begin
		logic ma;
		ma = 1'b0;
		for (int i = 0; i < 4; i++)
			if (atc_hvd[i] && tq[j] == {atc_wpad[i][19:1], tc_p ? m1.a[12] : atc_wpad[i][0], m1.a[11:10]})
				ma = 1'b1;
		mj[j] = lvd_q[j] && (transp ? (tq[j] == m1.a[31:10]) : ma);
	end
	if (!DC1_ATC) begin
		// the main port's entry (its hit and page), compared with each way's
		// tag beside the untranslated address: the registered transparency
		// selects, so the TTR compare and the translation's address select
		// stay off the tag compare
		logic [21:0] tpa;
		tpa = {atc_e.pa[19:1], tc_p ? m1.a[12] : atc_e.pa[0], m1.a[11:10]};
		for (int j = 0; j < 4; j++)
			mj[j] = lvd_q[j] && (transp ? (tq[j] == m1.a[31:10]) : (atc_hit && tq[j] == tpa));
	end
	d1_hit = |mj;
	d1_way = mj[3] ? 2'd3 : mj[2] ? 2'd2 : mj[1] ? 2'd1 : 2'd0;
	d1_mj  = mj;
end
// synthesis translate_off
// (the engine's state for the bench's profile: a parameterized module's
// enum items are not reachable through the hierarchy in Verilator)
wire sim_es_s  = (e_st == E_S_START);
wire sim_es_w  = (e_st == E_W_START);
wire sim_es_m  = (e_st == E_M_START);
wire sim_es_tw = (e_st == E_TW_START);
wire sim_es_i  = (e_st == E_IDLE);
logic sim_xchk = 1'b0;        // (the bench fails the run on it)
logic sim_kchk = 1'b0;        // a job completed for a discarded uop (E_S_DONE)
always_ff @(posedge clk) begin
	xres_t xo;
	xo = xlate(m1.a, m1.smode, m1_wr, fc_tt(m1.fc) == TT_ALT, atc_hit, atc_e,
	           tq_a[0], tq_a[1], tq_a[2], tq_a[3], lvd_q);
	// (while the engine steals the ATC's main port, xlate sees its address,
	// not DC1's: DC1 waits then)
	if (nreset && !steal && m1.ack == 2'd0 && m1.v && !m1_stale &&
	    (xo.hit != x_dc1.hit || (xo.hit && xo.way != x_dc1.way)))
	begin
		$display("FAIL: DMU: the parallel tag compare says hit=%b way=%0d, xlate hit=%b way=%0d",
		         x_dc1.hit, x_dc1.way, xo.hit, xo.way);
		sim_xchk <= 1'b1;
	end
end
// synthesis translate_on

always_comb begin
	x_dc1 = x_dc1r;
	// (the same hit and way, from the parallel compare)
	x_dc1.hit = d1_hit && x_dc1.ok && !x_dc1.flt;
	x_dc1.way = d1_way;
	if (m1.ack != 2'd0) begin
		// CPU space (interrupt acknowledge) is never translated nor cached
		x_dc1     = '0;
		x_dc1.ok  = 1'b1;
		x_dc1.pa  = m1.a;
		x_dc1.cm  = 2'b10;
	end
end
wire  [4:0] m1_end   = {1'b0, m1.a[3:0]} + {2'b00, nbytes(m1.msz)};
wire        m1_split = (m1.msz != SZ_Q) && (m1_end > 5'd16);
wire  [7:0] lsd_q    = lsd[m1.a[9:4]];
wire        m1_sfast = ((m1.mem == M_LD) || (m1.mem == M_ST && x_dc1.cm == 2'b01)) &&
                       m1_split && x_dc1.ok && !x_dc1.flt && x_dc1.hit &&
                       !x_dc1.cm[1] && dc_look && (m1.ack == 2'd0) && !m1.lock;
// (locked accesses -- TAS, CAS, CAS2 -- are noncachable (MC68040UM 7.4.1):
// the slow path pushes and invalidates a hit first)
wire        m1_fast  = (m1.mem == M_LD || m1.mem == M_RMW) && !m1.lock &&
                       x_dc1.ok && !x_dc1.flt && x_dc1.hit &&
                       !x_dc1.cm[1] && dc_look && (m1.ack == 2'd0) &&
                       (m1.msz != SZ_Q) && !m1_split;

//--------------------------------------------------------------------------
// DC2
//--------------------------------------------------------------------------
// a store older than the DC2 load and not yet in the data RAM (EX, WB)
wire  [27:0] m2_line = m2.x.pa[31:4];
// (by the line within the page only, PA11-4: a store to the same offset of
// another page is taken for the line too -- the load waits for it, or takes
// the slow path; a smaller, shorter compare on DC2's hold)
function automatic logic st_line(input mrec_t m, input logic [27:0] l);
	st_line = m.r.v && (m.r.mem == M_ST || m.r.mem == M_RMW) &&
	          (m.x.pa[11:4] == l[7:0] || (m.split && m.x1.pa[11:4] == l[7:0]));
endfunction
wire hz = st_line(m3, m2_line) || st_line(m4, m2_line);
// the fast load (never split) waits only for a store whose bytes it reads:
// a plain store within one line is compared by bytes, anything else (RMW,
// split, MOVE16) by the line
wire [15:0] m2_bm = bmask(m2.r.a[3:0], nbytes(m2.r.msz));
function automatic logic st_byte(input mrec_t m);
	st_byte = st_line(m, m2_line) &&
	          (m.r.mem == M_RMW || m.split || m.r.msz == SZ_Q ||
	           (bmask(m.x.pa[3:0], nbytes(m.r.msz)) & m2_bm) != 16'd0);
endfunction
wire hzf = st_byte(m3) || st_byte(m4);
// any store older than the DC2 uop not yet performed: a table walk for the
// DC2 uop must see it (the program may just have written a descriptor)
wire st_older = (m3.r.v && (m3.r.mem == M_ST || m3.r.mem == M_RMW)) ||
                (m4.r.v && (m4.r.mem == M_ST || m4.r.mem == M_RMW));
// a RAM write to the load's set, or any engine activity, after its lookup
// read the RAM makes the captured line stale: the engine reads it again

// (a store that left WB is still being written this cycle: dw)
wire fast_now = m2.r.v && m2.fast && !hzf && !(dw && !dwp && dw_set == m2.r.a[9:4]);
// (the operand from DC2's two long words: its bytes start at a[1:0] of the
// first; a split load's bytes past the line are masked by its user)
wire [31:0] fast_data = take({dq2, 64'd0}, {2'd0, m2.r.a[1:0]}, nbytes(m2.r.msz));

// a store with its translation known needs nothing from DC2 unless it must
// allocate (copyback miss), is split, or is a MOVE16 destination
wire st_simple = m2.r.v && (m2.r.mem == M_ST) && m2.x.ok && !m2.x.flt && !m2.split &&
                 (m2.r.msz != SZ_Q) &&
                 !(dc_en && m2.x.cm == 2'b01 && !m2.x.hit && !m2.r.noalloc && !m2.r.lock);

//--------------------------------------------------------------------------
// engine
//--------------------------------------------------------------------------
typedef enum logic [5:0] {
	E_IDLE,
	E_S_START, E_S_XL, E_S_XLW, E_S_XL2, E_S_ACT, E_S_RD, E_S_RDW, E_S_RD2, E_S_BUSD,
	E_S_NEXT, E_S_DONE, E_SP_W, E_SP_2, E_SP_3,
	E_W_START, E_W_PART, E_W_DONE,
	E_M_START, E_M_PG, E_M_SCAN, E_M_SCANW, E_M_SCAN2, E_M_IC, E_M_DONE, E_M_CLR,
	E_FILL, E_FILLW, E_FILL_W, E_FILL_INS, E_PUSHV, E_PUSHVW, E_PUSHV_W, E_PUSHV_B,
	E_BUS, E_BUS_W,
	E_TW_START, E_TW_DESC, E_TW_DESCW, E_TW_DESCW2, E_TW_DLK, E_TW_DBUS, E_TW_EVAL, E_TW_UPD, E_TW_UPD_W,
	E_TW_LKW, E_TW_DONE,
	E_I_DONE
} est_t;

est_t        e_st, e_ret, e_sret, e_wret;
logic        e_dc2_done;          // DC2 has its answer (until it advances)
logic        e_wst_done;          // the WB store is done (until WB advances)
logic [31:0] e_ldata;
logic        e_flt;
logic [31:0] e_faddr;
logic [15:0] e_fssw;
logic        e_part;              // working on part 1 of a split access
xres_t       e_x;                 // translation of the current part
logic [31:0] e_va;                // logical address of the current part
logic  [2:0] e_n;                 // bytes in the current part
logic [31:0] e_acc;               // load: assembled operand; store: left aligned data
logic        e_fromline;          // the operand comes from bo_line (inhibited fill)
logic        e_fillhit;           // ... from the line a load's own fill just installed
logic        e_kill;              // the DC2 job's uop was discarded
logic        sp_job;              // the DC2 job is a fast split read
logic        sp_dw;               // a write to the next set while its
                                  // stolen read was in flight (E_SP_W)
// engine states that write no data, tag or valid bit: the RAM outputs a
// lookup captured stay good (a fast split read; the RAM re-reads the held
// DC1 set after its stolen read, steal_q)
wire  e_quiet = (e_st == E_IDLE) || (e_st == E_S_START) || (e_st == E_SP_W) ||
                (e_st == E_SP_2) || (e_st == E_SP_3) || (e_st == E_S_DONE && sp_job);
logic        e_job;               // the engine owns the DC2 uop until it is done

// bus operation built by a job, run by E_BUS
typedef struct packed {
	logic        line;            // a line transfer
	logic        rd;
	logic  [1:0] tt;
	logic  [2:0] tm;
	logic  [1:0] upa;
	logic        ci;
	logic        lock;
	logic        locke;
	logic  [1:0] ack;             // acknowledge cycle (see req_t)
	logic  [1:0] tln;
} bop_t;
bop_t        bo;
logic [31:0] bo_wd;               // write data (left aligned)
logic [127:0] bo_line;            // line write data / line read result
logic        bo_err;
logic [31:0] bo_rd;               // read data (right aligned)
logic        bo_avec;
logic        bo_tci;
logic  [2:0] bo_left;             // bytes still to do
logic  [2:0] bo_pn;               // bytes in the piece on the bus
logic [31:0] bo_pa;               // address of the piece on the bus

// fill/push state
logic  [5:0] f_set;
// the dirty RAM's one read: the snoop's compare, the scan's set, else the
// fill/push set
// (the dirty bits share the valid copy's read: the states that read
// one and not the other are given the other's set)
always_comb ld_ra = lv_ra;
logic  [1:0] f_way;
logic [21:0] f_tag;
logic        pv_v;                // push buffer holds a dirty line
logic [127:0] pv_line;
logic [27:0] pv_lpa;              // its line address
logic        pv_dirty;
logic  [1:0] pv_tln;
logic        pv_lock;             // E_PUSHV: the push is part of a locked sequence (LOCK, 4.6.2)
logic  [1:0] pv_for;              // E_PUSHV: the push serves 0 a DC2 job, 1 a WB store, 2 CPUSH
logic        pbe_r;               // a push ended in TEA: an access error at once (7.6.1)
logic [31:0] pbe_a;               // ... the push's address
logic [127:0] pbe_d;              // ... and its line: the frame's PD0-PD3 (8.4.6)
assign pb_data = pbe_d;
logic [127:0] mv_line;            // MOVE16 line buffer

// the RAM write data: a fill or a restored victim (the buffers hold until
// the write cycle), else a word on every long word with byte enables
assign dw_wdata = (dw_src == 2'd1) ? bo_line : (dw_src == 2'd2) ? pv_line : {4{dw_word}};

// maintenance scan
logic  [7:0] ms_i;                // set*4 + way

// table walk state
typedef enum logic [1:0] { TW_ROOT, TW_PTR, TW_PAGE, TW_IND } twl_t;
twl_t        tw_lvl;
logic [31:0] tw_va;
logic        tw_s, tw_wr, tw_pt, tw_i;   // FC2, write access, PTEST, I-side
logic [31:0] tw_da;               // descriptor address
logic [31:0] tw_d;                // descriptor
logic        tw_wp;               // accumulated write protect
logic        tw_fail, tw_berr;
logic [31:0] tw_pd;               // final page descriptor
logic        tw_lkrd;             // the locked update's read is in flight (E_TW_LKW follows)

wire [6:0] tw_ri = tw_va[31:25];
wire [6:0] tw_pi = tw_va[24:18];
wire [5:0] tw_gi = tc_p ? {1'b0, tw_va[17:13]} : tw_va[17:12];

// next aligned piece of an operand
function automatic void piece(input logic [31:0] a, input logic [2:0] left,
                              output logic [1:0] bsiz, output logic [2:0] n);
	if (a[1:0] == 2'b00 && left >= 3'd4) begin bsiz = SIZ_L; n = 3'd4; end
	else if (a[0] == 1'b0 && left >= 3'd2) begin bsiz = SIZ_W; n = 3'd2; end
	else begin bsiz = SIZ_B; n = 3'd1; end
endfunction

logic [1:0] bo_siz;
logic [2:0] bo_np;
always_comb piece(bo_pa, bo_left, bo_siz, bo_np);

// bytes of a read piece from the lanes, right aligned
function automatic logic [31:0] grab(input logic [31:0] d, input logic [2:0] n,
                                     input logic [1:0] a10);
	case (n)
		3'd1:    grab = {24'd0, d[31 - 8*a10 -: 8]};
		3'd2:    grab = {16'd0, a10[1] ? d[15:0] : d[31:16]};
		default: grab = d;
	endcase
endfunction

// the victim way of a set: the first invalid way, else the counter
function automatic logic [1:0] victim(input logic [3:0] valid, input logic [1:0] rr);
	logic [1:0] v;
	v = rr;
	for (int i = 3; i >= 0; i--) if (!valid[i]) v = 2'(i);
	victim = v;
endfunction

// a line targeted by a store still in EX/WB is never evicted
function automatic logic store_holds(input logic [5:0] set, input logic [1:0] way,
                                     input mrec_t a, input mrec_t b);
	store_holds = (a.r.v && (a.r.mem == M_ST || a.r.mem == M_RMW) && a.x.hit &&
	               a.x.pa[9:4] == set && a.x.way == way) ||
	              (b.r.v && (b.r.mem == M_ST || b.r.mem == M_RMW) && b.x.hit &&
	               b.x.pa[9:4] == set && b.x.way == way);
endfunction

// SSW of an access error (MC68040UM figure 8-6): ATC (an ATC fault, clear
// for a bus error), LK, RW, SIZE (the original access size), TT and TM as
// the access drives them (MOVES: table 3-2; a MOVE16 line operand reports
// TT = 01).  MA is set by the caller for an ATC fault of the second page.
function automatic logic [15:0] mk_ssw(input logic atc, input logic lk, input logic rd,
                                       input logic [1:0] msz, input logic [2:0] fc);
	logic [1:0] sz;
	case (msz)
		SZ_B: sz = 2'b01;
		SZ_W: sz = 2'b10;
		SZ_L: sz = 2'b00;
		default: sz = 2'b11;
	endcase
	mk_ssw = {4'b0000, 1'b0, atc, lk, rd, 1'b0, sz,
	          (msz == SZ_Q) ? TT_MOVE16 : fc_tt(fc), fc_tm(fc)};
endfunction

//--------------------------------------------------------------------------
// WB fast store: a copyback store that hit, within one line
//--------------------------------------------------------------------------
wire wb_st   = m4.r.v && st_v && (m4.r.mem == M_ST || m4.r.mem == M_RMW);
wire wb_fast = wb_st && !m4.split && m4.x.ok && !m4.x.flt && m4.x.hit &&
               m4.x.cm == 2'b01 && dc_look && !m4.r.lock && (m4.r.msz != SZ_Q) &&
               (e_st == E_IDLE) && !e_wst_done;
wire  [31:0] wbf_word = lanes32(lalign(st_data, m4.r.msz), m4.r.a[1:0]);
wire  [15:0] wbf_be   = bmask(m4.r.a[3:0], nbytes(m4.r.msz));
assign wfm      = wb_fast && !sn_frz;
assign wfm_set  = m4.x.pa[9:4];
assign wfm_way  = m4.x.way;
assign wfm_be   = wbf_be;
assign wfm_word = wbf_word;
always_ff @(posedge clk) dwp <= nreset && wfm;
// a copyback store across a line, both parts hits: the first part this
// cycle, the second the next (wfs_p1), without the engine
logic        wfs_p1;
wire wb_fs = wb_st && m4.split && m4.x.ok && !m4.x.flt && m4.x.hit && m4.x.cm == 2'b01 &&
             m4.x1.ok && !m4.x1.flt && m4.x1.hit && m4.x1.cm == 2'b01 && dc_look &&
             !m4.r.lock && (m4.r.msz != SZ_Q) && (e_st == E_IDLE) && !e_wst_done && !wfs_p1;
wire   [2:0] wfs_n0  = 3'(5'd16 - {1'b0, m4.r.a[3:0]});
wire  [31:0] wfs_acc = lalign(st_data, m4.r.msz);

// a fast load behind an older store to its line waits for it (merged into
// its copy) instead of taking the engine
wire fast_wait = m2.r.v && m2.fast && (hzf || (dw && !dwp && dw_set == m2.r.a[9:4]));
// (not while an older store is in EX: it reaches WB, which has the engine
// first, before DC2's job -- the bus sees a store before a younger load's
// access, whatever the timing)
wire ex_st    = m3.r.v && (m3.r.mem != M_LD);
wire dc2_slow = m2.r.v && !fast_now && !fast_wait && !(st_simple && !e_job) && !e_dc2_done && !e_job &&
                !ex_st;
wire wb_slow  = wb_st && !wb_fast && !wb_fs && !wfs_p1 && !e_wst_done;

// store ready: the fast store answers in its own WB cycle (the engine's
// stores through the registered pulse)
logic st_rdy_r, st_fault_r;
assign st_rdy   = st_rdy_r || (wb_fast && !sn_frz) || (wfs_p1 && m4.x1.hit && !sn_frz);
assign st_fault = st_rdy_r && st_fault_r;

// a failed line fill: the long words of the line the access needs (this
// part's bytes e_va[3:0] .. +e_n-1) all arrived -- a load can complete
// from them; a store needs none from memory, only that the fill started
wire  [3:0] fill_last  = {1'b0, e_va[3:0]} + {1'b0, e_n} - 4'd1;
wire  [3:0] fill_need  = ((4'b1111 << e_va[3:2]) & (4'b1111 >> (2'd3 - fill_last[3:2])));
wire        fill_late_ok = (m2.r.mem == M_ST) ? (bo_got != 4'd0)
                                              : ((fill_need & ~bo_got) == 4'd0);

//--------------------------------------------------------------------------
// BIU request from the engine's bus step
//--------------------------------------------------------------------------
logic e_breq;
always_comb begin
	b_req  = e_breq;
	b_breq = '0;
	// acknowledge cycles (TT=3): IACK at $FFFFFFFF, a byte, TM = the level
	// (7.5.1); the breakpoint acknowledge a byte read at 0, TM = 0 (7.5.2)
	b_breq.addr  = (bo.ack == 2'd1) ? 32'hFFFF_FFFF : bo_pa;
	b_breq.siz   = (bo.ack == 2'd1) ? SIZ_B : bo.line ? SIZ_LINE : bo_siz;
	b_breq.rd    = bo.rd;
	b_breq.tt    = (bo.ack != 2'd0) ? TT_ACK : bo.tt;
	b_breq.tm    = (bo.ack == 2'd1) ? iack_lvl : (bo.ack != 2'd0) ? 3'd0 : bo.tm;
	b_breq.tln   = bo.tln;
	b_breq.upa   = bo.upa;
	b_breq.ci    = bo.ci;
	b_breq.lock  = bo.lock;
	b_breq.locke = bo.locke && !bo.rd && (bo.line || bo_left == bo_np);
	b_wdata      = bo.line ? bo_line :
	               {96'd0, (bo_np == 3'd1) ? {4{bo_wd[31:24]}} :
	                       (bo_np == 3'd2) ? {2{bo_wd[31:16]}} : bo_wd};
end

// (a stale lookup waits the clock its set is read again, rather than
// sending its uop to the engine's general path: after a miss the loads
// behind it would otherwise each take that path, every one keeping the
// engine busy for the next)
assign dm_hold1 = sn_frz || steal || steal_q || (m1.v && m1_stale) ||
                  (e_st != E_IDLE && e_st != E_W_START &&
                   e_st != E_W_PART && e_st != E_W_DONE);

// the table walk's descriptor line in the cache: the hit and its way, from
// the tags and valid bits read at the walk's set (tw_busy: the valid copy
// reads that set throughout the walk, its bus cycles included), registered
// every cycle (tw_hhq, tw_hwq; tw_hvq says the cycle before read that
// set, unfrozen).  E_TW_DLK reads the descriptor by the registered way,
// E_TW_UPD pushes or invalidates by it (waiting a cycle after a snoop
// froze the engine): the compare is off the data and bookkeeping paths
logic        tw_hw_h;
logic  [1:0] tw_hw_w;
logic        tw_hhq, tw_hvq;
logic  [1:0] tw_hwq;
always_comb begin
	tw_hw_h = 1'b0; tw_hw_w = 2'd0;
	for (int i = 0; i < 4; i++)
		if (lve_q[i] && tq_b[i] == tw_da[31:10]) begin tw_hw_h = 1'b1; tw_hw_w = 2'(i); end
end
// the data RAM's way for the engine's line readers, one select (and one
// line multiplexer) for them, every input a flip-flop: the snooper's way
// while it has the cache (the engine is frozen then), the walk's
// descriptor way, else f_way -- the fill's or push's victim way, or the
// hit way an operand or MOVE16 read (E_S_RD, E_SP_2) set
wire  [1:0]  dq_wsel = sn_frz ? sn_way : (e_st == E_TW_DLK) ? tw_hwq : f_way;
wire [127:0] dq_w    = dq_rn[dq_wsel];
// the engine's operand bytes, one extractor for its states: E_SP_3 the
// rest of a split load from the stolen read, E_S_ACT from the line a fill
// delivered (bo_line), E_S_RD2 from the read way (through the shared line
// multiplexer: f_way holds the hit way then)
wire  [2:0]  sp_n0    = 3'(5'd16 - {1'b0, m2.r.a[3:0]});
wire         etk_sp   = (e_st == E_SP_3);
wire [127:0] etk_line = (e_st == E_S_ACT) ? bo_line : dq_w;   // (f_way: e_x.way)
wire  [3:0]  etk_o    = etk_sp ? 4'd0 : e_va[3:0];
wire  [2:0]  etk_n    = etk_sp ? 3'(nbytes(m2.r.msz) - sp_n0) : e_n;
wire [31:0]  etk      = take(etk_line, etk_o, etk_n);

always_ff @(posedge clk) begin
	// a store's answer is kept until WB takes it (WB can be held in the
	// cycle it comes), and e_wst_done keeps the engine from doing the store
	// again -- a pulse there was lost and WB waited for it forever
	if (adv_wb || !wb_st) st_rdy_r <= 1'b0;
	mt_done   <= 1'b0;
	iw_done   <= 1'b0;
	atc_wr    <= 1'b0;
	atc_fall  <= 1'b0;
	atc_fpage <= 1'b0;
	iatc_flush_all  <= 1'b0;
	iatc_flush_page <= 1'b0;
	iatc_wr   <= 1'b0;
	tw_b      <= 1'b0;
	dw        <= 1'b0;
	steal_q   <= steal;
	atc_la_q  <= steal  ? st_la[31:12] : adv_ag ? dm_va[31:12] : m1.a[31:12];
	atc_fc2_q <= steal  ? st_fc2 : adv_ag ? dm_super : m1.smode;
	atc_set_q <= steal  ? (tc_p ? st_la[16:13] : st_la[15:12]) :
	             adv_ag ? (tc_p ? dm_va[16:13] : dm_va[15:12]) :
	                      (tc_p ? m1.a[16:13]  : m1.a[15:12]);

	if (!nreset) begin
		m1 <= '0; m2 <= '0; m3 <= '0; m4 <= '0;
		// (reset leaves the cache alone -- tags, state and data, MC68040UM
		// 4.3: "reset does not invalidate the cache lines"; the valid and
		// dirty bits have their power-up values from their initial blocks,
		// and CINVA clears them when the software asks)
		e_st <= E_IDLE; e_ret <= E_IDLE; e_sret <= E_IDLE; e_wret <= E_IDLE;
		e_dc2_done <= 1'b0; e_wst_done <= 1'b0;
		e_ldata <= '0; e_flt <= 1'b0; e_faddr <= '0; e_fssw <= '0;
		e_part <= 1'b0; e_x <= '0; e_va <= '0; e_n <= '0; e_acc <= '0; e_fromline <= 1'b0; e_fillhit <= 1'b0;
		e_breq <= 1'b0;
		bo <= '0; bo_wd <= '0; bo_line <= '0; bo_err <= 1'b0; bo_rd <= '0;
		bo_avec <= 1'b0; bo_tci <= 1'b0; bo_left <= '0; bo_pn <= '0; bo_pa <= '0;
		steal <= 1'b0; st_la <= '0; st_fc2 <= 1'b0; st_set <= '0;
		f_set <= '0; f_way <= '0; f_tag <= '0;
		pv_v <= 1'b0; pv_line <= '0; pv_lpa <= '0; pv_dirty <= 1'b0; pv_tln <= '0; pv_lock <= 1'b0;
		pv_for <= 2'd0; pbe_r <= 1'b0; pbe_a <= '0; pbe_d <= '0;
		mv_line <= '0;
		ms_i <= '0;
		sc_set <= '0; sc_lv <= '0; sc_ld <= '0;
		tw_lvl <= TW_ROOT; tw_va <= '0; tw_s <= 1'b0; tw_wr <= 1'b0; tw_pt <= 1'b0;
		tw_i <= 1'b0; tw_da <= '0; tw_d <= '0; tw_wp <= 1'b0; tw_fail <= 1'b0;
		tw_berr <= 1'b0; tw_pd <= '0; tw_upd <= 1'b0; tw_hw <= 4'd0; tw_lkrd <= 1'b0; tw_hhq <= 1'b0; tw_hwq <= '0; tw_hvq <= 1'b0;
		tset_b <= '0; tway_b <= '0; twd_b <= '0;
		dw_set <= '0; dw_way <= '0; dw_be <= '0; dw_src <= '0; dw_word <= '0;
		ic_inv <= 1'b0; ic_inv_scope <= '0; ic_inv_pa <= '0;
		rrc <= 2'd0;
		st_fault_r <= 1'b0; st_fssw <= '0; st_faddr <= '0;
		mt_mmusr <= '0; mt_fault <= 1'b0; mt_fssw <= '0; mt_faddr <= '0;
		atc_wla <= '0; atc_wfc2 <= 1'b0; atc_went <= '0; atc_fng <= 1'b0;
		iatc_flush_ng <= 1'b0; iatc_flush_la <= '0; iatc_flush_fc2 <= 1'b0;
		iatc_wla <= '0; iatc_wfc2 <= 1'b0; iatc_went <= '0;
		iw_ent <= '0;
		e_kill <= 1'b0;
		sp_dw  <= 1'b0;
		sp_job <= 1'b0;
		wfs_p1 <= 1'b0;
		e_job <= 1'b0;
		m1_stale <= 1'b0;
		sn_ph <= SN_IDLE; sn_src <= '0; sn_way <= '0; bo_cancel <= 1'b0;
		bo_ingnt <= 1'b0; sn_pvm <= 1'b0; sn_bom <= 1'b0;
		sn_look <= 1'b0; sn_hit <= 1'b0; sn_dirty <= 1'b0;
		clr_i   <= '0;
		clr_rst <= 1'b0;
	end
	else begin
		// the valid/dirty write port: at most one writer per cycle (the
		// WB fast store runs only with the engine idle, the snoop port
		// only with it frozen), applied at the end of this block
		logic [5:0] vp_set;
		logic [3:0] vp_wm;               // ways written
		logic       vp_lwe, vp_lv;       // valid: write, value
		logic       vp_dwe, vp_dv;       // dirty: write, value
		vp_set = '0; vp_wm = '0; vp_lwe = 1'b0; vp_lv = 1'b0;
		vp_dwe = 1'b0; vp_dv = 1'b0;

		//--------------------------------------------------------------
		// stage records
		//--------------------------------------------------------------
		if (adv_ag) begin
			m1.v       <= dm_req;
			m1.a       <= dm_va;
			m1.mem     <= dm_mem;
			m1.msz     <= dm_msz;
			m1.fc      <= dm_fc;
			m1.lock    <= dm_lock;
			m1.locke   <= dm_locke;
			m1.wi      <= dm_wi;
			m1.smode   <= dm_super;
			m1.noalloc <= dm_noalloc;
			m1.ack     <= dm_ack;
			m1_tp      <= transp_of(dm_va, dm_super, dm_fc, dm_ack);
			m1_aset    <= tc_p ? dm_va[16:13] : dm_va[15:12];
			m1_stale   <= (dw && dw_src != 2'd0 && dw_set == dm_va[9:4]) || !e_quiet;
		end
		else begin
			if (adv_dc1) m1.v <= 1'b0;
			m1_tp <= transp_of(m1.a, m1.smode, m1.fc, m1.ack);
			m1_aset <= tc_p ? m1.a[16:13] : m1.a[15:12];
			if ((dw && dw_src != 2'd0 && dw_set == m1.a[9:4]) || !e_quiet) m1_stale <= 1'b1;
			// held, the RAMs and the ATC read DC1's own set again every
			// clock (la_alt): a clock with the engine quiet and no write to
			// that set makes the lookup good again from the next one
			else if (!steal && !sn_rset) m1_stale <= 1'b0;
		end

		if (adv_dc1) begin
			m2.r     <= m1;
			m2.x     <= x_dc1;
			m2.split <= m1_split;
			m2.x1    <= '0;
			m2.fast  <= m1_fast && !m1_stale && !(dw && dw_src != 2'd0 && dw_set == m1.a[9:4]) &&
			            (e_st == E_IDLE);
			// (a store reads nothing: the copy's state does not matter; its
			// first part's lookup is trusted as the general path does)
			m2.sfast <= m1_sfast && (m1.mem == M_ST ||
			            (!m1_stale && !(dw && dw_src != 2'd0 && dw_set == m1.a[9:4]) &&
			             (e_st == E_IDLE)));
		end
		else begin
			if (adv_dc2) m2.r.v <= 1'b0;
			if ((dw && dw_src != 2'd0 && dw_set == m2.r.a[9:4]) || (e_st != E_IDLE)) m2.fast <= 1'b0;
			// its own split lookup (a read) leaves the copy as it was
			if (((dw && dw_src != 2'd0 && dw_set == m2.r.a[9:4]) || !e_quiet) && m2.r.mem != M_ST)
				m2.sfast <= 1'b0;
		end

		if (adv_dc2) begin
			m3 <= m2;
			e_dc2_done <= 1'b0;
		end
		else if (adv_ex) m3.r.v <= 1'b0;

		if (adv_ex) m4 <= m3;
		else if (adv_wb) m4.r.v <= 1'b0;

		if (adv_wb) e_wst_done <= 1'b0;

		//--------------------------------------------------------------
		// the WB fast store
		//--------------------------------------------------------------
		if (wb_fast && !sn_frz) begin
			dw      <= 1'b1;
			dw_set  <= m4.x.pa[9:4];
			dw_way  <= m4.x.way;
			dw_be   <= wbf_be;
			dw_src  <= 2'd0;
			dw_word <= wbf_word;
			vp_set = m4.x.pa[9:4]; vp_wm[m4.x.way] = 1'b1; vp_dwe = 1'b1; vp_dv = 1'b1;
			// answered this cycle: kept only if WB does not move
			st_rdy_r   <= !adv_wb;
			st_fault_r <= 1'b0;
			e_wst_done <= !adv_wb;
		end
		if (wb_fs && !sn_frz) begin
			dw      <= 1'b1;
			dw_set  <= m4.x.pa[9:4];
			dw_way  <= m4.x.way;
			dw_be   <= bmask(m4.r.a[3:0], wfs_n0);
			dw_src  <= 2'd0;
			dw_word <= lanes32(wfs_acc, m4.r.a[1:0]);
			vp_set = m4.x.pa[9:4]; vp_wm[m4.x.way] = 1'b1; vp_dwe = 1'b1; vp_dv = 1'b1;
			wfs_p1  <= 1'b1;
		end
		if (wfs_p1 && !sn_frz) begin
			wfs_p1 <= 1'b0;
			if (m4.x1.hit) begin
				dw      <= 1'b1;
				dw_set  <= m4.x1.pa[9:4];
				dw_way  <= m4.x1.way;
				dw_be   <= bmask(4'd0, nbytes(m4.r.msz) - wfs_n0);
				dw_src  <= 2'd0;
				dw_word <= lanes32(wfs_acc << (8 * wfs_n0), 2'd0);
				vp_set = m4.x1.pa[9:4]; vp_wm[m4.x1.way] = 1'b1; vp_dwe = 1'b1; vp_dv = 1'b1;
				st_rdy_r   <= !adv_wb;
				st_fault_r <= 1'b0;
				e_wst_done <= !adv_wb;
			end
			else begin
				// a snoop took the second line in between: the engine
				// writes the second part (as its own access would)
				e_part <= 1'b1;
				e_va   <= {m4.r.a[31:4] + 28'd1, 4'd0};
				e_x    <= m4.x1;
				e_n    <= nbytes(m4.r.msz) - wfs_n0;
				e_acc  <= wfs_acc << (8 * wfs_n0);
				bo_err <= 1'b0;
				e_st   <= E_W_PART;
			end
		end

		// the walk's line compare, registered (see tw_hhq)
		tw_hhq <= tw_hw_h;
		tw_hwq <= tw_hw_w;
		tw_hvq <= tw_busy && !sn_frz && (f_set == tw_da[9:4]);
		if (tw_busy) f_set <= tw_da[9:4];   // (lv_ra: the walk's set)

		//--------------------------------------------------------------
		// engine (frozen while the snooper has the cache)
		//--------------------------------------------------------------
		if (!sn_frz)
		case (e_st)
		E_IDLE: begin
			steal <= 1'b0;
			// a fetch's walk: its registers loaded whatever the engine takes
			// up (they are free while it is idle, and every other walk loads
			// its own), so the job choice -- the kill late in it -- is not
			// their enable
			if (iw_req && !iw_done) begin
				tw_va <= iw_va; tw_s <= iw_fc2; tw_wr <= 1'b0; tw_pt <= 1'b0; tw_i <= 1'b1;
			end
			if (wfs_p1)
				;                       // a split WB store's second part next
			else if (mt_v && !mt_done)
				e_st <= E_M_START;
			else if (wb_slow)
				e_st <= E_W_START;
			else if ((dc2_slow || (e_job && m2.r.v && !e_dc2_done)) && !kill_now) begin
				// the job's kill mark is cleared HERE, where the uop is known
				// alive (kill_now is excluded), not in E_S_START: a kill can
				// land while the engine sits in E_S_START frozen by a snoop
				// (the kill block below runs every clock, the case does not),
				// and E_S_START's body, run after the freeze, would erase it
				// -- the job then finished for a discarded uop, set
				// e_dc2_done, and the next uop into DC2 was answered at once
				// with the dead job's data (OPENSTEP: a name-cache pointer
				// read as 0 under disk DMA, 2026-10-19)
				e_kill <= 1'b0;
				e_st   <= E_S_START;
			end
			else if (iw_req && !iw_done) begin
				e_ret <= E_I_DONE;
				e_st  <= E_TW_START;
			end
		end

		//==============================================================
		// DC2 slow path
		//==============================================================
		E_S_START: begin
			// (e_kill: cleared when the job was scheduled, see E_IDLE)
			e_job  <= 1'b1;
			e_part <= 1'b0;
			e_va   <= m2.r.a;
			e_x    <= m2.x;
			e_acc  <= '0;
			e_flt  <= 1'b0;
			e_fromline <= 1'b0;
			e_fillhit  <= 1'b0;
			e_n    <= m2.split ? 3'(5'd16 - {1'b0, m2.r.a[3:0]}) : nbytes(m2.r.msz);
			sp_dw  <= 1'b0;
			sp_job <= m2.sfast;
			if (m2.sfast) begin
				// a load across a line, its first part a hit held in DC2's
				// copy: look the next line up (translation, tags and data
				// at once through the stolen ports)
				steal  <= 1'b1;
				st_la  <= {m2.r.a[31:4] + 28'd1, 4'd0};
				st_fc2 <= m2.r.smode;
				st_set <= m2.r.a[9:4] + 6'd1;
				e_st   <= E_SP_W;
			end
			else
				e_st   <= m2.x.ok ? E_S_ACT : E_S_XL;
		end
		E_SP_W: e_st <= E_SP_2;         // the RAMs register the stolen address
		E_SP_3: begin
			logic [2:0] n0;
			n0 = 3'(5'd16 - {1'b0, m2.r.a[3:0]});
			if (!e_kill && m2.sfast && m2.r.mem == M_ST && e_x.ok && !e_x.flt && !e_x.walk &&
			    e_x.hit && e_x.cm == 2'b01) begin
				// a copyback store across a line: both parts hit, nothing
				// to read; WB writes them
				m2.x1 <= e_x;
				e_st  <= E_S_DONE;
			end
			else if (!e_kill && m2.sfast && m2.r.mem == M_LD && e_x.ok && !e_x.flt && !e_x.walk &&
			    e_x.hit && !e_x.cm[1] &&
			    !hz && !st_line(m3, e_x.pa[31:4]) && !st_line(m4, e_x.pa[31:4]) &&
			    !sp_dw && !(dw && (dw_set == m2.r.a[9:4] || dw_set == st_set))) begin
				// the first part from DC2's copy, the rest from the stolen read
				// (DC2's bytes are fast_data's: its low bytes, past the
				// line, give way to the stolen read's)
				e_acc <= (fast_data & ~((32'd1 << (8 * (nbytes(m2.r.msz) - n0))) - 32'd1)) |
				         etk;
				m2.x1 <= e_x;
				e_st  <= E_S_DONE;
			end
			else begin
				steal  <= 1'b0;
				sp_job <= 1'b0;
				e_x    <= m2.x;
				e_st   <= m2.x.ok ? E_S_ACT : E_S_XL;
			end
		end
		E_SP_2: begin
			xres_t x;
			x  = xlate({m2.r.a[31:4] + 28'd1, 4'd0}, m2.r.smode, (m2.r.mem != M_LD || m2.r.lock || m2.r.wi),
			           fc_tt(m2.r.fc) == TT_ALT, atc_hit, atc_e,
			           tq_a[0], tq_a[1], tq_a[2], tq_a[3], lve_q);
			// the second part's translation and lookup, registered (the
			// decision and the data next cycle; the RAM keeps reading the
			// stolen set, the line multiplexer its way)
			e_x  <= x;
			f_way <= x.way;
			e_st <= E_SP_3;
		end
		E_S_XL: begin
			// look the current part up (translation and tags) via the
			// stolen ports; one cycle for the RAM and ATC reads
			steal  <= 1'b1;
			st_la  <= e_va;
			st_fc2 <= m2.r.smode;
			st_set <= e_va[9:4];
			e_st   <= E_S_XLW;
		end
		E_S_XLW: e_st <= E_S_XL2;      // the RAMs register the stolen address
		E_S_XL2: begin
			xres_t x;
			// (after a search: the ATC holds its result, a nonresident
			// entry for a failed one)
			x = xlate(e_va, m2.r.smode, (m2.r.mem != M_LD || m2.r.lock || m2.r.wi), fc_tt(m2.r.fc) == TT_ALT,
			          atc_hit, atc_e, tq_a[0], tq_a[1], tq_a[2], tq_a[3], lve_q);
			if (m2.r.ack != 2'd0) begin
				x    = '0;
				x.ok = 1'b1;
				x.pa = e_va;
				x.cm = 2'b10;
			end
			if (x.walk && e_kill) begin
				// the uop was discarded: no search for it
				steal  <= 1'b0;
				e_job  <= 1'b0;
				e_st   <= E_IDLE;
			end
			else if (x.walk && (st_older || dm_older)) begin
				// a table search only for the oldest instruction: older
				// stores first (they need the engine at WB), and nothing
				// older may discard the access after its search has set
				// history bits or met a bus error: retry
				steal <= 1'b0;
				e_st  <= E_IDLE;
			end
			else if (x.walk) begin
				tw_va <= e_va; tw_s <= m2.r.smode; tw_wr <= (m2.r.mem != M_LD || m2.r.lock || m2.r.wi);
				tw_pt <= 1'b0; tw_i <= 1'b0;
				tw_upd <= atc_hit;          // a first write: the entry's M
				tw_hw  <= atc_hv;           // (its way: the install rewrites it)
				e_ret <= E_S_XL;            // look up again after the walk
				e_st  <= E_TW_START;
			end
			else begin
				e_x  <= x;
				e_st <= E_S_ACT;
			end
		end
		E_S_ACT: if (e_kill) begin
			// the uop was discarded (no bus operation is in flight here)
			steal <= 1'b0;
			e_job <= 1'b0;
			e_st  <= E_IDLE;
		end
		else begin
			logic cach, alloc, rd, move16;
			move16 = (m2.r.msz == SZ_Q);
			cach   = dc_look && !e_x.cm[1] && !m2.r.lock && (m2.r.ack == 2'd0) && !move16;
			alloc  = cach && dc_en && !m2.r.noalloc;
			rd     = (m2.r.mem == M_LD) || (m2.r.mem == M_RMW);
			if (e_x.flt) begin
				e_flt   <= 1'b1;
				// FA is the operand's first byte even when a later part
				// faulted; MA marks an ATC fault on the second page
				e_faddr <= m2.r.a;
				e_fssw  <= mk_ssw(1'b1, m2.r.lock, m2.r.mem == M_LD && !m2.r.wi, m2.r.msz, m2.r.fc) |
				           (e_part ? 16'h0800 : 16'h0000);
				e_st    <= E_S_DONE;
			end
			else if (e_fillhit) begin
				// the fill installed the line (f_way) and it is in bo_line:
				// the operand from it, the part now a hit in that way
				e_acc     <= (e_acc << (8 * e_n)) | etk;
				e_fillhit <= 1'b0;
				e_x.hit   <= 1'b1;
				e_x.way   <= f_way;
				e_st      <= E_S_NEXT;
			end
			else if (e_fromline) begin
				// an inhibited fill delivered the line: the operand from it
				e_acc <= (e_acc << (8 * e_n)) | etk;
				e_fromline <= 1'b0;
				e_x.hit <= 1'b0;
				e_x.cm  <= 2'b11;
				e_st    <= E_S_NEXT;
			end
			else if (rd && !e_part && (m2.r.ack == 2'd0) && (e_x.cm[1] || m2.r.lock) && dm_older) begin
				// a serialized read (a noncachable serialized page, or a
				// locked access) waits until every earlier instruction has
				// completed: pending writes are on the bus first, and
				// nothing older can abort the instruction after the read
				// (MC68040UM 4.3.2, 7.7).  So does any cache-inhibited
				// read: the 68040 never reads a device on a path an older
				// instruction then discards (a mispredicted branch, a
				// serializing MOVEC) -- such a read cannot be taken back.
				// Retry from the start.
				steal <= 1'b0;
				e_st  <= E_IDLE;
			end
			else if (move16 && m2.r.mem == M_LD && e_x.hit && dc_look) begin
				// MOVE16 source hit: read from the cache, no allocation
				e_st <= E_S_RD;
			end
			else if (move16 && m2.r.mem == M_ST) begin
				// MOVE16 destination: a write hit invalidates the line (the
				// write replaces all of it, 4.3.2) -- unless CDIS, which
				// leaves the contents alone
				if (e_x.hit && dc_look) begin
					vp_set = e_va[9:4]; vp_wm[e_x.way] = 1'b1;
					vp_lwe = 1'b1; vp_lv = 1'b0; vp_dwe = 1'b1; vp_dv = 1'b0;
					e_x.hit <= 1'b0;
				end
				e_st <= E_S_NEXT;
			end
			else if (m2.r.mem == M_ST) begin
				// a store: a copyback miss allocates the line for WB
				if (alloc && e_x.cm == 2'b01 && !e_x.hit) begin
					f_set  <= e_va[9:4];
					f_tag  <= e_x.pa[31:10];
					f_way  <= victim(lve_q, rrc);
					e_sret <= E_S_XL;
					e_st   <= E_FILL;
				end
				else e_st <= E_S_NEXT;
			end
			else if (cach && e_x.hit && rd) begin
				// older stores to this line must reach the RAM first: give
				// the engine back to them and retry (the line of the part
				// being read: a split's second part has its own)
				if (e_part ? (st_line(m3, e_x.pa[31:4]) || st_line(m4, e_x.pa[31:4])) : hz) begin
					steal <= 1'b0; e_st <= E_IDLE;
				end
				else e_st <= E_S_RD;
			end
			else if (alloc && rd && !e_x.hit &&
			         (e_part ? (st_line(m3, e_x.pa[31:4]) || st_line(m4, e_x.pa[31:4])) : hz)) begin
				// an older store to this line has not reached memory yet
				steal <= 1'b0;
				e_st  <= E_IDLE;
			end
			else if (alloc && rd && !e_x.hit) begin
				f_set  <= e_va[9:4];
				f_tag  <= e_x.pa[31:10];
				f_way  <= victim(lve_q, rrc);
				e_sret <= E_S_XL;
				e_st   <= E_FILL;
			end
			else if (rd) begin
				// cache inhibited, no-allocate miss, locked, MOVE16 miss,
				// IACK: a matching line is pushed (if dirty) and invalidated
				// first (4.3.2, 4.6.2; with LOCK for a locked access); the
				// bus access goes in program order.  With CDIS the cache's
				// contents are left alone
				if (e_x.hit && dc_look && (m2.r.lock || e_x.cm[1] || move16)) begin
					f_set  <= e_va[9:4];
					f_way  <= e_x.way;
					pv_lock <= m2.r.lock;
					pv_for  <= 2'd0;
					e_sret <= E_S_ACT;
					e_x.hit <= 1'b0;
					e_st   <= E_PUSHV;
				end
				else if ((m3.r.v && m3.r.mem != M_LD) || (m4.r.v && m4.r.mem != M_LD)) begin
					// older stores go to the bus first (program order): the
					// engine is theirs until they are done, then retry
					steal <= 1'b0;
					e_st  <= E_IDLE;
				end
				else begin
					bo.line  <= move16;
					bo.rd    <= 1'b1;
					bo.tt    <= move16 ? TT_MOVE16 : fc_tt(m2.r.fc);
					bo.tm    <= fc_tm(m2.r.fc);
					bo.upa   <= e_x.upa;
					bo.ci    <= e_x.cm[1];
					bo.lock  <= m2.r.lock;
					bo.locke <= 1'b0;
					bo.ack   <= m2.r.ack;
					bo.tln   <= 2'd0;
					bo_pa    <= move16 ? {e_x.pa[31:4], 4'd0} : e_x.pa;
					bo_left  <= move16 ? 3'd4 : e_n;
					e_ret    <= E_S_BUSD;
					e_st     <= E_BUS;
				end
			end
			else e_st <= E_S_NEXT;
		end
		E_S_RD: begin
			// read the line through the stolen data port (the shared line
			// multiplexer selects f_way: the hit way's, for the operand
			// and for a MOVE16 source)
			steal  <= 1'b1;
			st_set <= e_va[9:4];
			f_way  <= e_x.way;
			e_st   <= E_S_RDW;
		end
		E_S_RDW: e_st <= E_S_RD2;
		E_S_RD2: begin
			if (m2.r.msz == SZ_Q) mv_line <= dq_w;
			else e_acc <= (e_acc << (8 * e_n)) | etk;
			e_st <= E_S_NEXT;
		end
		E_S_BUSD: begin
			// the bus read finished
			// (an acknowledge cycle's TEA is no access error: IACK takes the
			// spurious vector, BKPT the illegal instruction exception)
			if (bo_err && (m2.r.ack == 2'd0)) begin
				// FA is the operand's first byte even when a later part
				// faulted (MA marks an ATC fault only, 8.4.6.2)
				e_flt   <= 1'b1;
				e_faddr <= m2.r.a;
				e_fssw  <= mk_ssw(1'b0, m2.r.lock, 1'b1, m2.r.msz, m2.r.fc);
				e_st    <= E_S_DONE;
			end
			else begin
				if (m2.r.ack == 2'd1)
					// IACK: [7:0] vector, [8] AVEC, [9] TEA = spurious
					e_acc <= {22'd0, bo_err, bo_avec && !bo_err, bo_rd[7:0]};
				else if (m2.r.msz == SZ_Q)
					mv_line <= bo_line;
				else
					e_acc <= (e_acc << (8 * e_n)) | bo_rd;
				e_st <= E_S_NEXT;
			end
		end
		E_S_NEXT: begin
			if (m2.split && !e_part) begin
				m2.x   <= e_x;                 // part 0, for WB
				e_part <= 1'b1;
				e_va   <= {m2.r.a[31:4] + 28'd1, 4'd0};
				e_n    <= nbytes(m2.r.msz) - e_n;
				e_st   <= E_S_XL;
			end
			else begin
				if (m2.split) m2.x1 <= e_x; else m2.x <= e_x;
				e_st <= E_S_DONE;
			end
		end
		E_S_DONE: begin
			e_job      <= 1'b0;
			e_dc2_done <= !e_kill;
			// synthesis translate_off
			// a job may only complete for a uop still in DC2: a discarded
			// one carries e_kill (the bench fails the run on this)
			if (!e_kill && !m2.r.v) begin
				$display("FAIL: DMU: the slow-path job completed for a discarded DC2 uop without its kill mark (e_va=%08x)", e_va);
				sim_kchk <= 1'b1;
			end
			// synthesis translate_on
			e_ldata    <= e_acc;
			steal      <= 1'b0;
			e_st       <= E_IDLE;
			// a push this job made ended in TEA: the processor takes an
			// access error at once (7.6.1); the frame reports the push
			if (pbe_r && pv_for == 2'd0) begin
				e_flt   <= 1'b1;
				e_faddr <= pbe_a;
				e_fssw  <= SSW_PUSH | (pv_lock ? 16'h0200 : 16'h0000);
				pbe_r   <= 1'b0;
			end
		end

		//==============================================================
		// WB store through the engine (write-through, cache-inhibited,
		// locked, split, MOVE16)
		//==============================================================
		E_W_START: begin
			e_part <= 1'b0;
			e_acc  <= lalign(st_data, m4.r.msz);
			e_va   <= m4.r.a;
			e_x    <= m4.x;
			e_n    <= m4.split ? 3'(5'd16 - {1'b0, m4.r.a[3:0]}) : nbytes(m4.r.msz);
			bo_err <= 1'b0;
			e_st   <= E_W_PART;
		end
		E_W_PART: begin
			logic [15:0] be; logic upd;
			be  = bmask(e_va[3:0], e_n);
			upd = e_x.hit && dc_look && !e_x.cm[1] && !m4.r.lock && (m4.r.msz != SZ_Q);
			if (e_x.hit && dc_look && (m4.r.lock || e_x.cm[1])) begin
				// a locked write (TAS, CAS: noncachable, 7.4.1) and a
				// cache-inhibited write bypass the cache: a line they hit is
				// pushed if dirty and invalidated before the bus write
				// (4.3.2, 4.6.2) -- unless CDIS, which leaves the contents
				// alone
				f_set   <= e_va[9:4];
				f_way   <= e_x.way;
				pv_lock <= m4.r.lock;
				pv_for  <= 2'd1;
				e_x.hit <= 1'b0;
				e_sret  <= E_W_PART;
				e_st    <= E_PUSHV;
			end
			else begin
			if (upd) begin
				dw      <= 1'b1;
				dw_set  <= e_va[9:4];
				dw_way  <= e_x.way;
				dw_be   <= be;
				dw_src  <= 2'd0;
				dw_word <= lanes32(e_acc, e_va[1:0]);
				if (e_x.cm == 2'b01)
					if (be != 16'd0) begin
						vp_set = e_va[9:4]; vp_wm[e_x.way] = 1'b1; vp_dwe = 1'b1; vp_dv = 1'b1;
					end
			end
			if (upd && e_x.cm == 2'b01) begin
				e_st <= E_W_DONE;            // copyback: no bus write
			end
			else begin
				bo.line  <= (m4.r.msz == SZ_Q);
				bo.rd    <= 1'b0;
				bo.tt    <= (m4.r.msz == SZ_Q) ? TT_MOVE16 : fc_tt(m4.r.fc);
				bo.tm    <= fc_tm(m4.r.fc);
				bo.upa   <= e_x.upa;
				bo.ci    <= e_x.cm[1];
				bo.lock  <= m4.r.lock;
				bo.locke <= m4.r.locke && (!m4.split || e_part);
				bo.ack   <= m4.r.ack;
				bo.tln   <= 2'd0;
				bo_pa    <= (m4.r.msz == SZ_Q) ? {e_x.pa[31:4], 4'd0} : e_x.pa;
				bo_left  <= (m4.r.msz == SZ_Q) ? 3'd4 : e_n;
				bo_wd    <= e_acc;
				bo_line  <= mv_line;
				e_ret    <= E_W_DONE;
				e_st     <= E_BUS;
			end
			end
		end
		E_W_DONE: begin
			// a bus error on the write, or on a push the write made (7.6.1):
			// an access error
			if (bo_err || (pbe_r && pv_for == 2'd1)) begin
				st_rdy_r     <= 1'b1;
				st_fault_r   <= 1'b1;
				st_fssw    <= bo_err ? mk_ssw(1'b0, m4.r.lock, 1'b0, m4.r.msz, m4.r.fc)
				                     : (SSW_PUSH | (pv_lock ? 16'h0200 : 16'h0000));
				st_faddr   <= bo_err ? m4.r.a : pbe_a;
				if (!bo_err) pbe_r <= 1'b0;
				e_wst_done <= 1'b1;
				e_st       <= E_IDLE;
			end
			else if (m4.split && !e_part) begin
				e_part <= 1'b1;
				e_acc  <= e_acc << (8 * e_n);
				e_va   <= {m4.r.a[31:4] + 28'd1, 4'd0};
				e_x    <= m4.x1;
				e_n    <= nbytes(m4.r.msz) - e_n;
				e_st   <= E_W_PART;
			end
			else begin
				st_rdy_r     <= 1'b1;
				st_fault_r   <= 1'b0;
				e_wst_done <= 1'b1;
				e_st       <= E_IDLE;
			end
		end

		//==============================================================
		// maintenance at WB
		//==============================================================
		E_M_START: begin
			mt_fault <= 1'b0;
			case (mt_op)
				MT_PFLUSH, MT_PTEST: begin
					// both ATCs; by page, or all (N: spare global entries).
					// PTEST first discards the page's entry in both ATCs.
					atc_fng       <= (mt_op == MT_PFLUSH) && mt_ng;
					iatc_flush_ng <= (mt_op == MT_PFLUSH) && mt_ng;
					if (mt_op == MT_PFLUSH && mt_scope == 2'd3) begin
						atc_fall       <= 1'b1;
						iatc_flush_all <= 1'b1;
						e_st <= E_M_DONE;
					end
					else begin
						steal  <= 1'b1;
						st_la  <= mt_addr;
						st_fc2 <= mt_fc[2];
						iatc_flush_la  <= mt_addr;
						iatc_flush_fc2 <= mt_fc[2];
						e_st <= E_M_PG;
					end
				end
				default: begin
					// CINV / CPUSH
					if (!mt_caches[0]) e_st <= E_M_IC;
					else if (mt_op == MT_CINV && mt_scope == 2'd3) begin
						clr_i <= '0;
						e_st  <= E_M_CLR;
					end
					else begin
						// scan one set (line), or every set (page, all)
						ms_i <= (mt_scope == 2'd1) ? {mt_addr[9:4], 2'b00} : 8'd0;
						e_st <= E_M_SCAN;
					end
				end
			endcase
		end
		E_M_CLR: begin
			// every line invalid, a set a cycle (CINVA; and after reset)
			vp_set = clr_i; vp_wm = 4'hF;
			vp_lwe = 1'b1; vp_lv = 1'b0;
			clr_i <= clr_i + 6'd1;
			if (clr_i == 6'd63) begin
				clr_rst <= 1'b0;
				e_st    <= clr_rst ? E_IDLE : E_M_IC;
			end
		end
		E_M_PG: begin
			// the stolen ATC read of the page is valid now: flush it.  The
			// flush pulse compares the lookup port in the NEXT cycle, so the
			// port stays stolen (E_M_DONE / the walk's end release it)
			atc_fpage       <= 1'b1;
			iatc_flush_page <= 1'b1;
			if (mt_op == MT_PTEST) begin
				// a transparent translation answers without a search
				logic t0, t1, it0, it1, hitt, wpt, isp;
				isp = (mt_fc[1:0] == 2'b10);
				t0  = ttr_hit(dtt0, mt_addr, mt_fc[2]);
				t1  = ttr_hit(dtt1, mt_addr, mt_fc[2]);
				it0 = ttr_hit(itt0, mt_addr, mt_fc[2]);
				it1 = ttr_hit(itt1, mt_addr, mt_fc[2]);
				hitt = isp ? (it0 || it1) : (t0 || t1);
				wpt  = isp ? (it0 ? itt0[2] : itt1[2]) : (t0 ? dtt0[2] : dtt1[2]);
				if (hitt) begin
					mt_mmusr <= (mt_wr && wpt) ? 32'h0000_0800 : 32'h0000_0003;
					e_st <= E_M_DONE;
				end
				else begin
					tw_va <= mt_addr; tw_s <= mt_fc[2]; tw_wr <= mt_wr;
					tw_pt <= 1'b1; tw_i <= isp;
					tw_upd <= 1'b0;              // (the page's entry was just discarded)
					e_ret <= E_M_DONE;
					e_st  <= E_TW_START;
				end
			end
			else e_st <= E_M_DONE;
		end
		E_M_SCAN: begin
			tset_b <= ms_i[7:2];
			steal  <= 1'b1;
			st_set <= ms_i[7:2];
			sc_set <= ms_i[7:2];
			e_st   <= E_M_SCANW;
		end
		E_M_SCANW: begin
			// (a write this cycle reaches the copy at the write port)
			sc_lv <= lve_q;
			sc_ld <= ld_q;                 // (ld_ra: sc_set)
			e_st <= E_M_SCAN2;
		end
		E_M_SCAN2: begin
			logic [5:0] s; logic [1:0] w; logic m;
			s = ms_i[7:2]; w = ms_i[1:0];
			m = sc_lv[w] && ((mt_scope == 2'd3) ||
			                 (mt_scope == 2'd1 && tq_b[w] == mt_addr[31:10]) ||
			                 (mt_scope == 2'd2 && (tc_p ? tq_b[w][21:3] == mt_addr[31:13]
			                                            : tq_b[w][21:2] == mt_addr[31:12])));
			if (m && mt_op == MT_CPUSH && sc_ld[w]) begin
				// push (it is invalidated with the push)
				f_set   <= s;
				f_way   <= w;
				pv_lock <= 1'b0;
				pv_for  <= 2'd2;
				e_sret  <= E_M_SCAN;         // reread the set's tags after
				e_st    <= E_PUSHV;
			end
			else begin
				if (m) begin
					vp_set = s; vp_wm[w] = 1'b1;
					vp_lwe = 1'b1; vp_lv = 1'b0; vp_dwe = 1'b1; vp_dv = 1'b0;
				end
				if ((mt_scope == 2'd1 && w == 2'd3) || ms_i == 8'hFF) e_st <= E_M_IC;
				else begin
					ms_i <= ms_i + 8'd1;
					e_st <= (w == 2'd3) ? E_M_SCAN : E_M_SCAN2;
				end
			end
		end
		E_M_IC: begin
			// the instruction cache part of CINV/CPUSH
			steal <= 1'b0;
			if (mt_caches[1]) begin
				ic_inv       <= 1'b1;
				ic_inv_scope <= mt_scope;
				ic_inv_pa    <= mt_addr;
				if (ic_inv_done) begin
					ic_inv <= 1'b0;
					e_st   <= E_M_DONE;
				end
			end
			else e_st <= E_M_DONE;
		end
		E_M_DONE: begin
			mt_done <= 1'b1;
			steal   <= 1'b0;
			e_st    <= E_IDLE;
			// a push of CPUSH's ended in TEA: an access error (7.6.1)
			if (pbe_r && pv_for == 2'd2) begin
				mt_fault <= 1'b1;
				mt_fssw  <= SSW_PUSH;
				mt_faddr <= pbe_a;
				pbe_r    <= 1'b0;
			end
		end

		//==============================================================
		// sub-step: line fill of (f_set, f_way) with tag f_tag, critical
		// long word first.  The victim goes to the push buffer if dirty
		// and is pushed after the fill (4.6.2).  Returns to e_sret.
		//==============================================================
		E_FILL: begin
			if (store_holds(f_set, f_way, m3, m4))
				f_way <= f_way + 2'd1;      // that line belongs to a store
			else begin
				steal  <= 1'b1;
				st_set <= f_set;
				tset_b <= f_set;
				e_st   <= E_FILLW;
			end
		end
		E_FILLW: e_st <= E_FILL_W;
		E_FILL_W: begin
			if (lve_q[f_way] && ld_q[f_way]) begin     // (ld_ra, lv_ra: f_set)
				pv_v     <= 1'b1;
				pv_line  <= dq_w;
				pv_lpa   <= {tq_b[f_way], f_set};
				pv_dirty <= 1'b1;
				pv_tln   <= f_way;
				pv_lock  <= 1'b0;
				pv_for   <= 2'd0;
			end
			vp_set = f_set; vp_wm[f_way] = 1'b1;
			vp_lwe = 1'b1; vp_lv = 1'b0; vp_dwe = 1'b1; vp_dv = 1'b0;
			bo.line <= 1'b1; bo.rd <= 1'b1; bo.tt <= TT_NORMAL;
			bo.tm <= m2.r.smode ? TM_SDATA : TM_UDATA;
			bo.upa <= e_x.upa; bo.ci <= 1'b0; bo.lock <= 1'b0; bo.locke <= 1'b0;
			bo.ack <= 2'd0; bo.tln <= f_way;
			bo_pa   <= {f_tag, f_set, e_va[3:2], 2'b00};
			bo_left <= 3'd4;
			e_ret   <= E_FILL_INS;
			e_st    <= E_BUS;
		end
		E_FILL_INS: begin
			if (!bo_err && !bo_tci) begin
				dw      <= 1'b1;
				dw_set  <= f_set;
				dw_way  <= f_way;
				dw_be   <= 16'hFFFF;
				dw_src  <= 2'd1;
				tw_b    <= 1'b1;
				tset_b  <= f_set;
				tway_b  <= f_way;
				twd_b   <= f_tag;
				vp_set = f_set; vp_wm[f_way] = 1'b1;
				vp_lwe = 1'b1; vp_lv = 1'b1; vp_dwe = 1'b1; vp_dv = 1'b0;
				rrc <= rrc + 2'd1;
			end
			else if (pv_v) begin
				// failed or inhibited fill: the dirty victim is restored
				dw      <= 1'b1;
				dw_set  <= f_set;
				dw_way  <= f_way;
				dw_be   <= 16'hFFFF;
				dw_src  <= 2'd2;
				vp_set = f_set; vp_wm[f_way] = 1'b1;
				vp_lwe = 1'b1; vp_lv = 1'b1; vp_dwe = 1'b1; vp_dv = pv_dirty;
				pv_v <= 1'b0;
			end
			if (bo_err && fill_late_ok) begin
				// a later beat of the line failed, but what the access needs
				// arrived (MC68040UM 7.6.1, 4.6.1): no exception, the line not
				// allocated; a load takes its operand from what was read, a
				// store goes to memory (as for TCI)
				e_fromline <= (m2.r.mem != M_ST);
				e_x.cm     <= 2'b11;
				e_st       <= (m2.r.mem != M_ST) ? E_S_ACT : E_S_NEXT;
			end
			else if (bo_err) begin
				// the operand's long word did not arrive: an access fault
				e_flt   <= 1'b1;
				e_faddr <= m2.r.a;
				e_fssw  <= mk_ssw(1'b0, 1'b0, m2.r.mem == M_LD, m2.r.msz, m2.r.fc);
				e_st    <= E_S_DONE;
			end
			else if (bo_tci) begin
				// not cachable after all: the operand from the line read,
				// a store of this page writes through
				e_fromline <= (m2.r.mem != M_ST);
				e_x.cm     <= 2'b11;
				e_st       <= (m2.r.mem != M_ST) ? E_S_ACT : E_S_NEXT;
			end
			else if (pv_v) e_st <= E_PUSHV_B;
			else if (m2.r.mem == M_LD && e_sret == E_S_XL) begin
				// a load's own fill: its operand from the line just read
				// (still in bo_line), not a second lookup of that line
				e_fillhit <= 1'b1;
				e_st      <= E_S_ACT;
			end
			else e_st <= e_sret;
		end

		//==============================================================
		// sub-step: push (f_set, f_way) if dirty and invalidate it
		// (E_PUSHV), or push the buffered victim (E_PUSHV_B).  Returns
		// to e_sret.
		//==============================================================
		E_PUSHV: begin
			steal  <= 1'b1;
			st_set <= f_set;
			tset_b <= f_set;
			e_st   <= E_PUSHVW;
		end
		E_PUSHVW: e_st <= E_PUSHV_W;
		E_PUSHV_W: begin
			if (lve_q[f_way] && ld_q[f_way]) begin     // (ld_ra, lv_ra: f_set)
				pv_v     <= 1'b1;
				pv_line  <= dq_w;
				pv_lpa   <= {tq_b[f_way], f_set};
				pv_dirty <= 1'b1;
				pv_tln   <= f_way;
				e_st     <= E_PUSHV_B;
			end
			else e_st <= e_sret;
			vp_set = f_set; vp_wm[f_way] = 1'b1;
			vp_lwe = 1'b1; vp_lv = 1'b0; vp_dwe = 1'b1; vp_dv = 1'b0;
		end
		E_PUSHV_B: if (!pv_v) begin
			// a snoop took the buffered victim while the engine was frozen
			// here (an SC = 10 read supplies it and empties the buffer):
			// nothing left to push -- pushing pv_line now would write a stale
			// copy over memory the snooping master may already have changed
			e_st <= e_sret;
		end
		else begin
			// (LOCK on a push inside a locked sequence, 4.6.2)
			bo.line <= 1'b1; bo.rd <= 1'b0; bo.tt <= TT_NORMAL; bo.tm <= TM_PUSH;
			bo.upa <= 2'd0; bo.ci <= 1'b0; bo.lock <= pv_lock; bo.locke <= 1'b0;
			bo.ack <= 2'd0; bo.tln <= pv_tln;
			bo_pa   <= {pv_lpa, 4'd0};
			bo_left <= 3'd4;
			bo_line <= pv_line;
			pv_v    <= 1'b0;
			e_ret   <= e_sret;
			e_st    <= E_BUS;
		end

		//==============================================================
		// sub-step: bus operation (pieces / line / IACK); returns to e_ret
		//==============================================================
		E_BUS: begin
			bo_err <= 1'b0;
			bo_got <= 4'd0;
			bo_tci <= 1'b0;
			bo_avec <= 1'b0;
			bo_rd  <= '0;
			bo_ingnt <= 1'b0;
			if (bo_cancel) begin
				// a snoop invalidated the line this push carries
				bo_cancel <= 1'b0;
				e_st      <= e_ret;
			end
			else begin
				e_breq <= 1'b1;
				e_st   <= E_BUS_W;
			end
		end
		E_BUS_W: begin
			if (bo_cancel && !b_gnt && !bo_ingnt) begin
				// not on the bus yet (the snooped master has it): dropped
				bo_cancel <= 1'b0;
				e_breq    <= 1'b0;
				e_st      <= e_ret;
			end
			else if (b_gnt) begin
				e_breq <= 1'b0;
				bo_pn  <= bo_np;
				bo_ingnt <= 1'b1;
			end
			// (granted, then retried with the bus given up: the BIU drops
			// it on bi_drop and reports it done)
			if (b_err || b_done) begin
				bo_ingnt  <= 1'b0;
				bo_cancel <= 1'b0;
			end
			if (b_rvalid) begin
				if (bo.line) begin
					bo_line[127 - 32*b_rbeat -: 32] <= b_rdata;
					bo_got[b_rbeat] <= 1'b1;
					if (b_rbeat == bo_pa[3:2]) bo_tci <= b_rtci;
				end
				else begin
					bo_rd   <= (bo_rd << (8 * bo_pn)) | grab(b_rdata, bo_pn, bo_pa[1:0]);
					bo_avec <= b_ravec;
				end
			end
			if (b_err) begin
				// a push that ends in TEA: recorded for the access error the
				// job it served takes (7.6.1); the line is gone.  A walk's
				// (a descriptor line pushed before its update) fails the
				// search as a bus error.
				if (bo.line && !bo.rd && bo.tm == TM_PUSH) begin
					if (pv_for == 2'd3) begin tw_fail <= 1'b1; tw_berr <= 1'b1; end
					else begin pbe_r <= 1'b1; pbe_a <= bo_pa; pbe_d <= bo_line; end
				end
				else bo_err <= 1'b1;
				e_st   <= e_ret;
			end
			else if (b_done) begin
				if (bo.line || bo.ack != 2'd0) e_st <= e_ret;
				else begin
					if (!bo.rd) bo_wd <= bo_wd << (8 * bo_pn);
					bo_pa   <= bo_pa + {29'd0, bo_pn};
					bo_left <= bo_left - bo_pn;
					if (bo_left == bo_pn) e_st <= e_ret;
					else e_breq <= 1'b1;
				end
			end
		end

		//==============================================================
		// table walk (MC68040UM 3.2); the entry goes into the ATC that
		// tw_i selects; returns to e_ret
		//==============================================================
		E_TW_START: begin
			tw_lvl  <= TW_ROOT;
			tw_wp   <= 1'b0;
			tw_fail <= 1'b0;
			tw_berr <= 1'b0;
			tw_lkrd <= 1'b0;
			tw_da   <= {(tw_s ? srp[31:9] : urp[31:9]), 9'd0} + {23'd0, tw_ri, 2'b00};
			e_st    <= E_TW_DESC;
		end
		E_TW_DESC: begin
			// descriptor read: from the data cache if the line is there
			// (cachable write-through, no allocate, 3.2.5), else from the bus
			steal  <= 1'b1;
			st_set <= tw_da[9:4];
			tset_b <= tw_da[9:4];
			e_st   <= E_TW_DESCW;
		end
		// The tag RAM registers its port B address: tset_b lands at the end
		// of E_TW_DESC, the RAM takes it at the end of E_TW_DESCW, its tags
		// are on tq_b in E_TW_DESCW2, and the compare registered at the end
		// of that cycle (tw_hhq, tw_hwq) is what E_TW_DLK reads.  One wait
		// state fewer sampled the compare against the set addressed BEFORE
		// (the previous descriptor's, or the pipeline's): a false hit took
		// another line's data for the descriptor, a false miss read memory
		// past a dirty cached descriptor (the NeXT kernel's page-fault loop
		// of 2026-10-19, tb/asm/t_nx8k.s).
		E_TW_DESCW:  e_st <= E_TW_DESCW2;
		E_TW_DESCW2: e_st <= E_TW_DLK;    // (the tags of the set valid: the compare registers)
		E_TW_DLK: begin
			if (tw_hhq && dc_look) begin
				tw_d <= take(dq_w, tw_da[3:0], 3'd4);
				e_st <= E_TW_EVAL;
			end
			else begin
				bo.line <= 1'b0; bo.rd <= 1'b1; bo.tt <= TT_NORMAL;
				bo.tm   <= tw_i ? TM_TBL_CODE : TM_TBL_DATA;
				bo.upa  <= 2'd0; bo.ci <= 1'b0; bo.lock <= 1'b0; bo.locke <= 1'b0;
				bo.ack  <= 2'd0; bo.tln <= 2'd0;
				bo_pa   <= tw_da;
				bo_left <= 3'd4;
				e_wret  <= e_ret;
				e_ret   <= E_TW_DBUS;
				e_st    <= E_BUS;
			end
		end
		E_TW_DBUS: begin
			e_ret <= e_wret;
			if (bo_err) begin
				tw_fail <= 1'b1;
				tw_berr <= 1'b1;
				e_st    <= E_TW_DONE;
			end
			else begin
				tw_d <= bo_rd;
				e_st <= E_TW_EVAL;
			end
		end
		E_TW_EVAL: begin
			case (tw_lvl)
				TW_ROOT, TW_PTR: begin
					if (!tw_d[1]) begin
						tw_fail <= 1'b1;           // invalid table descriptor
						e_st    <= E_TW_DONE;
					end
					else begin
						tw_wp <= tw_wp | tw_d[2];
						if (!tw_d[3]) e_st <= E_TW_UPD;   // set U
						else begin
							if (tw_lvl == TW_ROOT) begin
								tw_lvl <= TW_PTR;
								tw_da  <= {tw_d[31:9], 9'd0} + {23'd0, tw_pi, 2'b00};
							end
							else begin
								tw_lvl <= TW_PAGE;
								tw_da  <= (tc_p ? {tw_d[31:7], 7'd0} : {tw_d[31:8], 8'd0}) +
								          {24'd0, tw_gi, 2'b00};
							end
							e_st <= E_TW_DESC;
						end
					end
				end
				default: begin
					// page descriptor (or the one an indirect points to)
					if (tw_d[1:0] == 2'b00 || (tw_lvl == TW_IND && tw_d[1:0] == 2'b10)) begin
						tw_fail <= 1'b1;
						e_st    <= E_TW_DONE;
					end
					else if (tw_d[1:0] == 2'b10) begin
						tw_lvl <= TW_IND;
						tw_da  <= {tw_d[31:2], 2'b00};
						e_st   <= E_TW_DESC;
					end
					else begin
						logic wp, sv, setm;
						wp   = tw_wp | tw_d[2];
						sv   = tw_d[7] && !tw_s;
						// PTESTW: a probe sets M only if the write is permitted
						setm = tw_wr && !wp && !sv && !tw_d[4];
						tw_pd <= tw_d;
						tw_wp <= wp;
						if (!tw_d[3] || setm) e_st <= E_TW_UPD;
						else e_st <= E_TW_DONE;
					end
				end
			endcase
		end
		E_TW_UPD: begin
			// descriptor update, MC68040UM table 3-1: with U clear a locked
			// read-modify-write sets U (the descriptor read again with LOCK,
			// E_TW_LKW, and written back with LOCK and LOCKE), except a
			// permitted write to a clean page (U and M clear), which is a
			// plain write of U and M; U set and M to set: a plain write.
			// The update is noncachable (3.2.5): a cached copy of the
			// descriptor's line is pushed if dirty (with LOCK for a locked
			// update, 4.6.2) and invalidated first.
			logic page, sv, setm, needu, lk, h;
			logic [1:0] w;
			logic [31:0] nd;
			est_t caller;
			page  = (tw_lvl == TW_PAGE || tw_lvl == TW_IND);
			sv    = page && tw_d[7] && !tw_s;
			setm  = page && tw_wr && !tw_wp && !sv && !tw_d[4];
			needu = !tw_d[3];
			lk    = needu && !setm;
			nd    = tw_d | 32'h8 | (setm ? 32'h10 : 32'h0);
			// (back from the push: e_ret is this state, the caller in e_wret)
			caller = (e_ret == E_TW_UPD) ? e_wret : e_ret;
			h = tw_hhq; w = tw_hwq;           // (registered the cycle before, lv_ra: tw_da)
			if (!tw_hvq) ;                    // (a snoop had the set: the compare registers now)
			else begin
			e_wret <= caller;
			if (h && ld_q[w]) begin
				// a dirty copy: pushed (E_PUSHV invalidates it), then back here
				f_set   <= tw_da[9:4];
				f_way   <= w;
				pv_lock <= lk;
				pv_for  <= 2'd3;
				e_sret  <= E_TW_UPD;
				e_st    <= E_PUSHV;
			end
			else begin
				if (h) begin
					vp_set = tw_da[9:4]; vp_wm[w] = 1'b1;
					vp_lwe = 1'b1; vp_lv = 1'b0; vp_dwe = 1'b1; vp_dv = 1'b0;
				end
				bo.line <= 1'b0; bo.tt <= TT_NORMAL;
				bo.tm   <= tw_i ? TM_TBL_CODE : TM_TBL_DATA;
				bo.upa  <= 2'd0; bo.ci <= 1'b1;
				bo.ack  <= 2'd0; bo.tln <= 2'd0;
				bo_pa   <= tw_da;
				bo_left <= 3'd4;
				e_st    <= E_BUS;
				if (lk) begin
					bo.rd   <= 1'b1;
					bo.lock <= 1'b1; bo.locke <= 1'b0;
					e_ret   <= E_TW_LKW;
				end
				else begin
					tw_d  <= nd;
					if (page) tw_pd <= nd;
					bo.rd   <= 1'b0;
					bo.lock <= 1'b0; bo.locke <= 1'b0;
					bo_wd   <= nd;
					e_ret   <= E_TW_UPD_W;
				end
			end
			end
		end
		E_TW_LKW: begin
			// the locked read is in: U into it, the locked write ends it
			logic [31:0] nd;
			nd = bo_rd | 32'h8;
			if (bo_err) begin
				e_ret   <= e_wret;
				tw_fail <= 1'b1;
				tw_berr <= 1'b1;
				e_st    <= E_TW_DONE;
			end
			else begin
				tw_d <= nd;
				if (tw_lvl == TW_PAGE || tw_lvl == TW_IND) tw_pd <= nd;
				bo.rd   <= 1'b0;
				bo.lock <= 1'b1; bo.locke <= 1'b1;
				bo_pa   <= tw_da;
				bo_left <= 3'd4;
				bo_wd   <= nd;
				e_ret   <= E_TW_UPD_W;
				e_st    <= E_BUS;
			end
		end
		E_TW_UPD_W: begin
			e_ret <= e_wret;
			if (bo_err) begin
				tw_fail <= 1'b1;
				tw_berr <= 1'b1;
				e_st    <= E_TW_DONE;
			end
			else if (tw_lvl == TW_ROOT) begin
				tw_lvl <= TW_PTR;
				tw_da  <= {tw_d[31:9], 9'd0} + {23'd0, tw_pi, 2'b00};
				e_st   <= E_TW_DESC;
			end
			else if (tw_lvl == TW_PTR) begin
				tw_lvl <= TW_PAGE;
				tw_da  <= (tc_p ? {tw_d[31:7], 7'd0} : {tw_d[31:8], 8'd0}) +
				          {24'd0, tw_gi, 2'b00};
				e_st   <= E_TW_DESC;
			end
			else e_st <= E_TW_DONE;
		end
		E_TW_DONE: begin
			atce_t e;
			e = '0;
			if (!tw_fail) begin
				e.pa  = tc_p ? {tw_pd[31:13], 1'b0} : tw_pd[31:12];
				e.g   = tw_pd[10];
				e.upa = tw_pd[9:8];
				e.s   = tw_pd[7];
				e.cm  = cm_eff(tw_pd[6:5]);
				e.m   = tw_pd[4];
				e.w   = tw_wp;
				e.r   = 1'b1;
			end
			e.b = tw_berr;
			// install (failed searches too, as the 68040 does: a nonresident
			// entry, R clear, B for a bus error)
			if (tw_i) begin
				iatc_wr   <= 1'b1;
				iatc_wla  <= tw_va;
				iatc_wfc2 <= tw_s;
				iatc_went <= e;
			end
			else begin
				atc_wr   <= 1'b1;
				atc_wla  <= tw_va;
				atc_wfc2 <= tw_s;
				atc_went <= e;
			end
			iw_ent <= e;
			if (tw_pt) begin
				// MMUSR: page frame (8K: bit 12 clear), B G U1 U0 S CM M - W T R
				mt_mmusr <= tw_berr ? 32'h0000_0800 :
				            tw_fail ? 32'h0000_0000 :
				            ((tc_p ? {tw_pd[31:13], 13'd0} : {tw_pd[31:12], 12'd0}) |
				             {21'd0, tw_pd[10], tw_pd[9:8], tw_pd[7], tw_pd[6:5],
				              tw_pd[4], 1'b0, tw_wp, 1'b0, 1'b1});
			end
			steal <= 1'b0;
			e_st  <= e_ret;
		end
		E_I_DONE: begin
			iw_done <= 1'b1;
			e_st    <= E_IDLE;
		end

		default: e_st <= E_IDLE;
		endcase

		if ((e_st == E_SP_W || e_st == E_SP_2) && dw && dw_set == st_set) sp_dw <= 1'b1;

		if (kill_now) begin
			// a kill comes with the WB uop leaving (or WB empty): every
			// record goes, including one EX moved into WB this cycle
			m1.v   <= 1'b0;
			m2.r.v <= 1'b0;
			m3.r.v <= 1'b0;
			m4.r.v <= 1'b0;
			e_dc2_done <= 1'b0;
			if (e_st != E_IDLE) e_kill <= 1'b1;
			if (e_st == E_IDLE) e_job <= 1'b0;
		end

		//--------------------------------------------------------------
		// snoop port
		//--------------------------------------------------------------
		sn_look <= 1'b0;
		case (sn_ph)
		SN_IDLE: if (sn_req) sn_ph <= SN_A;
		// the RAMs register the snooped set; a data or tag write issued
		// just before the freeze lands in this cycle, and a read of the
		// same set would miss it: present the set once more
		SN_A:    if (!dw && !tw_b) sn_ph <= SN_B;
		SN_B: begin
			logic [5:0] s;
			logic h; logic [1:0] w;
			s = sn_pa[9:4];
			h = 1'b0; w = 2'd0;
			for (int i = 0; i < 4; i++)
				if (lve_q[i] && tq_a[i] == sn_pa[31:10]) begin h = 1'b1; w = 2'(i); end
			sn_way <= w;
			sn_look <= 1'b1;
			sn_pvm <= pv_v && pv_lpa == sn_pa[31:4];
			sn_bom <= (e_st == E_BUS || e_st == E_BUS_W) && bo.line && !bo.rd &&
			          bo.tm == TM_PUSH && !bo_cancel && bo_pa[31:4] == sn_pa[31:4];
			if (h) begin
				sn_src   <= 2'd0;
				sn_hit   <= 1'b1;
				sn_dirty <= ld_q[w];          // (ld_ra: the snooped set)
			end
			else if (pv_v && pv_lpa == sn_pa[31:4]) begin
				// the dirty victim waiting for its push (4.7.2)
				sn_src   <= 2'd1;
				sn_hit   <= 1'b1;
				sn_dirty <= 1'b1;
			end
			else if ((e_st == E_BUS || e_st == E_BUS_W) && bo.line && !bo.rd &&
			         bo.tm == TM_PUSH && !bo_cancel && bo_pa[31:4] == sn_pa[31:4]) begin
				// a push queued for the bus
				sn_src   <= 2'd2;
				sn_hit   <= 1'b1;
				sn_dirty <= 1'b1;
			end
			else begin
				sn_hit   <= 1'b0;
				sn_dirty <= 1'b0;
			end
			sn_ph <= SN_H;
		end
		SN_H: begin
			logic [5:0] s;
			s = sn_pa[9:4];
			// (a line found in a way is invalidated below)
			if (sn_inv && sn_pvm) pv_v <= 1'b0;
			if (sn_inv && sn_bom) bo_cancel <= 1'b1;
			if (sn_wr) begin
				case (sn_src)
				2'd0: begin
					dw      <= 1'b1;
					dw_set  <= s;
					dw_way  <= sn_way;
					dw_be   <= sn_wbe;
					dw_src  <= 2'd0;
					dw_word <= sn_wword;
					vp_set = s; vp_wm[sn_way] = 1'b1; vp_dwe = 1'b1; vp_dv = 1'b1;
				end
				2'd1: for (int i = 0; i < 16; i++)
					if (sn_wbe[i]) pv_line[8*i +: 8] <= sn_wword[8*(i % 4) +: 8];
				default: for (int i = 0; i < 16; i++)
					if (sn_wbe[i]) bo_line[8*i +: 8] <= sn_wword[8*(i % 4) +: 8];
				endcase
			end
			if (!sn_req) sn_ph <= SN_R;
		end
		default: sn_ph <= SN_IDLE;   // SN_R: the owner's address is read again
		endcase
		// a snooped line leaves the cache (found in a way: invalidated)
		if (sn_ph == SN_H && sn_inv && sn_src == 2'd0) begin
			vp_set = sn_pa[9:4]; vp_wm[sn_way] = 1'b1;
			vp_lwe = 1'b1; vp_lv = 1'b0; vp_dwe = 1'b1; vp_dv = 1'b0;
			// (the records' hits on it: at the valid/dirty write port)
		end

		//--------------------------------------------------------------
		// a line leaving the cache -- whoever invalidates it: a snoop, an
		// inhibited or locked access's push, CINV/CPUSH -- leaves no record
		// with a hit on it: the stage records, those loaded this clock from
		// the stage before (DC1's lookup read the valid bits before this
		// write lands), both parts of a split, and the engine's own
		//--------------------------------------------------------------
		// (the record DC1 loads now loses its hit on any invalidation in its
		// set, whatever the way: its way and translation come late, and its
		// set is the untranslated page offset; a lost hit sends the access
		// to the engine, which looks the line up again)
		if (vp_lwe && !vp_lv && (|vp_wm) && adv_dc1 && m1.a[9:4] == vp_set) m2.x.hit <= 1'b0;
		if (vp_lwe && !vp_lv) begin
			for (int j = 0; j < 4; j++) if (vp_wm[j]) begin
				if (!adv_dc1) begin
					if (m2.x.hit && m2.x.pa[9:4] == vp_set && m2.x.way == 2'(j)) m2.x.hit <= 1'b0;
					if (m2.x1.hit && m2.x1.pa[9:4] == vp_set && m2.x1.way == 2'(j)) m2.x1.hit <= 1'b0;
				end
				if (adv_dc2) begin
					if (m2.x.hit && m2.x.pa[9:4] == vp_set && m2.x.way == 2'(j)) m3.x.hit <= 1'b0;
					if (m2.x1.hit && m2.x1.pa[9:4] == vp_set && m2.x1.way == 2'(j)) m3.x1.hit <= 1'b0;
				end
				else begin
					if (m3.x.hit && m3.x.pa[9:4] == vp_set && m3.x.way == 2'(j)) m3.x.hit <= 1'b0;
					if (m3.x1.hit && m3.x1.pa[9:4] == vp_set && m3.x1.way == 2'(j)) m3.x1.hit <= 1'b0;
				end
				if (adv_ex) begin
					if (m3.x.hit && m3.x.pa[9:4] == vp_set && m3.x.way == 2'(j)) m4.x.hit <= 1'b0;
					if (m3.x1.hit && m3.x1.pa[9:4] == vp_set && m3.x1.way == 2'(j)) m4.x1.hit <= 1'b0;
				end
				else begin
					if (m4.x.hit && m4.x.pa[9:4] == vp_set && m4.x.way == 2'(j)) m4.x.hit <= 1'b0;
					if (m4.x1.hit && m4.x1.pa[9:4] == vp_set && m4.x1.way == 2'(j)) m4.x1.hit <= 1'b0;
				end
				if (e_x.hit && e_x.pa[9:4] == vp_set && e_x.way == 2'(j)) e_x.hit <= 1'b0;
			end
		end

		//--------------------------------------------------------------
		// the valid/dirty write port
		//--------------------------------------------------------------
		begin
			if ((vp_dwe || vp_lwe) && vp_wm != 4'd0) begin
				logic [7:0] wo, wn;
				wo = lsw[vp_set];
				wn[7:4] = vp_dwe ? ((wo[7:4] & ~vp_wm) | (vp_wm & {4{vp_dv}})) : wo[7:4];
				wn[3:0] = vp_lwe ? ((wo[3:0] & ~vp_wm) | (vp_wm & {4{vp_lv}})) : wo[3:0];
				lsd[vp_set] <= wn;
				lse[vp_set] <= wn;
				lsw[vp_set] <= wn;
			end
			for (int j = 0; j < 4; j++)
				if (vp_wm[j]) begin
					// synthesis translate_off
					if (vp_lwe) lv[vp_set][j] <= vp_lv;
					// synthesis translate_on
					if (vp_lwe && vp_set == sc_set) sc_lv[j] <= vp_lv;
					if (vp_dwe && vp_set == sc_set) sc_ld[j] <= vp_dv;
				end
		end
	end
end

// synthesis translate_off
always_ff @(posedge clk)
	if (nreset && e_st == E_M_SCAN2 &&
	    (sc_lv != lv[sc_set] || (!sn_frz && (sc_lv & sc_ld) != (sc_lv & ld_q)))) begin
		$display("FAIL: the scan's valid/dirty copy %b %b, the set's %b", sc_lv, sc_ld, lv[sc_set]);
		$finish;
	end
// synthesis translate_on

// snoop: the line found, valid with sn_look (the RAM still reads the
// snooped set in the first H cycle)
assign sn_line = (sn_src == 2'd0) ? dq_w : (sn_src == 2'd1) ? pv_line : bo_line;

assign tw_busy = (e_st == E_TW_START) || (e_st == E_TW_DESC) || (e_st == E_TW_DESCW) || (e_st == E_TW_DESCW2) ||
                 (e_st == E_TW_DLK) || (e_st == E_TW_DBUS) || (e_st == E_TW_EVAL) ||
                 (e_st == E_TW_UPD) || (e_st == E_TW_LKW) || (e_st == E_TW_UPD_W) ||
                 (e_st == E_TW_DONE) ||
                 ((e_st == E_BUS || e_st == E_BUS_W) &&
                  (e_ret == E_TW_DBUS || e_ret == E_TW_LKW || e_ret == E_TW_UPD_W));

// DC2 answer
// once the engine has taken the DC2 uop, only its completion releases it
assign dc2_rdy = !m2.r.v || e_dc2_done || (!e_job && (fast_now || st_simple));
assign ldata   = e_dc2_done ? e_ldata : fast_data;
assign ldata_job = e_dc2_done;
// for AG's capture of a load into a base or index (a short path): the long
// word of the line the address points at -- the operand itself for an
// aligned long or an even word (in the low half), else not offered
wire [31:0] al_word = dq2[63:32];
assign ldata_al  = e_dc2_done ? e_ldata :
                   (m2.r.msz == SZ_W) ? {16'd0, m2.r.a[1] ? al_word[15:0] : al_word[31:16]} : al_word;
assign ldata_alv = e_dc2_done ||
                   (m2.r.msz == SZ_L && m2.r.a[1:0] == 2'd0) ||
                   (m2.r.msz == SZ_W && !m2.r.a[0]);
assign fault   = e_dc2_done && e_flt;
assign fvec    = 8'd2;
assign faddr   = e_faddr;
assign fssw    = e_fssw;

// the valid copies' reads: DC1's lookup; the engine state's set (a
// split's next line, the slow path's, the scan's, else the fill/push set), or the snooped set while the engine is frozen
assign lvd_q = lsd_q[3:0];
wire  [7:0] lse_q = lse[lv_ra];
assign lve_q = lse_q[3:0];
always_comb
	lv_ra = (sn_ph == SN_B)                            ? sn_pa[9:4] :
	        (e_st == E_SP_2)                           ? m2.r.a[9:4] + 6'd1 :
	        (e_st == E_S_XL2 || e_st == E_S_ACT ||
	         e_st == E_W_PART)                         ? e_va[9:4] :
	        (e_st == E_M_SCANW || e_st == E_M_SCAN2)   ? sc_set : f_set;
	// (a walk's set through f_set, which follows tw_da a cycle late while
	// the walk runs: the walk's decode stays off this read address)
initial for (int i = 0; i < 64; i++) begin
	lsd[i] = 8'd0; lse[i] = 8'd0; lsw[i] = 8'd0;
end
// synthesis translate_off
// the copies against the flip-flop model (after reset's sweep)
always_ff @(posedge clk)
	if (nreset && !clr_rst && (lvd_q != lv[m1.a[9:4]] || lve_q != lv[lv_ra])) begin
		$display("FAIL: dmu: valid RAM %b/%b, model %b/%b (sets %0d %0d)",
		         lvd_q, lve_q, lv[m1.a[9:4]], lv[lv_ra], m1.a[9:4], lv_ra);
		$finish;
	end
// synthesis translate_on

endmodule
// ---- ap68040_fetch.sv ----
//--------------------------------------------------------------------------//
// AP68040 - pipelined MC68040                                            //
//                                                                          //
// ap68040_fetch.sv - instruction fetch: I-ATC, instruction cache and the   //
// instruction queue                                                        //
//                                                                          //
// Instruction cache (MC68040UM section 4): 4 Kbytes, four ways of 64 sets //
// of 16-byte lines, physically tagged (PA31-10; the set is LA9-4), a      //
// valid bit per line, replacement by the first invalid way, else a 2-bit  //
// counter.  Lines are filled by a burst (critical long word first, TBI    //
// handled by the BIU, TCI: the line is not allocated).  Cache-inhibited   //
// pages and CACR.IE = 0 fetch long words.  The data RAM holds a long word //
// per address: F1 reads its long word of each way, a fill writes each    //
// beat into the victim way as it arrives; the victim is invalidated and   //
// retagged as the fill starts and validated when it completes (a TCI or  //
// failed fill leaves it invalid, 4.6.1).                                  //
//                                                                          //
// I-ATC (3.3): 64 entries like the D-ATC, translating supervisor and user //
// program space; ITT0/ITT1 transparent translation.  An ATC miss asks the //
// DMU's engine for a table walk; the walk installs the entry here         //
// (iatc_wr) -- a failed search too, as a nonresident entry (3.3) -- and   //
// the fetch looks again.                                                   //
//                                                                          //
// Pipeline, one aligned long word (two words) per cycle -- D1 decodes at  //
// most one instruction a cycle, and the queue absorbs long ones:         //
//   F0  fpc: I-ATC and ITT lookup, cache tag and data RAM read            //
//   F1  translation, tag compare; a hit is the long word's words from    //
//       the fetch address on.  Anything else rolls fpc back and runs in   //
//       miss engine (walk, line fill, cache-inhibited stream, fault)      //
//   F2  predecode                                                          //
//   F3  append to the queue                                                //
//                                                                          //
// The queue holds QN words: slot 0 is always the next word D1 decodes.    //
// A redirect (D1 branch or WB) empties the queue and the pipeline.  A     //
// faulted fetch marks its words; D1 raises the fault only if it uses them //
// (8.2.1).  Only the first fetch of a redirected stream is a demand       //
// fetch; a fault on the lookahead after it is speculative, and the back   //
// end refetches it on demand before it becomes an access error.           //
//                                                                          //
// Branch target buffer: 256 entries (BTB_AW) looked up with the F0       //
// address; a hit (the long word holds the last word of a branch D1        //
// predicted taken) ends the chunk at that word, flags it, and sends F0 to //
// the target in F1 (one bubble): the entry's, or for a return the top of //
// the fetch's return stack (pushed by the calls it takes, resynchronized //
// from D1's on every redirect).  The flagged word's target travels in a  //
// FIFO; D1 checks every flagged word against its own decode.              //
//                                                                          //
// CINV/CPUSH of the instruction cache arrive from the DMU (ic_inv): all   //
// in one cycle, a line in two, a page by a scan of the 64 sets.  Bus     //
// snooping (sn_inv) invalidates a line the same way (MC68040UM table   //
// 4-3, V5/V6).  Game Bub port: so does the system (xi_inv), for writes    //
// the processor's bus does not show it as another master's: its own and   //
// a DMA device's to memory it was let to cache instructions from.         //
//--------------------------------------------------------------------------//

module ap68040_fetch
	import ap68040_pkg::*, ap68040_upkg::*;
#(
	parameter bit DEBUG = 0          // the debug outputs' logic (0: they stay at zero)
)(
	input  logic        clk,
	input  logic        nreset,

	input  logic        redir_v,      // highest priority
	input  logic [31:0] redir_pc,
	input  logic        d_redir_v,    // decoder (predicted branch)
	input  logic [31:0] d_redir_pc,
	input  logic        stop,         // do not start new fetches

	input  logic        smode,        // S bit: program space and TM 6/2
	input  logic [31:0] cacr,
	input  logic [31:0] tc,
	input  logic [31:0] itt0,
	input  logic [31:0] itt1,
	input  logic        cdis,         // CDIS: the cache is disabled (contents kept)
	input  logic        mdis,         // MDIS: no page translation

	// decoder side
	output logic [15:0] win [8],
	output logic  [7:0] win_flt,      // the word came from a faulted fetch
	output logic  [7:0] win_fdem,     // ... the first of a redirected stream
	output logic  [7:0] win_fatc,     // ... an ATC (MMU) fault, else bus error
	output logic  [7:0] win_bt,       // ... ends a branch the BTB took
	output logic [31:0] bt_tgt,       // the target of the first such word
	output logic        dbg_btgo,     // debug: the BTB steers the fetch (a predicted taken branch)
	output logic [31:0] dbg_btpc,     // ... to there
	output pd_t         pd0,          // predecode of win[0]
	output pd_t         pd0_n,        // ... as it will be next cycle
	output logic  [3:0] qcnt,         // words available in win (0..8)
	output logic [31:0] qpc,
	input  logic  [2:0] consume,
	output logic        q_odd,        // the stream starts at an odd address
	input  logic        btb_we,       // D1 writes a BTB entry
	input  logic [BTB_AW-1:0] btb_wi,
	input  logic        btb_wv,       // valid (0 drops the entry)
	input  logic [BTB_TW-1:0] btb_wtag,
	input  logic        btb_wslot,    // the branch ends at word 1 of the long word
	input  logic  [1:0] btb_wkind,    // 0 branch, 1 call, 2 return (target from the stack)
	input  logic [30:0] btb_wtgt,     // target[31:1]
	input  logic [30:0] d_ras,        // D1's return stack, its top entry: the
	input  logic  [2:0] d_ras_tp,     // ... fetch's pointer and top entry are
	input  logic  [3:0] d_ras_n,      // ... resynchronized on every redirect

	// DMU: table walks for the I-ATC, I-ATC maintenance, cache invalidation
	output logic        iw_req,
	output logic [31:0] iw_va,
	output logic        iw_fc2,
	input  logic        iw_done,
	input  logic        iatc_wr,
	input  logic [31:0] iatc_wla,
	input  logic        iatc_wfc2,
	input  atce_t       iatc_went,
	input  logic        iatc_flush_all,
	input  logic        iatc_flush_page,
	input  logic        iatc_flush_ng,
	input  logic [31:0] iatc_flush_la,
	input  logic        iatc_flush_fc2,
	input  logic        ic_inv,
	input  logic  [1:0] ic_inv_scope,  // 1 line, 2 page, 3 all
	input  logic [31:0] ic_inv_pa,
	output logic        ic_inv_done,
	input  logic        sn_inv,        // snooper: invalidate the line at sn_inv_pa
	input  logic [31:0] sn_inv_pa,
	input  logic        sn_inv_all,    // ... or every line
	output logic        sn_inv_done,
	output logic        sn_ihit,       // ... and removed a valid line (or the line buffer)
	input  logic        xi_inv,        // Game Bub port: the system: invalidate the line at
	input  logic [31:0] xi_inv_pa,     // ... xi_inv_pa (held until xi_inv_done), as the
	input  logic        xi_inv_all,    // ... snooper's (sn_ihit too), or every line
	output logic        xi_inv_done,

	// BIU client
	output logic        b_req,
	output busreq_t     b_breq,
	input  logic        b_gnt,
	input  logic        b_done,
	input  logic        b_err,
	input  logic        b_rvalid,
	input  logic [31:0] b_rdata,
	input  logic  [1:0] b_rbeat,
	input  logic        b_rtci
);

localparam int QN = 8;            // (12: about 2% faster, 100 ALMs more)

wire tc_e  = tc[15] && !mdis;
wire tc_p  = tc[14];
wire ic_en = cacr[15] && !cdis;

function automatic logic ttr_hit(input logic [31:0] t, input logic [31:0] a,
                                 input logic s);
	ttr_hit = t[15] && (((a[31:24] ^ t[31:24]) & ~t[23:16]) == 8'd0) &&
	          (t[14] || (t[13] == s));
endfunction

//--------------------------------------------------------------------------
// queue
//--------------------------------------------------------------------------
logic [15:0]   qw [QN];
// the words' predecode: D1 reads only the head's, so it is a ring (no
// shift) with the head in a register (qp0) -- loaded as D1 consumes from
// the ring, or from F3 when the queue empties into it
// (two LUT RAM banks by slot parity: F3's two words land in consecutive
// slots, one per bank, so each bank has one write a cycle)
(* ramstyle = "MLAB, no_rw_check" *) logic [$bits(pd_t)-1:0] qpr_e [8];
(* ramstyle = "MLAB, no_rw_check" *) logic [$bits(pd_t)-1:0] qpr_o [8];
logic  [3:0]   qh;             // the ring's head
pd_t           qp0;
// synthesis translate_off
pd_t           qps [QN];       // (simulation: the shifting model, checked)
// synthesis translate_on
logic [QN-1:0] qf, qd, qa;     // faulted, demand fetch, ATC fault
logic [QN-1:0] qb;             // ends a branch the BTB took
logic [30:0]   tq [4];         // their targets, in queue order
logic  [2:0]   tq_n;
logic  [4:0]   cnt;
logic [31:0]   qpc_r;
logic          odd;

assign qcnt  = (cnt > 5'd8) ? 4'd8 : cnt[3:0];
assign qpc   = qpc_r;
assign q_odd = odd;
assign pd0   = qp0;
// the head's predecode as it will be next cycle (qp0's load): D1's
// attribute ROM reads it a cycle ahead
wire [3:0] qh_n = qwrap(5'(qh) + {2'b00, consume});        // the head next cycle
pd_t       qpr_rd;
assign qpr_rd = pd_t'(qh_n[0] ? qpr_o[qh_n[3:1]] : qpr_e[qh_n[3:1]]);
assign pd0_n = (cnt == {2'b00, consume}) ? f3_p[0] : qpr_rd;
function automatic logic [3:0] qwrap(input logic [4:0] x);   // x mod QN, x < 2*QN
	qwrap = (x >= 5'(QN)) ? 4'(x - 5'(QN)) : x[3:0];
endfunction

always_comb begin
	for (int i = 0; i < 8; i++) begin
		win[i]      = qw[i];
		win_flt[i]  = qf[i];
		win_fdem[i] = qd[i];
		win_fatc[i] = qa[i];
		win_bt[i]   = qb[i];
	end
end
assign bt_tgt = {tq[0], 1'b0};

// F2: the words of a chunk, their table words read (ap68040_pdrom, the
// words a cycle after their addresses); F3: predecoded from the table
// words and appended this cycle
logic  [1:0]  f2_n;
logic [15:0]  f2_w [2];
logic         f2_f, f2_d, f2_a;
logic  [1:0]  f2_b;            // the word ends a BTB-taken branch
logic [30:0]  f2_t;
logic  [1:0]  f3_n;
logic [15:0]  f3_w [2];
pdw_t         f3_r [2];        // the table's words for f3_w
pd_t          f3_p [2];
logic         f3_f, f3_d, f3_a;
logic  [1:0]  f3_b;
logic [30:0]  f3_t;
ap68040_pdrom pdrom (.clk(clk), .a0(f2_w[0][15:3]), .a1(f2_w[1][15:3]), .q0(f3_r[0]), .q1(f3_r[1]));
genvar gp;
generate
	for (gp = 0; gp < 2; gp++) begin : g_pd
		ap68040_predec pd (.op(f3_w[gp]), .w(f3_r[gp]), .pd(f3_p[gp]));
		// synthesis translate_off
		// (the table form against the parallel pattern decoder)
		pd_t pd_ref;
		ap68040_predec_pla pdr (.op(f3_w[gp]), .pd(pd_ref));
		always_ff @(posedge clk)
			if (nreset && f3_n > 2'(gp) && f3_p[gp] !== pd_ref) begin
				$display("FAIL: fetch: the table predecode of %04x is %h, the pattern decoder's %h", f3_w[gp], f3_p[gp], pd_ref);
				$finish;
			end
		// synthesis translate_on
	end
endgenerate

//--------------------------------------------------------------------------
// I-ATC
//--------------------------------------------------------------------------
logic [31:0] fpc;              // F0 fetch address (A0 clear)

// BTB: one array per word of the long word (a branch ending at word 0,
// one ending at word 1), each valid, tag, kind, target[31:1]: two taken
// branches in one long word (BSR then RTS, a short branch then RTS) no
// longer evict each other
localparam int BTB_DW = 1 + BTB_TW + 2 + 31;
logic [31:0] f1_pc;              // F1's address
// (block RAM: F0 presents fpc, F1 compares with f1_pc; an entry D1 writes
// at the edge F0's read registers it is not trusted -- no prediction)
logic [BTB_DW-1:0] btb_q0, btb_q1, btb_q;
logic        btb_cf;
ap68040_sdpr #(.AW(BTB_AW), .DW(BTB_DW)) btb0 (
	.clk(clk), .we(btb_we && !btb_wslot), .waddr(btb_wi),
	.wdata({btb_wv, btb_wtag, btb_wkind, btb_wtgt}),
	.raddr(fpc[BTB_AW+1:2]), .q(btb_q0)
);
ap68040_sdpr #(.AW(BTB_AW), .DW(BTB_DW)) btb1 (
	.clk(clk), .we(btb_we && btb_wslot), .waddr(btb_wi),
	.wdata({btb_wv, btb_wtag, btb_wkind, btb_wtgt}),
	.raddr(fpc[BTB_AW+1:2]), .q(btb_q1)
);
always_ff @(posedge clk) btb_cf <= btb_we && (btb_wi == fpc[BTB_AW+1:2]);
// the first branch of the fetch: word 0's when the fetch starts there
wire btb_hit0 = !btb_cf && btb_q0[BTB_DW-1] && btb_q0[BTB_DW-2 -: BTB_TW] == f1_pc[31:BTB_AW+2] && !f1_pc[1];
wire btb_hit1 = !btb_cf && btb_q1[BTB_DW-1] && btb_q1[BTB_DW-2 -: BTB_TW] == f1_pc[31:BTB_AW+2];
wire btb_hit  = btb_hit0 || btb_hit1;
wire btb_qslot = !btb_hit0;
assign btb_q   = btb_hit0 ? btb_q0 : btb_q1;

// the fetch's return stack: pushed by calls the BTB takes, popped by the
// returns it takes (their target), resynchronized from D1's on redirects
// (a LUT RAM: one write a cycle -- a call's push, or the top entry on a
// redirect -- and the top read; the entries below the top are the fetch's
// own: only predictions, EX checks every return)
(* ramstyle = "MLAB, no_rw_check" *) logic [30:0] fras [8];
logic  [2:0] fras_tp;
logic  [3:0] fras_n;
logic        atc_hit;
atce_t       atc_e;
ap68040_atc #(.SAME_SEARCH(0)) iatc (
	.clk(clk), .nreset(nreset), .p8k(tc_p),
	.la(iatc_flush_page ? iatc_flush_la : fpc),
	.fc2(iatc_flush_page ? iatc_flush_fc2 : smode), .set_m(4'd0),
	.hit(atc_hit), .ent(atc_e), .hv(), .wpa(),
	.la_d(32'd0), .fc2_d(1'b0), .set_d(4'd0), .hv_d(), .wpa_d(),
	.wr(iatc_wr), .wla(iatc_wla), .wfc2(iatc_wfc2), .went(iatc_went),
	.wsame(1'b0), .wsame_hv(4'd0),
	.flush_all(iatc_flush_all), .flush_page(iatc_flush_page),
	.flush_nonglobal(iatc_flush_ng)
);

//--------------------------------------------------------------------------
// cache arrays: tags and data in block RAM (read address registered in
// F0), valid bits in flip-flops
//--------------------------------------------------------------------------
// line valid, per set and way: a word of the four ways per set in LUT
// RAMs written at the edge and read without a clock -- one copy at F1's
// set, one at the fill's set or the invalidation's (they never run at
// once).  The second is read at the set every write goes to, so it forms
// the word written (the ways not written keep their bits).  Clearing every
// line (CINVA, a snooped clear, reset) runs the invalidation over the sets
(* ramstyle = "MLAB, no_rw_check" *) logic [3:0] ivf [64];
(* ramstyle = "MLAB, no_rw_check" *) logic [3:0] ivo [64];
wire   [3:0]   ivf_q, ivo_q;
logic  [5:0]   ivo_ra;
logic          inv_rst;         // the invalidation is reset's clear
// synthesis translate_off
logic  [3:0]   iv [64];          // (simulation: the flip-flop model, checked)
// synthesis translate_off
initial for (int i = 0; i < 64; i++) iv[i] = 4'd0;
// synthesis translate_on
// synthesis translate_on
logic  [1:0]   rr;
logic  [5:0]   c_raddr;
logic          c_we;
logic  [5:0]   c_waddr;
logic  [1:0]   c_wway;
logic [21:0]   c_wtag;
logic [31:0]   cd [4];        // each way's long word at F1's address
logic [23:0]   ct [4];

logic [31:0] m_cw;               // the fill's first long word (the one fetched)
logic  [3:0] m_got;              // ... the long words of it that arrived
logic        m_vclr;             // the fill's victim line is still to be invalidated
logic        m_rrinc;            // ... the set was full: the replacement counter moves
// The data RAMs hold a long word per address ({set, A3:A2}): F1 reads its
// long word of each way directly, and a fill writes each beat into the
// victim way as it arrives.  The victim is invalidated and given its new
// tag as the fill starts, and validated when the line is complete (a
// failed or TCI fill leaves it invalid, MC68040UM 4.6.1): the line is in
// the cache for the first fetch after it -- no line buffer.  The long word
// being fetched (the burst's first) is kept for a fill that is not
// allocated (TCI, a later beat's bus error), which delivers it alone.
wire         c_dwe = (st == S_FILL) && b_rvalid && m_alloc && !m_vclr;
genvar gw;
// (declared before their use: Vivado 2018.3 makes a separate implicit net of a
// signal an instance is connected to ahead of its declaration)
logic [31:0] m_pa;
logic  [1:0] m_way;
generate
	for (gw = 0; gw < 4; gw++) begin : g_way
		ap68040_sdp_be #(.AW(8), .NB(4), .OREG(0)) dram (
			.clk(clk), .we(c_dwe && m_way == 2'(gw)), .waddr({m_pa[9:4], b_rbeat}),
			.wbe(4'hF), .wdata(b_rdata), .raddr(fpc[9:2]), .oce(1'b1), .q(cd[gw])
		);
		ap68040_sdp_be #(.AW(6), .NB(3), .OREG(0)) tram (
			.clk(clk), .we(c_we && c_wway == 2'(gw)), .waddr(c_waddr),
			.wbe(3'b111), .wdata({2'b00, c_wtag}), .raddr(c_raddr), .oce(1'b1), .q(ct[gw])
		);
	end
endgenerate

//--------------------------------------------------------------------------
// state
//--------------------------------------------------------------------------
typedef enum logic [2:0] {
	S_RUN,     // pipelined fetch
	S_WALK,    // waiting for the DMU's table walk
	S_FILL,    // line fill burst
	S_CI,      // cache-inhibited long word stream
	S_HALT     // a fault was queued: wait for a redirect
} st_t;
st_t st;

logic        fnew;             // the next F0 starts a redirected stream

// F1
logic        f1_v;
logic        f1_btok;           // F0 had room for a taken branch's target
wire         f1_bt    = f1_btok && btb_hit;   // the BTB hit (in F1)
wire         f1_bslot = btb_qslot;            // ... where the branch ends
wire   [1:0] f1_bkind = btb_q[32:31];
wire  [30:0] f1_btgt  = btb_q[30:0];
logic        f1_s, f1_dem;
logic        f1_hit;
atce_t       f1_e;

logic        m_tci;            // the fill in progress was answered with TCI

// miss engine
logic        b_req_r;          // request pending (not granted yet)
logic        busy;             // a bus transaction is latched
logic        stale;            // ... for a stream that was redirected away
logic [31:0] m_la;             // the fetch address
logic  [1:0] m_upa;
logic        m_s, m_dem, m_ci, m_alloc;

// invalidation
logic        inv_busy, inv_hold, inv_ph;
logic  [6:0] inv_i;
logic        inv_sn;           // the running invalidation is the snooper's
logic        inv_x;            // ... the system's (xi_inv: inv_sn too)
logic        inv_lbh;          // ... and the line buffer held its line
logic  [1:0] inv_scope;
logic [31:0] inv_pa;

wire        redir_any = redir_v || d_redir_v;
wire [31:0] redir_npc = redir_v ? redir_pc : d_redir_pc;

//--------------------------------------------------------------------------
// F1 evaluation
//--------------------------------------------------------------------------
logic        x_ok, x_flt, x_walk, x_cach, x_hit;
logic [31:0] x_pa;
logic  [1:0] x_cm, x_upa, x_way;
logic [31:0] x_chunk;
logic  [3:0] x_mj;
// the ITT matches are formed in F0 (the TTRs change only by MOVEC, which
// serializes and refetches), so F1 starts from them
logic        f1_tt0, f1_tt1;
// ... and whether translation is on (TCR.E, MDIS), taken with them: F1's
// translation and its tag compare select both start from flip-flops
logic        f1_tce;
always_comb begin
	logic tt0, tt1, use_t;
	logic [21:0] tg;
	x_ok = 1'b0; x_flt = 1'b0; x_walk = 1'b0;
	x_pa = f1_pc; x_cm = 2'b00; x_upa = 2'b00;
	tt0 = f1_tt0;
	tt1 = f1_tt1;
	if (tt0 || tt1) begin
		x_ok  = 1'b1;
		x_cm  = tt0 ? itt0[6:5] : itt1[6:5];
		x_upa = tt0 ? itt0[9:8] : itt1[9:8];
	end
	else if (!f1_tce)
		x_ok = 1'b1;               // cachable (MC68040UM 3.1.2)
	else if (f1_hit) begin
		x_pa  = {f1_e.pa[19:1], tc_p ? f1_pc[12] : f1_e.pa[0], f1_pc[11:0]};
		x_cm  = f1_e.cm;
		x_upa = f1_e.upa;
		if (!f1_e.r || (f1_e.s && !f1_s)) x_flt = 1'b1;   // nonresident, supervisor only
		else x_ok = 1'b1;
	end
	else x_walk = 1'b1;
	x_cach = x_ok && ic_en && !x_cm[1];
	// the tags compare with both candidate addresses, the logical one (a
	// TTR or no translation) and the ATC's, and the translation selects
	// the outcome: it stays off the front of the compare (the ATC's
	// address matters only with a hit, x_cach is clear without one)
	use_t  = !(tt0 || tt1) && f1_tce;
	tg     = {f1_e.pa[19:1], tc_p ? f1_pc[12] : f1_e.pa[0], f1_pc[11:10]};
	x_hit  = 1'b0;
	x_way  = 2'd0;
	for (int i = 3; i >= 0; i--) begin
		x_mj[i] = ivf_q[i] && (use_t ? (ct[i][21:0] == tg) : (ct[i][21:0] == f1_pc[31:10]));
		if (x_mj[i]) begin x_hit = 1'b1; x_way = 2'(i); end
	end
	x_hit  = x_hit && x_cach;
	// (the chunk by the one-hot match, AND-OR: no encoded way on the path;
	// at most one way holds a line)
	x_chunk = '0;
	for (int i = 0; i < 4; i++) if (x_mj[i]) x_chunk = x_chunk | cd[i];
end
wire f1_go      = f1_v && !redir_any;
wire f1_deliver = f1_go && x_hit;

//--------------------------------------------------------------------------
// F0 issue: room for this chunk and those in flight
//--------------------------------------------------------------------------
wire [5:0] inflight = (f1_v ? 6'd2 : 6'd0) + {4'd0, f2_n} + {4'd0, f3_n};
// the target FIFO cannot overflow: count the flagged words on their way
// (debug: the BTB's redirect as F1 delivers, its target as below)
assign dbg_btgo = DEBUG && f1_deliver && f1_bt && !(f1_bkind == 2'd2 && fras_n == 4'd0);
assign dbg_btpc = DEBUG ? {((f1_bkind == 2'd2) ? fras[fras_tp] : f1_btgt), 1'b0} : 32'd0;
wire       bt_room  = ({1'b0, tq_n} + {3'd0, f1_v && f1_bt} + {3'd0, |f2_b} + {3'd0, |f3_b}) < 4'd4;
wire       room     = {1'b0, cnt} + inflight <= 6'(QN - 2);
// a snooped invalidation goes first (the snooper has priority, 4.5)
wire       f0_go    = (st == S_RUN) && !odd && !stop && !redir_any &&
                      !iatc_flush_page && !inv_busy && !sn_inv && !xi_inv && room;

assign c_raddr = inv_busy ? inv_i[5:0] : fpc[9:4];

//--------------------------------------------------------------------------
// BIU request
//--------------------------------------------------------------------------
assign b_req = b_req_r;
always_comb begin
	b_breq = '0;
	b_breq.addr = {m_pa[31:2], 2'b00};
	b_breq.rd   = 1'b1;
	b_breq.tt   = TT_NORMAL;
	b_breq.tm   = m_s ? TM_SCODE : TM_UCODE;
	b_breq.upa  = m_upa;
	if (st == S_FILL) begin
		b_breq.siz = SIZ_LINE;
		b_breq.tln = m_way;
	end
	else begin
		b_breq.siz = SIZ_L;
		b_breq.ci  = m_ci;
	end
end

assign iw_va  = m_la;
assign iw_fc2 = m_s;

// a transaction still outstanding after this cycle
wire out_next = (b_req_r && !b_gnt) || b_gnt || (busy && !(b_done || b_err));

//--------------------------------------------------------------------------
// sequential
//--------------------------------------------------------------------------
always_ff @(posedge clk) begin
	logic        frw;              // the return stack's write (below)
	logic  [2:0] frwa;
	logic [30:0] frwd;
	logic  [5:0] iw_set;           // the valid RAMs' write (below)
	logic  [3:0] iw_m;
	logic        iw_v;
	frw = 1'b0; frwa = '0; frwd = '0;
	iw_set = '0; iw_m = '0; iw_v = 1'b0;
	if (!nreset) begin
		cnt   <= '0;
		qf    <= '0; qd <= '0; qa <= '0;
		qpc_r <= '0;
		odd   <= 1'b0;
		fpc   <= '0;
		fnew  <= 1'b1;
		st    <= S_RUN;
		f1_v  <= 1'b0; f1_pc <= '0; f1_s <= 1'b0; f1_dem <= 1'b0; f1_hit <= 1'b0; f1_e <= '0;
		f1_tt0 <= 1'b0; f1_tt1 <= 1'b0; f1_tce <= 1'b0;
		f1_btok <= 1'b0;
		fras_tp <= '0; fras_n <= '0;
		f2_b  <= '0; f2_t <= '0; f3_b <= '0; f3_t <= '0;
		qb    <= '0; tq_n <= '0;
		for (int i = 0; i < 4; i++) tq[i] <= '0;
		f2_n  <= '0; f2_f <= 1'b0; f2_d <= 1'b0; f2_a <= 1'b0;
		for (int i = 0; i < 2; i++) f2_w[i] <= '0;
		f3_n  <= '0; f3_f <= 1'b0; f3_d <= 1'b0; f3_a <= 1'b0;
		for (int i = 0; i < 2; i++) f3_w[i] <= '0;
		m_tci <= 1'b0;
		busy  <= 1'b0; stale <= 1'b0; b_req_r <= 1'b0;
		m_la  <= '0; m_pa <= '0; m_upa <= '0; m_s <= 1'b0; m_dem <= 1'b0; m_ci <= 1'b0;
		m_alloc <= 1'b0; m_way <= '0; m_cw <= '0; m_vclr <= 1'b0; m_rrinc <= 1'b0;
		iw_req <= 1'b0;
		c_we  <= 1'b0; c_waddr <= '0; c_wway <= '0; c_wtag <= '0;
		rr    <= '0;
		// (reset leaves the cache alone, 5.3: its valid bits have their
		// power-up values from their initial blocks)
		inv_busy <= 1'b0; inv_hold <= 1'b0; inv_ph <= 1'b0; inv_i <= '0;
		inv_sn <= 1'b0; inv_scope <= 2'd3; inv_pa <= '0; inv_lbh <= 1'b0;
		inv_rst <= 1'b0;
		inv_x   <= 1'b0;
		sn_ihit <= 1'b0;
		ic_inv_done <= 1'b0;
		sn_inv_done <= 1'b0;
		xi_inv_done <= 1'b0;
		for (int i = 0; i < QN; i++) qw[i] <= '0;
		qh  <= '0;
		qp0 <= '0;
	end
	else begin
		logic [4:0] keep;
		c_we        <= 1'b0;
		ic_inv_done <= 1'b0;
		sn_inv_done <= 1'b0;
		xi_inv_done <= 1'b0;
		sn_ihit     <= 1'b0;
		inv_hold    <= 1'b0;

		//------------------------------------------------------------------
		// queue: shift out what D1 consumed, append F3; F2 -> F3
		//------------------------------------------------------------------
		keep = cnt - {2'b00, consume};
		for (int i = 0; i < QN; i++) begin
			logic [5:0] src;
			logic [4:0] k;
			src = 6'(i) + {3'b000, consume};
			k   = 5'(i) - keep;
			if (5'(i) < keep) begin
				// synthesis translate_off
				qps[i] <= qps[src[4:0]];
				// synthesis translate_on
				qw[i] <= qw[src[4:0]];
				qf[i] <= qf[src[4:0]];
				qd[i] <= qd[src[4:0]];
				qa[i] <= qa[src[4:0]];
				qb[i] <= qb[src[4:0]];
			end
			else if (k < {3'b000, f3_n}) begin
				// synthesis translate_off
				qps[i] <= f3_p[k[0]];
				// synthesis translate_on
				qw[i] <= f3_w[k[0]];
				qf[i] <= f3_f;
				qd[i] <= f3_d;
				qa[i] <= f3_a;
				qb[i] <= f3_b[k[0]];
			end
		end
		cnt   <= keep + {3'b000, f3_n};
		// the predecode ring: appended at head + count (wherever D1's
		// consume puts the head), the head moved by consume
		begin
			// (one write statement per bank, the word by the slot's parity:
			// two statements read as two write ports and keep it in logic)
			logic [3:0] w0, w1;
			logic       we_e, we_o;
			w0 = qwrap(5'(qh) + cnt);
			w1 = qwrap(5'(qh) + cnt + 5'd1);
			we_e = (f3_n != 2'd0 && !w0[0]) || (f3_n == 2'd2 && !w1[0]);
			we_o = (f3_n != 2'd0 &&  w0[0]) || (f3_n == 2'd2 &&  w1[0]);
			if (we_e) qpr_e[w0[0] ? w1[3:1] : w0[3:1]] <= w0[0] ? f3_p[1] : f3_p[0];
			if (we_o) qpr_o[w0[0] ? w0[3:1] : w1[3:1]] <= w0[0] ? f3_p[0] : f3_p[1];
			qh  <= qh_n;
			qp0 <= pd0_n;
		end
		// D1 consumed the end of a BTB-taken branch: the stream continues
		// at its target (the words after it in the queue came from there)
		begin
			logic        cfl;
			logic  [2:0] cj;
			logic [30:0] tqn [4];
			logic  [2:0] n;
			cfl = 1'b0; cj = 3'd0;
			for (int i = 6; i >= 0; i--)
				if (3'(i) < consume && qb[i]) begin cfl = 1'b1; cj = 3'(i); end
			// (a decode that ran past the flag is refetched at WB: the PC
			// of what follows it does not matter)
			qpc_r <= cfl ? {tq[0], 1'b0} : qpc_r + {28'd0, consume, 1'b0};
			for (int i = 0; i < 4; i++) tqn[i] = tq[i];
			n = tq_n;
			if (cfl && n != 3'd0) begin
				for (int i = 0; i < 3; i++) tqn[i] = tqn[i + 1];
				n = n - 3'd1;
			end
			if (f3_n != 2'd0 && f3_b != 2'b00 && n != 3'd4) begin
				tqn[n[1:0]] = f3_t;
				n = n + 3'd1;
			end
			for (int i = 0; i < 4; i++) tq[i] <= tqn[i];
			tq_n <= n;
		end
		f3_n  <= f2_n;
		f3_f  <= f2_f; f3_d <= f2_d; f3_a <= f2_a;
		f3_b  <= f2_b; f3_t <= f2_t;
		for (int i = 0; i < 2; i++) f3_w[i] <= f2_w[i];
		f2_n  <= '0;
		f2_b  <= '0;

		//------------------------------------------------------------------
		// F0 -> F1
		//------------------------------------------------------------------
		f1_v  <= 1'b0;
		f1_btok <= 1'b0;
		if (f0_go) begin
			f1_v   <= 1'b1;
			f1_btok <= bt_room;
			f1_pc  <= fpc;
			f1_s   <= smode;
			f1_tt0 <= ttr_hit(itt0, fpc, smode);
			f1_tt1 <= ttr_hit(itt1, fpc, smode);
			f1_tce <= tc_e;
			f1_dem <= fnew;
			f1_hit <= atc_hit;
			f1_e   <= atc_e;
			fnew   <= 1'b0;
			fpc    <= {fpc[31:2], 2'b00} + 32'd4;
		end

		//------------------------------------------------------------------
		// F1: a hit goes to F2; anything else to the miss engine, and F0
		// rolls back to the missed address
		//------------------------------------------------------------------
		if (f1_deliver) begin
			f2_n    <= f1_pc[1] ? 2'd1 : 2'd2;
			f2_w[0] <= f1_pc[1] ? x_chunk[15:0] : x_chunk[31:16];
			f2_w[1] <= x_chunk[15:0];
			f2_f <= 1'b0; f2_d <= 1'b0; f2_a <= 1'b0;
			if (f1_bt && !(f1_bkind == 2'd2 && fras_n == 4'd0)) begin
				// a predicted taken branch ends in this chunk: the words up
				// to its last, that one flagged; F0 goes to the target (a
				// return's from the stack) and its sequential fetch of this
				// cycle is dropped; a call pushes its return address
				logic [30:0] t;
				t = (f1_bkind == 2'd2) ? fras[fras_tp] : f1_btgt;
				f2_n <= (f1_pc[1] || !f1_bslot) ? 2'd1 : 2'd2;
				f2_b <= (f1_pc[1] || !f1_bslot) ? 2'b01 : 2'b10;
				f2_t <= t;
				f1_v <= 1'b0;
				f1_btok <= 1'b0;
				fpc  <= {t, 1'b0};
				fnew <= 1'b0;
				if (f1_bkind == 2'd1) begin
					frw  = 1'b1;
					frwa = fras_tp + 3'd1;
					frwd = {f1_pc[31:2], f1_bslot} + 31'd1;
					fras_tp <= fras_tp + 3'd1;
					if (fras_n != 4'd8) fras_n <= fras_n + 4'd1;
				end
				else if (f1_bkind == 2'd2) begin
					fras_tp <= fras_tp - 3'd1;
					fras_n  <= fras_n - 4'd1;
				end
			end
		end
		else if (f1_go) begin
			f1_v   <= 1'b0;
			fpc    <= f1_pc;
			fnew   <= f1_dem;
			m_la   <= f1_pc;
			m_pa   <= x_pa;
			m_upa  <= x_upa;
			m_s    <= f1_s;
			m_dem  <= f1_dem;
			m_ci   <= x_cm[1];
			if (x_walk) begin
				st     <= S_WALK;
				iw_req <= 1'b1;
			end
			else if (x_flt) begin
				// ATC fault: the long word's words carry it
				f2_n <= f1_pc[1] ? 2'd1 : 2'd2;
				for (int i = 0; i < 2; i++) f2_w[i] <= 16'd0;
				f2_f <= 1'b1; f2_d <= f1_dem; f2_a <= 1'b1;
				st   <= S_HALT;
			end
			else if (x_cach) begin
				logic [3:0] vv;
				vv = ivf_q;
				st      <= S_FILL;
				m_got   <= 4'd0;
				m_alloc <= 1'b1;
				m_tci   <= 1'b0;
				m_way   <= !vv[0] ? 2'd0 : !vv[1] ? 2'd1 : !vv[2] ? 2'd2 : !vv[3] ? 2'd3 : rr;
				m_vclr  <= 1'b1;
				m_rrinc <= (vv == 4'hF);
				b_req_r <= 1'b1;
			end
			else begin
				st      <= S_CI;
				b_req_r <= 1'b1;
			end
		end

		//------------------------------------------------------------------
		// miss engine
		//------------------------------------------------------------------
		if (b_gnt) begin
			b_req_r <= 1'b0;
			busy    <= 1'b1;
		end
		case (st)
		S_WALK:
			if (iw_done) begin
				iw_req <= 1'b0;
				st     <= S_RUN;
			end
		S_FILL: begin
			logic [31:0] lw0;
			// the long word being fetched: arriving now, or kept
			lw0 = (b_rvalid && b_rbeat == m_pa[3:2]) ? b_rdata : m_cw;
			// (the fill's first cycle: no beat has arrived yet) the victim
			// invalid, its tag the new line's
			if (m_vclr && !inv_busy) begin
				m_vclr  <= 1'b0;
				iw_set = m_pa[9:4]; iw_m[m_way] = 1'b1; iw_v = 1'b0;
				c_we    <= 1'b1;
				c_waddr <= m_pa[9:4];
				c_wway  <= m_way;
				c_wtag  <= m_pa[31:10];
			end
			// (a beat before the victim is invalid is not written: the
			// line is not allocated then)
			if (b_rvalid && m_vclr) m_alloc <= 1'b0;
			if (b_rvalid) begin
				if (b_rbeat == m_pa[3:2]) m_cw <= b_rdata;
				m_got[b_rbeat] <= 1'b1;
				if (b_rtci) begin m_alloc <= 1'b0; m_tci <= 1'b1; end
			end
			if (busy && b_done) begin
				busy  <= 1'b0;
				stale <= 1'b0;
				if (m_alloc && !(b_rvalid && b_rtci)) begin
					iw_set = m_pa[9:4]; iw_m[m_way] = 1'b1; iw_v = 1'b1;
					if (m_rrinc) rr <= rr + 2'd1;
				end
				st    <= S_RUN;
				if (m_tci || (b_rvalid && b_rtci)) begin
					// a TCI line is not kept (5.7.1: sequential access only
					// until the burst's last long word arrives): the long word
					// being fetched goes straight to the decoder, the next one
					// is fetched anew (unless a redirect takes the stream)
					if (!stale && !redir_any) begin
						logic [31:0] lw, nla;
						lw  = lw0;
						nla = {m_la[31:2], 2'b00} + 32'd4;
						if (m_la[1]) begin
							f2_n    <= 2'd1;
							f2_w[0] <= lw[15:0];
						end
						else begin
							f2_n    <= 2'd2;
							f2_w[0] <= lw[31:16];
							f2_w[1] <= lw[15:0];
						end
						f2_f  <= 1'b0; f2_d <= 1'b0; f2_a <= 1'b0;
						m_la  <= nla;
						m_pa  <= {m_pa[31:2], 2'b00} + 32'd4;
						m_dem <= 1'b0;
						fpc   <= nla;
						fnew  <= 1'b0;
					end
				end
			end
			if (busy && b_err) begin
				busy  <= 1'b0;
				stale <= 1'b0;
				if (stale) st <= S_RUN;
				else if (m_got[m_pa[3:2]]) begin
					// a later beat failed, the long word being fetched had
					// arrived (the burst starts with it): it is used, the line
					// is not allocated, and no exception (MC68060UM 7.9.1,
					// 5.7.1).  The next long word is fetched anew.
					logic [31:0] lw, nla;
					lw  = lw0;
					nla = {m_la[31:2], 2'b00} + 32'd4;
					if (m_la[1]) begin
						f2_n    <= 2'd1;
						f2_w[0] <= lw[15:0];
					end
					else begin
						f2_n    <= 2'd2;
						f2_w[0] <= lw[31:16];
						f2_w[1] <= lw[15:0];
					end
					f2_f  <= 1'b0; f2_d <= 1'b0; f2_a <= 1'b0;
					m_la  <= nla;
					m_pa  <= {m_pa[31:2], 2'b00} + 32'd4;
					m_dem <= 1'b0;
					fpc   <= nla;
					fnew  <= 1'b0;
					st    <= S_RUN;
				end
				else begin
					f2_n <= m_la[1] ? 2'd1 : 2'd2;
					for (int i = 0; i < 2; i++) f2_w[i] <= 16'd0;
					f2_f <= 1'b1; f2_d <= m_dem; f2_a <= 1'b0;
					st   <= S_HALT;
				end
			end
		end
		S_CI: begin
			if (busy && b_rvalid && !stale) begin
				if (m_la[1]) begin
					f2_n    <= 2'd1;
					f2_w[0] <= b_rdata[15:0];
				end
				else begin
					f2_n    <= 2'd2;
					f2_w[0] <= b_rdata[31:16];
					f2_w[1] <= b_rdata[15:0];
				end
				f2_f <= 1'b0; f2_d <= 1'b0; f2_a <= 1'b0;
			end
			if (busy && b_done) begin
				logic [31:0] nla;
				nla   = {m_la[31:2], 2'b00} + 32'd4;
				busy  <= 1'b0;
				stale <= 1'b0;
				if (stale) st <= S_RUN;
				else begin
					m_la  <= nla;
					m_pa  <= {m_pa[31:2], 2'b00} + 32'd4;
					m_dem <= 1'b0;
					fpc   <= nla;
					fnew  <= 1'b0;
					// the page ends (or the cache mode changed): translate again
					if (nla[11:0] == 12'd0 || (!m_ci && ic_en)) st <= S_RUN;
				end
			end
			else if (busy && b_err) begin
				busy  <= 1'b0;
				stale <= 1'b0;
				if (!stale) begin
					f2_n    <= m_la[1] ? 2'd1 : 2'd2;
					f2_w[0] <= 16'd0;
					f2_w[1] <= 16'd0;
					f2_f <= 1'b1; f2_d <= m_dem; f2_a <= 1'b0;
					st   <= S_HALT;
				end
				else st <= S_RUN;
			end
			else if (!busy && !b_req_r && !b_gnt && !redir_any && !stop &&
			         {1'b0, cnt} + {4'd0, f2_n} + {4'd0, f3_n} <= 6'(QN - 2))
				b_req_r <= 1'b1;        // the next long word of the stream
		end
		default: ;
		endcase

		//------------------------------------------------------------------
		// redirect: empty the queue and the pipeline.  A walk runs to its
		// end (the entry is installed); a line fill completes and is
		// installed; a cache-inhibited read completes and is discarded.
		//------------------------------------------------------------------
		if (redir_any) begin
			cnt   <= '0;
			f2_n  <= '0;
			f3_n  <= '0;
			f2_b  <= '0;
			f3_b  <= '0;
			tq_n  <= '0;
			f1_v  <= 1'b0;
			f1_btok <= 1'b0;
			frw  = 1'b1;
			frwa = d_ras_tp;
			frwd = d_ras;
			fras_tp <= d_ras_tp;
			fras_n  <= d_ras_n;
			fpc   <= {redir_npc[31:1], 1'b0};
			qpc_r <= redir_npc;
			odd   <= redir_npc[0];
			fnew  <= 1'b1;
			if (st == S_FILL || st == S_CI) begin
				if (out_next) stale <= 1'b1;
				else st <= S_RUN;
			end
			if (st == S_HALT) st <= S_RUN;
		end

		//------------------------------------------------------------------
		// CINV/CPUSH of the instruction cache
		//------------------------------------------------------------------
		if ((ic_inv || sn_inv || xi_inv) && !inv_busy && !inv_hold && st != S_FILL && !c_we) begin
			inv_sn    <= !ic_inv;
			inv_x     <= !ic_inv && !sn_inv;
			inv_scope <= ic_inv ? ic_inv_scope : 2'd1;
			inv_pa    <= ic_inv ? ic_inv_pa : sn_inv ? sn_inv_pa : xi_inv_pa;
			inv_lbh   <= 1'b0;
			if (ic_inv ? (ic_inv_scope == 2'd3) : sn_inv ? sn_inv_all : xi_inv_all) begin
				// every line: the sweep below (scope 3 matches every way)
				inv_scope <= 2'd3;
				sn_ihit   <= !ic_inv;
				inv_busy  <= 1'b1;
				inv_ph    <= 1'b0;
				inv_i     <= 7'd0;
			end
			else begin
				inv_busy <= 1'b1;
				inv_ph   <= 1'b0;
				inv_i    <= (!ic_inv || ic_inv_scope == 2'd1) ?
				            {1'b0, (ic_inv ? ic_inv_pa[9:4] : sn_inv ? sn_inv_pa[9:4] : xi_inv_pa[9:4])} : 7'd0;
			end
		end
		if (inv_busy) begin
			// this cycle reads set inv_i; the previous set's tags compare
			if (inv_ph) begin
				logic [5:0] s;
				s = (inv_scope == 2'd1) ? inv_pa[9:4] : 6'(inv_i - 7'd1);
				for (int w = 0; w < 4; w++) begin
					logic m;
					if (inv_scope == 2'd3)
						m = 1'b1;
					else if (inv_scope == 2'd1)
						m = ct[w][21:0] == inv_pa[31:10];
					else if (tc_p)
						m = ct[w][21:3] == inv_pa[31:13];
					else
						m = ct[w][21:2] == inv_pa[31:12];
					if (m) begin iw_set = s; iw_m[w] = 1'b1; iw_v = 1'b0; end
					if (m && ivo_q[w] && inv_sn) sn_ihit <= 1'b1;   // (ivo_ra: s)
				end
				if (inv_sn && inv_lbh) sn_ihit <= 1'b1;
			end
			inv_ph <= 1'b1;
			if (inv_scope == 2'd1) begin
				if (inv_ph) begin
					inv_busy    <= 1'b0;
					ic_inv_done <= !inv_sn;
					sn_inv_done <= inv_sn && !inv_x;
					xi_inv_done <= inv_sn && inv_x;
					inv_hold    <= 1'b1;
				end
			end
			else begin
				inv_i <= inv_i + 7'd1;
				if (inv_i == 7'd64) begin
					inv_busy    <= 1'b0;
					ic_inv_done <= !inv_sn && !inv_rst;
					sn_inv_done <= inv_sn && !inv_x;
					xi_inv_done <= inv_sn && inv_x;
					inv_hold    <= 1'b1;
					inv_rst     <= 1'b0;
				end
			end
		end
	end
	// the return stack's one write port
	if (nreset && frw) fras[frwa] <= frwd;
	// the valid RAMs' one write (both copies)
	if (nreset) begin
		if (iw_m != 4'd0) begin
			ivf[iw_set] <= (ivo_q & ~iw_m) | (iw_m & {4{iw_v}});
			ivo[iw_set] <= (ivo_q & ~iw_m) | (iw_m & {4{iw_v}});
		end
		// synthesis translate_off
		for (int j = 0; j < 4; j++) if (iw_m[j]) iv[iw_set][j] <= iw_v;
		if (iw_m != 4'd0 && iw_set != ivo_ra) begin
			$display("FAIL: fetch: a valid write at set %0d, the second copy read at %0d", iw_set, ivo_ra);
			$finish;
		end
		// synthesis translate_on
	end
end

// the valid copies' reads: F1's set; the invalidation's, else the fill's
wire [5:0] inv_s = (inv_scope == 2'd1) ? inv_pa[9:4] : 6'(inv_i - 7'd1);
always_comb ivo_ra = inv_busy ? inv_s : m_pa[9:4];
assign ivf_q = ivf[f1_pc[9:4]];
assign ivo_q = ivo[ivo_ra];
initial for (int i = 0; i < 64; i++) begin ivf[i] = 4'd0; ivo[i] = 4'd0; end
// synthesis translate_off
always_ff @(posedge clk)
	if (nreset && !inv_rst && (ivf_q != iv[f1_pc[9:4]] || ivo_q != iv[ivo_ra])) begin
		$display("FAIL: fetch: valid RAM %b/%b, model %b/%b", ivf_q, ivo_q, iv[f1_pc[9:4]], iv[ivo_ra]);
		$finish;
	end
// synthesis translate_on

// synthesis translate_off
always_ff @(posedge clk)
	if (nreset && cnt != 5'd0 && qp0 != qps[0]) begin
		$display("FAIL: fetch: the predecode ring's head %h, the queue's %h", qp0, qps[0]);
		$finish;
	end
// synthesis translate_on

endmodule
// ---- ap68040_fpif.sv ----
//--------------------------------------------------------------------------//
// AP68040 - pipelined MC68040                                               //
//                                                                          //
// ap68040_fpif.sv - the FPU at the EX stage                                //
//                                                                          //
// Wraps the floating point unit (ap040_fpu: registers, conversion,        //
// arithmetic, FSAVE state) for the pipeline.  Microcode moves the data    //
// (memory, Dn, FMOVEM, frames); the OP_FPU uops below run the FPU side in //
// EX, in program order, and act only once they are the oldest uop in     //
// flight (WB empty), so no FPU side effect is ever taken back by an older //
// exception.  Sub-operation in uop.cond:                                  //
//                                                                          //
//   CHK   first uop of every FPU instruction (A = extension word, B =     //
//         operation word): waits for a background operation, delivers a  //
//         pending arithmetic exception (pre-instruction: format $0, PC =  //
//         this instruction), latches the words, raises the encoding       //
//         faults (F-line, illegal, unimplemented EA) before any side      //
//         effect, and records FPIAR where the 68040 does                  //
//   EAL   latches the operand address (for later exception frames)        //
//   DISP  the FPU operation: FPm/<ea>/Dn to FPn, FMOVECR, FPn to <ea>;    //
//         A, B and the latch carry the operand's long words               //
//   GET   long word 1 or 2 (imm) of a store result or an FMOVEM register //
//   END   last uop of a store, FMOVEM, FSAVE or FRESTORE: raises a store  //
//         exception after the stores, acknowledges FSAVE, applies         //
//         FRESTORE                                                        //
//   CRR   CRW   control register slot read / write (imm / immb: 0 FPCR,  //
//         1 FPSR, 2 FPIAR; a slot not in the list does nothing)           //
//   LIST  FMOVEM: latches the register list (static, or Dn = A);          //
//         result: the signed byte adjustment of (An)+ / -(An)             //
//   MVR   MVW   FMOVEM: raw register read / write of the next slot        //
//   COND  FBcc / FScc / FTRAPcc;  DBCC  FDBcc (B = Dn)                     //
//   SV0   SVW   FSAVE: frame size (signed for -(An)) / frame word imm/4   //
//   RS0   RSW   FRESTORE: header check, frame size / frame word immb/4    //
//                                                                          //
// FMOVE/FADD/FSUB/FMUL on ordinary operands go into the FPU's pipeline,  //
// done at issue (one may follow every cycle); every other uop that reads  //
// or writes FPU state waits until the pipeline is empty (pbusy).         //
// Register-destination arithmetic past every datatype check is released  //
// to the background (as the 68040 runs its FPU beside the integer unit); //
// an enabled exception of a released operation becomes pending and is    //
// taken at the next FPU instruction.  The rules follow the previous       //
// core's corpus-validated FPU sequencing (WinUAE fpp.cpp).                 //
//--------------------------------------------------------------------------//

module ap68040_fpif
	import ap68040_pkg::*;
#(
	parameter logic [7:0] FPU_REVISION = 8'h41,
	parameter bit         FPU_PIPE     = 1
)(
	input  logic        clk,
	input  logic        nreset,

	// the uop in EX
	input  logic        ex_v,           // an OP_FPU uop is in EX
	input  logic  [3:0] sub,
	input  logic        fuse,           // CHK: dispatch in the same uop (FPm to FPn)
	input  logic        eal,            // CHK: latch the EA as well (EAL in the same uop)
	input  logic  [7:0] imm,            // operand A constant
	input  logic  [7:0] immb,           // operand B constant
	input  logic [31:0] av,
	input  logic [31:0] bv,
	input  logic [15:0] aw,             // av, bv without the memory operand
	input  logic [15:0] bw,             // (CHK's words: registers, no mux)
	input  logic [15:0] dw_a,           // the same words of the uop entering
	input  logic [15:0] dw_b,           // EX (DC2's), and EX not holding
	input  logic        dw_ld,          // (DC2 moving on or EX emptying: the
	                                    // decode is of the uop EX has next)
	input  logic [31:0] latch,
	input  logic [31:0] ea,             // the uop's EA (EAL)
	input  logic [31:0] pc,
	input  logic        safe,           // no older uop is in flight
	input  logic        adv,            // the uop leaves EX this cycle
	input  logic        kill,

	output logic        hold,
	output logic [31:0] res,
	output logic        dkill,          // no register write
	output logic        taken,          // FBcc / FDBcc
	output logic  [7:0] xvec,           // exception, 0 none
	output logic  [3:0] xfmt,
	output logic        xnext,          // stacked PC: the next instruction
	output logic [31:0] xaddr,          // frame address field
	output logic        xcommit,        // the uop's address updates stand
	output logic        st_kill,        // stores of this instruction suppressed

	// dynamic cancels at AG
	output logic  [7:0] mv_slots,       // FMOVEM slots that hold a register
	output logic  [2:0] cr_slots,       // FMOVEM control slots FPCR FPSR FPIAR
	output logic  [4:0] sv_words,       // FSAVE frame long words
	output logic  [4:0] rs_words        // FRESTORE frame long words
);

localparam logic [3:0] FC_CHK = 4'd0, FC_DISP = 4'd1, FC_GET = 4'd2, FC_END = 4'd3,
                       FC_CRR = 4'd4, FC_CRW = 4'd5, FC_LIST = 4'd6, FC_MVR = 4'd7,
                       FC_MVW = 4'd8, FC_COND = 4'd9, FC_DBCC = 4'd10, FC_SV0 = 4'd11,
                       FC_SVW = 4'd12, FC_RS0 = 4'd13, FC_RSW = 4'd14, FC_EAL = 4'd15;

localparam logic [7:0] VEC_ILL = 8'd4, VEC_TRAPCC = 8'd7, VEC_FLINE = 8'd11,
                       VEC_FMTERR = 8'd14, VEC_BSUN = 8'd48, VEC_OPERR = 8'd52,
                       VEC_SNAN = 8'd54, VEC_UNSUP = 8'd55;

localparam bit          REV40       = (FPU_REVISION == 8'h40);
localparam logic [31:0] IDLE_HDR    = {FPU_REVISION, 24'd0};
localparam logic [31:0] UNIMP_HDR   = {FPU_REVISION, REV40 ? 8'h28 : 8'h30, 16'd0};
localparam logic [31:0] BUSY_HDR    = {FPU_REVISION, 8'h60, 16'd0};
localparam logic [4:0]  UNIMP_WORDS = REV40 ? 5'd11 : 5'd13;

//--------------------------------------------------------------------------
// helpers
//--------------------------------------------------------------------------
function automatic logic [3:0] fp_bytes(input logic [2:0] f);
	case (f)
		3'd0, 3'd1: fp_bytes = 4'd4;
		3'd4:       fp_bytes = 4'd2;
		3'd6:       fp_bytes = 4'd1;
		3'd5:       fp_bytes = 4'd8;
		default:    fp_bytes = 4'd12;
	endcase
endfunction

// a memory operand the FPU pipeline takes (ap040_fpu q_n): an integer, or
// a zero or normalized single/double/extended with an unbiased exponent
// within +-60 (formed here, as the operand is registered, so the FPU's
// dispatch starts from a register)
function automatic logic nice_mem(input logic [95:0] d, input logic [2:0] f);
	case (f)
		3'd0, 3'd4, 3'd6: nice_mem = 1'b1;
		3'd1: nice_mem = (d[94:64] == 31'd0) || (d[94:87] >= 8'd67 && d[94:87] <= 8'd187);
		3'd5: nice_mem = (d[94:32] == 63'd0) || (d[94:84] >= 11'd963 && d[94:84] <= 11'd1083);
		3'd2: nice_mem = (d[63:0] == 64'd0) ? (d[94:80] != 15'h7FFF)
		                 : (d[63] && d[94:80] >= 15'd16323 && d[94:80] <= 15'd16443);
		default: nice_mem = 1'b0;
	endcase
endfunction

// WinUAE fault_if_nonexisting_opmode: 1 = F-line (format $0, no side
// effects), 2 = opmodes $78-$7F, which the 68040 reports as illegal
function automatic logic [1:0] opmode_class(input logic [6:0] op);
	case (op)
		7'h05, 7'h07, 7'h0B, 7'h13, 7'h17, 7'h1B,
		7'h29, 7'h2A, 7'h2B, 7'h2C, 7'h2D, 7'h2E, 7'h2F,
		7'h39, 7'h3B, 7'h3C, 7'h3D, 7'h3E, 7'h3F,
		7'h42, 7'h43, 7'h46, 7'h47,
		7'h48, 7'h49, 7'h4A, 7'h4B, 7'h4C, 7'h4D, 7'h4E, 7'h4F,
		7'h50, 7'h51, 7'h52, 7'h53, 7'h54, 7'h55, 7'h56, 7'h57,
		7'h59, 7'h5B, 7'h5D, 7'h5F,
		7'h61, 7'h65, 7'h69, 7'h6A, 7'h6B, 7'h6D, 7'h6E, 7'h6F,
		7'h70, 7'h71, 7'h72, 7'h73, 7'h74, 7'h75, 7'h76, 7'h77:
			opmode_class = 2'd1;
		7'h78, 7'h79, 7'h7A, 7'h7B, 7'h7C, 7'h7D, 7'h7E, 7'h7F:
			opmode_class = 2'd2;
		default:
			opmode_class = 2'd0;
	endcase
endfunction

// the opmodes the 68040 executes in hardware (the others: the FPSP)
function automatic logic op_in_hw(input logic [6:0] op);
	case (op)
		7'h00, 7'h40, 7'h44, 7'h18, 7'h58, 7'h5C, 7'h1A, 7'h5A, 7'h5E,
		7'h38, 7'h3A, 7'h22, 7'h62, 7'h66, 7'h28, 7'h68, 7'h6C,
		7'h23, 7'h27, 7'h63, 7'h67, 7'h20, 7'h24, 7'h60, 7'h64,
		7'h04, 7'h41, 7'h45:
			op_in_hw = 1'b1;
		default:
			op_in_hw = 1'b0;
	endcase
endfunction

// IEEE predicate over the FPSR condition codes {N, Z, I, NAN}
function automatic logic fp_cond(input logic [5:0] pred, input logic [3:0] cc);
	logic n, z, nan;
	n = cc[3]; z = cc[2]; nan = cc[0];
	case (pred[3:0])
		4'h0: fp_cond = 1'b0;
		4'h1: fp_cond = z;
		4'h2: fp_cond = !(nan | z | n);
		4'h3: fp_cond = z | !(nan | n);
		4'h4: fp_cond = n & !(nan | z);
		4'h5: fp_cond = z | (n & !nan);
		4'h6: fp_cond = !(nan | z);
		4'h7: fp_cond = !nan;
		4'h8: fp_cond = nan;
		4'h9: fp_cond = nan | z;
		4'hA: fp_cond = nan | !(n | z);
		4'hB: fp_cond = nan | z | !n;
		4'hC: fp_cond = nan | (n & !z);
		4'hD: fp_cond = nan | z | n;
		4'hE: fp_cond = !z;
		default: fp_cond = 1'b1;
	endcase
endfunction

// operand window: A, B, latch, left aligned by the source format
function automatic logic [95:0] din_of(input logic [2:0] f, input logic [31:0] a,
                                       input logic [31:0] b, input logic [31:0] c);
	case (f)
		3'd4:       din_of = {a[15:0], 80'd0};
		3'd6:       din_of = {a[7:0], 88'd0};
		3'd5:       din_of = {a, b, 32'd0};
		3'd2, 3'd3: din_of = {a, b, c};
		default:    din_of = {a, 64'd0};
	endcase
endfunction

//--------------------------------------------------------------------------
// the FPU
//--------------------------------------------------------------------------
logic        f_req, f_crwe, f_iawe, f_bsun, f_fmwe, f_rst;
logic        f_fsave_ack, f_rest_idle, f_rest_unimp, f_pendcap;
logic  [2:0] f_class, f_fmt, f_srcr, f_dstr, f_fmsel;
logic  [7:0] f_okvn;          // the FPU's register-ready flags, next cycle
logic        f_aok, f_bok;    // ... of the next source and destination
logic  [6:0] f_opm;
// (f_din also carries FMOVEM's register data: an operation's instruction
// waits until the FPU has taken its operand, so FMOVEM's writes come later)
logic [95:0] f_din;
logic        f_dnice;          // f_din is an ordinary operand (the FPU pipeline)
logic  [1:0] f_crsel;
logic [31:0] f_crwd, f_iapc;
logic        f_done, f_accepted, f_unimp, f_unsupp, f_excreq, f_used, f_wbok;
logic        f_pbusy;          // pipelined operations in flight
logic        f_pdone;          // the request went into the pipeline (this cycle)
// the released operation ends cleanly: done, or its F_WB without an
// enabled exception (a cycle sooner)
wire         f_end = (f_done || f_wbok) && !f_excreq;
logic        fresh;            // a fused CHK's request went out last cycle
logic  [7:0] f_excvec, f_curvec;
logic [95:0] f_dout, f_fmrd;
logic  [3:0] f_cc;
logic [31:0] f_crrd;
logic        f_bsun_en;
logic        s_unimp, s_busy, s_wbte15, s_e1pend, s_resume;
logic [15:0] s_cmd1, s_cmd3;
logic  [2:0] s_stag, s_dtag, s_flags, s_grs;
logic [95:0] s_fpt, s_et, s_wbt;
logic [31:0] s_fpiarc;
// FRESTORE: the frame's words go to the FPU's frame registers as they are
// read (f_rwe/f_rwf/f_rwd); the resume decision's few bits stay here
logic        f_rwe;
logic  [3:0] f_rwf;
logic [31:0] f_rwd;
logic  [7:0] r_cusavepc;
logic        r_et15, r_fpt15, r_busy;

// (declared before their use: Vivado 2018.3 makes a separate implicit net of a
// signal an instance is connected to ahead of its declaration)
logic [2:0] n_srcr, n_dstr, n_class, n_fmt;
logic [6:0] n_opm;
ap040_fpu #(.PIPE(FPU_PIPE)) fpu (
	.clk(clk), .nreset(nreset), .ce(1'b1),
	.req(f_req), .op_class(f_class), .opmode(f_opm), .wb_ok(f_wbok),
	.src_fmt(f_fmt), .src_r(f_srcr), .dst_r(f_dstr),
	.din(f_din), .din_nice(f_dnice), .done(f_done), .accepted(f_accepted),
	.unimp(f_unimp), .unsupp(f_unsupp),
	.exc_req(f_excreq), .exc_vec(f_excvec), .dout(f_dout),
	.fpcc(f_cc),
	.cr_sel(f_crsel), .cr_we(f_crwe), .cr_wdata(f_crwd), .cr_rdata(f_crrd),
	.bsun_req(f_bsun), .bsun_enable(f_bsun_en),
	.ia_we(f_iawe), .ia_wdata(f_iapc),
	.fm_sel(f_fmsel), .fm_we(f_fmwe), .fm_wdata(f_din), .fm_rdata(f_fmrd),
	.fpu_used(f_used), .pbusy(f_pbusy), .pdone(f_pdone),
	.okv_next(f_okvn), .sel_x(1'b1), .aok_x(f_aok), .bok_x(f_bok),
	.opmode_n(n_opm), .op_class_n(n_class), .src_fmt_n(n_fmt),
	.fstate_unimp(s_unimp),
	.fstate_cmd1(s_cmd1), .fstate_cmd3(s_cmd3),
	.fstate_stag(s_stag), .fstate_dtag(s_dtag), .fstate_flags(s_flags),
	.fstate_fpt(s_fpt), .fstate_et(s_et),
	.fsave_ack(f_fsave_ack), .frestore_idle(f_rest_idle), .frestore_unimp(f_rest_unimp),
	.pend_capture(f_pendcap), .cur_vec(f_curvec),
	.frestore_e1_pend(s_e1pend), .frestore_resume(s_resume),
	.frestore_cusavepc(r_cusavepc), .frestore_et15(r_et15), .frestore_fpt15(r_fpt15),
	.fstate_grs(s_grs), .fstate_wbte15(s_wbte15),
	.fstate_busy(s_busy), .fstate_wbt(s_wbt), .fstate_fpiar_c(s_fpiarc),
	.frestore_busy(r_busy),
	.frestore_we(f_rwe), .frestore_wf(f_rwf), .frestore_wd(f_rwd),
	.fp_reset(f_rst)
);

//--------------------------------------------------------------------------
// state
//--------------------------------------------------------------------------
logic [15:0] opw_q, ext_q;     // the instruction's words (latched by CHK)
logic        fsr_q;            // ... it is FSAVE or FRESTORE (for END's hold)
logic [31:0] lst_q;            // ... FMOVEM's LIST result for a static list: its
                               // bytes, negated for -(An)
logic        bg;               // a released operation is running
logic        pend;             // its enabled exception, for the next FPU instruction
logic  [7:0] pend_vec;
logic        go;               // DISP: the request is out
logic        done_q;           // DISP (store): the outcome is known
// the operation in EX ended with an enabled arithmetic exception (the
// FPU's one-cycle exc_req): it is pending for the next FPU instruction,
// as a released operation's is (MC68040UM 9.7: arithmetic exceptions are
// taken pre-instruction at the next FPU instruction; WinUAE fp_exp_pend),
// and the instruction completes
logic        fx_q;
logic [31:0] eaa;              // the operand address
logic        eav;
logic        sx_v;             // a store's exception, raised by END
logic  [7:0] sx_vec;
logic  [3:0] sx_fmt;
logic [31:0] sx_addr;
logic        sx_kill;          // the stores are suppressed
logic  [7:0] list;             // FMOVEM: the register list
logic        mv_lsb, mv_rev, mv_st, mv_m1;
logic  [2:0] slot;
logic        mvr_wait;         // MVR: the raw read port's set-up cycle
logic        crr_wait;         // CRR: the control register read's cycle
logic [95:0] get_q;            // the long words GET returns
logic  [1:0] sv_kind;          // FSAVE frame: 0 NULL, 1 IDLE, 2 UNIMP, 3 BUSY
logic  [1:0] rs_kind;          // FRESTORE frame, same codes

// the words decoded: CHK's own, else the latched ones
wire [15:0] opw = (sub == FC_CHK) ? bw : opw_q;
wire [15:0] ext = (sub == FC_CHK) ? aw : ext_q;
wire  [2:0] eam = opw[5:3];
wire  [2:0] ear = opw[2:0];
wire  [2:0] ocl = ext[15:13];
wire  [2:0] fmt = ext[12:10];
wire  [6:0] opm = ext[6:0];
wire        is_gen   = (opw[15:6] == 10'b1111_0010_00);
wire        is_cc    = (opw[15:6] == 10'b1111_0010_01);   // FScc FDBcc FTRAPcc
wire        is_bcc   = (opw[15:7] == 9'b1111_0010_1);
wire        is_fsave = (opw[15:6] == 10'b1111_0011_00);
wire        is_frest = (opw[15:6] == 10'b1111_0011_01);
wire        is_ftrap = is_cc && (eam == 3'd7) && (ear >= 3'd2) && (ear <= 3'd4);
wire        ea_dn    = (eam == 3'd0);
wire        ea_an    = (eam == 3'd1);
wire        ea_pi    = (eam == 3'd3);
wire        ea_pd    = (eam == 3'd4);
wire        ea_imm   = (eam == 3'd7) && (ear == 3'd4);
wire        ea_pcrel = (eam == 3'd7) && (ear == 3'd2 || ear == 3'd3);
wire        ea_dalt  = (eam >= 3'd2) && !(eam == 3'd7 && ear >= 3'd2);
// control registers of FMOVE(M): FPCR FPSR FPIAR; an empty list is FPIAR
wire  [2:0] crl      = (ext[12:10] == 3'd0) ? 3'b001 : ext[12:10];

//--------------------------------------------------------------------------
// CHK: the encoding faults, in the 68040's order (old core S_FPU_DEC)
//--------------------------------------------------------------------------
// (a function of the two words: CHK's are immediates, known in DC2, so the
// decode is registered as the uop enters EX -- off the hold and exception
// paths; the live decode checks it in simulation)
function automatic logic [5:0] chk_dec(input logic [15:0] ow, input logic [15:0] ew);
	logic [1:0] oc;
	logic [2:0] em, er, ol, fm, cl;
	logic       dn, an, pi, pd, im, pc, dalt, x, ill, un, ia;
	em = ow[5:3]; er = ow[2:0];
	ol = ew[15:13]; fm = ew[12:10];
	cl = (ew[12:10] == 3'd0) ? 3'b001 : ew[12:10];
	dn = (em == 3'd0); an = (em == 3'd1); pi = (em == 3'd3); pd = (em == 3'd4);
	im = (em == 3'd7) && (er == 3'd4);
	pc = (em == 3'd7) && (er == 3'd2 || er == 3'd3);
	dalt = (em >= 3'd2) && !(em == 3'd7 && er >= 3'd2);
	x = 1'b0; ill = 1'b0; un = 1'b0; ia = 1'b0;
	oc = opmode_class(ew[6:0]);
	if (ow[15:6] == 10'b1111_0010_00) case (ol)
		3'b000: begin
			if (oc == 2'd1) x = 1'b1;
			else if (oc == 2'd2) begin x = 1'b1; ill = 1'b1; end
		end
		3'b001: x = 1'b1;
		3'b010: begin
			if (fm != 3'd7 && oc == 2'd1) x = 1'b1;
			else if (fm != 3'd7 && oc == 2'd2) begin x = 1'b1; ill = 1'b1; end
			else if (fm == 3'd7) begin
				// FMOVECR: an <ea> field other than 0 is not one; F-line
				// (format $0; the M68040FPSP's x_fline.sa handles "an
				// fmovecr with a non-zero <ea> field")
				if (ow[5:0] != 6'd0) x = 1'b1;
			end
			else if (dn && fp_bytes(fm) > 4'd4) begin
				// an unimplemented Dn source format records FPIAR first;
				// a software opmode reports through the FPSP route
				x = 1'b1; ia = 1'b1;
				un = !(op_in_hw(ew[6:0]) || fm == 3'd3);
			end
			else if (an) begin
				x = 1'b1; ia = 1'b1; un = !op_in_hw(ew[6:0]);
			end
		end
		3'b011: begin
			if (dn) begin
				if (!(fm == 3'd3 || fm == 3'd7) && fp_bytes(fm) > 4'd4) x = 1'b1;
			end
			else if (!dalt) x = 1'b1;
		end
		3'b100, 3'b101: begin
			if (dn && !(cl == 3'b100 || cl == 3'b010 || cl == 3'b001)) x = 1'b1;
			else if (an && cl != 3'b001) x = 1'b1;
			else if (ew[13] && (im || pc)) x = 1'b1;
		end
		default: begin   // FMOVEM data registers
			if (em < 3'd2 || im) x = 1'b1;
			else if (ew[13] && (pi || pc)) x = 1'b1;
			else if (!ew[13] && pd) x = 1'b1;
		end
	endcase
	// with FSAVE/FRESTORE (CHK's pending rule) and the conditionals
	chk_dec = {x, ill, un, ia,
	           (ow[15:7] == 9'b1111_0011_0),
	           (ow[15:6] == 10'b1111_0010_01)};
endfunction
logic [5:0] cq;                 // chk_dec of the uop in EX (CHK's words)
always_ff @(posedge clk)
	if (!nreset) cq <= '0;
	else if (dw_ld) cq <= chk_dec(dw_b, dw_a);
wire chk_x   = cq[5];
wire chk_ill = cq[4];
wire chk_un  = cq[3];
wire chk_ia  = cq[2];
wire chk_fs  = cq[1];           // FSAVE or FRESTORE
// synthesis translate_off
always_ff @(posedge clk)
	if (nreset && ex_v && sub == FC_CHK && cq != chk_dec(bw, aw)) begin
		$display("FAIL: fpif: CHK's registered decode %b, its words decode %b", cq, chk_dec(bw, aw));
		$finish;
	end
// synthesis translate_on

// FMOVEM slot -> list bit -> register
function automatic logic [2:0] slot_bit(input logic [2:0] k, input logic lsb);
	slot_bit = lsb ? k : (3'd7 - k);
endfunction
// mv_slots: list in slot order, a register of its own (set with list and
// mv_lsb, so the same value a cycle earlier than a decode of them: it feeds
// AG's dynamic cancel, and so the register file's write enable)
wire [2:0] cur_bit = slot_bit(slot, mv_lsb);
wire [2:0] cur_reg = (!mv_st || mv_m1) ? (3'd7 - cur_bit) : cur_bit;  // loads: bit 7 = FP0
wire       cur_on  = list[cur_bit];
assign cr_slots = {crl[0], crl[1], crl[2]};       // bit 0 = FPCR slot
function automatic logic [1:0] crsel_of(input logic [1:0] k);   // the FPU's cr_sel
	crsel_of = (k == 2'd0) ? 2'd2 : (k == 2'd1) ? 2'd1 : 2'd0;
endfunction

// LIST's result from the instruction's words as CHK latches them
function automatic logic [31:0] lst_of(input logic [15:0] ow, input logic [15:0] xw);
	logic [3:0] n;
	logic [6:0] b;
	n = 4'd0;
	for (int i = 0; i < 8; i++) n = n + {3'd0, xw[i]};
	b = 7'(n) * 7'd12;
	lst_of = (ow[5:3] == 3'd4) ? -{25'd0, b} : {25'd0, b};
endfunction
// ... and for a dynamic list (Dn): from the operand, the words latched
function automatic logic [31:0] lst_dyn(input logic [15:0] ow, input logic [7:0] l);
	logic [3:0] n;
	logic [6:0] b;
	n = 4'd0;
	for (int i = 0; i < 8; i++) n = n + {3'd0, l[i]};
	b = 7'(n) * 7'd12;
	lst_dyn = (ow[5:3] == 3'd4) ? -{25'd0, b} : {25'd0, b};
endfunction
// FMOVEM list and adjustment (LIST, combinational for its result)
logic [7:0] l_now;
logic [6:0] l_bytes;
always_comb begin
	logic [3:0] n;
	l_now = ext[11] ? av[7:0] : ext[7:0];
	n = 4'd0;
	for (int i = 0; i < 8; i++) n = n + {3'd0, l_now[i]};
	l_bytes = 7'(n) * 7'd12;
end

// FSAVE frame
logic [1:0] sv_now;
always_comb begin
	if (!f_used)                sv_now = 2'd0;
	else if (s_unimp && s_busy) sv_now = 2'd3;
	else if (s_unimp)           sv_now = 2'd2;
	else                        sv_now = 2'd1;
end
function automatic logic [6:0] kbytes(input logic [1:0] k);
	kbytes = (k == 2'd3) ? 7'd100 : (k == 2'd2) ? {UNIMP_WORDS, 2'b00} : 7'd4;
endfunction
assign sv_words = (sv_kind == 2'd3) ? 5'd25 : (sv_kind == 2'd2) ? UNIMP_WORDS : 5'd1;
assign rs_words = (rs_kind == 2'd3) ? 5'd25 : (rs_kind == 2'd2) ? UNIMP_WORDS : 5'd1;
function automatic logic [1:0] rs_kind_of(input logic [31:0] h);
	rs_kind_of = (h == BUSY_HDR) ? 2'd3 : (h == UNIMP_HDR) ? 2'd2 :
	             (h[31:24] == 8'd0) ? 2'd0 : 2'd1;
endfunction
wire rs_ok = (av[31:24] == 8'd0) || (av == IDLE_HDR) || (av == UNIMP_HDR) || (av == BUSY_HDR);

function automatic logic [31:0] busy_word(input logic [4:0] n);
	case (n)
		5'd0:  busy_word = BUSY_HDR;
		5'd6:  busy_word = {s_wbt[95:80], 16'd0};
		5'd7:  busy_word = s_wbt[63:32];
		5'd8:  busy_word = s_wbt[31:0];
		5'd10: busy_word = s_fpiarc;
		5'd13: busy_word = {s_cmd3, 16'd0};
		5'd15: busy_word = {s_stag, 3'd0, s_grs, 23'd0};
		5'd16: busy_word = {s_cmd1, 16'd0};
		5'd17: busy_word = {s_dtag, 8'd0, s_wbte15, 20'd0};
		5'd18: busy_word = {5'd0, s_flags[2], s_flags[1], 4'd0, s_flags[0], 20'd0};
		5'd19: busy_word = s_fpt[95:64];
		5'd20: busy_word = s_fpt[63:32];
		5'd21: busy_word = s_fpt[31:0];
		5'd22: busy_word = s_et[95:64];
		5'd23: busy_word = s_et[63:32];
		5'd24: busy_word = s_et[31:0];
		default: busy_word = 32'd0;
	endcase
endfunction
function automatic logic [31:0] unimp_word(input logic [4:0] n0);
	logic [4:0] n;
	n = (REV40 && n0 != 5'd0) ? n0 + 5'd2 : n0;   // $40 omits words 1 and 2
	case (n)
		5'd0:  unimp_word = UNIMP_HDR;
		5'd1:  unimp_word = {s_cmd3, 16'd0};
		5'd3:  unimp_word = {s_stag, 3'd0, s_grs, 23'd0};
		5'd4:  unimp_word = {s_cmd1, 16'd0};
		5'd5:  unimp_word = {s_dtag, 8'd0, s_wbte15, 20'd0};
		5'd6:  unimp_word = {5'd0, s_flags[2], s_flags[1], 4'd0, s_flags[0], 20'd0};
		5'd7:  unimp_word = s_fpt[95:64];
		5'd8:  unimp_word = s_fpt[63:32];
		5'd9:  unimp_word = s_fpt[31:0];
		5'd10: unimp_word = s_et[95:64];
		5'd11: unimp_word = s_et[63:32];
		5'd12: unimp_word = s_et[31:0];
		default: unimp_word = 32'd0;
	endcase
endfunction

//--------------------------------------------------------------------------
// the uop in EX
//--------------------------------------------------------------------------
wire chk_pend = pend && !chk_fs;     // (CHK's) FSAVE/FRESTORE: their own rules
// uops with no FPU side effect need not wait to be the oldest: GET reads
// the latched result; END of an instruction with no store exception
// pending and not FSAVE/FRESTORE does nothing (a fault of an older uop
// discards it with the rest)
// (END's instruction is the latched one: fsr_q, not the opcode decode)
wire nosafe = (sub == FC_GET) || (sub == FC_END && !sx_v && !fsr_q);
// synthesis translate_off
always_ff @(posedge clk)
	if (nreset && ex_v && sub == FC_END && fsr_q != (is_fsave || is_frest)) begin
		$display("FAIL: fpif: fsr_q %b, the instruction's FSAVE/FRESTORE %b", fsr_q, is_fsave || is_frest);
		$finish;
	end
// synthesis translate_on

logic [31:0] res_g;            // the result as the hold logic forms it (checked, then unused)
always_comb begin
	hold    = 1'b0;
	res_g   = 32'd0;
	dkill   = 1'b0;
	taken   = 1'b0;
	xvec    = 8'd0;
	xfmt    = 4'd0;
	xnext   = 1'b0;
	xaddr   = pc;
	xcommit = 1'b0;
	st_kill = sx_kill;
	if (ex_v) begin
		if (!safe && !nosafe) hold = 1'b1;
		// FPU state (registers, FPSR, condition codes, control registers,
		// frames) is current only once the pipelined operations complete:
		// only a new operation (CHK, EAL, DISP) goes ahead of them
		else if (f_pbusy && !(sub == FC_CHK || sub == FC_EAL || sub == FC_DISP || sub == FC_GET))
			hold = 1'b1;
		else case (sub)
			FC_CHK: begin
				// the released operation completing this cycle without an
				// exception lets CHK go (one that raises one makes it pending
				// at this edge: CHK waits and delivers it)
				// the FPU sees it now: done at once if it went into the
				// pipeline (pdone: the registered done of this cycle may be
				// a released operation's, which fresh masks)
				if (fuse && go && fresh && !f_pdone) hold = 1'b1;
				else if (fuse && go) begin
					// dispatched (below): DISP's outcome
					if (f_unimp) begin
						xvec = VEC_FLINE; xfmt = 4'd2; xnext = 1'b1;
						xaddr = pc; xcommit = 1'b1;
					end
					else if (f_unsupp) begin
						xvec = VEC_UNSUP; xfmt = 4'd3; xnext = 1'b1;
						xaddr = 32'd0; xcommit = 1'b1;
					end
					else if (f_excreq || fx_q) ;   // pending: the instruction completes
					else if (!(f_accepted || f_done || f_pdone)) hold = 1'b1;
				end
				else if (bg && !f_end) hold = 1'b1;
				else if (chk_pend) begin
					xvec = pend_vec;
				end
				else if (chk_x) begin
					xvec = chk_ill ? VEC_ILL : VEC_FLINE;
					if (chk_un) begin xfmt = 4'd2; xnext = 1'b1; end
				end
				else if (fuse) hold = 1'b1;    // dispatching this cycle
			end
			FC_DISP: begin
				if (ocl == 3'b011) begin
					// a store: its outcome first; its exception comes from END
					if (!done_q) hold = 1'b1;
					if (ea_dn) begin
						case (fmt)
							3'd4:    res_g = {bv[31:16], f_dout[95:80]};
							3'd6:    res_g = {bv[31:8], f_dout[95:88]};
							default: res_g = f_dout[95:64];
						endcase
						dkill = sx_kill;
					end
					else case (fmt)
						3'd4:    res_g = {16'd0, f_dout[95:80]};
						3'd6:    res_g = {24'd0, f_dout[95:88]};
						default: res_g = f_dout[95:64];
					endcase
				end
				else if (go && f_unimp) begin
					xvec = VEC_FLINE; xfmt = 4'd2; xnext = 1'b1;
					xaddr = eav ? eaa : pc; xcommit = 1'b1;
				end
				else if (go && f_unsupp) begin
					xvec = VEC_UNSUP; xfmt = 4'd3; xnext = 1'b1;
					xaddr = eav ? eaa : 32'd0; xcommit = 1'b1;
				end
				else if (go && (f_excreq || fx_q)) ;   // pending: the instruction completes
				else if (!(go && (f_accepted || f_done || f_pdone))) hold = 1'b1;
			end
			FC_GET: res_g = (imm[1:0] == 2'd1) ? get_q[63:32] : get_q[31:0];
			FC_END: begin
				if (sx_v) begin
					xvec = sx_vec; xfmt = sx_fmt; xnext = 1'b1; xaddr = sx_addr;
					xcommit = 1'b1;
				end
			end
			FC_CRR: begin
				res_g = f_crrd;
				dkill = !cr_slots[imm[1:0]];
				if (!crr_wait) hold = 1'b1;
			end
			FC_LIST: res_g = (ea_pd) ? -{25'd0, l_bytes} : {25'd0, l_bytes};
			FC_MVR: begin
				res_g = mv_rev ? f_fmrd[31:0] : f_fmrd[95:64];
				if (!mvr_wait) hold = 1'b1;
			end
			FC_COND, FC_DBCC: begin
				logic [5:0] pred;
				logic c;
				pred = is_bcc ? opw[5:0] : ext[5:0];
				c = fp_cond(pred, f_cc);
				if (pred[4] && f_cc[0] && f_bsun_en) begin
					xvec = VEC_BSUN;
				end
				else if (sub == FC_DBCC) begin
					res_g = {bv[31:16], bv[15:0] - 16'd1};
					dkill = c;
					taken = !c && (bv[15:0] != 16'd0);
				end
				else if (is_bcc) taken = c;
				else if (is_ftrap) begin
					if (c) begin xvec = VEC_TRAPCC; xfmt = 4'd2; xnext = 1'b1; end
				end
				else res_g = {bv[31:8], {8{c}}};      // FScc
			end
			FC_SV0: begin
				if (bg) hold = 1'b1;
				else if (pend && !s_unimp) begin
					// frameless fallback: an earlier FSAVE already took the
					// pending exception's frame
					xvec = pend_vec;
				end
				res_g = ea_pd ? -{25'd0, kbytes(sv_now)} : {25'd0, kbytes(sv_now)};
			end
			FC_SVW: res_g = (sv_kind == 2'd3) ? busy_word(imm[6:2]) :
			              (sv_kind == 2'd2) ? unimp_word(imm[6:2]) :
			              (sv_kind == 2'd1) ? IDLE_HDR : 32'd0;
			FC_RS0: begin
				if (bg) hold = 1'b1;
				res_g = {25'd0, kbytes(rs_kind_of(av))};
				// an unknown frame is a format error at the FRESTORE
				if (!rs_ok) xvec = VEC_FMTERR;
			end
			default: ;
		endcase
	end
end

// the result, by the sub-operation only: EX takes it when the uop
// completes, so it need not wait for the hold's conditions (ex_v, safe,
// the pipeline): those stay off the result's path to the register file
always_comb begin
	res = 32'd0;
	case (sub)
		FC_DISP: if (ocl == 3'b011) begin
			if (ea_dn) case (fmt)
				3'd4:    res = {bv[31:16], f_dout[95:80]};
				3'd6:    res = {bv[31:8], f_dout[95:88]};
				default: res = f_dout[95:64];
			endcase
			else case (fmt)
				3'd4:    res = {16'd0, f_dout[95:80]};
				3'd6:    res = {24'd0, f_dout[95:88]};
				default: res = f_dout[95:64];
			endcase
		end
		FC_GET:  res = (imm[1:0] == 2'd1) ? get_q[63:32] : get_q[31:0];
		FC_CRR:  res = f_crrd;
		FC_LIST: res = ext_q[11] ? lst_dyn(opw_q, av[7:0]) : lst_q;
		FC_MVR:  res = mv_rev ? f_fmrd[31:0] : f_fmrd[95:64];
		FC_DBCC: res = {bv[31:16], bv[15:0] - 16'd1};
		FC_COND: res = {bv[31:8], {8{fp_cond(is_bcc ? opw[5:0] : ext[5:0], f_cc)}}};   // FScc
		FC_SV0:  res = ea_pd ? -{25'd0, kbytes(sv_now)} : {25'd0, kbytes(sv_now)};
		FC_SVW:  res = (sv_kind == 2'd3) ? busy_word(imm[6:2]) :
		               (sv_kind == 2'd2) ? unimp_word(imm[6:2]) :
		               (sv_kind == 2'd1) ? IDLE_HDR : 32'd0;
		FC_RS0:  res = {25'd0, kbytes(rs_kind_of(av))};
		default: ;
	endcase
end
// synthesis translate_off
always_ff @(posedge clk)
	if (nreset && ex_v && res_g != res && res_g != 32'd0) begin
		$display("FAIL: fpif result %h, the gated one %h (sub %0d)", res, res_g, sub);
		$finish;
	end
// synthesis translate_on

//--------------------------------------------------------------------------
// sequential
//--------------------------------------------------------------------------
wire act = ex_v && (safe || nosafe);

// the source and destination registers as they will be next cycle (CHK
// with DISP, DISP, the MVR read): the FPU's register-ready flags are
// selected by them ahead, into flip-flops (f_aok, f_bok), so its dispatch
// -- pdone, and with it the core's stall path -- starts from those
// (and the operation's class, opmode and format: the FPU registers whether
// the request can go into its pipeline from them, a cycle ahead)
always_comb begin
	n_srcr  = f_srcr;
	n_dstr  = f_dstr;
	n_class = f_class;
	n_opm   = f_opm;
	n_fmt   = f_fmt;
	if (!nreset) begin
		n_srcr = '0; n_dstr = '0; n_class = '0; n_opm = '0; n_fmt = '0;
	end
	else if (act) case (sub)
		FC_CHK: if (fuse && !go && !(bg && !f_end) && !chk_pend && !chk_x) begin
			n_srcr  = ext[12:10];
			n_dstr  = ext[9:7];
			n_class = ocl;
			n_opm   = opm;
			n_fmt   = fmt;
		end
		FC_DISP: if (!go) begin
			n_srcr  = (ocl == 3'b011) ? ext[9:7] : ext[12:10];
			n_dstr  = ext[9:7];
			n_class = ocl;
			n_opm   = opm;
			n_fmt   = fmt;
		end
		FC_MVR: if (!mvr_wait) n_srcr = cur_reg;
		default: ;
	endcase
end

always_ff @(posedge clk) begin
	if (!nreset) begin
		opw_q <= '0; ext_q <= '0; fsr_q <= 1'b0; lst_q <= '0;
		bg <= 1'b0; pend <= 1'b0; pend_vec <= '0; fresh <= 1'b0;
		go <= 1'b0; done_q <= 1'b0; fx_q <= 1'b0; eaa <= '0; eav <= 1'b0;
		sx_v <= 1'b0; sx_vec <= '0; sx_fmt <= '0; sx_addr <= '0; sx_kill <= 1'b0;
		list <= '0; mv_slots <= '0; mv_lsb <= 1'b0; mv_rev <= 1'b0; mv_st <= 1'b0; mv_m1 <= 1'b0;
		slot <= '0; mvr_wait <= 1'b0; crr_wait <= 1'b0; get_q <= '0;
		sv_kind <= '0; rs_kind <= '0;
		f_req <= 1'b0; f_crwe <= 1'b0; f_iawe <= 1'b0; f_bsun <= 1'b0; f_fmwe <= 1'b0; f_rst <= 1'b0;
		f_fsave_ack <= 1'b0; f_rest_idle <= 1'b0; f_rest_unimp <= 1'b0; f_pendcap <= 1'b0;
		f_class <= '0; f_fmt <= '0; f_srcr <= '0; f_dstr <= '0; f_fmsel <= '0; f_opm <= '0;
		f_aok <= 1'b0; f_bok <= 1'b0;
		f_din <= '0; f_dnice <= 1'b0; f_crsel <= '0; f_crwd <= '0; f_iapc <= '0;
		f_rwe <= 1'b0; f_rwf <= '0; f_rwd <= '0; r_cusavepc <= '0;
		r_et15 <= 1'b0; r_fpt15 <= 1'b0; r_busy <= 1'b0;
	end
	else begin
		f_req <= 1'b0; f_crwe <= 1'b0; f_iawe <= 1'b0; f_bsun <= 1'b0; f_fmwe <= 1'b0;
		f_rwe <= 1'b0;
		f_rst <= 1'b0; f_fsave_ack <= 1'b0; f_rest_idle <= 1'b0; f_rest_unimp <= 1'b0;
		f_pendcap <= 1'b0;
		fresh     <= 1'b0;

		// a released operation: completion, or its enabled exception
		// pending for the next FPU instruction (the FPU prepares the frame)
		if (bg && f_done) bg <= 1'b0;
		if (bg && f_excreq) begin
			bg        <= 1'b0;
			pend      <= 1'b1;
			pend_vec  <= f_excvec;
			f_pendcap <= 1'b1;
		end
		// the operation in EX (a fused CHK, or a DISP that is not a store):
		// its enabled exception likewise pends, with the frame prepared
		if (ex_v && go && !bg && f_excreq &&
		    ((sub == FC_CHK && fuse) || (sub == FC_DISP && ocl != 3'b011))) begin
			pend      <= 1'b1;
			pend_vec  <= f_excvec;
			f_pendcap <= 1'b1;
			fx_q      <= 1'b1;
		end
		if (adv || kill) fx_q <= 1'b0;

		f_srcr  <= n_srcr;
		f_dstr  <= n_dstr;
		f_class <= n_class;
		f_opm   <= n_opm;
		f_fmt   <= n_fmt;
		f_aok  <= f_okvn[n_srcr];
		f_bok  <= f_okvn[n_dstr];

		if (act) case (sub)
			FC_CHK: if (fuse && !go && !(bg && !f_end) && !chk_pend && !chk_x) begin
				// FPm to FPn: CHK's latching and DISP's request at once
				opw_q   <= opw;
				fsr_q   <= is_fsave || is_frest;
				lst_q   <= lst_of(opw, ext);
				ext_q   <= ext;
				eav     <= 1'b0;
				sx_v    <= 1'b0;
				sx_kill <= 1'b0;
				done_q  <= 1'b0;
				go      <= 1'b1;
				f_req   <= 1'b1;
				f_iawe  <= 1'b1;
				f_iapc  <= pc;
				f_din   <= din_of(fmt, av, bv, latch);
				f_dnice <= nice_mem(din_of(fmt, av, bv, latch), fmt);
				fresh   <= 1'b1;
			end
			else if (fuse && go) begin
				if (adv) begin
					go <= 1'b0;
					if (f_accepted && !f_done && !f_excreq) bg <= 1'b1;
				end
			end
			else if (adv) begin
				opw_q <= opw;
				fsr_q <= is_fsave || is_frest;
				lst_q <= lst_of(opw, ext);
				ext_q <= ext;
				// (an immediate operand has no address: its frames, EA 0)
				eav   <= eal && !ea_imm;
				if (eal) eaa <= ea;
				sx_v  <= 1'b0;
				sx_kill <= 1'b0;
				go    <= 1'b0;
				done_q <= 1'b0;
				if (chk_pend) pend <= 1'b0;
				// the encodings that fault after recording FPIAR.  The
				// conditionals (FBcc FScc FDBcc FTRAPcc) leave it alone:
				// their only exception is BSUN, and the M68040FPSP copies
				// the stacked PC to FPIAR "for MC68881/MC68882
				// compatibility" (MC68040UM 9.7.1, x_bsun.sa)
				else if (chk_x && chk_ia) begin
					f_iawe <= 1'b1;
					f_iapc <= pc;
				end
			end
			FC_EAL: begin
				// an immediate operand has no address (its frames: EA 0)
				eaa <= ea;
				eav <= !ea_imm;
			end
			FC_DISP: begin
				if (!go) begin
					go      <= 1'b1;
					f_req   <= 1'b1;
					f_iawe  <= 1'b1;
					f_iapc  <= pc;
					f_din   <= din_of(fmt, av, bv, latch);
					f_dnice <= nice_mem(din_of(fmt, av, bv, latch), fmt);
				end
				else if (ocl == 3'b011) begin
					if (f_unimp || f_unsupp || f_done) begin
						done_q <= 1'b1;
						get_q  <= f_dout;
					end
					if (f_unimp) begin
						sx_v <= 1'b1; sx_vec <= VEC_FLINE; sx_fmt <= 4'd2;
						sx_addr <= eav ? eaa : pc; sx_kill <= 1'b1;
					end
					else if (f_unsupp) begin
						sx_v <= 1'b1; sx_vec <= VEC_UNSUP; sx_fmt <= 4'd3;
						sx_addr <= ea_dn ? 32'd0 : eaa; sx_kill <= 1'b1;
					end
					else if (f_done && f_excreq) begin
						// an enabled SNAN/OPERR integer store writes nothing;
						// otherwise the destination is written, then the trap
						// (post-instruction, WinUAE fp_exception_pending(false));
						// the FPU prepares the E1/T frame the handler's FSAVE
						// takes (table 9-16, opclass 011)
						f_pendcap <= 1'b1;
						sx_v <= 1'b1; sx_vec <= f_excvec; sx_fmt <= 4'd3;
						sx_addr <= ea_dn ? 32'd0 : eaa;
						sx_kill <= (f_excvec == VEC_SNAN || f_excvec == VEC_OPERR) &&
						           (fmt == 3'd0 || fmt == 3'd4 || fmt == 3'd6);
					end
				end
				else if (adv && f_accepted && !f_done && !f_excreq) bg <= 1'b1;
			end
			FC_CRR: begin
				// the FPU reads the selected register combinationally:
				// select, then take it the next cycle
				if (adv) crr_wait <= 1'b0;
				else begin
					f_crsel  <= crsel_of(imm[1:0]);
					crr_wait <= 1'b1;
				end
			end
			FC_CRW: if (adv) begin
				f_crsel <= crsel_of(immb[1:0]);
				f_crwe  <= cr_slots[immb[1:0]];
				f_crwd  <= av;
			end
			FC_LIST: if (adv) begin
				list   <= l_now;
				for (int k = 0; k < 8; k++)
					mv_slots[k] <= l_now[slot_bit(3'(k), ext[13] && ea_pd)];
				mv_st  <= ext[13];
				mv_m1  <= ext[12];
				mv_lsb <= ext[13] && ea_pd;
				mv_rev <= ext[13] && (ext[12] == ea_pd);
				slot   <= 3'd0;
			end
			FC_MVR: begin
				if (!mvr_wait) begin
					// the raw image comes through the source-register port
					mvr_wait <= 1'b1;
				end
				else if (adv) begin
					get_q    <= mv_rev ? {f_fmrd[31:0], f_fmrd[63:32], f_fmrd[95:64]} : f_fmrd;
					mvr_wait <= 1'b0;
					slot     <= slot + 3'd1;
				end
			end
			FC_MVW: if (adv) begin
				if (cur_on) begin
					f_fmsel <= cur_reg;
					f_fmwe  <= 1'b1;
					f_din   <= {av, bv, latch};
				end
				slot <= slot + 3'd1;
			end
			FC_COND, FC_DBCC: if (adv) begin
				logic [5:0] pred;
				pred = is_bcc ? opw[5:0] : ext[5:0];
				// a signaling predicate on unordered sets BSUN
				if (pred[4] && f_cc[0]) f_bsun <= 1'b1;
			end
			FC_END: if (adv) begin
				sx_v <= 1'b0; sx_kill <= 1'b0;
				if (is_fsave) f_fsave_ack <= (sv_kind >= 2'd2);
				if (is_frest) case (rs_kind)
					2'd0: begin f_rst <= 1'b1; pend <= 1'b0; end
					2'd1: begin f_rest_idle <= 1'b1; pend <= 1'b0; end
					2'd2: begin
						// a restored arithmetic E1 frame re-arms its exception
						// for the next FPU instruction
						r_busy <= 1'b0;
						f_rest_unimp <= 1'b1;
						pend     <= s_e1pend;
						pend_vec <= f_curvec;
					end
					default: begin
						// BUSY: CU_SAVEPC $fe resumes the prepared command
						r_busy <= 1'b1;
						f_rest_unimp <= 1'b1;
						bg       <= s_resume;
						pend     <= !s_resume && s_e1pend;
						pend_vec <= f_curvec;
					end
				endcase
			end
			FC_SV0: if (adv) begin
				sv_kind <= sv_now;
				// a frame extraction consumes the pending exception; the
				// frameless fallback was taken as this uop's exception
				pend <= 1'b0;
			end
			FC_RS0: if (adv) begin
				rs_kind <= rs_kind_of(av);
				r_busy  <= (av == BUSY_HDR);
			end
			FC_RSW: if (adv) begin
				logic [4:0] k;
				logic [4:0] f;             // the field it holds (ap040_fpu's frestore_wf)
				k = immb[6:2];
				f = 5'h1F;
				if (rs_kind == 2'd3) case (k)
					5'd2:  r_cusavepc <= av[31:24];
					5'd6:  f = 5'd0;
					5'd7:  f = 5'd1;
					5'd8:  f = 5'd2;
					5'd10: f = 5'd3;
					5'd13: f = 5'd4;
					5'd15: begin f = 5'd5; r_et15 <= av[28]; end
					5'd16: f = 5'd6;
					5'd17: begin f = 5'd7; r_fpt15 <= av[28]; end
					5'd18: f = 5'd8;
					5'd19: f = 5'd9;
					5'd20: f = 5'd10;
					5'd21: f = 5'd11;
					5'd22: f = 5'd12;
					5'd23: f = 5'd13;
					5'd24: f = 5'd14;
					default: ;
				endcase
				else if (rs_kind == 2'd2) case (REV40 ? k + 5'd2 : k)
					5'd1:  f = 5'd4;
					5'd3:  f = 5'd5;
					5'd4:  f = 5'd6;
					5'd5:  f = 5'd7;
					5'd6:  f = 5'd8;
					5'd7:  f = 5'd9;
					5'd8:  f = 5'd10;
					5'd9:  f = 5'd11;
					5'd10: f = 5'd12;
					5'd11: f = 5'd13;
					5'd12: f = 5'd14;
					default: ;
				endcase
				f_rwe <= (f != 5'h1F);
				f_rwf <= f[3:0];
				f_rwd <= av;
			end
			default: ;
		endcase
		if (!(ex_v && sub == FC_CRR)) crr_wait <= 1'b0;
		// a request is done with when its uop leaves (a fused CHK may follow)
		if (act && adv && sub == FC_DISP) go <= 1'b0;
		if (kill) begin
			go <= 1'b0; mvr_wait <= 1'b0; crr_wait <= 1'b0;
		end
	end
end

endmodule
// ---- ap68040_muldiv.sv ----
//--------------------------------------------------------------------------//
// AP68040-60 - pipelined MC68040                                            //
//                                                                          //
// ap68040_muldiv.sv - iterative multiply and divide (from AP040's          //
// ap040_muldiv.v, which the cputest corpus validated)                       //
//                                                                          //
// MUL: 32x32 -> 64, signed or unsigned, one registered DSP product         //
// DIV: 64/32 -> q32,r32 restoring, DSTEPS bits per cycle; ovf when the true//
//      quotient does not fit 32 bits.  Signed quotients truncate toward    //
//      zero, the remainder takes the dividend's sign.                       //
// kill abandons a running operation (pipeline flush).                       //
//--------------------------------------------------------------------------//

module ap68040_muldiv #(
	parameter int DSTEPS = 4          // divide steps (quotient bits) per cycle: 4 or 2
) (
	input             clk,
	input             nreset,
	input             kill,

	input             start,
	input             is_div,
	input             sign_op,
	input      [31:0] op_a,        // multiplier / divisor
	input      [31:0] op_hi,       // dividend high (div only)
	input      [31:0] op_lo,       // multiplicand / dividend low

	output            busy,
	output reg        done,        // one cycle pulse
	output reg [31:0] res_hi,      // product high / remainder
	output reg [31:0] res_lo,      // product low / quotient
	output reg        ovf
);

reg        running;
reg        div_r;
reg        neg_q;                 // negate quotient / product
reg        neg_r;                 // negate remainder
reg  [6:0] count;
reg [31:0] den;                   // divisor / multiplier (absolute)
reg [31:0] mcand;                 // multiplicand (absolute)
reg [63:0] prod;                  // registered DSP product
reg [96:0] acc;

// absolute values for signed operations
wire [31:0] abs_a  = (sign_op && op_a[31]) ? (32'd0 - op_a) : op_a;
wire [63:0] dvd    = {op_hi, op_lo};
wire [63:0] abs_d  = (sign_op && op_hi[31]) ? (64'd0 - dvd) : dvd;
wire [31:0] abs_m  = (sign_op && op_lo[31]) ? (32'd0 - op_lo) : op_lo;

// divide: four cascaded restoring steps per cycle (64 bits = 16 rounds),
// each exactly one former one-bit iteration; the divisor is an explicit
// argument so the function stays pure (module-level variables read from
// inside a function are unreliable in continuous assignments under iverilog)
function [96:0] div_step;
	input [96:0] a;
	input [31:0] d;
	reg   [96:0] sh;
	reg   [33:0] t;
	begin
		sh = {a[95:0], 1'b0};
		t  = {1'b0, sh[96:64]} - {2'b00, d};
		if (!t[33]) div_step = {t[32:0], sh[63:1], 1'b1};
		else        div_step = sh;
	end
endfunction

wire [96:0] div4 = (DSTEPS == 4) ? div_step(div_step(div_step(div_step(acc, den), den), den), den)
                                 : div_step(div_step(acc, den), den);

wire [63:0] q_raw = div_r ? acc[63:0] : prod;
wire [31:0] r_raw = acc[95:64];

always @(posedge clk) begin
	if (!nreset) begin
		running <= 0;
		done    <= 0;
		div_r   <= 0;
		neg_q   <= 0;
		neg_r   <= 0;
		count   <= 0;
		den     <= 0;
		mcand   <= 0;
		prod    <= 0;
		acc     <= 0;
		res_hi  <= 0;
		res_lo  <= 0;
		ovf     <= 0;
	end
	else if (kill) begin
		running <= 1'b0;
		done    <= 1'b0;
	end
	else begin
		done <= 0;

		if (start) begin
			div_r   <= is_div;
			running <= 1;
			ovf     <= 0;
			if (is_div) begin
				den   <= abs_a;
				acc   <= {33'd0, abs_d};
				count <= 7'(64 / DSTEPS);
				neg_q <= sign_op && (op_hi[31] ^ op_a[31]);
				neg_r <= sign_op && op_hi[31];
			end
			else begin
				den   <= abs_a;
				mcand <= abs_m;
				count <= 7'd1;
				neg_q <= sign_op && (op_a[31] ^ op_lo[31]) && (op_a != 0) && (op_lo != 0);
				neg_r <= 0;
			end
		end
		else if (running) begin
			if (count != 0) begin
				count <= count - 7'd1;
				if (div_r) begin
					acc <= div4;
				end
				else begin
					// one registered 32x32 DSP-tree product, exactly the
					// value the former 32-cycle shift-add loop accumulated
					prod <= mcand * den;
				end
			end
			else begin
				running <= 1'b0;
				done    <= 1'b1;
				if (div_r) begin
					res_lo <= neg_q ? (32'd0 - q_raw[31:0]) : q_raw[31:0];
					res_hi <= neg_r ? (32'd0 - r_raw) : r_raw;
					ovf    <= (|q_raw[63:32]) |
					          (sign_op & (neg_q ? (q_raw[31:0] > 32'h8000_0000)
					                            : q_raw[31]));
				end
				else begin
					res_lo <= neg_q ? (32'd0 - q_raw[31:0]) : q_raw[31:0];
					res_hi <= neg_q ? (~q_raw[63:32] + {31'd0, (q_raw[31:0] == 32'd0)})
					                : q_raw[63:32];
					ovf    <= 0;
				end
			end
		end
	end
end

assign busy = running;

endmodule
// ---- ap68040_predec.sv ----
//--------------------------------------------------------------------------//
// AP68040 - pipelined MC68040                                            //
//                                                                          //
// ap68040_predec.sv - predecode of one instruction queue word              //
//                                                                          //
// Treats the word as an operation word and works out everything D1 needs  //
// to size the instruction without decoding it: legality, decoder entry,   //
// size, and the instruction length assuming brief index extension words. //
// D1 checks bit 8 of the words at the index extension positions (a full-  //
// format extension) and the slow flag (FPU immediates) and takes its      //
// multi-cycle path for those.                                             //
//--------------------------------------------------------------------------//

module ap68040_predec
	import ap68040_pkg::*, ap68040_upkg::*;
(
	input  logic [15:0] op,
	input  pdw_t        w,          // the table's word for op[15:3]
	output pd_t         pd
);

// ---- inlined from ap68040_pd_alt.svh (tools/import_ap68040.py) ----
// generated by tools/ucode.py - do not edit
// the predecoder table's alternate words (selected by the register field)
function automatic logic [24:0] pd_alt(input logic [4:0] k);
	case (k)
		5'd0: pd_alt = 25'h015043f;  // ORSR
		5'd1: pd_alt = 25'h016463f;  // ORSR
		5'd2: pd_alt = 25'h017043f;  // ANDSR
		5'd3: pd_alt = 25'h018463f;  // ANDSR
		5'd4: pd_alt = 25'h019043f;  // EORSR
		5'd5: pd_alt = 25'h01a463f;  // EORSR
		5'd6: pd_alt = 25'h021603f;  // CAS2
		5'd7: pd_alt = 25'h022a03f;  // CAS2
		5'd8: pd_alt = 25'h054803f;  // ILLG
		5'd9: pd_alt = 25'h05c803f;  // RESET
		5'd10: pd_alt = 25'h05d803f;  // NOP
		5'd11: pd_alt = 25'h05e863f;  // STOP
		5'd12: pd_alt = 25'h05f803f;  // RTE
		5'd13: pd_alt = 25'h060863f;  // RTD
		5'd14: pd_alt = 25'h061803f;  // RTS
		5'd15: pd_alt = 25'h062803f;  // TRAPV
		5'd16: pd_alt = 25'h063803f;  // RTR
		5'd17: pd_alt = 25'h064903f;  // MOVEC2
		5'd18: pd_alt = 25'h065903f;  // MOVE2C
		5'd19: pd_alt = 25'h1ff0000;  // -
		5'd20: pd_alt = 25'h0778c3f;  // TRAPcc
		5'd21: pd_alt = 25'h0788c3f;  // TRAPcc
		5'd22: pd_alt = 25'h0798c3f;  // TRAPcc
		5'd23: pd_alt = 25'h0ea9c3f;  // FTRAPcc
		5'd24: pd_alt = 25'h0eb9c3f;  // FTRAPcc
		5'd25: pd_alt = 25'h0ec9c3f;  // FTRAPcc
		default: pd_alt = 25'h1ff0000;
	endcase
endfunction
// ---- end of ap68040_pd_alt.svh ----

function automatic logic [3:0] ea_idx(input logic [2:0] m, input logic [2:0] r);
	if (m != 3'd7) ea_idx = {1'b0, m};
	else if (r <= 3'd4) ea_idx = 4'd7 + {1'b0, r};
	else ea_idx = EM_NONE;
endfunction

// extension words of an EA with a brief index extension
function automatic logic [2:0] ea_brief_len(input logic [3:0] i, input logic [1:0] sz);
	case (i)
		EM_AD16, EM_ABSW, EM_PC16, EM_AX, EM_PCX: ea_brief_len = 3'd1;
		EM_ABSL: ea_brief_len = 3'd2;
		EM_IMM:  ea_brief_len = (sz == SZ_L) ? 3'd2 : 3'd1;
		default: ea_brief_len = 3'd0;
	endcase
endfunction

always_comb begin
	pdw_t x;
	logic [24:0] aw;
	logic        use_alt;
	logic [4:0]  ak;
	logic [3:0]  i0, i1;
	logic [2:0]  nimm_l, nimm_n, l0_l, l0_n, l1_l, l1_n, b_l, b_n;
	logic [1:0]  sz;
	logic        isl, legal0;
	// the word, or the alternate the register field selects
	x = w;
	use_alt = 1'b0;
	ak = w.alt;
	case (w.kind)
		2'd1: begin use_alt = (op[2:0] == 3'd4); end
		2'd2: begin use_alt = (op[2:0] == 3'd2) || (op[2:0] == 3'd3) || (op[2:0] == 3'd4);
		            ak = w.alt + {2'd0, op[2:0]} - 5'd2; end
		2'd3: begin use_alt = 1'b1; ak = w.alt + {2'd0, op[2:0]}; end
		default: ;
	endcase
	aw = pd_alt(ak);
	if (use_alt) {x.ent, x.szc, x.nfix, x.immk, x.ea0v, x.ea1v, x.fpg, x.leg1, x.leg0} = aw;
	i0 = x.ea0v ? ea_idx(op[5:3], op[2:0]) : EM_NONE;
	i1 = x.ea1v ? ea_idx(op[8:6], op[11:9]) : EM_NONE;
	sz = (x.szc == 2'd3) ? op[7:6] : x.szc;
	// the lengths are formed for a long and for a shorter size side by
	// side, and the size picks one last (a timing path: the size comes
	// out of the table)
	isl = (x.szc == 2'd3) ? (op[7:6] == SZ_L) : (x.szc == SZ_L);
	case (x.immk)
		3'd1:       begin nimm_l = 3'd2; nimm_n = 3'd1; end
		3'd2, 3'd3: begin nimm_l = 3'd1; nimm_n = 3'd1; end
		3'd4:       begin nimm_l = 3'd2; nimm_n = 3'd2; end
		3'd5:       begin nimm_l = (op[7:0] == 8'h00) ? 3'd1 : (op[7:0] == 8'hFF) ? 3'd2 : 3'd0; nimm_n = nimm_l; end
		3'd6:       begin nimm_l = (op[2:0] == 3'd2) ? 3'd1 : (op[2:0] == 3'd3) ? 3'd2 : 3'd0; nimm_n = nimm_l; end
		3'd7:       begin nimm_l = op[6] ? 3'd2 : 3'd1; nimm_n = nimm_l; end
		default:    begin nimm_l = 3'd0; nimm_n = 3'd0; end
	endcase
	l0_l = ea_brief_len(i0, SZ_L);
	l0_n = ea_brief_len(i0, SZ_W);
	l1_l = ea_brief_len(i1, SZ_L);
	l1_n = ea_brief_len(i1, SZ_W);
	b_l  = 3'd1 + {1'b0, x.nfix} + nimm_l;
	b_n  = 3'd1 + {1'b0, x.nfix} + nimm_n;
	// EA0's legality: the word's bit for the mode, or for mode 7 the bit
	// of the register (5-7 are no modes)
	legal0 = !x.ea0v || ((op[5:3] != 3'd7) ? x.leg0[0] : (!op[2] || op[1:0] == 2'b00) && x.leg0[op[2:0]]);
	pd.legal = (x.ent != PD_NOENT) && legal0 && (!x.ea1v || x.leg1);
	pd.ent  = (x.ent == PD_NOENT) ? 9'd0 : x.ent;   // (no entry: 0, as the pattern decoder)
	pd.sz   = sz;
	pd.b    = isl ? b_l : b_n;
	pd.p1   = isl ? (b_l + l0_l) : (b_n + l0_n);
	pd.tot  = isl ? ({1'b0, b_l} + ({1'b0, l0_l} + {1'b0, l1_l}))
	              : ({1'b0, b_n} + ({1'b0, l0_n} + {1'b0, l1_n}));
	pd.x0   = (i0 == EM_AX) || (i0 == EM_PCX);
	pd.x1   = (i1 == EM_AX) || (i1 == EM_PCX);
	pd.slow = x.fpg && (i0 == EM_IMM);
	pd.i0   = i0;
	pd.i1   = i1;
	// an illegal word: D1 takes one word and the exception; b, p1 and tot
	// are not used for it (they stay off the override, a timing path)
	if (!pd.legal) begin
		pd.x0  = 1'b0;
		pd.x1  = 1'b0;
		pd.slow = 1'b0;
	end
end

endmodule

// the same predecode from the parallel pattern decoder (simulation: the
// reference the table form is checked against)
module ap68040_predec_pla
	import ap68040_pkg::*, ap68040_upkg::*;
(
	input  logic [15:0] op,
	output pd_t         pd
);

// ---- inlined from ap68040_dec_pla.svh (tools/import_ap68040.py) ----
// generated by tools/ucode.py - do not edit
// Operation word decoder: every pattern is matched in parallel and
// excluded by the more specific patterns overlapping it, so exactly
// one entry (or none) is selected; attributes are OR trees.
localparam int NENT = 276;
typedef struct packed {
	logic match;
	logic [8:0] ent;
	logic [9:0] rt;
	logic [6:0] eop;
	logic [3:0] econd;
	logic econd_v;
	logic [4:0] ccr;
	logic [1:0] szc;
	logic [11:0] ea0m;
	logic [11:0] ea1m;
	logic [1:0] nfix;
	logic [2:0] immk;
	logic priv;
	logic [5:0] jc0;
	logic [9:0] jt0;
	logic ea0v;
	logic ea1v;
	logic [1:0] fea;
	logic t0;
} pla_t;
function automatic logic [NENT-1:0] dec_sel(input logic [15:0] op);
	logic [NENT-1:0] m, s;
	m[0] = ((op & 16'hffc0) == 16'h0000) && (op[7:6] != 2'b11);  // OR IMM_OP
	m[1] = ((op & 16'hffc0) == 16'h0200) && (op[7:6] != 2'b11);  // AND IMM_OP
	m[2] = ((op & 16'hffc0) == 16'h0400) && (op[7:6] != 2'b11);  // SUB IMM_OP
	m[3] = ((op & 16'hffc0) == 16'h0600) && (op[7:6] != 2'b11);  // ADD IMM_OP
	m[4] = ((op & 16'hffc0) == 16'h0a00) && (op[7:6] != 2'b11);  // EOR IMM_OP
	m[5] = ((op & 16'hffc0) == 16'h0c00) && (op[7:6] != 2'b11);  // CMP IMM_CMP
	m[6] = ((op & 16'hffc0) == 16'h0e00) && (op[7:6] != 2'b11);  // MOVES MOVES
	m[7] = ((op & 16'hffc0) == 16'h0040) && (op[7:6] != 2'b11);  // OR IMM_OP
	m[8] = ((op & 16'hffc0) == 16'h0240) && (op[7:6] != 2'b11);  // AND IMM_OP
	m[9] = ((op & 16'hffc0) == 16'h0440) && (op[7:6] != 2'b11);  // SUB IMM_OP
	m[10] = ((op & 16'hffc0) == 16'h0640) && (op[7:6] != 2'b11);  // ADD IMM_OP
	m[11] = ((op & 16'hffc0) == 16'h0a40) && (op[7:6] != 2'b11);  // EOR IMM_OP
	m[12] = ((op & 16'hffc0) == 16'h0c40) && (op[7:6] != 2'b11);  // CMP IMM_CMP
	m[13] = ((op & 16'hffc0) == 16'h0e40) && (op[7:6] != 2'b11);  // MOVES MOVES
	m[14] = ((op & 16'hffc0) == 16'h0080) && (op[7:6] != 2'b11);  // OR IMM_OP
	m[15] = ((op & 16'hffc0) == 16'h0280) && (op[7:6] != 2'b11);  // AND IMM_OP
	m[16] = ((op & 16'hffc0) == 16'h0480) && (op[7:6] != 2'b11);  // SUB IMM_OP
	m[17] = ((op & 16'hffc0) == 16'h0680) && (op[7:6] != 2'b11);  // ADD IMM_OP
	m[18] = ((op & 16'hffc0) == 16'h0a80) && (op[7:6] != 2'b11);  // EOR IMM_OP
	m[19] = ((op & 16'hffc0) == 16'h0c80) && (op[7:6] != 2'b11);  // CMP IMM_CMP
	m[20] = ((op & 16'hffc0) == 16'h0e80) && (op[7:6] != 2'b11);  // MOVES MOVES
	m[21] = ((op & 16'hffff) == 16'h003c);  // ORSR CCR_LOG
	m[22] = ((op & 16'hffff) == 16'h007c);  // ORSR SR_LOG
	m[23] = ((op & 16'hffff) == 16'h023c);  // ANDSR CCR_LOG
	m[24] = ((op & 16'hffff) == 16'h027c);  // ANDSR SR_LOG
	m[25] = ((op & 16'hffff) == 16'h0a3c);  // EORSR CCR_LOG
	m[26] = ((op & 16'hffff) == 16'h0a7c);  // EORSR SR_LOG
	m[27] = ((op & 16'hffc0) == 16'h00c0);  // CHK2 CHK2
	m[28] = ((op & 16'hffc0) == 16'h02c0);  // CHK2 CHK2
	m[29] = ((op & 16'hffc0) == 16'h04c0);  // CHK2 CHK2
	m[30] = ((op & 16'hffc0) == 16'h0ac0);  // CAS CAS
	m[31] = ((op & 16'hffc0) == 16'h0cc0);  // CAS CAS
	m[32] = ((op & 16'hffc0) == 16'h0ec0);  // CAS CAS
	m[33] = ((op & 16'hffff) == 16'h0cfc);  // CAS2 CAS2
	m[34] = ((op & 16'hffff) == 16'h0efc);  // CAS2 CAS2
	m[35] = ((op & 16'hffc0) == 16'h0800);  // BTST BTST_IMM
	m[36] = ((op & 16'hffc0) == 16'h0840);  // BCHG BIT_IMM
	m[37] = ((op & 16'hffc0) == 16'h0880);  // BCLR BIT_IMM
	m[38] = ((op & 16'hffc0) == 16'h08c0);  // BSET BIT_IMM
	m[39] = ((op & 16'hf1c0) == 16'h0100);  // BTST BTST_DYN
	m[40] = ((op & 16'hf1c0) == 16'h0140);  // BCHG BIT_DYN
	m[41] = ((op & 16'hf1c0) == 16'h0180);  // BCLR BIT_DYN
	m[42] = ((op & 16'hf1c0) == 16'h01c0);  // BSET BIT_DYN
	m[43] = ((op & 16'hf1f8) == 16'h0108);  // MVPMR MOVEP_MR
	m[44] = ((op & 16'hf1f8) == 16'h0148);  // MVPMR MOVEP_MR
	m[45] = ((op & 16'hf1f8) == 16'h0188);  // MVPRM MOVEP_RM
	m[46] = ((op & 16'hf1f8) == 16'h01c8);  // MVPRM MOVEP_RM
	m[47] = ((op & 16'hf000) == 16'h1000);  // MOVE MOVE
	m[48] = ((op & 16'hf000) == 16'h3000);  // MOVE MOVE
	m[49] = ((op & 16'hf000) == 16'h2000);  // MOVE MOVE
	m[50] = ((op & 16'hf1c0) == 16'h3040);  // MOVEA MOVEA
	m[51] = ((op & 16'hf1c0) == 16'h2040);  // MOVEA MOVEA
	m[52] = ((op & 16'hffc0) == 16'h4000) && (op[7:6] != 2'b11);  // NEGX UNARY
	m[53] = ((op & 16'hffc0) == 16'h4200) && (op[7:6] != 2'b11);  // CLR CLR_W
	m[54] = ((op & 16'hffc0) == 16'h4400) && (op[7:6] != 2'b11);  // NEG UNARY
	m[55] = ((op & 16'hffc0) == 16'h4600) && (op[7:6] != 2'b11);  // NOT UNARY
	m[56] = ((op & 16'hffc0) == 16'h4a00) && (op[7:6] != 2'b11);  // TST TST
	m[57] = ((op & 16'hffc0) == 16'h4040) && (op[7:6] != 2'b11);  // NEGX UNARY
	m[58] = ((op & 16'hffc0) == 16'h4240) && (op[7:6] != 2'b11);  // CLR CLR_W
	m[59] = ((op & 16'hffc0) == 16'h4440) && (op[7:6] != 2'b11);  // NEG UNARY
	m[60] = ((op & 16'hffc0) == 16'h4640) && (op[7:6] != 2'b11);  // NOT UNARY
	m[61] = ((op & 16'hffc0) == 16'h4a40) && (op[7:6] != 2'b11);  // TST TST
	m[62] = ((op & 16'hffc0) == 16'h4080) && (op[7:6] != 2'b11);  // NEGX UNARY
	m[63] = ((op & 16'hffc0) == 16'h4280) && (op[7:6] != 2'b11);  // CLR CLR_W
	m[64] = ((op & 16'hffc0) == 16'h4480) && (op[7:6] != 2'b11);  // NEG UNARY
	m[65] = ((op & 16'hffc0) == 16'h4680) && (op[7:6] != 2'b11);  // NOT UNARY
	m[66] = ((op & 16'hffc0) == 16'h4a80) && (op[7:6] != 2'b11);  // TST TST
	m[67] = ((op & 16'hffc0) == 16'h40c0);  // MVSR2 MOVE_FROM_SR
	m[68] = ((op & 16'hffc0) == 16'h42c0);  // MVSR2 MOVE_FROM_CCR
	m[69] = ((op & 16'hffc0) == 16'h44c0);  // MV2SR MOVE_TO_CCR
	m[70] = ((op & 16'hffc0) == 16'h46c0);  // MV2SR MOVE_TO_SR
	m[71] = ((op & 16'hfff8) == 16'h4808);  // LINK LINK
	m[72] = ((op & 16'hffc0) == 16'h4800);  // NBCD UNARY
	m[73] = ((op & 16'hfff8) == 16'h4848);  // BKPT BKPT
	m[74] = ((op & 16'hfff8) == 16'h4840);  // SWAP SWAP
	m[75] = ((op & 16'hffc0) == 16'h4840);  // PEA PEA
	m[76] = ((op & 16'hfff8) == 16'h4880);  // EXT EXT
	m[77] = ((op & 16'hfff8) == 16'h48c0);  // EXT EXT
	m[78] = ((op & 16'hfff8) == 16'h49c0);  // EXT EXTB
	m[79] = ((op & 16'hffc0) == 16'h4880);  // MVMLE MOVEM_RM
	m[80] = ((op & 16'hffc0) == 16'h48c0);  // MVMLE MOVEM_RM
	m[81] = ((op & 16'hffc0) == 16'h4c80);  // MVMEL MOVEM_MR
	m[82] = ((op & 16'hffc0) == 16'h4cc0);  // MVMEL MOVEM_MR
	m[83] = ((op & 16'hffc0) == 16'h4ac0);  // TAS TAS
	m[84] = ((op & 16'hffff) == 16'h4afc);  // ILLG ILLEGAL
	m[85] = ((op & 16'hffc0) == 16'h4c00);  // MULL MULL
	m[86] = ((op & 16'hffc0) == 16'h4c40);  // DIVL DIVL
	m[87] = ((op & 16'hfff0) == 16'h4e40);  // TRAP TRAP
	m[88] = ((op & 16'hfff8) == 16'h4e50);  // LINK LINK
	m[89] = ((op & 16'hfff8) == 16'h4e58);  // UNLK UNLK
	m[90] = ((op & 16'hfff8) == 16'h4e60);  // MVR2USP MOVE_TO_USP
	m[91] = ((op & 16'hfff8) == 16'h4e68);  // MVUSP2R MOVE_FROM_USP
	m[92] = ((op & 16'hffff) == 16'h4e70);  // RESET RESET
	m[93] = ((op & 16'hffff) == 16'h4e71);  // NOP NOP
	m[94] = ((op & 16'hffff) == 16'h4e72);  // STOP STOP
	m[95] = ((op & 16'hffff) == 16'h4e73);  // RTE RTE
	m[96] = ((op & 16'hffff) == 16'h4e74);  // RTD RTD
	m[97] = ((op & 16'hffff) == 16'h4e75);  // RTS RTS
	m[98] = ((op & 16'hffff) == 16'h4e76);  // TRAPV TRAPV
	m[99] = ((op & 16'hffff) == 16'h4e77);  // RTR RTR
	m[100] = ((op & 16'hffff) == 16'h4e7a);  // MOVEC2 MOVEC_RD
	m[101] = ((op & 16'hffff) == 16'h4e7b);  // MOVE2C MOVEC_WR
	m[102] = ((op & 16'hffc0) == 16'h4e80);  // JSR JSR
	m[103] = ((op & 16'hffc0) == 16'h4ec0);  // JMP JMP
	m[104] = ((op & 16'hf1c0) == 16'h4100);  // CHK CHK
	m[105] = ((op & 16'hf1c0) == 16'h4180);  // CHK CHK
	m[106] = ((op & 16'hf1c0) == 16'h41c0);  // LEA LEA
	m[107] = ((op & 16'hf1c0) == 16'h5000) && (op[7:6] != 2'b11);  // ADD QUICK
	m[108] = ((op & 16'hf1c0) == 16'h5100) && (op[7:6] != 2'b11);  // SUB QUICK
	m[109] = ((op & 16'hf1c0) == 16'h5040) && (op[7:6] != 2'b11);  // ADD QUICK
	m[110] = ((op & 16'hf1c0) == 16'h5140) && (op[7:6] != 2'b11);  // SUB QUICK
	m[111] = ((op & 16'hf1c0) == 16'h5080) && (op[7:6] != 2'b11);  // ADD QUICK
	m[112] = ((op & 16'hf1c0) == 16'h5180) && (op[7:6] != 2'b11);  // SUB QUICK
	m[113] = ((op & 16'hf1f8) == 16'h5048);  // ADDA QUICK_A
	m[114] = ((op & 16'hf1f8) == 16'h5088);  // ADDA QUICK_A
	m[115] = ((op & 16'hf1f8) == 16'h5148);  // SUBA QUICK_SA
	m[116] = ((op & 16'hf1f8) == 16'h5188);  // SUBA QUICK_SA
	m[117] = ((op & 16'hf0c0) == 16'h50c0);  // Scc SCC
	m[118] = ((op & 16'hf0f8) == 16'h50c8);  // DBcc DBCC
	m[119] = ((op & 16'hf0ff) == 16'h50fa);  // TRAPcc TRAPCC
	m[120] = ((op & 16'hf0ff) == 16'h50fb);  // TRAPcc TRAPCC
	m[121] = ((op & 16'hf0ff) == 16'h50fc);  // TRAPcc TRAPCC
	m[122] = ((op & 16'hff00) == 16'h6100);  // BSR BSR
	m[123] = ((op & 16'hf000) == 16'h6000);  // Bcc BCC
	m[124] = ((op & 16'hf100) == 16'h7000);  // MOVE MOVEQ
	m[125] = ((op & 16'hf1c0) == 16'h8000) && (op[7:6] != 2'b11);  // OR OP_EA_DN
	m[126] = ((op & 16'hf1c0) == 16'h8100) && (op[7:6] != 2'b11);  // OR OP_DN_EA
	m[127] = ((op & 16'hf1c0) == 16'hc000) && (op[7:6] != 2'b11);  // AND OP_EA_DN
	m[128] = ((op & 16'hf1c0) == 16'hc100) && (op[7:6] != 2'b11);  // AND OP_DN_EA
	m[129] = ((op & 16'hf1c0) == 16'h9000) && (op[7:6] != 2'b11);  // SUB OP_EA_DN
	m[130] = ((op & 16'hf1c0) == 16'h9100) && (op[7:6] != 2'b11);  // SUB OP_DN_EA
	m[131] = ((op & 16'hf1c0) == 16'hd000) && (op[7:6] != 2'b11);  // ADD OP_EA_DN
	m[132] = ((op & 16'hf1c0) == 16'hd100) && (op[7:6] != 2'b11);  // ADD OP_DN_EA
	m[133] = ((op & 16'hf1c0) == 16'hb000) && (op[7:6] != 2'b11);  // CMP CMP_EA_DN
	m[134] = ((op & 16'hf1c0) == 16'hb100) && (op[7:6] != 2'b11);  // EOR OP_DN_EA
	m[135] = ((op & 16'hf1f8) == 16'hb108) && (op[7:6] != 2'b11);  // CMPM CMPM
	m[136] = ((op & 16'hf1f8) == 16'h9100) && (op[7:6] != 2'b11);  // SUBX ADDX_R
	m[137] = ((op & 16'hf1f8) == 16'h9108) && (op[7:6] != 2'b11);  // SUBX ADDX_M
	m[138] = ((op & 16'hf1f8) == 16'hd100) && (op[7:6] != 2'b11);  // ADDX ADDX_R
	m[139] = ((op & 16'hf1f8) == 16'hd108) && (op[7:6] != 2'b11);  // ADDX ADDX_M
	m[140] = ((op & 16'hf1c0) == 16'h8040) && (op[7:6] != 2'b11);  // OR OP_EA_DN
	m[141] = ((op & 16'hf1c0) == 16'h8140) && (op[7:6] != 2'b11);  // OR OP_DN_EA
	m[142] = ((op & 16'hf1c0) == 16'hc040) && (op[7:6] != 2'b11);  // AND OP_EA_DN
	m[143] = ((op & 16'hf1c0) == 16'hc140) && (op[7:6] != 2'b11);  // AND OP_DN_EA
	m[144] = ((op & 16'hf1c0) == 16'h9040) && (op[7:6] != 2'b11);  // SUB OP_EA_DN
	m[145] = ((op & 16'hf1c0) == 16'h9140) && (op[7:6] != 2'b11);  // SUB OP_DN_EA
	m[146] = ((op & 16'hf1c0) == 16'hd040) && (op[7:6] != 2'b11);  // ADD OP_EA_DN
	m[147] = ((op & 16'hf1c0) == 16'hd140) && (op[7:6] != 2'b11);  // ADD OP_DN_EA
	m[148] = ((op & 16'hf1c0) == 16'hb040) && (op[7:6] != 2'b11);  // CMP CMP_EA_DN
	m[149] = ((op & 16'hf1c0) == 16'hb140) && (op[7:6] != 2'b11);  // EOR OP_DN_EA
	m[150] = ((op & 16'hf1f8) == 16'hb148) && (op[7:6] != 2'b11);  // CMPM CMPM
	m[151] = ((op & 16'hf1f8) == 16'h9140) && (op[7:6] != 2'b11);  // SUBX ADDX_R
	m[152] = ((op & 16'hf1f8) == 16'h9148) && (op[7:6] != 2'b11);  // SUBX ADDX_M
	m[153] = ((op & 16'hf1f8) == 16'hd140) && (op[7:6] != 2'b11);  // ADDX ADDX_R
	m[154] = ((op & 16'hf1f8) == 16'hd148) && (op[7:6] != 2'b11);  // ADDX ADDX_M
	m[155] = ((op & 16'hf1c0) == 16'h8080) && (op[7:6] != 2'b11);  // OR OP_EA_DN
	m[156] = ((op & 16'hf1c0) == 16'h8180) && (op[7:6] != 2'b11);  // OR OP_DN_EA
	m[157] = ((op & 16'hf1c0) == 16'hc080) && (op[7:6] != 2'b11);  // AND OP_EA_DN
	m[158] = ((op & 16'hf1c0) == 16'hc180) && (op[7:6] != 2'b11);  // AND OP_DN_EA
	m[159] = ((op & 16'hf1c0) == 16'h9080) && (op[7:6] != 2'b11);  // SUB OP_EA_DN
	m[160] = ((op & 16'hf1c0) == 16'h9180) && (op[7:6] != 2'b11);  // SUB OP_DN_EA
	m[161] = ((op & 16'hf1c0) == 16'hd080) && (op[7:6] != 2'b11);  // ADD OP_EA_DN
	m[162] = ((op & 16'hf1c0) == 16'hd180) && (op[7:6] != 2'b11);  // ADD OP_DN_EA
	m[163] = ((op & 16'hf1c0) == 16'hb080) && (op[7:6] != 2'b11);  // CMP CMP_EA_DN
	m[164] = ((op & 16'hf1c0) == 16'hb180) && (op[7:6] != 2'b11);  // EOR OP_DN_EA
	m[165] = ((op & 16'hf1f8) == 16'hb188) && (op[7:6] != 2'b11);  // CMPM CMPM
	m[166] = ((op & 16'hf1f8) == 16'h9180) && (op[7:6] != 2'b11);  // SUBX ADDX_R
	m[167] = ((op & 16'hf1f8) == 16'h9188) && (op[7:6] != 2'b11);  // SUBX ADDX_M
	m[168] = ((op & 16'hf1f8) == 16'hd180) && (op[7:6] != 2'b11);  // ADDX ADDX_R
	m[169] = ((op & 16'hf1f8) == 16'hd188) && (op[7:6] != 2'b11);  // ADDX ADDX_M
	m[170] = ((op & 16'hf1c0) == 16'h80c0);  // DIVU DIVW
	m[171] = ((op & 16'hf1c0) == 16'h81c0);  // DIVS DIVW
	m[172] = ((op & 16'hf1c0) == 16'hc0c0);  // MULU MULW
	m[173] = ((op & 16'hf1c0) == 16'hc1c0);  // MULS MULW
	m[174] = ((op & 16'hf1f8) == 16'h8100);  // SBCD ADDX_R
	m[175] = ((op & 16'hf1f8) == 16'h8108);  // SBCD ADDX_M
	m[176] = ((op & 16'hf1f8) == 16'hc100);  // ABCD ADDX_R
	m[177] = ((op & 16'hf1f8) == 16'hc108);  // ABCD ADDX_M
	m[178] = ((op & 16'hf1f8) == 16'h8140);  // PACK PACK_R
	m[179] = ((op & 16'hf1f8) == 16'h8148);  // PACK PACK_M
	m[180] = ((op & 16'hf1f8) == 16'h8180);  // UNPK UNPK_R
	m[181] = ((op & 16'hf1f8) == 16'h8188);  // UNPK UNPK_M
	m[182] = ((op & 16'hf1c0) == 16'h90c0);  // SUBA SUBA
	m[183] = ((op & 16'hf1c0) == 16'h91c0);  // SUBA SUBA
	m[184] = ((op & 16'hf1c0) == 16'hd0c0);  // ADDA ADDA
	m[185] = ((op & 16'hf1c0) == 16'hd1c0);  // ADDA ADDA
	m[186] = ((op & 16'hf1c0) == 16'hb0c0);  // CMPA CMPA
	m[187] = ((op & 16'hf1c0) == 16'hb1c0);  // CMPA CMPA
	m[188] = ((op & 16'hf1f8) == 16'hc140);  // EXG EXG_DD
	m[189] = ((op & 16'hf1f8) == 16'hc148);  // EXG EXG_AA
	m[190] = ((op & 16'hf1f8) == 16'hc188);  // EXG EXG_DA
	m[191] = ((op & 16'hf1d8) == 16'he000) && (op[7:6] != 2'b11);  // ASR SHIFT_R
	m[192] = ((op & 16'hf1d8) == 16'he100) && (op[7:6] != 2'b11);  // ASL SHIFT_R
	m[193] = ((op & 16'hf1d8) == 16'he008) && (op[7:6] != 2'b11);  // LSR SHIFT_R
	m[194] = ((op & 16'hf1d8) == 16'he108) && (op[7:6] != 2'b11);  // LSL SHIFT_R
	m[195] = ((op & 16'hf1d8) == 16'he010) && (op[7:6] != 2'b11);  // ROXR SHIFT_R
	m[196] = ((op & 16'hf1d8) == 16'he110) && (op[7:6] != 2'b11);  // ROXL SHIFT_R
	m[197] = ((op & 16'hf1d8) == 16'he018) && (op[7:6] != 2'b11);  // ROR SHIFT_R
	m[198] = ((op & 16'hf1d8) == 16'he118) && (op[7:6] != 2'b11);  // ROL SHIFT_R
	m[199] = ((op & 16'hf1d8) == 16'he040) && (op[7:6] != 2'b11);  // ASR SHIFT_R
	m[200] = ((op & 16'hf1d8) == 16'he140) && (op[7:6] != 2'b11);  // ASL SHIFT_R
	m[201] = ((op & 16'hf1d8) == 16'he048) && (op[7:6] != 2'b11);  // LSR SHIFT_R
	m[202] = ((op & 16'hf1d8) == 16'he148) && (op[7:6] != 2'b11);  // LSL SHIFT_R
	m[203] = ((op & 16'hf1d8) == 16'he050) && (op[7:6] != 2'b11);  // ROXR SHIFT_R
	m[204] = ((op & 16'hf1d8) == 16'he150) && (op[7:6] != 2'b11);  // ROXL SHIFT_R
	m[205] = ((op & 16'hf1d8) == 16'he058) && (op[7:6] != 2'b11);  // ROR SHIFT_R
	m[206] = ((op & 16'hf1d8) == 16'he158) && (op[7:6] != 2'b11);  // ROL SHIFT_R
	m[207] = ((op & 16'hf1d8) == 16'he080) && (op[7:6] != 2'b11);  // ASR SHIFT_R
	m[208] = ((op & 16'hf1d8) == 16'he180) && (op[7:6] != 2'b11);  // ASL SHIFT_R
	m[209] = ((op & 16'hf1d8) == 16'he088) && (op[7:6] != 2'b11);  // LSR SHIFT_R
	m[210] = ((op & 16'hf1d8) == 16'he188) && (op[7:6] != 2'b11);  // LSL SHIFT_R
	m[211] = ((op & 16'hf1d8) == 16'he090) && (op[7:6] != 2'b11);  // ROXR SHIFT_R
	m[212] = ((op & 16'hf1d8) == 16'he190) && (op[7:6] != 2'b11);  // ROXL SHIFT_R
	m[213] = ((op & 16'hf1d8) == 16'he098) && (op[7:6] != 2'b11);  // ROR SHIFT_R
	m[214] = ((op & 16'hf1d8) == 16'he198) && (op[7:6] != 2'b11);  // ROL SHIFT_R
	m[215] = ((op & 16'hffc0) == 16'he0c0);  // ASRW SHIFT_M
	m[216] = ((op & 16'hffc0) == 16'he1c0);  // ASLW SHIFT_M
	m[217] = ((op & 16'hffc0) == 16'he2c0);  // LSRW SHIFT_M
	m[218] = ((op & 16'hffc0) == 16'he3c0);  // LSLW SHIFT_M
	m[219] = ((op & 16'hffc0) == 16'he4c0);  // ROXRW SHIFT_M
	m[220] = ((op & 16'hffc0) == 16'he5c0);  // ROXLW SHIFT_M
	m[221] = ((op & 16'hffc0) == 16'he6c0);  // RORW SHIFT_M
	m[222] = ((op & 16'hffc0) == 16'he7c0);  // ROLW SHIFT_M
	m[223] = ((op & 16'hffc0) == 16'he8c0);  // BFTST BF_TST
	m[224] = ((op & 16'hffc0) == 16'he9c0);  // BFEXTU BF_EXT
	m[225] = ((op & 16'hffc0) == 16'heac0);  // BFCHG BF_MOD
	m[226] = ((op & 16'hffc0) == 16'hebc0);  // BFEXTS BF_EXT
	m[227] = ((op & 16'hffc0) == 16'hecc0);  // BFCLR BF_MOD
	m[228] = ((op & 16'hffc0) == 16'hedc0);  // BFFFO BF_EXT
	m[229] = ((op & 16'hffc0) == 16'heec0);  // BFSET BF_MOD
	m[230] = ((op & 16'hffc0) == 16'hefc0);  // BFINS BF_MOD
	m[231] = ((op & 16'hffc0) == 16'hf200);  // FPP FPU_GEN
	m[232] = ((op & 16'hffc0) == 16'hf240);  // FScc FSCC
	m[233] = ((op & 16'hfff8) == 16'hf248);  // FDBcc FDBCC
	m[234] = ((op & 16'hffff) == 16'hf27a);  // FTRAPcc FTRAPCC
	m[235] = ((op & 16'hffff) == 16'hf27b);  // FTRAPcc FTRAPCC
	m[236] = ((op & 16'hffff) == 16'hf27c);  // FTRAPcc FTRAPCC
	m[237] = ((op & 16'hffc0) == 16'hf280);  // FBcc FBCC
	m[238] = ((op & 16'hffc0) == 16'hf2c0);  // FBcc FBCC
	m[239] = ((op & 16'hffc0) == 16'hf300);  // FSAVE FSAVE
	m[240] = ((op & 16'hffc0) == 16'hf340);  // FRESTORE FRESTORE
	m[241] = ((op & 16'hfff8) == 16'hf408);  // CINVL CACHE_OP
	m[242] = ((op & 16'hfff8) == 16'hf410);  // CINVP CACHE_OP
	m[243] = ((op & 16'hfff8) == 16'hf418);  // CINVA CACHE_OP
	m[244] = ((op & 16'hfff8) == 16'hf428);  // CPUSHL CACHE_OP
	m[245] = ((op & 16'hfff8) == 16'hf430);  // CPUSHP CACHE_OP
	m[246] = ((op & 16'hfff8) == 16'hf438);  // CPUSHA CACHE_OP
	m[247] = ((op & 16'hfff8) == 16'hf448);  // CINVL CACHE_OP
	m[248] = ((op & 16'hfff8) == 16'hf450);  // CINVP CACHE_OP
	m[249] = ((op & 16'hfff8) == 16'hf458);  // CINVA CACHE_OP
	m[250] = ((op & 16'hfff8) == 16'hf468);  // CPUSHL CACHE_OP
	m[251] = ((op & 16'hfff8) == 16'hf470);  // CPUSHP CACHE_OP
	m[252] = ((op & 16'hfff8) == 16'hf478);  // CPUSHA CACHE_OP
	m[253] = ((op & 16'hfff8) == 16'hf488);  // CINVL CACHE_OP
	m[254] = ((op & 16'hfff8) == 16'hf490);  // CINVP CACHE_OP
	m[255] = ((op & 16'hfff8) == 16'hf498);  // CINVA CACHE_OP
	m[256] = ((op & 16'hfff8) == 16'hf4a8);  // CPUSHL CACHE_OP
	m[257] = ((op & 16'hfff8) == 16'hf4b0);  // CPUSHP CACHE_OP
	m[258] = ((op & 16'hfff8) == 16'hf4b8);  // CPUSHA CACHE_OP
	m[259] = ((op & 16'hfff8) == 16'hf4c8);  // CINVL CACHE_OP
	m[260] = ((op & 16'hfff8) == 16'hf4d0);  // CINVP CACHE_OP
	m[261] = ((op & 16'hfff8) == 16'hf4d8);  // CINVA CACHE_OP
	m[262] = ((op & 16'hfff8) == 16'hf4e8);  // CPUSHL CACHE_OP
	m[263] = ((op & 16'hfff8) == 16'hf4f0);  // CPUSHP CACHE_OP
	m[264] = ((op & 16'hfff8) == 16'hf4f8);  // CPUSHA CACHE_OP
	m[265] = ((op & 16'hfff8) == 16'hf500);  // PFLUSHN PFLUSH
	m[266] = ((op & 16'hfff8) == 16'hf508);  // PFLUSH PFLUSH
	m[267] = ((op & 16'hfff8) == 16'hf510);  // PFLUSHAN PFLUSH
	m[268] = ((op & 16'hfff8) == 16'hf518);  // PFLUSHA PFLUSH
	m[269] = ((op & 16'hfff8) == 16'hf548);  // PTESTW PTEST
	m[270] = ((op & 16'hfff8) == 16'hf568);  // PTESTR PTEST
	m[271] = ((op & 16'hfff8) == 16'hf600);  // MOVE16 MOVE16
	m[272] = ((op & 16'hfff8) == 16'hf608);  // MOVE16 MOVE16
	m[273] = ((op & 16'hfff8) == 16'hf610);  // MOVE16 MOVE16
	m[274] = ((op & 16'hfff8) == 16'hf618);  // MOVE16 MOVE16
	m[275] = ((op & 16'hfff8) == 16'hf620);  // MOVE16 MOVE16
	s[0] = m[0] & ~(m[21]);
	s[1] = m[1] & ~(m[23]);
	s[2] = m[2];
	s[3] = m[3];
	s[4] = m[4] & ~(m[25]);
	s[5] = m[5];
	s[6] = m[6];
	s[7] = m[7] & ~(m[22]);
	s[8] = m[8] & ~(m[24]);
	s[9] = m[9];
	s[10] = m[10];
	s[11] = m[11] & ~(m[26]);
	s[12] = m[12];
	s[13] = m[13];
	s[14] = m[14];
	s[15] = m[15];
	s[16] = m[16];
	s[17] = m[17];
	s[18] = m[18];
	s[19] = m[19];
	s[20] = m[20];
	s[21] = m[21];
	s[22] = m[22];
	s[23] = m[23];
	s[24] = m[24];
	s[25] = m[25];
	s[26] = m[26];
	s[27] = m[27];
	s[28] = m[28];
	s[29] = m[29];
	s[30] = m[30];
	s[31] = m[31] & ~(m[33]);
	s[32] = m[32] & ~(m[34]);
	s[33] = m[33];
	s[34] = m[34];
	s[35] = m[35];
	s[36] = m[36];
	s[37] = m[37];
	s[38] = m[38];
	s[39] = m[39] & ~(m[43]);
	s[40] = m[40] & ~(m[44]);
	s[41] = m[41] & ~(m[45]);
	s[42] = m[42] & ~(m[46]);
	s[43] = m[43];
	s[44] = m[44];
	s[45] = m[45];
	s[46] = m[46];
	s[47] = m[47];
	s[48] = m[48] & ~(m[50]);
	s[49] = m[49] & ~(m[51]);
	s[50] = m[50];
	s[51] = m[51];
	s[52] = m[52];
	s[53] = m[53];
	s[54] = m[54];
	s[55] = m[55];
	s[56] = m[56];
	s[57] = m[57];
	s[58] = m[58];
	s[59] = m[59];
	s[60] = m[60];
	s[61] = m[61];
	s[62] = m[62];
	s[63] = m[63];
	s[64] = m[64];
	s[65] = m[65];
	s[66] = m[66];
	s[67] = m[67];
	s[68] = m[68];
	s[69] = m[69];
	s[70] = m[70];
	s[71] = m[71];
	s[72] = m[72] & ~(m[71]);
	s[73] = m[73];
	s[74] = m[74];
	s[75] = m[75] & ~(m[73] | m[74]);
	s[76] = m[76];
	s[77] = m[77];
	s[78] = m[78];
	s[79] = m[79] & ~(m[76]);
	s[80] = m[80] & ~(m[77]);
	s[81] = m[81];
	s[82] = m[82];
	s[83] = m[83] & ~(m[84]);
	s[84] = m[84];
	s[85] = m[85];
	s[86] = m[86];
	s[87] = m[87];
	s[88] = m[88];
	s[89] = m[89];
	s[90] = m[90];
	s[91] = m[91];
	s[92] = m[92];
	s[93] = m[93];
	s[94] = m[94];
	s[95] = m[95];
	s[96] = m[96];
	s[97] = m[97];
	s[98] = m[98];
	s[99] = m[99];
	s[100] = m[100];
	s[101] = m[101];
	s[102] = m[102];
	s[103] = m[103];
	s[104] = m[104];
	s[105] = m[105];
	s[106] = m[106] & ~(m[78]);
	s[107] = m[107];
	s[108] = m[108];
	s[109] = m[109] & ~(m[113]);
	s[110] = m[110] & ~(m[115]);
	s[111] = m[111] & ~(m[114]);
	s[112] = m[112] & ~(m[116]);
	s[113] = m[113];
	s[114] = m[114];
	s[115] = m[115];
	s[116] = m[116];
	s[117] = m[117] & ~(m[118] | m[119] | m[120] | m[121]);
	s[118] = m[118];
	s[119] = m[119];
	s[120] = m[120];
	s[121] = m[121];
	s[122] = m[122];
	s[123] = m[123] & ~(m[122]);
	s[124] = m[124];
	s[125] = m[125];
	s[126] = m[126] & ~(m[174] | m[175]);
	s[127] = m[127];
	s[128] = m[128] & ~(m[176] | m[177]);
	s[129] = m[129];
	s[130] = m[130] & ~(m[136] | m[137]);
	s[131] = m[131];
	s[132] = m[132] & ~(m[138] | m[139]);
	s[133] = m[133];
	s[134] = m[134] & ~(m[135]);
	s[135] = m[135];
	s[136] = m[136];
	s[137] = m[137];
	s[138] = m[138];
	s[139] = m[139];
	s[140] = m[140];
	s[141] = m[141] & ~(m[178] | m[179]);
	s[142] = m[142];
	s[143] = m[143] & ~(m[188] | m[189]);
	s[144] = m[144];
	s[145] = m[145] & ~(m[151] | m[152]);
	s[146] = m[146];
	s[147] = m[147] & ~(m[153] | m[154]);
	s[148] = m[148];
	s[149] = m[149] & ~(m[150]);
	s[150] = m[150];
	s[151] = m[151];
	s[152] = m[152];
	s[153] = m[153];
	s[154] = m[154];
	s[155] = m[155];
	s[156] = m[156] & ~(m[180] | m[181]);
	s[157] = m[157];
	s[158] = m[158] & ~(m[190]);
	s[159] = m[159];
	s[160] = m[160] & ~(m[166] | m[167]);
	s[161] = m[161];
	s[162] = m[162] & ~(m[168] | m[169]);
	s[163] = m[163];
	s[164] = m[164] & ~(m[165]);
	s[165] = m[165];
	s[166] = m[166];
	s[167] = m[167];
	s[168] = m[168];
	s[169] = m[169];
	s[170] = m[170];
	s[171] = m[171];
	s[172] = m[172];
	s[173] = m[173];
	s[174] = m[174];
	s[175] = m[175];
	s[176] = m[176];
	s[177] = m[177];
	s[178] = m[178];
	s[179] = m[179];
	s[180] = m[180];
	s[181] = m[181];
	s[182] = m[182];
	s[183] = m[183];
	s[184] = m[184];
	s[185] = m[185];
	s[186] = m[186];
	s[187] = m[187];
	s[188] = m[188];
	s[189] = m[189];
	s[190] = m[190];
	s[191] = m[191];
	s[192] = m[192];
	s[193] = m[193];
	s[194] = m[194];
	s[195] = m[195];
	s[196] = m[196];
	s[197] = m[197];
	s[198] = m[198];
	s[199] = m[199];
	s[200] = m[200];
	s[201] = m[201];
	s[202] = m[202];
	s[203] = m[203];
	s[204] = m[204];
	s[205] = m[205];
	s[206] = m[206];
	s[207] = m[207];
	s[208] = m[208];
	s[209] = m[209];
	s[210] = m[210];
	s[211] = m[211];
	s[212] = m[212];
	s[213] = m[213];
	s[214] = m[214];
	s[215] = m[215];
	s[216] = m[216];
	s[217] = m[217];
	s[218] = m[218];
	s[219] = m[219];
	s[220] = m[220];
	s[221] = m[221];
	s[222] = m[222];
	s[223] = m[223];
	s[224] = m[224];
	s[225] = m[225];
	s[226] = m[226];
	s[227] = m[227];
	s[228] = m[228];
	s[229] = m[229];
	s[230] = m[230];
	s[231] = m[231];
	s[232] = m[232] & ~(m[233] | m[234] | m[235] | m[236]);
	s[233] = m[233];
	s[234] = m[234];
	s[235] = m[235];
	s[236] = m[236];
	s[237] = m[237];
	s[238] = m[238];
	s[239] = m[239];
	s[240] = m[240];
	s[241] = m[241];
	s[242] = m[242];
	s[243] = m[243];
	s[244] = m[244];
	s[245] = m[245];
	s[246] = m[246];
	s[247] = m[247];
	s[248] = m[248];
	s[249] = m[249];
	s[250] = m[250];
	s[251] = m[251];
	s[252] = m[252];
	s[253] = m[253];
	s[254] = m[254];
	s[255] = m[255];
	s[256] = m[256];
	s[257] = m[257];
	s[258] = m[258];
	s[259] = m[259];
	s[260] = m[260];
	s[261] = m[261];
	s[262] = m[262];
	s[263] = m[263];
	s[264] = m[264];
	s[265] = m[265];
	s[266] = m[266];
	s[267] = m[267];
	s[268] = m[268];
	s[269] = m[269];
	s[270] = m[270];
	s[271] = m[271];
	s[272] = m[272];
	s[273] = m[273];
	s[274] = m[274];
	s[275] = m[275];
	dec_sel = s;
endfunction

function automatic pla_t ent_attr(input logic [8:0] ent, input logic hit);
	ent_attr = '0;
	case (ent)
		9'd0: ent_attr = '{1'b1, 9'd0, 10'd4, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR IMM_OP
		9'd1: ent_attr = '{1'b1, 9'd1, 10'd4, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND IMM_OP
		9'd2: ent_attr = '{1'b1, 9'd2, 10'd4, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB IMM_OP
		9'd3: ent_attr = '{1'b1, 9'd3, 10'd4, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD IMM_OP
		9'd4: ent_attr = '{1'b1, 9'd4, 10'd4, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR IMM_OP
		9'd5: ent_attr = '{1'b1, 9'd5, 10'd5, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'h7fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP IMM_CMP
		9'd6: ent_attr = '{1'b1, 9'd6, 10'd215, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b1, 6'd9, 10'd224, 1'b1, 1'b0, 2'd0, 1'b1};  // MOVES MOVES
		9'd7: ent_attr = '{1'b1, 9'd7, 10'd4, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR IMM_OP
		9'd8: ent_attr = '{1'b1, 9'd8, 10'd4, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND IMM_OP
		9'd9: ent_attr = '{1'b1, 9'd9, 10'd4, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB IMM_OP
		9'd10: ent_attr = '{1'b1, 9'd10, 10'd4, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD IMM_OP
		9'd11: ent_attr = '{1'b1, 9'd11, 10'd4, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR IMM_OP
		9'd12: ent_attr = '{1'b1, 9'd12, 10'd5, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'h7fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP IMM_CMP
		9'd13: ent_attr = '{1'b1, 9'd13, 10'd215, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b1, 6'd9, 10'd224, 1'b1, 1'b0, 2'd0, 1'b1};  // MOVES MOVES
		9'd14: ent_attr = '{1'b1, 9'd14, 10'd4, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR IMM_OP
		9'd15: ent_attr = '{1'b1, 9'd15, 10'd4, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND IMM_OP
		9'd16: ent_attr = '{1'b1, 9'd16, 10'd4, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB IMM_OP
		9'd17: ent_attr = '{1'b1, 9'd17, 10'd4, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD IMM_OP
		9'd18: ent_attr = '{1'b1, 9'd18, 10'd4, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR IMM_OP
		9'd19: ent_attr = '{1'b1, 9'd19, 10'd5, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'h7fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP IMM_CMP
		9'd20: ent_attr = '{1'b1, 9'd20, 10'd215, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b1, 6'd9, 10'd224, 1'b1, 1'b0, 2'd0, 1'b1};  // MOVES MOVES
		9'd21: ent_attr = '{1'b1, 9'd21, 10'd109, 7'd42, 4'd1, 1'b1, 5'h0, 2'd0, 12'h000, 12'h000, 2'd0, 3'd2, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ORSR CCR_LOG
		9'd22: ent_attr = '{1'b1, 9'd22, 10'd110, 7'd42, 4'd1, 1'b1, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // ORSR SR_LOG
		9'd23: ent_attr = '{1'b1, 9'd23, 10'd109, 7'd42, 4'd0, 1'b1, 5'h0, 2'd0, 12'h000, 12'h000, 2'd0, 3'd2, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ANDSR CCR_LOG
		9'd24: ent_attr = '{1'b1, 9'd24, 10'd110, 7'd42, 4'd0, 1'b1, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // ANDSR SR_LOG
		9'd25: ent_attr = '{1'b1, 9'd25, 10'd109, 7'd42, 4'd2, 1'b1, 5'h0, 2'd0, 12'h000, 12'h000, 2'd0, 3'd2, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EORSR CCR_LOG
		9'd26: ent_attr = '{1'b1, 9'd26, 10'd110, 7'd42, 4'd2, 1'b1, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // EORSR SR_LOG
		9'd27: ent_attr = '{1'b1, 9'd27, 10'd197, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'h7e4, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CHK2 CHK2
		9'd28: ent_attr = '{1'b1, 9'd28, 10'd197, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h7e4, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CHK2 CHK2
		9'd29: ent_attr = '{1'b1, 9'd29, 10'd197, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e4, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CHK2 CHK2
		9'd30: ent_attr = '{1'b1, 9'd30, 10'd187, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // CAS CAS
		9'd31: ent_attr = '{1'b1, 9'd31, 10'd187, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // CAS CAS
		9'd32: ent_attr = '{1'b1, 9'd32, 10'd187, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // CAS CAS
		9'd33: ent_attr = '{1'b1, 9'd33, 10'd189, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd2, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CAS2 CAS2
		9'd34: ent_attr = '{1'b1, 9'd34, 10'd189, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd2, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CAS2 CAS2
		9'd35: ent_attr = '{1'b1, 9'd35, 10'd42, 7'd30, 4'd0, 1'b0, 5'h0, 2'd0, 12'h7fd, 12'h000, 2'd0, 3'd2, 1'b0, 6'd5, 10'd44, 1'b1, 1'b0, 2'd0, 1'b0};  // BTST BTST_IMM
		9'd36: ent_attr = '{1'b1, 9'd36, 10'd36, 7'd31, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd2, 1'b0, 6'd5, 10'd38, 1'b1, 1'b0, 2'd0, 1'b0};  // BCHG BIT_IMM
		9'd37: ent_attr = '{1'b1, 9'd37, 10'd36, 7'd32, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd2, 1'b0, 6'd5, 10'd38, 1'b1, 1'b0, 2'd0, 1'b0};  // BCLR BIT_IMM
		9'd38: ent_attr = '{1'b1, 9'd38, 10'd36, 7'd33, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd2, 1'b0, 6'd5, 10'd38, 1'b1, 1'b0, 2'd0, 1'b0};  // BSET BIT_IMM
		9'd39: ent_attr = '{1'b1, 9'd39, 10'd45, 7'd30, 4'd0, 1'b0, 5'h0, 2'd0, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd5, 10'd47, 1'b1, 1'b0, 2'd0, 1'b0};  // BTST BTST_DYN
		9'd40: ent_attr = '{1'b1, 9'd40, 10'd39, 7'd31, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd5, 10'd41, 1'b1, 1'b0, 2'd0, 1'b0};  // BCHG BIT_DYN
		9'd41: ent_attr = '{1'b1, 9'd41, 10'd39, 7'd32, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd5, 10'd41, 1'b1, 1'b0, 2'd0, 1'b0};  // BCLR BIT_DYN
		9'd42: ent_attr = '{1'b1, 9'd42, 10'd39, 7'd33, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd5, 10'd41, 1'b1, 1'b0, 2'd0, 1'b0};  // BSET BIT_DYN
		9'd43: ent_attr = '{1'b1, 9'd43, 10'd133, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // MVPMR MOVEP_MR
		9'd44: ent_attr = '{1'b1, 9'd44, 10'd133, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // MVPMR MOVEP_MR
		9'd45: ent_attr = '{1'b1, 9'd45, 10'd143, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd10, 10'd147, 1'b0, 1'b0, 2'd0, 1'b0};  // MVPRM MOVEP_RM
		9'd46: ent_attr = '{1'b1, 9'd46, 10'd143, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd10, 10'd147, 1'b0, 1'b0, 2'd0, 1'b0};  // MVPRM MOVEP_RM
		9'd47: ent_attr = '{1'b1, 9'd47, 10'd32, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'hffd, 12'h1fd, 2'd0, 3'd0, 1'b0, 6'd12, 10'd34, 1'b1, 1'b1, 2'd0, 1'b0};  // MOVE MOVE
		9'd48: ent_attr = '{1'b1, 9'd48, 10'd32, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hfff, 12'h1fd, 2'd0, 3'd0, 1'b0, 6'd12, 10'd34, 1'b1, 1'b1, 2'd0, 1'b0};  // MOVE MOVE
		9'd49: ent_attr = '{1'b1, 9'd49, 10'd32, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h1fd, 2'd0, 3'd0, 1'b0, 6'd12, 10'd34, 1'b1, 1'b1, 2'd0, 1'b0};  // MOVE MOVE
		9'd50: ent_attr = '{1'b1, 9'd50, 10'd29, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd2, 10'd31, 1'b1, 1'b0, 2'd0, 1'b0};  // MOVEA MOVEA
		9'd51: ent_attr = '{1'b1, 9'd51, 10'd29, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd2, 10'd31, 1'b1, 1'b0, 2'd0, 1'b0};  // MOVEA MOVEA
		9'd52: ent_attr = '{1'b1, 9'd52, 10'd10, 7'd11, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEGX UNARY
		9'd53: ent_attr = '{1'b1, 9'd53, 10'd13, 7'd12, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CLR CLR_W
		9'd54: ent_attr = '{1'b1, 9'd54, 10'd10, 7'd10, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEG UNARY
		9'd55: ent_attr = '{1'b1, 9'd55, 10'd10, 7'd9, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NOT UNARY
		9'd56: ent_attr = '{1'b1, 9'd56, 10'd11, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // TST TST
		9'd57: ent_attr = '{1'b1, 9'd57, 10'd10, 7'd11, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEGX UNARY
		9'd58: ent_attr = '{1'b1, 9'd58, 10'd13, 7'd12, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CLR CLR_W
		9'd59: ent_attr = '{1'b1, 9'd59, 10'd10, 7'd10, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEG UNARY
		9'd60: ent_attr = '{1'b1, 9'd60, 10'd10, 7'd9, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NOT UNARY
		9'd61: ent_attr = '{1'b1, 9'd61, 10'd11, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // TST TST
		9'd62: ent_attr = '{1'b1, 9'd62, 10'd10, 7'd11, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEGX UNARY
		9'd63: ent_attr = '{1'b1, 9'd63, 10'd13, 7'd12, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CLR CLR_W
		9'd64: ent_attr = '{1'b1, 9'd64, 10'd10, 7'd10, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEG UNARY
		9'd65: ent_attr = '{1'b1, 9'd65, 10'd10, 7'd9, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NOT UNARY
		9'd66: ent_attr = '{1'b1, 9'd66, 10'd11, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // TST TST
		9'd67: ent_attr = '{1'b1, 9'd67, 10'd105, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // MVSR2 MOVE_FROM_SR
		9'd68: ent_attr = '{1'b1, 9'd68, 10'd106, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // MVSR2 MOVE_FROM_CCR
		9'd69: ent_attr = '{1'b1, 9'd69, 10'd107, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // MV2SR MOVE_TO_CCR
		9'd70: ent_attr = '{1'b1, 9'd70, 10'd108, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // MV2SR MOVE_TO_SR
		9'd71: ent_attr = '{1'b1, 9'd71, 10'd98, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd4, 1'b0, 6'd11, 10'd102, 1'b0, 1'b0, 2'd0, 1'b0};  // LINK LINK
		9'd72: ent_attr = '{1'b1, 9'd72, 10'd10, 7'd19, 4'd0, 1'b0, 5'h1f, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NBCD UNARY
		9'd73: ent_attr = '{1'b1, 9'd73, 10'd114, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // BKPT BKPT
		9'd74: ent_attr = '{1'b1, 9'd74, 10'd14, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SWAP SWAP
		9'd75: ent_attr = '{1'b1, 9'd75, 10'd27, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e4, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // PEA PEA
		9'd76: ent_attr = '{1'b1, 9'd76, 10'd15, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXT EXT
		9'd77: ent_attr = '{1'b1, 9'd77, 10'd15, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXT EXT
		9'd78: ent_attr = '{1'b1, 9'd78, 10'd16, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXT EXTB
		9'd79: ent_attr = '{1'b1, 9'd79, 10'd125, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h1f4, 12'h000, 2'd1, 3'd0, 1'b0, 6'd13, 10'd127, 1'b1, 1'b0, 2'd0, 1'b0};  // MVMLE MOVEM_RM
		9'd80: ent_attr = '{1'b1, 9'd80, 10'd125, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1f4, 12'h000, 2'd1, 3'd0, 1'b0, 6'd13, 10'd127, 1'b1, 1'b0, 2'd0, 1'b0};  // MVMLE MOVEM_RM
		9'd81: ent_attr = '{1'b1, 9'd81, 10'd128, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h7ec, 12'h000, 2'd1, 3'd0, 1'b0, 6'd13, 10'd130, 1'b1, 1'b0, 2'd0, 1'b0};  // MVMEL MOVEM_MR
		9'd82: ent_attr = '{1'b1, 9'd82, 10'd128, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7ec, 12'h000, 2'd1, 3'd0, 1'b0, 6'd13, 10'd130, 1'b1, 1'b0, 2'd0, 1'b0};  // MVMEL MOVEM_MR
		9'd83: ent_attr = '{1'b1, 9'd83, 10'd17, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // TAS TAS
		9'd84: ent_attr = '{1'b1, 9'd84, 10'd0, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ILLG ILLEGAL
		9'd85: ent_attr = '{1'b1, 9'd85, 10'd67, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hffd, 12'h000, 2'd1, 3'd0, 1'b0, 6'd15, 10'd69, 1'b1, 1'b0, 2'd0, 1'b0};  // MULL MULL
		9'd86: ent_attr = '{1'b1, 9'd86, 10'd72, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hffd, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // DIVL DIVL
		9'd87: ent_attr = '{1'b1, 9'd87, 10'd113, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // TRAP TRAP
		9'd88: ent_attr = '{1'b1, 9'd88, 10'd98, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd11, 10'd102, 1'b0, 1'b0, 2'd0, 1'b0};  // LINK LINK
		9'd89: ent_attr = '{1'b1, 9'd89, 10'd104, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // UNLK UNLK
		9'd90: ent_attr = '{1'b1, 9'd90, 10'd111, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // MVR2USP MOVE_TO_USP
		9'd91: ent_attr = '{1'b1, 9'd91, 10'd112, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // MVUSP2R MOVE_FROM_USP
		9'd92: ent_attr = '{1'b1, 9'd92, 10'd117, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // RESET RESET
		9'd93: ent_attr = '{1'b1, 9'd93, 10'd116, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // NOP NOP
		9'd94: ent_attr = '{1'b1, 9'd94, 10'd118, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // STOP STOP
		9'd95: ent_attr = '{1'b1, 9'd95, 10'd202, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // RTE RTE
		9'd96: ent_attr = '{1'b1, 9'd96, 10'd94, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // RTD RTD
		9'd97: ent_attr = '{1'b1, 9'd97, 10'd93, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // RTS RTS
		9'd98: ent_attr = '{1'b1, 9'd98, 10'd97, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // TRAPV TRAPV
		9'd99: ent_attr = '{1'b1, 9'd99, 10'd212, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // RTR RTR
		9'd100: ent_attr = '{1'b1, 9'd100, 10'd119, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd0, 1'b1, 6'd16, 10'd121, 1'b0, 1'b0, 2'd0, 1'b0};  // MOVEC2 MOVEC_RD
		9'd101: ent_attr = '{1'b1, 9'd101, 10'd122, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd0, 1'b1, 6'd16, 10'd124, 1'b0, 1'b0, 2'd0, 1'b1};  // MOVE2C MOVEC_WR
		9'd102: ent_attr = '{1'b1, 9'd102, 10'd90, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e4, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // JSR JSR
		9'd103: ent_attr = '{1'b1, 9'd103, 10'd89, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e4, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // JMP JMP
		9'd104: ent_attr = '{1'b1, 9'd104, 10'd76, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CHK CHK
		9'd105: ent_attr = '{1'b1, 9'd105, 10'd76, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CHK CHK
		9'd106: ent_attr = '{1'b1, 9'd106, 10'd26, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e4, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // LEA LEA
		9'd107: ent_attr = '{1'b1, 9'd107, 10'd8, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD QUICK
		9'd108: ent_attr = '{1'b1, 9'd108, 10'd8, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB QUICK
		9'd109: ent_attr = '{1'b1, 9'd109, 10'd8, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD QUICK
		9'd110: ent_attr = '{1'b1, 9'd110, 10'd8, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB QUICK
		9'd111: ent_attr = '{1'b1, 9'd111, 10'd8, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD QUICK
		9'd112: ent_attr = '{1'b1, 9'd112, 10'd8, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB QUICK
		9'd113: ent_attr = '{1'b1, 9'd113, 10'd24, 7'd1, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ADDA QUICK_A
		9'd114: ent_attr = '{1'b1, 9'd114, 10'd24, 7'd1, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ADDA QUICK_A
		9'd115: ent_attr = '{1'b1, 9'd115, 10'd25, 7'd3, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SUBA QUICK_SA
		9'd116: ent_attr = '{1'b1, 9'd116, 10'd25, 7'd3, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SUBA QUICK_SA
		9'd117: ent_attr = '{1'b1, 9'd117, 10'd12, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // Scc SCC
		9'd118: ent_attr = '{1'b1, 9'd118, 10'd88, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // DBcc DBCC
		9'd119: ent_attr = '{1'b1, 9'd119, 10'd96, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // TRAPcc TRAPCC
		9'd120: ent_attr = '{1'b1, 9'd120, 10'd96, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // TRAPcc TRAPCC
		9'd121: ent_attr = '{1'b1, 9'd121, 10'd96, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // TRAPcc TRAPCC
		9'd122: ent_attr = '{1'b1, 9'd122, 10'd87, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd5, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // BSR BSR
		9'd123: ent_attr = '{1'b1, 9'd123, 10'd86, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd5, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // Bcc BCC
		9'd124: ent_attr = '{1'b1, 9'd124, 10'd9, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // MOVE MOVEQ
		9'd125: ent_attr = '{1'b1, 9'd125, 10'd2, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_EA_DN
		9'd126: ent_attr = '{1'b1, 9'd126, 10'd3, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_DN_EA
		9'd127: ent_attr = '{1'b1, 9'd127, 10'd2, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_EA_DN
		9'd128: ent_attr = '{1'b1, 9'd128, 10'd3, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_DN_EA
		9'd129: ent_attr = '{1'b1, 9'd129, 10'd2, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_EA_DN
		9'd130: ent_attr = '{1'b1, 9'd130, 10'd3, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_DN_EA
		9'd131: ent_attr = '{1'b1, 9'd131, 10'd2, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_EA_DN
		9'd132: ent_attr = '{1'b1, 9'd132, 10'd3, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_DN_EA
		9'd133: ent_attr = '{1'b1, 9'd133, 10'd6, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP CMP_EA_DN
		9'd134: ent_attr = '{1'b1, 9'd134, 10'd3, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR OP_DN_EA
		9'd135: ent_attr = '{1'b1, 9'd135, 10'd53, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd1, 1'b0};  // CMPM CMPM
		9'd136: ent_attr = '{1'b1, 9'd136, 10'd50, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SUBX ADDX_R
		9'd137: ent_attr = '{1'b1, 9'd137, 10'd51, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // SUBX ADDX_M
		9'd138: ent_attr = '{1'b1, 9'd138, 10'd50, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ADDX ADDX_R
		9'd139: ent_attr = '{1'b1, 9'd139, 10'd51, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // ADDX ADDX_M
		9'd140: ent_attr = '{1'b1, 9'd140, 10'd2, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_EA_DN
		9'd141: ent_attr = '{1'b1, 9'd141, 10'd3, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_DN_EA
		9'd142: ent_attr = '{1'b1, 9'd142, 10'd2, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_EA_DN
		9'd143: ent_attr = '{1'b1, 9'd143, 10'd3, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_DN_EA
		9'd144: ent_attr = '{1'b1, 9'd144, 10'd2, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_EA_DN
		9'd145: ent_attr = '{1'b1, 9'd145, 10'd3, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_DN_EA
		9'd146: ent_attr = '{1'b1, 9'd146, 10'd2, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_EA_DN
		9'd147: ent_attr = '{1'b1, 9'd147, 10'd3, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_DN_EA
		9'd148: ent_attr = '{1'b1, 9'd148, 10'd6, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP CMP_EA_DN
		9'd149: ent_attr = '{1'b1, 9'd149, 10'd3, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR OP_DN_EA
		9'd150: ent_attr = '{1'b1, 9'd150, 10'd53, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd1, 1'b0};  // CMPM CMPM
		9'd151: ent_attr = '{1'b1, 9'd151, 10'd50, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SUBX ADDX_R
		9'd152: ent_attr = '{1'b1, 9'd152, 10'd51, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // SUBX ADDX_M
		9'd153: ent_attr = '{1'b1, 9'd153, 10'd50, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ADDX ADDX_R
		9'd154: ent_attr = '{1'b1, 9'd154, 10'd51, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // ADDX ADDX_M
		9'd155: ent_attr = '{1'b1, 9'd155, 10'd2, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_EA_DN
		9'd156: ent_attr = '{1'b1, 9'd156, 10'd3, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_DN_EA
		9'd157: ent_attr = '{1'b1, 9'd157, 10'd2, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_EA_DN
		9'd158: ent_attr = '{1'b1, 9'd158, 10'd3, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_DN_EA
		9'd159: ent_attr = '{1'b1, 9'd159, 10'd2, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_EA_DN
		9'd160: ent_attr = '{1'b1, 9'd160, 10'd3, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_DN_EA
		9'd161: ent_attr = '{1'b1, 9'd161, 10'd2, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_EA_DN
		9'd162: ent_attr = '{1'b1, 9'd162, 10'd3, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_DN_EA
		9'd163: ent_attr = '{1'b1, 9'd163, 10'd6, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP CMP_EA_DN
		9'd164: ent_attr = '{1'b1, 9'd164, 10'd3, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR OP_DN_EA
		9'd165: ent_attr = '{1'b1, 9'd165, 10'd53, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd1, 1'b0};  // CMPM CMPM
		9'd166: ent_attr = '{1'b1, 9'd166, 10'd50, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SUBX ADDX_R
		9'd167: ent_attr = '{1'b1, 9'd167, 10'd51, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // SUBX ADDX_M
		9'd168: ent_attr = '{1'b1, 9'd168, 10'd50, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ADDX ADDX_R
		9'd169: ent_attr = '{1'b1, 9'd169, 10'd51, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // ADDX ADDX_M
		9'd170: ent_attr = '{1'b1, 9'd170, 10'd66, 7'd49, 4'd0, 1'b0, 5'hf, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // DIVU DIVW
		9'd171: ent_attr = '{1'b1, 9'd171, 10'd66, 7'd49, 4'd1, 1'b1, 5'hf, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // DIVS DIVW
		9'd172: ent_attr = '{1'b1, 9'd172, 10'd65, 7'd48, 4'd0, 1'b0, 5'hf, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // MULU MULW
		9'd173: ent_attr = '{1'b1, 9'd173, 10'd65, 7'd48, 4'd1, 1'b1, 5'hf, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // MULS MULW
		9'd174: ent_attr = '{1'b1, 9'd174, 10'd50, 7'd18, 4'd0, 1'b0, 5'h1f, 2'd0, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SBCD ADDX_R
		9'd175: ent_attr = '{1'b1, 9'd175, 10'd51, 7'd18, 4'd0, 1'b0, 5'h1f, 2'd0, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // SBCD ADDX_M
		9'd176: ent_attr = '{1'b1, 9'd176, 10'd50, 7'd17, 4'd0, 1'b0, 5'h1f, 2'd0, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ABCD ADDX_R
		9'd177: ent_attr = '{1'b1, 9'd177, 10'd51, 7'd17, 4'd0, 1'b0, 5'h1f, 2'd0, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // ABCD ADDX_M
		9'd178: ent_attr = '{1'b1, 9'd178, 10'd55, 7'd20, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // PACK PACK_R
		9'd179: ent_attr = '{1'b1, 9'd179, 10'd57, 7'd20, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // PACK PACK_M
		9'd180: ent_attr = '{1'b1, 9'd180, 10'd60, 7'd21, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // UNPK UNPK_R
		9'd181: ent_attr = '{1'b1, 9'd181, 10'd62, 7'd21, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // UNPK UNPK_M
		9'd182: ent_attr = '{1'b1, 9'd182, 10'd21, 7'd3, 4'd0, 1'b0, 5'h0, 2'd1, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd7, 10'd23, 1'b1, 1'b0, 2'd0, 1'b0};  // SUBA SUBA
		9'd183: ent_attr = '{1'b1, 9'd183, 10'd21, 7'd3, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd7, 10'd23, 1'b1, 1'b0, 2'd0, 1'b0};  // SUBA SUBA
		9'd184: ent_attr = '{1'b1, 9'd184, 10'd18, 7'd1, 4'd0, 1'b0, 5'h0, 2'd1, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd2, 10'd20, 1'b1, 1'b0, 2'd0, 1'b0};  // ADDA ADDA
		9'd185: ent_attr = '{1'b1, 9'd185, 10'd18, 7'd1, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd2, 10'd20, 1'b1, 1'b0, 2'd0, 1'b0};  // ADDA ADDA
		9'd186: ent_attr = '{1'b1, 9'd186, 10'd7, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMPA CMPA
		9'd187: ent_attr = '{1'b1, 9'd187, 10'd7, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMPA CMPA
		9'd188: ent_attr = '{1'b1, 9'd188, 10'd77, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXG EXG_DD
		9'd189: ent_attr = '{1'b1, 9'd189, 10'd80, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXG EXG_AA
		9'd190: ent_attr = '{1'b1, 9'd190, 10'd83, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXG EXG_DA
		9'd191: ent_attr = '{1'b1, 9'd191, 10'd48, 7'd23, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASR SHIFT_R
		9'd192: ent_attr = '{1'b1, 9'd192, 10'd48, 7'd22, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASL SHIFT_R
		9'd193: ent_attr = '{1'b1, 9'd193, 10'd48, 7'd25, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSR SHIFT_R
		9'd194: ent_attr = '{1'b1, 9'd194, 10'd48, 7'd24, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSL SHIFT_R
		9'd195: ent_attr = '{1'b1, 9'd195, 10'd48, 7'd29, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXR SHIFT_R
		9'd196: ent_attr = '{1'b1, 9'd196, 10'd48, 7'd28, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXL SHIFT_R
		9'd197: ent_attr = '{1'b1, 9'd197, 10'd48, 7'd27, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROR SHIFT_R
		9'd198: ent_attr = '{1'b1, 9'd198, 10'd48, 7'd26, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROL SHIFT_R
		9'd199: ent_attr = '{1'b1, 9'd199, 10'd48, 7'd23, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASR SHIFT_R
		9'd200: ent_attr = '{1'b1, 9'd200, 10'd48, 7'd22, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASL SHIFT_R
		9'd201: ent_attr = '{1'b1, 9'd201, 10'd48, 7'd25, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSR SHIFT_R
		9'd202: ent_attr = '{1'b1, 9'd202, 10'd48, 7'd24, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSL SHIFT_R
		9'd203: ent_attr = '{1'b1, 9'd203, 10'd48, 7'd29, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXR SHIFT_R
		9'd204: ent_attr = '{1'b1, 9'd204, 10'd48, 7'd28, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXL SHIFT_R
		9'd205: ent_attr = '{1'b1, 9'd205, 10'd48, 7'd27, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROR SHIFT_R
		9'd206: ent_attr = '{1'b1, 9'd206, 10'd48, 7'd26, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROL SHIFT_R
		9'd207: ent_attr = '{1'b1, 9'd207, 10'd48, 7'd23, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASR SHIFT_R
		9'd208: ent_attr = '{1'b1, 9'd208, 10'd48, 7'd22, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASL SHIFT_R
		9'd209: ent_attr = '{1'b1, 9'd209, 10'd48, 7'd25, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSR SHIFT_R
		9'd210: ent_attr = '{1'b1, 9'd210, 10'd48, 7'd24, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSL SHIFT_R
		9'd211: ent_attr = '{1'b1, 9'd211, 10'd48, 7'd29, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXR SHIFT_R
		9'd212: ent_attr = '{1'b1, 9'd212, 10'd48, 7'd28, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXL SHIFT_R
		9'd213: ent_attr = '{1'b1, 9'd213, 10'd48, 7'd27, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROR SHIFT_R
		9'd214: ent_attr = '{1'b1, 9'd214, 10'd48, 7'd26, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROL SHIFT_R
		9'd215: ent_attr = '{1'b1, 9'd215, 10'd49, 7'd23, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ASRW SHIFT_M
		9'd216: ent_attr = '{1'b1, 9'd216, 10'd49, 7'd22, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ASLW SHIFT_M
		9'd217: ent_attr = '{1'b1, 9'd217, 10'd49, 7'd25, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // LSRW SHIFT_M
		9'd218: ent_attr = '{1'b1, 9'd218, 10'd49, 7'd24, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // LSLW SHIFT_M
		9'd219: ent_attr = '{1'b1, 9'd219, 10'd49, 7'd29, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ROXRW SHIFT_M
		9'd220: ent_attr = '{1'b1, 9'd220, 10'd49, 7'd28, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ROXLW SHIFT_M
		9'd221: ent_attr = '{1'b1, 9'd221, 10'd49, 7'd27, 4'd0, 1'b0, 5'hf, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // RORW SHIFT_M
		9'd222: ent_attr = '{1'b1, 9'd222, 10'd49, 7'd26, 4'd0, 1'b0, 5'hf, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ROLW SHIFT_M
		9'd223: ent_attr = '{1'b1, 9'd223, 10'd154, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd162, 1'b1, 1'b0, 2'd0, 1'b0};  // BFTST BF_TST
		9'd224: ent_attr = '{1'b1, 9'd224, 10'd164, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd172, 1'b1, 1'b0, 2'd0, 1'b0};  // BFEXTU BF_EXT
		9'd225: ent_attr = '{1'b1, 9'd225, 10'd174, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd185, 1'b1, 1'b0, 2'd0, 1'b0};  // BFCHG BF_MOD
		9'd226: ent_attr = '{1'b1, 9'd226, 10'd164, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd172, 1'b1, 1'b0, 2'd0, 1'b0};  // BFEXTS BF_EXT
		9'd227: ent_attr = '{1'b1, 9'd227, 10'd174, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd185, 1'b1, 1'b0, 2'd0, 1'b0};  // BFCLR BF_MOD
		9'd228: ent_attr = '{1'b1, 9'd228, 10'd164, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd172, 1'b1, 1'b0, 2'd0, 1'b0};  // BFFFO BF_EXT
		9'd229: ent_attr = '{1'b1, 9'd229, 10'd174, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd185, 1'b1, 1'b0, 2'd0, 1'b0};  // BFSET BF_MOD
		9'd230: ent_attr = '{1'b1, 9'd230, 10'd174, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd185, 1'b1, 1'b0, 2'd0, 1'b0};  // BFINS BF_MOD
		9'd231: ent_attr = '{1'b1, 9'd231, 10'd228, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h000, 2'd1, 3'd0, 1'b0, 6'd19, 10'd237, 1'b1, 1'b0, 2'd0, 1'b0};  // FPP FPU_GEN
		9'd232: ent_attr = '{1'b1, 9'd232, 10'd482, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // FScc FSCC
		9'd233: ent_attr = '{1'b1, 9'd233, 10'd484, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd1, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // FDBcc FDBCC
		9'd234: ent_attr = '{1'b1, 9'd234, 10'd486, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // FTRAPcc FTRAPCC
		9'd235: ent_attr = '{1'b1, 9'd235, 10'd486, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // FTRAPcc FTRAPCC
		9'd236: ent_attr = '{1'b1, 9'd236, 10'd486, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // FTRAPcc FTRAPCC
		9'd237: ent_attr = '{1'b1, 9'd237, 10'd480, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd7, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // FBcc FBCC
		9'd238: ent_attr = '{1'b1, 9'd238, 10'd480, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd7, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // FBcc FBCC
		9'd239: ent_attr = '{1'b1, 9'd239, 10'd488, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1f4, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // FSAVE FSAVE
		9'd240: ent_attr = '{1'b1, 9'd240, 10'd546, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7ec, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // FRESTORE FRESTORE
		9'd241: ent_attr = '{1'b1, 9'd241, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVL CACHE_OP
		9'd242: ent_attr = '{1'b1, 9'd242, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVP CACHE_OP
		9'd243: ent_attr = '{1'b1, 9'd243, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVA CACHE_OP
		9'd244: ent_attr = '{1'b1, 9'd244, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHL CACHE_OP
		9'd245: ent_attr = '{1'b1, 9'd245, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHP CACHE_OP
		9'd246: ent_attr = '{1'b1, 9'd246, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHA CACHE_OP
		9'd247: ent_attr = '{1'b1, 9'd247, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVL CACHE_OP
		9'd248: ent_attr = '{1'b1, 9'd248, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVP CACHE_OP
		9'd249: ent_attr = '{1'b1, 9'd249, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVA CACHE_OP
		9'd250: ent_attr = '{1'b1, 9'd250, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHL CACHE_OP
		9'd251: ent_attr = '{1'b1, 9'd251, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHP CACHE_OP
		9'd252: ent_attr = '{1'b1, 9'd252, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHA CACHE_OP
		9'd253: ent_attr = '{1'b1, 9'd253, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVL CACHE_OP
		9'd254: ent_attr = '{1'b1, 9'd254, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVP CACHE_OP
		9'd255: ent_attr = '{1'b1, 9'd255, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVA CACHE_OP
		9'd256: ent_attr = '{1'b1, 9'd256, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHL CACHE_OP
		9'd257: ent_attr = '{1'b1, 9'd257, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHP CACHE_OP
		9'd258: ent_attr = '{1'b1, 9'd258, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHA CACHE_OP
		9'd259: ent_attr = '{1'b1, 9'd259, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVL CACHE_OP
		9'd260: ent_attr = '{1'b1, 9'd260, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVP CACHE_OP
		9'd261: ent_attr = '{1'b1, 9'd261, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVA CACHE_OP
		9'd262: ent_attr = '{1'b1, 9'd262, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHL CACHE_OP
		9'd263: ent_attr = '{1'b1, 9'd263, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHP CACHE_OP
		9'd264: ent_attr = '{1'b1, 9'd264, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHA CACHE_OP
		9'd265: ent_attr = '{1'b1, 9'd265, 10'd226, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PFLUSHN PFLUSH
		9'd266: ent_attr = '{1'b1, 9'd266, 10'd226, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PFLUSH PFLUSH
		9'd267: ent_attr = '{1'b1, 9'd267, 10'd226, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PFLUSHAN PFLUSH
		9'd268: ent_attr = '{1'b1, 9'd268, 10'd226, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PFLUSHA PFLUSH
		9'd269: ent_attr = '{1'b1, 9'd269, 10'd227, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PTESTW PTEST
		9'd270: ent_attr = '{1'b1, 9'd270, 10'd227, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PTESTR PTEST
		9'd271: ent_attr = '{1'b1, 9'd271, 10'd131, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd4, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd3, 1'b0};  // MOVE16 MOVE16
		9'd272: ent_attr = '{1'b1, 9'd272, 10'd131, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd4, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd3, 1'b0};  // MOVE16 MOVE16
		9'd273: ent_attr = '{1'b1, 9'd273, 10'd131, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd4, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd3, 1'b0};  // MOVE16 MOVE16
		9'd274: ent_attr = '{1'b1, 9'd274, 10'd131, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd4, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd3, 1'b0};  // MOVE16 MOVE16
		9'd275: ent_attr = '{1'b1, 9'd275, 10'd131, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd3, 1'b0};  // MOVE16 MOVE16
		default: ;
	endcase
	if (!hit) ent_attr = '0;
endfunction

function automatic pla_t ent_attr_oh(input logic [NENT-1:0] s);
	pla_t a;
	a = '0;
	if (s[0]) a = a | {1'b1, 9'd0, 10'd4, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR IMM_OP
	if (s[1]) a = a | {1'b1, 9'd1, 10'd4, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND IMM_OP
	if (s[2]) a = a | {1'b1, 9'd2, 10'd4, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB IMM_OP
	if (s[3]) a = a | {1'b1, 9'd3, 10'd4, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD IMM_OP
	if (s[4]) a = a | {1'b1, 9'd4, 10'd4, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR IMM_OP
	if (s[5]) a = a | {1'b1, 9'd5, 10'd5, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'h7fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP IMM_CMP
	if (s[6]) a = a | {1'b1, 9'd6, 10'd215, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b1, 6'd9, 10'd224, 1'b1, 1'b0, 2'd0, 1'b1};  // MOVES MOVES
	if (s[7]) a = a | {1'b1, 9'd7, 10'd4, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR IMM_OP
	if (s[8]) a = a | {1'b1, 9'd8, 10'd4, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND IMM_OP
	if (s[9]) a = a | {1'b1, 9'd9, 10'd4, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB IMM_OP
	if (s[10]) a = a | {1'b1, 9'd10, 10'd4, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD IMM_OP
	if (s[11]) a = a | {1'b1, 9'd11, 10'd4, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR IMM_OP
	if (s[12]) a = a | {1'b1, 9'd12, 10'd5, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'h7fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP IMM_CMP
	if (s[13]) a = a | {1'b1, 9'd13, 10'd215, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b1, 6'd9, 10'd224, 1'b1, 1'b0, 2'd0, 1'b1};  // MOVES MOVES
	if (s[14]) a = a | {1'b1, 9'd14, 10'd4, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR IMM_OP
	if (s[15]) a = a | {1'b1, 9'd15, 10'd4, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND IMM_OP
	if (s[16]) a = a | {1'b1, 9'd16, 10'd4, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB IMM_OP
	if (s[17]) a = a | {1'b1, 9'd17, 10'd4, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD IMM_OP
	if (s[18]) a = a | {1'b1, 9'd18, 10'd4, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR IMM_OP
	if (s[19]) a = a | {1'b1, 9'd19, 10'd5, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'h7fd, 12'h000, 2'd0, 3'd1, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP IMM_CMP
	if (s[20]) a = a | {1'b1, 9'd20, 10'd215, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b1, 6'd9, 10'd224, 1'b1, 1'b0, 2'd0, 1'b1};  // MOVES MOVES
	if (s[21]) a = a | {1'b1, 9'd21, 10'd109, 7'd42, 4'd1, 1'b1, 5'h0, 2'd0, 12'h000, 12'h000, 2'd0, 3'd2, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ORSR CCR_LOG
	if (s[22]) a = a | {1'b1, 9'd22, 10'd110, 7'd42, 4'd1, 1'b1, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // ORSR SR_LOG
	if (s[23]) a = a | {1'b1, 9'd23, 10'd109, 7'd42, 4'd0, 1'b1, 5'h0, 2'd0, 12'h000, 12'h000, 2'd0, 3'd2, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ANDSR CCR_LOG
	if (s[24]) a = a | {1'b1, 9'd24, 10'd110, 7'd42, 4'd0, 1'b1, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // ANDSR SR_LOG
	if (s[25]) a = a | {1'b1, 9'd25, 10'd109, 7'd42, 4'd2, 1'b1, 5'h0, 2'd0, 12'h000, 12'h000, 2'd0, 3'd2, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EORSR CCR_LOG
	if (s[26]) a = a | {1'b1, 9'd26, 10'd110, 7'd42, 4'd2, 1'b1, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // EORSR SR_LOG
	if (s[27]) a = a | {1'b1, 9'd27, 10'd197, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'h7e4, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CHK2 CHK2
	if (s[28]) a = a | {1'b1, 9'd28, 10'd197, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h7e4, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CHK2 CHK2
	if (s[29]) a = a | {1'b1, 9'd29, 10'd197, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e4, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CHK2 CHK2
	if (s[30]) a = a | {1'b1, 9'd30, 10'd187, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // CAS CAS
	if (s[31]) a = a | {1'b1, 9'd31, 10'd187, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // CAS CAS
	if (s[32]) a = a | {1'b1, 9'd32, 10'd187, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1fc, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // CAS CAS
	if (s[33]) a = a | {1'b1, 9'd33, 10'd189, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd2, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CAS2 CAS2
	if (s[34]) a = a | {1'b1, 9'd34, 10'd189, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd2, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CAS2 CAS2
	if (s[35]) a = a | {1'b1, 9'd35, 10'd42, 7'd30, 4'd0, 1'b0, 5'h0, 2'd0, 12'h7fd, 12'h000, 2'd0, 3'd2, 1'b0, 6'd5, 10'd44, 1'b1, 1'b0, 2'd0, 1'b0};  // BTST BTST_IMM
	if (s[36]) a = a | {1'b1, 9'd36, 10'd36, 7'd31, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd2, 1'b0, 6'd5, 10'd38, 1'b1, 1'b0, 2'd0, 1'b0};  // BCHG BIT_IMM
	if (s[37]) a = a | {1'b1, 9'd37, 10'd36, 7'd32, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd2, 1'b0, 6'd5, 10'd38, 1'b1, 1'b0, 2'd0, 1'b0};  // BCLR BIT_IMM
	if (s[38]) a = a | {1'b1, 9'd38, 10'd36, 7'd33, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd2, 1'b0, 6'd5, 10'd38, 1'b1, 1'b0, 2'd0, 1'b0};  // BSET BIT_IMM
	if (s[39]) a = a | {1'b1, 9'd39, 10'd45, 7'd30, 4'd0, 1'b0, 5'h0, 2'd0, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd5, 10'd47, 1'b1, 1'b0, 2'd0, 1'b0};  // BTST BTST_DYN
	if (s[40]) a = a | {1'b1, 9'd40, 10'd39, 7'd31, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd5, 10'd41, 1'b1, 1'b0, 2'd0, 1'b0};  // BCHG BIT_DYN
	if (s[41]) a = a | {1'b1, 9'd41, 10'd39, 7'd32, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd5, 10'd41, 1'b1, 1'b0, 2'd0, 1'b0};  // BCLR BIT_DYN
	if (s[42]) a = a | {1'b1, 9'd42, 10'd39, 7'd33, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd5, 10'd41, 1'b1, 1'b0, 2'd0, 1'b0};  // BSET BIT_DYN
	if (s[43]) a = a | {1'b1, 9'd43, 10'd133, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // MVPMR MOVEP_MR
	if (s[44]) a = a | {1'b1, 9'd44, 10'd133, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // MVPMR MOVEP_MR
	if (s[45]) a = a | {1'b1, 9'd45, 10'd143, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd10, 10'd147, 1'b0, 1'b0, 2'd0, 1'b0};  // MVPRM MOVEP_RM
	if (s[46]) a = a | {1'b1, 9'd46, 10'd143, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd10, 10'd147, 1'b0, 1'b0, 2'd0, 1'b0};  // MVPRM MOVEP_RM
	if (s[47]) a = a | {1'b1, 9'd47, 10'd32, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'hffd, 12'h1fd, 2'd0, 3'd0, 1'b0, 6'd12, 10'd34, 1'b1, 1'b1, 2'd0, 1'b0};  // MOVE MOVE
	if (s[48]) a = a | {1'b1, 9'd48, 10'd32, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hfff, 12'h1fd, 2'd0, 3'd0, 1'b0, 6'd12, 10'd34, 1'b1, 1'b1, 2'd0, 1'b0};  // MOVE MOVE
	if (s[49]) a = a | {1'b1, 9'd49, 10'd32, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h1fd, 2'd0, 3'd0, 1'b0, 6'd12, 10'd34, 1'b1, 1'b1, 2'd0, 1'b0};  // MOVE MOVE
	if (s[50]) a = a | {1'b1, 9'd50, 10'd29, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd2, 10'd31, 1'b1, 1'b0, 2'd0, 1'b0};  // MOVEA MOVEA
	if (s[51]) a = a | {1'b1, 9'd51, 10'd29, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd2, 10'd31, 1'b1, 1'b0, 2'd0, 1'b0};  // MOVEA MOVEA
	if (s[52]) a = a | {1'b1, 9'd52, 10'd10, 7'd11, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEGX UNARY
	if (s[53]) a = a | {1'b1, 9'd53, 10'd13, 7'd12, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CLR CLR_W
	if (s[54]) a = a | {1'b1, 9'd54, 10'd10, 7'd10, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEG UNARY
	if (s[55]) a = a | {1'b1, 9'd55, 10'd10, 7'd9, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NOT UNARY
	if (s[56]) a = a | {1'b1, 9'd56, 10'd11, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // TST TST
	if (s[57]) a = a | {1'b1, 9'd57, 10'd10, 7'd11, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEGX UNARY
	if (s[58]) a = a | {1'b1, 9'd58, 10'd13, 7'd12, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CLR CLR_W
	if (s[59]) a = a | {1'b1, 9'd59, 10'd10, 7'd10, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEG UNARY
	if (s[60]) a = a | {1'b1, 9'd60, 10'd10, 7'd9, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NOT UNARY
	if (s[61]) a = a | {1'b1, 9'd61, 10'd11, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // TST TST
	if (s[62]) a = a | {1'b1, 9'd62, 10'd10, 7'd11, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEGX UNARY
	if (s[63]) a = a | {1'b1, 9'd63, 10'd13, 7'd12, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CLR CLR_W
	if (s[64]) a = a | {1'b1, 9'd64, 10'd10, 7'd10, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NEG UNARY
	if (s[65]) a = a | {1'b1, 9'd65, 10'd10, 7'd9, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NOT UNARY
	if (s[66]) a = a | {1'b1, 9'd66, 10'd11, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // TST TST
	if (s[67]) a = a | {1'b1, 9'd67, 10'd105, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // MVSR2 MOVE_FROM_SR
	if (s[68]) a = a | {1'b1, 9'd68, 10'd106, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // MVSR2 MOVE_FROM_CCR
	if (s[69]) a = a | {1'b1, 9'd69, 10'd107, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // MV2SR MOVE_TO_CCR
	if (s[70]) a = a | {1'b1, 9'd70, 10'd108, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // MV2SR MOVE_TO_SR
	if (s[71]) a = a | {1'b1, 9'd71, 10'd98, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd4, 1'b0, 6'd11, 10'd102, 1'b0, 1'b0, 2'd0, 1'b0};  // LINK LINK
	if (s[72]) a = a | {1'b1, 9'd72, 10'd10, 7'd19, 4'd0, 1'b0, 5'h1f, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // NBCD UNARY
	if (s[73]) a = a | {1'b1, 9'd73, 10'd114, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // BKPT BKPT
	if (s[74]) a = a | {1'b1, 9'd74, 10'd14, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SWAP SWAP
	if (s[75]) a = a | {1'b1, 9'd75, 10'd27, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e4, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // PEA PEA
	if (s[76]) a = a | {1'b1, 9'd76, 10'd15, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXT EXT
	if (s[77]) a = a | {1'b1, 9'd77, 10'd15, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXT EXT
	if (s[78]) a = a | {1'b1, 9'd78, 10'd16, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXT EXTB
	if (s[79]) a = a | {1'b1, 9'd79, 10'd125, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h1f4, 12'h000, 2'd1, 3'd0, 1'b0, 6'd13, 10'd127, 1'b1, 1'b0, 2'd0, 1'b0};  // MVMLE MOVEM_RM
	if (s[80]) a = a | {1'b1, 9'd80, 10'd125, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1f4, 12'h000, 2'd1, 3'd0, 1'b0, 6'd13, 10'd127, 1'b1, 1'b0, 2'd0, 1'b0};  // MVMLE MOVEM_RM
	if (s[81]) a = a | {1'b1, 9'd81, 10'd128, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h7ec, 12'h000, 2'd1, 3'd0, 1'b0, 6'd13, 10'd130, 1'b1, 1'b0, 2'd0, 1'b0};  // MVMEL MOVEM_MR
	if (s[82]) a = a | {1'b1, 9'd82, 10'd128, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7ec, 12'h000, 2'd1, 3'd0, 1'b0, 6'd13, 10'd130, 1'b1, 1'b0, 2'd0, 1'b0};  // MVMEL MOVEM_MR
	if (s[83]) a = a | {1'b1, 9'd83, 10'd17, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // TAS TAS
	if (s[84]) a = a | {1'b1, 9'd84, 10'd0, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ILLG ILLEGAL
	if (s[85]) a = a | {1'b1, 9'd85, 10'd67, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hffd, 12'h000, 2'd1, 3'd0, 1'b0, 6'd15, 10'd69, 1'b1, 1'b0, 2'd0, 1'b0};  // MULL MULL
	if (s[86]) a = a | {1'b1, 9'd86, 10'd72, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hffd, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // DIVL DIVL
	if (s[87]) a = a | {1'b1, 9'd87, 10'd113, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // TRAP TRAP
	if (s[88]) a = a | {1'b1, 9'd88, 10'd98, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd11, 10'd102, 1'b0, 1'b0, 2'd0, 1'b0};  // LINK LINK
	if (s[89]) a = a | {1'b1, 9'd89, 10'd104, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // UNLK UNLK
	if (s[90]) a = a | {1'b1, 9'd90, 10'd111, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // MVR2USP MOVE_TO_USP
	if (s[91]) a = a | {1'b1, 9'd91, 10'd112, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // MVUSP2R MOVE_FROM_USP
	if (s[92]) a = a | {1'b1, 9'd92, 10'd117, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // RESET RESET
	if (s[93]) a = a | {1'b1, 9'd93, 10'd116, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // NOP NOP
	if (s[94]) a = a | {1'b1, 9'd94, 10'd118, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // STOP STOP
	if (s[95]) a = a | {1'b1, 9'd95, 10'd202, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // RTE RTE
	if (s[96]) a = a | {1'b1, 9'd96, 10'd94, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // RTD RTD
	if (s[97]) a = a | {1'b1, 9'd97, 10'd93, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // RTS RTS
	if (s[98]) a = a | {1'b1, 9'd98, 10'd97, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // TRAPV TRAPV
	if (s[99]) a = a | {1'b1, 9'd99, 10'd212, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // RTR RTR
	if (s[100]) a = a | {1'b1, 9'd100, 10'd119, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd0, 1'b1, 6'd16, 10'd121, 1'b0, 1'b0, 2'd0, 1'b0};  // MOVEC2 MOVEC_RD
	if (s[101]) a = a | {1'b1, 9'd101, 10'd122, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd0, 1'b1, 6'd16, 10'd124, 1'b0, 1'b0, 2'd0, 1'b1};  // MOVE2C MOVEC_WR
	if (s[102]) a = a | {1'b1, 9'd102, 10'd90, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e4, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // JSR JSR
	if (s[103]) a = a | {1'b1, 9'd103, 10'd89, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e4, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // JMP JMP
	if (s[104]) a = a | {1'b1, 9'd104, 10'd76, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CHK CHK
	if (s[105]) a = a | {1'b1, 9'd105, 10'd76, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CHK CHK
	if (s[106]) a = a | {1'b1, 9'd106, 10'd26, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e4, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // LEA LEA
	if (s[107]) a = a | {1'b1, 9'd107, 10'd8, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD QUICK
	if (s[108]) a = a | {1'b1, 9'd108, 10'd8, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB QUICK
	if (s[109]) a = a | {1'b1, 9'd109, 10'd8, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD QUICK
	if (s[110]) a = a | {1'b1, 9'd110, 10'd8, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB QUICK
	if (s[111]) a = a | {1'b1, 9'd111, 10'd8, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD QUICK
	if (s[112]) a = a | {1'b1, 9'd112, 10'd8, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB QUICK
	if (s[113]) a = a | {1'b1, 9'd113, 10'd24, 7'd1, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ADDA QUICK_A
	if (s[114]) a = a | {1'b1, 9'd114, 10'd24, 7'd1, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ADDA QUICK_A
	if (s[115]) a = a | {1'b1, 9'd115, 10'd25, 7'd3, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SUBA QUICK_SA
	if (s[116]) a = a | {1'b1, 9'd116, 10'd25, 7'd3, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SUBA QUICK_SA
	if (s[117]) a = a | {1'b1, 9'd117, 10'd12, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // Scc SCC
	if (s[118]) a = a | {1'b1, 9'd118, 10'd88, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // DBcc DBCC
	if (s[119]) a = a | {1'b1, 9'd119, 10'd96, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // TRAPcc TRAPCC
	if (s[120]) a = a | {1'b1, 9'd120, 10'd96, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // TRAPcc TRAPCC
	if (s[121]) a = a | {1'b1, 9'd121, 10'd96, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // TRAPcc TRAPCC
	if (s[122]) a = a | {1'b1, 9'd122, 10'd87, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd5, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // BSR BSR
	if (s[123]) a = a | {1'b1, 9'd123, 10'd86, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd5, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // Bcc BCC
	if (s[124]) a = a | {1'b1, 9'd124, 10'd9, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // MOVE MOVEQ
	if (s[125]) a = a | {1'b1, 9'd125, 10'd2, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_EA_DN
	if (s[126]) a = a | {1'b1, 9'd126, 10'd3, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_DN_EA
	if (s[127]) a = a | {1'b1, 9'd127, 10'd2, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_EA_DN
	if (s[128]) a = a | {1'b1, 9'd128, 10'd3, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_DN_EA
	if (s[129]) a = a | {1'b1, 9'd129, 10'd2, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_EA_DN
	if (s[130]) a = a | {1'b1, 9'd130, 10'd3, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_DN_EA
	if (s[131]) a = a | {1'b1, 9'd131, 10'd2, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_EA_DN
	if (s[132]) a = a | {1'b1, 9'd132, 10'd3, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_DN_EA
	if (s[133]) a = a | {1'b1, 9'd133, 10'd6, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP CMP_EA_DN
	if (s[134]) a = a | {1'b1, 9'd134, 10'd3, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR OP_DN_EA
	if (s[135]) a = a | {1'b1, 9'd135, 10'd53, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd1, 1'b0};  // CMPM CMPM
	if (s[136]) a = a | {1'b1, 9'd136, 10'd50, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SUBX ADDX_R
	if (s[137]) a = a | {1'b1, 9'd137, 10'd51, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // SUBX ADDX_M
	if (s[138]) a = a | {1'b1, 9'd138, 10'd50, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ADDX ADDX_R
	if (s[139]) a = a | {1'b1, 9'd139, 10'd51, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // ADDX ADDX_M
	if (s[140]) a = a | {1'b1, 9'd140, 10'd2, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_EA_DN
	if (s[141]) a = a | {1'b1, 9'd141, 10'd3, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_DN_EA
	if (s[142]) a = a | {1'b1, 9'd142, 10'd2, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_EA_DN
	if (s[143]) a = a | {1'b1, 9'd143, 10'd3, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_DN_EA
	if (s[144]) a = a | {1'b1, 9'd144, 10'd2, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_EA_DN
	if (s[145]) a = a | {1'b1, 9'd145, 10'd3, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_DN_EA
	if (s[146]) a = a | {1'b1, 9'd146, 10'd2, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_EA_DN
	if (s[147]) a = a | {1'b1, 9'd147, 10'd3, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_DN_EA
	if (s[148]) a = a | {1'b1, 9'd148, 10'd6, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP CMP_EA_DN
	if (s[149]) a = a | {1'b1, 9'd149, 10'd3, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR OP_DN_EA
	if (s[150]) a = a | {1'b1, 9'd150, 10'd53, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd1, 1'b0};  // CMPM CMPM
	if (s[151]) a = a | {1'b1, 9'd151, 10'd50, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SUBX ADDX_R
	if (s[152]) a = a | {1'b1, 9'd152, 10'd51, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // SUBX ADDX_M
	if (s[153]) a = a | {1'b1, 9'd153, 10'd50, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ADDX ADDX_R
	if (s[154]) a = a | {1'b1, 9'd154, 10'd51, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // ADDX ADDX_M
	if (s[155]) a = a | {1'b1, 9'd155, 10'd2, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_EA_DN
	if (s[156]) a = a | {1'b1, 9'd156, 10'd3, 7'd7, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // OR OP_DN_EA
	if (s[157]) a = a | {1'b1, 9'd157, 10'd2, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_EA_DN
	if (s[158]) a = a | {1'b1, 9'd158, 10'd3, 7'd6, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // AND OP_DN_EA
	if (s[159]) a = a | {1'b1, 9'd159, 10'd2, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_EA_DN
	if (s[160]) a = a | {1'b1, 9'd160, 10'd3, 7'd3, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // SUB OP_DN_EA
	if (s[161]) a = a | {1'b1, 9'd161, 10'd2, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_EA_DN
	if (s[162]) a = a | {1'b1, 9'd162, 10'd3, 7'd1, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ADD OP_DN_EA
	if (s[163]) a = a | {1'b1, 9'd163, 10'd6, 7'd5, 4'd0, 1'b0, 5'hf, 2'd3, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMP CMP_EA_DN
	if (s[164]) a = a | {1'b1, 9'd164, 10'd3, 7'd8, 4'd0, 1'b0, 5'hf, 2'd3, 12'h1fd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // EOR OP_DN_EA
	if (s[165]) a = a | {1'b1, 9'd165, 10'd53, 7'd0, 4'd0, 1'b0, 5'h0, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd1, 1'b0};  // CMPM CMPM
	if (s[166]) a = a | {1'b1, 9'd166, 10'd50, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SUBX ADDX_R
	if (s[167]) a = a | {1'b1, 9'd167, 10'd51, 7'd4, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // SUBX ADDX_M
	if (s[168]) a = a | {1'b1, 9'd168, 10'd50, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ADDX ADDX_R
	if (s[169]) a = a | {1'b1, 9'd169, 10'd51, 7'd2, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // ADDX ADDX_M
	if (s[170]) a = a | {1'b1, 9'd170, 10'd66, 7'd49, 4'd0, 1'b0, 5'hf, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // DIVU DIVW
	if (s[171]) a = a | {1'b1, 9'd171, 10'd66, 7'd49, 4'd1, 1'b1, 5'hf, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // DIVS DIVW
	if (s[172]) a = a | {1'b1, 9'd172, 10'd65, 7'd48, 4'd0, 1'b0, 5'hf, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // MULU MULW
	if (s[173]) a = a | {1'b1, 9'd173, 10'd65, 7'd48, 4'd1, 1'b1, 5'hf, 2'd1, 12'hffd, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // MULS MULW
	if (s[174]) a = a | {1'b1, 9'd174, 10'd50, 7'd18, 4'd0, 1'b0, 5'h1f, 2'd0, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // SBCD ADDX_R
	if (s[175]) a = a | {1'b1, 9'd175, 10'd51, 7'd18, 4'd0, 1'b0, 5'h1f, 2'd0, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // SBCD ADDX_M
	if (s[176]) a = a | {1'b1, 9'd176, 10'd50, 7'd17, 4'd0, 1'b0, 5'h1f, 2'd0, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ABCD ADDX_R
	if (s[177]) a = a | {1'b1, 9'd177, 10'd51, 7'd17, 4'd0, 1'b0, 5'h1f, 2'd0, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // ABCD ADDX_M
	if (s[178]) a = a | {1'b1, 9'd178, 10'd55, 7'd20, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // PACK PACK_R
	if (s[179]) a = a | {1'b1, 9'd179, 10'd57, 7'd20, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // PACK PACK_M
	if (s[180]) a = a | {1'b1, 9'd180, 10'd60, 7'd21, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // UNPK UNPK_R
	if (s[181]) a = a | {1'b1, 9'd181, 10'd62, 7'd21, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd2, 1'b0};  // UNPK UNPK_M
	if (s[182]) a = a | {1'b1, 9'd182, 10'd21, 7'd3, 4'd0, 1'b0, 5'h0, 2'd1, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd7, 10'd23, 1'b1, 1'b0, 2'd0, 1'b0};  // SUBA SUBA
	if (s[183]) a = a | {1'b1, 9'd183, 10'd21, 7'd3, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd7, 10'd23, 1'b1, 1'b0, 2'd0, 1'b0};  // SUBA SUBA
	if (s[184]) a = a | {1'b1, 9'd184, 10'd18, 7'd1, 4'd0, 1'b0, 5'h0, 2'd1, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd2, 10'd20, 1'b1, 1'b0, 2'd0, 1'b0};  // ADDA ADDA
	if (s[185]) a = a | {1'b1, 9'd185, 10'd18, 7'd1, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd2, 10'd20, 1'b1, 1'b0, 2'd0, 1'b0};  // ADDA ADDA
	if (s[186]) a = a | {1'b1, 9'd186, 10'd7, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMPA CMPA
	if (s[187]) a = a | {1'b1, 9'd187, 10'd7, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // CMPA CMPA
	if (s[188]) a = a | {1'b1, 9'd188, 10'd77, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXG EXG_DD
	if (s[189]) a = a | {1'b1, 9'd189, 10'd80, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXG EXG_AA
	if (s[190]) a = a | {1'b1, 9'd190, 10'd83, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // EXG EXG_DA
	if (s[191]) a = a | {1'b1, 9'd191, 10'd48, 7'd23, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASR SHIFT_R
	if (s[192]) a = a | {1'b1, 9'd192, 10'd48, 7'd22, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASL SHIFT_R
	if (s[193]) a = a | {1'b1, 9'd193, 10'd48, 7'd25, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSR SHIFT_R
	if (s[194]) a = a | {1'b1, 9'd194, 10'd48, 7'd24, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSL SHIFT_R
	if (s[195]) a = a | {1'b1, 9'd195, 10'd48, 7'd29, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXR SHIFT_R
	if (s[196]) a = a | {1'b1, 9'd196, 10'd48, 7'd28, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXL SHIFT_R
	if (s[197]) a = a | {1'b1, 9'd197, 10'd48, 7'd27, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROR SHIFT_R
	if (s[198]) a = a | {1'b1, 9'd198, 10'd48, 7'd26, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROL SHIFT_R
	if (s[199]) a = a | {1'b1, 9'd199, 10'd48, 7'd23, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASR SHIFT_R
	if (s[200]) a = a | {1'b1, 9'd200, 10'd48, 7'd22, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASL SHIFT_R
	if (s[201]) a = a | {1'b1, 9'd201, 10'd48, 7'd25, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSR SHIFT_R
	if (s[202]) a = a | {1'b1, 9'd202, 10'd48, 7'd24, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSL SHIFT_R
	if (s[203]) a = a | {1'b1, 9'd203, 10'd48, 7'd29, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXR SHIFT_R
	if (s[204]) a = a | {1'b1, 9'd204, 10'd48, 7'd28, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXL SHIFT_R
	if (s[205]) a = a | {1'b1, 9'd205, 10'd48, 7'd27, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROR SHIFT_R
	if (s[206]) a = a | {1'b1, 9'd206, 10'd48, 7'd26, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROL SHIFT_R
	if (s[207]) a = a | {1'b1, 9'd207, 10'd48, 7'd23, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASR SHIFT_R
	if (s[208]) a = a | {1'b1, 9'd208, 10'd48, 7'd22, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ASL SHIFT_R
	if (s[209]) a = a | {1'b1, 9'd209, 10'd48, 7'd25, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSR SHIFT_R
	if (s[210]) a = a | {1'b1, 9'd210, 10'd48, 7'd24, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // LSL SHIFT_R
	if (s[211]) a = a | {1'b1, 9'd211, 10'd48, 7'd29, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXR SHIFT_R
	if (s[212]) a = a | {1'b1, 9'd212, 10'd48, 7'd28, 4'd0, 1'b0, 5'h1f, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROXL SHIFT_R
	if (s[213]) a = a | {1'b1, 9'd213, 10'd48, 7'd27, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROR SHIFT_R
	if (s[214]) a = a | {1'b1, 9'd214, 10'd48, 7'd26, 4'd0, 1'b0, 5'hf, 2'd3, 12'h000, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // ROL SHIFT_R
	if (s[215]) a = a | {1'b1, 9'd215, 10'd49, 7'd23, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ASRW SHIFT_M
	if (s[216]) a = a | {1'b1, 9'd216, 10'd49, 7'd22, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ASLW SHIFT_M
	if (s[217]) a = a | {1'b1, 9'd217, 10'd49, 7'd25, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // LSRW SHIFT_M
	if (s[218]) a = a | {1'b1, 9'd218, 10'd49, 7'd24, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // LSLW SHIFT_M
	if (s[219]) a = a | {1'b1, 9'd219, 10'd49, 7'd29, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ROXRW SHIFT_M
	if (s[220]) a = a | {1'b1, 9'd220, 10'd49, 7'd28, 4'd0, 1'b0, 5'h1f, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ROXLW SHIFT_M
	if (s[221]) a = a | {1'b1, 9'd221, 10'd49, 7'd27, 4'd0, 1'b0, 5'hf, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // RORW SHIFT_M
	if (s[222]) a = a | {1'b1, 9'd222, 10'd49, 7'd26, 4'd0, 1'b0, 5'hf, 2'd1, 12'h1fc, 12'h000, 2'd0, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // ROLW SHIFT_M
	if (s[223]) a = a | {1'b1, 9'd223, 10'd154, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd162, 1'b1, 1'b0, 2'd0, 1'b0};  // BFTST BF_TST
	if (s[224]) a = a | {1'b1, 9'd224, 10'd164, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd172, 1'b1, 1'b0, 2'd0, 1'b0};  // BFEXTU BF_EXT
	if (s[225]) a = a | {1'b1, 9'd225, 10'd174, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd185, 1'b1, 1'b0, 2'd0, 1'b0};  // BFCHG BF_MOD
	if (s[226]) a = a | {1'b1, 9'd226, 10'd164, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd172, 1'b1, 1'b0, 2'd0, 1'b0};  // BFEXTS BF_EXT
	if (s[227]) a = a | {1'b1, 9'd227, 10'd174, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd185, 1'b1, 1'b0, 2'd0, 1'b0};  // BFCLR BF_MOD
	if (s[228]) a = a | {1'b1, 9'd228, 10'd164, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd172, 1'b1, 1'b0, 2'd0, 1'b0};  // BFFFO BF_EXT
	if (s[229]) a = a | {1'b1, 9'd229, 10'd174, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd185, 1'b1, 1'b0, 2'd0, 1'b0};  // BFSET BF_MOD
	if (s[230]) a = a | {1'b1, 9'd230, 10'd174, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1e5, 12'h000, 2'd1, 3'd0, 1'b0, 6'd5, 10'd185, 1'b1, 1'b0, 2'd0, 1'b0};  // BFINS BF_MOD
	if (s[231]) a = a | {1'b1, 9'd231, 10'd228, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'hfff, 12'h000, 2'd1, 3'd0, 1'b0, 6'd19, 10'd237, 1'b1, 1'b0, 2'd0, 1'b0};  // FPP FPU_GEN
	if (s[232]) a = a | {1'b1, 9'd232, 10'd482, 7'd0, 4'd0, 1'b0, 5'h0, 2'd0, 12'h1fd, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b0};  // FScc FSCC
	if (s[233]) a = a | {1'b1, 9'd233, 10'd484, 7'd0, 4'd0, 1'b0, 5'h0, 2'd1, 12'h000, 12'h000, 2'd1, 3'd3, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // FDBcc FDBCC
	if (s[234]) a = a | {1'b1, 9'd234, 10'd486, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // FTRAPcc FTRAPCC
	if (s[235]) a = a | {1'b1, 9'd235, 10'd486, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // FTRAPcc FTRAPCC
	if (s[236]) a = a | {1'b1, 9'd236, 10'd486, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd6, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // FTRAPcc FTRAPCC
	if (s[237]) a = a | {1'b1, 9'd237, 10'd480, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd7, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // FBcc FBCC
	if (s[238]) a = a | {1'b1, 9'd238, 10'd480, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd7, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b0};  // FBcc FBCC
	if (s[239]) a = a | {1'b1, 9'd239, 10'd488, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h1f4, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // FSAVE FSAVE
	if (s[240]) a = a | {1'b1, 9'd240, 10'd546, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h7ec, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b1, 1'b0, 2'd0, 1'b1};  // FRESTORE FRESTORE
	if (s[241]) a = a | {1'b1, 9'd241, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVL CACHE_OP
	if (s[242]) a = a | {1'b1, 9'd242, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVP CACHE_OP
	if (s[243]) a = a | {1'b1, 9'd243, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVA CACHE_OP
	if (s[244]) a = a | {1'b1, 9'd244, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHL CACHE_OP
	if (s[245]) a = a | {1'b1, 9'd245, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHP CACHE_OP
	if (s[246]) a = a | {1'b1, 9'd246, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHA CACHE_OP
	if (s[247]) a = a | {1'b1, 9'd247, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVL CACHE_OP
	if (s[248]) a = a | {1'b1, 9'd248, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVP CACHE_OP
	if (s[249]) a = a | {1'b1, 9'd249, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVA CACHE_OP
	if (s[250]) a = a | {1'b1, 9'd250, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHL CACHE_OP
	if (s[251]) a = a | {1'b1, 9'd251, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHP CACHE_OP
	if (s[252]) a = a | {1'b1, 9'd252, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHA CACHE_OP
	if (s[253]) a = a | {1'b1, 9'd253, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVL CACHE_OP
	if (s[254]) a = a | {1'b1, 9'd254, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVP CACHE_OP
	if (s[255]) a = a | {1'b1, 9'd255, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVA CACHE_OP
	if (s[256]) a = a | {1'b1, 9'd256, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHL CACHE_OP
	if (s[257]) a = a | {1'b1, 9'd257, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHP CACHE_OP
	if (s[258]) a = a | {1'b1, 9'd258, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHA CACHE_OP
	if (s[259]) a = a | {1'b1, 9'd259, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVL CACHE_OP
	if (s[260]) a = a | {1'b1, 9'd260, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVP CACHE_OP
	if (s[261]) a = a | {1'b1, 9'd261, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CINVA CACHE_OP
	if (s[262]) a = a | {1'b1, 9'd262, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHL CACHE_OP
	if (s[263]) a = a | {1'b1, 9'd263, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHP CACHE_OP
	if (s[264]) a = a | {1'b1, 9'd264, 10'd225, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // CPUSHA CACHE_OP
	if (s[265]) a = a | {1'b1, 9'd265, 10'd226, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PFLUSHN PFLUSH
	if (s[266]) a = a | {1'b1, 9'd266, 10'd226, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PFLUSH PFLUSH
	if (s[267]) a = a | {1'b1, 9'd267, 10'd226, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PFLUSHAN PFLUSH
	if (s[268]) a = a | {1'b1, 9'd268, 10'd226, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PFLUSHA PFLUSH
	if (s[269]) a = a | {1'b1, 9'd269, 10'd227, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PTESTW PTEST
	if (s[270]) a = a | {1'b1, 9'd270, 10'd227, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd0, 1'b1, 6'd0, 10'd0, 1'b0, 1'b0, 2'd0, 1'b1};  // PTESTR PTEST
	if (s[271]) a = a | {1'b1, 9'd271, 10'd131, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd4, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd3, 1'b0};  // MOVE16 MOVE16
	if (s[272]) a = a | {1'b1, 9'd272, 10'd131, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd4, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd3, 1'b0};  // MOVE16 MOVE16
	if (s[273]) a = a | {1'b1, 9'd273, 10'd131, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd4, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd3, 1'b0};  // MOVE16 MOVE16
	if (s[274]) a = a | {1'b1, 9'd274, 10'd131, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd0, 3'd4, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd3, 1'b0};  // MOVE16 MOVE16
	if (s[275]) a = a | {1'b1, 9'd275, 10'd131, 7'd0, 4'd0, 1'b0, 5'h0, 2'd2, 12'h000, 12'h000, 2'd1, 3'd0, 1'b0, 6'd0, 10'd0, 1'b0, 1'b0, 2'd3, 1'b0};  // MOVE16 MOVE16
	ent_attr_oh = a;
endfunction

function automatic logic [8:0] sel_index(input logic [NENT-1:0] s);
	logic [8:0] x;
	x = '0;
	for (int i = 0; i < NENT; i++) if (s[i]) x = x | 9'(i);
	sel_index = x;
endfunction
function automatic pla_t dec_pla(input logic [15:0] op);
	logic [NENT-1:0] s;
	s = dec_sel(op);
	dec_pla = ent_attr(sel_index(s), |s);
endfunction
// ---- end of ap68040_dec_pla.svh ----

function automatic logic [3:0] ea_idx(input logic [2:0] m, input logic [2:0] r);
	if (m != 3'd7) ea_idx = {1'b0, m};
	else if (r <= 3'd4) ea_idx = 4'd7 + {1'b0, r};
	else ea_idx = EM_NONE;
endfunction

// extension words of an EA with a brief index extension
function automatic logic [2:0] ea_brief_len(input logic [3:0] i, input logic [1:0] sz);
	case (i)
		EM_AD16, EM_ABSW, EM_PC16, EM_AX, EM_PCX: ea_brief_len = 3'd1;
		EM_ABSL: ea_brief_len = 3'd2;
		EM_IMM:  ea_brief_len = (sz == SZ_L) ? 3'd2 : 3'd1;
		default: ea_brief_len = 3'd0;
	endcase
endfunction

always_comb begin
	logic [NENT-1:0] s;
	pla_t a;
	logic [3:0] i0, i1;
	logic [2:0] nimm_l, nimm_n, l0_l, l0_n, l1_l, l1_n, b_l, b_n;
	logic [1:0] sz;
	logic       isl;
	s  = dec_sel(op);
	a  = ent_attr_oh(s);
	i0 = a.ea0v ? ea_idx(op[5:3], op[2:0]) : EM_NONE;
	i1 = a.ea1v ? ea_idx(op[8:6], op[11:9]) : EM_NONE;
	sz = (a.szc == 2'd3) ? op[7:6] : a.szc;
	// the lengths are formed for a long and for a shorter size side by
	// side, and the size picks one last (a timing path: the size comes
	// out of the decode table)
	isl = (a.szc == 2'd3) ? (op[7:6] == SZ_L) : (a.szc == SZ_L);
	case (a.immk)
		3'd1:       begin nimm_l = 3'd2; nimm_n = 3'd1; end
		3'd2, 3'd3: begin nimm_l = 3'd1; nimm_n = 3'd1; end
		3'd4:       begin nimm_l = 3'd2; nimm_n = 3'd2; end
		3'd5:       begin nimm_l = (op[7:0] == 8'h00) ? 3'd1 : (op[7:0] == 8'hFF) ? 3'd2 : 3'd0; nimm_n = nimm_l; end
		3'd6:       begin nimm_l = (op[2:0] == 3'd2) ? 3'd1 : (op[2:0] == 3'd3) ? 3'd2 : 3'd0; nimm_n = nimm_l; end
		3'd7:       begin nimm_l = op[6] ? 3'd2 : 3'd1; nimm_n = nimm_l; end
		default:    begin nimm_l = 3'd0; nimm_n = 3'd0; end
	endcase
	l0_l = ea_brief_len(i0, SZ_L);
	l0_n = ea_brief_len(i0, SZ_W);
	l1_l = ea_brief_len(i1, SZ_L);
	l1_n = ea_brief_len(i1, SZ_W);
	b_l  = 3'd1 + {1'b0, a.nfix} + nimm_l;
	b_n  = 3'd1 + {1'b0, a.nfix} + nimm_n;
	pd.legal = a.match &&
	           (!a.ea0v || (i0 != EM_NONE && a.ea0m[i0])) &&
	           (!a.ea1v || (i1 != EM_NONE && a.ea1m[i1]));
	pd.ent  = a.ent;
	pd.sz   = sz;
	pd.b    = isl ? b_l : b_n;
	pd.p1   = isl ? (b_l + l0_l) : (b_n + l0_n);
	pd.tot  = isl ? ({1'b0, b_l} + ({1'b0, l0_l} + {1'b0, l1_l}))
	              : ({1'b0, b_n} + ({1'b0, l0_n} + {1'b0, l1_n}));
	pd.x0   = (i0 == EM_AX) || (i0 == EM_PCX);
	pd.x1   = (i1 == EM_AX) || (i1 == EM_PCX);
	pd.slow = (a.rt == UA_FPU_GEN) && (i0 == EM_IMM);
	pd.i0   = i0;
	pd.i1   = i1;
	// an illegal word: D1 takes one word and the exception; b, p1 and tot
	// are not used for it (they stay off the override, a timing path)
	if (!pd.legal) begin
		pd.x0  = 1'b0;
		pd.x1  = 1'b0;
		pd.slow = 1'b0;
	end
end

endmodule
// ---- ap68040_ram.sv ----
//--------------------------------------------------------------------------//
// AP68040 - pipelined MC68040                                            //
//                                                                          //
// ap68040_ram.sv - memory primitives, for Vivado 2018.3 (Game Bub)       //
//                                                                          //
//   ap68040_sdp_be   simple dual port block RAM (M10K): one write port     //
//                    with byte enables, one read port with a registered    //
//                    address and an optionally enabled output register     //
//   ap68040_tdp      true dual port block RAM (M10K), both ports read and  //
//                    write, registered addresses, unregistered outputs     //
//   ap68040_lutram   small RAM with an asynchronous read port (MLAB)       //
//--------------------------------------------------------------------------//

module ap68040_sdp_be #(
	parameter int AW = 6,
	parameter int NB = 16,           // bytes per word
	parameter bit OREG = 1           // registered output (one more cycle)
)(
	input  logic              clk,
	input  logic              we,
	input  logic [AW-1:0]     waddr,
	input  logic [NB-1:0]     wbe,
	input  logic [NB*8-1:0]   wdata,
	input  logic [AW-1:0]     raddr,    // sampled here: data the next cycle
	input  logic              oce,      // output register enable
	output logic [NB*8-1:0]   q
);
	// Vivado's byte-write simple dual port template: one two-dimensional
	// array, the byte enables in a loop of one process, the read registered
	// in the same process (read first: a read of the word written in the
	// same cycle returns the old data, as the Quartus version; the users
	// track that case).
	// 64 words or fewer (the data cache's lines, the instruction cache's
	// tags): LUT RAM, its asynchronous read registered here (the same old
	// data on a same-cycle write); a 128-bit line would take two block
	// RAMs of 512 words each for 64 of them. Deeper: block RAM.
	logic [NB*8-1:0] qr;
	generate
		if (AW <= 6) begin : g_lut
			(* ram_style = "distributed" *) logic [NB*8-1:0] mem [0:(1<<AW)-1];
			always_ff @(posedge clk) begin
				for (int i = 0; i < NB; i++)
					if (we && wbe[i]) mem[waddr][i*8 +: 8] <= wdata[i*8 +: 8];
				qr <= mem[raddr];
			end
		end
		else begin : g_bram
			(* ram_style = "block" *) logic [NB*8-1:0] mem [0:(1<<AW)-1];
			always_ff @(posedge clk) begin
				for (int i = 0; i < NB; i++)
					if (we && wbe[i]) mem[waddr][i*8 +: 8] <= wdata[i*8 +: 8];
				qr <= mem[raddr];
			end
		end
	endgenerate
	generate
		if (OREG) begin : g_oreg
			always_ff @(posedge clk) if (oce) q <= qr;
		end
		else begin : g_noreg
			assign q = qr;
		end
	endgenerate
endmodule

module ap68040_tdp #(
	parameter int AW = 6,
	parameter int DW = 22
)(
	input  logic          clk,
	input  logic [AW-1:0] addr_a,
	input  logic          we_a,
	input  logic [DW-1:0] wd_a,
	output logic [DW-1:0] q_a,
	output logic [DW-1:0] qa_raw,
	output logic          qa_bv,
	output logic [DW-1:0] qa_bd,
	input  logic [AW-1:0] addr_b,
	input  logic          we_b,
	input  logic [DW-1:0] wd_b,
	output logic [DW-1:0] q_b
);
	// Vivado's true dual port template: one process per port, each reading
	// first (the old word); the write is laid over the read by the compare
	// of registered addresses, as in the Quartus version.
	logic [DW-1:0] mem [0:(1<<AW)-1];
	logic [DW-1:0] qa_r, qb_r, wa_d, wb_d;
	logic [AW-1:0] ra, rb, wa_q, wb_q;
	logic          wa_v, wb_v;
	always_ff @(posedge clk) begin
		qa_r <= mem[addr_a];
		if (we_a) mem[addr_a] <= wd_a;
	end
	always_ff @(posedge clk) begin
		qb_r <= mem[addr_b];
		if (we_b) mem[addr_b] <= wd_b;
	end
	always_ff @(posedge clk) begin
		ra   <= addr_a;
		rb   <= addr_b;
		wa_v <= we_a; wa_q <= addr_a; wa_d <= wd_a;
		wb_v <= we_b; wb_q <= addr_b; wb_d <= wd_b;
	end
	// (port B's write wins a same-word collision, as in the old order)
	assign q_a    = (wb_v && wb_q == ra) ? wb_d : (wa_v && wa_q == ra) ? wa_d : qa_r;
	assign qa_raw = qa_r;
	assign qa_bv  = (wb_v && wb_q == ra) || (wa_v && wa_q == ra);
	assign qa_bd  = (wb_v && wb_q == ra) ? wb_d : wa_d;
	assign q_b = (wb_v && wb_q == rb) ? wb_d : (wa_v && wa_q == rb) ? wa_d : qb_r;
endmodule

module ap68040_lutram #(
	parameter int AW = 4,
	parameter int DW = 50
)(
	input  logic          clk,
	input  logic          we,
	input  logic [AW-1:0] waddr,
	input  logic [DW-1:0] wdata,
	input  logic [AW-1:0] raddr,
	output logic [DW-1:0] q
);
	(* ramstyle = "MLAB, no_rw_check" *) logic [DW-1:0] mem [0:(1<<AW)-1];
	initial for (int i = 0; i < (1 << AW); i++) mem[i] = '0;
	always_ff @(posedge clk) if (we) mem[waddr] <= wdata;
	assign q = mem[raddr];
endmodule

//--------------------------------------------------------------------------
// ap68040_rf: 32 x 32 register file in MLABs, three write ports and NR
// asynchronous read ports.  Each write port owns NR copies (one per read
// port); a live value table records which port wrote each register last,
// and a read selects that port's copy.  Two ports writing the same
// register in one cycle: the higher port number wins.
//--------------------------------------------------------------------------
module ap68040_rf #(
	parameter int NR = 5,
	parameter int NW = 3              // write ports (2 or 3): the later wins
)(
	input  logic        clk,
	input  logic  [2:0] we,
	input  logic  [4:0] wa [3],
	input  logic [31:0] wd [3],
	input  logic  [4:0] ra [NR],
	output logic [31:0] rd [NR]
);
	logic [1:0]  lvt [32];
	logic [31:0] q [NW][NR];
	genvar gw, gr;
	generate
		for (gw = 0; gw < NW; gw++) begin : g_w
			for (gr = 0; gr < NR; gr++) begin : g_r
				ap68040_lutram #(.AW(5), .DW(32)) bank (
					.clk(clk), .we(we[gw]), .waddr(wa[gw]), .wdata(wd[gw]),
					.raddr(ra[gr]), .q(q[gw][gr])
				);
			end
		end
	endgenerate
	initial for (int i = 0; i < 32; i++) lvt[i] = 2'd0;
	always_ff @(posedge clk)
		for (int w = 0; w < NW; w++)
			if (we[w]) lvt[wa[w]] <= 2'(w);
	always_comb
		for (int r = 0; r < NR; r++)
			rd[r] = q[lvt[ra[r]]][r];
endmodule

//--------------------------------------------------------------------------
// ap68040_sdpr: simple dual-port block RAM, one write and one read port,
// the read address registered (data the cycle after it is presented).  A
// read of the word written at the same edge is undefined (no_rw_check):
// the caller handles it.
//--------------------------------------------------------------------------
module ap68040_sdpr #(
	parameter int AW = 8,
	parameter int DW = 32
)(
	input  logic          clk,
	input  logic          we,
	input  logic [AW-1:0] waddr,
	input  logic [DW-1:0] wdata,
	input  logic [AW-1:0] raddr,
	output logic [DW-1:0] q
);
	// (the output registered, not the address: that read has the block
	// RAM's own read-during-write semantics, so no bypass logic is built)
	(* ramstyle = "M10K, no_rw_check" *) logic [DW-1:0] mem [0:(1<<AW)-1];
	initial for (int i = 0; i < (1 << AW); i++) mem[i] = '0;
	always_ff @(posedge clk) begin
		if (we) mem[waddr] <= wdata;
		q <= mem[raddr];
	end
endmodule

//--------------------------------------------------------------------------
// ap68040_pdrom: the predecoder's table (tools/ucode.py emit_pdrom), one
// word per operation word bits 15:3, in block RAM with two read ports
// (the fetch unit's two words a cycle); the words read a cycle after their
// addresses
//--------------------------------------------------------------------------
module ap68040_pdrom
	import ap68040_upkg::*;
(
	input  logic        clk,
	input  logic [12:0] a0,
	input  logic [12:0] a1,
	output pdw_t        q0,
	output pdw_t        q1
);
	(* romstyle = "M10K" *) logic [31:0] pd_rom [0:8191];
	initial begin
// ---- inlined from ap68040_pd_rom.svh (tools/import_ap68040.py) ----
// generated by tools/ucode.py - do not edit
// the predecoder table: pd_rom[{op[15:6], op[5:3]}] (block RAM initialization)
for (int i = 0; i < 4096; i++) pd_rom[i] = 32'h01ff0000;
for (int i = 4096; i < 8192; i++) pd_rom[i] = 32'h01ff0000;
pd_rom[0] = 32'h0000c33f;
pd_rom[1] = 32'h0000c320;
pd_rom[2] = 32'h0000c33f;
pd_rom[3] = 32'h0000c33f;
pd_rom[4] = 32'h0000c33f;
pd_rom[5] = 32'h0000c33f;
pd_rom[6] = 32'h0000c33f;
pd_rom[7] = 32'h4000c323;
pd_rom[8] = 32'h0007c33f;
pd_rom[9] = 32'h0007c320;
pd_rom[10] = 32'h0007c33f;
pd_rom[11] = 32'h0007c33f;
pd_rom[12] = 32'h0007c33f;
pd_rom[13] = 32'h0007c33f;
pd_rom[14] = 32'h0007c33f;
pd_rom[15] = 32'h4207c323;
pd_rom[16] = 32'h000ec33f;
pd_rom[17] = 32'h000ec320;
pd_rom[18] = 32'h000ec33f;
pd_rom[19] = 32'h000ec33f;
pd_rom[20] = 32'h000ec33f;
pd_rom[21] = 32'h000ec33f;
pd_rom[22] = 32'h000ec33f;
pd_rom[23] = 32'h000ec323;
pd_rom[24] = 32'h001b1120;
pd_rom[25] = 32'h001b1120;
pd_rom[26] = 32'h001b113f;
pd_rom[27] = 32'h001b1120;
pd_rom[28] = 32'h001b1120;
pd_rom[29] = 32'h001b113f;
pd_rom[30] = 32'h001b113f;
pd_rom[31] = 32'h001b112f;
pd_rom[32] = 32'h0027013f;
pd_rom[33] = 32'h002b463f;
pd_rom[34] = 32'h0027013f;
pd_rom[35] = 32'h0027013f;
pd_rom[36] = 32'h0027013f;
pd_rom[37] = 32'h0027013f;
pd_rom[38] = 32'h0027013f;
pd_rom[39] = 32'h0027013f;
pd_rom[40] = 32'h0028013f;
pd_rom[41] = 32'h002c863f;
pd_rom[42] = 32'h0028013f;
pd_rom[43] = 32'h0028013f;
pd_rom[44] = 32'h0028013f;
pd_rom[45] = 32'h0028013f;
pd_rom[46] = 32'h0028013f;
pd_rom[47] = 32'h00280123;
pd_rom[48] = 32'h0029013f;
pd_rom[49] = 32'h002d463f;
pd_rom[50] = 32'h0029013f;
pd_rom[51] = 32'h0029013f;
pd_rom[52] = 32'h0029013f;
pd_rom[53] = 32'h0029013f;
pd_rom[54] = 32'h0029013f;
pd_rom[55] = 32'h00290123;
pd_rom[56] = 32'h002a013f;
pd_rom[57] = 32'h002e863f;
pd_rom[58] = 32'h002a013f;
pd_rom[59] = 32'h002a013f;
pd_rom[60] = 32'h002a013f;
pd_rom[61] = 32'h002a013f;
pd_rom[62] = 32'h002a013f;
pd_rom[63] = 32'h002a0123;
pd_rom[64] = 32'h0001c33f;
pd_rom[65] = 32'h0001c320;
pd_rom[66] = 32'h0001c33f;
pd_rom[67] = 32'h0001c33f;
pd_rom[68] = 32'h0001c33f;
pd_rom[69] = 32'h0001c33f;
pd_rom[70] = 32'h0001c33f;
pd_rom[71] = 32'h4401c323;
pd_rom[72] = 32'h0008c33f;
pd_rom[73] = 32'h0008c320;
pd_rom[74] = 32'h0008c33f;
pd_rom[75] = 32'h0008c33f;
pd_rom[76] = 32'h0008c33f;
pd_rom[77] = 32'h0008c33f;
pd_rom[78] = 32'h0008c33f;
pd_rom[79] = 32'h4608c323;
pd_rom[80] = 32'h000fc33f;
pd_rom[81] = 32'h000fc320;
pd_rom[82] = 32'h000fc33f;
pd_rom[83] = 32'h000fc33f;
pd_rom[84] = 32'h000fc33f;
pd_rom[85] = 32'h000fc33f;
pd_rom[86] = 32'h000fc33f;
pd_rom[87] = 32'h000fc323;
pd_rom[88] = 32'h001c5120;
pd_rom[89] = 32'h001c5120;
pd_rom[90] = 32'h001c513f;
pd_rom[91] = 32'h001c5120;
pd_rom[92] = 32'h001c5120;
pd_rom[93] = 32'h001c513f;
pd_rom[94] = 32'h001c513f;
pd_rom[95] = 32'h001c512f;
pd_rom[96] = 32'h0027013f;
pd_rom[97] = 32'h002b463f;
pd_rom[98] = 32'h0027013f;
pd_rom[99] = 32'h0027013f;
pd_rom[100] = 32'h0027013f;
pd_rom[101] = 32'h0027013f;
pd_rom[102] = 32'h0027013f;
pd_rom[103] = 32'h0027013f;
pd_rom[104] = 32'h0028013f;
pd_rom[105] = 32'h002c863f;
pd_rom[106] = 32'h0028013f;
pd_rom[107] = 32'h0028013f;
pd_rom[108] = 32'h0028013f;
pd_rom[109] = 32'h0028013f;
pd_rom[110] = 32'h0028013f;
pd_rom[111] = 32'h00280123;
pd_rom[112] = 32'h0029013f;
pd_rom[113] = 32'h002d463f;
pd_rom[114] = 32'h0029013f;
pd_rom[115] = 32'h0029013f;
pd_rom[116] = 32'h0029013f;
pd_rom[117] = 32'h0029013f;
pd_rom[118] = 32'h0029013f;
pd_rom[119] = 32'h00290123;
pd_rom[120] = 32'h002a013f;
pd_rom[121] = 32'h002e863f;
pd_rom[122] = 32'h002a013f;
pd_rom[123] = 32'h002a013f;
pd_rom[124] = 32'h002a013f;
pd_rom[125] = 32'h002a013f;
pd_rom[126] = 32'h002a013f;
pd_rom[127] = 32'h002a0123;
pd_rom[128] = 32'h0002c33f;
pd_rom[129] = 32'h0002c320;
pd_rom[130] = 32'h0002c33f;
pd_rom[131] = 32'h0002c33f;
pd_rom[132] = 32'h0002c33f;
pd_rom[133] = 32'h0002c33f;
pd_rom[134] = 32'h0002c33f;
pd_rom[135] = 32'h0002c323;
pd_rom[136] = 32'h0009c33f;
pd_rom[137] = 32'h0009c320;
pd_rom[138] = 32'h0009c33f;
pd_rom[139] = 32'h0009c33f;
pd_rom[140] = 32'h0009c33f;
pd_rom[141] = 32'h0009c33f;
pd_rom[142] = 32'h0009c33f;
pd_rom[143] = 32'h0009c323;
pd_rom[144] = 32'h0010c33f;
pd_rom[145] = 32'h0010c320;
pd_rom[146] = 32'h0010c33f;
pd_rom[147] = 32'h0010c33f;
pd_rom[148] = 32'h0010c33f;
pd_rom[149] = 32'h0010c33f;
pd_rom[150] = 32'h0010c33f;
pd_rom[151] = 32'h0010c323;
pd_rom[152] = 32'h001d9120;
pd_rom[153] = 32'h001d9120;
pd_rom[154] = 32'h001d913f;
pd_rom[155] = 32'h001d9120;
pd_rom[156] = 32'h001d9120;
pd_rom[157] = 32'h001d913f;
pd_rom[158] = 32'h001d913f;
pd_rom[159] = 32'h001d912f;
pd_rom[160] = 32'h0027013f;
pd_rom[161] = 32'h002b463f;
pd_rom[162] = 32'h0027013f;
pd_rom[163] = 32'h0027013f;
pd_rom[164] = 32'h0027013f;
pd_rom[165] = 32'h0027013f;
pd_rom[166] = 32'h0027013f;
pd_rom[167] = 32'h0027013f;
pd_rom[168] = 32'h0028013f;
pd_rom[169] = 32'h002c863f;
pd_rom[170] = 32'h0028013f;
pd_rom[171] = 32'h0028013f;
pd_rom[172] = 32'h0028013f;
pd_rom[173] = 32'h0028013f;
pd_rom[174] = 32'h0028013f;
pd_rom[175] = 32'h00280123;
pd_rom[176] = 32'h0029013f;
pd_rom[177] = 32'h002d463f;
pd_rom[178] = 32'h0029013f;
pd_rom[179] = 32'h0029013f;
pd_rom[180] = 32'h0029013f;
pd_rom[181] = 32'h0029013f;
pd_rom[182] = 32'h0029013f;
pd_rom[183] = 32'h00290123;
pd_rom[184] = 32'h002a013f;
pd_rom[185] = 32'h002e863f;
pd_rom[186] = 32'h002a013f;
pd_rom[187] = 32'h002a013f;
pd_rom[188] = 32'h002a013f;
pd_rom[189] = 32'h002a013f;
pd_rom[190] = 32'h002a013f;
pd_rom[191] = 32'h002a0123;
pd_rom[192] = 32'h0003c33f;
pd_rom[193] = 32'h0003c320;
pd_rom[194] = 32'h0003c33f;
pd_rom[195] = 32'h0003c33f;
pd_rom[196] = 32'h0003c33f;
pd_rom[197] = 32'h0003c33f;
pd_rom[198] = 32'h0003c33f;
pd_rom[199] = 32'h0003c323;
pd_rom[200] = 32'h000ac33f;
pd_rom[201] = 32'h000ac320;
pd_rom[202] = 32'h000ac33f;
pd_rom[203] = 32'h000ac33f;
pd_rom[204] = 32'h000ac33f;
pd_rom[205] = 32'h000ac33f;
pd_rom[206] = 32'h000ac33f;
pd_rom[207] = 32'h000ac323;
pd_rom[208] = 32'h0011c33f;
pd_rom[209] = 32'h0011c320;
pd_rom[210] = 32'h0011c33f;
pd_rom[211] = 32'h0011c33f;
pd_rom[212] = 32'h0011c33f;
pd_rom[213] = 32'h0011c33f;
pd_rom[214] = 32'h0011c33f;
pd_rom[215] = 32'h0011c323;
pd_rom[224] = 32'h0027013f;
pd_rom[225] = 32'h002b463f;
pd_rom[226] = 32'h0027013f;
pd_rom[227] = 32'h0027013f;
pd_rom[228] = 32'h0027013f;
pd_rom[229] = 32'h0027013f;
pd_rom[230] = 32'h0027013f;
pd_rom[231] = 32'h0027013f;
pd_rom[232] = 32'h0028013f;
pd_rom[233] = 32'h002c863f;
pd_rom[234] = 32'h0028013f;
pd_rom[235] = 32'h0028013f;
pd_rom[236] = 32'h0028013f;
pd_rom[237] = 32'h0028013f;
pd_rom[238] = 32'h0028013f;
pd_rom[239] = 32'h00280123;
pd_rom[240] = 32'h0029013f;
pd_rom[241] = 32'h002d463f;
pd_rom[242] = 32'h0029013f;
pd_rom[243] = 32'h0029013f;
pd_rom[244] = 32'h0029013f;
pd_rom[245] = 32'h0029013f;
pd_rom[246] = 32'h0029013f;
pd_rom[247] = 32'h00290123;
pd_rom[248] = 32'h002a013f;
pd_rom[249] = 32'h002e863f;
pd_rom[250] = 32'h002a013f;
pd_rom[251] = 32'h002a013f;
pd_rom[252] = 32'h002a013f;
pd_rom[253] = 32'h002a013f;
pd_rom[254] = 32'h002a013f;
pd_rom[255] = 32'h002a0123;
pd_rom[256] = 32'h0023053f;
pd_rom[257] = 32'h00230520;
pd_rom[258] = 32'h0023053f;
pd_rom[259] = 32'h0023053f;
pd_rom[260] = 32'h0023053f;
pd_rom[261] = 32'h0023053f;
pd_rom[262] = 32'h0023053f;
pd_rom[263] = 32'h0023052f;
pd_rom[264] = 32'h0024053f;
pd_rom[265] = 32'h00240520;
pd_rom[266] = 32'h0024053f;
pd_rom[267] = 32'h0024053f;
pd_rom[268] = 32'h0024053f;
pd_rom[269] = 32'h0024053f;
pd_rom[270] = 32'h0024053f;
pd_rom[271] = 32'h00240523;
pd_rom[272] = 32'h0025053f;
pd_rom[273] = 32'h00250520;
pd_rom[274] = 32'h0025053f;
pd_rom[275] = 32'h0025053f;
pd_rom[276] = 32'h0025053f;
pd_rom[277] = 32'h0025053f;
pd_rom[278] = 32'h0025053f;
pd_rom[279] = 32'h00250523;
pd_rom[280] = 32'h0026053f;
pd_rom[281] = 32'h00260520;
pd_rom[282] = 32'h0026053f;
pd_rom[283] = 32'h0026053f;
pd_rom[284] = 32'h0026053f;
pd_rom[285] = 32'h0026053f;
pd_rom[286] = 32'h0026053f;
pd_rom[287] = 32'h00260523;
pd_rom[288] = 32'h0027013f;
pd_rom[289] = 32'h002b463f;
pd_rom[290] = 32'h0027013f;
pd_rom[291] = 32'h0027013f;
pd_rom[292] = 32'h0027013f;
pd_rom[293] = 32'h0027013f;
pd_rom[294] = 32'h0027013f;
pd_rom[295] = 32'h0027013f;
pd_rom[296] = 32'h0028013f;
pd_rom[297] = 32'h002c863f;
pd_rom[298] = 32'h0028013f;
pd_rom[299] = 32'h0028013f;
pd_rom[300] = 32'h0028013f;
pd_rom[301] = 32'h0028013f;
pd_rom[302] = 32'h0028013f;
pd_rom[303] = 32'h00280123;
pd_rom[304] = 32'h0029013f;
pd_rom[305] = 32'h002d463f;
pd_rom[306] = 32'h0029013f;
pd_rom[307] = 32'h0029013f;
pd_rom[308] = 32'h0029013f;
pd_rom[309] = 32'h0029013f;
pd_rom[310] = 32'h0029013f;
pd_rom[311] = 32'h00290123;
pd_rom[312] = 32'h002a013f;
pd_rom[313] = 32'h002e863f;
pd_rom[314] = 32'h002a013f;
pd_rom[315] = 32'h002a013f;
pd_rom[316] = 32'h002a013f;
pd_rom[317] = 32'h002a013f;
pd_rom[318] = 32'h002a013f;
pd_rom[319] = 32'h002a0123;
pd_rom[320] = 32'h0004c33f;
pd_rom[321] = 32'h0004c320;
pd_rom[322] = 32'h0004c33f;
pd_rom[323] = 32'h0004c33f;
pd_rom[324] = 32'h0004c33f;
pd_rom[325] = 32'h0004c33f;
pd_rom[326] = 32'h0004c33f;
pd_rom[327] = 32'h4804c323;
pd_rom[328] = 32'h000bc33f;
pd_rom[329] = 32'h000bc320;
pd_rom[330] = 32'h000bc33f;
pd_rom[331] = 32'h000bc33f;
pd_rom[332] = 32'h000bc33f;
pd_rom[333] = 32'h000bc33f;
pd_rom[334] = 32'h000bc33f;
pd_rom[335] = 32'h4a0bc323;
pd_rom[336] = 32'h0012c33f;
pd_rom[337] = 32'h0012c320;
pd_rom[338] = 32'h0012c33f;
pd_rom[339] = 32'h0012c33f;
pd_rom[340] = 32'h0012c33f;
pd_rom[341] = 32'h0012c33f;
pd_rom[342] = 32'h0012c33f;
pd_rom[343] = 32'h0012c323;
pd_rom[344] = 32'h001e1120;
pd_rom[345] = 32'h001e1120;
pd_rom[346] = 32'h001e113f;
pd_rom[347] = 32'h001e113f;
pd_rom[348] = 32'h001e113f;
pd_rom[349] = 32'h001e113f;
pd_rom[350] = 32'h001e113f;
pd_rom[351] = 32'h001e1123;
pd_rom[352] = 32'h0027013f;
pd_rom[353] = 32'h002b463f;
pd_rom[354] = 32'h0027013f;
pd_rom[355] = 32'h0027013f;
pd_rom[356] = 32'h0027013f;
pd_rom[357] = 32'h0027013f;
pd_rom[358] = 32'h0027013f;
pd_rom[359] = 32'h0027013f;
pd_rom[360] = 32'h0028013f;
pd_rom[361] = 32'h002c863f;
pd_rom[362] = 32'h0028013f;
pd_rom[363] = 32'h0028013f;
pd_rom[364] = 32'h0028013f;
pd_rom[365] = 32'h0028013f;
pd_rom[366] = 32'h0028013f;
pd_rom[367] = 32'h00280123;
pd_rom[368] = 32'h0029013f;
pd_rom[369] = 32'h002d463f;
pd_rom[370] = 32'h0029013f;
pd_rom[371] = 32'h0029013f;
pd_rom[372] = 32'h0029013f;
pd_rom[373] = 32'h0029013f;
pd_rom[374] = 32'h0029013f;
pd_rom[375] = 32'h00290123;
pd_rom[376] = 32'h002a013f;
pd_rom[377] = 32'h002e863f;
pd_rom[378] = 32'h002a013f;
pd_rom[379] = 32'h002a013f;
pd_rom[380] = 32'h002a013f;
pd_rom[381] = 32'h002a013f;
pd_rom[382] = 32'h002a013f;
pd_rom[383] = 32'h002a0123;
pd_rom[384] = 32'h0005c33f;
pd_rom[385] = 32'h0005c320;
pd_rom[386] = 32'h0005c33f;
pd_rom[387] = 32'h0005c33f;
pd_rom[388] = 32'h0005c33f;
pd_rom[389] = 32'h0005c33f;
pd_rom[390] = 32'h0005c33f;
pd_rom[391] = 32'h0005c32f;
pd_rom[392] = 32'h000cc33f;
pd_rom[393] = 32'h000cc320;
pd_rom[394] = 32'h000cc33f;
pd_rom[395] = 32'h000cc33f;
pd_rom[396] = 32'h000cc33f;
pd_rom[397] = 32'h000cc33f;
pd_rom[398] = 32'h000cc33f;
pd_rom[399] = 32'h000cc32f;
pd_rom[400] = 32'h0013c33f;
pd_rom[401] = 32'h0013c320;
pd_rom[402] = 32'h0013c33f;
pd_rom[403] = 32'h0013c33f;
pd_rom[404] = 32'h0013c33f;
pd_rom[405] = 32'h0013c33f;
pd_rom[406] = 32'h0013c33f;
pd_rom[407] = 32'h0013c32f;
pd_rom[408] = 32'h001f5120;
pd_rom[409] = 32'h001f5120;
pd_rom[410] = 32'h001f513f;
pd_rom[411] = 32'h001f513f;
pd_rom[412] = 32'h001f513f;
pd_rom[413] = 32'h001f513f;
pd_rom[414] = 32'h001f513f;
pd_rom[415] = 32'h4c1f5123;
pd_rom[416] = 32'h0027013f;
pd_rom[417] = 32'h002b463f;
pd_rom[418] = 32'h0027013f;
pd_rom[419] = 32'h0027013f;
pd_rom[420] = 32'h0027013f;
pd_rom[421] = 32'h0027013f;
pd_rom[422] = 32'h0027013f;
pd_rom[423] = 32'h0027013f;
pd_rom[424] = 32'h0028013f;
pd_rom[425] = 32'h002c863f;
pd_rom[426] = 32'h0028013f;
pd_rom[427] = 32'h0028013f;
pd_rom[428] = 32'h0028013f;
pd_rom[429] = 32'h0028013f;
pd_rom[430] = 32'h0028013f;
pd_rom[431] = 32'h00280123;
pd_rom[432] = 32'h0029013f;
pd_rom[433] = 32'h002d463f;
pd_rom[434] = 32'h0029013f;
pd_rom[435] = 32'h0029013f;
pd_rom[436] = 32'h0029013f;
pd_rom[437] = 32'h0029013f;
pd_rom[438] = 32'h0029013f;
pd_rom[439] = 32'h00290123;
pd_rom[440] = 32'h002a013f;
pd_rom[441] = 32'h002e863f;
pd_rom[442] = 32'h002a013f;
pd_rom[443] = 32'h002a013f;
pd_rom[444] = 32'h002a013f;
pd_rom[445] = 32'h002a013f;
pd_rom[446] = 32'h002a013f;
pd_rom[447] = 32'h002a0123;
pd_rom[448] = 32'h0006d120;
pd_rom[449] = 32'h0006d120;
pd_rom[450] = 32'h0006d13f;
pd_rom[451] = 32'h0006d13f;
pd_rom[452] = 32'h0006d13f;
pd_rom[453] = 32'h0006d13f;
pd_rom[454] = 32'h0006d13f;
pd_rom[455] = 32'h0006d123;
pd_rom[456] = 32'h000dd120;
pd_rom[457] = 32'h000dd120;
pd_rom[458] = 32'h000dd13f;
pd_rom[459] = 32'h000dd13f;
pd_rom[460] = 32'h000dd13f;
pd_rom[461] = 32'h000dd13f;
pd_rom[462] = 32'h000dd13f;
pd_rom[463] = 32'h000dd123;
pd_rom[464] = 32'h0014d120;
pd_rom[465] = 32'h0014d120;
pd_rom[466] = 32'h0014d13f;
pd_rom[467] = 32'h0014d13f;
pd_rom[468] = 32'h0014d13f;
pd_rom[469] = 32'h0014d13f;
pd_rom[470] = 32'h0014d13f;
pd_rom[471] = 32'h0014d123;
pd_rom[472] = 32'h00209120;
pd_rom[473] = 32'h00209120;
pd_rom[474] = 32'h0020913f;
pd_rom[475] = 32'h0020913f;
pd_rom[476] = 32'h0020913f;
pd_rom[477] = 32'h0020913f;
pd_rom[478] = 32'h0020913f;
pd_rom[479] = 32'h4e209123;
pd_rom[480] = 32'h0027013f;
pd_rom[481] = 32'h002b463f;
pd_rom[482] = 32'h0027013f;
pd_rom[483] = 32'h0027013f;
pd_rom[484] = 32'h0027013f;
pd_rom[485] = 32'h0027013f;
pd_rom[486] = 32'h0027013f;
pd_rom[487] = 32'h0027013f;
pd_rom[488] = 32'h0028013f;
pd_rom[489] = 32'h002c863f;
pd_rom[490] = 32'h0028013f;
pd_rom[491] = 32'h0028013f;
pd_rom[492] = 32'h0028013f;
pd_rom[493] = 32'h0028013f;
pd_rom[494] = 32'h0028013f;
pd_rom[495] = 32'h00280123;
pd_rom[496] = 32'h0029013f;
pd_rom[497] = 32'h002d463f;
pd_rom[498] = 32'h0029013f;
pd_rom[499] = 32'h0029013f;
pd_rom[500] = 32'h0029013f;
pd_rom[501] = 32'h0029013f;
pd_rom[502] = 32'h0029013f;
pd_rom[503] = 32'h00290123;
pd_rom[504] = 32'h002a013f;
pd_rom[505] = 32'h002e863f;
pd_rom[506] = 32'h002a013f;
pd_rom[507] = 32'h002a013f;
pd_rom[508] = 32'h002a013f;
pd_rom[509] = 32'h002a013f;
pd_rom[510] = 32'h002a013f;
pd_rom[511] = 32'h002a0123;
pd_rom[512] = 32'h002f01bf;
pd_rom[513] = 32'h002f01a0;
pd_rom[514] = 32'h002f01bf;
pd_rom[515] = 32'h002f01bf;
pd_rom[516] = 32'h002f01bf;
pd_rom[517] = 32'h002f01bf;
pd_rom[518] = 32'h002f01bf;
pd_rom[519] = 32'h002f01bf;
pd_rom[520] = 32'h002f019f;
pd_rom[521] = 32'h002f0180;
pd_rom[522] = 32'h002f019f;
pd_rom[523] = 32'h002f019f;
pd_rom[524] = 32'h002f019f;
pd_rom[525] = 32'h002f019f;
pd_rom[526] = 32'h002f019f;
pd_rom[527] = 32'h002f019f;
pd_rom[528] = 32'h002f01bf;
pd_rom[529] = 32'h002f01a0;
pd_rom[530] = 32'h002f01bf;
pd_rom[531] = 32'h002f01bf;
pd_rom[532] = 32'h002f01bf;
pd_rom[533] = 32'h002f01bf;
pd_rom[534] = 32'h002f01bf;
pd_rom[535] = 32'h002f01bf;
pd_rom[536] = 32'h002f01bf;
pd_rom[537] = 32'h002f01a0;
pd_rom[538] = 32'h002f01bf;
pd_rom[539] = 32'h002f01bf;
pd_rom[540] = 32'h002f01bf;
pd_rom[541] = 32'h002f01bf;
pd_rom[542] = 32'h002f01bf;
pd_rom[543] = 32'h002f01bf;
pd_rom[544] = 32'h002f01bf;
pd_rom[545] = 32'h002f01a0;
pd_rom[546] = 32'h002f01bf;
pd_rom[547] = 32'h002f01bf;
pd_rom[548] = 32'h002f01bf;
pd_rom[549] = 32'h002f01bf;
pd_rom[550] = 32'h002f01bf;
pd_rom[551] = 32'h002f01bf;
pd_rom[552] = 32'h002f01bf;
pd_rom[553] = 32'h002f01a0;
pd_rom[554] = 32'h002f01bf;
pd_rom[555] = 32'h002f01bf;
pd_rom[556] = 32'h002f01bf;
pd_rom[557] = 32'h002f01bf;
pd_rom[558] = 32'h002f01bf;
pd_rom[559] = 32'h002f01bf;
pd_rom[560] = 32'h002f01bf;
pd_rom[561] = 32'h002f01a0;
pd_rom[562] = 32'h002f01bf;
pd_rom[563] = 32'h002f01bf;
pd_rom[564] = 32'h002f01bf;
pd_rom[565] = 32'h002f01bf;
pd_rom[566] = 32'h002f01bf;
pd_rom[567] = 32'h002f01bf;
pd_rom[568] = 32'h002f01bf;
pd_rom[569] = 32'h002f01a0;
pd_rom[570] = 32'h002f01bf;
pd_rom[571] = 32'h002f01bf;
pd_rom[572] = 32'h002f01bf;
pd_rom[573] = 32'h002f01bf;
pd_rom[574] = 32'h002f01bf;
pd_rom[575] = 32'h002f01bf;
pd_rom[576] = 32'h002f01bf;
pd_rom[577] = 32'h002f01a0;
pd_rom[578] = 32'h002f01bf;
pd_rom[579] = 32'h002f01bf;
pd_rom[580] = 32'h002f01bf;
pd_rom[581] = 32'h002f01bf;
pd_rom[582] = 32'h002f01bf;
pd_rom[583] = 32'h002f01bf;
pd_rom[584] = 32'h002f019f;
pd_rom[585] = 32'h002f0180;
pd_rom[586] = 32'h002f019f;
pd_rom[587] = 32'h002f019f;
pd_rom[588] = 32'h002f019f;
pd_rom[589] = 32'h002f019f;
pd_rom[590] = 32'h002f019f;
pd_rom[591] = 32'h002f019f;
pd_rom[592] = 32'h002f01bf;
pd_rom[593] = 32'h002f01a0;
pd_rom[594] = 32'h002f01bf;
pd_rom[595] = 32'h002f01bf;
pd_rom[596] = 32'h002f01bf;
pd_rom[597] = 32'h002f01bf;
pd_rom[598] = 32'h002f01bf;
pd_rom[599] = 32'h002f01bf;
pd_rom[600] = 32'h002f01bf;
pd_rom[601] = 32'h002f01a0;
pd_rom[602] = 32'h002f01bf;
pd_rom[603] = 32'h002f01bf;
pd_rom[604] = 32'h002f01bf;
pd_rom[605] = 32'h002f01bf;
pd_rom[606] = 32'h002f01bf;
pd_rom[607] = 32'h002f01bf;
pd_rom[608] = 32'h002f01bf;
pd_rom[609] = 32'h002f01a0;
pd_rom[610] = 32'h002f01bf;
pd_rom[611] = 32'h002f01bf;
pd_rom[612] = 32'h002f01bf;
pd_rom[613] = 32'h002f01bf;
pd_rom[614] = 32'h002f01bf;
pd_rom[615] = 32'h002f01bf;
pd_rom[616] = 32'h002f01bf;
pd_rom[617] = 32'h002f01a0;
pd_rom[618] = 32'h002f01bf;
pd_rom[619] = 32'h002f01bf;
pd_rom[620] = 32'h002f01bf;
pd_rom[621] = 32'h002f01bf;
pd_rom[622] = 32'h002f01bf;
pd_rom[623] = 32'h002f01bf;
pd_rom[624] = 32'h002f01bf;
pd_rom[625] = 32'h002f01a0;
pd_rom[626] = 32'h002f01bf;
pd_rom[627] = 32'h002f01bf;
pd_rom[628] = 32'h002f01bf;
pd_rom[629] = 32'h002f01bf;
pd_rom[630] = 32'h002f01bf;
pd_rom[631] = 32'h002f01bf;
pd_rom[632] = 32'h002f01bf;
pd_rom[633] = 32'h002f01a0;
pd_rom[634] = 32'h002f01bf;
pd_rom[635] = 32'h002f01bf;
pd_rom[636] = 32'h002f01bf;
pd_rom[637] = 32'h002f01bf;
pd_rom[638] = 32'h002f01bf;
pd_rom[639] = 32'h002f01bf;
pd_rom[640] = 32'h002f01bf;
pd_rom[641] = 32'h002f01a0;
pd_rom[642] = 32'h002f01bf;
pd_rom[643] = 32'h002f01bf;
pd_rom[644] = 32'h002f01bf;
pd_rom[645] = 32'h002f01bf;
pd_rom[646] = 32'h002f01bf;
pd_rom[647] = 32'h002f01bf;
pd_rom[648] = 32'h002f019f;
pd_rom[649] = 32'h002f0180;
pd_rom[650] = 32'h002f019f;
pd_rom[651] = 32'h002f019f;
pd_rom[652] = 32'h002f019f;
pd_rom[653] = 32'h002f019f;
pd_rom[654] = 32'h002f019f;
pd_rom[655] = 32'h002f019f;
pd_rom[656] = 32'h002f01bf;
pd_rom[657] = 32'h002f01a0;
pd_rom[658] = 32'h002f01bf;
pd_rom[659] = 32'h002f01bf;
pd_rom[660] = 32'h002f01bf;
pd_rom[661] = 32'h002f01bf;
pd_rom[662] = 32'h002f01bf;
pd_rom[663] = 32'h002f01bf;
pd_rom[664] = 32'h002f01bf;
pd_rom[665] = 32'h002f01a0;
pd_rom[666] = 32'h002f01bf;
pd_rom[667] = 32'h002f01bf;
pd_rom[668] = 32'h002f01bf;
pd_rom[669] = 32'h002f01bf;
pd_rom[670] = 32'h002f01bf;
pd_rom[671] = 32'h002f01bf;
pd_rom[672] = 32'h002f01bf;
pd_rom[673] = 32'h002f01a0;
pd_rom[674] = 32'h002f01bf;
pd_rom[675] = 32'h002f01bf;
pd_rom[676] = 32'h002f01bf;
pd_rom[677] = 32'h002f01bf;
pd_rom[678] = 32'h002f01bf;
pd_rom[679] = 32'h002f01bf;
pd_rom[680] = 32'h002f01bf;
pd_rom[681] = 32'h002f01a0;
pd_rom[682] = 32'h002f01bf;
pd_rom[683] = 32'h002f01bf;
pd_rom[684] = 32'h002f01bf;
pd_rom[685] = 32'h002f01bf;
pd_rom[686] = 32'h002f01bf;
pd_rom[687] = 32'h002f01bf;
pd_rom[688] = 32'h002f01bf;
pd_rom[689] = 32'h002f01a0;
pd_rom[690] = 32'h002f01bf;
pd_rom[691] = 32'h002f01bf;
pd_rom[692] = 32'h002f01bf;
pd_rom[693] = 32'h002f01bf;
pd_rom[694] = 32'h002f01bf;
pd_rom[695] = 32'h002f01bf;
pd_rom[696] = 32'h002f019f;
pd_rom[697] = 32'h002f0180;
pd_rom[698] = 32'h002f019f;
pd_rom[699] = 32'h002f019f;
pd_rom[700] = 32'h002f019f;
pd_rom[701] = 32'h002f019f;
pd_rom[702] = 32'h002f019f;
pd_rom[703] = 32'h002f019f;
pd_rom[704] = 32'h002f01bf;
pd_rom[705] = 32'h002f01a0;
pd_rom[706] = 32'h002f01bf;
pd_rom[707] = 32'h002f01bf;
pd_rom[708] = 32'h002f01bf;
pd_rom[709] = 32'h002f01bf;
pd_rom[710] = 32'h002f01bf;
pd_rom[711] = 32'h002f01bf;
pd_rom[712] = 32'h002f019f;
pd_rom[713] = 32'h002f0180;
pd_rom[714] = 32'h002f019f;
pd_rom[715] = 32'h002f019f;
pd_rom[716] = 32'h002f019f;
pd_rom[717] = 32'h002f019f;
pd_rom[718] = 32'h002f019f;
pd_rom[719] = 32'h002f019f;
pd_rom[720] = 32'h002f01bf;
pd_rom[721] = 32'h002f01a0;
pd_rom[722] = 32'h002f01bf;
pd_rom[723] = 32'h002f01bf;
pd_rom[724] = 32'h002f01bf;
pd_rom[725] = 32'h002f01bf;
pd_rom[726] = 32'h002f01bf;
pd_rom[727] = 32'h002f01bf;
pd_rom[728] = 32'h002f01bf;
pd_rom[729] = 32'h002f01a0;
pd_rom[730] = 32'h002f01bf;
pd_rom[731] = 32'h002f01bf;
pd_rom[732] = 32'h002f01bf;
pd_rom[733] = 32'h002f01bf;
pd_rom[734] = 32'h002f01bf;
pd_rom[735] = 32'h002f01bf;
pd_rom[736] = 32'h002f01bf;
pd_rom[737] = 32'h002f01a0;
pd_rom[738] = 32'h002f01bf;
pd_rom[739] = 32'h002f01bf;
pd_rom[740] = 32'h002f01bf;
pd_rom[741] = 32'h002f01bf;
pd_rom[742] = 32'h002f01bf;
pd_rom[743] = 32'h002f01bf;
pd_rom[744] = 32'h002f01bf;
pd_rom[745] = 32'h002f01a0;
pd_rom[746] = 32'h002f01bf;
pd_rom[747] = 32'h002f01bf;
pd_rom[748] = 32'h002f01bf;
pd_rom[749] = 32'h002f01bf;
pd_rom[750] = 32'h002f01bf;
pd_rom[751] = 32'h002f01bf;
pd_rom[752] = 32'h002f01bf;
pd_rom[753] = 32'h002f01a0;
pd_rom[754] = 32'h002f01bf;
pd_rom[755] = 32'h002f01bf;
pd_rom[756] = 32'h002f01bf;
pd_rom[757] = 32'h002f01bf;
pd_rom[758] = 32'h002f01bf;
pd_rom[759] = 32'h002f01bf;
pd_rom[760] = 32'h002f019f;
pd_rom[761] = 32'h002f0180;
pd_rom[762] = 32'h002f019f;
pd_rom[763] = 32'h002f019f;
pd_rom[764] = 32'h002f019f;
pd_rom[765] = 32'h002f019f;
pd_rom[766] = 32'h002f019f;
pd_rom[767] = 32'h002f019f;
pd_rom[768] = 32'h002f01bf;
pd_rom[769] = 32'h002f01a0;
pd_rom[770] = 32'h002f01bf;
pd_rom[771] = 32'h002f01bf;
pd_rom[772] = 32'h002f01bf;
pd_rom[773] = 32'h002f01bf;
pd_rom[774] = 32'h002f01bf;
pd_rom[775] = 32'h002f01bf;
pd_rom[776] = 32'h002f019f;
pd_rom[777] = 32'h002f0180;
pd_rom[778] = 32'h002f019f;
pd_rom[779] = 32'h002f019f;
pd_rom[780] = 32'h002f019f;
pd_rom[781] = 32'h002f019f;
pd_rom[782] = 32'h002f019f;
pd_rom[783] = 32'h002f019f;
pd_rom[784] = 32'h002f01bf;
pd_rom[785] = 32'h002f01a0;
pd_rom[786] = 32'h002f01bf;
pd_rom[787] = 32'h002f01bf;
pd_rom[788] = 32'h002f01bf;
pd_rom[789] = 32'h002f01bf;
pd_rom[790] = 32'h002f01bf;
pd_rom[791] = 32'h002f01bf;
pd_rom[792] = 32'h002f01bf;
pd_rom[793] = 32'h002f01a0;
pd_rom[794] = 32'h002f01bf;
pd_rom[795] = 32'h002f01bf;
pd_rom[796] = 32'h002f01bf;
pd_rom[797] = 32'h002f01bf;
pd_rom[798] = 32'h002f01bf;
pd_rom[799] = 32'h002f01bf;
pd_rom[800] = 32'h002f01bf;
pd_rom[801] = 32'h002f01a0;
pd_rom[802] = 32'h002f01bf;
pd_rom[803] = 32'h002f01bf;
pd_rom[804] = 32'h002f01bf;
pd_rom[805] = 32'h002f01bf;
pd_rom[806] = 32'h002f01bf;
pd_rom[807] = 32'h002f01bf;
pd_rom[808] = 32'h002f01bf;
pd_rom[809] = 32'h002f01a0;
pd_rom[810] = 32'h002f01bf;
pd_rom[811] = 32'h002f01bf;
pd_rom[812] = 32'h002f01bf;
pd_rom[813] = 32'h002f01bf;
pd_rom[814] = 32'h002f01bf;
pd_rom[815] = 32'h002f01bf;
pd_rom[816] = 32'h002f01bf;
pd_rom[817] = 32'h002f01a0;
pd_rom[818] = 32'h002f01bf;
pd_rom[819] = 32'h002f01bf;
pd_rom[820] = 32'h002f01bf;
pd_rom[821] = 32'h002f01bf;
pd_rom[822] = 32'h002f01bf;
pd_rom[823] = 32'h002f01bf;
pd_rom[824] = 32'h002f019f;
pd_rom[825] = 32'h002f0180;
pd_rom[826] = 32'h002f019f;
pd_rom[827] = 32'h002f019f;
pd_rom[828] = 32'h002f019f;
pd_rom[829] = 32'h002f019f;
pd_rom[830] = 32'h002f019f;
pd_rom[831] = 32'h002f019f;
pd_rom[832] = 32'h002f01bf;
pd_rom[833] = 32'h002f01a0;
pd_rom[834] = 32'h002f01bf;
pd_rom[835] = 32'h002f01bf;
pd_rom[836] = 32'h002f01bf;
pd_rom[837] = 32'h002f01bf;
pd_rom[838] = 32'h002f01bf;
pd_rom[839] = 32'h002f01bf;
pd_rom[840] = 32'h002f019f;
pd_rom[841] = 32'h002f0180;
pd_rom[842] = 32'h002f019f;
pd_rom[843] = 32'h002f019f;
pd_rom[844] = 32'h002f019f;
pd_rom[845] = 32'h002f019f;
pd_rom[846] = 32'h002f019f;
pd_rom[847] = 32'h002f019f;
pd_rom[848] = 32'h002f01bf;
pd_rom[849] = 32'h002f01a0;
pd_rom[850] = 32'h002f01bf;
pd_rom[851] = 32'h002f01bf;
pd_rom[852] = 32'h002f01bf;
pd_rom[853] = 32'h002f01bf;
pd_rom[854] = 32'h002f01bf;
pd_rom[855] = 32'h002f01bf;
pd_rom[856] = 32'h002f01bf;
pd_rom[857] = 32'h002f01a0;
pd_rom[858] = 32'h002f01bf;
pd_rom[859] = 32'h002f01bf;
pd_rom[860] = 32'h002f01bf;
pd_rom[861] = 32'h002f01bf;
pd_rom[862] = 32'h002f01bf;
pd_rom[863] = 32'h002f01bf;
pd_rom[864] = 32'h002f01bf;
pd_rom[865] = 32'h002f01a0;
pd_rom[866] = 32'h002f01bf;
pd_rom[867] = 32'h002f01bf;
pd_rom[868] = 32'h002f01bf;
pd_rom[869] = 32'h002f01bf;
pd_rom[870] = 32'h002f01bf;
pd_rom[871] = 32'h002f01bf;
pd_rom[872] = 32'h002f01bf;
pd_rom[873] = 32'h002f01a0;
pd_rom[874] = 32'h002f01bf;
pd_rom[875] = 32'h002f01bf;
pd_rom[876] = 32'h002f01bf;
pd_rom[877] = 32'h002f01bf;
pd_rom[878] = 32'h002f01bf;
pd_rom[879] = 32'h002f01bf;
pd_rom[880] = 32'h002f01bf;
pd_rom[881] = 32'h002f01a0;
pd_rom[882] = 32'h002f01bf;
pd_rom[883] = 32'h002f01bf;
pd_rom[884] = 32'h002f01bf;
pd_rom[885] = 32'h002f01bf;
pd_rom[886] = 32'h002f01bf;
pd_rom[887] = 32'h002f01bf;
pd_rom[888] = 32'h002f019f;
pd_rom[889] = 32'h002f0180;
pd_rom[890] = 32'h002f019f;
pd_rom[891] = 32'h002f019f;
pd_rom[892] = 32'h002f019f;
pd_rom[893] = 32'h002f019f;
pd_rom[894] = 32'h002f019f;
pd_rom[895] = 32'h002f019f;
pd_rom[896] = 32'h002f01bf;
pd_rom[897] = 32'h002f01a0;
pd_rom[898] = 32'h002f01bf;
pd_rom[899] = 32'h002f01bf;
pd_rom[900] = 32'h002f01bf;
pd_rom[901] = 32'h002f01bf;
pd_rom[902] = 32'h002f01bf;
pd_rom[903] = 32'h002f01bf;
pd_rom[904] = 32'h002f019f;
pd_rom[905] = 32'h002f0180;
pd_rom[906] = 32'h002f019f;
pd_rom[907] = 32'h002f019f;
pd_rom[908] = 32'h002f019f;
pd_rom[909] = 32'h002f019f;
pd_rom[910] = 32'h002f019f;
pd_rom[911] = 32'h002f019f;
pd_rom[912] = 32'h002f01bf;
pd_rom[913] = 32'h002f01a0;
pd_rom[914] = 32'h002f01bf;
pd_rom[915] = 32'h002f01bf;
pd_rom[916] = 32'h002f01bf;
pd_rom[917] = 32'h002f01bf;
pd_rom[918] = 32'h002f01bf;
pd_rom[919] = 32'h002f01bf;
pd_rom[920] = 32'h002f01bf;
pd_rom[921] = 32'h002f01a0;
pd_rom[922] = 32'h002f01bf;
pd_rom[923] = 32'h002f01bf;
pd_rom[924] = 32'h002f01bf;
pd_rom[925] = 32'h002f01bf;
pd_rom[926] = 32'h002f01bf;
pd_rom[927] = 32'h002f01bf;
pd_rom[928] = 32'h002f01bf;
pd_rom[929] = 32'h002f01a0;
pd_rom[930] = 32'h002f01bf;
pd_rom[931] = 32'h002f01bf;
pd_rom[932] = 32'h002f01bf;
pd_rom[933] = 32'h002f01bf;
pd_rom[934] = 32'h002f01bf;
pd_rom[935] = 32'h002f01bf;
pd_rom[936] = 32'h002f01bf;
pd_rom[937] = 32'h002f01a0;
pd_rom[938] = 32'h002f01bf;
pd_rom[939] = 32'h002f01bf;
pd_rom[940] = 32'h002f01bf;
pd_rom[941] = 32'h002f01bf;
pd_rom[942] = 32'h002f01bf;
pd_rom[943] = 32'h002f01bf;
pd_rom[944] = 32'h002f01bf;
pd_rom[945] = 32'h002f01a0;
pd_rom[946] = 32'h002f01bf;
pd_rom[947] = 32'h002f01bf;
pd_rom[948] = 32'h002f01bf;
pd_rom[949] = 32'h002f01bf;
pd_rom[950] = 32'h002f01bf;
pd_rom[951] = 32'h002f01bf;
pd_rom[952] = 32'h002f019f;
pd_rom[953] = 32'h002f0180;
pd_rom[954] = 32'h002f019f;
pd_rom[955] = 32'h002f019f;
pd_rom[956] = 32'h002f019f;
pd_rom[957] = 32'h002f019f;
pd_rom[958] = 32'h002f019f;
pd_rom[959] = 32'h002f019f;
pd_rom[960] = 32'h002f01bf;
pd_rom[961] = 32'h002f01a0;
pd_rom[962] = 32'h002f01bf;
pd_rom[963] = 32'h002f01bf;
pd_rom[964] = 32'h002f01bf;
pd_rom[965] = 32'h002f01bf;
pd_rom[966] = 32'h002f01bf;
pd_rom[967] = 32'h002f01bf;
pd_rom[968] = 32'h002f019f;
pd_rom[969] = 32'h002f0180;
pd_rom[970] = 32'h002f019f;
pd_rom[971] = 32'h002f019f;
pd_rom[972] = 32'h002f019f;
pd_rom[973] = 32'h002f019f;
pd_rom[974] = 32'h002f019f;
pd_rom[975] = 32'h002f019f;
pd_rom[976] = 32'h002f01bf;
pd_rom[977] = 32'h002f01a0;
pd_rom[978] = 32'h002f01bf;
pd_rom[979] = 32'h002f01bf;
pd_rom[980] = 32'h002f01bf;
pd_rom[981] = 32'h002f01bf;
pd_rom[982] = 32'h002f01bf;
pd_rom[983] = 32'h002f01bf;
pd_rom[984] = 32'h002f01bf;
pd_rom[985] = 32'h002f01a0;
pd_rom[986] = 32'h002f01bf;
pd_rom[987] = 32'h002f01bf;
pd_rom[988] = 32'h002f01bf;
pd_rom[989] = 32'h002f01bf;
pd_rom[990] = 32'h002f01bf;
pd_rom[991] = 32'h002f01bf;
pd_rom[992] = 32'h002f01bf;
pd_rom[993] = 32'h002f01a0;
pd_rom[994] = 32'h002f01bf;
pd_rom[995] = 32'h002f01bf;
pd_rom[996] = 32'h002f01bf;
pd_rom[997] = 32'h002f01bf;
pd_rom[998] = 32'h002f01bf;
pd_rom[999] = 32'h002f01bf;
pd_rom[1000] = 32'h002f01bf;
pd_rom[1001] = 32'h002f01a0;
pd_rom[1002] = 32'h002f01bf;
pd_rom[1003] = 32'h002f01bf;
pd_rom[1004] = 32'h002f01bf;
pd_rom[1005] = 32'h002f01bf;
pd_rom[1006] = 32'h002f01bf;
pd_rom[1007] = 32'h002f01bf;
pd_rom[1008] = 32'h002f01bf;
pd_rom[1009] = 32'h002f01a0;
pd_rom[1010] = 32'h002f01bf;
pd_rom[1011] = 32'h002f01bf;
pd_rom[1012] = 32'h002f01bf;
pd_rom[1013] = 32'h002f01bf;
pd_rom[1014] = 32'h002f01bf;
pd_rom[1015] = 32'h002f01bf;
pd_rom[1016] = 32'h002f019f;
pd_rom[1017] = 32'h002f0180;
pd_rom[1018] = 32'h002f019f;
pd_rom[1019] = 32'h002f019f;
pd_rom[1020] = 32'h002f019f;
pd_rom[1021] = 32'h002f019f;
pd_rom[1022] = 32'h002f019f;
pd_rom[1023] = 32'h002f019f;
pd_rom[1024] = 32'h003181bf;
pd_rom[1025] = 32'h003181bf;
pd_rom[1026] = 32'h003181bf;
pd_rom[1027] = 32'h003181bf;
pd_rom[1028] = 32'h003181bf;
pd_rom[1029] = 32'h003181bf;
pd_rom[1030] = 32'h003181bf;
pd_rom[1031] = 32'h003181bf;
pd_rom[1032] = 32'h0033813f;
pd_rom[1033] = 32'h0033813f;
pd_rom[1034] = 32'h0033813f;
pd_rom[1035] = 32'h0033813f;
pd_rom[1036] = 32'h0033813f;
pd_rom[1037] = 32'h0033813f;
pd_rom[1038] = 32'h0033813f;
pd_rom[1039] = 32'h0033813f;
pd_rom[1040] = 32'h003181bf;
pd_rom[1041] = 32'h003181bf;
pd_rom[1042] = 32'h003181bf;
pd_rom[1043] = 32'h003181bf;
pd_rom[1044] = 32'h003181bf;
pd_rom[1045] = 32'h003181bf;
pd_rom[1046] = 32'h003181bf;
pd_rom[1047] = 32'h003181bf;
pd_rom[1048] = 32'h003181bf;
pd_rom[1049] = 32'h003181bf;
pd_rom[1050] = 32'h003181bf;
pd_rom[1051] = 32'h003181bf;
pd_rom[1052] = 32'h003181bf;
pd_rom[1053] = 32'h003181bf;
pd_rom[1054] = 32'h003181bf;
pd_rom[1055] = 32'h003181bf;
pd_rom[1056] = 32'h003181bf;
pd_rom[1057] = 32'h003181bf;
pd_rom[1058] = 32'h003181bf;
pd_rom[1059] = 32'h003181bf;
pd_rom[1060] = 32'h003181bf;
pd_rom[1061] = 32'h003181bf;
pd_rom[1062] = 32'h003181bf;
pd_rom[1063] = 32'h003181bf;
pd_rom[1064] = 32'h003181bf;
pd_rom[1065] = 32'h003181bf;
pd_rom[1066] = 32'h003181bf;
pd_rom[1067] = 32'h003181bf;
pd_rom[1068] = 32'h003181bf;
pd_rom[1069] = 32'h003181bf;
pd_rom[1070] = 32'h003181bf;
pd_rom[1071] = 32'h003181bf;
pd_rom[1072] = 32'h003181bf;
pd_rom[1073] = 32'h003181bf;
pd_rom[1074] = 32'h003181bf;
pd_rom[1075] = 32'h003181bf;
pd_rom[1076] = 32'h003181bf;
pd_rom[1077] = 32'h003181bf;
pd_rom[1078] = 32'h003181bf;
pd_rom[1079] = 32'h003181bf;
pd_rom[1080] = 32'h003181bf;
pd_rom[1081] = 32'h003181bf;
pd_rom[1082] = 32'h003181bf;
pd_rom[1083] = 32'h003181bf;
pd_rom[1084] = 32'h003181bf;
pd_rom[1085] = 32'h003181bf;
pd_rom[1086] = 32'h003181bf;
pd_rom[1087] = 32'h003181bf;
pd_rom[1088] = 32'h003181bf;
pd_rom[1089] = 32'h003181bf;
pd_rom[1090] = 32'h003181bf;
pd_rom[1091] = 32'h003181bf;
pd_rom[1092] = 32'h003181bf;
pd_rom[1093] = 32'h003181bf;
pd_rom[1094] = 32'h003181bf;
pd_rom[1095] = 32'h003181bf;
pd_rom[1096] = 32'h0033813f;
pd_rom[1097] = 32'h0033813f;
pd_rom[1098] = 32'h0033813f;
pd_rom[1099] = 32'h0033813f;
pd_rom[1100] = 32'h0033813f;
pd_rom[1101] = 32'h0033813f;
pd_rom[1102] = 32'h0033813f;
pd_rom[1103] = 32'h0033813f;
pd_rom[1104] = 32'h003181bf;
pd_rom[1105] = 32'h003181bf;
pd_rom[1106] = 32'h003181bf;
pd_rom[1107] = 32'h003181bf;
pd_rom[1108] = 32'h003181bf;
pd_rom[1109] = 32'h003181bf;
pd_rom[1110] = 32'h003181bf;
pd_rom[1111] = 32'h003181bf;
pd_rom[1112] = 32'h003181bf;
pd_rom[1113] = 32'h003181bf;
pd_rom[1114] = 32'h003181bf;
pd_rom[1115] = 32'h003181bf;
pd_rom[1116] = 32'h003181bf;
pd_rom[1117] = 32'h003181bf;
pd_rom[1118] = 32'h003181bf;
pd_rom[1119] = 32'h003181bf;
pd_rom[1120] = 32'h003181bf;
pd_rom[1121] = 32'h003181bf;
pd_rom[1122] = 32'h003181bf;
pd_rom[1123] = 32'h003181bf;
pd_rom[1124] = 32'h003181bf;
pd_rom[1125] = 32'h003181bf;
pd_rom[1126] = 32'h003181bf;
pd_rom[1127] = 32'h003181bf;
pd_rom[1128] = 32'h003181bf;
pd_rom[1129] = 32'h003181bf;
pd_rom[1130] = 32'h003181bf;
pd_rom[1131] = 32'h003181bf;
pd_rom[1132] = 32'h003181bf;
pd_rom[1133] = 32'h003181bf;
pd_rom[1134] = 32'h003181bf;
pd_rom[1135] = 32'h003181bf;
pd_rom[1136] = 32'h003181bf;
pd_rom[1137] = 32'h003181bf;
pd_rom[1138] = 32'h003181bf;
pd_rom[1139] = 32'h003181bf;
pd_rom[1140] = 32'h003181bf;
pd_rom[1141] = 32'h003181bf;
pd_rom[1142] = 32'h003181bf;
pd_rom[1143] = 32'h003181bf;
pd_rom[1144] = 32'h003181bf;
pd_rom[1145] = 32'h003181bf;
pd_rom[1146] = 32'h003181bf;
pd_rom[1147] = 32'h003181bf;
pd_rom[1148] = 32'h003181bf;
pd_rom[1149] = 32'h003181bf;
pd_rom[1150] = 32'h003181bf;
pd_rom[1151] = 32'h003181bf;
pd_rom[1152] = 32'h003181bf;
pd_rom[1153] = 32'h003181bf;
pd_rom[1154] = 32'h003181bf;
pd_rom[1155] = 32'h003181bf;
pd_rom[1156] = 32'h003181bf;
pd_rom[1157] = 32'h003181bf;
pd_rom[1158] = 32'h003181bf;
pd_rom[1159] = 32'h003181bf;
pd_rom[1160] = 32'h0033813f;
pd_rom[1161] = 32'h0033813f;
pd_rom[1162] = 32'h0033813f;
pd_rom[1163] = 32'h0033813f;
pd_rom[1164] = 32'h0033813f;
pd_rom[1165] = 32'h0033813f;
pd_rom[1166] = 32'h0033813f;
pd_rom[1167] = 32'h0033813f;
pd_rom[1168] = 32'h003181bf;
pd_rom[1169] = 32'h003181bf;
pd_rom[1170] = 32'h003181bf;
pd_rom[1171] = 32'h003181bf;
pd_rom[1172] = 32'h003181bf;
pd_rom[1173] = 32'h003181bf;
pd_rom[1174] = 32'h003181bf;
pd_rom[1175] = 32'h003181bf;
pd_rom[1176] = 32'h003181bf;
pd_rom[1177] = 32'h003181bf;
pd_rom[1178] = 32'h003181bf;
pd_rom[1179] = 32'h003181bf;
pd_rom[1180] = 32'h003181bf;
pd_rom[1181] = 32'h003181bf;
pd_rom[1182] = 32'h003181bf;
pd_rom[1183] = 32'h003181bf;
pd_rom[1184] = 32'h003181bf;
pd_rom[1185] = 32'h003181bf;
pd_rom[1186] = 32'h003181bf;
pd_rom[1187] = 32'h003181bf;
pd_rom[1188] = 32'h003181bf;
pd_rom[1189] = 32'h003181bf;
pd_rom[1190] = 32'h003181bf;
pd_rom[1191] = 32'h003181bf;
pd_rom[1192] = 32'h003181bf;
pd_rom[1193] = 32'h003181bf;
pd_rom[1194] = 32'h003181bf;
pd_rom[1195] = 32'h003181bf;
pd_rom[1196] = 32'h003181bf;
pd_rom[1197] = 32'h003181bf;
pd_rom[1198] = 32'h003181bf;
pd_rom[1199] = 32'h003181bf;
pd_rom[1200] = 32'h003181bf;
pd_rom[1201] = 32'h003181bf;
pd_rom[1202] = 32'h003181bf;
pd_rom[1203] = 32'h003181bf;
pd_rom[1204] = 32'h003181bf;
pd_rom[1205] = 32'h003181bf;
pd_rom[1206] = 32'h003181bf;
pd_rom[1207] = 32'h003181bf;
pd_rom[1208] = 32'h0031819f;
pd_rom[1209] = 32'h0031819f;
pd_rom[1210] = 32'h0031819f;
pd_rom[1211] = 32'h0031819f;
pd_rom[1212] = 32'h0031819f;
pd_rom[1213] = 32'h0031819f;
pd_rom[1214] = 32'h0031819f;
pd_rom[1215] = 32'h0031819f;
pd_rom[1216] = 32'h003181bf;
pd_rom[1217] = 32'h003181bf;
pd_rom[1218] = 32'h003181bf;
pd_rom[1219] = 32'h003181bf;
pd_rom[1220] = 32'h003181bf;
pd_rom[1221] = 32'h003181bf;
pd_rom[1222] = 32'h003181bf;
pd_rom[1223] = 32'h003181bf;
pd_rom[1224] = 32'h0033813f;
pd_rom[1225] = 32'h0033813f;
pd_rom[1226] = 32'h0033813f;
pd_rom[1227] = 32'h0033813f;
pd_rom[1228] = 32'h0033813f;
pd_rom[1229] = 32'h0033813f;
pd_rom[1230] = 32'h0033813f;
pd_rom[1231] = 32'h0033813f;
pd_rom[1232] = 32'h003181bf;
pd_rom[1233] = 32'h003181bf;
pd_rom[1234] = 32'h003181bf;
pd_rom[1235] = 32'h003181bf;
pd_rom[1236] = 32'h003181bf;
pd_rom[1237] = 32'h003181bf;
pd_rom[1238] = 32'h003181bf;
pd_rom[1239] = 32'h003181bf;
pd_rom[1240] = 32'h003181bf;
pd_rom[1241] = 32'h003181bf;
pd_rom[1242] = 32'h003181bf;
pd_rom[1243] = 32'h003181bf;
pd_rom[1244] = 32'h003181bf;
pd_rom[1245] = 32'h003181bf;
pd_rom[1246] = 32'h003181bf;
pd_rom[1247] = 32'h003181bf;
pd_rom[1248] = 32'h003181bf;
pd_rom[1249] = 32'h003181bf;
pd_rom[1250] = 32'h003181bf;
pd_rom[1251] = 32'h003181bf;
pd_rom[1252] = 32'h003181bf;
pd_rom[1253] = 32'h003181bf;
pd_rom[1254] = 32'h003181bf;
pd_rom[1255] = 32'h003181bf;
pd_rom[1256] = 32'h003181bf;
pd_rom[1257] = 32'h003181bf;
pd_rom[1258] = 32'h003181bf;
pd_rom[1259] = 32'h003181bf;
pd_rom[1260] = 32'h003181bf;
pd_rom[1261] = 32'h003181bf;
pd_rom[1262] = 32'h003181bf;
pd_rom[1263] = 32'h003181bf;
pd_rom[1264] = 32'h003181bf;
pd_rom[1265] = 32'h003181bf;
pd_rom[1266] = 32'h003181bf;
pd_rom[1267] = 32'h003181bf;
pd_rom[1268] = 32'h003181bf;
pd_rom[1269] = 32'h003181bf;
pd_rom[1270] = 32'h003181bf;
pd_rom[1271] = 32'h003181bf;
pd_rom[1272] = 32'h0031819f;
pd_rom[1273] = 32'h0031819f;
pd_rom[1274] = 32'h0031819f;
pd_rom[1275] = 32'h0031819f;
pd_rom[1276] = 32'h0031819f;
pd_rom[1277] = 32'h0031819f;
pd_rom[1278] = 32'h0031819f;
pd_rom[1279] = 32'h0031819f;
pd_rom[1280] = 32'h003181bf;
pd_rom[1281] = 32'h003181bf;
pd_rom[1282] = 32'h003181bf;
pd_rom[1283] = 32'h003181bf;
pd_rom[1284] = 32'h003181bf;
pd_rom[1285] = 32'h003181bf;
pd_rom[1286] = 32'h003181bf;
pd_rom[1287] = 32'h003181bf;
pd_rom[1288] = 32'h0033813f;
pd_rom[1289] = 32'h0033813f;
pd_rom[1290] = 32'h0033813f;
pd_rom[1291] = 32'h0033813f;
pd_rom[1292] = 32'h0033813f;
pd_rom[1293] = 32'h0033813f;
pd_rom[1294] = 32'h0033813f;
pd_rom[1295] = 32'h0033813f;
pd_rom[1296] = 32'h003181bf;
pd_rom[1297] = 32'h003181bf;
pd_rom[1298] = 32'h003181bf;
pd_rom[1299] = 32'h003181bf;
pd_rom[1300] = 32'h003181bf;
pd_rom[1301] = 32'h003181bf;
pd_rom[1302] = 32'h003181bf;
pd_rom[1303] = 32'h003181bf;
pd_rom[1304] = 32'h003181bf;
pd_rom[1305] = 32'h003181bf;
pd_rom[1306] = 32'h003181bf;
pd_rom[1307] = 32'h003181bf;
pd_rom[1308] = 32'h003181bf;
pd_rom[1309] = 32'h003181bf;
pd_rom[1310] = 32'h003181bf;
pd_rom[1311] = 32'h003181bf;
pd_rom[1312] = 32'h003181bf;
pd_rom[1313] = 32'h003181bf;
pd_rom[1314] = 32'h003181bf;
pd_rom[1315] = 32'h003181bf;
pd_rom[1316] = 32'h003181bf;
pd_rom[1317] = 32'h003181bf;
pd_rom[1318] = 32'h003181bf;
pd_rom[1319] = 32'h003181bf;
pd_rom[1320] = 32'h003181bf;
pd_rom[1321] = 32'h003181bf;
pd_rom[1322] = 32'h003181bf;
pd_rom[1323] = 32'h003181bf;
pd_rom[1324] = 32'h003181bf;
pd_rom[1325] = 32'h003181bf;
pd_rom[1326] = 32'h003181bf;
pd_rom[1327] = 32'h003181bf;
pd_rom[1328] = 32'h003181bf;
pd_rom[1329] = 32'h003181bf;
pd_rom[1330] = 32'h003181bf;
pd_rom[1331] = 32'h003181bf;
pd_rom[1332] = 32'h003181bf;
pd_rom[1333] = 32'h003181bf;
pd_rom[1334] = 32'h003181bf;
pd_rom[1335] = 32'h003181bf;
pd_rom[1336] = 32'h0031819f;
pd_rom[1337] = 32'h0031819f;
pd_rom[1338] = 32'h0031819f;
pd_rom[1339] = 32'h0031819f;
pd_rom[1340] = 32'h0031819f;
pd_rom[1341] = 32'h0031819f;
pd_rom[1342] = 32'h0031819f;
pd_rom[1343] = 32'h0031819f;
pd_rom[1344] = 32'h003181bf;
pd_rom[1345] = 32'h003181bf;
pd_rom[1346] = 32'h003181bf;
pd_rom[1347] = 32'h003181bf;
pd_rom[1348] = 32'h003181bf;
pd_rom[1349] = 32'h003181bf;
pd_rom[1350] = 32'h003181bf;
pd_rom[1351] = 32'h003181bf;
pd_rom[1352] = 32'h0033813f;
pd_rom[1353] = 32'h0033813f;
pd_rom[1354] = 32'h0033813f;
pd_rom[1355] = 32'h0033813f;
pd_rom[1356] = 32'h0033813f;
pd_rom[1357] = 32'h0033813f;
pd_rom[1358] = 32'h0033813f;
pd_rom[1359] = 32'h0033813f;
pd_rom[1360] = 32'h003181bf;
pd_rom[1361] = 32'h003181bf;
pd_rom[1362] = 32'h003181bf;
pd_rom[1363] = 32'h003181bf;
pd_rom[1364] = 32'h003181bf;
pd_rom[1365] = 32'h003181bf;
pd_rom[1366] = 32'h003181bf;
pd_rom[1367] = 32'h003181bf;
pd_rom[1368] = 32'h003181bf;
pd_rom[1369] = 32'h003181bf;
pd_rom[1370] = 32'h003181bf;
pd_rom[1371] = 32'h003181bf;
pd_rom[1372] = 32'h003181bf;
pd_rom[1373] = 32'h003181bf;
pd_rom[1374] = 32'h003181bf;
pd_rom[1375] = 32'h003181bf;
pd_rom[1376] = 32'h003181bf;
pd_rom[1377] = 32'h003181bf;
pd_rom[1378] = 32'h003181bf;
pd_rom[1379] = 32'h003181bf;
pd_rom[1380] = 32'h003181bf;
pd_rom[1381] = 32'h003181bf;
pd_rom[1382] = 32'h003181bf;
pd_rom[1383] = 32'h003181bf;
pd_rom[1384] = 32'h003181bf;
pd_rom[1385] = 32'h003181bf;
pd_rom[1386] = 32'h003181bf;
pd_rom[1387] = 32'h003181bf;
pd_rom[1388] = 32'h003181bf;
pd_rom[1389] = 32'h003181bf;
pd_rom[1390] = 32'h003181bf;
pd_rom[1391] = 32'h003181bf;
pd_rom[1392] = 32'h003181bf;
pd_rom[1393] = 32'h003181bf;
pd_rom[1394] = 32'h003181bf;
pd_rom[1395] = 32'h003181bf;
pd_rom[1396] = 32'h003181bf;
pd_rom[1397] = 32'h003181bf;
pd_rom[1398] = 32'h003181bf;
pd_rom[1399] = 32'h003181bf;
pd_rom[1400] = 32'h0031819f;
pd_rom[1401] = 32'h0031819f;
pd_rom[1402] = 32'h0031819f;
pd_rom[1403] = 32'h0031819f;
pd_rom[1404] = 32'h0031819f;
pd_rom[1405] = 32'h0031819f;
pd_rom[1406] = 32'h0031819f;
pd_rom[1407] = 32'h0031819f;
pd_rom[1408] = 32'h003181bf;
pd_rom[1409] = 32'h003181bf;
pd_rom[1410] = 32'h003181bf;
pd_rom[1411] = 32'h003181bf;
pd_rom[1412] = 32'h003181bf;
pd_rom[1413] = 32'h003181bf;
pd_rom[1414] = 32'h003181bf;
pd_rom[1415] = 32'h003181bf;
pd_rom[1416] = 32'h0033813f;
pd_rom[1417] = 32'h0033813f;
pd_rom[1418] = 32'h0033813f;
pd_rom[1419] = 32'h0033813f;
pd_rom[1420] = 32'h0033813f;
pd_rom[1421] = 32'h0033813f;
pd_rom[1422] = 32'h0033813f;
pd_rom[1423] = 32'h0033813f;
pd_rom[1424] = 32'h003181bf;
pd_rom[1425] = 32'h003181bf;
pd_rom[1426] = 32'h003181bf;
pd_rom[1427] = 32'h003181bf;
pd_rom[1428] = 32'h003181bf;
pd_rom[1429] = 32'h003181bf;
pd_rom[1430] = 32'h003181bf;
pd_rom[1431] = 32'h003181bf;
pd_rom[1432] = 32'h003181bf;
pd_rom[1433] = 32'h003181bf;
pd_rom[1434] = 32'h003181bf;
pd_rom[1435] = 32'h003181bf;
pd_rom[1436] = 32'h003181bf;
pd_rom[1437] = 32'h003181bf;
pd_rom[1438] = 32'h003181bf;
pd_rom[1439] = 32'h003181bf;
pd_rom[1440] = 32'h003181bf;
pd_rom[1441] = 32'h003181bf;
pd_rom[1442] = 32'h003181bf;
pd_rom[1443] = 32'h003181bf;
pd_rom[1444] = 32'h003181bf;
pd_rom[1445] = 32'h003181bf;
pd_rom[1446] = 32'h003181bf;
pd_rom[1447] = 32'h003181bf;
pd_rom[1448] = 32'h003181bf;
pd_rom[1449] = 32'h003181bf;
pd_rom[1450] = 32'h003181bf;
pd_rom[1451] = 32'h003181bf;
pd_rom[1452] = 32'h003181bf;
pd_rom[1453] = 32'h003181bf;
pd_rom[1454] = 32'h003181bf;
pd_rom[1455] = 32'h003181bf;
pd_rom[1456] = 32'h003181bf;
pd_rom[1457] = 32'h003181bf;
pd_rom[1458] = 32'h003181bf;
pd_rom[1459] = 32'h003181bf;
pd_rom[1460] = 32'h003181bf;
pd_rom[1461] = 32'h003181bf;
pd_rom[1462] = 32'h003181bf;
pd_rom[1463] = 32'h003181bf;
pd_rom[1464] = 32'h0031819f;
pd_rom[1465] = 32'h0031819f;
pd_rom[1466] = 32'h0031819f;
pd_rom[1467] = 32'h0031819f;
pd_rom[1468] = 32'h0031819f;
pd_rom[1469] = 32'h0031819f;
pd_rom[1470] = 32'h0031819f;
pd_rom[1471] = 32'h0031819f;
pd_rom[1472] = 32'h003181bf;
pd_rom[1473] = 32'h003181bf;
pd_rom[1474] = 32'h003181bf;
pd_rom[1475] = 32'h003181bf;
pd_rom[1476] = 32'h003181bf;
pd_rom[1477] = 32'h003181bf;
pd_rom[1478] = 32'h003181bf;
pd_rom[1479] = 32'h003181bf;
pd_rom[1480] = 32'h0033813f;
pd_rom[1481] = 32'h0033813f;
pd_rom[1482] = 32'h0033813f;
pd_rom[1483] = 32'h0033813f;
pd_rom[1484] = 32'h0033813f;
pd_rom[1485] = 32'h0033813f;
pd_rom[1486] = 32'h0033813f;
pd_rom[1487] = 32'h0033813f;
pd_rom[1488] = 32'h003181bf;
pd_rom[1489] = 32'h003181bf;
pd_rom[1490] = 32'h003181bf;
pd_rom[1491] = 32'h003181bf;
pd_rom[1492] = 32'h003181bf;
pd_rom[1493] = 32'h003181bf;
pd_rom[1494] = 32'h003181bf;
pd_rom[1495] = 32'h003181bf;
pd_rom[1496] = 32'h003181bf;
pd_rom[1497] = 32'h003181bf;
pd_rom[1498] = 32'h003181bf;
pd_rom[1499] = 32'h003181bf;
pd_rom[1500] = 32'h003181bf;
pd_rom[1501] = 32'h003181bf;
pd_rom[1502] = 32'h003181bf;
pd_rom[1503] = 32'h003181bf;
pd_rom[1504] = 32'h003181bf;
pd_rom[1505] = 32'h003181bf;
pd_rom[1506] = 32'h003181bf;
pd_rom[1507] = 32'h003181bf;
pd_rom[1508] = 32'h003181bf;
pd_rom[1509] = 32'h003181bf;
pd_rom[1510] = 32'h003181bf;
pd_rom[1511] = 32'h003181bf;
pd_rom[1512] = 32'h003181bf;
pd_rom[1513] = 32'h003181bf;
pd_rom[1514] = 32'h003181bf;
pd_rom[1515] = 32'h003181bf;
pd_rom[1516] = 32'h003181bf;
pd_rom[1517] = 32'h003181bf;
pd_rom[1518] = 32'h003181bf;
pd_rom[1519] = 32'h003181bf;
pd_rom[1520] = 32'h003181bf;
pd_rom[1521] = 32'h003181bf;
pd_rom[1522] = 32'h003181bf;
pd_rom[1523] = 32'h003181bf;
pd_rom[1524] = 32'h003181bf;
pd_rom[1525] = 32'h003181bf;
pd_rom[1526] = 32'h003181bf;
pd_rom[1527] = 32'h003181bf;
pd_rom[1528] = 32'h0031819f;
pd_rom[1529] = 32'h0031819f;
pd_rom[1530] = 32'h0031819f;
pd_rom[1531] = 32'h0031819f;
pd_rom[1532] = 32'h0031819f;
pd_rom[1533] = 32'h0031819f;
pd_rom[1534] = 32'h0031819f;
pd_rom[1535] = 32'h0031819f;
pd_rom[1536] = 32'h003041bf;
pd_rom[1537] = 32'h003041bf;
pd_rom[1538] = 32'h003041bf;
pd_rom[1539] = 32'h003041bf;
pd_rom[1540] = 32'h003041bf;
pd_rom[1541] = 32'h003041bf;
pd_rom[1542] = 32'h003041bf;
pd_rom[1543] = 32'h003041bf;
pd_rom[1544] = 32'h0032413f;
pd_rom[1545] = 32'h0032413f;
pd_rom[1546] = 32'h0032413f;
pd_rom[1547] = 32'h0032413f;
pd_rom[1548] = 32'h0032413f;
pd_rom[1549] = 32'h0032413f;
pd_rom[1550] = 32'h0032413f;
pd_rom[1551] = 32'h0032413f;
pd_rom[1552] = 32'h003041bf;
pd_rom[1553] = 32'h003041bf;
pd_rom[1554] = 32'h003041bf;
pd_rom[1555] = 32'h003041bf;
pd_rom[1556] = 32'h003041bf;
pd_rom[1557] = 32'h003041bf;
pd_rom[1558] = 32'h003041bf;
pd_rom[1559] = 32'h003041bf;
pd_rom[1560] = 32'h003041bf;
pd_rom[1561] = 32'h003041bf;
pd_rom[1562] = 32'h003041bf;
pd_rom[1563] = 32'h003041bf;
pd_rom[1564] = 32'h003041bf;
pd_rom[1565] = 32'h003041bf;
pd_rom[1566] = 32'h003041bf;
pd_rom[1567] = 32'h003041bf;
pd_rom[1568] = 32'h003041bf;
pd_rom[1569] = 32'h003041bf;
pd_rom[1570] = 32'h003041bf;
pd_rom[1571] = 32'h003041bf;
pd_rom[1572] = 32'h003041bf;
pd_rom[1573] = 32'h003041bf;
pd_rom[1574] = 32'h003041bf;
pd_rom[1575] = 32'h003041bf;
pd_rom[1576] = 32'h003041bf;
pd_rom[1577] = 32'h003041bf;
pd_rom[1578] = 32'h003041bf;
pd_rom[1579] = 32'h003041bf;
pd_rom[1580] = 32'h003041bf;
pd_rom[1581] = 32'h003041bf;
pd_rom[1582] = 32'h003041bf;
pd_rom[1583] = 32'h003041bf;
pd_rom[1584] = 32'h003041bf;
pd_rom[1585] = 32'h003041bf;
pd_rom[1586] = 32'h003041bf;
pd_rom[1587] = 32'h003041bf;
pd_rom[1588] = 32'h003041bf;
pd_rom[1589] = 32'h003041bf;
pd_rom[1590] = 32'h003041bf;
pd_rom[1591] = 32'h003041bf;
pd_rom[1592] = 32'h003041bf;
pd_rom[1593] = 32'h003041bf;
pd_rom[1594] = 32'h003041bf;
pd_rom[1595] = 32'h003041bf;
pd_rom[1596] = 32'h003041bf;
pd_rom[1597] = 32'h003041bf;
pd_rom[1598] = 32'h003041bf;
pd_rom[1599] = 32'h003041bf;
pd_rom[1600] = 32'h003041bf;
pd_rom[1601] = 32'h003041bf;
pd_rom[1602] = 32'h003041bf;
pd_rom[1603] = 32'h003041bf;
pd_rom[1604] = 32'h003041bf;
pd_rom[1605] = 32'h003041bf;
pd_rom[1606] = 32'h003041bf;
pd_rom[1607] = 32'h003041bf;
pd_rom[1608] = 32'h0032413f;
pd_rom[1609] = 32'h0032413f;
pd_rom[1610] = 32'h0032413f;
pd_rom[1611] = 32'h0032413f;
pd_rom[1612] = 32'h0032413f;
pd_rom[1613] = 32'h0032413f;
pd_rom[1614] = 32'h0032413f;
pd_rom[1615] = 32'h0032413f;
pd_rom[1616] = 32'h003041bf;
pd_rom[1617] = 32'h003041bf;
pd_rom[1618] = 32'h003041bf;
pd_rom[1619] = 32'h003041bf;
pd_rom[1620] = 32'h003041bf;
pd_rom[1621] = 32'h003041bf;
pd_rom[1622] = 32'h003041bf;
pd_rom[1623] = 32'h003041bf;
pd_rom[1624] = 32'h003041bf;
pd_rom[1625] = 32'h003041bf;
pd_rom[1626] = 32'h003041bf;
pd_rom[1627] = 32'h003041bf;
pd_rom[1628] = 32'h003041bf;
pd_rom[1629] = 32'h003041bf;
pd_rom[1630] = 32'h003041bf;
pd_rom[1631] = 32'h003041bf;
pd_rom[1632] = 32'h003041bf;
pd_rom[1633] = 32'h003041bf;
pd_rom[1634] = 32'h003041bf;
pd_rom[1635] = 32'h003041bf;
pd_rom[1636] = 32'h003041bf;
pd_rom[1637] = 32'h003041bf;
pd_rom[1638] = 32'h003041bf;
pd_rom[1639] = 32'h003041bf;
pd_rom[1640] = 32'h003041bf;
pd_rom[1641] = 32'h003041bf;
pd_rom[1642] = 32'h003041bf;
pd_rom[1643] = 32'h003041bf;
pd_rom[1644] = 32'h003041bf;
pd_rom[1645] = 32'h003041bf;
pd_rom[1646] = 32'h003041bf;
pd_rom[1647] = 32'h003041bf;
pd_rom[1648] = 32'h003041bf;
pd_rom[1649] = 32'h003041bf;
pd_rom[1650] = 32'h003041bf;
pd_rom[1651] = 32'h003041bf;
pd_rom[1652] = 32'h003041bf;
pd_rom[1653] = 32'h003041bf;
pd_rom[1654] = 32'h003041bf;
pd_rom[1655] = 32'h003041bf;
pd_rom[1656] = 32'h003041bf;
pd_rom[1657] = 32'h003041bf;
pd_rom[1658] = 32'h003041bf;
pd_rom[1659] = 32'h003041bf;
pd_rom[1660] = 32'h003041bf;
pd_rom[1661] = 32'h003041bf;
pd_rom[1662] = 32'h003041bf;
pd_rom[1663] = 32'h003041bf;
pd_rom[1664] = 32'h003041bf;
pd_rom[1665] = 32'h003041bf;
pd_rom[1666] = 32'h003041bf;
pd_rom[1667] = 32'h003041bf;
pd_rom[1668] = 32'h003041bf;
pd_rom[1669] = 32'h003041bf;
pd_rom[1670] = 32'h003041bf;
pd_rom[1671] = 32'h003041bf;
pd_rom[1672] = 32'h0032413f;
pd_rom[1673] = 32'h0032413f;
pd_rom[1674] = 32'h0032413f;
pd_rom[1675] = 32'h0032413f;
pd_rom[1676] = 32'h0032413f;
pd_rom[1677] = 32'h0032413f;
pd_rom[1678] = 32'h0032413f;
pd_rom[1679] = 32'h0032413f;
pd_rom[1680] = 32'h003041bf;
pd_rom[1681] = 32'h003041bf;
pd_rom[1682] = 32'h003041bf;
pd_rom[1683] = 32'h003041bf;
pd_rom[1684] = 32'h003041bf;
pd_rom[1685] = 32'h003041bf;
pd_rom[1686] = 32'h003041bf;
pd_rom[1687] = 32'h003041bf;
pd_rom[1688] = 32'h003041bf;
pd_rom[1689] = 32'h003041bf;
pd_rom[1690] = 32'h003041bf;
pd_rom[1691] = 32'h003041bf;
pd_rom[1692] = 32'h003041bf;
pd_rom[1693] = 32'h003041bf;
pd_rom[1694] = 32'h003041bf;
pd_rom[1695] = 32'h003041bf;
pd_rom[1696] = 32'h003041bf;
pd_rom[1697] = 32'h003041bf;
pd_rom[1698] = 32'h003041bf;
pd_rom[1699] = 32'h003041bf;
pd_rom[1700] = 32'h003041bf;
pd_rom[1701] = 32'h003041bf;
pd_rom[1702] = 32'h003041bf;
pd_rom[1703] = 32'h003041bf;
pd_rom[1704] = 32'h003041bf;
pd_rom[1705] = 32'h003041bf;
pd_rom[1706] = 32'h003041bf;
pd_rom[1707] = 32'h003041bf;
pd_rom[1708] = 32'h003041bf;
pd_rom[1709] = 32'h003041bf;
pd_rom[1710] = 32'h003041bf;
pd_rom[1711] = 32'h003041bf;
pd_rom[1712] = 32'h003041bf;
pd_rom[1713] = 32'h003041bf;
pd_rom[1714] = 32'h003041bf;
pd_rom[1715] = 32'h003041bf;
pd_rom[1716] = 32'h003041bf;
pd_rom[1717] = 32'h003041bf;
pd_rom[1718] = 32'h003041bf;
pd_rom[1719] = 32'h003041bf;
pd_rom[1720] = 32'h0030419f;
pd_rom[1721] = 32'h0030419f;
pd_rom[1722] = 32'h0030419f;
pd_rom[1723] = 32'h0030419f;
pd_rom[1724] = 32'h0030419f;
pd_rom[1725] = 32'h0030419f;
pd_rom[1726] = 32'h0030419f;
pd_rom[1727] = 32'h0030419f;
pd_rom[1728] = 32'h003041bf;
pd_rom[1729] = 32'h003041bf;
pd_rom[1730] = 32'h003041bf;
pd_rom[1731] = 32'h003041bf;
pd_rom[1732] = 32'h003041bf;
pd_rom[1733] = 32'h003041bf;
pd_rom[1734] = 32'h003041bf;
pd_rom[1735] = 32'h003041bf;
pd_rom[1736] = 32'h0032413f;
pd_rom[1737] = 32'h0032413f;
pd_rom[1738] = 32'h0032413f;
pd_rom[1739] = 32'h0032413f;
pd_rom[1740] = 32'h0032413f;
pd_rom[1741] = 32'h0032413f;
pd_rom[1742] = 32'h0032413f;
pd_rom[1743] = 32'h0032413f;
pd_rom[1744] = 32'h003041bf;
pd_rom[1745] = 32'h003041bf;
pd_rom[1746] = 32'h003041bf;
pd_rom[1747] = 32'h003041bf;
pd_rom[1748] = 32'h003041bf;
pd_rom[1749] = 32'h003041bf;
pd_rom[1750] = 32'h003041bf;
pd_rom[1751] = 32'h003041bf;
pd_rom[1752] = 32'h003041bf;
pd_rom[1753] = 32'h003041bf;
pd_rom[1754] = 32'h003041bf;
pd_rom[1755] = 32'h003041bf;
pd_rom[1756] = 32'h003041bf;
pd_rom[1757] = 32'h003041bf;
pd_rom[1758] = 32'h003041bf;
pd_rom[1759] = 32'h003041bf;
pd_rom[1760] = 32'h003041bf;
pd_rom[1761] = 32'h003041bf;
pd_rom[1762] = 32'h003041bf;
pd_rom[1763] = 32'h003041bf;
pd_rom[1764] = 32'h003041bf;
pd_rom[1765] = 32'h003041bf;
pd_rom[1766] = 32'h003041bf;
pd_rom[1767] = 32'h003041bf;
pd_rom[1768] = 32'h003041bf;
pd_rom[1769] = 32'h003041bf;
pd_rom[1770] = 32'h003041bf;
pd_rom[1771] = 32'h003041bf;
pd_rom[1772] = 32'h003041bf;
pd_rom[1773] = 32'h003041bf;
pd_rom[1774] = 32'h003041bf;
pd_rom[1775] = 32'h003041bf;
pd_rom[1776] = 32'h003041bf;
pd_rom[1777] = 32'h003041bf;
pd_rom[1778] = 32'h003041bf;
pd_rom[1779] = 32'h003041bf;
pd_rom[1780] = 32'h003041bf;
pd_rom[1781] = 32'h003041bf;
pd_rom[1782] = 32'h003041bf;
pd_rom[1783] = 32'h003041bf;
pd_rom[1784] = 32'h0030419f;
pd_rom[1785] = 32'h0030419f;
pd_rom[1786] = 32'h0030419f;
pd_rom[1787] = 32'h0030419f;
pd_rom[1788] = 32'h0030419f;
pd_rom[1789] = 32'h0030419f;
pd_rom[1790] = 32'h0030419f;
pd_rom[1791] = 32'h0030419f;
pd_rom[1792] = 32'h003041bf;
pd_rom[1793] = 32'h003041bf;
pd_rom[1794] = 32'h003041bf;
pd_rom[1795] = 32'h003041bf;
pd_rom[1796] = 32'h003041bf;
pd_rom[1797] = 32'h003041bf;
pd_rom[1798] = 32'h003041bf;
pd_rom[1799] = 32'h003041bf;
pd_rom[1800] = 32'h0032413f;
pd_rom[1801] = 32'h0032413f;
pd_rom[1802] = 32'h0032413f;
pd_rom[1803] = 32'h0032413f;
pd_rom[1804] = 32'h0032413f;
pd_rom[1805] = 32'h0032413f;
pd_rom[1806] = 32'h0032413f;
pd_rom[1807] = 32'h0032413f;
pd_rom[1808] = 32'h003041bf;
pd_rom[1809] = 32'h003041bf;
pd_rom[1810] = 32'h003041bf;
pd_rom[1811] = 32'h003041bf;
pd_rom[1812] = 32'h003041bf;
pd_rom[1813] = 32'h003041bf;
pd_rom[1814] = 32'h003041bf;
pd_rom[1815] = 32'h003041bf;
pd_rom[1816] = 32'h003041bf;
pd_rom[1817] = 32'h003041bf;
pd_rom[1818] = 32'h003041bf;
pd_rom[1819] = 32'h003041bf;
pd_rom[1820] = 32'h003041bf;
pd_rom[1821] = 32'h003041bf;
pd_rom[1822] = 32'h003041bf;
pd_rom[1823] = 32'h003041bf;
pd_rom[1824] = 32'h003041bf;
pd_rom[1825] = 32'h003041bf;
pd_rom[1826] = 32'h003041bf;
pd_rom[1827] = 32'h003041bf;
pd_rom[1828] = 32'h003041bf;
pd_rom[1829] = 32'h003041bf;
pd_rom[1830] = 32'h003041bf;
pd_rom[1831] = 32'h003041bf;
pd_rom[1832] = 32'h003041bf;
pd_rom[1833] = 32'h003041bf;
pd_rom[1834] = 32'h003041bf;
pd_rom[1835] = 32'h003041bf;
pd_rom[1836] = 32'h003041bf;
pd_rom[1837] = 32'h003041bf;
pd_rom[1838] = 32'h003041bf;
pd_rom[1839] = 32'h003041bf;
pd_rom[1840] = 32'h003041bf;
pd_rom[1841] = 32'h003041bf;
pd_rom[1842] = 32'h003041bf;
pd_rom[1843] = 32'h003041bf;
pd_rom[1844] = 32'h003041bf;
pd_rom[1845] = 32'h003041bf;
pd_rom[1846] = 32'h003041bf;
pd_rom[1847] = 32'h003041bf;
pd_rom[1848] = 32'h0030419f;
pd_rom[1849] = 32'h0030419f;
pd_rom[1850] = 32'h0030419f;
pd_rom[1851] = 32'h0030419f;
pd_rom[1852] = 32'h0030419f;
pd_rom[1853] = 32'h0030419f;
pd_rom[1854] = 32'h0030419f;
pd_rom[1855] = 32'h0030419f;
pd_rom[1856] = 32'h003041bf;
pd_rom[1857] = 32'h003041bf;
pd_rom[1858] = 32'h003041bf;
pd_rom[1859] = 32'h003041bf;
pd_rom[1860] = 32'h003041bf;
pd_rom[1861] = 32'h003041bf;
pd_rom[1862] = 32'h003041bf;
pd_rom[1863] = 32'h003041bf;
pd_rom[1864] = 32'h0032413f;
pd_rom[1865] = 32'h0032413f;
pd_rom[1866] = 32'h0032413f;
pd_rom[1867] = 32'h0032413f;
pd_rom[1868] = 32'h0032413f;
pd_rom[1869] = 32'h0032413f;
pd_rom[1870] = 32'h0032413f;
pd_rom[1871] = 32'h0032413f;
pd_rom[1872] = 32'h003041bf;
pd_rom[1873] = 32'h003041bf;
pd_rom[1874] = 32'h003041bf;
pd_rom[1875] = 32'h003041bf;
pd_rom[1876] = 32'h003041bf;
pd_rom[1877] = 32'h003041bf;
pd_rom[1878] = 32'h003041bf;
pd_rom[1879] = 32'h003041bf;
pd_rom[1880] = 32'h003041bf;
pd_rom[1881] = 32'h003041bf;
pd_rom[1882] = 32'h003041bf;
pd_rom[1883] = 32'h003041bf;
pd_rom[1884] = 32'h003041bf;
pd_rom[1885] = 32'h003041bf;
pd_rom[1886] = 32'h003041bf;
pd_rom[1887] = 32'h003041bf;
pd_rom[1888] = 32'h003041bf;
pd_rom[1889] = 32'h003041bf;
pd_rom[1890] = 32'h003041bf;
pd_rom[1891] = 32'h003041bf;
pd_rom[1892] = 32'h003041bf;
pd_rom[1893] = 32'h003041bf;
pd_rom[1894] = 32'h003041bf;
pd_rom[1895] = 32'h003041bf;
pd_rom[1896] = 32'h003041bf;
pd_rom[1897] = 32'h003041bf;
pd_rom[1898] = 32'h003041bf;
pd_rom[1899] = 32'h003041bf;
pd_rom[1900] = 32'h003041bf;
pd_rom[1901] = 32'h003041bf;
pd_rom[1902] = 32'h003041bf;
pd_rom[1903] = 32'h003041bf;
pd_rom[1904] = 32'h003041bf;
pd_rom[1905] = 32'h003041bf;
pd_rom[1906] = 32'h003041bf;
pd_rom[1907] = 32'h003041bf;
pd_rom[1908] = 32'h003041bf;
pd_rom[1909] = 32'h003041bf;
pd_rom[1910] = 32'h003041bf;
pd_rom[1911] = 32'h003041bf;
pd_rom[1912] = 32'h0030419f;
pd_rom[1913] = 32'h0030419f;
pd_rom[1914] = 32'h0030419f;
pd_rom[1915] = 32'h0030419f;
pd_rom[1916] = 32'h0030419f;
pd_rom[1917] = 32'h0030419f;
pd_rom[1918] = 32'h0030419f;
pd_rom[1919] = 32'h0030419f;
pd_rom[1920] = 32'h003041bf;
pd_rom[1921] = 32'h003041bf;
pd_rom[1922] = 32'h003041bf;
pd_rom[1923] = 32'h003041bf;
pd_rom[1924] = 32'h003041bf;
pd_rom[1925] = 32'h003041bf;
pd_rom[1926] = 32'h003041bf;
pd_rom[1927] = 32'h003041bf;
pd_rom[1928] = 32'h0032413f;
pd_rom[1929] = 32'h0032413f;
pd_rom[1930] = 32'h0032413f;
pd_rom[1931] = 32'h0032413f;
pd_rom[1932] = 32'h0032413f;
pd_rom[1933] = 32'h0032413f;
pd_rom[1934] = 32'h0032413f;
pd_rom[1935] = 32'h0032413f;
pd_rom[1936] = 32'h003041bf;
pd_rom[1937] = 32'h003041bf;
pd_rom[1938] = 32'h003041bf;
pd_rom[1939] = 32'h003041bf;
pd_rom[1940] = 32'h003041bf;
pd_rom[1941] = 32'h003041bf;
pd_rom[1942] = 32'h003041bf;
pd_rom[1943] = 32'h003041bf;
pd_rom[1944] = 32'h003041bf;
pd_rom[1945] = 32'h003041bf;
pd_rom[1946] = 32'h003041bf;
pd_rom[1947] = 32'h003041bf;
pd_rom[1948] = 32'h003041bf;
pd_rom[1949] = 32'h003041bf;
pd_rom[1950] = 32'h003041bf;
pd_rom[1951] = 32'h003041bf;
pd_rom[1952] = 32'h003041bf;
pd_rom[1953] = 32'h003041bf;
pd_rom[1954] = 32'h003041bf;
pd_rom[1955] = 32'h003041bf;
pd_rom[1956] = 32'h003041bf;
pd_rom[1957] = 32'h003041bf;
pd_rom[1958] = 32'h003041bf;
pd_rom[1959] = 32'h003041bf;
pd_rom[1960] = 32'h003041bf;
pd_rom[1961] = 32'h003041bf;
pd_rom[1962] = 32'h003041bf;
pd_rom[1963] = 32'h003041bf;
pd_rom[1964] = 32'h003041bf;
pd_rom[1965] = 32'h003041bf;
pd_rom[1966] = 32'h003041bf;
pd_rom[1967] = 32'h003041bf;
pd_rom[1968] = 32'h003041bf;
pd_rom[1969] = 32'h003041bf;
pd_rom[1970] = 32'h003041bf;
pd_rom[1971] = 32'h003041bf;
pd_rom[1972] = 32'h003041bf;
pd_rom[1973] = 32'h003041bf;
pd_rom[1974] = 32'h003041bf;
pd_rom[1975] = 32'h003041bf;
pd_rom[1976] = 32'h0030419f;
pd_rom[1977] = 32'h0030419f;
pd_rom[1978] = 32'h0030419f;
pd_rom[1979] = 32'h0030419f;
pd_rom[1980] = 32'h0030419f;
pd_rom[1981] = 32'h0030419f;
pd_rom[1982] = 32'h0030419f;
pd_rom[1983] = 32'h0030419f;
pd_rom[1984] = 32'h003041bf;
pd_rom[1985] = 32'h003041bf;
pd_rom[1986] = 32'h003041bf;
pd_rom[1987] = 32'h003041bf;
pd_rom[1988] = 32'h003041bf;
pd_rom[1989] = 32'h003041bf;
pd_rom[1990] = 32'h003041bf;
pd_rom[1991] = 32'h003041bf;
pd_rom[1992] = 32'h0032413f;
pd_rom[1993] = 32'h0032413f;
pd_rom[1994] = 32'h0032413f;
pd_rom[1995] = 32'h0032413f;
pd_rom[1996] = 32'h0032413f;
pd_rom[1997] = 32'h0032413f;
pd_rom[1998] = 32'h0032413f;
pd_rom[1999] = 32'h0032413f;
pd_rom[2000] = 32'h003041bf;
pd_rom[2001] = 32'h003041bf;
pd_rom[2002] = 32'h003041bf;
pd_rom[2003] = 32'h003041bf;
pd_rom[2004] = 32'h003041bf;
pd_rom[2005] = 32'h003041bf;
pd_rom[2006] = 32'h003041bf;
pd_rom[2007] = 32'h003041bf;
pd_rom[2008] = 32'h003041bf;
pd_rom[2009] = 32'h003041bf;
pd_rom[2010] = 32'h003041bf;
pd_rom[2011] = 32'h003041bf;
pd_rom[2012] = 32'h003041bf;
pd_rom[2013] = 32'h003041bf;
pd_rom[2014] = 32'h003041bf;
pd_rom[2015] = 32'h003041bf;
pd_rom[2016] = 32'h003041bf;
pd_rom[2017] = 32'h003041bf;
pd_rom[2018] = 32'h003041bf;
pd_rom[2019] = 32'h003041bf;
pd_rom[2020] = 32'h003041bf;
pd_rom[2021] = 32'h003041bf;
pd_rom[2022] = 32'h003041bf;
pd_rom[2023] = 32'h003041bf;
pd_rom[2024] = 32'h003041bf;
pd_rom[2025] = 32'h003041bf;
pd_rom[2026] = 32'h003041bf;
pd_rom[2027] = 32'h003041bf;
pd_rom[2028] = 32'h003041bf;
pd_rom[2029] = 32'h003041bf;
pd_rom[2030] = 32'h003041bf;
pd_rom[2031] = 32'h003041bf;
pd_rom[2032] = 32'h003041bf;
pd_rom[2033] = 32'h003041bf;
pd_rom[2034] = 32'h003041bf;
pd_rom[2035] = 32'h003041bf;
pd_rom[2036] = 32'h003041bf;
pd_rom[2037] = 32'h003041bf;
pd_rom[2038] = 32'h003041bf;
pd_rom[2039] = 32'h003041bf;
pd_rom[2040] = 32'h0030419f;
pd_rom[2041] = 32'h0030419f;
pd_rom[2042] = 32'h0030419f;
pd_rom[2043] = 32'h0030419f;
pd_rom[2044] = 32'h0030419f;
pd_rom[2045] = 32'h0030419f;
pd_rom[2046] = 32'h0030419f;
pd_rom[2047] = 32'h0030419f;
pd_rom[2048] = 32'h0034c13f;
pd_rom[2049] = 32'h0034c120;
pd_rom[2050] = 32'h0034c13f;
pd_rom[2051] = 32'h0034c13f;
pd_rom[2052] = 32'h0034c13f;
pd_rom[2053] = 32'h0034c13f;
pd_rom[2054] = 32'h0034c13f;
pd_rom[2055] = 32'h0034c123;
pd_rom[2056] = 32'h0039c13f;
pd_rom[2057] = 32'h0039c120;
pd_rom[2058] = 32'h0039c13f;
pd_rom[2059] = 32'h0039c13f;
pd_rom[2060] = 32'h0039c13f;
pd_rom[2061] = 32'h0039c13f;
pd_rom[2062] = 32'h0039c13f;
pd_rom[2063] = 32'h0039c123;
pd_rom[2064] = 32'h003ec13f;
pd_rom[2065] = 32'h003ec120;
pd_rom[2066] = 32'h003ec13f;
pd_rom[2067] = 32'h003ec13f;
pd_rom[2068] = 32'h003ec13f;
pd_rom[2069] = 32'h003ec13f;
pd_rom[2070] = 32'h003ec13f;
pd_rom[2071] = 32'h003ec123;
pd_rom[2072] = 32'h0043413f;
pd_rom[2073] = 32'h00434120;
pd_rom[2074] = 32'h0043413f;
pd_rom[2075] = 32'h0043413f;
pd_rom[2076] = 32'h0043413f;
pd_rom[2077] = 32'h0043413f;
pd_rom[2078] = 32'h0043413f;
pd_rom[2079] = 32'h00434123;
pd_rom[2080] = 32'h0068813f;
pd_rom[2081] = 32'h00688120;
pd_rom[2082] = 32'h0068813f;
pd_rom[2083] = 32'h0068813f;
pd_rom[2084] = 32'h0068813f;
pd_rom[2085] = 32'h0068813f;
pd_rom[2086] = 32'h0068813f;
pd_rom[2087] = 32'h0068813f;
pd_rom[2096] = 32'h0069413f;
pd_rom[2097] = 32'h00694120;
pd_rom[2098] = 32'h0069413f;
pd_rom[2099] = 32'h0069413f;
pd_rom[2100] = 32'h0069413f;
pd_rom[2101] = 32'h0069413f;
pd_rom[2102] = 32'h0069413f;
pd_rom[2103] = 32'h0069413f;
pd_rom[2104] = 32'h006a8120;
pd_rom[2105] = 32'h006a8120;
pd_rom[2106] = 32'h006a813f;
pd_rom[2107] = 32'h006a8120;
pd_rom[2108] = 32'h006a8120;
pd_rom[2109] = 32'h006a813f;
pd_rom[2110] = 32'h006a813f;
pd_rom[2111] = 32'h006a812f;
pd_rom[2112] = 32'h0035c13f;
pd_rom[2113] = 32'h0035c120;
pd_rom[2114] = 32'h0035c13f;
pd_rom[2115] = 32'h0035c13f;
pd_rom[2116] = 32'h0035c13f;
pd_rom[2117] = 32'h0035c13f;
pd_rom[2118] = 32'h0035c13f;
pd_rom[2119] = 32'h0035c123;
pd_rom[2120] = 32'h003ac13f;
pd_rom[2121] = 32'h003ac120;
pd_rom[2122] = 32'h003ac13f;
pd_rom[2123] = 32'h003ac13f;
pd_rom[2124] = 32'h003ac13f;
pd_rom[2125] = 32'h003ac13f;
pd_rom[2126] = 32'h003ac13f;
pd_rom[2127] = 32'h003ac123;
pd_rom[2128] = 32'h003fc13f;
pd_rom[2129] = 32'h003fc120;
pd_rom[2130] = 32'h003fc13f;
pd_rom[2131] = 32'h003fc13f;
pd_rom[2132] = 32'h003fc13f;
pd_rom[2133] = 32'h003fc13f;
pd_rom[2134] = 32'h003fc13f;
pd_rom[2135] = 32'h003fc123;
pd_rom[2136] = 32'h0044413f;
pd_rom[2137] = 32'h00444120;
pd_rom[2138] = 32'h0044413f;
pd_rom[2139] = 32'h0044413f;
pd_rom[2140] = 32'h0044413f;
pd_rom[2141] = 32'h0044413f;
pd_rom[2142] = 32'h0044413f;
pd_rom[2143] = 32'h00444123;
pd_rom[2144] = 32'h0068813f;
pd_rom[2145] = 32'h00688120;
pd_rom[2146] = 32'h0068813f;
pd_rom[2147] = 32'h0068813f;
pd_rom[2148] = 32'h0068813f;
pd_rom[2149] = 32'h0068813f;
pd_rom[2150] = 32'h0068813f;
pd_rom[2151] = 32'h0068813f;
pd_rom[2160] = 32'h0069413f;
pd_rom[2161] = 32'h00694120;
pd_rom[2162] = 32'h0069413f;
pd_rom[2163] = 32'h0069413f;
pd_rom[2164] = 32'h0069413f;
pd_rom[2165] = 32'h0069413f;
pd_rom[2166] = 32'h0069413f;
pd_rom[2167] = 32'h0069413f;
pd_rom[2168] = 32'h006a8120;
pd_rom[2169] = 32'h006a8120;
pd_rom[2170] = 32'h006a813f;
pd_rom[2171] = 32'h006a8120;
pd_rom[2172] = 32'h006a8120;
pd_rom[2173] = 32'h006a813f;
pd_rom[2174] = 32'h006a813f;
pd_rom[2175] = 32'h006a812f;
pd_rom[2176] = 32'h0036c13f;
pd_rom[2177] = 32'h0036c120;
pd_rom[2178] = 32'h0036c13f;
pd_rom[2179] = 32'h0036c13f;
pd_rom[2180] = 32'h0036c13f;
pd_rom[2181] = 32'h0036c13f;
pd_rom[2182] = 32'h0036c13f;
pd_rom[2183] = 32'h0036c123;
pd_rom[2184] = 32'h003bc13f;
pd_rom[2185] = 32'h003bc120;
pd_rom[2186] = 32'h003bc13f;
pd_rom[2187] = 32'h003bc13f;
pd_rom[2188] = 32'h003bc13f;
pd_rom[2189] = 32'h003bc13f;
pd_rom[2190] = 32'h003bc13f;
pd_rom[2191] = 32'h003bc123;
pd_rom[2192] = 32'h0040c13f;
pd_rom[2193] = 32'h0040c120;
pd_rom[2194] = 32'h0040c13f;
pd_rom[2195] = 32'h0040c13f;
pd_rom[2196] = 32'h0040c13f;
pd_rom[2197] = 32'h0040c13f;
pd_rom[2198] = 32'h0040c13f;
pd_rom[2199] = 32'h0040c123;
pd_rom[2200] = 32'h0045413f;
pd_rom[2201] = 32'h00454120;
pd_rom[2202] = 32'h0045413f;
pd_rom[2203] = 32'h0045413f;
pd_rom[2204] = 32'h0045413f;
pd_rom[2205] = 32'h0045413f;
pd_rom[2206] = 32'h0045413f;
pd_rom[2207] = 32'h0045413f;
pd_rom[2208] = 32'h0068813f;
pd_rom[2209] = 32'h00688120;
pd_rom[2210] = 32'h0068813f;
pd_rom[2211] = 32'h0068813f;
pd_rom[2212] = 32'h0068813f;
pd_rom[2213] = 32'h0068813f;
pd_rom[2214] = 32'h0068813f;
pd_rom[2215] = 32'h0068813f;
pd_rom[2224] = 32'h0069413f;
pd_rom[2225] = 32'h00694120;
pd_rom[2226] = 32'h0069413f;
pd_rom[2227] = 32'h0069413f;
pd_rom[2228] = 32'h0069413f;
pd_rom[2229] = 32'h0069413f;
pd_rom[2230] = 32'h0069413f;
pd_rom[2231] = 32'h0069413f;
pd_rom[2232] = 32'h006a8120;
pd_rom[2233] = 32'h006a8120;
pd_rom[2234] = 32'h006a813f;
pd_rom[2235] = 32'h006a8120;
pd_rom[2236] = 32'h006a8120;
pd_rom[2237] = 32'h006a813f;
pd_rom[2238] = 32'h006a813f;
pd_rom[2239] = 32'h006a812f;
pd_rom[2240] = 32'h0037c13f;
pd_rom[2241] = 32'h0037c120;
pd_rom[2242] = 32'h0037c13f;
pd_rom[2243] = 32'h0037c13f;
pd_rom[2244] = 32'h0037c13f;
pd_rom[2245] = 32'h0037c13f;
pd_rom[2246] = 32'h0037c13f;
pd_rom[2247] = 32'h0037c123;
pd_rom[2248] = 32'h003cc13f;
pd_rom[2249] = 32'h003cc120;
pd_rom[2250] = 32'h003cc13f;
pd_rom[2251] = 32'h003cc13f;
pd_rom[2252] = 32'h003cc13f;
pd_rom[2253] = 32'h003cc13f;
pd_rom[2254] = 32'h003cc13f;
pd_rom[2255] = 32'h003cc123;
pd_rom[2256] = 32'h0041c13f;
pd_rom[2257] = 32'h0041c120;
pd_rom[2258] = 32'h0041c13f;
pd_rom[2259] = 32'h0041c13f;
pd_rom[2260] = 32'h0041c13f;
pd_rom[2261] = 32'h0041c13f;
pd_rom[2262] = 32'h0041c13f;
pd_rom[2263] = 32'h0041c123;
pd_rom[2264] = 32'h0046413f;
pd_rom[2265] = 32'h00464120;
pd_rom[2266] = 32'h0046413f;
pd_rom[2267] = 32'h0046413f;
pd_rom[2268] = 32'h0046413f;
pd_rom[2269] = 32'h0046413f;
pd_rom[2270] = 32'h0046413f;
pd_rom[2271] = 32'h0046413f;
pd_rom[2272] = 32'h0068813f;
pd_rom[2273] = 32'h00688120;
pd_rom[2274] = 32'h0068813f;
pd_rom[2275] = 32'h0068813f;
pd_rom[2276] = 32'h0068813f;
pd_rom[2277] = 32'h0068813f;
pd_rom[2278] = 32'h0068813f;
pd_rom[2279] = 32'h0068813f;
pd_rom[2288] = 32'h0069413f;
pd_rom[2289] = 32'h00694120;
pd_rom[2290] = 32'h0069413f;
pd_rom[2291] = 32'h0069413f;
pd_rom[2292] = 32'h0069413f;
pd_rom[2293] = 32'h0069413f;
pd_rom[2294] = 32'h0069413f;
pd_rom[2295] = 32'h0069413f;
pd_rom[2296] = 32'h006a8120;
pd_rom[2297] = 32'h006a8120;
pd_rom[2298] = 32'h006a813f;
pd_rom[2299] = 32'h006a8120;
pd_rom[2300] = 32'h006a8120;
pd_rom[2301] = 32'h006a813f;
pd_rom[2302] = 32'h006a813f;
pd_rom[2303] = 32'h006a812f;
pd_rom[2304] = 32'h0048013f;
pd_rom[2305] = 32'h0047883f;
pd_rom[2306] = 32'h0048013f;
pd_rom[2307] = 32'h0048013f;
pd_rom[2308] = 32'h0048013f;
pd_rom[2309] = 32'h0048013f;
pd_rom[2310] = 32'h0048013f;
pd_rom[2311] = 32'h00480123;
pd_rom[2312] = 32'h004a403f;
pd_rom[2313] = 32'h0049803f;
pd_rom[2314] = 32'h004b813f;
pd_rom[2315] = 32'h004b8120;
pd_rom[2316] = 32'h004b8120;
pd_rom[2317] = 32'h004b813f;
pd_rom[2318] = 32'h004b813f;
pd_rom[2319] = 32'h004b812f;
pd_rom[2320] = 32'h004c403f;
pd_rom[2321] = 32'h004f5120;
pd_rom[2322] = 32'h004f513f;
pd_rom[2323] = 32'h004f5120;
pd_rom[2324] = 32'h004f513f;
pd_rom[2325] = 32'h004f513f;
pd_rom[2326] = 32'h004f513f;
pd_rom[2327] = 32'h004f5123;
pd_rom[2328] = 32'h004d803f;
pd_rom[2329] = 32'h00509120;
pd_rom[2330] = 32'h0050913f;
pd_rom[2331] = 32'h00509120;
pd_rom[2332] = 32'h0050913f;
pd_rom[2333] = 32'h0050913f;
pd_rom[2334] = 32'h0050913f;
pd_rom[2335] = 32'h00509123;
pd_rom[2336] = 32'h0068813f;
pd_rom[2337] = 32'h00688120;
pd_rom[2338] = 32'h0068813f;
pd_rom[2339] = 32'h0068813f;
pd_rom[2340] = 32'h0068813f;
pd_rom[2341] = 32'h0068813f;
pd_rom[2342] = 32'h0068813f;
pd_rom[2343] = 32'h0068813f;
pd_rom[2352] = 32'h0069413f;
pd_rom[2353] = 32'h00694120;
pd_rom[2354] = 32'h0069413f;
pd_rom[2355] = 32'h0069413f;
pd_rom[2356] = 32'h0069413f;
pd_rom[2357] = 32'h0069413f;
pd_rom[2358] = 32'h0069413f;
pd_rom[2359] = 32'h0069413f;
pd_rom[2360] = 32'h004e803f;
pd_rom[2361] = 32'h006a8120;
pd_rom[2362] = 32'h006a813f;
pd_rom[2363] = 32'h006a8120;
pd_rom[2364] = 32'h006a8120;
pd_rom[2365] = 32'h006a813f;
pd_rom[2366] = 32'h006a813f;
pd_rom[2367] = 32'h006a812f;
pd_rom[2368] = 32'h0038c13f;
pd_rom[2369] = 32'h0038c120;
pd_rom[2370] = 32'h0038c13f;
pd_rom[2371] = 32'h0038c13f;
pd_rom[2372] = 32'h0038c13f;
pd_rom[2373] = 32'h0038c13f;
pd_rom[2374] = 32'h0038c13f;
pd_rom[2375] = 32'h0038c13f;
pd_rom[2376] = 32'h003dc13f;
pd_rom[2377] = 32'h003dc13f;
pd_rom[2378] = 32'h003dc13f;
pd_rom[2379] = 32'h003dc13f;
pd_rom[2380] = 32'h003dc13f;
pd_rom[2381] = 32'h003dc13f;
pd_rom[2382] = 32'h003dc13f;
pd_rom[2383] = 32'h003dc13f;
pd_rom[2384] = 32'h0042c13f;
pd_rom[2385] = 32'h0042c13f;
pd_rom[2386] = 32'h0042c13f;
pd_rom[2387] = 32'h0042c13f;
pd_rom[2388] = 32'h0042c13f;
pd_rom[2389] = 32'h0042c13f;
pd_rom[2390] = 32'h0042c13f;
pd_rom[2391] = 32'h0042c13f;
pd_rom[2392] = 32'h0053013f;
pd_rom[2393] = 32'h00530120;
pd_rom[2394] = 32'h0053013f;
pd_rom[2395] = 32'h0053013f;
pd_rom[2396] = 32'h0053013f;
pd_rom[2397] = 32'h0053013f;
pd_rom[2398] = 32'h0053013f;
pd_rom[2399] = 32'h50530123;
pd_rom[2400] = 32'h0068813f;
pd_rom[2401] = 32'h00688120;
pd_rom[2402] = 32'h0068813f;
pd_rom[2403] = 32'h0068813f;
pd_rom[2404] = 32'h0068813f;
pd_rom[2405] = 32'h0068813f;
pd_rom[2406] = 32'h0068813f;
pd_rom[2407] = 32'h0068813f;
pd_rom[2416] = 32'h0069413f;
pd_rom[2417] = 32'h00694120;
pd_rom[2418] = 32'h0069413f;
pd_rom[2419] = 32'h0069413f;
pd_rom[2420] = 32'h0069413f;
pd_rom[2421] = 32'h0069413f;
pd_rom[2422] = 32'h0069413f;
pd_rom[2423] = 32'h0069413f;
pd_rom[2424] = 32'h006a8120;
pd_rom[2425] = 32'h006a8120;
pd_rom[2426] = 32'h006a813f;
pd_rom[2427] = 32'h006a8120;
pd_rom[2428] = 32'h006a8120;
pd_rom[2429] = 32'h006a813f;
pd_rom[2430] = 32'h006a813f;
pd_rom[2431] = 32'h006a812f;
pd_rom[2432] = 32'h0055913f;
pd_rom[2433] = 32'h00559120;
pd_rom[2434] = 32'h0055913f;
pd_rom[2435] = 32'h0055913f;
pd_rom[2436] = 32'h0055913f;
pd_rom[2437] = 32'h0055913f;
pd_rom[2438] = 32'h0055913f;
pd_rom[2439] = 32'h0055913f;
pd_rom[2440] = 32'h0056913f;
pd_rom[2441] = 32'h00569120;
pd_rom[2442] = 32'h0056913f;
pd_rom[2443] = 32'h0056913f;
pd_rom[2444] = 32'h0056913f;
pd_rom[2445] = 32'h0056913f;
pd_rom[2446] = 32'h0056913f;
pd_rom[2447] = 32'h0056913f;
pd_rom[2448] = 32'h00515120;
pd_rom[2449] = 32'h00515120;
pd_rom[2450] = 32'h0051513f;
pd_rom[2451] = 32'h0051513f;
pd_rom[2452] = 32'h00515120;
pd_rom[2453] = 32'h0051513f;
pd_rom[2454] = 32'h0051513f;
pd_rom[2455] = 32'h0051512f;
pd_rom[2456] = 32'h00529120;
pd_rom[2457] = 32'h00529120;
pd_rom[2458] = 32'h0052913f;
pd_rom[2459] = 32'h0052913f;
pd_rom[2460] = 32'h00529120;
pd_rom[2461] = 32'h0052913f;
pd_rom[2462] = 32'h0052913f;
pd_rom[2463] = 32'h0052912f;
pd_rom[2464] = 32'h0068813f;
pd_rom[2465] = 32'h00688120;
pd_rom[2466] = 32'h0068813f;
pd_rom[2467] = 32'h0068813f;
pd_rom[2468] = 32'h0068813f;
pd_rom[2469] = 32'h0068813f;
pd_rom[2470] = 32'h0068813f;
pd_rom[2471] = 32'h0068813f;
pd_rom[2480] = 32'h0069413f;
pd_rom[2481] = 32'h00694120;
pd_rom[2482] = 32'h0069413f;
pd_rom[2483] = 32'h0069413f;
pd_rom[2484] = 32'h0069413f;
pd_rom[2485] = 32'h0069413f;
pd_rom[2486] = 32'h0069413f;
pd_rom[2487] = 32'h0069413f;
pd_rom[2488] = 32'h006a8120;
pd_rom[2489] = 32'h006a8120;
pd_rom[2490] = 32'h006a813f;
pd_rom[2491] = 32'h006a8120;
pd_rom[2492] = 32'h006a8120;
pd_rom[2493] = 32'h006a813f;
pd_rom[2494] = 32'h006a813f;
pd_rom[2495] = 32'h006a812f;
pd_rom[2504] = 32'h0057803f;
pd_rom[2505] = 32'h0057803f;
pd_rom[2506] = 32'h0058463f;
pd_rom[2507] = 32'h0059803f;
pd_rom[2508] = 32'h005a803f;
pd_rom[2509] = 32'h005b803f;
pd_rom[2510] = 32'hd25c803f;
pd_rom[2511] = 32'ha3ff0000;
pd_rom[2512] = 32'h00668120;
pd_rom[2513] = 32'h00668120;
pd_rom[2514] = 32'h0066813f;
pd_rom[2515] = 32'h00668120;
pd_rom[2516] = 32'h00668120;
pd_rom[2517] = 32'h0066813f;
pd_rom[2518] = 32'h0066813f;
pd_rom[2519] = 32'h0066812f;
pd_rom[2520] = 32'h00678120;
pd_rom[2521] = 32'h00678120;
pd_rom[2522] = 32'h0067813f;
pd_rom[2523] = 32'h00678120;
pd_rom[2524] = 32'h00678120;
pd_rom[2525] = 32'h0067813f;
pd_rom[2526] = 32'h0067813f;
pd_rom[2527] = 32'h0067812f;
pd_rom[2528] = 32'h0068813f;
pd_rom[2529] = 32'h00688120;
pd_rom[2530] = 32'h0068813f;
pd_rom[2531] = 32'h0068813f;
pd_rom[2532] = 32'h0068813f;
pd_rom[2533] = 32'h0068813f;
pd_rom[2534] = 32'h0068813f;
pd_rom[2535] = 32'h0068813f;
pd_rom[2544] = 32'h0069413f;
pd_rom[2545] = 32'h00694120;
pd_rom[2546] = 32'h0069413f;
pd_rom[2547] = 32'h0069413f;
pd_rom[2548] = 32'h0069413f;
pd_rom[2549] = 32'h0069413f;
pd_rom[2550] = 32'h0069413f;
pd_rom[2551] = 32'h0069413f;
pd_rom[2552] = 32'h006a8120;
pd_rom[2553] = 32'h006a8120;
pd_rom[2554] = 32'h006a813f;
pd_rom[2555] = 32'h006a8120;
pd_rom[2556] = 32'h006a8120;
pd_rom[2557] = 32'h006a813f;
pd_rom[2558] = 32'h006a813f;
pd_rom[2559] = 32'h006a812f;
pd_rom[2560] = 32'h006bc13f;
pd_rom[2561] = 32'h006bc120;
pd_rom[2562] = 32'h006bc13f;
pd_rom[2563] = 32'h006bc13f;
pd_rom[2564] = 32'h006bc13f;
pd_rom[2565] = 32'h006bc13f;
pd_rom[2566] = 32'h006bc13f;
pd_rom[2567] = 32'h006bc123;
pd_rom[2568] = 32'h006dc13f;
pd_rom[2569] = 32'h0071403f;
pd_rom[2570] = 32'h006dc13f;
pd_rom[2571] = 32'h006dc13f;
pd_rom[2572] = 32'h006dc13f;
pd_rom[2573] = 32'h006dc13f;
pd_rom[2574] = 32'h006dc13f;
pd_rom[2575] = 32'h006dc123;
pd_rom[2576] = 32'h006fc13f;
pd_rom[2577] = 32'h0072803f;
pd_rom[2578] = 32'h006fc13f;
pd_rom[2579] = 32'h006fc13f;
pd_rom[2580] = 32'h006fc13f;
pd_rom[2581] = 32'h006fc13f;
pd_rom[2582] = 32'h006fc13f;
pd_rom[2583] = 32'h006fc123;
pd_rom[2584] = 32'h0075013f;
pd_rom[2585] = 32'h0076463f;
pd_rom[2586] = 32'h0075013f;
pd_rom[2587] = 32'h0075013f;
pd_rom[2588] = 32'h0075013f;
pd_rom[2589] = 32'h0075013f;
pd_rom[2590] = 32'h0075013f;
pd_rom[2591] = 32'ha8750123;
pd_rom[2592] = 32'h006cc13f;
pd_rom[2593] = 32'h006cc120;
pd_rom[2594] = 32'h006cc13f;
pd_rom[2595] = 32'h006cc13f;
pd_rom[2596] = 32'h006cc13f;
pd_rom[2597] = 32'h006cc13f;
pd_rom[2598] = 32'h006cc13f;
pd_rom[2599] = 32'h006cc123;
pd_rom[2600] = 32'h006ec13f;
pd_rom[2601] = 32'h0073403f;
pd_rom[2602] = 32'h006ec13f;
pd_rom[2603] = 32'h006ec13f;
pd_rom[2604] = 32'h006ec13f;
pd_rom[2605] = 32'h006ec13f;
pd_rom[2606] = 32'h006ec13f;
pd_rom[2607] = 32'h006ec123;
pd_rom[2608] = 32'h0070c13f;
pd_rom[2609] = 32'h0074803f;
pd_rom[2610] = 32'h0070c13f;
pd_rom[2611] = 32'h0070c13f;
pd_rom[2612] = 32'h0070c13f;
pd_rom[2613] = 32'h0070c13f;
pd_rom[2614] = 32'h0070c13f;
pd_rom[2615] = 32'h0070c123;
pd_rom[2616] = 32'h0075013f;
pd_rom[2617] = 32'h0076463f;
pd_rom[2618] = 32'h0075013f;
pd_rom[2619] = 32'h0075013f;
pd_rom[2620] = 32'h0075013f;
pd_rom[2621] = 32'h0075013f;
pd_rom[2622] = 32'h0075013f;
pd_rom[2623] = 32'ha8750123;
pd_rom[2624] = 32'h006bc13f;
pd_rom[2625] = 32'h006bc120;
pd_rom[2626] = 32'h006bc13f;
pd_rom[2627] = 32'h006bc13f;
pd_rom[2628] = 32'h006bc13f;
pd_rom[2629] = 32'h006bc13f;
pd_rom[2630] = 32'h006bc13f;
pd_rom[2631] = 32'h006bc123;
pd_rom[2632] = 32'h006dc13f;
pd_rom[2633] = 32'h0071403f;
pd_rom[2634] = 32'h006dc13f;
pd_rom[2635] = 32'h006dc13f;
pd_rom[2636] = 32'h006dc13f;
pd_rom[2637] = 32'h006dc13f;
pd_rom[2638] = 32'h006dc13f;
pd_rom[2639] = 32'h006dc123;
pd_rom[2640] = 32'h006fc13f;
pd_rom[2641] = 32'h0072803f;
pd_rom[2642] = 32'h006fc13f;
pd_rom[2643] = 32'h006fc13f;
pd_rom[2644] = 32'h006fc13f;
pd_rom[2645] = 32'h006fc13f;
pd_rom[2646] = 32'h006fc13f;
pd_rom[2647] = 32'h006fc123;
pd_rom[2648] = 32'h0075013f;
pd_rom[2649] = 32'h0076463f;
pd_rom[2650] = 32'h0075013f;
pd_rom[2651] = 32'h0075013f;
pd_rom[2652] = 32'h0075013f;
pd_rom[2653] = 32'h0075013f;
pd_rom[2654] = 32'h0075013f;
pd_rom[2655] = 32'ha8750123;
pd_rom[2656] = 32'h006cc13f;
pd_rom[2657] = 32'h006cc120;
pd_rom[2658] = 32'h006cc13f;
pd_rom[2659] = 32'h006cc13f;
pd_rom[2660] = 32'h006cc13f;
pd_rom[2661] = 32'h006cc13f;
pd_rom[2662] = 32'h006cc13f;
pd_rom[2663] = 32'h006cc123;
pd_rom[2664] = 32'h006ec13f;
pd_rom[2665] = 32'h0073403f;
pd_rom[2666] = 32'h006ec13f;
pd_rom[2667] = 32'h006ec13f;
pd_rom[2668] = 32'h006ec13f;
pd_rom[2669] = 32'h006ec13f;
pd_rom[2670] = 32'h006ec13f;
pd_rom[2671] = 32'h006ec123;
pd_rom[2672] = 32'h0070c13f;
pd_rom[2673] = 32'h0074803f;
pd_rom[2674] = 32'h0070c13f;
pd_rom[2675] = 32'h0070c13f;
pd_rom[2676] = 32'h0070c13f;
pd_rom[2677] = 32'h0070c13f;
pd_rom[2678] = 32'h0070c13f;
pd_rom[2679] = 32'h0070c123;
pd_rom[2680] = 32'h0075013f;
pd_rom[2681] = 32'h0076463f;
pd_rom[2682] = 32'h0075013f;
pd_rom[2683] = 32'h0075013f;
pd_rom[2684] = 32'h0075013f;
pd_rom[2685] = 32'h0075013f;
pd_rom[2686] = 32'h0075013f;
pd_rom[2687] = 32'ha8750123;
pd_rom[2688] = 32'h006bc13f;
pd_rom[2689] = 32'h006bc120;
pd_rom[2690] = 32'h006bc13f;
pd_rom[2691] = 32'h006bc13f;
pd_rom[2692] = 32'h006bc13f;
pd_rom[2693] = 32'h006bc13f;
pd_rom[2694] = 32'h006bc13f;
pd_rom[2695] = 32'h006bc123;
pd_rom[2696] = 32'h006dc13f;
pd_rom[2697] = 32'h0071403f;
pd_rom[2698] = 32'h006dc13f;
pd_rom[2699] = 32'h006dc13f;
pd_rom[2700] = 32'h006dc13f;
pd_rom[2701] = 32'h006dc13f;
pd_rom[2702] = 32'h006dc13f;
pd_rom[2703] = 32'h006dc123;
pd_rom[2704] = 32'h006fc13f;
pd_rom[2705] = 32'h0072803f;
pd_rom[2706] = 32'h006fc13f;
pd_rom[2707] = 32'h006fc13f;
pd_rom[2708] = 32'h006fc13f;
pd_rom[2709] = 32'h006fc13f;
pd_rom[2710] = 32'h006fc13f;
pd_rom[2711] = 32'h006fc123;
pd_rom[2712] = 32'h0075013f;
pd_rom[2713] = 32'h0076463f;
pd_rom[2714] = 32'h0075013f;
pd_rom[2715] = 32'h0075013f;
pd_rom[2716] = 32'h0075013f;
pd_rom[2717] = 32'h0075013f;
pd_rom[2718] = 32'h0075013f;
pd_rom[2719] = 32'ha8750123;
pd_rom[2720] = 32'h006cc13f;
pd_rom[2721] = 32'h006cc120;
pd_rom[2722] = 32'h006cc13f;
pd_rom[2723] = 32'h006cc13f;
pd_rom[2724] = 32'h006cc13f;
pd_rom[2725] = 32'h006cc13f;
pd_rom[2726] = 32'h006cc13f;
pd_rom[2727] = 32'h006cc123;
pd_rom[2728] = 32'h006ec13f;
pd_rom[2729] = 32'h0073403f;
pd_rom[2730] = 32'h006ec13f;
pd_rom[2731] = 32'h006ec13f;
pd_rom[2732] = 32'h006ec13f;
pd_rom[2733] = 32'h006ec13f;
pd_rom[2734] = 32'h006ec13f;
pd_rom[2735] = 32'h006ec123;
pd_rom[2736] = 32'h0070c13f;
pd_rom[2737] = 32'h0074803f;
pd_rom[2738] = 32'h0070c13f;
pd_rom[2739] = 32'h0070c13f;
pd_rom[2740] = 32'h0070c13f;
pd_rom[2741] = 32'h0070c13f;
pd_rom[2742] = 32'h0070c13f;
pd_rom[2743] = 32'h0070c123;
pd_rom[2744] = 32'h0075013f;
pd_rom[2745] = 32'h0076463f;
pd_rom[2746] = 32'h0075013f;
pd_rom[2747] = 32'h0075013f;
pd_rom[2748] = 32'h0075013f;
pd_rom[2749] = 32'h0075013f;
pd_rom[2750] = 32'h0075013f;
pd_rom[2751] = 32'ha8750123;
pd_rom[2752] = 32'h006bc13f;
pd_rom[2753] = 32'h006bc120;
pd_rom[2754] = 32'h006bc13f;
pd_rom[2755] = 32'h006bc13f;
pd_rom[2756] = 32'h006bc13f;
pd_rom[2757] = 32'h006bc13f;
pd_rom[2758] = 32'h006bc13f;
pd_rom[2759] = 32'h006bc123;
pd_rom[2760] = 32'h006dc13f;
pd_rom[2761] = 32'h0071403f;
pd_rom[2762] = 32'h006dc13f;
pd_rom[2763] = 32'h006dc13f;
pd_rom[2764] = 32'h006dc13f;
pd_rom[2765] = 32'h006dc13f;
pd_rom[2766] = 32'h006dc13f;
pd_rom[2767] = 32'h006dc123;
pd_rom[2768] = 32'h006fc13f;
pd_rom[2769] = 32'h0072803f;
pd_rom[2770] = 32'h006fc13f;
pd_rom[2771] = 32'h006fc13f;
pd_rom[2772] = 32'h006fc13f;
pd_rom[2773] = 32'h006fc13f;
pd_rom[2774] = 32'h006fc13f;
pd_rom[2775] = 32'h006fc123;
pd_rom[2776] = 32'h0075013f;
pd_rom[2777] = 32'h0076463f;
pd_rom[2778] = 32'h0075013f;
pd_rom[2779] = 32'h0075013f;
pd_rom[2780] = 32'h0075013f;
pd_rom[2781] = 32'h0075013f;
pd_rom[2782] = 32'h0075013f;
pd_rom[2783] = 32'ha8750123;
pd_rom[2784] = 32'h006cc13f;
pd_rom[2785] = 32'h006cc120;
pd_rom[2786] = 32'h006cc13f;
pd_rom[2787] = 32'h006cc13f;
pd_rom[2788] = 32'h006cc13f;
pd_rom[2789] = 32'h006cc13f;
pd_rom[2790] = 32'h006cc13f;
pd_rom[2791] = 32'h006cc123;
pd_rom[2792] = 32'h006ec13f;
pd_rom[2793] = 32'h0073403f;
pd_rom[2794] = 32'h006ec13f;
pd_rom[2795] = 32'h006ec13f;
pd_rom[2796] = 32'h006ec13f;
pd_rom[2797] = 32'h006ec13f;
pd_rom[2798] = 32'h006ec13f;
pd_rom[2799] = 32'h006ec123;
pd_rom[2800] = 32'h0070c13f;
pd_rom[2801] = 32'h0074803f;
pd_rom[2802] = 32'h0070c13f;
pd_rom[2803] = 32'h0070c13f;
pd_rom[2804] = 32'h0070c13f;
pd_rom[2805] = 32'h0070c13f;
pd_rom[2806] = 32'h0070c13f;
pd_rom[2807] = 32'h0070c123;
pd_rom[2808] = 32'h0075013f;
pd_rom[2809] = 32'h0076463f;
pd_rom[2810] = 32'h0075013f;
pd_rom[2811] = 32'h0075013f;
pd_rom[2812] = 32'h0075013f;
pd_rom[2813] = 32'h0075013f;
pd_rom[2814] = 32'h0075013f;
pd_rom[2815] = 32'ha8750123;
pd_rom[2816] = 32'h006bc13f;
pd_rom[2817] = 32'h006bc120;
pd_rom[2818] = 32'h006bc13f;
pd_rom[2819] = 32'h006bc13f;
pd_rom[2820] = 32'h006bc13f;
pd_rom[2821] = 32'h006bc13f;
pd_rom[2822] = 32'h006bc13f;
pd_rom[2823] = 32'h006bc123;
pd_rom[2824] = 32'h006dc13f;
pd_rom[2825] = 32'h0071403f;
pd_rom[2826] = 32'h006dc13f;
pd_rom[2827] = 32'h006dc13f;
pd_rom[2828] = 32'h006dc13f;
pd_rom[2829] = 32'h006dc13f;
pd_rom[2830] = 32'h006dc13f;
pd_rom[2831] = 32'h006dc123;
pd_rom[2832] = 32'h006fc13f;
pd_rom[2833] = 32'h0072803f;
pd_rom[2834] = 32'h006fc13f;
pd_rom[2835] = 32'h006fc13f;
pd_rom[2836] = 32'h006fc13f;
pd_rom[2837] = 32'h006fc13f;
pd_rom[2838] = 32'h006fc13f;
pd_rom[2839] = 32'h006fc123;
pd_rom[2840] = 32'h0075013f;
pd_rom[2841] = 32'h0076463f;
pd_rom[2842] = 32'h0075013f;
pd_rom[2843] = 32'h0075013f;
pd_rom[2844] = 32'h0075013f;
pd_rom[2845] = 32'h0075013f;
pd_rom[2846] = 32'h0075013f;
pd_rom[2847] = 32'ha8750123;
pd_rom[2848] = 32'h006cc13f;
pd_rom[2849] = 32'h006cc120;
pd_rom[2850] = 32'h006cc13f;
pd_rom[2851] = 32'h006cc13f;
pd_rom[2852] = 32'h006cc13f;
pd_rom[2853] = 32'h006cc13f;
pd_rom[2854] = 32'h006cc13f;
pd_rom[2855] = 32'h006cc123;
pd_rom[2856] = 32'h006ec13f;
pd_rom[2857] = 32'h0073403f;
pd_rom[2858] = 32'h006ec13f;
pd_rom[2859] = 32'h006ec13f;
pd_rom[2860] = 32'h006ec13f;
pd_rom[2861] = 32'h006ec13f;
pd_rom[2862] = 32'h006ec13f;
pd_rom[2863] = 32'h006ec123;
pd_rom[2864] = 32'h0070c13f;
pd_rom[2865] = 32'h0074803f;
pd_rom[2866] = 32'h0070c13f;
pd_rom[2867] = 32'h0070c13f;
pd_rom[2868] = 32'h0070c13f;
pd_rom[2869] = 32'h0070c13f;
pd_rom[2870] = 32'h0070c13f;
pd_rom[2871] = 32'h0070c123;
pd_rom[2872] = 32'h0075013f;
pd_rom[2873] = 32'h0076463f;
pd_rom[2874] = 32'h0075013f;
pd_rom[2875] = 32'h0075013f;
pd_rom[2876] = 32'h0075013f;
pd_rom[2877] = 32'h0075013f;
pd_rom[2878] = 32'h0075013f;
pd_rom[2879] = 32'ha8750123;
pd_rom[2880] = 32'h006bc13f;
pd_rom[2881] = 32'h006bc120;
pd_rom[2882] = 32'h006bc13f;
pd_rom[2883] = 32'h006bc13f;
pd_rom[2884] = 32'h006bc13f;
pd_rom[2885] = 32'h006bc13f;
pd_rom[2886] = 32'h006bc13f;
pd_rom[2887] = 32'h006bc123;
pd_rom[2888] = 32'h006dc13f;
pd_rom[2889] = 32'h0071403f;
pd_rom[2890] = 32'h006dc13f;
pd_rom[2891] = 32'h006dc13f;
pd_rom[2892] = 32'h006dc13f;
pd_rom[2893] = 32'h006dc13f;
pd_rom[2894] = 32'h006dc13f;
pd_rom[2895] = 32'h006dc123;
pd_rom[2896] = 32'h006fc13f;
pd_rom[2897] = 32'h0072803f;
pd_rom[2898] = 32'h006fc13f;
pd_rom[2899] = 32'h006fc13f;
pd_rom[2900] = 32'h006fc13f;
pd_rom[2901] = 32'h006fc13f;
pd_rom[2902] = 32'h006fc13f;
pd_rom[2903] = 32'h006fc123;
pd_rom[2904] = 32'h0075013f;
pd_rom[2905] = 32'h0076463f;
pd_rom[2906] = 32'h0075013f;
pd_rom[2907] = 32'h0075013f;
pd_rom[2908] = 32'h0075013f;
pd_rom[2909] = 32'h0075013f;
pd_rom[2910] = 32'h0075013f;
pd_rom[2911] = 32'ha8750123;
pd_rom[2912] = 32'h006cc13f;
pd_rom[2913] = 32'h006cc120;
pd_rom[2914] = 32'h006cc13f;
pd_rom[2915] = 32'h006cc13f;
pd_rom[2916] = 32'h006cc13f;
pd_rom[2917] = 32'h006cc13f;
pd_rom[2918] = 32'h006cc13f;
pd_rom[2919] = 32'h006cc123;
pd_rom[2920] = 32'h006ec13f;
pd_rom[2921] = 32'h0073403f;
pd_rom[2922] = 32'h006ec13f;
pd_rom[2923] = 32'h006ec13f;
pd_rom[2924] = 32'h006ec13f;
pd_rom[2925] = 32'h006ec13f;
pd_rom[2926] = 32'h006ec13f;
pd_rom[2927] = 32'h006ec123;
pd_rom[2928] = 32'h0070c13f;
pd_rom[2929] = 32'h0074803f;
pd_rom[2930] = 32'h0070c13f;
pd_rom[2931] = 32'h0070c13f;
pd_rom[2932] = 32'h0070c13f;
pd_rom[2933] = 32'h0070c13f;
pd_rom[2934] = 32'h0070c13f;
pd_rom[2935] = 32'h0070c123;
pd_rom[2936] = 32'h0075013f;
pd_rom[2937] = 32'h0076463f;
pd_rom[2938] = 32'h0075013f;
pd_rom[2939] = 32'h0075013f;
pd_rom[2940] = 32'h0075013f;
pd_rom[2941] = 32'h0075013f;
pd_rom[2942] = 32'h0075013f;
pd_rom[2943] = 32'ha8750123;
pd_rom[2944] = 32'h006bc13f;
pd_rom[2945] = 32'h006bc120;
pd_rom[2946] = 32'h006bc13f;
pd_rom[2947] = 32'h006bc13f;
pd_rom[2948] = 32'h006bc13f;
pd_rom[2949] = 32'h006bc13f;
pd_rom[2950] = 32'h006bc13f;
pd_rom[2951] = 32'h006bc123;
pd_rom[2952] = 32'h006dc13f;
pd_rom[2953] = 32'h0071403f;
pd_rom[2954] = 32'h006dc13f;
pd_rom[2955] = 32'h006dc13f;
pd_rom[2956] = 32'h006dc13f;
pd_rom[2957] = 32'h006dc13f;
pd_rom[2958] = 32'h006dc13f;
pd_rom[2959] = 32'h006dc123;
pd_rom[2960] = 32'h006fc13f;
pd_rom[2961] = 32'h0072803f;
pd_rom[2962] = 32'h006fc13f;
pd_rom[2963] = 32'h006fc13f;
pd_rom[2964] = 32'h006fc13f;
pd_rom[2965] = 32'h006fc13f;
pd_rom[2966] = 32'h006fc13f;
pd_rom[2967] = 32'h006fc123;
pd_rom[2968] = 32'h0075013f;
pd_rom[2969] = 32'h0076463f;
pd_rom[2970] = 32'h0075013f;
pd_rom[2971] = 32'h0075013f;
pd_rom[2972] = 32'h0075013f;
pd_rom[2973] = 32'h0075013f;
pd_rom[2974] = 32'h0075013f;
pd_rom[2975] = 32'ha8750123;
pd_rom[2976] = 32'h006cc13f;
pd_rom[2977] = 32'h006cc120;
pd_rom[2978] = 32'h006cc13f;
pd_rom[2979] = 32'h006cc13f;
pd_rom[2980] = 32'h006cc13f;
pd_rom[2981] = 32'h006cc13f;
pd_rom[2982] = 32'h006cc13f;
pd_rom[2983] = 32'h006cc123;
pd_rom[2984] = 32'h006ec13f;
pd_rom[2985] = 32'h0073403f;
pd_rom[2986] = 32'h006ec13f;
pd_rom[2987] = 32'h006ec13f;
pd_rom[2988] = 32'h006ec13f;
pd_rom[2989] = 32'h006ec13f;
pd_rom[2990] = 32'h006ec13f;
pd_rom[2991] = 32'h006ec123;
pd_rom[2992] = 32'h0070c13f;
pd_rom[2993] = 32'h0074803f;
pd_rom[2994] = 32'h0070c13f;
pd_rom[2995] = 32'h0070c13f;
pd_rom[2996] = 32'h0070c13f;
pd_rom[2997] = 32'h0070c13f;
pd_rom[2998] = 32'h0070c13f;
pd_rom[2999] = 32'h0070c123;
pd_rom[3000] = 32'h0075013f;
pd_rom[3001] = 32'h0076463f;
pd_rom[3002] = 32'h0075013f;
pd_rom[3003] = 32'h0075013f;
pd_rom[3004] = 32'h0075013f;
pd_rom[3005] = 32'h0075013f;
pd_rom[3006] = 32'h0075013f;
pd_rom[3007] = 32'ha8750123;
pd_rom[3008] = 32'h006bc13f;
pd_rom[3009] = 32'h006bc120;
pd_rom[3010] = 32'h006bc13f;
pd_rom[3011] = 32'h006bc13f;
pd_rom[3012] = 32'h006bc13f;
pd_rom[3013] = 32'h006bc13f;
pd_rom[3014] = 32'h006bc13f;
pd_rom[3015] = 32'h006bc123;
pd_rom[3016] = 32'h006dc13f;
pd_rom[3017] = 32'h0071403f;
pd_rom[3018] = 32'h006dc13f;
pd_rom[3019] = 32'h006dc13f;
pd_rom[3020] = 32'h006dc13f;
pd_rom[3021] = 32'h006dc13f;
pd_rom[3022] = 32'h006dc13f;
pd_rom[3023] = 32'h006dc123;
pd_rom[3024] = 32'h006fc13f;
pd_rom[3025] = 32'h0072803f;
pd_rom[3026] = 32'h006fc13f;
pd_rom[3027] = 32'h006fc13f;
pd_rom[3028] = 32'h006fc13f;
pd_rom[3029] = 32'h006fc13f;
pd_rom[3030] = 32'h006fc13f;
pd_rom[3031] = 32'h006fc123;
pd_rom[3032] = 32'h0075013f;
pd_rom[3033] = 32'h0076463f;
pd_rom[3034] = 32'h0075013f;
pd_rom[3035] = 32'h0075013f;
pd_rom[3036] = 32'h0075013f;
pd_rom[3037] = 32'h0075013f;
pd_rom[3038] = 32'h0075013f;
pd_rom[3039] = 32'ha8750123;
pd_rom[3040] = 32'h006cc13f;
pd_rom[3041] = 32'h006cc120;
pd_rom[3042] = 32'h006cc13f;
pd_rom[3043] = 32'h006cc13f;
pd_rom[3044] = 32'h006cc13f;
pd_rom[3045] = 32'h006cc13f;
pd_rom[3046] = 32'h006cc13f;
pd_rom[3047] = 32'h006cc123;
pd_rom[3048] = 32'h006ec13f;
pd_rom[3049] = 32'h0073403f;
pd_rom[3050] = 32'h006ec13f;
pd_rom[3051] = 32'h006ec13f;
pd_rom[3052] = 32'h006ec13f;
pd_rom[3053] = 32'h006ec13f;
pd_rom[3054] = 32'h006ec13f;
pd_rom[3055] = 32'h006ec123;
pd_rom[3056] = 32'h0070c13f;
pd_rom[3057] = 32'h0074803f;
pd_rom[3058] = 32'h0070c13f;
pd_rom[3059] = 32'h0070c13f;
pd_rom[3060] = 32'h0070c13f;
pd_rom[3061] = 32'h0070c13f;
pd_rom[3062] = 32'h0070c13f;
pd_rom[3063] = 32'h0070c123;
pd_rom[3064] = 32'h0075013f;
pd_rom[3065] = 32'h0076463f;
pd_rom[3066] = 32'h0075013f;
pd_rom[3067] = 32'h0075013f;
pd_rom[3068] = 32'h0075013f;
pd_rom[3069] = 32'h0075013f;
pd_rom[3070] = 32'h0075013f;
pd_rom[3071] = 32'ha8750123;
pd_rom[3072] = 32'h007b8a3f;
pd_rom[3073] = 32'h007b8a3f;
pd_rom[3074] = 32'h007b8a3f;
pd_rom[3075] = 32'h007b8a3f;
pd_rom[3076] = 32'h007b8a3f;
pd_rom[3077] = 32'h007b8a3f;
pd_rom[3078] = 32'h007b8a3f;
pd_rom[3079] = 32'h007b8a3f;
pd_rom[3080] = 32'h007b8a3f;
pd_rom[3081] = 32'h007b8a3f;
pd_rom[3082] = 32'h007b8a3f;
pd_rom[3083] = 32'h007b8a3f;
pd_rom[3084] = 32'h007b8a3f;
pd_rom[3085] = 32'h007b8a3f;
pd_rom[3086] = 32'h007b8a3f;
pd_rom[3087] = 32'h007b8a3f;
pd_rom[3088] = 32'h007b8a3f;
pd_rom[3089] = 32'h007b8a3f;
pd_rom[3090] = 32'h007b8a3f;
pd_rom[3091] = 32'h007b8a3f;
pd_rom[3092] = 32'h007b8a3f;
pd_rom[3093] = 32'h007b8a3f;
pd_rom[3094] = 32'h007b8a3f;
pd_rom[3095] = 32'h007b8a3f;
pd_rom[3096] = 32'h007b8a3f;
pd_rom[3097] = 32'h007b8a3f;
pd_rom[3098] = 32'h007b8a3f;
pd_rom[3099] = 32'h007b8a3f;
pd_rom[3100] = 32'h007b8a3f;
pd_rom[3101] = 32'h007b8a3f;
pd_rom[3102] = 32'h007b8a3f;
pd_rom[3103] = 32'h007b8a3f;
pd_rom[3104] = 32'h007a8a3f;
pd_rom[3105] = 32'h007a8a3f;
pd_rom[3106] = 32'h007a8a3f;
pd_rom[3107] = 32'h007a8a3f;
pd_rom[3108] = 32'h007a8a3f;
pd_rom[3109] = 32'h007a8a3f;
pd_rom[3110] = 32'h007a8a3f;
pd_rom[3111] = 32'h007a8a3f;
pd_rom[3112] = 32'h007a8a3f;
pd_rom[3113] = 32'h007a8a3f;
pd_rom[3114] = 32'h007a8a3f;
pd_rom[3115] = 32'h007a8a3f;
pd_rom[3116] = 32'h007a8a3f;
pd_rom[3117] = 32'h007a8a3f;
pd_rom[3118] = 32'h007a8a3f;
pd_rom[3119] = 32'h007a8a3f;
pd_rom[3120] = 32'h007a8a3f;
pd_rom[3121] = 32'h007a8a3f;
pd_rom[3122] = 32'h007a8a3f;
pd_rom[3123] = 32'h007a8a3f;
pd_rom[3124] = 32'h007a8a3f;
pd_rom[3125] = 32'h007a8a3f;
pd_rom[3126] = 32'h007a8a3f;
pd_rom[3127] = 32'h007a8a3f;
pd_rom[3128] = 32'h007a8a3f;
pd_rom[3129] = 32'h007a8a3f;
pd_rom[3130] = 32'h007a8a3f;
pd_rom[3131] = 32'h007a8a3f;
pd_rom[3132] = 32'h007a8a3f;
pd_rom[3133] = 32'h007a8a3f;
pd_rom[3134] = 32'h007a8a3f;
pd_rom[3135] = 32'h007a8a3f;
pd_rom[3136] = 32'h007b8a3f;
pd_rom[3137] = 32'h007b8a3f;
pd_rom[3138] = 32'h007b8a3f;
pd_rom[3139] = 32'h007b8a3f;
pd_rom[3140] = 32'h007b8a3f;
pd_rom[3141] = 32'h007b8a3f;
pd_rom[3142] = 32'h007b8a3f;
pd_rom[3143] = 32'h007b8a3f;
pd_rom[3144] = 32'h007b8a3f;
pd_rom[3145] = 32'h007b8a3f;
pd_rom[3146] = 32'h007b8a3f;
pd_rom[3147] = 32'h007b8a3f;
pd_rom[3148] = 32'h007b8a3f;
pd_rom[3149] = 32'h007b8a3f;
pd_rom[3150] = 32'h007b8a3f;
pd_rom[3151] = 32'h007b8a3f;
pd_rom[3152] = 32'h007b8a3f;
pd_rom[3153] = 32'h007b8a3f;
pd_rom[3154] = 32'h007b8a3f;
pd_rom[3155] = 32'h007b8a3f;
pd_rom[3156] = 32'h007b8a3f;
pd_rom[3157] = 32'h007b8a3f;
pd_rom[3158] = 32'h007b8a3f;
pd_rom[3159] = 32'h007b8a3f;
pd_rom[3160] = 32'h007b8a3f;
pd_rom[3161] = 32'h007b8a3f;
pd_rom[3162] = 32'h007b8a3f;
pd_rom[3163] = 32'h007b8a3f;
pd_rom[3164] = 32'h007b8a3f;
pd_rom[3165] = 32'h007b8a3f;
pd_rom[3166] = 32'h007b8a3f;
pd_rom[3167] = 32'h007b8a3f;
pd_rom[3168] = 32'h007b8a3f;
pd_rom[3169] = 32'h007b8a3f;
pd_rom[3170] = 32'h007b8a3f;
pd_rom[3171] = 32'h007b8a3f;
pd_rom[3172] = 32'h007b8a3f;
pd_rom[3173] = 32'h007b8a3f;
pd_rom[3174] = 32'h007b8a3f;
pd_rom[3175] = 32'h007b8a3f;
pd_rom[3176] = 32'h007b8a3f;
pd_rom[3177] = 32'h007b8a3f;
pd_rom[3178] = 32'h007b8a3f;
pd_rom[3179] = 32'h007b8a3f;
pd_rom[3180] = 32'h007b8a3f;
pd_rom[3181] = 32'h007b8a3f;
pd_rom[3182] = 32'h007b8a3f;
pd_rom[3183] = 32'h007b8a3f;
pd_rom[3184] = 32'h007b8a3f;
pd_rom[3185] = 32'h007b8a3f;
pd_rom[3186] = 32'h007b8a3f;
pd_rom[3187] = 32'h007b8a3f;
pd_rom[3188] = 32'h007b8a3f;
pd_rom[3189] = 32'h007b8a3f;
pd_rom[3190] = 32'h007b8a3f;
pd_rom[3191] = 32'h007b8a3f;
pd_rom[3192] = 32'h007b8a3f;
pd_rom[3193] = 32'h007b8a3f;
pd_rom[3194] = 32'h007b8a3f;
pd_rom[3195] = 32'h007b8a3f;
pd_rom[3196] = 32'h007b8a3f;
pd_rom[3197] = 32'h007b8a3f;
pd_rom[3198] = 32'h007b8a3f;
pd_rom[3199] = 32'h007b8a3f;
pd_rom[3200] = 32'h007b8a3f;
pd_rom[3201] = 32'h007b8a3f;
pd_rom[3202] = 32'h007b8a3f;
pd_rom[3203] = 32'h007b8a3f;
pd_rom[3204] = 32'h007b8a3f;
pd_rom[3205] = 32'h007b8a3f;
pd_rom[3206] = 32'h007b8a3f;
pd_rom[3207] = 32'h007b8a3f;
pd_rom[3208] = 32'h007b8a3f;
pd_rom[3209] = 32'h007b8a3f;
pd_rom[3210] = 32'h007b8a3f;
pd_rom[3211] = 32'h007b8a3f;
pd_rom[3212] = 32'h007b8a3f;
pd_rom[3213] = 32'h007b8a3f;
pd_rom[3214] = 32'h007b8a3f;
pd_rom[3215] = 32'h007b8a3f;
pd_rom[3216] = 32'h007b8a3f;
pd_rom[3217] = 32'h007b8a3f;
pd_rom[3218] = 32'h007b8a3f;
pd_rom[3219] = 32'h007b8a3f;
pd_rom[3220] = 32'h007b8a3f;
pd_rom[3221] = 32'h007b8a3f;
pd_rom[3222] = 32'h007b8a3f;
pd_rom[3223] = 32'h007b8a3f;
pd_rom[3224] = 32'h007b8a3f;
pd_rom[3225] = 32'h007b8a3f;
pd_rom[3226] = 32'h007b8a3f;
pd_rom[3227] = 32'h007b8a3f;
pd_rom[3228] = 32'h007b8a3f;
pd_rom[3229] = 32'h007b8a3f;
pd_rom[3230] = 32'h007b8a3f;
pd_rom[3231] = 32'h007b8a3f;
pd_rom[3232] = 32'h007b8a3f;
pd_rom[3233] = 32'h007b8a3f;
pd_rom[3234] = 32'h007b8a3f;
pd_rom[3235] = 32'h007b8a3f;
pd_rom[3236] = 32'h007b8a3f;
pd_rom[3237] = 32'h007b8a3f;
pd_rom[3238] = 32'h007b8a3f;
pd_rom[3239] = 32'h007b8a3f;
pd_rom[3240] = 32'h007b8a3f;
pd_rom[3241] = 32'h007b8a3f;
pd_rom[3242] = 32'h007b8a3f;
pd_rom[3243] = 32'h007b8a3f;
pd_rom[3244] = 32'h007b8a3f;
pd_rom[3245] = 32'h007b8a3f;
pd_rom[3246] = 32'h007b8a3f;
pd_rom[3247] = 32'h007b8a3f;
pd_rom[3248] = 32'h007b8a3f;
pd_rom[3249] = 32'h007b8a3f;
pd_rom[3250] = 32'h007b8a3f;
pd_rom[3251] = 32'h007b8a3f;
pd_rom[3252] = 32'h007b8a3f;
pd_rom[3253] = 32'h007b8a3f;
pd_rom[3254] = 32'h007b8a3f;
pd_rom[3255] = 32'h007b8a3f;
pd_rom[3256] = 32'h007b8a3f;
pd_rom[3257] = 32'h007b8a3f;
pd_rom[3258] = 32'h007b8a3f;
pd_rom[3259] = 32'h007b8a3f;
pd_rom[3260] = 32'h007b8a3f;
pd_rom[3261] = 32'h007b8a3f;
pd_rom[3262] = 32'h007b8a3f;
pd_rom[3263] = 32'h007b8a3f;
pd_rom[3264] = 32'h007b8a3f;
pd_rom[3265] = 32'h007b8a3f;
pd_rom[3266] = 32'h007b8a3f;
pd_rom[3267] = 32'h007b8a3f;
pd_rom[3268] = 32'h007b8a3f;
pd_rom[3269] = 32'h007b8a3f;
pd_rom[3270] = 32'h007b8a3f;
pd_rom[3271] = 32'h007b8a3f;
pd_rom[3272] = 32'h007b8a3f;
pd_rom[3273] = 32'h007b8a3f;
pd_rom[3274] = 32'h007b8a3f;
pd_rom[3275] = 32'h007b8a3f;
pd_rom[3276] = 32'h007b8a3f;
pd_rom[3277] = 32'h007b8a3f;
pd_rom[3278] = 32'h007b8a3f;
pd_rom[3279] = 32'h007b8a3f;
pd_rom[3280] = 32'h007b8a3f;
pd_rom[3281] = 32'h007b8a3f;
pd_rom[3282] = 32'h007b8a3f;
pd_rom[3283] = 32'h007b8a3f;
pd_rom[3284] = 32'h007b8a3f;
pd_rom[3285] = 32'h007b8a3f;
pd_rom[3286] = 32'h007b8a3f;
pd_rom[3287] = 32'h007b8a3f;
pd_rom[3288] = 32'h007b8a3f;
pd_rom[3289] = 32'h007b8a3f;
pd_rom[3290] = 32'h007b8a3f;
pd_rom[3291] = 32'h007b8a3f;
pd_rom[3292] = 32'h007b8a3f;
pd_rom[3293] = 32'h007b8a3f;
pd_rom[3294] = 32'h007b8a3f;
pd_rom[3295] = 32'h007b8a3f;
pd_rom[3296] = 32'h007b8a3f;
pd_rom[3297] = 32'h007b8a3f;
pd_rom[3298] = 32'h007b8a3f;
pd_rom[3299] = 32'h007b8a3f;
pd_rom[3300] = 32'h007b8a3f;
pd_rom[3301] = 32'h007b8a3f;
pd_rom[3302] = 32'h007b8a3f;
pd_rom[3303] = 32'h007b8a3f;
pd_rom[3304] = 32'h007b8a3f;
pd_rom[3305] = 32'h007b8a3f;
pd_rom[3306] = 32'h007b8a3f;
pd_rom[3307] = 32'h007b8a3f;
pd_rom[3308] = 32'h007b8a3f;
pd_rom[3309] = 32'h007b8a3f;
pd_rom[3310] = 32'h007b8a3f;
pd_rom[3311] = 32'h007b8a3f;
pd_rom[3312] = 32'h007b8a3f;
pd_rom[3313] = 32'h007b8a3f;
pd_rom[3314] = 32'h007b8a3f;
pd_rom[3315] = 32'h007b8a3f;
pd_rom[3316] = 32'h007b8a3f;
pd_rom[3317] = 32'h007b8a3f;
pd_rom[3318] = 32'h007b8a3f;
pd_rom[3319] = 32'h007b8a3f;
pd_rom[3320] = 32'h007b8a3f;
pd_rom[3321] = 32'h007b8a3f;
pd_rom[3322] = 32'h007b8a3f;
pd_rom[3323] = 32'h007b8a3f;
pd_rom[3324] = 32'h007b8a3f;
pd_rom[3325] = 32'h007b8a3f;
pd_rom[3326] = 32'h007b8a3f;
pd_rom[3327] = 32'h007b8a3f;
pd_rom[3328] = 32'h007b8a3f;
pd_rom[3329] = 32'h007b8a3f;
pd_rom[3330] = 32'h007b8a3f;
pd_rom[3331] = 32'h007b8a3f;
pd_rom[3332] = 32'h007b8a3f;
pd_rom[3333] = 32'h007b8a3f;
pd_rom[3334] = 32'h007b8a3f;
pd_rom[3335] = 32'h007b8a3f;
pd_rom[3336] = 32'h007b8a3f;
pd_rom[3337] = 32'h007b8a3f;
pd_rom[3338] = 32'h007b8a3f;
pd_rom[3339] = 32'h007b8a3f;
pd_rom[3340] = 32'h007b8a3f;
pd_rom[3341] = 32'h007b8a3f;
pd_rom[3342] = 32'h007b8a3f;
pd_rom[3343] = 32'h007b8a3f;
pd_rom[3344] = 32'h007b8a3f;
pd_rom[3345] = 32'h007b8a3f;
pd_rom[3346] = 32'h007b8a3f;
pd_rom[3347] = 32'h007b8a3f;
pd_rom[3348] = 32'h007b8a3f;
pd_rom[3349] = 32'h007b8a3f;
pd_rom[3350] = 32'h007b8a3f;
pd_rom[3351] = 32'h007b8a3f;
pd_rom[3352] = 32'h007b8a3f;
pd_rom[3353] = 32'h007b8a3f;
pd_rom[3354] = 32'h007b8a3f;
pd_rom[3355] = 32'h007b8a3f;
pd_rom[3356] = 32'h007b8a3f;
pd_rom[3357] = 32'h007b8a3f;
pd_rom[3358] = 32'h007b8a3f;
pd_rom[3359] = 32'h007b8a3f;
pd_rom[3360] = 32'h007b8a3f;
pd_rom[3361] = 32'h007b8a3f;
pd_rom[3362] = 32'h007b8a3f;
pd_rom[3363] = 32'h007b8a3f;
pd_rom[3364] = 32'h007b8a3f;
pd_rom[3365] = 32'h007b8a3f;
pd_rom[3366] = 32'h007b8a3f;
pd_rom[3367] = 32'h007b8a3f;
pd_rom[3368] = 32'h007b8a3f;
pd_rom[3369] = 32'h007b8a3f;
pd_rom[3370] = 32'h007b8a3f;
pd_rom[3371] = 32'h007b8a3f;
pd_rom[3372] = 32'h007b8a3f;
pd_rom[3373] = 32'h007b8a3f;
pd_rom[3374] = 32'h007b8a3f;
pd_rom[3375] = 32'h007b8a3f;
pd_rom[3376] = 32'h007b8a3f;
pd_rom[3377] = 32'h007b8a3f;
pd_rom[3378] = 32'h007b8a3f;
pd_rom[3379] = 32'h007b8a3f;
pd_rom[3380] = 32'h007b8a3f;
pd_rom[3381] = 32'h007b8a3f;
pd_rom[3382] = 32'h007b8a3f;
pd_rom[3383] = 32'h007b8a3f;
pd_rom[3384] = 32'h007b8a3f;
pd_rom[3385] = 32'h007b8a3f;
pd_rom[3386] = 32'h007b8a3f;
pd_rom[3387] = 32'h007b8a3f;
pd_rom[3388] = 32'h007b8a3f;
pd_rom[3389] = 32'h007b8a3f;
pd_rom[3390] = 32'h007b8a3f;
pd_rom[3391] = 32'h007b8a3f;
pd_rom[3392] = 32'h007b8a3f;
pd_rom[3393] = 32'h007b8a3f;
pd_rom[3394] = 32'h007b8a3f;
pd_rom[3395] = 32'h007b8a3f;
pd_rom[3396] = 32'h007b8a3f;
pd_rom[3397] = 32'h007b8a3f;
pd_rom[3398] = 32'h007b8a3f;
pd_rom[3399] = 32'h007b8a3f;
pd_rom[3400] = 32'h007b8a3f;
pd_rom[3401] = 32'h007b8a3f;
pd_rom[3402] = 32'h007b8a3f;
pd_rom[3403] = 32'h007b8a3f;
pd_rom[3404] = 32'h007b8a3f;
pd_rom[3405] = 32'h007b8a3f;
pd_rom[3406] = 32'h007b8a3f;
pd_rom[3407] = 32'h007b8a3f;
pd_rom[3408] = 32'h007b8a3f;
pd_rom[3409] = 32'h007b8a3f;
pd_rom[3410] = 32'h007b8a3f;
pd_rom[3411] = 32'h007b8a3f;
pd_rom[3412] = 32'h007b8a3f;
pd_rom[3413] = 32'h007b8a3f;
pd_rom[3414] = 32'h007b8a3f;
pd_rom[3415] = 32'h007b8a3f;
pd_rom[3416] = 32'h007b8a3f;
pd_rom[3417] = 32'h007b8a3f;
pd_rom[3418] = 32'h007b8a3f;
pd_rom[3419] = 32'h007b8a3f;
pd_rom[3420] = 32'h007b8a3f;
pd_rom[3421] = 32'h007b8a3f;
pd_rom[3422] = 32'h007b8a3f;
pd_rom[3423] = 32'h007b8a3f;
pd_rom[3424] = 32'h007b8a3f;
pd_rom[3425] = 32'h007b8a3f;
pd_rom[3426] = 32'h007b8a3f;
pd_rom[3427] = 32'h007b8a3f;
pd_rom[3428] = 32'h007b8a3f;
pd_rom[3429] = 32'h007b8a3f;
pd_rom[3430] = 32'h007b8a3f;
pd_rom[3431] = 32'h007b8a3f;
pd_rom[3432] = 32'h007b8a3f;
pd_rom[3433] = 32'h007b8a3f;
pd_rom[3434] = 32'h007b8a3f;
pd_rom[3435] = 32'h007b8a3f;
pd_rom[3436] = 32'h007b8a3f;
pd_rom[3437] = 32'h007b8a3f;
pd_rom[3438] = 32'h007b8a3f;
pd_rom[3439] = 32'h007b8a3f;
pd_rom[3440] = 32'h007b8a3f;
pd_rom[3441] = 32'h007b8a3f;
pd_rom[3442] = 32'h007b8a3f;
pd_rom[3443] = 32'h007b8a3f;
pd_rom[3444] = 32'h007b8a3f;
pd_rom[3445] = 32'h007b8a3f;
pd_rom[3446] = 32'h007b8a3f;
pd_rom[3447] = 32'h007b8a3f;
pd_rom[3448] = 32'h007b8a3f;
pd_rom[3449] = 32'h007b8a3f;
pd_rom[3450] = 32'h007b8a3f;
pd_rom[3451] = 32'h007b8a3f;
pd_rom[3452] = 32'h007b8a3f;
pd_rom[3453] = 32'h007b8a3f;
pd_rom[3454] = 32'h007b8a3f;
pd_rom[3455] = 32'h007b8a3f;
pd_rom[3456] = 32'h007b8a3f;
pd_rom[3457] = 32'h007b8a3f;
pd_rom[3458] = 32'h007b8a3f;
pd_rom[3459] = 32'h007b8a3f;
pd_rom[3460] = 32'h007b8a3f;
pd_rom[3461] = 32'h007b8a3f;
pd_rom[3462] = 32'h007b8a3f;
pd_rom[3463] = 32'h007b8a3f;
pd_rom[3464] = 32'h007b8a3f;
pd_rom[3465] = 32'h007b8a3f;
pd_rom[3466] = 32'h007b8a3f;
pd_rom[3467] = 32'h007b8a3f;
pd_rom[3468] = 32'h007b8a3f;
pd_rom[3469] = 32'h007b8a3f;
pd_rom[3470] = 32'h007b8a3f;
pd_rom[3471] = 32'h007b8a3f;
pd_rom[3472] = 32'h007b8a3f;
pd_rom[3473] = 32'h007b8a3f;
pd_rom[3474] = 32'h007b8a3f;
pd_rom[3475] = 32'h007b8a3f;
pd_rom[3476] = 32'h007b8a3f;
pd_rom[3477] = 32'h007b8a3f;
pd_rom[3478] = 32'h007b8a3f;
pd_rom[3479] = 32'h007b8a3f;
pd_rom[3480] = 32'h007b8a3f;
pd_rom[3481] = 32'h007b8a3f;
pd_rom[3482] = 32'h007b8a3f;
pd_rom[3483] = 32'h007b8a3f;
pd_rom[3484] = 32'h007b8a3f;
pd_rom[3485] = 32'h007b8a3f;
pd_rom[3486] = 32'h007b8a3f;
pd_rom[3487] = 32'h007b8a3f;
pd_rom[3488] = 32'h007b8a3f;
pd_rom[3489] = 32'h007b8a3f;
pd_rom[3490] = 32'h007b8a3f;
pd_rom[3491] = 32'h007b8a3f;
pd_rom[3492] = 32'h007b8a3f;
pd_rom[3493] = 32'h007b8a3f;
pd_rom[3494] = 32'h007b8a3f;
pd_rom[3495] = 32'h007b8a3f;
pd_rom[3496] = 32'h007b8a3f;
pd_rom[3497] = 32'h007b8a3f;
pd_rom[3498] = 32'h007b8a3f;
pd_rom[3499] = 32'h007b8a3f;
pd_rom[3500] = 32'h007b8a3f;
pd_rom[3501] = 32'h007b8a3f;
pd_rom[3502] = 32'h007b8a3f;
pd_rom[3503] = 32'h007b8a3f;
pd_rom[3504] = 32'h007b8a3f;
pd_rom[3505] = 32'h007b8a3f;
pd_rom[3506] = 32'h007b8a3f;
pd_rom[3507] = 32'h007b8a3f;
pd_rom[3508] = 32'h007b8a3f;
pd_rom[3509] = 32'h007b8a3f;
pd_rom[3510] = 32'h007b8a3f;
pd_rom[3511] = 32'h007b8a3f;
pd_rom[3512] = 32'h007b8a3f;
pd_rom[3513] = 32'h007b8a3f;
pd_rom[3514] = 32'h007b8a3f;
pd_rom[3515] = 32'h007b8a3f;
pd_rom[3516] = 32'h007b8a3f;
pd_rom[3517] = 32'h007b8a3f;
pd_rom[3518] = 32'h007b8a3f;
pd_rom[3519] = 32'h007b8a3f;
pd_rom[3520] = 32'h007b8a3f;
pd_rom[3521] = 32'h007b8a3f;
pd_rom[3522] = 32'h007b8a3f;
pd_rom[3523] = 32'h007b8a3f;
pd_rom[3524] = 32'h007b8a3f;
pd_rom[3525] = 32'h007b8a3f;
pd_rom[3526] = 32'h007b8a3f;
pd_rom[3527] = 32'h007b8a3f;
pd_rom[3528] = 32'h007b8a3f;
pd_rom[3529] = 32'h007b8a3f;
pd_rom[3530] = 32'h007b8a3f;
pd_rom[3531] = 32'h007b8a3f;
pd_rom[3532] = 32'h007b8a3f;
pd_rom[3533] = 32'h007b8a3f;
pd_rom[3534] = 32'h007b8a3f;
pd_rom[3535] = 32'h007b8a3f;
pd_rom[3536] = 32'h007b8a3f;
pd_rom[3537] = 32'h007b8a3f;
pd_rom[3538] = 32'h007b8a3f;
pd_rom[3539] = 32'h007b8a3f;
pd_rom[3540] = 32'h007b8a3f;
pd_rom[3541] = 32'h007b8a3f;
pd_rom[3542] = 32'h007b8a3f;
pd_rom[3543] = 32'h007b8a3f;
pd_rom[3544] = 32'h007b8a3f;
pd_rom[3545] = 32'h007b8a3f;
pd_rom[3546] = 32'h007b8a3f;
pd_rom[3547] = 32'h007b8a3f;
pd_rom[3548] = 32'h007b8a3f;
pd_rom[3549] = 32'h007b8a3f;
pd_rom[3550] = 32'h007b8a3f;
pd_rom[3551] = 32'h007b8a3f;
pd_rom[3552] = 32'h007b8a3f;
pd_rom[3553] = 32'h007b8a3f;
pd_rom[3554] = 32'h007b8a3f;
pd_rom[3555] = 32'h007b8a3f;
pd_rom[3556] = 32'h007b8a3f;
pd_rom[3557] = 32'h007b8a3f;
pd_rom[3558] = 32'h007b8a3f;
pd_rom[3559] = 32'h007b8a3f;
pd_rom[3560] = 32'h007b8a3f;
pd_rom[3561] = 32'h007b8a3f;
pd_rom[3562] = 32'h007b8a3f;
pd_rom[3563] = 32'h007b8a3f;
pd_rom[3564] = 32'h007b8a3f;
pd_rom[3565] = 32'h007b8a3f;
pd_rom[3566] = 32'h007b8a3f;
pd_rom[3567] = 32'h007b8a3f;
pd_rom[3568] = 32'h007b8a3f;
pd_rom[3569] = 32'h007b8a3f;
pd_rom[3570] = 32'h007b8a3f;
pd_rom[3571] = 32'h007b8a3f;
pd_rom[3572] = 32'h007b8a3f;
pd_rom[3573] = 32'h007b8a3f;
pd_rom[3574] = 32'h007b8a3f;
pd_rom[3575] = 32'h007b8a3f;
pd_rom[3576] = 32'h007b8a3f;
pd_rom[3577] = 32'h007b8a3f;
pd_rom[3578] = 32'h007b8a3f;
pd_rom[3579] = 32'h007b8a3f;
pd_rom[3580] = 32'h007b8a3f;
pd_rom[3581] = 32'h007b8a3f;
pd_rom[3582] = 32'h007b8a3f;
pd_rom[3583] = 32'h007b8a3f;
pd_rom[3584] = 32'h007c803f;
pd_rom[3585] = 32'h007c803f;
pd_rom[3586] = 32'h007c803f;
pd_rom[3587] = 32'h007c803f;
pd_rom[3588] = 32'h007c803f;
pd_rom[3589] = 32'h007c803f;
pd_rom[3590] = 32'h007c803f;
pd_rom[3591] = 32'h007c803f;
pd_rom[3592] = 32'h007c803f;
pd_rom[3593] = 32'h007c803f;
pd_rom[3594] = 32'h007c803f;
pd_rom[3595] = 32'h007c803f;
pd_rom[3596] = 32'h007c803f;
pd_rom[3597] = 32'h007c803f;
pd_rom[3598] = 32'h007c803f;
pd_rom[3599] = 32'h007c803f;
pd_rom[3600] = 32'h007c803f;
pd_rom[3601] = 32'h007c803f;
pd_rom[3602] = 32'h007c803f;
pd_rom[3603] = 32'h007c803f;
pd_rom[3604] = 32'h007c803f;
pd_rom[3605] = 32'h007c803f;
pd_rom[3606] = 32'h007c803f;
pd_rom[3607] = 32'h007c803f;
pd_rom[3608] = 32'h007c803f;
pd_rom[3609] = 32'h007c803f;
pd_rom[3610] = 32'h007c803f;
pd_rom[3611] = 32'h007c803f;
pd_rom[3612] = 32'h007c803f;
pd_rom[3613] = 32'h007c803f;
pd_rom[3614] = 32'h007c803f;
pd_rom[3615] = 32'h007c803f;
pd_rom[3648] = 32'h007c803f;
pd_rom[3649] = 32'h007c803f;
pd_rom[3650] = 32'h007c803f;
pd_rom[3651] = 32'h007c803f;
pd_rom[3652] = 32'h007c803f;
pd_rom[3653] = 32'h007c803f;
pd_rom[3654] = 32'h007c803f;
pd_rom[3655] = 32'h007c803f;
pd_rom[3656] = 32'h007c803f;
pd_rom[3657] = 32'h007c803f;
pd_rom[3658] = 32'h007c803f;
pd_rom[3659] = 32'h007c803f;
pd_rom[3660] = 32'h007c803f;
pd_rom[3661] = 32'h007c803f;
pd_rom[3662] = 32'h007c803f;
pd_rom[3663] = 32'h007c803f;
pd_rom[3664] = 32'h007c803f;
pd_rom[3665] = 32'h007c803f;
pd_rom[3666] = 32'h007c803f;
pd_rom[3667] = 32'h007c803f;
pd_rom[3668] = 32'h007c803f;
pd_rom[3669] = 32'h007c803f;
pd_rom[3670] = 32'h007c803f;
pd_rom[3671] = 32'h007c803f;
pd_rom[3672] = 32'h007c803f;
pd_rom[3673] = 32'h007c803f;
pd_rom[3674] = 32'h007c803f;
pd_rom[3675] = 32'h007c803f;
pd_rom[3676] = 32'h007c803f;
pd_rom[3677] = 32'h007c803f;
pd_rom[3678] = 32'h007c803f;
pd_rom[3679] = 32'h007c803f;
pd_rom[3712] = 32'h007c803f;
pd_rom[3713] = 32'h007c803f;
pd_rom[3714] = 32'h007c803f;
pd_rom[3715] = 32'h007c803f;
pd_rom[3716] = 32'h007c803f;
pd_rom[3717] = 32'h007c803f;
pd_rom[3718] = 32'h007c803f;
pd_rom[3719] = 32'h007c803f;
pd_rom[3720] = 32'h007c803f;
pd_rom[3721] = 32'h007c803f;
pd_rom[3722] = 32'h007c803f;
pd_rom[3723] = 32'h007c803f;
pd_rom[3724] = 32'h007c803f;
pd_rom[3725] = 32'h007c803f;
pd_rom[3726] = 32'h007c803f;
pd_rom[3727] = 32'h007c803f;
pd_rom[3728] = 32'h007c803f;
pd_rom[3729] = 32'h007c803f;
pd_rom[3730] = 32'h007c803f;
pd_rom[3731] = 32'h007c803f;
pd_rom[3732] = 32'h007c803f;
pd_rom[3733] = 32'h007c803f;
pd_rom[3734] = 32'h007c803f;
pd_rom[3735] = 32'h007c803f;
pd_rom[3736] = 32'h007c803f;
pd_rom[3737] = 32'h007c803f;
pd_rom[3738] = 32'h007c803f;
pd_rom[3739] = 32'h007c803f;
pd_rom[3740] = 32'h007c803f;
pd_rom[3741] = 32'h007c803f;
pd_rom[3742] = 32'h007c803f;
pd_rom[3743] = 32'h007c803f;
pd_rom[3776] = 32'h007c803f;
pd_rom[3777] = 32'h007c803f;
pd_rom[3778] = 32'h007c803f;
pd_rom[3779] = 32'h007c803f;
pd_rom[3780] = 32'h007c803f;
pd_rom[3781] = 32'h007c803f;
pd_rom[3782] = 32'h007c803f;
pd_rom[3783] = 32'h007c803f;
pd_rom[3784] = 32'h007c803f;
pd_rom[3785] = 32'h007c803f;
pd_rom[3786] = 32'h007c803f;
pd_rom[3787] = 32'h007c803f;
pd_rom[3788] = 32'h007c803f;
pd_rom[3789] = 32'h007c803f;
pd_rom[3790] = 32'h007c803f;
pd_rom[3791] = 32'h007c803f;
pd_rom[3792] = 32'h007c803f;
pd_rom[3793] = 32'h007c803f;
pd_rom[3794] = 32'h007c803f;
pd_rom[3795] = 32'h007c803f;
pd_rom[3796] = 32'h007c803f;
pd_rom[3797] = 32'h007c803f;
pd_rom[3798] = 32'h007c803f;
pd_rom[3799] = 32'h007c803f;
pd_rom[3800] = 32'h007c803f;
pd_rom[3801] = 32'h007c803f;
pd_rom[3802] = 32'h007c803f;
pd_rom[3803] = 32'h007c803f;
pd_rom[3804] = 32'h007c803f;
pd_rom[3805] = 32'h007c803f;
pd_rom[3806] = 32'h007c803f;
pd_rom[3807] = 32'h007c803f;
pd_rom[3840] = 32'h007c803f;
pd_rom[3841] = 32'h007c803f;
pd_rom[3842] = 32'h007c803f;
pd_rom[3843] = 32'h007c803f;
pd_rom[3844] = 32'h007c803f;
pd_rom[3845] = 32'h007c803f;
pd_rom[3846] = 32'h007c803f;
pd_rom[3847] = 32'h007c803f;
pd_rom[3848] = 32'h007c803f;
pd_rom[3849] = 32'h007c803f;
pd_rom[3850] = 32'h007c803f;
pd_rom[3851] = 32'h007c803f;
pd_rom[3852] = 32'h007c803f;
pd_rom[3853] = 32'h007c803f;
pd_rom[3854] = 32'h007c803f;
pd_rom[3855] = 32'h007c803f;
pd_rom[3856] = 32'h007c803f;
pd_rom[3857] = 32'h007c803f;
pd_rom[3858] = 32'h007c803f;
pd_rom[3859] = 32'h007c803f;
pd_rom[3860] = 32'h007c803f;
pd_rom[3861] = 32'h007c803f;
pd_rom[3862] = 32'h007c803f;
pd_rom[3863] = 32'h007c803f;
pd_rom[3864] = 32'h007c803f;
pd_rom[3865] = 32'h007c803f;
pd_rom[3866] = 32'h007c803f;
pd_rom[3867] = 32'h007c803f;
pd_rom[3868] = 32'h007c803f;
pd_rom[3869] = 32'h007c803f;
pd_rom[3870] = 32'h007c803f;
pd_rom[3871] = 32'h007c803f;
pd_rom[3904] = 32'h007c803f;
pd_rom[3905] = 32'h007c803f;
pd_rom[3906] = 32'h007c803f;
pd_rom[3907] = 32'h007c803f;
pd_rom[3908] = 32'h007c803f;
pd_rom[3909] = 32'h007c803f;
pd_rom[3910] = 32'h007c803f;
pd_rom[3911] = 32'h007c803f;
pd_rom[3912] = 32'h007c803f;
pd_rom[3913] = 32'h007c803f;
pd_rom[3914] = 32'h007c803f;
pd_rom[3915] = 32'h007c803f;
pd_rom[3916] = 32'h007c803f;
pd_rom[3917] = 32'h007c803f;
pd_rom[3918] = 32'h007c803f;
pd_rom[3919] = 32'h007c803f;
pd_rom[3920] = 32'h007c803f;
pd_rom[3921] = 32'h007c803f;
pd_rom[3922] = 32'h007c803f;
pd_rom[3923] = 32'h007c803f;
pd_rom[3924] = 32'h007c803f;
pd_rom[3925] = 32'h007c803f;
pd_rom[3926] = 32'h007c803f;
pd_rom[3927] = 32'h007c803f;
pd_rom[3928] = 32'h007c803f;
pd_rom[3929] = 32'h007c803f;
pd_rom[3930] = 32'h007c803f;
pd_rom[3931] = 32'h007c803f;
pd_rom[3932] = 32'h007c803f;
pd_rom[3933] = 32'h007c803f;
pd_rom[3934] = 32'h007c803f;
pd_rom[3935] = 32'h007c803f;
pd_rom[3968] = 32'h007c803f;
pd_rom[3969] = 32'h007c803f;
pd_rom[3970] = 32'h007c803f;
pd_rom[3971] = 32'h007c803f;
pd_rom[3972] = 32'h007c803f;
pd_rom[3973] = 32'h007c803f;
pd_rom[3974] = 32'h007c803f;
pd_rom[3975] = 32'h007c803f;
pd_rom[3976] = 32'h007c803f;
pd_rom[3977] = 32'h007c803f;
pd_rom[3978] = 32'h007c803f;
pd_rom[3979] = 32'h007c803f;
pd_rom[3980] = 32'h007c803f;
pd_rom[3981] = 32'h007c803f;
pd_rom[3982] = 32'h007c803f;
pd_rom[3983] = 32'h007c803f;
pd_rom[3984] = 32'h007c803f;
pd_rom[3985] = 32'h007c803f;
pd_rom[3986] = 32'h007c803f;
pd_rom[3987] = 32'h007c803f;
pd_rom[3988] = 32'h007c803f;
pd_rom[3989] = 32'h007c803f;
pd_rom[3990] = 32'h007c803f;
pd_rom[3991] = 32'h007c803f;
pd_rom[3992] = 32'h007c803f;
pd_rom[3993] = 32'h007c803f;
pd_rom[3994] = 32'h007c803f;
pd_rom[3995] = 32'h007c803f;
pd_rom[3996] = 32'h007c803f;
pd_rom[3997] = 32'h007c803f;
pd_rom[3998] = 32'h007c803f;
pd_rom[3999] = 32'h007c803f;
pd_rom[4032] = 32'h007c803f;
pd_rom[4033] = 32'h007c803f;
pd_rom[4034] = 32'h007c803f;
pd_rom[4035] = 32'h007c803f;
pd_rom[4036] = 32'h007c803f;
pd_rom[4037] = 32'h007c803f;
pd_rom[4038] = 32'h007c803f;
pd_rom[4039] = 32'h007c803f;
pd_rom[4040] = 32'h007c803f;
pd_rom[4041] = 32'h007c803f;
pd_rom[4042] = 32'h007c803f;
pd_rom[4043] = 32'h007c803f;
pd_rom[4044] = 32'h007c803f;
pd_rom[4045] = 32'h007c803f;
pd_rom[4046] = 32'h007c803f;
pd_rom[4047] = 32'h007c803f;
pd_rom[4048] = 32'h007c803f;
pd_rom[4049] = 32'h007c803f;
pd_rom[4050] = 32'h007c803f;
pd_rom[4051] = 32'h007c803f;
pd_rom[4052] = 32'h007c803f;
pd_rom[4053] = 32'h007c803f;
pd_rom[4054] = 32'h007c803f;
pd_rom[4055] = 32'h007c803f;
pd_rom[4056] = 32'h007c803f;
pd_rom[4057] = 32'h007c803f;
pd_rom[4058] = 32'h007c803f;
pd_rom[4059] = 32'h007c803f;
pd_rom[4060] = 32'h007c803f;
pd_rom[4061] = 32'h007c803f;
pd_rom[4062] = 32'h007c803f;
pd_rom[4063] = 32'h007c803f;
pd_rom[4096] = 32'h007dc13f;
pd_rom[4097] = 32'h007dc120;
pd_rom[4098] = 32'h007dc13f;
pd_rom[4099] = 32'h007dc13f;
pd_rom[4100] = 32'h007dc13f;
pd_rom[4101] = 32'h007dc13f;
pd_rom[4102] = 32'h007dc13f;
pd_rom[4103] = 32'h007dc13f;
pd_rom[4104] = 32'h008cc13f;
pd_rom[4105] = 32'h008cc120;
pd_rom[4106] = 32'h008cc13f;
pd_rom[4107] = 32'h008cc13f;
pd_rom[4108] = 32'h008cc13f;
pd_rom[4109] = 32'h008cc13f;
pd_rom[4110] = 32'h008cc13f;
pd_rom[4111] = 32'h008cc13f;
pd_rom[4112] = 32'h009bc13f;
pd_rom[4113] = 32'h009bc120;
pd_rom[4114] = 32'h009bc13f;
pd_rom[4115] = 32'h009bc13f;
pd_rom[4116] = 32'h009bc13f;
pd_rom[4117] = 32'h009bc13f;
pd_rom[4118] = 32'h009bc13f;
pd_rom[4119] = 32'h009bc13f;
pd_rom[4120] = 32'h00aa413f;
pd_rom[4121] = 32'h00aa4120;
pd_rom[4122] = 32'h00aa413f;
pd_rom[4123] = 32'h00aa413f;
pd_rom[4124] = 32'h00aa413f;
pd_rom[4125] = 32'h00aa413f;
pd_rom[4126] = 32'h00aa413f;
pd_rom[4127] = 32'h00aa413f;
pd_rom[4128] = 32'h00ae003f;
pd_rom[4129] = 32'h00af003f;
pd_rom[4130] = 32'h007ec13f;
pd_rom[4131] = 32'h007ec13f;
pd_rom[4132] = 32'h007ec13f;
pd_rom[4133] = 32'h007ec13f;
pd_rom[4134] = 32'h007ec13f;
pd_rom[4135] = 32'h007ec123;
pd_rom[4136] = 32'h00b2863f;
pd_rom[4137] = 32'h00b3863f;
pd_rom[4138] = 32'h008dc13f;
pd_rom[4139] = 32'h008dc13f;
pd_rom[4140] = 32'h008dc13f;
pd_rom[4141] = 32'h008dc13f;
pd_rom[4142] = 32'h008dc13f;
pd_rom[4143] = 32'h008dc123;
pd_rom[4144] = 32'h00b4863f;
pd_rom[4145] = 32'h00b5863f;
pd_rom[4146] = 32'h009cc13f;
pd_rom[4147] = 32'h009cc13f;
pd_rom[4148] = 32'h009cc13f;
pd_rom[4149] = 32'h009cc13f;
pd_rom[4150] = 32'h009cc13f;
pd_rom[4151] = 32'h009cc123;
pd_rom[4152] = 32'h00ab413f;
pd_rom[4153] = 32'h00ab4120;
pd_rom[4154] = 32'h00ab413f;
pd_rom[4155] = 32'h00ab413f;
pd_rom[4156] = 32'h00ab413f;
pd_rom[4157] = 32'h00ab413f;
pd_rom[4158] = 32'h00ab413f;
pd_rom[4159] = 32'h00ab413f;
pd_rom[4160] = 32'h007dc13f;
pd_rom[4161] = 32'h007dc120;
pd_rom[4162] = 32'h007dc13f;
pd_rom[4163] = 32'h007dc13f;
pd_rom[4164] = 32'h007dc13f;
pd_rom[4165] = 32'h007dc13f;
pd_rom[4166] = 32'h007dc13f;
pd_rom[4167] = 32'h007dc13f;
pd_rom[4168] = 32'h008cc13f;
pd_rom[4169] = 32'h008cc120;
pd_rom[4170] = 32'h008cc13f;
pd_rom[4171] = 32'h008cc13f;
pd_rom[4172] = 32'h008cc13f;
pd_rom[4173] = 32'h008cc13f;
pd_rom[4174] = 32'h008cc13f;
pd_rom[4175] = 32'h008cc13f;
pd_rom[4176] = 32'h009bc13f;
pd_rom[4177] = 32'h009bc120;
pd_rom[4178] = 32'h009bc13f;
pd_rom[4179] = 32'h009bc13f;
pd_rom[4180] = 32'h009bc13f;
pd_rom[4181] = 32'h009bc13f;
pd_rom[4182] = 32'h009bc13f;
pd_rom[4183] = 32'h009bc13f;
pd_rom[4184] = 32'h00aa413f;
pd_rom[4185] = 32'h00aa4120;
pd_rom[4186] = 32'h00aa413f;
pd_rom[4187] = 32'h00aa413f;
pd_rom[4188] = 32'h00aa413f;
pd_rom[4189] = 32'h00aa413f;
pd_rom[4190] = 32'h00aa413f;
pd_rom[4191] = 32'h00aa413f;
pd_rom[4192] = 32'h00ae003f;
pd_rom[4193] = 32'h00af003f;
pd_rom[4194] = 32'h007ec13f;
pd_rom[4195] = 32'h007ec13f;
pd_rom[4196] = 32'h007ec13f;
pd_rom[4197] = 32'h007ec13f;
pd_rom[4198] = 32'h007ec13f;
pd_rom[4199] = 32'h007ec123;
pd_rom[4200] = 32'h00b2863f;
pd_rom[4201] = 32'h00b3863f;
pd_rom[4202] = 32'h008dc13f;
pd_rom[4203] = 32'h008dc13f;
pd_rom[4204] = 32'h008dc13f;
pd_rom[4205] = 32'h008dc13f;
pd_rom[4206] = 32'h008dc13f;
pd_rom[4207] = 32'h008dc123;
pd_rom[4208] = 32'h00b4863f;
pd_rom[4209] = 32'h00b5863f;
pd_rom[4210] = 32'h009cc13f;
pd_rom[4211] = 32'h009cc13f;
pd_rom[4212] = 32'h009cc13f;
pd_rom[4213] = 32'h009cc13f;
pd_rom[4214] = 32'h009cc13f;
pd_rom[4215] = 32'h009cc123;
pd_rom[4216] = 32'h00ab413f;
pd_rom[4217] = 32'h00ab4120;
pd_rom[4218] = 32'h00ab413f;
pd_rom[4219] = 32'h00ab413f;
pd_rom[4220] = 32'h00ab413f;
pd_rom[4221] = 32'h00ab413f;
pd_rom[4222] = 32'h00ab413f;
pd_rom[4223] = 32'h00ab413f;
pd_rom[4224] = 32'h007dc13f;
pd_rom[4225] = 32'h007dc120;
pd_rom[4226] = 32'h007dc13f;
pd_rom[4227] = 32'h007dc13f;
pd_rom[4228] = 32'h007dc13f;
pd_rom[4229] = 32'h007dc13f;
pd_rom[4230] = 32'h007dc13f;
pd_rom[4231] = 32'h007dc13f;
pd_rom[4232] = 32'h008cc13f;
pd_rom[4233] = 32'h008cc120;
pd_rom[4234] = 32'h008cc13f;
pd_rom[4235] = 32'h008cc13f;
pd_rom[4236] = 32'h008cc13f;
pd_rom[4237] = 32'h008cc13f;
pd_rom[4238] = 32'h008cc13f;
pd_rom[4239] = 32'h008cc13f;
pd_rom[4240] = 32'h009bc13f;
pd_rom[4241] = 32'h009bc120;
pd_rom[4242] = 32'h009bc13f;
pd_rom[4243] = 32'h009bc13f;
pd_rom[4244] = 32'h009bc13f;
pd_rom[4245] = 32'h009bc13f;
pd_rom[4246] = 32'h009bc13f;
pd_rom[4247] = 32'h009bc13f;
pd_rom[4248] = 32'h00aa413f;
pd_rom[4249] = 32'h00aa4120;
pd_rom[4250] = 32'h00aa413f;
pd_rom[4251] = 32'h00aa413f;
pd_rom[4252] = 32'h00aa413f;
pd_rom[4253] = 32'h00aa413f;
pd_rom[4254] = 32'h00aa413f;
pd_rom[4255] = 32'h00aa413f;
pd_rom[4256] = 32'h00ae003f;
pd_rom[4257] = 32'h00af003f;
pd_rom[4258] = 32'h007ec13f;
pd_rom[4259] = 32'h007ec13f;
pd_rom[4260] = 32'h007ec13f;
pd_rom[4261] = 32'h007ec13f;
pd_rom[4262] = 32'h007ec13f;
pd_rom[4263] = 32'h007ec123;
pd_rom[4264] = 32'h00b2863f;
pd_rom[4265] = 32'h00b3863f;
pd_rom[4266] = 32'h008dc13f;
pd_rom[4267] = 32'h008dc13f;
pd_rom[4268] = 32'h008dc13f;
pd_rom[4269] = 32'h008dc13f;
pd_rom[4270] = 32'h008dc13f;
pd_rom[4271] = 32'h008dc123;
pd_rom[4272] = 32'h00b4863f;
pd_rom[4273] = 32'h00b5863f;
pd_rom[4274] = 32'h009cc13f;
pd_rom[4275] = 32'h009cc13f;
pd_rom[4276] = 32'h009cc13f;
pd_rom[4277] = 32'h009cc13f;
pd_rom[4278] = 32'h009cc13f;
pd_rom[4279] = 32'h009cc123;
pd_rom[4280] = 32'h00ab413f;
pd_rom[4281] = 32'h00ab4120;
pd_rom[4282] = 32'h00ab413f;
pd_rom[4283] = 32'h00ab413f;
pd_rom[4284] = 32'h00ab413f;
pd_rom[4285] = 32'h00ab413f;
pd_rom[4286] = 32'h00ab413f;
pd_rom[4287] = 32'h00ab413f;
pd_rom[4288] = 32'h007dc13f;
pd_rom[4289] = 32'h007dc120;
pd_rom[4290] = 32'h007dc13f;
pd_rom[4291] = 32'h007dc13f;
pd_rom[4292] = 32'h007dc13f;
pd_rom[4293] = 32'h007dc13f;
pd_rom[4294] = 32'h007dc13f;
pd_rom[4295] = 32'h007dc13f;
pd_rom[4296] = 32'h008cc13f;
pd_rom[4297] = 32'h008cc120;
pd_rom[4298] = 32'h008cc13f;
pd_rom[4299] = 32'h008cc13f;
pd_rom[4300] = 32'h008cc13f;
pd_rom[4301] = 32'h008cc13f;
pd_rom[4302] = 32'h008cc13f;
pd_rom[4303] = 32'h008cc13f;
pd_rom[4304] = 32'h009bc13f;
pd_rom[4305] = 32'h009bc120;
pd_rom[4306] = 32'h009bc13f;
pd_rom[4307] = 32'h009bc13f;
pd_rom[4308] = 32'h009bc13f;
pd_rom[4309] = 32'h009bc13f;
pd_rom[4310] = 32'h009bc13f;
pd_rom[4311] = 32'h009bc13f;
pd_rom[4312] = 32'h00aa413f;
pd_rom[4313] = 32'h00aa4120;
pd_rom[4314] = 32'h00aa413f;
pd_rom[4315] = 32'h00aa413f;
pd_rom[4316] = 32'h00aa413f;
pd_rom[4317] = 32'h00aa413f;
pd_rom[4318] = 32'h00aa413f;
pd_rom[4319] = 32'h00aa413f;
pd_rom[4320] = 32'h00ae003f;
pd_rom[4321] = 32'h00af003f;
pd_rom[4322] = 32'h007ec13f;
pd_rom[4323] = 32'h007ec13f;
pd_rom[4324] = 32'h007ec13f;
pd_rom[4325] = 32'h007ec13f;
pd_rom[4326] = 32'h007ec13f;
pd_rom[4327] = 32'h007ec123;
pd_rom[4328] = 32'h00b2863f;
pd_rom[4329] = 32'h00b3863f;
pd_rom[4330] = 32'h008dc13f;
pd_rom[4331] = 32'h008dc13f;
pd_rom[4332] = 32'h008dc13f;
pd_rom[4333] = 32'h008dc13f;
pd_rom[4334] = 32'h008dc13f;
pd_rom[4335] = 32'h008dc123;
pd_rom[4336] = 32'h00b4863f;
pd_rom[4337] = 32'h00b5863f;
pd_rom[4338] = 32'h009cc13f;
pd_rom[4339] = 32'h009cc13f;
pd_rom[4340] = 32'h009cc13f;
pd_rom[4341] = 32'h009cc13f;
pd_rom[4342] = 32'h009cc13f;
pd_rom[4343] = 32'h009cc123;
pd_rom[4344] = 32'h00ab413f;
pd_rom[4345] = 32'h00ab4120;
pd_rom[4346] = 32'h00ab413f;
pd_rom[4347] = 32'h00ab413f;
pd_rom[4348] = 32'h00ab413f;
pd_rom[4349] = 32'h00ab413f;
pd_rom[4350] = 32'h00ab413f;
pd_rom[4351] = 32'h00ab413f;
pd_rom[4352] = 32'h007dc13f;
pd_rom[4353] = 32'h007dc120;
pd_rom[4354] = 32'h007dc13f;
pd_rom[4355] = 32'h007dc13f;
pd_rom[4356] = 32'h007dc13f;
pd_rom[4357] = 32'h007dc13f;
pd_rom[4358] = 32'h007dc13f;
pd_rom[4359] = 32'h007dc13f;
pd_rom[4360] = 32'h008cc13f;
pd_rom[4361] = 32'h008cc120;
pd_rom[4362] = 32'h008cc13f;
pd_rom[4363] = 32'h008cc13f;
pd_rom[4364] = 32'h008cc13f;
pd_rom[4365] = 32'h008cc13f;
pd_rom[4366] = 32'h008cc13f;
pd_rom[4367] = 32'h008cc13f;
pd_rom[4368] = 32'h009bc13f;
pd_rom[4369] = 32'h009bc120;
pd_rom[4370] = 32'h009bc13f;
pd_rom[4371] = 32'h009bc13f;
pd_rom[4372] = 32'h009bc13f;
pd_rom[4373] = 32'h009bc13f;
pd_rom[4374] = 32'h009bc13f;
pd_rom[4375] = 32'h009bc13f;
pd_rom[4376] = 32'h00aa413f;
pd_rom[4377] = 32'h00aa4120;
pd_rom[4378] = 32'h00aa413f;
pd_rom[4379] = 32'h00aa413f;
pd_rom[4380] = 32'h00aa413f;
pd_rom[4381] = 32'h00aa413f;
pd_rom[4382] = 32'h00aa413f;
pd_rom[4383] = 32'h00aa413f;
pd_rom[4384] = 32'h00ae003f;
pd_rom[4385] = 32'h00af003f;
pd_rom[4386] = 32'h007ec13f;
pd_rom[4387] = 32'h007ec13f;
pd_rom[4388] = 32'h007ec13f;
pd_rom[4389] = 32'h007ec13f;
pd_rom[4390] = 32'h007ec13f;
pd_rom[4391] = 32'h007ec123;
pd_rom[4392] = 32'h00b2863f;
pd_rom[4393] = 32'h00b3863f;
pd_rom[4394] = 32'h008dc13f;
pd_rom[4395] = 32'h008dc13f;
pd_rom[4396] = 32'h008dc13f;
pd_rom[4397] = 32'h008dc13f;
pd_rom[4398] = 32'h008dc13f;
pd_rom[4399] = 32'h008dc123;
pd_rom[4400] = 32'h00b4863f;
pd_rom[4401] = 32'h00b5863f;
pd_rom[4402] = 32'h009cc13f;
pd_rom[4403] = 32'h009cc13f;
pd_rom[4404] = 32'h009cc13f;
pd_rom[4405] = 32'h009cc13f;
pd_rom[4406] = 32'h009cc13f;
pd_rom[4407] = 32'h009cc123;
pd_rom[4408] = 32'h00ab413f;
pd_rom[4409] = 32'h00ab4120;
pd_rom[4410] = 32'h00ab413f;
pd_rom[4411] = 32'h00ab413f;
pd_rom[4412] = 32'h00ab413f;
pd_rom[4413] = 32'h00ab413f;
pd_rom[4414] = 32'h00ab413f;
pd_rom[4415] = 32'h00ab413f;
pd_rom[4416] = 32'h007dc13f;
pd_rom[4417] = 32'h007dc120;
pd_rom[4418] = 32'h007dc13f;
pd_rom[4419] = 32'h007dc13f;
pd_rom[4420] = 32'h007dc13f;
pd_rom[4421] = 32'h007dc13f;
pd_rom[4422] = 32'h007dc13f;
pd_rom[4423] = 32'h007dc13f;
pd_rom[4424] = 32'h008cc13f;
pd_rom[4425] = 32'h008cc120;
pd_rom[4426] = 32'h008cc13f;
pd_rom[4427] = 32'h008cc13f;
pd_rom[4428] = 32'h008cc13f;
pd_rom[4429] = 32'h008cc13f;
pd_rom[4430] = 32'h008cc13f;
pd_rom[4431] = 32'h008cc13f;
pd_rom[4432] = 32'h009bc13f;
pd_rom[4433] = 32'h009bc120;
pd_rom[4434] = 32'h009bc13f;
pd_rom[4435] = 32'h009bc13f;
pd_rom[4436] = 32'h009bc13f;
pd_rom[4437] = 32'h009bc13f;
pd_rom[4438] = 32'h009bc13f;
pd_rom[4439] = 32'h009bc13f;
pd_rom[4440] = 32'h00aa413f;
pd_rom[4441] = 32'h00aa4120;
pd_rom[4442] = 32'h00aa413f;
pd_rom[4443] = 32'h00aa413f;
pd_rom[4444] = 32'h00aa413f;
pd_rom[4445] = 32'h00aa413f;
pd_rom[4446] = 32'h00aa413f;
pd_rom[4447] = 32'h00aa413f;
pd_rom[4448] = 32'h00ae003f;
pd_rom[4449] = 32'h00af003f;
pd_rom[4450] = 32'h007ec13f;
pd_rom[4451] = 32'h007ec13f;
pd_rom[4452] = 32'h007ec13f;
pd_rom[4453] = 32'h007ec13f;
pd_rom[4454] = 32'h007ec13f;
pd_rom[4455] = 32'h007ec123;
pd_rom[4456] = 32'h00b2863f;
pd_rom[4457] = 32'h00b3863f;
pd_rom[4458] = 32'h008dc13f;
pd_rom[4459] = 32'h008dc13f;
pd_rom[4460] = 32'h008dc13f;
pd_rom[4461] = 32'h008dc13f;
pd_rom[4462] = 32'h008dc13f;
pd_rom[4463] = 32'h008dc123;
pd_rom[4464] = 32'h00b4863f;
pd_rom[4465] = 32'h00b5863f;
pd_rom[4466] = 32'h009cc13f;
pd_rom[4467] = 32'h009cc13f;
pd_rom[4468] = 32'h009cc13f;
pd_rom[4469] = 32'h009cc13f;
pd_rom[4470] = 32'h009cc13f;
pd_rom[4471] = 32'h009cc123;
pd_rom[4472] = 32'h00ab413f;
pd_rom[4473] = 32'h00ab4120;
pd_rom[4474] = 32'h00ab413f;
pd_rom[4475] = 32'h00ab413f;
pd_rom[4476] = 32'h00ab413f;
pd_rom[4477] = 32'h00ab413f;
pd_rom[4478] = 32'h00ab413f;
pd_rom[4479] = 32'h00ab413f;
pd_rom[4480] = 32'h007dc13f;
pd_rom[4481] = 32'h007dc120;
pd_rom[4482] = 32'h007dc13f;
pd_rom[4483] = 32'h007dc13f;
pd_rom[4484] = 32'h007dc13f;
pd_rom[4485] = 32'h007dc13f;
pd_rom[4486] = 32'h007dc13f;
pd_rom[4487] = 32'h007dc13f;
pd_rom[4488] = 32'h008cc13f;
pd_rom[4489] = 32'h008cc120;
pd_rom[4490] = 32'h008cc13f;
pd_rom[4491] = 32'h008cc13f;
pd_rom[4492] = 32'h008cc13f;
pd_rom[4493] = 32'h008cc13f;
pd_rom[4494] = 32'h008cc13f;
pd_rom[4495] = 32'h008cc13f;
pd_rom[4496] = 32'h009bc13f;
pd_rom[4497] = 32'h009bc120;
pd_rom[4498] = 32'h009bc13f;
pd_rom[4499] = 32'h009bc13f;
pd_rom[4500] = 32'h009bc13f;
pd_rom[4501] = 32'h009bc13f;
pd_rom[4502] = 32'h009bc13f;
pd_rom[4503] = 32'h009bc13f;
pd_rom[4504] = 32'h00aa413f;
pd_rom[4505] = 32'h00aa4120;
pd_rom[4506] = 32'h00aa413f;
pd_rom[4507] = 32'h00aa413f;
pd_rom[4508] = 32'h00aa413f;
pd_rom[4509] = 32'h00aa413f;
pd_rom[4510] = 32'h00aa413f;
pd_rom[4511] = 32'h00aa413f;
pd_rom[4512] = 32'h00ae003f;
pd_rom[4513] = 32'h00af003f;
pd_rom[4514] = 32'h007ec13f;
pd_rom[4515] = 32'h007ec13f;
pd_rom[4516] = 32'h007ec13f;
pd_rom[4517] = 32'h007ec13f;
pd_rom[4518] = 32'h007ec13f;
pd_rom[4519] = 32'h007ec123;
pd_rom[4520] = 32'h00b2863f;
pd_rom[4521] = 32'h00b3863f;
pd_rom[4522] = 32'h008dc13f;
pd_rom[4523] = 32'h008dc13f;
pd_rom[4524] = 32'h008dc13f;
pd_rom[4525] = 32'h008dc13f;
pd_rom[4526] = 32'h008dc13f;
pd_rom[4527] = 32'h008dc123;
pd_rom[4528] = 32'h00b4863f;
pd_rom[4529] = 32'h00b5863f;
pd_rom[4530] = 32'h009cc13f;
pd_rom[4531] = 32'h009cc13f;
pd_rom[4532] = 32'h009cc13f;
pd_rom[4533] = 32'h009cc13f;
pd_rom[4534] = 32'h009cc13f;
pd_rom[4535] = 32'h009cc123;
pd_rom[4536] = 32'h00ab413f;
pd_rom[4537] = 32'h00ab4120;
pd_rom[4538] = 32'h00ab413f;
pd_rom[4539] = 32'h00ab413f;
pd_rom[4540] = 32'h00ab413f;
pd_rom[4541] = 32'h00ab413f;
pd_rom[4542] = 32'h00ab413f;
pd_rom[4543] = 32'h00ab413f;
pd_rom[4544] = 32'h007dc13f;
pd_rom[4545] = 32'h007dc120;
pd_rom[4546] = 32'h007dc13f;
pd_rom[4547] = 32'h007dc13f;
pd_rom[4548] = 32'h007dc13f;
pd_rom[4549] = 32'h007dc13f;
pd_rom[4550] = 32'h007dc13f;
pd_rom[4551] = 32'h007dc13f;
pd_rom[4552] = 32'h008cc13f;
pd_rom[4553] = 32'h008cc120;
pd_rom[4554] = 32'h008cc13f;
pd_rom[4555] = 32'h008cc13f;
pd_rom[4556] = 32'h008cc13f;
pd_rom[4557] = 32'h008cc13f;
pd_rom[4558] = 32'h008cc13f;
pd_rom[4559] = 32'h008cc13f;
pd_rom[4560] = 32'h009bc13f;
pd_rom[4561] = 32'h009bc120;
pd_rom[4562] = 32'h009bc13f;
pd_rom[4563] = 32'h009bc13f;
pd_rom[4564] = 32'h009bc13f;
pd_rom[4565] = 32'h009bc13f;
pd_rom[4566] = 32'h009bc13f;
pd_rom[4567] = 32'h009bc13f;
pd_rom[4568] = 32'h00aa413f;
pd_rom[4569] = 32'h00aa4120;
pd_rom[4570] = 32'h00aa413f;
pd_rom[4571] = 32'h00aa413f;
pd_rom[4572] = 32'h00aa413f;
pd_rom[4573] = 32'h00aa413f;
pd_rom[4574] = 32'h00aa413f;
pd_rom[4575] = 32'h00aa413f;
pd_rom[4576] = 32'h00ae003f;
pd_rom[4577] = 32'h00af003f;
pd_rom[4578] = 32'h007ec13f;
pd_rom[4579] = 32'h007ec13f;
pd_rom[4580] = 32'h007ec13f;
pd_rom[4581] = 32'h007ec13f;
pd_rom[4582] = 32'h007ec13f;
pd_rom[4583] = 32'h007ec123;
pd_rom[4584] = 32'h00b2863f;
pd_rom[4585] = 32'h00b3863f;
pd_rom[4586] = 32'h008dc13f;
pd_rom[4587] = 32'h008dc13f;
pd_rom[4588] = 32'h008dc13f;
pd_rom[4589] = 32'h008dc13f;
pd_rom[4590] = 32'h008dc13f;
pd_rom[4591] = 32'h008dc123;
pd_rom[4592] = 32'h00b4863f;
pd_rom[4593] = 32'h00b5863f;
pd_rom[4594] = 32'h009cc13f;
pd_rom[4595] = 32'h009cc13f;
pd_rom[4596] = 32'h009cc13f;
pd_rom[4597] = 32'h009cc13f;
pd_rom[4598] = 32'h009cc13f;
pd_rom[4599] = 32'h009cc123;
pd_rom[4600] = 32'h00ab413f;
pd_rom[4601] = 32'h00ab4120;
pd_rom[4602] = 32'h00ab413f;
pd_rom[4603] = 32'h00ab413f;
pd_rom[4604] = 32'h00ab413f;
pd_rom[4605] = 32'h00ab413f;
pd_rom[4606] = 32'h00ab413f;
pd_rom[4607] = 32'h00ab413f;
pd_rom[4608] = 32'h0081c13f;
pd_rom[4609] = 32'h0081c120;
pd_rom[4610] = 32'h0081c13f;
pd_rom[4611] = 32'h0081c13f;
pd_rom[4612] = 32'h0081c13f;
pd_rom[4613] = 32'h0081c13f;
pd_rom[4614] = 32'h0081c13f;
pd_rom[4615] = 32'h0081c13f;
pd_rom[4616] = 32'h0090c13f;
pd_rom[4617] = 32'h0090c13f;
pd_rom[4618] = 32'h0090c13f;
pd_rom[4619] = 32'h0090c13f;
pd_rom[4620] = 32'h0090c13f;
pd_rom[4621] = 32'h0090c13f;
pd_rom[4622] = 32'h0090c13f;
pd_rom[4623] = 32'h0090c13f;
pd_rom[4624] = 32'h009fc13f;
pd_rom[4625] = 32'h009fc13f;
pd_rom[4626] = 32'h009fc13f;
pd_rom[4627] = 32'h009fc13f;
pd_rom[4628] = 32'h009fc13f;
pd_rom[4629] = 32'h009fc13f;
pd_rom[4630] = 32'h009fc13f;
pd_rom[4631] = 32'h009fc13f;
pd_rom[4632] = 32'h00b6413f;
pd_rom[4633] = 32'h00b6413f;
pd_rom[4634] = 32'h00b6413f;
pd_rom[4635] = 32'h00b6413f;
pd_rom[4636] = 32'h00b6413f;
pd_rom[4637] = 32'h00b6413f;
pd_rom[4638] = 32'h00b6413f;
pd_rom[4639] = 32'h00b6413f;
pd_rom[4640] = 32'h0088c03f;
pd_rom[4641] = 32'h0089c03f;
pd_rom[4642] = 32'h0082c13f;
pd_rom[4643] = 32'h0082c13f;
pd_rom[4644] = 32'h0082c13f;
pd_rom[4645] = 32'h0082c13f;
pd_rom[4646] = 32'h0082c13f;
pd_rom[4647] = 32'h0082c123;
pd_rom[4648] = 32'h0097c03f;
pd_rom[4649] = 32'h0098c03f;
pd_rom[4650] = 32'h0091c13f;
pd_rom[4651] = 32'h0091c13f;
pd_rom[4652] = 32'h0091c13f;
pd_rom[4653] = 32'h0091c13f;
pd_rom[4654] = 32'h0091c13f;
pd_rom[4655] = 32'h0091c123;
pd_rom[4656] = 32'h00a6c03f;
pd_rom[4657] = 32'h00a7c03f;
pd_rom[4658] = 32'h00a0c13f;
pd_rom[4659] = 32'h00a0c13f;
pd_rom[4660] = 32'h00a0c13f;
pd_rom[4661] = 32'h00a0c13f;
pd_rom[4662] = 32'h00a0c13f;
pd_rom[4663] = 32'h00a0c123;
pd_rom[4664] = 32'h00b7813f;
pd_rom[4665] = 32'h00b7813f;
pd_rom[4666] = 32'h00b7813f;
pd_rom[4667] = 32'h00b7813f;
pd_rom[4668] = 32'h00b7813f;
pd_rom[4669] = 32'h00b7813f;
pd_rom[4670] = 32'h00b7813f;
pd_rom[4671] = 32'h00b7813f;
pd_rom[4672] = 32'h0081c13f;
pd_rom[4673] = 32'h0081c120;
pd_rom[4674] = 32'h0081c13f;
pd_rom[4675] = 32'h0081c13f;
pd_rom[4676] = 32'h0081c13f;
pd_rom[4677] = 32'h0081c13f;
pd_rom[4678] = 32'h0081c13f;
pd_rom[4679] = 32'h0081c13f;
pd_rom[4680] = 32'h0090c13f;
pd_rom[4681] = 32'h0090c13f;
pd_rom[4682] = 32'h0090c13f;
pd_rom[4683] = 32'h0090c13f;
pd_rom[4684] = 32'h0090c13f;
pd_rom[4685] = 32'h0090c13f;
pd_rom[4686] = 32'h0090c13f;
pd_rom[4687] = 32'h0090c13f;
pd_rom[4688] = 32'h009fc13f;
pd_rom[4689] = 32'h009fc13f;
pd_rom[4690] = 32'h009fc13f;
pd_rom[4691] = 32'h009fc13f;
pd_rom[4692] = 32'h009fc13f;
pd_rom[4693] = 32'h009fc13f;
pd_rom[4694] = 32'h009fc13f;
pd_rom[4695] = 32'h009fc13f;
pd_rom[4696] = 32'h00b6413f;
pd_rom[4697] = 32'h00b6413f;
pd_rom[4698] = 32'h00b6413f;
pd_rom[4699] = 32'h00b6413f;
pd_rom[4700] = 32'h00b6413f;
pd_rom[4701] = 32'h00b6413f;
pd_rom[4702] = 32'h00b6413f;
pd_rom[4703] = 32'h00b6413f;
pd_rom[4704] = 32'h0088c03f;
pd_rom[4705] = 32'h0089c03f;
pd_rom[4706] = 32'h0082c13f;
pd_rom[4707] = 32'h0082c13f;
pd_rom[4708] = 32'h0082c13f;
pd_rom[4709] = 32'h0082c13f;
pd_rom[4710] = 32'h0082c13f;
pd_rom[4711] = 32'h0082c123;
pd_rom[4712] = 32'h0097c03f;
pd_rom[4713] = 32'h0098c03f;
pd_rom[4714] = 32'h0091c13f;
pd_rom[4715] = 32'h0091c13f;
pd_rom[4716] = 32'h0091c13f;
pd_rom[4717] = 32'h0091c13f;
pd_rom[4718] = 32'h0091c13f;
pd_rom[4719] = 32'h0091c123;
pd_rom[4720] = 32'h00a6c03f;
pd_rom[4721] = 32'h00a7c03f;
pd_rom[4722] = 32'h00a0c13f;
pd_rom[4723] = 32'h00a0c13f;
pd_rom[4724] = 32'h00a0c13f;
pd_rom[4725] = 32'h00a0c13f;
pd_rom[4726] = 32'h00a0c13f;
pd_rom[4727] = 32'h00a0c123;
pd_rom[4728] = 32'h00b7813f;
pd_rom[4729] = 32'h00b7813f;
pd_rom[4730] = 32'h00b7813f;
pd_rom[4731] = 32'h00b7813f;
pd_rom[4732] = 32'h00b7813f;
pd_rom[4733] = 32'h00b7813f;
pd_rom[4734] = 32'h00b7813f;
pd_rom[4735] = 32'h00b7813f;
pd_rom[4736] = 32'h0081c13f;
pd_rom[4737] = 32'h0081c120;
pd_rom[4738] = 32'h0081c13f;
pd_rom[4739] = 32'h0081c13f;
pd_rom[4740] = 32'h0081c13f;
pd_rom[4741] = 32'h0081c13f;
pd_rom[4742] = 32'h0081c13f;
pd_rom[4743] = 32'h0081c13f;
pd_rom[4744] = 32'h0090c13f;
pd_rom[4745] = 32'h0090c13f;
pd_rom[4746] = 32'h0090c13f;
pd_rom[4747] = 32'h0090c13f;
pd_rom[4748] = 32'h0090c13f;
pd_rom[4749] = 32'h0090c13f;
pd_rom[4750] = 32'h0090c13f;
pd_rom[4751] = 32'h0090c13f;
pd_rom[4752] = 32'h009fc13f;
pd_rom[4753] = 32'h009fc13f;
pd_rom[4754] = 32'h009fc13f;
pd_rom[4755] = 32'h009fc13f;
pd_rom[4756] = 32'h009fc13f;
pd_rom[4757] = 32'h009fc13f;
pd_rom[4758] = 32'h009fc13f;
pd_rom[4759] = 32'h009fc13f;
pd_rom[4760] = 32'h00b6413f;
pd_rom[4761] = 32'h00b6413f;
pd_rom[4762] = 32'h00b6413f;
pd_rom[4763] = 32'h00b6413f;
pd_rom[4764] = 32'h00b6413f;
pd_rom[4765] = 32'h00b6413f;
pd_rom[4766] = 32'h00b6413f;
pd_rom[4767] = 32'h00b6413f;
pd_rom[4768] = 32'h0088c03f;
pd_rom[4769] = 32'h0089c03f;
pd_rom[4770] = 32'h0082c13f;
pd_rom[4771] = 32'h0082c13f;
pd_rom[4772] = 32'h0082c13f;
pd_rom[4773] = 32'h0082c13f;
pd_rom[4774] = 32'h0082c13f;
pd_rom[4775] = 32'h0082c123;
pd_rom[4776] = 32'h0097c03f;
pd_rom[4777] = 32'h0098c03f;
pd_rom[4778] = 32'h0091c13f;
pd_rom[4779] = 32'h0091c13f;
pd_rom[4780] = 32'h0091c13f;
pd_rom[4781] = 32'h0091c13f;
pd_rom[4782] = 32'h0091c13f;
pd_rom[4783] = 32'h0091c123;
pd_rom[4784] = 32'h00a6c03f;
pd_rom[4785] = 32'h00a7c03f;
pd_rom[4786] = 32'h00a0c13f;
pd_rom[4787] = 32'h00a0c13f;
pd_rom[4788] = 32'h00a0c13f;
pd_rom[4789] = 32'h00a0c13f;
pd_rom[4790] = 32'h00a0c13f;
pd_rom[4791] = 32'h00a0c123;
pd_rom[4792] = 32'h00b7813f;
pd_rom[4793] = 32'h00b7813f;
pd_rom[4794] = 32'h00b7813f;
pd_rom[4795] = 32'h00b7813f;
pd_rom[4796] = 32'h00b7813f;
pd_rom[4797] = 32'h00b7813f;
pd_rom[4798] = 32'h00b7813f;
pd_rom[4799] = 32'h00b7813f;
pd_rom[4800] = 32'h0081c13f;
pd_rom[4801] = 32'h0081c120;
pd_rom[4802] = 32'h0081c13f;
pd_rom[4803] = 32'h0081c13f;
pd_rom[4804] = 32'h0081c13f;
pd_rom[4805] = 32'h0081c13f;
pd_rom[4806] = 32'h0081c13f;
pd_rom[4807] = 32'h0081c13f;
pd_rom[4808] = 32'h0090c13f;
pd_rom[4809] = 32'h0090c13f;
pd_rom[4810] = 32'h0090c13f;
pd_rom[4811] = 32'h0090c13f;
pd_rom[4812] = 32'h0090c13f;
pd_rom[4813] = 32'h0090c13f;
pd_rom[4814] = 32'h0090c13f;
pd_rom[4815] = 32'h0090c13f;
pd_rom[4816] = 32'h009fc13f;
pd_rom[4817] = 32'h009fc13f;
pd_rom[4818] = 32'h009fc13f;
pd_rom[4819] = 32'h009fc13f;
pd_rom[4820] = 32'h009fc13f;
pd_rom[4821] = 32'h009fc13f;
pd_rom[4822] = 32'h009fc13f;
pd_rom[4823] = 32'h009fc13f;
pd_rom[4824] = 32'h00b6413f;
pd_rom[4825] = 32'h00b6413f;
pd_rom[4826] = 32'h00b6413f;
pd_rom[4827] = 32'h00b6413f;
pd_rom[4828] = 32'h00b6413f;
pd_rom[4829] = 32'h00b6413f;
pd_rom[4830] = 32'h00b6413f;
pd_rom[4831] = 32'h00b6413f;
pd_rom[4832] = 32'h0088c03f;
pd_rom[4833] = 32'h0089c03f;
pd_rom[4834] = 32'h0082c13f;
pd_rom[4835] = 32'h0082c13f;
pd_rom[4836] = 32'h0082c13f;
pd_rom[4837] = 32'h0082c13f;
pd_rom[4838] = 32'h0082c13f;
pd_rom[4839] = 32'h0082c123;
pd_rom[4840] = 32'h0097c03f;
pd_rom[4841] = 32'h0098c03f;
pd_rom[4842] = 32'h0091c13f;
pd_rom[4843] = 32'h0091c13f;
pd_rom[4844] = 32'h0091c13f;
pd_rom[4845] = 32'h0091c13f;
pd_rom[4846] = 32'h0091c13f;
pd_rom[4847] = 32'h0091c123;
pd_rom[4848] = 32'h00a6c03f;
pd_rom[4849] = 32'h00a7c03f;
pd_rom[4850] = 32'h00a0c13f;
pd_rom[4851] = 32'h00a0c13f;
pd_rom[4852] = 32'h00a0c13f;
pd_rom[4853] = 32'h00a0c13f;
pd_rom[4854] = 32'h00a0c13f;
pd_rom[4855] = 32'h00a0c123;
pd_rom[4856] = 32'h00b7813f;
pd_rom[4857] = 32'h00b7813f;
pd_rom[4858] = 32'h00b7813f;
pd_rom[4859] = 32'h00b7813f;
pd_rom[4860] = 32'h00b7813f;
pd_rom[4861] = 32'h00b7813f;
pd_rom[4862] = 32'h00b7813f;
pd_rom[4863] = 32'h00b7813f;
pd_rom[4864] = 32'h0081c13f;
pd_rom[4865] = 32'h0081c120;
pd_rom[4866] = 32'h0081c13f;
pd_rom[4867] = 32'h0081c13f;
pd_rom[4868] = 32'h0081c13f;
pd_rom[4869] = 32'h0081c13f;
pd_rom[4870] = 32'h0081c13f;
pd_rom[4871] = 32'h0081c13f;
pd_rom[4872] = 32'h0090c13f;
pd_rom[4873] = 32'h0090c13f;
pd_rom[4874] = 32'h0090c13f;
pd_rom[4875] = 32'h0090c13f;
pd_rom[4876] = 32'h0090c13f;
pd_rom[4877] = 32'h0090c13f;
pd_rom[4878] = 32'h0090c13f;
pd_rom[4879] = 32'h0090c13f;
pd_rom[4880] = 32'h009fc13f;
pd_rom[4881] = 32'h009fc13f;
pd_rom[4882] = 32'h009fc13f;
pd_rom[4883] = 32'h009fc13f;
pd_rom[4884] = 32'h009fc13f;
pd_rom[4885] = 32'h009fc13f;
pd_rom[4886] = 32'h009fc13f;
pd_rom[4887] = 32'h009fc13f;
pd_rom[4888] = 32'h00b6413f;
pd_rom[4889] = 32'h00b6413f;
pd_rom[4890] = 32'h00b6413f;
pd_rom[4891] = 32'h00b6413f;
pd_rom[4892] = 32'h00b6413f;
pd_rom[4893] = 32'h00b6413f;
pd_rom[4894] = 32'h00b6413f;
pd_rom[4895] = 32'h00b6413f;
pd_rom[4896] = 32'h0088c03f;
pd_rom[4897] = 32'h0089c03f;
pd_rom[4898] = 32'h0082c13f;
pd_rom[4899] = 32'h0082c13f;
pd_rom[4900] = 32'h0082c13f;
pd_rom[4901] = 32'h0082c13f;
pd_rom[4902] = 32'h0082c13f;
pd_rom[4903] = 32'h0082c123;
pd_rom[4904] = 32'h0097c03f;
pd_rom[4905] = 32'h0098c03f;
pd_rom[4906] = 32'h0091c13f;
pd_rom[4907] = 32'h0091c13f;
pd_rom[4908] = 32'h0091c13f;
pd_rom[4909] = 32'h0091c13f;
pd_rom[4910] = 32'h0091c13f;
pd_rom[4911] = 32'h0091c123;
pd_rom[4912] = 32'h00a6c03f;
pd_rom[4913] = 32'h00a7c03f;
pd_rom[4914] = 32'h00a0c13f;
pd_rom[4915] = 32'h00a0c13f;
pd_rom[4916] = 32'h00a0c13f;
pd_rom[4917] = 32'h00a0c13f;
pd_rom[4918] = 32'h00a0c13f;
pd_rom[4919] = 32'h00a0c123;
pd_rom[4920] = 32'h00b7813f;
pd_rom[4921] = 32'h00b7813f;
pd_rom[4922] = 32'h00b7813f;
pd_rom[4923] = 32'h00b7813f;
pd_rom[4924] = 32'h00b7813f;
pd_rom[4925] = 32'h00b7813f;
pd_rom[4926] = 32'h00b7813f;
pd_rom[4927] = 32'h00b7813f;
pd_rom[4928] = 32'h0081c13f;
pd_rom[4929] = 32'h0081c120;
pd_rom[4930] = 32'h0081c13f;
pd_rom[4931] = 32'h0081c13f;
pd_rom[4932] = 32'h0081c13f;
pd_rom[4933] = 32'h0081c13f;
pd_rom[4934] = 32'h0081c13f;
pd_rom[4935] = 32'h0081c13f;
pd_rom[4936] = 32'h0090c13f;
pd_rom[4937] = 32'h0090c13f;
pd_rom[4938] = 32'h0090c13f;
pd_rom[4939] = 32'h0090c13f;
pd_rom[4940] = 32'h0090c13f;
pd_rom[4941] = 32'h0090c13f;
pd_rom[4942] = 32'h0090c13f;
pd_rom[4943] = 32'h0090c13f;
pd_rom[4944] = 32'h009fc13f;
pd_rom[4945] = 32'h009fc13f;
pd_rom[4946] = 32'h009fc13f;
pd_rom[4947] = 32'h009fc13f;
pd_rom[4948] = 32'h009fc13f;
pd_rom[4949] = 32'h009fc13f;
pd_rom[4950] = 32'h009fc13f;
pd_rom[4951] = 32'h009fc13f;
pd_rom[4952] = 32'h00b6413f;
pd_rom[4953] = 32'h00b6413f;
pd_rom[4954] = 32'h00b6413f;
pd_rom[4955] = 32'h00b6413f;
pd_rom[4956] = 32'h00b6413f;
pd_rom[4957] = 32'h00b6413f;
pd_rom[4958] = 32'h00b6413f;
pd_rom[4959] = 32'h00b6413f;
pd_rom[4960] = 32'h0088c03f;
pd_rom[4961] = 32'h0089c03f;
pd_rom[4962] = 32'h0082c13f;
pd_rom[4963] = 32'h0082c13f;
pd_rom[4964] = 32'h0082c13f;
pd_rom[4965] = 32'h0082c13f;
pd_rom[4966] = 32'h0082c13f;
pd_rom[4967] = 32'h0082c123;
pd_rom[4968] = 32'h0097c03f;
pd_rom[4969] = 32'h0098c03f;
pd_rom[4970] = 32'h0091c13f;
pd_rom[4971] = 32'h0091c13f;
pd_rom[4972] = 32'h0091c13f;
pd_rom[4973] = 32'h0091c13f;
pd_rom[4974] = 32'h0091c13f;
pd_rom[4975] = 32'h0091c123;
pd_rom[4976] = 32'h00a6c03f;
pd_rom[4977] = 32'h00a7c03f;
pd_rom[4978] = 32'h00a0c13f;
pd_rom[4979] = 32'h00a0c13f;
pd_rom[4980] = 32'h00a0c13f;
pd_rom[4981] = 32'h00a0c13f;
pd_rom[4982] = 32'h00a0c13f;
pd_rom[4983] = 32'h00a0c123;
pd_rom[4984] = 32'h00b7813f;
pd_rom[4985] = 32'h00b7813f;
pd_rom[4986] = 32'h00b7813f;
pd_rom[4987] = 32'h00b7813f;
pd_rom[4988] = 32'h00b7813f;
pd_rom[4989] = 32'h00b7813f;
pd_rom[4990] = 32'h00b7813f;
pd_rom[4991] = 32'h00b7813f;
pd_rom[4992] = 32'h0081c13f;
pd_rom[4993] = 32'h0081c120;
pd_rom[4994] = 32'h0081c13f;
pd_rom[4995] = 32'h0081c13f;
pd_rom[4996] = 32'h0081c13f;
pd_rom[4997] = 32'h0081c13f;
pd_rom[4998] = 32'h0081c13f;
pd_rom[4999] = 32'h0081c13f;
pd_rom[5000] = 32'h0090c13f;
pd_rom[5001] = 32'h0090c13f;
pd_rom[5002] = 32'h0090c13f;
pd_rom[5003] = 32'h0090c13f;
pd_rom[5004] = 32'h0090c13f;
pd_rom[5005] = 32'h0090c13f;
pd_rom[5006] = 32'h0090c13f;
pd_rom[5007] = 32'h0090c13f;
pd_rom[5008] = 32'h009fc13f;
pd_rom[5009] = 32'h009fc13f;
pd_rom[5010] = 32'h009fc13f;
pd_rom[5011] = 32'h009fc13f;
pd_rom[5012] = 32'h009fc13f;
pd_rom[5013] = 32'h009fc13f;
pd_rom[5014] = 32'h009fc13f;
pd_rom[5015] = 32'h009fc13f;
pd_rom[5016] = 32'h00b6413f;
pd_rom[5017] = 32'h00b6413f;
pd_rom[5018] = 32'h00b6413f;
pd_rom[5019] = 32'h00b6413f;
pd_rom[5020] = 32'h00b6413f;
pd_rom[5021] = 32'h00b6413f;
pd_rom[5022] = 32'h00b6413f;
pd_rom[5023] = 32'h00b6413f;
pd_rom[5024] = 32'h0088c03f;
pd_rom[5025] = 32'h0089c03f;
pd_rom[5026] = 32'h0082c13f;
pd_rom[5027] = 32'h0082c13f;
pd_rom[5028] = 32'h0082c13f;
pd_rom[5029] = 32'h0082c13f;
pd_rom[5030] = 32'h0082c13f;
pd_rom[5031] = 32'h0082c123;
pd_rom[5032] = 32'h0097c03f;
pd_rom[5033] = 32'h0098c03f;
pd_rom[5034] = 32'h0091c13f;
pd_rom[5035] = 32'h0091c13f;
pd_rom[5036] = 32'h0091c13f;
pd_rom[5037] = 32'h0091c13f;
pd_rom[5038] = 32'h0091c13f;
pd_rom[5039] = 32'h0091c123;
pd_rom[5040] = 32'h00a6c03f;
pd_rom[5041] = 32'h00a7c03f;
pd_rom[5042] = 32'h00a0c13f;
pd_rom[5043] = 32'h00a0c13f;
pd_rom[5044] = 32'h00a0c13f;
pd_rom[5045] = 32'h00a0c13f;
pd_rom[5046] = 32'h00a0c13f;
pd_rom[5047] = 32'h00a0c123;
pd_rom[5048] = 32'h00b7813f;
pd_rom[5049] = 32'h00b7813f;
pd_rom[5050] = 32'h00b7813f;
pd_rom[5051] = 32'h00b7813f;
pd_rom[5052] = 32'h00b7813f;
pd_rom[5053] = 32'h00b7813f;
pd_rom[5054] = 32'h00b7813f;
pd_rom[5055] = 32'h00b7813f;
pd_rom[5056] = 32'h0081c13f;
pd_rom[5057] = 32'h0081c120;
pd_rom[5058] = 32'h0081c13f;
pd_rom[5059] = 32'h0081c13f;
pd_rom[5060] = 32'h0081c13f;
pd_rom[5061] = 32'h0081c13f;
pd_rom[5062] = 32'h0081c13f;
pd_rom[5063] = 32'h0081c13f;
pd_rom[5064] = 32'h0090c13f;
pd_rom[5065] = 32'h0090c13f;
pd_rom[5066] = 32'h0090c13f;
pd_rom[5067] = 32'h0090c13f;
pd_rom[5068] = 32'h0090c13f;
pd_rom[5069] = 32'h0090c13f;
pd_rom[5070] = 32'h0090c13f;
pd_rom[5071] = 32'h0090c13f;
pd_rom[5072] = 32'h009fc13f;
pd_rom[5073] = 32'h009fc13f;
pd_rom[5074] = 32'h009fc13f;
pd_rom[5075] = 32'h009fc13f;
pd_rom[5076] = 32'h009fc13f;
pd_rom[5077] = 32'h009fc13f;
pd_rom[5078] = 32'h009fc13f;
pd_rom[5079] = 32'h009fc13f;
pd_rom[5080] = 32'h00b6413f;
pd_rom[5081] = 32'h00b6413f;
pd_rom[5082] = 32'h00b6413f;
pd_rom[5083] = 32'h00b6413f;
pd_rom[5084] = 32'h00b6413f;
pd_rom[5085] = 32'h00b6413f;
pd_rom[5086] = 32'h00b6413f;
pd_rom[5087] = 32'h00b6413f;
pd_rom[5088] = 32'h0088c03f;
pd_rom[5089] = 32'h0089c03f;
pd_rom[5090] = 32'h0082c13f;
pd_rom[5091] = 32'h0082c13f;
pd_rom[5092] = 32'h0082c13f;
pd_rom[5093] = 32'h0082c13f;
pd_rom[5094] = 32'h0082c13f;
pd_rom[5095] = 32'h0082c123;
pd_rom[5096] = 32'h0097c03f;
pd_rom[5097] = 32'h0098c03f;
pd_rom[5098] = 32'h0091c13f;
pd_rom[5099] = 32'h0091c13f;
pd_rom[5100] = 32'h0091c13f;
pd_rom[5101] = 32'h0091c13f;
pd_rom[5102] = 32'h0091c13f;
pd_rom[5103] = 32'h0091c123;
pd_rom[5104] = 32'h00a6c03f;
pd_rom[5105] = 32'h00a7c03f;
pd_rom[5106] = 32'h00a0c13f;
pd_rom[5107] = 32'h00a0c13f;
pd_rom[5108] = 32'h00a0c13f;
pd_rom[5109] = 32'h00a0c13f;
pd_rom[5110] = 32'h00a0c13f;
pd_rom[5111] = 32'h00a0c123;
pd_rom[5112] = 32'h00b7813f;
pd_rom[5113] = 32'h00b7813f;
pd_rom[5114] = 32'h00b7813f;
pd_rom[5115] = 32'h00b7813f;
pd_rom[5116] = 32'h00b7813f;
pd_rom[5117] = 32'h00b7813f;
pd_rom[5118] = 32'h00b7813f;
pd_rom[5119] = 32'h00b7813f;
pd_rom[5632] = 32'h0085c13f;
pd_rom[5633] = 32'h0085c120;
pd_rom[5634] = 32'h0085c13f;
pd_rom[5635] = 32'h0085c13f;
pd_rom[5636] = 32'h0085c13f;
pd_rom[5637] = 32'h0085c13f;
pd_rom[5638] = 32'h0085c13f;
pd_rom[5639] = 32'h0085c13f;
pd_rom[5640] = 32'h0094c13f;
pd_rom[5641] = 32'h0094c13f;
pd_rom[5642] = 32'h0094c13f;
pd_rom[5643] = 32'h0094c13f;
pd_rom[5644] = 32'h0094c13f;
pd_rom[5645] = 32'h0094c13f;
pd_rom[5646] = 32'h0094c13f;
pd_rom[5647] = 32'h0094c13f;
pd_rom[5648] = 32'h00a3c13f;
pd_rom[5649] = 32'h00a3c13f;
pd_rom[5650] = 32'h00a3c13f;
pd_rom[5651] = 32'h00a3c13f;
pd_rom[5652] = 32'h00a3c13f;
pd_rom[5653] = 32'h00a3c13f;
pd_rom[5654] = 32'h00a3c13f;
pd_rom[5655] = 32'h00a3c13f;
pd_rom[5656] = 32'h00ba413f;
pd_rom[5657] = 32'h00ba413f;
pd_rom[5658] = 32'h00ba413f;
pd_rom[5659] = 32'h00ba413f;
pd_rom[5660] = 32'h00ba413f;
pd_rom[5661] = 32'h00ba413f;
pd_rom[5662] = 32'h00ba413f;
pd_rom[5663] = 32'h00ba413f;
pd_rom[5664] = 32'h0086c13f;
pd_rom[5665] = 32'h0087c03f;
pd_rom[5666] = 32'h0086c13f;
pd_rom[5667] = 32'h0086c13f;
pd_rom[5668] = 32'h0086c13f;
pd_rom[5669] = 32'h0086c13f;
pd_rom[5670] = 32'h0086c13f;
pd_rom[5671] = 32'h0086c123;
pd_rom[5672] = 32'h0095c13f;
pd_rom[5673] = 32'h0096c03f;
pd_rom[5674] = 32'h0095c13f;
pd_rom[5675] = 32'h0095c13f;
pd_rom[5676] = 32'h0095c13f;
pd_rom[5677] = 32'h0095c13f;
pd_rom[5678] = 32'h0095c13f;
pd_rom[5679] = 32'h0095c123;
pd_rom[5680] = 32'h00a4c13f;
pd_rom[5681] = 32'h00a5c03f;
pd_rom[5682] = 32'h00a4c13f;
pd_rom[5683] = 32'h00a4c13f;
pd_rom[5684] = 32'h00a4c13f;
pd_rom[5685] = 32'h00a4c13f;
pd_rom[5686] = 32'h00a4c13f;
pd_rom[5687] = 32'h00a4c123;
pd_rom[5688] = 32'h00bb813f;
pd_rom[5689] = 32'h00bb813f;
pd_rom[5690] = 32'h00bb813f;
pd_rom[5691] = 32'h00bb813f;
pd_rom[5692] = 32'h00bb813f;
pd_rom[5693] = 32'h00bb813f;
pd_rom[5694] = 32'h00bb813f;
pd_rom[5695] = 32'h00bb813f;
pd_rom[5696] = 32'h0085c13f;
pd_rom[5697] = 32'h0085c120;
pd_rom[5698] = 32'h0085c13f;
pd_rom[5699] = 32'h0085c13f;
pd_rom[5700] = 32'h0085c13f;
pd_rom[5701] = 32'h0085c13f;
pd_rom[5702] = 32'h0085c13f;
pd_rom[5703] = 32'h0085c13f;
pd_rom[5704] = 32'h0094c13f;
pd_rom[5705] = 32'h0094c13f;
pd_rom[5706] = 32'h0094c13f;
pd_rom[5707] = 32'h0094c13f;
pd_rom[5708] = 32'h0094c13f;
pd_rom[5709] = 32'h0094c13f;
pd_rom[5710] = 32'h0094c13f;
pd_rom[5711] = 32'h0094c13f;
pd_rom[5712] = 32'h00a3c13f;
pd_rom[5713] = 32'h00a3c13f;
pd_rom[5714] = 32'h00a3c13f;
pd_rom[5715] = 32'h00a3c13f;
pd_rom[5716] = 32'h00a3c13f;
pd_rom[5717] = 32'h00a3c13f;
pd_rom[5718] = 32'h00a3c13f;
pd_rom[5719] = 32'h00a3c13f;
pd_rom[5720] = 32'h00ba413f;
pd_rom[5721] = 32'h00ba413f;
pd_rom[5722] = 32'h00ba413f;
pd_rom[5723] = 32'h00ba413f;
pd_rom[5724] = 32'h00ba413f;
pd_rom[5725] = 32'h00ba413f;
pd_rom[5726] = 32'h00ba413f;
pd_rom[5727] = 32'h00ba413f;
pd_rom[5728] = 32'h0086c13f;
pd_rom[5729] = 32'h0087c03f;
pd_rom[5730] = 32'h0086c13f;
pd_rom[5731] = 32'h0086c13f;
pd_rom[5732] = 32'h0086c13f;
pd_rom[5733] = 32'h0086c13f;
pd_rom[5734] = 32'h0086c13f;
pd_rom[5735] = 32'h0086c123;
pd_rom[5736] = 32'h0095c13f;
pd_rom[5737] = 32'h0096c03f;
pd_rom[5738] = 32'h0095c13f;
pd_rom[5739] = 32'h0095c13f;
pd_rom[5740] = 32'h0095c13f;
pd_rom[5741] = 32'h0095c13f;
pd_rom[5742] = 32'h0095c13f;
pd_rom[5743] = 32'h0095c123;
pd_rom[5744] = 32'h00a4c13f;
pd_rom[5745] = 32'h00a5c03f;
pd_rom[5746] = 32'h00a4c13f;
pd_rom[5747] = 32'h00a4c13f;
pd_rom[5748] = 32'h00a4c13f;
pd_rom[5749] = 32'h00a4c13f;
pd_rom[5750] = 32'h00a4c13f;
pd_rom[5751] = 32'h00a4c123;
pd_rom[5752] = 32'h00bb813f;
pd_rom[5753] = 32'h00bb813f;
pd_rom[5754] = 32'h00bb813f;
pd_rom[5755] = 32'h00bb813f;
pd_rom[5756] = 32'h00bb813f;
pd_rom[5757] = 32'h00bb813f;
pd_rom[5758] = 32'h00bb813f;
pd_rom[5759] = 32'h00bb813f;
pd_rom[5760] = 32'h0085c13f;
pd_rom[5761] = 32'h0085c120;
pd_rom[5762] = 32'h0085c13f;
pd_rom[5763] = 32'h0085c13f;
pd_rom[5764] = 32'h0085c13f;
pd_rom[5765] = 32'h0085c13f;
pd_rom[5766] = 32'h0085c13f;
pd_rom[5767] = 32'h0085c13f;
pd_rom[5768] = 32'h0094c13f;
pd_rom[5769] = 32'h0094c13f;
pd_rom[5770] = 32'h0094c13f;
pd_rom[5771] = 32'h0094c13f;
pd_rom[5772] = 32'h0094c13f;
pd_rom[5773] = 32'h0094c13f;
pd_rom[5774] = 32'h0094c13f;
pd_rom[5775] = 32'h0094c13f;
pd_rom[5776] = 32'h00a3c13f;
pd_rom[5777] = 32'h00a3c13f;
pd_rom[5778] = 32'h00a3c13f;
pd_rom[5779] = 32'h00a3c13f;
pd_rom[5780] = 32'h00a3c13f;
pd_rom[5781] = 32'h00a3c13f;
pd_rom[5782] = 32'h00a3c13f;
pd_rom[5783] = 32'h00a3c13f;
pd_rom[5784] = 32'h00ba413f;
pd_rom[5785] = 32'h00ba413f;
pd_rom[5786] = 32'h00ba413f;
pd_rom[5787] = 32'h00ba413f;
pd_rom[5788] = 32'h00ba413f;
pd_rom[5789] = 32'h00ba413f;
pd_rom[5790] = 32'h00ba413f;
pd_rom[5791] = 32'h00ba413f;
pd_rom[5792] = 32'h0086c13f;
pd_rom[5793] = 32'h0087c03f;
pd_rom[5794] = 32'h0086c13f;
pd_rom[5795] = 32'h0086c13f;
pd_rom[5796] = 32'h0086c13f;
pd_rom[5797] = 32'h0086c13f;
pd_rom[5798] = 32'h0086c13f;
pd_rom[5799] = 32'h0086c123;
pd_rom[5800] = 32'h0095c13f;
pd_rom[5801] = 32'h0096c03f;
pd_rom[5802] = 32'h0095c13f;
pd_rom[5803] = 32'h0095c13f;
pd_rom[5804] = 32'h0095c13f;
pd_rom[5805] = 32'h0095c13f;
pd_rom[5806] = 32'h0095c13f;
pd_rom[5807] = 32'h0095c123;
pd_rom[5808] = 32'h00a4c13f;
pd_rom[5809] = 32'h00a5c03f;
pd_rom[5810] = 32'h00a4c13f;
pd_rom[5811] = 32'h00a4c13f;
pd_rom[5812] = 32'h00a4c13f;
pd_rom[5813] = 32'h00a4c13f;
pd_rom[5814] = 32'h00a4c13f;
pd_rom[5815] = 32'h00a4c123;
pd_rom[5816] = 32'h00bb813f;
pd_rom[5817] = 32'h00bb813f;
pd_rom[5818] = 32'h00bb813f;
pd_rom[5819] = 32'h00bb813f;
pd_rom[5820] = 32'h00bb813f;
pd_rom[5821] = 32'h00bb813f;
pd_rom[5822] = 32'h00bb813f;
pd_rom[5823] = 32'h00bb813f;
pd_rom[5824] = 32'h0085c13f;
pd_rom[5825] = 32'h0085c120;
pd_rom[5826] = 32'h0085c13f;
pd_rom[5827] = 32'h0085c13f;
pd_rom[5828] = 32'h0085c13f;
pd_rom[5829] = 32'h0085c13f;
pd_rom[5830] = 32'h0085c13f;
pd_rom[5831] = 32'h0085c13f;
pd_rom[5832] = 32'h0094c13f;
pd_rom[5833] = 32'h0094c13f;
pd_rom[5834] = 32'h0094c13f;
pd_rom[5835] = 32'h0094c13f;
pd_rom[5836] = 32'h0094c13f;
pd_rom[5837] = 32'h0094c13f;
pd_rom[5838] = 32'h0094c13f;
pd_rom[5839] = 32'h0094c13f;
pd_rom[5840] = 32'h00a3c13f;
pd_rom[5841] = 32'h00a3c13f;
pd_rom[5842] = 32'h00a3c13f;
pd_rom[5843] = 32'h00a3c13f;
pd_rom[5844] = 32'h00a3c13f;
pd_rom[5845] = 32'h00a3c13f;
pd_rom[5846] = 32'h00a3c13f;
pd_rom[5847] = 32'h00a3c13f;
pd_rom[5848] = 32'h00ba413f;
pd_rom[5849] = 32'h00ba413f;
pd_rom[5850] = 32'h00ba413f;
pd_rom[5851] = 32'h00ba413f;
pd_rom[5852] = 32'h00ba413f;
pd_rom[5853] = 32'h00ba413f;
pd_rom[5854] = 32'h00ba413f;
pd_rom[5855] = 32'h00ba413f;
pd_rom[5856] = 32'h0086c13f;
pd_rom[5857] = 32'h0087c03f;
pd_rom[5858] = 32'h0086c13f;
pd_rom[5859] = 32'h0086c13f;
pd_rom[5860] = 32'h0086c13f;
pd_rom[5861] = 32'h0086c13f;
pd_rom[5862] = 32'h0086c13f;
pd_rom[5863] = 32'h0086c123;
pd_rom[5864] = 32'h0095c13f;
pd_rom[5865] = 32'h0096c03f;
pd_rom[5866] = 32'h0095c13f;
pd_rom[5867] = 32'h0095c13f;
pd_rom[5868] = 32'h0095c13f;
pd_rom[5869] = 32'h0095c13f;
pd_rom[5870] = 32'h0095c13f;
pd_rom[5871] = 32'h0095c123;
pd_rom[5872] = 32'h00a4c13f;
pd_rom[5873] = 32'h00a5c03f;
pd_rom[5874] = 32'h00a4c13f;
pd_rom[5875] = 32'h00a4c13f;
pd_rom[5876] = 32'h00a4c13f;
pd_rom[5877] = 32'h00a4c13f;
pd_rom[5878] = 32'h00a4c13f;
pd_rom[5879] = 32'h00a4c123;
pd_rom[5880] = 32'h00bb813f;
pd_rom[5881] = 32'h00bb813f;
pd_rom[5882] = 32'h00bb813f;
pd_rom[5883] = 32'h00bb813f;
pd_rom[5884] = 32'h00bb813f;
pd_rom[5885] = 32'h00bb813f;
pd_rom[5886] = 32'h00bb813f;
pd_rom[5887] = 32'h00bb813f;
pd_rom[5888] = 32'h0085c13f;
pd_rom[5889] = 32'h0085c120;
pd_rom[5890] = 32'h0085c13f;
pd_rom[5891] = 32'h0085c13f;
pd_rom[5892] = 32'h0085c13f;
pd_rom[5893] = 32'h0085c13f;
pd_rom[5894] = 32'h0085c13f;
pd_rom[5895] = 32'h0085c13f;
pd_rom[5896] = 32'h0094c13f;
pd_rom[5897] = 32'h0094c13f;
pd_rom[5898] = 32'h0094c13f;
pd_rom[5899] = 32'h0094c13f;
pd_rom[5900] = 32'h0094c13f;
pd_rom[5901] = 32'h0094c13f;
pd_rom[5902] = 32'h0094c13f;
pd_rom[5903] = 32'h0094c13f;
pd_rom[5904] = 32'h00a3c13f;
pd_rom[5905] = 32'h00a3c13f;
pd_rom[5906] = 32'h00a3c13f;
pd_rom[5907] = 32'h00a3c13f;
pd_rom[5908] = 32'h00a3c13f;
pd_rom[5909] = 32'h00a3c13f;
pd_rom[5910] = 32'h00a3c13f;
pd_rom[5911] = 32'h00a3c13f;
pd_rom[5912] = 32'h00ba413f;
pd_rom[5913] = 32'h00ba413f;
pd_rom[5914] = 32'h00ba413f;
pd_rom[5915] = 32'h00ba413f;
pd_rom[5916] = 32'h00ba413f;
pd_rom[5917] = 32'h00ba413f;
pd_rom[5918] = 32'h00ba413f;
pd_rom[5919] = 32'h00ba413f;
pd_rom[5920] = 32'h0086c13f;
pd_rom[5921] = 32'h0087c03f;
pd_rom[5922] = 32'h0086c13f;
pd_rom[5923] = 32'h0086c13f;
pd_rom[5924] = 32'h0086c13f;
pd_rom[5925] = 32'h0086c13f;
pd_rom[5926] = 32'h0086c13f;
pd_rom[5927] = 32'h0086c123;
pd_rom[5928] = 32'h0095c13f;
pd_rom[5929] = 32'h0096c03f;
pd_rom[5930] = 32'h0095c13f;
pd_rom[5931] = 32'h0095c13f;
pd_rom[5932] = 32'h0095c13f;
pd_rom[5933] = 32'h0095c13f;
pd_rom[5934] = 32'h0095c13f;
pd_rom[5935] = 32'h0095c123;
pd_rom[5936] = 32'h00a4c13f;
pd_rom[5937] = 32'h00a5c03f;
pd_rom[5938] = 32'h00a4c13f;
pd_rom[5939] = 32'h00a4c13f;
pd_rom[5940] = 32'h00a4c13f;
pd_rom[5941] = 32'h00a4c13f;
pd_rom[5942] = 32'h00a4c13f;
pd_rom[5943] = 32'h00a4c123;
pd_rom[5944] = 32'h00bb813f;
pd_rom[5945] = 32'h00bb813f;
pd_rom[5946] = 32'h00bb813f;
pd_rom[5947] = 32'h00bb813f;
pd_rom[5948] = 32'h00bb813f;
pd_rom[5949] = 32'h00bb813f;
pd_rom[5950] = 32'h00bb813f;
pd_rom[5951] = 32'h00bb813f;
pd_rom[5952] = 32'h0085c13f;
pd_rom[5953] = 32'h0085c120;
pd_rom[5954] = 32'h0085c13f;
pd_rom[5955] = 32'h0085c13f;
pd_rom[5956] = 32'h0085c13f;
pd_rom[5957] = 32'h0085c13f;
pd_rom[5958] = 32'h0085c13f;
pd_rom[5959] = 32'h0085c13f;
pd_rom[5960] = 32'h0094c13f;
pd_rom[5961] = 32'h0094c13f;
pd_rom[5962] = 32'h0094c13f;
pd_rom[5963] = 32'h0094c13f;
pd_rom[5964] = 32'h0094c13f;
pd_rom[5965] = 32'h0094c13f;
pd_rom[5966] = 32'h0094c13f;
pd_rom[5967] = 32'h0094c13f;
pd_rom[5968] = 32'h00a3c13f;
pd_rom[5969] = 32'h00a3c13f;
pd_rom[5970] = 32'h00a3c13f;
pd_rom[5971] = 32'h00a3c13f;
pd_rom[5972] = 32'h00a3c13f;
pd_rom[5973] = 32'h00a3c13f;
pd_rom[5974] = 32'h00a3c13f;
pd_rom[5975] = 32'h00a3c13f;
pd_rom[5976] = 32'h00ba413f;
pd_rom[5977] = 32'h00ba413f;
pd_rom[5978] = 32'h00ba413f;
pd_rom[5979] = 32'h00ba413f;
pd_rom[5980] = 32'h00ba413f;
pd_rom[5981] = 32'h00ba413f;
pd_rom[5982] = 32'h00ba413f;
pd_rom[5983] = 32'h00ba413f;
pd_rom[5984] = 32'h0086c13f;
pd_rom[5985] = 32'h0087c03f;
pd_rom[5986] = 32'h0086c13f;
pd_rom[5987] = 32'h0086c13f;
pd_rom[5988] = 32'h0086c13f;
pd_rom[5989] = 32'h0086c13f;
pd_rom[5990] = 32'h0086c13f;
pd_rom[5991] = 32'h0086c123;
pd_rom[5992] = 32'h0095c13f;
pd_rom[5993] = 32'h0096c03f;
pd_rom[5994] = 32'h0095c13f;
pd_rom[5995] = 32'h0095c13f;
pd_rom[5996] = 32'h0095c13f;
pd_rom[5997] = 32'h0095c13f;
pd_rom[5998] = 32'h0095c13f;
pd_rom[5999] = 32'h0095c123;
pd_rom[6000] = 32'h00a4c13f;
pd_rom[6001] = 32'h00a5c03f;
pd_rom[6002] = 32'h00a4c13f;
pd_rom[6003] = 32'h00a4c13f;
pd_rom[6004] = 32'h00a4c13f;
pd_rom[6005] = 32'h00a4c13f;
pd_rom[6006] = 32'h00a4c13f;
pd_rom[6007] = 32'h00a4c123;
pd_rom[6008] = 32'h00bb813f;
pd_rom[6009] = 32'h00bb813f;
pd_rom[6010] = 32'h00bb813f;
pd_rom[6011] = 32'h00bb813f;
pd_rom[6012] = 32'h00bb813f;
pd_rom[6013] = 32'h00bb813f;
pd_rom[6014] = 32'h00bb813f;
pd_rom[6015] = 32'h00bb813f;
pd_rom[6016] = 32'h0085c13f;
pd_rom[6017] = 32'h0085c120;
pd_rom[6018] = 32'h0085c13f;
pd_rom[6019] = 32'h0085c13f;
pd_rom[6020] = 32'h0085c13f;
pd_rom[6021] = 32'h0085c13f;
pd_rom[6022] = 32'h0085c13f;
pd_rom[6023] = 32'h0085c13f;
pd_rom[6024] = 32'h0094c13f;
pd_rom[6025] = 32'h0094c13f;
pd_rom[6026] = 32'h0094c13f;
pd_rom[6027] = 32'h0094c13f;
pd_rom[6028] = 32'h0094c13f;
pd_rom[6029] = 32'h0094c13f;
pd_rom[6030] = 32'h0094c13f;
pd_rom[6031] = 32'h0094c13f;
pd_rom[6032] = 32'h00a3c13f;
pd_rom[6033] = 32'h00a3c13f;
pd_rom[6034] = 32'h00a3c13f;
pd_rom[6035] = 32'h00a3c13f;
pd_rom[6036] = 32'h00a3c13f;
pd_rom[6037] = 32'h00a3c13f;
pd_rom[6038] = 32'h00a3c13f;
pd_rom[6039] = 32'h00a3c13f;
pd_rom[6040] = 32'h00ba413f;
pd_rom[6041] = 32'h00ba413f;
pd_rom[6042] = 32'h00ba413f;
pd_rom[6043] = 32'h00ba413f;
pd_rom[6044] = 32'h00ba413f;
pd_rom[6045] = 32'h00ba413f;
pd_rom[6046] = 32'h00ba413f;
pd_rom[6047] = 32'h00ba413f;
pd_rom[6048] = 32'h0086c13f;
pd_rom[6049] = 32'h0087c03f;
pd_rom[6050] = 32'h0086c13f;
pd_rom[6051] = 32'h0086c13f;
pd_rom[6052] = 32'h0086c13f;
pd_rom[6053] = 32'h0086c13f;
pd_rom[6054] = 32'h0086c13f;
pd_rom[6055] = 32'h0086c123;
pd_rom[6056] = 32'h0095c13f;
pd_rom[6057] = 32'h0096c03f;
pd_rom[6058] = 32'h0095c13f;
pd_rom[6059] = 32'h0095c13f;
pd_rom[6060] = 32'h0095c13f;
pd_rom[6061] = 32'h0095c13f;
pd_rom[6062] = 32'h0095c13f;
pd_rom[6063] = 32'h0095c123;
pd_rom[6064] = 32'h00a4c13f;
pd_rom[6065] = 32'h00a5c03f;
pd_rom[6066] = 32'h00a4c13f;
pd_rom[6067] = 32'h00a4c13f;
pd_rom[6068] = 32'h00a4c13f;
pd_rom[6069] = 32'h00a4c13f;
pd_rom[6070] = 32'h00a4c13f;
pd_rom[6071] = 32'h00a4c123;
pd_rom[6072] = 32'h00bb813f;
pd_rom[6073] = 32'h00bb813f;
pd_rom[6074] = 32'h00bb813f;
pd_rom[6075] = 32'h00bb813f;
pd_rom[6076] = 32'h00bb813f;
pd_rom[6077] = 32'h00bb813f;
pd_rom[6078] = 32'h00bb813f;
pd_rom[6079] = 32'h00bb813f;
pd_rom[6080] = 32'h0085c13f;
pd_rom[6081] = 32'h0085c120;
pd_rom[6082] = 32'h0085c13f;
pd_rom[6083] = 32'h0085c13f;
pd_rom[6084] = 32'h0085c13f;
pd_rom[6085] = 32'h0085c13f;
pd_rom[6086] = 32'h0085c13f;
pd_rom[6087] = 32'h0085c13f;
pd_rom[6088] = 32'h0094c13f;
pd_rom[6089] = 32'h0094c13f;
pd_rom[6090] = 32'h0094c13f;
pd_rom[6091] = 32'h0094c13f;
pd_rom[6092] = 32'h0094c13f;
pd_rom[6093] = 32'h0094c13f;
pd_rom[6094] = 32'h0094c13f;
pd_rom[6095] = 32'h0094c13f;
pd_rom[6096] = 32'h00a3c13f;
pd_rom[6097] = 32'h00a3c13f;
pd_rom[6098] = 32'h00a3c13f;
pd_rom[6099] = 32'h00a3c13f;
pd_rom[6100] = 32'h00a3c13f;
pd_rom[6101] = 32'h00a3c13f;
pd_rom[6102] = 32'h00a3c13f;
pd_rom[6103] = 32'h00a3c13f;
pd_rom[6104] = 32'h00ba413f;
pd_rom[6105] = 32'h00ba413f;
pd_rom[6106] = 32'h00ba413f;
pd_rom[6107] = 32'h00ba413f;
pd_rom[6108] = 32'h00ba413f;
pd_rom[6109] = 32'h00ba413f;
pd_rom[6110] = 32'h00ba413f;
pd_rom[6111] = 32'h00ba413f;
pd_rom[6112] = 32'h0086c13f;
pd_rom[6113] = 32'h0087c03f;
pd_rom[6114] = 32'h0086c13f;
pd_rom[6115] = 32'h0086c13f;
pd_rom[6116] = 32'h0086c13f;
pd_rom[6117] = 32'h0086c13f;
pd_rom[6118] = 32'h0086c13f;
pd_rom[6119] = 32'h0086c123;
pd_rom[6120] = 32'h0095c13f;
pd_rom[6121] = 32'h0096c03f;
pd_rom[6122] = 32'h0095c13f;
pd_rom[6123] = 32'h0095c13f;
pd_rom[6124] = 32'h0095c13f;
pd_rom[6125] = 32'h0095c13f;
pd_rom[6126] = 32'h0095c13f;
pd_rom[6127] = 32'h0095c123;
pd_rom[6128] = 32'h00a4c13f;
pd_rom[6129] = 32'h00a5c03f;
pd_rom[6130] = 32'h00a4c13f;
pd_rom[6131] = 32'h00a4c13f;
pd_rom[6132] = 32'h00a4c13f;
pd_rom[6133] = 32'h00a4c13f;
pd_rom[6134] = 32'h00a4c13f;
pd_rom[6135] = 32'h00a4c123;
pd_rom[6136] = 32'h00bb813f;
pd_rom[6137] = 32'h00bb813f;
pd_rom[6138] = 32'h00bb813f;
pd_rom[6139] = 32'h00bb813f;
pd_rom[6140] = 32'h00bb813f;
pd_rom[6141] = 32'h00bb813f;
pd_rom[6142] = 32'h00bb813f;
pd_rom[6143] = 32'h00bb813f;
pd_rom[6144] = 32'h007fc13f;
pd_rom[6145] = 32'h007fc120;
pd_rom[6146] = 32'h007fc13f;
pd_rom[6147] = 32'h007fc13f;
pd_rom[6148] = 32'h007fc13f;
pd_rom[6149] = 32'h007fc13f;
pd_rom[6150] = 32'h007fc13f;
pd_rom[6151] = 32'h007fc13f;
pd_rom[6152] = 32'h008ec13f;
pd_rom[6153] = 32'h008ec120;
pd_rom[6154] = 32'h008ec13f;
pd_rom[6155] = 32'h008ec13f;
pd_rom[6156] = 32'h008ec13f;
pd_rom[6157] = 32'h008ec13f;
pd_rom[6158] = 32'h008ec13f;
pd_rom[6159] = 32'h008ec13f;
pd_rom[6160] = 32'h009dc13f;
pd_rom[6161] = 32'h009dc120;
pd_rom[6162] = 32'h009dc13f;
pd_rom[6163] = 32'h009dc13f;
pd_rom[6164] = 32'h009dc13f;
pd_rom[6165] = 32'h009dc13f;
pd_rom[6166] = 32'h009dc13f;
pd_rom[6167] = 32'h009dc13f;
pd_rom[6168] = 32'h00ac413f;
pd_rom[6169] = 32'h00ac4120;
pd_rom[6170] = 32'h00ac413f;
pd_rom[6171] = 32'h00ac413f;
pd_rom[6172] = 32'h00ac413f;
pd_rom[6173] = 32'h00ac413f;
pd_rom[6174] = 32'h00ac413f;
pd_rom[6175] = 32'h00ac413f;
pd_rom[6176] = 32'h00b0003f;
pd_rom[6177] = 32'h00b1003f;
pd_rom[6178] = 32'h0080c13f;
pd_rom[6179] = 32'h0080c13f;
pd_rom[6180] = 32'h0080c13f;
pd_rom[6181] = 32'h0080c13f;
pd_rom[6182] = 32'h0080c13f;
pd_rom[6183] = 32'h0080c123;
pd_rom[6184] = 32'h00bc803f;
pd_rom[6185] = 32'h00bd803f;
pd_rom[6186] = 32'h008fc13f;
pd_rom[6187] = 32'h008fc13f;
pd_rom[6188] = 32'h008fc13f;
pd_rom[6189] = 32'h008fc13f;
pd_rom[6190] = 32'h008fc13f;
pd_rom[6191] = 32'h008fc123;
pd_rom[6192] = 32'h009ec120;
pd_rom[6193] = 32'h00be803f;
pd_rom[6194] = 32'h009ec13f;
pd_rom[6195] = 32'h009ec13f;
pd_rom[6196] = 32'h009ec13f;
pd_rom[6197] = 32'h009ec13f;
pd_rom[6198] = 32'h009ec13f;
pd_rom[6199] = 32'h009ec123;
pd_rom[6200] = 32'h00ad413f;
pd_rom[6201] = 32'h00ad4120;
pd_rom[6202] = 32'h00ad413f;
pd_rom[6203] = 32'h00ad413f;
pd_rom[6204] = 32'h00ad413f;
pd_rom[6205] = 32'h00ad413f;
pd_rom[6206] = 32'h00ad413f;
pd_rom[6207] = 32'h00ad413f;
pd_rom[6208] = 32'h007fc13f;
pd_rom[6209] = 32'h007fc120;
pd_rom[6210] = 32'h007fc13f;
pd_rom[6211] = 32'h007fc13f;
pd_rom[6212] = 32'h007fc13f;
pd_rom[6213] = 32'h007fc13f;
pd_rom[6214] = 32'h007fc13f;
pd_rom[6215] = 32'h007fc13f;
pd_rom[6216] = 32'h008ec13f;
pd_rom[6217] = 32'h008ec120;
pd_rom[6218] = 32'h008ec13f;
pd_rom[6219] = 32'h008ec13f;
pd_rom[6220] = 32'h008ec13f;
pd_rom[6221] = 32'h008ec13f;
pd_rom[6222] = 32'h008ec13f;
pd_rom[6223] = 32'h008ec13f;
pd_rom[6224] = 32'h009dc13f;
pd_rom[6225] = 32'h009dc120;
pd_rom[6226] = 32'h009dc13f;
pd_rom[6227] = 32'h009dc13f;
pd_rom[6228] = 32'h009dc13f;
pd_rom[6229] = 32'h009dc13f;
pd_rom[6230] = 32'h009dc13f;
pd_rom[6231] = 32'h009dc13f;
pd_rom[6232] = 32'h00ac413f;
pd_rom[6233] = 32'h00ac4120;
pd_rom[6234] = 32'h00ac413f;
pd_rom[6235] = 32'h00ac413f;
pd_rom[6236] = 32'h00ac413f;
pd_rom[6237] = 32'h00ac413f;
pd_rom[6238] = 32'h00ac413f;
pd_rom[6239] = 32'h00ac413f;
pd_rom[6240] = 32'h00b0003f;
pd_rom[6241] = 32'h00b1003f;
pd_rom[6242] = 32'h0080c13f;
pd_rom[6243] = 32'h0080c13f;
pd_rom[6244] = 32'h0080c13f;
pd_rom[6245] = 32'h0080c13f;
pd_rom[6246] = 32'h0080c13f;
pd_rom[6247] = 32'h0080c123;
pd_rom[6248] = 32'h00bc803f;
pd_rom[6249] = 32'h00bd803f;
pd_rom[6250] = 32'h008fc13f;
pd_rom[6251] = 32'h008fc13f;
pd_rom[6252] = 32'h008fc13f;
pd_rom[6253] = 32'h008fc13f;
pd_rom[6254] = 32'h008fc13f;
pd_rom[6255] = 32'h008fc123;
pd_rom[6256] = 32'h009ec120;
pd_rom[6257] = 32'h00be803f;
pd_rom[6258] = 32'h009ec13f;
pd_rom[6259] = 32'h009ec13f;
pd_rom[6260] = 32'h009ec13f;
pd_rom[6261] = 32'h009ec13f;
pd_rom[6262] = 32'h009ec13f;
pd_rom[6263] = 32'h009ec123;
pd_rom[6264] = 32'h00ad413f;
pd_rom[6265] = 32'h00ad4120;
pd_rom[6266] = 32'h00ad413f;
pd_rom[6267] = 32'h00ad413f;
pd_rom[6268] = 32'h00ad413f;
pd_rom[6269] = 32'h00ad413f;
pd_rom[6270] = 32'h00ad413f;
pd_rom[6271] = 32'h00ad413f;
pd_rom[6272] = 32'h007fc13f;
pd_rom[6273] = 32'h007fc120;
pd_rom[6274] = 32'h007fc13f;
pd_rom[6275] = 32'h007fc13f;
pd_rom[6276] = 32'h007fc13f;
pd_rom[6277] = 32'h007fc13f;
pd_rom[6278] = 32'h007fc13f;
pd_rom[6279] = 32'h007fc13f;
pd_rom[6280] = 32'h008ec13f;
pd_rom[6281] = 32'h008ec120;
pd_rom[6282] = 32'h008ec13f;
pd_rom[6283] = 32'h008ec13f;
pd_rom[6284] = 32'h008ec13f;
pd_rom[6285] = 32'h008ec13f;
pd_rom[6286] = 32'h008ec13f;
pd_rom[6287] = 32'h008ec13f;
pd_rom[6288] = 32'h009dc13f;
pd_rom[6289] = 32'h009dc120;
pd_rom[6290] = 32'h009dc13f;
pd_rom[6291] = 32'h009dc13f;
pd_rom[6292] = 32'h009dc13f;
pd_rom[6293] = 32'h009dc13f;
pd_rom[6294] = 32'h009dc13f;
pd_rom[6295] = 32'h009dc13f;
pd_rom[6296] = 32'h00ac413f;
pd_rom[6297] = 32'h00ac4120;
pd_rom[6298] = 32'h00ac413f;
pd_rom[6299] = 32'h00ac413f;
pd_rom[6300] = 32'h00ac413f;
pd_rom[6301] = 32'h00ac413f;
pd_rom[6302] = 32'h00ac413f;
pd_rom[6303] = 32'h00ac413f;
pd_rom[6304] = 32'h00b0003f;
pd_rom[6305] = 32'h00b1003f;
pd_rom[6306] = 32'h0080c13f;
pd_rom[6307] = 32'h0080c13f;
pd_rom[6308] = 32'h0080c13f;
pd_rom[6309] = 32'h0080c13f;
pd_rom[6310] = 32'h0080c13f;
pd_rom[6311] = 32'h0080c123;
pd_rom[6312] = 32'h00bc803f;
pd_rom[6313] = 32'h00bd803f;
pd_rom[6314] = 32'h008fc13f;
pd_rom[6315] = 32'h008fc13f;
pd_rom[6316] = 32'h008fc13f;
pd_rom[6317] = 32'h008fc13f;
pd_rom[6318] = 32'h008fc13f;
pd_rom[6319] = 32'h008fc123;
pd_rom[6320] = 32'h009ec120;
pd_rom[6321] = 32'h00be803f;
pd_rom[6322] = 32'h009ec13f;
pd_rom[6323] = 32'h009ec13f;
pd_rom[6324] = 32'h009ec13f;
pd_rom[6325] = 32'h009ec13f;
pd_rom[6326] = 32'h009ec13f;
pd_rom[6327] = 32'h009ec123;
pd_rom[6328] = 32'h00ad413f;
pd_rom[6329] = 32'h00ad4120;
pd_rom[6330] = 32'h00ad413f;
pd_rom[6331] = 32'h00ad413f;
pd_rom[6332] = 32'h00ad413f;
pd_rom[6333] = 32'h00ad413f;
pd_rom[6334] = 32'h00ad413f;
pd_rom[6335] = 32'h00ad413f;
pd_rom[6336] = 32'h007fc13f;
pd_rom[6337] = 32'h007fc120;
pd_rom[6338] = 32'h007fc13f;
pd_rom[6339] = 32'h007fc13f;
pd_rom[6340] = 32'h007fc13f;
pd_rom[6341] = 32'h007fc13f;
pd_rom[6342] = 32'h007fc13f;
pd_rom[6343] = 32'h007fc13f;
pd_rom[6344] = 32'h008ec13f;
pd_rom[6345] = 32'h008ec120;
pd_rom[6346] = 32'h008ec13f;
pd_rom[6347] = 32'h008ec13f;
pd_rom[6348] = 32'h008ec13f;
pd_rom[6349] = 32'h008ec13f;
pd_rom[6350] = 32'h008ec13f;
pd_rom[6351] = 32'h008ec13f;
pd_rom[6352] = 32'h009dc13f;
pd_rom[6353] = 32'h009dc120;
pd_rom[6354] = 32'h009dc13f;
pd_rom[6355] = 32'h009dc13f;
pd_rom[6356] = 32'h009dc13f;
pd_rom[6357] = 32'h009dc13f;
pd_rom[6358] = 32'h009dc13f;
pd_rom[6359] = 32'h009dc13f;
pd_rom[6360] = 32'h00ac413f;
pd_rom[6361] = 32'h00ac4120;
pd_rom[6362] = 32'h00ac413f;
pd_rom[6363] = 32'h00ac413f;
pd_rom[6364] = 32'h00ac413f;
pd_rom[6365] = 32'h00ac413f;
pd_rom[6366] = 32'h00ac413f;
pd_rom[6367] = 32'h00ac413f;
pd_rom[6368] = 32'h00b0003f;
pd_rom[6369] = 32'h00b1003f;
pd_rom[6370] = 32'h0080c13f;
pd_rom[6371] = 32'h0080c13f;
pd_rom[6372] = 32'h0080c13f;
pd_rom[6373] = 32'h0080c13f;
pd_rom[6374] = 32'h0080c13f;
pd_rom[6375] = 32'h0080c123;
pd_rom[6376] = 32'h00bc803f;
pd_rom[6377] = 32'h00bd803f;
pd_rom[6378] = 32'h008fc13f;
pd_rom[6379] = 32'h008fc13f;
pd_rom[6380] = 32'h008fc13f;
pd_rom[6381] = 32'h008fc13f;
pd_rom[6382] = 32'h008fc13f;
pd_rom[6383] = 32'h008fc123;
pd_rom[6384] = 32'h009ec120;
pd_rom[6385] = 32'h00be803f;
pd_rom[6386] = 32'h009ec13f;
pd_rom[6387] = 32'h009ec13f;
pd_rom[6388] = 32'h009ec13f;
pd_rom[6389] = 32'h009ec13f;
pd_rom[6390] = 32'h009ec13f;
pd_rom[6391] = 32'h009ec123;
pd_rom[6392] = 32'h00ad413f;
pd_rom[6393] = 32'h00ad4120;
pd_rom[6394] = 32'h00ad413f;
pd_rom[6395] = 32'h00ad413f;
pd_rom[6396] = 32'h00ad413f;
pd_rom[6397] = 32'h00ad413f;
pd_rom[6398] = 32'h00ad413f;
pd_rom[6399] = 32'h00ad413f;
pd_rom[6400] = 32'h007fc13f;
pd_rom[6401] = 32'h007fc120;
pd_rom[6402] = 32'h007fc13f;
pd_rom[6403] = 32'h007fc13f;
pd_rom[6404] = 32'h007fc13f;
pd_rom[6405] = 32'h007fc13f;
pd_rom[6406] = 32'h007fc13f;
pd_rom[6407] = 32'h007fc13f;
pd_rom[6408] = 32'h008ec13f;
pd_rom[6409] = 32'h008ec120;
pd_rom[6410] = 32'h008ec13f;
pd_rom[6411] = 32'h008ec13f;
pd_rom[6412] = 32'h008ec13f;
pd_rom[6413] = 32'h008ec13f;
pd_rom[6414] = 32'h008ec13f;
pd_rom[6415] = 32'h008ec13f;
pd_rom[6416] = 32'h009dc13f;
pd_rom[6417] = 32'h009dc120;
pd_rom[6418] = 32'h009dc13f;
pd_rom[6419] = 32'h009dc13f;
pd_rom[6420] = 32'h009dc13f;
pd_rom[6421] = 32'h009dc13f;
pd_rom[6422] = 32'h009dc13f;
pd_rom[6423] = 32'h009dc13f;
pd_rom[6424] = 32'h00ac413f;
pd_rom[6425] = 32'h00ac4120;
pd_rom[6426] = 32'h00ac413f;
pd_rom[6427] = 32'h00ac413f;
pd_rom[6428] = 32'h00ac413f;
pd_rom[6429] = 32'h00ac413f;
pd_rom[6430] = 32'h00ac413f;
pd_rom[6431] = 32'h00ac413f;
pd_rom[6432] = 32'h00b0003f;
pd_rom[6433] = 32'h00b1003f;
pd_rom[6434] = 32'h0080c13f;
pd_rom[6435] = 32'h0080c13f;
pd_rom[6436] = 32'h0080c13f;
pd_rom[6437] = 32'h0080c13f;
pd_rom[6438] = 32'h0080c13f;
pd_rom[6439] = 32'h0080c123;
pd_rom[6440] = 32'h00bc803f;
pd_rom[6441] = 32'h00bd803f;
pd_rom[6442] = 32'h008fc13f;
pd_rom[6443] = 32'h008fc13f;
pd_rom[6444] = 32'h008fc13f;
pd_rom[6445] = 32'h008fc13f;
pd_rom[6446] = 32'h008fc13f;
pd_rom[6447] = 32'h008fc123;
pd_rom[6448] = 32'h009ec120;
pd_rom[6449] = 32'h00be803f;
pd_rom[6450] = 32'h009ec13f;
pd_rom[6451] = 32'h009ec13f;
pd_rom[6452] = 32'h009ec13f;
pd_rom[6453] = 32'h009ec13f;
pd_rom[6454] = 32'h009ec13f;
pd_rom[6455] = 32'h009ec123;
pd_rom[6456] = 32'h00ad413f;
pd_rom[6457] = 32'h00ad4120;
pd_rom[6458] = 32'h00ad413f;
pd_rom[6459] = 32'h00ad413f;
pd_rom[6460] = 32'h00ad413f;
pd_rom[6461] = 32'h00ad413f;
pd_rom[6462] = 32'h00ad413f;
pd_rom[6463] = 32'h00ad413f;
pd_rom[6464] = 32'h007fc13f;
pd_rom[6465] = 32'h007fc120;
pd_rom[6466] = 32'h007fc13f;
pd_rom[6467] = 32'h007fc13f;
pd_rom[6468] = 32'h007fc13f;
pd_rom[6469] = 32'h007fc13f;
pd_rom[6470] = 32'h007fc13f;
pd_rom[6471] = 32'h007fc13f;
pd_rom[6472] = 32'h008ec13f;
pd_rom[6473] = 32'h008ec120;
pd_rom[6474] = 32'h008ec13f;
pd_rom[6475] = 32'h008ec13f;
pd_rom[6476] = 32'h008ec13f;
pd_rom[6477] = 32'h008ec13f;
pd_rom[6478] = 32'h008ec13f;
pd_rom[6479] = 32'h008ec13f;
pd_rom[6480] = 32'h009dc13f;
pd_rom[6481] = 32'h009dc120;
pd_rom[6482] = 32'h009dc13f;
pd_rom[6483] = 32'h009dc13f;
pd_rom[6484] = 32'h009dc13f;
pd_rom[6485] = 32'h009dc13f;
pd_rom[6486] = 32'h009dc13f;
pd_rom[6487] = 32'h009dc13f;
pd_rom[6488] = 32'h00ac413f;
pd_rom[6489] = 32'h00ac4120;
pd_rom[6490] = 32'h00ac413f;
pd_rom[6491] = 32'h00ac413f;
pd_rom[6492] = 32'h00ac413f;
pd_rom[6493] = 32'h00ac413f;
pd_rom[6494] = 32'h00ac413f;
pd_rom[6495] = 32'h00ac413f;
pd_rom[6496] = 32'h00b0003f;
pd_rom[6497] = 32'h00b1003f;
pd_rom[6498] = 32'h0080c13f;
pd_rom[6499] = 32'h0080c13f;
pd_rom[6500] = 32'h0080c13f;
pd_rom[6501] = 32'h0080c13f;
pd_rom[6502] = 32'h0080c13f;
pd_rom[6503] = 32'h0080c123;
pd_rom[6504] = 32'h00bc803f;
pd_rom[6505] = 32'h00bd803f;
pd_rom[6506] = 32'h008fc13f;
pd_rom[6507] = 32'h008fc13f;
pd_rom[6508] = 32'h008fc13f;
pd_rom[6509] = 32'h008fc13f;
pd_rom[6510] = 32'h008fc13f;
pd_rom[6511] = 32'h008fc123;
pd_rom[6512] = 32'h009ec120;
pd_rom[6513] = 32'h00be803f;
pd_rom[6514] = 32'h009ec13f;
pd_rom[6515] = 32'h009ec13f;
pd_rom[6516] = 32'h009ec13f;
pd_rom[6517] = 32'h009ec13f;
pd_rom[6518] = 32'h009ec13f;
pd_rom[6519] = 32'h009ec123;
pd_rom[6520] = 32'h00ad413f;
pd_rom[6521] = 32'h00ad4120;
pd_rom[6522] = 32'h00ad413f;
pd_rom[6523] = 32'h00ad413f;
pd_rom[6524] = 32'h00ad413f;
pd_rom[6525] = 32'h00ad413f;
pd_rom[6526] = 32'h00ad413f;
pd_rom[6527] = 32'h00ad413f;
pd_rom[6528] = 32'h007fc13f;
pd_rom[6529] = 32'h007fc120;
pd_rom[6530] = 32'h007fc13f;
pd_rom[6531] = 32'h007fc13f;
pd_rom[6532] = 32'h007fc13f;
pd_rom[6533] = 32'h007fc13f;
pd_rom[6534] = 32'h007fc13f;
pd_rom[6535] = 32'h007fc13f;
pd_rom[6536] = 32'h008ec13f;
pd_rom[6537] = 32'h008ec120;
pd_rom[6538] = 32'h008ec13f;
pd_rom[6539] = 32'h008ec13f;
pd_rom[6540] = 32'h008ec13f;
pd_rom[6541] = 32'h008ec13f;
pd_rom[6542] = 32'h008ec13f;
pd_rom[6543] = 32'h008ec13f;
pd_rom[6544] = 32'h009dc13f;
pd_rom[6545] = 32'h009dc120;
pd_rom[6546] = 32'h009dc13f;
pd_rom[6547] = 32'h009dc13f;
pd_rom[6548] = 32'h009dc13f;
pd_rom[6549] = 32'h009dc13f;
pd_rom[6550] = 32'h009dc13f;
pd_rom[6551] = 32'h009dc13f;
pd_rom[6552] = 32'h00ac413f;
pd_rom[6553] = 32'h00ac4120;
pd_rom[6554] = 32'h00ac413f;
pd_rom[6555] = 32'h00ac413f;
pd_rom[6556] = 32'h00ac413f;
pd_rom[6557] = 32'h00ac413f;
pd_rom[6558] = 32'h00ac413f;
pd_rom[6559] = 32'h00ac413f;
pd_rom[6560] = 32'h00b0003f;
pd_rom[6561] = 32'h00b1003f;
pd_rom[6562] = 32'h0080c13f;
pd_rom[6563] = 32'h0080c13f;
pd_rom[6564] = 32'h0080c13f;
pd_rom[6565] = 32'h0080c13f;
pd_rom[6566] = 32'h0080c13f;
pd_rom[6567] = 32'h0080c123;
pd_rom[6568] = 32'h00bc803f;
pd_rom[6569] = 32'h00bd803f;
pd_rom[6570] = 32'h008fc13f;
pd_rom[6571] = 32'h008fc13f;
pd_rom[6572] = 32'h008fc13f;
pd_rom[6573] = 32'h008fc13f;
pd_rom[6574] = 32'h008fc13f;
pd_rom[6575] = 32'h008fc123;
pd_rom[6576] = 32'h009ec120;
pd_rom[6577] = 32'h00be803f;
pd_rom[6578] = 32'h009ec13f;
pd_rom[6579] = 32'h009ec13f;
pd_rom[6580] = 32'h009ec13f;
pd_rom[6581] = 32'h009ec13f;
pd_rom[6582] = 32'h009ec13f;
pd_rom[6583] = 32'h009ec123;
pd_rom[6584] = 32'h00ad413f;
pd_rom[6585] = 32'h00ad4120;
pd_rom[6586] = 32'h00ad413f;
pd_rom[6587] = 32'h00ad413f;
pd_rom[6588] = 32'h00ad413f;
pd_rom[6589] = 32'h00ad413f;
pd_rom[6590] = 32'h00ad413f;
pd_rom[6591] = 32'h00ad413f;
pd_rom[6592] = 32'h007fc13f;
pd_rom[6593] = 32'h007fc120;
pd_rom[6594] = 32'h007fc13f;
pd_rom[6595] = 32'h007fc13f;
pd_rom[6596] = 32'h007fc13f;
pd_rom[6597] = 32'h007fc13f;
pd_rom[6598] = 32'h007fc13f;
pd_rom[6599] = 32'h007fc13f;
pd_rom[6600] = 32'h008ec13f;
pd_rom[6601] = 32'h008ec120;
pd_rom[6602] = 32'h008ec13f;
pd_rom[6603] = 32'h008ec13f;
pd_rom[6604] = 32'h008ec13f;
pd_rom[6605] = 32'h008ec13f;
pd_rom[6606] = 32'h008ec13f;
pd_rom[6607] = 32'h008ec13f;
pd_rom[6608] = 32'h009dc13f;
pd_rom[6609] = 32'h009dc120;
pd_rom[6610] = 32'h009dc13f;
pd_rom[6611] = 32'h009dc13f;
pd_rom[6612] = 32'h009dc13f;
pd_rom[6613] = 32'h009dc13f;
pd_rom[6614] = 32'h009dc13f;
pd_rom[6615] = 32'h009dc13f;
pd_rom[6616] = 32'h00ac413f;
pd_rom[6617] = 32'h00ac4120;
pd_rom[6618] = 32'h00ac413f;
pd_rom[6619] = 32'h00ac413f;
pd_rom[6620] = 32'h00ac413f;
pd_rom[6621] = 32'h00ac413f;
pd_rom[6622] = 32'h00ac413f;
pd_rom[6623] = 32'h00ac413f;
pd_rom[6624] = 32'h00b0003f;
pd_rom[6625] = 32'h00b1003f;
pd_rom[6626] = 32'h0080c13f;
pd_rom[6627] = 32'h0080c13f;
pd_rom[6628] = 32'h0080c13f;
pd_rom[6629] = 32'h0080c13f;
pd_rom[6630] = 32'h0080c13f;
pd_rom[6631] = 32'h0080c123;
pd_rom[6632] = 32'h00bc803f;
pd_rom[6633] = 32'h00bd803f;
pd_rom[6634] = 32'h008fc13f;
pd_rom[6635] = 32'h008fc13f;
pd_rom[6636] = 32'h008fc13f;
pd_rom[6637] = 32'h008fc13f;
pd_rom[6638] = 32'h008fc13f;
pd_rom[6639] = 32'h008fc123;
pd_rom[6640] = 32'h009ec120;
pd_rom[6641] = 32'h00be803f;
pd_rom[6642] = 32'h009ec13f;
pd_rom[6643] = 32'h009ec13f;
pd_rom[6644] = 32'h009ec13f;
pd_rom[6645] = 32'h009ec13f;
pd_rom[6646] = 32'h009ec13f;
pd_rom[6647] = 32'h009ec123;
pd_rom[6648] = 32'h00ad413f;
pd_rom[6649] = 32'h00ad4120;
pd_rom[6650] = 32'h00ad413f;
pd_rom[6651] = 32'h00ad413f;
pd_rom[6652] = 32'h00ad413f;
pd_rom[6653] = 32'h00ad413f;
pd_rom[6654] = 32'h00ad413f;
pd_rom[6655] = 32'h00ad413f;
pd_rom[6656] = 32'h0083c13f;
pd_rom[6657] = 32'h0083c120;
pd_rom[6658] = 32'h0083c13f;
pd_rom[6659] = 32'h0083c13f;
pd_rom[6660] = 32'h0083c13f;
pd_rom[6661] = 32'h0083c13f;
pd_rom[6662] = 32'h0083c13f;
pd_rom[6663] = 32'h0083c13f;
pd_rom[6664] = 32'h0092c13f;
pd_rom[6665] = 32'h0092c13f;
pd_rom[6666] = 32'h0092c13f;
pd_rom[6667] = 32'h0092c13f;
pd_rom[6668] = 32'h0092c13f;
pd_rom[6669] = 32'h0092c13f;
pd_rom[6670] = 32'h0092c13f;
pd_rom[6671] = 32'h0092c13f;
pd_rom[6672] = 32'h00a1c13f;
pd_rom[6673] = 32'h00a1c13f;
pd_rom[6674] = 32'h00a1c13f;
pd_rom[6675] = 32'h00a1c13f;
pd_rom[6676] = 32'h00a1c13f;
pd_rom[6677] = 32'h00a1c13f;
pd_rom[6678] = 32'h00a1c13f;
pd_rom[6679] = 32'h00a1c13f;
pd_rom[6680] = 32'h00b8413f;
pd_rom[6681] = 32'h00b8413f;
pd_rom[6682] = 32'h00b8413f;
pd_rom[6683] = 32'h00b8413f;
pd_rom[6684] = 32'h00b8413f;
pd_rom[6685] = 32'h00b8413f;
pd_rom[6686] = 32'h00b8413f;
pd_rom[6687] = 32'h00b8413f;
pd_rom[6688] = 32'h008ac03f;
pd_rom[6689] = 32'h008bc03f;
pd_rom[6690] = 32'h0084c13f;
pd_rom[6691] = 32'h0084c13f;
pd_rom[6692] = 32'h0084c13f;
pd_rom[6693] = 32'h0084c13f;
pd_rom[6694] = 32'h0084c13f;
pd_rom[6695] = 32'h0084c123;
pd_rom[6696] = 32'h0099c03f;
pd_rom[6697] = 32'h009ac03f;
pd_rom[6698] = 32'h0093c13f;
pd_rom[6699] = 32'h0093c13f;
pd_rom[6700] = 32'h0093c13f;
pd_rom[6701] = 32'h0093c13f;
pd_rom[6702] = 32'h0093c13f;
pd_rom[6703] = 32'h0093c123;
pd_rom[6704] = 32'h00a8c03f;
pd_rom[6705] = 32'h00a9c03f;
pd_rom[6706] = 32'h00a2c13f;
pd_rom[6707] = 32'h00a2c13f;
pd_rom[6708] = 32'h00a2c13f;
pd_rom[6709] = 32'h00a2c13f;
pd_rom[6710] = 32'h00a2c13f;
pd_rom[6711] = 32'h00a2c123;
pd_rom[6712] = 32'h00b9813f;
pd_rom[6713] = 32'h00b9813f;
pd_rom[6714] = 32'h00b9813f;
pd_rom[6715] = 32'h00b9813f;
pd_rom[6716] = 32'h00b9813f;
pd_rom[6717] = 32'h00b9813f;
pd_rom[6718] = 32'h00b9813f;
pd_rom[6719] = 32'h00b9813f;
pd_rom[6720] = 32'h0083c13f;
pd_rom[6721] = 32'h0083c120;
pd_rom[6722] = 32'h0083c13f;
pd_rom[6723] = 32'h0083c13f;
pd_rom[6724] = 32'h0083c13f;
pd_rom[6725] = 32'h0083c13f;
pd_rom[6726] = 32'h0083c13f;
pd_rom[6727] = 32'h0083c13f;
pd_rom[6728] = 32'h0092c13f;
pd_rom[6729] = 32'h0092c13f;
pd_rom[6730] = 32'h0092c13f;
pd_rom[6731] = 32'h0092c13f;
pd_rom[6732] = 32'h0092c13f;
pd_rom[6733] = 32'h0092c13f;
pd_rom[6734] = 32'h0092c13f;
pd_rom[6735] = 32'h0092c13f;
pd_rom[6736] = 32'h00a1c13f;
pd_rom[6737] = 32'h00a1c13f;
pd_rom[6738] = 32'h00a1c13f;
pd_rom[6739] = 32'h00a1c13f;
pd_rom[6740] = 32'h00a1c13f;
pd_rom[6741] = 32'h00a1c13f;
pd_rom[6742] = 32'h00a1c13f;
pd_rom[6743] = 32'h00a1c13f;
pd_rom[6744] = 32'h00b8413f;
pd_rom[6745] = 32'h00b8413f;
pd_rom[6746] = 32'h00b8413f;
pd_rom[6747] = 32'h00b8413f;
pd_rom[6748] = 32'h00b8413f;
pd_rom[6749] = 32'h00b8413f;
pd_rom[6750] = 32'h00b8413f;
pd_rom[6751] = 32'h00b8413f;
pd_rom[6752] = 32'h008ac03f;
pd_rom[6753] = 32'h008bc03f;
pd_rom[6754] = 32'h0084c13f;
pd_rom[6755] = 32'h0084c13f;
pd_rom[6756] = 32'h0084c13f;
pd_rom[6757] = 32'h0084c13f;
pd_rom[6758] = 32'h0084c13f;
pd_rom[6759] = 32'h0084c123;
pd_rom[6760] = 32'h0099c03f;
pd_rom[6761] = 32'h009ac03f;
pd_rom[6762] = 32'h0093c13f;
pd_rom[6763] = 32'h0093c13f;
pd_rom[6764] = 32'h0093c13f;
pd_rom[6765] = 32'h0093c13f;
pd_rom[6766] = 32'h0093c13f;
pd_rom[6767] = 32'h0093c123;
pd_rom[6768] = 32'h00a8c03f;
pd_rom[6769] = 32'h00a9c03f;
pd_rom[6770] = 32'h00a2c13f;
pd_rom[6771] = 32'h00a2c13f;
pd_rom[6772] = 32'h00a2c13f;
pd_rom[6773] = 32'h00a2c13f;
pd_rom[6774] = 32'h00a2c13f;
pd_rom[6775] = 32'h00a2c123;
pd_rom[6776] = 32'h00b9813f;
pd_rom[6777] = 32'h00b9813f;
pd_rom[6778] = 32'h00b9813f;
pd_rom[6779] = 32'h00b9813f;
pd_rom[6780] = 32'h00b9813f;
pd_rom[6781] = 32'h00b9813f;
pd_rom[6782] = 32'h00b9813f;
pd_rom[6783] = 32'h00b9813f;
pd_rom[6784] = 32'h0083c13f;
pd_rom[6785] = 32'h0083c120;
pd_rom[6786] = 32'h0083c13f;
pd_rom[6787] = 32'h0083c13f;
pd_rom[6788] = 32'h0083c13f;
pd_rom[6789] = 32'h0083c13f;
pd_rom[6790] = 32'h0083c13f;
pd_rom[6791] = 32'h0083c13f;
pd_rom[6792] = 32'h0092c13f;
pd_rom[6793] = 32'h0092c13f;
pd_rom[6794] = 32'h0092c13f;
pd_rom[6795] = 32'h0092c13f;
pd_rom[6796] = 32'h0092c13f;
pd_rom[6797] = 32'h0092c13f;
pd_rom[6798] = 32'h0092c13f;
pd_rom[6799] = 32'h0092c13f;
pd_rom[6800] = 32'h00a1c13f;
pd_rom[6801] = 32'h00a1c13f;
pd_rom[6802] = 32'h00a1c13f;
pd_rom[6803] = 32'h00a1c13f;
pd_rom[6804] = 32'h00a1c13f;
pd_rom[6805] = 32'h00a1c13f;
pd_rom[6806] = 32'h00a1c13f;
pd_rom[6807] = 32'h00a1c13f;
pd_rom[6808] = 32'h00b8413f;
pd_rom[6809] = 32'h00b8413f;
pd_rom[6810] = 32'h00b8413f;
pd_rom[6811] = 32'h00b8413f;
pd_rom[6812] = 32'h00b8413f;
pd_rom[6813] = 32'h00b8413f;
pd_rom[6814] = 32'h00b8413f;
pd_rom[6815] = 32'h00b8413f;
pd_rom[6816] = 32'h008ac03f;
pd_rom[6817] = 32'h008bc03f;
pd_rom[6818] = 32'h0084c13f;
pd_rom[6819] = 32'h0084c13f;
pd_rom[6820] = 32'h0084c13f;
pd_rom[6821] = 32'h0084c13f;
pd_rom[6822] = 32'h0084c13f;
pd_rom[6823] = 32'h0084c123;
pd_rom[6824] = 32'h0099c03f;
pd_rom[6825] = 32'h009ac03f;
pd_rom[6826] = 32'h0093c13f;
pd_rom[6827] = 32'h0093c13f;
pd_rom[6828] = 32'h0093c13f;
pd_rom[6829] = 32'h0093c13f;
pd_rom[6830] = 32'h0093c13f;
pd_rom[6831] = 32'h0093c123;
pd_rom[6832] = 32'h00a8c03f;
pd_rom[6833] = 32'h00a9c03f;
pd_rom[6834] = 32'h00a2c13f;
pd_rom[6835] = 32'h00a2c13f;
pd_rom[6836] = 32'h00a2c13f;
pd_rom[6837] = 32'h00a2c13f;
pd_rom[6838] = 32'h00a2c13f;
pd_rom[6839] = 32'h00a2c123;
pd_rom[6840] = 32'h00b9813f;
pd_rom[6841] = 32'h00b9813f;
pd_rom[6842] = 32'h00b9813f;
pd_rom[6843] = 32'h00b9813f;
pd_rom[6844] = 32'h00b9813f;
pd_rom[6845] = 32'h00b9813f;
pd_rom[6846] = 32'h00b9813f;
pd_rom[6847] = 32'h00b9813f;
pd_rom[6848] = 32'h0083c13f;
pd_rom[6849] = 32'h0083c120;
pd_rom[6850] = 32'h0083c13f;
pd_rom[6851] = 32'h0083c13f;
pd_rom[6852] = 32'h0083c13f;
pd_rom[6853] = 32'h0083c13f;
pd_rom[6854] = 32'h0083c13f;
pd_rom[6855] = 32'h0083c13f;
pd_rom[6856] = 32'h0092c13f;
pd_rom[6857] = 32'h0092c13f;
pd_rom[6858] = 32'h0092c13f;
pd_rom[6859] = 32'h0092c13f;
pd_rom[6860] = 32'h0092c13f;
pd_rom[6861] = 32'h0092c13f;
pd_rom[6862] = 32'h0092c13f;
pd_rom[6863] = 32'h0092c13f;
pd_rom[6864] = 32'h00a1c13f;
pd_rom[6865] = 32'h00a1c13f;
pd_rom[6866] = 32'h00a1c13f;
pd_rom[6867] = 32'h00a1c13f;
pd_rom[6868] = 32'h00a1c13f;
pd_rom[6869] = 32'h00a1c13f;
pd_rom[6870] = 32'h00a1c13f;
pd_rom[6871] = 32'h00a1c13f;
pd_rom[6872] = 32'h00b8413f;
pd_rom[6873] = 32'h00b8413f;
pd_rom[6874] = 32'h00b8413f;
pd_rom[6875] = 32'h00b8413f;
pd_rom[6876] = 32'h00b8413f;
pd_rom[6877] = 32'h00b8413f;
pd_rom[6878] = 32'h00b8413f;
pd_rom[6879] = 32'h00b8413f;
pd_rom[6880] = 32'h008ac03f;
pd_rom[6881] = 32'h008bc03f;
pd_rom[6882] = 32'h0084c13f;
pd_rom[6883] = 32'h0084c13f;
pd_rom[6884] = 32'h0084c13f;
pd_rom[6885] = 32'h0084c13f;
pd_rom[6886] = 32'h0084c13f;
pd_rom[6887] = 32'h0084c123;
pd_rom[6888] = 32'h0099c03f;
pd_rom[6889] = 32'h009ac03f;
pd_rom[6890] = 32'h0093c13f;
pd_rom[6891] = 32'h0093c13f;
pd_rom[6892] = 32'h0093c13f;
pd_rom[6893] = 32'h0093c13f;
pd_rom[6894] = 32'h0093c13f;
pd_rom[6895] = 32'h0093c123;
pd_rom[6896] = 32'h00a8c03f;
pd_rom[6897] = 32'h00a9c03f;
pd_rom[6898] = 32'h00a2c13f;
pd_rom[6899] = 32'h00a2c13f;
pd_rom[6900] = 32'h00a2c13f;
pd_rom[6901] = 32'h00a2c13f;
pd_rom[6902] = 32'h00a2c13f;
pd_rom[6903] = 32'h00a2c123;
pd_rom[6904] = 32'h00b9813f;
pd_rom[6905] = 32'h00b9813f;
pd_rom[6906] = 32'h00b9813f;
pd_rom[6907] = 32'h00b9813f;
pd_rom[6908] = 32'h00b9813f;
pd_rom[6909] = 32'h00b9813f;
pd_rom[6910] = 32'h00b9813f;
pd_rom[6911] = 32'h00b9813f;
pd_rom[6912] = 32'h0083c13f;
pd_rom[6913] = 32'h0083c120;
pd_rom[6914] = 32'h0083c13f;
pd_rom[6915] = 32'h0083c13f;
pd_rom[6916] = 32'h0083c13f;
pd_rom[6917] = 32'h0083c13f;
pd_rom[6918] = 32'h0083c13f;
pd_rom[6919] = 32'h0083c13f;
pd_rom[6920] = 32'h0092c13f;
pd_rom[6921] = 32'h0092c13f;
pd_rom[6922] = 32'h0092c13f;
pd_rom[6923] = 32'h0092c13f;
pd_rom[6924] = 32'h0092c13f;
pd_rom[6925] = 32'h0092c13f;
pd_rom[6926] = 32'h0092c13f;
pd_rom[6927] = 32'h0092c13f;
pd_rom[6928] = 32'h00a1c13f;
pd_rom[6929] = 32'h00a1c13f;
pd_rom[6930] = 32'h00a1c13f;
pd_rom[6931] = 32'h00a1c13f;
pd_rom[6932] = 32'h00a1c13f;
pd_rom[6933] = 32'h00a1c13f;
pd_rom[6934] = 32'h00a1c13f;
pd_rom[6935] = 32'h00a1c13f;
pd_rom[6936] = 32'h00b8413f;
pd_rom[6937] = 32'h00b8413f;
pd_rom[6938] = 32'h00b8413f;
pd_rom[6939] = 32'h00b8413f;
pd_rom[6940] = 32'h00b8413f;
pd_rom[6941] = 32'h00b8413f;
pd_rom[6942] = 32'h00b8413f;
pd_rom[6943] = 32'h00b8413f;
pd_rom[6944] = 32'h008ac03f;
pd_rom[6945] = 32'h008bc03f;
pd_rom[6946] = 32'h0084c13f;
pd_rom[6947] = 32'h0084c13f;
pd_rom[6948] = 32'h0084c13f;
pd_rom[6949] = 32'h0084c13f;
pd_rom[6950] = 32'h0084c13f;
pd_rom[6951] = 32'h0084c123;
pd_rom[6952] = 32'h0099c03f;
pd_rom[6953] = 32'h009ac03f;
pd_rom[6954] = 32'h0093c13f;
pd_rom[6955] = 32'h0093c13f;
pd_rom[6956] = 32'h0093c13f;
pd_rom[6957] = 32'h0093c13f;
pd_rom[6958] = 32'h0093c13f;
pd_rom[6959] = 32'h0093c123;
pd_rom[6960] = 32'h00a8c03f;
pd_rom[6961] = 32'h00a9c03f;
pd_rom[6962] = 32'h00a2c13f;
pd_rom[6963] = 32'h00a2c13f;
pd_rom[6964] = 32'h00a2c13f;
pd_rom[6965] = 32'h00a2c13f;
pd_rom[6966] = 32'h00a2c13f;
pd_rom[6967] = 32'h00a2c123;
pd_rom[6968] = 32'h00b9813f;
pd_rom[6969] = 32'h00b9813f;
pd_rom[6970] = 32'h00b9813f;
pd_rom[6971] = 32'h00b9813f;
pd_rom[6972] = 32'h00b9813f;
pd_rom[6973] = 32'h00b9813f;
pd_rom[6974] = 32'h00b9813f;
pd_rom[6975] = 32'h00b9813f;
pd_rom[6976] = 32'h0083c13f;
pd_rom[6977] = 32'h0083c120;
pd_rom[6978] = 32'h0083c13f;
pd_rom[6979] = 32'h0083c13f;
pd_rom[6980] = 32'h0083c13f;
pd_rom[6981] = 32'h0083c13f;
pd_rom[6982] = 32'h0083c13f;
pd_rom[6983] = 32'h0083c13f;
pd_rom[6984] = 32'h0092c13f;
pd_rom[6985] = 32'h0092c13f;
pd_rom[6986] = 32'h0092c13f;
pd_rom[6987] = 32'h0092c13f;
pd_rom[6988] = 32'h0092c13f;
pd_rom[6989] = 32'h0092c13f;
pd_rom[6990] = 32'h0092c13f;
pd_rom[6991] = 32'h0092c13f;
pd_rom[6992] = 32'h00a1c13f;
pd_rom[6993] = 32'h00a1c13f;
pd_rom[6994] = 32'h00a1c13f;
pd_rom[6995] = 32'h00a1c13f;
pd_rom[6996] = 32'h00a1c13f;
pd_rom[6997] = 32'h00a1c13f;
pd_rom[6998] = 32'h00a1c13f;
pd_rom[6999] = 32'h00a1c13f;
pd_rom[7000] = 32'h00b8413f;
pd_rom[7001] = 32'h00b8413f;
pd_rom[7002] = 32'h00b8413f;
pd_rom[7003] = 32'h00b8413f;
pd_rom[7004] = 32'h00b8413f;
pd_rom[7005] = 32'h00b8413f;
pd_rom[7006] = 32'h00b8413f;
pd_rom[7007] = 32'h00b8413f;
pd_rom[7008] = 32'h008ac03f;
pd_rom[7009] = 32'h008bc03f;
pd_rom[7010] = 32'h0084c13f;
pd_rom[7011] = 32'h0084c13f;
pd_rom[7012] = 32'h0084c13f;
pd_rom[7013] = 32'h0084c13f;
pd_rom[7014] = 32'h0084c13f;
pd_rom[7015] = 32'h0084c123;
pd_rom[7016] = 32'h0099c03f;
pd_rom[7017] = 32'h009ac03f;
pd_rom[7018] = 32'h0093c13f;
pd_rom[7019] = 32'h0093c13f;
pd_rom[7020] = 32'h0093c13f;
pd_rom[7021] = 32'h0093c13f;
pd_rom[7022] = 32'h0093c13f;
pd_rom[7023] = 32'h0093c123;
pd_rom[7024] = 32'h00a8c03f;
pd_rom[7025] = 32'h00a9c03f;
pd_rom[7026] = 32'h00a2c13f;
pd_rom[7027] = 32'h00a2c13f;
pd_rom[7028] = 32'h00a2c13f;
pd_rom[7029] = 32'h00a2c13f;
pd_rom[7030] = 32'h00a2c13f;
pd_rom[7031] = 32'h00a2c123;
pd_rom[7032] = 32'h00b9813f;
pd_rom[7033] = 32'h00b9813f;
pd_rom[7034] = 32'h00b9813f;
pd_rom[7035] = 32'h00b9813f;
pd_rom[7036] = 32'h00b9813f;
pd_rom[7037] = 32'h00b9813f;
pd_rom[7038] = 32'h00b9813f;
pd_rom[7039] = 32'h00b9813f;
pd_rom[7040] = 32'h0083c13f;
pd_rom[7041] = 32'h0083c120;
pd_rom[7042] = 32'h0083c13f;
pd_rom[7043] = 32'h0083c13f;
pd_rom[7044] = 32'h0083c13f;
pd_rom[7045] = 32'h0083c13f;
pd_rom[7046] = 32'h0083c13f;
pd_rom[7047] = 32'h0083c13f;
pd_rom[7048] = 32'h0092c13f;
pd_rom[7049] = 32'h0092c13f;
pd_rom[7050] = 32'h0092c13f;
pd_rom[7051] = 32'h0092c13f;
pd_rom[7052] = 32'h0092c13f;
pd_rom[7053] = 32'h0092c13f;
pd_rom[7054] = 32'h0092c13f;
pd_rom[7055] = 32'h0092c13f;
pd_rom[7056] = 32'h00a1c13f;
pd_rom[7057] = 32'h00a1c13f;
pd_rom[7058] = 32'h00a1c13f;
pd_rom[7059] = 32'h00a1c13f;
pd_rom[7060] = 32'h00a1c13f;
pd_rom[7061] = 32'h00a1c13f;
pd_rom[7062] = 32'h00a1c13f;
pd_rom[7063] = 32'h00a1c13f;
pd_rom[7064] = 32'h00b8413f;
pd_rom[7065] = 32'h00b8413f;
pd_rom[7066] = 32'h00b8413f;
pd_rom[7067] = 32'h00b8413f;
pd_rom[7068] = 32'h00b8413f;
pd_rom[7069] = 32'h00b8413f;
pd_rom[7070] = 32'h00b8413f;
pd_rom[7071] = 32'h00b8413f;
pd_rom[7072] = 32'h008ac03f;
pd_rom[7073] = 32'h008bc03f;
pd_rom[7074] = 32'h0084c13f;
pd_rom[7075] = 32'h0084c13f;
pd_rom[7076] = 32'h0084c13f;
pd_rom[7077] = 32'h0084c13f;
pd_rom[7078] = 32'h0084c13f;
pd_rom[7079] = 32'h0084c123;
pd_rom[7080] = 32'h0099c03f;
pd_rom[7081] = 32'h009ac03f;
pd_rom[7082] = 32'h0093c13f;
pd_rom[7083] = 32'h0093c13f;
pd_rom[7084] = 32'h0093c13f;
pd_rom[7085] = 32'h0093c13f;
pd_rom[7086] = 32'h0093c13f;
pd_rom[7087] = 32'h0093c123;
pd_rom[7088] = 32'h00a8c03f;
pd_rom[7089] = 32'h00a9c03f;
pd_rom[7090] = 32'h00a2c13f;
pd_rom[7091] = 32'h00a2c13f;
pd_rom[7092] = 32'h00a2c13f;
pd_rom[7093] = 32'h00a2c13f;
pd_rom[7094] = 32'h00a2c13f;
pd_rom[7095] = 32'h00a2c123;
pd_rom[7096] = 32'h00b9813f;
pd_rom[7097] = 32'h00b9813f;
pd_rom[7098] = 32'h00b9813f;
pd_rom[7099] = 32'h00b9813f;
pd_rom[7100] = 32'h00b9813f;
pd_rom[7101] = 32'h00b9813f;
pd_rom[7102] = 32'h00b9813f;
pd_rom[7103] = 32'h00b9813f;
pd_rom[7104] = 32'h0083c13f;
pd_rom[7105] = 32'h0083c120;
pd_rom[7106] = 32'h0083c13f;
pd_rom[7107] = 32'h0083c13f;
pd_rom[7108] = 32'h0083c13f;
pd_rom[7109] = 32'h0083c13f;
pd_rom[7110] = 32'h0083c13f;
pd_rom[7111] = 32'h0083c13f;
pd_rom[7112] = 32'h0092c13f;
pd_rom[7113] = 32'h0092c13f;
pd_rom[7114] = 32'h0092c13f;
pd_rom[7115] = 32'h0092c13f;
pd_rom[7116] = 32'h0092c13f;
pd_rom[7117] = 32'h0092c13f;
pd_rom[7118] = 32'h0092c13f;
pd_rom[7119] = 32'h0092c13f;
pd_rom[7120] = 32'h00a1c13f;
pd_rom[7121] = 32'h00a1c13f;
pd_rom[7122] = 32'h00a1c13f;
pd_rom[7123] = 32'h00a1c13f;
pd_rom[7124] = 32'h00a1c13f;
pd_rom[7125] = 32'h00a1c13f;
pd_rom[7126] = 32'h00a1c13f;
pd_rom[7127] = 32'h00a1c13f;
pd_rom[7128] = 32'h00b8413f;
pd_rom[7129] = 32'h00b8413f;
pd_rom[7130] = 32'h00b8413f;
pd_rom[7131] = 32'h00b8413f;
pd_rom[7132] = 32'h00b8413f;
pd_rom[7133] = 32'h00b8413f;
pd_rom[7134] = 32'h00b8413f;
pd_rom[7135] = 32'h00b8413f;
pd_rom[7136] = 32'h008ac03f;
pd_rom[7137] = 32'h008bc03f;
pd_rom[7138] = 32'h0084c13f;
pd_rom[7139] = 32'h0084c13f;
pd_rom[7140] = 32'h0084c13f;
pd_rom[7141] = 32'h0084c13f;
pd_rom[7142] = 32'h0084c13f;
pd_rom[7143] = 32'h0084c123;
pd_rom[7144] = 32'h0099c03f;
pd_rom[7145] = 32'h009ac03f;
pd_rom[7146] = 32'h0093c13f;
pd_rom[7147] = 32'h0093c13f;
pd_rom[7148] = 32'h0093c13f;
pd_rom[7149] = 32'h0093c13f;
pd_rom[7150] = 32'h0093c13f;
pd_rom[7151] = 32'h0093c123;
pd_rom[7152] = 32'h00a8c03f;
pd_rom[7153] = 32'h00a9c03f;
pd_rom[7154] = 32'h00a2c13f;
pd_rom[7155] = 32'h00a2c13f;
pd_rom[7156] = 32'h00a2c13f;
pd_rom[7157] = 32'h00a2c13f;
pd_rom[7158] = 32'h00a2c13f;
pd_rom[7159] = 32'h00a2c123;
pd_rom[7160] = 32'h00b9813f;
pd_rom[7161] = 32'h00b9813f;
pd_rom[7162] = 32'h00b9813f;
pd_rom[7163] = 32'h00b9813f;
pd_rom[7164] = 32'h00b9813f;
pd_rom[7165] = 32'h00b9813f;
pd_rom[7166] = 32'h00b9813f;
pd_rom[7167] = 32'h00b9813f;
pd_rom[7168] = 32'h00bfc03f;
pd_rom[7169] = 32'h00c1c03f;
pd_rom[7170] = 32'h00c3c03f;
pd_rom[7171] = 32'h00c5c03f;
pd_rom[7172] = 32'h00bfc03f;
pd_rom[7173] = 32'h00c1c03f;
pd_rom[7174] = 32'h00c3c03f;
pd_rom[7175] = 32'h00c5c03f;
pd_rom[7176] = 32'h00c7c03f;
pd_rom[7177] = 32'h00c9c03f;
pd_rom[7178] = 32'h00cbc03f;
pd_rom[7179] = 32'h00cdc03f;
pd_rom[7180] = 32'h00c7c03f;
pd_rom[7181] = 32'h00c9c03f;
pd_rom[7182] = 32'h00cbc03f;
pd_rom[7183] = 32'h00cdc03f;
pd_rom[7184] = 32'h00cfc03f;
pd_rom[7185] = 32'h00d1c03f;
pd_rom[7186] = 32'h00d3c03f;
pd_rom[7187] = 32'h00d5c03f;
pd_rom[7188] = 32'h00cfc03f;
pd_rom[7189] = 32'h00d1c03f;
pd_rom[7190] = 32'h00d3c03f;
pd_rom[7191] = 32'h00d5c03f;
pd_rom[7192] = 32'h00d74120;
pd_rom[7193] = 32'h00d74120;
pd_rom[7194] = 32'h00d7413f;
pd_rom[7195] = 32'h00d7413f;
pd_rom[7196] = 32'h00d7413f;
pd_rom[7197] = 32'h00d7413f;
pd_rom[7198] = 32'h00d7413f;
pd_rom[7199] = 32'h00d74123;
pd_rom[7200] = 32'h00c0c03f;
pd_rom[7201] = 32'h00c2c03f;
pd_rom[7202] = 32'h00c4c03f;
pd_rom[7203] = 32'h00c6c03f;
pd_rom[7204] = 32'h00c0c03f;
pd_rom[7205] = 32'h00c2c03f;
pd_rom[7206] = 32'h00c4c03f;
pd_rom[7207] = 32'h00c6c03f;
pd_rom[7208] = 32'h00c8c03f;
pd_rom[7209] = 32'h00cac03f;
pd_rom[7210] = 32'h00ccc03f;
pd_rom[7211] = 32'h00cec03f;
pd_rom[7212] = 32'h00c8c03f;
pd_rom[7213] = 32'h00cac03f;
pd_rom[7214] = 32'h00ccc03f;
pd_rom[7215] = 32'h00cec03f;
pd_rom[7216] = 32'h00d0c03f;
pd_rom[7217] = 32'h00d2c03f;
pd_rom[7218] = 32'h00d4c03f;
pd_rom[7219] = 32'h00d6c03f;
pd_rom[7220] = 32'h00d0c03f;
pd_rom[7221] = 32'h00d2c03f;
pd_rom[7222] = 32'h00d4c03f;
pd_rom[7223] = 32'h00d6c03f;
pd_rom[7224] = 32'h00d84120;
pd_rom[7225] = 32'h00d84120;
pd_rom[7226] = 32'h00d8413f;
pd_rom[7227] = 32'h00d8413f;
pd_rom[7228] = 32'h00d8413f;
pd_rom[7229] = 32'h00d8413f;
pd_rom[7230] = 32'h00d8413f;
pd_rom[7231] = 32'h00d84123;
pd_rom[7232] = 32'h00bfc03f;
pd_rom[7233] = 32'h00c1c03f;
pd_rom[7234] = 32'h00c3c03f;
pd_rom[7235] = 32'h00c5c03f;
pd_rom[7236] = 32'h00bfc03f;
pd_rom[7237] = 32'h00c1c03f;
pd_rom[7238] = 32'h00c3c03f;
pd_rom[7239] = 32'h00c5c03f;
pd_rom[7240] = 32'h00c7c03f;
pd_rom[7241] = 32'h00c9c03f;
pd_rom[7242] = 32'h00cbc03f;
pd_rom[7243] = 32'h00cdc03f;
pd_rom[7244] = 32'h00c7c03f;
pd_rom[7245] = 32'h00c9c03f;
pd_rom[7246] = 32'h00cbc03f;
pd_rom[7247] = 32'h00cdc03f;
pd_rom[7248] = 32'h00cfc03f;
pd_rom[7249] = 32'h00d1c03f;
pd_rom[7250] = 32'h00d3c03f;
pd_rom[7251] = 32'h00d5c03f;
pd_rom[7252] = 32'h00cfc03f;
pd_rom[7253] = 32'h00d1c03f;
pd_rom[7254] = 32'h00d3c03f;
pd_rom[7255] = 32'h00d5c03f;
pd_rom[7256] = 32'h00d94120;
pd_rom[7257] = 32'h00d94120;
pd_rom[7258] = 32'h00d9413f;
pd_rom[7259] = 32'h00d9413f;
pd_rom[7260] = 32'h00d9413f;
pd_rom[7261] = 32'h00d9413f;
pd_rom[7262] = 32'h00d9413f;
pd_rom[7263] = 32'h00d94123;
pd_rom[7264] = 32'h00c0c03f;
pd_rom[7265] = 32'h00c2c03f;
pd_rom[7266] = 32'h00c4c03f;
pd_rom[7267] = 32'h00c6c03f;
pd_rom[7268] = 32'h00c0c03f;
pd_rom[7269] = 32'h00c2c03f;
pd_rom[7270] = 32'h00c4c03f;
pd_rom[7271] = 32'h00c6c03f;
pd_rom[7272] = 32'h00c8c03f;
pd_rom[7273] = 32'h00cac03f;
pd_rom[7274] = 32'h00ccc03f;
pd_rom[7275] = 32'h00cec03f;
pd_rom[7276] = 32'h00c8c03f;
pd_rom[7277] = 32'h00cac03f;
pd_rom[7278] = 32'h00ccc03f;
pd_rom[7279] = 32'h00cec03f;
pd_rom[7280] = 32'h00d0c03f;
pd_rom[7281] = 32'h00d2c03f;
pd_rom[7282] = 32'h00d4c03f;
pd_rom[7283] = 32'h00d6c03f;
pd_rom[7284] = 32'h00d0c03f;
pd_rom[7285] = 32'h00d2c03f;
pd_rom[7286] = 32'h00d4c03f;
pd_rom[7287] = 32'h00d6c03f;
pd_rom[7288] = 32'h00da4120;
pd_rom[7289] = 32'h00da4120;
pd_rom[7290] = 32'h00da413f;
pd_rom[7291] = 32'h00da413f;
pd_rom[7292] = 32'h00da413f;
pd_rom[7293] = 32'h00da413f;
pd_rom[7294] = 32'h00da413f;
pd_rom[7295] = 32'h00da4123;
pd_rom[7296] = 32'h00bfc03f;
pd_rom[7297] = 32'h00c1c03f;
pd_rom[7298] = 32'h00c3c03f;
pd_rom[7299] = 32'h00c5c03f;
pd_rom[7300] = 32'h00bfc03f;
pd_rom[7301] = 32'h00c1c03f;
pd_rom[7302] = 32'h00c3c03f;
pd_rom[7303] = 32'h00c5c03f;
pd_rom[7304] = 32'h00c7c03f;
pd_rom[7305] = 32'h00c9c03f;
pd_rom[7306] = 32'h00cbc03f;
pd_rom[7307] = 32'h00cdc03f;
pd_rom[7308] = 32'h00c7c03f;
pd_rom[7309] = 32'h00c9c03f;
pd_rom[7310] = 32'h00cbc03f;
pd_rom[7311] = 32'h00cdc03f;
pd_rom[7312] = 32'h00cfc03f;
pd_rom[7313] = 32'h00d1c03f;
pd_rom[7314] = 32'h00d3c03f;
pd_rom[7315] = 32'h00d5c03f;
pd_rom[7316] = 32'h00cfc03f;
pd_rom[7317] = 32'h00d1c03f;
pd_rom[7318] = 32'h00d3c03f;
pd_rom[7319] = 32'h00d5c03f;
pd_rom[7320] = 32'h00db4120;
pd_rom[7321] = 32'h00db4120;
pd_rom[7322] = 32'h00db413f;
pd_rom[7323] = 32'h00db413f;
pd_rom[7324] = 32'h00db413f;
pd_rom[7325] = 32'h00db413f;
pd_rom[7326] = 32'h00db413f;
pd_rom[7327] = 32'h00db4123;
pd_rom[7328] = 32'h00c0c03f;
pd_rom[7329] = 32'h00c2c03f;
pd_rom[7330] = 32'h00c4c03f;
pd_rom[7331] = 32'h00c6c03f;
pd_rom[7332] = 32'h00c0c03f;
pd_rom[7333] = 32'h00c2c03f;
pd_rom[7334] = 32'h00c4c03f;
pd_rom[7335] = 32'h00c6c03f;
pd_rom[7336] = 32'h00c8c03f;
pd_rom[7337] = 32'h00cac03f;
pd_rom[7338] = 32'h00ccc03f;
pd_rom[7339] = 32'h00cec03f;
pd_rom[7340] = 32'h00c8c03f;
pd_rom[7341] = 32'h00cac03f;
pd_rom[7342] = 32'h00ccc03f;
pd_rom[7343] = 32'h00cec03f;
pd_rom[7344] = 32'h00d0c03f;
pd_rom[7345] = 32'h00d2c03f;
pd_rom[7346] = 32'h00d4c03f;
pd_rom[7347] = 32'h00d6c03f;
pd_rom[7348] = 32'h00d0c03f;
pd_rom[7349] = 32'h00d2c03f;
pd_rom[7350] = 32'h00d4c03f;
pd_rom[7351] = 32'h00d6c03f;
pd_rom[7352] = 32'h00dc4120;
pd_rom[7353] = 32'h00dc4120;
pd_rom[7354] = 32'h00dc413f;
pd_rom[7355] = 32'h00dc413f;
pd_rom[7356] = 32'h00dc413f;
pd_rom[7357] = 32'h00dc413f;
pd_rom[7358] = 32'h00dc413f;
pd_rom[7359] = 32'h00dc4123;
pd_rom[7360] = 32'h00bfc03f;
pd_rom[7361] = 32'h00c1c03f;
pd_rom[7362] = 32'h00c3c03f;
pd_rom[7363] = 32'h00c5c03f;
pd_rom[7364] = 32'h00bfc03f;
pd_rom[7365] = 32'h00c1c03f;
pd_rom[7366] = 32'h00c3c03f;
pd_rom[7367] = 32'h00c5c03f;
pd_rom[7368] = 32'h00c7c03f;
pd_rom[7369] = 32'h00c9c03f;
pd_rom[7370] = 32'h00cbc03f;
pd_rom[7371] = 32'h00cdc03f;
pd_rom[7372] = 32'h00c7c03f;
pd_rom[7373] = 32'h00c9c03f;
pd_rom[7374] = 32'h00cbc03f;
pd_rom[7375] = 32'h00cdc03f;
pd_rom[7376] = 32'h00cfc03f;
pd_rom[7377] = 32'h00d1c03f;
pd_rom[7378] = 32'h00d3c03f;
pd_rom[7379] = 32'h00d5c03f;
pd_rom[7380] = 32'h00cfc03f;
pd_rom[7381] = 32'h00d1c03f;
pd_rom[7382] = 32'h00d3c03f;
pd_rom[7383] = 32'h00d5c03f;
pd_rom[7384] = 32'h00dd4120;
pd_rom[7385] = 32'h00dd4120;
pd_rom[7386] = 32'h00dd413f;
pd_rom[7387] = 32'h00dd413f;
pd_rom[7388] = 32'h00dd413f;
pd_rom[7389] = 32'h00dd413f;
pd_rom[7390] = 32'h00dd413f;
pd_rom[7391] = 32'h00dd4123;
pd_rom[7392] = 32'h00c0c03f;
pd_rom[7393] = 32'h00c2c03f;
pd_rom[7394] = 32'h00c4c03f;
pd_rom[7395] = 32'h00c6c03f;
pd_rom[7396] = 32'h00c0c03f;
pd_rom[7397] = 32'h00c2c03f;
pd_rom[7398] = 32'h00c4c03f;
pd_rom[7399] = 32'h00c6c03f;
pd_rom[7400] = 32'h00c8c03f;
pd_rom[7401] = 32'h00cac03f;
pd_rom[7402] = 32'h00ccc03f;
pd_rom[7403] = 32'h00cec03f;
pd_rom[7404] = 32'h00c8c03f;
pd_rom[7405] = 32'h00cac03f;
pd_rom[7406] = 32'h00ccc03f;
pd_rom[7407] = 32'h00cec03f;
pd_rom[7408] = 32'h00d0c03f;
pd_rom[7409] = 32'h00d2c03f;
pd_rom[7410] = 32'h00d4c03f;
pd_rom[7411] = 32'h00d6c03f;
pd_rom[7412] = 32'h00d0c03f;
pd_rom[7413] = 32'h00d2c03f;
pd_rom[7414] = 32'h00d4c03f;
pd_rom[7415] = 32'h00d6c03f;
pd_rom[7416] = 32'h00de4120;
pd_rom[7417] = 32'h00de4120;
pd_rom[7418] = 32'h00de413f;
pd_rom[7419] = 32'h00de413f;
pd_rom[7420] = 32'h00de413f;
pd_rom[7421] = 32'h00de413f;
pd_rom[7422] = 32'h00de413f;
pd_rom[7423] = 32'h00de4123;
pd_rom[7424] = 32'h00bfc03f;
pd_rom[7425] = 32'h00c1c03f;
pd_rom[7426] = 32'h00c3c03f;
pd_rom[7427] = 32'h00c5c03f;
pd_rom[7428] = 32'h00bfc03f;
pd_rom[7429] = 32'h00c1c03f;
pd_rom[7430] = 32'h00c3c03f;
pd_rom[7431] = 32'h00c5c03f;
pd_rom[7432] = 32'h00c7c03f;
pd_rom[7433] = 32'h00c9c03f;
pd_rom[7434] = 32'h00cbc03f;
pd_rom[7435] = 32'h00cdc03f;
pd_rom[7436] = 32'h00c7c03f;
pd_rom[7437] = 32'h00c9c03f;
pd_rom[7438] = 32'h00cbc03f;
pd_rom[7439] = 32'h00cdc03f;
pd_rom[7440] = 32'h00cfc03f;
pd_rom[7441] = 32'h00d1c03f;
pd_rom[7442] = 32'h00d3c03f;
pd_rom[7443] = 32'h00d5c03f;
pd_rom[7444] = 32'h00cfc03f;
pd_rom[7445] = 32'h00d1c03f;
pd_rom[7446] = 32'h00d3c03f;
pd_rom[7447] = 32'h00d5c03f;
pd_rom[7448] = 32'h00df913f;
pd_rom[7449] = 32'h00df9120;
pd_rom[7450] = 32'h00df913f;
pd_rom[7451] = 32'h00df9120;
pd_rom[7452] = 32'h00df9120;
pd_rom[7453] = 32'h00df913f;
pd_rom[7454] = 32'h00df913f;
pd_rom[7455] = 32'h00df912f;
pd_rom[7456] = 32'h00c0c03f;
pd_rom[7457] = 32'h00c2c03f;
pd_rom[7458] = 32'h00c4c03f;
pd_rom[7459] = 32'h00c6c03f;
pd_rom[7460] = 32'h00c0c03f;
pd_rom[7461] = 32'h00c2c03f;
pd_rom[7462] = 32'h00c4c03f;
pd_rom[7463] = 32'h00c6c03f;
pd_rom[7464] = 32'h00c8c03f;
pd_rom[7465] = 32'h00cac03f;
pd_rom[7466] = 32'h00ccc03f;
pd_rom[7467] = 32'h00cec03f;
pd_rom[7468] = 32'h00c8c03f;
pd_rom[7469] = 32'h00cac03f;
pd_rom[7470] = 32'h00ccc03f;
pd_rom[7471] = 32'h00cec03f;
pd_rom[7472] = 32'h00d0c03f;
pd_rom[7473] = 32'h00d2c03f;
pd_rom[7474] = 32'h00d4c03f;
pd_rom[7475] = 32'h00d6c03f;
pd_rom[7476] = 32'h00d0c03f;
pd_rom[7477] = 32'h00d2c03f;
pd_rom[7478] = 32'h00d4c03f;
pd_rom[7479] = 32'h00d6c03f;
pd_rom[7480] = 32'h00e0913f;
pd_rom[7481] = 32'h00e09120;
pd_rom[7482] = 32'h00e0913f;
pd_rom[7483] = 32'h00e09120;
pd_rom[7484] = 32'h00e09120;
pd_rom[7485] = 32'h00e0913f;
pd_rom[7486] = 32'h00e0913f;
pd_rom[7487] = 32'h00e0912f;
pd_rom[7488] = 32'h00bfc03f;
pd_rom[7489] = 32'h00c1c03f;
pd_rom[7490] = 32'h00c3c03f;
pd_rom[7491] = 32'h00c5c03f;
pd_rom[7492] = 32'h00bfc03f;
pd_rom[7493] = 32'h00c1c03f;
pd_rom[7494] = 32'h00c3c03f;
pd_rom[7495] = 32'h00c5c03f;
pd_rom[7496] = 32'h00c7c03f;
pd_rom[7497] = 32'h00c9c03f;
pd_rom[7498] = 32'h00cbc03f;
pd_rom[7499] = 32'h00cdc03f;
pd_rom[7500] = 32'h00c7c03f;
pd_rom[7501] = 32'h00c9c03f;
pd_rom[7502] = 32'h00cbc03f;
pd_rom[7503] = 32'h00cdc03f;
pd_rom[7504] = 32'h00cfc03f;
pd_rom[7505] = 32'h00d1c03f;
pd_rom[7506] = 32'h00d3c03f;
pd_rom[7507] = 32'h00d5c03f;
pd_rom[7508] = 32'h00cfc03f;
pd_rom[7509] = 32'h00d1c03f;
pd_rom[7510] = 32'h00d3c03f;
pd_rom[7511] = 32'h00d5c03f;
pd_rom[7512] = 32'h00e1913f;
pd_rom[7513] = 32'h00e19120;
pd_rom[7514] = 32'h00e1913f;
pd_rom[7515] = 32'h00e19120;
pd_rom[7516] = 32'h00e19120;
pd_rom[7517] = 32'h00e1913f;
pd_rom[7518] = 32'h00e1913f;
pd_rom[7519] = 32'h00e19123;
pd_rom[7520] = 32'h00c0c03f;
pd_rom[7521] = 32'h00c2c03f;
pd_rom[7522] = 32'h00c4c03f;
pd_rom[7523] = 32'h00c6c03f;
pd_rom[7524] = 32'h00c0c03f;
pd_rom[7525] = 32'h00c2c03f;
pd_rom[7526] = 32'h00c4c03f;
pd_rom[7527] = 32'h00c6c03f;
pd_rom[7528] = 32'h00c8c03f;
pd_rom[7529] = 32'h00cac03f;
pd_rom[7530] = 32'h00ccc03f;
pd_rom[7531] = 32'h00cec03f;
pd_rom[7532] = 32'h00c8c03f;
pd_rom[7533] = 32'h00cac03f;
pd_rom[7534] = 32'h00ccc03f;
pd_rom[7535] = 32'h00cec03f;
pd_rom[7536] = 32'h00d0c03f;
pd_rom[7537] = 32'h00d2c03f;
pd_rom[7538] = 32'h00d4c03f;
pd_rom[7539] = 32'h00d6c03f;
pd_rom[7540] = 32'h00d0c03f;
pd_rom[7541] = 32'h00d2c03f;
pd_rom[7542] = 32'h00d4c03f;
pd_rom[7543] = 32'h00d6c03f;
pd_rom[7544] = 32'h00e2913f;
pd_rom[7545] = 32'h00e29120;
pd_rom[7546] = 32'h00e2913f;
pd_rom[7547] = 32'h00e29120;
pd_rom[7548] = 32'h00e29120;
pd_rom[7549] = 32'h00e2913f;
pd_rom[7550] = 32'h00e2913f;
pd_rom[7551] = 32'h00e2912f;
pd_rom[7552] = 32'h00bfc03f;
pd_rom[7553] = 32'h00c1c03f;
pd_rom[7554] = 32'h00c3c03f;
pd_rom[7555] = 32'h00c5c03f;
pd_rom[7556] = 32'h00bfc03f;
pd_rom[7557] = 32'h00c1c03f;
pd_rom[7558] = 32'h00c3c03f;
pd_rom[7559] = 32'h00c5c03f;
pd_rom[7560] = 32'h00c7c03f;
pd_rom[7561] = 32'h00c9c03f;
pd_rom[7562] = 32'h00cbc03f;
pd_rom[7563] = 32'h00cdc03f;
pd_rom[7564] = 32'h00c7c03f;
pd_rom[7565] = 32'h00c9c03f;
pd_rom[7566] = 32'h00cbc03f;
pd_rom[7567] = 32'h00cdc03f;
pd_rom[7568] = 32'h00cfc03f;
pd_rom[7569] = 32'h00d1c03f;
pd_rom[7570] = 32'h00d3c03f;
pd_rom[7571] = 32'h00d5c03f;
pd_rom[7572] = 32'h00cfc03f;
pd_rom[7573] = 32'h00d1c03f;
pd_rom[7574] = 32'h00d3c03f;
pd_rom[7575] = 32'h00d5c03f;
pd_rom[7576] = 32'h00e3913f;
pd_rom[7577] = 32'h00e39120;
pd_rom[7578] = 32'h00e3913f;
pd_rom[7579] = 32'h00e39120;
pd_rom[7580] = 32'h00e39120;
pd_rom[7581] = 32'h00e3913f;
pd_rom[7582] = 32'h00e3913f;
pd_rom[7583] = 32'h00e39123;
pd_rom[7584] = 32'h00c0c03f;
pd_rom[7585] = 32'h00c2c03f;
pd_rom[7586] = 32'h00c4c03f;
pd_rom[7587] = 32'h00c6c03f;
pd_rom[7588] = 32'h00c0c03f;
pd_rom[7589] = 32'h00c2c03f;
pd_rom[7590] = 32'h00c4c03f;
pd_rom[7591] = 32'h00c6c03f;
pd_rom[7592] = 32'h00c8c03f;
pd_rom[7593] = 32'h00cac03f;
pd_rom[7594] = 32'h00ccc03f;
pd_rom[7595] = 32'h00cec03f;
pd_rom[7596] = 32'h00c8c03f;
pd_rom[7597] = 32'h00cac03f;
pd_rom[7598] = 32'h00ccc03f;
pd_rom[7599] = 32'h00cec03f;
pd_rom[7600] = 32'h00d0c03f;
pd_rom[7601] = 32'h00d2c03f;
pd_rom[7602] = 32'h00d4c03f;
pd_rom[7603] = 32'h00d6c03f;
pd_rom[7604] = 32'h00d0c03f;
pd_rom[7605] = 32'h00d2c03f;
pd_rom[7606] = 32'h00d4c03f;
pd_rom[7607] = 32'h00d6c03f;
pd_rom[7608] = 32'h00e4913f;
pd_rom[7609] = 32'h00e49120;
pd_rom[7610] = 32'h00e4913f;
pd_rom[7611] = 32'h00e49120;
pd_rom[7612] = 32'h00e49120;
pd_rom[7613] = 32'h00e4913f;
pd_rom[7614] = 32'h00e4913f;
pd_rom[7615] = 32'h00e4912f;
pd_rom[7616] = 32'h00bfc03f;
pd_rom[7617] = 32'h00c1c03f;
pd_rom[7618] = 32'h00c3c03f;
pd_rom[7619] = 32'h00c5c03f;
pd_rom[7620] = 32'h00bfc03f;
pd_rom[7621] = 32'h00c1c03f;
pd_rom[7622] = 32'h00c3c03f;
pd_rom[7623] = 32'h00c5c03f;
pd_rom[7624] = 32'h00c7c03f;
pd_rom[7625] = 32'h00c9c03f;
pd_rom[7626] = 32'h00cbc03f;
pd_rom[7627] = 32'h00cdc03f;
pd_rom[7628] = 32'h00c7c03f;
pd_rom[7629] = 32'h00c9c03f;
pd_rom[7630] = 32'h00cbc03f;
pd_rom[7631] = 32'h00cdc03f;
pd_rom[7632] = 32'h00cfc03f;
pd_rom[7633] = 32'h00d1c03f;
pd_rom[7634] = 32'h00d3c03f;
pd_rom[7635] = 32'h00d5c03f;
pd_rom[7636] = 32'h00cfc03f;
pd_rom[7637] = 32'h00d1c03f;
pd_rom[7638] = 32'h00d3c03f;
pd_rom[7639] = 32'h00d5c03f;
pd_rom[7640] = 32'h00e5913f;
pd_rom[7641] = 32'h00e59120;
pd_rom[7642] = 32'h00e5913f;
pd_rom[7643] = 32'h00e59120;
pd_rom[7644] = 32'h00e59120;
pd_rom[7645] = 32'h00e5913f;
pd_rom[7646] = 32'h00e5913f;
pd_rom[7647] = 32'h00e59123;
pd_rom[7648] = 32'h00c0c03f;
pd_rom[7649] = 32'h00c2c03f;
pd_rom[7650] = 32'h00c4c03f;
pd_rom[7651] = 32'h00c6c03f;
pd_rom[7652] = 32'h00c0c03f;
pd_rom[7653] = 32'h00c2c03f;
pd_rom[7654] = 32'h00c4c03f;
pd_rom[7655] = 32'h00c6c03f;
pd_rom[7656] = 32'h00c8c03f;
pd_rom[7657] = 32'h00cac03f;
pd_rom[7658] = 32'h00ccc03f;
pd_rom[7659] = 32'h00cec03f;
pd_rom[7660] = 32'h00c8c03f;
pd_rom[7661] = 32'h00cac03f;
pd_rom[7662] = 32'h00ccc03f;
pd_rom[7663] = 32'h00cec03f;
pd_rom[7664] = 32'h00d0c03f;
pd_rom[7665] = 32'h00d2c03f;
pd_rom[7666] = 32'h00d4c03f;
pd_rom[7667] = 32'h00d6c03f;
pd_rom[7668] = 32'h00d0c03f;
pd_rom[7669] = 32'h00d2c03f;
pd_rom[7670] = 32'h00d4c03f;
pd_rom[7671] = 32'h00d6c03f;
pd_rom[7672] = 32'h00e6913f;
pd_rom[7673] = 32'h00e69120;
pd_rom[7674] = 32'h00e6913f;
pd_rom[7675] = 32'h00e69120;
pd_rom[7676] = 32'h00e69120;
pd_rom[7677] = 32'h00e6913f;
pd_rom[7678] = 32'h00e6913f;
pd_rom[7679] = 32'h00e69123;
pd_rom[7744] = 32'h00e7917f;
pd_rom[7745] = 32'h00e7917f;
pd_rom[7746] = 32'h00e7917f;
pd_rom[7747] = 32'h00e7917f;
pd_rom[7748] = 32'h00e7917f;
pd_rom[7749] = 32'h00e7917f;
pd_rom[7750] = 32'h00e7917f;
pd_rom[7751] = 32'h00e7917f;
pd_rom[7752] = 32'h00e8113f;
pd_rom[7753] = 32'h00e9563f;
pd_rom[7754] = 32'h00e8113f;
pd_rom[7755] = 32'h00e8113f;
pd_rom[7756] = 32'h00e8113f;
pd_rom[7757] = 32'h00e8113f;
pd_rom[7758] = 32'h00e8113f;
pd_rom[7759] = 32'haee81123;
pd_rom[7760] = 32'h00ed8e3f;
pd_rom[7761] = 32'h00ed8e3f;
pd_rom[7762] = 32'h00ed8e3f;
pd_rom[7763] = 32'h00ed8e3f;
pd_rom[7764] = 32'h00ed8e3f;
pd_rom[7765] = 32'h00ed8e3f;
pd_rom[7766] = 32'h00ed8e3f;
pd_rom[7767] = 32'h00ed8e3f;
pd_rom[7768] = 32'h00ee8e3f;
pd_rom[7769] = 32'h00ee8e3f;
pd_rom[7770] = 32'h00ee8e3f;
pd_rom[7771] = 32'h00ee8e3f;
pd_rom[7772] = 32'h00ee8e3f;
pd_rom[7773] = 32'h00ee8e3f;
pd_rom[7774] = 32'h00ee8e3f;
pd_rom[7775] = 32'h00ee8e3f;
pd_rom[7776] = 32'h00ef8120;
pd_rom[7777] = 32'h00ef8120;
pd_rom[7778] = 32'h00ef813f;
pd_rom[7779] = 32'h00ef8120;
pd_rom[7780] = 32'h00ef813f;
pd_rom[7781] = 32'h00ef813f;
pd_rom[7782] = 32'h00ef813f;
pd_rom[7783] = 32'h00ef8123;
pd_rom[7784] = 32'h00f08120;
pd_rom[7785] = 32'h00f08120;
pd_rom[7786] = 32'h00f0813f;
pd_rom[7787] = 32'h00f0813f;
pd_rom[7788] = 32'h00f08120;
pd_rom[7789] = 32'h00f0813f;
pd_rom[7790] = 32'h00f0813f;
pd_rom[7791] = 32'h00f0812f;
pd_rom[7809] = 32'h00f1803f;
pd_rom[7810] = 32'h00f2803f;
pd_rom[7811] = 32'h00f3803f;
pd_rom[7813] = 32'h00f4803f;
pd_rom[7814] = 32'h00f5803f;
pd_rom[7815] = 32'h00f6803f;
pd_rom[7817] = 32'h00f7803f;
pd_rom[7818] = 32'h00f8803f;
pd_rom[7819] = 32'h00f9803f;
pd_rom[7821] = 32'h00fa803f;
pd_rom[7822] = 32'h00fb803f;
pd_rom[7823] = 32'h00fc803f;
pd_rom[7825] = 32'h00fd803f;
pd_rom[7826] = 32'h00fe803f;
pd_rom[7827] = 32'h00ff803f;
pd_rom[7829] = 32'h0100803f;
pd_rom[7830] = 32'h0101803f;
pd_rom[7831] = 32'h0102803f;
pd_rom[7833] = 32'h0103803f;
pd_rom[7834] = 32'h0104803f;
pd_rom[7835] = 32'h0105803f;
pd_rom[7837] = 32'h0106803f;
pd_rom[7838] = 32'h0107803f;
pd_rom[7839] = 32'h0108803f;
pd_rom[7840] = 32'h0109803f;
pd_rom[7841] = 32'h010a803f;
pd_rom[7842] = 32'h010b803f;
pd_rom[7843] = 32'h010c803f;
pd_rom[7849] = 32'h010d803f;
pd_rom[7853] = 32'h010e803f;
pd_rom[7872] = 32'h010f883f;
pd_rom[7873] = 32'h0110883f;
pd_rom[7874] = 32'h0111883f;
pd_rom[7875] = 32'h0112883f;
pd_rom[7876] = 32'h0113903f;
// ---- end of ap68040_pd_rom.svh ----
	end
	always_ff @(posedge clk) begin
		q0 <= pdw_t'(pd_rom[a0]);
		q1 <= pdw_t'(pd_rom[a1]);
	end
endmodule
// ---- ap68040_snoop.sv ----
//--------------------------------------------------------------------------//
// AP68040 - pipelined MC68040                                               //
//                                                                          //
// ap68040_snoop.sv - bus snooper (MC68040UM 4.4, 4.5, 4.7, 7.9)             //
//                                                                          //
// While another master owns the bus, every transfer it starts (TS) with   //
// TT = normal or MOVE16 and SC1/SC0 = 01 or 10 is snooped:                //
//                                                                          //
//   SC   read                               write                          //
//   01   dirty hit: inhibit memory, supply  byte/word/long dirty hit:      //
//        the data, line stays dirty         inhibit memory, sink the data //
//                                           into the line (stays dirty);  //
//                                           clean hit or line write:      //
//                                           invalidate, memory responds   //
//   10   dirty hit: inhibit memory, supply  any hit: invalidate, memory   //
//        the data, then invalidate; clean   responds                       //
//        hit: invalidate                                                   //
//                                                                          //
// The instruction cache drops a matching line for an SC = 10 read and     //
// for any snooped write (table 4-3).  SC = 00 and 11, and TT = 2 or 3,    //
// are not snooped.                                                        //
//                                                                          //
// MI (memory inhibit) is asserted whenever another master owns the bus,  //
// except while the memory is allowed to answer the current transfer: it  //
// is negated at once for a transfer that is not snooped, after the       //
// lookup when no intervention is needed, and never during an             //
// intervention, in which this unit is the slave (TA, and D31-D0 for a    //
// read; a line moves one long word per bus clock, A3:A2 wrapping).  MI   //
// is negated whenever we own the bus.  Terminations are counted only     //
// while MI is negated: four TAs for a line unless TBI ends the burst      //
// (the master then runs long-word transfers, each snooped), one TEA, or  //
// a retry.                                                                //
//                                                                          //
// Every output to the bus is a flip-flop that changes only on a bus clock //
// edge (bclk_en); inputs are sampled only then.  The cache lookup runs   //
// in processor clocks through the DMU's snoop port and the fetch unit's  //
// invalidation request.                                                   //
//--------------------------------------------------------------------------//

module ap68040_snoop
	import ap68040_pkg::*;
(
	input  logic        clk,
	input  logic        nreset,
	input  logic        bclk_en,
	input  logic        own,            // BIU: we are the bus master

	// the bus, as the alternate master drives it
	input  logic [31:0] a_i,
	input  logic        ts_n_i,
	input  logic        rw_n_i,
	input  logic  [1:0] siz_i,
	input  logic  [1:0] tt_i,
	input  logic  [1:0] sc,
	input  logic [31:0] d_i,
	input  logic        ta_n_i,
	input  logic        tea_n_i,
	input  logic        tbi_n_i,
	output logic        mi_n,
	output logic        ta_n_o,
	output logic        ta_oe,
	output logic [31:0] d_o,
	output logic        d_oe,

	// data cache: the DMU's snoop port
	output logic        dc_req,
	output logic [31:0] dc_pa,
	input  logic        dc_look,
	input  logic        dc_hit,
	input  logic        dc_dirty,
	input  logic [127:0] dc_line,
	output logic        dc_inv,
	output logic        dc_wr,
	output logic [15:0] dc_wbe,
	output logic [31:0] dc_wword,       // on every long word, dc_wbe picks

	// instruction cache: line invalidation in the fetch unit
	output logic        ic_req,
	output logic [31:0] ic_pa,
	output logic        ic_all,         // ... or every line (queue overflow)
	input  logic        ic_done
);

typedef enum logic [2:0] {
	S_IDLE,     // between transfers: MI asserted unless we own the bus
	S_LOOK,     // the data cache is being searched (MI asserted)
	S_MEMW,     // memory may answer: negate MI on the next bus clock
	S_MEM,      // memory answers: count its terminations
	S_SRC,      // intervention: supply the data
	S_SINK,     // intervention: take the data
	S_SINKW,    // the data was taken: write it into the line
	S_END       // TA driven negated one bus clock before it is released
} st_t;

st_t         st;
logic        mi_q;            // MI as driven while another master owns the bus
logic [31:0] s_a;             // the snooped transfer
logic        s_rd, s_line;
logic  [1:0] s_siz, s_sc;
logic  [1:0] beat;
logic [127:0] s_line_d;       // the line supplied by an intervention

// I-cache invalidations wait in a two-entry queue (the fetch unit may be
// busy with a line fill): ic_req/ic_pa/ic_all is the head, iq_* the
// second entry.  A line that does not fit turns the rest of the queue
// into one invalidation of the whole cache (more than the 68040 drops,
// never less).
logic        iq_v1, iq_all;
logic [27:0] iq_l1;

assign mi_n = own ? 1'b1 : mi_q;

// byte lanes selected by SIZ/A1/A0 (MC68040UM table 7-1)
function automatic logic [3:0] lanes(input logic [1:0] s, input logic [1:0] a10);
	case (s)
		SIZ_B:   lanes = 4'b1000 >> a10;
		SIZ_W:   lanes = a10[1] ? 4'b0011 : 4'b1100;
		default: lanes = 4'b1111;
	endcase
endfunction

function automatic logic [31:0] line_word(input logic [127:0] l, input logic [1:0] k);
	line_word = l[127 - 32 * k -: 32];
endfunction

// a transfer starting on this bus clock edge
wire ts_alt  = !own && !ts_n_i;
wire snoopen = (tt_i == TT_NORMAL || tt_i == TT_MOVE16) && (sc == 2'b01 || sc == 2'b10);

always_ff @(posedge clk) begin
	dc_inv <= 1'b0;
	dc_wr  <= 1'b0;
	if (!nreset) begin
		st      <= S_IDLE;
		mi_q    <= 1'b0;          // asserted during and after reset (7.9.1)
		ta_n_o  <= 1'b1;
		ta_oe   <= 1'b0;
		d_o     <= '0;
		d_oe    <= 1'b0;
		s_a     <= '0;
		s_rd    <= 1'b0;
		s_line  <= 1'b0;
		s_siz   <= '0;
		s_sc    <= '0;
		beat    <= '0;
		s_line_d <= '0;
		dc_req  <= 1'b0;
		dc_pa   <= '0;
		dc_wbe  <= '0;
		dc_wword <= '0;
		ic_req  <= 1'b0;
		ic_pa   <= '0;
		ic_all  <= 1'b0;
		iq_v1   <= 1'b0;
		iq_all  <= 1'b0;
		iq_l1   <= '0;
	end
	else begin
		logic start;
		start = 1'b0;

		case (st)
		S_IDLE: begin
			if (bclk_en) begin
				mi_q  <= 1'b0;
				start = ts_alt;
			end
		end

		S_LOOK: begin
			if (dc_look) begin
				logic src, sink, inv;
				src  = s_rd && dc_hit && dc_dirty;
				sink = !s_rd && !s_line && s_sc == 2'b01 && dc_hit && dc_dirty;
				inv  = dc_hit && (s_rd ? (s_sc == 2'b10) : !sink);
				dc_inv   <= inv;
				s_line_d <= dc_line;
				if (sink) st <= S_SINK;          // keeps the cache until written
				else begin
					dc_req <= 1'b0;
					st     <= src ? S_SRC : S_MEMW;
				end
			end
		end

		S_MEMW: begin
			if (bclk_en) begin
				mi_q <= 1'b1;
				beat <= 2'd0;
				st   <= S_MEM;
			end
		end

		S_MEM: begin
			if (bclk_en) begin
				if (!tea_n_i || (!ta_n_i && (!s_line || beat == 2'd3 ||
				                            (beat == 2'd0 && !tbi_n_i)))) begin
					// TEA, retry, the last beat, or a burst-inhibited line
					// (its long words come as transfers of their own)
					mi_q  <= 1'b0;
					st    <= S_IDLE;
					start = ts_alt;
				end
				else if (!ta_n_i) beat <= beat + 2'd1;
			end
		end

		S_SRC: begin
			if (bclk_en) begin
				if (!ta_oe) begin
					// first beat: drive TA with the long word at A3:A2
					ta_oe  <= 1'b1;
					ta_n_o <= 1'b0;
					d_oe   <= 1'b1;
					d_o    <= line_word(s_line_d, s_a[3:2]);
					beat   <= 2'd0;
				end
				else if (!s_line || beat == 2'd3) begin
					ta_n_o <= 1'b1;
					d_oe   <= 1'b0;
					st     <= S_END;
				end
				else begin
					beat <= beat + 2'd1;
					d_o  <= line_word(s_line_d, s_a[3:2] + beat + 2'd1);
				end
			end
		end

		S_SINK: begin
			if (bclk_en) begin
				ta_oe  <= 1'b1;
				ta_n_o <= 1'b0;
				st     <= S_SINKW;
			end
		end

		S_SINKW: begin
			if (bclk_en) begin
				// the master sees TA on this edge, with its data on the bus
				logic [3:0] be;
				be = lanes(s_siz, s_a[1:0]);
				dc_wbe   <= {12'd0, be} << (4 * (2'd3 - s_a[3:2]));
				dc_wword <= d_i;
				dc_wr    <= 1'b1;
				dc_req   <= 1'b0;
				ta_n_o   <= 1'b1;
				st       <= S_END;
			end
		end

		S_END: begin
			if (bclk_en) begin
				ta_oe <= 1'b0;
				st    <= S_IDLE;
				start = ts_alt;
			end
		end

		default: st <= S_IDLE;
		endcase

		// a snooped transfer begins: latch it, ask the caches
		if (start) begin
			s_a    <= a_i;
			s_rd   <= rw_n_i;
			s_line <= (siz_i == SIZ_LINE);
			s_siz  <= siz_i;
			s_sc   <= sc;
			beat   <= 2'd0;
			if (snoopen) begin
				dc_req <= 1'b1;
				dc_pa  <= a_i;
				st     <= S_LOOK;
			end
			else begin
				mi_q <= 1'b1;            // not snooped: memory answers at once
				st   <= S_MEM;
			end
		end

		// the instruction cache: an invalidating read, or any write
		begin
			logic        v0, a0, v1, ov, push;
			logic [27:0] l0, l1, nl;
			v0 = ic_req; a0 = ic_all; l0 = ic_pa[31:4];
			v1 = iq_v1;  ov = iq_all; l1 = iq_l1;
			nl = a_i[31:4];
			push = start && snoopen && (!rw_n_i || sc == 2'b10);
			if (ic_done) begin
				// the head is done: the second entry moves up
				v0 = v1 || ov; a0 = ov; l0 = l1;
				v1 = 1'b0; ov = 1'b0;
			end
			if (push) begin
				if (!v0) begin v0 = 1'b1; a0 = 1'b0; l0 = nl; end
				else if (a0 || l0 == nl || ov || (v1 && l1 == nl)) ;   // covered
				else if (!v1) begin v1 = 1'b1; l1 = nl; end
				else ov = 1'b1;
			end
			ic_req <= v0; ic_all <= a0; ic_pa <= {l0, 4'd0};
			iq_v1  <= v1; iq_all <= ov; iq_l1 <= l1;
		end
	end
end

endmodule
// ---- ap68040_useq.sv ----
//--------------------------------------------------------------------------//
// AP68040 - pipelined MC68040                                            //
//                                                                          //
// ap68040_useq.sv - D2: micro-sequencer                                     //
//                                                                          //
// Turns a decoded instruction into uops by walking its microcode routine   //
// (rtl/gen/ap68040_ucode_rom.svh), one uop per cycle:                       //
//   * symbolic operands (EA0, DX, IMM, ...) become registers, immediates   //
//     or the uop's own memory access; A7 maps to USP/ISP/MSP by S and M    //
//   * an EA with memory indirection gets a pointer load (into T13 for EA0, //
//     T12 for EA1) before the uop that uses it                             //
//   * a source (An)+/-(An) update marked noupd is deferred into the uop    //
//     flagged upd2 (merged when both EAs use the same register), so an     //
//     instruction that faults on its second access restarts cleanly        //
//   * the back end's exception entry starts an exception routine           //
//--------------------------------------------------------------------------//

module ap68040_useq
	import ap68040_pkg::*, ap68040_upkg::*;
(
	input  logic        clk,
	input  logic        nreset,
	input  logic        flush,

	// record FIFO from D1
	input  logic  [1:0] rq_n,
	input  dinst_t      rq0,
	input  dinst_t      rq1,
	output logic        rq_pop,
	output logic        rq_pop_e,   // an early form: implies rq_pop (D1's room)

	input  logic        smode,
	input  logic        master,     // M bit

	input  logic        exc_go,
	input  logic        exc_pend,   // the back end prepares an exception entry: issue nothing
	input  logic  [3:0] exc_kind,
	input  logic  [4:0] exc_ssp,

	// uop FIFO towards the back end: uq0 is the head
	output logic  [1:0] uq_n,
	output uop_t        uq0,
	input  logic        uq_pop      // the back end takes uq0 this cycle
);



//--------------------------------------------------------------------------
// state
//--------------------------------------------------------------------------
logic  [9:0] upc;               // address of uw_q
uword_t      uw_q;              // microcode word at upc (the ROM's output)
logic        uw_v;              // uw_q is valid for the current instruction
logic        exc_mode;          // running an exception routine
logic        first;
logic        ind0, ind1;        // pointer of EA0 / EA1 already loaded
logic        def_v;             // a deferred source update is pending
logic  [4:0] def_reg;
logic  [7:0] def_amt;
logic  [4:0] ssp;
// MOVEM loop
logic        mv_act;            // the loop has started for this instruction
logic [15:0] mv_mask;           // registers still to transfer
logic [31:0] mv_off;            // address offset of the next transfer
logic  [7:0] mv_cnt;            // bytes transferred so far
logic        mv_t11;            // the address is in T11 (base register in the list)
logic  [1:0] mv_fix;            // fix-up uops emitted after the last transfer

// the instruction being sequenced: the D1 FIFO head, or nothing for an
// exception routine
dinst_t      src;
always_comb src = exc_mode ? '0 : rq0;
logic        src_first;
assign src_first = first;

uword_t      uw;
assign uw = uw_q;

// uop FIFO
uop_t        uq1;
wire         room_out = (uq_n != 2'd2);

//--------------------------------------------------------------------------
// register naming
//--------------------------------------------------------------------------
wire [4:0] sp_reg = !smode ? R_USP : (master ? R_MSP : R_ISP);

function automatic logic [4:0] areg(input logic [2:0] n, input logic [4:0] spr);
	areg = (n == 3'd7) ? spr : (R_A0 + {2'b00, n});
endfunction

function automatic logic [4:0] dreg(input logic [2:0] n);
	dreg = {2'b00, n};
endfunction

function automatic logic is_mem(input logic [3:0] m);
	is_mem = (m >= EM_AI) && (m != EM_IMM) && (m != EM_NONE);
endfunction

function automatic logic is_reg(input logic [3:0] m);
	is_reg = (m == EM_DN) || (m == EM_AN);
endfunction

// minus a small amount: the low bits negated, the rest the sign -- no
// 32-bit carry chain after the sequencer's selects
function automatic logic [31:0] neg5(input logic [4:0] x);
	neg5 = {{27{x != 5'd0}}, 5'd0 - x};
endfunction
function automatic logic [31:0] neg7(input logic [6:0] x);
	neg7 = {{25{x != 7'd0}}, 7'd0 - x};
endfunction

function automatic logic [4:0] size_bytes(input logic [1:0] s, input logic is_sp);
	case (s)
		SZ_B:    size_bytes = is_sp ? 5'd2 : 5'd1;
		SZ_W:    size_bytes = 5'd2;
		SZ_L:    size_bytes = 5'd4;
		default: size_bytes = 5'd16;      // line (MOVE16)
	endcase
endfunction

//--------------------------------------------------------------------------
// one uop from (uw, src)
//--------------------------------------------------------------------------
typedef struct packed {
	logic        v;          // operand present
	logic  [1:0] src;
	logic  [4:0] r;
	logic        imm_v;
	logic [31:0] imm;
	logic        mem;        // the operand is this uop's memory EA
	logic        ea1;        // ... and it is EA1
} opsel_t;

uop_t        nu;
logic        n_ptr;          // nu is a pointer load (memory indirect)
logic        n_ptr_ea1;
logic        n_jump;         // pure jump micro-instruction
logic  [9:0] n_jt;
logic        n_mv_pre;       // nu is the MOVEM address copy into T11
logic [15:0] n_mv_rest;      // mask after this transfer
logic        n_def_set;      // nu defers its source update
logic  [4:0] n_def_reg;
logic  [7:0] n_def_amt;

// FPU operand bytes for AG modes FEA / FUPD: opclass 010/011 by format (a
// byte through A7 moves it by two), FMOVE(M) of control registers four per
// register; the other FPU instructions move their address register by a
// run-time amount (ADDT0)
logic [6:0] fp_size;
always_comb begin
	logic [2:0] crl;
	crl = (src.ext1[12:10] == 3'd0) ? 3'b001 : src.ext1[12:10];
	case (src.ext1[15:13])
		3'b010, 3'b011: case (src.ext1[12:10])
			3'd0, 3'd1: fp_size = 7'd4;
			3'd4:       fp_size = 7'd2;
			3'd6:       fp_size = (src.ea0.r == 3'd7) ? 7'd2 : 7'd1;
			3'd5:       fp_size = 7'd8;
			default:    fp_size = 7'd12;
		endcase
		3'b100, 3'b101: fp_size = {3'd0, 2'(crl[0]) + 2'(crl[1]) + 2'(crl[2]), 2'b00};
		default: fp_size = 7'd0;
	endcase
end

logic        dbg_dm;             // (simulation: the merge and the
logic [31:0] dbg_dpre;           // displacement it was formed for;
logic        dbg_mvd;            // a MOVEM offset for AG, and the offset)
logic [31:0] dbg_mvo;
always_comb begin
	opsel_t oa, ob, od;
	ea_t    me;              // the uop's memory EA
	logic   me_v, me_ea1;
	logic [31:0] disp_pre;       // the uop's displacement before a deferred-update merge
	logic        dmerge;         // ... which applies (see the upd2 block)
	logic [1:0] osz, msz;
	logic [2:0] mszf;
	logic [4:0] amt;
	logic       me_sp;
	logic [31:0] q, shc;
	logic [6:0] op;
	logic [3:0] cnd;
	logic       jc_true;
	logic [31:0] dval;
	logic [31:0] pcx;

	nu        = '0;
	dbg_mvo   = '0;
	n_ptr     = 1'b0;
	n_ptr_ea1 = 1'b0;
	n_jump    = 1'b0;
	n_jt      = uw.jt;
	n_def_set = 1'b0;
	n_def_reg = '0;
	n_def_amt = '0;
	n_mv_pre  = 1'b0;
	n_mv_rest = '0;

	osz = (uw.sz  == 2'd0) ? src.sz : (uw.sz  - 2'd1);
	mszf = (uw.msz == 3'd0) ? {1'b0, src.sz} : (uw.msz - 3'd1);
	msz  = mszf[1:0];
	q   = (src.opw[11:9] == 3'd0) ? 32'd8 : {29'd0, src.opw[11:9]};

	// pure jump words (a routine's first jump is resolved in D1)
	case (uw.jc)
		JC_NEVER:    jc_true = 1'b0;
		JC_ALWAYS:   jc_true = 1'b1;
		JC_EXT10:    jc_true = src.ext1[10];
		JC_EXT11:    jc_true = src.ext1[11];
		JC_EA0_MEM:  jc_true = is_mem(src.ea0.m);
		JC_EA0_DN:   jc_true = (src.ea0.m == EM_DN);
		JC_EA0_IMM:  jc_true = (src.ea0.m == EM_IMM);
		JC_SZ_L:     jc_true = (src.sz == SZ_L);
		JC_AY7:      jc_true = (src.opw[2:0] == 3'd7);
		JC_SUPER:    jc_true = smode;
		JC_MASK0:    jc_true = (src.ext1 == 16'd0);
		JC_FP_OC0:   jc_true = (src.ext1[15:13] == 3'b000);
		JC_FP_OC2:   jc_true = (src.ext1[15:13] == 3'b010);
		JC_FP_OC3:   jc_true = (src.ext1[15:13] == 3'b011);
		JC_FP_OC45:  jc_true = (src.ext1[15:14] == 2'b10);
		JC_FP_OC67:  jc_true = (src.ext1[15:14] == 2'b11);
		JC_FMT_1:    jc_true = (src.ext1[12:10] == 3'd6);
		JC_FMT_2:    jc_true = (src.ext1[12:10] == 3'd4);
		JC_FMT_8:    jc_true = (src.ext1[12:10] == 3'd5);
		JC_FMT_12:   jc_true = (src.ext1[12:10] == 3'd2 || src.ext1[12:10] == 3'd3);
		JC_FMT_7:    jc_true = (src.ext1[12:10] == 3'd7);
		JC_EA0_APD:  jc_true = (src.ea0.m == EM_APD);
		JC_EA0_AIP:  jc_true = (src.ea0.m == EM_AIP);
		JC_EXT13:    jc_true = src.ext1[13];
		default:     jc_true = 1'b0;
	endcase
	// a micro-instruction with a jump condition is a pure jump
	n_jump = (uw.jc != JC_NEVER);

	//----------------------------------------------------------------------
	// operand selectors
	//----------------------------------------------------------------------
	for (int k = 0; k < 3; k++) begin
		logic [5:0] s;
		opsel_t o;
		s = (k == 0) ? uw.a : (k == 1) ? uw.b : uw.d;
		o = '0;
		o.v = (s != S_NONE);
		o.src = OS_REG;
		if (s >= 6'd40) o.r = 5'(s - 6'd25);
		else case (s)
			S_EA0, S_EA0R, S_EA1, S_EA1R: begin
				ea_t e;
				e = (s == S_EA0 || s == S_EA0R) ? src.ea0 : src.ea1;
				if (e.m == EM_DN) o.r = dreg(e.r);
				else if (e.m == EM_AN) o.r = areg(e.r, sp_reg);
				else if (e.m == EM_IMM) begin
					o.src = OS_IMM; o.imm_v = 1'b1; o.imm = e.bd;
				end
				else if (s == S_EA0R || s == S_EA1R) o.v = 1'b0;
				else begin
					o.src = OS_MEM; o.mem = 1'b1; o.ea1 = (s == S_EA1);
				end
			end
			S_DX:    o.r = dreg(src.opw[11:9]);
			S_DY:    o.r = dreg(src.opw[2:0]);
			S_AX:    o.r = areg(src.opw[11:9], sp_reg);
			S_AY:    o.r = areg(src.opw[2:0], sp_reg);
			S_SP:    o.r = sp_reg;
			S_SSP:   o.r = ssp;
			S_X1R:   o.r = src.ext1[15] ? areg(src.ext1[14:12], sp_reg) : dreg(src.ext1[14:12]);
			S_X1DL:  o.r = dreg(src.ext1[14:12]);
			S_X1DH:  o.r = dreg(src.ext1[2:0]);
			S_X1DU:  o.r = dreg(src.ext1[8:6]);
			S_X2DC:  o.r = dreg(src.ext2[2:0]);
			S_X2DU:  o.r = dreg(src.ext2[8:6]);
			S_X2R:   o.r = src.ext2[15] ? areg(src.ext2[14:12], sp_reg) : dreg(src.ext2[14:12]);
			S_IMM:   begin o.src = OS_IMM; o.imm_v = 1'b1; o.imm = src.imm; end
			S_QUICK: begin o.src = OS_IMM; o.imm_v = 1'b1; o.imm = q; end
			S_MOVEQ: begin o.src = OS_IMM; o.imm_v = 1'b1; o.imm = {{24{src.opw[7]}}, src.opw[7:0]}; end
			S_SHCNT: begin
				if (src.opw[5]) o.r = dreg(src.opw[11:9]);
				else begin o.src = OS_IMM; o.imm_v = 1'b1; o.imm = q; end
			end
			S_NPC:   begin o.src = OS_IMM; o.imm_v = 1'b1; o.imm = src.pc + {27'd0, src.ilen, 1'b0}; end
			S_PC:    begin o.src = OS_IMM; o.imm_v = 1'b1; o.imm = src.pc; end
			S_CONST: begin o.src = OS_IMM; o.imm_v = 1'b1; o.imm = {{16{uw.cval[15]}}, uw.cval}; end
			S_ZERO:  o.src = OS_ZERO;
			S_LD:    o.src = OS_MEM;
			// MOVEC register number, as the special register selector:
			// $000-$008 -> $00-$08, $800-$808 -> $10-$18
			S_CREG:  begin o.src = OS_IMM; o.imm_v = 1'b1; o.imm = {27'd0, src.ext1[11], src.ext1[3:0]}; end
			S_BFO: begin
				if (src.ext1[11]) o.r = dreg(src.ext1[8:6]);
				else begin o.src = OS_IMM; o.imm_v = 1'b1; o.imm = {27'd0, src.ext1[10:6]}; end
			end
			S_BFW: begin
				if (src.ext1[5]) o.r = dreg(src.ext1[2:0]);
				else begin o.src = OS_IMM; o.imm_v = 1'b1; o.imm = {27'd0, src.ext1[4:0]}; end
			end
			S_OPW:   begin o.src = OS_IMM; o.imm_v = 1'b1; o.imm = {16'd0, src.opw}; end
			S_EXT1:  begin o.src = OS_IMM; o.imm_v = 1'b1; o.imm = {16'd0, src.ext1}; end
			S_FPDL:  o.r = dreg(src.ext1[6:4]);      // FMOVEM dynamic list register
			S_CREGR: o.r = (src.ext1[2:0] == 3'd0) ? R_USP : (src.ext1[2:0] == 3'd3) ? R_MSP : R_ISP;
			default: o.v = 1'b0;
		endcase
		if (k == 0) oa = o; else if (k == 1) ob = o; else od = o;
	end

	//----------------------------------------------------------------------
	// operation fields
	//----------------------------------------------------------------------
	op  = uw.op_inst ? src.eop : uw.op;
	case (uw.cond_inst)
		3'd1:    cnd = src.opw[11:8];
		3'd2:    cnd = src.econd;
		3'd3:    cnd = {2'b00, src.ext1[10], src.ext1[11]};
		3'd4:    cnd = {1'b0, src.opw[10:8]};     // bit field, register
		3'd5:    cnd = {1'b1, src.opw[10:8]};     // bit field, memory
		3'd6:    cnd = {2'b00, !src.ext1[15], src.ext1[11]};  // CHK2/CMP2
		default: cnd = uw.cond;
	endcase
	nu.op     = op;
	nu.sz     = osz;
	nu.msz    = msz;
	nu.cond   = cnd;
	nu.ccr_we = uw.ccr_inst ? src.ccr : uw.ccr;
	nu.a_src  = oa.v ? oa.src : OS_ZERO;
	nu.a_reg  = oa.r;
	nu.a_sxw  = (uw.sxw == 2'd1) || (uw.sxw == 2'd2 && src.sz == SZ_W);
	nu.b_src  = ob.v ? ob.src : OS_ZERO;
	nu.b_reg  = ob.r;
	nu.imm    = oa.imm_v ? oa.imm : {{16{uw.cval[15]}}, uw.cval};
	nu.imm_b  = {ob.imm[31], ob.imm[15:0]};   // (never a full immediate: 16 bits and the sign)
	nu.mfc    = (uw.mfc == MFC_EAP) ? MFC_NORM : uw.mfc;
	nu.dyn    = uw.dyn;
	nu.dynk   = uw.dynk;
	nu.mlock  = uw.lock;
	nu.mlocke = uw.locke;
	nu.mwi    = uw.wi;
	nu.br     = uw.br;
	nu.target = src.target;
	nu.pred   = src.pred && (uw.br != BR_NONE);
	nu.bst    = src.bst;
	nu.bhc    = src.bhc;
	nu.ser    = uw.ser;
	// FMOVEM / FMOVE of control registers to memory are T0 trace points
	// FMOVEM / FMOVE of control registers to memory are T0 trace points
	nu.t0cof  = src.t0 || (src.opw[15:6] == 10'b1111_0010_00 &&
	                       (src.ext1[15:13] == 3'b101 || src.ext1[15:13] == 3'b111));
	nu.pc     = src.pc;
	nu.ilen   = src.ilen;
	nu.ras    = src.ras;
	nu.exr     = exc_mode;
	nu.first  = src_first;
	nu.last   = uw.last;
	nu.exc    = (src.exc != 8'd0) ? src.exc : 8'd0;

	// destination
	if (od.v && od.src == OS_REG) begin
		nu.d_v   = 1'b1;
		nu.d_reg = od.r;
	end

	//----------------------------------------------------------------------
	// memory access and address generation
	//----------------------------------------------------------------------
	me_v   = oa.mem || ob.mem || od.mem;
	me_ea1 = oa.mem ? oa.ea1 : ob.mem ? ob.ea1 : od.ea1;
	me     = me_ea1 ? src.ea1 : src.ea0;
	if (uw.ag == AGM_EA0 || uw.ag == AGM_LEA0 || uw.ag == AGM_FEA) begin me = src.ea0; me_ea1 = 1'b0; end
	if (uw.ag == AGM_EA1) begin me = src.ea1; me_ea1 = 1'b1; end
	me_sp  = (me.r == 3'd7);
	amt    = size_bytes(msz, me_sp && (me.m == EM_AIP || me.m == EM_APD));

	if (uw.mem != 2'd0)
		nu.mem = uw.mem;
	else if (uw.a == S_LD || uw.b == S_LD)
		nu.mem = M_LD;
	else if (me_v) begin
		if ((ob.mem || oa.mem) && od.mem) nu.mem = M_RMW;
		else if (od.mem)                  nu.mem = M_ST;
		else                              nu.mem = M_LD;
	end


	if (me_v || uw.ag == AGM_EA0 || uw.ag == AGM_EA1 || uw.ag == AGM_LEA0 ||
	    (uw.ag == AGM_FEA && src.ea0.m != EM_IMM)) begin
		logic [4:0] bre;
		logic       mi_stage1;
		nu.ag = 1'b1;
		bre   = areg(me.r, sp_reg);
		mi_stage1 = (me.mi != 2'd0) && !(me_ea1 ? ind1 : ind0);
		case (me.m)
			EM_AI: begin nu.base_v = 1'b1; nu.base = bre; end
			EM_AIP: begin
				nu.base_v = 1'b1; nu.base = bre;
				nu.pinc = 1'b1; nu.upd_v = 1'b1; nu.upd_reg = bre;
				nu.upd_amt = {3'd0, amt};
			end
			EM_APD: begin
				nu.base_v = 1'b1; nu.base = bre;
				nu.disp = neg5(amt);
				nu.upd_v = 1'b1; nu.upd_reg = bre;
			end
			EM_AD16: begin nu.base_v = 1'b1; nu.base = bre; nu.disp = me.bd; end
			EM_ABSW, EM_ABSL: nu.disp = me.bd;
			EM_PC16: begin nu.disp = me.bd; nu.mprog = 1'b1; end   // D1 added the PC
			EM_AX, EM_PCX: begin
				logic [4:0] xr;
				xr = me.xa ? areg(me.xr, sp_reg) : dreg(me.xr);
				if (me.mi == 2'd0 || mi_stage1) begin
					// address (or the pointer address) from base/index/bd
					if (me.m == EM_AX) begin nu.base_v = !me.bs; nu.base = bre; nu.disp = me.bd; end
					else begin nu.disp = me.bd; nu.mprog = !me.bs; end   // D1 added the PC
					nu.idx_v = !me.is && (me.mi != 2'd2);
					nu.idx   = xr;
					nu.idx_l = me.xl;
					nu.scale = me.sc;
				end
				else begin
					// through the pointer: T13 (EA0) / T12 (EA1) + index + od
					nu.base_v = 1'b1;
					nu.base   = me_ea1 ? (R_T0 + 5'd12) : (R_T0 + 5'd13);
					nu.disp   = me.od;
					nu.idx_v  = !me.is && (me.mi == 2'd2);
					nu.idx    = xr;
					nu.idx_l  = me.xl;
					nu.scale  = me.sc;
					nu.mprog  = 1'b0;
				end
				if (mi_stage1) begin
					// this cycle: the pointer load only
					n_ptr     = 1'b1;
					n_ptr_ea1 = me_ea1;
				end
			end
			default: ;
		endcase

		// deferral of the source update into a later uop
		if (uw.noupd && !me_ea1 && (me.m == EM_AIP || me.m == EM_APD)) begin
			logic xuse;
			// an EA1 index naming the same register cannot see a deferred
			// value: update in place then
			xuse = (src.ea1.m == EM_AX || src.ea1.m == EM_PCX) && !src.ea1.is &&
			       src.ea1.xa && (areg(src.ea1.xr, sp_reg) == bre);
			if (!xuse) begin
				nu.upd_v  = 1'b0;
				nu.pinc   = 1'b0;
				n_def_set = 1'b1;
				n_def_reg = bre;
				n_def_amt = (me.m == EM_AIP) ? {3'd0, amt} : -{3'd0, amt};
			end
		end
	end
	// ADDA.L (A0)+,A0 / CMPA.L -(A0),A0: the destination register is read
	// after the source EA's update (the 68000 family computes the EA first)
	nu.b_upd = nu.upd_v && !me_ea1 && (me.m == EM_AIP || me.m == EM_APD) &&
	           nu.b_src == OS_REG && nu.b_reg == nu.upd_reg;
	// MOVES Rn,<ea> computes the EA first: MOVES.L A6,-(A6) stores the
	// decremented A6 (WinUAE, the cputest oracle); MOVE reads the source first
	nu.a_upd = nu.upd_v && (me.m == EM_AIP || me.m == EM_APD) &&
	           src.opw[15:8] == 8'h0E && nu.a_src == OS_REG && nu.a_reg == nu.upd_reg;
	// the deferred update lands on the upd2 uop, memory or not (FRESTORE
	// commits (An)+ only after its frame check).  Its displacement merge is
	// applied after the MOVEM block (no MOVEM uop has upd2), so the two
	// additions are parallel rather than chained.
	disp_pre = nu.disp;
	dmerge   = 1'b0;
	if (uw.upd2 && def_v) begin
		logic same, m16;
		same = nu.ag && nu.base_v && nu.base == def_reg &&
		       (me.mi == 2'd0 || !(me_ea1 ? ind1 : ind0));
		// MOVE16 (Ax)+,(Ay)+ with Ax = Ay: both transfers use the original
		// address and the register advances once (WinUAE, the cputest
		// oracle); CMPM-style pairs see the first update
		m16 = (src.opw[15:3] == 13'h1EC4);
		if (same && m16) begin
			// the destination's own (An)+ is the only update
		end
		else if (same) begin
			dmerge = 1'b1;
			if (me.m == EM_AIP) nu.upd_amt = nu.upd_amt + def_amt;
		end
		if (!(same && (me.m == EM_AIP || me.m == EM_APD || m16))) begin
			nu.upd2_v   = 1'b1;
			nu.upd2_reg = def_reg;
			nu.upd2_amt = def_amt;
		end
	end

	//----------------------------------------------------------------------
	// explicit AG modes
	//----------------------------------------------------------------------
	begin
		logic [4:0]  rb, rw;
		logic        rb_v;
		logic [31:0] dsv;
		rb_v = (uw.agb != S_NONE) && (uw.agb != S_ZERO);
		case (uw.agb)
			S_X1R: rb = src.ext1[15] ? areg(src.ext1[14:12], sp_reg) : dreg(src.ext1[14:12]);
			S_X2R: rb = src.ext2[15] ? areg(src.ext2[14:12], sp_reg) : dreg(src.ext2[14:12]);
			S_AX:  rb = areg(src.opw[11:9], sp_reg);
			S_AY:  rb = areg(src.opw[2:0], sp_reg);
			S_SP:  rb = sp_reg;
			S_SSP: rb = ssp;
			default: rb = 5'(uw.agb - 6'd25);   // USP ISP MSP T0-T13 (>= 40)
		endcase
		case (uw.agw)
			S_AX:  rw = areg(src.opw[11:9], sp_reg);
			S_AY:  rw = areg(src.opw[2:0], sp_reg);
			S_SP:  rw = sp_reg;
			S_SSP: rw = ssp;
			default: rw = 5'(uw.agw - 6'd25);
		endcase
		case (uw.dsel)
			DS_IMM:    dsv = src.imm;
			DS_NIMM:   dsv = -((src.sz == SZ_W) ? {{16{src.ea0.bd[15]}}, src.ea0.bd[15:0]} : src.ea0.bd);
			DS_QUICK:  dsv = q;
			DS_NQUICK: dsv = neg5(q[4:0]);      // q: 1..8
			DS_IMMC:   dsv = src.imm + {{16{uw.cval[15]}}, uw.cval};
			DS_SZB:    dsv = {27'd0, size_bytes(src.sz, 1'b0)};
			default:   dsv = {{16{uw.cval[15]}}, uw.cval};
		endcase
		case (uw.ag)
			AGM_PUSH: begin
				nu.ag = 1'b1; nu.base_v = 1'b1; nu.base = sp_reg;
				nu.disp = neg5(size_bytes(msz, 1'b1));
				nu.upd_v = 1'b1; nu.upd_reg = sp_reg;
			end
			AGM_POP: begin
				nu.ag = 1'b1; nu.base_v = 1'b1; nu.base = sp_reg;
				nu.pinc = 1'b1; nu.upd_v = 1'b1; nu.upd_reg = sp_reg;
				nu.upd_amt = {3'd0, size_bytes(msz, 1'b1)};
			end
			AGM_POPR: begin
				nu.ag = 1'b1; nu.base_v = 1'b1; nu.base = rb;
				nu.pinc = 1'b1; nu.upd_v = 1'b1; nu.upd_reg = rw;
				nu.upd_amt = {3'd0, size_bytes(msz, 1'b0)};
			end
			AGM_BASED, AGM_BASEDU: begin
				nu.ag = 1'b1; nu.base_v = rb_v; nu.base = rb; nu.disp = dsv;
				if (uw.ag == AGM_BASEDU) begin
					nu.upd_v = 1'b1;
					nu.upd_reg = (uw.agw != S_NONE) ? rw : rb;
				end
				else if (uw.agw != S_NONE) begin
					nu.upd_v = 1'b1; nu.upd_reg = rw;
				end
			end
			AGM_ADDC: begin
				nu.ag = 1'b1; nu.base_v = rb_v; nu.base = rb; nu.disp = dsv;
				nu.upd_v = 1'b1; nu.upd_reg = rw;
			end
			AGM_VAL0, AGM_ADDV: begin
				nu.ag = 1'b1;
				nu.base_v = (uw.ag == AGM_ADDV); nu.base = rb;
				if (src.ea0.m == EM_IMM)
					nu.disp = (src.sz == SZ_W) ? {{16{src.ea0.bd[15]}}, src.ea0.bd[15:0]} : src.ea0.bd;
				else begin
					nu.idx_v = 1'b1;
					nu.idx   = (src.ea0.m == EM_AN) ? areg(src.ea0.r, sp_reg) : dreg(src.ea0.r);
					nu.idx_l = (src.sz == SZ_L);
				end
				nu.upd_v = 1'b1; nu.upd_reg = rw;
			end
			AGM_ADDT0: begin
				nu.ag = 1'b1; nu.base_v = 1'b1; nu.base = rb;
				nu.idx_v = 1'b1; nu.idx = R_T0; nu.idx_l = 1'b1;
				nu.upd_v = 1'b1; nu.upd_reg = rw;
			end
			AGM_LEA0: begin
				if (uw.agw != S_NONE) begin nu.upd_v = !n_ptr; nu.upd_reg = rw; end
				nu.mem = M_NONE;
			end
			AGM_FEA: begin
				// the FPU operand's address into agw: (An)+ An, -(An) An -
				// size (the register moves with FUPD), #imm its place in the
				// instruction stream (D1: bd = PC + 4; a byte is the word's
				// low byte), else the EA
				nu.mem = M_NONE;
				if (src.ea0.m == EM_AIP || src.ea0.m == EM_APD) begin
					nu.ag = 1'b1; nu.base_v = 1'b1; nu.base = areg(src.ea0.r, sp_reg);
					nu.idx_v = 1'b0; nu.pinc = 1'b0;
					nu.disp = (src.ea0.m == EM_APD) ? neg7(fp_size) : 32'd0;
				end
				else if (src.ea0.m == EM_IMM) begin
					nu.ag = 1'b1; nu.base_v = 1'b0; nu.idx_v = 1'b0; nu.pinc = 1'b0;
					nu.disp = src.ea0.bd + ((src.ext1[15:13] == 3'b010 &&
					                         src.ext1[12:10] == 3'd6) ? 32'd1 : 32'd0);
					nu.mprog = 1'b1;
				end
				nu.upd_v = !n_ptr; nu.upd_reg = rw;
			end
			AGM_FUPD: begin
				if (src.ea0.m == EM_AIP || src.ea0.m == EM_APD) begin
					nu.ag = 1'b1; nu.base_v = 1'b1; nu.base = areg(src.ea0.r, sp_reg);
					nu.idx_v = 1'b0; nu.pinc = 1'b0;
					nu.disp = (src.ea0.m == EM_APD) ? neg7(fp_size) : {25'd0, fp_size};
					nu.upd_v = 1'b1; nu.upd_reg = areg(src.ea0.r, sp_reg);
				end
			end
			default: ;
		endcase
	end

	//----------------------------------------------------------------------
	// MOVEM: one transfer per set mask bit.  -(An): mask bit 0 is A7 and the
	// addresses descend from An; other modes ascend from the EA.  An is
	// updated by the last transfer only.
	//----------------------------------------------------------------------
	if (uw.loop) begin
		logic [15:0] m;
		logic  [3:0] bi, rn;
		logic  [4:0] r;
		logic  [2:0] sb;
		logic        pd, pi, lastx, base_in, fb_in, fx_in;
		logic  [4:0] an, xreg;
		logic [31:0] off;
		logic [15:0] low;
		logic  [3:0] k_an, k_x;
		logic        is_an, is_x;
		m  = mv_act ? mv_mask : src.ext1;
		pd = (src.ea0.m == EM_APD);
		pi = (src.ea0.m == EM_AIP);
		bi = 4'd0;
		for (int i = 15; i >= 0; i--) if (m[i]) bi = 4'(i);
		rn = pd ? (4'd15 - bi) : bi;
		r  = rn[3] ? areg(rn[2:0], sp_reg) : dreg(rn[2:0]);
		// (the lowest set bit cleared: m & ~low, no encoder on the way to
		// the last-transfer test, which pops the decoder's record)
		low   = m & (~m + 16'd1);
		n_mv_rest = m & ~low;
		lastx = (n_mv_rest == 16'd0);
		sb = (src.sz == SZ_L) ? 3'd4 : 3'd2;
		an = areg(src.ea0.r, sp_reg);
		// whether this transfer's register is An or the index register,
		// from the mask's lowest set bit directly (not through the encoder
		// and the register number: a timing path); the register numbers
		// are one-to-one, so r == an exactly when rn is {1, An}
		k_an  = pd ? (4'd15 - {1'b1, src.ea0.r}) : {1'b1, src.ea0.r};
		k_x   = {src.ea0.xa, src.ea0.xr};
		is_an = low[k_an];
		is_x  = low[k_x];
		// A load list that contains a register of the EA (the base, or the
		// index of an indexed mode) works from a copy of the address in
		// T11, and the loaded base/index commits only after the last
		// transfer (through T7/T6 and fix-up uops): a fault on a later
		// transfer restarts the instruction with the original EA.  (An)+
		// discards a loaded An: the final An is the incremented address.
		fb_in   = (uw.d == S_MVR) && !pd && !pi &&
		          (src.ea0.m == EM_AI || src.ea0.m == EM_AD16 ||
		           (src.ea0.m == EM_AX && !src.ea0.bs)) &&
		          src.ext1[{1'b1, src.ea0.r}];
		xreg    = src.ea0.xa ? areg(src.ea0.xr, sp_reg) : dreg(src.ea0.xr);
		fx_in   = (uw.d == S_MVR) && (src.ea0.m == EM_AX || src.ea0.m == EM_PCX) &&
		          !src.ea0.is && src.ext1[{src.ea0.xa, src.ea0.xr}] &&
		          !(fb_in && xreg == an);
		base_in = fb_in || fx_in ||
		          ((uw.d == S_MVR) && pi && src.ext1[{1'b1, src.ea0.r}]);
		off = mv_act ? mv_off : (pd ? -{29'd0, sb} : 32'd0);
		nu.last = lastx && !fb_in && !fx_in;
		if (uw.d == S_MVR) begin
			nu.d_v = 1'b1; nu.d_reg = r;
			if (fb_in && is_an)           nu.d_reg = R_T0 + 5'd7;
			else if (fx_in && !pd && is_x) nu.d_reg = R_T0 + 5'd6;
			else if (pi && is_an)         nu.d_v   = 1'b0;
		end
		else begin
			nu.a_src = OS_REG; nu.a_reg = r;
			// -(An) storing An itself writes An - size (68020 and later)
			if (pd && is_an) begin
				nu.op = OP_SUB; nu.sz = SZ_L;
				nu.a_src = OS_IMM; nu.imm = {29'd0, sb};
				nu.b_src = OS_REG; nu.b_reg = an;
			end
		end
		if (mv_act && mv_mask == 16'd0) begin
			// after the last transfer: commit the deferred base, then index
			uop_t p;
			logic fxb;
			fxb = fb_in && mv_fix == 2'd0;
			p = '0;
			p.pc = nu.pc; p.ilen = nu.ilen; p.exr = nu.exr; p.first = 1'b0;
			p.op = OP_MOV; p.sz = SZ_L; p.ccr_we = 5'd0;
			p.a_src = OS_REG; p.a_reg = fxb ? (R_T0 + 5'd7) : (R_T0 + 5'd6);
			p.b_src = OS_ZERO;
			p.d_v = 1'b1; p.d_reg = fxb ? an : xreg;
			p.last = !(fxb && fx_in);
			p.exc = nu.exc;
			nu = p;
			n_mv_rest = 16'd0;
		end
		else if (base_in && !mv_t11) begin
			// first: T11 = the address, then the transfers from T11
			uop_t p;
			p = '0;
			p.pc = nu.pc; p.ilen = nu.ilen; p.exr = nu.exr; p.first = nu.first;
			p.ag = 1'b1;
			p.base_v = nu.base_v; p.base = nu.base;
			p.idx_v = nu.idx_v; p.idx = nu.idx; p.idx_l = nu.idx_l; p.scale = nu.scale;
			p.disp = nu.disp; p.mprog = nu.mprog;
			p.upd_v = 1'b1; p.upd_reg = R_T0 + 5'd11;
			p.exc = nu.exc;
			nu = p;
			n_mv_pre = 1'b1;
		end
		else begin
			if (mv_t11) begin
				nu.base_v = 1'b1; nu.base = R_T0 + 5'd11;
				nu.idx_v = 1'b0; nu.disp = 32'd0;
			end
			// MOVEM continuation (SSW CM): for the indexed and PC-relative
			// modes a transfer carries its offset from the calculated EA;
			// a fault stacks that EA, and RTE resumes from it
			if (src.ea0.m == EM_AX || src.ea0.m == EM_PC16 || src.ea0.m == EM_PCX) begin
				nu.cond   = 4'hC;
				nu.target = off;
			end
			// address of this transfer: the offset (within +-64) is added
			// by AG as the uop enters it, as a deferred update's is (off
			// the sequencer's EA selects)
			if (pd) nu.disp = off;          // undo the generic -(An) offset
			else begin
				nu.dmv = 1'b1;
				nu.dma = off[7:0];
				dbg_mvo = off;
			end
			nu.pinc = 1'b0;
			nu.upd_v = 1'b0;
			if (lastx && pd) begin
				nu.upd_v = 1'b1; nu.upd_reg = an;          // An = lowest address
			end
			if (lastx && pi) begin
				nu.pinc = 1'b1; nu.upd_v = 1'b1; nu.upd_reg = an;
				nu.upd_amt = (mv_act ? mv_cnt : 8'd0) + {5'd0, sb};
			end
		end
	end

	// FMOVEM of control registers: a slot whose register is not in the
	// (static) list is no operation
	if (uw.dyn == 3'd4) begin
		logic [2:0] crl;
		crl = (src.ext1[12:10] == 3'd0) ? 3'b001 : src.ext1[12:10];
		if (!crl[2 - uw.dynk[1:0]]) begin
			nu.mem = M_NONE; nu.ag = 1'b0; nu.upd_v = 1'b0; nu.upd2_v = 1'b0;
			nu.d_v = 1'b0;
		end
		nu.dyn = 3'd0;
	end

	// FPU operand transfers read the EA's space: program space for
	// PC-relative and immediate sources
	if (uw.mfc == MFC_EAP)
		nu.mprog = (src.ea0.m == EM_PC16 || src.ea0.m == EM_PCX || src.ea0.m == EM_IMM);

	// (the addition itself is AG's, as the uop enters it: off the
	// microcode ROM's path to the uop queue.  No upd2 uop has an explicit
	// AG mode, so its displacement is still disp_pre -- checked below)
	dbg_dm   = dmerge;
	dbg_dpre = disp_pre;
	dbg_mvd  = nu.dmv;              // (MOVEM's offset, before a merge)
	if (dmerge) begin
		nu.dmv  = 1'b1;
		nu.dma  = def_amt;
	end

	// a pointer load replaces the uop this cycle
	if (n_ptr) begin
		uop_t p;
		p = '0;
		p.pc = nu.pc; p.ilen = nu.ilen; p.exr = nu.exr; p.first = nu.first; p.last = 1'b0;
		p.op = OP_MOV; p.sz = SZ_L; p.msz = SZ_L; p.ccr_we = 5'd0;
		p.a_src = OS_MEM; p.b_src = OS_ZERO;
		p.ag = 1'b1;
		p.base_v = nu.base_v; p.base = nu.base;
		p.idx_v = nu.idx_v; p.idx = nu.idx; p.idx_l = nu.idx_l; p.scale = nu.scale;
		p.disp = nu.disp; p.dmv = nu.dmv; p.dma = nu.dma;
		p.mem = M_LD; p.mprog = nu.mprog;
		p.d_v = 1'b1;
		p.d_reg = n_ptr_ea1 ? (R_T0 + 5'd12) : (R_T0 + 5'd13);
		p.exc = nu.exc;
		nu = p;
		n_def_set = 1'b0;
	end
end

//--------------------------------------------------------------------------
// sequencing.  uw_q is read one cycle ahead: the next address is chosen
// from the current word and the records, and the ROM output registered.
//--------------------------------------------------------------------------
wire step = uw_v && room_out && !flush && !exc_go && !exc_pend;
wire emit = step && !n_jump;
wire stay = n_ptr || n_mv_pre || (uw.loop && !nu.last);   // same word again
wire done = emit && !stay && uw.last;                       // instruction ends

assign rq_pop = done && !exc_mode;
// The pop from the word's own bits and the record's EA modes, not the uop
// built from them (D1's room, a timing path): a plain last word -- no
// jump, no MOVEM loop -- of an instruction with no memory-indirect EA (no
// pointer load) ends it whenever it steps.  It implies rq_pop; the rare
// pop it misses only costs D1 a clock.
assign rq_pop_e = step && !exc_mode && uw.last && (uw.jc == JC_NEVER) && !uw.loop &&
                  (rq0.ea0.mi == 2'd0) && (rq0.ea1.mi == 2'd0);
// synthesis translate_off
always_ff @(posedge clk)
	if (rq_pop_e && !rq_pop) begin
		$display("FAIL: useq: the early pop without the pop");
		$finish;
	end
// synthesis translate_on

logic [9:0] na;          // next microcode address
logic       nv;
always_comb begin
	na = upc;
	nv = uw_v;
	if (exc_go) begin
		case (exc_kind)
			4'd1:    na = UA_EXC_FMT2;
			4'd2:    na = UA_EXC_FMT7;
			4'd3:    na = UA_EXC_IRQ;
			4'd5:    na = UA_EXC_IRQM;
			4'd4:    na = UA_EXC_RESET;
			default: na = UA_EXC_FMT0;
		endcase
		nv = 1'b1;
	end
	else if (flush) begin
		nv = 1'b0;
	end
	else if (step) begin
		if (n_jump)      na = jc_now ? uw.jt : upc + 10'd1;
		else if (stay)   na = upc;
		else if (!uw.last) na = upc + 10'd1;
		else if (!exc_mode && rq_n[1]) na = rq1.rt;        // next instruction
		else nv = 1'b0;
	end
	else if (!uw_v && !exc_mode && !exc_pend && rq_n != 2'd0) begin
		na = rq0.rt;                                         // first word
		nv = 1'b1;
	end
end

// the microcode ROM in block RAM: its address register is the sequencing
// register (uw_q is the word at upc, read one cycle ahead as before)
(* romstyle = "M10K" *) logic [$bits(uword_t)-1:0] urom [0:1023];
initial begin
// ---- inlined from ap68040_ucode_init.svh (tools/import_ap68040.py) ----
// generated by tools/ucode.py - do not edit
for (int i = 0; i < 1024; i++) urom[i] = '0;
urom[0] = 121'h10000000;  // ILLEGAL.0
urom[1] = 121'h10000000;  // DEC_EXC.0
urom[2] = 121'h1000010022080000000000010000000;  // OP_EA_DN.0
urom[3] = 121'h1000010080820000000000010000000;  // OP_DN_EA.0
urom[4] = 121'h1000010100820000000000010000000;  // IMM_OP.0
urom[5] = 121'ha0007900800000000000010000000;  // IMM_CMP.0
urom[6] = 121'ha0007822000000000000010000000;  // CMP_EA_DN.0
urom[7] = 121'hb8007823010000000000010000000;  // CMPA.0
urom[8] = 121'h1000010120820000000000010000000;  // QUICK.0
urom[9] = 121'h18007940080000000000010000000;  // MOVEQ.0
urom[10] = 121'h1000010000820000000000010000000;  // UNARY.0
urom[11] = 121'h7820000000000000010000000;  // TST.0
urom[12] = 121'h44020000d020000000000010000000;  // SCC.0
urom[13] = 121'h100001000d020000000000010000000;  // CLR_W.0
urom[14] = 121'h1e00078028a0000000000010000000;  // SWAP.0
urom[15] = 121'h1a00078028a0000000000010000000;  // EXT.0
urom[16] = 121'h1c00078028a0000000000010000000;  // EXTB.0
urom[17] = 121'h200007800820000000000610000000;  // TAS.0
urom[18] = 121'h102800;  // ADDA.0
urom[19] = 121'h40c3000000010000000;  // ADDA.1
urom[20] = 121'h380000230d0000000000010000000;  // ADDA.2
urom[21] = 121'h382e00;  // SUBA.0
urom[22] = 121'h780000230d0000000000010000000;  // SUBA.1
urom[23] = 121'h48c3200000010000000;  // SUBA.2
urom[24] = 121'h48e3b00000010000000;  // QUICK_A.0
urom[25] = 121'h48e3c00000010000000;  // QUICK_SA.0
urom[26] = 121'h5003000000010000000;  // LEA.0
urom[27] = 121'h5015800000000000000;  // PEA.0
urom[28] = 121'h1b000560001800000008010000000;  // PEA.1
urom[29] = 121'h103e00;  // MOVEA.0
urom[30] = 121'h3803000000010000000;  // MOVEA.1
urom[31] = 121'h180000200d0000000000010000000;  // MOVEA.2
urom[32] = 121'h604400;  // MOVE.0
urom[33] = 121'h7821840000000000010000000;  // MOVE.1
urom[34] = 121'h20560000000000004000000;  // MOVE.2
urom[35] = 121'h7d60040000000000012000000;  // MOVE.3
urom[36] = 121'h284c00;  // BIT_IMM.0
urom[37] = 121'h1000002100820000000000010000000;  // BIT_IMM.1
urom[38] = 121'h1018002100820000000000010000000;  // BIT_IMM.2
urom[39] = 121'h285200;  // BIT_DYN.0
urom[40] = 121'h1000002080820000000000010000000;  // BIT_DYN.1
urom[41] = 121'h1018002080820000000000010000000;  // BIT_DYN.2
urom[42] = 121'h285800;  // BTST_IMM.0
urom[43] = 121'h3c0002100800000000000010000000;  // BTST_IMM.1
urom[44] = 121'h3d8002100800000000000010000000;  // BTST_IMM.2
urom[45] = 121'h285e00;  // BTST_DYN.0
urom[46] = 121'h3c0002080800000000000010000000;  // BTST_DYN.1
urom[47] = 121'h3d8002080800000000000010000000;  // BTST_DYN.2
urom[48] = 121'h10000101628a0000000000010000000;  // SHIFT_R.0
urom[49] = 121'h1000010220820000000010010000000;  // SHIFT_M.0
urom[50] = 121'h10000100a2080000000000010000000;  // ADDX_R.0
urom[51] = 121'h20560000000000004000000;  // ADDX_M.0
urom[52] = 121'h1000010561040000000000012000000;  // ADDX_M.1
urom[53] = 121'h20560000000000004000000;  // CMPM.0
urom[54] = 121'ha0007d61000000000000012000000;  // CMPM.1
urom[55] = 121'h280000102d60000000000000000000;  // PACK_R.0
urom[56] = 121'h8000562080000000000010000000;  // PACK_R.1
urom[57] = 121'h12000020560000000000004000000;  // PACK_M.0
urom[58] = 121'h280000115d60000000000000000000;  // PACK_M.1
urom[59] = 121'h9000560040000000000012000000;  // PACK_M.2
urom[60] = 121'h2a0000102d60000000000000000000;  // UNPK_R.0
urom[61] = 121'h10000562080000000000010000000;  // UNPK_R.1
urom[62] = 121'h9000020560000000000004000000;  // UNPK_M.0
urom[63] = 121'h2a0000115d60000000000000000000;  // UNPK_M.1
urom[64] = 121'h12000560040000000000012000000;  // UNPK_M.2
urom[65] = 121'h1000407822080000000000010000000;  // MULW.0
urom[66] = 121'h1000407822080000000000010000000;  // DIVW.0
urom[67] = 121'h788a00;  // MULL.0
urom[68] = 121'h618607829a60000000000010000000;  // MULL.1
urom[69] = 121'h618607829800000000000000000000;  // MULL.2
urom[70] = 121'h660000000280000000000000000000;  // MULL.3
urom[71] = 121'h660020000260000000000010000000;  // MULL.4
urom[72] = 121'h640000280000000000000000000000;  // DIVL.0
urom[73] = 121'h638607829800000000000000000000;  // DIVL.1
urom[74] = 121'h660000000280000000000000000000;  // DIVL.2
urom[75] = 121'h660020000260000000000010000000;  // DIVL.3
urom[76] = 121'h4e0007822000000000000010000000;  // CHK.0
urom[77] = 121'h18000080560000000000000000000;  // EXG_DD.0
urom[78] = 121'h180000a0080000000000000000000;  // EXG_DD.1
urom[79] = 121'h180005600a0000000000010000000;  // EXG_DD.2
urom[80] = 121'h180000c0560000000000000000000;  // EXG_AA.0
urom[81] = 121'h180000e00c0000000000000000000;  // EXG_AA.1
urom[82] = 121'h180005600e0000000000010000000;  // EXG_AA.2
urom[83] = 121'h18000080560000000000000000000;  // EXG_DA.0
urom[84] = 121'h180000e0080000000000000000000;  // EXG_DA.1
urom[85] = 121'h180005600e0000000000010000000;  // EXG_DA.2
urom[86] = 121'h480200000000000000000030000000;  // BCC.0
urom[87] = 121'h1b0001c0001800000008050000000;  // BSR.0
urom[88] = 121'h4a02000028a0000000000030000000;  // DBCC.0
urom[89] = 121'h10005000000000070000000;  // JMP.0
urom[90] = 121'h5015800000000000000;  // JSR.0
urom[91] = 121'h1b0001d58018000000080b0000000;  // JSR.1
urom[92] = 121'h1b0001d0001800000008050000000;  // JSR_K.0
urom[93] = 121'h1b000360002000000004090000000;  // RTS.0
urom[94] = 121'h1b000360562980000004000000000;  // RTD.0
urom[95] = 121'h560004986500040090000000;  // RTD.1
urom[96] = 121'h4c0200000000000000000010000000;  // TRAPCC.0
urom[97] = 121'h4c0120000000000000000010000000;  // TRAPV.0
urom[98] = 121'h58cc00;  // LINK.0
urom[99] = 121'h1b0000e0001800000008000000000;  // LINK.1
urom[100] = 121'h2983800000000000000;  // LINK.2
urom[101] = 121'h4986100000010000000;  // LINK.3
urom[102] = 121'h7b000226001800000048000000000;  // LINK.4
urom[103] = 121'h4986100000010000000;  // LINK.5
urom[104] = 121'h1b0003600e60e6000004010000000;  // UNLK.0
urom[105] = 121'h59000000d020000000200010000000;  // MOVE_FROM_SR.0
urom[106] = 121'h59000000d020000000210010000000;  // MOVE_FROM_CCR.0
urom[107] = 121'h54006f820000000000000010000000;  // MOVE_TO_CCR.0
urom[108] = 121'h56006f820000000000000010000000;  // MOVE_TO_SR.0
urom[109] = 121'h54040f900000000000000010000000;  // CCR_LOG.0
urom[110] = 121'h56040f900000000000000010000000;  // SR_LOG.0
urom[111] = 121'h180000e0500000000000010000000;  // MOVE_TO_USP.0
urom[112] = 121'h180005000e0000000000010000000;  // MOVE_FROM_USP.0
urom[113] = 121'h10000000;  // TRAP.0
urom[114] = 121'h9000360002a00000007000000000;  // BKPT.0
urom[115] = 121'h6c0120000000000000000010000000;  // BKPT.1
urom[116] = 121'h6c0000000000000000000018000000;  // NOP.0
urom[117] = 121'h6c0020000000000000000018000000;  // RESET.0
urom[118] = 121'h6c0040100000000000000018000000;  // STOP.0
urom[119] = 121'h80f200;  // MOVEC_RD.0
urom[120] = 121'h598000380240000000000010000000;  // MOVEC_RD.1
urom[121] = 121'h180003a0240000000000010000000;  // MOVEC_RD.2
urom[122] = 121'h80f800;  // MOVEC_WR.0
urom[123] = 121'h5b800024e000000000000018000000;  // MOVEC_WR.1
urom[124] = 121'h180002403a0000000000018000000;  // MOVEC_WR.2
urom[125] = 121'h68fe00;  // MOVEM_RM.0
urom[126] = 121'h320020000000000010000100;  // MOVEM_RM.1
urom[127] = 121'h10000000;  // MOVEM_RM.2
urom[128] = 121'h690400;  // MOVEM_MR.0
urom[129] = 121'h18000020330000000000010000100;  // MOVEM_MR.1
urom[130] = 121'h10000000;  // MOVEM_MR.2
urom[131] = 121'h1c000020000000000000004000000;  // MOVE16.0
urom[132] = 121'h1c000000040000000000012000000;  // MOVE16.1
urom[133] = 121'h90003685628e0500000000000000;  // MOVEP_MR.0
urom[134] = 121'h318000235d60000000080000000000;  // MOVEP_MR.1
urom[135] = 121'h9000375d628e0500020000000000;  // MOVEP_MR.2
urom[136] = 121'h511400;  // MOVEP_MR.3
urom[137] = 121'h10000562080000000000010000000;  // MOVEP_MR.4
urom[138] = 121'h318000235d60000000080000000000;  // MOVEP_MR.5
urom[139] = 121'h9000375d628e0500040000000000;  // MOVEP_MR.6
urom[140] = 121'h318000235d60000000080000000000;  // MOVEP_MR.7
urom[141] = 121'h9000375d628e0500060000000000;  // MOVEP_MR.8
urom[142] = 121'h18000560080000000000010000000;  // MOVEP_MR.9
urom[143] = 121'h512600;  // MOVEP_RM.0
urom[144] = 121'h338000222560000000080000000000;  // MOVEP_RM.1
urom[145] = 121'h90005600028e0500008000000000;  // MOVEP_RM.2
urom[146] = 121'h90000800028e0500028010000000;  // MOVEP_RM.3
urom[147] = 121'h338000222560000000180000000000;  // MOVEP_RM.4
urom[148] = 121'h90005600028e0500008000000000;  // MOVEP_RM.5
urom[149] = 121'h338000222560000000100000000000;  // MOVEP_RM.6
urom[150] = 121'h90005600028e0500028000000000;  // MOVEP_RM.7
urom[151] = 121'h338000222560000000080000000000;  // MOVEP_RM.8
urom[152] = 121'h90005600028e0500048000000000;  // MOVEP_RM.9
urom[153] = 121'h90000800028e0500068010000000;  // MOVEP_RM.10
urom[154] = 121'h294400;  // BF_TST.0
urom[155] = 121'h6b80003cfd60000000000000000000;  // BF_TST.1
urom[156] = 121'h5016000000000000000;  // BF_TST.2
urom[157] = 121'h6d96000000000000000;  // BF_TST.3
urom[158] = 121'h1b1c03605a2d80000000000000000;  // BF_TST.4
urom[159] = 121'h91a03685c2d80000040000000000;  // BF_TST.5
urom[160] = 121'h5d80005c0000000000000000000000;  // BF_TST.6
urom[161] = 121'h680a07a76800000000000010000000;  // BF_TST.7
urom[162] = 121'h6b80003cfd60000000000000000000;  // BF_TST.8
urom[163] = 121'h680807a60800000000000010000000;  // BF_TST.9
urom[164] = 121'h295800;  // BF_EXT.0
urom[165] = 121'h6b80003cfd60000000000000000000;  // BF_EXT.1
urom[166] = 121'h5016000000000000000;  // BF_EXT.2
urom[167] = 121'h6d96000000000000000;  // BF_EXT.3
urom[168] = 121'h1b1c03605a2d80000000000000000;  // BF_EXT.4
urom[169] = 121'h91a03685c2d80000040000000000;  // BF_EXT.5
urom[170] = 121'h5d80005c0000000000000000000000;  // BF_EXT.6
urom[171] = 121'h680a07a76a60000000000010000000;  // BF_EXT.7
urom[172] = 121'h6b80003cfd60000000000000000000;  // BF_EXT.8
urom[173] = 121'h680807a60a60000000000010000000;  // BF_EXT.9
urom[174] = 121'h297200;  // BF_MOD.0
urom[175] = 121'h6b80003cfd60000000000000000000;  // BF_MOD.1
urom[176] = 121'h5016000000000000000;  // BF_MOD.2
urom[177] = 121'h6d96000000000000000;  // BF_MOD.3
urom[178] = 121'h1b1c03605a2d80000000100000000;  // BF_MOD.4
urom[179] = 121'h91a03685c2d80000040100000000;  // BF_MOD.5
urom[180] = 121'h5d80005c0000000000000000000000;  // BF_MOD.6
urom[181] = 121'h680a07a76da0000000000000000000;  // BF_MOD.7
urom[182] = 121'h6b80200005c0000000000000000000;  // BF_MOD.8
urom[183] = 121'h1b1c05a0002d80000008000000000;  // BF_MOD.9
urom[184] = 121'h91a05c0002d80000048010000000;  // BF_MOD.10
urom[185] = 121'h6b80003cfd60000000000000000000;  // BF_MOD.11
urom[186] = 121'h680807a60820000000000010000000;  // BF_MOD.12
urom[187] = 121'h5d8000280000000000000000000000;  // CAS.0
urom[188] = 121'h5e0007aa0a8080000000c610000000;  // CAS.1
urom[189] = 121'h360562a40000000500000000;  // CAS2.0
urom[190] = 121'h360582b00000000500000000;  // CAS2.1
urom[191] = 121'h720007a95800000000000000000000;  // CAS2.2
urom[192] = 121'h720027ad6000000000000000000000;  // CAS2.3
urom[193] = 121'h7400002a0002a40000008400000000;  // CAS2.4
urom[194] = 121'h7400202f6002b00000008600000000;  // CAS2.5
urom[195] = 121'h76000056a280000000000000000000;  // CAS2.6
urom[196] = 121'h76000058b2c0000000000010000000;  // CAS2.7
urom[197] = 121'h5016000000000000000;  // CHK2.0
urom[198] = 121'h18000360562d80000000000000000;  // CHK2.1
urom[199] = 121'h180003605a2d80600000000000000;  // CHK2.2
urom[200] = 121'h5d8000560000000000000000000000;  // CHK2.3
urom[201] = 121'h520c02da9000000000000010000000;  // CHK2.4
urom[202] = 121'h12000360582980000001800000000;  // RTE.0
urom[203] = 121'h1b0003605a2980000021800000000;  // RTE.1
urom[204] = 121'h120003605c2980000061800000000;  // RTE.2
urom[205] = 121'h7900005c0560000000000000000000;  // RTE.3
urom[206] = 121'h6998800000000000000;  // RTE.4
urom[207] = 121'h1b1603605e2980000081800000000;  // RTE.5
urom[208] = 121'h1a1603686029800000c1800000000;  // RTE.6
urom[209] = 121'h4e26000000000000000;  // RTE.7
urom[210] = 121'h6d80c05f8000000000000000000000;  // RTE.8
urom[211] = 121'h7b0000596800000000000010000000;  // RTE.9
urom[212] = 121'h12000360582980000000000000000;  // RTR.0
urom[213] = 121'h1b0003605a2980000020000000000;  // RTR.1
urom[214] = 121'h54006fd968049860000600b0000000;  // RTR.2
urom[215] = 121'h49c000;  // MOVES.0
urom[216] = 121'h89b400;  // MOVES.1
urom[217] = 121'h29240000000000810000000;  // MOVES.2
urom[218] = 121'h20560000000000800000000;  // MOVES.3
urom[219] = 121'h51be00;  // MOVES.4
urom[220] = 121'h91bc00;  // MOVES.5
urom[221] = 121'h1b8000015a40000000000010000000;  // MOVES.6
urom[222] = 121'h1d8000015a40000000000010000000;  // MOVES.7
urom[223] = 121'h18000560240000000000010000000;  // MOVES.8
urom[224] = 121'h240020000000001010000000;  // MOVES.9
urom[225] = 121'h6d80600f0000000000000018000000;  // CACHE_OP.0
urom[226] = 121'h6d80800f0000000000000018000000;  // PFLUSH.0
urom[227] = 121'h6d80a00f0000000000000018000000;  // PTEST.0
urom[228] = 121'h99da00;  // FPU_GEN.0
urom[229] = 121'h6f8000430000000000000000000000;  // FPU_GEN.1
urom[230] = 121'h99d800;  // FPU_GEN.2
urom[231] = 121'ha1dc00;  // FPU_GEN.3
urom[232] = 121'haa2e00;  // FPU_GEN.4
urom[233] = 121'hb29a00;  // FPU_GEN.5
urom[234] = 121'hbae000;  // FPU_GEN.6
urom[235] = 121'h6f8020000000000000000010000000;  // FPU_GEN.7
urom[236] = 121'h6f8020000000000000000010000000;  // FPU_RR.0
urom[237] = 121'h6f0000430000000000000010000000;  // FPU_RRF.0
urom[238] = 121'he1d800;  // FPU_IN.0
urom[239] = 121'h2a0400;  // FPU_IN.1
urom[240] = 121'h6f81e000000701b000000000000000;  // FPU_IN.2
urom[241] = 121'hd9fc00;  // FPU_IN.3
urom[242] = 121'hd1f600;  // FPU_IN.4
urom[243] = 121'hc9f200;  // FPU_IN.5
urom[244] = 121'hc1ee00;  // FPU_IN.6
urom[245] = 121'h1b000360562ec0000006800000000;  // FPU_IN.7
urom[246] = 121'h6f8020560007800000000010000000;  // FPU_IN.8
urom[247] = 121'h19000360562ec0000006800000000;  // FPU_IN1.0
urom[248] = 121'h6f8020560007800000000010000000;  // FPU_IN1.1
urom[249] = 121'h1a000360562ec0000006800000000;  // FPU_IN2.0
urom[250] = 121'h6f8020560007800000000010000000;  // FPU_IN2.1
urom[251] = 121'h1b000360562ec0000006800000000;  // FPU_IN8.0
urom[252] = 121'h1b000360582ec0000046800000000;  // FPU_IN8.1
urom[253] = 121'h6f8020576007800000000010000000;  // FPU_IN8.2
urom[254] = 121'h1b000360562ec0000006800000000;  // FPU_IN12.0
urom[255] = 121'h1b000360582ec0000046800000000;  // FPU_IN12.1
urom[256] = 121'h5db000360002ec0000086800000000;  // FPU_IN12.2
urom[257] = 121'h6f8020576007800000000010000000;  // FPU_IN12.3
urom[258] = 121'h6f8020020000000000000010000000;  // FPU_IND.0
urom[259] = 121'h6f8000430000000000000000000000;  // FPU_K_IND.0
urom[260] = 121'h6f8020020000000000000010000000;  // FPU_K_IND.1
urom[261] = 121'h6e800043000701b000000000000000;  // FPU_K_IN4.0
urom[262] = 121'h1b000360562ec0000006800000000;  // FPU_K_IN4.1
urom[263] = 121'h6f8020560007800000000010000000;  // FPU_K_IN4.2
urom[264] = 121'h6e800043000701b000000000000000;  // FPU_K_IN1.0
urom[265] = 121'h19000360562ec0000006800000000;  // FPU_K_IN1.1
urom[266] = 121'h6f8020560007800000000010000000;  // FPU_K_IN1.2
urom[267] = 121'h6e800043000701b000000000000000;  // FPU_K_IN2.0
urom[268] = 121'h1a000360562ec0000006800000000;  // FPU_K_IN2.1
urom[269] = 121'h6f8020560007800000000010000000;  // FPU_K_IN2.2
urom[270] = 121'h6e800043000701b000000000000000;  // FPU_K_IN8.0
urom[271] = 121'h1b000360562ec0000006800000000;  // FPU_K_IN8.1
urom[272] = 121'h1b000360582ec0000046800000000;  // FPU_K_IN8.2
urom[273] = 121'h6f8020576007800000000010000000;  // FPU_K_IN8.3
urom[274] = 121'h6e800043000701b000000000000000;  // FPU_K_IN12.0
urom[275] = 121'h1b000360562ec0000006800000000;  // FPU_K_IN12.1
urom[276] = 121'h1b000360582ec0000046800000000;  // FPU_K_IN12.2
urom[277] = 121'h5db000360002ec0000086800000000;  // FPU_K_IN12.3
urom[278] = 121'h6f8020576007800000000010000000;  // FPU_K_IN12.4
urom[279] = 121'h2a5c00;  // FPU_OUT.0
urom[280] = 121'h6f81e000000701b000000000000000;  // FPU_OUT.1
urom[281] = 121'h6f8020000560000000000000000000;  // FPU_OUT.2
urom[282] = 121'hda5000;  // FPU_OUT.3
urom[283] = 121'hd24800;  // FPU_OUT.4
urom[284] = 121'hca4400;  // FPU_OUT.5
urom[285] = 121'hc24000;  // FPU_OUT.6
urom[286] = 121'h1b000560002ec0000008000000000;  // FPU_OUT.7
urom[287] = 121'h6f8060000007800000000010000000;  // FPU_OUT.8
urom[288] = 121'h19000560002ec0000008000000000;  // FPU_OUT1.0
urom[289] = 121'h6f8060000007800000000010000000;  // FPU_OUT1.1
urom[290] = 121'h1a000560002ec0000008000000000;  // FPU_OUT2.0
urom[291] = 121'h6f8060000007800000000010000000;  // FPU_OUT2.1
urom[292] = 121'h6f8040220580000000010000000000;  // FPU_OUT8.0
urom[293] = 121'h1b000560002ec0000008000000000;  // FPU_OUT8.1
urom[294] = 121'h1b000580002ec0000048000000000;  // FPU_OUT8.2
urom[295] = 121'h6f8060000007800000000010000000;  // FPU_OUT8.3
urom[296] = 121'h6f8040220580000000010000000000;  // FPU_OUT12.0
urom[297] = 121'h6f80402205a0000000020000000000;  // FPU_OUT12.1
urom[298] = 121'h1b000560002ec0000008000000000;  // FPU_OUT12.2
urom[299] = 121'h1b000580002ec0000048000000000;  // FPU_OUT12.3
urom[300] = 121'h1b0005a0002ec0000088000000000;  // FPU_OUT12.4
urom[301] = 121'h6f8060000007800000000010000000;  // FPU_OUT12.5
urom[302] = 121'h6f8020000820000000000000000000;  // FPU_OUTD.0
urom[303] = 121'h6f8060000000000000000010000000;  // FPU_OUTD.1
urom[304] = 121'h6f8000430000000000000000000000;  // FPU_K_OUTD.0
urom[305] = 121'h6f8020000820000000000000000000;  // FPU_K_OUTD.1
urom[306] = 121'h6f8060000000000000000010000000;  // FPU_K_OUTD.2
urom[307] = 121'h6e800043000701b000000000000000;  // FPU_K_OUT4.0
urom[308] = 121'h6f8020000560000000000000000000;  // FPU_K_OUT4.1
urom[309] = 121'h1b000560002ec0000008000000000;  // FPU_K_OUT4.2
urom[310] = 121'h6f8060000007800000000010000000;  // FPU_K_OUT4.3
urom[311] = 121'h6e800043000701b000000000000000;  // FPU_K_OUT1.0
urom[312] = 121'h6f8020000560000000000000000000;  // FPU_K_OUT1.1
urom[313] = 121'h19000560002ec0000008000000000;  // FPU_K_OUT1.2
urom[314] = 121'h6f8060000007800000000010000000;  // FPU_K_OUT1.3
urom[315] = 121'h6e800043000701b000000000000000;  // FPU_K_OUT2.0
urom[316] = 121'h6f8020000560000000000000000000;  // FPU_K_OUT2.1
urom[317] = 121'h1a000560002ec0000008000000000;  // FPU_K_OUT2.2
urom[318] = 121'h6f8060000007800000000010000000;  // FPU_K_OUT2.3
urom[319] = 121'h6e800043000701b000000000000000;  // FPU_K_OUT8.0
urom[320] = 121'h6f8020000560000000000000000000;  // FPU_K_OUT8.1
urom[321] = 121'h6f8040220580000000010000000000;  // FPU_K_OUT8.2
urom[322] = 121'h1b000560002ec0000008000000000;  // FPU_K_OUT8.3
urom[323] = 121'h1b000580002ec0000048000000000;  // FPU_K_OUT8.4
urom[324] = 121'h6f8060000007800000000010000000;  // FPU_K_OUT8.5
urom[325] = 121'h6e800043000701b000000000000000;  // FPU_K_OUT12.0
urom[326] = 121'h6f8020000560000000000000000000;  // FPU_K_OUT12.1
urom[327] = 121'h6f8040220580000000010000000000;  // FPU_K_OUT12.2
urom[328] = 121'h6f80402205a0000000020000000000;  // FPU_K_OUT12.3
urom[329] = 121'h1b000560002ec0000008000000000;  // FPU_K_OUT12.4
urom[330] = 121'h1b000580002ec0000048000000000;  // FPU_K_OUT12.5
urom[331] = 121'h1b0005a0002ec0000088000000000;  // FPU_K_OUT12.6
urom[332] = 121'h6f8060000007800000000010000000;  // FPU_K_OUT12.7
urom[333] = 121'hfabe00;  // FPU_CR.0
urom[334] = 121'h2ab600;  // FPU_CR.1
urom[335] = 121'h32b600;  // FPU_CR.2
urom[336] = 121'h6f81e000000701b000000000000000;  // FPU_CR.3
urom[337] = 121'h1b000360562ec0000006800000080;  // FPU_CR.4
urom[338] = 121'h6f80a0568800000000000000000000;  // FPU_CR.5
urom[339] = 121'h4edb000040000000080;  // FPU_CR.6
urom[340] = 121'h1b000360562ec0000006800000081;  // FPU_CR.7
urom[341] = 121'h6f80a0568800000000010000000000;  // FPU_CR.8
urom[342] = 121'h4edb000040000000081;  // FPU_CR.9
urom[343] = 121'h1b000360562ec0000006800000082;  // FPU_CR.10
urom[344] = 121'h6f80a0568800000000020000000000;  // FPU_CR.11
urom[345] = 121'h4edb000040000000082;  // FPU_CR.12
urom[346] = 121'h6f8060000007800000000010000000;  // FPU_CR.13
urom[347] = 121'h6f80a0028800000000000000000000;  // FPU_CRLR.0
urom[348] = 121'h6f80a0028800000000010000000000;  // FPU_CRLR.1
urom[349] = 121'h6f80a0028800000000020000000000;  // FPU_CRLR.2
urom[350] = 121'h6f8060000000000000000010000000;  // FPU_CRLR.3
urom[351] = 121'h2ad800;  // FPU_CRS.0
urom[352] = 121'h32d800;  // FPU_CRS.1
urom[353] = 121'h6f81e000000701b000000000000000;  // FPU_CRS.2
urom[354] = 121'h6f8080220560000000000000000000;  // FPU_CRS.3
urom[355] = 121'h1b000560002ec0000008000000080;  // FPU_CRS.4
urom[356] = 121'h4edb000040000000080;  // FPU_CRS.5
urom[357] = 121'h6f8080220560000000010000000000;  // FPU_CRS.6
urom[358] = 121'h1b000560002ec0000008000000081;  // FPU_CRS.7
urom[359] = 121'h4edb000040000000081;  // FPU_CRS.8
urom[360] = 121'h6f8080220560000000020000000000;  // FPU_CRS.9
urom[361] = 121'h1b000560002ec0000008000000082;  // FPU_CRS.10
urom[362] = 121'h4edb000040000000082;  // FPU_CRS.11
urom[363] = 121'h6f8060000007800000000010000000;  // FPU_CRS.12
urom[364] = 121'h6f8080220020000000000000000000;  // FPU_CRSR.0
urom[365] = 121'h6f8080220020000000010000000000;  // FPU_CRSR.1
urom[366] = 121'h6f8080220020000000020000000000;  // FPU_CRSR.2
urom[367] = 121'h6f8060000000000000000010000000;  // FPU_CRSR.3
urom[368] = 121'h6f80c0440560000000000000000000;  // FPU_MVM.0
urom[369] = 121'h4d7a800000000000000;  // FPU_MVM.1
urom[370] = 121'heaee00;  // FPU_MVM.2
urom[371] = 121'hf2f200;  // FPU_MVM.3
urom[372] = 121'h6f81e000000701b000000000000000;  // FPU_MVM.4
urom[373] = 121'hfb4a00;  // FPU_MVM.5
urom[374] = 121'haf600;  // FPU_MVM.6
urom[375] = 121'h68fb000000000000000;  // FPU_MVPD.0
urom[376] = 121'hb4a00;  // FPU_MVPD.1
urom[377] = 121'h48fb000000000000000;  // FPU_MVPI.0
urom[378] = 121'haf600;  // FPU_MVPI.1
urom[379] = 121'h1b0003605a2ec0000006800000020;  // FPU_MVL.0
urom[380] = 121'h1b0003605c2ec0000046800000020;  // FPU_MVL.1
urom[381] = 121'h5db000360002ec0000086800000020;  // FPU_MVL.2
urom[382] = 121'h6f81005b7000000000000000000000;  // FPU_MVL.3
urom[383] = 121'h4edb0000c0000000020;  // FPU_MVL.4
urom[384] = 121'h1b0003605a2ec0000006800000021;  // FPU_MVL.5
urom[385] = 121'h1b0003605c2ec0000046800000021;  // FPU_MVL.6
urom[386] = 121'h5db000360002ec0000086800000021;  // FPU_MVL.7
urom[387] = 121'h6f81005b7000000000000000000000;  // FPU_MVL.8
urom[388] = 121'h4edb0000c0000000021;  // FPU_MVL.9
urom[389] = 121'h1b0003605a2ec0000006800000022;  // FPU_MVL.10
urom[390] = 121'h1b0003605c2ec0000046800000022;  // FPU_MVL.11
urom[391] = 121'h5db000360002ec0000086800000022;  // FPU_MVL.12
urom[392] = 121'h6f81005b7000000000000000000000;  // FPU_MVL.13
urom[393] = 121'h4edb0000c0000000022;  // FPU_MVL.14
urom[394] = 121'h1b0003605a2ec0000006800000023;  // FPU_MVL.15
urom[395] = 121'h1b0003605c2ec0000046800000023;  // FPU_MVL.16
urom[396] = 121'h5db000360002ec0000086800000023;  // FPU_MVL.17
urom[397] = 121'h6f81005b7000000000000000000000;  // FPU_MVL.18
urom[398] = 121'h4edb0000c0000000023;  // FPU_MVL.19
urom[399] = 121'h1b0003605a2ec0000006800000024;  // FPU_MVL.20
urom[400] = 121'h1b0003605c2ec0000046800000024;  // FPU_MVL.21
urom[401] = 121'h5db000360002ec0000086800000024;  // FPU_MVL.22
urom[402] = 121'h6f81005b7000000000000000000000;  // FPU_MVL.23
urom[403] = 121'h4edb0000c0000000024;  // FPU_MVL.24
urom[404] = 121'h1b0003605a2ec0000006800000025;  // FPU_MVL.25
urom[405] = 121'h1b0003605c2ec0000046800000025;  // FPU_MVL.26
urom[406] = 121'h5db000360002ec0000086800000025;  // FPU_MVL.27
urom[407] = 121'h6f81005b7000000000000000000000;  // FPU_MVL.28
urom[408] = 121'h4edb0000c0000000025;  // FPU_MVL.29
urom[409] = 121'h1b0003605a2ec0000006800000026;  // FPU_MVL.30
urom[410] = 121'h1b0003605c2ec0000046800000026;  // FPU_MVL.31
urom[411] = 121'h5db000360002ec0000086800000026;  // FPU_MVL.32
urom[412] = 121'h6f81005b7000000000000000000000;  // FPU_MVL.33
urom[413] = 121'h4edb0000c0000000026;  // FPU_MVL.34
urom[414] = 121'h1b0003605a2ec0000006800000027;  // FPU_MVL.35
urom[415] = 121'h1b0003605c2ec0000046800000027;  // FPU_MVL.36
urom[416] = 121'h5db000360002ec0000086800000027;  // FPU_MVL.37
urom[417] = 121'h6f81005b7000000000000000000000;  // FPU_MVL.38
urom[418] = 121'h4edb0000c0000000027;  // FPU_MVL.39
urom[419] = 121'hf3be00;  // FPU_MVL.40
urom[420] = 121'h6f8060000000000000000010000000;  // FPU_MVL.41
urom[421] = 121'h6f80e00005a0000000000000000000;  // FPU_MVS.0
urom[422] = 121'h6f80402205c0000000010000000000;  // FPU_MVS.1
urom[423] = 121'h6f80402205e0000000020000000000;  // FPU_MVS.2
urom[424] = 121'h1b0005a0002ec0000008000000020;  // FPU_MVS.3
urom[425] = 121'h1b0005c0002ec0000048000000020;  // FPU_MVS.4
urom[426] = 121'h1b0005e0002ec0000088000000020;  // FPU_MVS.5
urom[427] = 121'h4edb0000c0000000020;  // FPU_MVS.6
urom[428] = 121'h6f80e00005a0000000000000000000;  // FPU_MVS.7
urom[429] = 121'h6f80402205c0000000010000000000;  // FPU_MVS.8
urom[430] = 121'h6f80402205e0000000020000000000;  // FPU_MVS.9
urom[431] = 121'h1b0005a0002ec0000008000000021;  // FPU_MVS.10
urom[432] = 121'h1b0005c0002ec0000048000000021;  // FPU_MVS.11
urom[433] = 121'h1b0005e0002ec0000088000000021;  // FPU_MVS.12
urom[434] = 121'h4edb0000c0000000021;  // FPU_MVS.13
urom[435] = 121'h6f80e00005a0000000000000000000;  // FPU_MVS.14
urom[436] = 121'h6f80402205c0000000010000000000;  // FPU_MVS.15
urom[437] = 121'h6f80402205e0000000020000000000;  // FPU_MVS.16
urom[438] = 121'h1b0005a0002ec0000008000000022;  // FPU_MVS.17
urom[439] = 121'h1b0005c0002ec0000048000000022;  // FPU_MVS.18
urom[440] = 121'h1b0005e0002ec0000088000000022;  // FPU_MVS.19
urom[441] = 121'h4edb0000c0000000022;  // FPU_MVS.20
urom[442] = 121'h6f80e00005a0000000000000000000;  // FPU_MVS.21
urom[443] = 121'h6f80402205c0000000010000000000;  // FPU_MVS.22
urom[444] = 121'h6f80402205e0000000020000000000;  // FPU_MVS.23
urom[445] = 121'h1b0005a0002ec0000008000000023;  // FPU_MVS.24
urom[446] = 121'h1b0005c0002ec0000048000000023;  // FPU_MVS.25
urom[447] = 121'h1b0005e0002ec0000088000000023;  // FPU_MVS.26
urom[448] = 121'h4edb0000c0000000023;  // FPU_MVS.27
urom[449] = 121'h6f80e00005a0000000000000000000;  // FPU_MVS.28
urom[450] = 121'h6f80402205c0000000010000000000;  // FPU_MVS.29
urom[451] = 121'h6f80402205e0000000020000000000;  // FPU_MVS.30
urom[452] = 121'h1b0005a0002ec0000008000000024;  // FPU_MVS.31
urom[453] = 121'h1b0005c0002ec0000048000000024;  // FPU_MVS.32
urom[454] = 121'h1b0005e0002ec0000088000000024;  // FPU_MVS.33
urom[455] = 121'h4edb0000c0000000024;  // FPU_MVS.34
urom[456] = 121'h6f80e00005a0000000000000000000;  // FPU_MVS.35
urom[457] = 121'h6f80402205c0000000010000000000;  // FPU_MVS.36
urom[458] = 121'h6f80402205e0000000020000000000;  // FPU_MVS.37
urom[459] = 121'h1b0005a0002ec0000008000000025;  // FPU_MVS.38
urom[460] = 121'h1b0005c0002ec0000048000000025;  // FPU_MVS.39
urom[461] = 121'h1b0005e0002ec0000088000000025;  // FPU_MVS.40
urom[462] = 121'h4edb0000c0000000025;  // FPU_MVS.41
urom[463] = 121'h6f80e00005a0000000000000000000;  // FPU_MVS.42
urom[464] = 121'h6f80402205c0000000010000000000;  // FPU_MVS.43
urom[465] = 121'h6f80402205e0000000020000000000;  // FPU_MVS.44
urom[466] = 121'h1b0005a0002ec0000008000000026;  // FPU_MVS.45
urom[467] = 121'h1b0005c0002ec0000048000000026;  // FPU_MVS.46
urom[468] = 121'h1b0005e0002ec0000088000000026;  // FPU_MVS.47
urom[469] = 121'h4edb0000c0000000026;  // FPU_MVS.48
urom[470] = 121'h6f80e00005a0000000000000000000;  // FPU_MVS.49
urom[471] = 121'h6f80402205c0000000010000000000;  // FPU_MVS.50
urom[472] = 121'h6f80402205e0000000020000000000;  // FPU_MVS.51
urom[473] = 121'h1b0005a0002ec0000008000000027;  // FPU_MVS.52
urom[474] = 121'h1b0005c0002ec0000048000000027;  // FPU_MVS.53
urom[475] = 121'h1b0005e0002ec0000088000000027;  // FPU_MVS.54
urom[476] = 121'h4edb0000c0000000027;  // FPU_MVS.55
urom[477] = 121'hebbe00;  // FPU_MVS.56
urom[478] = 121'h6f8060000000000000000010000000;  // FPU_MVS.57
urom[479] = 121'h6f80600000068e3800000010000000;  // FPU_MVE.0
urom[480] = 121'h6f8000430000000000000000000000;  // FBCC.0
urom[481] = 121'h6f8120000000000000000030000000;  // FBCC.1
urom[482] = 121'h6f8000430000000000000000000000;  // FSCC.0
urom[483] = 121'h6e812000d020000000000010000000;  // FSCC.1
urom[484] = 121'h6f8000430000000000000000000000;  // FDBCC.0
urom[485] = 121'h6f81400028a0000000000030000000;  // FDBCC.1
urom[486] = 121'h6f8000430000000000000000000000;  // FTRAPCC.0
urom[487] = 121'h6f8120000000000000000010000000;  // FTRAPCC.1
urom[488] = 121'h6f8000430000000000000000000000;  // FSAVE.0
urom[489] = 121'h6f8160000560000000000000000000;  // FSAVE.1
urom[490] = 121'h4d7a800000000000000;  // FSAVE.2
urom[491] = 121'hec0e00;  // FSAVE.3
urom[492] = 121'h501b000000000000000;  // FSAVE.4
urom[493] = 121'h6fb180220002ec0000008000000040;  // FSAVE.5
urom[494] = 121'h6fb180220002ec0000048000000041;  // FSAVE.6
urom[495] = 121'h6fb180220002ec0000088000000042;  // FSAVE.7
urom[496] = 121'h6fb180220002ec00000c8000000043;  // FSAVE.8
urom[497] = 121'h6fb180220002ec0000108000000044;  // FSAVE.9
urom[498] = 121'h6fb180220002ec0000148000000045;  // FSAVE.10
urom[499] = 121'h6fb180220002ec0000188000000046;  // FSAVE.11
urom[500] = 121'h6fb180220002ec00001c8000000047;  // FSAVE.12
urom[501] = 121'h6fb180220002ec0000208000000048;  // FSAVE.13
urom[502] = 121'h6fb180220002ec0000248000000049;  // FSAVE.14
urom[503] = 121'h6fb180220002ec000028800000004a;  // FSAVE.15
urom[504] = 121'h6fb180220002ec00002c800000004b;  // FSAVE.16
urom[505] = 121'h6fb180220002ec000030800000004c;  // FSAVE.17
urom[506] = 121'h6fb180220002ec000034800000004d;  // FSAVE.18
urom[507] = 121'h6fb180220002ec000038800000004e;  // FSAVE.19
urom[508] = 121'h6fb180220002ec00003c800000004f;  // FSAVE.20
urom[509] = 121'h6fb180220002ec0000408000000050;  // FSAVE.21
urom[510] = 121'h6fb180220002ec0000448000000051;  // FSAVE.22
urom[511] = 121'h6fb180220002ec0000488000000052;  // FSAVE.23
urom[512] = 121'h6fb180220002ec00004c8000000053;  // FSAVE.24
urom[513] = 121'h6fb180220002ec0000508000000054;  // FSAVE.25
urom[514] = 121'h6fb180220002ec0000548000000055;  // FSAVE.26
urom[515] = 121'h6fb180220002ec0000588000000056;  // FSAVE.27
urom[516] = 121'h6fb180220002ec00005c8000000057;  // FSAVE.28
urom[517] = 121'h6fb180220002ec0000608000000058;  // FSAVE.29
urom[518] = 121'h6f8060000000000000000010000000;  // FSAVE.30
urom[519] = 121'h68fb000000000000000;  // FSAVE_PD.0
urom[520] = 121'h6fb180220002ec0000008000000040;  // FSAVE_PD.1
urom[521] = 121'h6fb180220002ec0000048000000041;  // FSAVE_PD.2
urom[522] = 121'h6fb180220002ec0000088000000042;  // FSAVE_PD.3
urom[523] = 121'h6fb180220002ec00000c8000000043;  // FSAVE_PD.4
urom[524] = 121'h6fb180220002ec0000108000000044;  // FSAVE_PD.5
urom[525] = 121'h6fb180220002ec0000148000000045;  // FSAVE_PD.6
urom[526] = 121'h6fb180220002ec0000188000000046;  // FSAVE_PD.7
urom[527] = 121'h6fb180220002ec00001c8000000047;  // FSAVE_PD.8
urom[528] = 121'h6fb180220002ec0000208000000048;  // FSAVE_PD.9
urom[529] = 121'h6fb180220002ec0000248000000049;  // FSAVE_PD.10
urom[530] = 121'h6fb180220002ec000028800000004a;  // FSAVE_PD.11
urom[531] = 121'h6fb180220002ec00002c800000004b;  // FSAVE_PD.12
urom[532] = 121'h6fb180220002ec000030800000004c;  // FSAVE_PD.13
urom[533] = 121'h6fb180220002ec000034800000004d;  // FSAVE_PD.14
urom[534] = 121'h6fb180220002ec000038800000004e;  // FSAVE_PD.15
urom[535] = 121'h6fb180220002ec00003c800000004f;  // FSAVE_PD.16
urom[536] = 121'h6fb180220002ec0000408000000050;  // FSAVE_PD.17
urom[537] = 121'h6fb180220002ec0000448000000051;  // FSAVE_PD.18
urom[538] = 121'h6fb180220002ec0000488000000052;  // FSAVE_PD.19
urom[539] = 121'h6fb180220002ec00004c8000000053;  // FSAVE_PD.20
urom[540] = 121'h6fb180220002ec0000508000000054;  // FSAVE_PD.21
urom[541] = 121'h6fb180220002ec0000548000000055;  // FSAVE_PD.22
urom[542] = 121'h6fb180220002ec0000588000000056;  // FSAVE_PD.23
urom[543] = 121'h6fb180220002ec00005c8000000057;  // FSAVE_PD.24
urom[544] = 121'h6fb180220002ec0000608000000058;  // FSAVE_PD.25
urom[545] = 121'h6f8060000004ec3800000010000000;  // FSAVE_PD.26
urom[546] = 121'h6f8000430000000000000000000000;  // FRESTORE.0
urom[547] = 121'hf48200;  // FRESTORE.1
urom[548] = 121'h501b000000000000000;  // FRESTORE.2
urom[549] = 121'h1b000360562ec0000004000000000;  // FRESTORE.3
urom[550] = 121'h6f81a0560560000000000000000000;  // FRESTORE.4
urom[551] = 121'h4d7a800000000000000;  // FRESTORE.5
urom[552] = 121'h6fb1c0368802ec0000044000000061;  // FRESTORE.6
urom[553] = 121'h6fb1c0368802ec0000084000000062;  // FRESTORE.7
urom[554] = 121'h6fb1c0368802ec00000c4000000063;  // FRESTORE.8
urom[555] = 121'h6fb1c0368802ec0000104000000064;  // FRESTORE.9
urom[556] = 121'h6fb1c0368802ec0000144000000065;  // FRESTORE.10
urom[557] = 121'h6fb1c0368802ec0000184000000066;  // FRESTORE.11
urom[558] = 121'h6fb1c0368802ec00001c4000000067;  // FRESTORE.12
urom[559] = 121'h6fb1c0368802ec0000204000000068;  // FRESTORE.13
urom[560] = 121'h6fb1c0368802ec0000244000000069;  // FRESTORE.14
urom[561] = 121'h6fb1c0368802ec000028400000006a;  // FRESTORE.15
urom[562] = 121'h6fb1c0368802ec00002c400000006b;  // FRESTORE.16
urom[563] = 121'h6fb1c0368802ec000030400000006c;  // FRESTORE.17
urom[564] = 121'h6fb1c0368802ec000034400000006d;  // FRESTORE.18
urom[565] = 121'h6fb1c0368802ec000038400000006e;  // FRESTORE.19
urom[566] = 121'h6fb1c0368802ec00003c400000006f;  // FRESTORE.20
urom[567] = 121'h6fb1c0368802ec0000404000000070;  // FRESTORE.21
urom[568] = 121'h6fb1c0368802ec0000444000000071;  // FRESTORE.22
urom[569] = 121'h6fb1c0368802ec0000484000000072;  // FRESTORE.23
urom[570] = 121'h6fb1c0368802ec00004c4000000073;  // FRESTORE.24
urom[571] = 121'h6fb1c0368802ec0000504000000074;  // FRESTORE.25
urom[572] = 121'h6fb1c0368802ec0000544000000075;  // FRESTORE.26
urom[573] = 121'h6fb1c0368802ec0000584000000076;  // FRESTORE.27
urom[574] = 121'h6fb1c0368802ec00005c4000000077;  // FRESTORE.28
urom[575] = 121'h6fb1c0368802ec0000604000000078;  // FRESTORE.29
urom[576] = 121'h6f8060000000000000000010000000;  // FRESTORE.30
urom[577] = 121'h48fb000000000000000;  // FREST_PI.0
urom[578] = 121'h1b000360562ec0000004000000000;  // FREST_PI.1
urom[579] = 121'h6f81a0560560000000000000000000;  // FREST_PI.2
urom[580] = 121'h4d7a800000000000000;  // FREST_PI.3
urom[581] = 121'h6fb1c0368802ec0000044000000061;  // FREST_PI.4
urom[582] = 121'h6fb1c0368802ec0000084000000062;  // FREST_PI.5
urom[583] = 121'h6fb1c0368802ec00000c4000000063;  // FREST_PI.6
urom[584] = 121'h6fb1c0368802ec0000104000000064;  // FREST_PI.7
urom[585] = 121'h6fb1c0368802ec0000144000000065;  // FREST_PI.8
urom[586] = 121'h6fb1c0368802ec0000184000000066;  // FREST_PI.9
urom[587] = 121'h6fb1c0368802ec00001c4000000067;  // FREST_PI.10
urom[588] = 121'h6fb1c0368802ec0000204000000068;  // FREST_PI.11
urom[589] = 121'h6fb1c0368802ec0000244000000069;  // FREST_PI.12
urom[590] = 121'h6fb1c0368802ec000028400000006a;  // FREST_PI.13
urom[591] = 121'h6fb1c0368802ec00002c400000006b;  // FREST_PI.14
urom[592] = 121'h6fb1c0368802ec000030400000006c;  // FREST_PI.15
urom[593] = 121'h6fb1c0368802ec000034400000006d;  // FREST_PI.16
urom[594] = 121'h6fb1c0368802ec000038400000006e;  // FREST_PI.17
urom[595] = 121'h6fb1c0368802ec00003c400000006f;  // FREST_PI.18
urom[596] = 121'h6fb1c0368802ec0000404000000070;  // FREST_PI.19
urom[597] = 121'h6fb1c0368802ec0000444000000071;  // FREST_PI.20
urom[598] = 121'h6fb1c0368802ec0000484000000072;  // FREST_PI.21
urom[599] = 121'h6fb1c0368802ec00004c4000000073;  // FREST_PI.22
urom[600] = 121'h6fb1c0368802ec0000504000000074;  // FREST_PI.23
urom[601] = 121'h6fb1c0368802ec0000544000000075;  // FREST_PI.24
urom[602] = 121'h6fb1c0368802ec0000584000000076;  // FREST_PI.25
urom[603] = 121'h6fb1c0368802ec00005c4000000077;  // FREST_PI.26
urom[604] = 121'h6fb1c0368802ec0000604000000078;  // FREST_PI.27
urom[605] = 121'h6f80600000068e3800000010000000;  // FREST_PI.28
urom[606] = 121'h120006e00029a00fffe9800000000;  // EXC_FMT0.0
urom[607] = 121'h1b0006800029a00fffa9800000000;  // EXC_FMT0.1
urom[608] = 121'h120006a00031a00fff89800000000;  // EXC_FMT0.2
urom[609] = 121'h1b1e0360002e60000005890000000;  // EXC_FMT0.3
urom[610] = 121'h1b0006c00029a00fffc9800000000;  // EXC_FMT2.0
urom[611] = 121'h120006e00029a00fffa9800000000;  // EXC_FMT2.1
urom[612] = 121'h1b0006800029a00fff69800000000;  // EXC_FMT2.2
urom[613] = 121'h120006a00031a00fff49800000000;  // EXC_FMT2.3
urom[614] = 121'h1b1e0360002e60000005890000000;  // EXC_FMT2.4
urom[615] = 121'h1b0005c00029a00fffc9800000000;  // EXC_FMT7.0
urom[616] = 121'h1b0005a00029a00fff89800000000;  // EXC_FMT7.1
urom[617] = 121'h1b0005800029a00fff49800000000;  // EXC_FMT7.2
urom[618] = 121'h1b0005600029a00fff09800000000;  // EXC_FMT7.3
urom[619] = 121'h1b0002000029a00ffec9800000000;  // EXC_FMT7.4
urom[620] = 121'h1b0002000029a00ffe89800000000;  // EXC_FMT7.5
urom[621] = 121'h1b0002000029a00ffe49800000000;  // EXC_FMT7.6
urom[622] = 121'h1b0006400029a00ffe09800000000;  // EXC_FMT7.7
urom[623] = 121'h1b0006200029a00ffdc9800000000;  // EXC_FMT7.8
urom[624] = 121'h1b0002000029a00ffd89800000000;  // EXC_FMT7.9
urom[625] = 121'h1b0006c00029a00ffd89800000000;  // EXC_FMT7.10
urom[626] = 121'h1b0002000029a00ffd49800000000;  // EXC_FMT7.11
urom[627] = 121'h120002000029a00ffd29800000000;  // EXC_FMT7.12
urom[628] = 121'h120007000029a00ffd09800000000;  // EXC_FMT7.13
urom[629] = 121'h1b0006000029a00ffcc9800000000;  // EXC_FMT7.14
urom[630] = 121'h120006e00029a00ffca9800000000;  // EXC_FMT7.15
urom[631] = 121'h1b0006800029a00ffc69800000000;  // EXC_FMT7.16
urom[632] = 121'h120006a00031a00ffc49800000000;  // EXC_FMT7.17
urom[633] = 121'h1b1e0360002e60000005890000000;  // EXC_FMT7.18
urom[634] = 121'h1b000360522a00000005800000000;  // EXC_RESET.0
urom[635] = 121'h1b000360002a00000045890000000;  // EXC_RESET.1
urom[636] = 121'h7d90003606e2a000ffff6000000000;  // EXC_IRQ.0
urom[637] = 121'h7d8020000660000000000000000000;  // EXC_IRQ.1
urom[638] = 121'h120006e0002d200fffe9800000000;  // EXC_IRQ.2
urom[639] = 121'h1b000680002d200fffa9800000000;  // EXC_IRQ.3
urom[640] = 121'h120006a00035200fff89800000000;  // EXC_IRQ.4
urom[641] = 121'h1b1e0360002e60000005890000000;  // EXC_IRQ.5
urom[642] = 121'h7d90003606e2a000ffff6000000000;  // EXC_IRQM.0
urom[643] = 121'h7d8020000660000000000000000000;  // EXC_IRQM.1
urom[644] = 121'h120006e0002d400fffe9800000000;  // EXC_IRQM.2
urom[645] = 121'h1b000680002d400fffa9800000000;  // EXC_IRQM.3
urom[646] = 121'h120006a00035400fff89800000000;  // EXC_IRQM.4
urom[647] = 121'hf000023be40000010000000000000;  // EXC_IRQM.5
urom[648] = 121'hf000023ae20000020000000000000;  // EXC_IRQM.6
urom[649] = 121'h12000640002d200fffe9800000000;  // EXC_IRQM.7
urom[650] = 121'h1b000680002d200fffa9800000000;  // EXC_IRQM.8
urom[651] = 121'h120006200035200fff89800000000;  // EXC_IRQM.9
urom[652] = 121'h1b1e0360002e60000005890000000;  // EXC_IRQM.10
// ---- end of ap68040_ucode_init.svh ----
end
logic [$bits(uword_t)-1:0] uw_raw;
always_ff @(posedge clk) uw_raw <= urom[na];
assign uw_q = uword_t'(uw_raw);

always_ff @(posedge clk) begin
	if (!nreset) begin
		upc      <= '0;
		uw_v     <= 1'b0;
		exc_mode <= 1'b0;
		first    <= 1'b1;
		ind0     <= 1'b0;
		ind1     <= 1'b0;
		def_v    <= 1'b0;
		def_reg  <= '0;
		def_amt  <= '0;
		ssp      <= R_ISP;
		mv_act   <= 1'b0;
		mv_mask  <= '0;
		mv_off   <= '0;
		mv_cnt   <= '0;
		mv_t11   <= 1'b0;
		mv_fix   <= 2'd0;
		uq_n     <= 2'd0;
		uq0      <= '0;
		uq1      <= '0;
	end
	else begin
		upc  <= na;
		uw_v <= nv;

		// uop FIFO: both outcomes formed without the pop (the back end's
		// stall, a late signal), which selects between them last
		if (uq_pop && uq_n != 2'd0) begin
			uq0  <= (emit && uq_n == 2'd1) ? nu : uq1;
			uq1  <= (emit && uq_n == 2'd2) ? nu : uq1;
			uq_n <= emit ? uq_n : uq_n - 2'd1;
		end
		else begin
			uq0  <= (emit && uq_n == 2'd0) ? nu : uq0;
			uq1  <= (emit && uq_n == 2'd1) ? nu : uq1;
			uq_n <= emit ? uq_n + 2'd1 : uq_n;
		end

		if (emit) begin
			first <= 1'b0;
			if (n_ptr) begin
				if (n_ptr_ea1) ind1 <= 1'b1; else ind0 <= 1'b1;
			end
			else if (n_mv_pre) begin
				mv_t11 <= 1'b1;
			end
			else if (uw.loop && !nu.last) begin
				if (mv_act && mv_mask == 16'd0) mv_fix <= mv_fix + 2'd1;
				mv_act  <= 1'b1;
				mv_mask <= n_mv_rest;
				mv_off  <= (mv_act ? mv_off : ((src.ea0.m == EM_APD) ?
				            -{29'd0, (src.sz == SZ_L) ? 3'd4 : 3'd2} : 32'd0)) +
				           ((src.ea0.m == EM_APD) ? -{29'd0, (src.sz == SZ_L) ? 3'd4 : 3'd2}
				                                  :  {29'd0, (src.sz == SZ_L) ? 3'd4 : 3'd2});
				mv_cnt  <= (mv_act ? mv_cnt : 8'd0) + ((src.sz == SZ_L) ? 8'd4 : 8'd2);
			end
			else if (n_def_set) begin
				def_v   <= 1'b1;
				def_reg <= n_def_reg;
				def_amt <= n_def_amt;
			end
		end
		if (done) begin
			// the next instruction starts with clean per-instruction state
			first  <= 1'b1;
			ind0   <= 1'b0;
			ind1   <= 1'b0;
			def_v  <= 1'b0;
			mv_act <= 1'b0;
			mv_t11 <= 1'b0;
			mv_fix <= 2'd0;
			if (exc_mode) exc_mode <= 1'b0;
		end

		if (flush) begin
			first <= 1'b1;
			ind0  <= 1'b0;
			ind1  <= 1'b0;
			def_v <= 1'b0;
			mv_act <= 1'b0;
			mv_t11 <= 1'b0;
			mv_fix <= 2'd0;
			uq_n  <= 2'd0;
			if (!exc_go) exc_mode <= 1'b0;
		end
		if (exc_go) begin
			exc_mode <= 1'b1;
			first    <= 1'b1;
			ssp      <= exc_ssp;
			uq_n     <= 2'd0;
		end
	end
end

// jump condition of the current word (named for the sequencing block)
logic jc_now;
always_comb begin
	case (uw.jc)
		JC_ALWAYS:   jc_now = 1'b1;
		JC_EXT10:    jc_now = src.ext1[10];
		JC_EXT11:    jc_now = src.ext1[11];
		JC_EA0_MEM:  jc_now = is_mem(src.ea0.m);
		JC_EA0_DN:   jc_now = (src.ea0.m == EM_DN);
		JC_EA0_IMM:  jc_now = (src.ea0.m == EM_IMM);
		JC_SZ_L:     jc_now = (src.sz == SZ_L);
		JC_AY7:      jc_now = (src.opw[2:0] == 3'd7);
		JC_SUPER:    jc_now = smode;
		JC_MASK0:    jc_now = (src.ext1 == 16'd0);
		JC_X1A:      jc_now = src.ext1[15];
		JC_SZ_B:     jc_now = (src.sz == SZ_B);
		JC_EA0_AN:   jc_now = (src.ea0.m == EM_AN);
		JC_EA0_APD:  jc_now = (src.ea0.m == EM_APD);
		JC_EA0_AIP:  jc_now = (src.ea0.m == EM_AIP);
		JC_EXT13:    jc_now = src.ext1[13];
		JC_FP_OC0:   jc_now = (src.ext1[15:13] == 3'b000);
		JC_FP_OC2:   jc_now = (src.ext1[15:13] == 3'b010);
		JC_FP_OC3:   jc_now = (src.ext1[15:13] == 3'b011);
		JC_FP_OC45:  jc_now = (src.ext1[15:14] == 2'b10);
		JC_FP_OC67:  jc_now = (src.ext1[15:14] == 2'b11);
		JC_FMT_1:    jc_now = (src.ext1[12:10] == 3'd6);
		JC_FMT_2:    jc_now = (src.ext1[12:10] == 3'd4);
		JC_FMT_8:    jc_now = (src.ext1[12:10] == 3'd5);
		JC_FMT_12:   jc_now = (src.ext1[12:10] == 3'd2 || src.ext1[12:10] == 3'd3);
		JC_FMT_7:    jc_now = (src.ext1[12:10] == 3'd7);
		JC_CREG_RF:  jc_now = (src.ext1[11:0] == 12'h800) || (src.ext1[11:0] == 12'h803) ||
		                      (src.ext1[11:0] == 12'h804);
		default:     jc_now = 1'b0;
	endcase
end

// synthesis translate_off
always_ff @(posedge clk)
	if (nreset && emit && (dbg_mvd && (dbg_dm || dbg_mvo[31:7] != {25{dbg_mvo[7]}}))) begin
		$display("FAIL: useq: a MOVEM offset %h for AG (merge %b)", dbg_mvo, dbg_dm);
		$finish;
	end
always_ff @(posedge clk)
	if (nreset && emit && dbg_dm && nu.disp != dbg_dpre) begin
		$display("FAIL: useq: a merged uop's displacement %h changed from %h", nu.disp, dbg_dpre);
		$finish;
	end
// synthesis translate_on

endmodule
