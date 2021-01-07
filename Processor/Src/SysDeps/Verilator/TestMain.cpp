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

unsigned int main_time = 0;     // Current simulation time

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
    for (int i = 0; i < LSCALAR_NUM; i++) {
        phyRegNum[i] = core->retirementRMT->regRMT->debugValue[i];
    }

    // Update RRMT
    //ActiveListIndexPath alHeadPtr;
    auto alHeadPtr = core->activeList->headPtr;
    for (int i = 0; i < commitNumInThisCycle; i++) {
        // ActiveListEntry alHead;
        const auto& alHead = core->activeList->activeList->debugValue[alHeadPtr];
        if (helper->ActiveListEntry_writeReg(alHead)) {
            phyRegNum[helper->ActiveListEntry_logDstRegNum(alHead)] = helper->ActiveListEntry_phyDstRegNum(alHead);
        }
        alHeadPtr++;
    }

    // Get regData
    for(int i = 0; i < LSCALAR_NUM; i++) {
        regData[i] = core->registerFile->phyReg->debugValue[phyRegNum[i]];
    }
    
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
    bool ENABLE_PC_GOAL = true;
    bool SHOW_SERIAL_OUT = false;
    string TEST_CODE = "Verification/TestCode/C/Fibonacci";
    string REG_CSV_FILE = "";
    string RSD_LOG_FILE = "";
    string WAVE_LOG_FILE = "";

    // Parse command line parameters
    //     MAX_TEST_CYCLES=<cycles>
    //     TEST_CODE=<path to code>
    regex re("([^=]+)=([^=]+)");
    for (int i = 1; i < argc; i++) {
        cmatch results;
        if (regex_match(argv[i], results, re)) {
            auto name = results[1].str();
            auto value = results[2].str();
            if (name == "MAX_TEST_CYCLES") {
                MAX_TEST_CYCLES = stoi(value);
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
    uint32_t* mainMem = (uint32_t*)(top->Main_Zynq_Wrapper->main->memory->body->body__DOT__ram->array);

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
    

    int numCommittedARM_Op = 0;
    int numCommittedMicroOp = 0;
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

            // ダンプ
#ifdef RSD_VERILATOR_TRACE
            if (tfp)
                tfp->dump(main_time);
#endif
            // 実行が開始されていたらクロックをインクリメント
            if (top->clk_p && start){
                kanataCycle++;
                cycle++;

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
                            DataPath regData[LSCALAR_NUM];
                            GetCommittedRegisterValue(top, i, regData);
                            registerFileCSV_Dumper.Dump(
                                helper->ActiveListEntry_pc(core->cmStage->alReadData[i]),
                                regData
                            );
                        }
                    }
                }

                // Count number of committed Ops.
                for (int i = 0; i < COMMIT_WIDTH; i++) {
                    if (debugRegister.cmReg[i].commit) {
                        numCommittedMicroOp += 1;
                        if ( debugRegister.cmReg[i].opId.mid == 0 ){
                            numCommittedARM_Op += 1;
                        }
                    }
                }

                // Check end of simulation.
                if (ENABLE_PC_GOAL) {
                    lastCommittedPC = top->ledOut;
                    if (lastCommittedPC == static_cast<typeof(top->ledOut)>(PC_GOAL)) {
                        // lastCommittedPC は 16bit 分しか外に出てきていないので，下位で判定しておく
                        printf("PC reached PC_GOAL: %08x\n", PC_GOAL);
                        break;
                    }
                }
            }
            start = !top->posResetOut;

            main_time += RSD_STEP; // 62.5MHz
            if (main_time == RSD_INITIALIZATION_CYCLE*RSD_STEP*2) {
                top->negResetIn = 1; // リセット解除
            }
            
            // 指定サイクル数の実行で終了
            // Modelsim 側とクロック数の計算をあわすため +1
            if (cycle + 1 >= MAX_TEST_CYCLES)
                break;         
        }

    } catch (const std::runtime_error& error) {

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

    printf("Num of committed RISC-V-ops: %d\n", numCommittedARM_Op);
    printf("Num of committed micro-ops: %d\n", numCommittedMicroOp);
    if (cycle != 0) {
        printf("IPC (RISC-V instruction): %f\n", (double)numCommittedARM_Op / (double)cycle);
        printf("IPC (micro-op): %f\n", (double)numCommittedMicroOp / (double)cycle);
    }
    printf("Elapsed cycles: %d\n", (int32_t)cycle);

    // Dump Register File
    RegisterFileHexDumper registerFileHexDumper;
    DataPath regData[LSCALAR_NUM];
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
}
