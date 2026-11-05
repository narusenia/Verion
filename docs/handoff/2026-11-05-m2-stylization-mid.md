# 引き継ぎ: M2 途中（ShadowPalette まで済 → StylizedSpecular・RimLight から）

## 済み（ローカル main、origin より 4 コミット先行＝未 push。push は毎回確認）
- 項目 1・2・6（Motion Vector 除く）・9 済。項目 3・4・7 は実装済みで README は進行中/済を反映
- Lighting AOV: 5 成分 + Visibility + 光ごとスロット（`u`, `r`、4 枠）。`--lighting-aovs`。Material ID AOV も済
- `verion-stylization` クレート: `stylize`（HybridSurface.diffuse/shadow、ToonRamp 光ごと、ShadowPalette）
- glTF 拡張 `VERION_materials_stylization`（hybridSurface / toonRamp / shadowPalette）。仕様は `docs/specifications/gltf-stylization-extension.md` とスキーマ
- `render-cli --mode stylized`。ADR-0012 で Viewer は winit + egui

## 決めたこと
- ramp の応答は光ごとの cosθ×可視性。面光源・環境光は 1 枠にまとめる
- Motion Vector は M5 へ。デノイズと Viewer は依存追加が絡むので、頼まれたときだけ
- 順序: StylizedSpecular・RimLight → Viewer → デノイズ

## 未解決（協議待ち。あとで）
- 面光源・環境光の近似、間接影の定義（間接拡散に補正をかける近似）、光 4 つ以上のスロット共有
- baseline は怪しい。AC 接続・温めた後にユーザーが `mise run bench record` を実行し、±2% を確認。それまで bench の 10% ゲートは当てにしない
- ビューティ経路は lighting 追加で数 % 遅い（同一条件比 cube +6〜8%）。実機の OOM・HDRI 照合、M4 Pro 確認、項目 1・3 は M1 から継続
- 未実施: ShadowPalette 実画像の確認（`scratchpad` の `shadow_*.exr` を tev で）

## 次の一手
1. `Cargo.lock` の差分と本メモをコミットし、push の可否を確認
2. REQ-STY-004・005（StylizedSpecular・RimLight）。IR 変種 → Pass → 拡張 → 仕様書の順。specular は `PixelInput.specular` 合計だけでは足りないので、光ごとの入力が要るか先に判断
3. 変更ごとに `mise run check`（deny 含む）を push 前に回す。新依存は無断で足さない

## 進め方
- 論理単位で英語 1 行コミット、docs 更新は確認を取る。EXR は tev で見てもらう（`open -a tev`）
- 新しい会話の最初の一言: 「docs/handoff/2026-11-05-m2-stylization-mid.md を読んで続けて」
