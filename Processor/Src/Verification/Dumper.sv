// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


package DumperTypes;
    import BasicTypes::*;
    import CacheSystemTypes::*;
    import PipelineTypes::*;
    import RenameLogicTypes::*;
    import SchedulerTypes::*;
    import ActiveListIndexTypes::*;
    import MicroOpTypes::*;
    import LoadStoreUnitTypes::*;
    import IO_UnitTypes::*;
    import DebugTypes::*;

    localparam KS_NP = 0;
    localparam KS_IF = 1;
    localparam KS_PD = 2;
    localparam KS_ID = 3;
    localparam KS_RN = 4;
    localparam KS_DS = 5;
    localparam KS_SC = 6;
    localparam KS_IS = 7;
    localparam KS_RR = 8;
    localparam KS_EX = 9;
    localparam KS_MA = 10;
    localparam KS_MT = 11;
    localparam KS_RW = 12;
    localparam KS_WC = 13;
    localparam KS_CM = 14;


    // Kanata log dumper
    class KanataDumper;
        integer m_file;
        integer m_cycle;
        integer m_retireID;

        // ファイルオープン
        function automatic void Open( string fileName );
            m_cycle = -1;
            m_retireID = 1;
            m_file  = $fopen( fileName, "w" );

            // ヘッダと初期状態の出力
            $fwrite( m_file, "RSD_Kanata\t0000\n" );

            // Output file format comments.
            $fwrite( m_file, "#\tS:\n" );
            $fwrite( m_file, "#\tstage_id\tvalid\tstall\tclear\tiid\tmid\n" );
            $fwrite( m_file, "#\tL:\n" );
            $fwrite( m_file, "#\tiid\tmid\tpc\tcode\n" );
        endfunction

        // ファイルクローズ
        function automatic void Close();
            $fclose( m_file );
        endfunction

        // サイクルを一つ進める
        function automatic void ProceedCycle();
            m_cycle++;
            $fwrite( m_file, "C\t%d\n", 1 );
            $fwrite( m_file, "#\tcycle:%0d\n", m_cycle );
        endfunction

        function automatic void DumpStage( integer stage, logic valid, logic stall, logic clear, integer sid, integer mid, string str );
            // Format: S    stage_id valid stall clear sid mid
            if( valid )
                $fwrite( m_file, "S\t%0d\t%0d\t%0d\t%0d\t%0d\t%0d\t%s\n", stage, valid, stall, clear, sid, mid, str );
        endfunction

// `ifdef RSD_FUNCTIONAL_SIMULATION
//         function automatic void DumpPreDecodeStage( integer stage, logic valid, logic stall, logic clear, integer sid, integer mid, string str );
//             // Format: S    stage_id valid stall clear sid mid
//             if( valid )
//                 $fwrite( m_file, "S\t%0d\t%0d\t%0d\t%0d\t%0d\t%0d\t%s\n", stage, valid, stall, clear, sid, mid, str );
//         endfunction
// `endif

        function automatic void DumpInsnCode( integer sid, integer mid, AddrPath pc, InsnPath insn );
            $fwrite( m_file, "L\t%0d\t%0d\t%x\t%x\n", sid, mid, pc, insn );
        endfunction

        // 1サイクル分のダンプ動作を全て行う
        // 内部でProceedCycle/DumpStage/DumpInsnCodeを呼ぶ
        function automatic void DumpCycle( DebugRegister debugRegister );
            string str;

`ifdef RSD_FUNCTIONAL_SIMULATION
            string strAluCode;
            string strOpType;
`endif

            this.ProceedCycle();

            // FetchStage
            for ( int i = 0; i < FETCH_WIDTH; i++ ) begin
                this.DumpStage(
                    KS_NP, // stage id
                    debugRegister.npReg[i].valid, // valid
                    debugRegister.npStagePipeCtrl.stall, // stall
                    debugRegister.npStagePipeCtrl.clear, // clear
                    debugRegister.npReg[i].sid, // sid
                    0, // mid
                    "" // comment
                );
            end
            for ( int i = 0; i < FETCH_WIDTH; i++ ) begin
                str =debugRegister.ifReg[i].icMiss ? "i-cache-miss\\n" : "";
                this.DumpStage(
                    KS_IF, // stage id
                    debugRegister.ifReg[i].valid, // valid
                    debugRegister.ifStagePipeCtrl.stall &&
                        !debugRegister.ifReg[i].flush, // stall
                    debugRegister.ifStagePipeCtrl.clear || 
                        debugRegister.ifReg[i].flush, // clear
                    debugRegister.ifReg[i].sid, // sid
                    0, // mid
                    str // comment
                );
            end

            // PreDecodeStage
            for ( int i = 0; i < DECODE_WIDTH; i++ ) begin
`ifdef RSD_FUNCTIONAL_SIMULATION
                strAluCode.bintoa(debugRegister.pdReg[i].aluCode);
                strOpType.bintoa(debugRegister.pdReg[i].opType);

                this.DumpStage(
                    KS_PD, // stage id
                    debugRegister.pdReg[i].valid, // valid
                    debugRegister.pdStagePipeCtrl.stall, // stall
                    debugRegister.pdStagePipeCtrl.clear, // clear
                    debugRegister.pdReg[i].sid, // sid
                    0, // mid
                    {"optype:0b", strOpType, " ALU-code:0b", strAluCode, "\\n"} // comment
                );
`else
                this.DumpStage(
                    KS_PD, // stage id
                    debugRegister.pdReg[i].valid, // valid
                    debugRegister.pdStagePipeCtrl.stall, // stall
                    debugRegister.pdStagePipeCtrl.clear, // clear
                    debugRegister.pdReg[i].sid, // sid
                    0, // mid
                    "" // comment
                );
`endif
            end

            // DecodeStage
            for( int i = 0; i < DECODE_WIDTH; i++ ) begin
                str = "";
                if( debugRegister.idReg[i].undefined )
                    str = "An undefined instruction is decoded.";
                if( debugRegister.idReg[i].unsupported )
                    str = "An unsupported instruction is decoded.";
                if(debugRegister.idReg[i].flushTriggering)
                    str = "Br-pred-miss-id\\n";

                this.DumpStage(
                    KS_ID, // stage id
                    debugRegister.idReg[i].valid, // valid
                    debugRegister.idStagePipeCtrl.stall && !debugRegister.stallByDecodeStage, // stall
                    debugRegister.idStagePipeCtrl.clear || debugRegister.idReg[i].flushed , // clear
                    debugRegister.idReg[i].opId.sid, // sid
                    debugRegister.idReg[i].opId.mid, // mid
                    str // comment
                );

            end

            for ( int i = 0; i < DECODE_WIDTH; i++ ) begin
                if( debugRegister.idReg[i].valid ) begin
                    this.DumpInsnCode(
                        debugRegister.idReg[i].opId.sid, // sid
                        debugRegister.idReg[i].opId.mid, // mid
                        debugRegister.idReg[i].pc,
                        debugRegister.idReg[i].insn
                    );
                end
            end

            //
            // --- RenameStage
            //
            for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
                this.DumpStage(
                    KS_RN, // stage id
                    debugRegister.rnReg[i].valid, // valid
                    debugRegister.rnStagePipeCtrl.stall, // stall
                    debugRegister.rnStagePipeCtrl.clear, // clear
                    debugRegister.rnReg[i].opId.sid, // sid
                    debugRegister.rnReg[i].opId.mid, // mid
                    ""
                );
            end

            //
            // DispatchStage
            //
            for ( int i = 0; i < DISPATCH_WIDTH; i++ ) begin
                str = "";
`ifdef RSD_FUNCTIONAL_SIMULATION
                // Dump renaming information to 'str'.
                // Destination
                str = "map: ";
                if( debugRegister.dsReg[i].writeReg ) begin
                    $sformat( str, "%sr%0d(p%0d), ",
                        str,
                        debugRegister.dsReg[i].logDstReg,
                        debugRegister.dsReg[i].phyDstReg
                    );
                end
                $sformat( str, "%s = ", str );

                // Sources
                if( debugRegister.dsReg[i].readRegA ) begin
                    $sformat( str, "%sr%0d(p%0d), ",
                        str,
                        debugRegister.dsReg[i].logSrcRegA,
                        debugRegister.dsReg[i].phySrcRegA
                    );
                end
                if( debugRegister.dsReg[i].readRegB ) begin
                    $sformat( str, "%sr%0d(p%0d), ",
                        str,
                        debugRegister.dsReg[i].logSrcRegB,
                        debugRegister.dsReg[i].phySrcRegB
                    );
                end

                // Previously mapped registers
                $sformat( str, "%s\\nprev: ", str );

                if( debugRegister.dsReg[i].writeReg ) begin
                    $sformat( str, "%sr%0d(p%0d), ",
                        str,
                        debugRegister.dsReg[i].logDstReg,
                        debugRegister.dsReg[i].phyPrevDstReg
                    );
                end

                // Active list allocation
                $sformat( str, "%s\\nAL alloc: %0d ",
                    str,
                    debugRegister.dsReg[i].activeListPtr
                );
                // Issue queue allocation
                $sformat( str, "%s\\nIQ alloc: %0d ",
                    str,
                    debugRegister.dsReg[i].issueQueuePtr
                );
`endif

                this.DumpStage(
                    KS_DS, // stage id
                    debugRegister.dsReg[i].valid, // valid
                    debugRegister.dsStagePipeCtrl.stall, // stall
                    debugRegister.dsStagePipeCtrl.clear, // clear
                    debugRegister.dsReg[i].opId.sid, // sid
                    debugRegister.dsReg[i].opId.mid, // mid
                    str // comment
                );
            end

            //
            // ScheduleStage
            // Scan all entries in the issue queue and output their state.
            //
            for( int i = 0; i < ISSUE_QUEUE_ENTRY_NUM; i++ ) begin
                this.DumpStage(
                    KS_SC, // stage id
                    debugRegister.scheduler[i].valid, // valid
                    debugRegister.backEndPipeCtrl.stall, // stall
                    debugRegister.issueQueue[i].flush, // clear
                    debugRegister.issueQueue[i].opId.sid, // sid
                    debugRegister.issueQueue[i].opId.mid, // mid
                    "" // comment
                );
            end

            //
            // IssueStage
            //
            for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
                str = "";
                this.DumpStage(
                    KS_IS, // stage id
                    debugRegister.intIsReg[i].valid, // valid
                    debugRegister.backEndPipeCtrl.stall, // stall
                    debugRegister.intIsReg[i].flush, // clear
                    debugRegister.intIsReg[i].opId.sid, // sid
                    debugRegister.intIsReg[i].opId.mid, // mid
                    str // comment
                );
            end
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            for ( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
                str = "";
                this.DumpStage(
                    KS_IS, // stage id
                    debugRegister.complexIsReg[i].valid, // valid
                    debugRegister.backEndPipeCtrl.stall, // stall
                    debugRegister.complexIsReg[i].flush, // clear
                    debugRegister.complexIsReg[i].opId.sid, // sid
                    debugRegister.complexIsReg[i].opId.mid, // mid
                    str // comment
                );
            end
`endif
            for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
                str = "";
                this.DumpStage(
                    KS_IS, // stage id
                    debugRegister.memIsReg[i].valid, // valid
                    debugRegister.backEndPipeCtrl.stall, // stall
                    debugRegister.memIsReg[i].flush, // clear
                    debugRegister.memIsReg[i].opId.sid, // sid
                    debugRegister.memIsReg[i].opId.mid, // mid
                    str // comment
                );
            end


            //
            // RegisterReadStage
            //
            for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
                this.DumpStage(
                    KS_RR, // stage id
                    debugRegister.intRrReg[i].valid, // valid
                    debugRegister.backEndPipeCtrl.stall, // stall
                    debugRegister.intRrReg[i].flush, // clear
                    debugRegister.intRrReg[i].opId.sid, // sid
                    debugRegister.intRrReg[i].opId.mid, // mid
                    "" // comment
                );
            end
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            for ( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
                this.DumpStage(
                    KS_RR, // stage id
                    debugRegister.complexRrReg[i].valid, // valid
                    debugRegister.backEndPipeCtrl.stall, // stall
                    debugRegister.complexRrReg[i].flush, // clear
                    debugRegister.complexRrReg[i].opId.sid, // sid
                    debugRegister.complexRrReg[i].opId.mid, // mid
                    "" // comment
                );
            end
`endif
            for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
                this.DumpStage(
                    KS_RR, // stage id
                    debugRegister.memRrReg[i].valid, // valid
                    debugRegister.backEndPipeCtrl.stall, // stall
                    debugRegister.memRrReg[i].flush, // clear
                    debugRegister.memRrReg[i].opId.sid, // sid
                    debugRegister.memRrReg[i].opId.mid, // mid
                    "" // comment
                );
            end

            //
            // ExecutionStage
            //
            for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
                // Issue queue allocation
                str = "";
`ifdef RSD_FUNCTIONAL_SIMULATION
                $sformat( str, "%s\\nd:0x%0x = fu(a:0x%0x, b:0x%0x), alu:0b%b, op:0b%b", str,
                    debugRegister.intExReg[i].dataOut,
                    debugRegister.intExReg[i].fuOpA,
                    debugRegister.intExReg[i].fuOpB,
                    debugRegister.intExReg[i].aluCode,
                    debugRegister.intExReg[i].opType
                );
                if (debugRegister.intExReg[i].brPredMiss) begin
                    $sformat(str, "%s\\nBr-pred-miss-ex", str);
                end
`endif
                this.DumpStage(
                    KS_EX, // stage id
                    debugRegister.intExReg[i].valid, // valid
                    debugRegister.backEndPipeCtrl.stall, // stall
                    debugRegister.intExReg[i].flush, // clear
                    debugRegister.intExReg[i].opId.sid, // sid
                    debugRegister.intExReg[i].opId.mid, // mid
                    str
                );
            end

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            for ( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
                for ( int j = 0; j < COMPLEX_EXEC_STAGE_DEPTH; j++ ) begin
                    // Issue queue allocation
                    str = "";
`ifdef RSD_FUNCTIONAL_SIMULATION
                    if ( j == 0 ) begin
                        // 複数段の実行ステージの最初に、オペランドを表示
                        $sformat( str, "%s\\nfu(a:0x%0x, b:0x%0x)", str,
                            debugRegister.complexExReg[i].fuOpA,
                            debugRegister.complexExReg[i].fuOpB
                        );
                    end
`endif
                    this.DumpStage(
                        KS_EX, // stage id
                        debugRegister.complexExReg[i].valid[j], // valid
                        debugRegister.backEndPipeCtrl.stall, // stall
                        debugRegister.complexExReg[i].flush[j], // clear
                        debugRegister.complexExReg[i].opId[j].sid, // sid
                        debugRegister.complexExReg[i].opId[j].mid, // mid
                        str
                    );
                end
            end
`endif
            for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
                str = "";
                // Issue queue allocation
`ifdef RSD_FUNCTIONAL_SIMULATION
                if (debugRegister.memExReg[i].opType == MEM_MOP_TYPE_CSR) begin
                    $sformat( str, "%s\\nd:0x%0x = csr[0x%0x], csr[0x%0x] <= fu(0x%0x)", str,
                        debugRegister.memExReg[i].addrOut,
                        debugRegister.memExReg[i].fuOpA,
                        debugRegister.memExReg[i].fuOpA,
                        debugRegister.memExReg[i].fuOpB
                    );
                end
                else begin
                    $sformat( str, "%s\\nd:0x%0x = fu(a:0x%0x, b:0x%0x)\\nop:0b%b, size:0b%b, signed:0b%b",
                        str,
                        debugRegister.memExReg[i].addrOut,
                        debugRegister.memExReg[i].fuOpA,
                        debugRegister.memExReg[i].fuOpB,
                        debugRegister.memExReg[i].opType,
                        debugRegister.memExReg[i].size,
                        debugRegister.memExReg[i].isSigned
                    );
                end
`endif
                this.DumpStage(
                    KS_EX, // stage id
                    debugRegister.memExReg[i].valid, // valid
                    debugRegister.backEndPipeCtrl.stall, // stall
                    debugRegister.memExReg[i].flush, // clear
                    debugRegister.memExReg[i].opId.sid, // sid
                    debugRegister.memExReg[i].opId.mid, // mid
                    str
                );
            end

            //
            // --- Memory Tag Access Stage
            //
            for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
                str = "";
`ifdef RSD_FUNCTIONAL_SIMULATION
                    // Memory access
                    if (debugRegister.mtReg[i].executeLoad) begin
                        $sformat( str, "%s\\n = load([#0x%0x])",
                            str,
                            debugRegister.mtReg[i].executedLoadAddr,
                        );
                        if (debugRegister.mtReg[i].mshrAllocated) begin
                            $sformat( str, 
                                "%s\\nD$-miss. MSHR alloc: %0d",
                                str,
                                debugRegister.mtReg[i].mshrEntryID
                            );
                        end
                        else if (debugRegister.mtReg[i].mshrHit) begin
                            $sformat( str, 
                                "%s\\nMSHR hit: %0d",
                                str,
                                debugRegister.mtReg[i].mshrEntryID
                            );
                        end
                    end
                    if (debugRegister.mtReg[i].executeStore) begin
                        $sformat( str, "%s\\nstore(#0x%0x, [#0x%0x])\\n", str,
                            debugRegister.mtReg[i].executedStoreData,
                            debugRegister.mtReg[i].executedStoreAddr
                        );
                    end
`endif

                this.DumpStage(
                    KS_MT,  // stage id
                    debugRegister.mtReg[i].valid, // valid
                    debugRegister.backEndPipeCtrl.stall, // stall
                    debugRegister.mtReg[i].flush, // clear
                    debugRegister.mtReg[i].opId.sid, // sid
                    debugRegister.mtReg[i].opId.mid, // mid
                    str
                );
            end

            //
            // --- Memory Access Stage
            //
            for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
                str = "";
`ifdef RSD_FUNCTIONAL_SIMULATION
                    // Memory access
                    if( debugRegister.maReg[i].executeLoad ) begin
                        $sformat( str, "%s\\n#0x%0x = load()",
                            str,
                            debugRegister.maReg[i].executedLoadData
                        );
                        /*
                        $sformat( str, "%s\\n#0x%0x (vec:%0x) = load()",
                            str,
                            debugRegister.maReg[i].executedLoadData,
                            debugRegister.maReg[i].executedLoadVectorData
                        );
                        */
                    end
`endif

                this.DumpStage(
                    KS_MA,//KS_MA, // stage id
                    debugRegister.maReg[i].valid, // valid
                    debugRegister.backEndPipeCtrl.stall, // stall
                    debugRegister.maReg[i].flush, // clear
                    debugRegister.maReg[i].opId.sid, // sid
                    debugRegister.maReg[i].opId.mid, // mid
                    str
                );
            end

            //
            // --- Register Write stage
            //
            for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
                this.DumpStage(
                    KS_RW, // stage id
                    debugRegister.intRwReg[i].valid, // valid
                    debugRegister.backEndPipeCtrl.stall, // stall
                    debugRegister.intRwReg[i].flush, // clear
                    debugRegister.intRwReg[i].opId.sid, // sid
                    debugRegister.intRwReg[i].opId.mid, // mid
                    ""
                );
            end
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            for ( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
                this.DumpStage(
                    KS_RW, // stage id
                    debugRegister.complexRwReg[i].valid, // valid
                    debugRegister.backEndPipeCtrl.stall, // stall
                    debugRegister.complexRwReg[i].flush, // clear
                    debugRegister.complexRwReg[i].opId.sid, // sid
                    debugRegister.complexRwReg[i].opId.mid, // mid
                    ""
                );
            end
`endif
            for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
                this.DumpStage(
                    KS_RW, // stage id
                    debugRegister.memRwReg[i].valid, // valid
                    debugRegister.backEndPipeCtrl.stall, // stall
                    debugRegister.memRwReg[i].flush, // clear
                    debugRegister.memRwReg[i].opId.sid, // sid
                    debugRegister.memRwReg[i].opId.mid, // mid
                    ""
                );
            end

            //
            // --- Commit stage
            //
            // Dump commitment information to 'str'.
            for ( int i = 0; i < COMMIT_WIDTH; i++ ) begin
                str = "";
                `ifdef RSD_FUNCTIONAL_SIMULATION
                    str = "\\nrelease: ";
                    if( debugRegister.cmReg[i].releaseReg ) begin
                        $sformat( str, "%sp%0d, ",
                            str,
                            debugRegister.cmReg[i].phyReleasedReg
                        );
                    end
                `endif
                if ( debugRegister.cmReg[i].flush ) begin
                    this.DumpStage(
                        KS_WC, // stage id
                        debugRegister.cmReg[i].flush, // valid
                        FALSE, // stall
                        TRUE, // clear
                        debugRegister.cmReg[i].opId.sid, // sid
                        debugRegister.cmReg[i].opId.mid, // mid
                        str // comment
                    );
                end
                else if ( debugRegister.cmReg[i].commit ) begin
                    this.DumpStage(
                        KS_CM, // stage id
                        debugRegister.cmReg[i].commit, // valid
                        FALSE, // stall
                        FALSE, // clear
                        debugRegister.cmReg[i].opId.sid, // sid
                        debugRegister.cmReg[i].opId.mid, // mid
                        str // comment
                    );
                end
            end

        endfunction

    endclass;

    // シリアル出力をファイルに保存する
    class SerialDumper;
        integer m_file;
        string m_str;

        // クラス作成直後に呼ぶ必要のある関数
        function automatic void Init();
            m_str = "";
        endfunction

        // 毎サイクル呼ぶ必要のある関数
        function automatic void CheckSignal( logic we, SerialDataPath data, integer showOutput);
            // 書込データがあったらm_strに追加する
            if (we) begin
                $sformat( m_str, "%s%c", m_str, data );
                if (showOutput) begin
                    $write("%c", data);
                end
            end
        endfunction

        // 指定されたファイルに書込
        function automatic void DumpToFile( string fileName );
            m_file = $fopen( fileName, "w" );
            $fwrite( m_file, "%s", m_str );
            $fclose( m_file );
        endfunction

    endclass;


    // 論理レジスタの値を、hexファイルに出力する。
    // シミュレーション終了時に一度だけ呼び出すことを意図している。
    class RegisterFileHexDumper;
        integer m_file;

        // ファイルオープン
        function automatic void Open( string fileName );
            m_file  = $fopen( fileName, "w" );
        endfunction

        // ファイルクローズ
        function automatic void Close();
            $fclose( m_file );
        endfunction

        function automatic void Dump(
            input AddrPath pc,
            input DataPath regData[ LSCALAR_NUM ]
        );
            // Dump logical register R0-R31
            for( int i = 0; i < LSCALAR_NUM; i++ ) begin
                $fdisplay( m_file, "0x%08h", regData[i] );
            end

            // Dump PC
            $fdisplay( m_file, "0x%08h", pc );
        endfunction
    endclass;


    // 論理レジスタの値を、csvファイルに出力する。
    // 1命令コミットするごとに呼び出すことを意図している。
    // 将来的には、アーキテクチャステート全体のダンプを可能にしたい。
    class RegisterFileCSV_Dumper;
        integer m_file;
        integer m_cycle;

        // ファイルオープン
        function automatic void Open( string fileName );
            m_file  = $fopen( fileName, "w" );
            m_cycle = -1;
        endfunction

        // ファイルクローズ
        function automatic void Close();
            $fclose( m_file );
        endfunction

        // サイクルを一つ進める
        function automatic void ProceedCycle();
            m_cycle++;
        endfunction

        function automatic void Dump(
            input AddrPath pc,
            input DataPath regData[ LSCALAR_NUM ]
        );

            // dump cycle, PC
            $fwrite( m_file, "%d,", m_cycle );
            $fwrite( m_file, "0x%04h,", pc );

            // Dump logical register R0-R15.
            for( int i = 0; i < LSCALAR_NUM; i++ ) begin
                $fwrite( m_file, "0x%-h,", regData[i] );
            end

            $fwrite( m_file, "\n" );
        endfunction
    endclass;

endpackage

