OUTPUT_ARCH("riscv")
ENTRY(_rsd_reset)

MEMORY {
  rom (rx) : ORIGIN = 0x1000, LENGTH = 0xf000
  ram (rw) : ORIGIN = 0x80000000, LENGTH = 0x40000
}

SECTIONS {
  /* Reset and the TestDriver's fixed goal PC must remain at 0x1000/0x1004. */
  .text.reset 0x1000 : { KEEP(*(.text.reset)) } > rom
  .text.init : { *(.text.init) } > rom
  .text.rvtest : { *(.text.rvtest) *(.text.rvtest.*) } > rom

  .data 0x80000000 : {
    *(.rodata) *(.rodata.*) *(.srodata) *(.srodata.*)
    *(.data) *(.data.*) *(.sdata) *(.sdata.*)
  } > ram
  .bss (NOLOAD) : {
    . = ALIGN(16);
    __bss_start = .;
    *(.sbss) *(.sbss.*) *(.bss) *(.bss.*) *(COMMON)
    . = ALIGN(16);
    __bss_end = .;
    __stack_bottom = .;
    . += 0x1000;
    __stack_top = .;
  } > ram

  /* DUT/Sail IO code differs in size: keep it after test data so that
     signature addresses are identical in the reference and self-check ELFs. */
  .text.rvmodel : { *(.text.rvmodel) *(.text.rvmodel.*) *(.text) *(.text.*) } > rom
  .tohost : { *(.tohost) } > ram
}
