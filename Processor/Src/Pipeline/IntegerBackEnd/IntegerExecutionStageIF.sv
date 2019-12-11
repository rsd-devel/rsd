// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- IntegerExecutionStageIF
//

import BasicTypes::*;
import BypassTypes::*;
import OpFormatTypes::*;
import PipelineTypes::*;


interface IntegerExecutionStageIF( input logic clk, rst );

    // Pipeline register
    IntegerRegisterWriteStageRegPath nextStage [ INT_ISSUE_WIDTH ];
    
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
endinterface : IntegerExecutionStageIF




