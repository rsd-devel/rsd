# クロスコンパイラ環境の設定

HOST_TYPE = $(shell uname)

# Platform: linux
ifneq (,$(findstring Linux,$(HOST_TYPE)))
RSD_GCC_NATIVE = $(RSD_GCC_PATH)
RSD_ENV_NATIVE = $(RSD_ENV)
RSD_ROOT_NATIVE = $(RSD_ROOT)
endif

# Platform: cygwin
ifneq (,$(findstring CYGWIN,$(HOST_TYPE)))
RSD_GCC_NATIVE = $(shell cygpath -u "$$RSD_GCC_PATH")
RSD_ENV_NATIVE = $(shell cygpath -u "$$RSD_ENV")
RSD_ROOT_NATIVE = $(shell cygpath -u "$$RSD_ROOT")
endif

RSD_GCC_VERSION = $(shell ls ${RSD_GCC_PATH} | grep -E "^${RSD_GCC_PREFIX}\gcc\-[0-9\.]+" | sed -r 's/([^ ]+)-gcc-([0-9\.]+)/\2/')
RSD_GCC_NAME = $(shell echo ${RSD_GCC_PREFIX} | sed -e 's/-$$//')

# Check required environment variables
ifndef RSD_GCC_PATH
$(error RSD_GCC_PATH is not set.)
endif
ifndef RSD_GCC_PREFIX
$(error RSD_GCC_PREFIX is not set.)
endif
ifndef RSD_GCC_VERSION
$(error RSD_GCC_PATH and/or RSD_GCC_PREFIX have a wront value.)
endif
ifndef RSD_GCC_NAME
$(error RSD_GCC_PREFIX has a wront value.)
endif

RSD_TEST_CODE_ROOT = $(RSD_ROOT_NATIVE)/Processor/Src/Verification/TestCode
RSD_TOOL_ROOT      = $(RSD_ROOT_NATIVE)/Processor/Tools
RSD_TEST_TOOL_ROOT = $(RSD_ROOT_NATIVE)/Processor/Tools/TestDriver


#
# コンパイラの設定
#
CC = $(RSD_GCC_NATIVE)/$(RSD_GCC_PREFIX)gcc
AS = $(RSD_GCC_NATIVE)/$(RSD_GCC_PREFIX)as
LD = $(RSD_GCC_NATIVE)/$(RSD_GCC_PREFIX)ld
OBJDUMP = $(RSD_GCC_NATIVE)/$(RSD_GCC_PREFIX)objdump
OBJCOPY = $(RSD_GCC_NATIVE)/$(RSD_GCC_PREFIX)objcopy
STRIP = $(RSD_GCC_NATIVE)/$(RSD_GCC_PREFIX)strip


#
# コンパイルオプションとリンクオプション
#
CFLAGS = \
	-g \
	-O3 \
	-fno-stack-protector \
	-fno-zero-initialized-in-bss \
	-ffreestanding \
	-fno-builtin \
	-nostdlib \
	-nodefaultlibs \
	-nostartfiles \
	-mstrict-align \
	-march=rv32im \

LDFLAGS= \
	-static \

LIBC =
LIBGCC = \
	-L$(RSD_GCC_NATIVE)/../lib/gcc/${RSD_GCC_NAME}/$(RSD_GCC_VERSION) \
	-lgcc \
	-lgcov \
	-L$(RSD_GCC_NATIVE)/../${RSD_GCC_NAME}/lib \
	-lm



# --------
# RSD 用スタートアップルーチンとリンカスクリプト
#
CRTOBJ = $(RSD_TEST_CODE_ROOT)/rsd-crt.o
CRTASM = $(RSD_TEST_CODE_ROOT)/rsd-crt.s
LDOBJ = $(RSD_TEST_CODE_ROOT)/rsd-loader.o
LDSRC = $(RSD_TEST_CODE_ROOT)/rsd-loader.c
LDSCRIPT = $(RSD_TEST_CODE_ROOT)/rsd-ld.script

# ROM の先頭 0x1000 までに結合するためのダミーの ROM
# 中身が 0 のバイナリを作成する
DUMMY_ROM = $(RSD_TEST_CODE_ROOT)/dummy_rom.bin

# スタートアップルーチンのコンパイル
$(CRTOBJ): $(CRTASM) $(DUMMY_ROM) $(RSD_TEST_CODE_ROOT)/Asm/rsd-asm-macros.h
	$(CC) $(CFLAGS) -x assembler-with-cpp -o $@ -c $<

$(LDOBJ): $(LDSRC)
	$(CC) $(CFLAGS) -o $@ -c $<


$(DUMMY_ROM):
	head -c $(ROM_PADDING_SIZE) /dev/zero > $(DUMMY_ROM)

# --------
# テストコードのバイナリ設定

# 生成するバイナリのアドレス
# RAM は ローダでROMから必要なデータをコピーしたり初期化したりするので関係ない
ROM_PADDING_SIZE = 4096 # 0x1000
ROM_START_ADDR = 0x00001000
ROM_END_ADDR   = 0x00010000

ROM_SIZE   = 65536      # 0x1000 + (0x10000 - 0x1000) = 0x10000

# BIN_SIZE は ROM+CODE の合計サイズ
BIN_SIZE   = 0x10000

# .text* と .rodata* ，.bss，.dataなどを ROM として取り出すコマンド
# （.text* は，名前が .text から始まるセクションすべて）
# 詳細は ../../rsd-ld.script を参照
ROM_COPY = $(OBJCOPY) \
		-O binary --strip-all --strip-debug \
		--only-section .text* \
		--only-section .rodata* \
		--only-section .srodata* \
		--only-section .eh_frame* \
		--only-section .bss* \
		--only-section .data* \
		--only-section .sbss* \
		--only-section .sdata* \
		--set-start=$(ROM_START_ADDR) \
		--pad-to=$(ROM_END_ADDR) \


# --------
# テストコード生成ツール
#

# バイナリファイルを、RSDのシミュレーションで使える形式のhexに変換
BIN_TO_HEX = \
	python3 $(RSD_TEST_TOOL_ROOT)/BinaryToHex.py

HEX_TO_IHEX = \
	python3 $(RSD_TOOL_ROOT)/Hex2IHex/hex2ihex.py


# --------
# このファイルをインクルードする Makefile 内でデフォルトターゲットを
# 指定するためにデフォルトターゲットをリセット
.DEFAULT_GOAL =

