// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- BrPredStageIF
//

import BasicTypes::*;
import PipelineTypes::*;
import FetchUnitTypes::*;
import MemoryMapTypes::*;

interface BrPredStageIF( input logic clk, rst, rstStart );
    
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

    // I-cache
    AddrPath  icNextReadAddrIn; // Logical address for the next I-cache lookup.

    // Pipeline register
    FetchStageRegPath nextStage[ FETCH_WIDTH ];

    modport ThisStage(
    input
        clk,
        rst,
        brResult,
        interruptAddrIn,
        interruptAddrWE,
    output
        pcOut,
        fetchRequestPC,
        icNextReadAddrIn,
        nextStage
    );

    modport NextStage(
    input
        fetchRequestPC,
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
        brResult
    );

    modport BranchPredictor(
    input
        clk,
        rst,
        rstStart,
        fetchRequestPC,
        brResult
    );

    modport ICache(
    input
        clk,
        rst,
        rstStart,
        icNextReadAddrIn
    );

    modport InterruptController(
    input
        pcOut,
    output
        interruptAddrIn,
        interruptAddrWE
    );


endinterface : BrPredStageIF
