# ACT4 dependencies are fetched and installed explicitly, outside test builds.
ARCH_TEST_URL = https://github.com/riscv/riscv-arch-test.git
ARCH_TEST_REVISION = 887ca0885f427e2b7824fedce5806b7fb7aed5d1
BUNDLER_VERSION = 4.0.22
SAIL_VERSION = 0.15
SAIL_ARCH := $(shell uname -m)
SAIL_SHA256_x86_64 = 8bb3626a6ce5d45c1d1fa7b907f9d9602cc23270883e470db5d6401f26a2e143
SAIL_SHA256_aarch64 = 52980f9afb50f2468c61589522d28ac97d74db36ad3fdcdb63b335f5c4286202
SAIL_SHA256 = $(SAIL_SHA256_$(SAIL_ARCH))
SAIL_URL = https://github.com/riscv/sail-riscv/releases/download/$(SAIL_VERSION)/sail-riscv-Linux-$(SAIL_ARCH).tar.gz
PYTHON ?= python3
JOBS ?= $(shell nproc)
include ../../../Makefiles/CoreSources.inc.mk
# Add extensions here as their RSD configuration and adapters are validated.
comma := ,
empty :=
space := $(empty) $(empty)
ACT_PRIV_EXTENSIONS := ExceptionsSm ExceptionsZaamo ExceptionsZalrsc
ACT_AVAILABLE_EXTENSIONS := I M Zaamo Zalrsc Zicsr $(ACT_PRIV_EXTENSIONS) \
	$(if $(filter +define+RSD_ENABLE_ZBA +define+RSD_ENABLE_ZBA=%,$(RSD_SRC_CFG)),Zba) \
	$(if $(filter +define+RSD_ENABLE_ZICOND +define+RSD_ENABLE_ZICOND=%,$(RSD_SRC_CFG)),Zicond) \
	$(if $(filter 1,$(RSD_HAS_FP)),F)
# Keep F opt-in until rounding modes and div/sqrt rounding flags are implemented.
ACT_EXTENSIONS ?= $(subst $(space),$(comma),$(strip $(filter-out F,$(ACT_AVAILABLE_EXTENSIONS))))
ACT_EXTENSION_LIST := $(subst $(comma), ,$(ACT_EXTENSIONS))
# Upstream's 1,000-testcase FP files exceed RSD's fixed ROM/RAM layout.
# Include the generated list so make also selects new chunks on the first build.
ifneq ($(filter F,$(ACT_EXTENSION_LIST)),)
ifneq ($(filter build run run-cases,$(MAKECMDGOALS) $(if $(MAKECMDGOALS),,build)),)
include Build/Generated/F.mk
endif
endif
# Only M-mode exception cases are used; delegation cases need an S-mode port.
ACT_GENERATED_SOURCES := $(foreach extension,$(filter $(ACT_PRIV_EXTENSIONS),$(ACT_EXTENSION_LIST)),Build/Generated/priv/$(extension)/$(extension)-00.S)
ACT_SOURCES := $(sort $(foreach extension,$(filter-out F,$(ACT_EXTENSION_LIST)),$(wildcard External/tests/rv32i/$(extension)/*.S)) \
	$(if $(filter F,$(ACT_EXTENSION_LIST)),$(ACT_FP_SOURCES)) \
	$(ACT_GENERATED_SOURCES))
ACT_TESTS ?= $(basename $(notdir $(ACT_SOURCES)))
ACT_SELECTED_SOURCES := $(foreach test,$(ACT_TESTS),$(filter %/$(test).S,$(ACT_SOURCES)))
ACT_CASES := $(patsubst External/tests/%.S,%,$(patsubst Build/Generated/%.S,%,$(ACT_SELECTED_SOURCES)))
TEST_DRIVER ?= $(PYTHON) ../Tools/TestDriver/RunTest.py -o --simulator=verilator

# Keep environments, downloaded tools and caches beside this test suite.
BUILD_ROOT := $(CURDIR)/Build
CASE_ROOT := $(BUILD_ROOT)/Cases
ACT_RESULTS := $(sort $(addprefix $(CASE_ROOT)/,$(addsuffix /result.log,$(ACT_CASES))))
ACT_ELF_ROOT := $(BUILD_ROOT)/act/rsd-rv32i/elfs
SAIL_ARCHIVE = $(BUILD_ROOT)/sail-riscv-$(SAIL_VERSION)-Linux-$(SAIL_ARCH).tar.gz
SAIL_BINARY = $(BUILD_ROOT)/sail/bin/sail_riscv_sim
export VIRTUAL_ENV := $(BUILD_ROOT)/venv
export GEM_HOME := $(BUILD_ROOT)/gems
export GEM_PATH := $(GEM_HOME)
export BUNDLE_APP_CONFIG := $(BUILD_ROOT)/bundle-config
export BUNDLE_PATH := $(BUILD_ROOT)/bundle
export BUNDLE_FROZEN := true
export BUNDLE_GEMFILE := $(CURDIR)/External/framework/src/act/data/Gemfile
export XDG_CACHE_HOME := $(BUILD_ROOT)/cache
# UDB takes exclusive locks on read-only cache files, which fail on NFS.
# Keep its regenerated architecture data on the container's local filesystem.
export XDG_DATA_HOME := /tmp/rsd-arch-test-$(shell id -u)/data
export PATH := $(VIRTUAL_ENV)/bin:$(GEM_HOME)/bin:/usr/lib/llvm-22/bin:$(BUILD_ROOT)/sail/bin:$(PATH)
BUNDLE = "$(GEM_HOME)/bin/bundle" _$(BUNDLER_VERSION)_

.DEFAULT_GOAL := build
.PHONY: fetch setup check check-source check-platform check-selection config build run run-cases clean
# Always rerun selected cases, even when their result files already exist.
.PHONY: $(ACT_RESULTS)

# Keep Vivado's elaboration workflow sequential.
ifneq ($(findstring --simulator=vivadosim,$(TEST_DRIVER)),)
.NOTPARALLEL:
endif

fetch:
	@if test -e External; then \
		$(MAKE) check-source; \
	else \
		git init -q External && \
		git -C External remote add origin $(ARCH_TEST_URL) && \
		git -C External fetch --depth=1 origin $(ARCH_TEST_REVISION) && \
		git -C External checkout --detach $(ARCH_TEST_REVISION); \
	fi

check-source:
	@test -d External/.git || { echo "Run make test-fetch-riscv-arch-test from Processor/Src first." >&2; exit 1; }
	@test "$$(git -C External rev-parse HEAD)" = "$(ARCH_TEST_REVISION)" || { echo "riscv-arch-test revision differs from ARCH_TEST_REVISION in Makefile." >&2; exit 1; }
	@git -C External diff --quiet HEAD || { echo "riscv-arch-test External has local changes; preserve or revert them before setup." >&2; exit 1; }

check-platform:
	@test "$$(uname -s)" = Linux && test -n "$(SAIL_SHA256)" || { echo "Sail setup supports Linux x86_64 and aarch64." >&2; exit 1; }

$(SAIL_ARCHIVE): | check-platform
	mkdir -p "$(BUILD_ROOT)"
	curl --fail --location --retry 3 --output "$@.tmp" "$(SAIL_URL)"
	printf '%s  %s\n' "$(SAIL_SHA256)" "$@.tmp" | sha256sum --check -
	mv "$@.tmp" "$@"

$(SAIL_BINARY): $(SAIL_ARCHIVE) Makefile
	printf '%s  %s\n' "$(SAIL_SHA256)" "$(SAIL_ARCHIVE)" | sha256sum --check -
	mkdir -p "$(BUILD_ROOT)/sail"
	tar -xzf "$(SAIL_ARCHIVE)" --strip-components=1 -C "$(BUILD_ROOT)/sail"
	touch "$@"

# Use Ubuntu's Python/Ruby and upstream packages; no mise, uv or toolchain build.
setup: check-source check-platform $(SAIL_BINARY)
	$(PYTHON) -m venv "$(VIRTUAL_ENV)"
	"$(VIRTUAL_ENV)/bin/python3" -m pip install --disable-pip-version-check \
		-e ./External/framework -e ./External/generators/testgen -e ./External/generators/coverage
	gem list --local --exact bundler --version $(BUNDLER_VERSION) --installed || \
		gem install bundler --version $(BUNDLER_VERSION) --no-document
	$(BUNDLE) install --jobs $(JOBS)
	$(MAKE) check

# Check installed tools without downloading or changing the environment.
check: check-source check-platform
	@test -x "$(VIRTUAL_ENV)/bin/act" && test -x "$(GEM_HOME)/bin/bundle" && test -x "$(SAIL_BINARY)" || \
		{ echo "Run make test-setup-riscv-arch-test from Processor/Src first." >&2; exit 1; }
	"$(VIRTUAL_ENV)/bin/python3" -m pip check
	$(BUNDLE) check
	$(BUNDLE) exec udb version
	"$(VIRTUAL_ENV)/bin/act" --help >/dev/null
	"$(VIRTUAL_ENV)/bin/testgen" --help >/dev/null
	"$(VIRTUAL_ENV)/bin/covergroupgen" --help >/dev/null
	"$(SAIL_BINARY)" --version
	clang --version
	ld.lld --version
	llvm-objcopy --version

# ACT4 runs Sail to generate expected values, then embeds them in a self-check ELF.
check-selection:
	@test -z "$(filter-out $(ACT_AVAILABLE_EXTENSIONS),$(ACT_EXTENSION_LIST))" || \
		{ echo "Unsupported ACT_EXTENSIONS: $(filter-out $(ACT_AVAILABLE_EXTENSIONS),$(ACT_EXTENSION_LIST)); available: $(ACT_AVAILABLE_EXTENSIONS)." >&2; exit 1; }
	@test -n "$(ACT_CASES)" || { echo "No ACT4 tests selected." >&2; exit 1; }
	@test -z "$(filter-out $(basename $(notdir $(ACT_SELECTED_SOURCES))),$(ACT_TESTS))" || \
		{ echo "Unknown ACT_TESTS: $(filter-out $(basename $(notdir $(ACT_SELECTED_SOURCES))),$(ACT_TESTS))." >&2; exit 1; }

$(ACT_GENERATED_SOURCES): Makefile | check-source
	testgen External/testplans -o "$(BUILD_ROOT)/Generated" --extensions $(notdir $(@D)) --jobs $(JOBS)
	@test -s "$@"
	touch "$@"

# Keep all upstream coverpoints; change only the number of testcases per ELF.
Build/Generated/F.mk: Makefile External/testplans/F.csv | check-source
	@test -x "$(VIRTUAL_ENV)/bin/python3" || { echo "Run make test-setup-riscv-arch-test from Processor/Src first." >&2; exit 1; }
	"$(VIRTUAL_ENV)/bin/python3" -c 'from pathlib import Path; import testgen.generate.unpriv as gen; gen.TESTCASES_PER_FILE = 250; gen.generate_unpriv_extension_tests(32, False, "F", Path("External/testplans"), Path("Build/Generated"))'
	@printf 'ACT_FP_SOURCES := %s\n' "$$(echo Build/Generated/rv32i/F/*.S)" > "$@.tmp"
	mv "$@.tmp" "$@"

# Generate the selected optional extensions without duplicating configuration.
# Preserve unchanged timestamps so ACT4 can reuse its build and Sail results.
config:
	mkdir -p "$(BUILD_ROOT)/Config"
	@for file in rsd-rv32i.yaml sail.json rvmodel_macros.h; do \
		cp "$$file" "$(BUILD_ROOT)/Config/$$file.tmp" || exit 1; \
		if test -n "$(filter F,$(ACT_EXTENSION_LIST))"; then \
			case "$$file" in \
				rsd-rv32i.yaml) sed '/name: Zicsr,/a\  - { name: F, version: "= 2.2.0" }' "$$file" > "$(BUILD_ROOT)/Config/$$file.tmp" && \
					printf '\n  MUTABLE_MISA_F: false\n  HW_MSTATUS_FS_DIRTY_UPDATE: precise\n  MSTATUS_FS_LEGAL_VALUES: [0, 1, 2, 3]\n' >> "$(BUILD_ROOT)/Config/$$file.tmp" || exit 1 ;; \
				sail.json) sed -e 's/"fs_legal_states": "ExtContext_Off"/"fs_legal_states": "ExtContext_FourState"/' \
					-e 's/"F": {"supported": false, "mutable_misa": true,/"F": {"supported": true, "mutable_misa": false,/' "$$file" > "$(BUILD_ROOT)/Config/$$file.tmp" || exit 1 ;; \
			esac; \
		fi; \
		for extension in $(filter Zba Zicond,$(ACT_EXTENSION_LIST)); do \
			case "$$file" in \
				rsd-rv32i.yaml) sed -i "/name: Zicsr,/a\\  - { name: $$extension, version: \"= 1.0.0\" }" "$(BUILD_ROOT)/Config/$$file.tmp" ;; \
				sail.json) sed -i "s/\"$$extension\": {\"supported\": false}/\"$$extension\": {\"supported\": true}/" "$(BUILD_ROOT)/Config/$$file.tmp" ;; \
			esac || exit 1; \
		done; \
		if cmp -s "$(BUILD_ROOT)/Config/$$file.tmp" "$(BUILD_ROOT)/Config/$$file"; then \
			rm "$(BUILD_ROOT)/Config/$$file.tmp"; \
		else mv "$(BUILD_ROOT)/Config/$$file.tmp" "$(BUILD_ROOT)/Config/$$file"; fi || exit 1; \
	done

build: check-source check-selection check config $(filter Build/Generated/%,$(ACT_SELECTED_SOURCES))
# Replace only the staged sources, so narrowing the filter cannot include old tests.
	rm -rf "$(BUILD_ROOT)/Tests"
	@for source in $(ACT_SELECTED_SOURCES); do \
		relative=$${source#External/tests/}; relative=$${relative#Build/Generated/}; \
		mkdir -p "$(BUILD_ROOT)/Tests/$${relative%/*}" && \
		cp -p "$$source" "$(BUILD_ROOT)/Tests/$$relative" || exit 1; \
	done
	cp -a External/tests/env "$(BUILD_ROOT)/Tests/"
	act test_config.yaml --test-dir "$(BUILD_ROOT)/Tests" --coverpoint-dir External/coverpoints \
		--workdir "$(BUILD_ROOT)/act" --extensions "$(ACT_EXTENSIONS)" --fast --jobs $(JOBS)
	$(MAKE) $(addprefix $(CASE_ROOT)/,$(addsuffix /code.hex,$(ACT_CASES))) \
		$(addprefix $(CASE_ROOT)/,$(addsuffix /cfg.xml,$(ACT_CASES))) \
		$(addprefix $(CASE_ROOT)/,$(addsuffix /serial.ref.txt,$(ACT_CASES)))

$(CASE_ROOT)/%/code.hex: $(ACT_ELF_ROOT)/%.elf Makefile
	mkdir -p "$(@D)"
	llvm-objcopy -O binary --only-section=.text.reset --only-section=.text.init \
		--only-section=.text.rvmodel \
		--gap-fill=0 --pad-to=0x10000 "$<" "$(@D)/rom.bin"
	@test "$$(stat -c %s "$(@D)/rom.bin")" -eq 61440
	llvm-objcopy -O binary --only-section=.data --only-section=.text.rvtest \
		--gap-fill=0 --pad-to=0x80040000 "$<" "$(@D)/ram.bin"
	@test "$$(stat -c %s "$(@D)/ram.bin")" -eq 262144
	dd if=/dev/zero of="$(@D)/code.bin" bs=4096 count=1 status=none
	cat "$(@D)/rom.bin" "$(@D)/ram.bin" >> "$(@D)/code.bin"
	$(PYTHON) ../../../../Tools/TestDriver/BinaryToHex.py "$(@D)/code.bin" "$@.tmp"
	mv "$@.tmp" "$@"

$(CASE_ROOT)/%/cfg.xml: cfg.xml Makefile
	mkdir -p "$(@D)"
# FP and SC have many operand/result checks; exception tests invoke handlers.
	@case "$*" in \
		rv32i/F/*|rv32i/Zalrsc/Zalrsc-sc.w-*) sed 's/<MaxTestInstructions>20000/<MaxTestInstructions>50000/' "$<" > "$@" ;; \
		priv/Exceptions*/*) sed 's/<MaxTestInstructions>20000/<MaxTestInstructions>100000/' "$<" > "$@" ;; \
		*) cp "$<" "$@" ;; \
	esac

# Match the complete upstream self-check pass message, including its filename.
$(CASE_ROOT)/%/serial.ref.txt: Makefile
	mkdir -p "$(@D)"
	printf '\nRVCP-SUMMARY: TEST PASSED - Test File "%s.S"\n\n' "$(notdir $*)" > "$@"

# Finish the build before starting cases; inherit make's jobserver for execution.
run: build
	rm -f "$(BUILD_ROOT)/summary.log"
	$(MAKE) --output-sync=target run-cases

# Catch test failures so make runs every case without requiring -k.
# Each worker writes its own result, keeping parallel output files independent.
$(ACT_RESULTS): $(CASE_ROOT)/%/result.log:
	@cd ../../..; \
	test_dir="Verification/TestCode/riscv-arch-test/Build/Cases/$*"; \
	rm -f "$$test_dir/result.log" || exit 1; \
	if $(TEST_DRIVER) "$$test_dir"; then \
		printf 'PASS %s\n' "$*" > "$$test_dir/result.log"; \
	else \
		status=$$?; \
		printf 'FAIL %s (exit %s)\n' "$*" "$$status" > "$$test_dir/result.log"; \
	fi

# Aggregate in test-name order only after all workers have finished.
run-cases: $(ACT_RESULTS)
	@summary="$(BUILD_ROOT)/summary.log"; \
	printf 'ACT4 results:\n' > "$$summary"; \
	passed=0; failed=0; \
	for result in $(ACT_RESULTS); do \
		IFS= read -r line < "$$result" || exit 1; \
		printf '%s\n' "$$line" >> "$$summary"; \
		if test "$${line%% *}" = PASS; then \
			passed=$$((passed + 1)); \
		else \
			failed=$$((failed + 1)); \
		fi; \
	done; \
	printf '%s passed, %s failed\n' "$$passed" "$$failed" >> "$$summary"; \
	printf '\n'; cat "$$summary"; \
	test "$$failed" -eq 0

clean:
	rm -rf "$(BUILD_ROOT)/Config" "$(BUILD_ROOT)/Generated" "$(BUILD_ROOT)/Tests" "$(BUILD_ROOT)/act" "$(CASE_ROOT)" "$(BUILD_ROOT)/summary.log"
