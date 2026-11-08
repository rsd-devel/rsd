UNIT_NAME = FPDivSqrtUnit
TEST_BENCH_MODULE = Test$(UNIT_NAME)
SOURCE_ROOT = ../../../

include $(SOURCE_ROOT)Makefiles/CoreSources.inc.mk
MODULES = \
	FloatingPointUnit/FPDivSqrtUnitIF.sv \
	Recovery/RecoveryManagerIF.sv \
	FloatingPointUnit/FP32DivSqrter.sv \
	FloatingPointUnit/FPDivSqrtUnit.sv
TEST_MODULES = Verification/UnitTest/FPDivSqrtUnit/TestFPDivSqrtUnit.sv
VLOG_OPTIONS = $(RSD_SRC_CFG) +incdir+$(SOURCE_ROOT) -suppress 2605
VSIM_OPTIONS = -suppress 2605 -suppress 8233

include ../../../Makefiles/UnitTest.inc.mk
