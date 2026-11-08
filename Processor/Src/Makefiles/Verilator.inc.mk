# Shared Verilator options for core and unit testbenches.
ifndef RSD_VERILATOR_BIN
VERILATOR_BIN = verilator
else
VERILATOR_BIN = $(RSD_VERILATOR_BIN)
endif


VERILATED_TOP_MODULE_NAME = V$(TOP_MODULE)

# Temporally disabled warnings
# MULTIDRIVEN: simulation-only initializers also write always_ff registers.
VERILATOR_DISABLED_WARNING = \
     -Wno-WIDTH \
     -Wno-INITIALDLY \
     -Wno-UNOPTFLAT \
     -Wno-MULTIDRIVEN \

# RSD specific constants
# RSD_SRC_CFG is defined in Makefiles/CoreSources.inc.mk
RSD_VERILATOR_DEFINITION ?= \
	+define+RSD_FUNCTIONAL_SIMULATION \
	$(RSD_SRC_CFG) \


# --main/--timing: Generate the execution loop for the shared SV testbench.
# --assert: Enable all assertions.
# --Mdir: Name of output object directory.
# We use "-Os" and "-output-split 15000" for faster compilation.
# See https://www.veripool.org/papers/Verilator_Accelerated_OSDA2020.pdf
VERILATOR_OPTION = \
	--cc \
	--main \
	--timing \
	--timescale 1ns/1ps \
	--exe \
	--assert \
	-sv \
	--top-module $(TOP_MODULE) \
	$(VERILATOR_DISABLED_WARNING) \
	$(RSD_VERILATOR_DEFINITION) \
	--Mdir $(LIBRARY_WORK_RTL) \
	+incdir+. \
	--trace \
	-CFLAGS "-Os" \
	-output-split 15000 \
	#-CFLAGS "-O0 -g" \
	#--MMD \
	#-O3 \

