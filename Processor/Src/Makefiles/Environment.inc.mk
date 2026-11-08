# Always use this checkout, even if the shell inherited another RSD_ROOT.
override RSD_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../..)
export RSD_ROOT

# Validate explicit settings. Query mode must work before setup for completion.
ifeq ($(findstring q,$(firstword $(MAKEFLAGS))),)
REQUIRE_ENV = $(foreach name,$(1),$(if $(strip $($(name))),,$(error $(name) is not set. Use the dev container or source your edited Processor/Tools/SetEnv/MySetEnv.sh (see README.md))))
endif
