// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- MemoryIssueStageIF
//

import BasicTypes::*;
import PipelineTypes::*;


interface MemoryIssueStageIF( input logic clk, rst );
    
    // Pipeline register
    MemoryRegisterReadStageRegPath nextStage [ MEM_ISSUE_WIDTH ];
    
    
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

endinterface : MemoryIssueStageIF




