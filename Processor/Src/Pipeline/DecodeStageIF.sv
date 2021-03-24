// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- FetchPipe
//

import BasicTypes::*;
import PipelineTypes::*;
import MicroOpTypes::*;
import FetchUnitTypes::*;

interface DecodeStageIF( input logic clk, rst );

    // Pipeline registers 
    RenameStageRegPath nextStage[ DECODE_WIDTH ];
    logic nextFlush;
    AddrPath nextRecoveredPC;
    BranchGlobalHistoryPath nextRecoveredBrHistory;
    
    modport ThisStage(
    input 
        clk, 
        rst,
    output 
        nextStage,
        nextFlush,
        nextRecoveredPC,
        nextRecoveredBrHistory
    );
    
    modport NextStage(
    input
        nextStage,
        nextFlush,
        nextRecoveredPC,
        nextRecoveredBrHistory
    );
    
endinterface : DecodeStageIF



