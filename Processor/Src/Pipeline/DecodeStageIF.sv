// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- FetchPipe
//

import BasicTypes::*;
import FetchUnitTypes::*;
import PipelineTypes::*;
import MicroOpTypes::*;

interface DecodeStageIF( input logic clk, rst );

    // Pipeline registers 
    RenameStageRegPath nextStage[ DECODE_WIDTH ];
    FetchRedirectPath nextRedirect;

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
        nextRedirect,
        elpState
    );
    
    modport NextStage(
    input
        nextStage,
        nextRedirect
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



