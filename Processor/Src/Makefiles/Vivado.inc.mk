
# Specify the target Zynq board.
# Supported Zynq boards: Zedboard
TARGET_BOARD = Zedboard



# -------------------------------

# For Vivado
VIVADO_BOARD_PROJECT = rsd
VIVADO_POST_SYNTHESIS_PROJECT = rsd_post_synthesis

VIVADO_PROJECT_ROOT = ../Project/Vivado/TargetBoards/$(TARGET_BOARD)
VIVADO_PROJECT_FILE = $(VIVADO_BOARD_PROJECT_ROOT)/rsd.xpr
VIVADO_BOARD_PROJECT_ROOT = $(VIVADO_PROJECT_ROOT)/$(VIVADO_BOARD_PROJECT)
VIVADO_POST_SYNTHESIS_PROJECT_ROOT = $(VIVADO_PROJECT_ROOT)/$(VIVADO_POST_SYNTHESIS_PROJECT)
VIVADO_BOARD_PROJECT_IMPL = $(VIVADO_BOARD_PROJECT_ROOT)/$(VIVADO_BOARD_PROJECT).runs/impl_1
VIVADO_BOARD_PROJECT_SDK = $(VIVADO_BOARD_PROJECT_ROOT)/$(VIVADO_BOARD_PROJECT).sdk
VIVADO_XSA_FILE = $(VIVADO_BOARD_PROJECT_ROOT)/design_1_wrapper.xsa
VIVADO_BIT_FILE = $(VIVADO_BOARD_PROJECT_IMPL)/design_1_wrapper.bit
VIVADO_FSBL_FILE = $(VIVADO_BOARD_PROJECT_SDK)/fsbl/Release/fsbl.elf

# Linux(ARM)用

# ターゲットボードを追加したらここも追加
ifeq ($(TARGET_BOARD),Zedboard)
	UBOOT_CONFIG = zynq_zed_config
	DEVICETREE_CONFIG = zynq-zed
else
	ifeq ($(TARGET_BOARD),ZC706)
		UBOOT_CONFIG = zynq_zc706_config
		DEVICETREE_CONFIG = zynq-zc706
	else
		UBOOT_CONFIG = none
		DEVICETREE_CONFIG = none
	endif
endif

KERNEL_CONFIG = xilinx_zynq_defconfig
ARM_CROSSCOMPILE = arm-linux-gnueabihf-

ARM_LINUX_ROOT = $(RSD_ARM_LINUX)
KERNEL_ROOT = $(RSD_ARM_LINUX)/linux-xlnx
UBOOT_ROOT = $(RSD_ARM_LINUX)/u-boot-xlnx
DTC_ROOT = $(RSD_ARM_LINUX)/dtc
INITRD = $(RSD_ARM_LINUX)/arm_ramdisk.image.gz
ARM_LINUX_BOOT = $(ARM_LINUX_ROOT)/boot

ARM_LINUX_SRC_ROOT = $(RSD_ROOT)/Processor/Project/Vivado/ARM_Linux
KERNEL_SRC_ROOT = $(ARM_LINUX_SRC_ROOT)/linux-xlnx
UBOOT_SRC_ROOT = $(ARM_LINUX_SRC_ROOT)/u-boot-xlnx
BIF_FILE = $(ARM_LINUX_SRC_ROOT)/boot.bif
UINITRD_FILE = $(ARM_LINUX_BOOT)/uramdisk.image.gz
BIT_FILE = $(ARM_LINUX_BOOT)/boot.bin
DEVICETREE_FILE = $(ARM_LINUX_BOOT)/devicetree.dtb
FSBL_FILE = $(ARM_LINUX_BOOT)/fsbl.elf
UBOOT_FILE = $(ARM_LINUX_BOOT)/u-boot.elf
UKERNEL_FILE = $(ARM_LINUX_BOOT)/uImage
ROOTFS_FILE = $(ARM_LINUX_ROOT)/ROOTFS.tar.gz

KERNEL_BRANCH = v2019.2.01
UBOOT_BRANCH = v2019.2
KERNEL_TAG = xilinx-v2019.2.01
UBOOT_TAG = xilinx-v2019.2

# -------------------------------
# Vivado : Make RSD project, run synthesis and run implementation for TARGET_BOARD.
#

# vivadoプロジェクトを作成して開く．すでに作成されている場合は開くのみ．
vivado: $(VIVADO_PROJECT_FILE)
	$(RSD_VIVADO_BIN)/vivado $(VIVADO_PROJECT_FILE) &

# vivadoプロジェクトの削除
vivado-clean:
	rm -f -r $(VIVADO_BOARD_PROJECT_ROOT)
	rm -f vivado*.jou
	rm -f vivado*.log
	rm -f vivado*.zip
	rm -f vivado*.str


# -------------------------------
# ARM-Linux : Make fsbl, initrd, u-boot, kernel, device-tree and boot.bin for TARGET_BOARD.
#

xilinx-arm-linux: $(ARM_LINUX_BOOT) $(FSBL_FILE) $(BIT_FILE)
	$(MAKE) xilinx-arm-linux-u-boot
	$(MAKE) xilinx-arm-linux-kernel
	$(MAKE) xilinx-arm-linux-device-tree
	$(MAKE) xilinx-arm-linux-bootbin
	$(MAKE) xilinx-arm-linux-download-rootfs

xilinx-arm-linux-clean:
	$(MAKE) xilinx-arm-linux-kernel-clean
	$(MAKE) xilinx-arm-linux-u-boot-clean
	$(MAKE) xilinx-arm-linux-initrd-clean
	$(MAKE) xilinx-arm-linux-bootbin-clean
	$(MAKE) xilinx-arm-linux-rootfs-clean

# Do NOT use this command.
xilinx-arm-linux-clone-all: $(ARM_LINUX_ROOT) $(KERNEL_ROOT) $(UBOOT_ROOT) $(DTC_ROOT)/dtc $(INITRD) $(ARM_LINUX_BOOT)
	@echo "All repos have been already cloned."

$(ARM_LINUX_ROOT):
	mkdir $(ARM_LINUX_ROOT)

$(KERNEL_ROOT):
	$(MAKE) xilinx-arm-linux-kernel-fetch; \
	cd $(KERNEL_ROOT); \
	patch -p1 < $(KERNEL_SRC_ROOT)/linux-xlnx.rsd.diff || $(MAKE) xilinx-arm-linux-kernel-clean

# Do NOT use this command.
xilinx-arm-linux-kernel-fetch:
	git clone https://github.com/Xilinx/linux-xlnx.git $(KERNEL_ROOT)
	@cd $(KERNEL_ROOT); \
	git checkout -b $(KERNEL_BRANCH) refs/tags/$(KERNEL_TAG)

# Do NOT use this command.
xilinx-arm-linux-kernel-clean:
	rm -f -r $(KERNEL_ROOT)

$(UBOOT_ROOT):
	$(MAKE) xilinx-arm-linux-u-boot-fetch; \
	cd $(UBOOT_ROOT); \
	patch -p1 < $(UBOOT_SRC_ROOT)/u-boot-xlnx.rsd.diff || $(MAKE) xilinx-arm-linux-u-boot-clean

# Do NOT use this command.
xilinx-arm-linux-u-boot-fetch:
	git clone https://github.com/Xilinx/u-boot-xlnx.git $(UBOOT_ROOT)
	@cd $(UBOOT_ROOT); \
	git checkout -b $(UBOOT_BRANCH) refs/tags/$(UBOOT_TAG)

# Do NOT use this command.
xilinx-arm-linux-u-boot-clean:
	rm -f -r $(UBOOT_ROOT)

$(DTC_ROOT)/dtc:
	$(MAKE) xilinx-arm-linux-dtc || $(MAKE) xilinx-arm-linux-dtc-clean

# Do NOT use this command.
xilinx-arm-linux-dtc:
	git clone https://git.kernel.org/pub/scm/utils/dtc/dtc.git $(DTC_ROOT)
	@cd $(DTC_ROOT); \
	make CC=gcc CXX=g++

# Do NOT use this command.
xilinx-arm-linux-dtc-clean:
	rm -f -r $(DTC_ROOT)

$(INITRD):
	wget -N -P $(ARM_LINUX_ROOT) http://www.wiki.xilinx.com/file/view/arm_ramdisk.image.gz/419243558/arm_ramdisk.image.gz

$(ARM_LINUX_BOOT):
	mkdir $(ARM_LINUX_BOOT)

# Do NOT use this command.
xilinx-arm-linux-all:
	$(MAKE) xilinx-arm-linux-fsbl
	$(MAKE) xilinx-arm-linux-u-boot
	$(MAKE) xilinx-arm-linux-initrd
	$(MAKE) xilinx-arm-linux-kernel
	$(MAKE) xilinx-arm-linux-bitstream
	$(MAKE) xilinx-arm-linux-bootbin
	$(MAKE) xilinx-arm-linux-download-rootfs

$(FSBL_FILE): $(VIVADO_FSBL_FILE)
	cp $(VIVADO_FSBL_FILE) $(ARM_LINUX_BOOT)/fsbl.elf

$(VIVADO_FSBL_FILE): $(VIVADO_XSA_FILE)
	xsct $(VIVADO_PROJECT_ROOT)/scripts/synthesis/make_fsbl.tcl

$(VIVADO_XSA_FILE): $(VIVADO_BIT_FILE)
#	$(RSD_VIVADO_BIN)/vivado -mode batch -source $(VIVADO_PROJECT_ROOT)/export_xsa.tcl
#	cp $(VIVADO_BOARD_PROJECT_IMPL)/design_1_wrapper.sysdef $(VIVADO_XSA_FILE)
#	@echo "(Re-)build hdf using Vivado!"
#	exit 1

$(UBOOT_FILE): $(UBOOT_ROOT)
	$(MAKE) xilinx-arm-linux-u-boot

# Do NOT use this command.
xilinx-arm-linux-u-boot: $(UBOOT_ROOT)
	cd $(UBOOT_ROOT); \
	make $(UBOOT_CONFIG) CROSS_COMPILE=$(ARM_CROSSCOMPILE) -j4; \
	make CROSS_COMPILE=$(ARM_CROSSCOMPILE) -j4; \
	cp $(UBOOT_ROOT)/u-boot $(ARM_LINUX_BOOT)/u-boot.elf

$(UINITRD_FILE): $(UBOOT_FILE) $(INITRD)
	$(MAKE) xilinx-arm-linux-initrd

# Do NOT use this command.
xilinx-arm-linux-initrd: $(INITRD)
	$(UBOOT_ROOT)/tools/mkimage -A arm -T ramdisk -C gzip -d $(INITRD) $(ARM_LINUX_BOOT)/uramdisk.image.gz

# Do NOT use this command.
xilinx-arm-linux-initrd-clean:
	rm -f $(ARM_LINUX_BOOT)/uramdisk.image.gz
	rm -f $(INITRD)

$(UKERNEL_FILE):
	$(MAKE) xilinx-arm-linux-kernel

# Do NOT use this command.
xilinx-arm-linux-kernel: $(KERNEL_ROOT)
	cd $(KERNEL_ROOT); \
	make ARCH=arm CROSS_COMPILE=$(ARM_CROSSCOMPILE) $(KERNEL_CONFIG) -j4; \
	make ARCH=arm CROSS_COMPILE=$(ARM_CROSSCOMPILE) UIMAGE_LOADADDR=0x8000 uImage -j4
	cp $(KERNEL_ROOT)/arch/arm/boot/uImage $(ARM_LINUX_BOOT)
	cp $(ARM_LINUX_BOOT)/uImage $(ARM_LINUX_BOOT)/uImage.bin

$(DEVICETREE_FILE): $(UKERNEL_FILE)
	$(MAKE) xilinx-arm-linux-device-tree

# Do NOT use this command.
xilinx-arm-linux-device-tree: $(UKERNEL_FILE)
	cd $(KERNEL_ROOT); \
	make ARCH=arm CROSS_COMPILE=$(ARM_CROSSCOMPILE) $(DEVICETREE_CONFIG).dtb
	cp $(KERNEL_ROOT)/arch/arm/boot/dts/zynq-zed.dtb $(ARM_LINUX_BOOT)/devicetree.dtb

$(BIT_FILE): $(VIVADO_BIT_FILE)
	cp $(VIVADO_BIT_FILE) $(ARM_LINUX_BOOT)/boot.bit

$(VIVADO_BIT_FILE): $(VIVADO_PROJECT_FILE)
	$(RSD_VIVADO_BIN)/vivado -mode batch -source $(VIVADO_PROJECT_ROOT)/scripts/synthesis/generate_bitstream.tcl

# Do NOT use this command.
xilinx-arm-linux-bootbin:
	cd $(ARM_LINUX_BOOT); \
	bootgen -w -image $(BIF_FILE) -o i boot.bin

# Do NOT use this command.
xilinx-arm-linux-bootbin-clean:
	rm -r -f $(ARM_LINUX_BOOT)

# This command downloads the rootfs for ARM Linux (ROOTFS.tar.gz) from Google Drive.
# This long command is required because Google Drive requires two steps below to download a large file:
# 1. Get a code for downloading the file,
# 2. Download the file using the code.
# If ROOTFS.tar.gz is not downloaded successfully, please download it from the following link using a web browser.
# https://drive.google.com/open?id=1mmk7WDH1OZPpwxO0jdu9cWamLYID__2B
$(ROOTFS_FILE):
	wget --load-cookies /tmp/cookie "https://docs.google.com/uc?export=download&confirm=$(shell wget --quiet --save-cookies /tmp/cookie --keep-session-cookies --no-check-certificate 'https://docs.google.com/uc?export=download&id=1mmk7WDH1OZPpwxO0jdu9cWamLYID__2B' -O- | sed -rn 's/.*confirm=([0-9A-Za-z_]+).*/\1\n/p')&id=1mmk7WDH1OZPpwxO0jdu9cWamLYID__2B" -O $(ROOTFS_FILE)

# Do NOT use this command.
xilinx-arm-linux-download-rootfs: $(ROOTFS_FILE)

# Do NOT use this command.
xilinx-arm-linux-rootfs-clean:
	rm -f $(ROOTFS_FILE)
