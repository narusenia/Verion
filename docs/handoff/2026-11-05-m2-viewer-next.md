# 引き継ぎ: M2 の Stylization 層が揃った → Viewer → clearcoat から

前の引き継ぎ（`2026-11-05-m2-stylization-mid.md`）の続き。協議と精査は終え、そこで決めたことの実装まで済み。

## 済み（origin に push 済み。未 push は直近 4 コミット＝多重散乱補償）
- 項目 3・4・5・13・14・15 済。Stylization の層: HybridSurface（diffuse・specular・gi・shadow・outline）、ToonRamp、ShadowPalette、RimLight、StylizedSpecular（帯＋`ramp` の多段）、OutlineStyle。層は材質に書いた順に適用
- ライトスロットは光ごとに拡散 `u`・鏡面 `s`・方向・可視性（260 B/画素）。PostProcess は `verion-stylization::postprocess`（輪郭線・色調整。`render-cli --exposure / --saturation / --white-balance`）
- 項目 12 の多重散乱補償: 金属の鏡面に `1 + F0(1/E − 1)`。E の表は `scripts/gen_ggx_albedo.py` で生成。既定で有効、`--no-multiscatter` で切替。Mitsuba 照合（`render_ppm`）は無効で行う
- 仕様・要件・M2 README は更新済み

## 決めたこと
- ライトスロット: 面光源・環境光は slot 3 に同居。環境光は太陽つきなら段が出る（確認済み）
- Viewer は winit + egui（ADR-0012）。描画経路は `winit` + `egui` + 自前 Metal 表示を推奨。依存追加は許可済み。追加前に `mise run deny` でライセンス確認
- MatCap は協議リスト入り

## 未解決（協議へ）
- push: 直近 4 コミット。リモートは移転済み（`git@github.com:narusenia/verion.git`、`remote set-url` は未実施）
- bench: scale が +7.4%（10% 門限内）。温めて再計測し、必要なら baseline を再記録
- 協議: MatCap、間接鏡面（映り込み）が `hybridSurface.specular` で置き換わる制限、拡散 HDRI での ramp、4 光以上のスロット共有、誘電体の多重散乱
- EXR に PostProcess の適用値を残していない（REQ-STY-011 の受入条件 3）。`gi` の鏡面・Mitsuba 照合の実行は未実施
- M1 から継続: 実機の OOM・HDRI 照合、M4 Pro 確認

## 次の一手（この順）
1. Viewer（項目 10）: 依存（winit・egui 系）のライセンスを `mise run deny` で確認 → 累積表示・AOV 切替・パラメータ変更→再累積の最小版。実装前に経路（自前 Metal 表示）を確認
2. clearcoat → sheen（`gltf` クレート 1.4 は未対応のため glTF 拡張を自前パース。REQ-CORE-003）→ Dispersion の RGB 近似（`KHR_materials_dispersion` の仕様は原文未読）
3. デノイズ（項目 8: OIDN / MetalFX の選定を ADR に記録。依存追加が絡むので頼まれたとき）、評価の初期版（項目 11）

## 進め方
- 論理単位で英語 1 行コミット。docs 更新は確認を取る。push は毎回確認。`mise run check` を push 前に回す
- 関連: `docs/implementation/M2-stylization/README.md`、`docs/specifications/gltf-stylization-extension.md`、`crates/verion-stylization/src/{lib,postprocess}.rs`、`shaders/pathtrace.slang`、`crates/verion-gpu-metal/src/renderer.rs`
- 新しい会話の最初の一言: 「docs/handoff/2026-11-05-m2-viewer-next.md を読んで続けて」
