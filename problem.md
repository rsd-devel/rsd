# Veryl 移行メモ

このファイルは、RSD の SystemVerilog から Veryl への移行で、まだ注意が必要な点だけをまとめる。履歴の羅列ではなく、現在の状態、意図的に残した SV leaf、既知の変換上の例外を確認するためのメモである。

## 現在の状態

- `Processor/Src` の公開モジュール/インターフェースは基本的に native Veryl 化済み。
- `include(inline)` と `embed (inline) sv` は残していない。
- `Decoder` は native Veryl 実装になっており、`Decoder_SV` leaf への参照は残していない。
- `FPIssueStage`、`FPRegisterReadStage`、`FPExecutionStage`、`FPRegisterWriteStage`、`MemoryTagAccessStage`、`ReplayQueue`、`Core`、`DCache` も native Veryl 化済み。
- 残っている `$sv::` 参照は、RAM/AXI/メモリキュー/DCacheArray の合成・メモリ推論に関わる leaf に限る。
- 手書き Veryl には `unsupported loop`、`TODO(translate)`、`unsupported jump` のマーカーは残っていない。
- `veryl check --quiet` と `veryl build --quiet` は通過済み。

確認に使った代表コマンド:

```sh
rg -n '\$sv|include\(inline\)|embed \(inline\) sv|Decoder_SV' Processor/Src -g '*.veryl'
rg -n 'unsupported loop|TODO\(translate\)|unsupported jump' Processor/Src -g '*.veryl'
veryl check --quiet
veryl build --quiet
```

## 意図的に残している SV leaf

以下は「未変換」ではなく、Veryl のトランスパイルで生成 SV の形が変わると合成・RAM 推論・ベンダ依存挙動に影響し得るため、native Veryl wrapper から SV leaf を呼ぶ形で残している。

| Veryl wrapper | SV leaf | 残している理由 |
| --- | --- | --- |
| `Processor/Src/Primitives/RAM.veryl` | `*_SV` RAM 群 | RAM 推論、ベンダ分岐、初期化関数、debug assert の形を保持するため |
| `Processor/Src/Memory/ControlQueue.veryl` | `ControlQueue_SV` | `syn_ramstyle = "select_ram"` 付き配列 RAM の推論形状を保持するため |
| `Processor/Src/Memory/MemoryReadReqQueue.veryl` | `MemoryReadReqQueue_SV` | 同上 |
| `Processor/Src/Memory/MemoryWriteDataQueue.veryl` | `MemoryWriteDataQueue_SV` | 同上 |
| `Processor/Src/Memory/Memory.veryl` | `Memory_SV` | メモリモデル/シミュレーション依存実装を保持するため |
| `Processor/Src/Memory/Axi4Memory.veryl` | `Axi4Memory_SV` | AXI メモリ実装の既存 SV 形状を保持するため |
| `Processor/Src/Memory/Axi4LiteMemory.veryl` | `Axi4LiteDualPortBlockRAM_SV` | AXI Lite RAM 実装の既存 SV 形状を保持するため |
| `Processor/Src/Memory/Axi4LiteControlRegister.veryl` | `Axi4LitePlToPsControlRegister_SV`, `Axi4LitePsToPlControlRegister_SV` | AXI Lite control register 実装の既存 SV 形状を保持するため |
| `Processor/Src/Cache/DCache.veryl` | `DCacheArray_SV` | `BlockTrueDualPortRAM` 群、Synplify/Vivado 回避用配線、reset 時 RAM 初期化パターンを保持するため |

この方針により、外部から見える公開 module 名は Veryl 側に置きつつ、合成時に敏感な RAM/AXI 本体だけ SV leaf として固定している。

## 移行時の共通ルール

### モジュール外 function

元 SV でモジュール外に定義されていた function は、Veryl では package に移している。

代表例:

- `DecoderFunctions`
- `CommitStageFunctions`
- `DCacheFunctions`
- `ICacheFunctions`
- `LoadStoreUnitFunctions`
- `CSR_UnitFunctions`
- `BypassControllerTypes`

### マクロ assert

`RSD_ASSERT_CLK`、`RSD_STATIC_ASSERT`、一部の debug/non-synthesis initial は、そのまま native Veryl にできない箇所がある。これらは指定どおり、直前に共通コメントを置いてコメントアウトしている。

```veryl
// NOT_TRANSPILED_TO_VERYL
// ...
```

### マクロ条件付き構成

Veryl の struct/modport/interface 定義では、SV と同じ位置にプリプロセッサ分岐を置けない箇所がある。このため、いくつかのファイルは現行構成に合わせて展開している。

主な前提:

- `RSD_MARCH_FP_PIPE` は有効な構成として展開。
- `RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE` は無効な構成として展開。
- `RSD_ENABLE_ZBA`、`RSD_ENABLE_ZICOND` は Decoder 側で有効な構成として展開。
- `DebugTypes.veryl` は現行の FP/デバッグ有効構成で必要な packed debug field を明示。
- `IO_UnitTypes.veryl` は現行構成に合わせて LED 幅 16、serial 幅 32 を明示。

別のマクロ組み合わせを使う場合は、該当 interface/type/package の別表現を追加する必要がある。

### Veryl の型検査に合わせた表現

元 SV と意味は同じだが、Veryl の型検査を通すために表現を変えた箇所がある。

- array-of-struct は `Type<N>` 形式を使う箇所がある。
- `PreDecodeStage.veryl` の `microOps` は `MicroOpInfoArray [DECODE_WIDTH]` とし、stage register へ要素ごとに代入している。
- `SchedulerTypes.veryl` の `SchedulerSrcTag` は `SchedulerRegTag<N>` 形式で保持している。
- union の別名 field 参照は、Veryl が型検査できる field へ寄せている箇所がある。
- SV の variable part-select は、shift/or や helper function に展開した箇所がある。

## 個別の注意点

### Decoder

`Processor/Src/Decoder/Decoder.sv` はモジュール外 function が多く、`veryl translate --stdout` では FP デコードの三項演算子チェーン周辺で構文的に不正な Veryl が生成された。

現在は手作業で native Veryl 化済み。function 群は `DecoderFunctions` package に移し、`PreDecodeStage.veryl` から native `Decoder` を直接 instantiate している。`Decoder_SV` leaf への参照は残していない。

### ReplayQueue

`ReplayQueue.veryl` は native Veryl 実装へ移した。

変換中、`flushInt`/`flushMem` の計算で Veryl 0.20.1-nightly の `combinational_loop` 検出に引っかかった。これは元 SV 上の実回路ループではなく、解析器が次の依存を保守的に同一組合せ経路として扱った false positive と判断している。

```text
popEntry -> QueuePointer/RAM -> replayEntryOut -> flush* -> popEntry
```

元の `QueuePointerWithEntryCount` は head/tail/count がレジスタ出力で、`DistributedDualPortRAM` の read address もそのレジスタ出力から来るため、実際にはレジスタ境界が入る。

対処として、ReplayQueue 内では pointer レジスタと小さな replay storage を native Veryl に展開し、`flush*` 計算ブロックと `popEntry`/replay 出力計算ブロックを分離した。

### DCache

`DCache.veryl` は controller、memory request arbiter/mux、array port arbiter/mux、miss handler、top glue まで native Veryl 化済み。module 外 function 群は `DCacheFunctions` package に移した。

`DCacheArray` だけは RAM 推論形状を保つため、native Veryl wrapper から `DCacheArray_SV` を呼ぶ形で残している。これは理由なく残した SV leaf ではなく、合成時の挙動を固定するための例外である。

MSHR allocation では、元 SV の一般ループをそのまま書くと Veryl 0.20.1-nightly が `mshrConflict`/`portInitMSHR` を `combinational_loop` として検出した。現行 RSD 構成では load port 1、store port 1、MSHR 2 entry が定数なので、元 SV と同じ load 優先、次に store の優先順を scalar に展開して false positive を回避した。

### Core / FP backend

`Core.veryl` は native Veryl 実装へ移した。

FP backend の次の stage も native Veryl 実装へ移しており、`Core.veryl` からの `$sv::FP...` 直呼びは削除済み。

- `FPIssueStage.veryl`
- `FPRegisterReadStage.veryl`
- `FPExecutionStage.veryl`
- `FPRegisterWriteStage.veryl`

`FPExecutionStage` の local pipeline register は、`ComplexIntegerExecutionStage` と同じ `LocalPipeReg<ISSUE_WIDTH, DEPTH - 1>` 形式で保持している。元 SV の `inside` と三項演算子は if/OR 条件へ展開した。

### MemoryTagAccessStage

`MemoryTagAccessStage.veryl` は native Veryl 実装へ移した。理由のない SV leaf としては残していない。

### Cache / branch predictor

`ICache.veryl` は main module まで native Veryl 化済み。hit/eviction way 探索の `break` は `foundHit` / `foundEvict` フラグ付きループへ展開した。RAM 配列サブモジュールは native RAM wrapper 経由で SV leaf の RAM 本体を参照する。

`BTB.veryl`、`Gshare.veryl`、`Bimodal.veryl` は native Veryl 化済み。PHT/BTB RAM 本体は RAM wrapper 経由で SV leaf 側に残している。

### Load/store / queues

`LoadQueue.veryl`、`StoreQueue.veryl`、`StoreCommitter.veryl`、`LoadStoreUnit.veryl` は native Veryl 化済み。

`StoreQueue` の data RAM、`DestinationRAM`、`MemoryDependencyPredictor` など、RAM 推論対象の本体は RAM wrapper 経由で SV leaf 側に残している。

### Register / scheduler / rename

`RegisterFile.veryl`、`BypassNetwork.veryl`、`BypassController.veryl`、`Scheduler.veryl`、`IssueQueue.veryl`、`WakeupPipelineRegister.veryl`、`RenameLogic.veryl`、`ActiveList.veryl` は native Veryl 化済み。

RAM 本体を持つ箇所は、公開 module を Veryl に置いたうえで RAM wrapper 経由の SV leaf に切り出している。

## 残っている確認ポイント

- 別マクロ構成でビルドする場合は、現行構成として展開した interface/type/package を再確認する。
- 合成向け flow で RAM 推論が期待どおりか確認する。
- `// NOT_TRANSPILED_TO_VERYL` の箇所は、必要なら Veryl 側で書ける assert 形式に置き換える。
- Veryl の `combinational_loop` false positive 回避として scalar 展開した箇所は、ポート数や MSHR 数を変更した場合に再確認する。
