// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- RenameStageIF
// The interface of a rename stage.
//

import BasicTypes::*;
import MemoryMapTypes::*;
import PipelineTypes::*;


interface RenameStageIF( input logic clk, rst, rstStart );
    
    // Paths to the pipeline registers of a next stage.
    DispatchStageRegPath nextStage [ RENAME_WIDTH ];

    PC_Path pc [ RENAME_WIDTH ];
    logic memDependencyPred [ RENAME_WIDTH ];

    modport ThisStage(
    input
        clk,
        rst,
    output
        nextStage,
        pc
    );

    modport NextStage(
    input
        nextStage,
        memDependencyPred
    );

    modport MemoryDependencyPredictor(
    input
        clk,
        rst,
        rstStart,
        pc,
    output
        memDependencyPred
    );


endinterface : RenameStageIF




