// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- FetchStageIF
//

import BasicTypes::*;
import PipelineTypes::*;
import FetchUnitTypes::*;
import MemoryMapTypes::*;

interface FetchStageIF( input logic clk, rst, rstStart );

    // Predictions and their valid mask are indexed from the aligned fetch-group base.
    logic [FETCH_WIDTH-1:0] fetchSlotValid;

    // BTB
    PC_Path btbOut[FETCH_WIDTH];
    logic btbHit[FETCH_WIDTH];
    BTB_WayIndexPath btbHitWay[FETCH_WIDTH];
    logic readIsCondBr[FETCH_WIDTH];
    
    // BranchPredictor
    logic updateBrHistory[FETCH_WIDTH];
    logic brPredTaken[FETCH_WIDTH];
    BranchGlobalHistoryPath brGlobalHistory[FETCH_WIDTH];
    PHT_EntryPath phtPrevValue[FETCH_WIDTH];

    // I-Cache
    logic     icReadHit [ FETCH_WIDTH ];
    logic     icRE;
    InsnPath  icReadDataOut[ FETCH_WIDTH ];
    AddrPath  icReadAddrIn; // Logical address of the current fetch.

    // Pipeline register
    PreDecodeStageRegPath nextStage[ FETCH_WIDTH ];

    modport ThisStage(
    input
        clk,
        rst,
        icReadHit,
        icReadDataOut,
        btbOut,
        btbHit,
        btbHitWay,
        brPredTaken,
        brGlobalHistory,
        phtPrevValue,
    output
        fetchSlotValid,
        updateBrHistory,
        nextStage,
        icRE,
        icReadAddrIn
    );

    modport BrPredStage(
    input
        fetchSlotValid,
        icRE,
        icReadAddrIn,
        btbOut,
        btbHit,
        brPredTaken
    );

    modport NextStage(
    input
        nextStage
    );

    modport ICache(
    input
        icRE, // Read Enable
        icReadAddrIn,
    output
        icReadHit,
        icReadDataOut
    );

    modport BTB(
    output
        btbOut,
        btbHit,
        btbHitWay,
        readIsCondBr
    );

    modport BranchPredictor(
    input
        updateBrHistory,
        btbOut,
        btbHit,
        readIsCondBr,
    output
        brPredTaken,
        brGlobalHistory,
        phtPrevValue
    );

endinterface : FetchStageIF
