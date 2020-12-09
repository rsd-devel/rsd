// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// CSR Unit
//

`include "BasicMacros.sv"

import BasicTypes::*;
import CSR_UnitTypes::*;
import MemoryMapTypes::*;

module InterruptController(
    CSR_UnitIF.InterruptController csrUnit,
    ControllerIF.InterruptController ctrl,
    NextPCStageIF.InterruptController fetchStage,
    RecoveryManagerIF.InterruptController recoveryManager
);
    logic reqInterrupt, triggerInterrupt;
    logic reqTimerInterrupt, reqExternalInterrupt;
    CSR_CAUSE_InterruptCodePath interruptCode;
    PC_Path interruptTargetAddr;
    CSR_BodyPath csrReg;
    InterruptCodeConvPath interruptCodeConv;

    `RSD_STATIC_ASSERT(
        RSD_EXTERNAL_INTERRUPT_CODE_WIDTH == CSR_CAUSE_INTERRUPT_CODE_WIDTH,
        "The width of an external interrupt code and the code in the CSR do not match"
    );

    always_comb begin
        csrReg = csrUnit.csrWholeOut;

        reqTimerInterrupt =     csrReg.mie.MTIE && csrReg.mip.MTIP;
        reqExternalInterrupt =  csrReg.mie.MEIE && csrReg.mip.MEIP;

        reqInterrupt = csrReg.mstatus.MIE && (reqTimerInterrupt || reqExternalInterrupt);
        interruptCodeConv.exCode = csrUnit.externalInterruptCodeInCSR; // Type conversion through union
        if (reqTimerInterrupt) begin
            // Timer has higher priority.
            interruptCode = CSR_CAUSE_INTERRUPT_CODE_TIMER;
        end
        else begin
            interruptCode = interruptCodeConv.csrCode;
        end

        // パイプライン全体が空になるまでフェッチをとめる        
        ctrl.npStageSendBubbleLowerForInterrupt =
            reqInterrupt;
        
        // * パイプライン全体が空になったら割り込みをかける
        // * パイプラインが空でもリカバリマネージャが PC を書き換えている途中の
        //   可能性があるため，きちんと待つ必要がある
        // * reqInterrupt は csrReg のみをみて決定しているので，
        //   要求を出したことによって，CSR 内で MIE が落とされてループするということは
        //   ないはず
        triggerInterrupt = 
            ctrl.wholePipelineEmpty && 
            !recoveryManager.unableToStartRecovery && 
            reqInterrupt;

        csrUnit.triggerInterrupt = triggerInterrupt;
        csrUnit.interruptRetAddr = fetchStage.pcOut;
        csrUnit.interruptCode = interruptCode;

        interruptTargetAddr = ToPC_FromAddr({
            (csrReg.mtvec.mode == CSR_MTVEC_MODE_VECTORED) ? 
                (csrReg.mtvec.base + interruptCode) : csrReg.mtvec.base, 
            CSR_MTVEC_BASE_PADDING
        });

        fetchStage.interruptAddrWE = triggerInterrupt;
        fetchStage.interruptAddrIn = interruptTargetAddr;
    end

endmodule