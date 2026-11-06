#ifndef RSD_RVMODEL_MACROS_H
#define RSD_RVMODEL_MACROS_H

// Keep instruction tests in M-mode when U is enabled in the profile.
// Privileged tests enter S/U-mode explicitly through the ACT4 trap handler.
#ifndef BOOT_TO_MMODE
#define BOOT_TO_MMODE
#endif

.pushsection .text.reset,"ax",@progbits
.option push
.option norvc
.global _rsd_reset
_rsd_reset:
  j rvtest_entry_point
_rsd_goal:
  j _rsd_goal
.option pop
.popsection

#define RVMODEL_DATA_SECTION

// Unmapped in both RSD and Sail, including adjacent misaligned addresses.
#define RVMODEL_ACCESS_FAULT_ADDRESS 0x20000000

// Privileged tests allocate a trap signature before including this file.
#if defined(TRAP_SIGUPD_COUNT) && TRAP_SIGUPD_COUNT > 0
#define STANDARD_SM_SUPPORTED
// Install both handlers without initializing unsupported HPM CSRs.
#ifdef S_SUPPORTED
#define RSD_ACT4_INIT_S \
  csrw mideleg, zero; \
  csrw medeleg, zero; \
  RVTEST_TRAP_PROLOG S; \
  csrw sepc, zero; \
  csrw stval, zero; \
  csrw scause, zero
#else
#define RSD_ACT4_INIT_S
#endif
#define RVMODEL_BOOT_TO_MMODE \
  csrw mie, zero; \
  csrw mip, zero; \
  RVTEST_TRAP_PROLOG M; \
  RSD_ACT4_INIT_S; \
  li t0, 0x1800; \
  csrw mstatus, t0; \
  csrw mepc, zero; \
  csrw mtval, zero; \
  csrw mcause, zero
#else
// Unexpected traps in integer/CSR instruction tests fail directly.
#define RVMODEL_BOOT_TO_MMODE \
  la t0, rvmodel_halt_fail; \
  csrw mtvec, t0
#endif

// ACT4 calls these only after checking its embedded Sail-generated results.
// Drain pending UART writes before entering the termination loop.
#define RSD_ACT4_HALT(_STATUS) \
  li a0, _STATUS; \
  fence iorw, iorw; \
  la t0, _rsd_goal; \
  jr t0
#define RVMODEL_HALT_PASS RSD_ACT4_HALT(0)
#define RVMODEL_HALT_FAIL RSD_ACT4_HALT(1)

#define RVMODEL_IO_WRITE_STR(_R1, _R2, _R3, _STR_PTR) \
  li _R2, 0x40002000; \
1: lbu _R1, 0(_STR_PTR); \
  beqz _R1, 2f; \
  sw _R1, 0(_R2); \
  addi _STR_PTR, _STR_PTR, 1; \
  j 1b; \
2:

// RSD CLINT addresses used by ACT4; the trap prolog parks the timer.
#define RVMODEL_MTIME_ADDRESS 0x40017ff8
#define RVMODEL_MTIMECMP_ADDRESS 0x40014000
#define RVMODEL_MSIP_ADDRESS 0x40010000

// Allow interrupt propagation and keep delayed MTI pending after WFI setup.
#define RVMODEL_INTERRUPT_LATENCY 10
#define RVMODEL_TIMER_INT_SOON_DELAY 10000

// With EnableUART_Interrupts, TestMain consumes UART DC1/DC3 as source-1
// assert/deassert commands. Sail substitutes its own interrupt device.
#define RSD_ACT4_SET_EXT(_R1, _R2, _CTX) \
  li _R2, 0xc0000004; \
  li _R1, 1; \
  sw _R1, 0(_R2); \
  li _R2, (0xc0002000 + (1 - _CTX) * 0x80); \
  sw zero, 0(_R2); \
  li _R2, (0xc0002000 + _CTX * 0x80); \
  li _R1, 2; \
  sw _R1, 0(_R2); \
  li _R2, (0xc0200000 + _CTX * 0x1000); \
  sw zero, 0(_R2); \
  li _R2, 0x40002000; \
  li _R1, 0x11; \
  sw _R1, 0(_R2); \
  fence iorw, iorw

// Deassert the level before completing, so the gateway cannot re-pend it.
#define RSD_ACT4_CLR_EXT(_R1, _R2, _CTX) \
  li _R2, 0x40002000; \
  li _R1, 0x13; \
  sw _R1, 0(_R2); \
  fence iorw, iorw; \
  li _R2, (0xc0200004 + _CTX * 0x1000); \
  lw _R1, 0(_R2); \
  sw _R1, 0(_R2); \
  fence iorw, iorw

#define RVMODEL_SET_MEXT_INT(_R1, _R2) RSD_ACT4_SET_EXT(_R1, _R2, 0)
#define RVMODEL_CLR_MEXT_INT(_R1, _R2) RSD_ACT4_CLR_EXT(_R1, _R2, 0)
#define RVMODEL_SET_SEXT_INT(_R1, _R2) RSD_ACT4_SET_EXT(_R1, _R2, 1)
#define RVMODEL_CLR_SEXT_INT(_R1, _R2) RSD_ACT4_CLR_EXT(_R1, _R2, 1)

#endif
