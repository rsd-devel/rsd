// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Branch predictor
//

import MicroArchConf::*;
import BasicTypes::*;
import FetchUnitTypes::*;

module BranchPredictor(
    NextPCStageIF.BranchPredictor port,
    FetchStageIF.BranchPredictor fetch,
    ControllerIF.BranchPredictor ctrl
);

    generate
        if (CONF_BRANCH_PREDICTOR_USE_GSHARE) begin
            Gshare predictor( port, fetch, ctrl );
        end
        else begin
            Bimodal predictor( port, fetch );
        end
    endgenerate

endmodule : BranchPredictor
