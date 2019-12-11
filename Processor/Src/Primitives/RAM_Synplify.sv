// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- RAM implementation.
//


//
// -- Block RAM configured for READ_FIRST mode.
// 
// You can get a read value 1-cycle after you set a read address.
// When you write and read simultaneously, a read value becomes
// the written value .
//

// Simple Dual Port RAM ( 1-read / 1-write )
module BlockDualPortRAM #( 
    parameter ENTRY_NUM = 128, 
    parameter ENTRY_BIT_SIZE = 64
)( 
    input logic clk,
    input logic we,
    input logic [$clog2(ENTRY_NUM)-1: 0] wa,
    input logic [ENTRY_BIT_SIZE-1: 0] wv,
    input logic [$clog2(ENTRY_NUM)-1: 0] ra,
    output logic [ENTRY_BIT_SIZE-1: 0] rv
);
    parameter INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    typedef logic [INDEX_BIT_SIZE-1: 0] Address;
    typedef logic [ENTRY_BIT_SIZE-1: 0] Value;
    
    Value array[ENTRY_NUM];   // synthesis syn_ramstyle = "block_ram"
    
    always_ff @(posedge clk) begin
        rv <= array[ra];
        if(we) 
            array[wa] <= wv;
    end

endmodule : BlockDualPortRAM


// True Dual Port RAM ( 2-read/write )
module BlockTrueDualPortRAM #( 
    parameter ENTRY_NUM = 128, 
    parameter ENTRY_BIT_SIZE = 1,
    parameter PORT_NUM  = 2 // Do NOT change this parameter to synthesize True Dual Port RAM
)( 
    input logic clk,
    input logic we[PORT_NUM],
    input logic [$clog2(ENTRY_NUM)-1: 0] rwa[PORT_NUM],
    input logic [ENTRY_BIT_SIZE-1: 0] wv[PORT_NUM],
    output logic [ENTRY_BIT_SIZE-1: 0] rv[PORT_NUM]
);
    parameter INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    typedef logic [INDEX_BIT_SIZE-1: 0] Address;
    typedef logic [ENTRY_BIT_SIZE-1: 0] Value;
    
    Value array[ENTRY_NUM];   // synthesis syn_ramstyle = "block_ram"
    
    
    // generate を使って下記のように生成しないと，Synplify が同じアドレスへの
    // 書き込みを検出する回路を生成してしまう．この回路は本来動作に影響しないが，
    // Synplify のバグで壊れた回路が生成されるので，正常動作しなくなる．
    generate
        for (genvar i = 0; i < PORT_NUM; i++) begin
            always_ff @(posedge clk) begin
                rv[i] <= array[ rwa[i] ];
                if(we[i]) 
                    array[ rwa[i] ] <= wv[i];
            end
        end
    endgenerate

    generate
        for (genvar j = 0; j < PORT_NUM; j++) begin
            for (genvar i = 0; i < PORT_NUM; i++) begin
                `RSD_ASSERT_CLK_FMT(
                    clk,
                    !(we[i] && we[j] && rwa[i] == rwa[j] && i != j),
                    ("Multiple ports(%x,%x) write to the same entry.", i, j)
                );
            end
        end
    endgenerate
endmodule : BlockTrueDualPortRAM


module BlockMultiPortRAM #( 
    parameter ENTRY_NUM = 16, 
    parameter ENTRY_BIT_SIZE = 8, 
    parameter READ_NUM  = 2,
    parameter WRITE_NUM = 2
)( 
    input logic clk,
    input logic we[WRITE_NUM],
    input logic [$clog2(ENTRY_NUM)-1: 0] wa[WRITE_NUM],
    input logic [ENTRY_BIT_SIZE-1: 0] wv[WRITE_NUM],
    input logic [$clog2(ENTRY_NUM)-1: 0] ra[READ_NUM],
    output logic [ENTRY_BIT_SIZE-1: 0] rv[READ_NUM]
);
    parameter INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    typedef logic [INDEX_BIT_SIZE-1: 0] Address;
    typedef logic [ENTRY_BIT_SIZE-1: 0] Value;

    parameter WRITE_NUM_BIT_SIZE = $clog2( WRITE_NUM );
    typedef logic [WRITE_NUM_BIT_SIZE-1: 0] Select;

    Select select [1 << INDEX_BIT_SIZE];
    Value rvBank [READ_NUM][WRITE_NUM];
    
    // Block RAM の読み出しは1サイクル遅れる
    // select 用にレジスタに置く
    Address raReg[READ_NUM];

    always_ff @(posedge clk) begin
        raReg <= ra;
    end
    
    // generate で生成すると，書き込み調停用の回路が作られない
    generate 
    
        // read/write 用に必要なだけデュプリケート
        for (genvar j = 0; j < WRITE_NUM; j++) begin
            for (genvar i = 0; i < READ_NUM; i++) begin
                BlockDualPortRAM#(ENTRY_NUM, ENTRY_BIT_SIZE)
                    rBank(clk, we[j], wa[j], wv[j], ra[i], rvBank[i][j]);
            end
        end

        for (genvar i = 0; i < READ_NUM; i++) begin
            assign rv[i] = rvBank[i][select[raReg[i]]];
        end
        
        for (genvar j = 0; j < WRITE_NUM; j++) begin
            always_ff @(posedge clk) begin
                if(we[j])
                    select[ wa[j] ] <= j;
            end
        end
        
    endgenerate
    
    // For Debug
    `ifndef RSD_SYNTHESIS
        Value debugValue[ENTRY_NUM];
        always_ff @(posedge clk) begin
            for (int i = 0; i < WRITE_NUM; i++) begin
                if(we[i])
                    debugValue[ wa[i] ] <= wv[i];
            end
        end
    `endif
    
endmodule : BlockMultiPortRAM


//
// 電源投入時に初期化されるBlockRAM
// リセット時には初期化は行われない
//
module InitializedBlockRAM #( 
    parameter ENTRY_NUM = 128, 
    parameter ENTRY_BIT_SIZE = 64,
    parameter INIT_HEX_FILE = "code.hex"
)( 
    input logic clk,
    input logic we,
    input logic [$clog2(ENTRY_NUM)-1: 0] wa,
    input logic [ENTRY_BIT_SIZE-1: 0] wv,
    input logic [$clog2(ENTRY_NUM)-1: 0] ra,
    output logic [ENTRY_BIT_SIZE-1: 0] rv
);
    parameter INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    typedef logic [INDEX_BIT_SIZE-1: 0] Address;
    typedef logic [ENTRY_BIT_SIZE-1: 0] Value;

    Value array[ENTRY_NUM]; // synthesis syn_ramstyle = "block_ram"
    Address raReg;

    always_ff @(posedge clk) begin
        if(we)
            array[wa] <= wv;
            
        raReg <= ra;
    end
    
    always_comb begin
        rv = array[raReg];
    end

    initial begin
        $readmemh(INIT_HEX_FILE, array);
    end

endmodule : InitializedBlockRAM

//
// Distributed RAM を使用したシングルポートRAM
// multi read/write

module DistributedSinglePortRAM #( 
    parameter ENTRY_NUM = 128, 
    parameter ENTRY_BIT_SIZE = 64
)( 
    input logic clk,
    input logic we,
    input logic [$clog2(ENTRY_NUM)-1: 0] rwa,
    input logic [ENTRY_BIT_SIZE-1: 0] wv,
    output logic [ENTRY_BIT_SIZE-1: 0] rv
);
    parameter INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    typedef logic [INDEX_BIT_SIZE-1: 0] Address;
    typedef logic [ENTRY_BIT_SIZE-1: 0] Value;

    Value array[ENTRY_NUM]; // synthesis syn_ramstyle = "select_ram"
    
    always_ff @(posedge clk) begin
        if(we)
            array[rwa] <= wv;
    end
    
    always_comb begin
        rv = array[rwa];
    end
        

endmodule : DistributedSinglePortRAM

//
// Distributed RAM を使用したマルチポートRAM
// multi read/write
//

// 1-read / 1-write
module DistributedDualPortRAM #( 
    parameter ENTRY_NUM = 128, 
    parameter ENTRY_BIT_SIZE = 64
)( 
    input logic clk,
    input logic we,
    input logic [INDEX_BIT_SIZE-1: 0] wa,
    input logic [ENTRY_BIT_SIZE-1: 0] wv,
    input logic [INDEX_BIT_SIZE-1: 0] ra,
    output logic [ENTRY_BIT_SIZE-1: 0] rv
);

    parameter INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    logic [ENTRY_BIT_SIZE-1: 0] array[ENTRY_NUM];  // synthesis syn_ramstyle = "select_ram"

    always_ff @(posedge clk) begin
        if(we)
            array[wa] <= wv;
    end
    
    always_comb begin
        rv = array[ra];
    end
        

`ifndef RSD_SYNTHESIS
    initial begin
        for (int i = 0; i < (1<<INDEX_BIT_SIZE); i++) begin
            for (int j = 0; j < ENTRY_BIT_SIZE; j++) begin
                array[i][j] = 0;
            end
        end
    end
`endif

endmodule : DistributedDualPortRAM


// 1-read-write / (N-1)-read ports
module DistributedSharedMultiPortRAM #( 
    parameter ENTRY_NUM = 128, 
    parameter ENTRY_BIT_SIZE = 64,
    parameter READ_NUM  = 4
)( 
    input logic clk,
    input logic we,
    input logic [$clog2(ENTRY_NUM)-1: 0 ] rwa,
    input logic [ENTRY_BIT_SIZE-1: 0 ] wv,
    input logic [$clog2(ENTRY_NUM)-1: 0 ] ra[READ_NUM-1],
    output logic [ENTRY_BIT_SIZE-1: 0 ] rv[READ_NUM]
);
    parameter INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    typedef logic [INDEX_BIT_SIZE-1: 0] Address;
    typedef logic [ENTRY_BIT_SIZE-1: 0] Value;
    
    Value array[ ENTRY_NUM ];  // synthesis syn_ramstyle = "select_ram"

    always_ff @(posedge clk) begin
        if(we)
            array[rwa] <= wv;
    end
    
    always_comb begin
        for (int i = 0; i < READ_NUM-1; i++) begin
            rv[i] = array[ ra[i] ];
        end
        rv[READ_NUM-1] = array[rwa];
    end
        
endmodule : DistributedSharedMultiPortRAM



// N-read / M-write (Live Value Table 使用)
module DistributedMultiPortRAM #( 
    parameter ENTRY_NUM = 64, 
    parameter ENTRY_BIT_SIZE = 63, 
    parameter READ_NUM = 3,
    parameter WRITE_NUM = 3
)( 
    input logic clk,
    input logic we[ WRITE_NUM ],
    input logic [$clog2(ENTRY_NUM)-1: 0] wa[WRITE_NUM],
    input logic [ENTRY_BIT_SIZE-1: 0] wv[WRITE_NUM],
    input logic [$clog2(ENTRY_NUM)-1: 0] ra[READ_NUM],
    output logic [ENTRY_BIT_SIZE-1: 0] rv[READ_NUM]
);
    parameter INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    typedef logic [INDEX_BIT_SIZE-1: 0] Address;
    typedef logic [ENTRY_BIT_SIZE-1: 0] Value;
    
    parameter WRITE_NUM_BIT_SIZE = $clog2(WRITE_NUM);
    typedef logic [WRITE_NUM_BIT_SIZE-1: 0] LiveValue;
    
    

    // generate で生成すると，書き込み調停用の回路が作られない
    generate 
        
        if (WRITE_NUM > 1) begin
            Value rvBank[READ_NUM][WRITE_NUM];
            LiveValue lvi[WRITE_NUM];
            LiveValue lvo[READ_NUM];

            NarrowDistributedMultiPortRAM #(INDEX_BIT_SIZE, WRITE_NUM_BIT_SIZE, READ_NUM, WRITE_NUM)
            //RegisterMultiPortRAM #(ENTRY_NUM, WRITE_NUM_BIT_SIZE, READ_NUM, WRITE_NUM)
                lvt(clk, we, wa, lvi, ra, lvo);

            // read/write 用に必要なだけデュプリケート
            for (genvar j = 0; j < WRITE_NUM; j++) begin
                for ( genvar i = 0; i < READ_NUM; i++) begin
                    DistributedDualPortRAM#(ENTRY_NUM, ENTRY_BIT_SIZE)
                        rBank(clk, we[j], wa[j], wv[j], ra[i], rvBank[i][j]);
                end
            end

            for (genvar i = 0; i < READ_NUM; i++) begin
                assign rv[i] = rvBank[i][ lvo[i] ];
            end
            
            for (genvar i = 0; i < WRITE_NUM; i++) begin
                assign lvi[i] = i;
            end
        end
        else begin
            // For single write port RAM.
            // read 用に必要なだけデュプリケート
            for (genvar i = 0; i < READ_NUM; i++) begin
                DistributedDualPortRAM#(ENTRY_NUM, ENTRY_BIT_SIZE)
                    rBank(clk, we[0], wa[0], wv[0], ra[i], rv[i]);
            end
        end
        
    endgenerate
    
    // For Debug
`ifndef RSD_SYNTHESIS
        Value debugValue[ 1 << INDEX_BIT_SIZE ];
        always_ff @ ( posedge clk ) begin
            for(int i = 0; i < WRITE_NUM; i++) begin
                if( we[i] )
                    debugValue[ wa[i] ] <= wv[i];
            end
        end
`endif
    
endmodule : DistributedMultiPortRAM


//
// XOR based LUT RAM.
// "Multi-ported memories for FPGAs via XOR", Laforest, Charles Eric et. al., 
// FPGA 2012
//

module NarrowDistributedMultiPortRAM #( 
    parameter INDEX_BIT_SIZE = 5, 
    parameter ENTRY_BIT_SIZE = 2, 
    parameter READ_NUM  = 8,
    parameter WRITE_NUM = 2
)( 
    input  logic clk,
    input  logic we[WRITE_NUM],
    input  logic [INDEX_BIT_SIZE-1: 0] wa[WRITE_NUM],
    input  logic [ENTRY_BIT_SIZE-1: 0] wv[WRITE_NUM],
    input  logic [INDEX_BIT_SIZE-1: 0] ra[READ_NUM],
    output logic [ENTRY_BIT_SIZE-1: 0] rv[READ_NUM]
);
    typedef logic [INDEX_BIT_SIZE-1: 0] Address;
    typedef logic [ENTRY_BIT_SIZE-1: 0] Value;
    
    parameter WRITE_NUM_BIT_SIZE = $clog2(WRITE_NUM);
    
    Value rwbWriteValue[WRITE_NUM];
    Address wbReadAddr[WRITE_NUM];
    Value wbReadValue[WRITE_NUM][WRITE_NUM];

    Address rbReadAddr[READ_NUM];
    Value rbReadValue[WRITE_NUM][READ_NUM];

    generate 
        
        // Horizontal banks: the same address and value is written.
        // Vertical banks: they are xor-ed.
        
        
        // A w-bank is a bank for feeding values to write ports of other banks.
        // wB(j,i): 
        //   wB(0,0)     wB(0,1) ... wB(0,#WN-1) 
        //   wB(1,0)     wB(1,1) ... wB(1,#WN-1) 
        //   ...
        //   wB(#WN-1,0) wB(1,1) ... wB(#WN-1,#WN-1) 
        
        for (genvar j = 0; j < WRITE_NUM; j++) begin : wj
            for (genvar i = 0; i < WRITE_NUM; i++) begin : wi
                if (j != i) begin
                    // The bank of i == j is not necessary.
                    DistributedDualPortRAM#(INDEX_BIT_SIZE, ENTRY_BIT_SIZE)
                        wBank(clk, we[j], wa[j], rwbWriteValue[j], wbReadAddr[i], wbReadValue[j][i]);
                end
            end
        end


        // A r-bank is a bank for feeding values to read ports.
        // wB(j,i): 
        //   rB(0,0)     rB(0,1) ... rB(0,#RN-1) 
        //   rB(1,0)     rB(1,1) ... rB(1,#RN-1) 
        //   ...
        //   rB(#WN-1,0) rB(1,1) ... rB(#WN-1,#RN-1) 
        
        for (genvar j = 0; j < WRITE_NUM; j++) begin : rj
            for (genvar i = 0; i < READ_NUM; i++) begin : ri
                DistributedDualPortRAM#(INDEX_BIT_SIZE, ENTRY_BIT_SIZE)
                    rBank(clk, we[j], wa[j], rwbWriteValue[j], rbReadAddr[i], rbReadValue[j][i]);
            end
        end

    endgenerate
    
    
    always_comb begin
        // Read from w-banks.
        for (int j = 0; j < WRITE_NUM; j++) begin
            wbReadAddr[j] = wa[j];
        end

        // XOR
        for (int i = 0; i < WRITE_NUM; i++) begin
            rwbWriteValue[i] = wv[i];
            for (int j = 0; j < WRITE_NUM; j++) begin
                if (i != j) begin
                    rwbWriteValue[i] ^= wbReadValue[j][i];
                end
            end
        end

        // Read from r-banks.
        for (int i = 0; i < READ_NUM; i++) begin
            rbReadAddr[i] = ra[i];
        end

        // XOR
        for (int i = 0; i < READ_NUM; i++) begin
            rv[i] = 0;
            for (int j = 0; j < WRITE_NUM; j++) begin
                rv[i] ^= rbReadValue[j][i];
            end
        end
    end
    
    generate
        for (genvar j = 0; j < WRITE_NUM; j++) begin
            for (genvar i = 0; i < WRITE_NUM; i++) begin
                `RSD_ASSERT_CLK_FMT(
                    clk,
                    !(we[i] && we[j] && wa[i] == wa[j] && i != j),
                    ("Multiple ports(%x,%x) write to the same entry.", i, j)
                );
            end
        end
    endgenerate
    
    // For Debug
`ifndef RSD_SYNTHESIS
    Value debugValue[1 << INDEX_BIT_SIZE];
    always_ff @(posedge clk) begin
        for (int i = 0; i < WRITE_NUM; i++) begin
            if (we[i])
                debugValue[ wa[i] ] <= wv[i];
        end
    end
`endif

endmodule : NarrowDistributedMultiPortRAM


//
// LUT+FF
//

module RegisterMultiPortRAM #( 
    parameter ENTRY_NUM = 64, 
    parameter ENTRY_BIT_SIZE = 2, 
    parameter READ_NUM = 8,
    parameter WRITE_NUM = 4
)( 
    input logic clk,
    input logic we[WRITE_NUM],
    input logic [$clog2(ENTRY_NUM)-1: 0] wa[WRITE_NUM],
    input logic [ENTRY_BIT_SIZE-1: 0] wv[WRITE_NUM],
    input logic [$clog2(ENTRY_NUM)-1: 0] ra[READ_NUM],
    output logic [ENTRY_BIT_SIZE-1: 0] rv[READ_NUM]
);
    parameter INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    typedef logic [INDEX_BIT_SIZE-1: 0] Address;
    typedef logic [ENTRY_BIT_SIZE-1: 0] Value;

    Value array[ENTRY_NUM];
    
    generate 
        for (genvar i = 0; i < WRITE_NUM; i++) begin
            always_ff @(posedge clk) begin
                if (we[i])
                    array[ wa[i] ] <= wv[i];
            end
        end
    endgenerate

    always_comb begin
        for (int i = 0; i < READ_NUM; i++) begin
            rv[i] = array[ ra[i] ];
        end
    end


endmodule : RegisterMultiPortRAM




//
// --- マルチバンクRAM
// wa/ra が連続アドレスである場合のみ正しく動く．
// 論理シミュレーション時はバンクコンフリクトはエラーとして出力される．
//

module DistributedMultiBankRAM #( 
    parameter ENTRY_NUM = 64, 
    parameter ENTRY_BIT_SIZE = 63, 
    parameter READ_NUM  = 4,
    parameter WRITE_NUM = 2
)( 
    input  logic clk,
    input  logic we[WRITE_NUM],
    input  logic [$clog2(ENTRY_NUM)-1: 0] wa[WRITE_NUM],
    input  logic [ENTRY_BIT_SIZE-1: 0] wv[WRITE_NUM],
    input  logic [$clog2(ENTRY_NUM)-1: 0] ra[READ_NUM],
    output logic [ENTRY_BIT_SIZE-1: 0] rv[READ_NUM]
);
    parameter INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    typedef logic [INDEX_BIT_SIZE-1: 0] Address;
    typedef logic [ENTRY_BIT_SIZE-1: 0] Value;
    
    parameter BANK_NUM_BIT_WIDTH = $clog2(READ_NUM > WRITE_NUM ? READ_NUM : WRITE_NUM);
    parameter BANK_NUM = 1 << BANK_NUM_BIT_WIDTH;
    parameter BANK_INDEX_BIT_SIZE = INDEX_BIT_SIZE - BANK_NUM_BIT_WIDTH;

    
    Address waBank[BANK_NUM];
    Address raBank[BANK_NUM];
    Value rvBank[BANK_NUM];
    Value wvBank[BANK_NUM];
    logic weBank[BANK_NUM];
    
    generate 
        for (genvar i = 0; i < BANK_NUM; i++) begin
            DistributedDualPortRAM#(1 << BANK_INDEX_BIT_SIZE, ENTRY_BIT_SIZE)
                rBank(
                    clk, 
                    weBank[i], 
                    waBank[i][INDEX_BIT_SIZE-1 : BANK_NUM_BIT_WIDTH], 
                    wvBank[i], 
                    raBank[i][INDEX_BIT_SIZE-1 : BANK_NUM_BIT_WIDTH], 
                    rvBank[i]
                );
        end
    endgenerate
    
    always_comb begin

        for (int b = 0; b < BANK_NUM; b++) begin
            weBank[b] = '0;     // It must be 0.
            waBank[b] = wa[0];  // Don't care
            wvBank[b] = wv[0];
            
            for (int i = 0; i < WRITE_NUM; i++) begin
                if (we[i] && wa[i][BANK_NUM_BIT_WIDTH-1 : 0] == b) begin
                    weBank[b] = we[i];
                    waBank[b] = wa[i];
                    wvBank[b] = wv[i];
                    break;
                end
            end
        end

        for (int b = 0; b < BANK_NUM; b++) begin
            raBank[b] = ra[0]; // Don't care
            for (int i = 0; i < READ_NUM; i++) begin
                if (ra[i][BANK_NUM_BIT_WIDTH-1 : 0] == b) begin
                    raBank[b] = ra[i];
                    break;
                end
            end
        end

        for (int i = 0; i < READ_NUM; i++) begin
            rv[i] = rvBank[0];  // Don't care
            for (int b = 0; b < BANK_NUM; b++) begin
                if (ra[i][BANK_NUM_BIT_WIDTH-1 : 0] == b) begin
                    rv[i] = rvBank[b];
                    break;
                end
            end
        end
        
    end

    generate
        for (genvar j = 0; j < WRITE_NUM; j++) begin
            for (genvar i = 0; i < WRITE_NUM; i++) begin
                `RSD_ASSERT_CLK_FMT(
                    clk,
                    !(we[i] && we[j] && wa[i][BANK_NUM_BIT_WIDTH-1 : 0] == wa[j][BANK_NUM_BIT_WIDTH-1 : 0] && i != j),
                    ("Multiple ports(%x,%x) write to the same bank.", i, j)
                );
            end
        end
        for (genvar j = 0; j < READ_NUM; j++) begin
            for (genvar i = 0; i < READ_NUM; i++) begin
                `RSD_ASSERT_CLK_FMT(
                    clk,
                    !(ra[i][BANK_NUM_BIT_WIDTH-1 : 0] == ra[j][BANK_NUM_BIT_WIDTH-1 : 0] && i != j),
                    ("Multiple ports(%x,%x) read from the same bank.", i, j)
                );
            end
        end
    endgenerate
    
`ifndef RSD_SYNTHESIS
    // For Debug
    Value debugValue[ENTRY_NUM];
    initial begin
        for (int i = 0; i < (1<<INDEX_BIT_SIZE); i++) begin
            for (int j = 0; j < ENTRY_BIT_SIZE; j++) begin
                debugValue[i][j] = 0;
            end
        end
    end

    always_ff @(posedge clk) begin
        for (int i = 0; i < WRITE_NUM; i++) begin
            if (we[i])
                debugValue[ wa[i] ] <= wv[i];
        end
    end

    generate
        for (genvar i = 0; i < READ_NUM; i++) begin
            `RSD_ASSERT_CLK_FMT(
                clk,
                debugValue[ra[i]] == rv[i],
                ("The read output of a port(%x) is incorrect.", i)
            );
        end
    endgenerate
`endif
    
    
endmodule : DistributedMultiBankRAM
