// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Integer Write back stage
//

import BasicTypes::*;
import OpFormatTypes::*;
import MicroOpTypes::*;
import RenameLogicTypes::*;
import PipelineTypes::*;
import SchedulerTypes::*;
import FetchUnitTypes::*;
import DebugTypes::*;




module IntegerRegisterWriteStage(
    //IntegerRegisterWriteStageIF.ThisStage port,
    IntegerExecutionStageIF.NextStage prev,
    SchedulerIF.IntegerRegisterWriteStage scheduler,
    NextPCStageIF.IntegerRegisterWriteStage ifStage,
    RegisterFileIF.IntegerRegisterWriteStage registerFile,
    ActiveListIF.IntegerRegisterWriteStage activeList,
    RecoveryManagerIF.IntegerRegisterWriteStage recovery,
    ControllerIF.IntegerRegisterWriteStage ctrl,
    DebugIF.IntegerRegisterWriteStage debug
);
    IntegerRegisterWriteStageRegPath pipeReg [INT_ISSUE_WIDTH];

`ifndef RSD_SYNTHESIS
    // Don't care these values, but avoiding undefined status in Questa.
    initial begin
        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            pipeReg[i] = '0;
        end
    end
`endif

    // --- Pipeline registers
    always_ff@( posedge /*port.clk*/ ctrl.clk )   // synchronous rst
    begin
        if (ctrl.rst) begin
            for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
                pipeReg[i].valid <= FALSE;
            end
        end
        else if(!ctrl.backEnd.stall) begin   // write data
            pipeReg <= prev.nextStage;
        end
    end

    ActiveListWriteData alWriteData[INT_ISSUE_WIDTH];
    IntIssueQueueEntry iqData[INT_ISSUE_WIDTH];
    BranchResult brResult[INT_ISSUE_WIDTH];
    logic stall, clear;
    logic flush[ INT_ISSUE_WIDTH ];
    logic update [ INT_ISSUE_WIDTH ];
    logic valid [ INT_ISSUE_WIDTH ];
    logic regValid [ INT_ISSUE_WIDTH ];

    always_comb begin

        // Pipeline control
        stall = ctrl.backEnd.stall;
        clear = ctrl.backEnd.clear;

        for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            iqData[i] = pipeReg[i].intQueueData;
            regValid[i] = pipeReg[i].dataOut.valid;

            valid[i] = pipeReg[i].valid;
            flush[i] = SelectiveFlushDetector(
                        recovery.toRecoveryPhase,
                        recovery.flushRangeHeadPtr,
                        recovery.flushRangeTailPtr,
                        iqData[i].activeListPtr
                        );
            update[i] = !stall && !clear && valid[i] && !flush[i];

            //
            // Register file
            //
            registerFile.intDstRegWE[i] =
                update[i] && iqData[i].opDst.writeReg;

            registerFile.intDstRegNum[i] = iqData[i].opDst.phyDstRegNum;
            registerFile.intDstRegData[i] = pipeReg[i].dataOut;

            //
            // Active list
            //
            alWriteData[i].ptr = iqData[i].activeListPtr;
            alWriteData[i].loadQueuePtr = iqData[i].loadQueueRecoveryPtr;
            alWriteData[i].storeQueuePtr = iqData[i].storeQueueRecoveryPtr;
            alWriteData[i].pc = pipeReg[i].brResult.nextAddr;
            alWriteData[i].dataAddr = '0;
            alWriteData[i].isBranch = (iqData[i].opType inside { INT_MOP_TYPE_BR, INT_MOP_TYPE_RIJ });
            alWriteData[i].isStore = FALSE;

            // Branch results.
            brResult[i] = pipeReg[i].brResult;
            brResult[i].valid = pipeReg[i].brResult.valid && update[i] && regValid[i];
            ifStage.brResult = brResult;

            // ExecState
            if ( update[i] ) begin
                if (regValid[i]) begin
                    alWriteData[i].state =
                        pipeReg[i].brMissPred ? EXEC_STATE_REFETCH_NEXT : EXEC_STATE_SUCCESS;
                end
                else begin
                    alWriteData[i].state = EXEC_STATE_NOT_FINISHED;
                end
            end
            else begin
                alWriteData[i].state = EXEC_STATE_NOT_FINISHED;
            end


            // 実行が正しく終了してる場合，フォールト判定を行う
            if (alWriteData[i].state inside {EXEC_STATE_REFETCH_NEXT, EXEC_STATE_SUCCESS}) begin
                if (brResult[i].nextAddr[INSN_ADDR_BIT_WIDTH-1:0] != 0 && brResult[i].valid) begin
                    alWriteData[i].state = EXEC_STATE_FAULT_INSN_MISALIGNED;
                    alWriteData[i].dataAddr = brResult[i].nextAddr;
                end
            end

            activeList.intWrite[i] = update[i];
            activeList.intWriteData[i] = alWriteData[i];

            // Replay
            scheduler.intRecordEntry[i] = update[i] && !regValid[i];
            scheduler.intRecordData[i] = pipeReg[i].intQueueData;
        end

        // Debug Register
        `ifndef RSD_DISABLE_DEBUG_REGISTER
            for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
                debug.intRwReg[i].valid = valid[i];
                debug.intRwReg[i].flush = flush[i];
                debug.intRwReg[i].opId = pipeReg[i].opId;
            end
        `endif
    end
endmodule : IntegerRegisterWriteStage
