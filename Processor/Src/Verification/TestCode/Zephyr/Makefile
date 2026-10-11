# Fetch public Zephyr explicitly; ordinary builds never download dependencies.
ZEPHYR_URL = https://github.com/zephyrproject-rtos/zephyr.git
ZEPHYR_REVISION = 684c9e8f32e4373a21098559f748f06915f950c9
PYTHON ?= python3
CROSS_COMPILE ?= $(if $(RSD_GCC_PATH),$(RSD_GCC_PATH)/$(RSD_GCC_PREFIX),riscv64-unknown-elf-)
# Ubuntu's GCC has no built-in sysroot; avoid scanning host library directories.
SYSROOT_DIR ?= /usr/lib/picolibc/riscv64-unknown-elf
JOBS ?= $(shell nproc)
export ZEPHYR_BASE := $(CURDIR)/External/zephyr
export PIP_CACHE_DIR := $(CURDIR)/Build/cache/pip
VENV := $(CURDIR)/Build/venv
VENV_PYTHON := $(VENV)/bin/python3
PORT_FILES := $(wildcard boards/rsd/* soc/rsd/*)

.DEFAULT_GOAL := build
.PHONY: fetch setup check-source check build clean

fetch:
	@if test -e External/zephyr; then \
		$(MAKE) check-source; \
	else \
		git init -q External/zephyr && \
		git -C External/zephyr remote add origin $(ZEPHYR_URL) && \
		git -C External/zephyr fetch --depth=1 origin $(ZEPHYR_REVISION) && \
		git -C External/zephyr checkout --detach $(ZEPHYR_REVISION); \
	fi

check-source:
	@test -d External/zephyr/.git || { echo "Run make test-fetch-Zephyr from Processor/Src first." >&2; exit 1; }
	@test "$$(git -C External/zephyr rev-parse HEAD)" = "$(ZEPHYR_REVISION)" || { echo "Zephyr revision differs from ZEPHYR_REVISION in Makefile." >&2; exit 1; }
	@git -C External/zephyr diff --quiet HEAD || { echo "Zephyr External has local changes; preserve or revert them before building." >&2; exit 1; }

# Only Python packages used by this CMake build; no west, SDK or vendor modules.
setup: check-source
	$(PYTHON) -m venv "$(VENV)"
	"$(VENV_PYTHON)" -m pip install --disable-pip-version-check pyelftools PyYAML packaging jsonschema pykwalify
	$(MAKE) check

check: check-source
	@test -x "$(VENV_PYTHON)" || { echo "Run make test-setup-Zephyr from Processor/Src first." >&2; exit 1; }
	"$(VENV_PYTHON)" -m pip check
	"$(VENV_PYTHON)" -c 'import elftools, yaml, packaging, jsonschema, pykwalify'
	@for tool in cmake ninja gperf dtc "$(CROSS_COMPILE)gcc" "$(CROSS_COMPILE)objcopy"; do \
		command -v "$$tool" >/dev/null || { echo "Missing Zephyr build tool: $$tool" >&2; exit 1; }; \
	done

# The upstream sample and kernel use RSD's out-of-tree board/SoC unchanged.
# Zephyr 4.4 needs the module scanner's generated Kconfig includes. Passing
# ZEPHYR_BASE runs that scanner, which excludes Zephyr itself from the modules.
Build/HelloWorld/zephyr/zephyr.elf: Makefile $(PORT_FILES) | check
	cmake -S "$(ZEPHYR_BASE)/samples/hello_world" -B Build/HelloWorld -G Ninja \
		-DBOARD=rsd/rsd -DBOARD_ROOT="$(CURDIR)" -DSOC_ROOT="$(CURDIR)" \
		-DUSER_CACHE_DIR="$(CURDIR)/Build/cache" \
		-DZEPHYR_MODULES="$(ZEPHYR_BASE)" -DZEPHYR_TOOLCHAIN_VARIANT=cross-compile \
		-DSYSROOT_DIR="$(SYSROOT_DIR)" \
		-DCROSS_COMPILE="$(CROSS_COMPILE)" -DPython3_EXECUTABLE="$(VENV_PYTHON)" \
		-DTOOLCHAIN_HAS_NEWLIB=OFF -DTOOLCHAIN_HAS_PICOLIBC=OFF
	cmake --build Build/HelloWorld --parallel $(JOBS)

Build/HelloWorld/code.hex: Build/HelloWorld/zephyr/zephyr.elf Makefile ../../../../Tools/TestDriver/BinaryToHex.py
	$(CROSS_COMPILE)objdump -d "$<" > Build/HelloWorld/code.dump
# With XIP, initialized RAM data also has a ROM load address.
	$(CROSS_COMPILE)objcopy -O binary --gap-fill=0 --pad-to=0x10000 "$<" Build/HelloWorld/rom.bin
	@test "$$(stat -c %s Build/HelloWorld/rom.bin)" -eq 61440
	dd if=/dev/zero of=Build/HelloWorld/code.bin bs=4096 count=1 status=none
	cat Build/HelloWorld/rom.bin >> Build/HelloWorld/code.bin
	$(PYTHON) ../../../../Tools/TestDriver/BinaryToHex.py Build/HelloWorld/code.bin "$@.tmp"
	mv "$@.tmp" "$@"

Build/HelloWorld/cfg.xml: cfg.xml Makefile
	mkdir -p "$(@D)"
	cp "$<" "$@"

Build/HelloWorld/serial.ref.txt: Makefile
	mkdir -p "$(@D)"
	printf 'Hello World! rsd/rsd\n' > "$@"

build: Build/HelloWorld/code.hex Build/HelloWorld/cfg.xml Build/HelloWorld/serial.ref.txt

clean:
	rm -rf Build/HelloWorld
