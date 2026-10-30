// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- RAM implementation.
//

`include "BasicMacros.sv"

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
    localparam INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    typedef logic [INDEX_BIT_SIZE-1: 0] Address;
    typedef logic [ENTRY_BIT_SIZE-1: 0] Value;
    
`ifdef RSD_SYNTHESIS_OPT_MICROSEMI
    Value array[ENTRY_NUM];   // synthesis syn_ramstyle = "lsram"
`else
    Value array[ENTRY_NUM];   // synthesis syn_ramstyle = "block_ram"
`endif

    always_ff @(posedge clk) begin
        rv <= array[ra];
        if(we) 
            array[wa] <= wv;
    end


    generate
        `RSD_ASSERT_CLK_FMT(
            clk,
            !(we && wa >= ENTRY_NUM),
            ("Write to the outside of the RAM array.")
        );

        `RSD_ASSERT_CLK_FMT(
            clk,
            !(ra >= ENTRY_NUM),
            ("Read from the outside of the RAM array.")
        );
    endgenerate

endmodule : BlockDualPortRAM


// True Dual Port RAM ( 2-read/write )
module BlockTrueDualPortRAM #( 
    parameter ENTRY_NUM = 16, 
    parameter ENTRY_BIT_SIZE = 1,
    parameter PORT_NUM  = 2 // Do NOT change this parameter to synthesize True Dual Port RAM
)( 
    input logic clk,
    input logic we[PORT_NUM],
    input logic [$clog2(ENTRY_NUM)-1: 0] rwa[PORT_NUM],
    input logic [ENTRY_BIT_SIZE-1: 0] wv[PORT_NUM],
    output logic [ENTRY_BIT_SIZE-1: 0] rv[PORT_NUM]
);
    localparam INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    typedef logic [INDEX_BIT_SIZE-1: 0] Address;
    typedef logic [ENTRY_BIT_SIZE-1: 0] Value;

`ifdef RSD_SYNTHESIS_OPT_MICROSEMI
    Value array[ENTRY_NUM];   // synthesis syn_ramstyle = "lsram"
`else
    Value array[ENTRY_NUM];   // synthesis syn_ramstyle = "block_ram"
`endif
    
`ifdef RSD_SYNTHESIS_DESIGN_COMPILER
    // Design Compiler does not accept the statements for Synplify
    always_ff @(posedge clk) begin
        for (int i = 0; i < PORT_NUM; i++) begin
            rv[i] <= array[ rwa[i] ];
            if(we[i]) 
                array[ rwa[i] ] <= wv[i];
        end
    end
`else
    // These statements are for Synplify.
    // The following circuit must be written in a *generate* clause.
    // This is because Synplify generates a circuit that detects writing to the same address if *generate* clause is not used. 
    // This circuit does not affect the operation, but a broken circuit is generated due to a bug of Synplify.
    generate
        for (genvar i = 0; i < PORT_NUM; i++) begin
            always_ff @(posedge clk) begin
                rv[i] <= array[ rwa[i] ];
                if(we[i]) 
                    array[ rwa[i] ] <= wv[i];
            end
        end
    endgenerate
`endif

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

        for (genvar i = 0; i < PORT_NUM; i++) begin
            `RSD_ASSERT_CLK_FMT(
                clk,
                !(rwa[i] >= ENTRY_NUM),
                ("Port (%x) read from or write to the outside of the RAM array.", i)
            );
        end
    endgenerate

endmodule : BlockTrueDualPortRAM


//
// BlockRAM initialized at power-on
// Initialization is NOT performed at reset
// Used by the internal main-memory model in RTL and post-synthesis tests.
// Normal ZedBoard builds use external AXI memory (RSD_USE_EXTERNAL_MEMORY).
// Post-synthesis tests synthesize this RAM too, including its HEX initialization.
//
module InitializedBlockRAM #( 
    parameter ENTRY_NUM = 128, 
    parameter ENTRY_BIT_SIZE = 64,
    parameter INIT_HEX_FILE = ""
)( 
    input logic clk,
    input logic we,
    input logic [$clog2(ENTRY_NUM)-1: 0] wa,
    input logic [ENTRY_BIT_SIZE-1: 0] wv,
    input logic [$clog2(ENTRY_NUM)-1: 0] ra,
    output logic [ENTRY_BIT_SIZE-1: 0] rv
);

`ifdef RSD_SYNTHESIS
    // Prevent verification memory from being included in a normal synthesis build.
    `ifndef RSD_POST_SYNTHESIS
        `RSD_STATIC_ASSERT(1'b0, "InitializedBlockRAM is only for RTL and post-synthesis tests.");
    `endif
`endif

    // Match code.hex so simulation and synthesis can load the same image directly.
    // Vivado 2019.2 did not preserve initialization when a temporary HEX array
    // was copied into an access-width array during initialization.
    localparam HEX_FILE_ENTRY_BIT_SIZE = 128;
    localparam HEX_FILE_ENTRY_NUM = ENTRY_NUM * ENTRY_BIT_SIZE / HEX_FILE_ENTRY_BIT_SIZE;
    localparam WRITE_SLICE_BIT_SIZE = (ENTRY_BIT_SIZE < HEX_FILE_ENTRY_BIT_SIZE) ?
        ENTRY_BIT_SIZE : HEX_FILE_ENTRY_BIT_SIZE;
    localparam READ_BIT_SIZE = (ENTRY_BIT_SIZE > HEX_FILE_ENTRY_BIT_SIZE) ?
        ENTRY_BIT_SIZE : HEX_FILE_ENTRY_BIT_SIZE;

    typedef logic [ENTRY_BIT_SIZE-1:0] Value;
    typedef logic [HEX_FILE_ENTRY_BIT_SIZE-1:0] HexValue;
    HexValue array[HEX_FILE_ENTRY_NUM]; // synthesis syn_ramstyle = "block_ram"

    `RSD_STATIC_ASSERT(
        ENTRY_BIT_SIZE >= 8 && (ENTRY_BIT_SIZE & (ENTRY_BIT_SIZE-1)) == 0 &&
        (ENTRY_NUM * ENTRY_BIT_SIZE) % HEX_FILE_ENTRY_BIT_SIZE == 0,
        "Use a power-of-two byte width and a whole number of 128-bit HEX entries"
    );

    logic [READ_BIT_SIZE-1:0] readValue;
    logic [$clog2(ENTRY_NUM)-1:0] readAddress;
    Value writtenValue;
    logic bypassWrite;

    // Keep the RAM accesses in one process: Vivado 2019.2 loses initialization
    // when partial writes are split into separate generated processes.
    // Initialization routines also write array, so this is not an always_ff process.
    // Register the complete HEX word for BRAM inference; select its slice afterward.
    // Port addresses count ENTRY_BIT_SIZE-bit words, rather than HEX entries.
    // Wider requests work in simulation, but 256-bit requests did not infer BRAM
    // with Vivado 2019.2 or Synplify U-2023.03. Post-synthesis tests use 64 bits.
    always @(posedge clk) begin
        for (int word = 0; word < READ_BIT_SIZE / HEX_FILE_ENTRY_BIT_SIZE; word++) begin
            readValue[word*HEX_FILE_ENTRY_BIT_SIZE+:HEX_FILE_ENTRY_BIT_SIZE] <=
                array[ra*ENTRY_BIT_SIZE/HEX_FILE_ENTRY_BIT_SIZE + word];
            // Fixed slices infer write enables. Reading and rewriting the full word
            // would add a RAM read port and prevented BRAM-only inference in Synplify.
            for (int lane = 0; lane < HEX_FILE_ENTRY_BIT_SIZE / WRITE_SLICE_BIT_SIZE; lane++) begin
                if (we && (wa*ENTRY_BIT_SIZE % HEX_FILE_ENTRY_BIT_SIZE) == lane*WRITE_SLICE_BIT_SIZE)
                    array[wa*ENTRY_BIT_SIZE/HEX_FILE_ENTRY_BIT_SIZE + word]
                         [lane*WRITE_SLICE_BIT_SIZE+:WRITE_SLICE_BIT_SIZE] <=
                        wv[word*WRITE_SLICE_BIT_SIZE+:WRITE_SLICE_BIT_SIZE];
            end
        end
    end

    always @(posedge clk) begin
        readAddress <= ra;
        writtenValue <= wv;
        bypassWrite <= we && wa == ra;
    end
    // Preserve one-cycle write-first behavior independently of the inferred RAM mode.
    // Compare port addresses: writing another slice of the same HEX word must not bypass.
    assign rv = bypassWrite ? writtenValue :
                (readValue >> (readAddress*ENTRY_BIT_SIZE % HEX_FILE_ENTRY_BIT_SIZE));

    // Simulation and synthesis read the same 128-bit HEX image directly.
    initial begin
        if (INIT_HEX_FILE != "")
            $readmemh(INIT_HEX_FILE, array);
    end

`ifdef RSD_FUNCTIONAL_SIMULATION
    `ifndef RSD_POST_SYNTHESIS
    function automatic void InitializeMemory(input string fileName);
        // Sparse images leave unspecified words untouched, preserving dummy data or writes.
        $readmemh(fileName, array);
    endfunction

    function automatic void FillDummyData();
        // Keep unwritten memory deterministic; existing tests expect 0xcd bytes.
        for (int i = 0; i < HEX_FILE_ENTRY_NUM; i++)
            array[i] = {HEX_FILE_ENTRY_BIT_SIZE/8{8'hcd}};
    endfunction
    `endif
`endif

    `RSD_ASSERT_CLK_FMT(clk, !(we && wa >= ENTRY_NUM),
                        ("Write to the outside of the RAM array."));
    `RSD_ASSERT_CLK_FMT(clk, !(ra >= ENTRY_NUM),
                        ("Read from the outside of the RAM array."));
endmodule : InitializedBlockRAM


//
// Single Port RAM using Distributed RAM
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
    localparam INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
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

    generate
        `RSD_ASSERT_CLK_FMT(
            clk,
            !(we && rwa >= ENTRY_NUM),
            ("Write to the outside of the RAM array.")
        );
    endgenerate

endmodule : DistributedSinglePortRAM

//
// Multi ports RAM using Distributed RAM
// multi read/write
//

// 1-read / 1-write
module DistributedDualPortRAM #( 
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

    localparam INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    typedef logic [INDEX_BIT_SIZE-1: 0] Address;
    typedef logic [ENTRY_BIT_SIZE-1: 0] Value;
    Value array[ENTRY_NUM];  // synthesis syn_ramstyle = "select_ram"

    always_ff @(posedge clk) begin
        if(we)
            array[wa] <= wv;
    end
    
    always_comb begin
        rv = array[ra];
    end

`ifndef RSD_SYNTHESIS
    initial begin
        for (int i = 0; i < ENTRY_NUM; i++) begin
            for (int j = 0; j < ENTRY_BIT_SIZE; j++) begin
                array[i][j] = 0;
            end
        end
    end
`endif

    generate
        `RSD_ASSERT_CLK_FMT(
            clk,
            !(we && wa >= ENTRY_NUM),
            ("Write to the outside of the RAM array.")
        );
    endgenerate

endmodule : DistributedDualPortRAM

// 1-read / 1-write
module RegisterDualPortRAM #( 
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

    localparam INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    typedef logic [INDEX_BIT_SIZE-1: 0] Address;
    typedef logic [ENTRY_BIT_SIZE-1: 0] Value;
    Value array[ENTRY_NUM];   // synthesis syn_ramstyle = "registers"

    always_ff @(posedge clk) begin
        if(we)
            array[wa] <= wv;
    end
    
    always_comb begin
        rv = array[ra];
    end

`ifndef RSD_SYNTHESIS
    initial begin
        for (int i = 0; i < (ENTRY_NUM); i++) begin
            for (int j = 0; j < ENTRY_BIT_SIZE; j++) begin
                array[i][j] = 0;
            end
        end
    end
`endif

    generate
        `RSD_ASSERT_CLK_FMT(
            clk,
            !(we && wa >= ENTRY_NUM),
            ("Write to the outside of the RAM array.")
        );

        `RSD_ASSERT_CLK_FMT(
            clk,
            !(ra >= ENTRY_NUM),
            ("Read from the outside of the RAM array.")
        );
    endgenerate

endmodule : RegisterDualPortRAM


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
    localparam INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
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

    generate
        `RSD_ASSERT_CLK_FMT(
            clk,
            !(rwa >= ENTRY_NUM),
            ("Port (%x) read from or write to the outside of the RAM array.", 0)
        );

`ifndef RSD_VIVADO_SIMULATION
        for (genvar i = 0; i < READ_NUM-1; i++) begin
            `RSD_ASSERT_CLK_FMT(
                clk,
                !(ra >= ENTRY_NUM),
                ("Port (%x) read from the outside of the RAM array.", i+1)
            );
        end
`endif
    endgenerate
        
endmodule : DistributedSharedMultiPortRAM



// N-read / M-write (Use Live Value Table)
module LVT_DistributedMultiPortRAM #( 
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
    localparam INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    typedef logic [INDEX_BIT_SIZE-1: 0] Address;
    typedef logic [ENTRY_BIT_SIZE-1: 0] Value;
    
    // avoid logic[-1:0] when WRITE_NUM == 1
    localparam WRITE_NUM_BIT_SIZE = WRITE_NUM == 1 ? 1 : $clog2(WRITE_NUM);
    typedef logic [WRITE_NUM_BIT_SIZE-1: 0] LiveValue;

    // When using *generate*, a circuit for write arbitration is not created
    generate 
        
        if (WRITE_NUM > 1) begin
            Value rvBank[READ_NUM][WRITE_NUM];
            LiveValue lvi[WRITE_NUM];
            LiveValue lvo[READ_NUM];

`ifdef RSD_SYNTHESIS_OPT_MICROSEMI
            RegisterMultiPortRAM #(ENTRY_NUM, WRITE_NUM_BIT_SIZE, READ_NUM, WRITE_NUM)
                lvt(clk, we, wa, lvi, ra, lvo);
`else
            // For Xilinx
            XOR_DistributedMultiPortRAM #(ENTRY_NUM, WRITE_NUM_BIT_SIZE, READ_NUM, WRITE_NUM)
                lvt(clk, we, wa, lvi, ra, lvo);
`endif

            // Duplicate as many as needed for read/write
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
            // Duplicate as many as needed for read
            for (genvar i = 0; i < READ_NUM; i++) begin
                DistributedDualPortRAM#(ENTRY_NUM, ENTRY_BIT_SIZE)
                    rBank(clk, we[0], wa[0], wv[0], ra[i], rv[i]);
            end
        end
        
    endgenerate
    
    // For Debug
`ifndef RSD_SYNTHESIS
    Value debugValue[ ENTRY_NUM ];
    always_ff @ ( posedge clk ) begin
        for(int i = 0; i < WRITE_NUM; i++) begin
            if( we[i] )
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
    
endmodule : LVT_DistributedMultiPortRAM


//
// XOR based LUT RAM.
// "Multi-ported memories for FPGAs via XOR", Laforest, Charles Eric et. al., 
// FPGA 2012
//

module XOR_DistributedMultiPortRAM #( 
    parameter ENTRY_NUM = 32, 
    parameter ENTRY_BIT_SIZE = 2, 
    parameter READ_NUM  = 8,
    parameter WRITE_NUM = 2
)( 
    input  logic clk,
    input  logic we[WRITE_NUM],
    input  logic [$clog2(ENTRY_NUM)-1: 0] wa[WRITE_NUM],
    input  logic [ENTRY_BIT_SIZE-1: 0] wv[WRITE_NUM],
    input  logic [$clog2(ENTRY_NUM)-1: 0] ra[READ_NUM],
    output logic [ENTRY_BIT_SIZE-1: 0] rv[READ_NUM]
);
    localparam INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    typedef logic [INDEX_BIT_SIZE-1: 0] Address;
    typedef logic [ENTRY_BIT_SIZE-1: 0] Value;
    
    localparam WRITE_NUM_BIT_SIZE = $clog2(WRITE_NUM);
    
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
                    DistributedDualPortRAM#(ENTRY_NUM, ENTRY_BIT_SIZE)
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
                DistributedDualPortRAM#(ENTRY_NUM, ENTRY_BIT_SIZE)
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
    Value debugValue[ENTRY_NUM];
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

endmodule : XOR_DistributedMultiPortRAM


// N-read / M-write (use Live Value Table)
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
    localparam INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    typedef logic [INDEX_BIT_SIZE-1: 0] Address;
    typedef logic [ENTRY_BIT_SIZE-1: 0] Value;

    generate 
        if ((READ_NUM < 2 && WRITE_NUM && ENTRY_BIT_SIZE < 8) || 
            (INDEX_BIT_SIZE <= 4 && ENTRY_BIT_SIZE > 64)) begin
`ifdef RSD_SYNTHESIS_OPT_MICROSEMI
            RegisterMultiPortRAM #(ENTRY_NUM, ENTRY_BIT_SIZE, READ_NUM, WRITE_NUM)
                body(clk, we, wa, wv, ra, rv);
`else
            // For Xilinx
            XOR_DistributedMultiPortRAM #(ENTRY_NUM, ENTRY_BIT_SIZE, READ_NUM, WRITE_NUM)
                body(clk, we, wa, wv, ra, rv);
`endif
        end
        else begin
            LVT_DistributedMultiPortRAM#(ENTRY_NUM, ENTRY_BIT_SIZE, READ_NUM, WRITE_NUM)
                body(clk, we, wa, wv, ra, rv);
        end
    endgenerate

    // For Debug
`ifndef RSD_SYNTHESIS
    Value debugValue[ENTRY_NUM];
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
    
endmodule


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
    localparam INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    typedef logic [INDEX_BIT_SIZE-1: 0] Address;
    typedef logic [ENTRY_BIT_SIZE-1: 0] Value;

`ifdef RSD_SYNTHESIS_OPT_MICROSEMI
    Value array[ENTRY_NUM]; // synthesis syn_ramstyle = "registers"
`else
    Value array[ENTRY_NUM];
`endif 

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

    // For Debug
`ifndef RSD_SYNTHESIS
    Value debugValue[ENTRY_NUM];
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

endmodule : RegisterMultiPortRAM


//
// --- Distributed RAM consisting of multiple banks
// In a functional simulation, a bank conflict is detected as an error
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
    localparam INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    typedef logic [INDEX_BIT_SIZE-1: 0] Address;
    typedef logic [ENTRY_BIT_SIZE-1: 0] Value;

    localparam BANK_NUM_BIT_WIDTH = $clog2(READ_NUM > WRITE_NUM ? READ_NUM : WRITE_NUM);
    localparam BANK_NUM = 1 << BANK_NUM_BIT_WIDTH;


    generate
        if (BANK_NUM >= 2) begin
            DistributedMultiBankRAM_ForGE2Banks#(ENTRY_NUM, ENTRY_BIT_SIZE, READ_NUM, WRITE_NUM)
                rBank(clk, we, wa, wv, ra, rv);
        end
        else begin
            DistributedDualPortRAM#(ENTRY_NUM, ENTRY_BIT_SIZE)
                rBank(clk, we[0], wa[0], wv[0], ra[0], rv[0]);
        end
    endgenerate


`ifndef RSD_SYNTHESIS
    // For Debug
    Value debugValue[ ENTRY_NUM ];
    initial begin
        for (int i = 0; i < ENTRY_NUM; i++) begin
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
                debugValue[ ra[i] ] == rv[i],
                ("The read output of a port(%x) is incorrect.", i)
            );
        end
    endgenerate
`endif

endmodule : DistributedMultiBankRAM

//
// --- Distributed RAM consisting of multiple banks
// Generated in DistributedMultiBankRAM when the number of banks is 2 or more
//
module DistributedMultiBankRAM_ForGE2Banks #( 
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
    localparam INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    typedef logic [INDEX_BIT_SIZE-1: 0] Address;
    typedef logic [ENTRY_BIT_SIZE-1: 0] Value;
    
    localparam BANK_NUM_BIT_WIDTH = $clog2(READ_NUM > WRITE_NUM ? READ_NUM : WRITE_NUM);
    localparam BANK_NUM = 1 << BANK_NUM_BIT_WIDTH;
    localparam BANK_INDEX_BIT_SIZE = INDEX_BIT_SIZE - BANK_NUM_BIT_WIDTH;

    
    Address waBank[BANK_NUM];
    Address raBank[BANK_NUM];
    Value rvBank[BANK_NUM];
    Value wvBank[BANK_NUM];
    logic weBank[BANK_NUM];
    
    // Raise error if the number of entries is not a multiple of 
    // the number of banks
    `RSD_STATIC_ASSERT(
        ENTRY_NUM % BANK_NUM == 0,
        "Set the number of entries a multiple of the number of banks."
    );

    generate 
        for (genvar i = 0; i < BANK_NUM; i++) begin
            if (ENTRY_BIT_SIZE < 8) begin
                RegisterDualPortRAM#(ENTRY_NUM / BANK_NUM, ENTRY_BIT_SIZE)
                    rBank(
                        clk, 
                        weBank[i], 
                        waBank[i][INDEX_BIT_SIZE-1 : BANK_NUM_BIT_WIDTH], 
                        wvBank[i], 
                        raBank[i][INDEX_BIT_SIZE-1 : BANK_NUM_BIT_WIDTH], 
                        rvBank[i]
                    );
            end
            else begin
                DistributedDualPortRAM#(ENTRY_NUM / BANK_NUM, ENTRY_BIT_SIZE)
                    rBank(
                        clk, 
                        weBank[i], 
                        waBank[i][INDEX_BIT_SIZE-1 : BANK_NUM_BIT_WIDTH], 
                        wvBank[i], 
                        raBank[i][INDEX_BIT_SIZE-1 : BANK_NUM_BIT_WIDTH], 
                        rvBank[i]
                    );
            end
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
    
endmodule : DistributedMultiBankRAM_ForGE2Banks


//
// --- Block RAM consisting of multiple banks
// In a functional simulation, a bank conflict is detected as an error
//
module BlockMultiBankRAM #(
    parameter ENTRY_NUM = 64, 
    parameter ENTRY_BIT_SIZE = 63, 
    parameter READ_NUM  = 2,
    parameter WRITE_NUM = 2
)( 
    input  logic clk,
    input  logic we[WRITE_NUM],
    input  logic [$clog2(ENTRY_NUM)-1: 0] wa[WRITE_NUM],
    input  logic [ENTRY_BIT_SIZE-1: 0] wv[WRITE_NUM],
    input  logic [$clog2(ENTRY_NUM)-1: 0] ra[READ_NUM],
    output logic [ENTRY_BIT_SIZE-1: 0] rv[READ_NUM]
);
    
    localparam INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    typedef logic [INDEX_BIT_SIZE-1: 0] Address;
    typedef logic [ENTRY_BIT_SIZE-1: 0] Value;

    localparam BANK_NUM_BIT_WIDTH = $clog2(READ_NUM > WRITE_NUM ? READ_NUM : WRITE_NUM);
    localparam BANK_NUM = 1 << BANK_NUM_BIT_WIDTH;

    generate 
        if (BANK_NUM >= 2) begin
            BlockMultiBankRAM_Body#(ENTRY_NUM, ENTRY_BIT_SIZE, READ_NUM, WRITE_NUM)
                rBank(clk, we, wa, wv, ra, rv);
        end
        else begin
            BlockDualPortRAM#(ENTRY_NUM, ENTRY_BIT_SIZE)
                rBank(clk, we[0], wa[0], wv[0], ra[0], rv[0]);
        end
    endgenerate

`ifndef RSD_SYNTHESIS
    // For Debug
    Value debugValue[ ENTRY_NUM ];
    initial begin
        for (int i = 0; i < ENTRY_NUM; i++) begin
            for (int j = 0; j < ENTRY_BIT_SIZE; j++) begin
                debugValue[i][j] = 0;
            end
        end
    end

    Value rvReg[READ_NUM];
    always_ff @(posedge clk) begin
        for (int i = 0; i < READ_NUM; i++) begin
            rvReg[i] <= debugValue[ ra[i] ];
        end
        for (int i = 0; i < WRITE_NUM; i++) begin
            if (we[i])
                debugValue[ wa[i] ] <= wv[i];
        end

    end

    generate
        for (genvar i = 0; i < READ_NUM; i++) begin
            `RSD_ASSERT_CLK_FMT(
                clk,
                rvReg[i] == rv[i],
                ("The read output of a port(%x) is incorrect", i)
            );
        end
    endgenerate
`endif

endmodule : BlockMultiBankRAM


//
// --- Block RAM consisting of multiple banks
// Generated in BlockMultiBankRAM when the number of banks is 2 or more
//
module BlockMultiBankRAM_Body #(
    parameter ENTRY_NUM = 64, 
    parameter ENTRY_BIT_SIZE = 63, 
    parameter READ_NUM  = 2,
    parameter WRITE_NUM = 2
)( 
    input  logic clk,
    input  logic we[WRITE_NUM],
    input  logic [$clog2(ENTRY_NUM)-1: 0] wa[WRITE_NUM],
    input  logic [ENTRY_BIT_SIZE-1: 0] wv[WRITE_NUM],
    input  logic [$clog2(ENTRY_NUM)-1: 0] ra[READ_NUM],
    output logic [ENTRY_BIT_SIZE-1: 0] rv[READ_NUM]
);
    localparam INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    typedef logic [INDEX_BIT_SIZE-1: 0] Address;
    typedef logic [ENTRY_BIT_SIZE-1: 0] Value;
    
    localparam BANK_NUM_BIT_WIDTH = $clog2(READ_NUM > WRITE_NUM ? READ_NUM : WRITE_NUM);
    localparam BANK_NUM = 1 << BANK_NUM_BIT_WIDTH;
    localparam BANK_INDEX_BIT_SIZE = INDEX_BIT_SIZE - BANK_NUM_BIT_WIDTH;

    
    Address waBank[BANK_NUM];
    Address raBank[BANK_NUM];
    Value rvBank[BANK_NUM];
    Value wvBank[BANK_NUM];
    logic weBank[BANK_NUM];

    Address raReg[BANK_NUM];

    // Raise error if the number of entries is not a multiple of 
    // the number of banks
    `RSD_STATIC_ASSERT(
        ENTRY_NUM % BANK_NUM == 0,
        "Set the number of entries a multiple of the number of banks."
    );
    
    generate 
        for (genvar i = 0; i < BANK_NUM; i++) begin
            BlockDualPortRAM#(ENTRY_NUM/BANK_NUM, ENTRY_BIT_SIZE)
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
    
    always_ff @(posedge clk) begin
        for (int i = 0; i < BANK_NUM; i++) begin
            raReg[i] <= ra[i];
        end
    end

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
                if (raReg[i][BANK_NUM_BIT_WIDTH-1 : 0] == b) begin
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

endmodule : BlockMultiBankRAM_Body
