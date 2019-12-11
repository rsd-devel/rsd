// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- Controller
//

import BasicTypes::*;
import PipelineTypes::*;


interface ControllerIF(
input
    logic clk,
    logic rst
);


    //
    // Pipeline
    //
    // PipelineControll::stall は，そのステージの頭にあるパイプラインレジスタの
    // 書き込み制御を行う．たとえば ifStage であれば PC の，idStage であれば，
    // if/id ステージ間のパイプラインレジスタの WE に接続される．
    //
    // PipelineControll::clear は，有効な場合，そのステージの次のステージに送り
    // 込む命令の valid を強制的に落とす（次のステージにNOPを送る）．
    // これは，そのサイクルにそのステージにいる命令を無効化し，
    // 次のステージにNOP を送り込むことを意味する．
    //
    PipelineControll npStage;
    PipelineControll ifStage;
    PipelineControll pdStage;
    PipelineControll idStage;
    PipelineControll rnStage;
    PipelineControll dsStage;

    PipelineControll scStage;
    PipelineControll isStage;
    PipelineControll backEnd;
    PipelineControll cmStage;

    // 生きた命令がいるかどうか
    logic ifStageEmpty;
    logic pdStageEmpty;
    logic idStageEmpty;
    logic rnStageEmpty;
    logic activeListEmpty;
    logic wholePipelineEmpty;

    //
    // --- Requests from pipeline stages.
    //
    logic npStageSendBubbleLower;
    logic npStageSendBubbleLowerForInterrupt;
    logic ifStageSendBubbleLower;
    logic idStageStallUpper;
    logic rnStageFlushUpper;
    logic rnStageSendBubbleLower;
    logic cmStageFlushUpper;
    logic isStageStallUpper;

    //
    // --- Special signals
    //
    logic stallByDecodeStage;

    modport Controller(
    input
        clk,
        rst,
        cmStageFlushUpper,
        rnStageSendBubbleLower,
        idStageStallUpper,
        rnStageFlushUpper,
        npStageSendBubbleLower,
        ifStageSendBubbleLower,
        npStageSendBubbleLowerForInterrupt,
        isStageStallUpper,
        ifStageEmpty,
        pdStageEmpty,
        idStageEmpty,
        rnStageEmpty,
        activeListEmpty,
    output
        npStage,
        ifStage,
        pdStage,
        idStage,
        rnStage,
        dsStage,
        isStage,
        scStage,
        backEnd,
        cmStage,
        stallByDecodeStage,
        wholePipelineEmpty
    );

    modport NextPCStage(
    input
        npStage,
    output
        npStageSendBubbleLower
    );

    modport FetchStage(
    input
        ifStage,
    output
        ifStageSendBubbleLower,
        ifStageEmpty
    );

    modport DecodeStage(
    input
        idStage,
        stallByDecodeStage,
    output
        idStageStallUpper,
        idStageEmpty
    );

    modport PreDecodeStage(
    input
        pdStage,
    output
        pdStageEmpty
    );

    modport RenameStage(
    input
        rnStage,
    output
        rnStageFlushUpper,
        rnStageSendBubbleLower,
        rnStageEmpty
    );

    modport DispatchStage(
    input
        clk,
        rst,
        dsStage
    );

    modport ScheduleStage(
    input
        scStage
    );

    modport IntegerIssueStage(
    input
        isStage,
        isStageStallUpper
    );

    modport IntegerRegisterReadStage(
    input
        backEnd
    );

    modport IntegerExecutionStage(
    input
        backEnd
    );

    modport IntegerRegisterWriteStage(
    input
        clk,
        rst,
        backEnd
    );

    modport ComplexIntegerIssueStage(
    input
        isStage
    );

    modport ComplexIntegerRegisterReadStage(
    input
        backEnd
    );

    modport ComplexIntegerExecutionStage(
    input
        backEnd
    );

    modport ComplexIntegerRegisterWriteStage(
    input
        clk,
        rst,
        backEnd
    );

    modport MemoryIssueStage(
    input
        isStage
    );

    modport MemoryRegisterReadStage(
    input
        backEnd
    );

    modport MemoryExecutionStage(
    input
        backEnd
    );

    modport MemoryTagAccessStage(
    input
        backEnd
    );

    modport MemoryAccessStage(
    input
        backEnd
    );

    modport MemoryRegisterWriteStage(
    input
        clk,
        rst,
        backEnd
    );

    modport CommitStage(
    input
        cmStage
    );

    modport BypassController(
    input
        backEnd
    );

    modport BypassNetwork(
    input
        backEnd
    );

    modport VectorBypassNetwork(
    input
        backEnd
    );

    modport DCache(
    input
        backEnd
    );

    modport LoadStoreUnit(
    input
        backEnd
    );

    modport ReplayQueue(
    output
        isStageStallUpper
    );

    modport BranchPredictor(
    input
        ifStage
    );

    modport RecoveryManager(
    output
        cmStageFlushUpper
    );

    modport ActiveList(
    output
        activeListEmpty
    );

    modport InterruptController(
    input 
        wholePipelineEmpty,
    output 
        npStageSendBubbleLowerForInterrupt
    );

endinterface : ControllerIF

