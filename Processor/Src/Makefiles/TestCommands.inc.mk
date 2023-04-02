# "test-~" command is defined here.
# Included from ../Makefile, ../Makefile.verilator
#
# RUN_TEST and RUN_TEST_OMIT_MSG are defined in the above Makefiles.
# They must be changed depending on which simulator is used (modelsim or verilator).


# -------------------------------
# Test : Run test and verify values of register files in the end of simulation.
#        This is only for pre-translate simulation.

LEVEL1_TESTS = \
	test-RV32I-ControlTransfer \
	test-RV32I-ControlTransferZynq \
	test-RV32I-IntRegImm \
	test-RV32I-IntRegImmZynq \
	test-RV32I-IntRegReg \
	test-RV32I-IntRegRegZynq \
	test-RV32I-LoadAndStore \
	test-RV32I-LoadAndStoreZynq \
	test-RV32I-UncachableLoadAndStore \
	test-RV32I-CacheFlush \
	test-RV32I-ZeroRegister \
	test-RV32I-MemoryAccessZynq \
	test-RV32I-ReplayQueueTest \
	test-RV32I-DynamicRecovery \
	test-RV32I-MemoryDependenyPrediction \
	test-RV32I-Fence \
	test-RV32I-CSR \
	test-RV32I-Timer \
	test-RV32I-Fault \
	test-RV32M-IntMulZynq \
	test-RV32M-IntDivZynq \
	test-RV32M-DividerTest \
	test-HelloWorld \
	test-Fibonacci \
	test-Exception \
	test-DCache \

#	test-RV32I-MisalignedMemAccess \

# アドレス変更に伴い，一時的に無効に
#	test-PerformanceCounter \

LEVEL2_TESTS = \
	test-riscv-compliance \
	test-Coremark \
	test-Coremark_for_RV32I \
	test-Dhrystone \
	test-Zephyr \


# TestCodeのビルドとクリーンアップ
test-build: test-build-crt test-build-asm test-build-C test-build-Coremark test-build-Dhrystone test-build-Zephyr test-build-riscv-compliance
test-clean: test-clean-crt test-clean-asm test-clean-C test-clean-Coremark test-clean-Dhrystone test-clean-Zephyr test-clean-riscv-compliance

# test-env-build は env 側のバイナリと hex を再生成する
# test-build 時は，単純にこれをコピーする
test-env-build: test-env-build-Coremark test-env-build-Dhrystone test-env-build-Zephyr
	$(MAKE) test-build

test-env-clean: test-env-clean-Zephyr
	$(MAKE) test-clean
	

# テストで使用するスタートアップルーチン
test-build-crt:
	(cd Verification/TestCode; $(MAKE))
test-clean-crt:
	(cd Verification/TestCode; $(MAKE) clean)

# アセンブラで書かれたテスト
test-build-asm: test-build-crt
	(cd Verification/TestCode/Asm; make)
test-clean-asm:
	(cd Verification/TestCode/Asm; make clean)

# C で書かれたもの
test-build-C: test-build-crt
	(cd Verification/TestCode/C; make)
test-clean-C:
	(cd Verification/TestCode/C; make clean)


# Coremark 関連
test-build-Coremark:
	(cd Verification/TestCode/Coremark; make copy)
test-env-build-Coremark:
	(cd Verification/TestCode/Coremark; make)
test-clean-Coremark:
	(cd Verification/TestCode/Coremark; make clean)

# Dhrystone 関連
test-build-Dhrystone:
	(cd Verification/TestCode/Dhrystone; make copy)
test-env-build-Dhrystone:
	(cd Verification/TestCode/Dhrystone; make)
test-clean-Dhrystone:
	(cd Verification/TestCode/Dhrystone; make clean)

# Zephyr 関連
test-build-Zephyr:
	(cd Verification/TestCode/Zephyr; make copy)
test-env-build-Zephyr:
	(cd Verification/TestCode/Zephyr; make)
test-clean-Zephyr:
	(cd Verification/TestCode/Zephyr; make clean)
test-env-clean-Zephyr:
	(cd Verification/TestCode/Zephyr; make env-clean)

# riscv-compliance
test-build-riscv-compliance:
	(cd Verification/TestCode/riscv-compliance; make copy)
test-env-build-riscv-compliance:
	(cd Verification/TestCode/riscv-compliance; make)
test-clean-riscv-compliance:
	(cd Verification/TestCode/riscv-compliance; make clean)
test-env-clean-riscv-compliance:
	(cd Verification/TestCode/riscv-compliance; make env-clean)


# test / test-* コマンドでは、RSD.logは出力しない

test:
	$(RUN_TEST) $(TEST_CODE)
	@echo "==== Test Successful ===="

test-all: test-1 test-2
	@echo "==== Test Successful (all) ===="
test-1: $(LEVEL1_TESTS)
	@echo "==== Test Successful (test-1) ===="
test-2: $(LEVEL2_TESTS)
	@echo "==== Test Successful (test-2) ===="

test-RV32I-ControlTransfer:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/ControlTransfer
test-RV32I-IntRegImm:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/IntRegImm
test-RV32I-IntRegReg:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/IntRegReg
test-RV32I-LoadAndStore:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/LoadAndStore
test-RV32I-ControlTransferZynq:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/ControlTransferZynq
test-RV32I-IntRegImmZynq:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/IntRegImmZynq
test-RV32I-IntRegRegZynq:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/IntRegRegZynq
test-RV32I-LoadAndStoreZynq:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/LoadAndStoreZynq
test-RV32I-UncachableLoadAndStore:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/UncachableLoadAndStore
test-RV32I-CacheFlush:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/CacheFlush
test-RV32I-ZeroRegister:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/ZeroRegister
test-RV32I-MemoryAccessZynq:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/MemoryAccessZynq
test-RV32I-ReplayQueueTest:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/ReplayQueueTest
test-RV32I-DynamicRecovery:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/DynamicRecovery
test-RV32I-MemoryDependenyPrediction:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/MemoryDependencyPrediction
test-RV32I-Fence:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/Fence
test-RV32I-CSR:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/CSR
test-RV32I-Timer:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/Timer
test-RV32I-Fault:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/Fault
test-RV32I-MisalignedMemAccess:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/MisalignedMemAccess

test-RV32M-IntMulZynq:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/IntMulZynq
test-RV32M-IntDivZynq:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/IntDivZynq
test-RV32M-DividerTest:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/DividerTest

test-RV32F-Asm:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/FP
test-RV32F-C:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/C/FP

test-HelloWorld:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/C/HelloWorld
test-Fibonacci:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/C/Fibonacci
test-Coremark:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Coremark/Coremark
test-Coremark_for_RV32I:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Coremark/Coremark_for_RV32I
test-PerformanceCounter:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/C/PerformanceCounter
test-Dhrystone:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Dhrystone/Dhrystone
test-Dhrystone-for-contest:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Dhrystone/Dhrystone_for_Contest
test-Exception:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/C/Exception
test-DCache:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/C/DCache


# Zephyr のテストターゲット
# test-Zephyr-* の形でテストタスクを作る
ZEPHYR_TESTS =  \
	HelloWorld \
	Philosophers \
	Synchronization \
	Dhrystone \

ZEPHYR_TEST_TARGETS = $(ZEPHYR_TESTS:%=test-Zephyr-%)

.PHONY: $(ZEPHYR_TEST_TARGETS)
$(ZEPHYR_TEST_TARGETS):
	@$(RUN_TEST_OMIT_MSG) Verification/TestCode/Zephyr/$(patsubst test-Zephyr-%,%,$@)

test-Zephyr: $(ZEPHYR_TEST_TARGETS)
	@echo "==== Test Successful (test-Zephyr) ===="

RISCV_RV32I_COMPLIANCE_TESTS =    \
    I-ENDIANESS-01 \
    I-RF_x0-01 \
    I-RF_size-01 \
    I-RF_width-01 \
    I-DELAY_SLOTS-01 \
    I-JAL-01 \
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
    I-SLTI-01 \
    I-SLTIU-01 \
    I-BEQ-01 \
    I-BNE-01 \
    I-BLT-01 \
    I-BLTU-01 \
    I-BGE-01 \
    I-BGEU-01 \
    I-SLL-01 \
    I-SLT-01 \
    I-CSRRW-01 \
    I-CSRRWI-01 \
    I-NOP-01 \
    I-CSRRSI-01 \
    I-CSRRC-01 \
    I-CSRRCI-01 \
    I-ECALL-01 \
    I-EBREAK-01 \
    I-IO \
    I-SRLI-01 \
    I-CSRRS-01 \
    I-JALR-01 \
    I-SRL-01 \
    I-SLLI-01 \
	I-SRA-01 \
    I-SRAI-01 \
    I-SLTU-01 \
    I-MISALIGN_JMP-01 \
	I-MISALIGN_LDST-01 \

#    I-FENCE.I-01 \

RISCV_RV32I_COMPLIANCE_TEST_TARGETS = $(RISCV_RV32I_COMPLIANCE_TESTS:%=test-riscv-compliance-%)

.PHONY: $(RISCV_RV32I_COMPLIANCE_TEST_TARGETS)
$(RISCV_RV32I_COMPLIANCE_TEST_TARGETS):
	@$(RUN_TEST_OMIT_MSG) Verification/TestCode/riscv-compliance/$(patsubst test-riscv-compliance-%,%,$@)

test-riscv-compliance: $(RISCV_RV32I_COMPLIANCE_TEST_TARGETS)
	@echo "==== Test Successful (test-riscv-compliance) ===="

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

# unsupported rounding mode
    #fadd_b7-01 \
    fadd_b2-01 \
    fadd_b4-01 \
    fadd_b5-01 \
    fdiv_b4-01 \
    fdiv_b5-01 \
    fdiv_b6-01 \
    fdiv_b7-01 \
    fmadd_b4-01 \
    fmadd_b5-01 \
    fmadd_b6-01 \
    fmadd_b7-01 \
    fmsub_b4-01 \
    fmsub_b5-01 \
    fmsub_b6-01 \
    fmsub_b7-01 \
    fmul_b4-01 \
    fmul_b5-01 \
    fmul_b6-01 \
    fmul_b7-01 \
    fnmadd_b4-01 \
    fnmadd_b5-01 \
    fnmadd_b6-01 \
    fnmadd_b7-01 \
    fnmsub_b4-01 \
    fnmsub_b5-01 \
    fnmsub_b6-01 \
    fnmsub_b7-01 \
    fsqrt_b3-01 \
    fsqrt_b4-01 \
    fsqrt_b5-01 \
    fsqrt_b7-01 \
    fsqrt_b8-01 \
    fsub_b4-01 \
    fsub_b5-01 \
    fsub_b7-01 \

# unsupported fflags
    #fadd_b1-01 \
    fadd_b10-01 \
    fadd_b12-01 \
    fadd_b13-01 \
    fdiv_b1-01 \
    fdiv_b2-01 \
    fdiv_b20-01 \
    fmadd_b14-01 \
    fmadd_b16-01 \
    fmadd_b17-01 \
    fmadd_b18-01 \
    fmadd_b2-01 \
    fmsub_b14-01 \
    fmsub_b16-01 \
    fmsub_b17-01 \
    fmsub_b18-01 \
    fmsub_b2-01 \
    fmul_b1-01 \
    fmul_b2-01 \
    fnmadd_b14-01 \
    fnmadd_b16-01 \
    fnmadd_b17-01 \
    fnmadd_b18-01 \
    fnmadd_b2-01 \
    fnmsub_b14-01 \
    fnmsub_b16-01 \
    fnmsub_b17-01 \
    fnmsub_b18-01 \
    fnmsub_b2-01 \
    fsqrt_b1-01 \
    fsqrt_b2-01 \
    fsqrt_b20-01 \
    fsqrt_b9-01 \
    fsub_b1-01 \
    fsub_b10-01 \
    fsub_b12-01 \
    fsub_b13-01 \
    fsub_b2-01 \

RISCV_RV32F_COMPLIANCE_TESTS =    \
  fcvt.s.w_b25-01 \
  fcvt.s.w_b26-01 \
  fcvt.s.wu_b25-01 \
  fcvt.s.wu_b26-01 \
  fcvt.w.s_b1-01 \
  fcvt.w.s_b22-01 \
  fcvt.w.s_b23-01 \
  fcvt.w.s_b24-01 \
  fcvt.w.s_b27-01 \
  fclass_b1-01 \
  fcvt.w.s_b28-01 \
  fcvt.w.s_b29-01 \
  fcvt.wu.s_b1-01 \
  fcvt.wu.s_b22-01 \
  fcvt.wu.s_b23-01 \
  fcvt.wu.s_b24-01 \
  fcvt.wu.s_b27-01 \
  fcvt.wu.s_b28-01 \
  fcvt.wu.s_b29-01 \
  feq_b1-01 \
  fle_b1-01 \
  flt_b1-01 \
  flw-align-01 \
  fmax_b1-01 \
  fmin_b1-01 \
  fmv.w.x_b25-01 \
  fmv.w.x_b26-01 \
  fmv.x.w_b1-01 \
  fmv.x.w_b22-01 \
  fmv.x.w_b23-01 \
  fmv.x.w_b24-01 \
  fmv.x.w_b27-01 \
  fmv.x.w_b28-01 \
  fmv.x.w_b29-01 \
  fsgnj_b1-01 \
  fsgnjn_b1-01 \
  fsgnjx_b1-01 \
  fsw-align-01 \

RISCV_RV32F_COMPLIANCE_TEST_TARGETS = $(RISCV_RV32F_COMPLIANCE_TESTS:%=test-riscv-compliance-%)

.PHONY: $(RISCV_RV32F_COMPLIANCE_TEST_TARGETS)
$(RISCV_RV32F_COMPLIANCE_TEST_TARGETS):
	@$(RUN_TEST_OMIT_MSG) Verification/TestCode/riscv-compliance/$(patsubst test-riscv-compliance-%,%,$@)

test-riscv-compliance-f: $(RISCV_RV32F_COMPLIANCE_TEST_TARGETS)
	@echo "==== Test Successful (test-riscv-compliance) ===="

# Aggregate cycle/IPC information from verilator/modelsim log.
test-summary-all:
	grep "Elapsed cycles" Verification/ --include=verilator.log -r | sed -e "s/.\+\/\(.\+\)\/\(.\+\)\/verilator.log:Elapsed cycles:[ ]*/\1\/\2,/g" > verilator-cycles.csv
	grep "IPC (RISC-V instruction)" Verification/ --include=verilator.log -r | sed -e "s/.\+\/\(.\+\)\/\(.\+\)\/verilator.log:IPC (RISC-V instruction):[ ]*/\1\/\2,/g" > verilator-ipc.csv
	grep "Num of I$$ misses" Verification/ --include=verilator.log -r | sed -e "s/.\+\/\(.\+\)\/\(.\+\)\/verilator.log:Num of I$$ misses:[ ]*/\1\/\2,/g" > verilator-icache-misses.csv
	grep "Num of D$$ load misses" Verification/ --include=verilator.log -r | sed -e "s/.\+\/\(.\+\)\/\(.\+\)\/verilator.log:Num of D$$ load misses:[ ]*/\1\/\2,/g" > verilator-load-misses.csv
	grep "Num of D$$ store misses" Verification/ --include=verilator.log -r | sed -e "s/.\+\/\(.\+\)\/\(.\+\)\/verilator.log:Num of D$$ store misses:[ ]*/\1\/\2,/g" > verilator-store-misses.csv
	grep "Num of branch prediction misses" Verification/ --include=verilator.log -r | sed -e "s/.\+\/\(.\+\)\/\(.\+\)\/verilator.log:Num of branch prediction misses:[ ]*/\1\/\2,/g" > verilator-br-pred-misses.csv
	grep "Elapsed cycles" Verification/ --include=vsim.log -r | sed -e "s/.\+\/\(.\+\)\/\(.\+\)\/vsim.log:# Elapsed cycles:[ ]*/\1\/\2,/g" > modelsim-cycles.csv
	grep "IPC (RISC-V instruction)" Verification/ --include=vsim.log -r | sed -e "s/.\+\/\(.\+\)\/\(.\+\)\/vsim.log:# IPC (RISC-V instruction):[ ]*/\1\/\2,/g" > modelsim-ipc.csv
	grep "Num of I$$ misses" Verification/ --include=vsim.log -r | sed -e "s/.\+\/\(.\+\)\/\(.\+\)\/vsim.log:# Num of I$$ misses:[ ]*/\1\/\2,/g" > vsim-icache-misses.csv
	grep "Num of D$$ load misses" Verification/ --include=vsim.log -r | sed -e "s/.\+\/\(.\+\)\/\(.\+\)\/vsim.log:# Num of D$$ load misses:[ ]*/\1\/\2,/g" > vsim-load-misses.csv
	grep "Num of D$$ store misses" Verification/ --include=vsim.log -r | sed -e "s/.\+\/\(.\+\)\/\(.\+\)\/vsim.log:# Num of D$$ store misses:[ ]*/\1\/\2,/g" > vsim-store-misses.csv
	grep "Num of branch prediction misses" Verification/ --include=vsim.log -r | sed -e "s/.\+\/\(.\+\)\/\(.\+\)\/vsim.log:# Num of branch prediction misses:[ ]*/\1\/\2,/g" > vsim-br-pred-misses.csv

