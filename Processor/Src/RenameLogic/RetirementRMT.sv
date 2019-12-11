// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Register Map Table
//

import BasicTypes::*;
import RenameLogicTypes::*;


module RetirementRMT(RenameLogicIF.RetirementRMT port);

    //
    // --- RMT for general registers
    //
    logic we [ COMMIT_WIDTH ];
    LRegNumPath writeLogRegNum[ COMMIT_WIDTH ];
    logic [ RMT_ENTRY_BIT_SIZE-1:0 ] writePhyRegNum[ COMMIT_WIDTH ];

    LRegNumPath rstWriteLogRegNum[ COMMIT_WIDTH ];
    logic [ RMT_ENTRY_BIT_SIZE-1:0 ] rstWritePhyRegNum[ COMMIT_WIDTH ];
    
    LRegNumPath readLogRegNum[ RENAME_WIDTH ];
    logic [ RMT_ENTRY_BIT_SIZE-1:0 ] readPhyRegNum[ RENAME_WIDTH ];
    
    DistributedMultiPortRAM #( 
        .ENTRY_NUM( RMT_ENTRY_NUM ),
        .ENTRY_BIT_SIZE( RMT_ENTRY_BIT_SIZE ),
        .READ_NUM( RENAME_WIDTH ),
        .WRITE_NUM( COMMIT_WIDTH )
    ) regRMT ( 
        .clk( port.clk ),
        .we( we ),
        .wa( writeLogRegNum ),
        .wv( writePhyRegNum ),
        .ra( readLogRegNum ),
        .rv( readPhyRegNum )
    );
    
    always_comb begin
        for (int i = 0; i < COMMIT_WIDTH; i++) begin

            // Write data
            if ( !port.rst ) begin
                writeLogRegNum[i] = port.retRMT_WriteReg_LogRegNum[i];
                writePhyRegNum[i] = port.retRMT_WriteReg_PhyRegNum[i].regNum;
                we[i] = port.retRMT_WriteReg[i];
                
                // Write to Write Bypass
                for (int j = 0; j < i; j++) begin
                    if (we[i] && writeLogRegNum[i] == writeLogRegNum[j])
                        we[j] = FALSE;
                end
            end
            else begin
                // Reset RMT
                writeLogRegNum[i] = rstWriteLogRegNum[i];
                writePhyRegNum[i] = rstWritePhyRegNum[i];
                we[i] = (i == 0 ? TRUE : FALSE);
            end
        end
            
        // Read data
        for (int i = 0; i < RENAME_WIDTH; i++) begin
            readLogRegNum[i] = port.retRMT_ReadReg_LogRegNum[i];
            port.retRMT_ReadReg_PhyRegNum[i].regNum = readPhyRegNum[i];
`ifdef RSD_ENABLE_VECTOR_PATH
            port.retRMT_ReadReg_PhyRegNum[i].isVector
                = port.retRMT_ReadReg_LogRegNum[i].isVector;
`endif
            // Retirement RMT is used for recovery, thus it does not require a
            // bypass logic.
        end
    end
    
    // - Initialization logic
    always_ff @( posedge port.clk ) begin
        for (int i = 0; i < COMMIT_WIDTH; i++) begin
            if (port.rstStart)
                rstWriteLogRegNum[i] <= 0;
            else
                rstWriteLogRegNum[i] <= rstWriteLogRegNum[i] + 1;
        end
    end
    
    // フリーリストには0からREG_FREE_LIST_ENTRY_NUM-1が入っているので、
    // RMTの初期値はREG_FREE_LIST_ENTRY_NUM以上の値を使う
    always_comb begin
        for (int i = 0; i < COMMIT_WIDTH; i++) begin
`ifdef RSD_ENABLE_VECTOR_PATH
            if ( !rstWriteLogRegNum[i].isVector )
                rstWritePhyRegNum[i] =
                    rstWriteLogRegNum[i].regNum + SCALAR_FREE_LIST_ENTRY_NUM;
            else
                rstWritePhyRegNum[i] =
                    rstWriteLogRegNum[i].regNum + VECTOR_FREE_LIST_ENTRY_NUM;
`else
            rstWritePhyRegNum[i] =
                rstWriteLogRegNum[i].regNum + SCALAR_FREE_LIST_ENTRY_NUM;
`endif
        end
    end   
    
endmodule : RetirementRMT


