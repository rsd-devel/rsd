#ifndef RSD_RVMODEL_MACROS_H
#define RSD_RVMODEL_MACROS_H

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
// Install ACT4's M-mode trap handler without initializing unsupported HPM CSRs.
#define RVMODEL_BOOT_TO_MMODE \
  csrw mie, zero; \
  csrw mip, zero; \
  RVTEST_TRAP_PROLOG M; \
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

#endif
