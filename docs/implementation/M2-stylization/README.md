# M2: Stylization と最小 Viewer（v0.1）

目標: 写実から Toon までを連続調整でき、AOV を分離出力する。
依存: M1。方針: ADR-0005 / 0008 / 0009。

| # | 項目 | REQ | 状態 |
|---|------|-----|------|
| 1 | Stylization 用 glTF 拡張のスキーマ確定（仕様書） | REQ-IO-002 | 済（仕様書と JSON Schema は確定。ローダーは `VERION_materials_stylization` を読み、範囲外は取り込みエラー、未知のプロパティは警告にする） |
| 2 | Material IR の 3 分離と `ShadingContext` | REQ-STY-008 | 済（`Base BSDF` / `Stylization Layers` / `Output Channels` の分離は M1 から。`ShadingContext`（光ごとの成分を保持）と `Revisions.stylization`、EXR の `verion/stylizationRevision` を追加。`ShadingContext` の Slang 側対応は項目 3 以降） |
| 3 | HybridSurface | REQ-STY-001 | 済（IR・検証・glTF 拡張と、Pass での評価。成分ごとの係数で `diffuse`（ToonRamp）・`specular`（StylizedSpecular）・`gi`（間接光の平坦化）・`shadow`（ShadowPalette）・`outline`（輪郭線の不透明度）を混ぜる。`reflection` は映り込み（間接鏡面）を消す度合いで、既定 0 で残す（直接鏡面はスロットから復元して分ける）。GPU 側は光ごとのスロットを出すのみで、評価は Pass（CPU）） |
| 4 | ToonRamp・ShadowPalette | REQ-STY-002 / 003 | 済（`ToonRamp`（光ごとに段階化）と `ShadowPalette`（直接影・間接影を別々に色補正）を IR・Pass・glTF 拡張に実装。GPU 側は光ごとのスロットを出すのみで、評価は Pass（CPU）） |
| 5 | StylizedSpecular・RimLight | REQ-STY-004 / 005 | 進行中（RimLight は済: IR・glTF 拡張・Pass と、実画像（球と床）での確認まで。ライトスロットは拡散 `u`・鏡面 `s`・方向・可視性を持ち（点・平行・スポットは強さ順に slot 0〜2、弱い光は合算）、層は材質に書いた順に適用する。StylizedSpecular は帯状と、`ramp` による多段まで済（IR・glTF 拡張・Pass）。楕円・手描き風は後続） |
| 6 | Lighting AOV の分離出力 | REQ-STY-006 | 進行中（一次ヒットの DirectDiffuse・IndirectDiffuse・Specular・Transmission・Emission・Visibility を分離し、`render-cli --lighting-aovs` で EXR に出力（光ごとのスロットは EXR に出さず内部入力。1 ピクセル約 260 バイト。光ごとのスロットは拡散 `u`・鏡面 `s`・方向・可視性を持つ）。5 成分の和はビューティと一致。間接光は最初のバウンスのローブ側に入れる。Normal・Depth・Object ID は M1 から出力済み。Material ID も出力済み。Motion Vector は M5 に送る） |
| 7 | Stylization Pass（一次ヒット Hybrid） | REQ-STY-007 | 進行中（`verion-stylization` クレートに、AOV から最終色を合成する Pass（デノイズ抜き）を追加。層は材質に書いた順に適用する（ToonRamp・ShadowPalette・RimLight・StylizedSpecular と `gi`）。ramp は光ごとの cosθ × 可視性で段階化する（lighting AOV に光ごとのスロットを持つ）。`render-cli --mode stylized` で接続済み。Toon の見た目は実画像で確認済み（点光源・太陽つき HDRI）。デノイズ（項目 8）は未着手） |
| 8 | デノイズ（OIDN / MetalFX の選定を ADR に記録） | REQ-ACC-001 | 進行中（選定は済: ADR-0013 で OIDN を先に採用、MetalFX は動画の段階で再評価。依存の追加と実装は未着手） |
| 9 | Viewer の GUI 技術を決める | REQ-VIEW-002 | 済（winit + egui。ADR-0012） |
| 10 | 最小 Viewer（累積・AOV 切替・パラメータ変更→再累積） | REQ-VIEW-002 | 済（`verion-viewer` クレート（`viewer scene.gltf`）。累積表示（プログレスバー付き）、AOV 切替（Beauty・Albedo・Normal・Depth）、Stylized 切替と色調整スライダ、多重散乱の切替→再累積。表示は egui テクスチャ（ADR-0012）。軌道カメラ（ドラッグ・スクロール）、ウィンドウ追従の解像度、材質ごとの Stylization スライダも済。Stylization は後処理なので再累積は要らない。操作感の確認は協議） |
| 11 | Stylization 評価の初期版（Art Direction 一致・デノイズによる消失） | REQ-QA-003 | 未着手 |
| 12 | 写実材質の拡充（多重散乱補償・clearcoat・sheen・Dispersion の RGB 近似） | REQ-CORE-003 | 済（多重散乱補償は済: 金属の鏡面に係数を掛ける方式で、白炉が 1 に戻る。E の表は `scripts/gen_ggx_albedo.py` で生成。既定で有効、`render-cli --no-multiscatter` と `Renderer::set_multiscatter` で切替。clearcoat は済: `KHR_materials_clearcoat` を読み、IOR 1.5 の GGX 層を追加ローブにする（層間の屈折・吸収は省略、テクスチャ未対応）。sheen も済: `KHR_materials_sheen` を読み、Charlie 分布の層を基底と coat の間に置く（基底は方向アルベドで減衰。表は `scripts/gen_sheen_albedo.py`、テクスチャ未対応）。Dispersion も済: `KHR_materials_dispersion` を読み、IOR を R・G・B で `±(ior−1)·0.025·dispersion` ずらす。パスが最初の分散ヒットで 1 チャンネルを選んで追従する。実シーンは `scenes/showcase.gltf`・`scenes/sheen_compare.gltf`（`scripts/gen_showcase_scene.py`）。Mitsuba 照合は未実施） |
| 13 | PostProcess の枠と最小の色調整 | REQ-STY-011 | 済（`verion-stylization::postprocess` に `PostFrame`・`outline`・`color_grade`（ゲイン・彩度・ホワイトバランス）。色調整は `render-cli --exposure / --saturation / --white-balance`（`--mode stylized` のみ）。EXR には非物理の印（`physical` = false）と、適用した色調整の値（`verion/exposure`・`verion/saturation`・`verion/whiteBalance`）を残す） |
| 14 | 間接光の平坦化（`HybridSurface.gi`） | REQ-STY-001 | 済（間接拡散を「アルベド × 材質ごとの一定の環境光」へ混ぜる。一定値はフレーム内の間接拡散の和 ÷ アルベドの和。Albedo AOV を Pass に渡す。実画像は未確認） |
| 15 | 最小の輪郭線（Normal・Depth・Object ID・Material ID から画面空間で作る。項目 13 の枠の最初の Pass。時間的安定性は M8） | REQ-STY-009 / 011 | 済（材質ごとの `outlineStyle` と `hybridSurface.outline`（不透明度）。線は近い側の物体の内側に引き、太さは画素単位。実画像（球と床）で確認） |
| 16 | MatCap（視線空間の法線で画像を引く陰影。1 枚で拡散・鏡面を置き換える。別画像への拡張は後続） | REQ-STY-012 | 進行中（仕様・要件の追加まで。IR・Pass・取り込み・Viewer・見本シーンは未着手） |

## 完了条件

- 同一シーンを写実から Toon まで連続調整できる
- デノイズが Toon 境界を消さない
- Reference モードが Stylization をバイパスする
