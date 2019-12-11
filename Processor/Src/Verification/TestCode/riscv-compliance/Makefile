#
# Do "make" on the lower directory
#

# Copy files only if RSD_ENV is defined
ifdef RSD_ENV

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

SRC_DIR = $(RSD_ENV)/Tools/Testbench/riscv-compliance/
.DEFAULT: all
all: 
	cd $(SRC_DIR); $(MAKE)

env-clean: clean
	cd $(SRC_DIR); $(MAKE) clean


# By making $(SRC_DIRS) a pseudo target with PHONY,
# run every time regardless of timestamp
.PHONY: $(SRC_TESTS)
$(SRC_TESTS):
	cp $(SRC_DIR)/work/rv32i/$@ ./ -r -a

#	mkdir ./work/rv32i/references -p
#	cp $(SRC_DIR)/work/rv32i/$@.hex ./work/rv32i -r -a
#	cp $(SRC_DIR)/work/rv32i/references/$@.reference_output ./work/rv32i/reference -r -a
#	cp $(SRC_DIR)/work/verify.sh ./work


copy: $(SRC_TESTS)

clean: 
	rm $(SRC_TESTS) -r -f


else	# ifdef RSD_ENV

# Do nothing

all: 
env-clean:
copy:
clean: 

endif	# ifdef RSD_ENV

