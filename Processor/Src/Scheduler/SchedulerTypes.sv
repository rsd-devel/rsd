// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- Types related to an issue queue.
//

package SchedulerTypes;

import MicroArchConf::*;
import BasicTypes::*;
import CacheSystemTypes::*;
import MemoryMapTypes::*;
import MicroOpTypes::*;
import OpFormatTypes::*;
import BypassTypes::*;
import RenameLogicTypes::*;
import LoadStoreUnitTypes::*;
import FetchUnitTypes::*;

// Issue queue
localparam ISSUE_QUEUE_ENTRY_NUM = CONF_ISSUE_QUEUE_ENTRY_NUM;
localparam ISSUE_QUEUE_ENTRY_NUM_BIT_WIDTH = $clog2(ISSUE_QUEUE_ENTRY_NUM);

typedef logic [ISSUE_QUEUE_ENTRY_NUM_BIT_WIDTH-1:0] IssueQueueIndexPath;
typedef logic [ISSUE_QUEUE_ENTRY_NUM_BIT_WIDTH:0] IssueQueueCountPath;

typedef logic [ISSUE_QUEUE_ENTRY_NUM-1:0] IssueQueueOneHotPath;

localparam ISSUE_QUEUE_SRC_REG_NUM = MICRO_OP_SOURCE_REG_NUM;

localparam ISSUE_QUEUE_INT_LATENCY     = 1;
//localparam ISSUE_QUEUE_COMPLEX_LATENCY = COMPLEX_EXEC_STAGE_DEPTH;
localparam ISSUE_QUEUE_COMPLEX_LATENCY = COMPLEX_EXEC_STAGE_DEPTH + 2;
localparam ISSUE_QUEUE_MEM_LATENCY     = 3;

localparam WAKEUP_WIDTH = INT_ISSUE_WIDTH + COMPLEX_ISSUE_WIDTH + LOAD_ISSUE_WIDTH;    // Stores do not wakeup consumers.

// --- Issue queue flush count
// - 例外発生時に、発行キューは例外命令より後方の命令が選択的にフラッシュされる。
//   その際、フリーリストへのインデックスの返却は専用のポートを介して複数サイクルで行われる。
//   ISSUE_QUEUE_RESET_CYCLE はそのサイクル数を表す。
localparam ISSUE_QUEUE_RETURN_INDEX_WIDTH = 2;
localparam ISSUE_QUEUE_RETURN_INDEX_CYCLE
    = (ISSUE_QUEUE_ENTRY_NUM-1) / ISSUE_QUEUE_RETURN_INDEX_WIDTH + 1; // 割り算して切り上げ
localparam ISSUE_QUEUE_RETURN_INDEX_CYCLE_BIT_SIZE
    = $clog2( ISSUE_QUEUE_RETURN_INDEX_CYCLE );

// --- Issue queue reset count
localparam ISSUE_QUEUE_RESET_CYCLE
    = (ISSUE_QUEUE_ENTRY_NUM-1) / (ISSUE_WIDTH+ISSUE_QUEUE_RETURN_INDEX_WIDTH) + 1; // 割り算して切り上げ
localparam ISSUE_QUEUE_RESET_CYCLE_BIT_SIZE
    = $clog2( ISSUE_QUEUE_RESET_CYCLE );


//
// --- Active list 
//
localparam ACTIVE_LIST_ENTRY_NUM = CONF_ACTIVE_LIST_ENTRY_NUM;
localparam ACTIVE_LIST_ENTRY_NUM_BIT_WIDTH = $clog2( ACTIVE_LIST_ENTRY_NUM );
typedef logic [ACTIVE_LIST_ENTRY_NUM_BIT_WIDTH-1:0] ActiveListIndexPath;
typedef logic [ACTIVE_LIST_ENTRY_NUM_BIT_WIDTH:0] ActiveListCountPath;

// Information about the execution of an op.
typedef enum logic [3:0] // ExecutionState
{
    EXEC_STATE_NOT_FINISHED     = 4'b0000,
    EXEC_STATE_SUCCESS          = 4'b0001, // Execution is successfully finished.
    
    EXEC_STATE_REFETCH_THIS     = 4'b0010, // Execution is failed.
                                           // It must be refetch from this op. 
    EXEC_STATE_REFETCH_NEXT     = 4'b0011, // Execution is successfully finished,
                                           // but it must be refetch from next op.
    EXEC_STATE_TRAP_ECALL       = 4'b0100, // Execution causes a trap (ECALL)
    EXEC_STATE_TRAP_EBREAK      = 4'b0101, // Execution causes a trap (EBREAK)
    EXEC_STATE_TRAP_MRET        = 4'b0110,  // Execution causes a MRET

    EXEC_STATE_FAULT_LOAD_MISALIGNED  = 4'b1000,  // Misaligned load is executed
    EXEC_STATE_FAULT_LOAD_VIOLATION   = 4'b1001,  // Load access violation
    EXEC_STATE_FAULT_STORE_MISALIGNED = 4'b1010,  // Misaligned store is executed
    EXEC_STATE_FAULT_STORE_VIOLATION  = 4'b1011,  // Store access violation

    EXEC_STATE_FAULT_INSN_ILLEGAL     = 4'b1100,  // Illegal instruction
    EXEC_STATE_FAULT_INSN_VIOLATION   = 4'b1101,  // Illegal instruction
    EXEC_STATE_FAULT_INSN_MISALIGNED  = 4'b1110   // Misaligned instruction address
} ExecutionState;
localparam EXEC_STATE_BIT_WIDTH = $bits(ExecutionState);

typedef struct packed // ActiveListEntry
{
    `ifndef RSD_DISABLE_DEBUG_REGISTER // Debug info
        OpId      opId;
    `endif

    PC_Path pc;
    
    LRegNumPath logDstRegNum;
    logic writeReg;
    
    logic isLoad;
    logic isStore;
    logic isBranch; // TRUE if the op is BR or RIJ
    logic isEnv;    // TRUE if the op is ECALL/EBREAK
    
    logic last;         // TRUE if this micro-op is the last micro-op in an instruction
    logic undefined;
    
    // For releasing a register to a free list on recovery.
    PRegNumPath  phyDstRegNum;

    // For releasing a register to a free list on commitment.
    // and recovering a RMT.
    PRegNumPath  phyPrevDstRegNum;

    IssueQueueIndexPath prevDependIssueQueuePtr;
    
} ActiveListEntry;


typedef struct packed // ActiveListWriteData
{
    ActiveListIndexPath ptr;
    LoadQueueIndexPath loadQueuePtr;
    StoreQueueIndexPath storeQueuePtr;
    ExecutionState      state;
    PC_Path             pc;
    AddrPath            dataAddr;
    logic               isBranch;
    logic               isStore;
} ActiveListWriteData;


// Convert a pointer of an active list to an "age."
// An "age" can be directly compared with a comparator.
function automatic ActiveListCountPath ActiveListPtrToAge(ActiveListIndexPath ptr, ActiveListIndexPath head);
    ActiveListCountPath age;
    age = ptr;
    if (ptr < head)
        return age + ACTIVE_LIST_ENTRY_NUM; // Wrap around.
    else
        return age;
endfunction


//
// --- OpInfo of Integer Pipeline
//

// IntOpSubInfo と BrOpSubInfo のビット幅を合わせるための　padding の計算をする
localparam INT_SUB_INFO_BIT_WIDTH = 
    $bits(OpOperandType) * 2 + $bits(IntALU_Code) + $bits(ShiftOperandType) + $bits(ShifterPath);
localparam BR_SUB_INFO_BIT_WIDTH =
    $bits(OpOperandType) * 2 + $bits(BranchPred) + $bits(BranchDisplacement);
    
localparam INT_SUB_INFO_PADDING_BIT_WIDTH = 
    BR_SUB_INFO_BIT_WIDTH - INT_SUB_INFO_BIT_WIDTH;

//
typedef struct packed // IntOpInfo
{

    // 論理レジスタを読むかどうか
    OpOperandType operandTypeA;
    OpOperandType operandTypeB;

    IntALU_Code aluCode;

    // 即値
    ShiftOperandType shiftType;
    ShifterPath      shiftIn;

    // BrOpSubInfo とビット幅を合わせるための padding
    logic [INT_SUB_INFO_PADDING_BIT_WIDTH-1:0] padding;
} IntOpSubInfo;

//
typedef struct packed // BrOpInfo
{
    // 論理レジスタを読むかどうか
    OpOperandType operandTypeA;
    OpOperandType operandTypeB;

    BranchPred bPred;
    BranchDisplacement brDisp;        // 分岐ターゲット
} BrOpSubInfo;

typedef union packed    // IntOpInfo
{
    IntOpSubInfo intSubInfo;
    BrOpSubInfo  brSubInfo;
} IntOpInfo;

typedef struct packed // IntIssueQueueEntry
{
`ifndef RSD_DISABLE_DEBUG_REGISTER // Debug info
    OpId      opId;
`endif

    IntOpInfo intOpInfo;

    IntMicroOpSubType opType;
    CondCode cond;
    ActiveListIndexPath activeListPtr;
    LoadQueueIndexPath loadQueueRecoveryPtr;    //for recovery
    StoreQueueIndexPath storeQueueRecoveryPtr;    //for recovery
    OpSrc opSrc;
    OpDst opDst;
    PC_Path pc;
} IntIssueQueueEntry;


//
// --- OpInfo of Complex Integer Pipeline
//

// 1+2=3
typedef struct packed // MulOpInfo
{
    logic mulGetUpper; // 乗算で33-64bit目を結果とするか否か
    IntMUL_Code mulCode;
} MulOpSubInfo;

// 1+2=3
typedef struct packed // DivOpInfo
{
    logic padding;
    IntDIV_Code divCode;
} DivOpSubInfo;

typedef union packed    // ComplexOpInfo
{
    MulOpSubInfo  mulSubInfo;
    DivOpSubInfo  divSubInfo;
} ComplexOpInfo;

typedef struct packed // ComplexIssueQueueEntry
{
`ifndef RSD_DISABLE_DEBUG_REGISTER // Debug info
    OpId      opId;
`endif

    ComplexOpInfo complexOpInfo;
    ComplexMicroOpSubType opType;

    ActiveListIndexPath activeListPtr;
    LoadQueueIndexPath loadQueueRecoveryPtr;    //for recovery
    StoreQueueIndexPath storeQueueRecoveryPtr;    //for recovery
    OpSrc opSrc;
    OpDst opDst;
    PC_Path pc;
} ComplexIssueQueueEntry;

typedef struct packed // MemOpInfo
{
    MemMicroOpSubType opType;

    // 条件コード
    CondCode cond;

    // 論理レジスタを読むかどうか
    OpOperandType operandTypeA;
    OpOperandType operandTypeB;

    // アドレッシング
    AddrOperandImm addrIn;
    logic isAddAddr;    // オフセット加算
    logic isRegAddr;    // レジスタアドレッシング
    MemAccessMode memAccessMode; // signed/unsigned and access size

    // CSR
    CSR_CtrlPath csrCtrl;
    ENV_Code envCode;

    // FENCE.I
    logic isFenceI;

    // Complex
`ifdef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
    MulOpSubInfo mulSubInfo;
    DivOpSubInfo divSubInfo;
`endif

    // Pointer of LSQ
    LoadQueueIndexPath loadQueuePtr;
    StoreQueueIndexPath storeQueuePtr;

    // MSHRをAllocateした命令かどうか
    logic hasAllocatedMSHR;
    MSHR_IndexPath mshrID;

} MemOpInfo;

typedef struct packed // MemIssueQueueEntry
{
`ifndef RSD_DISABLE_DEBUG_REGISTER // Debug info
    OpId      opId;
`endif

    MemOpInfo memOpInfo;
    ActiveListIndexPath activeListPtr;
    LoadQueueIndexPath loadQueueRecoveryPtr;    //for recovery
    StoreQueueIndexPath storeQueueRecoveryPtr;    //for recovery
    OpSrc opSrc;
    OpDst opDst;
    PC_Path pc;
} MemIssueQueueEntry;

//
// Entry of Scheduler
//

typedef struct packed // SchedulerEntry
{
    MicroOpType opType;
    MicroOpSubType opSubType;

    logic srcRegValidA;
    logic srcRegValidB;
    OpSrc opSrc;
    OpDst opDst;

    // Pointer to producers in an issue queue.
    IssueQueueIndexPath srcPtrRegA;
    IssueQueueIndexPath srcPtrRegB;
} SchedulerEntry;


//
// A tag for a source CAM and a ready bit table.
// These tags are used for a ready bit table, thus they are necessary in
// matrix based implementation.
//

// For a physic's register.
typedef struct packed // SchedulerRegTag
{
    PRegNumPath num;
    logic valid;
} SchedulerRegTag;

//
// A pointer for a producer matrix.
//

// For a physical register.
typedef struct packed // SchedulerRegPtr
{
    IssueQueueIndexPath ptr;
    logic valid;
} SchedulerRegPtr;

//
// For the destination operand of an op.
//
typedef struct packed // SchedulerDstTag
{
    SchedulerRegTag  regTag;
} SchedulerDstTag;

// For the source operands of an op.
typedef struct packed // SchedulerSrcTag
{
    SchedulerRegTag  [ISSUE_QUEUE_SRC_REG_NUM-1:0] regTag;
    SchedulerRegPtr  [ISSUE_QUEUE_SRC_REG_NUM-1:0] regPtr;
} SchedulerSrcTag;

// Replay queue
localparam REPLAY_QUEUE_ENTRY_NUM = CONF_REPLAY_QUEUE_ENTRY_NUM;
localparam REPLAY_QUEUE_ENTRY_NUM_BIT_WIDTH = $clog2(REPLAY_QUEUE_ENTRY_NUM);
typedef logic [REPLAY_QUEUE_ENTRY_NUM_BIT_WIDTH-1 : 0] ReplayQueueIndexPath;
typedef logic [REPLAY_QUEUE_ENTRY_NUM_BIT_WIDTH : 0] ReplayQueueCountPath;

// Memory Dependent Predictor
localparam MDT_ENTRY_NUM = CONF_MDT_ENTRY_NUM;
localparam MDT_ENTRY_NUM_BIT_WIDTH = $clog2(MDT_ENTRY_NUM);
typedef logic [MDT_ENTRY_NUM_BIT_WIDTH-1:0] MDT_IndexPath;

typedef struct packed // struct MDT_Entry
{
    logic counter;
    //logic [MDT_ENTRY_WIDTH-1:0] counter; // for expand counter width
} MDT_Entry;

function automatic MDT_IndexPath ToMDT_Index(PC_Path addr);
    return
        addr[
            MDT_ENTRY_NUM_BIT_WIDTH + INSN_ADDR_BIT_WIDTH - 1: 
            INSN_ADDR_BIT_WIDTH
        ];
endfunction

endpackage : SchedulerTypes
