// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


import BasicTypes::*;
import PipelineTypes::*;


interface ComplexIntegerRegisterReadStageIF( input logic clk, rst );

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
    // Pipeline register
    ComplexIntegerExecutionStageRegPath nextStage [ COMPLEX_ISSUE_WIDTH ];

    modport ThisStage(
    input
        clk,
        rst,
    output
        nextStage
    );

    modport NextStage(
    input
        nextStage
    );
`endif

endinterface : ComplexIntegerRegisterReadStageIF




