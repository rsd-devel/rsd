// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- IntegerIssueStageIF
//

import BasicTypes::*;
import PipelineTypes::*;


interface IntegerIssueStageIF( input logic clk, rst );
    
    // Pipeline register
    IntegerRegisterReadStageRegPath nextStage [ INT_ISSUE_WIDTH ];
    
    
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

endinterface : IntegerIssueStageIF




