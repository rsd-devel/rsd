# Public Dhrystone 2.1; fetch explicitly before building.
DHRYSTONE_URL = https://github.com/sifive/benchmark-dhrystone.git
DHRYSTONE_REVISION = 0ddff533cc9052c524990d5ace4560372053314b
DHRYSTONE_BUILTINS ?= 1
ifneq ($(DHRYSTONE_BUILTINS),0)
ifneq ($(DHRYSTONE_BUILTINS),1)
$(error DHRYSTONE_BUILTINS must be 0 or 1)
endif
endif

# The same Makefile is used inside the output directory.
ifeq ($(DHRYSTONE_BUILD),1)
include ../../Makefile.inc
ARCHFLAGS = -march=rv32im_zicsr_zifencei -mabi=ilp32
LIBRARY_ARCHFLAGS = -march=rv32im -mabi=ilp32
LIBGCC = -lgcc
# Use picolibc's strcpy/strcmp; the port supplies allocation, time and output.
LIBC = -lc
ifeq ($(DHRYSTONE_BUILTINS),1)
# Override the shared -fno-builtin after -ffreestanding, for this test only.
CFLAGS += -fbuiltin
endif
DUMMY_ROM = dummy_rom.bin
# The upstream C uses K&R definitions and implicit procedure declarations.
XCFLAGS = -I../External -include string.h -std=gnu99 -DTIME -DDHRY_ITERS=100 \
	-Wno-implicit-int -Wno-implicit-function-declaration
OBJS = dhrystone_port.o dhry_2.o rsd-crt.o rsd-loader.o
BUILD_MAKEFILES = ../Makefile ../../Makefile.inc .builtin-config
vpath %.c ../External ..

# Recompile when toggling builtins, including when switching back to zero.
.PHONY: force-builtin-config
.builtin-config: force-builtin-config
	@if ! test -f $@ || test "$$(cat $@)" != "$(DHRYSTONE_BUILTINS)"; then \
		printf '%s\n' "$(DHRYSTONE_BUILTINS)" > $@; \
	fi

%.o: %.c $(BUILD_MAKEFILES)
	$(CC) $(CFLAGS) $(XCFLAGS) -MMD -MP -c $< -o $@

rsd-crt.o: $(CRTASM) $(BUILD_MAKEFILES)
	$(CC) $(CFLAGS) -MMD -MP -x assembler-with-cpp -c $< -o $@
rsd-loader.o: $(LDSRC) $(BUILD_MAKEFILES)
	$(CC) $(CFLAGS) -MMD -MP -c $< -o $@

code.elf: $(OBJS) $(LDSCRIPT) $(BUILD_MAKEFILES)
	$(LD) -o $@ rsd-crt.o rsd-loader.o $(filter-out rsd-crt.o rsd-loader.o,$(OBJS)) $(LIBGCC) $(LIBC) -T$(LDSCRIPT) $(LDFLAGS)
$(DUMMY_ROM): $(BUILD_MAKEFILES)
	head -c $(ROM_PADDING_SIZE) /dev/zero > $@
code.bin: code.elf $(DUMMY_ROM) $(BUILD_MAKEFILES)
	$(OBJDUMP) -D $< > code.dump
	$(ROM_COPY) $< code.rom.bin
	cat $(DUMMY_ROM) code.rom.bin > $@
code.hex: code.bin $(RSD_TEST_TOOL_ROOT)/BinaryToHex.py $(BUILD_MAKEFILES)
	$(BIN_TO_HEX) $< $@ $(BIN_SIZE)

-include $(OBJS:.o=.d)
else
.DEFAULT_GOAL := all
.PHONY: all fetch check-source clean
all: check-source
	$(MAKE) -C Dhrystone -f ../Makefile DHRYSTONE_BUILD=1 code.hex

fetch:
	@if test -e External; then \
		$(MAKE) check-source; \
	else \
		git clone --no-checkout $(DHRYSTONE_URL) External && \
		git -C External checkout --detach $(DHRYSTONE_REVISION); \
	fi

check-source:
	@test -d External/.git || { echo "Run make test-fetch-Dhrystone from Processor/Src first." >&2; exit 1; }
	@test "$$(git -C External rev-parse HEAD)" = "$(DHRYSTONE_REVISION)" || { echo "Dhrystone revision differs from DHRYSTONE_REVISION in Makefile." >&2; exit 1; }
	@git -C External diff --quiet HEAD || { echo "Dhrystone External has local changes; preserve or revert them before building." >&2; exit 1; }

# Preserve the checkout and tracked test inputs.
clean:
	rm -f $(addprefix Dhrystone/,*.o *.d code.elf code.bin code.rom.bin code.hex code.dump dummy_rom.bin reg.out.hex serial.out.txt *.log .builtin-config)
endif
