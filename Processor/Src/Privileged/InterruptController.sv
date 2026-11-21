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
    DecodeStageIF.InterruptController decodeStage,
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

    // Each destination has its own priority encoder. Select the destination
    // once, so an S-mode source never extends the M-mode selection chain.
    function automatic CSR_CAUSE_InterruptCodePath SelectInterruptCode(
        input DataPath pending
    );
        logic [7:0] customHalf;
        logic [3:0] customQuarter;
        logic [1:0] customPair;
        logic [3:0] customCode;
        CSR_CAUSE_InterruptCodePath code;

        // A balanced encoder selects the highest-numbered custom interrupt.
        customCode[3] = |pending[31:24];
        customHalf = customCode[3] ? pending[31:24] : pending[23:16];
        customCode[2] = |customHalf[7:4];
        customQuarter = customCode[2] ? customHalf[7:4] : customHalf[3:0];
        customCode[1] = |customQuarter[3:2];
        customPair = customCode[1] ? customQuarter[3:2] : customQuarter[1:0];
        customCode[0] = customPair[1];

        // Within a destination: custom > MEI > MSI > MTI > SEI > SSI > STI.
        if (|pending[31:16])
            code = CSR_CAUSE_InterruptCodePath'({1'b1, customCode});
        else if (pending[CSR_CAUSE_INTERRUPT_CODE_M_EXTERNAL])
            code = CSR_CAUSE_INTERRUPT_CODE_M_EXTERNAL;
        else if (pending[CSR_CAUSE_INTERRUPT_CODE_M_SOFTWARE])
            code = CSR_CAUSE_INTERRUPT_CODE_M_SOFTWARE;
        else if (pending[CSR_CAUSE_INTERRUPT_CODE_M_TIMER])
            code = CSR_CAUSE_INTERRUPT_CODE_M_TIMER;
        else if (pending[CSR_CAUSE_INTERRUPT_CODE_S_EXTERNAL])
            code = CSR_CAUSE_INTERRUPT_CODE_S_EXTERNAL;
        else if (pending[CSR_CAUSE_INTERRUPT_CODE_S_SOFTWARE])
            code = CSR_CAUSE_INTERRUPT_CODE_S_SOFTWARE;
        else if (pending[CSR_CAUSE_INTERRUPT_CODE_S_TIMER])
            code = CSR_CAUSE_INTERRUPT_CODE_S_TIMER;
        else
            code = CSR_CAUSE_InterruptCodePath'(0);
        return code;
    endfunction

    DataPath pending, machinePending, supervisorPending;
    logic machineValid, supervisorValid;

    always_comb begin
        csrReg = csrUnit.csrWholeOut;

        // Ignore unimplemented interrupt bits before testing either destination.
        pending = csrReg.mie & csrReg.mip & 32'hffff0aaa;
        machinePending = pending & ~csrReg.mideleg;
        supervisorPending = pending & csrReg.mideleg;
        machineValid = (|machinePending) &&
            (csrUnit.privilegeLevel < PRIVILEGE_LEVEL_M || csrReg.mstatus.MIE);
        supervisorValid = (|supervisorPending) &&
            (csrUnit.privilegeLevel < PRIVILEGE_LEVEL_S ||
             (csrUnit.privilegeLevel == PRIVILEGE_LEVEL_S && csrReg.mstatus.SIE));

        interruptRequest.valid = machineValid || supervisorValid;
        interruptRequest.toSmode = !machineValid && supervisorValid;
        interruptRequest.code = machineValid ? SelectInterruptCode(machinePending) :
            supervisorValid ? SelectInterruptCode(supervisorPending) :
            CSR_CAUSE_InterruptCodePath'(0);

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
        csrUnit.interruptELP = decodeStage.elpState;

        interruptXtvec = interruptToSmode ? csrReg.stvec : csrReg.mtvec;
        interruptTargetAddr = ToPC_FromAddr({
            (interruptXtvec.mode == CSR_XTVEC_MODE_VECTORED) ?
                (interruptXtvec.base + interruptCode) : interruptXtvec.base,
            CSR_XTVEC_BASE_PADDING
        });

        fetchStage.interruptAddrWE = triggerInterrupt;
        fetchStage.interruptAddrIn = interruptTargetAddr;
        decodeStage.setELP_OnInterrupt = triggerInterrupt;
    end

endmodule
