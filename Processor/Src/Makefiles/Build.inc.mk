# Shared core source dependencies and generated RTL; run from Processor/Src.
SOURCE_ROOT ?= ./
TOOLS_ROOT ?= ../Tools/
include Makefiles/GenerateConfig.inc.mk

# Keep this manifest in place with literal TYPES/CORE_MODULES lists for sv-tests.
include Makefiles/CoreSources.inc.mk

DEPS_RTL = $(abspath $(addprefix $(SOURCE_ROOT),$(TYPES) $(MODULES) $(TEST_MODULES)))

# Use the generator's absolute paths so each output has a single make target.
# Keep the source manifest itself relative for sv-tests.
CORE_TEMPLATE_FILES := $(abspath $(CORE_TEMPLATE_FILES))
