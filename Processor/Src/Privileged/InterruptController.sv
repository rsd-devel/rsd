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
    logic reqInterrupt, triggerInterrupt, interruptToSmode;
    CSR_CAUSE_InterruptCodePath interruptCode;
    CSR_XTVEC_Path interruptXtvec;

    PC_Path interruptTargetAddr;
    CSR_BodyPath csrReg;

    `RSD_STATIC_ASSERT(
        RSD_CUSTOM_INTERRUPT_CODE_WIDTH + 1 == CSR_CAUSE_INTERRUPT_CODE_WIDTH,
        "The width of an custom interrupt code and the code in the CSR do not match"
    );

    function void checkInterrupt(
        input CSR_BodyPath csrReg,
        input CSR_CAUSE_InterruptCodePath code,
        inout logic triggerInterrupt,
        inout logic interruptToSmode,
        inout CSR_CAUSE_InterruptCodePath interruptCode
    );
        if (csrReg.mie[code] && csrReg.mip[code]) begin
            if (csrReg.mideleg[code]) begin
                // trap to S-mode
                if (csrUnit.privilegeLevel <= PRIVILEGE_LEVEL_S && // trap to higher mode is not allowed
                    (csrUnit.privilegeLevel < PRIVILEGE_LEVEL_S || csrReg.mstatus.SIE)
                ) begin
                    triggerInterrupt = 1;
                    interruptToSmode = 1;
                    interruptCode = code;
                end
            end else begin
                // trap to M-mode
                if (csrUnit.privilegeLevel < PRIVILEGE_LEVEL_M || csrReg.mstatus.MIE) begin
                    triggerInterrupt = 1;
                    interruptToSmode = 0;
                    interruptCode = code;
                end
            end
        end
    endfunction

    always_comb begin
        csrReg = csrUnit.csrWholeOut;

        // priority order is
        // Custom Interrupt (msb > msb -1 > ... > 16) > MEI > MSI > MTI > SEI > SSI > STI > LCOFI
        reqInterrupt = 0;
        interruptCode = 0;
        interruptToSmode = 0;

        checkInterrupt(csrReg, CSR_CAUSE_INTERRUPT_CODE_S_TIMER   , reqInterrupt, interruptToSmode, interruptCode);
        checkInterrupt(csrReg, CSR_CAUSE_INTERRUPT_CODE_S_SOFTWARE, reqInterrupt, interruptToSmode, interruptCode);
        checkInterrupt(csrReg, CSR_CAUSE_INTERRUPT_CODE_S_EXTERNAL, reqInterrupt, interruptToSmode, interruptCode);
        checkInterrupt(csrReg, CSR_CAUSE_INTERRUPT_CODE_M_TIMER   , reqInterrupt, interruptToSmode, interruptCode);
        checkInterrupt(csrReg, CSR_CAUSE_INTERRUPT_CODE_M_SOFTWARE, reqInterrupt, interruptToSmode, interruptCode);
        checkInterrupt(csrReg, CSR_CAUSE_INTERRUPT_CODE_M_EXTERNAL, reqInterrupt, interruptToSmode, interruptCode);

        // Custom Interrupt
        // TODO replace custom interrupt with PLIC
        for (int i = 16; i < 32; i++) begin
            checkInterrupt(csrReg, CSR_CAUSE_InterruptCodePath'(i), reqInterrupt, interruptToSmode, interruptCode);
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

        interruptXtvec = interruptToSmode ? csrReg.stvec : csrReg.mtvec;
        interruptTargetAddr = ToPC_FromAddr({
            (interruptXtvec.mode == CSR_XTVEC_MODE_VECTORED) ?
                (interruptXtvec.base + interruptCode) : interruptXtvec.base,
            CSR_XTVEC_BASE_PADDING
        });

        fetchStage.interruptAddrWE = triggerInterrupt;
        fetchStage.interruptAddrIn = interruptTargetAddr;
    end

endmodule