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
# Add extensions here as their RSD configuration and adapters are validated.
ACT_AVAILABLE_EXTENSIONS := I
ACT_EXTENSIONS ?= $(ACT_AVAILABLE_EXTENSIONS)
comma := ,
ACT_EXTENSION_LIST := $(subst $(comma), ,$(ACT_EXTENSIONS))
ACT_SOURCES := $(sort $(foreach extension,$(ACT_EXTENSION_LIST),$(wildcard External/tests/rv32i/$(extension)/*.S)))
ACT_TESTS ?= $(basename $(notdir $(ACT_SOURCES)))
ACT_SELECTED_SOURCES := $(foreach test,$(ACT_TESTS),$(filter %/$(test).S,$(ACT_SOURCES)))
ACT_CASES := $(patsubst External/tests/%.S,%,$(ACT_SELECTED_SOURCES))
TEST_DRIVER ?= $(PYTHON) ../Tools/TestDriver/RunTest.py -o --simulator=verilator

# Keep environments, downloaded tools and caches beside this test suite.
BUILD_ROOT := $(CURDIR)/Build
CASE_ROOT := $(BUILD_ROOT)/Cases
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
.PHONY: fetch setup check check-source check-platform check-selection build run clean

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

build: check-source check-selection check
# Replace only the staged sources, so narrowing the filter cannot include old tests.
	rm -rf "$(BUILD_ROOT)/Tests/rv32i"
	@for source in $(ACT_SELECTED_SOURCES); do \
		relative=$${source#External/tests/}; \
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

$(CASE_ROOT)/%/cfg.xml: cfg.xml
	mkdir -p "$(@D)"
	cp "$<" "$@"

# Match the complete upstream self-check pass message, including its filename.
$(CASE_ROOT)/%/serial.ref.txt: Makefile
	mkdir -p "$(@D)"
	printf '\nRVCP-SUMMARY: TEST PASSED - Test File "%s.S"\n\n' "$(notdir $*)" > "$@"

# Run each case from Src for simulator-relative paths, with a fresh model process.
# Preserve every result and report failure after all selected cases have run.
run: build
	@cd ../../..; \
	summary="Verification/TestCode/riscv-arch-test/Build/summary.log"; \
	printf 'ACT4 results:\n' > "$$summary"; \
	passed=0; failed=0; \
	for test in $(ACT_CASES); do \
		if $(TEST_DRIVER) "Verification/TestCode/riscv-arch-test/Build/Cases/$$test"; then \
			printf 'PASS %s\n' "$$test" >> "$$summary"; \
			passed=$$((passed + 1)); \
		else \
			status=$$?; \
			printf 'FAIL %s (exit %s)\n' "$$test" "$$status" >> "$$summary"; \
			failed=$$((failed + 1)); \
		fi; \
	done; \
	printf '%s passed, %s failed\n' "$$passed" "$$failed" >> "$$summary"; \
	printf '\n'; cat "$$summary"; \
	test "$$failed" -eq 0

clean:
	rm -rf "$(BUILD_ROOT)/Tests" "$(BUILD_ROOT)/act" "$(CASE_ROOT)" "$(BUILD_ROOT)/summary.log"
