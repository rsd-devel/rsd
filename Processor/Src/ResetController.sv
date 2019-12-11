// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


import BasicTypes::*;

module ResetController #(
    parameter CYCLE_OF_RESET_SEQUENCE = 10000
)(
    input  logic clk, rstTrigger, locked,
    output logic rst, rstStart
);
    logic unsigned [ $clog2(CYCLE_OF_RESET_SEQUENCE):0 ] count;
    
    always_ff @(posedge clk or posedge rstTrigger) begin
        // --- rst
        // - rstTriggerがアサートされた後、
        //   CYCLE_OF_RESET_SEQUENCEサイクルの間アサートされ続ける
        if ( rstTrigger || !locked ) begin
            count <= 0;
            rst <= TRUE;
        end
        else if ( rst ) begin
            count <= count + 1;
            rst <= ( count >= CYCLE_OF_RESET_SEQUENCE ? FALSE : TRUE );
        end
        else begin
            count <= 0;
            rst <= FALSE;
        end
    end
    
    // --- rstStart
    // - リセットの開始時に1サイクルだけアサートされる信号線。
    //   RAMなどを初期化する回路は、
    //   リセット信号がアサートされている間(CYCLE_OF_RESET_SEQUENCEサイクル)駆動するが、
    //   その初期化回路もリセットを行う必要がある。
    //   初期化回路はrstがアサートされている間動くので、
    //   rstをリセット信号としては使用できない。
    //   そこで、初期化回路のリセットにはrstStartを用いる。
    always_comb begin
        rstStart = ( rst && count == 0 ) ? TRUE : FALSE;
    end
endmodule
