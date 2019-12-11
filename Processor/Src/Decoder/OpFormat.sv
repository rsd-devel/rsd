// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


package OpFormatTypes;

import BasicTypes::*;

// JAL, JALR uses PC+4 as operands
localparam PC_OPERAND_OFFSET = 4;

//
// --- 条件コードの定義
//
typedef enum logic [2:0]    // enum CondCode
{
    COND_EQ  = 3'b000, // EQ  '='
    COND_NE  = 3'b001, // NE  '!='
    COND_LT  = 3'b100, // LT  符号付き'<'
    COND_GE  = 3'b101, // GE  符号付き'>'
    COND_LTU = 3'b110, // LTU 符号なし'<'
    COND_GEU = 3'b111, // GEU 符号なし'>'
    COND_AL  = 3'b010  // AL 常時（無条件）
} CondCode;

//
// 命令タイプ
//
typedef enum logic [2:0]    // enum OpCode
{
    OC_INT_REG = 3'b000,    // 整数演算（レジスタ）
    OC_INT_IMM = 3'b001,    // 整数演算（即値）
    OC_MEM_IMM = 3'b010,    // ロード/ストア（即値オフセット・アドレッシング）
    OC_MEM_REG = 3'b011,    // ロード/ストア（レジスタオフセット・アドレッシング）
    OC_MEM_MUL = 3'b100,    // 複数ロード/ストア
    OC_BR      = 3'b101        // 分岐
} OpCode;


//
// Op命令とOpImm命令のfunct3
//
typedef enum logic [2:0]    // enum OpFunct3
{
    OP_FUNCT3_ADD_SUB   = 3'b000,
    OP_FUNCT3_SLT       = 3'b010,
    OP_FUNCT3_SLTU      = 3'b011,
    OP_FUNCT3_EOR       = 3'b100,
    OP_FUNCT3_OR        = 3'b110,
    OP_FUNCT3_AND       = 3'b111,
    OP_FUNCT3_SLL       = 3'b001,
    OP_FUNCT3_SRL_SRA   = 3'b101
} OpFunct3;

//
// Op命令のfunct7
//
typedef enum logic [6:0]    // enum OpFunct7
{
    OP_FUNCT7_ADD = 7'b0000000,
    OP_FUNCT7_SUB = 7'b0100000
} OpFunct7;

//
// シフト命令のfunct7
//
typedef enum logic [6:0]    // enum ShiftFunct7
{
    SHIFT_FUNCT7_SRL = 7'b0000000,
    SHIFT_FUNCT7_SRA = 7'b0100000
} ShiftFunct7;

//
// RV32Mのfunct7
//
typedef enum logic [6:0]    // enum RV32MFunct7
{
    RV32M_FUNCT7_ALL = 7'b0000001
} RV32MFunct7;

//
// 分岐命令のfunct3
//
typedef enum logic [2:0]    // enum BrFunct3
{
    BRANCH_FUNCT3_BEQ     = 3'b000,
    BRANCH_FUNCT3_BNE     = 3'b001,
    BRANCH_FUNCT3_BLT     = 3'b100,
    BRANCH_FUNCT3_BGE     = 3'b101,
    BRANCH_FUNCT3_BLTU    = 3'b110,
    BRANCH_FUNCT3_BGEU    = 3'b111
} BrFunct3;

//
// Mem命令のfunct3
//
typedef enum logic [2:0]    // enum MemFunct3
{
    MEM_FUNCT3_SIGNED_BYTE          = 3'b000,
    MEM_FUNCT3_SIGNED_HALF_WORD     = 3'b001,
    MEM_FUNCT3_WORD                 = 3'b010,
    MEM_FUNCT3_UNSIGNED_BYTE        = 3'b100,
    MEM_FUNCT3_UNSIGNED_HALF_WORD   = 3'b101
} MemFunct3;

//
// RV32M(乗算・除算・剰余)命令のfunct3
//
typedef enum logic [2:0]    // enum RV32MFunct3
{
    RV32M_FUNCT3_MUL     = 3'b000,
    RV32M_FUNCT3_MULH    = 3'b001,
    RV32M_FUNCT3_MULHSU  = 3'b010,
    RV32M_FUNCT3_MULHU   = 3'b011,
    RV32M_FUNCT3_DIV     = 3'b100,
    RV32M_FUNCT3_DIVU    = 3'b101,
    RV32M_FUNCT3_REM     = 3'b110,
    RV32M_FUNCT3_REMU    = 3'b111
} RV32MFunct3;

//
// Misc-Mem命令のfunct3
//
typedef enum logic [2:0]    // enum MiscMemFunct3
{
    MISC_MEM_FUNCT3_FENCE   = 3'b000, // FENCE
    MISC_MEM_FUNCT3_FENCE_I = 3'b001  // FENCE.I
} MiscMemFunct3;

//
// System 命令の funct3, funct12
//
typedef enum logic [2:0]    // enum SystemFunct3
{
    SYSTEM_FUNCT3_PRIV  = 3'b000,     // Privileged (ecall/ebreak/mret

    SYSTEM_FUNCT3_CSR_RW    = 3'b001, // CSRRW
    SYSTEM_FUNCT3_CSR_RS    = 3'b010, // CSRRS
    SYSTEM_FUNCT3_CSR_RC    = 3'b011, // CSRRC

    SYSTEM_FUNCT3_UNDEFINED = 3'b100,  // ???

    SYSTEM_FUNCT3_CSR_RW_I  = 3'b101, // CSRRWI
    SYSTEM_FUNCT3_CSR_RS_I  = 3'b110, // CSRRSI
    SYSTEM_FUNCT3_CSR_RC_I  = 3'b111  // CSRRCI

} SystemFunct3;

typedef enum logic [11:0]    // enum SystemFunct12
{
    SYSTEM_FUNCT12_ECALL  = 12'b0000_0000_0000, // ECALL
    SYSTEM_FUNCT12_EBREAK = 12'b0000_0000_0001, // EBREAK
    SYSTEM_FUNCT12_MRET   = 12'b0011_0000_0010, // MRET
    SYSTEM_FUNCT12_WFI    = 12'b0001_0000_0101  // WFI
} SystemFunct12;


//
// --- shifter_operand の定義
//


// Shift operand type
typedef enum logic    // enum ShiftOperandType
{
    SOT_IMM_SHIFT = 1'b0,   // Immediate shift
    SOT_REG_SHIFT = 1'b1    // Register shift
} ShiftOperandType;

typedef enum logic [1:0]    // enum ShiftType
{
    ST_LSL = 2'b00, // Logical shift left
    ST_LSR = 2'b01, // Logical shift right
    ST_ASR = 2'b10, // Arithmetic shift right
    ST_ROR = 2'b11  // Rotate
} ShiftType;

typedef enum logic [1:0]    // Imm
{
    RISCV_IMM_R    = 2'b00,
    RISCV_IMM_I    = 2'b01,
    RISCV_IMM_S    = 2'b10,
    RISCV_IMM_U    = 2'b11
} RISCV_ImmType;


//即値 : 5+2+1+20+2 = 30 bit → SHIFTER_WIDTH
typedef struct packed    // struct RISCV_IntOperandImmShift
{
    logic [4:0] shift;
    ShiftType   shiftType;
    logic       isRegShift;
    logic [19:0] imm;
    RISCV_ImmType immType;
} RISCV_IntOperandImmShift;


//
// --- アドレッシング
//

// 即値
localparam ADDR_OPERAND_IMM_WIDTH = 12;
localparam ADDR_SIGN_EXTENTION_WIDTH = ADDR_WIDTH - ADDR_OPERAND_IMM_WIDTH;

typedef struct packed    // struct AddrOperandImm
{
    logic [11:0] imm;    // [11:0] offset
} AddrOperandImm;


// Memory Access Mode (signed / access size)
typedef enum logic [1:0]
{
    MEM_ACCESS_SIZE_BYTE = 2'b00,
    MEM_ACCESS_SIZE_HALF_WORD = 2'b01,
    MEM_ACCESS_SIZE_WORD = 2'b10,
    MEM_ACCESS_SIZE_VEC  = 2'b11
} MemAccessSizeType;

function automatic logic IsMisalignedAddress(input AddrPath addr, input MemAccessSizeType size);
    if (size == MEM_ACCESS_SIZE_BYTE || size == MEM_ACCESS_SIZE_VEC) begin
        return FALSE;
    end
    else if (size == MEM_ACCESS_SIZE_HALF_WORD) begin
        return addr[0:0] != 0 ? TRUE : FALSE;
    end
    else if (size == MEM_ACCESS_SIZE_WORD) begin
        return addr[1:0] != 0 ? TRUE : FALSE;
    end
    else 
        return FALSE;
endfunction

typedef struct packed
{
    logic isSigned;
    MemAccessSizeType size;
} MemAccessMode;

// ディスプレースメント幅: 各分岐命令のディスプレースメントはそれぞれ
// Branch: 12ビット，JAL: 20ビット， JALR: 12ビット
// のビット幅でエンコードされる．
localparam BR_DISP_WIDTH = 20;
typedef logic [BR_DISP_WIDTH-1:0] BranchDisplacement;
// 符号拡張用
localparam BR_DISP_SIGN_EXTENTION_WIDTH = ADDR_WIDTH - BR_DISP_WIDTH;


// ALU code
typedef enum logic [3:0]    // enum ALU_Code
{
    AC_ADD  = 4'b0000,    // ADD    加算
    AC_SLT  = 4'b0010,    // SLT    比較 Rd = if Rs1 < Rs2 then 1 else 0
    AC_SLTU = 4'b0011,    // SLTU   符号なし比較
    AC_EOR  = 4'b0100,    // EOR    排他的論理和
    AC_ORR  = 4'b0110,    // ORR    （包含的）論理和
    AC_AND  = 4'b0111,    // AND    論理積
    AC_SUB  = 4'b0001    // SUB    減算
} IntALU_Code;


// IntMUL code
typedef enum logic [1:0]    // enum IntMUL_Code
{
    AC_MUL    = 2'b00,    // MUL    
    AC_MULH   = 2'b01,    // MULH
    AC_MULHSU = 2'b10,    // MULHSU 
    AC_MULHU  = 2'b11     // MULHU  
} IntMUL_Code;


// IntDIV code
typedef enum logic [1:0]    // enum IntDIV_Code
{
    AC_DIV    = 2'b00,    // DIV    
    AC_DIVU   = 2'b01,    // DIVU
    AC_REM    = 2'b10,    // REM 
    AC_REMU   = 2'b11     // REMU  
} IntDIV_Code;

// CSR operation code
typedef enum logic [1:0]    // enum CSR_Code
{
    CSR_UNKNOWN = 2'b00,    // ???
    CSR_WRITE   = 2'b01,    // WRITE
    CSR_SET     = 2'b10,    // SET
    CSR_CLEAR   = 2'b11     // CLEAR
} CSR_Code;

localparam CSR_NUMBER_WIDTH = 12;
typedef logic [CSR_NUMBER_WIDTH-1:0] CSR_NumberPath;

localparam CSR_IMM_WIDTH = 5;
typedef logic [CSR_IMM_WIDTH-1:0] CSR_ImmPath;

typedef struct packed // 5+1+2=8
{
    CSR_ImmPath imm;
    logic isImm;
    CSR_Code code;
} CSR_CtrlPath;

// Environment operation code
typedef enum logic [2:0]      // enum ENV_Code
{
    ENV_CALL            = 3'b000,    // ECALL
    ENV_BREAK           = 3'b001,    // EBREAK
    ENV_MRET            = 3'b010,    // MRET
    ENV_INSN_ILLEGAL    = 3'b011,    // Executes illegal insturction
    ENV_INSN_VIOLATION  = 3'b100,    // Insturction access violation

    ENV_UNKNOWN         = 3'b101     //
} ENV_Code;




//RISCV Instruction Format

//
// RISCV 命令タイプ
//
typedef enum logic [6:0]    // enum OpCode
{
    RISCV_OP_IMM    = 7'b0010011,
    RISCV_OP        = 7'b0110011,
    RISCV_LUI       = 7'b0110111,
    RISCV_AUIPC     = 7'b0010111,
    RISCV_JAL       = 7'b1101111,
    RISCV_JALR      = 7'b1100111,
    RISCV_BR        = 7'b1100011,
    RISCV_LD        = 7'b0000011,
    RISCV_ST        = 7'b0100011,
    RISCV_MISC_MEM  = 7'b0001111,
    RISCV_SYSTEM    = 7'b1110011
} RISCV_OpCode;


// R-Type
typedef struct packed
{
    logic [6:0]     funct7;     // [31:25] funct7
    logic [4:0]     rs2;        // [24:20] Rs2
    logic [4:0]     rs1;        // [19:15] Rs1
    logic [2:0]     funct3;     // [14:12] funct3
    logic [4:0]     rd;         // [11: 7] Rd
    RISCV_OpCode    opCode;     // [ 6: 0] 命令タイプ
} RISCV_ISF_Common;

// R-Type
typedef struct packed
{
    logic [6:0]     funct7;     // [31:25] funct7
    logic [4:0]     rs2;        // [24:20] Rs2
    logic [4:0]     rs1;        // [19:15] Rs1
    logic [2:0]     funct3;     // [14:12] funct3
    logic [4:0]     rd;         // [11: 7] Rd
    RISCV_OpCode    opCode;     // [ 6: 0] 命令タイプ
} RISCV_ISF_R;

// I-Type
typedef struct packed
{
    logic [11:0]    imm;        // [31:20] Imm
    logic [4:0]     rs1;        // [19:15] Rs1
    logic [2:0]     funct3;     // [14:12] funct3
    logic [4:0]     rd;         // [11: 7] Rd
    RISCV_OpCode    opCode;     // [ 6: 0] 命令タイプ
} RISCV_ISF_I;

// S-Type
typedef struct packed
{
    logic [6:0]     imm2;       // [31:25] imm[11:5]
    logic [4:0]     rs2;        // [24:20] Rs2
    logic [4:0]     rs1;        // [19:15] Rs1
    logic [2:0]     funct3;     // [14:12] funct3
    logic [4:0]     imm1;       // [11: 7] imm[4:0]
    RISCV_OpCode    opCode;     // [ 6: 0] 命令タイプ
} RISCV_ISF_S;

// U-Type
typedef struct packed
{
    logic [19:0]    imm;        // [31:12] imm
    logic [4:0]     rd;         // [11: 7] Rd
    RISCV_OpCode    opCode;     // [ 6: 0] 命令タイプ
} RISCV_ISF_U;

// B-Type 
typedef struct packed 
{ 
    logic           imm12;      // [31:31] imm[12] 
    logic [5:0]     imm10_5;    // [30:25] imm[10:5] 
    logic [4:0]     rs2;        // [24:20] Rs2 
    logic [4:0]     rs1;        // [19:15] Rs1 
    logic [2:0]     funct3;     // [14:12] funct3 
    logic [3:0]     imm4_1;     // [11:8]  imm[4:1] 
    logic           imm11;      // [7:7]   imm[11] 
    RISCV_OpCode    opCode;     // [ 6: 0] 命令タイプ 
} RISCV_ISF_B;

// J-Type 
typedef struct packed 
{ 
    logic           imm20;      // [31:31] imm[20] 
    logic [9:0]     imm10_1;    // [30:21] imm[10:1] 
    logic           imm11;      // [20:20] imm[11] 
    logic [7:0]     imm19_12;   // [19:12] imm[19:12] 
    logic [4:0]     rd;         // [11: 7] Rd 
    RISCV_OpCode    opCode;     // [ 6: 0] 命令タイプ 
} RISCV_ISF_J;

// MISC-MEM 
typedef struct packed 
{ 
    logic [3:0] reserved;       // [31:28] reserved
    logic pi;                   // [27:27] pi
    logic po;                   // [26:26] po
    logic pr;                   // [25:25] pr
    logic pw;                   // [24:24] pw
    logic si;                   // [23:23] si
    logic so;                   // [22:22] so
    logic sr;                   // [21:21] sr
    logic sw;                   // [20:20] sw
    logic [4:0]     rs1;        // [19:15] Rs1
    logic [2:0]     funct3;     // [14:12] funct3
    logic [4:0]     rd;         // [11: 7] Rd 
    RISCV_OpCode    opCode;     // [ 6: 0] 命令タイプ 
} RISCV_ISF_MISC_MEM;

// SYSTEM
typedef struct packed 
{ 
    logic [11:0]    funct12;    // [31:20] csr
    logic [4:0]     rs1;        // [19:15] Rs1
    logic [2:0]     funct3;     // [14:12] funct3
    logic [4:0]     rd;         // [11: 7] Rd 
    RISCV_OpCode    opCode;     // [ 6: 0] 命令タイプ 
} RISCV_ISF_SYSTEM;


//
// ---RISCV→ALUCODE の変換
//
function automatic void RISCV_DecodeOpImmFunct3(
    output IntALU_Code aluCode,
    input OpFunct3 funct3
);
    case(funct3)
        OP_FUNCT3_ADD_SUB : begin  //ADDI
            aluCode = AC_ADD;
        end
        OP_FUNCT3_SLT : begin  //SLTI
            aluCode = AC_SLT;
        end
        OP_FUNCT3_SLTU : begin  //SLTUI
            aluCode = AC_SLTU;
        end
        OP_FUNCT3_EOR : begin  //EORI
            aluCode = AC_EOR;
        end
        OP_FUNCT3_OR : begin  //ORI
            aluCode = AC_ORR;
        end
        OP_FUNCT3_AND : begin  //ANDI
            aluCode = AC_AND;
        end
        OP_FUNCT3_SLL : begin //SLLI
            aluCode = AC_AND;
        end
        OP_FUNCT3_SRL_SRA : begin //SRLI, SRAI
            aluCode = AC_AND;
        end
        default : begin
            aluCode = AC_AND; 
        end
    endcase // funct3
endfunction

function automatic void RISCV_DecodeOpFunct3(
    output IntALU_Code aluCode,
    input OpFunct3 funct3,
    input OpFunct7 funct7
);
    case(funct3)
        OP_FUNCT3_ADD_SUB : begin  //ADD or SUB
            if(funct7==OP_FUNCT7_ADD) begin
                aluCode = AC_ADD;
            end else begin
                aluCode = AC_SUB;
            end
        end
        OP_FUNCT3_SLT : begin  //SLT
            aluCode = AC_SLT;
        end
        OP_FUNCT3_SLTU : begin  //SLTU
            aluCode = AC_SLTU;
        end
        OP_FUNCT3_EOR : begin  //EOR
            aluCode = AC_EOR;
        end
        OP_FUNCT3_OR : begin  //OR
            aluCode = AC_ORR;
        end
        OP_FUNCT3_AND : begin  //AND
            aluCode = AC_AND;
        end
        OP_FUNCT3_SLL : begin //SLL
            aluCode = AC_AND;
        end
        OP_FUNCT3_SRL_SRA : begin //SRL, SRA
            aluCode = AC_AND;
        end
        default : begin
            aluCode = AC_AND;
        end
    endcase // funct3
endfunction


//
// ---RISCV→ConditionCode の変換
//      ConditionCodeはARMのものを変更して使う
function automatic void RISCV_DecodeBrFunct3(
    output CondCode condCode,
    input BrFunct3 funct3
);
    case(funct3)
        BRANCH_FUNCT3_BEQ : begin  //BEQ
            condCode = COND_EQ;
        end
        BRANCH_FUNCT3_BNE : begin  //BNE
            condCode = COND_NE;
        end
        BRANCH_FUNCT3_BLT : begin  //BLT
            condCode = COND_LT;
        end
        BRANCH_FUNCT3_BGE : begin  //BGE
            condCode = COND_GE;
        end
        BRANCH_FUNCT3_BLTU : begin  //BLTU
            condCode = COND_LTU;
        end
        BRANCH_FUNCT3_BGEU : begin  //BGEU
            condCode = COND_GEU;
        end
        default : begin
            condCode = COND_AL;
        end
    endcase // funct3
endfunction

//
// ---LD/ST のサイズの変換
//
function automatic void RISCV_DecodeMemAccessMode(
    output MemAccessMode memAccessMode,
    input MemFunct3 funct3
);
    case(funct3)
        MEM_FUNCT3_SIGNED_BYTE : begin  //LB, SB
            memAccessMode.isSigned = TRUE;
            memAccessMode.size = MEM_ACCESS_SIZE_BYTE;
        end
        MEM_FUNCT3_SIGNED_HALF_WORD : begin  //LH, SH
            memAccessMode.isSigned = TRUE;
            memAccessMode.size = MEM_ACCESS_SIZE_HALF_WORD;
        end
        MEM_FUNCT3_WORD : begin  //LW, SW
            memAccessMode.isSigned = TRUE;
            memAccessMode.size = MEM_ACCESS_SIZE_WORD;
        end
        MEM_FUNCT3_UNSIGNED_BYTE : begin  //LBU
            memAccessMode.isSigned = FALSE;
            memAccessMode.size = MEM_ACCESS_SIZE_BYTE;
        end
        MEM_FUNCT3_UNSIGNED_HALF_WORD : begin  //LHU
            memAccessMode.isSigned = FALSE;
            memAccessMode.size = MEM_ACCESS_SIZE_HALF_WORD;
        end
        default : begin  //WORD
            memAccessMode.isSigned = TRUE;
            memAccessMode.size = MEM_ACCESS_SIZE_BYTE;
        end
    endcase
endfunction

function automatic void RISCV_DecodeComplexOpFunct3(
    output IntMUL_Code mulCode,
    output IntDIV_Code divCode,
    input RV32MFunct3 funct3
);
    case(funct3)
        RV32M_FUNCT3_MUL : begin  //ADD or SUB
            mulCode = AC_MUL;
            divCode = AC_DIV;
        end
        RV32M_FUNCT3_MULH : begin  //SLT
            mulCode = AC_MULH;
            divCode = AC_DIV;
        end
        RV32M_FUNCT3_MULHSU : begin  //SLTU
            mulCode = AC_MULHSU;
            divCode = AC_DIV;
        end
        RV32M_FUNCT3_MULHU : begin  //EOR
            mulCode = AC_MULHU;
            divCode = AC_DIV;
        end
        RV32M_FUNCT3_DIV : begin  //OR
            mulCode = AC_MUL;
            divCode = AC_DIV;
        end
        RV32M_FUNCT3_DIVU : begin  //AND
            mulCode = AC_MUL;
            divCode = AC_DIVU;
        end
        RV32M_FUNCT3_REM : begin //SLL
            mulCode = AC_MUL;
            divCode = AC_REM;
        end
        RV32M_FUNCT3_REMU : begin //SRL, SRA
            mulCode = AC_MUL;
            divCode = AC_REMU;
        end
        default : begin
            mulCode = AC_MUL;
            divCode = AC_DIV;
        end
    endcase // funct3
endfunction

//
// brDispのデコード
//
function automatic BranchDisplacement GetBranchDisplacement(
    input RISCV_ISF_B isfBr
);
    return
    {
        {9{isfBr.imm12}},   // 9 bits sign extention
        isfBr.imm11,    // 1 bits
        isfBr.imm10_5,  // 6 bits
        isfBr.imm4_1    // 4 bits
    };
endfunction

function automatic BranchDisplacement GetJAL_Target(
    input RISCV_ISF_J isfJAL
);
    return
    {
        isfJAL.imm20,    //  1 bits
        isfJAL.imm19_12, //  8 bits
        isfJAL.imm11,    //  1 bits
        isfJAL.imm10_1   // 10 bits
    };
endfunction

function automatic BranchDisplacement GetJALR_Target(
    input RISCV_ISF_I isfJALR
);
    return
    {
        {8{isfJALR.imm[11]}},   // 8 bits sign extention
        isfJALR.imm             // 12 bits
    };
endfunction

//
// signed extention
//
function automatic logic [19:0] ShamtExtention(
    input RISCV_ISF_R isfR
);
    return { 15'h0, isfR.rs2 };
endfunction

function automatic logic [19:0] I_TypeImmExtention(
    input RISCV_ISF_I isfI
);
    return { {8{isfI.imm[11]}}, isfI.imm };
endfunction

function automatic AddrPath ExtendBranchDisplacement(
    input BranchDisplacement brDisp
);
    return
    {
        { (ADDR_WIDTH-BR_DISP_WIDTH-1){brDisp[BR_DISP_WIDTH-1]} },
        brDisp,
        1'b0
    };
endfunction

function automatic AddrPath ExtendJALR_Target(
    input BranchDisplacement brDisp
);
    return
    {
        { (ADDR_WIDTH-BR_DISP_WIDTH){brDisp[BR_DISP_WIDTH-1]} },
        brDisp
    };
endfunction


function automatic AddrPath AddJALR_TargetOffset(    
    input AddrPath data, input BranchDisplacement disp
);
    AddrPath target;
    target = data + ExtendJALR_Target(disp);
    target[0] = 1'b0;   // Mask the LSB
    return target;
endfunction


endpackage

