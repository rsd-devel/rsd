# -------------------------------
# Shared ModelSim/QuestaSim definitions for core and RTL unit tests.
#

VLOG = $(RSD_QUESTASIM_PATH)/vlog
VLIB = $(RSD_QUESTASIM_PATH)/vlib
# In Linux, "vsim" is launched in GUI, so explicitly specify a command line mode (-c)
VSIM = $(RSD_QUESTASIM_PATH)/vsim -c   
MODELSIM = $(RSD_QUESTASIM_PATH)/vsim 


# -------------------------------
# Program options
#

VLOG_OPTIONS_RTL = \
	+define+RSD_FUNCTIONAL_SIMULATION \

# -lint: Checks a coding style
# -pedanticerrors: Forces display of an error message (rather than a warning)
# +librescan:  Scans libraries in command-line order for all unresolved mod
# -sv: system verilog
# -nocovercells: ???
# -novopt: disable optimization
# -incr: incremental build
# +incdir+./: adds "./" to include search paths 
VLOG_OPTIONS_COMMON = \
	-lint \
	-pedanticerrors \
	+librescan \
	-sv \
	-nocovercells \
	+acc \
	-incr \
	-suppress 7061 \
	+incdir+./ \


# -------------------------------
# Commands
#

default: rtl

all: rtl

# Simulation on a command line mode.
run: rtl-run

# Simulation on a GUI mode.
run-gui: rtl-run-gui

# Both core and unit tests build RTL before running.
.PHONY: test
test: rtl

# Core tests supply RUN_TEST and define their recipe in TestCommands.inc.mk.
# Otherwise, run a self-checking RTL testbench, returning failures to make.
# Questa TESTSTATUS: 0 = passed, 1 = warning, 2 or higher = failed.
ifndef RUN_TEST
test:
	$(VSIM) $(TARGET_MODULE_RTL) $(VSIM_OPTIONS) $(VSIM_OPTIONS_RTL) -onfinish stop \
		-do 'set BreakOnAssertion 2; run -all; quit -code [expr {[coverage attribute -name TESTSTATUS -concise] >= 2}]'
endif

# -------------------------------
# Functional simulation
#

LIBRARY_NAME_RTL = $(UNIT_NAME)
LIBRARY_WORK_RTL = $(PROJECT_WORK)/$(LIBRARY_NAME_RTL)

TARGET_MODULE_RTL = \
	$(PROJECT_WORK)/$(LIBRARY_NAME_RTL).$(TEST_BENCH_MODULE) \

DEPS_RTL = \
	$(TYPES:%=$(SOURCE_ROOT)%) \
	$(MODULES:%=$(SOURCE_ROOT)%) \
	$(TEST_MODULES:%=$(SOURCE_ROOT)%) \

rtl: $(LIBRARY_WORK_RTL) Makefile $(DEPS_RTL)
	$(VLOG) -work $(LIBRARY_WORK_RTL) \
	$(VLOG_OPTIONS) $(VLOG_OPTIONS_COMMON) $(VLOG_OPTIONS_RTL) \
	$(DEPS_RTL) # compile
	$(VSIM) $(TARGET_MODULE_RTL) -do "quit" # link check

rtl-run:
	$(VSIM) $(TARGET_MODULE_RTL) $(VSIM_OPTIONS) $(VSIM_OPTIONS_RTL) -do "run -all"

rtl-run-gui:
	$(MODELSIM) $(TARGET_MODULE_RTL) $(VSIM_OPTIONS) $(VSIM_OPTIONS_RTL) $(VSIM_OPTIONS_DUMP)

rtl-clean:
	mkdir $(PROJECT_WORK) -p
	rm -f -r $(LIBRARY_WORK_RTL)
	$(VLIB) $(PROJECT_WORK)/$(LIBRARY_NAME_RTL)

$(LIBRARY_WORK_RTL):
	mkdir $(PROJECT_WORK) -p
	$(VLIB) $(PROJECT_WORK)/$(LIBRARY_NAME_RTL)

# -------------------------------
# Clean
#
clean:
	mkdir $(PROJECT_WORK) -p
	rm -f -r $(LIBRARY_WORK_RTL)
