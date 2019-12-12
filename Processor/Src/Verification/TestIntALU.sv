// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


import MicroOpTypes::*;
import OpFormatTypes::*;
import BasicTypes::*;


module TestIntALU;

    parameter STEP = 10;
    
    integer i;
    integer index;
    integer cycle;
    logic rst;
    logic clk;
    string message;
    
    
    
    IntALU_Code aluCode;
    DataPath fuOpA_In;
    DataPath fuOpB_In;
    DataPath aluDataOut;
    
    IntALU intALU(.*);

    initial begin
        
        `define OP_TEST( code, a, b, dataOut ) \
            aluCode     = code; \
            fuOpA_In  = a; \
            fuOpB_In  = b; \
            #STEP \
            $display( "%s %08x, %08x => %08x", aluCode, fuOpA_In, fuOpB_In, aluDataOut );\
            assert( aluDataOut == dataOut );\
        
        //        code    opA               opB         dataAssert
        `OP_TEST( AC_ADD, 32'hf,            32'h1,      32'h10       );
        `OP_TEST( AC_ADD, 32'hffffffff,     32'h1,      32'h0        );
        `OP_TEST( AC_ADD, 32'hffffffff,     32'h0,      32'hffffffff );
        
        `OP_TEST( AC_SUB, 32'h00000000,     32'h1,      32'hffffffff );
        
        `OP_TEST( AC_ADD, 32'h7fffffff,     32'h0,      32'h7fffffff );
        `OP_TEST( AC_ADD, 32'h7fffffff,     32'h1,      32'h80000000 ); // Overflow
        `OP_TEST( AC_ADD, 32'h80000000,     32'h0,      32'h80000000 );
        `OP_TEST( AC_ADD, 32'h80000000,     32'hffffffff, 32'h7fffffff ); // Overflow
        `OP_TEST( AC_ADC, 32'h7fffffff,     32'h0,      32'h7fffffff );
        `OP_TEST( AC_ADC, 32'h7fffffff,     32'h0,      32'h80000000 ); // Overflow
        
        `OP_TEST( AC_SUB, 32'h80000000,     32'h0,      32'h80000000 );
        `OP_TEST( AC_SUB, 32'h80000000,     32'h1,      32'h7fffffff ); // Overflow
        `OP_TEST( AC_SUB, 32'h7fffffff,     32'h0,      32'h7fffffff );
        `OP_TEST( AC_SUB, 32'h7fffffff,     32'hffffffff, 32'h80000000 ); // Overflow
        
        $finish;
    end

endmodule

