// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- RegisterWritePipeIF
//

import BasicTypes::*;
import PipelineTypes::*;


interface MemoryAccessStageIF( input logic clk, rst );

    // Pipeline register
    MemoryRegisterWriteStageRegPath nextStage[MEM_ISSUE_WIDTH];
    
    
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

endinterface : MemoryAccessStageIF




