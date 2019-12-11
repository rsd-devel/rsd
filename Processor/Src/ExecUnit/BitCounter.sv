// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Bit counter unit (Process CLZ instruction)
//

import BasicTypes::*;
import OpFormatTypes::*;

// ビット・カウンタ
// データの上位から0が連続しているビットの数を出力
module BitCounter(
input
    DataPath fuOpA_In,
output
    DataPath dataOut
);
    DataPath count;
    
    always_comb begin
        for ( count = 0; count < DATA_WIDTH; count++ ) begin
            if ( fuOpA_In[ DATA_WIDTH - count - 1 ] == TRUE )
                break;
        end
        dataOut = count;
    end

endmodule : BitCounter

// パイプライン化されたビット・カウンタ
// PIPELINE_DEPTHは2以上でなければならない
module PipelinedBitCounter#( 
    parameter PIPELINE_DEPTH = 3
)(
input
    clk, rst, stall,
    DataPath fuOpA_In,
output
    DataPath dataOut
);
    DataPath pipeReg[ PIPELINE_DEPTH-1 ]; // synthesis syn_pipeline = 1
    DataPath count;
    
    always_comb begin
        for ( count = 0; count < DATA_WIDTH; count++ ) begin
            if ( fuOpA_In[ DATA_WIDTH - count - 1 ] == TRUE )
                break;
        end
        dataOut = pipeReg[ PIPELINE_DEPTH-2 ];
    end

    always_ff @(posedge clk) begin
        if ( rst ) begin
            for ( int i = 0; i < PIPELINE_DEPTH-1; i++)
                pipeReg[i] <= '0;
        end
        else if ( stall ) begin
            for ( int i = 0; i < PIPELINE_DEPTH-1; i++)
                pipeReg[i] <= pipeReg[i];
        end
        else begin
            pipeReg[0] <= count;
            for ( int i = 1; i < PIPELINE_DEPTH-1; i++)
                pipeReg[i] <= pipeReg[i-1];
        end
    end

endmodule : PipelinedBitCounter
