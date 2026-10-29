OUTPUT_ARCH("riscv")
ENTRY(_rsd_reset)

MEMORY {
  rom (rx) : ORIGIN = 0x1000, LENGTH = 0xf000
  ram (rw) : ORIGIN = 0x80000000, LENGTH = 0x40000
}

SECTIONS {
  /* Keep reset and the legacy termination loop at 0x1000/0x1004. */
  .text.reset 0x1000 : { KEEP(*(.text.reset)) } > rom
  .text.init : { *(.text.init) } > rom

  .data 0x80000000 : {
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
  .text.rvtest MAX(0x80010000, ALIGN(__stack_top, 0x1000)) : {
    *(.text.rvtest) *(.text.rvtest.*)
  } > ram

  /* DUT/Sail IO code differs in size: keep it after test data so that
     signature addresses are identical in the reference and self-check ELFs. */
  .text.rvmodel : { *(.text.rvmodel) *(.text.rvmodel.*) *(.text) *(.text.*) } > rom
  .tohost : { *(.tohost) } > ram
}
