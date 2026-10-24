include ../Makefile.inc

.DEFAULT_GOAL := all
.PHONY: all clean


# --------
# ソースディレクトリのリスト
# 各ディレクトリには code.s が1つ存在している前提
#

SRC_DIRS = \
    ControlTransfer \
	IntRegImm \
	IntRegReg \
	LoadAndStore \
	ControlTransferZynq \
	IntRegImmZynq \
	IntRegRegZynq \
	LoadAndStoreZynq \
	ZeroRegister \
	MemoryAccessZynq \
	ReplayQueueTest \
	DynamicRecovery \
	MemoryDependencyPrediction \
	IntMulZynq \
	IntDivZynq \
	DividerTest \
	Gshare \
	Fence \
	CSR \
	ENV \
	Timer \
	MSWI \
	Fault \
	MisalignedMemAccess \
	UncachableLoadAndStore \
	CacheFlush \
    FP \
    Aext \

# Keep FP artifacts in the clean target regardless of the configuration.
ifeq ($(RSD_HAS_FP)$(filter clean,$(MAKECMDGOALS)),0)
SRC_DIRS := $(filter-out FP,$(SRC_DIRS))
endif

# 中間ファイルのリスト
ASM_SRCS  = $(SRC_DIRS:%=%/code.s)
ASM_OBJS  = $(SRC_DIRS:%=%/code.o)
ASM_ELFS  = $(SRC_DIRS:%=%/code.elf)
ASM_ROM_BINS  = $(SRC_DIRS:%=%/code.rom.bin)
# ASM_RAM.BINS  = $(SRC_DIRS:%=%/code.ram.bin)
ASM_BINS  = $(SRC_DIRS:%=%/code.bin)
ASM_DUMP  = $(SRC_DIRS:%=%/code.dump)
ASM_DSTS  = $(SRC_DIRS:%=%/code.hex)


# ----
# 生成ルール
# $(ASM_DSTS) の全ファイルを生成 -> 
#   各ファイルごとに依存関係を逆辿りすることで全体が生成される
#
$(ASM_OBJS): %.o: %.s Makefile ../Makefile.inc
	$(CC) $(CFLAGS) -MMD -MP -x assembler-with-cpp -o $@ -c $<

# LD の引数の順にアドレス空間に配置されるため，
# CRTOBJ は必ず先頭に置く必要がある
# また，$(LIBGCC) $(LIBC) -T$(LDSCRIPT) $(LDFLAGS) は
# $(OBJS) が依存しているためその後ろに置く必要がある．
%.elf: %.o $(CRTOBJ) $(LDOBJ) $(LDSCRIPT) Makefile ../Makefile.inc
	$(LD) -o $@ $(CRTOBJ) $(LDOBJ) $< $(LIBC) $(LIBGCC) $(LIBC) -T$(LDSCRIPT) $(LDFLAGS)
	$(OBJDUMP) -S -D $@ > $(basename $<).dump	# for debug

# ELF から必要なセクションを取り出した code.rom.bin を作る
# cat を使って，先頭 4KB のダミー，ROM の順に結合
# ダミーは ROM が 0x1000 がはじまるため
%.bin: %.elf $(DUMMY_ROM) Makefile ../Makefile.inc
	$(ROM_COPY) $< $(basename $<).rom.bin
	cat $(DUMMY_ROM) $(basename $<).rom.bin > $@	

# HEX に変換
%.hex: %.bin $(RSD_TEST_TOOL_ROOT)/BinaryToHex.py Makefile ../Makefile.inc
	$(BIN_TO_HEX) $< $@ $(BIN_SIZE)

all: $(ASM_DSTS)


clean:
	rm $(ASM_DSTS) $(ASM_ELFS) $(ASM_BINS) $(ASM_ROM_BINS) $(ASM_OBJS) $(ASM_OBJS:.o=.d) $(ASM_DUMP) -f

# 中間ファイルが残るように
.PRECIOUS: $(ASM_DSTS) $(ASM_ELFS) $(ASM_BINS) $(ASM_ROM_BINS) $(ASM_OBJS)

-include $(ASM_OBJS:.o=.d)

