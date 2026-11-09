OUTPUT_ARCH("riscv")
ENTRY(_rsd_reset)

INCLUDE ../rsd-memory-map.ld

MEMORY {
  rom (rx) : ORIGIN = RSD_ROM_BASE, LENGTH = RSD_ROM_SIZE
  ram (rw) : ORIGIN = RSD_RAM_BASE, LENGTH = RSD_RAM_SIZE
}

SECTIONS {
  /* Keep reset and the legacy termination loop at 0x1000/0x1004. */
  .text.reset RSD_RESET_VECTOR : { KEEP(*(.text.reset)) } > rom
  .text.init : { *(.text.init) } > rom

  .data RSD_RAM_BASE : {
    *(.rodata) *(.rodata.*) *(.srodata) *(.srodata.*)
    *(.data) *(.data.*) *(.sdata) *(.sdata.*)
  } > ram
  .bss ALIGN(ADDR(.data) + SIZEOF(.data), 16) (NOLOAD) : {
    . = ALIGN(16);
    __bss_start = .;
    *(.sbss) *(.sbss.*) *(.bss) *(.bss.*) *(COMMON)
    . = ALIGN(16);
    __bss_end = .;
    __stack_bottom = .;
    . += 0x1000;
    __stack_top = .;
    _end = .;
  } > ram
  /* Keep the usual code address, but leave room for larger exception data. */
  .text.rvtest MAX(RSD_RAM_BASE + 0x10000, ALIGN(__stack_top, 0x1000)) : {
    *(.text.rvtest) *(.text.rvtest.*)
  } > ram

  /* Keep interrupt helpers within JAL range of the test. DUT/Sail helpers
     differ in size, so place them after both test data and test code. */
  .text.rvmodel : { *(.text.rvmodel) *(.text.rvmodel.*) *(.text) *(.text.*) } > ram
  .tohost : { *(.tohost) } > ram
}
