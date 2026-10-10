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

// Reset already enters M-mode with interrupts disabled. This initial port
// runs unprivileged tests only; do not enable STANDARD_SM_SUPPORTED yet.
#define RVMODEL_BOOT_TO_MMODE \
  la t0, rvmodel_halt_fail; \
  csrw mtvec, t0

// ACT4 calls these only after checking its embedded Sail-generated results.
// Flush pending UART writes before reaching the TestDriver's goal PC.
#define RSD_ACT4_HALT(_STATUS) \
  li a0, _STATUS; \
  fence iorw, iorw; \
  j _rsd_goal
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

// Required framework definitions; interrupt tests are outside this first port.
#define RVMODEL_INTERRUPT_LATENCY 10
#define RVMODEL_TIMER_INT_SOON_DELAY 10000

#endif
