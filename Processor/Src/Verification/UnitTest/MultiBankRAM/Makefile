include ../../../Makefiles/Environment.inc.mk

# Check bank routing and read latency with equal and unequal port counts.
UNIT_NAME = MultiBankRAM
TEST_BENCH_MODULE = Test$(UNIT_NAME)
SOURCE_ROOT = ../../../
TYPES =
MODULES = Primitives/RAM.sv
TEST_MODULES = Verification/UnitTest/MultiBankRAM/TestMultiBankRAM.sv
VLOG_OPTIONS = +incdir+$(SOURCE_ROOT)
include ../../../Makefiles/UnitTest.inc.mk
