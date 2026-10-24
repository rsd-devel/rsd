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
	test-RV32I-MisalignedMemAccess \
	test-RV32I-UncachableLoadAndStore \
	test-RV32I-CacheFlush \
	test-RV32I-ZeroRegister \
	test-RV32I-MemoryAccessZynq \
	test-RV32I-ReplayQueueTest \
	test-RV32I-DynamicRecovery \
	test-RV32I-MemoryDependencyPrediction \
	test-RV32I-Fence \
	test-RV32I-CSR \
	test-RV32I-ENV \
	test-RV32I-Timer \
	test-RV32I-MSWI \
	test-RV32I-Fault \
	test-RV32M-IntMulZynq \
	test-RV32M-IntDivZynq \
	test-RV32M-DividerTest \
    test-RV32A-Aext \
	test-HelloWorld \
	test-Fibonacci \
	test-Exception \
	test-DCache \
	test-PerformanceCounter \

ifeq ($(RSD_HAS_FP),1)
LEVEL1_TESTS += test-RV32F-Asm test-RV32F-C
endif

LEVEL2_TESTS = \
	test-Coremark \
	test-Coremark_for_RV32I \
	test-Dhrystone

EX_TESTS = \
	test-riscv-arch-test \
	test-Zephyr


# Build the in-repository tests without external test sources.
# Clean first when changing the toolchain or command-line build flags.
.PHONY: test-build-basic test-clean-basic test-build-crt test-clean-crt
.PHONY: test-build-asm test-clean-asm test-build-C test-clean-C
test-build-basic: test-build-asm test-build-C
test-clean-basic: test-clean-asm test-clean-C test-clean-crt

# Always check source dependencies before running a basic test.
# Each test depends on its build, including when make runs in parallel.
BASIC_ASM_TESTS = $(filter test-RV32I-% test-RV32M-% test-RV32A-%,$(LEVEL1_TESTS))
BASIC_C_TESTS = test-HelloWorld test-Fibonacci test-Exception test-DCache \
	test-PerformanceCounter
ifeq ($(RSD_HAS_FP),1)
BASIC_ASM_TESTS += test-RV32F-Asm
BASIC_C_TESTS += test-RV32F-C
endif
.PHONY: $(BASIC_ASM_TESTS) $(BASIC_C_TESTS)
$(BASIC_ASM_TESTS): test-build-asm
$(BASIC_C_TESTS): test-build-C

# Build standard and extended tests separately; clean both groups.
.PHONY: test-build test-build-ex test-clean
test-build: test-build-crt test-build-asm test-build-C test-build-Coremark test-build-Dhrystone
test-build-ex: test-build-Zephyr test-build-riscv-arch-test
test-clean: test-clean-crt test-clean-asm test-clean-C test-clean-Coremark test-clean-Dhrystone test-clean-Zephyr test-clean-riscv-arch-test

# テストで使用するスタートアップルーチン
test-build-crt:
	(cd Verification/TestCode; $(MAKE))
test-clean-crt:
	(cd Verification/TestCode; $(MAKE) clean)

# アセンブラで書かれたテスト
test-build-asm: test-build-crt
	$(MAKE) -C Verification/TestCode/Asm
test-clean-asm:
	$(MAKE) -C Verification/TestCode/Asm clean

# C で書かれたもの
test-build-C: test-build-crt
	$(MAKE) -C Verification/TestCode/C
test-clean-C:
	$(MAKE) -C Verification/TestCode/C clean


# Coremark 関連
.PHONY: test-fetch-Coremark test-build-Coremark test-clean-Coremark
.PHONY: test-Coremark test-Coremark_for_RV32I
test-fetch-Coremark:
	$(MAKE) -C Verification/TestCode/Coremark fetch
test-build-Coremark:
	$(MAKE) -C Verification/TestCode/Coremark BENCHMARK=0
test-clean-Coremark:
	$(MAKE) -C Verification/TestCode/Coremark clean
test-Coremark test-Coremark_for_RV32I: test-build-Coremark

# Dhrystone 関連
.PHONY: test-fetch-Dhrystone test-build-Dhrystone test-clean-Dhrystone test-Dhrystone
test-fetch-Dhrystone:
	$(MAKE) -C Verification/TestCode/Dhrystone fetch
test-build-Dhrystone:
	$(MAKE) -C Verification/TestCode/Dhrystone BENCHMARK=0
test-clean-Dhrystone:
	$(MAKE) -C Verification/TestCode/Dhrystone clean
test-Dhrystone: test-build-Dhrystone

# Measure benchmark loops using mcycle.
DHRYSTONE_BENCH_ITERATIONS ?= 2000
.PHONY: bench-Coremark bench-Dhrystone
bench-Coremark:
	$(MAKE) -C Verification/TestCode/Coremark Coremark BENCHMARK=1
	$(RUN_TEST_OMIT_MSG) --benchmark=coremark Verification/TestCode/Coremark/Coremark
bench-Dhrystone: MAX_TEST_INSTRUCTIONS = 2000000
bench-Dhrystone:
	$(MAKE) -C Verification/TestCode/Dhrystone BENCHMARK=1 DHRYSTONE_ITERATIONS=$(DHRYSTONE_BENCH_ITERATIONS)
	$(RUN_TEST_OMIT_MSG) --benchmark=dhrystone --benchmark-iterations=$(DHRYSTONE_BENCH_ITERATIONS) --max-test-instructions=$(MAX_TEST_INSTRUCTIONS) Verification/TestCode/Dhrystone/Dhrystone

# Public Zephyr source and isolated Python build dependencies.
.PHONY: test-fetch-Zephyr test-setup-Zephyr test-check-Zephyr test-build-Zephyr test-clean-Zephyr
test-fetch-Zephyr:
	$(MAKE) -C Verification/TestCode/Zephyr fetch
test-setup-Zephyr:
	$(MAKE) -C Verification/TestCode/Zephyr setup
test-check-Zephyr:
	$(MAKE) -C Verification/TestCode/Zephyr check
test-build-Zephyr:
	$(MAKE) -C Verification/TestCode/Zephyr build
test-clean-Zephyr:
	$(MAKE) -C Verification/TestCode/Zephyr clean

# ACT4 source checkout and isolated dependency setup.
.PHONY: test-fetch-riscv-arch-test test-setup-riscv-arch-test test-check-riscv-arch-test
test-fetch-riscv-arch-test:
	$(MAKE) -C Verification/TestCode/riscv-arch-test fetch
test-setup-riscv-arch-test:
	$(MAKE) -C Verification/TestCode/riscv-arch-test setup
test-check-riscv-arch-test:
	$(MAKE) -C Verification/TestCode/riscv-arch-test check

# Run the selected ACT4 cases through the normal TestDriver and summarize results.
.PHONY: test-build-riscv-arch-test test-clean-riscv-arch-test test-riscv-arch-test
test-build-riscv-arch-test:
	$(MAKE) -C Verification/TestCode/riscv-arch-test build
test-clean-riscv-arch-test:
	$(MAKE) -C Verification/TestCode/riscv-arch-test clean
test-riscv-arch-test:
	$(MAKE) -C Verification/TestCode/riscv-arch-test run TEST_DRIVER="$(patsubst @%,%,$(RUN_TEST_OMIT_MSG))"

# test / test-* コマンドでは、RSD.logは出力しない

test:
	$(RUN_TEST) $(TEST_CODE)
	@echo "==== Test Successful ===="

# Test the test infrastructure itself: TestDriver and the DevContainer launcher.
# Each suite uses stubs; TestDriver also checks an existing Verilator model when available.
PYTHON ?= python3
.PHONY: test-tools test-tools-TestDriver test-tools-DevContainer
test-tools: test-tools-TestDriver test-tools-DevContainer
	@echo "==== Test Successful (test-tools) ===="

test-tools-TestDriver test-tools-DevContainer: test-tools-%:
	$(PYTHON) -B -m unittest discover -s ../Tools/$*/Tests -p 'Test*.py' -v

.PHONY: test-all test-1 test-2 test-ex
test-all: test-1 test-2
	@echo "==== Test Successful (all) ===="
test-1: $(LEVEL1_TESTS)
	@echo "==== Test Successful (test-1) ===="
test-2: $(LEVEL2_TESTS)
	@echo "==== Test Successful (test-2) ===="
test-ex: $(EX_TESTS)
	@echo "==== Test Successful (test-ex) ===="

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
test-RV32I-MemoryDependencyPrediction:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/MemoryDependencyPrediction
test-RV32I-Fence:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/Fence
test-RV32I-CSR:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/CSR
test-RV32I-ENV:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/ENV

test-RV32I-MSWI:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/MSWI
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

test-RV32A-Aext:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/Aext

ifeq ($(RSD_HAS_FP),1)
test-RV32F-Asm:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/FP
test-RV32F-C:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/C/FP
else
.PHONY: test-RV32F-Asm test-RV32F-C
test-RV32F-Asm test-RV32F-C:
	@echo "FP tests require RSD_MARCH_FP_PIPE in RSD_SRC_CFG" >&2
	@exit 1
endif

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
test-Exception:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/C/Exception
test-DCache:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/C/DCache


# Build and run the current upstream Zephyr samples.
ZEPHYR_TESTS = HelloWorld Philosophers Synchronization
ZEPHYR_TEST_TARGETS = $(ZEPHYR_TESTS:%=test-Zephyr-%)

# Zephyr samples continue running until the instruction budget is reached.
.PHONY: test-Zephyr $(ZEPHYR_TEST_TARGETS)
$(ZEPHYR_TEST_TARGETS): test-build-Zephyr

test-Zephyr-HelloWorld:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Zephyr/Build/HelloWorld

test-Zephyr-Synchronization:
	$(RUN_TEST_OMIT_MSG) --serial-prefix Verification/TestCode/Zephyr/Build/Synchronization

test-Zephyr-Philosophers:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Zephyr/Build/Philosophers
	python3 Verification/TestCode/Zephyr/CheckOutput.py Verification/TestCode/Zephyr/Build/Philosophers/serial.out.txt

test-Zephyr: $(ZEPHYR_TEST_TARGETS)
	@echo "==== Test Successful (test-Zephyr) ===="

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

