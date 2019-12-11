// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- MemoryExecutionStageIF
//

import BasicTypes::*;
import BypassTypes::*;
import OpFormatTypes::*;
import PipelineTypes::*;


interface MemoryExecutionStageIF( input logic clk, rst );

    // Pipeline register
    MemoryTagAccessStageRegPath nextStage[MEM_ISSUE_WIDTH];
    
    
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
endinterface : MemoryExecutionStageIF




