// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Commit stage
//

`include "BasicMacros.sv"

import BasicTypes::*;
import MemoryMapTypes::*;
import OpFormatTypes::*;
import MicroOpTypes::*;
import PipelineTypes::*;
import RenameLogicTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;
import DebugTypes::*;
import FetchUnitTypes::*;

// 実行が終わってInsnの範囲を調べ、
// それがアクティブリストの先頭からop何個分に相当するかを返す
function automatic void GetFinishedInsnRange(
    output CommitLaneCountPath finishedInsnRange,
    input  CommitLaneCountPath finishedOpNum,    // the number of ops in an active list.
    input  ExecutionState      execState[COMMIT_WIDTH], // the execution state of the head ops on an active list.
    input  logic               last[COMMIT_WIDTH]
);
    finishedInsnRange = 0;
    for (int i = COMMIT_WIDTH - 1; i >= 0; i--) begin
        if (i < finishedOpNum && last[i]) begin
            finishedInsnRange = i + 1;
            break;
        end
    end
endfunction

// 実行が終わったopの数を出力。最大でCOMMIT_WIDTH
function automatic void GetFinishedOpNum(
    output CommitLaneCountPath finishedOpNum,
    input  ActiveListCountPath activeListCount,
    input  ExecutionState      execState[COMMIT_WIDTH] // the execution state of the head ops on an active list.
);
    finishedOpNum = 0;
    for (int i = 0; i < COMMIT_WIDTH; i++) begin
        if (i < activeListCount && execState[i] != EXEC_STATE_NOT_FINISHED)
            finishedOpNum = i + 1;
        else
            break;
    end
endfunction

// そのInsnと次のInsnの最初のマイクロ命令を指すポインタを得る
function automatic void GetInsnPtr(
    output CommitLaneIndexPath headOfThisInsn[COMMIT_WIDTH],
    output CommitLaneIndexPath tailOfThisInsn[COMMIT_WIDTH],
    input  logic        last [COMMIT_WIDTH]
);
    for (int i = 0; i < COMMIT_WIDTH; i++) begin
        headOfThisInsn[i] = 0;
        for (int j = i - 1; 0 <= j; j--) begin
            if (last[j]) begin
                headOfThisInsn[i] = j + 1;
                break;
            end
        end

        tailOfThisInsn[i] = COMMIT_WIDTH-1;
        for (int j = i; j < COMMIT_WIDTH; j++) begin
            if (last[j]) begin
                tailOfThisInsn[i] = j;
                break;
            end
        end
    end
endfunction

// Decide which ops are committed.
function automatic void DecideCommit(
    output logic commit[COMMIT_WIDTH],         // Whether to commit or not
    output logic toRecoveryPhase,              // Misprediction is detected and recover the system.
    output CommitLaneIndexPath recoveredIndex, // The index of mis-predicted op.
    output RefetchType refetchType,            // Where to refetch from.
    output ExecutionState recoveryCause,       // Why recovery is caused
    input logic startCommit,                      // In commit phase or not.
    input ActiveListCountPath activeListCount,    // the number of ops in an active list.
    input ExecutionState execState[COMMIT_WIDTH], // the execution state of the head ops on an active list.
    input logic isBranch [COMMIT_WIDTH],          // Whether the op is BR or RIJ
    input logic isStore [COMMIT_WIDTH],          // Whether the op is store
    input logic last[COMMIT_WIDTH],      // Whether the op is last of the insn or not
    input logic unableToStartRecovery    // Whether to start recovery
);



    CommitLaneIndexPath headOfThisInsn[COMMIT_WIDTH];
    CommitLaneIndexPath tailOfThisInsn[COMMIT_WIDTH];

    logic recovery[COMMIT_WIDTH];
    CommitLaneIndexPath recoveryPoint[COMMIT_WIDTH];
    logic recoveryTrigger;
    CommitLaneCountPath recoveryStart;

    // 実行終了し、コミット可能なマイクロ命令の数
    CommitLaneCountPath finishedOpNum;

    // すべてのマイクロ命令が終了したInstructionに属するマイクロ命令の数の合計。
    // 実行終了したマイクロ命令は、Instruction単位でコミットされるため、
    // これを計算しておくことが必要となる。
    CommitLaneCountPath finishedInsnRange;

    RefetchType opRefetchType[COMMIT_WIDTH]; // RefetchType of each lane.

    GetInsnPtr(headOfThisInsn, tailOfThisInsn, last);

    GetFinishedOpNum(finishedOpNum, activeListCount, execState);

    GetFinishedInsnRange(finishedInsnRange, finishedOpNum, execState, last);

    for (int i = 0; i < COMMIT_WIDTH; i++) begin
        if (execState[i] == EXEC_STATE_REFETCH_NEXT) begin
            recovery[i] = TRUE;
            recoveryPoint[i] = tailOfThisInsn[i];
            opRefetchType[i] = (
                isBranch[i] ?   REFETCH_TYPE_BRANCH_TARGET : 
                isStore[i]  ?   REFETCH_TYPE_STORE_NEXT_PC :
                                REFETCH_TYPE_NEXT_PC
            );
        end
        else if (execState[i] inside {
            EXEC_STATE_REFETCH_THIS,
            EXEC_STATE_STORE_LOAD_FORWARDING_MISS
        }) begin
            recovery[i] = TRUE;
            recoveryPoint[i] = headOfThisInsn[i];
            opRefetchType[i] = REFETCH_TYPE_THIS_PC;
        end
        else if (execState[i] inside{
            EXEC_STATE_TRAP_ECALL, 
            EXEC_STATE_TRAP_EBREAK, 
            EXEC_STATE_TRAP_MRET,
            EXEC_STATE_FAULT_INSN_MISALIGNED
        }) begin
            recovery[i] = TRUE;
            recoveryPoint[i] = tailOfThisInsn[i];
            opRefetchType[i] = REFETCH_TYPE_NEXT_PC_TO_CSR_TARGET;
        end
        else if (execState[i] inside{
            EXEC_STATE_FAULT_LOAD_MISALIGNED,
            EXEC_STATE_FAULT_LOAD_VIOLATION,
            EXEC_STATE_FAULT_STORE_MISALIGNED,
            EXEC_STATE_FAULT_STORE_VIOLATION,
            EXEC_STATE_FAULT_INSN_ILLEGAL,
            EXEC_STATE_FAULT_INSN_VIOLATION
        }) begin
            recovery[i] = TRUE;
            recoveryPoint[i] = headOfThisInsn[i];
            opRefetchType[i] = REFETCH_TYPE_THIS_PC_TO_CSR_TARGET;
        end
        else begin
            // Set dummy values
            recovery[i] = FALSE;
            recoveryPoint[i] = 0;
            opRefetchType[i] = REFETCH_TYPE_THIS_PC;
        end
    end

    recoveryTrigger = FALSE;
    recoveredIndex = 0;
    recoveryStart = COMMIT_WIDTH; // max value
    refetchType = REFETCH_TYPE_THIS_PC; // dummy value
    recoveryCause = EXEC_STATE_SUCCESS;
    for (int i = 0; i < COMMIT_WIDTH; i++) begin
        if (i < finishedInsnRange) begin
            if (recovery[i] && recoveryPoint[i] < recoveryStart) begin
                recoveryTrigger = TRUE;
                recoveredIndex = i;
                recoveryStart = recoveryPoint[i];
                refetchType = opRefetchType[i];
                recoveryCause = execState[i];
            end
        end
    end

    toRecoveryPhase = (startCommit && recoveryTrigger && !unableToStartRecovery ? TRUE : FALSE);

    for (int i = 0; i < COMMIT_WIDTH; i++) begin
        if (startCommit) begin
            if (recoveryTrigger) begin
                if (i < recoveryStart) begin
                    commit[i] = TRUE;
                end
                else if (i == recoveryStart) begin
                    commit[i] =
                        ( ((execState[i] inside {
                            EXEC_STATE_REFETCH_THIS,
                            EXEC_STATE_STORE_LOAD_FORWARDING_MISS,
                            EXEC_STATE_FAULT_LOAD_MISALIGNED,
                            EXEC_STATE_FAULT_LOAD_VIOLATION,
                            EXEC_STATE_FAULT_STORE_MISALIGNED,
                            EXEC_STATE_FAULT_STORE_VIOLATION,
                            EXEC_STATE_FAULT_INSN_ILLEGAL,
                            EXEC_STATE_FAULT_INSN_VIOLATION
                        }) || unableToStartRecovery) ? FALSE : TRUE);
                end
                else begin
                    commit[i] = FALSE;
                end
            end
            else begin
                commit[i] = (i < finishedInsnRange ? TRUE : FALSE);
            end
        end
        else begin
            commit[i] = FALSE;
        end
    end
endfunction



module CommitStage(
    CommitStageIF.ThisStage port,
    RenameLogicIF.CommitStage renameLogic,
    ActiveListIF.CommitStage activeList,
    LoadStoreUnitIF.CommitStage loadStoreUnit,
    RecoveryManagerIF.CommitStage recovery,
    CSR_UnitIF.CommitStage csrUnit,
    DebugIF.CommitStage debug
);

    logic toRecoveryPhase;

    logic commit [ COMMIT_WIDTH ] /*verilator public*/;
    logic last [ COMMIT_WIDTH ];
    logic isBranch [ COMMIT_WIDTH ];
    logic isStore [ COMMIT_WIDTH ];

    ActiveListEntry alReadData [ COMMIT_WIDTH ] /*verilator public*/;
    ExecutionState execState [ COMMIT_WIDTH ];

    CommitLaneIndexPath recoveryOpIndex;
    RefetchType refetchType;
    ExecutionState recoveryCause;

    CommitLaneCountPath commitNum;
    CommitLaneCountPath commitLoadNum;
    CommitLaneCountPath commitStoreNum;
`ifdef RSD_MARCH_FP_PIPE
    logic fflagsWE;
    FFlags_Path fflagsData;
`endif

    PipelinePhase phase;

    PC_Path lastCommittedPC, prevLastCommittedPC;

    always_ff@(posedge port.clk) begin
        prevLastCommittedPC <= lastCommittedPC;
        /*
        for (int i=0; i < COMMIT_WIDTH; ++i) begin
            if(commit[i] & |activeList.fflagsData[i]) begin
                $display("%x %b", alReadData[i].pc, activeList.fflagsData[i]);
            end
        end
        */
    end

    always_comb begin

        // The head entries of an active list.
        alReadData = activeList.readData;
        execState = activeList.headExecState;

        // Phase of a pipeline
        phase = recovery.phase;

        for (int i = 0; i < COMMIT_WIDTH; i++) begin
            last[i] = alReadData[i].last;
            isBranch[i] = alReadData[i].isBranch;
            isStore[i] = alReadData[i].isStore;
        end

        // Decide which instructions are committed.
        DecideCommit(
            .commit(commit),
            .toRecoveryPhase(toRecoveryPhase),
            .recoveredIndex(recoveryOpIndex),
            .refetchType(refetchType),
            .recoveryCause(recoveryCause),
            .startCommit(phase == PHASE_COMMIT),
            .activeListCount(activeList.validEntryNum),
            .execState(execState),
            .last(last),
            .isBranch(isBranch),
            .isStore(isStore),
            .unableToStartRecovery(recovery.unableToStartRecovery)
       );

        // Count num of commit instructions.
        commitNum = 0;
        commitLoadNum = 0;
        commitStoreNum = 0;
        for (int i = 0; i < COMMIT_WIDTH; i++) begin
            if (commit[i]) begin
                commitNum++;
                if (alReadData[i].isLoad)
                    commitLoadNum++;
                if (alReadData[i].isStore)
                    commitStoreNum++;
            end
        end

        // To the rename logic.
        renameLogic.commit = commit[0];
        renameLogic.commitNum = commitNum;

        for (int i = 0; i < COMMIT_WIDTH; i++) begin
            if (commit[i]) begin
                renameLogic.retRMT_WriteReg[i] = alReadData[i].writeReg;
                renameLogic.retRMT_WriteReg_PhyRegNum[i] = alReadData[i].phyDstRegNum;
                renameLogic.retRMT_WriteReg_LogRegNum[i] = alReadData[i].logDstRegNum;
            end
            else begin
                renameLogic.retRMT_WriteReg[i] = FALSE;
                renameLogic.retRMT_WriteReg_PhyRegNum[i] = 0;
                renameLogic.retRMT_WriteReg_LogRegNum[i] = 0;
            end
        end

        // Update load/store unit.
        loadStoreUnit.releaseLoadQueue = commit[0];
        loadStoreUnit.releaseLoadQueueEntryNum = commitLoadNum;
        loadStoreUnit.commitStore = commit[0];
        loadStoreUnit.commitStoreNum = commitStoreNum;

        // To RecoveryManager
        recovery.exceptionDetectedInCommitStage = toRecoveryPhase;
        recovery.refetchTypeFromCommitStage = refetchType;
        recovery.recoveryOpIndex = recoveryOpIndex;
        recovery.recoveryCauseFromCommitStage = recoveryCause;

        // lastCommittedPC
        lastCommittedPC = prevLastCommittedPC;
        for (int i = 0; i < COMMIT_WIDTH; i++) begin
            if (commit[i])
                lastCommittedPC = alReadData[i].pc;
        end

        // CSR Update
        csrUnit.commitNum = commitNum;
    
`ifdef RSD_MARCH_FP_PIPE
        // CSR FFLAGS Update
        fflagsWE = FALSE;
        fflagsData = '0;
        for (int i = 0; i < COMMIT_WIDTH; i++) begin
            if (commit[i]) begin
                fflagsWE = TRUE;
                fflagsData |= activeList.fflagsData[i];
            end
        end
        csrUnit.fflagsWE = fflagsWE;
        csrUnit.fflagsData = fflagsData;
`endif

        // Debug Register
        for (int i = 0; i < COMMIT_WIDTH; i++) begin
`ifndef RSD_DISABLE_DEBUG_REGISTER
            debug.toRecoveryPhase = toRecoveryPhase;
            debug.cmReg[i].commit = commit[i];
            debug.cmReg[i].flush =
                (i < renameLogic.flushNum) && recovery.renameLogicRecoveryRMT;

            debug.cmReg[i].opId = alReadData[i].opId;
`ifdef RSD_FUNCTIONAL_SIMULATION
            debug.cmReg[i].releaseReg = renameLogic.releaseReg[i];
            debug.cmReg[i].phyReleasedReg = renameLogic.phyReleasedReg[i];
`endif
`endif
            debug.lastCommittedPC = lastCommittedPC;
        end
    end

    generate
        for (genvar i = 0; i < COMMIT_WIDTH; i++) begin
            `RSD_ASSERT_CLK(
                port.clk,
                !(commit[i] && phase == PHASE_COMMIT && alReadData[i].undefined),
                "An undefined or unsupported op is retired."
            );
        end
    endgenerate
`ifdef RSD_FUNCTIONAL_SIMULATION
    localparam DEADLOCK_DETECT_CYCLES = 500;
    integer cycles;
    always_ff @(posedge port.clk) begin
        if (port.rst || commit[0]) begin
            cycles <= 0;
        end
        else begin
            cycles <= cycles + 1;
        end
    end


    generate
        `RSD_ASSERT_CLK(
            port.clk,
            !(cycles > DEADLOCK_DETECT_CYCLES),
            "Deadlock detected"
        );
    endgenerate

`endif

endmodule : CommitStage

