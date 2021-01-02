// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// HardwareCounter
// 実行サイクル数など、性能を解析する上で必要な値をカウントするモジュール
//

import BasicTypes::*;
import DebugTypes::*;

//
// 面積削減のため、実行サイクル数のカウントだけやるモジュール
//
module SimpleHardwareCounter (
    HardwareCounterIF.HardwareCounter port
);
`ifndef RSD_DISABLE_HARDWARE_COUNTER
    // リセットが解除されてからのサイクル数
    DataPath countCycle;
    
    always_ff @(posedge port.clk) begin
        if ( port.rst ) begin
            countCycle <= 0;
        end
        else begin
            countCycle <= countCycle + 1;
        end
    end

    // データの出力
    always_comb begin
        for ( int i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin
            port.hardwareCounterData[i] = countCycle;
        end
    end
`else
    always_comb begin
        for ( int i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin
            port.hardwareCounterData[i] = 0; // Suppressing warning.
        end
    end
`endif
endmodule : SimpleHardwareCounter

//
// すべてのHWカウンタを持つモジュール
//
module HardwareCounter (
    HardwareCounterIF.HardwareCounter port
);
`ifndef RSD_DISABLE_HARDWARE_COUNTER
    // リセットが解除されてからのサイクル数
    DataPath countCycle;
    
    // ロードがDキャッシュにミスした回数
    DataPath countLoadMiss, nextCountLoadMiss;
    
    // コミット関係
    DataPath countCommit;
    DataPath countRefetchThisPC;
    DataPath countRefetchNextPC;
    DataPath countRefetchBrTarget;
    
    always_ff @(posedge port.clk) begin
        if ( port.rst ) begin
            countCycle <= 0;
            countCommit <= 0;
            countRefetchThisPC <= 0;
            countRefetchNextPC <= 0;
            countRefetchBrTarget <= 0;
            countLoadMiss <= 0;
        end
        else begin
            countCycle <= countCycle + 1;
            countCommit <= countCommit + port.commitNum;
            countRefetchThisPC <=
                countRefetchThisPC + ( port.refetchThisPC ? 1 : 0 );
            countRefetchNextPC <=
                countRefetchNextPC + ( port.refetchNextPC ? 1 : 0 );
            countRefetchBrTarget <=
                countRefetchBrTarget + ( port.refetchBrTarget ? 1 : 0 );
            countLoadMiss <= nextCountLoadMiss;
        end
    end
    
    // 面倒なカウント
    always_comb begin
        nextCountLoadMiss = countLoadMiss;
        for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
            if ( port.loadMiss[i] )
                nextCountLoadMiss++;
        end
    end
    
    // データの出力
    DataPath hardwareCounterData[ LOAD_ISSUE_WIDTH ];
    always_comb begin
        for ( int i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin
            case ( port.hardwareCounterType[i] )
            default:
                port.hardwareCounterData[i] = 0;
            HW_CNT_TYPE_CYCLE:
                port.hardwareCounterData[i] = countCycle;
            HW_CNT_TYPE_COMMIT:
                port.hardwareCounterData[i] = countCommit;
            HW_CNT_TYPE_REFETCH_THIS_PC:
                port.hardwareCounterData[i] = countRefetchThisPC;
            HW_CNT_TYPE_REFETCH_NEXT_PC:
                port.hardwareCounterData[i] = countRefetchNextPC;
            HW_CNT_TYPE_REFETCH_BR_TARGET:
                port.hardwareCounterData[i] = countRefetchBrTarget;
            HW_CNT_TYPE_LOAD_MISS:
                port.hardwareCounterData[i] = countLoadMiss;
            endcase
        end

        port.hardwareCounterData = hardwareCounterData;
    end
`else
    always_comb begin
        for ( int i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin
            port.hardwareCounterData[i] = 0; // Suppressing warning.
        end
    end
`endif
endmodule : HardwareCounter
