// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- FetchPipe
//

import BasicTypes::*;
import PipelineTypes::*;
import MicroOpTypes::*;

interface DecodeStageIF( input logic clk, rst );

    // Pipeline registers 
    RenameStageRegPath nextStage[ DECODE_WIDTH ];
    logic nextFlush;
    AddrPath nextRecoveredPC;
    
    logic serializeNextInsn;

    modport ThisStage(
    input 
        clk, 
        rst,
        serializeNextInsn,
    output 
        nextStage,
        nextFlush,
        nextRecoveredPC
    );
    
    modport NextStage(
    input
        nextStage,
        nextFlush,
        nextRecoveredPC
    );

    modport RecoveryManager(
    output
        serializeNextInsn
    );
    
endinterface : DecodeStageIF



