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

# rom size over
    #fadd_b11-01 \
    fadd_b3-01 \
    fadd_b8-01 \
    fdiv_b21-01 \
    fdiv_b3-01 \
    fdiv_b8-01 \
    fdiv_b9-01 \
    feq_b19-01 \
    fle_b19-01 \
    flt_b19-01 \
    fmadd_b1-01 \
    fmadd_b15-01 \
    fmadd_b3-01 \
    fmadd_b8-01 \
    fmax_b19-01 \
    fmin_b19-01 \
    fmsub_b1-01 \
    fmsub_b15-01 \
    fmsub_b3-01 \
    fmsub_b8-01 \
    fmul_b3-01 \
    fmul_b8-01 \
    fmul_b9-01 \
    fnmadd_b1-01 \
    fnmadd_b15-01 \
    fnmadd_b3-01 \
    fnmadd_b8-01 \
    fnmsub_b1-01 \
    fnmsub_b15-01 \
    fnmsub_b3-01 \
    fnmsub_b8-01 \
    fsub_b11-01 \
    fsub_b3-01 \
    fsub_b8-01 \

SRC_F_TESTS =    \
    fadd_b1-01 \
    fadd_b10-01 \
    fadd_b12-01 \
    fadd_b13-01 \
    fadd_b2-01 \
    fadd_b4-01 \
    fadd_b5-01 \
    fadd_b7-01 \
    fclass_b1-01 \
    fcvt.s.w_b25-01 \
    fcvt.s.w_b26-01 \
    fcvt.s.wu_b25-01 \
    fcvt.s.wu_b26-01 \
    fcvt.w.s_b1-01 \
    fcvt.w.s_b22-01 \
    fcvt.w.s_b23-01 \
    fcvt.w.s_b24-01 \
    fcvt.w.s_b27-01 \
    fcvt.w.s_b28-01 \
    fcvt.w.s_b29-01 \
    fcvt.wu.s_b1-01 \
    fcvt.wu.s_b22-01 \
    fcvt.wu.s_b23-01 \
    fcvt.wu.s_b24-01 \
    fcvt.wu.s_b27-01 \
    fcvt.wu.s_b28-01 \
    fcvt.wu.s_b29-01 \
    fdiv_b1-01 \
    fdiv_b2-01 \
    fdiv_b20-01 \
    fdiv_b4-01 \
    fdiv_b5-01 \
    fdiv_b6-01 \
    fdiv_b7-01 \
    feq_b1-01 \
    fle_b1-01 \
    flt_b1-01 \
    flw-align-01 \
    fmadd_b14-01 \
    fmadd_b16-01 \
    fmadd_b17-01 \
    fmadd_b18-01 \
    fmadd_b2-01 \
    fmadd_b4-01 \
    fmadd_b5-01 \
    fmadd_b6-01 \
    fmadd_b7-01 \
    fmax_b1-01 \
    fmin_b1-01 \
    fmsub_b14-01 \
    fmsub_b16-01 \
    fmsub_b17-01 \
    fmsub_b18-01 \
    fmsub_b2-01 \
    fmsub_b4-01 \
    fmsub_b5-01 \
    fmsub_b6-01 \
    fmsub_b7-01 \
    fmul_b1-01 \
    fmul_b2-01 \
    fmul_b4-01 \
    fmul_b5-01 \
    fmul_b6-01 \
    fmul_b7-01 \
    fmv.w.x_b25-01 \
    fmv.w.x_b26-01 \
    fmv.x.w_b1-01 \
    fmv.x.w_b22-01 \
    fmv.x.w_b23-01 \
    fmv.x.w_b24-01 \
    fmv.x.w_b27-01 \
    fmv.x.w_b28-01 \
    fmv.x.w_b29-01 \
    fnmadd_b14-01 \
    fnmadd_b16-01 \
    fnmadd_b17-01 \
    fnmadd_b18-01 \
    fnmadd_b2-01 \
    fnmadd_b4-01 \
    fnmadd_b5-01 \
    fnmadd_b6-01 \
    fnmadd_b7-01 \
    fnmsub_b14-01 \
    fnmsub_b16-01 \
    fnmsub_b17-01 \
    fnmsub_b18-01 \
    fnmsub_b2-01 \
    fnmsub_b4-01 \
    fnmsub_b5-01 \
    fnmsub_b6-01 \
    fnmsub_b7-01 \
    fsgnj_b1-01 \
    fsgnjn_b1-01 \
    fsgnjx_b1-01 \
    fsqrt_b1-01 \
    fsqrt_b2-01 \
    fsqrt_b20-01 \
    fsqrt_b3-01 \
    fsqrt_b4-01 \
    fsqrt_b5-01 \
    fsqrt_b7-01 \
    fsqrt_b8-01 \
    fsqrt_b9-01 \
    fsub_b1-01 \
    fsub_b10-01 \
    fsub_b12-01 \
    fsub_b13-01 \
    fsub_b2-01 \
    fsub_b4-01 \
    fsub_b5-01 \
    fsub_b7-01 \
    fsw-align-01 \

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

.PHONY: $(SRC_F_TESTS)
$(SRC_F_TESTS):
	cp $(SRC_DIR)/work/rv32f/$@ ./ -r -a

#	mkdir ./work/rv32i/references -p
#	cp $(SRC_DIR)/work/rv32i/$@.hex ./work/rv32i -r -a
#	cp $(SRC_DIR)/work/rv32i/references/$@.reference_output ./work/rv32i/reference -r -a
#	cp $(SRC_DIR)/work/verify.sh ./work


copy: $(SRC_TESTS) $(SRC_F_TESTS)

clean: 
	rm $(SRC_TESTS) $(SRC_F_TESTS) -r -f


else	# ifdef RSD_ENV

# Do nothing

all: 
env-clean:
copy:
clean: 

endif	# ifdef RSD_ENV

