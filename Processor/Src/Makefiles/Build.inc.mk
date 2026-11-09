# Shared core source dependencies and generated RTL; run from Processor/Src.
SOURCE_ROOT ?= ./
TOOLS_ROOT ?= ../Tools/
include Makefiles/Environment.inc.mk
include Makefiles/GenerateMemoryMap.inc.mk

# Keep this manifest in place with literal TYPES/CORE_MODULES lists for sv-tests.
include Makefiles/CoreSources.inc.mk

DEPS_RTL = $(addprefix $(SOURCE_ROOT),$(TYPES) $(MODULES) $(TEST_MODULES))

# The manifest stays relative for sv-tests; share the absolute generation rule.
$(CORE_TEMPLATE_FILES): $(RSD_MEMORY_MAP_OUTPUTS)
