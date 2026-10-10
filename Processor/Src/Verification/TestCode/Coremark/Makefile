# Public CoreMark; fetch explicitly before building.
COREMARK_URL = https://github.com/eembc/coremark.git
COREMARK_REVISION = d5fad6bd094899101a4e5fd53af7298160ced6ab
VARIANTS = Coremark Coremark_for_RV32I

# The same Makefile is used inside each output directory.
ifneq ($(COREMARK_ARCH),)
include ../../Makefile.inc
ARCHFLAGS = -march=$(COREMARK_ARCH)_zicsr_zifencei -mabi=ilp32
LIBRARY_ARCHFLAGS = -march=$(COREMARK_ARCH) -mabi=ilp32
# This integer-only port needs GCC helpers, but no libc or math library.
LIBGCC = -lgcc
DUMMY_ROM = dummy_rom.bin
XCFLAGS = -I.. -I../External -DITERATIONS=1
CORE_SRCS = core_list_join.c core_main.c core_matrix.c core_state.c core_util.c
OBJS = $(CORE_SRCS:.c=.o) core_portme.o ee_printf.o rsd-crt.o rsd-loader.o
BUILD_MAKEFILES = ../Makefile ../../Makefile.inc
vpath %.c ../External ..

%.o: %.c $(BUILD_MAKEFILES)
	$(CC) $(CFLAGS) $(XCFLAGS) -MMD -MP -c $< -o $@

rsd-crt.o: $(CRTASM) $(BUILD_MAKEFILES)
	$(CC) $(CFLAGS) -MMD -MP -x assembler-with-cpp -c $< -o $@
rsd-loader.o: $(LDSRC) $(BUILD_MAKEFILES)
	$(CC) $(CFLAGS) -MMD -MP -c $< -o $@

# Adapt only the UART stub; keep the downloaded source and its license intact.
ee_printf.c: ../External/barebones/ee_printf.c ../Makefile
	sed '/^#error.*uart_send_char/c\    extern void serial_out_char(char); serial_out_char(c);' $< > $@

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

# CRC expectations are fixed; only the compiler version comes from the toolchain.
serial.ref.txt: ../serial.ref.txt.in $(BUILD_MAKEFILES)
	sed -e 's/@GCC_VERSION@/$(shell $(CC) -dumpfullversion -dumpversion)/' -e 's/@COMPILER_FLAGS@//' $< > $@

-include $(OBJS:.o=.d)
else
.DEFAULT_GOAL := all
.PHONY: all fetch check-source clean $(VARIANTS)
all: $(VARIANTS)

fetch:
	@if test -e External; then \
		$(MAKE) check-source; \
	else \
		git clone --no-checkout $(COREMARK_URL) External && \
		git -C External checkout --detach $(COREMARK_REVISION); \
	fi

check-source:
	@test -d External/.git || { echo "Run make test-fetch-Coremark from Processor/Src first." >&2; exit 1; }
	@test "$$(git -C External rev-parse HEAD)" = "$(COREMARK_REVISION)" || { echo "CoreMark revision differs from COREMARK_REVISION in Makefile." >&2; exit 1; }
	@git -C External diff --quiet HEAD || { echo "CoreMark External has local changes; preserve or revert them before building." >&2; exit 1; }

Coremark: COREMARK_ARCH = rv32im
Coremark_for_RV32I: COREMARK_ARCH = rv32i
$(VARIANTS): check-source
	$(MAKE) -C $@ -f ../Makefile COREMARK_ARCH=$(COREMARK_ARCH) code.hex serial.ref.txt

# Preserve the checkout and the tracked test configuration.
clean:
	rm -f $(foreach dir,$(VARIANTS),$(addprefix $(dir)/,*.o *.d code.elf code.bin code.rom.bin code.hex code.dump dummy_rom.bin ee_printf.c serial.ref.txt reg.out.hex serial.out.txt *.log))
endif
