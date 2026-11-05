# ADR-0012: 最小 Viewer の GUI は winit + egui にする

- 状態: 採用
- 日付: 2026-11-05

## 背景

REQ-VIEW-002 の最小 Viewer は、累積画像の表示、AOV の切り替え、Stylization パラメータのスライダを持つ。GUI 技術は M2 着手時に決めるとしていた。条件は次のとおり。

- ホスト言語は Rust（ADR-0006）。Backend は Metal 先行で Vulkan が後続（ADR-0001）
- 依存は商用再配布できるライセンスに限る（AGENTS.md）
- v0.1 の Viewer は最小で、作り込まない

## 決定

- ウィンドウとイベントは winit、UI（スライダ・AOV 切り替え）は egui を使う
- 累積画像は、Renderer の出力を `CAMetalLayer` に直接表示する。egui はその上に重ねる
- 候補にした GPUI、AppKit / SwiftUI 直接、Slint / iced は採らない
  - GPUI: 安定版がなく git 依存になりやすく、API の変動が大きい
  - AppKit / SwiftUI: Rust 単一言語（ADR-0006）から外れ、Vulkan 側に使い回せない
  - Slint / iced: Metal レイヤーを埋め込む経路が弱い。Slint はライセンス条件が再配布要件と合うか未確認

## 結果

- egui の描画先は未決。wgpu 版を使うか、egui の出力を自前の Metal 描画に流すかは項目 10 で選ぶ。wgpu は依存が大きいので、その時点でライセンスと `mise run deny` を確認する
- 依存の追加は項目 10 で行い、本 ADR では追加しない
- winit、egui とも `deny` の許可ライセンス（MIT / Apache-2.0）に収まるかは、追加時に確認する（未検証）
- Viewer を閉じても `render-cli` の経路は変わらない。GUI は `verion-render-cli` とは別クレートにする
