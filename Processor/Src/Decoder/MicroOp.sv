// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Definitions related to micro ops.
//


package MicroOpTypes;

import BasicTypes::*;
import OpFormatTypes::*;


localparam LINK_REGISTER = 5'h 1;
localparam MICRO_OP_TMP_REGISTER = 4'h f;
localparam ZERO_REGISTER = 5'h 0;

localparam MICRO_OP_MAX_NUM = 3;     // An instruction is decoded to up to 3 micro ops.
localparam MICRO_OP_INDEX_BITS = 2;  
typedef logic [MICRO_OP_INDEX_BITS-1:0] MicroOpIndex;   // マイクロOp のインデックス
typedef logic [MICRO_OP_INDEX_BITS  :0] MicroOpCount;


localparam ALL_DECODED_MICRO_OP_WIDTH = MICRO_OP_MAX_NUM * DECODE_WIDTH;
localparam ALL_DECODED_MICRO_OP_WIDTH_BIT_SIZE = MICRO_OP_INDEX_BITS + DECODE_WIDTH_BIT_SIZE;

typedef logic [ALL_DECODED_MICRO_OP_WIDTH-1:0] AllDecodedMicroOpPath;
typedef logic [ALL_DECODED_MICRO_OP_WIDTH-DECODE_WIDTH-1:0] RemainingDecodedMicroOpPath;
typedef logic [ALL_DECODED_MICRO_OP_WIDTH_BIT_SIZE-1:0] AllDecodedMicroOpIndex;


localparam MICRO_OP_SOURCE_REG_NUM = 2;

typedef enum logic [1:0]
{
    MOP_TYPE_INT     = 2'b00,
    MOP_TYPE_COMPLEX = 2'b01,
    MOP_TYPE_MEM     = 2'b10
} MicroOpType;

// 各サブタイプは，パイプライン中で処理を見分けるために使用される
typedef enum logic [2:0]
{
    INT_MOP_TYPE_ALU       = 3'b000,
    INT_MOP_TYPE_SHIFT     = 3'b001,

    INT_MOP_TYPE_BR        = 3'b010,
    INT_MOP_TYPE_RIJ       = 3'b011
} IntMicroOpSubType;

typedef enum logic [2:0]
{
    COMPLEX_MOP_TYPE_MUL       = 3'b000,
    COMPLEX_MOP_TYPE_DIV       = 3'b001   // DIV演算器を使うもの(DIVとREM)
`ifdef RSD_ENABLE_VECTOR_PATH
    COMPLEX_MOP_TYPE_VEC_ADD   = 3'b011,
    COMPLEX_MOP_TYPE_VEC_MUL   = 3'b100
`endif
} ComplexMicroOpSubType;

typedef enum logic [2:0]
{
    MEM_MOP_TYPE_LOAD      = 3'b000,
    MEM_MOP_TYPE_STORE     = 3'b001,

    // Mem パイプで乗除算をやる場合のコード
    MEM_MOP_TYPE_MUL       = 3'b010,
    MEM_MOP_TYPE_DIV       = 3'b011,

    MEM_MOP_TYPE_CSR       = 3'b100, // CSR access
    MEM_MOP_TYPE_FENCE     = 3'b101, // fence
    MEM_MOP_TYPE_ENV       = 3'b110  // env

} MemMicroOpSubType;

typedef union packed    // OpSubType
{
    IntMicroOpSubType     intType;
    ComplexMicroOpSubType complexType;
    MemMicroOpSubType     memType;
} MicroOpSubType;

typedef struct packed // OpId
{
    OpSerial sid;
    MicroOpIndex mid;
} OpId;

// The type of operand.
typedef enum logic [1:0]    // enum OperandType
{
    OOT_REG = 2'b00,   // Register
    OOT_IMM = 2'b01,   // Immediate
    OOT_PC  = 2'b10    // PC
} OpOperandType;


//
// The eperands of micro-ops
// The order of fields is important. The order must be fixed for simplifying a decoder.
//

// Int: 6+6+6+ 4+ 1+ 30=53 bits
typedef struct packed // IntMicroOpOperand
{
    // 論理レジスタ番号
    LRegNumPath dstRegNum;
    LRegNumPath srcRegNumA;    // レジスタN 相当
    LRegNumPath srcRegNumB;    // 第2オペランド

    // ALU
    IntALU_Code aluCode;

    // Shift
    ShiftOperandType shiftType;

    // Shifter operand and imm
    ShifterPath shiftIn;
} IntMicroOpOperand;

// Mem: 6+6+6 +1+1+3 +8 +15 +12 = 18+5+8+10+12 = 53 bits
typedef struct packed // MemMicroOpOperand
{
    // 論理レジスタ番号
    LRegNumPath dstRegNum;
    LRegNumPath srcRegNumA;    // レジスタN 相当
    LRegNumPath srcRegNumB;    // 第2オペランド

    logic isAddAddr;    // オフセット加算
    logic isRegAddr;    // レジスタアドレッシング
    MemAccessMode memAccessMode; // signed/unsigned and access size

    CSR_CtrlPath csrCtrl;
    logic [9:0] padding; //　padding

    // Address offset or CSR number
    AddrOperandImm addrIn;
} MemMicroOpOperand;

// Branch:6+6+6 +15 +20=53 bits
typedef struct packed // BrMicroOpOperand
{
    // 論理レジスタ番号
    LRegNumPath dstRegNum;
    LRegNumPath srcRegNumA;    // レジスタN 相当
    LRegNumPath srcRegNumB;    // 第2オペランド
    logic [14:0] padding;       // padding
    BranchDisplacement brDisp;  // Branch offset.
} BrMicroOpOperand;

// Complex Integer: 6+6+6 +1 +16 +18 = 35+18= 53 bits
typedef struct packed // ComplexMicroOpOperand
{
    // 論理レジスタ番号
    LRegNumPath dstRegNum;
    LRegNumPath srcRegNumA;    // レジスタN 相当
    LRegNumPath srcRegNumB;    // 第2オペランド

    logic mulGetUpper;  // 乗算結果の33-64bit目を使用
    IntMUL_Code mulCode;
    IntDIV_Code divCode;

    logic [15:0] padding;        // Padding field.
    logic [13:0] riscv_padding; // RISCV用のpadding
} ComplexMicroOpOperand;

// MiscMem: 6+6+6 +1 +16 +18 = 35+18= 53 bits
typedef struct packed // MiscMemMicroOpOperand
{
    // 論理レジスタ番号
    LRegNumPath dstRegNum;
    LRegNumPath srcRegNumA;    // レジスタN 相当
    LRegNumPath srcRegNumB;    // 第2オペランド

    logic fence;
    logic fenceI;

    logic [14:0] padding;        // Padding field.
    logic [17:0] riscv_padding; // RISCV用のpadding
} MiscMemMicroOpOperand;

// MiscMem: 6+6+6 +3+1 +19 +12 = 18+4+19+12= 53 bits
typedef struct packed // SystemMicroOpOperand
{
    // 論理レジスタ番号
    LRegNumPath dstRegNum;
    LRegNumPath srcRegNumA;    // レジスタN 相当
    LRegNumPath srcRegNumB;    // 第2オペランド

    ENV_Code envCode;
    logic isEnv;

    logic [18:0] padding;        // Padding field.

    logic [11:0] imm;
} SystemMicroOpOperand;

typedef union packed    // MicroOpOperand
{
    IntMicroOpOperand     intOp;
    MemMicroOpOperand     memOp;
    BrMicroOpOperand      brOp;
    ComplexMicroOpOperand complexOp;
    MiscMemMicroOpOperand miscMemOp;
    SystemMicroOpOperand  systemOp;
} MicroOpOperand;


typedef struct packed // OpInfo
{
    // 条件コード
    CondCode cond;

    // 命令の種類
    MicroOpType mopType;
    MicroOpSubType mopSubType;
    
    // The operands of this micro op.
    MicroOpOperand operand;

    OpOperandType opTypeA;
    OpOperandType opTypeB;

    logic writeReg;     // レジスタ書き込みを行うかどうか
    
    // 無効な命令
    logic undefined;    // Undefined op.
    logic unsupported;  // Defined, but unsuported.
    
    // マイクロOp に分割されているかどうか
    logic split;
    
    // Whether this micro op is valid or not.
    logic valid;

    // Whether this micro op is the last micro op in an original instruction.
    logic last;
    
    // マイクロOp のインデックス
    MicroOpIndex mid;

    // This instruction needs serialization.
    // That is, 
    // * this instruction is not fed to the succeeding stages until all the 
    // preceding instructions are retired. 
    // * The succeeding instructions are never fetched until this instruction 
    // is retired. 
    // * Already fetched succeeding instructions are flushed when this 
    // instruction is decoded.
    logic serialized;    
} OpInfo;

typedef struct packed { // InsnInfo
    logic writePC;  // This instruction writes the PC.

    // call/return
    logic isCall;
    logic isReturn;
    
    // PC relative (JAL, branch)
    logic isRelBranch;

    // See comments of "serialized" in OpInfo
    logic isSerialized;    
} InsnInfo;


endpackage

