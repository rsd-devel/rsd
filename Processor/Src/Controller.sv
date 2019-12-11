// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


import BasicTypes::*;
import PipelineTypes::*;
import DebugTypes::*;

module Controller(
    ControllerIF.Controller port,
    DebugIF.Controller debug
);

    PipelineControll npStage;
    PipelineControll ifStage;
    PipelineControll pdStage;
    PipelineControll idStage;
    PipelineControll rnStage;
    PipelineControll dsStage;

    PipelineControll scStage;
    PipelineControll isStage;
    PipelineControll backEnd;
    PipelineControll cmStage;
    logic stallByDecodeStage;

    always_comb begin

        //
        // See comments in ControllerIF for stall/clear
        //

        stallByDecodeStage = FALSE;

        //
        // --- Front-end control
        //
        if( port.rst ) begin
            // リセット時にパイプラインラッチに無効化フラグを書くため，stall はFALSE に
            //              stall/ clear
            npStage = { FALSE, TRUE };
            ifStage = { FALSE, TRUE };
            pdStage = { FALSE, TRUE };
            idStage = { FALSE, TRUE };
            rnStage = { FALSE, TRUE };
            dsStage = { FALSE, TRUE };

        end
        else begin
            //
            // 通常時
            //              stall/ clear
            npStage = { FALSE, FALSE };
            ifStage = { FALSE, FALSE };
            pdStage = { FALSE, FALSE };
            idStage = { FALSE, FALSE };
            rnStage = { FALSE, FALSE };
            dsStage = { FALSE, FALSE };

            //
            // A request from lower stages has a higher priority.
            //
            if( port.cmStageFlushUpper ) begin
                // Clear ops not in the active list when branch misprediction is detected.
                //              stall/ clear
                npStage = { FALSE, FALSE };
                ifStage = { FALSE, TRUE };
                pdStage = { FALSE, TRUE };
                idStage = { FALSE, TRUE };
                rnStage = { FALSE, TRUE };
                dsStage = { FALSE, TRUE };

            end
            else if( port.rnStageSendBubbleLower ) begin
                //
                // Stall and send a bubble to lower stages because there are not enough
                // physical registers
                //              stall/ clear
                npStage = { TRUE,  FALSE };
                ifStage = { TRUE,  FALSE };
                pdStage = { TRUE,  FALSE };
                idStage = { TRUE,  FALSE };
                rnStage = { TRUE,  TRUE  }; // 後続ステージにバブル（NOP）を送る
            end
            else if( port.rnStageFlushUpper ) begin
                //
                // リネーマより上流をフラッシュ
                //              stall/ clear
                npStage = { FALSE, FALSE };
                ifStage = { FALSE, TRUE };
                pdStage = { FALSE, TRUE };
                idStage = { FALSE, TRUE };

            end
            else if( port.idStageStallUpper ) begin
                //
                // デコーダより上流（フェッチャ）をストール
                // マイクロOp デコードを行うためにとめているため，
                // バブルは不要
                //              stall/ clear
                npStage = { TRUE,  FALSE };
                ifStage = { TRUE,  FALSE };
                pdStage = { TRUE,  FALSE };
                idStage = { TRUE,  FALSE };

                stallByDecodeStage = TRUE;
            end
            else if(
                port.ifStageSendBubbleLower
            ) begin
                //
                // I-Cache miss.
                // Stop PC update and Send NOPs to the lower stages.
                //          stall/ clear
                npStage = { TRUE, TRUE };  
                ifStage = { TRUE, TRUE };  
            end
            else if(
                port.npStageSendBubbleLower || 
                port.npStageSendBubbleLowerForInterrupt
            ) begin
                //
                // Interrupt
                //
                npStage = { TRUE, TRUE };  
            end
        end


        port.npStage = npStage;
        port.ifStage = ifStage;
        port.pdStage = pdStage;
        port.idStage = idStage;
        port.rnStage = rnStage;
        port.dsStage = dsStage;
        port.stallByDecodeStage = stallByDecodeStage;

        //
        // --- Back-end control
        //

        if( port.rst ) begin
            // リセット時にパイプラインラッチに無効化フラグを書くため，stall はFALSE に
            //              stall/ clear
            scStage = { FALSE, TRUE };
            isStage = { FALSE, TRUE };
            backEnd = { FALSE, TRUE };
            cmStage = { FALSE, TRUE };

        end
        else begin
            //
            // A request from lower stages has a higher priority.
            //
            if (port.isStageStallUpper) begin
                // Stall scheduler
                scStage = { TRUE, FALSE };
                isStage = { TRUE, FALSE };
                backEnd = { FALSE, FALSE };
                cmStage = { FALSE, FALSE };
            end
            else begin
                //
                // 通常時
                //              stall/ clear
                scStage = { FALSE, FALSE };
                isStage = { FALSE, FALSE };
                backEnd = { FALSE, FALSE };
                cmStage = { FALSE, FALSE };
            end
        end

        port.scStage = scStage;
        port.isStage = isStage;
        port.backEnd = backEnd;
        port.cmStage = cmStage;

        // パイプライン全体で生きている命令がいるかどうか
        port.wholePipelineEmpty = 
            npStage.clear &&            // IF は clear されない限り何か有効な命令をフェッチする
            port.ifStageEmpty &&
            port.pdStageEmpty &&
            port.idStageEmpty && 
            port.rnStageEmpty &&
            port.activeListEmpty;

`ifndef RSD_DISABLE_DEBUG_REGISTER
        // Debug Register
        debug.npStagePipeCtrl = npStage;
        debug.ifStagePipeCtrl = ifStage;
        debug.pdStagePipeCtrl = pdStage;
        debug.idStagePipeCtrl = idStage;
        debug.rnStagePipeCtrl = rnStage;
        debug.dsStagePipeCtrl = dsStage;
        debug.backEndPipeCtrl = backEnd;
        debug.cmStagePipeCtrl = cmStage;
        debug.stallByDecodeStage = stallByDecodeStage;
`endif
    end

endmodule
