// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

// This is a program loader for RSD on a Zynq board.
// How to use:
//   1. Send this file to Debian on the Zynq board,
//   2. Compile this code on Debian on the Zynq board,
//   3. Send code.hex of the program you want to run to Debian,
//   4. Run your program on RSD by "./loader <path of code.hex> <byte size of code.hex>".

#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <errno.h>

#define RAM_SIZE   0x10000000
#define PL2PS_SIZE 0x1000
#define PS2PL_SIZE 0x1000

// PSからRSDに送るプログラムのワード数(メモリの1エントリ単位)
#define PROGRAM_WORDSIZE 4096

// RSDのメモリ1エントリあたりのバイト数
#define MEMORY_WORD_BYTE_SIZE 16

// RSDのメモリ1エントリあたりの文字数
#define MEMORY_WORD_CHAR_SIZE MEMORY_WORD_BYTE_SIZE*2

// AXIバスのバイト幅
#define AXI_WORD_BYTE_SIZE 4

// 注意: このプログラムはMEMORY_WORD_BYTE_SIZEがAXI_WORD_BYTE_SIZEで割り切れないと正しく動作しない

// RSDの1ワード(AXIバスの1ワード単位)を16進数で表現する場合の文字数
#define AXI_WORD_CHAR_SIZE AXI_WORD_BYTE_SIZE*2

// PSからRSDに送るプログラムの文字数(programinit関数内に記述したプログラムの文字数)
#define PROGRAM_CHARSIZE PROGRAM_WORDSIZE*MEMORY_WORD_BYTE_SIZE*2


// ------------------------------------------------
// PS -> PL のメモリマップドレジスタの各データに対応するオフセット
// PLから対応するデータを受け取る際に使用する

// PL内のデータ受け取り用FIFOのFULL信号
#define S2L_FULL_OFFSET 0

// 現在PLが受け取ったワード数(メモリの1エントリ単位)
#define S2L_MEMORY_WORDCOUNT_OFFSET 3

// PL内のデータ受け取り用FIFOのEMPTY信号 (普段は使わない)
#define S2L_EMPTY_OFFSET 4

// デバッグ用．普段は使わない．
#define S2L_POPED_DATACOUNT_OFFSET 5

// ------------------------------------------------
// PS -> PL のメモリマップドレジスタの各データに対応するオフセット
// PSからPLに対応するデータを送る際に使用する

// このオフセットに書き込むとPL内のデータ受け取り用FIFOにプッシュされる
#define S2L_PUSHED_DATA_OFFSET 0

// プッシュされたデータを書き込むRSDのメインメモリ上のアドレスをこのオフセットに書き込む
// Byteアドレスであることに注意
#define S2L_MEMORY_ADDR_OFFSET 1

// このオフセットにPSからPLに送信するプログラムのデータサイズをメモリの1エントリ単位のワード数で書き込む
#define S2L_PROGRAM_WORDSIZE_OFFSET 2

// ------------------------------------------------
// PL -> PS のメモリマップドレジスタの各データに対応するオフセット
// PSがPL(RSD)から対応するデータを受け取る際に使用する

// PLからのデータを一時的に保存するFIFOのEMPTY信号
#define L2S_EMPTY_OFFSET 0

// PLからのデータを一時的に保存するFIFOの先頭にあるデータ
// このオフセットからデータを読むと，自動的にPOPもされたことになる
#define L2S_DATA_OFFSET 1

// このオフセットにPSからPLに送信するプログラムのデータサイズをメモリの1エントリ単位のワード数で書き込む
#define L2S_PROGRAM_WORDSIZE_OFFSET 2

#define DONE_OFFSET 6

// ------------------------------------------------

// void programinit();

int ram_open(){
    int fd = -1;
    fd = open("/dev/uio0", O_RDWR);
    return fd;
}

int pl2ps_open(){
    int fd = -1;
    fd = open("/dev/uio1", O_RDWR);
    return fd;
}

int ps2pl_open(){
    int fd = -1;
    fd = open("/dev/uio2", O_RDWR);
    return fd;
}

int main(int argc, char *argv[])
{
    int i, j;
    int ram;
    int pl2ps;
    int ps2pl;
    volatile unsigned int* mem;
    volatile unsigned int* rsd_pl2ps;
    volatile unsigned int* rsd_ps2pl;

    // PSからRSDに送るプログラムの文字数(programinit関数内に記述したプログラムの文字数)
    int program_bytesize;
    int program_wordsize;
    int program_charsize;

    char line[MEMORY_WORD_CHAR_SIZE];
    
//
// -- オプションチェック
//
    if ((argc == 2) && ((argv[1] == "-h") || (argv[1] == "--help"))) {
        printf("usage: loader <path of code.hex> <byte size of code.hex>\n");
        return 0;
    }
    else if (argc != 3) {
        printf("usage: loader <path of code.hex> <byte size of code.hex>\n");
        return -1;
    }

//
// -- プログラムサイズチェック
//
    
    // PSからRSDに送るプログラムのbyte数
    program_bytesize = atoi(argv[2]);

    if (program_bytesize == 0) {
        printf("Invalid code.hex size of %c\n", argv[2]);
        return -1;
    }

    // PSからRSDに送るプログラムのワード数(メモリの1エントリ単位)
    program_wordsize = program_bytesize/16;

    // PSからRSDに送るプログラムの文字数(code.hex内の文字数)
    program_charsize = program_bytesize*2;

//
// -- プログラムファイルを読み込み
//
    FILE *fp;
    if ((fp = fopen(argv[1], "r")) == NULL) {
        printf("code.hex open error\n");
        return -1;
    }

    char prog[program_charsize+3];
    i = 0;
    j = 0;
    while(1) {
        if (fgets(line, MEMORY_WORD_CHAR_SIZE+3, fp) == NULL) {
            printf("code.hex size mismatch\n");
            fclose(fp);
            return -1;
        }

        for (j=0;j<MEMORY_WORD_CHAR_SIZE;j++) {
            prog[j+i*MEMORY_WORD_CHAR_SIZE] = line[j];
        }        

        i++;
        if (i>=program_wordsize) {
            break;
        }
    }

    printf("load finish, %d\n", i);

    fclose(fp);

//
// -- デバイスファイルをオープンしてアロケート
//
    ram = ram_open();
    if (ram < 0) {
        printf("Failed to open ram");
        return -2;
    }
    mem = mmap( NULL, RAM_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, ram, 0);
    if (mem == MAP_FAILED) {
        printf("Failed to mmap ram");
        close(ram);
        return -1;
    }

    pl2ps = pl2ps_open();
    if (pl2ps < 0) {
        printf("Failed to open pl2ps");
        return -2;
    }
    rsd_pl2ps = mmap( NULL, PL2PS_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, pl2ps, 0);
    if (rsd_pl2ps == MAP_FAILED) {
        printf("Failed to mmap pl2ps");
        close(pl2ps);
        return -1;
    }

    ps2pl = ps2pl_open();
    if (pl2ps < 0) {
        printf("Failed to open ps2pl");
        return -2;
    }
    rsd_ps2pl = mmap( NULL, PS2PL_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, ps2pl, 0);
    if (rsd_ps2pl == MAP_FAILED) {
        printf("Failed to mmap ps2pl");
        close(ps2pl);
        return -1;
    }

//
// -- main
//
    rsd_ps2pl[DONE_OFFSET] = 0;

    // プログラムの1文字
    char rc;
    // プログラムの1ワード(AXIバスの1ワード単位)
    char val[AXI_WORD_CHAR_SIZE+2];
    // valは必ず"0x????????"となる
    val[0] = '0';
    val[1] = 'x';

    char *endptr;
    unsigned long x;

    i = 2;
    j = 0;
    int k = 3;
    int sendword = 0;
    int offset = 0;
    int t = 0;

    for (t=0;t<67108864;t++) {
        mem[t] = 0;
    }

    for (;;)
    {
        // プログラムの全データの送信が終わったらbreak
        if (j == program_charsize) {
            break;
        }
        rc = prog[j];
        j++;
        val[i] = rc;
        // valに1ワード(AXIバスの1ワード単位)が格納されたら送信する
        if(i==(AXI_WORD_CHAR_SIZE+1)) {
            i = 2;
            x = strtoul(val, &endptr, 16);
            mem[offset+k] = x;
            if (k == 0) {
                k = 3;
                offset += 4;
            } else {
                k--;
            }

        } else {
            i++;
        }

    }

    rsd_ps2pl[DONE_OFFSET] = 1;
    t = 0;
    int u = 0;

    // プログラムの転送が終わったら，PL(RSD)からの出力をポーリングして表示する
    // TODO: 無限ループになっているので，ある特定の出力を受け取ったら終了するとかをしてもいいかもしれない
    while(1) {
        // PLからのデータが入っているFIFOが空でなかったらPOPして表示
        if (rsd_pl2ps[L2S_EMPTY_OFFSET] != 1) {
            printf("%c", (char)rsd_pl2ps[L2S_DATA_OFFSET]);
        }
        if (t == 10000000) {
            t = 0;
            printf("%08x, %d, %d, %d\n", rsd_pl2ps[4], rsd_pl2ps[5], rsd_pl2ps[L2S_EMPTY_OFFSET], rsd_pl2ps[2]);
        } else {
            t++;
        }
    }


//
// -- デバイスファイルをアンマップしてクローズ
//
    munmap((void *)mem, RAM_SIZE);
    munmap((void *)rsd_pl2ps, PL2PS_SIZE);
    munmap((void *)rsd_ps2pl, PS2PL_SIZE);
    close(ram);
    close(pl2ps);
    close(ps2pl);
 
    return 0;
}
