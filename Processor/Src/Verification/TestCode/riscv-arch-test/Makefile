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

# Keep environments, downloaded tools and caches beside this test suite.
BUILD_ROOT := $(CURDIR)/Build
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

.DEFAULT_GOAL := check
.PHONY: fetch setup check check-source check-platform

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
