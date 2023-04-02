// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// A pipeline stage for register read.
//


import BasicTypes::*;
import OpFormatTypes::*;
import MicroOpTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;
import CacheSystemTypes::*;
import PipelineTypes::*;
import DebugTypes::*;

//
// --- オペランドの選択
//
function automatic DataPath SelectOperand(
input
    OpOperandType opType, DataPath regV, DataPath immV, DataPath pcV
);
    case( opType )
    default:    // OOT_REG
        return regV;
    OOT_IMM:
        return immV;
    OOT_PC:
        return pcV;
    endcase
endfunction

//
// --- Memory Register Read Stage
//
module MemoryRegisterReadStage(
    MemoryRegisterReadStageIF.ThisStage port,
    MemoryIssueStageIF.NextStage prev,
    RegisterFileIF.MemoryRegisterReadStage registerFile,
    BypassNetworkIF.MemoryRegisterReadStage bypass,
    RecoveryManagerIF.MemoryRegisterReadStage recovery,
    ControllerIF.MemoryRegisterReadStage ctrl,
    DebugIF.MemoryRegisterReadStage debug
);

    // --- Pipeline registers
    MemoryRegisterReadStageRegPath pipeReg [MEM_ISSUE_WIDTH];

`ifndef RSD_SYNTHESIS
    // Don't care these values, but avoiding undefined status in Questa.
    initial begin
        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            pipeReg[i] = '0;
        end
    end
`endif

    always_ff@( posedge port.clk )   // synchronous rst
    begin
        if (port.rst) begin
            for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
                pipeReg[i].valid <= '0;
            end
        end
        else if (!ctrl.backEnd.stall) begin             // write data
            pipeReg <= prev.nextStage;
        end
    end


    // Operand
    DataPath immOut [ MEM_ISSUE_WIDTH ];
    AddrPath pc [ MEM_ISSUE_WIDTH ];
    PRegDataPath operandA [ MEM_ISSUE_WIDTH ];
    PRegDataPath operandB [ MEM_ISSUE_WIDTH ];

    // Pipeline controll
    logic stall, clear;
    logic flush[ MEM_ISSUE_WIDTH ];
    MemIssueQueueEntry iqData[MEM_ISSUE_WIDTH];
    MemOpInfo memOpInfo[MEM_ISSUE_WIDTH];
    OpSrc opSrc[MEM_ISSUE_WIDTH];
    OpDst opDst[MEM_ISSUE_WIDTH];
    MemoryExecutionStageRegPath nextStage [MEM_ISSUE_WIDTH];
    MSHR_IndexPath mshrID;

    always_comb begin
        stall = ctrl.backEnd.stall;
        clear = ctrl.backEnd.clear;

        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            iqData[i] = pipeReg[i].memQueueData;
            memOpInfo[i] = iqData[i].memOpInfo;
            opSrc[i] = iqData[i].opSrc;
            opDst[i] = iqData[i].opDst;
            pc[i] = iqData[i].pc;

            //
            // Register file
            //

            registerFile.memSrcRegNumA[i] = opSrc[i].phySrcRegNumA;
            registerFile.memSrcRegNumB[i] = opSrc[i].phySrcRegNumB;


            //
            // To a bypass network.
            // ストールやフラッシュの制御は，Bypass モジュールの内部で
            // コントローラの信号を参照して行われている
            //
            bypass.memPhySrcRegNumA[i] = opSrc[i].phySrcRegNumA;
            bypass.memPhySrcRegNumB[i] = opSrc[i].phySrcRegNumB;

            bypass.memWriteReg[i]  = opDst[i].writeReg & pipeReg[i].valid;
            bypass.memPhyDstRegNum[i] = opDst[i].phyDstRegNum;
            bypass.memReadRegA[i] = ( memOpInfo[i].operandTypeA == OOT_REG );
            bypass.memReadRegB[i] = ( memOpInfo[i].operandTypeB == OOT_REG );

            //
            // --- オペランド選択
            //
            immOut[i] = '0; //RISCVにおいて即値をオペランドにとるようなロード/ストアはない(アドレス計算はExecutionStage)
            operandA[i].data = SelectOperand(
                memOpInfo[i].operandTypeA,
                registerFile.memSrcRegDataA[i].data,
                immOut[i],
                pc[i]
            );
            operandB[i].data = SelectOperand(
                memOpInfo[i].operandTypeB,
                registerFile.memSrcRegDataB[i].data,
                immOut[i],
                pc[i]
            );
            operandA[i].valid = (memOpInfo[i].operandTypeA != OOT_REG || registerFile.memSrcRegDataA[i].valid);
            operandB[i].valid = (memOpInfo[i].operandTypeB != OOT_REG || registerFile.memSrcRegDataB[i].valid);

            //
            // --- Pipeline ラッチ書き込み
            //
            `ifndef RSD_DISABLE_DEBUG_REGISTER
                nextStage[i].opId = pipeReg[i].opId;
            `endif


            // リセットorフラッシュ時はNOP
            flush[i] = SelectiveFlushDetector(
                recovery.toRecoveryPhase,
                recovery.flushRangeHeadPtr,
                recovery.flushRangeTailPtr,
                recovery.flushAllInsns,
                iqData[i].activeListPtr
            );
            nextStage[i].valid =
                (stall || clear || port.rst || flush[i]) ? FALSE : pipeReg[i].valid;

            nextStage[i].memQueueData = pipeReg[i].memQueueData;

            // レジスタ値&フラグ
            nextStage[i].operandA = operandA[i];
            nextStage[i].operandB = operandB[i];

            // バイパス制御
            nextStage[i].bCtrl = bypass.memCtrlOut[i];

            // Release the entries of the issue queue.
            nextStage[i].replay = pipeReg[i].replay && pipeReg[i].valid;
            nextStage[i].issueQueuePtr = pipeReg[i].issueQueuePtr;
        end

        port.nextStage = nextStage;

        // Debug Register
`ifndef RSD_DISABLE_DEBUG_REGISTER
        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            debug.memRrReg[i].valid = pipeReg[i].valid;
            debug.memRrReg[i].flush = flush[i];
            debug.memRrReg[i].opId = pipeReg[i].opId;
        end
`endif
    end
endmodule : MemoryRegisterReadStage
