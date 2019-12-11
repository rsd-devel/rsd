// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- FetchPipeIF
//

import BasicTypes::*;
import BypassTypes::*;
import PipelineTypes::*;


interface MemoryRegisterReadStageIF( input logic clk, rst );
    
    // Pipeline register
    MemoryExecutionStageRegPath nextStage [ MEM_ISSUE_WIDTH ];
    
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

endinterface : MemoryRegisterReadStageIF




