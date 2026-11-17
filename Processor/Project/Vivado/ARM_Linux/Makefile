# PS-side Linux for ZedBoard; Vivado/Vitis 2019.2 supplies bitstream and FSBL.
# fetch/build run in the dev container. bootbin runs with bootgen on the host;
# image then assembles the SD image in the same environment as build.
# From the repository root:
#   ./RunContainer.sh make platform/zynq/fetch
#   ./RunContainer.sh make platform/zynq/build
#   make platform/zynq/hardware/build RSD_VIVADO_BIN=/path/to/Vivado/2019.2/bin RSD_XSCT=/path/to/Vitis/2019.2/bin/xsct
#   make platform/zynq/bootbin/build RSD_VIVADO_BIN=/path/to/Vivado/2019.2/bin
#   ./RunContainer.sh make platform/zynq/image/build
# Output: Processor/Project/Vivado/ARM_Linux/Build/images/rsd-zedboard.img
# An SSH client key pair (rsd-zedboard_ed25519 and .pub) is generated beside the image
# on the first build and reused. Only the public key is installed in the image.
# Connect with ssh -i Processor/Project/Vivado/ARM_Linux/Build/images/rsd-zedboard_ed25519 root@<board-ip>.
# Keep the private key on the client. clean removes it along with Build.
# Optional initial settings: pass RSD_ROOTFS_OVERLAY=/absolute/path/to/settings
# to platform/zynq/build, then run platform/zynq/image/build as usual.
# For static IPv4, place etc/network/interfaces in that directory, e.g.:
#   auto lo
#   iface lo inet loopback
#   auto eth0
#   iface eth0 inet static
#       address 192.168.1.50
#       netmask 255.255.255.0
#       gateway 192.168.1.1
# Put DNS servers in etc/resolv.conf (e.g. nameserver 192.168.1.1).
# Paths must be visible inside the build environment. With no overlay, a fresh
# build uses DHCP. Buildroot retains overlaid files on incremental builds;
# removing an overlay or files from it requires clean, then build.
# Kernel/bootloader source or patch changes require clean, then build.
include ../../../Src/Makefiles/Environment.inc.mk
.DEFAULT_GOAL := build
.DELETE_ON_ERROR:

export RSD_ZYNQ_ROOT := $(CURDIR)
# Release tarballs must not inherit the enclosing RSD Git revision as their version.
export GIT_CEILING_DIRECTORIES := $(CURDIR)
RSD_BUILDROOT_VERSION := 2025.02.19
RSD_BUILDROOT_SHA256 := e5e58bff1da91f022f60cefdfe280140c08023cd0aeec1e5f6f9da0ea866d69c
RSD_BUILDROOT_ARCHIVE := External/buildroot-$(RSD_BUILDROOT_VERSION).tar.xz
RSD_BUILDROOT := $(CURDIR)/External/buildroot-$(RSD_BUILDROOT_VERSION)
RSD_ZYNQ_BUILD := $(CURDIR)/Build
RSD_ZYNQ_IMAGES := $(RSD_ZYNQ_BUILD)/images
RSD_ZYNQ_BOARD := $(abspath ../TargetBoards/Zedboard/rsd)
RSD_ZYNQ_BIT ?= $(RSD_ZYNQ_BOARD)/rsd.runs/impl_1/design_1_wrapper.bit
RSD_ZYNQ_FSBL ?= $(RSD_ZYNQ_BOARD)/rsd.sdk/fsbl/Release/fsbl.elf
RSD_BOOTGEN ?= $(if $(RSD_VIVADO_BIN),$(RSD_VIVADO_BIN)/bootgen,bootgen)
# Optional existing public key; otherwise generate/reuse a key pair in images.
export RSD_SSH_PUBLIC_KEY ?=
# Standard Buildroot overlay; keep machine-specific settings outside the sources.
export RSD_ROOTFS_OVERLAY ?=
export BR2_DL_DIR := $(CURDIR)/External/downloads
RSD_BUILDROOT_MAKE = $(MAKE) -C $(RSD_BUILDROOT) O=$(RSD_ZYNQ_BUILD)

.PHONY: fetch build bootbin image clean
fetch: $(RSD_BUILDROOT)/Makefile
	$(RSD_BUILDROOT_MAKE) BR2_DEFCONFIG=$(CURDIR)/buildroot.config defconfig
	$(RSD_BUILDROOT_MAKE) source

$(RSD_BUILDROOT_ARCHIVE):
	mkdir -p External
	curl --fail --location --retry 3 https://buildroot.org/downloads/$(notdir $@) -o $@.tmp
	echo '$(RSD_BUILDROOT_SHA256)  $@.tmp' | sha256sum -c -
	mv $@.tmp $@

$(RSD_BUILDROOT)/Makefile: $(RSD_BUILDROOT_ARCHIVE)
	echo '$(RSD_BUILDROOT_SHA256)  $<' | sha256sum -c -
	tar -xJf $< -C External
	touch $@

# Read the pinned settings each time. Keep using the same build environment;
# Buildroot host tools and intermediate files are not relocatable.
build:
	@case "$(RSD_ROOTFS_OVERLAY)" in ""|/*) ;; *) echo 'RSD_ROOTFS_OVERLAY must be an absolute directory path.' >&2; exit 1;; esac
	@test -z "$(RSD_ROOTFS_OVERLAY)" || test -d "$(RSD_ROOTFS_OVERLAY)" || { echo 'RSD_ROOTFS_OVERLAY directory does not exist.' >&2; exit 1; }
	@test -f $(RSD_BUILDROOT)/Makefile || { echo 'Run make platform/zynq/fetch first.' >&2; exit 1; }
	$(RSD_BUILDROOT_MAKE) BR2_DEFCONFIG=$(CURDIR)/buildroot.config defconfig
	$(RSD_BUILDROOT_MAKE)

# Keep proprietary tools out of the Linux/rootfs build. Never use a dummy FSBL
# or bitstream to produce an image which might be mistaken for a bootable one.
bootbin: $(RSD_ZYNQ_IMAGES)/boot.bin

$(RSD_ZYNQ_IMAGES)/boot.bin: $(RSD_ZYNQ_FSBL) $(RSD_ZYNQ_BIT) $(RSD_ZYNQ_IMAGES)/u-boot boot.bif
	test -s "$(RSD_ZYNQ_FSBL)" && test -s "$(RSD_ZYNQ_BIT)" && test -s $(RSD_ZYNQ_IMAGES)/u-boot
	cp "$(RSD_ZYNQ_FSBL)" $(RSD_ZYNQ_IMAGES)/fsbl.elf
	cp "$(RSD_ZYNQ_BIT)" $(RSD_ZYNQ_IMAGES)/boot.bit
	cd $(RSD_ZYNQ_IMAGES) && "$(RSD_BOOTGEN)" -arch zynq -w -image $(CURDIR)/boot.bif -o boot.bin

# Buildroot's host tools require the build environment (normally devcontainer).
# No mounting, loop device, root access or SD-card write is needed here.
image:
	test -s $(RSD_ZYNQ_IMAGES)/boot.bin && test -s $(RSD_ZYNQ_IMAGES)/rootfs.ext4
	@test ! $(RSD_ZYNQ_IMAGES)/u-boot -nt $(RSD_ZYNQ_IMAGES)/boot.bin || { echo "Rebuild platform/zynq/bootbin/build after U-Boot changes." >&2; exit 1; }
	PATH="$(RSD_ZYNQ_BUILD)/host/bin:$(RSD_ZYNQ_BUILD)/host/sbin:$$PATH" \
		BUILD_DIR=$(RSD_ZYNQ_BUILD)/build BINARIES_DIR=$(RSD_ZYNQ_IMAGES) BR2_CONFIG=$(RSD_ZYNQ_BUILD)/.config \
		bash $(RSD_BUILDROOT)/support/scripts/genimage.sh -c $(CURDIR)/genimage.cfg

clean:
	rm -rf $(RSD_ZYNQ_BUILD)
