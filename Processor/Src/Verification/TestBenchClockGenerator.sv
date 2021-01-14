// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


`timescale 1ns/1ps

parameter KANATA_CYCLE_DISPLACEMENT = -1;
// Kanataのクロック表示とのズレを指定する
// 例：最初の命令をメモリからL1Iに読み込んで
//     フェッチステージに入るまで4サイクルかかるため、
//     KANATA_CYCLE_DISPLACEMENTに4を指定し、ズレを矯正する

module TestBenchClockGenerator #(
    parameter STEP = 10,
    parameter INITIALIZATION_CYCLE = 8
)(
    input  logic rstOut,
    output logic clk, rst
);
    task WaitCycle ( int cycle );
        for ( int i = 0; i < cycle; i++ )
            @(posedge clk);
    endtask
    
    integer cycle;
    integer kanataCycle;

    // clk
    initial begin
        clk <= 1'b0;
        cycle <= 0;
        kanataCycle <= -KANATA_CYCLE_DISPLACEMENT;
        forever begin
            #STEP clk <= 1'b0;
            #STEP clk <= 1'b1;
            if ( rstOut == 1'b0 ) begin
                //$display( "%d cycle %d KanataCycle %tps", cycle, kanataCycle, $time );
                cycle += 1;
                kanataCycle += 1;
            end
        end
    end
    
    // rst
    initial begin
        rst <= 1'b1;
        
        // It needs a few cycles to initialize Xilinx primitives like X_FF.
        WaitCycle( INITIALIZATION_CYCLE );
        rst <= 1'b0;
    end
    
endmodule : TestBenchClockGenerator
