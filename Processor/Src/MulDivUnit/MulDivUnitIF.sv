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
import ActiveListIndexTypes::*;


interface MulDivUnitIF(input logic clk, rst);

    // dummy signal to prevent that some modports become empty
    logic dummy;
    logic stall;

    DataPath dataInA[MULDIV_ISSUE_WIDTH];
    DataPath dataInB[MULDIV_ISSUE_WIDTH];

    DataPath    mulDataOut  [MULDIV_ISSUE_WIDTH];
    logic       mulGetUpper [MULDIV_ISSUE_WIDTH];
    IntMUL_Code mulCode     [MULDIV_ISSUE_WIDTH];

    IntDIV_Code divCode     [MULDIV_ISSUE_WIDTH];
    logic       divReq      [MULDIV_ISSUE_WIDTH];
    logic       divReserved [MULDIV_ISSUE_WIDTH];
    logic       divBusy     [MULDIV_ISSUE_WIDTH];
    logic       divFree     [MULDIV_ISSUE_WIDTH];

    logic divAcquire[MULDIV_ISSUE_WIDTH];
    OpDst acquireOpDst[MULDIV_ISSUE_WIDTH];
    OpDst divPendingDst[MULDIV_ISSUE_WIDTH];

    ActiveListIndexPath acquireActiveListPtr[MULDIV_ISSUE_WIDTH];

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
        divReq,
        divAcquire,
        acquireOpDst,
        acquireActiveListPtr,
    output
        mulDataOut,
        divPendingDst,
        divBusy,
        divReserved,
        divFree
    );

    modport ComplexIntegerIssueStage(
    input
        dummy
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        ,
    output
        divAcquire,
        acquireActiveListPtr,
        acquireOpDst
`endif
    );

    modport ComplexIntegerExecutionStage(
    input
        mulDataOut,
        divBusy,
        divReserved,
        divFree
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        ,
    output
        stall,
        dataInA,
        dataInB,
        mulGetUpper,
        mulCode,
        divCode,
        divReq
`endif
    );

    modport MemoryIssueStage(
    input
        dummy
`ifdef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        ,
    output
        divAcquire,
        acquireActiveListPtr,
        acquireOpDst
`endif
    );

    modport MemoryExecutionStage(
    input
        divBusy,
        divReserved,
        divFree
`ifdef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        ,
    output
        stall,
        dataInA,
        dataInB,
        mulGetUpper,
        mulCode,
        divCode,
        divReq
`endif
    );

    modport MemoryAccessStage(input mulDataOut);

    modport Scheduler(
    input
        divFree
    );

    modport ReplayQueue(
    input
        divPendingDst,
        divBusy
    );

endinterface
