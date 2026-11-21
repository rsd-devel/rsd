# SPDX-License-Identifier: Apache-2.0
add_subdirectory(${ZEPHYR_BASE}/soc/common/riscv-privileged riscv-privileged)
zephyr_sources(console.c)
set(SOC_LINKER_SCRIPT ${ZEPHYR_BASE}/include/zephyr/arch/riscv/common/linker.ld CACHE INTERNAL "")
