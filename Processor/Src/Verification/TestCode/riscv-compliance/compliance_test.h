#ifndef RSD_COMPLIANCE_TEST_H
#define RSD_COMPLIANCE_TEST_H

// The pinned sources use the old name of CSR 0x343.
#define mbadaddr mtval
#define RV_COMPLIANCE_RV32M
#define RV_COMPLIANCE_HALT

#define RV_COMPLIANCE_CODE_BEGIN \
    _rsd_main: ; \
    la a0, _rsd_unexpected_trap; \
    csrw mtvec, a0;
#define RV_COMPLIANCE_CODE_END j _rsd_finalize
#define RV_COMPLIANCE_DATA_BEGIN .balign 16; _rsd_begin_output_data:
#define RV_COMPLIANCE_DATA_END _rsd_end_output_data:

    .option nopic
    .text
    .balign 16
    .globl _start
_start:
    j _rsd_main
// Keep the common simulator exit address at 0x1004.
_rsd_goal:
    j _rsd_goal

// Exception tests install their own handlers. An unexpected trap must fail
// through the instruction limit, rather than proceed to signature output.
_rsd_unexpected_trap:
    j _rsd_unexpected_trap

_rsd_finalize:
    la a3, _rsd_begin_output_data
    la a4, _rsd_end_output_data
    li t0, 0x40002000
    la t1, _rsd_hex_digits

// Match the upstream reference format: 16 bytes per line, most significant
// byte first, with two lowercase hexadecimal characters for each byte.
_rsd_signature_line:
    addi a5, a3, 15
_rsd_signature_byte:
    lbu a2, 0(a5)
    srli a0, a2, 4
    add a0, a0, t1
    lbu a0, 0(a0)
    sw a0, 0(t0)
    andi a0, a2, 15
    add a0, a0, t1
    lbu a0, 0(a0)
    sw a0, 0(t0)
    addi a5, a5, -1
    bgeu a5, a3, _rsd_signature_byte
    li a0, 10
    sw a0, 0(t0)
    addi a3, a3, 16
    bne a3, a4, _rsd_signature_line
    // Wait for serial stores to complete before the simulator stops.
    fence iorw, iorw
    j _rsd_goal

    .section .rodata
_rsd_hex_digits:
    .ascii "0123456789abcdef"
    .text

#endif // RSD_COMPLIANCE_TEST_H
