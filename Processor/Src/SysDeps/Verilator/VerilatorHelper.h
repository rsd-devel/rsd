// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

//
// Helper macros and functions to extract values defined in SystemVerilog from CPP. 
// See comments in VerilatorHelper.h
//

#ifndef SYSDEPS_VERILATOR_VERILATOR_HELPER_H
#define SYSDEPS_VERILATOR_VERILATOR_HELPER_H

#include "VMain_Zynq_Wrapper.h"
#include "VMain_Zynq_Wrapper__Syms.h"    // To see all public symbols

#include <stdio.h>
#include <string>


// Parameters
// Write bridge code in VerilatorHelper.sv
#define RSD_MAKE_PARAMETER(name) \
    static const auto name = VMain_Zynq_Wrapper_VerilatorHelper::name

RSD_MAKE_PARAMETER(PC_GOAL);
RSD_MAKE_PARAMETER(PHY_ADDR_SECTION_0_BASE);
RSD_MAKE_PARAMETER(PHY_ADDR_SECTION_1_BASE);

RSD_MAKE_PARAMETER(LSCALAR_NUM);
RSD_MAKE_PARAMETER(FETCH_WIDTH);
RSD_MAKE_PARAMETER(DECODE_WIDTH);
RSD_MAKE_PARAMETER(RENAME_WIDTH);
RSD_MAKE_PARAMETER(DISPATCH_WIDTH);
RSD_MAKE_PARAMETER(COMMIT_WIDTH);

RSD_MAKE_PARAMETER(INT_ISSUE_WIDTH);
RSD_MAKE_PARAMETER(COMPLEX_ISSUE_WIDTH);
RSD_MAKE_PARAMETER(MEM_ISSUE_WIDTH);

RSD_MAKE_PARAMETER(ISSUE_QUEUE_ENTRY_NUM);
RSD_MAKE_PARAMETER(COMPLEX_EXEC_STAGE_DEPTH);

RSD_MAKE_PARAMETER(MEM_MOP_TYPE_CSR);


// Types
typedef uint32_t DataPath;
typedef uint32_t AddrPath;
typedef uint32_t LED_Path;
typedef uint32_t SerialDataPath;
typedef uint32_t InsnPath;
typedef uint32_t PC_Path;

typedef uint32_t OpSerial;
typedef uint32_t MicroOpIndex;

typedef uint32_t ActiveListIndexPath;
typedef uint32_t ActiveListCountPath;

typedef uint32_t StoreQueueCountPath;


typedef uint32_t IntALU_Code;
typedef uint32_t IntMicroOpSubType;

typedef uint32_t LRegNumPath;
typedef uint32_t PRegNumPath;

typedef uint32_t IssueQueueIndexPath;
typedef uint32_t LSQ_BlockDataPath;
typedef uint32_t VectorPath;

typedef uint32_t MemMicroOpSubType;
typedef uint32_t MemAccessSizeType;


struct OpId
{
    OpSerial sid;
    MicroOpIndex mid;
};

struct PipelineControll
{
    bool stall;
    bool clear;
};



//
// --- Debug Register
//

struct NextPCStageDebugRegister{
    bool valid;
    OpSerial sid;
};

struct FetchStageDebugRegister{
    bool valid;
    OpSerial sid;
    bool flush;
    bool icMiss;
};

struct PreDecodeStageDebugRegister{ // PreDecodeStageDebugRegister
    bool valid;
    OpSerial sid;
#ifdef RSD_FUNCTIONAL_SIMULATION
    // 演算のソースと結果の値は、機能シミュレーション時のみデバッグ出力する
    // 合成時は、IOポートが足りなくて不可能であるため
    IntALU_Code aluCode;
    IntMicroOpSubType opType;
#endif
};

struct DecodeStageDebugRegister{
    bool valid;
    bool flushed;    // Branch misprediction is detected on instruction decode and flush this instruction.
    bool flushTriggering;   // This op causes branch misprediction and triggers flush.
    OpId opId;
    AddrPath pc;
    InsnPath insn;
    bool undefined;
    bool unsupported;
};

struct RenameStageDebugRegister{
    bool valid;
    OpId opId;

    // Physical register numbers are outputted in the next stage, because
    // The pop flags of the free list is negated and correct physical
    // register numbers cannot be outputted in this stage when the pipeline
    // is stalled.
};

struct DispatchStageDebugRegister{
    bool valid;
    OpId opId;


#ifdef RSD_FUNCTIONAL_SIMULATION
    // レジスタ番号は、機能シミュレーション時のみデバッグ出力する
    // 合成時は、IOポートが足りなくて不可能であるため
    bool readRegA;
    LRegNumPath logSrcRegA;
    PRegNumPath phySrcRegA;

    bool readRegB;
    LRegNumPath logSrcRegB;
    PRegNumPath phySrcRegB;

    bool writeReg;
    LRegNumPath logDstReg;
    PRegNumPath phyDstReg;
    PRegNumPath phyPrevDstReg;

    IssueQueueIndexPath issueQueuePtr;
#endif
};

struct IntegerIssueStageDebugRegister{
    bool valid;
    bool flush;
    OpId opId;
};

struct IntegerRegisterReadStageDebugRegister{
    bool valid;
    bool flush;
    OpId opId;
};

struct IntegerExecutionStageDebugRegister{
    bool valid;
    bool flush;
    OpId opId;

#ifdef RSD_FUNCTIONAL_SIMULATION
    // 演算のソースと結果の値は、機能シミュレーション時のみデバッグ出力する
    // 合成時は、IOポートが足りなくて不可能であるため
    DataPath dataOut;
    DataPath fuOpA;
    DataPath fuOpB;
    IntALU_Code aluCode;
    IntMicroOpSubType opType;
    bool brPredMiss;
#endif

};

struct IntegerRegisterWriteStageDebugRegister{
    bool valid;
    bool flush;
    OpId opId;
};

struct ComplexIntegerIssueStageDebugRegister{
    bool valid;
    bool flush;
    OpId opId;
};

struct ComplexIntegerRegisterReadStageDebugRegister{
    bool valid;
    bool flush;
    OpId opId;
};

struct ComplexIntegerExecutionStageDebugRegister{
    bool valid[COMPLEX_EXEC_STAGE_DEPTH];
    bool flush;
    OpId opId[COMPLEX_EXEC_STAGE_DEPTH];

#ifdef RSD_FUNCTIONAL_SIMULATION
    // 演算のソースと結果の値は、機能シミュレーション時のみデバッグ出力する
    // 合成時は、IOポートが足りなくて不可能であるため
    DataPath dataOut;
    DataPath fuOpA;
    DataPath fuOpB;

    VectorPath vecDataOut;
    VectorPath fuVecOpA;
    VectorPath fuVecOpB;
#endif

};

struct ComplexIntegerRegisterWriteStageDebugRegister{
    bool valid;
    bool flush;
    OpId opId;
};

struct MemoryIssueStageDebugRegister{
    bool valid;
    bool flush;
    OpId opId;
};

struct MemoryRegisterReadStageDebugRegister{
    bool valid;
    bool flush;
    OpId opId;
};

struct MemoryExecutionStageDebugRegister{
    bool valid;
    bool flush;
    OpId opId;

#ifdef RSD_FUNCTIONAL_SIMULATION
    // 演算のソースと結果の値は、機能シミュレーション時のみデバッグ出力する
    // 合成時は、IOポートが足りなくて不可能であるため
    AddrPath addrOut;
    DataPath fuOpA;
    DataPath fuOpB;
    VectorPath fuVecOpB;
    MemMicroOpSubType opType;
    MemAccessSizeType size;
    bool isSigned;
#endif

};

struct MemoryTagAccessStageDebugRegister{
    bool valid;
    bool flush;
    OpId opId;
#ifdef RSD_FUNCTIONAL_SIMULATION
    bool executeLoad;
    AddrPath executedLoadAddr;
    bool mshrHit;
    bool mshrAllocated;
    DataPath mshrEntryID;
    bool executeStore;
    AddrPath executedStoreAddr;
    DataPath executedStoreData;
    VectorPath executedStoreVectorData;
#endif
};

struct MemoryAccessStageDebugRegister{
    bool valid;
    bool flush;
    OpId opId;
#ifdef RSD_FUNCTIONAL_SIMULATION
    bool executeLoad;
    DataPath executedLoadData;
    VectorPath executedLoadVectorData;
#endif
};

struct MemoryRegisterWriteStageDebugRegister{
    bool valid;
    bool flush;
    OpId opId;
};

struct CommitStageDebugRegister{
    bool commit;
    bool flush;
    OpId opId;

#ifdef RSD_FUNCTIONAL_SIMULATION
    bool releaseReg;
    PRegNumPath phyReleasedReg;
#endif
};

struct ActiveListDebugRegister{
    bool finished;
    OpId opId;
};

struct SchedulerDebugRegister{
    bool valid;
};

struct IssueQueueDebugRegister{
    bool flush;
    OpId opId;
};

struct PerfCounterPath {
    DataPath numIC_Miss;
    DataPath numLoadMiss;
    DataPath numStoreMiss;
    DataPath numStoreLoadForwardingFail;
    DataPath numMemDepPredMiss;
    DataPath numBranchPredMiss;
    DataPath numBranchPredMissDetectedOnDecode;
};

struct DebugRegister{

    // DebugRegister of each stage
    NextPCStageDebugRegister npReg[FETCH_WIDTH];
    FetchStageDebugRegister   ifReg[FETCH_WIDTH];
    PreDecodeStageDebugRegister pdReg[DECODE_WIDTH];
    DecodeStageDebugRegister    idReg[DECODE_WIDTH];
    RenameStageDebugRegister    rnReg[RENAME_WIDTH];
    DispatchStageDebugRegister  dsReg[DISPATCH_WIDTH];

    IntegerIssueStageDebugRegister          intIsReg[INT_ISSUE_WIDTH];
    IntegerRegisterReadStageDebugRegister   intRrReg[INT_ISSUE_WIDTH];
    IntegerExecutionStageDebugRegister      intExReg[INT_ISSUE_WIDTH];
    IntegerRegisterWriteStageDebugRegister  intRwReg[INT_ISSUE_WIDTH];

    ComplexIntegerIssueStageDebugRegister          complexIsReg[COMPLEX_ISSUE_WIDTH];
    ComplexIntegerRegisterReadStageDebugRegister   complexRrReg[COMPLEX_ISSUE_WIDTH];
    ComplexIntegerExecutionStageDebugRegister      complexExReg[COMPLEX_ISSUE_WIDTH];
    ComplexIntegerRegisterWriteStageDebugRegister  complexRwReg[COMPLEX_ISSUE_WIDTH];

    MemoryIssueStageDebugRegister           memIsReg[MEM_ISSUE_WIDTH];
    MemoryRegisterReadStageDebugRegister    memRrReg[MEM_ISSUE_WIDTH];
    MemoryExecutionStageDebugRegister       memExReg[MEM_ISSUE_WIDTH];
    MemoryTagAccessStageDebugRegister       mtReg[MEM_ISSUE_WIDTH];
    MemoryAccessStageDebugRegister          maReg[MEM_ISSUE_WIDTH];
    MemoryRegisterWriteStageDebugRegister   memRwReg[MEM_ISSUE_WIDTH];

    CommitStageDebugRegister cmReg[COMMIT_WIDTH];

    SchedulerDebugRegister  scheduler[ISSUE_QUEUE_ENTRY_NUM];
    IssueQueueDebugRegister issueQueue[ISSUE_QUEUE_ENTRY_NUM];

    // Signals related to commit
    bool toRecoveryPhase;
    ActiveListIndexPath activeListHeadPtr;
    ActiveListCountPath activeListCount;

    // Pipeline control signal
    PipelineControll npStagePipeCtrl;
    PipelineControll ifStagePipeCtrl;
    PipelineControll pdStagePipeCtrl;
    PipelineControll idStagePipeCtrl;
    PipelineControll rnStagePipeCtrl;
    PipelineControll dsStagePipeCtrl;
    PipelineControll backEndPipeCtrl;
    PipelineControll cmStagePipeCtrl;
    bool stallByDecodeStage;

    // Others
    bool loadStoreUnitAllocatable;
    bool storeCommitterPhase;
    StoreQueueCountPath storeQueueCount;
    bool busyInRecovery;
    bool storeQueueEmpty;
    
    // Performance counters
    PerfCounterPath perfCounter;
};

static void GetDebugRegister(DebugRegister* d, VMain_Zynq_Wrapper *top)
{
    VMain_Zynq_Wrapper_VerilatorHelper* h = top->VerilatorHelper;
    const auto& r = top->debugRegister;

    // DebugRegister of each stage
    #define RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(dummy0, stage, dummy1, member) \
        { \
            int index = 0;  \
            for (auto& i : d->stage) { \
                i.member = h->DebugRegister_##stage##_##member(r, index); \
                index++; \
            } \
        }

    #define RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR_OP_ID(dummy0, stage, dummy1, member) \
        { \
            int index = 0;  \
            for (auto& i : d->stage) { \
                auto opId = h->DebugRegister_##stage##_##member(r, index); \
                i.member.sid = h->OpId_sid(opId); \
                i.member.mid = h->OpId_mid(opId); \
                index++; \
            } \
        }
    
    #define RSD_MAKE_STRUCT_ACCESSOR(typeName, memberTypeName, memberName) \
        d->memberName = h->DebugRegister_##memberName(r); \

    #define RSD_MAKE_STRUCT_ACCESSOR_LV2(typeName, memberName0, memberTypeName1, memberName1) \
        d->memberName0.memberName1 = h->DebugRegister_##memberName0##_##memberName1(r); \

    #define RSD_MAKE_DEBUG_REG_PIPELINE_CTRL(typeName, memberTypeName, memberName) \
        d->memberName.stall = h->PipelineControll_stall(h->DebugRegister_##memberName(r)); \
        d->memberName.clear = h->PipelineControll_clear(h->DebugRegister_##memberName(r)); \


    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, npReg, logic, valid);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, npReg, OpSerial, sid);

    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, ifReg, logic, valid);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, ifReg, OpSerial, sid);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, ifReg, logic, flush);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, ifReg, logic, icMiss);

    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, pdReg, logic, valid);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, pdReg, OpSerial, sid);
#ifdef RSD_FUNCTIONAL_SIMULATION
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, pdReg, IntALU_Code, aluCode);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, pdReg, IntMicroOpSubType, opType);
#endif

    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, idReg, logic, valid);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, idReg, logic, flushed);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, idReg, logic, flushTriggering);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR_OP_ID(DebugRegister, idReg, OpId, opId);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, idReg, PC_Path, pc);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, idReg, InsnPath, insn);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, idReg, logic, undefined);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, idReg, logic, unsupported);

    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, rnReg, logic, valid);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR_OP_ID(DebugRegister, rnReg, OpId, opId);

    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, dsReg, logic, valid);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR_OP_ID(DebugRegister, dsReg, OpId, opId);
#ifdef RSD_FUNCTIONAL_SIMULATION
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, dsReg, logic, readRegA);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, dsReg, LRegNumPath, logSrcRegA);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, dsReg, PRegNumPath, phySrcRegA);

    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, dsReg, logic, readRegB);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, dsReg, LRegNumPath, logSrcRegB);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, dsReg, PRegNumPath, phySrcRegB);

    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, dsReg, logic, writeReg);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, dsReg, LRegNumPath, logDstReg);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, dsReg, PRegNumPath, phyDstReg);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, dsReg, PRegNumPath, phyPrevDstReg);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, dsReg, IssueQueueIndexPath, issueQueuePtr);
#endif

    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intIsReg, logic, valid);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intIsReg, logic, flush);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR_OP_ID(DebugRegister, intIsReg, OpId, opId);

    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intRrReg, logic, valid);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intRrReg, logic, flush);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR_OP_ID(DebugRegister, intRrReg, OpId, opId);

    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intExReg, logic, valid);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intExReg, logic, flush);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR_OP_ID(DebugRegister, intExReg, OpId, opId);
#ifdef RSD_FUNCTIONAL_SIMULATION
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intExReg, DataPath, dataOut);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intExReg, DataPath, fuOpA);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intExReg, DataPath, fuOpB);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intExReg, IntALU_Code, aluCode);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intExReg, IntMicroOpSubType, opType);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intExReg, logic, brPredMiss);
#endif
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intRwReg, logic, valid);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, intRwReg, logic, flush);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR_OP_ID(DebugRegister, intRwReg, OpId, opId);

#ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexIsReg, logic, valid);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexIsReg, logic, flush);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR_OP_ID(DebugRegister, complexIsReg, OpId, opId);

    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexRrReg, logic, valid);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexRrReg, logic, flush);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR_OP_ID(DebugRegister, complexRrReg, OpId, opId);

    // Output only the first execution stage of a complex pipeline
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexExReg, logic, flush);
    //RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexExReg, logic, valid[0]);
    //RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexExReg, logic, opId[0]);
    {
        int index = 0;
        for (auto& i : d->complexExReg) {
            i.valid[0] = h->DebugRegister_complexExReg_valid(r, index);
            index++;
        }
    }
    {
        int index = 0;
        for (auto& i : d->complexExReg) {
            auto opId = h->DebugRegister_complexExReg_opId(r, index);
            i.opId[0].sid = h->OpId_sid(opId);
            i.opId[0].mid = h->OpId_mid(opId);
        }
    }

#ifdef RSD_FUNCTIONAL_SIMULATION
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexExReg, DataPath, dataOut);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexExReg, DataPath, fuOpA);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexExReg, DataPath, fuOpB);
    //RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexExReg, VectorPath, vecDataOut);
    //RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexExReg, VectorPath, fuVecOpA);
    //RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexExReg, VectorPath, fuVecOpB);
#endif

    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexRwReg, logic, valid);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, complexRwReg, logic, flush);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR_OP_ID(DebugRegister, complexRwReg, OpId, opId);
#endif  // #ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE


    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memIsReg, logic, valid);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memIsReg, logic, flush);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR_OP_ID(DebugRegister, memIsReg, OpId, opId);

    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memRrReg, logic, valid);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memRrReg, logic, flush);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR_OP_ID(DebugRegister, memRrReg, OpId, opId);

    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memExReg, logic, valid);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memExReg, logic, flush);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR_OP_ID(DebugRegister, memExReg, OpId, opId);
#ifdef RSD_FUNCTIONAL_SIMULATION
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memExReg, AddrPath, addrOut);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memExReg, DataPath, fuOpA);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memExReg, DataPath, fuOpB);
    //RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memExReg, VectorPath, fuVecOpB);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memExReg, MemMicroOpSubType, opType);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memExReg, MemAccessSizeType, size);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memExReg, logic, isSigned);
#endif

    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, mtReg, logic, valid);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, mtReg, logic, flush);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR_OP_ID(DebugRegister, mtReg, OpId, opId);
#ifdef RSD_FUNCTIONAL_SIMULATION
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, mtReg, logic, executeLoad);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, mtReg, AddrPath, executedLoadAddr);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, mtReg, logic, mshrAllocated);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, mtReg, logic, mshrHit);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, mtReg, DataPath, mshrEntryID);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, mtReg, logic, executeStore);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, mtReg, AddrPath, executedStoreAddr);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, mtReg, DataPath, executedStoreData);
    //RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, mtReg, VectorPath, executedStoreVecData);
#endif

    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, maReg, logic, valid);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, maReg, logic, flush);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR_OP_ID(DebugRegister, maReg, OpId, opId);
#ifdef RSD_FUNCTIONAL_SIMULATION
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, maReg, logic, executeLoad);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, maReg, DataPath, executedLoadData);
    //RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, maReg, VectorPath, executedLoadVecData);
#endif

    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memRwReg, logic, valid);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, memRwReg, logic, flush);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR_OP_ID(DebugRegister, memRwReg, OpId, opId);


    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, cmReg, logic, commit);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, cmReg, logic, flush);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR_OP_ID(DebugRegister, cmReg, OpId, opId);
#ifdef RSD_FUNCTIONAL_SIMULATION
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, cmReg, logic, releaseReg);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, cmReg, PRegNumPath, phyReleasedReg);
#endif

    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, scheduler, logic, valid);

    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR(DebugRegister, issueQueue, logic, flush);
    RSD_MAKE_DEBUG_REG_STAGE_ACCESSOR_OP_ID(DebugRegister, issueQueue, OpId, opId);
    
    RSD_MAKE_STRUCT_ACCESSOR(DebugRegister, logic, toRecoveryPhase);
    RSD_MAKE_STRUCT_ACCESSOR(DebugRegister, ActiveListIndexPath, activeListHeadPtr);
    RSD_MAKE_STRUCT_ACCESSOR(DebugRegister, ActiveListCountPath, activeListCount);

    RSD_MAKE_DEBUG_REG_PIPELINE_CTRL(DebugRegister, PipelineControll, npStagePipeCtrl);
    RSD_MAKE_DEBUG_REG_PIPELINE_CTRL(DebugRegister, PipelineControll, ifStagePipeCtrl);
    RSD_MAKE_DEBUG_REG_PIPELINE_CTRL(DebugRegister, PipelineControll, pdStagePipeCtrl);
    RSD_MAKE_DEBUG_REG_PIPELINE_CTRL(DebugRegister, PipelineControll, idStagePipeCtrl);
    RSD_MAKE_DEBUG_REG_PIPELINE_CTRL(DebugRegister, PipelineControll, rnStagePipeCtrl);
    RSD_MAKE_DEBUG_REG_PIPELINE_CTRL(DebugRegister, PipelineControll, dsStagePipeCtrl);
    RSD_MAKE_DEBUG_REG_PIPELINE_CTRL(DebugRegister, PipelineControll, backEndPipeCtrl);
    RSD_MAKE_DEBUG_REG_PIPELINE_CTRL(DebugRegister, PipelineControll, cmStagePipeCtrl);
    RSD_MAKE_STRUCT_ACCESSOR(DebugRegister, logic, stallByDecodeStage);

    RSD_MAKE_STRUCT_ACCESSOR(DebugRegister, logic, loadStoreUnitAllocatable);
    RSD_MAKE_STRUCT_ACCESSOR(DebugRegister, logic, storeCommitterPhase);
    RSD_MAKE_STRUCT_ACCESSOR(DebugRegister, StoreQueueCountPath, storeQueueCount);
    RSD_MAKE_STRUCT_ACCESSOR(DebugRegister, logic, busyInRecovery);
    RSD_MAKE_STRUCT_ACCESSOR(DebugRegister, logic, storeQueueEmpty);


#ifdef RSD_FUNCTIONAL_SIMULATION
    RSD_MAKE_STRUCT_ACCESSOR_LV2(DebugRegister, perfCounter, DataPath, numIC_Miss)
    RSD_MAKE_STRUCT_ACCESSOR_LV2(DebugRegister, perfCounter, DataPath, numLoadMiss)
    RSD_MAKE_STRUCT_ACCESSOR_LV2(DebugRegister, perfCounter, DataPath, numStoreMiss)
    RSD_MAKE_STRUCT_ACCESSOR_LV2(DebugRegister, perfCounter, DataPath, numStoreLoadForwardingFail)
    RSD_MAKE_STRUCT_ACCESSOR_LV2(DebugRegister, perfCounter, DataPath, numMemDepPredMiss)
    RSD_MAKE_STRUCT_ACCESSOR_LV2(DebugRegister, perfCounter, DataPath, numBranchPredMiss)
    RSD_MAKE_STRUCT_ACCESSOR_LV2(DebugRegister, perfCounter, DataPath, numBranchPredMissDetectedOnDecode)
#endif
}

#endif
