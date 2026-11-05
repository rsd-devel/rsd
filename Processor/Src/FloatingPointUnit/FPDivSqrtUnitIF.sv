// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// FP Div/Sqrt Unit
//

`include "BasicMacros.sv"
import BasicTypes::*;
import OpFormatTypes::*;
import ActiveListIndexTypes::*;

interface FPDivSqrtUnitIF(input logic clk, rst);
    logic stall;

    DataPath dataInA[FP_DIVSQRT_ISSUE_WIDTH];
    DataPath dataInB[FP_DIVSQRT_ISSUE_WIDTH];

    DataPath    DataOut  [FP_DIVSQRT_ISSUE_WIDTH];
    FFlags_Path FFlagsOut[FP_DIVSQRT_ISSUE_WIDTH];
    logic is_divide      [FP_DIVSQRT_ISSUE_WIDTH];
    Rounding_Mode rm     [FP_DIVSQRT_ISSUE_WIDTH];
    logic       Req      [FP_DIVSQRT_ISSUE_WIDTH];
    logic       Reserved [FP_DIVSQRT_ISSUE_WIDTH];
    logic       Busy     [FP_DIVSQRT_ISSUE_WIDTH];
    logic       Free     [FP_DIVSQRT_ISSUE_WIDTH];

    logic Acquire[FP_DIVSQRT_ISSUE_WIDTH];
    ActiveListIndexPath acquireActiveListPtr[FP_DIVSQRT_ISSUE_WIDTH];
    OpDst acquireOpDst[FP_DIVSQRT_ISSUE_WIDTH];
    OpDst pendingDst[FP_DIVSQRT_ISSUE_WIDTH];

    // Complete through an idle ordinary FP RW port after its invalidation.
    logic passedRW[FP_DIVSQRT_ISSUE_WIDTH];
    logic writeReady[FP_DIVSQRT_ISSUE_WIDTH];
    logic writeValid[FP_DIVSQRT_ISSUE_WIDTH];
    ActiveListIndexPath writePtr[FP_DIVSQRT_ISSUE_WIDTH];

    modport FPDivSqrtUnit(
    input
        clk,
        rst,
        stall,
        dataInA,
        dataInB,
        is_divide,
        rm,
        Req,
        Acquire,
        acquireActiveListPtr,
        acquireOpDst,
        passedRW,
        writeReady,
    output
        DataOut,
        FFlagsOut,
        pendingDst,
        writeValid,
        writePtr,
        Busy,
        Reserved,
        Free
    );

    modport FPIssueStage(
    output
        Acquire,
        acquireActiveListPtr,
        acquireOpDst
    );

    modport FPExecutionStage(
    input
        Busy,
        Reserved,
        Free,
    output
        stall,
        dataInA,
        dataInB,
        is_divide,
        rm,
        Req
    );

    modport FPRegisterWriteStage(
    input
        DataOut,
        FFlagsOut,
        pendingDst,
        writeValid,
        writePtr,
    output
        passedRW,
        writeReady
    );

    modport Scheduler(
    input
        Free
    );

    modport ReplayQueue(
    input
        Busy,
        pendingDst
    );
endinterface
