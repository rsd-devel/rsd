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

    // The BTB and PHT read and capture the predecessor's rows on the same edges.
    logic btbUpdateAllowed, capturePredRows, brLookupValid;
    BTB_SetIndexPath btbReadSet;
    PHT_RowIndexPath phtReadRow;

    // Executed branch results for updating a branch predictor.
    // This signal is written back from a write back stage.
    BranchResult brResult[ INT_ISSUE_WIDTH ];

    // Interrupt
    PC_Path interruptAddrIn;
    logic interruptAddrWE;

    // BTB/PHT results use groupOffset, in instructions from the aligned group base.
    PC_Path btbOut[FETCH_WIDTH];
    logic btbHit[FETCH_WIDTH];
    BTB_WayIndexPath btbHitWay[FETCH_WIDTH];
    BTB_BranchType readBrType[FETCH_WIDTH];
    logic brPredTaken[FETCH_WIDTH];
    PHT_EntryPath phtPrevValue[FETCH_WIDTH];

    PC_Path rasTopPC;
    RAS_IndexPath rasPtr;

    // Addresses for the next cache lookup and the response currently in Fetch.
    AddrPath icNextReadAddrIn, icReadAddrIn;
    logic icRE;
    // A hit covers the cache line containing icReadAddrIn.
    logic icReadHit;
    // Lane 0 of the I-cache response and the group sent to PreDecode start at icReadAddrIn.
    InsnPath icReadDataOut[FETCH_WIDTH];

    PreDecodeStageRegPath nextStage;

    modport ThisStage(
    input
        clk,
        rst,
        interruptAddrIn,
        interruptAddrWE,
        btbHit,
        btbHitWay,
        btbOut,
        readBrType,
        brPredTaken,
        phtPrevValue,
        rasTopPC,
        rasPtr,
        icReadHit,
        icReadDataOut,
    output
        pcOut,
        phtReadRow,
        btbUpdateAllowed,
        capturePredRows,
        btbReadSet,
        brLookupValid,
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
        pcOut,
        btbUpdateAllowed,
        capturePredRows,
        btbReadSet,
        brLookupValid,
        brResult,
    output
        btbOut,
        btbHit,
        btbHitWay,
        readBrType
    );

    modport RAS(
    input
        clk,
        rst,
        rstStart,
        pcOut,
        interruptAddrWE,
        nextStage,
    output
        rasTopPC,
        rasPtr
    );

    modport BranchPredictor(
    input
        clk,
        rst,
        rstStart,
        phtReadRow,
        capturePredRows,
        brLookupValid,
        brResult,
    output
        brPredTaken,
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
