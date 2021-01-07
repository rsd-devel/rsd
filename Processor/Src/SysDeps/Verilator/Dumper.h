// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


// (Verification/Dumper.sv からの移植)

#ifndef SYSDEPS_VERILATOR_DUMP_H
#define SYSDEPS_VERILATOR_DUMP_H

#include "VerilatorHelper.h"
#include "VMain_Zynq_Wrapper.h"
#include "VMain_Zynq_Wrapper__Syms.h"    // To see all public symbols

#include <stdio.h>
#include <string>




// Kanata log dumper
class KanataDumper
{
private:
    static const int KS_NP = 0;
    static const int KS_IF = 1;
    static const int KS_PD = 2;
    static const int KS_ID = 3;
    static const int KS_RN = 4;
    static const int KS_DS = 5;
    static const int KS_SC = 6;
    static const int KS_IS = 7;
    static const int KS_RR = 8;
    static const int KS_EX = 9;
    static const int KS_MA = 10;
    static const int KS_MT = 11;
    static const int KS_RW = 12;
    static const int KS_WC = 13;
    static const int KS_CM = 14;

    FILE* m_file;
    int64_t m_cycle;
    int64_t m_retireID;

    // ヘルパ
    std::string FormatString(const char* fmt, ...)
    {
        va_list arg;
        va_start(arg, fmt);
        std::string dst;
        for(int size = 128;;size *= 2){
            char* buf = new char[size];
            
            va_list work_arg;
            va_copy(work_arg, arg);

            int writeSize = ::vsnprintf(buf, size, fmt, work_arg);
            bool success = (writeSize < size) && (writeSize != -1);

            va_end(work_arg);

            if(success)
                dst.assign(buf);

            delete[] buf;

            if(success)
                break;
        }
        va_end(arg);
        
        return dst;
    }

    std::string Bin2Str(int b, int length, bool zeroPadding)
    {
        std::string dst;
        bool start = zeroPadding;
        for (int i = length - 1; i >= 0; i--) {
            bool s = ((b >> i) & 1);
            if (start || s) {
                dst += s ? "1" : "0";
                start = true;
            }
        }
        if (!start) 
            dst = "0";
        return dst;
    }
public:
    KanataDumper()
    {
        m_file = nullptr;
        m_cycle = 0;
        m_retireID = 0;
    }

    // ファイルオープン
    void Open(const std::string& fileName)
    {
        m_cycle = -1;
        m_retireID = 1;
        m_file = fopen(fileName.c_str(), "w");
        if (!m_file) {
            printf("Could not open %s\n", fileName.c_str());
        }

        // ヘッダと初期状態の出力
        fprintf(m_file, "RSD_Kanata\t0000\n");

        // Output file format comments.
        fprintf(m_file, "#\tS:\n");
        fprintf(m_file, "#\tstage_id\tvalid\tstall\tclear\tiid\tmid\n");
        fprintf(m_file, "#\tL:\n");
        fprintf(m_file, "#\tiid\tmid\tpc\tcode\n");
    }

    // ファイルクローズ
    void Close(){
        if (m_file) {
            fclose(m_file);
            m_file = nullptr;
        }
    }

    // サイクルを一つ進める
    void ProceedCycle(){
        m_cycle++;
        fprintf(m_file, "C\t%11d\n", 1);
        fprintf(m_file, "#\tcycle:%0d\n", (int32_t)m_cycle);
    };

    void DumpStage(
        int stage, bool valid, bool stall, bool clear, int sid, int mid, const std::string& str){
        // Format: S    stage_id valid stall clear sid mid
        if(valid)
            fprintf(m_file, "S\t%0d\t%0d\t%0d\t%0d\t%0d\t%0d\t%s\n", stage, valid, stall, clear, sid, mid, str.c_str());
    }

// `ifdef RSD_FUNCTIONAL_SIMULATION
//         void DumpPreDecodeStage( int stage, bool valid, bool stall, bool clear, int sid, int mid, string str );
//             // Format: S    stage_id valid stall clear sid mid
//             if( valid )
//                 fprintf(m_file, "S\t%0d\t%0d\t%0d\t%0d\t%0d\t%0d\t%s\n", stage, valid, stall, clear, sid, mid, str );
//         }
// `endif

    void DumpInsnCode( int sid, int mid, AddrPath pc, InsnPath insn){
        fprintf(m_file, "L\t%0d\t%0d\t%08x\t%08x\n", sid, mid, pc, insn);
    }

    // 1サイクル分のダンプ動作を全て行う
    // 内部でProceedCycle/DumpStage/DumpInsnCodeを呼ぶ
    void DumpCycle(const DebugRegister& debugRegister){
        std::string str;

#ifdef RSD_FUNCTIONAL_SIMULATION
        std::string strAluCode;
        std::string strOpType;

#endif
        ProceedCycle();

        // FetchStage
        for (int i = 0; i < FETCH_WIDTH; i++) {
            DumpStage(
                KS_NP, // stage id
                debugRegister.npReg[i].valid, // valid
                debugRegister.npStagePipeCtrl.stall, // stall
                debugRegister.npStagePipeCtrl.clear, // clear
                debugRegister.npReg[i].sid, // sid
                0, // mid
                "" // comment
            );
        }

        for (int i = 0; i < FETCH_WIDTH; i++) {
            str = debugRegister.ifReg[i].icMiss ? "i-cache-miss\\n" : "";
            DumpStage(
                KS_IF, // stage id
                debugRegister.ifReg[i].valid, // valid
                debugRegister.ifStagePipeCtrl.stall &&
                    !debugRegister.ifReg[i].flush,     // stall
                debugRegister.ifStagePipeCtrl.clear || 
                    debugRegister.ifReg[i].flush,      // clear
                debugRegister.ifReg[i].sid, // sid
                0, // mid
                str // comment
            );
        }

        // PreDecodeStage
        for(int i = 0; i < DECODE_WIDTH; i++) {
#ifdef RSD_FUNCTIONAL_SIMULATION
            strAluCode = Bin2Str(debugRegister.pdReg[i].aluCode, 4, false);
            strOpType = Bin2Str(debugRegister.pdReg[i].opType, 3, false);

            DumpStage(
                KS_PD, // stage id
                debugRegister.pdReg[i].valid, // valid
                debugRegister.pdStagePipeCtrl.stall, // stall
                debugRegister.pdStagePipeCtrl.clear, // clear
                debugRegister.pdReg[i].sid, // sid
                0, // mid
                std::string() + "optype:0b" + strOpType + " ALU-code:0b" + strAluCode + "\\n"// comment
            );
#else
            DumpStage(
                KS_PD, // stage id
                debugRegister.pdReg[i].valid, // valid
                debugRegister.pdStagePipeCtrl.stall, // stall
                debugRegister.pdStagePipeCtrl.clear, // clear
                debugRegister.pdReg[i].sid, // sid
                0, // mid
                "" // comment
            );
#endif
        }

        // DecodeStage
        for (int i = 0; i < DECODE_WIDTH; i++) {
            str = "";
            if (debugRegister.idReg[i].undefined)
                str = "An undefined instruction is decoded.";
            if (debugRegister.idReg[i].unsupported)
                str = "An unsupported instruction is decoded.";
            if(debugRegister.idReg[i].flushTriggering)
                str = "Br-pred-miss-id\\n";

            DumpStage(
                KS_ID, // stage id
                debugRegister.idReg[i].valid, // valid
                debugRegister.idStagePipeCtrl.stall && !debugRegister.stallByDecodeStage, // stall
                debugRegister.idStagePipeCtrl.clear || debugRegister.idReg[i].flushed , // clear
                debugRegister.idReg[i].opId.sid, // sid
                debugRegister.idReg[i].opId.mid, // mid
                str // comment
            );
        }

        for (int i = 0; i < DECODE_WIDTH; i++) {
            if (debugRegister.idReg[i].valid) {
                DumpInsnCode(
                    debugRegister.idReg[i].opId.sid, // sid
                    debugRegister.idReg[i].opId.mid, // mid
                    debugRegister.idReg[i].pc,
                    debugRegister.idReg[i].insn
                );
            }
        }

        //
        // --- RenameStage
        //
        for (int i = 0; i < RENAME_WIDTH; i++) {
            DumpStage(
                KS_RN, // stage id
                debugRegister.rnReg[i].valid, // valid
                debugRegister.rnStagePipeCtrl.stall, // stall
                debugRegister.rnStagePipeCtrl.clear, // clear
                debugRegister.rnReg[i].opId.sid, // sid
                debugRegister.rnReg[i].opId.mid, // mid
                ""
            );
        }

        //
        // DispatchStage
        //
        for (int i = 0; i < DISPATCH_WIDTH; i++) {
            str = "";
#ifdef RSD_FUNCTIONAL_SIMULATION
            // Dump renaming information to 'str'.
            // Destination
            str = "map: ";
            if (debugRegister.dsReg[i].writeReg) {
                str += FormatString(
                    "r%0d(p%0d), ",
                    debugRegister.dsReg[i].logDstReg,
                    debugRegister.dsReg[i].phyDstReg
                );
            }
            str += " = ";

            // Sources
            if( debugRegister.dsReg[i].readRegA ) {
                str += FormatString(
                    "r%0d(p%0d), ",
                    debugRegister.dsReg[i].logSrcRegA,
                    debugRegister.dsReg[i].phySrcRegA
                );
            }
            if( debugRegister.dsReg[i].readRegB ) {
                str += FormatString(
                    "r%0d(p%0d), ",
                    debugRegister.dsReg[i].logSrcRegB,
                    debugRegister.dsReg[i].phySrcRegB
                );
            }

            // Previously mapped registers
            str += "\\nprev: ";

            if( debugRegister.dsReg[i].writeReg ) {
                str += FormatString(
                    "r%0d(p%0d), ",
                    debugRegister.dsReg[i].logDstReg,
                    debugRegister.dsReg[i].phyPrevDstReg
                );
            }

            // Issue queue allcation
            str += FormatString(
                "\\nIQ alloc: %0d ",
                debugRegister.dsReg[i].issueQueuePtr
            );
#endif

            DumpStage(
                KS_DS, // stage id
                debugRegister.dsReg[i].valid, // valid
                debugRegister.dsStagePipeCtrl.stall, // stall
                debugRegister.dsStagePipeCtrl.clear, // clear
                debugRegister.dsReg[i].opId.sid, // sid
                debugRegister.dsReg[i].opId.mid, // mid
                str // comment
            );
        }

        //
        // ScheduleStage
        // Scan all entries in the issue queue and output their state.
        //
        for (int i = 0; i < ISSUE_QUEUE_ENTRY_NUM; i++) {
            DumpStage(
                KS_SC, // stage id
                debugRegister.scheduler[i].valid, // valid
                debugRegister.backEndPipeCtrl.stall, // stall
                debugRegister.issueQueue[i].flush, // clear
                debugRegister.issueQueue[i].opId.sid, // sid
                debugRegister.issueQueue[i].opId.mid, // mid
                "" // comment
            );
        }

        //
        // IssueStage
        //
        for (int i = 0; i < INT_ISSUE_WIDTH; i++) {
            str = "";
            DumpStage(
                KS_IS, // stage id
                debugRegister.intIsReg[i].valid, // valid
                debugRegister.backEndPipeCtrl.stall, // stall
                debugRegister.intIsReg[i].flush, // clear
                debugRegister.intIsReg[i].opId.sid, // sid
                debugRegister.intIsReg[i].opId.mid, // mid
                str // comment
            );
        }
        for(int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) {
            str = "";
            DumpStage(
                KS_IS, // stage id
                debugRegister.complexIsReg[i].valid, // valid
                debugRegister.backEndPipeCtrl.stall, // stall
                debugRegister.complexIsReg[i].flush, // clear
                debugRegister.complexIsReg[i].opId.sid, // sid
                debugRegister.complexIsReg[i].opId.mid, // mid
                str // comment
            );
        }
        for(int i = 0; i < MEM_ISSUE_WIDTH; i++) {
            str = "";
            DumpStage(
                KS_IS, // stage id
                debugRegister.memIsReg[i].valid, // valid
                debugRegister.backEndPipeCtrl.stall, // stall
                debugRegister.memIsReg[i].flush, // clear
                debugRegister.memIsReg[i].opId.sid, // sid
                debugRegister.memIsReg[i].opId.mid, // mid
                str // comment
            );
        }


        //
        // RegisterReadStage
        //
        for(int i = 0; i < INT_ISSUE_WIDTH; i++) {
            DumpStage(
                KS_RR, // stage id
                debugRegister.intRrReg[i].valid, // valid
                debugRegister.backEndPipeCtrl.stall, // stall
                debugRegister.intRrReg[i].flush, // clear
                debugRegister.intRrReg[i].opId.sid, // sid
                debugRegister.intRrReg[i].opId.mid, // mid
                "" // comment
            );
        }
        for(int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) {
            DumpStage(
                KS_RR, // stage id
                debugRegister.complexRrReg[i].valid, // valid
                debugRegister.backEndPipeCtrl.stall, // stall
                debugRegister.complexRrReg[i].flush, // clear
                debugRegister.complexRrReg[i].opId.sid, // sid
                debugRegister.complexRrReg[i].opId.mid, // mid
                "" // comment
            );
        }
        for(int i = 0; i < MEM_ISSUE_WIDTH; i++) {
            DumpStage(
                KS_RR, // stage id
                debugRegister.memRrReg[i].valid, // valid
                debugRegister.backEndPipeCtrl.stall, // stall
                debugRegister.memRrReg[i].flush, // clear
                debugRegister.memRrReg[i].opId.sid, // sid
                debugRegister.memRrReg[i].opId.mid, // mid
                "" // comment
            );
        }

        //
        // ExecutionStage
        //
        for(int i = 0; i < INT_ISSUE_WIDTH; i++) {
            // Issue queue allcation
            str = "";
#ifdef RSD_FUNCTIONAL_SIMULATION
            str += FormatString(
                "\\nd:0x%0x = fu(a:0x%0x, b:0x%0x), alu:0b%s, op:0b%s", 
                debugRegister.intExReg[i].dataOut,
                debugRegister.intExReg[i].fuOpA,
                debugRegister.intExReg[i].fuOpB,
                Bin2Str(debugRegister.intExReg[i].aluCode, 4, true).c_str(),
                Bin2Str(debugRegister.intExReg[i].opType, 3, true).c_str()
            );
            if (debugRegister.intExReg[i].brPredMiss) {
                str += "\\nBr-pred-miss-ex";
            }
#endif
            DumpStage(
                KS_EX, // stage id
                debugRegister.intExReg[i].valid, // valid
                debugRegister.backEndPipeCtrl.stall, // stall
                debugRegister.intExReg[i].flush, // clear
                debugRegister.intExReg[i].opId.sid, // sid
                debugRegister.intExReg[i].opId.mid, // mid
                str
            );
        }

        for(int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) {
            for(int j = 0; j < COMPLEX_EXEC_STAGE_DEPTH; j++ ) {
                // Issue queue allcation
                str = "";
#ifdef RSD_FUNCTIONAL_SIMULATION
                if ( j == 0 ) {
                    // 複数段の実行ステージの最初に、オペランドを表示
                    str += FormatString(
                        "\\nfu(a:0x%0x, b:0x%0x)", 
                        debugRegister.complexExReg[i].fuOpA,
                        debugRegister.complexExReg[i].fuOpB
                    );
                }
#endif
                DumpStage(
                    KS_EX, // stage id
                    debugRegister.complexExReg[i].valid[j], // valid
                    debugRegister.backEndPipeCtrl.stall, // stall
                    debugRegister.complexExReg[i].flush, // clear
                    debugRegister.complexExReg[i].opId[j].sid, // sid
                    debugRegister.complexExReg[i].opId[j].mid, // mid
                    str
                );
            }
        }

        for(int i = 0; i < MEM_ISSUE_WIDTH; i++) {
            str = "";
            // Issue queue allcation
#ifdef RSD_FUNCTIONAL_SIMULATION
            if (debugRegister.memExReg[i].opType == MEM_MOP_TYPE_CSR) {
                str += FormatString(
                    "\\nd:0x%0x = csr[0x%0x], csr[0x%0x] <= fu(0x%0x)",
                    debugRegister.memExReg[i].addrOut,
                    debugRegister.memExReg[i].fuOpA,
                    debugRegister.memExReg[i].fuOpA,
                    debugRegister.memExReg[i].fuOpB
                );
            }
            else{
                str += FormatString(
                    "\\nd:0x%0x = fu(a:0x%0x, b:0x%0x)\\nop:0b%s, size:0b%s, signed:0b%s",
                    debugRegister.memExReg[i].addrOut,
                    debugRegister.memExReg[i].fuOpA,
                    debugRegister.memExReg[i].fuOpB,
                    Bin2Str(debugRegister.memExReg[i].opType, 3, true).c_str(),
                    Bin2Str(debugRegister.memExReg[i].size, 2, true).c_str(),
                    Bin2Str(debugRegister.memExReg[i].isSigned, 1, true).c_str()
                );
            }
#endif
            DumpStage(
                KS_EX, // stage id
                debugRegister.memExReg[i].valid, // valid
                debugRegister.backEndPipeCtrl.stall, // stall
                debugRegister.memExReg[i].flush, // clear
                debugRegister.memExReg[i].opId.sid, // sid
                debugRegister.memExReg[i].opId.mid, // mid
                str
            );
        }

        //
        // --- Memory Tag Access Stage
        //
        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) {
            str = "";
#ifdef RSD_FUNCTIONAL_SIMULATION
                // Memory access
                if (debugRegister.mtReg[i].executeLoad) {
                    str += FormatString(
                        "\\n = load([#0x%0x])",
                        debugRegister.mtReg[i].executedLoadAddr
                    );
                    if (debugRegister.mtReg[i].mshrAllocated) {
                        str += FormatString(
                            "\\nD$-miss. MSHR alloc: %0d",
                            debugRegister.mtReg[i].mshrEntryID
                        );
                    }
                    else if (debugRegister.mtReg[i].mshrHit) {
                        str += FormatString(
                            "\\nMSHR hit: %0d",
                            debugRegister.mtReg[i].mshrEntryID
                        );
                    }
                }
                if (debugRegister.mtReg[i].executeStore) {
                    str += FormatString(
                        "\\nstore(#0x%0x, [#0x%0x])\\n",
                        debugRegister.mtReg[i].executedStoreData,
                        debugRegister.mtReg[i].executedStoreAddr
                    );
                }
#endif

            DumpStage(
                KS_MT,  // stage id
                debugRegister.mtReg[i].valid, // valid
                debugRegister.backEndPipeCtrl.stall, // stall
                debugRegister.mtReg[i].flush, // clear
                debugRegister.mtReg[i].opId.sid, // sid
                debugRegister.mtReg[i].opId.mid, // mid
                str
            );
        }

        //
        // --- Memory Access Stage
        //
        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) {
            str = "";
#ifdef RSD_FUNCTIONAL_SIMULATION
                // Memory access
                if( debugRegister.maReg[i].executeLoad ) {
                    str += FormatString("\\n#0x%0x = load()",
                        debugRegister.maReg[i].executedLoadData
                    );
                }
#endif

            DumpStage(
                KS_MA,//KS_MA, // stage id
                debugRegister.maReg[i].valid, // valid
                debugRegister.backEndPipeCtrl.stall, // stall
                debugRegister.maReg[i].flush, // clear
                debugRegister.maReg[i].opId.sid, // sid
                debugRegister.maReg[i].opId.mid, // mid
                str
            );
        }

        //
        // --- Register Write stage
        //
        for(int i = 0; i < INT_ISSUE_WIDTH; i++) {
            DumpStage(
                KS_RW, // stage id
                debugRegister.intRwReg[i].valid, // valid
                debugRegister.backEndPipeCtrl.stall, // stall
                debugRegister.intRwReg[i].flush, // clear
                debugRegister.intRwReg[i].opId.sid, // sid
                debugRegister.intRwReg[i].opId.mid, // mid
                ""
            );
        }
        for(int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) {
            DumpStage(
                KS_RW, // stage id
                debugRegister.complexRwReg[i].valid, // valid
                debugRegister.backEndPipeCtrl.stall, // stall
                debugRegister.complexRwReg[i].flush, // clear
                debugRegister.complexRwReg[i].opId.sid, // sid
                debugRegister.complexRwReg[i].opId.mid, // mid
                ""
            );
        }
        for(int i = 0; i < MEM_ISSUE_WIDTH; i++) {
            DumpStage(
                KS_RW, // stage id
                debugRegister.memRwReg[i].valid, // valid
                debugRegister.backEndPipeCtrl.stall, // stall
                debugRegister.memRwReg[i].flush, // clear
                debugRegister.memRwReg[i].opId.sid, // sid
                debugRegister.memRwReg[i].opId.mid, // mid
                ""
            );
        }

        //
        // --- Commit stage
        //
        // Dump commitment information to 'str'.
        for (int i = 0; i < COMMIT_WIDTH; i++) {
            str = "";
            #ifdef RSD_FUNCTIONAL_SIMULATION
                str = "\\nrelease: ";
                if( debugRegister.cmReg[i].releaseReg ) {
                    str += FormatString(
                        "p%0d, ",
                        debugRegister.cmReg[i].phyReleasedReg
                    );
                }
            #endif
            if ( debugRegister.cmReg[i].flush ) {
                DumpStage(
                    KS_WC, // stage id
                    debugRegister.cmReg[i].flush, // valid
                    false, // stall
                    true, // clear
                    debugRegister.cmReg[i].opId.sid, // sid
                    debugRegister.cmReg[i].opId.mid, // mid
                    str // comment
                );
            }
            else if ( debugRegister.cmReg[i].commit ) {
                DumpStage(
                    KS_CM, // stage id
                    debugRegister.cmReg[i].commit, // valid
                    false, // stall
                    false, // clear
                    debugRegister.cmReg[i].opId.sid, // sid
                    debugRegister.cmReg[i].opId.mid, // mid
                    str // comment
                );
            }
        }

    }

};


// シリアル出力をファイルに保存する
class SerialDumper{
private:
    FILE* m_file;
    bool m_outToSTDOUT;
public:

    SerialDumper(bool outToSTDOUT)
    {
        m_file = nullptr;
        m_outToSTDOUT = outToSTDOUT;
    }
    // ファイルオープン
    void Open(const std::string& fileName){
        m_file = fopen(fileName.c_str(), "wb");
        if (!m_file) {
            printf("Could not open %s\n", fileName.c_str());
        }
    }

    // ファイルクローズ
    void Close()
    {
        if (m_file) {
            fclose(m_file);
            m_file = nullptr;
        }
    }

    // 毎サイクル呼ぶ必要のある関数
    void CheckSignal(bool we, SerialDataPath data)
    {
        // 書込データがあったらm_strに追加する
        // (data != 0xff) = 0 は verilog 側のコードと仕様をあわせるため
        // 終端文字はださない
        if (we && (data & 0xff) != 0 && m_file) {
            //fprintf(m_file, "%c", (char)data);
            fwrite(&data, 1, 1, m_file);
        }
        if (m_outToSTDOUT && we) {
            printf("%c", data);
            fflush(stdout);
        }
    }

};


// 論理レジスタの値を、hexファイルに出力する。
// シミュレーション終了時に一度だけ呼び出すことを意図している。
class RegisterFileHexDumper{
private:
    FILE* m_file;

public:
    RegisterFileHexDumper()
    {
        m_file = nullptr;
    }

    // ファイルオープン
    void Open(const std::string& fileName){
        m_file = fopen(fileName.c_str(), "w");
        if (!m_file) {
            printf("Could not open %s\n", fileName.c_str());
        }
    }

    // ファイルクローズ
    void Close()
    {
        if (m_file) {
            fclose(m_file);
            m_file = nullptr;
        }
    }

    void Dump(AddrPath pc, DataPath* regData)
    {
        // Dump logical register R0-R31
        for (int i = 0; i < LSCALAR_NUM; i++) {
            fprintf(m_file, "0x%08x\n", regData[i]);
        }

        // Dump PC
        fprintf(m_file, "0x%08x\n", pc);
    }
};

// 論理レジスタの値を、csvファイルに出力する。
// 1命令コミットするごとに呼び出すことを意図している。
// 将来的には、アーキテクチャステート全体のダンプを可能にしたい。
class RegisterFileCSV_Dumper
{
public:
    RegisterFileCSV_Dumper()
    {
        m_file = nullptr;
        m_cycle = -1;
    }

    // ファイルオープン
    void Open(const std::string& fileName){
        m_file = fopen(fileName.c_str(), "w");
        if (!m_file) {
            printf("Could not open %s\n", fileName.c_str());
        }
        m_cycle = -1;
    }

    // ファイルクローズ
    void Close()
    {
        if (m_file){
            fclose(m_file);
            m_file = nullptr;
        }
    }

    // サイクルを一つ進める
    void ProceedCycle()
    {
        m_cycle++;
    }

    void Dump(
        AddrPath pc,
        DataPath* regData
    )
    {
        // dump cycle, PC
        //fprintf(m_file, "%11d,", m_cycle);
        fprintf(m_file, "0x%08x", pc);

        // Dump logical register R0-R15.
        for(int i = 0; i < LSCALAR_NUM; i++) {
            fprintf(m_file, ",0x%08x", regData[i]);
        }

        fprintf(m_file, "\n");
    }

private:
    FILE* m_file;
    int32_t m_cycle;
};

#endif

