include ../../../Makefiles/Environment.inc.mk

UNIT_NAME = MulDivUnit
TEST_BENCH_MODULE = Test$(UNIT_NAME)
SOURCE_ROOT = ../../../

include $(SOURCE_ROOT)Makefiles/CoreSources.inc.mk
MODULES = \
	MulDivUnit/MulDivUnitIF.sv \
	Recovery/RecoveryManagerIF.sv \
	Primitives/Multiplier.sv \
	Primitives/Divider.sv \
	ExecUnit/MultiplierUnit.sv \
	ExecUnit/DividerUnit.sv \
	MulDivUnit/MulDivUnit.sv
TEST_MODULES = Verification/UnitTest/MulDivUnit/TestMulDivUnit.sv
VLOG_OPTIONS = $(RSD_SRC_CFG) +incdir+$(SOURCE_ROOT) -suppress 2605
VSIM_OPTIONS = -suppress 2605 -suppress 8233

include ../../../Makefiles/UnitTest.inc.mk
