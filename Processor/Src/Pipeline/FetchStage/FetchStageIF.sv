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

    // Registered PC used as the interrupt return address.
    PC_Path  pcOut;

    // Address for the next predictor lookup, including redirects and repeated requests.
    PC_Path  fetchRequestPC;

    // Executed branch results for updating a branch predictor.
    // This signal is written back from a write back stage.
    BranchResult brResult[ INT_ISSUE_WIDTH ];

    // Interrupt
    PC_Path interruptAddrIn;
    logic interruptAddrWE;

    // BTB/PHT results and updateBrHistory use groupOffset, in instructions from the aligned group base.
    PC_Path btbOut[FETCH_WIDTH];
    logic btbHit[FETCH_WIDTH];
    BTB_WayIndexPath btbHitWay[FETCH_WIDTH];
    logic readIsCondBr[FETCH_WIDTH];
    logic brPredTaken[FETCH_WIDTH];
    BranchGlobalHistoryPath brGlobalHistory[FETCH_WIDTH];
    PHT_EntryPath phtPrevValue[FETCH_WIDTH];

    logic updateBrHistory[FETCH_WIDTH];

    // Addresses for the next cache lookup and the response currently in Fetch.
    AddrPath icNextReadAddrIn, icReadAddrIn;
    logic icRE;
    // I-cache responses and nextStage use fetchLane. Lane 0 is the instruction at icReadAddrIn.
    logic icReadHit[FETCH_WIDTH];
    InsnPath icReadDataOut[FETCH_WIDTH];

    PreDecodeStageRegPath nextStage[FETCH_WIDTH];

    modport ThisStage(
    input
        clk,
        rst,
        interruptAddrIn,
        interruptAddrWE,
        btbHit,
        btbHitWay,
        btbOut,
        brPredTaken,
        brGlobalHistory,
        phtPrevValue,
        icReadHit,
        icReadDataOut,
    output
        pcOut,
        fetchRequestPC,
        updateBrHistory,
        icNextReadAddrIn,
        icReadAddrIn,
        icRE,
        nextStage
    );

    modport NextStage(
    input
        nextStage
    );

    modport IntegerRegisterWriteStage(
    output
        brResult
    );

    modport BTB(
    input
        clk,
        rst,
        rstStart,
        fetchRequestPC,
        brResult,
    output
        btbOut,
        btbHit,
        btbHitWay,
        readIsCondBr
    );

    modport BranchPredictor(
    input
        clk,
        rst,
        rstStart,
        fetchRequestPC,
        brResult,
        updateBrHistory,
        btbHit,
        readIsCondBr,
    output
        brPredTaken,
        brGlobalHistory,
        phtPrevValue
    );

    modport ICache(
    input
        clk,
        rst,
        rstStart,
        icNextReadAddrIn,
        icRE,
        icReadAddrIn,
    output
        icReadHit,
        icReadDataOut
    );

    modport InterruptController(
    input
        pcOut,
    output
        interruptAddrIn,
        interruptAddrWE
    );


endinterface : FetchStageIF
