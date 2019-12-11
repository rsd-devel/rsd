// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


import BasicTypes::*;
import BypassTypes::*;
import PipelineTypes::*;


interface IntegerRegisterReadStageIF( input logic clk, rst );
    
    // Pipeline register
    IntegerExecutionStageRegPath nextStage [ INT_ISSUE_WIDTH ];

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


endinterface : IntegerRegisterReadStageIF




