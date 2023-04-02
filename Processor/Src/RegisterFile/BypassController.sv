// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


import BasicTypes::*;
import ActiveListIndexTypes::*;
import PipelineTypes::*;
import BypassTypes::*;

//
// --- Bypass controller
//
// BypassController outputs control information that controlls BypassNetwork.
// BypassController is connected to a register read stage.
//

typedef struct packed // struct BypassCtrlOperand
{
    PRegNumPath dstRegNum;
    logic writeReg;
} BypassCtrlOperand;


module BypassCtrlStage(
    input  logic clk, rst, 
    input  PipelineControll ctrl,
    input  BypassCtrlOperand in, 
    output BypassCtrlOperand out 
);
    BypassCtrlOperand body;
    
    always_ff@( posedge clk )               // synchronous rst 
    begin
        if( rst || ctrl.clear ) begin              // rst 
            body.dstRegNum <= 0;
            body.writeReg  <= FALSE;
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

module BypassController( 
    BypassNetworkIF.BypassController port,
    ControllerIF.BypassController ctrl
);

    function automatic BypassSelect SelectReg( 
    input
        PRegNumPath regNum,
        logic read,
        BypassCtrlOperand intEX [ INT_ISSUE_WIDTH ],
        BypassCtrlOperand intWB [ INT_ISSUE_WIDTH ],
        BypassCtrlOperand memMA [ LOAD_ISSUE_WIDTH ],
        BypassCtrlOperand memWB [ LOAD_ISSUE_WIDTH ]
    );
        BypassSelect ret;
        ret.valid = FALSE;
        //ret.stg = BYPASS_STAGE_DEFAULT;
        ret.stg = BYPASS_STAGE_INT_EX;
        ret.lane.intLane = 0;
        ret.lane.memLane = 0;
        // Not implemented 
        ret.lane.complexLane = 0; 
`ifdef RSD_MARCH_FP_PIPE
        ret.lane.fpLane = 0; 
`endif

        for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            if ( read && intEX[i].writeReg && regNum == intEX[i].dstRegNum ) begin
                ret.valid = TRUE;
                ret.stg = BYPASS_STAGE_INT_EX;
                ret.lane.intLane = i;
                break;
            end
            if ( read && intWB[i].writeReg && regNum == intWB[i].dstRegNum ) begin
                ret.valid = TRUE;
                ret.stg = BYPASS_STAGE_INT_WB;
                ret.lane.intLane = i;
                break;
            end
        end
        
        for ( int i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin
            if ( read && memMA[i].writeReg && regNum == memMA[i].dstRegNum ) begin
                ret.valid = TRUE;
                ret.stg = BYPASS_STAGE_MEM_MA;
                ret.lane.memLane = i;
                break;
            end
            if ( read && memWB[i].writeReg && regNum == memWB[i].dstRegNum ) begin
                ret.valid = TRUE;
                ret.stg = BYPASS_STAGE_MEM_WB;
                ret.lane.memLane = i;
                break;
            end
        end
        
        return ret;
    endfunction

    logic clk, rst;
    
    assign clk = port.clk;
    assign rst = port.rst;
    
    //
    // Back-end Pipeline Structure
    //
    // Int:     IS RR EX WB
    // Complex: IS RR EX WB
    // Mem:     IS RR EX MT MA WB
    BypassCtrlOperand intRR [ INT_ISSUE_WIDTH ];
    BypassCtrlOperand intEX [ INT_ISSUE_WIDTH ];
    BypassCtrlOperand intWB [ INT_ISSUE_WIDTH ];
    BypassCtrlOperand memRR [ LOAD_ISSUE_WIDTH ];
    BypassCtrlOperand memEX [ LOAD_ISSUE_WIDTH ];
    BypassCtrlOperand memMT [ LOAD_ISSUE_WIDTH ];
    BypassCtrlOperand memMA [ LOAD_ISSUE_WIDTH ];
    BypassCtrlOperand memWB [ LOAD_ISSUE_WIDTH ];

    for ( genvar i = 0; i < INT_ISSUE_WIDTH; i++ ) begin : stgInt
        BypassCtrlStage stgIntRR( clk, rst, ctrl.backEnd, intRR[i], intEX[i] );
        BypassCtrlStage stgIntEX( clk, rst, ctrl.backEnd, intEX[i], intWB[i] );
    end

    for ( genvar i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin : stgMem
        BypassCtrlStage stgMemRR( clk, rst, ctrl.backEnd, memRR[i], memEX[i] );
        BypassCtrlStage stgMemEX( clk, rst, ctrl.backEnd, memEX[i], memMT[i] );
        BypassCtrlStage stgMemMT( clk, rst, ctrl.backEnd, memMT[i], memMA[i] );
        BypassCtrlStage stgMemMA( clk, rst, ctrl.backEnd, memMA[i], memWB[i] );
    end
    
    BypassControll intBypassCtrl [ INT_ISSUE_WIDTH ];
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
    BypassControll complexBypassCtrl [ COMPLEX_ISSUE_WIDTH ];
`endif
    BypassControll memBypassCtrl [ MEM_ISSUE_WIDTH ];
`ifdef  RSD_MARCH_FP_PIPE
    BypassControll fpBypassCtrl [ FP_ISSUE_WIDTH ];
`endif

    always_comb begin
        for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            intRR[i].dstRegNum = port.intPhyDstRegNum[i];
            intRR[i].writeReg  = port.intWriteReg[i];

            intBypassCtrl[i].rA   = SelectReg ( port.intPhySrcRegNumA[i], port.intReadRegA[i], intEX, intWB, memMA, memWB );
            intBypassCtrl[i].rB   = SelectReg ( port.intPhySrcRegNumB[i], port.intReadRegB[i], intEX, intWB, memMA, memWB );
        end
        port.intCtrlOut = intBypassCtrl;

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        for ( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
            complexBypassCtrl[i].rA   = SelectReg ( port.complexPhySrcRegNumA[i], port.complexReadRegA[i], intEX, intWB, memMA, memWB );
            complexBypassCtrl[i].rB   = SelectReg ( port.complexPhySrcRegNumB[i], port.complexReadRegB[i], intEX, intWB, memMA, memWB );
        end
        port.complexCtrlOut = complexBypassCtrl;
`endif

        for ( int i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin
            memRR[i].dstRegNum = port.memPhyDstRegNum[i];
            memRR[i].writeReg  = port.memWriteReg[i];
        end

        for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
            memBypassCtrl[i].rA   = SelectReg ( port.memPhySrcRegNumA[i], port.memReadRegA[i], intEX, intWB, memMA, memWB );
            memBypassCtrl[i].rB   = SelectReg ( port.memPhySrcRegNumB[i], port.memReadRegB[i], intEX, intWB, memMA, memWB );
        end
        port.memCtrlOut = memBypassCtrl;

`ifdef RSD_MARCH_FP_PIPE
        for ( int i = 0; i < FP_ISSUE_WIDTH; i++ ) begin
            fpBypassCtrl[i].rA   = SelectReg ( port.fpPhySrcRegNumA[i], port.fpReadRegA[i], intEX, intWB, memMA, memWB );
            fpBypassCtrl[i].rB   = SelectReg ( port.fpPhySrcRegNumB[i], port.fpReadRegB[i], intEX, intWB, memMA, memWB );
            fpBypassCtrl[i].rC   = SelectReg ( port.fpPhySrcRegNumC[i], port.fpReadRegC[i], intEX, intWB, memMA, memWB );
        end
        port.fpCtrlOut = fpBypassCtrl;
`endif
    end

endmodule : BypassController

