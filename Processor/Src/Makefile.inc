# -------------------------------
# This file includes definitions that used from the main Makefile and unit tests.
#

VLOG = $(RSD_QUESTASIM_PATH)/vlog
VLIB = $(RSD_QUESTASIM_PATH)/vlib
# In Linux, "vsim" is launched in GUI, so explicitly specify a command line mode (-c)
VSIM = $(RSD_QUESTASIM_PATH)/vsim -c   
VOPT = $(RSD_QUESTASIM_PATH)/vopt
MODELSIM = $(RSD_QUESTASIM_PATH)/vsim 





# -------------------------------
# FPGAプリミティブの定義があるファイルを指定する．
SIMPRIMS = \
	X_AND2B1L.v \
	X_BUF.v \
	X_CARRY4.v \
	X_CKBUF.v \
	X_DCM_SP.v \
	X_FF.v \
	X_IBUFDS.v \
	X_INV.v \
	X_IPAD.v \
	X_LATCHE.v \
	X_LUT2.v \
	X_LUT3.v \
	X_LUT4.v \
	X_LUT5.v \
	X_LUT6.v \
	X_LUT6_2.v \
	X_MUX2.v \
	X_OBUF.v \
	X_ONE.v \
	X_OPAD.v \
	X_MMCM_ADV.v \
	X_RAM32M.v \
	X_RAM64M.v \
	X_RAMB8BWER.v \
	X_RAMB16BWER.v \
	X_RAMB18E1.v \
	X_RAMB36E1.v \
	X_RAMD128.v \
	X_RAMD16.v \
	X_RAMD32.v \
	X_RAMD64.v \
	X_RAMD64_ADV.v \
	X_RAMS128.v \
	X_RAMS16.v \
	X_RAMS32.v \
	X_RAMS64.v \
	X_SFF.v \
	X_SRL16E.v \
	X_SRLC16E.v \
	X_SRLC32E.v \
	X_XOR2.v \
	X_ZERO.v \
	X_DSP48E1.v \

UNISIMS = \
	AND2B1L.v \
	BUF.v \
	BUFG.v \
	CARRY4.v \
	DCM_SP.v \
	FDCE.v \
	FDPE.v \
	FDRE.v \
	FDSE.v \
	FDRSE.v \
	IBUF.v \
	IBUFDS.v \
	INV.v \
	LUT1.v \
	LUT2.v \
	LUT3.v \
	LUT4.v \
	LUT5.v \
	LUT6.v \
	LUT6_2.v \
	OBUF.v \
	MMCM_ADV.v \
	MUXF7.v \
	MUXF8.v \
	RAM32M.v \
	RAM32X1D.v \
	RAM64M.v \
	RAM64X1D.v \
	RAM128X1D.v \
	RAMB8BWER.v \
	RAMB16BWER.v \
	RAMB18E1.v \
	RAMB36E1.v \
	SRL16E.v \
	SRLC16E.v \
	SRLC32E.v \
	XOR2.v \
	DSP48E1.v \
	RAM256X1S.v \


# glbl モジュール．コンパイル時のターゲットに指定する必要がある．
GLBL = glbl.v
GLBL_MODULE = glbl

# -------------------------------
# FPGAプリミティブの定義があるファイルが存在するパス．
# ModelSimが処理するため、CygwinではなくWindowsのパスとして指定する．

VIVADO_SIMPRIMS_ROOT= $(RSD_VIVADO)/verilog/src/simprims/
VIVADO_UNISIMS_ROOT= $(RSD_VIVADO)/verilog/src/unisims/
VIVADO_GLBL_ROOT= $(RSD_VIVADO)/verilog/src/

DEPS_VIVADO = \
	$(SIMPRIMS:%="$(VIVADO_SIMPRIMS_ROOT)%") \
	$(UNISIMS:%="$(VIVADO_UNISIMS_ROOT)%") \
	$(GLBL:%="$(VIVADO_GLBL_ROOT)%") \

# -------------------------------
# Unit test helper
#

REPLACE_PATH = python3 $(TOOLS_ROOT)/UnitTestHelper/ReplacePath.py

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

all: rtl translate map par

# Simulation on a command line mode.
run: rtl-run

# Simulation on a GUI mode.
run-gui: rtl-run-gui

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
