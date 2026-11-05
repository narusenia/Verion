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
- 累積画像は、Renderer の出力（CPU 側の平均）を egui のテクスチャとして表示する。eframe（egui-wgpu、Metal 上で動作）を使う。当初案の「`CAMetalLayer` への直接表示」は、egui の Metal painter の自作が要るため採らなかった（2026-11-05 項目 10 で変更）
- 候補にした GPUI、AppKit / SwiftUI 直接、Slint / iced は採らない
  - GPUI: 安定版がなく git 依存になりやすく、API の変動が大きい
  - AppKit / SwiftUI: Rust 単一言語（ADR-0006）から外れ、Vulkan 側に使い回せない
  - Slint / iced: Metal レイヤーを埋め込む経路が弱い。Slint はライセンス条件が再配布要件と合うか未確認

## 結果

- wgpu 系の依存が増え、ビルドは重くなる。GPU 上の累積バッファは毎フレーム CPU に読み戻すため、解像度を上げると重い。性能が要るときは直接表示に戻す
- 依存の追加は項目 10 で行い、本 ADR では追加しない
- `mise run deny` で確認済み。egui の同梱フォント（OFL-1.1・Ubuntu-font-1.0）だけ単独の例外にした（`deny.toml`）。出荷時はライセンス表記の同梱が要る
- Viewer を閉じても `render-cli` の経路は変わらない。GUI は `verion-render-cli` とは別クレートにする
