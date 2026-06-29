
# CAUTION! The following macros must be defined in SynthesisMacros.sv on synthesis.
#
# Definitions related to microarchitecture configuration:
# * RSD_MARCH_UNIFIED_LDST_MEM_PIPE:  Use unified LS/ST pipeline
# * RSD_MARCH_INT_ISSUE_WIDTH=N: Set issue width to N
# * RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE: Integrate mul/div to a memory pipe
RSD_SRC_CFG = \
	+define+RSD_MARCH_INT_ISSUE_WIDTH=2 \
	+define+RSD_MARCH_FP_PIPE \
	+define+RSD_ENABLE_ZBA \
	+define+RSD_ENABLE_ZICOND \

#	+define+RSD_MARCH_UNIFIED_LDST_MEM_PIPE \
#	+define+RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE \


# Veryl is used for packages, interfaces, and converted modules.
VERYL_FILELIST ?= rsd.f
VERYL_GENERATED_RTL ?= $(VERYL_FILELIST)
VERYL_SOURCE_LIST = $(shell awk 'BEGIN { in_sources = 0 } /^sources = \[/ { in_sources = 1; next } in_sources && /^\]/ { in_sources = 0 } in_sources { gsub(/[",]/, ""); gsub(/^[ \t]+|[ \t]+$$/, ""); if ($$0 != "") print $$0 }' Veryl.toml)
VERYL_ORDERED_RTL = $(VERYL_SOURCE_LIST:%.veryl=target/veryl/%.sv)

# TYPES specifies files that include packages that contain type definitions.
# Be careful about the order of these files.
# A file containing a imported package should be placed first.
TYPES = $(VERYL_ORDERED_RTL)

# CORE_MODULES specifies files that defines the RSD core.
# The order of the files in this section is arbitrary.
CORE_MODULES = \

SV_LEAF_MODULES = \
	Primitives/RAM.sv \
	Cache/DCache.sv \
	Memory/Memory.sv \
	Memory/Axi4LiteControlRegister.sv \
	Memory/Axi4LiteMemory.sv \
	Memory/ControlQueue.sv \
	Memory/Axi4Memory.sv \
	Memory/MemoryReadReqQueue.sv \
	Memory/MemoryWriteDataQueue.sv \

# MODULES specifies what to compile for simulation.
MODULES = \
	Main_Zynq_Wrapper.sv \
	Main_Zynq.sv \
	$(SV_LEAF_MODULES) \
	$(CORE_MODULES) \

# Specify files with module definitions that are used only for testing and not used for synthesis.
# TestMain depends on Dumper and should come later.
TEST_MODULES = \
	Verification/TestBenchClockGenerator.sv \
	Verification/Dumper.sv \
	Verification/TestMain.sv \

# Header files
# This list is used when generating Vivado custom IP of RSD
HEADERS = \
	BasicMacros.sv \
	SysDeps/SynthesisMacros.svh \
	SysDeps/XilinxMacros.vh \
