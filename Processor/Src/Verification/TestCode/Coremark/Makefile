#
# 下位にあるディレクトリに対して make を行う
#

# 受付可能なサブコマンド
TARGETS = all clean

# RSD_ENV が定義されていれば，そこから追加でコピーを行う
ifdef RSD_ENV
COPIED_SRC_DIRS = \
	Coremark \
	Coremark_for_RV32I \
	Coremark_for_Synthesis \

COPY:
	cp $(RSD_ENV)/Tools/Testbench/Coremark ./ -r -a
	cp $(RSD_ENV)/Tools/Testbench/Coremark_for_RV32I ./ -r -a
	cp $(RSD_ENV)/Tools/Testbench/Coremark_for_Synthesis ./ -r -a
else
COPIED_SRC_DIRS =
COPY:
endif


.DEFAULT_GOAL =	# デフォルトターゲットを無効化しておく

# 子 make が行われるディレクトリ
SRC_DIRS = \
	$(COPIED_SRC_DIRS) \


# TARGETS の中のどれかに該当した場合，SRC_DIRS が依存元となる
$(TARGETS): COPY $(SRC_DIRS)

copy: COPY


# SRC_DIRS 内の各要素ごとに make を実行
# $(MAKE): 親 make の引数を子にそのまま伝える（-j 等が子にも伝わる）
# $(MAKECMDGOALS): 親 make のサブコマンド
$(SRC_DIRS):
	$(MAKE) -C $@ $(MAKECMDGOALS)


# $(SRC_DIRS) を PHONY で疑似ターゲットにしてしまうことで，
# タイムスタンプ等関係なく毎回実行されるようにする
.PHONY: $(TARGETS) $(SRC_DIRS) copy
