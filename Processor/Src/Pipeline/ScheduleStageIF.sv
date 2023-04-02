// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- DispatchStageIF
//

import BasicTypes::*;
import PipelineTypes::*;


interface ScheduleStageIF( input logic clk, rst );
    
    // Pipeline register
    IssueStageRegPath intNextStage     [ INT_ISSUE_WIDTH ];
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
    IssueStageRegPath complexNextStage [ COMPLEX_ISSUE_WIDTH ];
`endif
    IssueStageRegPath memNextStage     [ MEM_ISSUE_WIDTH ];
`ifdef RSD_MARCH_FP_PIPE
    IssueStageRegPath fpNextStage     [ FP_ISSUE_WIDTH ];
`endif
    
    modport ThisStage(
    input
        clk,
        rst,
    output
        intNextStage,
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        complexNextStage,
`endif
        memNextStage
`ifdef RSD_MARCH_FP_PIPE
        ,
        fpNextStage
`endif
    );
    
    modport IntNextStage(
    input
        intNextStage
    );

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
    modport ComplexNextStage(
    input
        complexNextStage
    );
`endif

    modport MemNextStage(
    input
        memNextStage
    );

`ifdef RSD_MARCH_FP_PIPE
    modport FPNextStage(
    input
        fpNextStage
    );
`endif

endinterface : ScheduleStageIF




