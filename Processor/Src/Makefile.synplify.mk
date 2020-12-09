
# Makefile for synthesizing on Vivado using Synplify netlist

# Specify test code and simulation cycles of post-synthesis simulation
MAX_TEST_CYCLES = 10000
SHOW_SERIAL_OUT = 1
ENABLE_PC_GOAL = 1
TEST_CODE = Verification/TestCode/C/Fibonacci
#TEST_CODE = Verification/TestCode/C/HelloWorld

SOURCE_ROOT  = ./
TOOLS_ROOT   = ../Tools/
PROJECT_WORK =  ../Project/ModelSim
TEST_CODE_HEX = $(TEST_CODE)/code.hex

# Specify a top module name for test
UNIT_NAME         = Main

# Library name and a top level module（simulation target）
TEST_BENCH_MODULE = Test$(UNIT_NAME)
TOP_MODULE        = $(UNIT_NAME)

# Output files
RSD_LOG_FILE_RTL       			= RSD.log
RSD_LOG_FILE_POST_SYNTHESIS 	= RSD-post-synthesis.log
KANATA_LOG_FILE_RTL       		= Kanata.log
KANATA_LOG_FILE_POST_SYNTHESIS 	= Kanata-post-synthesis.log
DEBUG_LOG_FILE_RTL       		= Debug.log
DEBUG_LOG_FILE_POST_SYNTHESIS 	= Debug-post-synthesis.log
REG_CSV_FILE 					= Register.csv



SYNPLIFY_ROOT = ../Project/Synplify
SYNPLIFY_PROJECT_ROOT = $(SYNPLIFY_ROOT)/$(TARGET_BOARD)
SYNPLIFY_POST_SYNTHESIS_PROJECT_ROOT = $(SYNPLIFY_ROOT)/$(TARGET_BOARD)_post_synthesis

MAKEFILE = Makefile.synplify.mk
MAKE = make -f $(MAKEFILE)

# -------------------------------
# Synthesis
# This procedure uses both Synplify and Vivado.
#   1. Create Synplify netlist (launch Synplify manually and 
#	    open project $(RSD_ROOT)/Processor/Project/Synplify/ver2017-03.prj)
#   2. Synthesize RSD using Vivado
#

SYNPLIFY_NETLIST = $(SYNPLIFY_PROJECT_ROOT)/rsd.vm

# Vivado synthesis related items are defined in this file
include Makefiles/Vivado.inc.mk

$(VIVADO_PROJECT_FILE): $(SYNPLIFY_NETLIST)
	@cd $(VIVADO_PROJECT_ROOT); \
	$(RSD_VIVADO_BIN)/vivado -mode batch \
		-source scripts/synthesis/create_project_using_synplify_netlist.tcl
	
$(SYNPLIFY_NETLIST): $(TYPES) $(TEST_MODULES) $(MODULES)
	@ echo "(Re-)build post-synthesis netlist using Synplify!"
	$(MAKE) vivado-clean
	@ exit 1


# -------------------------------
# Post synthesis simulation
# This procedure uses Synplify, Vivado and QuestaSim (or ModelSim).
#   1. Create Synplify netlist for post synthesis sim. (launch Synplify manually and
#	    open project $(RSD_ROOT)/Processor/Project/Synplify/ver2017-03.prj)
#   2. Synthesize RSD using Vivado
#	3. Launch post-synthesis simulation on QuestaSim

include Makefile.inc
include Makefiles/CoreSources.inc.mk

SYNPLIFY_ROOT = ../Project/Synplify
SYNPLIFY_POST_SYNTHESIS_PROJECT_ROOT = $(SYNPLIFY_ROOT)/Zedboard_post_synthesis
SYNPLIFY_POST_SYNTHESIS_NETLIST = $(SYNPLIFY_POST_SYNTHESIS_PROJECT_ROOT)/rsd.vm
VIVADO_POST_SYNTHESIS_PROJECT_FILE = $(VIVADO_POST_SYNTHESIS_PROJECT_ROOT)/rsd_post_synthesis.xpr
POST_SYNTHESIS_MODULE = $(VIVADO_PROJECT_ROOT)/$(TOP_MODULE)_post_synthesis.v
POST_SYNTHESIS_CODE_HEX = $(SYNPLIFY_ROOT)/code.hex

LIBRARY_NAME_POST_SYNTHESIS = $(UNIT_NAME)_post_synthesis
LIBRARY_WORK_POST_SYNTHESIS = $(PROJECT_WORK)/$(LIBRARY_NAME_POST_SYNTHESIS)

DEPS_POST_SYNTHESIS = \
	$(TYPES:%=$(SOURCE_ROOT)%) \
	$(TEST_MODULES:%=$(SOURCE_ROOT)%) \
	$(POST_SYNTHESIS_MODULE) \

TARGET_MODULE_POST_SYNTHESIS = \
	$(PROJECT_WORK)/$(LIBRARY_NAME_POST_SYNTHESIS).$(TEST_BENCH_MODULE) \
	$(PROJECT_WORK)/$(LIBRARY_NAME_POST_SYNTHESIS).$(GLBL_MODULE) \

VLOG_OPTIONS_POST_SYNTHESIS = \
	+define+RSD_FUNCTIONAL_SIMULATION \
	+define+RSD_POST_SYNTHESIS_SIMULATION \

VSIM_OPTIONS_POST_SYNTHESIS = \
	+RSD_LOG_FILE=$(RSD_LOG_FILE_POST_SYNTHESIS) \
	+DEBUG_LOG_FILE=$(DEBUG_LOG_FILE_POST_SYNTHESIS) \
	-modelsimini $(RSD_MODELSIM_INI) \
	-L simprims_ver \
	-L unisims_ver \

# post-synthesisシミュレーション用のmodelsimプロジェクトのコンパイル
post-synthesis:
	diff -u $(TEST_CODE_HEX) $(POST_SYNTHESIS_CODE_HEX)
	$(MAKE) post-synthesis-main

# post-synthesisシミュレーションの実行
# 事前にコンパイルが必要
post-synthesis-run:
	$(VSIM) $(TARGET_MODULE_POST_SYNTHESIS) \
		$(VSIM_OPTIONS) $(VSIM_OPTIONS_POST_SYNTHESIS) -do "run -all"

# post-synthesisシミュレーションのGUIを用いた実行
# 事前にコンパイルが必要
post-synthesis-run-gui:
	$(MODELSIM) $(TARGET_MODULE_POST_SYNTHESIS) \
		$(VSIM_OPTIONS) $(VSIM_OPTIONS_POST_SYNTHESIS)

# Dump post-synthesis simulation Kanata log 
post-synthesis-kanata: post-synthesis-run
	$(KANATA_CONVERTER) $(RSD_LOG_FILE_POST_SYNTHESIS) $(KANATA_LOG_FILE_POST_SYNTHESIS)


# post-synthesisシミュレーション関連ファイルの削除
post-synthesis-clean:
	mkdir $(PROJECT_WORK) -p
	rm -f -r $(LIBRARY_WORK_POST_SYNTHESIS)
	$(VLIB) $(PROJECT_WORK)/$(LIBRARY_NAME_POST_SYNTHESIS)
	$(MAKE) vivado-post-synthesis-clean

# post-synthesisシミュレーションモデル(.vm)作成用vivadoプロジェクトの削除
vivado-post-synthesis-clean: 
	rm -f -r $(VIVADO_POST_SYNTHESIS_PROJECT_ROOT)
	rm -f vivado*.jou
	rm -f vivado*.log
	rm -f vivado*.zip
	rm -f vivado*.str

# Do NOT use this command.
# This command is called automatically if you need.
post-synthesis-main: $(LIBRARY_WORK_POST_SYNTHESIS) Makefile $(DEPS_POST_SYNTHESIS) 
	$(VLOG) -work $(LIBRARY_WORK_POST_SYNTHESIS) \
		$(VLOG_OPTIONS) $(VLOG_OPTIONS_COMMON) $(VLOG_OPTIONS_POST_SYNTHESIS) \
		$(DEPS_VIVADO) $(DEPS_POST_SYNTHESIS) # compile

# Do NOT use this command.
# This command is called automatically if you need.
vivado-post-synthesis-create:
	$(RSD_VIVADO_BIN)/vivado -mode batch \
		-source $(VIVADO_PROJECT_ROOT)/scripts/post_synthesis/create_project_for_questasim.tcl

$(LIBRARY_WORK_POST_SYNTHESIS):
	mkdir $(PROJECT_WORK) -p
	$(VLIB) $(PROJECT_WORK)/$(LIBRARY_NAME_POST_SYNTHESIS)

$(SYNPLIFY_POST_SYNTHESIS_NETLIST): $(TYPES) $(TEST_MODULES) $(MODULES)
	@echo "Re-build post-synthesis netlist using Synplify!"
	exit 1

$(POST_SYNTHESIS_MODULE): $(SYNPLIFY_POST_SYNTHESIS_NETLIST) $(VIVADO_POST_SYNTHESIS_PROJECT_FILE)
	$(RSD_VIVADO_BIN)/vivado -mode batch \
		-source $(VIVADO_PROJECT_ROOT)/scripts/post_synthesis/run_synthesis.tcl

$(VIVADO_POST_SYNTHESIS_PROJECT_FILE):
	$(MAKE) vivado-post-synthesis-create || $(MAKE) vivado-post-synthesis-clean

