// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- PreDecodeStageIF
//

import BasicTypes::*;
import PipelineTypes::*;
import MicroOpTypes::*;

interface PreDecodeStageIF(input logic clk, rst);

    // Pipeline registers 
    DecodeStageRegPath nextStage[DECODE_WIDTH];
    
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
    
endinterface : PreDecodeStageIF



