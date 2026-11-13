# Program builds and test targets, included by the main Makefile.
# RUN_TEST and RUN_TEST_OMIT_MSG use the selected SIM backend.
# Public test/<subject>/run targets execute tests and check their results.
# Suite setup, builds and usage: https://github.com/rsd-devel/rsd/wiki/en-test-program


# -------------------------------
# Test : Run test and verify values of register files in the end of simulation.
#        This is only for pre-translate simulation.

LEVEL1_TESTS = \
	test/Asm/ControlTransfer/run \
	test/Asm/ControlTransferZynq/run \
	test/Asm/IntRegImm/run \
	test/Asm/IntRegImmZynq/run \
	test/Asm/IntRegReg/run \
	test/Asm/IntRegRegZynq/run \
	test/Asm/LoadAndStore/run \
	test/Asm/LoadAndStoreZynq/run \
	test/Asm/MisalignedMemAccess/run \
	test/Asm/UncachableLoadAndStore/run \
	test/Asm/ICacheFlush/run \
	test/Asm/DCacheFlush/run \
	test/Asm/ZeroRegister/run \
	test/Asm/MemoryAccessZynq/run \
	test/Asm/ReplayQueueTest/run \
	test/Asm/DynamicRecovery/run \
	test/Asm/MemoryDependencyPrediction/run \
	test/Asm/Fence/run \
	test/Asm/CSR/run \
	test/Asm/ENV/run \
	test/Asm/Timer/run \
	test/Asm/MSWI/run \
	test/Asm/Fault/run \
	test/Asm/IntMulZynq/run \
	test/Asm/IntDivZynq/run \
	test/Asm/DividerTest/run \
    test/Asm/Aext/run \
	test/C/HelloWorld/run \
	test/C/Fibonacci/run \
	test/C/Exception/run \
	test/C/DCache/run \
	test/C/PerformanceCounter/run \

ifeq ($(RSD_HAS_FP),1)
LEVEL1_TESTS += test/Asm/FP/run test/C/FP/run
endif

ifeq ($(RSD_HAS_ZICFILP),1)
LEVEL1_TESTS += test/Asm/LandingPad/run
endif

LEVEL2_TESTS = \
	test/External/Coremark/run \
	test/External/Coremark/Coremark_for_RV32I/run \
	test/External/Dhrystone/run

EX_TESTS = \
	test/External/riscv-arch-test/run \
	test/External/Zephyr/run


# Build the in-repository tests without external test sources.
# Clean first when changing the toolchain or command-line build flags.
.PHONY: test/level-1/build test/level-1/clean test/crt/build test/crt/clean
.PHONY: test/Asm/build test/Asm/clean test/C/build test/C/clean
test/level-1/build: test/Asm/build test/C/build
test/level-1/clean: test/Asm/clean test/C/clean test/crt/clean

# Always check source dependencies before running a basic test.
# Each test depends on its build, including when make runs in parallel.
BASIC_ASM_TESTS = $(filter test/Asm/%,$(LEVEL1_TESTS))
BASIC_C_TESTS = $(filter test/C/%,$(LEVEL1_TESTS))
.PHONY: $(BASIC_ASM_TESTS) $(BASIC_C_TESTS)
$(BASIC_ASM_TESTS): test/Asm/build
$(BASIC_C_TESTS): test/C/build

# Public test targets use <subject>/<operation>; External groups programs built from upstream sources.
# Build standard and extended tests separately; clean both groups.
.PHONY: test/all/build test/level-2/build test/ex/build test/clean
test/all/build: test/crt/build test/Asm/build test/C/build test/External/Coremark/build test/External/Dhrystone/build
test/level-2/build: test/External/Coremark/build test/External/Dhrystone/build
test/ex/build: test/External/Zephyr/build test/External/riscv-arch-test/build
test/clean: test/crt/clean test/Asm/clean test/C/clean test/External/Coremark/clean test/External/Dhrystone/clean test/External/Zephyr/clean test/External/riscv-arch-test/clean

# テストで使用するスタートアップルーチン
test/crt/build:
	(cd Verification/TestCode; $(MAKE))
test/crt/clean:
	(cd Verification/TestCode; $(MAKE) clean)

# アセンブラで書かれたテスト
test/Asm/build: test/crt/build
	$(MAKE) -C Verification/TestCode/Asm
test/Asm/clean:
	$(MAKE) -C Verification/TestCode/Asm clean

# C で書かれたもの
test/C/build: test/crt/build
	$(MAKE) -C Verification/TestCode/C
test/C/clean:
	$(MAKE) -C Verification/TestCode/C clean


# Coremark 関連
.PHONY: test/External/Coremark/fetch test/External/Coremark/build test/External/Coremark/clean
.PHONY: test/External/Coremark/run test/External/Coremark/Coremark_for_RV32I/run
test/External/Coremark/fetch:
	$(MAKE) -C Verification/TestCode/Coremark fetch
test/External/Coremark/build:
	$(MAKE) -C Verification/TestCode/Coremark BENCHMARK=0
test/External/Coremark/clean:
	$(MAKE) -C Verification/TestCode/Coremark clean
test/External/Coremark/run test/External/Coremark/Coremark_for_RV32I/run: test/External/Coremark/build

# Dhrystone 関連
.PHONY: test/External/Dhrystone/fetch test/External/Dhrystone/build test/External/Dhrystone/clean test/External/Dhrystone/run
test/External/Dhrystone/fetch:
	$(MAKE) -C Verification/TestCode/Dhrystone fetch
test/External/Dhrystone/build:
	$(MAKE) -C Verification/TestCode/Dhrystone BENCHMARK=0
test/External/Dhrystone/clean:
	$(MAKE) -C Verification/TestCode/Dhrystone clean
test/External/Dhrystone/run: test/External/Dhrystone/build

# Measure benchmark loops using mcycle.
DHRYSTONE_BENCH_ITERATIONS ?= 2000
.PHONY: bench/Coremark/run bench/Dhrystone/run
bench/Coremark/run:
	$(MAKE) -C Verification/TestCode/Coremark Coremark BENCHMARK=1
	$(RUN_TEST_OMIT_MSG) --benchmark=coremark Verification/TestCode/Coremark/Coremark
bench/Dhrystone/run: MAX_TEST_INSTRUCTIONS = 2000000
bench/Dhrystone/run:
	$(MAKE) -C Verification/TestCode/Dhrystone BENCHMARK=1 DHRYSTONE_ITERATIONS=$(DHRYSTONE_BENCH_ITERATIONS)
	$(RUN_TEST_OMIT_MSG) --benchmark=dhrystone --benchmark-iterations=$(DHRYSTONE_BENCH_ITERATIONS) --max-test-instructions=$(MAX_TEST_INSTRUCTIONS) Verification/TestCode/Dhrystone/Dhrystone

# Public Zephyr source and isolated Python build dependencies.
.PHONY: test/External/Zephyr/fetch test/External/Zephyr/setup test/External/Zephyr/check test/External/Zephyr/build test/External/Zephyr/clean
test/External/Zephyr/fetch:
	$(MAKE) -C Verification/TestCode/Zephyr fetch
test/External/Zephyr/setup:
	$(MAKE) -C Verification/TestCode/Zephyr setup
test/External/Zephyr/check:
	$(MAKE) -C Verification/TestCode/Zephyr check
test/External/Zephyr/build:
	$(MAKE) -C Verification/TestCode/Zephyr build
test/External/Zephyr/clean:
	$(MAKE) -C Verification/TestCode/Zephyr clean

# ACT4 source checkout and isolated dependency setup.
.PHONY: test/External/riscv-arch-test/fetch test/External/riscv-arch-test/setup test/External/riscv-arch-test/check
test/External/riscv-arch-test/fetch:
	$(MAKE) -C Verification/TestCode/riscv-arch-test fetch
test/External/riscv-arch-test/setup:
	$(MAKE) -C Verification/TestCode/riscv-arch-test setup
test/External/riscv-arch-test/check:
	$(MAKE) -C Verification/TestCode/riscv-arch-test check

# Run the selected ACT4 cases through the normal TestDriver and summarize results.
.PHONY: test/External/riscv-arch-test/build test/External/riscv-arch-test/clean test/External/riscv-arch-test/run
test/External/riscv-arch-test/build:
	$(MAKE) -C Verification/TestCode/riscv-arch-test build
test/External/riscv-arch-test/clean:
	$(MAKE) -C Verification/TestCode/riscv-arch-test clean
test/External/riscv-arch-test/run:
	$(MAKE) -C Verification/TestCode/riscv-arch-test run TEST_DRIVER="$(patsubst @%,%,$(RUN_TEST_OMIT_MSG))"

# test / test/* do not write RSD.log.

.PHONY: test
test:
	$(RUN_TEST) $(TEST_CODE)
	@echo "==== Test Successful ===="

# Test the test infrastructure itself: TestDriver and the DevContainer launcher.
# Each suite uses stubs; TestDriver also checks an existing Verilator model when available.
PYTHON ?= python3
.PHONY: test/tools/run test/tools/TestDriver/run test/tools/DevContainer/run
test/tools/run: test/tools/TestDriver/run test/tools/DevContainer/run test/tools/Config/run
	@echo "==== Test Successful (test/tools/run) ===="

test/tools/TestDriver/run test/tools/DevContainer/run: test/tools/%/run:
	$(PYTHON) -B -m unittest discover -s ../Tools/$*/Tests -p 'Test*.py' -v

.PHONY: test/all/run test/level-1/run test/level-2/run test/ex/run
test/all/run: test/level-1/run test/level-2/run
	@echo "==== Test Successful (all) ===="
test/level-1/run: $(LEVEL1_TESTS)
	@echo "==== Test Successful (test/level-1/run) ===="
test/level-2/run: $(LEVEL2_TESTS)
	@echo "==== Test Successful (test/level-2/run) ===="
test/ex/run: $(EX_TESTS)
	@echo "==== Test Successful (test/ex/run) ===="

test/Asm/ControlTransfer/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/ControlTransfer
test/Asm/IntRegImm/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/IntRegImm
test/Asm/IntRegReg/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/IntRegReg
test/Asm/LoadAndStore/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/LoadAndStore
test/Asm/ControlTransferZynq/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/ControlTransferZynq
test/Asm/IntRegImmZynq/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/IntRegImmZynq
test/Asm/IntRegRegZynq/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/IntRegRegZynq
test/Asm/LoadAndStoreZynq/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/LoadAndStoreZynq
test/Asm/UncachableLoadAndStore/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/UncachableLoadAndStore
test/Asm/ICacheFlush/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/ICacheFlush
test/Asm/DCacheFlush/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/DCacheFlush
test/Asm/ZeroRegister/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/ZeroRegister
test/Asm/MemoryAccessZynq/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/MemoryAccessZynq
test/Asm/ReplayQueueTest/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/ReplayQueueTest
test/Asm/DynamicRecovery/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/DynamicRecovery
test/Asm/MemoryDependencyPrediction/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/MemoryDependencyPrediction
test/Asm/Fence/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/Fence
test/Asm/CSR/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/CSR
test/Asm/ENV/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/ENV

test/Asm/MSWI/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/MSWI
test/Asm/Timer/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/Timer
test/Asm/Fault/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/Fault
test/Asm/MisalignedMemAccess/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/MisalignedMemAccess
.PHONY: test/Asm/LandingPad/run
ifeq ($(RSD_HAS_ZICFILP),1)
test/Asm/LandingPad/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/LandingPad
else
test/Asm/LandingPad/run:
	@echo "LandingPad tests require RSD_ENABLE_ZICFILP in RSD_SRC_CFG" >&2
	@exit 1
endif

test/Asm/IntMulZynq/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/IntMulZynq
test/Asm/IntDivZynq/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/IntDivZynq
test/Asm/DividerTest/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/DividerTest

test/Asm/Aext/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/Aext

ifeq ($(RSD_HAS_FP),1)
test/Asm/FP/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Asm/FP
test/C/FP/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/C/FP
else
.PHONY: test/Asm/FP/run test/C/FP/run
test/Asm/FP/run test/C/FP/run:
	@echo "FP tests require RSD_MARCH_FP_PIPE in RSD_SRC_CFG" >&2
	@exit 1
endif

test/C/HelloWorld/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/C/HelloWorld
test/C/Fibonacci/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/C/Fibonacci
test/External/Coremark/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Coremark/Coremark
test/External/Coremark/Coremark_for_RV32I/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Coremark/Coremark_for_RV32I
test/C/PerformanceCounter/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/C/PerformanceCounter
test/External/Dhrystone/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Dhrystone/Dhrystone
test/C/Exception/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/C/Exception
test/C/DCache/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/C/DCache


# Build and run the current upstream Zephyr samples.
ZEPHYR_TESTS = HelloWorld Philosophers Synchronization
ZEPHYR_TEST_TARGETS = $(ZEPHYR_TESTS:%=test/External/Zephyr/%/run)

# Zephyr samples continue running until the instruction budget is reached.
.PHONY: test/External/Zephyr/run $(ZEPHYR_TEST_TARGETS)
$(ZEPHYR_TEST_TARGETS): test/External/Zephyr/build

test/External/Zephyr/HelloWorld/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Zephyr/Build/HelloWorld

test/External/Zephyr/Synchronization/run:
	$(RUN_TEST_OMIT_MSG) --serial-prefix Verification/TestCode/Zephyr/Build/Synchronization

test/External/Zephyr/Philosophers/run:
	$(RUN_TEST_OMIT_MSG) Verification/TestCode/Zephyr/Build/Philosophers
	python3 Verification/TestCode/Zephyr/CheckOutput.py Verification/TestCode/Zephyr/Build/Philosophers/serial.out.txt

test/External/Zephyr/run: $(ZEPHYR_TEST_TARGETS)
	@echo "==== Test Successful (test/External/Zephyr/run) ===="


.PHONY: test/tools/Config/run
# Test the configuration generator itself, not the processor RTL.
test/tools/Config/run: $(RSD_CONFIG_OUTPUTS)
	$(PYTHON) -B -m unittest discover -s $(RSD_ROOT)/Processor/Tools/ConfigGenerator/Tests -p 'Test*.py' -v
