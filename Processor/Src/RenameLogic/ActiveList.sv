// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Active list
//

`include "BasicMacros.sv"

import BasicTypes::*;
import MemoryMapTypes::*;
import MicroOpTypes::*;
import RenameLogicTypes::*;
import SchedulerTypes::*;
import LoadStoreUnitTypes::*;
import PipelineTypes::*;
import DebugTypes::*;


//
// Current implementation is a FIFO with:
//   - 1 input to tail for dispatch.
//   - 1 output from head for commit/recovery.
//   - 1 input to random entries for execution.
//
module ActiveList(
    ActiveListIF.ActiveList port,
    RecoveryManagerIF.ActiveList recovery,
    ControllerIF.ActiveList ctrl,
    DebugIF.ActiveList debug
);

    //
    // --- Pointers
    //
    ActiveListIndexPath headPtr/*verilator public*/;   // Set it public from a test bench for verilator.
    ActiveListIndexPath headPtrList[COMMIT_WIDTH];
    ActiveListIndexPath tailPtr; // 次に割り当てを行うエントリを指す
    ActiveListIndexPath tailPtrList[COMMIT_WIDTH];
    ActiveListIndexPath readPtrList[COMMIT_WIDTH];
    ActiveListIndexPath pushedTailPtr [RENAME_WIDTH];
    ActiveListCountPath count;
    RenameLaneCountPath pushNum;

    // Parameter: Size, Initial head pos., Initial tail pos., Initial count
    BiTailMultiWidthQueuePointer #(ACTIVE_LIST_ENTRY_NUM, 0, 0, 0, RENAME_WIDTH, COMMIT_WIDTH)
        activeListPointer(
            .clk(port.clk),
            .rst(port.rst), // On flush, pointers are recovered by the store committer.
            .popHead(port.popHeadNum > 0),
            .popHeadCount(port.popHeadNum),
            .pushTail(pushNum > 0),
            .pushTailCount(pushNum),
            .popTail( port.popTailNum > 0 ),
            .popTailCount( port.popTailNum ),
            .count(count),
            .headPtr(headPtr),
            .tailPtr(tailPtr)
        );

    always_comb begin
        // In the active list, recovery and allocation can be simultaneously carried out,
        // thus allocation is decided by its current count without its phase.
        port.allocatable = (count <= ACTIVE_LIST_ENTRY_NUM - RENAME_WIDTH) ? TRUE : FALSE;
        port.validEntryNum = count;

        pushNum = 0;
        for (int i = 0; i < RENAME_WIDTH; i++) begin
            if ((tailPtr + pushNum) >= ACTIVE_LIST_ENTRY_NUM) begin
                pushedTailPtr[i] = tailPtr + pushNum - ACTIVE_LIST_ENTRY_NUM;
            end
            else begin
                pushedTailPtr[i] = tailPtr + pushNum;
            end
            pushNum += (port.pushTail[i] ? 1 : 0);
        end
        for (int i = 0; i < COMMIT_WIDTH; i++) begin
            if ((headPtr + i) < ACTIVE_LIST_ENTRY_NUM) begin
                headPtrList[i] = headPtr + i;
            end
            else begin
                headPtrList[i] = headPtr + i - ACTIVE_LIST_ENTRY_NUM;
            end
        end
        for (int i = 0; i < COMMIT_WIDTH; i++) begin    //Actually limited to RENAME_WIDTH
            if (( tailPtr - 1 - i) >= ACTIVE_LIST_ENTRY_NUM) begin
                tailPtrList[i] = tailPtr - 1 - i + ACTIVE_LIST_ENTRY_NUM;
            end
            else begin
                tailPtrList[i] = tailPtr - 1 - i;
            end
        end

        if( RECOVERY_FROM_ACTIVE_LIST && ( port.popTailNum > 0 ) ) begin
            readPtrList = tailPtrList;
        end else begin
            readPtrList = headPtrList;
        end

        port.detectedFlushRangeTailPtr = tailPtr + pushNum;
        port.pushedTailPtr = pushedTailPtr;
        //port.detectedFlushRangeHeadPtr = headPtr + port.popHeadNum;

        ctrl.activeListEmpty = count == 0;

`ifndef RSD_DISABLE_DEBUG_REGISTER
        // Debug Register
        debug.activeListHeadPtr = headPtr;
        debug.activeListCount = count;
`endif
    end


    //
    // --- Active List
    //
    logic pushTail [RENAME_WIDTH];
    ActiveListEntry pushedTailData [RENAME_WIDTH];
    ActiveListEntry readData[COMMIT_WIDTH];

    //DistributedMultiPortRAM #(
    DistributedMultiBankRAM #(
        .ENTRY_NUM( ACTIVE_LIST_ENTRY_NUM ),
        .ENTRY_BIT_SIZE( $bits( ActiveListEntry ) ),
        .READ_NUM( COMMIT_WIDTH  ),
        .WRITE_NUM( RENAME_WIDTH )
    ) activeList (
        .clk( port.clk ),
        .we( pushTail ),
        .wa( pushedTailPtr ),
        .wv( pushedTailData ),
        .ra( readPtrList ),
        .rv( readData )
    );

    always_comb begin
        pushTail = port.pushTail;
        pushedTailData = port.pushedTailData;
        port.readData = readData;
    end


    //
    // --- Execution result write
    //
    logic we[ISSUE_WIDTH];
    ActiveListWriteData writeData[ISSUE_WIDTH];
    always_comb begin
        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            we[i] = port.intWrite[i];
            writeData[i] = port.intWriteData[i];
        end
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        for (int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin
            we[(i+INT_ISSUE_WIDTH)] = port.complexWrite[i];
            writeData[(i+INT_ISSUE_WIDTH)] = port.complexWriteData[i];
        end
`endif
        for (int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
            we[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] = port.memWrite[i];
            writeData[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] = port.memWriteData[i];
        end
    end


    // Recovery register.
    // Record the oldest recovery point of an op that occurs misprediction.
    typedef struct packed
    {
        PC_Path pc;
        AddrPath faultingDataAddr;
        ActiveListIndexPath ptr;
        LoadQueueIndexPath loadQueuePtr;
        StoreQueueIndexPath storeQueuePtr;
        logic valid;
        ExecutionState state;
    } RecoveryRegPath;

    ActiveListCountPath oldestAge;
    ActiveListCountPath writeAge[ISSUE_WIDTH];
    logic exceptionDetected;
    RefetchType refetchType;
    IssueLaneIndexPath exceptionIndex;

    RecoveryRegPath recoveryReg;
    RecoveryRegPath nextRecoveryReg;
    ActiveListCountPath recoveryEntryNum, nextRecoveryEntryNum;
    ActiveListIndexPath flushRangeHeadPtr, flushRangeTailPtr;
    always_ff@(posedge port.clk) begin
        if (port.rst || recovery.toRecoveryPhase && !exceptionDetected ) begin
            recoveryReg <= '0;
        end
        else begin
            recoveryReg <= nextRecoveryReg;
        end
    end

    // One cycle delay for RenameLogicCommitter.
    always_ff@(posedge port.clk) begin
        if(port.rst)
            recoveryEntryNum <= '0;
        else if(recovery.toRecoveryPhase) begin
            recoveryEntryNum <= nextRecoveryEntryNum;
        end
    end

    always_comb begin
        nextRecoveryReg = recoveryReg;
        oldestAge = ActiveListPtrToAge(recoveryReg.ptr, headPtr);
        
        exceptionIndex = '0;
        exceptionDetected = FALSE;
        refetchType = REFETCH_TYPE_THIS_PC;

        for (int i = 0; i < ISSUE_WIDTH; i++) begin
            writeAge[i] = ActiveListPtrToAge(writeData[i].ptr, headPtr);

            if (we[i] && 
                !(writeData[i].state inside {EXEC_STATE_NOT_FINISHED, EXEC_STATE_SUCCESS})
            ) begin
                // Record the oldest recovery point.
                if (!nextRecoveryReg.valid || writeAge[i] < oldestAge) begin
                    oldestAge = writeAge[i];
                    nextRecoveryReg.valid = TRUE;
                    nextRecoveryReg.ptr = writeData[i].ptr;
                    nextRecoveryReg.loadQueuePtr = writeData[i].loadQueuePtr;
                    nextRecoveryReg.storeQueuePtr = writeData[i].storeQueuePtr;
                    nextRecoveryReg.pc = writeData[i].pc;
                    nextRecoveryReg.faultingDataAddr = writeData[i].dataAddr;
                    nextRecoveryReg.state = writeData[i].state;

                    // Rwステージで例外が検出された時点でリカバリを開始する(詳細はRecoveryManager)
                    // EXEC_STATE_TRAP や例外は必ずコミット時に処理する（CSR の操作が伴うため）
                    exceptionDetected = writeData[i].state inside {
                        EXEC_STATE_REFETCH_NEXT, EXEC_STATE_REFETCH_THIS
                    };
                    exceptionIndex = i;
                    // refetchTypeはflushOpのheadPtrを決めるためとrecoveredPCを確定するために使う
                    // Int命令の例外は分岐命令なので分岐ターゲットに飛ぶ
                    // Mem命令のREFETCH_NEXTは順序違反検出なので次のPCに飛ぶ
                    if(writeData[i].state == EXEC_STATE_REFETCH_NEXT) begin
                        refetchType = ( 
                            writeData[i].isBranch ? REFETCH_TYPE_BRANCH_TARGET : 
                            writeData[i].isStore ?  REFETCH_TYPE_STORE_NEXT_PC : 
                                                    REFETCH_TYPE_NEXT_PC 
                        );
                    end
                    else begin
                        refetchType = REFETCH_TYPE_THIS_PC;
                    end
                end
            end

            if (exceptionDetected && !recovery.unableToStartRecovery) begin
                nextRecoveryReg.state = EXEC_STATE_SUCCESS;
            end
        end

        //PCのリカバリに用いる
        //これらのPCはRecoveryManagerのRecoveryRegisterを経由してFetchStageに送られる
        recovery.recoveredPC_FromCommitStage = ToAddrFromPC(recoveryReg.pc);
        recovery.recoveredPC_FromRwStage = ToAddrFromPC(nextRecoveryReg.pc);

        // Fault handling
        recovery.faultingDataAddr = recoveryReg.faultingDataAddr;

        //LSQのリカバリに用いる
        port.loadQueueRecoveryTailPtr = recoveryReg.loadQueuePtr;
        port.storeQueueRecoveryTailPtr = recoveryReg.storeQueuePtr;

        //リカバリをしなければならない命令はアクティブリストのtailからリカバリを起こした命令(またはその命令の後ろ)までのエントリにあたる
        flushRangeHeadPtr = recovery.flushRangeHeadPtr;
        flushRangeTailPtr = recovery.flushRangeTailPtr;

        // Calculate # of flush insts
        if (flushRangeHeadPtr == flushRangeTailPtr 
                        && count == ACTIVE_LIST_ENTRY_NUM) begin
            // Flush all insts in ActiveList
            // Because head and tail pointers match when ActiveList is full or empty,
            // flushAllInsns is needed to distinguish between them
            nextRecoveryEntryNum = ACTIVE_LIST_ENTRY_NUM;
            recovery.flushAllInsns = TRUE;
        end
        else begin
            nextRecoveryEntryNum = (flushRangeTailPtr >= flushRangeHeadPtr) ?
                                flushRangeTailPtr - flushRangeHeadPtr : ACTIVE_LIST_ENTRY_NUM + flushRangeTailPtr - flushRangeHeadPtr;
            recovery.flushAllInsns = FALSE;
        end
        // RenameLogicCommitterにtoRecoveryPhase信号が
        // 届いた次のサイクルに信号を送る必要があるので,1サイクルの遅延を入れている
        port.recoveryEntryNum = recoveryEntryNum;

        // RecoveryManagerに例外が検出されたことを知らせる信号
        // 先行してRwステージリカバリを行っていた場合は, コミット時まで待つ
        recovery.exceptionDetectedInRwStage = exceptionDetected && !recovery.unableToStartRecovery;
        recovery.refetchTypeFromRwStage = refetchType;

        // flushRangeHeadPtrを保存するために用いる
        port.exceptionOpPtr = nextRecoveryReg.ptr;
    end

    //
    // --- ExecutionState
    //

    parameter EXEC_STATE_WRITE_NUM = RENAME_WIDTH + ISSUE_WIDTH;
    logic               esWE[EXEC_STATE_WRITE_NUM];
    ActiveListIndexPath esWA[EXEC_STATE_WRITE_NUM];
    ActiveListIndexPath esRA[COMMIT_WIDTH];
    logic esWV[EXEC_STATE_WRITE_NUM];
    logic esRV[COMMIT_WIDTH];
    
    ExecutionState headExecState[COMMIT_WIDTH];

    DistributedMultiPortRAM #(
        .ENTRY_NUM(ACTIVE_LIST_ENTRY_NUM),
        .ENTRY_BIT_SIZE($bits(logic)),
        .READ_NUM(COMMIT_WIDTH),
        .WRITE_NUM(EXEC_STATE_WRITE_NUM)
    )  execState (
        .clk(port.clk),
        .we(esWE),
        .wa(esWA),
        .wv(esWV),
        .ra(esRA),
        .rv(esRV)
    );

    always_comb begin
        if (port.rst) begin
            // Head entries are initialized.
            for (int i = 0; i < EXEC_STATE_WRITE_NUM; i++) begin
                esWE[i] = FALSE;
                esWA[i] = i;
                esWV[i] = FALSE;
            end
        end
        else begin
            for (int i = 0; i < RENAME_WIDTH; i++) begin
                esWE[i] = port.pushTail[i];
                esWA[i] = pushedTailPtr[i];
                esWV[i] = FALSE;
            end

            for (int i = 0; i < ISSUE_WIDTH; i++ ) begin
                esWE[(i+RENAME_WIDTH)] = we[i];
                esWA[(i+RENAME_WIDTH)] = writeData[i].ptr;
                //Rwステージで検出された例外はコミットステージで再度検出されないようにExecStateをEXEC_STATE_SUCCESSにしておく必要がある
                //exceptionIndexは例外を起こした命令の場所を示す
                //esWV[(i+RENAME_WIDTH)] = ( exceptionDetected && !recovery.unableToStartRecovery && (exceptionIndex == i) ) ? TRUE : writeData[i].state;
                esWV[(i+RENAME_WIDTH)] = (writeData[i].state != EXEC_STATE_NOT_FINISHED);
            end
        end

        esRA = headPtrList;
        for (int i = 0; i < COMMIT_WIDTH; i++) begin
            if (recoveryReg.valid && (esRA[i] == recoveryReg.ptr)) begin
                headExecState[i] = recoveryReg.state;
            end
            else begin
                if (esRV[i]) begin
                    headExecState[i] = EXEC_STATE_SUCCESS;
                end
                else begin
                    headExecState[i] = EXEC_STATE_NOT_FINISHED;
                end
            end
        end
        port.headExecState = headExecState;
    end
    
// Verify whether the ExecState is correct
`ifndef RSD_SYNTHESIS
    logic               esRefWE[EXEC_STATE_WRITE_NUM];
    ActiveListIndexPath esRefWA[EXEC_STATE_WRITE_NUM];
    ActiveListIndexPath esRefRA[COMMIT_WIDTH];
    logic [EXEC_STATE_BIT_WIDTH-1:0] esRefWV[EXEC_STATE_WRITE_NUM];
    logic [EXEC_STATE_BIT_WIDTH-1:0] esRefRV[COMMIT_WIDTH];
    logic execStateIsDifferentFromRef;
    
    // Whether in recovery
    logic regInRecovery, nextInRecovery;
    always_ff@(posedge port.clk) begin
        if (port.rst) begin
            regInRecovery <= FALSE;
        end
        else begin
            regInRecovery <= nextInRecovery;
        end
    end


    // Record ExecState of all instructions in ActiveList
    DistributedMultiPortRAM #(
        .ENTRY_NUM(ACTIVE_LIST_ENTRY_NUM),
        .ENTRY_BIT_SIZE($bits(ExecutionState)),
        .READ_NUM(COMMIT_WIDTH),
        .WRITE_NUM(EXEC_STATE_WRITE_NUM)
    ) execStateRef (
        .clk(port.clk),
        .we(esRefWE),
        .wa(esRefWA),
        .wv(esRefWV),
        .ra(esRefRA),
        .rv(esRefRV)
    );

    ExecutionState headExecStateRef[COMMIT_WIDTH];

    always_comb begin
        esRefRA = headPtrList;
        
        if (port.rst) begin
            // Head entries are initialized.
            for (int i = 0; i < EXEC_STATE_WRITE_NUM; i++) begin
                esRefWE[i] = FALSE;
                esRefWA[i] = i;
                esRefWV[i] = EXEC_STATE_NOT_FINISHED;
            end
        end
        else begin
            for (int i = 0; i < RENAME_WIDTH; i++) begin
                esRefWE[i] = port.pushTail[i];
                esRefWA[i] = pushedTailPtr[i];
                esRefWV[i] = EXEC_STATE_NOT_FINISHED;
            end

            for (int i = 0; i < ISSUE_WIDTH; i++ ) begin
                esRefWE[(i+RENAME_WIDTH)] = we[i];
                esRefWA[(i+RENAME_WIDTH)] = writeData[i].ptr;
                //Rwステージで検出された例外はコミットステージで再度検出されないようにExecStateをEXEC_STATE_SUCCESSにしておく必要がある
                //exceptionIndexは例外を起こした命令の場所を示す
                esRefWV[(i+RENAME_WIDTH)] = ( exceptionDetected && !recovery.unableToStartRecovery && (exceptionIndex == i) ) ? EXEC_STATE_SUCCESS : writeData[i].state;
            end
        end

        nextInRecovery = regInRecovery;
        if (recovery.toRecoveryPhase) begin
            nextInRecovery = TRUE;
        end
        if (recovery.toCommitPhase) begin
            nextInRecovery = FALSE;
        end
        
        execStateIsDifferentFromRef = FALSE;
        for (int i = 0; i < COMMIT_WIDTH; i++) begin
            headExecStateRef[i] = ExecutionState'(esRefRV[i]);
            
            // Compare ExecState to reference value
            if (esRV[i] && (i < count) && !nextInRecovery) begin
                execStateIsDifferentFromRef |= 
                    (headExecState[i] != headExecStateRef[i]);
            end

            // Do not check instructions after the exception
            if (esRA[i] == recoveryReg.ptr) begin
                break;
            end
        end
    end

    `RSD_ASSERT_CLK(
        port.clk,
        !execStateIsDifferentFromRef,
        "Execution State value is different from the reference's value."
    );

`endif

endmodule : ActiveList
