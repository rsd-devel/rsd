// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Branch predictor
//

import BasicTypes::*;
import FetchUnitTypes::*;

module BranchPredictor(
    FetchStageIF.BranchPredictor port,
    ControllerIF.BranchPredictor ctrl
);

    if (USE_GSHARE) begin : gshare
        Gshare predictor( port, ctrl );
    end
    else begin : bimodal
        Bimodal predictor( port );
    end

endmodule : BranchPredictor
