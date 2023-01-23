// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Register file
//

import BasicTypes::*;

module RegisterFile(
    RegisterFileIF.RegisterFile port
);
    //
    // Register
    //
    parameter REG_READ_NUM = (INT_ISSUE_WIDTH + COMPLEX_ISSUE_WIDTH + MEM_ISSUE_WIDTH) * 2 + FP_ISSUE_WIDTH;
    parameter REG_WRITE_NUM = INT_ISSUE_WIDTH + COMPLEX_ISSUE_WIDTH + LOAD_ISSUE_WIDTH + FP_ISSUE_WIDTH;

    logic       regWE      [ REG_WRITE_NUM ];
    PScalarRegNumPath dstRegNum  [ REG_WRITE_NUM ];
    PRegDataPath dstRegData [ REG_WRITE_NUM ];
    PScalarRegNumPath srcRegNum  [ REG_READ_NUM ];
    PRegDataPath srcRegData [ REG_READ_NUM ];

    DistributedMultiPortRAM #(
        .ENTRY_NUM( PSCALAR_NUM ),
        .ENTRY_BIT_SIZE( $bits(PRegDataPath) ),
        .READ_NUM( REG_READ_NUM ),
        .WRITE_NUM( REG_WRITE_NUM )
    ) phyReg (
        .clk( port.clk ),
        .we( regWE ),
        .wa( dstRegNum ),
        .wv( dstRegData ),
        .ra( srcRegNum ),
        .rv( srcRegData )
    );

    // - Initialization logic
    PRegNumPath regRstIndex;
    always_ff @( posedge port.clk ) begin
        if (port.rstStart)
            regRstIndex <= 0;
        else
            regRstIndex <= regRstIndex + REG_WRITE_NUM;
    end

    always_comb begin
        for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
`ifdef RSD_ENABLE_VECTOR_PATH
            regWE     [i] = port.intDstRegWE[i] && !port.intDstRegNum[i].isVector;
`elsif RSD_ENABLE_FP_PATH
            regWE     [i] = port.intDstRegWE[i] && !port.intDstRegNum[i].isFP;
`else
            regWE     [i] = port.intDstRegWE[i];
`endif
            dstRegNum [i] = port.intDstRegNum[i].regNum;
            dstRegData[i] = port.intDstRegData[i];

            srcRegNum[i*2  ] = port.intSrcRegNumA[i].regNum;
            srcRegNum[i*2+1] = port.intSrcRegNumB[i].regNum;
            port.intSrcRegDataA[i] = srcRegData[i*2  ];
            port.intSrcRegDataB[i] = srcRegData[i*2+1];
        end
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        for ( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
`ifdef RSD_ENABLE_VECTOR_PATH
            regWE     [i+INT_ISSUE_WIDTH] = port.complexDstRegWE[i] && !port.complexDstRegNum[i].isVector;
`elsif RSD_ENABLE_FP_PATH
            regWE     [i+INT_ISSUE_WIDTH] = port.complexDstRegWE[i] && !port.complexDstRegNum[i].isFP;
`else
            regWE     [i+INT_ISSUE_WIDTH] = port.complexDstRegWE[i];
`endif
            dstRegNum [i+INT_ISSUE_WIDTH] = port.complexDstRegNum[i].regNum;
            dstRegData[i+INT_ISSUE_WIDTH] = port.complexDstRegData[i];

            srcRegNum[(i+INT_ISSUE_WIDTH)*2  ] = port.complexSrcRegNumA[i].regNum;
            srcRegNum[(i+INT_ISSUE_WIDTH)*2+1] = port.complexSrcRegNumB[i].regNum;
            port.complexSrcRegDataA[i] = srcRegData[(i+INT_ISSUE_WIDTH)*2  ];
            port.complexSrcRegDataB[i] = srcRegData[(i+INT_ISSUE_WIDTH)*2+1];
        end
`endif
        for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
            srcRegNum[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)*2  ] = port.memSrcRegNumA[i].regNum;
            srcRegNum[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)*2+1] = port.memSrcRegNumB[i].regNum;
            port.memSrcRegDataA[i] = srcRegData[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)*2  ];
`ifndef RSD_ENABLE_FP_PATH
            port.memSrcRegDataB[i] = srcRegData[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)*2+1];
`else
            port.memSrcRegDataB[i] = port.memSrcRegNumB[i].isFP ? srcFPRegData[i+FP_ISSUE_WIDTH*3] : srcRegData[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)*2+1];
`endif
        end

        for ( int i = 0; i < LOAD_ISSUE_WIDTH; i++) begin
`ifdef RSD_ENABLE_VECTOR_PATH
            regWE     [(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] = port.memDstRegWE[i] && !port.memDstRegNum[i].isVector;
`elsif RSD_ENABLE_FP_PATH
            regWE     [(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] = port.memDstRegWE[i] && !port.memDstRegNum[i].isFP;
`else
            regWE     [(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] = port.memDstRegWE[i];
`endif

            dstRegNum [(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] = port.memDstRegNum[i].regNum;
            dstRegData[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] = port.memDstRegData[i];
        end

`ifdef RSD_ENABLE_FP_PATH 
        for ( int i = 0; i < FP_ISSUE_WIDTH; i++ ) begin
            srcRegNum[i+(INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH+MEM_ISSUE_WIDTH)*2  ] = port.fpSrcRegNumA[i].regNum;
            //port.fpSrcRegDataA[i] = srcRegData[i+(INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH+MEM_ISSUE_WIDTH)*2  ];
            regWE     [(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH+LOAD_ISSUE_WIDTH)] = port.fpDstRegWE[i] && !port.fpDstRegNum[i].isFP;
            dstRegNum [(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH+LOAD_ISSUE_WIDTH)] = port.fpDstRegNum[i].regNum;
            dstRegData[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH+LOAD_ISSUE_WIDTH)] = port.fpDstRegData[i];
        end
`endif
        // 以下のリセット後の初期化処理で全てのレジスタに0x0を代入する.
        // ゼロレジスタは, 書き込み時にはDecoderでwriteフラグを落とし,
        // 読み込み時は,RMTの初期化によって割り当てられる,
        // 0x0で初期化された物理レジスタの0番エントリを実際に参照することで実現している.
        // よって, 以下の初期化処理を論理合成時も省略してはならない
        if (port.rst) begin
            for (int i = 0; i < REG_WRITE_NUM; i++) begin
                regWE     [i] = TRUE;
                dstRegNum [i] = regRstIndex + i;
                dstRegData[i].data = 'h00000000;
                dstRegData[i].valid = TRUE;
            end
        end
    end


    //
    // Vector
    //
`ifdef RSD_ENABLE_VECTOR_PATH
    parameter VEC_READ_NUM = COMPLEX_ISSUE_WIDTH * 2 + STORE_ISSUE_WIDTH;
    parameter VEC_WRITE_NUM = COMPLEX_ISSUE_WIDTH + LOAD_ISSUE_WIDTH;

    logic             vecWE      [ VEC_WRITE_NUM ];
    PVectorRegNumPath dstVecNum  [ VEC_WRITE_NUM ];
    PVecDataPath      dstVecData [ VEC_WRITE_NUM ];
    PVectorRegNumPath srcVecNum  [ VEC_READ_NUM ];
    PVecDataPath      srcVecData [ VEC_READ_NUM ];
    DistributedMultiPortRAM #(
        .ENTRY_NUM( PVECTOR_NUM ),
        .ENTRY_BIT_SIZE( $bits(PVecDataPath) ),
        .READ_NUM( VEC_READ_NUM ),
        .WRITE_NUM( VEC_WRITE_NUM )
    ) phyVec (
        .clk( port.clk ),
        .we( vecWE ),
        .wa( dstVecNum ),
        .wv( dstVecData ),
        .ra( srcVecNum ),
        .rv( srcVecData )
    );

    // - Initialization logic
    PVectorRegNumPath vecRstIndex;
    always_ff @( posedge port.clk ) begin
        if (port.rstStart)
            vecRstIndex <= 0;
        else
            vecRstIndex <= vecRstIndex + VEC_WRITE_NUM;
    end

    always_comb begin
        for ( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
            vecWE     [i] = port.complexDstRegWE[i] && port.complexDstRegNum[i].isVector;
            dstVecNum [i] = port.complexDstRegNum[i].regNum;
            dstVecData[i] = port.complexDstVecData[i];

            srcVecNum[i*2  ] = port.complexSrcRegNumA[i].regNum;
            srcVecNum[i*2+1] = port.complexSrcRegNumB[i].regNum;
            port.complexSrcVecDataA[i] = srcVecData[i*2  ];
            port.complexSrcVecDataB[i] = srcVecData[i*2+1];
        end

        for ( int i = 0; i < STORE_ISSUE_WIDTH; i++ ) begin
            srcVecNum[(i+COMPLEX_ISSUE_WIDTH)*2] = port.memSrcRegNumB[i+STORE_ISSUE_LANE_BEGIN].regNum;
            port.memSrcVecDataB[i] = srcVecData[(i+COMPLEX_ISSUE_WIDTH)*2];
        end

        for ( int i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin
            vecWE     [(i+COMPLEX_ISSUE_WIDTH)] = port.memDstRegWE[i] && port.memDstRegNum[i].isVector;
            dstVecNum [(i+COMPLEX_ISSUE_WIDTH)] = port.memDstRegNum[i].regNum;
            dstVecData[(i+COMPLEX_ISSUE_WIDTH)] = port.memDstVecData[i];
        end
        if (port.rst) begin
            for (int i = 0; i < VEC_WRITE_NUM; i++) begin
                vecWE     [i] = TRUE;
                dstVecNum [i] = vecRstIndex + i;
                dstVecData[i].data = 128'hcdcdcdcd_cdcdcdcd_cdcdcdcd_cdcdcdcd;
                dstVecData[i].valid = TRUE;
            end
        end
    end
`endif

    //
    // FP
    //
`ifdef RSD_ENABLE_FP_PATH
    parameter FP_READ_NUM = FP_ISSUE_WIDTH * 3 + MEM_ISSUE_WIDTH;
    parameter FP_WRITE_NUM = FP_ISSUE_WIDTH + LOAD_ISSUE_WIDTH;

    logic             fpRegWE      [ FP_WRITE_NUM ];
    PScalarFPRegNumPath       dstFPRegNum  [ FP_WRITE_NUM ];
    PRegDataPath      dstFPRegData [ FP_WRITE_NUM ];
    PScalarFPRegNumPath       srcFPRegNum  [ FP_READ_NUM ];
    PRegDataPath      srcFPRegData [ FP_READ_NUM ];
    DistributedMultiPortRAM #(
        .ENTRY_NUM( PSCALAR_FP_NUM ),
        .ENTRY_BIT_SIZE( $bits(PRegDataPath) ),
        .READ_NUM( FP_READ_NUM ),
        .WRITE_NUM( FP_WRITE_NUM )
    ) phyFPReg (
        .clk( port.clk ),
        .we( fpRegWE ),
        .wa( dstFPRegNum ),
        .wv( dstFPRegData ),
        .ra( srcFPRegNum ),
        .rv( srcFPRegData )
    );

    // - Initialization logic
    PRegNumPath fpRstIndex;
    always_ff @( posedge port.clk ) begin
        if (port.rstStart)
            fpRstIndex <= 0;
        else
            fpRstIndex <= fpRstIndex + FP_WRITE_NUM;
    end

    always_comb begin
        for ( int i = 0; i < FP_ISSUE_WIDTH; i++ ) begin
            fpRegWE     [i] = port.fpDstRegWE[i] && port.fpDstRegNum[i].isFP;
            dstFPRegNum [i] = port.fpDstRegNum[i].regNum;
            dstFPRegData[i] = port.fpDstRegData[i];

            srcFPRegNum[i*3  ] = port.fpSrcRegNumA[i].regNum;
            srcFPRegNum[i*3+1] = port.fpSrcRegNumB[i].regNum;
            srcFPRegNum[i*3+2] = port.fpSrcRegNumC[i].regNum;
            port.fpSrcRegDataA[i] = port.fpSrcRegNumA[i].isFP ? srcFPRegData[i*3] : srcRegData[i+(INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH+MEM_ISSUE_WIDTH)*2];
            port.fpSrcRegDataB[i] = srcFPRegData[i*3+1];
            port.fpSrcRegDataC[i] = srcFPRegData[i*3+2];
        end

        for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
            srcFPRegNum[i+FP_ISSUE_WIDTH*3] = port.memSrcRegNumB[i].regNum;
        end

        for ( int i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin
            fpRegWE     [i+FP_ISSUE_WIDTH] = port.memDstRegWE[i] && port.memDstRegNum[i].isFP;
            dstFPRegNum [i+FP_ISSUE_WIDTH] = port.memDstRegNum[i].regNum;
            dstFPRegData[i+FP_ISSUE_WIDTH] = port.memDstRegData[i];
        end
        
        if (port.rst) begin
            for (int i = 0; i < FP_WRITE_NUM; i++) begin
                fpRegWE     [i] = TRUE;
                dstFPRegNum [i] = fpRstIndex + i;
                dstFPRegData[i].data = 'h00000000;
                dstFPRegData[i].valid = TRUE;
            end
        end
    end
`endif

endmodule : RegisterFile
