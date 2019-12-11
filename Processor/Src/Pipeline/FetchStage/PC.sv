// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// PC
// PC has INSN_RESET_VECTOR and cannot use AddrReg.
//

import BasicTypes::*;
import MemoryMapTypes::*;

module PC( NextPCStageIF.PC port );
    
    FlipFlopWE#( PC_WIDTH, INSN_RESET_VECTOR ) 
        body( 
            .out( port.pcOut ), 
            .in ( port.pcIn ),
            .we ( port.pcWE ), 
            .clk( port.clk ),
            .rst( port.rst )
        );
        
endmodule : PC

