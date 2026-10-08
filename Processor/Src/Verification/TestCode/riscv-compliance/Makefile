# Preserve the existing RV32I suite; fetch explicitly before building.
COMPLIANCE_URL = https://github.com/riscv/riscv-compliance.git
COMPLIANCE_REVISION = 797ce6cb945f8567303c4fc78eb5d80f9b817db5
SUITE = External/riscv-test-suite/rv32i
TESTS = $(basename $(notdir $(wildcard $(SUITE)/src/*.S)))

include ../Makefile.inc
ARCHFLAGS = -march=rv32i -mabi=ilp32
LIBRARY_ARCHFLAGS = $(ARCHFLAGS)
DUMMY_ROM = dummy_rom.bin
# The simulator loads the first 64 KiB into ROM, then 32 KiB into RAM.
BIN_SIZE = 0x18000
BUILD_MAKEFILES = Makefile ../Makefile.inc
HEADERS = compliance_test.h compliance_io.h External/riscv-test-env/test_macros.h

.DEFAULT_GOAL := all
.PHONY: all fetch check-source clean
all: check-source $(TESTS:%=%/code.hex) $(TESTS:%=%/cfg.xml) $(TESTS:%=%/serial.ref.txt)

fetch:
	@if test -e External; then \
		$(MAKE) check-source; \
	else \
		git init -q External && \
		git -C External remote add origin $(COMPLIANCE_URL) && \
		git -C External fetch --depth=1 origin $(COMPLIANCE_REVISION) && \
		git -C External checkout --detach $(COMPLIANCE_REVISION); \
	fi

check-source:
	@test -d External/.git || { echo "Run make test-fetch-riscv-compliance from Processor/Src first." >&2; exit 1; }
	@test "$$(git -C External rev-parse HEAD)" = "$(COMPLIANCE_REVISION)" || { echo "riscv-compliance revision differs from COMPLIANCE_REVISION in Makefile." >&2; exit 1; }
	@git -C External diff --quiet HEAD || { echo "riscv-compliance External has local changes; preserve or revert them before building." >&2; exit 1; }

%/code.o: $(SUITE)/src/%.S $(HEADERS) $(BUILD_MAKEFILES) | check-source
	mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -I. -IExternal/riscv-test-env -MMD -MP -c $< -o $@

%/code.elf: %/code.o $(LDSCRIPT) $(BUILD_MAKEFILES)
	$(LD) -o $@ $< -T$(LDSCRIPT) $(LDFLAGS) -Wl,--no-relax
	$(OBJDUMP) -D $@ > $(dir $@)code.dump

$(DUMMY_ROM): $(BUILD_MAKEFILES)
	head -c $(ROM_PADDING_SIZE) /dev/zero > $@

# These assembly tests have their own entry point and no data-copy loader.
# Place initialized data directly in the simulator's RAM image.
%/code.bin: %/code.elf $(DUMMY_ROM) $(BUILD_MAKEFILES)
	$(OBJCOPY) -O binary --only-section .text --only-section .rodata --only-section .srodata --pad-to=$(ROM_END_ADDR) $< $(dir $@)code.rom.bin
	$(OBJCOPY) -O binary --only-section .data $< $(dir $@)code.ram.bin
	cat $(DUMMY_ROM) $(dir $@)code.rom.bin $(dir $@)code.ram.bin > $@

%/code.hex: %/code.bin $(RSD_TEST_TOOL_ROOT)/BinaryToHex.py $(BUILD_MAKEFILES)
	$(BIN_TO_HEX) $< $@ $(BIN_SIZE)

%/cfg.xml: cfg.xml
	mkdir -p $(dir $@)
	cp $< $@

%/serial.ref.txt: $(SUITE)/references/%.reference_output | check-source
	mkdir -p $(dir $@)
	cp $< $@

# Case directories contain only generated files; preserve External and adapters.
clean:
	rm -rf $(wildcard I-*) $(DUMMY_ROM)

.SECONDARY:
-include $(TESTS:%=%/code.d)
