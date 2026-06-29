# Veryl 移行メモ

このファイルは、現在の Veryl 利用方針と、移行中に見つかったツール起因の注意点だけをまとめる。

## 過去の package/interface 限定方針

以下は module Veryl 化前の記録で、現在の方針ではない。

- Veryl 化の対象は package と interface だけにする。
- module 本体は SystemVerilog のまま使う。
- Verification 配下のテスト用 SV は対象外にする。
- Veryl 生成物は `target/rsd_pkg_if.sv` の bundle 1 ファイルにまとめる。
- `Veryl.toml` の `omit_project_prefix = true` で、package/interface 名にプロジェクト prefix が付かないようにする。
- 非 Verification の SV package/interface ソースは削除済み。Verilator には Veryl 生成 bundle を先に読ませる。

確認済みコマンド:

```sh
cd Processor/Src
make -f Makefile.verilator.mk build -j
```

## 生成 bundle まわり

`Processor/Src/Makefiles/CoreSources.inc.mk` では、SV package/interface の代わりに `target/rsd_pkg_if.sv` を `TYPES` の先頭へ入れる。

`Processor/Src/Makefile.verilator.mk` では、Verilator build 前に `veryl build --quiet` を実行し、生成 bundle に必要最小限の後処理を入れる。

後処理している理由:

- enum variant 名を既存 SV 側の参照に合わせるため。
- Verilator C++ 側から見える必要がある parameter/typedef に `/*verilator public*/` を戻すため。

## 既知の注意点

### interface constructor 引数

元 SV interface には `DebugIF debugIF(clk, rst);` のように constructor 引数を渡す形があった。

Veryl 生成 interface は SV の interface port list を出さないため、同じ形では instantiate できない。現在は module 側で `DebugIF debugIF();` のように引数なしで生成し、`debugIF.clk` / `debugIF.rst` / `rstStart` などを明示 assign している。

このため、interface 側を Veryl にする場合は、constructor 引数に依存した接続を module 側の明示配線へ寄せる必要がある。

### enum variant 名

Veryl の enum は、生成 SV では `PipelinePhase::PHASE_COMMIT` 相当の variant が `PipelinePhase_PHASE_COMMIT` のように enum 名付きで出力される。

確認した範囲:

- `veryl metadata --format json` の `[build]` 項目に enum variant prefix を省略する設定はない。
- 公式 build 設定の `omit_project_prefix` は module/interface/package 名の project prefix を省略する設定で、enum variant 名には効かない。
- `omit_enum_prefix` / `strip_enum_prefix` などの名前を試すと、Veryl 0.20.1-nightly は unknown field として拒否した。

したがって、現時点では TOML 設定で「機械的置換なしに、生成 SV の enum variant prefix を落として `a::b` を `b` として出力する」Veryl build option は見つかっていない。将来 Veryl 側に該当 option が追加された場合は、Makefile の enum 後処理を置き換える。

### PipelinePhase alias と Verilator internal error

Veryl 生成 bundle を Verilator に読ませると、`PipelinePhase` enum の public alias 付近で internal error が出た。

問題になった形:

```systemverilog
localparam PipelinePhase PHASE_COMMIT = PipelinePhase_PHASE_COMMIT;
```

既存 SV module 側は `PHASE_COMMIT` のような短い enumerator 名を参照している。一方、Veryl 生成 bundle は `PipelinePhase_PHASE_COMMIT` を実体として出し、短い名は localparam alias になる。この alias 周辺で Verilator が苦手な形になった。

現在の回避策:

- 生成 bundle 内の enum alias 対応を拾う。
- `PipelinePhase_PHASE_COMMIT` のような参照を `PHASE_COMMIT` へ寄せる。
- `localparam PHASE_COMMIT = PHASE_COMMIT;` になった自己 alias 行は削除する。

この回避策は `Processor/Src/Makefile.verilator.mk` の Veryl build 後処理に閉じ込めている。

### `verilator public` と Veryl attribute

Veryl には `#[sv("...")]` attribute があり、SV attribute `(* ... *)` を生成できる。

ただし、`#[sv("verilator public")]` は次のような生成になる。

```systemverilog
(* verilator public *)
localparam int unsigned X = 1;
```

手元の Verilator 4.228 では、この SV attribute 形式では package localparam が C++ ヘッダへ公開されなかった。元 SV と同じ次の metacomment 形式では公開された。

```systemverilog
localparam int X /*verilator public*/ = 1;
```

そのため、現在は Veryl attribute だけには置き換えず、生成 bundle 後処理で `/*verilator public*/` を必要箇所へ戻している。

### package function 内の packed array select

Veryl 生成 package 内 function で、次のような式に対して Verilator が internal error を出した。

```systemverilog
e.complexExReg[i].opId[0]
```

見えたエラーは `No VarRef or Const under ArraySel` 系で、package/interface 限定構成でも `VerilatorHelper` の型ユーティリティとして生成される箇所だった。

現在の回避策:

- `Processor/Src/SysDeps/Verilator/VerilatorHelper.veryl` で、`e.complexExReg[i]` / `e.fpExReg[i]` をいったん local 変数に受ける。
- その local 変数に対して `stageReg.opId[0]` / `stageReg.valid[0]` のように select する。

これで元 SV に近い段階的な参照になり、Verilator の internal error を避けている。

### combinational_loop false positive

以前の module まで Veryl 化する試行では、ReplayQueue や DCache の一部で Veryl 0.20.1-nightly の `combinational_loop` 検出に引っかかった。

これは元 SV 上の実回路ループではなく、解析器がレジスタ境界や RAM read の依存を保守的に同一組合せ経路として扱った false positive と判断している。

代表例:

```text
popEntry -> QueuePointer/RAM -> replayEntryOut -> flush* -> popEntry
```

現在の package/interface 限定方針では module 本体を Veryl 化しないため、この問題は build blocker ではない。ただし、将来 module の Veryl 化を再開する場合は、該当箇所を scalar 展開する、計算ブロックを分ける、または合成上敏感な RAM/queue を SV leaf として切り出す必要がある。

## 再確認ポイント

- Veryl の新しいバージョンで enum variant prefix を制御する build option が追加されていないか。
- Veryl が Verilator metacomment を直接出せるようになっていないか。
- Verilator 更新後に、`PipelinePhase` alias と package function の internal error 回避がまだ必要か。
- 別マクロ構成で build する場合、Veryl 化済み package/interface の展開前提が合っているか。

## module Veryl 化後の追加メモ

module も Veryl 生成物を使う方針へ更新したため、上の「package/interface 限定」「生成 bundle 後処理」は過去の方針になった。現在の Verilator build では `veryl build` 後に生成 SV を `perl` などで書き換えず、`Veryl.toml` の `sources` 配列を Makefile 側で読んで `target/veryl/*.sv` を明示順で Verilator に渡している。`rsd.f` は Veryl の生成確認には使うが、Verilator の入力順制御には使わない。

`-Wno-LATCH` は使わない。今回見つかった `NextPCStage` の latch warning は、分岐予測の探索フラグ、次 PC、次段レジスタの既定値を `always_comb` の先頭で明示初期化することで Veryl 側の記述として直した。

Veryl の directory target は、明示 `sources = [...]` だけだと現環境で出力先 directory 自体をファイルとして開こうとして失敗した。そのため暫定的に deprecated warning 付きの `source = "."` を残している。ただし Verilator へ渡す順序は `sources` 配列から作っているので、順序依存のある package/interface/module は TOML 側で管理している。

Veryl 生成の package localparam は、元 SV の `/*verilator public*/` metacomment と同じ形では C++ 側へ公開されなかった。生成物後処理で戻す方針はやめ、Verilator testbench に必要な固定パラメータは `SysDeps/Verilator/VerilatorHelper.h` 側の `constexpr` として持つことにした。これは現行 `RSD_SRC_CFG` 前提なので、別マクロ構成を有効にする場合は C++ 側定数との同期が必要になる。

Veryl の関数引数に unpacked array を渡す形は、Verilator の生成 C++ で配列と packed 値の型が噛み合わないことがあった。`PreDecodeStage` は中間配列型を明示し、`BypassController` / `BypassNetwork` は関数に配列を渡さずモジュール内配列を直接参照する形へ寄せた。

Veryl wrapper 越しに SV leaf を使う箇所はまだ残っている。具体的には RAM、DCache 本体、Memory/AXI/queue 系のリーフ実装で、Veryl 側から `$sv::*_SV` を instantiate している。このため該当 SV は削除していない。逆に、同名 `.veryl` があり現在の Verilator file list から外れた旧 module SV は削除した。

Veryl wrapper により Verilator の C++ 階層名が変わったため、`TestMain.cpp` の debug RAM 参照や main memory 参照には `body` 階層を追加した。また commit 後の register dump で必要な commit stage の PC/commit 情報は、C++ から内部 module 階層へ直接潜らず `DebugRegister` と `VerilatorHelper` 経由で読む形に寄せた。
