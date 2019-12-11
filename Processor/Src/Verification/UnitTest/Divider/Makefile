# Specify the name of a module to be tested.
UNIT_NAME         = Divider

# Library name and top level module (for simulation)
TOP_MODULE        = $(TEST_BENCH_MODULE)Top
TEST_BENCH_MODULE = Test$(UNIT_NAME)

SOURCE_ROOT  = ../../../
TOOLS_ROOT   = ../../../../Tools/
PROJECT_WORK = ../../../../Project/ModelSim
ISE_PROJECT_ROOT = ../../../../Project/Synplify/$(UNIT_NAME)/pr_1/

# In TYPES, specify files containing packages that define types.
# Make sure that a dependency is in front of the dependent source.
TYPES = \
	BasicTypes.sv \

# Specify files with module definition.
# These modules are used only for test and are not used during synthesis.
# It is not necessary to care about the file order in TEST_MODULES.
TEST_MODULES = \
	Verification/TestBenchClockGenerator.sv \
	Verification/UnitTest/Divider/TestDivider.sv \

# Specify a file with other modules, interface definitions.
# The order here does not cause any problem.
MODULES = \
	Primitives/Divider.sv \
	Verification/UnitTest/Divider/RefDivider.sv \
	Verification/UnitTest/Divider/TestDividerTop.sv \

# Hide certain warnings during synthesis
VLOG_OPTIONS = \
	-suppress 2605 \

# Hide certain warnings during simulation
VSIM_OPTIONS = \
	-suppress 2605 \
	-suppress 8233 \

include ../../../Makefile.inc
