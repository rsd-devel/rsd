// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- Divider Unit
// This unit performs 32bit/32bit = 32bit using the nonrestoring division method
//

import BasicTypes::*;
 
module Divider(
input
    logic clk, rst,         // clock, reset
    logic req,              // request a new operation
    DataPath dividend,
    DataPath divisor,
    logic isSigned,          // operation is performed in a singed mode
output
    logic finished,
    DataPath quotient,
    DataPath remainder
);
    // 演算幅
    // 符号なしを，符号付きに拡張するので +1 する
    // 32-bit 符号なしは，33ビット符号付きの正の値とする
    parameter LOOP_COUNT = DATA_WIDTH + 1;

    // 演算はさらに +1 ビットの幅で行う
    // これは左シフト時に，符号ビットが上位に追い出されて消滅してしまうのをふせぐため
    // 1ビット余計に持っておけば，必ず符号は残る
    parameter DIVIDER_WIDTH = LOOP_COUNT + 1;
    typedef logic [DIVIDER_WIDTH-1:0] DividerPath;

    // オーバーフロー判定用定数
    parameter DATA_MINUS_ONE = (1 << DATA_WIDTH) - 1;
    parameter DATA_MINIMUM = (1 << (DATA_WIDTH - 1));


    // Internal registers
    DividerPath regZ, nextZ;  // dividend
    DividerPath regD, nextD;  // divisor
    DividerPath regQ, nextQ;  // quotient
    DividerPath regR, nextR;  // remainder
    logic regSigned, nextSigned; // signed or unsigned


    logic [$clog2(LOOP_COUNT+1)-1:0] regCounter, nextCounter;

    typedef enum logic[1:0]
    {
        PHASE_FINISHED = 0,     // Division is finished. It outputs results to quotient, remainder 
        PHASE_PROCESSING = 1,   // In processing
        PHASE_COMPENSATING = 2  // In processing for compensating results
    } Phase;
    Phase regPhase, nextPhase;

     always_ff @(posedge clk) begin
        if (rst) begin
            regZ <= 0;
            regD <= 0;
            regQ <= 0;
            regR <= 0;
            regPhase <= PHASE_FINISHED;
            regCounter <= 0;
            regSigned <= FALSE;
        end
        else begin
            regZ <= nextZ;
            regD <= nextD;
            regQ <= nextQ;
            regR <= nextR;
            regPhase <= nextPhase;
            regCounter <= nextCounter;
            regSigned <= nextSigned;
        end
     end


     always_comb begin
        finished = (regPhase == PHASE_FINISHED) ? TRUE : FALSE;

        if (req) begin
            /*
            // 入力を 64bit に符号拡張
            dividend = dividend_src | (p_sign ? ((uint64_t)0xffffffff << 32) : 0);
            dividend = dividend & op_mask;
            divisor = divisor_src | (s_divisor ? ((uint64_t)0xffffffff << 32) : 0);
            divisor = divisor & op_mask;
            */

            // A request is accepted regardless of the current phase
            if (isSigned) begin
                // Sign extend
                // 2 bits are added because DIVIDER_WIDTH = DATA_WIDTH + 2
                nextZ = dividend[DATA_WIDTH - 1] ? {2'b11, dividend} : {2'b00, dividend};
                nextD = divisor[DATA_WIDTH - 1] ? {2'b11, divisor} : {2'b00, divisor};
            end
            else begin
                nextZ = {2'b00, dividend};
                nextD = {2'b00, divisor};
            end

            /*
            uint64_t q = 0;
            uint64_t pr = p_sign ? -1 : 0;  // pr は符号拡張してうめておく
            */
            nextQ = 0;
            nextR = nextZ[DIVIDER_WIDTH-1] ? -1 : 0;   // not DATA_WIDTH-1!

            nextSigned = isSigned;
            nextPhase = PHASE_PROCESSING;
            nextCounter = 0;
        end
        else begin 
            nextZ = regZ;
            nextD = regD;
            nextQ = regQ;
            nextR = regR;
            nextSigned = regSigned;
            nextCounter = regCounter;

            // Sign
            //signZ = regZ[DATA_WIDTH - 1];
            //signD = regD[DATA_WIDTH - 1];

            if (regPhase == PHASE_PROCESSING) begin

                // 左に桁上げ
                // op_mask の幅が +1 されているのは，このとき符号ビットが消滅しないように
                // するため
                //uint64_t new_bit = ((dividend >> (dividend_length - 1 - i)) & 1);
                //pr = (pr << 1) | new_bit;
                //pr &= op_mask;
                nextR = (regR << 1) | regZ[LOOP_COUNT - 1 - regCounter];
                
                //$display("regCounter:%d, nextR[DIVIDER_WIDTH-1]:%d, regZ[DATA_WIDTH-1]:%d", regCounter, nextR[DIVIDER_WIDTH-1], regZ[DATA_WIDTH-1]);
                
                // if (s_pr != s_divisor) {
                if (nextR[DIVIDER_WIDTH-1] != regD[DIVIDER_WIDTH-1]) begin
                    nextR += regD;
                    // q <<= 1;
                    nextQ = regQ << 1;
                end
                else begin
                    nextR -= regD;
                    // q <<= 1;
                    // q |= 1;
                    nextQ = (regQ << 1) | 1;
                end

                nextCounter = regCounter + 1;
                nextPhase = (nextCounter >= LOOP_COUNT) ? PHASE_COMPENSATING : PHASE_PROCESSING;
            end
            else if (regPhase == PHASE_COMPENSATING) begin

                // -1,1 から通常のバイナリへのデコード
                nextQ = (regQ << 1) + 1;
                nextR = regR;

                //bool s_pr = ((pr >> dividend_length) & 1);
                //uint64_t result_mask = ((uint64_t)1 << (dividend_length)) - 1;
                
                if (regR[DATA_WIDTH+1-1:0] == 0) begin
                    // 余りが 0 の時は補正はいらない
                end 
                else begin
                    if (regR[DATA_WIDTH+1-1:0] == regD[DATA_WIDTH+1-1:0]) begin
                        // 余りが序数と一致した場合，戻す
                        nextR -= regD;
                        nextQ += 1;
                    end
                    else if (regR[DATA_WIDTH+1-1:0] + regD[DATA_WIDTH+1-1:0] == 0) begin
                        // 余りが序数の反転と一致した場合，戻す
                        nextR += regD;
                        nextQ -= 1;
                    end
                    else if (regZ[DATA_WIDTH+1-1] != regR[DATA_WIDTH+1-1]) begin
                        // p_sign = (dividend_src & 0x80000000);
                        // s_pr = 
                        // 序数と余りの符号が一致しない場合，補正する
                        if (regR[DATA_WIDTH+1-1] != regD[DATA_WIDTH+1-1]) begin
                            nextR += regD;
                            nextQ -= 1;
                        end
                        else begin
                            nextR -= regD;
                            nextQ += 1;
                        end
                    end

                    // Results on division by zero or overflow are difined by 
                    // RISC-V specification.
                    if (regD == 0) begin
                        // Division by zero
                        nextQ = -1;
                        nextR = regZ;
                    end
                    else if (regSigned && regZ == DATA_MINIMUM && regD == DATA_MINUS_ONE) begin 
                        // Sigined division can cause overflow
                        // ex. 8 bits signed division "-0x80 / -1 = 0x80"
                        // causes overflow because the resulst 0x80 > 0x7f
                        nextQ = regZ;
                        nextR = 0;
                    end
                end
                nextPhase = PHASE_FINISHED;
            end
            else begin  // PHASE_FINISHED
                nextPhase = regPhase;
            end
        end

        // Output results
        quotient = regQ;
        remainder = regR;

     end

endmodule : Divider


module QuickDivider(
input
    logic clk, rst,         // clock, reset
    logic req,              // request a new operation
    DataPath dividend,
    DataPath divisor,
    logic isSigned,          // operation is performed in a singed mode
output
    logic finished,
    DataPath quotient,
    DataPath remainder
);


    // 演算幅
    // 符号なしを，符号付きに拡張するので +1 する
    // 32-bit 符号なしは，33-bit 符号付きの正の値とする
    parameter DIVIDER_WIDTH = DATA_WIDTH + 1;
    typedef logic [DIVIDER_WIDTH-1:0] DividerPath;

    function automatic logic [$clog2(DIVIDER_WIDTH+1)-1:0] CountSignificantBits(
    input
        DividerPath dividend
    );
        // 1 <= CountSignificantBits <= 33

        // CountSignificantBits == 1 if dividend == 0 or dividend == -1
        CountSignificantBits = 1;
        for (int i = DIVIDER_WIDTH-2; i >= 0; --i) begin
            if (dividend[DIVIDER_WIDTH-1] != dividend[i]) begin
                CountSignificantBits = i + 2;
                break;
            end
        end

    endfunction

    // 商の最大ビット数
    parameter MAX_LOOP_COUNT = DATA_WIDTH + 1;

    // オーバーフロー判定用定数
    parameter DATA_MINUS_ONE = (1 << DATA_WIDTH) - 1;
    parameter DATA_MINIMUM = (1 << (DATA_WIDTH - 1));


    // Internal registers
    DividerPath regZ, nextZ;  // dividend
    DividerPath regD, nextD;  // divisor
    DividerPath regQ, nextQ;  // quotient
    DividerPath regR, nextR;  // remainder
    logic regSigned, nextSigned; // signed or unsigned


    logic [$clog2(MAX_LOOP_COUNT+1)-1:0] regCounter, nextCounter;

    typedef enum logic[1:0]
    {
        PHASE_FINISHED = 0,     // Division is finished. It outputs results to quotient, remainder 
        PHASE_FIRSTBIT = 1,     // In processing first bit
        PHASE_PROCESSING = 2,   // In processing
        PHASE_COMPENSATING = 3  // In processing for compensating results
    } Phase;
    Phase regPhase, nextPhase;

    always_ff @(posedge clk) begin
        if (rst) begin
            regZ <= 0;
            regD <= 0;
            regQ <= 0;
            regR <= 0;
            regPhase <= PHASE_FINISHED;
            regCounter <= 0;
            regSigned <= FALSE;
        end
        else begin
            regZ <= nextZ;
            regD <= nextD;
            regQ <= nextQ;
            regR <= nextR;
            regPhase <= nextPhase;
            regCounter <= nextCounter;
            regSigned <= nextSigned;
        end
    end


    always_comb begin
        finished = (regPhase == PHASE_FINISHED) ? TRUE : FALSE;

        if (req) begin
            // 入力を演算幅である 33-bit 符号付き整数に変換

            // A request is accepted regardless of the current phase
            if (isSigned) begin
                // Sign extend
                // 1 bits are added because DIVIDER_WIDTH = DATA_WIDTH + 1
                nextZ = dividend[DATA_WIDTH - 1] ? {1'b1, dividend} : {1'b0, dividend};
                nextD = divisor[DATA_WIDTH - 1] ? {1'b1, divisor} : {1'b0, divisor};
            end
            else begin
                nextZ = {1'b0, dividend};
                nextD = {1'b0, divisor};
            end

            // nextQ は次のサイクルで埋められるので↓は意味なし
            nextQ = 0;
            // nextR は符号拡張して埋めておく
            nextR = nextZ[DIVIDER_WIDTH-1] ? -1 : 0;

            nextSigned = isSigned;
            nextPhase = PHASE_FIRSTBIT;
            // 被除数の絶対値が小さいとき 32+α サイクルも計算する必要はない
            // 商の立ち方は -1 を T と書くことにして
            // その場合商が正の時 1TTTTTT... 商が負の時 T111111... となる
            // 先頭の 0 を許せば  000001T...            000001T というような
            // 商を立てることができ，無駄を省くことができる
            // 除数のことを考慮せず，保守的に0でない商が立つビット幅を求める
            // （除数の絶対値が大きい場合は，商の長さをさらに短くできる）
            // 商は最大でも CountSiginificatntBits(nextZ) ビットで表せる
            nextCounter = CountSignificantBits(nextZ);
        end
        else begin 
            nextZ = regZ;
            nextD = regD;
            nextQ = regQ;
            nextR = regR;
            nextSigned = regSigned;
            nextCounter = regCounter;

            // Sign
            //signZ = regZ[DATA_WIDTH - 1];
            //signD = regD[DATA_WIDTH - 1];

            if (regPhase == PHASE_FIRSTBIT) begin

                // 左に桁上げ
                nextR = (regR << 1) | regZ[regCounter - 1];

                if (regR[DIVIDER_WIDTH-1] != regD[DIVIDER_WIDTH-1]) begin
                    nextR += regD;
                    // 実際に立つ商は T だが，最上位ビットは追い出し，
                    // 最終的な結果に表れないようにしている
                    // ただし商の符号を決めるために使われる
                    // 補正前商の先頭が T ということはデコード後は負の値
                    // よって符号拡張を見越して事前に埋めておく
                    nextQ = -1;
                end
                else begin
                    nextR -= regD;
                    // 実際に立つ商は 1 でありそれ以外は同上
                    // 補正前商の先頭が 1 ということはデコード後は正の値
                    nextQ = 0;
                end

                nextCounter = regCounter - 1;
                nextPhase = (nextCounter == 0) ? PHASE_COMPENSATING : PHASE_PROCESSING;
            end
            else if (regPhase == PHASE_PROCESSING) begin

                // 左に桁上げ
                nextR = (regR << 1) | regZ[regCounter - 1];
                
                //$display("regCounter:%d, nextR[DIVIDER_WIDTH-1]:%d, regZ[DATA_WIDTH-1]:%d", regCounter, nextR[DIVIDER_WIDTH-1], regZ[DATA_WIDTH-1]);
                
                // signR = regR[DIVIDER_WIDTH-1]
                // 桁上げしたものではなく元の値を参照することで
                // 符号ビットが追い出される問題が発生しなくなる
                if (regR[DIVIDER_WIDTH-1] != regD[DIVIDER_WIDTH-1]) begin
                    nextR += regD;
                    // q <<= 1;
                    nextQ = regQ << 1;
                end
                else begin
                    nextR -= regD;
                    // q <<= 1;
                    // q |= 1;
                    nextQ = (regQ << 1) | 1;
                end

                nextCounter = regCounter - 1;
                nextPhase = (nextCounter == 0) ? PHASE_COMPENSATING : PHASE_PROCESSING;
            end
            else if (regPhase == PHASE_COMPENSATING) begin

                // -1(T),1 から通常のバイナリへのデコード
                // q の中では T は 0，1 は 1 として表現されている
                // 前者の寄与は-(~q) ，後者の寄与は q
                // 足し合わせると q + (-(~q)) == q + (q+1)
                // よって以下の式になる
                nextQ = (regQ << 1) + 1;
                nextR = regR;

                // 補正前商は最近接丸めで奇数に丸めた商
                // * 真の商が偶数の時，補正が必要
                // * 余りがある場合，ゼロへの丸めになるよう補正が必要
                if (regR == 0) begin
                    // 余りが 0 の時は補正はいらない
                end 
                else begin
                    if (regR == regD) begin
                        // 余りが除数と一致した場合，戻す
                        // 割り切れて真の商が偶数かつ除数が負の時に発生
                        nextR -= regD;
                        nextQ += 1;
                    end
                    else if (regR == -regD) begin
                        // 余りが除数の反転と一致した場合，戻す
                        // 割り切れて真の商が偶数かつ除数が正の時に発生
                        nextR += regD;
                        nextQ -= 1;
                    end
                    else if (regR[DIVIDER_WIDTH-1] != regZ[DIVIDER_WIDTH-1]) begin
                        // 除数と余りの符号が一致しない場合，補正する
                        if (regR[DIVIDER_WIDTH-1] != regD[DIVIDER_WIDTH-1]) begin
                            nextR += regD;
                            nextQ -= 1;
                        end
                        else begin
                            nextR -= regD;
                            nextQ += 1;
                        end
                    end
                end

                // Results on division by zero or overflow are difined by 
                // RISC-V specification.
                if (regD == 0) begin
                    // Division by zero
                    nextQ = -1;
                    nextR = regZ;
                end
                else if (regSigned && regZ == DATA_MINIMUM && regD == DATA_MINUS_ONE) begin 
                    // Sigined division can cause overflow
                    // ex. 8 bits signed division "-0x80 / -1 = 0x80"
                    // causes overflow because the resulst 0x80 > 0x7f
                    nextQ = regZ;
                    nextR = 0;
                end

                nextPhase = PHASE_FINISHED;
            end
            else begin  // PHASE_FINISHED
                nextPhase = regPhase;
            end
        end

        // Output results
        quotient = regQ;
        remainder = regR;

    end

endmodule : QuickDivider
