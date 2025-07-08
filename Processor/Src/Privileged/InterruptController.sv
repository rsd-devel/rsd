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
    CSR_CAUSE_InterruptCodePath interruptCode;
    PC_Path interruptTargetAddr;
    CSR_BodyPath csrReg;

    `RSD_STATIC_ASSERT(
        RSD_CUSTOM_INTERRUPT_CODE_WIDTH + 1 == CSR_CAUSE_INTERRUPT_CODE_WIDTH,
        "The width of an custom interrupt code and the code in the CSR do not match"
    );

    always_comb begin
        csrReg = csrUnit.csrWholeOut;

        // priority order is
        // Custom Interrupt (msb > msb -1 > ... > 16) > MEI > MSI > MTI > SEI > SSI > STI > LCOFI
        reqInterrupt = 0;
        interruptCode = 0;

        // Machine timer interrupt
        if (csrReg.mie.MTIE && csrReg.mip.MTIP) begin
            reqInterrupt = 1;
            interruptCode = CSR_CAUSE_INTERRUPT_CODE_TIMER;
        end

        // Custom Interrupt
        for (int i = 16; i < 32; i++) begin
            if (csrReg.mie[i] && csrReg.mip[i]) begin
                reqInterrupt = 1;
                interruptCode = i;
            end
        end

        // check global mask
        reqInterrupt &= csrUnit.privilegeLevel < PRIVILEGE_LEVEL_M || csrReg.mstatus.MIE;

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
            (csrReg.mtvec.mode == CSR_XTVEC_MODE_VECTORED) ? 
                (csrReg.mtvec.base + interruptCode) : csrReg.mtvec.base, 
            CSR_XTVEC_BASE_PADDING
        });

        fetchStage.interruptAddrWE = triggerInterrupt;
        fetchStage.interruptAddrIn = interruptTargetAddr;
    end

endmodule