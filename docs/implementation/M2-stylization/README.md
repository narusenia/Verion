# M2: Stylization と最小 Viewer（v0.1）

目標: 写実から Toon までを連続調整でき、AOV を分離出力する。
依存: M1。方針: ADR-0005 / 0008 / 0009。

| # | 項目 | REQ | 状態 |
|---|------|-----|------|
| 1 | Stylization 用 glTF 拡張のスキーマ確定（仕様書） | REQ-IO-002 | 済（仕様書と JSON Schema は確定。ローダーは `VERION_materials_stylization` を読み、範囲外は取り込みエラー、未知のプロパティは警告にする） |
| 2 | Material IR の 3 分離と `ShadingContext` | REQ-STY-008 | 済（`Base BSDF` / `Stylization Layers` / `Output Channels` の分離は M1 から。`ShadingContext`（光ごとの成分を保持）と `Revisions.stylization`、EXR の `verion/stylizationRevision` を追加。`ShadingContext` の Slang 側対応は項目 3 以降） |
| 3 | HybridSurface | REQ-STY-001 | 進行中（IR の `HybridSurface` と検証は済。GPU 評価は未着手） |
| 4 | ToonRamp・ShadowPalette | REQ-STY-002 / 003 | 済（`ToonRamp`（光ごとに段階化）と `ShadowPalette`（直接影・間接影を別々に色補正）を IR・Pass・glTF 拡張に実装。GPU 側は光ごとのスロットを出すのみで、評価は Pass（CPU）） |
| 5 | StylizedSpecular・RimLight | REQ-STY-004 / 005 | 進行中（RimLight は済: IR・glTF 拡張・Pass と、実画像（球と床）での確認まで。ライトスロットは拡散 `u`・鏡面 `s`・方向・可視性を持ち、層は材質に書いた順に適用する。StylizedSpecular は帯状と、`ramp` による多段まで済（IR・glTF 拡張・Pass）。楕円・手描き風は後続） |
| 6 | Lighting AOV の分離出力 | REQ-STY-006 | 進行中（一次ヒットの DirectDiffuse・IndirectDiffuse・Specular・Transmission・Emission・Visibility を分離し、`render-cli --lighting-aovs` で EXR に出力（光ごとのスロットは EXR に出さず内部入力。1 ピクセル約 260 バイト。光ごとのスロットは拡散 `u`・鏡面 `s`・方向・可視性を持つ）。5 成分の和はビューティと一致。間接光は最初のバウンスのローブ側に入れる。Normal・Depth・Object ID は M1 から出力済み。Material ID も出力済み。Motion Vector は M5 に送る） |
| 7 | Stylization Pass（一次ヒット Hybrid） | REQ-STY-007 | 進行中（`verion-stylization` クレートに、AOV から最終色を合成する Pass（デノイズ抜き）を追加。`HybridSurface.diffuse` で直接拡散を `ToonRamp` に寄せる部分のみ。他の成分は物理のまま。ramp は光ごとの cosθ × 可視性で段階化する（lighting AOV に光ごとのスロットを持つ）。`render-cli --mode stylized` で接続済み。Toon の見た目は実画像で未確認） |
| 8 | デノイズ（OIDN / MetalFX の選定を ADR に記録） | REQ-ACC-001 | 未着手 |
| 9 | Viewer の GUI 技術を決める | REQ-VIEW-002 | 済（winit + egui。ADR-0012） |
| 10 | 最小 Viewer（累積・AOV 切替・パラメータ変更→再累積） | REQ-VIEW-002 | 未着手 |
| 11 | Stylization 評価の初期版（Art Direction 一致・デノイズによる消失） | REQ-QA-003 | 未着手 |
| 12 | 写実材質の拡充（多重散乱補償・clearcoat・sheen・Dispersion の RGB 近似） | REQ-CORE-003 | 未着手 |
| 13 | PostProcess の枠と最小の色調整 | REQ-STY-011 | 未着手 |
| 14 | 間接光の平坦化（`HybridSurface.gi`） | REQ-STY-001 | 済（間接拡散を「アルベド × 材質ごとの一定の環境光」へ混ぜる。一定値はフレーム内の間接拡散の和 ÷ アルベドの和。Albedo AOV を Pass に渡す。実画像は未確認） |
| 15 | 最小の輪郭線（Normal・Depth・Object ID・Material ID から画面空間で作る。項目 13 の枠の最初の Pass。時間的安定性は M8） | REQ-STY-009 / 011 | 未着手 |

## 完了条件

- 同一シーンを写実から Toon まで連続調整できる
- デノイズが Toon 境界を消さない
- Reference モードが Stylization をバイパスする
