# クロスコンパイル環境の読み込み
include $(RSD_ROOT)/Processor/Src/Verification/TestCode/Makefile.inc

# rsd-env の git の管理から除外するために，
# env 以下に全てをインストールする
# RVC: RISC-V Compliacne
RISCV_COMPLIANCE_WORK = $(RSD_ROOT)/Processor/ThirdParty/TestTargets/riscv-compliance/work
RISCV_COMPLIANCE_SRC = $(RISCV_COMPLIANCE_WORK)/riscv-compliance

RISCV_COMPLIANCE_URL = https://github.com/riscv/riscv-compliance
RISCV_COMPLIANCE_COMMIT_HASH = 797ce6cb945f8567303c4fc78eb5d80f9b817db5


.DEFAULT_GOAL = all



#
# --- Clone and build riscv-compliance
#


# checkout riscv-compliane
$(RISCV_COMPLIANCE_SRC): 
	mkdir $(RISCV_COMPLIANCE_WORK) -p
	cd $(RISCV_COMPLIANCE_WORK) ;\
		git clone $(RISCV_COMPLIANCE_URL);
	cd $(RISCV_COMPLIANCE_WORK)/riscv-compliance ;\
		git checkout $(RISCV_COMPLIANCE_COMMIT_HASH)

distclean-riscv-compliance:
	rm $(RISCV_COMPLIANCE_WORK) -r -f

# gcc にパスを通しておく必要がある
#export PATH = $(shell echo $$PATH):${RSD_GCC_PATH}/
#export RISCV_PREFIX = riscv32-unknown-elf-

#build-riscv-compliance: | $(RISCV_COMPLIANCE_SRC)
#	cd $(RISCV_COMPLIANCE_SRC) ;\
#		$(MAKE) RISCV_TARGET=riscvOVPsim  RISCV_DEVICE=rv32i
#clean-riscv-compliance:
#	cd $(RISCV_COMPLIANCE_SRC) ;\
#		$(MAKE) clean


#--------------------------------------
#
# --- Build binary and hex files for RSD
#

# from riscv-test-suite/rv32i/Makeflag
SRC_TESTS =    \
    I-ENDIANESS-01 \
    I-RF_x0-01 \
    I-RF_size-01 \
    I-RF_width-01 \
    I-MISALIGN_JMP-01 \
    I-MISALIGN_LDST-01 \
    I-DELAY_SLOTS-01 \
    I-JAL-01 \
    I-JALR-01 \
    I-LUI-01 \
    I-AUIPC-01 \
    I-LW-01 \
    I-LH-01 \
    I-LHU-01 \
    I-LB-01 \
    I-LBU-01 \
    I-SW-01 \
    I-SH-01 \
    I-SB-01 \
    I-ADD-01 \
    I-ADDI-01 \
    I-AND-01 \
    I-OR-01 \
    I-ORI-01 \
    I-XORI-01 \
    I-XOR-01 \
    I-SUB-01 \
    I-ANDI-01 \
    I-FENCE.I-01 \
    I-SLTI-01 \
    I-SLTIU-01 \
    I-BEQ-01 \
    I-BNE-01 \
    I-BLT-01 \
    I-BLTU-01 \
    I-BGE-01 \
    I-BGEU-01 \
    I-SRLI-01 \
    I-SLLI-01 \
    I-SRAI-01 \
    I-SLL-01 \
    I-SRL-01 \
    I-SRA-01 \
    I-SLT-01 \
    I-SLTU-01 \
    I-CSRRW-01 \
    I-CSRRWI-01 \
    I-NOP-01 \
    I-CSRRS-01 \
    I-CSRRSI-01 \
    I-CSRRC-01 \
    I-CSRRCI-01 \
    I-ECALL-01 \
    I-EBREAK-01 \
    I-IO \


SRC_DIR = $(RISCV_COMPLIANCE_SRC)/riscv-test-suite/rv32i/src
SRCS = $(SRC_TESTS:%=$(SRC_DIR)/%.S)

DST_DIR = ./work/rv32i
DST_HEX_FILES = $(SRC_TESTS:%=$(DST_DIR)/%/code.hex)

TARGET = ./target-rsd
XCFLAGS = -I $(TARGET) -I $(RISCV_COMPLIANCE_SRC)/riscv-test-env

TMP_ELFS = $(DST_HEX_FILES:%.hex=%.elf)
TMP_OBJS = $(DST_HEX_FILES:%.hex=%.o)
TMP_BINS = $(DST_HEX_FILES:%.hex=%.bin)
TMP_RAM_BINS = $(DST_HEX_FILES:%.hex=%.ram.bin)
TMP_ROM_BINS = $(DST_HEX_FILES:%.hex=%.rom.bin)
TMP_DUMPS = $(DST_HEX_FILES:%.hex=%.dump)

REF_DIR = $(RISCV_COMPLIANCE_SRC)/riscv-test-suite/rv32i/references


all: | $(RISCV_COMPLIANCE_SRC)
	$(MAKE) build

build:	$(DST_HEX_FILES) 
	cp $(REF_DIR) $(DST_DIR)/ -r
	cp $(RISCV_COMPLIANCE_SRC)/riscv-test-env/verify.sh $(DST_DIR)/../ -r
	
#%/code.o: $(SRC_DIR)/$(notdir %.S)
$(DST_DIR)/%/code.o: $(SRC_DIR)/%.S cfg.xml $(TARGET)/compliance_io.h $(TARGET)/compliance_test.h 
	mkdir $(dir $@) -p
	$(CC) $(CFLAGS) $(XCFLAGS) -o $@ -c $<
	cp cfg.xml $(dir $@)/
	cp $(REF_DIR)/$(basename $(notdir $<)).reference_output $(dir $@)/serial.ref.txt

# LD の引数の順にアドレス空間に配置されるため，
# CRTOBJ は必ず先頭に置く必要がある
# また，$(LIBGCC) $(LIBC) -T$(LDSCRIPT) $(LDFLAGS) は
# $(OBJS) が依存しているためその後ろに置く必要がある．
$(DST_DIR)/%/code.elf: $(DST_DIR)/%/code.o
	$(LD) -o $@ $< -T$(LDSCRIPT)
	$(OBJDUMP) -D $@ > $(basename $<).dump	# for debug

# ELF から必要なセクションを取り出した code.rom.bin/code.ram.bin を作る
# cat を使って，先頭 4KB のダミー，ROM，RAM の順に結合
# ダミーは ROM が 0x1000 がはじまるため
$(DST_DIR)/%/code.bin: $(DST_DIR)/%/code.elf $(DUMMY_ROM)
	$(ROM_COPY) $< $(basename $<).rom.bin
	$(RAM_COPY) $< $(basename $<).ram.bin
	cat $(DUMMY_ROM) $(basename $<).rom.bin $(basename $<).ram.bin > $@	

# HEX に変換
$(DST_DIR)/%/code.hex: $(DST_DIR)/%/code.bin
	$(BIN_TO_HEX) $< $@ $(BIN_SIZE)

clean:
	rm GDB_CommandFile padding.bin QEMU.log QEMU_Register -f
	rm $(TMP_ELFS) $(TMP_OBJS) $(TMP_RAM_BINS) $(TMP_ROM_BINS) $(TMP_BINS) $(TMP_DUMPS) -r -f

distclean: clean distclean-riscv-compliance
	rm $(DST_DIR) -r -f


# To preserve temporal files
.PRECIOUS: $(TMP_ELFS) $(TMP_OBJS) $(TMP_RAM_BINS) $(TMP_ROM_BINS) $(TMP_BINS) $(TMP_BINS) $(TMP_DUMPS)
