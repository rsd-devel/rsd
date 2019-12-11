// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- MemoryTagAccessStageIF
//

import BasicTypes::*;
import PipelineTypes::*;


interface MemoryTagAccessStageIF(input logic clk, rst);

    // Pipeline register
    MemoryAccessStageRegPath nextStage[MEM_ISSUE_WIDTH];
    
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

endinterface : MemoryTagAccessStageIF




