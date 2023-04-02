// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- Bypass network
//

import BasicTypes::*;
import PipelineTypes::*;
import BypassTypes::*;

typedef struct packed // struct BypassOperand
{
    PRegDataPath value;
} BypassOperand;


module BypassStage(
    input  logic clk, rst, 
    input  PipelineControll ctrl,
    input  BypassOperand in, 
    output BypassOperand out 
);
    BypassOperand body;
    
    always_ff@( posedge clk )               // synchronous rst 
    begin
        if( rst || ctrl.clear ) begin              // rst 
            body.value.data <= 0;
            body.value.valid <= 0;
        end
        else if( ctrl.stall ) begin         // write data
            body <= body;
        end
        else begin
            body <= in;
        end
    end
    
    assign out = body;
endmodule


module BypassNetwork( 
    BypassNetworkIF.BypassNetwork port,
    ControllerIF.BypassNetwork ctrl
);
    function automatic PRegDataPath SelectData( 
    input
        BypassSelect sel,
        BypassOperand intEX [ INT_ISSUE_WIDTH ],
        BypassOperand intWB [ INT_ISSUE_WIDTH ],
        BypassOperand memMA [ LOAD_ISSUE_WIDTH ],
        BypassOperand memWB [ LOAD_ISSUE_WIDTH ]
    );
        if( sel.stg == BYPASS_STAGE_INT_EX )
            return intEX[sel.lane.intLane].value;
        else   if( sel.stg == BYPASS_STAGE_INT_WB )
            return intWB[sel.lane.intLane].value;
        else   if( sel.stg == BYPASS_STAGE_MEM_MA )
            return memMA[sel.lane.memLane].value;
        else   if( sel.stg == BYPASS_STAGE_MEM_WB )
            return memWB[sel.lane.memLane].value;
        else
            return '0;
        
    endfunction 


    BypassOperand intDst [ INT_ISSUE_WIDTH ];
    BypassOperand intEX  [ INT_ISSUE_WIDTH ];
    BypassOperand intWB  [ INT_ISSUE_WIDTH ];
    BypassOperand memDst [ LOAD_ISSUE_WIDTH ];
    BypassOperand memMA  [ LOAD_ISSUE_WIDTH ];
    BypassOperand memWB  [ LOAD_ISSUE_WIDTH ];

    generate 
        for ( genvar i = 0; i < INT_ISSUE_WIDTH; i++ ) begin : stgInt
            BypassStage stgIntEX( port.clk, port.rst, ctrl.backEnd, intDst[i], intEX[i] );
            BypassStage stgIntWB( port.clk, port.rst, ctrl.backEnd, intEX[i],  intWB[i] );
        end
        
        for ( genvar i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin : stgMem
            BypassStage stgMemMA( port.clk, port.rst, ctrl.backEnd, memDst[i], memMA[i] );
            BypassStage stgMemWB( port.clk, port.rst, ctrl.backEnd, memMA[i],  memWB[i] );
        end
    endgenerate
    
    always_comb begin

        for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            intDst[i].value = port.intDstRegDataOut[i];
            
            port.intSrcRegDataOutA[i] = SelectData( port.intCtrlIn[i].rA,   intEX, intWB, memMA, memWB );
            port.intSrcRegDataOutB[i] = SelectData( port.intCtrlIn[i].rB,   intEX, intWB, memMA, memWB );
        end
        
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        for ( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
            port.complexSrcRegDataOutA[i] = SelectData( port.complexCtrlIn[i].rA,   intEX, intWB, memMA, memWB );
            port.complexSrcRegDataOutB[i] = SelectData( port.complexCtrlIn[i].rB,   intEX, intWB, memMA, memWB );
        end
`endif
        
        for ( int i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin
            memDst[i].value = port.memDstRegDataOut[i];
        end
            
        for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
            port.memSrcRegDataOutA[i] = SelectData( port.memCtrlIn[i].rA,   intEX, intWB, memMA, memWB );
            port.memSrcRegDataOutB[i] = SelectData( port.memCtrlIn[i].rB,   intEX, intWB, memMA, memWB );
        end

`ifdef RSD_MARCH_FP_PIPE
        for ( int i = 0; i < FP_ISSUE_WIDTH; i++ ) begin
            port.fpSrcRegDataOutA[i] = SelectData( port.fpCtrlIn[i].rA,   intEX, intWB, memMA, memWB );
            port.fpSrcRegDataOutB[i] = SelectData( port.fpCtrlIn[i].rB,   intEX, intWB, memMA, memWB );
            port.fpSrcRegDataOutC[i] = SelectData( port.fpCtrlIn[i].rC,   intEX, intWB, memMA, memWB );
        end
`endif
    end

endmodule : BypassNetwork

