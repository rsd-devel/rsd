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
    
    Value array[ENTRY_NUM];

    always @(posedge clk) begin
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

    Value array[ENTRY_NUM];
    
    always_ff @(posedge clk) begin
        for (int i = 0; i < PORT_NUM; i++) begin
            rv[i] <= array[ rwa[i] ];
            if(we[i]) 
                array[ rwa[i] ] <= wv[i];
        end
    end

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

    Value array[ENTRY_NUM];

    always_ff @(posedge clk) begin
        for (int i = 0; i < WRITE_NUM; i++) begin
            if (we[i]) begin
                array[ wa[i] ] <= wv[i];
            end
        end
    end

    always_comb begin
        for (int i = 0; i < READ_NUM; i++) begin
            rv[i] <= array[ ra[i] ];
        end
    end

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
    localparam INDEX_BIT_SIZE = $clog2(ENTRY_NUM);
    typedef logic [INDEX_BIT_SIZE-1: 0] Address;
    typedef logic [ENTRY_BIT_SIZE-1: 0] Value;

    Value array[ENTRY_NUM];

    Address raReg;

    always @(posedge clk) begin
        if(we)
            array[wa] <= wv;
            
        raReg <= ra;
    end
    
    always_comb begin
        rv = array[raReg];
    end

`ifndef RSD_SYNTHESIS 
    `ifndef RSD_DISABLE_INITIAL
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
    `endif
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
    
endmodule : InitializedBlockRAM

//
// InitializedBlockRAM that supports a bandwidth of 64 bits or less
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

`ifdef RSD_SYNTHESIS
    HexArrayValue array[1 << HEX_FILE_INDEX_BIT_SIZE]; // synthesis syn_ramstyle = "block_ram"
`else
    // This signal will be written in a test bench, so set public for verilator.
    HexArrayValue array[1 << HEX_FILE_INDEX_BIT_SIZE] /*verilator public*/;
`endif

    Address raReg;
    HexArrayIndex hexFileRA;
    HexArrayValue hexFileRV;
    HexArrayEntryOffset hexFileRAOffset;

    HexArrayIndex hexFileWA;
    HexArrayValue hexFileWV;
    HexArrayEntryOffset hexFileWAOffset;
    HexArrayValue tmpWriteEntry;

    always @(posedge clk) begin
        if (we) begin
            array[hexFileWA] <= hexFileWV;
        end
            
        raReg <= ra;
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

`ifndef RSD_SYNTHESIS
    `ifndef RSD_DISABLE_INITIAL
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
    `endif
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
`ifndef RSD_VCS_SIMULATION
    `RSD_STATIC_ASSERT(
        HEX_FILE_ENTRY_BIT_WIDTH <= ENTRY_BIT_WIDTH, 
        "Set ENTRY_BIT_SIZE more than 128 bits"
    );
`endif

    function automatic HexArrayIndex GetHexArrayIndexFromAddress(Address addr, CountPath count);
        if (HEX_FILE_INDEX_BIT_SIZE > INDEX_BIT_SIZE) begin
            return {addr, count};
        end
        else begin
            return addr;
        end
    endfunction

`ifdef RSD_SYNTHESIS
    HexArrayValue array[1 << HEX_FILE_INDEX_BIT_SIZE]; // synthesis syn_ramstyle = "block_ram"
`else
    // This signal will be written in a test bench, so set public for verilator.
    HexArrayValue array[1 << HEX_FILE_INDEX_BIT_SIZE] /*verilator public*/;
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

`ifndef RSD_SYNTHESIS
    `ifndef RSD_DISABLE_INITIAL
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
    `endif
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

    always @(posedge clk) begin
        if(we)
            array[wa] <= wv;
    end
    
    always_comb begin
        rv = array[ra];
    end

`ifndef RSD_SYNTHESIS
    `ifndef RSD_DISABLE_INITIAL
        initial begin
            for (int i = 0; i < ENTRY_NUM; i++) begin
                for (int j = 0; j < ENTRY_BIT_SIZE; j++) begin
                    array[i][j] = 0;
                end
            end
        end
    `endif
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

    always @(posedge clk) begin
        if(we)
            array[wa] <= wv;
    end
    
    always_comb begin
        rv = array[ra];
    end

`ifndef RSD_SYNTHESIS
    `ifndef RSD_DISABLE_INITIAL
        initial begin
            for (int i = 0; i < (ENTRY_NUM); i++) begin
                for (int j = 0; j < ENTRY_BIT_SIZE; j++) begin
                    array[i][j] = 0;
                end
            end
        end
    `endif
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
    `ifndef RSD_VCS_SIMULATION
        for (genvar i = 0; i < READ_NUM-1; i++) begin
            `RSD_ASSERT_CLK_FMT(
                clk,
                !(ra >= ENTRY_NUM),
                ("Port (%x) read from the outside of the RAM array.", i+1)
            );
        end
    `endif
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
    
    Value array[ENTRY_NUM];

    always_ff @(posedge clk) begin
        for (int i = 0; i < WRITE_NUM; i++) begin
            if (we[i]) begin
                array[ wa[i] ] <= wv[i];
            end
        end
    end

    always_comb begin
        for (int i = 0; i < READ_NUM; i++) begin
            rv[i] <= array[ ra[i] ];
        end
    end
    
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
    
    Value array[ENTRY_NUM];

    always_ff @(posedge clk) begin
        for (int i = 0; i < WRITE_NUM; i++) begin
            if (we[i]) begin
                array[ wa[i] ] <= wv[i];
            end
        end
    end

    always_comb begin
        for (int i = 0; i < READ_NUM; i++) begin
            rv[i] <= array[ ra[i] ];
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

    Value array[ENTRY_NUM];

    always_ff @(posedge clk) begin
        for (int i = 0; i < WRITE_NUM; i++) begin
            if (we[i]) begin
                array[wa[i]] <= wv[i];
            end
        end
    end

    always_comb begin
        for (int i = 0; i < READ_NUM; i++) begin
            rv[i] = array[ra[i]];
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
            always @(posedge clk) begin
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


    `ifndef RSD_DISABLE_INITIAL
        initial begin
            for (int i = 0; i < ENTRY_NUM; i++) begin
                for (int j = 0; j < ENTRY_BIT_SIZE; j++) begin
                    debugValue[i][j] = 0;
                end
            end
        end
    `endif

    always @(posedge clk) begin
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

    `ifndef RSD_DISABLE_INITIAL
        initial begin
            for (int i = 0; i < ENTRY_NUM; i++) begin
                for (int j = 0; j < ENTRY_BIT_SIZE; j++) begin
                    debugValue[i][j] = 0;
                end
            end
        end
    `endif

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
