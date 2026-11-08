# Check the initialized RAM itself, including widths different from the HEX format.
UNIT_NAME = InitializedBlockRAM
TEST_BENCH_MODULE = Test$(UNIT_NAME)
SOURCE_ROOT = ../../../
TYPES =
MODULES = Primitives/RAM.sv
TEST_MODULES = Verification/UnitTest/InitializedBlockRAM/TestInitializedBlockRAM.sv
VLOG_OPTIONS = +incdir+$(SOURCE_ROOT)
VSIM_OPTIONS = -suppress 8233
include ../../../Makefiles/UnitTest.inc.mk
