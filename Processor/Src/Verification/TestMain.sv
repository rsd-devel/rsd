// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


`timescale 1ns/1ps

import DumperTypes::*;
import BasicTypes::*;
import CacheSystemTypes::*;
import MemoryTypes::*;
import PipelineTypes::*;
import RenameLogicTypes::*;
import SchedulerTypes::*;
import MicroOpTypes::*;
import LoadStoreUnitTypes::*;
import MemoryMapTypes::*;
import IO_UnitTypes::*;
import DebugTypes::*;


parameter STEP = 8; // 62.5Mhz
parameter HOLD = 2;
parameter SETUP = 2;
parameter WAIT = STEP*2-HOLD-SETUP;
parameter HOLD_PLUS_WAIT = HOLD + WAIT;

module TestMain;

    //
    // Check compiler directives.
    //
    `ifdef RSD_SYNTHESIS
        initial begin
            $error("Wrong compiler directive: RSD_SYNTHESIS");
            $finish;
        end
    `endif

    `ifndef RSD_FUNCTIONAL_SIMULATION
        `ifndef RSD_POST_SYNTHESIS_SIMULATION
            initial begin
                $error("Neither RSD_FUNCTIONAL_SIMULATION nor RSD_POST_SYNTHESIS_SIMULATION is defined as a compiler directive.");
                $finish;
            end
        `endif
    `endif

    //
    // Functions
    //

    `ifdef RSD_FUNCTIONAL_SIMULATION
        `ifndef RSD_POST_SYNTHESIS_SIMULATION
            // RetirementRMTからコミット済の論理レジスタの値を得る
            task GetCommittedRegisterValue(
                input int commitNumInThisCycle,
                output DataPath regData[ LSCALAR_NUM ]
            );
                int rollbackNum;
                PRegNumPath  phyRegNum[ LSCALAR_NUM ];
                ActiveListIndexPath alHeadPtr;
                ActiveListEntry alHead;

                int tmpSelect;
                DataPath tmpRegData  [ ISSUE_WIDTH ];

                // Copy RMT to local variable.
                for( int i = 0; i < LSCALAR_NUM; i++ ) begin
                   phyRegNum[i] = main.main.core.retirementRMT.regRMT.debugValue[i];
                end

                // Update RRMT
                alHeadPtr = main.main.core.activeList.headPtr;
                for( int i = 0; i < commitNumInThisCycle; i++ ) begin
                    alHead = main.main.core.activeList.activeList.debugValue[ alHeadPtr ];
                    if ( alHead.writeReg ) begin
                        phyRegNum[ alHead.logDstRegNum ] = alHead.phyDstRegNum;
                    end
                    alHeadPtr++;
                end

                // Get regData
                for( int i = 0; i < LSCALAR_NUM; i++ ) begin
                    regData[i] = main.main.core.registerFile.phyReg.debugValue[ phyRegNum[i] ];
                end
            endtask
        `endif
    `endif

    // These parameters are passed as command line arguments.
    int MAX_TEST_CYCLES;
    int SHOW_SERIAL_OUT;
    int ENABLE_PC_GOAL;
    string TEST_CODE;
    string RSD_LOG_FILE;
    string REG_CSV_FILE;
    string DUMMY_DATA_FILE;

    string codeFileName;
    string regOutFileName;
    string serialDumpFileName;

    integer cycle;
    integer entry;

    integer dumpFlush; // A flag used for avoiding to dump flush more than once.
    integer count;
    string str;

    DataPath regData[ LSCALAR_NUM ];

    integer commitNumInLastCycle;
    integer numCommittedRISCV_Op;
    integer numCommittedMicroOp;
    real realTmp;

    //
    // Source of clock and reset
    //
    logic clk, rst, rstOut;

    TestBenchClockGenerator #(
        .STEP(STEP)
    ) clkgen (
        .clk( clk ),
        .rst( rst ),
        .rstOut( rstOut )
    );

    //
    // Main module
    //
    LED_Path ledOut;
    LED_Path lastCommittedPC;
    DebugRegister debugRegister;
    logic rxd, txd;
    logic serialWE;
    SerialDataPath serialWriteData;

    Main_Zynq_Wrapper main(
        .clk_p( clk ),
        .clk_n ( ~clk ),
        .negResetIn( ~rst ),
        .posResetOut( rstOut ),
        .*
    );

`ifdef RSD_SYNTHESIS_VIVADO
    always_comb begin
        debugRegister = main.debugRegister;
    end
`endif
    //
    // Dumpers
    //
    logic enableDumpKanata;
    logic enableDumpRegCSV;

    KanataDumper kanataDumper;
    RegisterFileHexDumper registerFileHexDumper;
    RegisterFileCSV_Dumper registerFileCSV_Dumper;
    SerialDumper serialDumper;


    //
    // Test Bench
    //
    initial begin

        // init variable
        dumpFlush = FALSE;
        numCommittedRISCV_Op = 0;
        numCommittedMicroOp = 0;

        // settings
        if( !$value$plusargs( "MAX_TEST_CYCLES=%d", MAX_TEST_CYCLES ) ) begin
            MAX_TEST_CYCLES = 100;
        end
        if( !$value$plusargs( "TEST_CODE=%s", TEST_CODE ) ) begin
            TEST_CODE = "Verification/TestCode/Fibonacci";
        end
        if( !$value$plusargs( "DUMMY_DATA_FILE=%s", DUMMY_DATA_FILE ) ) begin
            DUMMY_DATA_FILE = "Verification/DummyData.hex";
        end
        if( !$value$plusargs( "SHOW_SERIAL_OUT=%d", SHOW_SERIAL_OUT ) ) begin
            SHOW_SERIAL_OUT = 0;
        end
        if( !$value$plusargs( "ENABLE_PC_GOAL=%d", ENABLE_PC_GOAL ) ) begin
            ENABLE_PC_GOAL = 1;
        end

        enableDumpKanata = FALSE;
        if( $value$plusargs( "RSD_LOG_FILE=%s", RSD_LOG_FILE ) ) begin
            enableDumpKanata = TRUE;
            kanataDumper = new;
            kanataDumper.Open( RSD_LOG_FILE );
        end

        enableDumpRegCSV = FALSE;
        if( $value$plusargs( "REG_CSV_FILE=%s", REG_CSV_FILE ) ) begin
            enableDumpRegCSV = TRUE;
            registerFileCSV_Dumper = new;
            registerFileCSV_Dumper.Open( REG_CSV_FILE );
        end

        codeFileName = { TEST_CODE, "/", "code.hex" };
        regOutFileName = { TEST_CODE, "/", "reg.out.hex" };
        serialDumpFileName = { TEST_CODE, "/", "serial.out.txt" };

        serialDumper = new;
        serialDumper.Init();

        // Initialize memory
        #STEP;
        `ifdef RSD_FUNCTIONAL_SIMULATION
            `ifndef RSD_POST_SYNTHESIS_SIMULATION
                // Fill memory with dummy data 
                // see InitializedBlockRAM module in Primitives/RAM.sv in details
                main.main.memory.body.FillDummyData(DUMMY_DATA_FILE, DUMMY_HEX_ENTRY_NUM);


                // ファイル内容は物理メモリ空間の先頭から連続して展開される
                // ファイル先頭 64KB は ROM とみなされ，残りが RAM の空間に展開される
                //   Physical 0x0_0000 - 0x0_ffff -> Logical 0x0000_0000 - 0x0000_ffff: ROM (64KB)
                //   Physical 0x1_0000 - 0x4_ffff -> Logical 0x8000_0000 - 0x8003_ffff: RAM (256KB)
                // たとえば 128KB のファイルの場合，
                // 先頭 64KB は 論理空間の 0x0000_0000 - 0x0000_FFFF に，
                // 後続 64KB は 論理空間の 0x8000_0000 - 0x8000_FFFF に展開されることになる
                main.main.memory.body.InitializeMemory(codeFileName);
            `endif
        `endif

        //
        // Simulation body
        //
        @(negedge rstOut);
        for( cycle = 0; cycle < MAX_TEST_CYCLES; cycle++ ) begin
            if (SHOW_SERIAL_OUT == 0 && (clkgen.kanataCycle < 10000 || clkgen.kanataCycle % 10000 == 0)) begin
                $display( "%d cycle %d KanataCycle %tps", clkgen.cycle, clkgen.kanataCycle, $time );
            end

            @(posedge clk);
            #HOLD_PLUS_WAIT;

            serialDumper.CheckSignal( serialWE, serialWriteData, SHOW_SERIAL_OUT );

            // Dump RSD.log for Kanata
            if ( enableDumpKanata ) begin
                kanataDumper.DumpCycle( debugRegister );
            end

            // Dump values of logical register file to a CSV file.
            `ifdef RSD_FUNCTIONAL_SIMULATION
                `ifndef RSD_POST_SYNTHESIS_SIMULATION
                    if ( enableDumpRegCSV ) begin
                        registerFileCSV_Dumper.ProceedCycle();

                        for ( int i = 0; i < COMMIT_WIDTH; i++ ) begin
                            if ( main.main.core.cmStage.commit[i] ) begin
                                GetCommittedRegisterValue( i, regData );
                                registerFileCSV_Dumper.Dump( main.main.core.cmStage.alReadData[i].pc, regData );
                            end
                        end
                    end
                `endif
            `endif
            
            // Count number of committed Ops.
            for ( int i = 0; i < COMMIT_WIDTH; i++ ) begin
                if ( debugRegister.cmReg[i].commit ) begin
                    numCommittedMicroOp += 1;
                    if ( debugRegister.cmReg[i].opId.mid == 0 ) begin
                        numCommittedRISCV_Op += 1;
                    end
                end
            end
            
            // Check end of simulation.
            lastCommittedPC = ledOut;
            if ( ENABLE_PC_GOAL != 0 && lastCommittedPC == PC_GOAL[LED_WIDTH-1:0] ) begin
                // lastCommittedPC は 16bit 分しか外に出てきていないので，下位で判定しておく
                $display( "PC reached PC_GOAL: %08x", PC_GOAL );
                break;
            end

        end

        // Close Dumper
        serialDumper.DumpToFile( serialDumpFileName );
        if ( enableDumpKanata ) kanataDumper.Close();
        if ( enableDumpRegCSV ) registerFileCSV_Dumper.Close();

        // Simulation Result
        $display("Num of I$ misses: %d", debugRegister.perfCounter.numIC_Miss);
        $display("Num of D$ load misses: %d", debugRegister.perfCounter.numLoadMiss);
        $display("Num of D$ store misses: %d", debugRegister.perfCounter.numStoreMiss);
        $display("Num of memory dependency prediction misses: %d", debugRegister.perfCounter.numStoreLoadForwardingFail);
        $display("Num of store-load-forwarding misses: %d", debugRegister.perfCounter.numMemDepPredMiss);
        $display("Num of branch prediction misses: %d", debugRegister.perfCounter.numBranchPredMiss);
        $display("Num of branch prediction misses detected on decode: %d", debugRegister.perfCounter.numBranchPredMissDetectedOnDecode);

        $display( "Num of committed RISC-V-ops: %d", numCommittedRISCV_Op );
        $display( "Num of committed micro-ops: %d", numCommittedMicroOp );
        if ( cycle != 0 ) begin
            realTmp = cycle;
            $display( "IPC (RISC-V instruction): %f", numCommittedRISCV_Op / realTmp );
            $display( "IPC (micro-op): %f", numCommittedMicroOp / realTmp );
        end
        $display("Elapsed cycles: %d", cycle);


        `ifdef RSD_FUNCTIONAL_SIMULATION
            `ifndef RSD_POST_SYNTHESIS_SIMULATION
                // Count the number of commit in the last cycle.
                for ( count = 0; count < COMMIT_WIDTH; count++ ) begin
                    if ( !main.main.core.cmStage.commit[count] )
                        break;
                end
                commitNumInLastCycle = count;

                // Dump Register File
                GetCommittedRegisterValue( commitNumInLastCycle, regData );
                registerFileHexDumper = new;
                registerFileHexDumper.Open( regOutFileName );
                registerFileHexDumper.Dump( lastCommittedPC, regData );
                registerFileHexDumper.Close();
            `endif
        `endif

        $finish;

    end

endmodule

