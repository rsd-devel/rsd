include ../../../Makefiles/Environment.inc.mk

UNIT_NAME = BranchRecovery
TEST_BENCH_MODULE = Test$(UNIT_NAME)
SOURCE_ROOT = ../../../

include $(SOURCE_ROOT)Makefiles/CoreSources.inc.mk
MODULES = $(CORE_MODULES)
TEST_MODULES = Verification/UnitTest/BranchRecovery/TestBranchRecovery.sv
VLOG_OPTIONS = $(RSD_SRC_CFG) +incdir+$(SOURCE_ROOT) -suppress 2605
VSIM_OPTIONS = -suppress 2605 -suppress 8233

include ../../../Makefiles/UnitTest.inc.mk
