// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- FPIssueStageIF
//

import BasicTypes::*;
import PipelineTypes::*;


interface FPIssueStageIF( input logic clk, rst );
    
`ifdef RSD_MARCH_FP_PIPE
    // Pipeline register
    FPRegisterReadStageRegPath nextStage [ FP_ISSUE_WIDTH ];
    
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


endinterface : FPIssueStageIF