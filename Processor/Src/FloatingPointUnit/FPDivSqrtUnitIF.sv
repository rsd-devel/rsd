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
    logic       Finished [FP_DIVSQRT_ISSUE_WIDTH];
    logic       Busy     [FP_DIVSQRT_ISSUE_WIDTH];
    logic       Free     [FP_DIVSQRT_ISSUE_WIDTH];

    logic Acquire[FP_DIVSQRT_ISSUE_WIDTH];
    logic Release[FP_DIVSQRT_ISSUE_WIDTH];
    ActiveListIndexPath acquireActiveListPtr[FP_DIVSQRT_ISSUE_WIDTH];

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
        Release,
        acquireActiveListPtr,
    output
        DataOut,
        FFlagsOut,
        Finished,
        Busy,
        Reserved,
        Free
    );

    modport FPIssueStage(
    output
        Acquire,
        acquireActiveListPtr
    );

    modport FPExecutionStage(
    input
        DataOut,
        Finished,
        Busy,
        Reserved,
        Free,
        FFlagsOut,
    output
        stall,
        dataInA,
        dataInB,
        is_divide,
        rm,
        Req,
        Release
    );

    modport Scheduler(
    input
        Free
    );

    modport ReplayQueue(
    input
        Busy
    );
endinterface
