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
- 順序: 協議と精査 → StylizedSpecular・RimLight → Viewer → デノイズ

## 未解決
- baseline は怪しい。AC 接続・温めた後にユーザーが `mise run bench record` を実行し、±2% を確認。それまで bench の 10% ゲートは当てにしない
- ビューティ経路は lighting 追加で数 % 遅い（同一条件比 cube +6〜8%）。実機の OOM・HDRI 照合、M4 Pro 確認、項目 1・3 は M1 から継続
- 未実施: ShadowPalette 実画像の確認（`scratchpad` の `shadow_*.exr` を tev で）

## 次の一手
StylizedSpecular・RimLight の前に、次の 3 つを先にやる。実装には入らず、協議と精査を先にする。
1. `Cargo.lock` の差分と本メモをコミット済みか確認し、push の可否を確認
2. 協議（下の協議リスト）。結論が出るまで docs へは書かず、まとめて反映する
3. 精査 2 本
   - 物理側の現状と、写実の高品質に足りないものの精査: 多重散乱（GGX は単一散乱のみ）、clearcoat・sheen、SSS、ボリューム、髪の BSDF、Dispersion、スペクトル対応。現状は M1 の拡散・GGX 金属・誘電体（透過）まで
   - Toon の表現力強化の精査: 今は拡散の ToonRamp と ShadowPalette のみで、Toon 寄りに偏っている。目標は ArkKnights: Endfield 風の見た目も含む（輪郭・顔影・髪ハイライト・網点などは REQ-STY-009 の M8 や PostProcess）。何を M2 に前倒しするかを決める
- その後に REQ-STY-004・005（StylizedSpecular・RimLight）。specular は `PixelInput.specular` 合計だけでは足りないので、光ごとの入力が要るか先に判断
- 変更ごとに `mise run check`（deny 含む）を push 前に回す。新依存は無断で足さない

## 協議リスト（結論待ち）
- 面光源・環境光の近似、間接影の定義、光 4 つ以上のスロット共有、Visibility の定義
- 「写実と Toon を同じシーンで両方高品質に」を M3 以降の明示的な軸にするか
- 写実側の材質の厚み（上の精査 1）。Dispersion は RGB 近似（IOR をチャンネルごとに変える）か、スペクトルか。`KHR_materials_dispersion` の仕様と `gltf` クレートの対応は未確認
- 多層（材質の層重ね / Stylization 層の多層化 / 写実と Toon の出力合成のどれか未確認。協議で意味を確認）
- PostProcess の計画（色収差、ブルーム、色調整、背景合成）
- bench の baseline（ユーザーが温めてから再記録）

## 進め方
- 論理単位で英語 1 行コミット、docs 更新は確認を取る。EXR は tev で見てもらう（`open -a tev`）
- 新しい会話の最初の一言: 「docs/handoff/2026-11-05-m2-stylization-mid.md を読んで続けて」
