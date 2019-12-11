// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- IntegerRegisterWritePipeIF
//

import BasicTypes::*;
import PipelineTypes::*;


interface IntegerRegisterWriteStageIF( input logic clk, rst );
    
    modport ThisStage(
    input
        clk,
        rst
    );

endinterface : IntegerRegisterWriteStageIF




