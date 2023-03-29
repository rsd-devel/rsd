// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


import BasicTypes::*;
import PipelineTypes::*;


interface FPRegisterReadStageIF( input logic clk, rst );

`ifdef RSD_MARCH_FP_PIPE
    // Pipeline register
    FPExecutionStageRegPath nextStage [ FP_ISSUE_WIDTH ];

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

endinterface : FPRegisterReadStageIF
