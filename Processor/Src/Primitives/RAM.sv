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


module BlockMultiPortRAM #( 
    parameter ENTRY_NUM = 4, 
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
    localparam INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    typedef logic [INDEX_BIT_SIZE-1: 0] Address;
    typedef logic [ENTRY_BIT_SIZE-1: 0] Value;

    // When using *generate*, a circuit for write arbitration is not created
    generate 
        if (WRITE_NUM > 1) begin

            localparam WRITE_NUM_BIT_SIZE = $clog2( WRITE_NUM );
            typedef logic [WRITE_NUM_BIT_SIZE-1: 0] Select;

            Select select [ENTRY_NUM];
            Value rvBank [READ_NUM][WRITE_NUM];

            logic weReg[WRITE_NUM];
            Address waReg[WRITE_NUM];
            
            // Block RAM read is delayed by 1 cycle
            // use a register for select
            Address raReg[READ_NUM];

            always_ff @(posedge clk) begin
                raReg <= ra;
                weReg <= we;
                waReg <= wa;
            end
                
        
            // Duplicate as many as needed for read/write
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
                    if (weReg[j]) begin
                        select[ waReg[j] ] <= j;
                    end
                end
            end
        end
        else begin
            // For single write port RAM.
            // Duplicate as many as needed for read
            for (genvar i = 0; i < READ_NUM; i++) begin
                BlockDualPortRAM#(ENTRY_NUM, ENTRY_BIT_SIZE)
                    rBank(clk, we[0], wa[0], wv[0], ra[i], rv[i]);
            end
        end

    endgenerate

    // For Debug
    `ifndef RSD_SYNTHESIS
        Value debugValue[ENTRY_NUM];
        always_ff @(posedge clk) begin
            for (int i = 0; i < WRITE_NUM; i++) begin
                if (we[i]) begin
                    debugValue[ wa[i] ] <= wv[i];
                end
            end
        end
    `endif


    generate
        for (genvar i = 0; i < READ_NUM; i++) begin
            `RSD_ASSERT_CLK_FMT(
                clk,
                !(ra[i] >= ENTRY_NUM),
                ("Port (%x) read from the outside of the RAM array.", i)
            );
        end
        for (genvar i = 0; i < WRITE_NUM; i++) begin
            `RSD_ASSERT_CLK_FMT(
                clk,
                !(we[i] && wa[i] >= ENTRY_NUM),
                ("Port (%x) write to the outside of the RAM array.", i)
            );
        end
    endgenerate
    
endmodule : BlockMultiPortRAM


//
// BlockRAM initialized at power-on
// Initialization is NOT performed at reset
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

    localparam HEX_FILE_ENTRY_BIT_SIZE = 128;
    generate
        // Add label to if and for clause to access the module that
        // generated dynamically
        if (ENTRY_BIT_SIZE <= HEX_FILE_ENTRY_BIT_SIZE) begin : body
            InitializedBlockRAM_ForNarrowRequest #(
                .ENTRY_NUM (ENTRY_NUM),
                .ENTRY_BIT_SIZE (ENTRY_BIT_SIZE),
                .INIT_HEX_FILE (INIT_HEX_FILE)
            ) ram (
                .clk (clk),
                .we (we),
                .wa (wa),
                .wv (wv),
                .ra (ra),
                .rv (rv)
            );
        end
        else begin : body
            InitializedBlockRAM_ForWideRequest #(
                .ENTRY_NUM (ENTRY_NUM),
                .ENTRY_BIT_SIZE (ENTRY_BIT_SIZE),
                .INIT_HEX_FILE (INIT_HEX_FILE)
            ) ram (
                .clk (clk),
                .we (we),
                .wa (wa),
                .wv (wv),
                .ra (ra),
                .rv (rv)
            );
        end
    endgenerate

`ifdef RSD_FUNCTIONAL_SIMULATION
    `ifndef RSD_POST_SYNTHESIS
    // Initialize memory data with file read data
    function automatic void InitializeMemory(string INIT_HEX_FILE);
        $readmemh(INIT_HEX_FILE, body.ram.array);
    endfunction

    function automatic void FillDummyData(string DUMMY_DATA_FILE, integer DUMMY_HEX_ENTRY_NUM);
        integer entry;
        for ( entry = 0; entry < body.ram.HEX_FILE_ARRAY_ENTRY_NUM; entry += DUMMY_HEX_ENTRY_NUM ) begin
            $readmemh(
                DUMMY_DATA_FILE,
                body.ram.array,
                entry, // Begin address
                entry + DUMMY_HEX_ENTRY_NUM - 1 // End address
            );
        end
    endfunction
    `endif
`endif
    
endmodule : InitializedBlockRAM


//
// InitializedBlockRAM that supports a bandwidth of 128 bits or less
//
module InitializedBlockRAM_ForNarrowRequest #( 
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

    // Request side
    localparam INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    typedef logic [INDEX_BIT_SIZE-1: 0] Address;
    typedef logic [ENTRY_BIT_SIZE-1: 0] Value;
    localparam ENTRY_BIT_WIDTH = $clog2(ENTRY_BIT_SIZE);

    // Since the hex file is read in 128 bits units, the memory array is also 128 bits units.
    localparam HEX_FILE_ENTRY_BIT_SIZE = 128;
    // Calculates the index width when the memory array is configured in 128 bits units from the bandwidth
    // ********-------   : 128 bits memory array (Actual memory array)
    // *********------  : 64 bits memory array (Externally visible memory array)
    // (Index)   (Offset)
    // The sum of the bit width of Index and Offset is always the same
    localparam HEX_FILE_ENTRY_BIT_WIDTH = $clog2(HEX_FILE_ENTRY_BIT_SIZE);
    localparam HEX_FILE_INDEX_BIT_SIZE = INDEX_BIT_SIZE + ENTRY_BIT_WIDTH - HEX_FILE_ENTRY_BIT_WIDTH;

    // Hex file memory array
    localparam HEX_BLOCK_OFFSET_INDEX = 
        (INDEX_BIT_SIZE > HEX_FILE_INDEX_BIT_SIZE) ? INDEX_BIT_SIZE - HEX_FILE_INDEX_BIT_SIZE : 1;
    typedef logic [HEX_FILE_INDEX_BIT_SIZE-1: 0] HexArrayIndex;
    typedef logic [HEX_FILE_ENTRY_BIT_SIZE-1: 0] HexArrayValue;
    typedef logic [HEX_BLOCK_OFFSET_INDEX-1:0] HexArrayEntryOffset;

    // Raise an error if the bandwidth is greater than 128 bits
    `RSD_STATIC_ASSERT(
        HEX_FILE_ENTRY_BIT_WIDTH <= ENTRY_BIT_SIZE, 
        "Set ENTRY_BIT_SIZE less than or equal to 128 bits"
    );

    function automatic HexArrayEntryOffset GetBlockOffsetFromAddress(Address addr);
        if (INDEX_BIT_SIZE > HEX_FILE_INDEX_BIT_SIZE)  begin
            return addr[HEX_BLOCK_OFFSET_INDEX-1:0];
        end
        else begin
            return '0;
        end
    endfunction

    function automatic HexArrayIndex GetHexArrayIndexFromAddress(Address addr);
        if (INDEX_BIT_SIZE > HEX_FILE_INDEX_BIT_SIZE)  begin
            return addr[INDEX_BIT_SIZE-1:HEX_BLOCK_OFFSET_INDEX];
        end
        else begin
            return addr;
        end
    endfunction

    localparam HEX_FILE_ARRAY_ENTRY_NUM = 1 << HEX_FILE_INDEX_BIT_SIZE;
`ifdef RSD_SYNTHESIS
    HexArrayValue array[HEX_FILE_ARRAY_ENTRY_NUM]; // synthesis syn_ramstyle = "block_ram"
`else
    // This signal will be written in a test bench, so set public for verilator.
    HexArrayValue array[HEX_FILE_ARRAY_ENTRY_NUM] /*verilator public*/;
`endif

    Address raReg;
    HexArrayIndex hexFileRA;
    HexArrayValue hexFileRV;
    HexArrayEntryOffset hexFileRAOffset;

    HexArrayIndex hexFileWA;
    HexArrayValue hexFileWV;
    HexArrayEntryOffset hexFileWAOffset;
    HexArrayValue tmpWriteEntry;
    // Hack for synplify: avoid being inferred as asymmetric RAM
    HexArrayValue dummyRV/* synthesis syn_noprune=1 */;

    always_ff @(posedge clk) begin
        if (we) begin
            array[hexFileWA] <= hexFileWV;
        end
            
        raReg <= ra;
        dummyRV <= hexFileRV;
    end
    
    // Read request
    always_comb begin
        // Read from the hex file array
        hexFileRA = GetHexArrayIndexFromAddress(raReg);
        hexFileRAOffset =GetBlockOffsetFromAddress(raReg);
        hexFileRV = array[hexFileRA];
        // Reads the position specified by the offset in the 128 bits entry
        rv = hexFileRV[hexFileRAOffset*ENTRY_BIT_SIZE+:ENTRY_BIT_SIZE];
    end

    // Write request
    always_comb begin
        // Write to the hex file array
        hexFileWA = GetHexArrayIndexFromAddress(wa);
        hexFileWAOffset = GetBlockOffsetFromAddress(wa);

        // Since only the appropriate part of the 128-bit entry needs 
        // to be rewritten, read the data once
        tmpWriteEntry = array[hexFileWA];
        // Update only the appropriate parts
        tmpWriteEntry[hexFileWAOffset*ENTRY_BIT_SIZE+:ENTRY_BIT_SIZE] = wv;
        hexFileWV = tmpWriteEntry;
    end

    initial begin
        if (INIT_HEX_FILE != "") begin
            $readmemh(INIT_HEX_FILE, array);
        end
        else begin
            $display(
                "INIT_HEX_FILE in InitializedBlockRAM is not specified, so no file is read."
            );
        end
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

endmodule : InitializedBlockRAM_ForNarrowRequest


//
// InitializedBlockRAM that supports a bandwidth of 256 bits or more
//
module InitializedBlockRAM_ForWideRequest #( 
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

    // Request side
    localparam INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    typedef logic [INDEX_BIT_SIZE-1: 0] Address;
    typedef logic [ENTRY_BIT_SIZE-1: 0] Value;
    localparam ENTRY_BIT_WIDTH = $clog2(ENTRY_BIT_SIZE);

    // Since the hex file is read in 128 bits units, the memory array is also 128 bits units.
    localparam HEX_FILE_ENTRY_BIT_SIZE = 128;
    // Calculates the index width when the memory array is configured in 128 bits units from the bandwidth
    // ********-------   : 128 bits memory array (Actual memory array)
    // *******--------   : 256 bits memory array  (Externally visible memory array)
    // (Index)   (Offset)
    // The sum of the bit width of Index and Offset is always the same
    localparam HEX_FILE_ENTRY_BIT_WIDTH = $clog2(HEX_FILE_ENTRY_BIT_SIZE);
    localparam HEX_FILE_INDEX_BIT_SIZE = 
        INDEX_BIT_SIZE + ENTRY_BIT_WIDTH - HEX_FILE_ENTRY_BIT_WIDTH;

    // Since the bandwidth is wide, 
    // read is realized by accessing hexArray multiple times.
    // Therefore, calculate how many times hexArray needs to be accessed
    localparam DIFF_BIT_WIDTH = (HEX_FILE_INDEX_BIT_SIZE > INDEX_BIT_SIZE) ? 
        HEX_FILE_INDEX_BIT_SIZE - INDEX_BIT_SIZE : 1;
    typedef logic [DIFF_BIT_WIDTH-1:0] CountPath;
    localparam HEX_BLOCK_FILL_NUM = (HEX_FILE_INDEX_BIT_SIZE > INDEX_BIT_SIZE) ?
        1 << DIFF_BIT_WIDTH : 1;

    // Hex file memory array
    typedef logic [HEX_FILE_INDEX_BIT_SIZE-1: 0] HexArrayIndex;
    typedef logic [HEX_FILE_ENTRY_BIT_SIZE-1: 0] HexArrayValue;

    // Raise an error if the bandwidth is smaller than or equal to 128 bits
    `RSD_STATIC_ASSERT(
        HEX_FILE_ENTRY_BIT_WIDTH <= ENTRY_BIT_WIDTH, 
        "Set ENTRY_BIT_SIZE more than 128 bits"
    );

    function automatic HexArrayIndex GetHexArrayIndexFromAddress(Address addr, CountPath count);
        if (HEX_FILE_INDEX_BIT_SIZE > INDEX_BIT_SIZE) begin
            return {addr, count};
        end
        else begin
            return addr;
        end
    endfunction

    localparam HEX_FILE_ARRAY_ENTRY_NUM = 1 << HEX_FILE_INDEX_BIT_SIZE;
`ifdef RSD_SYNTHESIS
    HexArrayValue array[HEX_FILE_ARRAY_ENTRY_NUM]; // synthesis syn_ramstyle = "block_ram"
`else
    // This signal will be written in a test bench, so set public for verilator.
    HexArrayValue array[HEX_FILE_ARRAY_ENTRY_NUM] /*verilator public*/;
`endif

    Address raReg;
    HexArrayIndex hexFileRA[HEX_BLOCK_FILL_NUM];
    HexArrayValue hexFileRV[HEX_BLOCK_FILL_NUM];

    HexArrayIndex hexFileWA[HEX_BLOCK_FILL_NUM];
    HexArrayValue hexFileWV[HEX_BLOCK_FILL_NUM];

    always_ff @(posedge clk) begin
        if (we) begin
            for (int i = 0; i < HEX_BLOCK_FILL_NUM; i++) begin
                array[hexFileWA[i]] <= hexFileWV[i];
            end
        end
            
        raReg <= ra;
    end
    
    // Read request
    always_comb begin
        // Read from the hex file array
        for (int i = 0; i < HEX_BLOCK_FILL_NUM; i++) begin
            hexFileRA[i] = GetHexArrayIndexFromAddress(raReg, i);
            hexFileRV[i] = array[hexFileRA[i]];
            rv[HEX_FILE_ENTRY_BIT_SIZE*i+:HEX_FILE_ENTRY_BIT_SIZE] = hexFileRV[i];
        end
    end

    // Write request
    always_comb begin
        // Write to the hex file array
        for (int i = 0; i < HEX_BLOCK_FILL_NUM; i++) begin
            hexFileWA[i] = GetHexArrayIndexFromAddress(wa, i);
            hexFileWV[i] = wv[HEX_FILE_ENTRY_BIT_SIZE*i+:HEX_FILE_ENTRY_BIT_SIZE];
        end
    end

    initial begin
        if (INIT_HEX_FILE != "") begin
            $readmemh(INIT_HEX_FILE, array);
        end
        else begin
            $display(
                "INIT_HEX_FILE in InitializedBlockRAM is not specified, so no file is read."
            );
        end
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

endmodule : InitializedBlockRAM_ForWideRequest


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
    // This signal will be written in a test bench, so set public for verilator.
    Value debugValue[ ENTRY_NUM ] /*verilator public*/;  
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
    Value debugValue[ENTRY_NUM] /*verilator public*/;
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
    Value debugValue[ENTRY_NUM] /*verilator public*/;
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
    // This signal will be written in a test bench, so set public for verilator.
    Value debugValue[ ENTRY_NUM ] /*verilator public*/;
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
    // This signal will be written in a test bench, so set public for verilator.
    Value debugValue[ ENTRY_NUM ] /*verilator public*/;
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
