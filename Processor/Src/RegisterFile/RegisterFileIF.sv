// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- RegisterFileIF
//

import BasicTypes::*;


interface RegisterFileIF( input logic clk, rst, rstStart );
    
    /* Integer Register Read */
    PRegNumPath intSrcRegNumA [ INT_ISSUE_WIDTH ];
    PRegNumPath intSrcRegNumB [ INT_ISSUE_WIDTH ];
    
    PRegDataPath intSrcRegDataA [ INT_ISSUE_WIDTH ];
    PRegDataPath intSrcRegDataB [ INT_ISSUE_WIDTH ];
    
    /* Integer Register Write */
    logic intDstRegWE  [ INT_ISSUE_WIDTH ];
    PRegNumPath intDstRegNum  [ INT_ISSUE_WIDTH ];    
    PRegDataPath intDstRegData  [ INT_ISSUE_WIDTH ];
    
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
    /* Complex Integer Register Read */
    PRegNumPath  complexSrcRegNumA [ COMPLEX_ISSUE_WIDTH ];
    PRegNumPath  complexSrcRegNumB [ COMPLEX_ISSUE_WIDTH ];
    
    PRegDataPath  complexSrcRegDataA [ COMPLEX_ISSUE_WIDTH ];
    PRegDataPath  complexSrcRegDataB [ COMPLEX_ISSUE_WIDTH ];


    /* Complex Integer Register Write */
    logic complexDstRegWE  [ COMPLEX_ISSUE_WIDTH ];

    PRegNumPath  complexDstRegNum  [ COMPLEX_ISSUE_WIDTH ];
    
    PRegDataPath  complexDstRegData  [ COMPLEX_ISSUE_WIDTH ];
`endif

    /* Memory Register Read */
    PRegNumPath memSrcRegNumA [ MEM_ISSUE_WIDTH ];
    PRegNumPath memSrcRegNumB [ MEM_ISSUE_WIDTH ];
    
    PRegDataPath  memSrcRegDataA [ MEM_ISSUE_WIDTH ];
    PRegDataPath  memSrcRegDataB [ MEM_ISSUE_WIDTH ];
    
    /* Memory Register Write */
    logic memDstRegWE  [ LOAD_ISSUE_WIDTH ];

    PRegNumPath memDstRegNum [ LOAD_ISSUE_WIDTH ];
    
    PRegDataPath memDstRegData  [ LOAD_ISSUE_WIDTH ];

`ifdef RSD_ENABLE_VECTOR_PATH
    PVecDataPath  complexSrcVecDataA [ COMPLEX_ISSUE_WIDTH ];
    PVecDataPath  complexSrcVecDataB [ COMPLEX_ISSUE_WIDTH ];
    PVecDataPath  complexDstVecData  [ COMPLEX_ISSUE_WIDTH ];
    PVecDataPath  memSrcVecDataB [ STORE_ISSUE_WIDTH ];
    PVecDataPath memDstVecData [ LOAD_ISSUE_WIDTH ];
`endif    

    modport RegisterFile(
    input 
        clk,
        rst,
        rstStart,
        intSrcRegNumA,
        intSrcRegNumB,
        memSrcRegNumA,
        memSrcRegNumB,
        intDstRegWE,
        intDstRegNum,
        intDstRegData,
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        complexSrcRegNumA,
        complexSrcRegNumB,
        complexDstRegWE,
        complexDstRegNum,
        complexDstRegData,
`endif
        memDstRegWE,
        memDstRegNum,
        memDstRegData,
`ifdef RSD_ENABLE_VECTOR_PATH
        complexDstVecData,
        memDstVecData,
`endif
    output
`ifdef RSD_ENABLE_VECTOR_PATH
        complexSrcVecDataA,
        complexSrcVecDataB,
        memSrcVecDataB,
`endif
        intSrcRegDataA,
        intSrcRegDataB,
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        complexSrcRegDataA,
        complexSrcRegDataB,
`endif
        memSrcRegDataA,
        memSrcRegDataB
    );
    
    modport IntegerRegisterReadStage(
    input
        intSrcRegDataA,
        intSrcRegDataB,
    output
        intSrcRegNumA,
        intSrcRegNumB
    );
    
    modport IntegerRegisterWriteStage(
    output
        intDstRegWE,
        intDstRegNum,
        intDstRegData
    );

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE    
    modport ComplexIntegerRegisterReadStage(
    input
        complexSrcRegDataA,
        complexSrcRegDataB,
`ifdef RSD_ENABLE_VECTOR_PATH
        complexSrcVecDataA,
        complexSrcVecDataB,
`endif
    output
        complexSrcRegNumA,
        complexSrcRegNumB
    );
    
    modport ComplexIntegerRegisterWriteStage(
    output
 `ifdef RSD_ENABLE_VECTOR_PATH
        complexDstVecData,
 `endif
        complexDstRegWE,
        complexDstRegNum,
        complexDstRegData
    );
`endif

    modport MemoryRegisterReadStage(
    input
        memSrcRegDataA,
        memSrcRegDataB,
`ifdef RSD_ENABLE_VECTOR_PATH
         memSrcVecDataB,
`endif
    output
        memSrcRegNumA,
        memSrcRegNumB
    );
    
    modport MemoryRegisterWriteStage(
    output
`ifdef RSD_ENABLE_VECTOR_PATH
        memDstVecData,
`endif
        memDstRegWE,
        memDstRegNum,
        memDstRegData
    );
    
endinterface : RegisterFileIF




