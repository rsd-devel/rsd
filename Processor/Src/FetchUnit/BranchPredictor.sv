// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Branch predictor
//

import BasicTypes::*;
import FetchUnitTypes::*;

`define USE_GSHARE

module BranchPredictor(
    FetchStageIF.BranchPredictor port,
    ControllerIF.BranchPredictor ctrl
);

`ifdef USE_GSHARE
    Gshare predictor( port, ctrl );
`else
    Bimodal predictor( port );
`endif

endmodule : BranchPredictor
