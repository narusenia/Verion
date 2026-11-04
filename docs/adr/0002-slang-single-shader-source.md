# ADR-0002: Shader は Slang 一本化とし、M1 でスパイク検証する

- 状態: 採用
- 日付: 2026-11-04

## 背景

Metal 先行・Vulkan 後追いなので、BSDF・Integrator・Stylization を 2 回書くと Backend 間の見た目が崩れる（草案リスク 4）。

## 決定

- Shader は Slang で書き、MSL と SPIR-V にコンパイルする
- M1 の最初に「Slang → MSL で Metal RT が動く」スパイクを行う。不可なら MSL ネイティブへ切り替え、結論を ADR に記録する
- Rust の Metal バインディングは `objc2-metal` を想定する

## スパイク結果（2026-11-04、暫定採用）

- 検証環境: slangc 2026.21（Apache-2.0 with LLVM Exceptions）、Metal Toolchain 27B47
- 三角形 1 枚の交差判定が Metal RT で期待どおり動作した（`verion-spike-rt`）
  - Slang の `RayQuery` / `TraceRayInline` が MSL の `metal::raytracing::intersection_query` に変換された
  - `RaytracingAccelerationStructure` が `acceleration_structure<instancing>` に変換された
  - `.air` / `.metallib` までオフラインで生成できた
- 気づき: エントリ名が `main_0` に改名される。リソースは `[[buffer(n)]]` に宣言順で割り当たる
- 結論: 暫定採用。MSL ネイティブへの撤退は現時点で不要

### 暫定とする理由（未検証）

- 複数マテリアルや intersection function table を要するシェーダー構造
- 複数バッファ・構造体を含む Slang パラメータのバインド
- デバッグ性、SPIR-V 側、M4 Pro と M5 の両機での動作

上記を M1 の項目 3 以降で確認し、問題があればこの ADR を更新する。

## 結果

- Slang の制約に縛られる
