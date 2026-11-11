# Keep configuration generation separate from CoreSources.inc.mk so callers can use it
# without overwriting their own TYPES/MODULES lists (notably unit tests).
# CoreSources.inc.mk also serves as a source manifest parsed directly by
# sv-tests and Xilinx tools.
# Shared by RTL builds and software/test builds, including direct invocations.
# Include Environment.inc.mk first to set RSD_ROOT.
RSD_CONFIG_GENERATOR := $(RSD_ROOT)/Processor/Tools/ConfigGenerator/ConfigGenerator.py

# GNU Make 4.2 has no grouped targets. Each group shares one generation stamp.
# Force regeneration when any output is missing. Remove the stamp before running
# so failed generation is retried. Use the first output's timestamp for the stamp
# so included .mk outputs do not appear older than their prerequisite.

# Memory map: RTL types and software definitions.
RSD_MEMORY_MAP_OUTPUTS := $(RSD_ROOT)/Processor/Src/Config/MemoryMapTypes.sv \
	$(addprefix $(RSD_ROOT)/Processor/Src/Verification/TestCode/,rsd-memory-map.h rsd-memory-map.ld rsd-memory-map.mk)
RSD_MEMORY_MAP_STAMP := $(RSD_ROOT)/Processor/Src/Config/MemoryMap.stamp

$(RSD_MEMORY_MAP_OUTPUTS): $(RSD_MEMORY_MAP_STAMP)
ifneq ($(filter-out $(wildcard $(RSD_MEMORY_MAP_OUTPUTS)),$(RSD_MEMORY_MAP_OUTPUTS)),)
.PHONY: $(RSD_MEMORY_MAP_STAMP)
endif

$(RSD_MEMORY_MAP_STAMP): $(RSD_CONFIG_GENERATOR) \
	$(RSD_ROOT)/Processor/Config/MemoryMap.toml \
	$(RSD_ROOT)/Processor/Src/Config/MemoryMapTypes.template.sv
	@rm -f "$@"
	python3 $(RSD_CONFIG_GENERATOR) --rsd-root $(RSD_ROOT) --only memory-map
	@for output in $(RSD_MEMORY_MAP_OUTPUTS); do test -s "$$output" || exit 1; done
	@touch -r "$(firstword $(RSD_MEMORY_MAP_OUTPUTS))" "$@"

# Microarchitecture: RTL parameters, synthesis macros, and simulator defines.
RSD_MICRO_ARCH_OUTPUTS := $(addprefix $(RSD_ROOT)/Processor/Src/,Config/MicroArchConf.sv Config/MicroArchMacros.svh Makefiles/MicroArch.inc.mk)
RSD_MICRO_ARCH_STAMP := $(RSD_ROOT)/Processor/Src/Config/MicroArch.stamp

$(RSD_MICRO_ARCH_OUTPUTS): $(RSD_MICRO_ARCH_STAMP)
ifneq ($(filter-out $(wildcard $(RSD_MICRO_ARCH_OUTPUTS)),$(RSD_MICRO_ARCH_OUTPUTS)),)
.PHONY: $(RSD_MICRO_ARCH_STAMP)
endif

$(RSD_MICRO_ARCH_STAMP): $(RSD_CONFIG_GENERATOR) \
	$(RSD_ROOT)/Processor/Config/MicroArch.toml \
	$(RSD_ROOT)/Processor/Src/Config/MicroArchConf.template.sv
	@rm -f "$@"
	python3 $(RSD_CONFIG_GENERATOR) --rsd-root $(RSD_ROOT) --only microarch
	@for output in $(RSD_MICRO_ARCH_OUTPUTS); do test -s "$$output" || exit 1; done
	@touch -r "$(firstword $(RSD_MICRO_ARCH_OUTPUTS))" "$@"

RSD_CONFIG_OUTPUTS := $(RSD_MEMORY_MAP_OUTPUTS) $(RSD_MICRO_ARCH_OUTPUTS)
