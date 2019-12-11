// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Complex Integer Execution stage
//
// 乗算/SIMD 命令の演算を行う
// COMPLEX_EXEC_STAGE_DEPTH 段にパイプライン化されている
//

`include "BasicMacros.sv"
import BasicTypes::*;
import OpFormatTypes::*;


interface MulDivUnitIF(input logic clk, rst);

    logic stall;

    DataPath dataInA[MULDIV_ISSUE_WIDTH];
    DataPath dataInB[MULDIV_ISSUE_WIDTH];

    DataPath    mulDataOut  [MULDIV_ISSUE_WIDTH];
    logic       mulGetUpper [MULDIV_ISSUE_WIDTH];
    IntMUL_Code mulCode     [MULDIV_ISSUE_WIDTH];

    DataPath    divDataOut  [MULDIV_ISSUE_WIDTH];
    IntDIV_Code divCode     [MULDIV_ISSUE_WIDTH];
    logic       divReset    [MULDIV_ISSUE_WIDTH];
    logic       divReq      [MULDIV_ISSUE_WIDTH];
    logic       divReserved [MULDIV_ISSUE_WIDTH];
    logic       divFinished [MULDIV_ISSUE_WIDTH];
    logic       divBusy     [MULDIV_ISSUE_WIDTH];
    logic       divFree     [MULDIV_ISSUE_WIDTH];

    logic divAcquire[MULDIV_ISSUE_WIDTH];
    logic divRelease[MULDIV_ISSUE_WIDTH];

    logic divResetFromMI_Stage[MULDIV_ISSUE_WIDTH];
    logic divResetFromMR_Stage[MULDIV_ISSUE_WIDTH];
    logic divResetFromMT_Stage[MULDIV_ISSUE_WIDTH];
    
    logic divResetFromCI_Stage[MULDIV_ISSUE_WIDTH];

    modport MulDivUnit(
    input
        clk,
        rst,
        stall,
        dataInA,
        dataInB,
        mulGetUpper,
        mulCode,
        divCode,
        divReset,
        divResetFromCI_Stage,
        divResetFromMI_Stage,
        divResetFromMR_Stage,
        divResetFromMT_Stage,
        divReq,
        divAcquire,
        divRelease,
    output
        mulDataOut,
        divDataOut,
        divFinished,
        divBusy,
        divReserved,
        divFree
    );

    modport ComplexIntegerIssueStage(
    output
        divAcquire,
        divResetFromCI_Stage
    );

    modport ComplexIntegerExecutionStage(
    input
        mulDataOut,
        divDataOut,
        divFinished,
        divBusy,
        divReserved,
        divFree,
    output
        stall,
        dataInA,
        dataInB,
        mulGetUpper,
        mulCode,
        divCode,
        divReset,
        divReq,
        divRelease
    );

    modport MemoryIssueStage(
    output
        divAcquire,
        divResetFromMI_Stage
    );

    modport MemoryRegisterReadStage(
    output
        divResetFromMR_Stage
    );

    modport MemoryExecutionStage(
    input
        divBusy,
        divReserved,
        divFree,
    output
        stall,
        dataInA,
        dataInB,
        mulGetUpper,
        mulCode,
        divCode,
        divReset,
        divReq
    );

    modport MemoryTagAccessStage(
    input
        divFinished,
    output 
        divResetFromMT_Stage
    );

    modport MemoryAccessStage(
    input
        mulDataOut,
        divDataOut,
        divFinished,
    output 
        divRelease
    );


    modport Scheduler(
    input
        divFree
    );

    modport ReplayQueue(
    input
        divBusy
    );

endinterface
