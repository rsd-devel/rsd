#
# 下位にあるディレクトリに対して make を行う
#


# 受付可能なサブコマンド
TARGETS = all clean

.DEFAULT_GOAL =	# デフォルトターゲットを無効化しておく

# 子 make が行われるディレクトリ
SRC_DIRS = \
	Fibonacci \
	HelloWorld \
	PerformanceCounter \
	Exception \
	DCache \


# TARGETS の中のどれかに該当した場合，SRC_DIRS が依存元となる
$(TARGETS): $(SRC_DIRS)


# SRC_DIRS 内の各要素ごとに make を実行
# $(MAKE): 親 make の引数を子にそのまま伝える（-j 等が子にも伝わる）
# $(MAKECMDGOALS): 親 make のサブコマンド
$(SRC_DIRS):
	$(MAKE) -C $@ $(MAKECMDGOALS)


# $(SRC_DIRS) を PHONY で疑似ターゲットにしてしまうことで，
# タイムスタンプ等関係なく毎回実行されるようにする
.PHONY: $(TARGETS) $(SRC_DIRS)
