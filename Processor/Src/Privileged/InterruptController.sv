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
    typedef struct packed {
        logic valid;
        logic toSmode;
        CSR_CAUSE_InterruptCodePath code;
    } InterruptRequestPath;
    InterruptRequestPath interruptRequest;

    logic reqInterrupt, triggerInterrupt, interruptToSmode;
    CSR_CAUSE_InterruptCodePath interruptCode;
    CSR_XTVEC_Path interruptXtvec;

    PC_Path interruptTargetAddr;
    CSR_BodyPath csrReg;

    `RSD_STATIC_ASSERT(
        RSD_CUSTOM_INTERRUPT_CODE_WIDTH + 1 == CSR_CAUSE_INTERRUPT_CODE_WIDTH,
        "The width of an custom interrupt code and the code in the CSR do not match"
    );

    function automatic InterruptRequestPath checkInterrupt(
        input CSR_BodyPath csrReg,
        input CSR_CAUSE_InterruptCodePath code,
        input PrivilegeLevelType privilegeLevel,
        input InterruptRequestPath previous
    );
        InterruptRequestPath result;
        // Preserve the previous selection unless this higher-priority source wins.
        result = previous;
        if (csrReg.mie[code] && csrReg.mip[code]) begin
            if (csrReg.mideleg[code]) begin
                // trap to S-mode
                if (privilegeLevel <= PRIVILEGE_LEVEL_S && // trap to higher mode is not allowed
                    (privilegeLevel < PRIVILEGE_LEVEL_S || csrReg.mstatus.SIE)
                ) begin
                    result.valid = 1;
                    result.toSmode = 1;
                    result.code = code;
                end
            end else begin
                // trap to M-mode
                if (privilegeLevel < PRIVILEGE_LEVEL_M || csrReg.mstatus.MIE) begin
                    result.valid = 1;
                    result.toSmode = 0;
                    result.code = code;
                end
            end
        end
        return result;
    endfunction

    always_comb begin
        csrReg = csrUnit.csrWholeOut;

        // priority order is
        // Custom Interrupt (msb > msb -1 > ... > 16) > MEI > MSI > MTI > SEI > SSI > STI > LCOFI
        interruptRequest = '0;

        interruptRequest = checkInterrupt(csrReg, CSR_CAUSE_INTERRUPT_CODE_S_TIMER   , csrUnit.privilegeLevel, interruptRequest);
        interruptRequest = checkInterrupt(csrReg, CSR_CAUSE_INTERRUPT_CODE_S_SOFTWARE, csrUnit.privilegeLevel, interruptRequest);
        interruptRequest = checkInterrupt(csrReg, CSR_CAUSE_INTERRUPT_CODE_S_EXTERNAL, csrUnit.privilegeLevel, interruptRequest);
        interruptRequest = checkInterrupt(csrReg, CSR_CAUSE_INTERRUPT_CODE_M_TIMER   , csrUnit.privilegeLevel, interruptRequest);
        interruptRequest = checkInterrupt(csrReg, CSR_CAUSE_INTERRUPT_CODE_M_SOFTWARE, csrUnit.privilegeLevel, interruptRequest);
        interruptRequest = checkInterrupt(csrReg, CSR_CAUSE_INTERRUPT_CODE_M_EXTERNAL, csrUnit.privilegeLevel, interruptRequest);

        // Custom Interrupt
        // TODO replace custom interrupt with PLIC
        for (int i = 16; i < 32; i++) begin
            interruptRequest = checkInterrupt(csrReg, CSR_CAUSE_InterruptCodePath'(i), csrUnit.privilegeLevel, interruptRequest);
        end

        reqInterrupt = interruptRequest.valid;
        interruptToSmode = interruptRequest.toSmode;
        interruptCode = interruptRequest.code;

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