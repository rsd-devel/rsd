// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- Vector Bypass network
//

import BasicTypes::*;
import PipelineTypes::*;
import BypassTypes::*;

typedef struct packed // struct VectorBypassOperand
{
    PVecDataPath value;
} VectorBypassOperand;


module VectorBypassStage(
    input  logic clk, rst,
    input  PipelineControll ctrl,
    input  VectorBypassOperand in,
    output VectorBypassOperand out
);
    VectorBypassOperand body;

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

`ifdef RSD_ENABLE_VECTOR_PATH

module VectorBypassNetwork(
    BypassNetworkIF.VectorBypassNetwork port,
    ControllerIF.VectorBypassNetwork ctrl
);
    function automatic PVecDataPath SelectData(
    input
        BypassSelect sel,
        VectorBypassOperand memMA [ LOAD_ISSUE_WIDTH ],
        VectorBypassOperand memWB [ LOAD_ISSUE_WIDTH ]
    );
        if( sel.stg == BYPASS_STAGE_MEM_MA )
            return memMA[sel.lane.memLane].value;
        else   if( sel.stg == BYPASS_STAGE_MEM_WB )
            return memWB[sel.lane.memLane].value;
        else
            return '0;

    endfunction


    VectorBypassOperand memDst [ LOAD_ISSUE_WIDTH ];
    VectorBypassOperand memMA  [ LOAD_ISSUE_WIDTH ];
    VectorBypassOperand memWB  [ LOAD_ISSUE_WIDTH ];

    generate
        for ( genvar i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin : stgMem
            VectorBypassStage stgMemMA( port.clk, port.rst, ctrl.backEnd, memDst[i], memMA[i] );
            VectorBypassStage stgMemWB( port.clk, port.rst, ctrl.backEnd, memMA[i],  memWB[i] );
        end
    endgenerate

    always_comb begin

        for ( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
            port.complexSrcVecDataOutA[i] = SelectData( port.complexCtrlIn[i].rA, memMA, memWB );
            port.complexSrcVecDataOutB[i] = SelectData( port.complexCtrlIn[i].rB, memMA, memWB );
        end

        for ( int i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin
            memDst[i].value = port.memDstVecDataOut[i];
        end

        for ( int i = 0; i < STORE_ISSUE_WIDTH; i++ ) begin
            port.memSrcVecDataOutB[i] = SelectData( port.memCtrlIn[(i+STORE_ISSUE_LANE_BEGIN)].rB, memMA, memWB );
        end
    end
endmodule : VectorBypassNetwork

`endif