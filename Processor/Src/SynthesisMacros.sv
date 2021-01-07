// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

// This file is used only on synthesis and is not used for simulation.


/*************************************/
/* These macros must not be changed. */
/*************************************/
// RSD_SYNTHESIS specifies that RSD is compiled for synthesizing.
`define RSD_SYNTHESIS 

// 特定の信号(2次元以上のunpack配列？)は、
// Synplifyの合成時はinput／QuestaSimのシミュレーション時はref
// としないと動かないので、そのためのdefine
`define REF input 

//`define RSD_POST_SYNTHESIS
//`define RSD_SYNTHESIS_ZEDBOARD

`define RSD_SYNTHESIS_VIVADO


/********************************************************************/
/* These macros are for user configuration, so you can change them. */
/********************************************************************/

// Microarchitectural configuration
//`define RSD_MARCH_UNIFIED_LDST_MEM_PIPE 
`define RSD_MARCH_INT_ISSUE_WIDTH 2
//`define RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE 
//`define RSD_MARCH_UNIFIED_LDST_MEM_PIPE

// Enable Microsemi specific optimization
//`define RSD_SYNTHESIS_OPT_MICROSEMI



// if RSD_DISABLE_PERFORMANCE_COUNTER is defined, performance counters are not synthesized.
`define RSD_DISABLE_PERFORMANCE_COUNTER

/*
  Define one of these macros.
    - RSD_SYNTHESIS_TED : For Tokyo Electron Device Virtex-6 board (TB-6V-760LX)
        Defined compiler directives :
            `RSD_SMALL_MEMORY
            `RSD_SYNTHESIS_FPGA
    - RSD_SYNTHESIS_ATLYS : For Atlys Spartan-6 board
        Defined compiler directives :
            `RSD_DISABLE_DEBUG_REGISTER
            `RSD_USE_PROGRAM_LOADER
            `RSD_USE_EXTERNAL_MEMORY
            `RSD_SYNTHESIS_FPGA
    - RSD_SYNTHESIS_ZEDBOARD : For ZedBoard Zynq-7000 board
        Defined compiler directives :
            `RSD_DISABLE_DEBUG_REGISTER
            `RSD_USE_PROGRAM_LOADER
            `RSD_SYNTHESIS_ZYNQ
    - RSD_POST_SYNTHESIS : For post-synthesis simulation
*/

/*
  Define one of these macros.
    - RSD_SYNTHESIS_SYNPLIFY : For Synopsys Synplify
    - RSD_SYNTHESIS_VIVADO   : For Xilinx Vivado
*/

`ifdef RSD_SYNTHESIS_ATLYS
    // If a RSD_DISABLE_DEBUG_REGISTER macro is not declared,
    // registers which are needed to debug is synthesized.
    // When you define a RSD_DISABLE_DEBUG_REGISTER macro,
    // you cannot utilize post-synthesis simulation,
    // but the area and speed of the processor are expected to improve.
    
    // AtlysボードはIOポートが少ないので、
    // 大量のIOポートを必要とするデバッグレジスタは今のところ実装できない
    `define RSD_DISABLE_DEBUG_REGISTER

    // プログラムローダをインスタンシエートする。
    // プログラムローダはリセット後にプログラムデータをシリアル通信で受けとり、
    // それをメモリに書き込む。この動作が終わるまでコアはメモリにアクセスできない。
    // 現在、プログラムローダはAtlysボードのみ対応しており、
    // 受け取るデータのサイズは SysDeps/Atlys/AtlysTypes.sv で設定する。
    `define RSD_USE_PROGRAM_LOADER

    // FPGA外部のメモリを使用する。
    // 現在は、AtlysボードのDDR2メモリにのみ対応。
    `define RSD_USE_EXTERNAL_MEMORY

    // 非ZYNQのFPGAがターゲット．
    // UART出力先がボードのI/Oポートで，ビット幅が8-bitとなる
    `define RSD_SYNTHESIS_FPGA

`elsif RSD_SYNTHESIS_TED
    `define RSD_SYNTHESIS_FPGA
`elsif RSD_SYNTHESIS_ZEDBOARD
    
    `define RSD_DISABLE_DEBUG_REGISTER

    // ZYNQがターゲット．
    // UART出力先がPSのUARTポートで，ビット幅が32-bitとなる
    `define RSD_SYNTHESIS_ZYNQ

    // `define RSD_USE_PROGRAM_LOADER

    `define RSD_USE_EXTERNAL_MEMORY
    
`elsif RSD_POST_SYNTHESIS
    //`define RSD_DISABLE_DEBUG_REGISTER
    `define RSD_FUNCTIONAL_SIMULATION

`elsif RSD_SYNTHESIS_DESIGN_COMPILER

    `define RSD_DISABLE_DEBUG_REGISTER
    
`else
    // RSD_SYNTHESIS_TED / RSD_SYNTHESIS_ATLYS / RSD_SYNTHESIS_ZEDBOARD のいずれも定義されていない場合は
    // コンパイルエラーとする
    "Error!"
`endif

//
// シミュレーション時のみ定義されるはずのコンパイラディレクティブが
// 定義されていたらエラーとする。
//
`ifdef RSD_FUNCTIONAL_SIMULATION
    `ifndef RSD_POST_SYNTHESIS
        "Error!"
    `endif
`endif

`ifdef RSD_POST_SYNTHESIS_SIMULATION
    "Error!"
`endif
