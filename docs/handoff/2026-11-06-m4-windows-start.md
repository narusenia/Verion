# 引き継ぎ: M4 を Windows 機（RTX 3080）で始める

前の引き継ぎ（`2026-11-06-m3-complete.md`）の続き。Mac で M4 の項目 1・2 を終え、origin に push 済み。項目 3 以降は Vulkan のレイトレーシングが動く Windows 機で進める。計画は `docs/implementation/M4-vulkan/README.md`（状態はその表だけで管理する）。

## 済み（Mac）
- 項目 1: Backend の契約クレート `verion-gpu`（trait `RayTracingBackend` と `Accumulation`、共有型 `Integrator`・`Adaptive`・`Aovs`・`LightingAovs`・`MemoryUsage`）。CLI と Viewer は `type Backend = verion_gpu_metal::Renderer` と関連型 `<Backend as RayTracingBackend>::Context` / `::Accumulation` だけを使う
- 項目 2: `mise run shaders` が MSL と SPIR-V を両方作る。SPIR-V は `crates/verion-gpu-vulkan/shaders/*.spv`（1.5 + ray query、エントリ名 `main`）。`verion-gpu-vulkan` は今は `SHADERS`（名前と SPIR-V の組）を埋め込むだけ
- 項目 15 相当: CI（`.github/workflows/ci.yml`）は既に `windows-latest` で `mise run check` を通している

## Windows 機で最初にやること
1. clone して `mise install`（rust 1.99・slangc 2026.21・cargo-deny など。Mitsuba は照合用で不要なら飛ばしてよい）
2. `mise run check` が通ることを確かめる（CI と同じ。Metal 系は `cfg(target_os = "macos")` で外れる）
3. Vulkan SDK / ドライバで ray query・acceleration structure・SER（`VK_NV_ray_tracing_invocation_reorder` または EXT 版）が使えるかを `vulkaninfo` で確かめ、結果を M4 README の項目 3 に書く
4. `scripts/*.sh` は sh なので Git Bash で動かす。`mise run shaders:check` も同様

## 項目 3 以降の要点
- 依存: `ash`（MIT / Apache-2.0）を第一候補。`verion-gpu-vulkan` の Cargo.toml に `cfg(not(target_os = "macos"))` で足し、`mise run deny` で確かめる。メモリ割り当て（自前か `gpu-allocator`）は必要になった時点で決める
- `verion-gpu-vulkan` に `verion-gpu` への依存を足し、`RayTracingBackend` を実装する。Metal 側の実装（`crates/verion-gpu-metal/src/renderer.rs`・`renderer/wavefront.rs`）がそのまま手本になる
- バインド: descriptor set 0、binding 番号は Metal の buffer index と同じ（`shaders/include/pt_core.slang` が 0〜18、`include/wf_state.slang` が 19〜24）。0 は TLAS、6 はパラメータブロック
- パラメータブロック（36 語、`PARAM_WORDS`）: シェーダーでは `StructuredBuffer<uint>` なので、Dispatch ごとの領域を持つストレージバッファで渡す（push constant にはしない）。Metal は `setBytes` で Dispatch ごとに複製しているので、Wavefront では深さごとに値が違う点に注意（words 6・30・31）
- Wavefront の `wf_select` は binding 22（`queueOut`）を深さ 0 のキューに差し替えて使う（`wavefront.rs` の `bind` 後の上書き）
- CLI と Viewer の切替（項目 8）: `type Backend` を `cfg(target_os)` で切り替える。`--backend` の実行時選択は項目 8 で、必要なら enum で包む
- 画像比較（項目 9）: ビット一致は求めない。高 spp の EXR どうしを `crates/verion-render-io/examples/exr_diff.rs` で比べ、閾値は初回実測で決める。Metal 側の参照 EXR は Mac で作って持ち込む

## 要確認（利用者）
- Octane の利用環境（項目 14 の前）
- Verion のライセンス判断の時期（ADR-0004）

## 進め方
- 新しい会話の最初の一言: 「docs/handoff/2026-11-06-m4-windows-start.md を読んで M4 の項目 3 から続けて」
- push は毎回確認を取る
