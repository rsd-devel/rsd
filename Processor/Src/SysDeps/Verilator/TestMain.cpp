#include "VMain_Zynq_Wrapper.h"
#include "VMain_Zynq_Wrapper__Syms.h"    // To see all public symbols

#include "VerilatorHelper.h"
#include "Dumper.h"

#include <verilated.h>    // Defines common routines
#include <verilated_vcd_c.h>

#include <stdexcept>
#include <regex>
#include <fstream>
#include <iostream>


using namespace std;

uint64_t main_time = 0;     // Current simulation time

double sc_time_stamp () {       // Called by $time in Verilog
    return main_time;
}

int GetCommittedRegisterValue(
    VMain_Zynq_Wrapper* top,
    int commitNumInThisCycle,
    DataPath* regData
){
    auto* core = top->Main_Zynq_Wrapper->main->core;
    auto* helper = top->VerilatorHelper;
    static const int LSCALAR_NUM = helper->LSCALAR_NUM;

    typeof (core->retirementRMT->regRMT->debugValue) phyRegNum;

    // Copy RMT to local variable.
    for (int i = 0; i < LREG_NUM; i++) {
        phyRegNum[i] = core->retirementRMT->regRMT->debugValue[i];
    }

    // Update RRMT
    //ActiveListIndexPath alHeadPtr;
    auto alHeadPtr = core->activeList->headPtr;
    for (int i = 0; i < commitNumInThisCycle; i++) {
        // ActiveListEntry alHead;
        const auto& alHead = core->activeList->activeList->debugValue[alHeadPtr];
        if (helper->ActiveListEntry_writeReg(alHead)) {
            phyRegNum[helper->ActiveListEntry_logDstRegNum(alHead)] = helper->ActiveListEntry_phyDstRegNum_regNum(alHead);
        }
        alHeadPtr++;
    }

    // Get regData
    for(int i = 0; i < LSCALAR_NUM; i++) {
        regData[i] = core->registerFile->phyReg->debugValue[phyRegNum[i]];
    }
#ifdef RSD_MARCH_FP_PIPE
    for(int i = LSCALAR_NUM; i < LSCALAR_NUM + LSCALAR_FP_NUM; i++) {
        regData[i] = core->registerFile->phyFPReg->debugValue[phyRegNum[i]];
    }
#endif
    
    return 0;
}


int main(int argc, char** argv) {

    // Initialize verilated modules
    Verilated::commandArgs(argc, argv);   // Remember args

    auto *top = new VMain_Zynq_Wrapper();
    auto* core = top->Main_Zynq_Wrapper->main->core;
    auto* helper = top->VerilatorHelper;


    // Initialize test bench
    int64_t MAX_TEST_CYCLES = 100;
    int64_t MAX_TEST_INSTRUCTIONS = 0;
    int64_t MAX_NO_COMMIT_CYCLES = 500;
    bool ENABLE_PC_GOAL = true;
    bool SHOW_SERIAL_OUT = false;
    string TEST_CODE = "Verification/TestCode/C/Fibonacci";
    string REG_CSV_FILE = "";
    string RSD_LOG_FILE = "";
    string WAVE_LOG_FILE = "";

    // Parse command line parameters
    //     MAX_TEST_INSTRUCTIONS=<committed RISC-V instructions>
    //     MAX_NO_COMMIT_CYCLES=<consecutive cycles without any commit>
    //     MAX_TEST_CYCLES=<cycles, or 0 to disable>
    //     TEST_CODE=<path to code>
    regex re("([^=]+)=([^=]+)");
    for (int i = 1; i < argc; i++) {
        cmatch results;
        if (regex_match(argv[i], results, re)) {
            auto name = results[1].str();
            auto value = results[2].str();
            if (name == "MAX_TEST_CYCLES") {
                MAX_TEST_CYCLES = stoll(value);
            }
            else if (name == "MAX_TEST_INSTRUCTIONS") {
                MAX_TEST_INSTRUCTIONS = stoll(value);
            }
            else if (name == "MAX_NO_COMMIT_CYCLES") {
                MAX_NO_COMMIT_CYCLES = stoll(value);
            }
            else if (name == "ENABLE_PC_GOAL") {
                ENABLE_PC_GOAL = stoi(value) ? true : false;
            }
            else if (name == "SHOW_SERIAL_OUT") {
                SHOW_SERIAL_OUT = stoi(value) ? true : false;
            }
            else if (name == "REG_CSV_FILE") {
                REG_CSV_FILE = value;
            }
            else if (name == "RSD_LOG_FILE") {
                RSD_LOG_FILE = value;
            }
            else if (name == "TEST_CODE") {
                TEST_CODE = value;
            }
            else if (name == "WAVE_LOG_FILE") {
                WAVE_LOG_FILE = value;
            }
            else {
                printf("Unknown parameter:%s\n", argv[i]);
            }
        }
        else {
            printf("Unknown parameter:%s\n", argv[i]);
        }
    }

    if (MAX_TEST_CYCLES < 0 || MAX_TEST_INSTRUCTIONS < 0 ||
        MAX_NO_COMMIT_CYCLES <= 0 ||
        (MAX_TEST_CYCLES == 0 && MAX_TEST_INSTRUCTIONS == 0)) {
        fprintf(stderr, "Invalid simulation limits.\n");
        return 1;
    }

#ifdef RSD_VERILATOR_TRACE
    VerilatedVcdC* tfp = nullptr;
    if (WAVE_LOG_FILE != "") {
        Verilated::traceEverOn(true);
        tfp = new VerilatedVcdC();
        top->trace(tfp, 99);
        tfp->open("simx.vcd");
    }
#endif

    // Initialize dumpers
    bool enableDumpKanata = false;
    KanataDumper kanataDumper;
    if (RSD_LOG_FILE != "") {
        enableDumpKanata = true;
        kanataDumper.Open(RSD_LOG_FILE);
    }

    bool enableDumpRegCSV = false;
    RegisterFileCSV_Dumper registerFileCSV_Dumper;
    if (REG_CSV_FILE != "") {
        enableDumpRegCSV = true;
        registerFileCSV_Dumper.Open(REG_CSV_FILE);
    }

    string codeFileName = TEST_CODE + "/" + "code.hex";
    string regOutFileName = TEST_CODE + "/" + "reg.out.hex";
    string serialDumpFileName = TEST_CODE + "/" + "serial.out.txt";

    SerialDumper serialDumper(SHOW_SERIAL_OUT);  // サイクルダンプ無効時は標準出力にシリアルの結果を出す
    serialDumper.Open(serialDumpFileName);

    // The word of the main memory is 128 bits.
    // A word is implemented as uint32_t[4] in verilated modules.
    //int MEMORY_ENTRY_NUM = top->MemoryTypes->MEMORY_ENTRY_NUM;
    //uint32_t* mainMem = &(top->Main_Zynq_Wrapper->main->memory->body->array[0][0]);
    //assert(top->MemoryTypes->MEMORY_ENTRY_BIT_NUM == 128);
    //assert(sizeof(top->Main_Zynq_Wrapper->main->memory->body->array) == 128/8 * MEMORY_ENTRY_NUM);
    // To access the module generated in generate,
    // use (Label given in generate section)__DOT__(module name)
    size_t mainMemWordSize = sizeof(top->Main_Zynq_Wrapper->main->memory->body->body__DOT__ram->array) / sizeof(uint32_t);
    uint32_t* mainMem = reinterpret_cast<uint32_t*>(&top->Main_Zynq_Wrapper->main->memory->body->body__DOT__ram->array);

    // Fill dummy data
    for (int i = 0; i < mainMemWordSize; i++) {
        mainMem[i] = 0xcdcdcdcd;
    }

    // Load code data
    auto loadHexFile = [&](
        const string& fileName, 
        uint32_t* mainMem, 
        uint32_t offset, 
        bool neccesary
    ) {
        ifstream ifs(fileName);
        if (ifs.fail()) {
            if (neccesary) {
                printf("Fail to load \"%s\".\n", fileName.c_str());
                exit(1);
            }
        }
        string line;
        uint32_t wordAddr = offset / sizeof(uint32_t);
        while (getline(ifs, line)) {
            if (wordAddr >= mainMemWordSize) {
                printf("\"%s\" is too large.\n", fileName.c_str());
                exit(1);
            }
            for (int i = 0; i < 4; i++) {
                string wordStr = line.substr((3 - i) * 8, 8);
                uint32_t word = strtoul(wordStr.c_str(), nullptr, 16);
                mainMem[wordAddr + i] = word;
            }
            wordAddr += 4;
        }    
        printf(
            "Loaded %s into a physical memory region [%x-%x].\n",
            fileName.c_str(),
            (uint32_t)offset,
            (uint32_t)(offset + wordAddr * sizeof(uint32_t) - 1)
        );
    };
    // ファイル内容は物理メモリ空間の先頭から連続して展開される
    // ファイル先頭 64KB は ROM とみなされ，残りが RAM の空間に展開される
    //   Physical 0x0_0000 - 0x0_ffff -> Logical 0x0000_0000 - 0x0000_ffff: ROM (64KB)
    //   Physical 0x1_0000 - 0x4_ffff -> Logical 0x8000_0000 - 0x8003_ffff: RAM (256KB)
    // たとえば 128KB のファイルの場合，
    // 先頭 64KB は 論理空間の 0x0000_0000 - 0x0000_FFFF に，
    // 後続 64KB は 論理空間の 0x8000_0000 - 0x8000_FFFF に展開されることになる
    loadHexFile(codeFileName, mainMem, 0, true);
    

    int64_t numCommittedRISCV_Op = 0;
    int64_t numCommittedMicroOp = 0;
    int64_t elapsedCycles = 0;
    int64_t noCommitCycles = 0;
    int64_t maxNoCommitCycles = 0;
    string terminationReason = "unexpected_finish";
    LED_Path lastCommittedPC = 0;
    DebugRegister debugRegister;
    memset(&debugRegister, 0x0, sizeof(DebugRegister));


    // TestBenchClockGenerator にあわせる
    const int RSD_STEP = 8;   
    const int RSD_KANATA_CYCLE_DISPLACEMENT = -1;
    const int RSD_INITIALIZATION_CYCLE = 8;
    int64_t cycle = -1;
    int64_t kanataCycle = cycle - RSD_KANATA_CYCLE_DISPLACEMENT;

    bool start = false; // タイミングを TestMain.sv にあわせるため

    try{

        top->negResetIn = 0;        // Set some inputs
        top->clk_p = 0;
        top->clk_n = 1;
        top->rxd = 0;

        top->eval();
#ifdef RSD_VERILATOR_TRACE
        if (tfp) tfp->dump(main_time);
#endif
        main_time += RSD_STEP*2; 

        while (!Verilated::gotFinish()) {
            // クロック更新
            top->clk_p = !top->clk_p;
            top->clk_n = !top->clk_n;
            top->eval();    // 評価
            if (Verilated::gotFinish())
                break; // Keep unexpected_finish even if a budget is reached.

            // ダンプ
#ifdef RSD_VERILATOR_TRACE
            if (tfp)
                tfp->dump(main_time);
#endif
            // 実行が開始されていたらクロックをインクリメント
            if (top->clk_p && start){
                kanataCycle++;
                cycle++;
                elapsedCycles++;

                // ダンプ
                GetDebugRegister(&debugRegister, top);
                if (!SHOW_SERIAL_OUT && (kanataCycle < 10000 || kanataCycle % 10000 == 0)){
                    printf("%d cycle, %d KanataCycle, %d ns\n", (uint32_t)cycle, (uint32_t)kanataCycle, (uint32_t)main_time);
                }

                serialDumper.CheckSignal(
                    top->serialWE, 
                    top->serialWriteData
                );

                // Dump RSD.log for Kanata
                if (enableDumpKanata){
                    kanataDumper.DumpCycle(debugRegister);
                }

                if (enableDumpRegCSV) {
                    registerFileCSV_Dumper.ProceedCycle();

                    for (int i = 0; i < COMMIT_WIDTH; i++) {
                        // 1命令ずつコミットを追ってレジスタ状態をダンプする
                        if (core->cmStage->commit[i]) {
                            DataPath regData[LREG_NUM];
                            GetCommittedRegisterValue(top, i, regData);
                            registerFileCSV_Dumper.Dump(
                                helper->ActiveListEntry_pc(core->cmStage->alReadData[i]),
                                regData
                            );
                        }
                    }
                }

                // Use the same commit signals as lastCommittedPC and the
                // register dump; DebugRegister is delayed by one clock.
                // Count an instruction when its last micro-op commits.
                bool committedThisCycle = false;
                for (int i = 0; i < COMMIT_WIDTH; i++) {
                    if (core->cmStage->commit[i]) {
                        committedThisCycle = true;
                        numCommittedMicroOp += 1;
                        if (helper->ActiveListEntry_last(core->cmStage->alReadData[i])) {
                            numCommittedRISCV_Op += 1;
                        }
                    }
                }

                // Start monitoring at reset release, including the first fetch.
                noCommitCycles = committedThisCycle ? 0 : noCommitCycles + 1;
                if (noCommitCycles > maxNoCommitCycles)
                    maxNoCommitCycles = noCommitCycles;
                if (noCommitCycles > MAX_NO_COMMIT_CYCLES) {
                    terminationReason = "no_commit_limit";
                    break;
                }

                // A goal reached on the budget boundary still completes the test.
                lastCommittedPC = top->ledOut;
                if (ENABLE_PC_GOAL) {
                    if (lastCommittedPC == static_cast<typeof(top->ledOut)>(PC_GOAL)) {
                        // lastCommittedPC は 16bit 分しか外に出てきていないので，下位で判定しておく
                        terminationReason = "pc_goal";
                        printf("PC reached PC_GOAL: %08x\n", PC_GOAL);
                        break;
                    }
                }
                if (MAX_TEST_INSTRUCTIONS > 0 && numCommittedRISCV_Op >= MAX_TEST_INSTRUCTIONS) {
                    terminationReason = "instruction_limit";
                    break;
                }
                if (MAX_TEST_CYCLES > 0 && elapsedCycles >= MAX_TEST_CYCLES) {
                    terminationReason = "cycle_limit";
                    break;
                }
            }
            start = !top->posResetOut;

            main_time += RSD_STEP; // 62.5MHz
            // Release reset on the falling edge, as in TestBenchClockGenerator.
            if (main_time == RSD_INITIALIZATION_CYCLE*RSD_STEP*2 + RSD_STEP) {
                top->negResetIn = 1; // リセット解除
            }
            
        }

    } catch (const std::exception& error) {
        fprintf(stderr, "Simulation failed: %s\n", error.what());
        terminationReason = "runtime_error";
    }

    // Count the number of commit in the last cycle.
    int commitNumInLastCycle = 0;
    for (int count = 0; count < COMMIT_WIDTH; count++) {
        if (!core->cmStage->commit[count])
            break;
        commitNumInLastCycle++;
    }   

    // Close Dumpers
    //serialDumper.DumpToFile(serialDumpFileName);
    serialDumper.Close();
    kanataDumper.Close();
    registerFileCSV_Dumper.Close();

    // Simulation Result
    printf("Num of I$ misses: %d\n", debugRegister.perfCounter.numIC_Miss);
    printf("Num of D$ load misses: %d\n", debugRegister.perfCounter.numLoadMiss);
    printf("Num of D$ store misses: %d\n", debugRegister.perfCounter.numStoreMiss);
    printf("Num of branch prediction misses: %d\n", debugRegister.perfCounter.numBranchPredMiss);
    printf("Num of branch prediction misses detected on decode: %d\n", debugRegister.perfCounter.numBranchPredMissDetectedOnDecode);
    printf("Num of store-load-forwanind misses: %d\n", debugRegister.perfCounter.numStoreLoadForwardingFail);
    printf("Num of memory dependency prediction misses: %d\n", debugRegister.perfCounter.numMemDepPredMiss);

    printf("Num of committed RISC-V-ops: %lld\n", (long long)numCommittedRISCV_Op);
    printf("Num of committed micro-ops: %lld\n", (long long)numCommittedMicroOp);
    if (elapsedCycles != 0) {
        printf("IPC (RISC-V instruction): %f\n", (double)numCommittedRISCV_Op / (double)elapsedCycles);
        printf("IPC (micro-op): %f\n", (double)numCommittedMicroOp / (double)elapsedCycles);
    }
    printf("Elapsed cycles: %lld\n", (long long)elapsedCycles);
    printf("Max consecutive no-commit cycles: %lld\n", (long long)maxNoCommitCycles);
    printf("Simulation result: %s\n", terminationReason.c_str());

    // Dump Register File
    RegisterFileHexDumper registerFileHexDumper;
    DataPath regData[LREG_NUM];
    GetCommittedRegisterValue(top, commitNumInLastCycle, regData);
    registerFileHexDumper.Open(regOutFileName);
    registerFileHexDumper.Dump(lastCommittedPC, regData);
    registerFileHexDumper.Close();


#ifdef RSD_VERILATOR_TRACE
    if (tfp) {
        tfp->close();
        tfp = nullptr;
    }
#endif
    top->final();        // シミュレーション終了

    // Continuous tests complete their instruction budget. Cycle-only settings
    // remain supported for external tests that have not yet been migrated.
    const bool success = terminationReason == "pc_goal" ||
        (!ENABLE_PC_GOAL && (terminationReason == "instruction_limit" ||
            (MAX_TEST_INSTRUCTIONS == 0 && terminationReason == "cycle_limit")));
    return success ? 0 : 1;
}
