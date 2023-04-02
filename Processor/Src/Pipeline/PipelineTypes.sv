// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// ---Pipeline Registers
//

package PipelineTypes;

import MicroOpTypes::*;
import BasicTypes::*;
import OpFormatTypes::*;
import BypassTypes::*;
import RenameLogicTypes::*;
import LoadStoreUnitTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;
import FetchUnitTypes::*;
import MemoryMapTypes::*;
import CacheSystemTypes::*;

// Controll of a pipeline
// See comments in Controller
typedef struct packed// struct PipelineControll
{
    logic stall;
    logic clear;
} PipelineControll;


// For Recovery
// Phase of a pipeline
// See code of RecoveryManager.sv
typedef enum logic[1:0]
{
    PHASE_COMMIT = 0,
    PHASE_RECOVER_0 = 1,    // The first cycle of a recovery phase.
    PHASE_RECOVER_1 = 2
} PipelinePhase;

// Exception Type
typedef enum logic [2:0] { // RefetchType
    // Re-fetch starts from the PC of an instruction that causes an exception.
    // This re-fetch occurs on store-load-forwarding miss when a load attempts 
    // to read data whose range is outside the range of the stored data.
    // It is determined in MemoryTagAccessStage.
    REFETCH_TYPE_THIS_PC                = 3'b000,   

    // Re-fetch starts from the next PC of an instruction that causes an exception.
    // This re-fetch occurs on a load speculation miss when a load speculatively 
    // reads a value before the dependent store is executed (memAccessOrderViolation).
    // Is is determined in MemoryTagAccessStage.
    REFETCH_TYPE_NEXT_PC                = 3'b001,
    REFETCH_TYPE_STORE_NEXT_PC          = 3'b010,

    // Re-fetch from a correct branch target.
    // This re-fetch occurs on a branch prediction miss.
    REFETCH_TYPE_BRANCH_TARGET          = 3'b011,

    // Re-fetch from a PC specified by CSR.
    // This refetch occurs on a trap or an exception.
    REFETCH_TYPE_NEXT_PC_TO_CSR_TARGET  = 3'b100,
    REFETCH_TYPE_THIS_PC_TO_CSR_TARGET  = 3'b101
} RefetchType;

//
// Pipeline registers.
// These registers put at the head of each stage.
// For example, DecodeStageRegPath is put at the head of a decode stage, and
// they are written by a fetch stage.
//

typedef struct packed { // FetchStageRegPath
`ifndef RSD_DISABLE_DEBUG_REGISTER
    OpSerial sid;
`endif
    logic valid;
    PC_Path pc;
} FetchStageRegPath;

typedef struct packed // PreDecodeStageRegPath
{
`ifndef RSD_DISABLE_DEBUG_REGISTER
    OpSerial sid;
`endif

    logic    valid;     // Valid flag. If this is 0, this op is treated as NOP.
    InsnPath insn;      // Instruction code
    PC_Path pc;
    BranchPred brPred;
} PreDecodeStageRegPath;

typedef struct packed // DecodeStageRegPath
{
`ifndef RSD_DISABLE_DEBUG_REGISTER
    OpSerial sid;
`endif

    logic    valid;     // Valid flag. If this is 0, this op is treated as NOP.
    InsnPath insn;      // Instruction code
    PC_Path pc;
    BranchPred brPred;

    OpInfo [MICRO_OP_MAX_NUM-1:0] microOps;  // Decoded micro ops
    InsnInfo insnInfo;   // Whether a decoded instruction is branch or not.
} DecodeStageRegPath;


typedef struct packed // RenameStageRegPath
{
`ifndef RSD_DISABLE_DEBUG_REGISTER
    OpId      opId;
`endif

    logic    valid;     // Valid flag. If this is 0, this op is treated as NOP.
    OpInfo   opInfo;    // Decoded micro op.
    PC_Path pc;
    BranchPred bPred;
} RenameStageRegPath;

typedef struct packed // DispatchStageRegPath
{
`ifndef RSD_DISABLE_DEBUG_REGISTER
    OpId      opId;
`endif

    logic    valid;     // Valid flag. If this is 0, this op is treated as NOP.
    OpInfo   opInfo;    // Decoded micro op.

    PC_Path pc;        // Program counter
    BranchPred brPred;  // Branch prediction result.

    // Renamed physical register numbers.
    PRegNumPath phySrcRegNumA;
    PRegNumPath phySrcRegNumB;
`ifdef RSD_MARCH_FP_PIPE
    PRegNumPath phySrcRegNumC;
`endif
    PRegNumPath phyDstRegNum;
    PRegNumPath phyPrevDstRegNum;  // For releasing a register.

    // Source pointer for a matrix scheduler.
    IssueQueueIndexPath srcIssueQueuePtrRegA;
    IssueQueueIndexPath srcIssueQueuePtrRegB;
`ifdef RSD_MARCH_FP_PIPE
    IssueQueueIndexPath srcIssueQueuePtrRegC;
`endif

    IssueQueueIndexPath issueQueuePtr;
    ActiveListIndexPath activeListPtr;
    LoadQueueIndexPath loadQueuePtr;
    StoreQueueIndexPath storeQueuePtr;
    LoadQueueIndexPath loadQueueRecoveryPtr;
    StoreQueueIndexPath storeQueueRecoveryPtr;
} DispatchStageRegPath;

typedef struct packed // IssueStageRegPath
{
    logic    valid;     // Valid flag. If this is 0, this op is treated as NOP.
    IssueQueueIndexPath issueQueuePtr;
} IssueStageRegPath;

//
// Integer back end
//
typedef struct packed // IntegerRegisterReadStageRegPath
{
`ifndef RSD_DISABLE_DEBUG_REGISTER
    OpId      opId;
`endif

    logic valid;     // Valid flag. If this is 0, its op is treated as NOP.
    IntIssueQueueEntry intQueueData;
} IntegerRegisterReadStageRegPath;


typedef struct packed // IntegerExecutionStageRegPath
{
`ifndef RSD_DISABLE_DEBUG_REGISTER
    OpId      opId;
`endif

    logic valid;      // Valid flag. If this is 0, its op is treated as NOP.
    IntIssueQueueEntry intQueueData;

    // register read out
    PRegDataPath operandA;
    PRegDataPath operandB;

    // Bypass control
    BypassControll bCtrl;
} IntegerExecutionStageRegPath;


typedef struct packed // IntegerRegisterWriteStageRegPath
{

`ifndef RSD_DISABLE_DEBUG_REGISTER
    OpId      opId;
`endif

    logic valid;  // Valid flag. If this is 0, its op is treated as NOP.
    IntIssueQueueEntry intQueueData;

    PRegDataPath dataOut;   // Result of ALU/shifter/Load

    logic brMissPred;
    BranchResult brResult;  // Result of branch
} IntegerRegisterWriteStageRegPath;

//
// ComplexInteger back end
//
typedef struct packed // ComplexIntegerRegisterReadStageRegPath
{
`ifndef RSD_DISABLE_DEBUG_REGISTER
    OpId      opId;
`endif

    logic valid;     // Valid flag. If this is 0, its op is treated as NOP.
    logic replay;
    ComplexIssueQueueEntry complexQueueData;
} ComplexIntegerRegisterReadStageRegPath;


typedef struct packed // ComplexIntegerExecutionStageRegPath
{
`ifndef RSD_DISABLE_DEBUG_REGISTER
    OpId      opId;
`endif

    logic valid;      // Valid flag. If this is 0, its op is treated as NOP.
    logic replay;
    logic isFlushed;
    ComplexIssueQueueEntry complexQueueData;

    // register read out
    PRegDataPath operandA;
    PRegDataPath operandB;

    // Bypass control
    BypassControll bCtrl;
} ComplexIntegerExecutionStageRegPath;


typedef struct packed // ComplexIntegerRegisterWriteStageRegPath
{

`ifndef RSD_DISABLE_DEBUG_REGISTER
    OpId      opId;
`endif

    logic valid;  // Valid flag. If this is 0, its op is treated as NOP.
    ComplexIssueQueueEntry complexQueueData;

    PRegDataPath dataOut;   // Result of Execution
} ComplexIntegerRegisterWriteStageRegPath;


//
// Memory back end
//
typedef struct packed // MemoryRegisterReadStageRegPath
{
`ifndef RSD_DISABLE_DEBUG_REGISTER
    OpId      opId;
`endif

    logic valid;     // Valid flag. If this is 0, its op is treated as NOP.
    MemIssueQueueEntry memQueueData;

    // For release of the entries of an issue queue. See comments in MemoryExecutionStage.
    IssueQueueIndexPath issueQueuePtr;
    logic replay;
} MemoryRegisterReadStageRegPath;


typedef struct packed // MemoryExecutionStageRegPath
{
`ifndef RSD_DISABLE_DEBUG_REGISTER
    OpId      opId;
`endif

    logic valid;      // Valid flag. If this is 0, its op is treated as NOP.
    MemIssueQueueEntry memQueueData;

    // register read out
    PRegDataPath operandA;
    PRegDataPath operandB;

    // Bypass control
    BypassControll bCtrl;

    // For release of the entries of an issue queue. See comments in MemoryExecutionStage.
    IssueQueueIndexPath issueQueuePtr;
    logic replay;

} MemoryExecutionStageRegPath;


typedef struct packed // MemoryTagAccessStageRegPath
{
`ifndef RSD_DISABLE_DEBUG_REGISTER
    OpId      opId;
`endif

    logic valid;      // Valid flag. If this is 0, its op is treated as NOP.
    MemIssueQueueEntry memQueueData;

    logic condEnabled;      // 条件コードは有効か
    logic regValid;         // Whether source operands are valid or not.

    DataPath addrOut;       // The result of address calculation.
    DataPath dataIn;        // The input data for store or CSR data out
    MemoryMapType memMapType;  // Memory map type: mem/io
    PhyAddrPath phyAddrOut;

} MemoryTagAccessStageRegPath;


typedef struct packed // MemoryAccessStageRegPath
{
`ifndef RSD_DISABLE_DEBUG_REGISTER
    OpId      opId;
`endif

    logic    valid;      // Valid flag. If this is 0, its op is treated as NOP.

    logic isStore;
    logic isLoad;
    logic isCSR;
    logic isDiv;
    logic isMul;
    OpDst opDst;

    ActiveListIndexPath activeListPtr;  // Use to write recovery reg
    LoadQueueIndexPath loadQueueRecoveryPtr;
    StoreQueueIndexPath storeQueueRecoveryPtr;
    AddrPath pc;

    logic regValid;             // Whether source operands are valid or not.
    ExecutionState execState;   // Execution status. See RenameLogicTypes.sv
    
    AddrPath addrOut;    // The result of address calculation.
    MemoryMapType memMapType;  // Memory map type: mem/io
    PhyAddrPath phyAddrOut;    // The result of address calculation.
    
    // CSR data out. csrDataOut is from dataIn in MemoryTagAccessStageRegPath
    // TODO: addrOut and csrDataOut is exclusively used, these can be unified.
    DataPath csrDataOut; 

    logic hasAllocatedMSHR; // This op allocated an MSHR entry or not
    MSHR_IndexPath mshrID;
    logic storeForwardMiss;      // Store-load forwarding miss occurs
} MemoryAccessStageRegPath;


typedef struct packed // MemoryRegisterWriteStageRegPath
{
`ifndef RSD_DISABLE_DEBUG_REGISTER
    OpId      opId;
`endif

    logic    valid;     // Valid flag. If this is 0, its op is treated as NOP.
    ActiveListIndexPath activeListPtr;
    LoadQueueIndexPath loadQueueRecoveryPtr;
    StoreQueueIndexPath storeQueueRecoveryPtr;
    AddrPath pc;
    AddrPath addrOut;

    OpDst    opDst;
    ExecutionState execState; // Execution status. See RenameLogicTypes.sv
    logic isStore;
    logic isLoad;

    PRegDataPath dataOut;    // Result of Load

    logic hasAllocatedMSHR; // This op allocated an MSHR entry or not
    MSHR_IndexPath mshrID;
    logic storeForwardMiss;      // Store-load forwarding miss occurs
} MemoryRegisterWriteStageRegPath;

//
// FP back end
//
typedef struct packed // FPRegisterReadStageRegPath
{
`ifndef RSD_DISABLE_DEBUG_REGISTER
    OpId      opId;
`endif

    logic valid;     // Valid flag. If this is 0, its op is treated as NOP.
    logic replay;
    FPIssueQueueEntry fpQueueData;
} FPRegisterReadStageRegPath;


typedef struct packed // FPExecutionStageRegPath
{
`ifndef RSD_DISABLE_DEBUG_REGISTER
    OpId      opId;
`endif

    logic valid;      // Valid flag. If this is 0, its op is treated as NOP.
    logic replay;
    logic isFlushed;
    FPIssueQueueEntry fpQueueData;

    // register read out
    PRegDataPath operandA;
    PRegDataPath operandB;
    PRegDataPath operandC;

    // Bypass control
    BypassControll bCtrl;
} FPExecutionStageRegPath;


typedef struct packed // FPRegisterWriteStageRegPath
{

`ifndef RSD_DISABLE_DEBUG_REGISTER
    OpId      opId;
`endif

    logic valid;  // Valid flag. If this is 0, its op is treated as NOP.
    FPIssueQueueEntry fpQueueData;

    PRegDataPath dataOut;   // Result of Execution
    FFlags_Path fflagsOut;
} FPRegisterWriteStageRegPath;

endpackage


