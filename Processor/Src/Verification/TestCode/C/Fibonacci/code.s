    .file   "code.c"
    .option nopic
    .text
.Ltext0:
    .align  2
    .globl  Fibonacci
    .type   Fibonacci, @function
Fibonacci:
.LFB0:
    .file 1 "Fibonacci/code.c"
    .loc 1 3 0
.LVL0:
    .loc 1 6 0
    blez    a0,.L4
    .loc 1 5 0
    li  a3,1
    li  a4,1
    .loc 1 6 0
    li  a5,0
    j   .L3
.LVL1:
.L5:
    .loc 1 7 0
    mv  a4,a2
.LVL2:
.L3:
    .loc 1 6 0 discriminator 3
    add a5,a5,1
.LVL3:
    .loc 1 7 0 discriminator 3
    add a2,a4,a3
.LVL4:
    mv  a3,a4
    .loc 1 6 0 discriminator 3
    bne a0,a5,.L5
    .loc 1 12 0
    mv  a0,a2
.LVL5:
    ret
.LVL6:
.L4:
    .loc 1 6 0
    li  a2,0
    .loc 1 12 0
    mv  a0,a2
.LVL7:
    ret
.LFE0:
    .size   Fibonacci, .-Fibonacci
    .section    .text.startup,"ax",@progbits
    .align  2
    .globl  main
    .type   main, @function
main:
.LFB1:
    .loc 1 14 0
.LVL8:
.LBB4:
.LBB5:
    .loc 1 7 0
    li  a5,20
    .loc 1 5 0
    li  a3,1
    li  a4,1
    j   .L8
.LVL9:
.L9:
    .loc 1 7 0
    mv  a4,a0
.LVL10:
.L8:
    add a5,a5,-1
    add a0,a4,a3
.LVL11:
    mv  a3,a4
    .loc 1 6 0
    bnez    a5,.L9
.LVL12:
.LBE5:
.LBE4:
    .loc 1 18 0
    add a0,a0,1
    ret
.LFE1:
    .size   main, .-main
    .section    .debug_frame,"",@progbits
.Lframe0:
    .4byte  .LECIE0-.LSCIE0
.LSCIE0:
    .4byte  0xffffffff
    .byte   0x3
    .string ""
    .byte   0x1
    .byte   0x7c
    .byte   0x1
    .byte   0xc
    .byte   0x2
    .byte   0
    .align  2
.LECIE0:
.LSFDE0:
    .4byte  .LEFDE0-.LASFDE0
.LASFDE0:
    .4byte  .Lframe0
    .4byte  .LFB0
    .4byte  .LFE0-.LFB0
    .align  2
.LEFDE0:
.LSFDE2:
    .4byte  .LEFDE2-.LASFDE2
.LASFDE2:
    .4byte  .Lframe0
    .4byte  .LFB1
    .4byte  .LFE1-.LFB1
    .align  2
.LEFDE2:
    .text
.Letext0:
    .section    .debug_info,"",@progbits
.Ldebug_info0:
    .4byte  0x102
    .2byte  0x4
    .4byte  .Ldebug_abbrev0
    .byte   0x4
    .byte   0x1
    .4byte  .LASF0
    .byte   0xc
    .4byte  .LASF1
    .4byte  .LASF2
    .4byte  .Ldebug_ranges0+0
    .4byte  0
    .4byte  .Ldebug_line0
    .byte   0x2
    .4byte  .LASF3
    .byte   0x1
    .byte   0xe
    .4byte  0x81
    .4byte  .LFB1
    .4byte  .LFE1-.LFB1
    .byte   0x1
    .byte   0x9c
    .4byte  0x81
    .byte   0x3
    .string "ret"
    .byte   0x1
    .byte   0xf
    .4byte  0x81
    .byte   0x4
    .4byte  0x88
    .4byte  .LBB4
    .4byte  .LBE4-.LBB4
    .byte   0x1
    .byte   0x10
    .byte   0x5
    .4byte  0x98
    .4byte  .LLST5
    .byte   0x6
    .4byte  .LBB5
    .4byte  .LBE5-.LBB5
    .byte   0x7
    .4byte  0xe0
    .byte   0x7
    .4byte  0xe9
    .byte   0x7
    .4byte  0xf2
    .byte   0x7
    .4byte  0xfb
    .byte   0
    .byte   0
    .byte   0
    .byte   0x8
    .byte   0x4
    .byte   0x5
    .string "int"
    .byte   0x9
    .4byte  .LASF4
    .byte   0x1
    .byte   0x3
    .4byte  0x81
    .byte   0x1
    .4byte  0xc8
    .byte   0xa
    .4byte  .LASF5
    .byte   0x1
    .byte   0x3
    .4byte  0x81
    .byte   0x3
    .string "i"
    .byte   0x1
    .byte   0x4
    .4byte  0x81
    .byte   0x3
    .string "x"
    .byte   0x1
    .byte   0x4
    .4byte  0x81
    .byte   0x3
    .string "y"
    .byte   0x1
    .byte   0x4
    .4byte  0x81
    .byte   0x3
    .string "z"
    .byte   0x1
    .byte   0x4
    .4byte  0x81
    .byte   0
    .byte   0xb
    .4byte  0x88
    .4byte  .LFB0
    .4byte  .LFE0-.LFB0
    .byte   0x1
    .byte   0x9c
    .byte   0x5
    .4byte  0x98
    .4byte  .LLST0
    .byte   0xc
    .4byte  0xa3
    .4byte  .LLST1
    .byte   0xc
    .4byte  0xac
    .4byte  .LLST2
    .byte   0xc
    .4byte  0xb5
    .4byte  .LLST3
    .byte   0xc
    .4byte  0xbe
    .4byte  .LLST4
    .byte   0
    .byte   0
    .section    .debug_abbrev,"",@progbits
.Ldebug_abbrev0:
    .byte   0x1
    .byte   0x11
    .byte   0x1
    .byte   0x25
    .byte   0xe
    .byte   0x13
    .byte   0xb
    .byte   0x3
    .byte   0xe
    .byte   0x1b
    .byte   0xe
    .byte   0x55
    .byte   0x17
    .byte   0x11
    .byte   0x1
    .byte   0x10
    .byte   0x17
    .byte   0
    .byte   0
    .byte   0x2
    .byte   0x2e
    .byte   0x1
    .byte   0x3f
    .byte   0x19
    .byte   0x3
    .byte   0xe
    .byte   0x3a
    .byte   0xb
    .byte   0x3b
    .byte   0xb
    .byte   0x49
    .byte   0x13
    .byte   0x11
    .byte   0x1
    .byte   0x12
    .byte   0x6
    .byte   0x40
    .byte   0x18
    .byte   0x97,0x42
    .byte   0x19
    .byte   0x1
    .byte   0x13
    .byte   0
    .byte   0
    .byte   0x3
    .byte   0x34
    .byte   0
    .byte   0x3
    .byte   0x8
    .byte   0x3a
    .byte   0xb
    .byte   0x3b
    .byte   0xb
    .byte   0x49
    .byte   0x13
    .byte   0
    .byte   0
    .byte   0x4
    .byte   0x1d
    .byte   0x1
    .byte   0x31
    .byte   0x13
    .byte   0x11
    .byte   0x1
    .byte   0x12
    .byte   0x6
    .byte   0x58
    .byte   0xb
    .byte   0x59
    .byte   0xb
    .byte   0
    .byte   0
    .byte   0x5
    .byte   0x5
    .byte   0
    .byte   0x31
    .byte   0x13
    .byte   0x2
    .byte   0x17
    .byte   0
    .byte   0
    .byte   0x6
    .byte   0xb
    .byte   0x1
    .byte   0x11
    .byte   0x1
    .byte   0x12
    .byte   0x6
    .byte   0
    .byte   0
    .byte   0x7
    .byte   0x34
    .byte   0
    .byte   0x31
    .byte   0x13
    .byte   0
    .byte   0
    .byte   0x8
    .byte   0x24
    .byte   0
    .byte   0xb
    .byte   0xb
    .byte   0x3e
    .byte   0xb
    .byte   0x3
    .byte   0x8
    .byte   0
    .byte   0
    .byte   0x9
    .byte   0x2e
    .byte   0x1
    .byte   0x3f
    .byte   0x19
    .byte   0x3
    .byte   0xe
    .byte   0x3a
    .byte   0xb
    .byte   0x3b
    .byte   0xb
    .byte   0x27
    .byte   0x19
    .byte   0x49
    .byte   0x13
    .byte   0x20
    .byte   0xb
    .byte   0x1
    .byte   0x13
    .byte   0
    .byte   0
    .byte   0xa
    .byte   0x5
    .byte   0
    .byte   0x3
    .byte   0xe
    .byte   0x3a
    .byte   0xb
    .byte   0x3b
    .byte   0xb
    .byte   0x49
    .byte   0x13
    .byte   0
    .byte   0
    .byte   0xb
    .byte   0x2e
    .byte   0x1
    .byte   0x31
    .byte   0x13
    .byte   0x11
    .byte   0x1
    .byte   0x12
    .byte   0x6
    .byte   0x40
    .byte   0x18
    .byte   0x97,0x42
    .byte   0x19
    .byte   0
    .byte   0
    .byte   0xc
    .byte   0x34
    .byte   0
    .byte   0x31
    .byte   0x13
    .byte   0x2
    .byte   0x17
    .byte   0
    .byte   0
    .byte   0
    .section    .debug_loc,"",@progbits
.Ldebug_loc0:
.LLST5:
    .4byte  .LVL8
    .4byte  .LVL12
    .2byte  0x2
    .byte   0x44
    .byte   0x9f
    .4byte  0
    .4byte  0
.LLST0:
    .4byte  .LVL0
    .4byte  .LVL5
    .2byte  0x1
    .byte   0x5a
    .4byte  .LVL5
    .4byte  .LVL6
    .2byte  0x4
    .byte   0xf3
    .byte   0x1
    .byte   0x5a
    .byte   0x9f
    .4byte  .LVL6
    .4byte  .LVL7
    .2byte  0x1
    .byte   0x5a
    .4byte  .LVL7
    .4byte  .LFE0
    .2byte  0x4
    .byte   0xf3
    .byte   0x1
    .byte   0x5a
    .byte   0x9f
    .4byte  0
    .4byte  0
.LLST1:
    .4byte  .LVL0
    .4byte  .LVL1
    .2byte  0x2
    .byte   0x30
    .byte   0x9f
    .4byte  .LVL1
    .4byte  .LVL3
    .2byte  0x1
    .byte   0x5f
    .4byte  .LVL3
    .4byte  .LVL4
    .2byte  0x3
    .byte   0x7f
    .byte   0x7f
    .byte   0x9f
    .4byte  .LVL4
    .4byte  .LVL6
    .2byte  0x1
    .byte   0x5f
    .4byte  .LVL6
    .4byte  .LFE0
    .2byte  0x2
    .byte   0x30
    .byte   0x9f
    .4byte  0
    .4byte  0
.LLST2:
    .4byte  .LVL0
    .4byte  .LVL1
    .2byte  0x2
    .byte   0x31
    .byte   0x9f
    .4byte  .LVL1
    .4byte  .LVL2
    .2byte  0x1
    .byte   0x5c
    .4byte  .LVL2
    .4byte  .LVL4
    .2byte  0x1
    .byte   0x5e
    .4byte  .LVL4
    .4byte  .LVL6
    .2byte  0x1
    .byte   0x5c
    .4byte  .LVL6
    .4byte  .LFE0
    .2byte  0x2
    .byte   0x31
    .byte   0x9f
    .4byte  0
    .4byte  0
.LLST3:
    .4byte  .LVL0
    .4byte  .LVL1
    .2byte  0x2
    .byte   0x31
    .byte   0x9f
    .4byte  .LVL1
    .4byte  .LVL4
    .2byte  0x1
    .byte   0x5d
    .4byte  .LVL4
    .4byte  .LVL6
    .2byte  0x1
    .byte   0x5e
    .4byte  .LVL6
    .4byte  .LFE0
    .2byte  0x2
    .byte   0x31
    .byte   0x9f
    .4byte  0
    .4byte  0
.LLST4:
    .4byte  .LVL1
    .4byte  .LVL2
    .2byte  0x1
    .byte   0x5c
    .4byte  .LVL4
    .4byte  .LVL6
    .2byte  0x1
    .byte   0x5c
    .4byte  0
    .4byte  0
    .section    .debug_aranges,"",@progbits
    .4byte  0x24
    .2byte  0x2
    .4byte  .Ldebug_info0
    .byte   0x4
    .byte   0
    .2byte  0
    .2byte  0
    .4byte  .Ltext0
    .4byte  .Letext0-.Ltext0
    .4byte  .LFB1
    .4byte  .LFE1-.LFB1
    .4byte  0
    .4byte  0
    .section    .debug_ranges,"",@progbits
.Ldebug_ranges0:
    .4byte  .Ltext0
    .4byte  .Letext0
    .4byte  .LFB1
    .4byte  .LFE1
    .4byte  0
    .4byte  0
    .section    .debug_line,"",@progbits
.Ldebug_line0:
    .section    .debug_str,"MS",@progbits,1
.LASF5:
    .string "loop"
.LASF1:
    .string "Fibonacci/code.c"
.LASF2:
    .string "/home/akaki/windows_workspace/RSD/Processor/Src/Verification/TestCode/C"
.LASF3:
    .string "main"
.LASF0:
    .string "GNU C11 7.1.1 20170509 -mstrict-align -march=rv32i -mabi=ilp32 -g -O3 -fno-stack-protector -fno-zero-initialized-in-bss -ffreestanding -fno-builtin"
.LASF4:
    .string "Fibonacci"
    .ident  "GCC: (GNU) 7.1.1 20170509"
