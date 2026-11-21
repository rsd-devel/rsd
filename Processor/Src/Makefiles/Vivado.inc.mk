$(call REQUIRE_ENV,RSD_VIVADO_ROOT)


# Specify the target Zynq board.
# Supported Zynq boards: Zedboard
TARGET_BOARD = Zedboard

# -------------------------------

# For Vivado
VIVADO_BOARD_PROJECT = rsd
VIVADO_POST_SYNTHESIS_PROJECT = rsd_post_synthesis

VIVADO_PROJECT_ROOT = ../Project/Vivado/TargetBoards/$(TARGET_BOARD)
VIVADO_PROJECT_FILE = $(VIVADO_BOARD_PROJECT_ROOT)/rsd.xpr
VIVADO_BOARD_PROJECT_ROOT = $(VIVADO_PROJECT_ROOT)/$(VIVADO_BOARD_PROJECT)
VIVADO_POST_SYNTHESIS_PROJECT_ROOT = $(VIVADO_PROJECT_ROOT)/$(VIVADO_POST_SYNTHESIS_PROJECT)
VIVADO_BOARD_PROJECT_IMPL = $(VIVADO_BOARD_PROJECT_ROOT)/$(VIVADO_BOARD_PROJECT).runs/impl_1
VIVADO_BOARD_PROJECT_SDK = $(VIVADO_BOARD_PROJECT_ROOT)/$(VIVADO_BOARD_PROJECT).sdk
VIVADO_XSA_FILE = $(VIVADO_BOARD_PROJECT_ROOT)/design_1_wrapper.xsa
VIVADO_BIT_FILE = $(VIVADO_BOARD_PROJECT_IMPL)/design_1_wrapper.bit
VIVADO_FSBL_FILE = $(VIVADO_BOARD_PROJECT_SDK)/fsbl/Release/fsbl.elf

# -------------------------------
# Vivado : Make RSD project, run synthesis and run implementation for TARGET_BOARD.
#

# vivadoプロジェクトを作成して開く．すでに作成されている場合は開くのみ．
vivado: $(VIVADO_PROJECT_FILE)
	$(RSD_VIVADO_ROOT)/bin/vivado $(VIVADO_PROJECT_FILE) &

# vivadoプロジェクトの削除
vivado-clean:
	rm -f -r $(VIVADO_BOARD_PROJECT_ROOT)
	rm -f vivado*.jou
	rm -f vivado*.log
	rm -f vivado*.zip
	rm -f vivado*.str

# Vivado を使った合成
vivado-synthesis: $(VIVADO_BIT_FILE)
	@echo "==== Build Successful ===="

VIVADO_RTL_INPUTS = $(abspath $(addprefix $(SOURCE_ROOT),$(TYPES) $(MODULES) $(HEADERS) Config/SynthesisMacros.sv))

# Both frontends use rsd.xpr. Re-import the IP when switching synthesis tools.
VIVADO_PROJECT_FLOW := $(basename $(notdir $(MAKEFILE)))
VIVADO_PROJECT_FLOW_FILE := $(VIVADO_BOARD_PROJECT_ROOT)/.synthesis-tool
ifneq ($(VIVADO_PROJECT_FLOW),$(file <$(VIVADO_PROJECT_FLOW_FILE)))
.PHONY: vivado-flow-changed
$(VIVADO_PROJECT_FILE): vivado-flow-changed
endif

# These inputs are also used when Vivado implements a Synplify netlist.
$(VIVADO_PROJECT_FILE): $(VIVADO_PROJECT_ROOT)/scripts/synthesis/design_1.tcl $(VIVADO_PROJECT_ROOT)/project_src/zedboard.xdc

# ビットストリームの生成
# XSA ファイルは generate_bitstream.tcl 内で bit と同時に生成される
$(VIVADO_BIT_FILE) $(VIVADO_XSA_FILE): $(VIVADO_PROJECT_FILE) $(DEPS_RTL)
	$(RSD_VIVADO_ROOT)/bin/vivado -mode batch -source $(VIVADO_PROJECT_ROOT)/scripts/synthesis/generate_bitstream.tcl
	
# $(VIVADO_XSA_FILE): $(VIVADO_BIT_FILE)
#	$(RSD_VIVADO_ROOT)/bin/vivado -mode batch -source $(VIVADO_PROJECT_ROOT)/export_xsa.tcl
#	cp $(VIVADO_BOARD_PROJECT_IMPL)/design_1_wrapper.sysdef $(VIVADO_XSA_FILE)
#	@echo "(Re-)build hdf using Vivado!"
#	exit 1


# Build hardware/FSBL outside the dev container using Vivado/Vitis 2019.2.
.PHONY: zynq-hardware
zynq-hardware: $(VIVADO_FSBL_FILE)

$(VIVADO_FSBL_FILE): $(VIVADO_XSA_FILE) $(VIVADO_PROJECT_ROOT)/scripts/synthesis/make_fsbl.tcl
	@$(call REQUIRE_ENV,RSD_VITIS_ROOT)test -x "$(RSD_VITIS_ROOT)/bin/xsct"
	rm -rf $(VIVADO_BOARD_PROJECT_SDK)
	"$(RSD_VITIS_ROOT)/bin/xsct" $(VIVADO_PROJECT_ROOT)/scripts/synthesis/make_fsbl.tcl
	test -s $@
