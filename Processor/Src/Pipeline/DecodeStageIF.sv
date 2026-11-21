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

    ELP_State_Type elpState;
    logic recoverELP;
    ELP_State_Type recoveredELP;
    logic setELP_OnInterrupt;
    
    logic serializeNextInsn;

    modport ThisStage(
    input 
        clk, 
        rst,
        serializeNextInsn,
        recoverELP,
        recoveredELP,
        setELP_OnInterrupt,
    output 
        nextStage,
        nextFlush,
        nextRecoveredPC,
        elpState
    );
    
    modport NextStage(
    input
        nextStage,
        nextFlush,
        nextRecoveredPC
    );

    modport InterruptController(
    input
        elpState,
    output
        setELP_OnInterrupt
    );

    modport RecoveryManager(
    output
        serializeNextInsn,
        recoverELP,
        recoveredELP
    );
    
endinterface : DecodeStageIF



