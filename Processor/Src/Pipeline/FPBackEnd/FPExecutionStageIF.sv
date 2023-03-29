// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- FPExecutionStageIF
//

import BasicTypes::*;
import PipelineTypes::*;

interface FPExecutionStageIF( input logic clk, rst );

`ifdef RSD_MARCH_FP_PIPE

    // Pipeline register
    FPRegisterWriteStageRegPath nextStage [ FP_ISSUE_WIDTH ];
    
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

endinterface : FPExecutionStageIF