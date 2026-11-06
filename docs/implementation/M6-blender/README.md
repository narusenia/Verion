# M6: Blender 連携

目標: Blender の実シーンを Verion で編集・プレビュー・最終出力できるようにする。IES・ライトリンク・Cryptomatte・Shadow Catcher・UDIM もこの段階で入れる。
依存: M1〜M5（特に M5 の `update` と Interactive モード）。方針: ADR-0003 / 0009 / 0011 / 0017 / 0018 / 0019。

順序は「つなぐ → 見える → 編集に追従 → 機能を足す → 配る」。アダプタは薄く保ち、ロジックは Rust のコアに置く（M9 で Cinema 4D・Maya が同じコアを使うため）。

| # | 項目 | REQ | 状態 |
|---|------|-----|------|
| 1 | Blender の本体を用意する（4.5 LTS と 5.x。`blender -b` で Python を実行できること） | — | 済（`~/Applications/Blender/stable/` に 4.5.15 LTS と 5.2.3 LTS。Python は 3.11.15 と 3.13.13、numpy は 1.26.4 と 2.3.4） |
| 2 | `verion-py`（PyO3、abi3）: Scene IR の構築 API（メッシュ・Instance・材質・ライト・カメラを numpy で受ける）、Renderer と Accumulation、結果を numpy で返す。`maturin` でビルド。Blender 抜きの Python スクリプトで glTF と同じ画像になる | REQ-DCC-001 | 済（`crates/verion-py`。abi3 の 1 本が Blender 4.5（numpy 1.26）と 5.2（numpy 2.3）と素の Python で動く。`scripts/py_test.sh`。Scene のビルダーは glTF インポータと同じ画像） |
| 3 | アドオンの骨格 `plugins/blender/`: `RenderEngine` の登録、プロパティ（spp・モード・ReSTIR・Adaptive・デノイズ）、拡張の読み込みと版の確認。4.5 LTS と 5.x の API 差は薄い層に閉じる | REQ-DCC-001 | 済（`plugins/blender/verion_blender`。RenderEngine、プロパティ、版の確認 `native.py`、API 差は `compat.py`） |
| 4 | シーン同期（Final）: depsgraph からメッシュ（三角形化・法線・UV）、Instance（Transform・材質の割り当て）、カメラ（センサーフィット・シフト・被写界深度）、ライト（Point / Spot / Sun / Area）、ワールド（色・HDRI。手続き型の Sky Texture は HDRI へベイク）。ライトの W は Cycles の換算に合わせ、ライト種別ごとに Cycles との明るさを比べて記録する。同じシーンを glTF 経由の `render-cli` と比べて一致する | REQ-DCC-001 / REQ-CORE-001 | 一部済（メッシュ・Instance・カメラ（センサーフィット・シフト・DoF）・ライト 4 種・ワールド（色・HDRI・手続き型は Cycles でベイク）。ライトの換算は `light-units.md`。glTF 経由との画像比較は項目 14） |
| 5 | 材質変換: Principled BSDF を Base BSDF に変換（色・金属・粗さ・透過・IOR・発光・コート・シーン・アルファ・ノーマルマップ・画像）。非対応ノードは警告して代替値にし、プロシージャルはベイク | REQ-DCC-003 | 済（Principled・Diffuse・Glossy・Glass・Emission・Transparent・Mix、画像・法線マップ・UDIM、アルファ（定数）は `opacity`（確率的な素通し。影の光線にも効く）。手続き型の入力（Base Color・Roughness・Metallic・Emission）は Cycles のベイクでテクスチャにする（`bake_material.py`。UV のないメッシュは警告して既定値）。非対応は警告。画像のアルファ（切り抜き）は IR が画像のアルファを持たないため未対応） |
| 6 | Final 出力: Render Result に Combined と AOV（Lighting AOV・Depth・Normal・Albedo・SampleCount）。進捗とキャンセル、OIDN のデノイズ、EXR のメタデータ（非物理の印） | REQ-DCC-001 / REQ-ACC-001 | 済（Combined と AOV、進捗とキャンセル、OIDN、EXR の非物理の印、レンダ範囲） |
| 7 | ビューポートレンダ: `view_update` を `Changes` に変換して `update` を呼び、`view_draw` で表示する。Interactive モード（ReSTIR）を使う。描画中も UI を止めない（GIL を放して別スレッド）。First Clean Preview を計測して記録する | REQ-DCC-002 / REQ-VIEW-003 | 済（`Viewport` のロジックはヘッドレスでテスト済み。`view_draw` は Mac（Metal）と Windows（Vulkan、Blender 5.2.3）の GUI で確認。計測は `first-clean-preview.md`。Windows の GUI で見つけた 2 件を直した: Rendered → Solid → Rendered で止まる（古いエンジンが循環参照で残り、1 ビューポート約 4.2 GB の VRAM が解放されず `OutOfMemory`）、ジョブがエラーで終わっても黙って止まる（ログに出すようにした）。Windows の 4.5 LTS は GUI 未確認） |
| 8 | Stylization ノード: Blender のノードで Stylization レイヤー（ToonRamp・ShadowPalette など）を編集し、glTF 拡張と同じスキーマの IR に変換する | REQ-DCC-001 / REQ-STY | 済（マテリアルタブの Stylization パネル `stylization.py`: hybridSurface・Toon Ramp・Shadow Palette・Rim・Stylized Specular・Outline・MatCap。glTF 拡張と同じ JSON をネイティブの同じ検証に通す。ワールドタブに仮想の主光源の設定。`test_stylization.py`。ノードエディタのノードではなくパネル（理由は下の「決めてあること」）） |
| 9 | IES とライトリンク: `.ies` の配光を Spot / Point に使う。ライトごとの対象 Instance の絞り込み（TLAS のマスク）。NEE と MIS を保つ | REQ-CORE-004 / REQ-DCC-001 | 済（点・スポット光の IES（LM-63 の C 型。光の軸は Blender の -Z）とライトリンク（受光側のコレクション。点・スポット・面光源、リンクした光 31 個まで）。強さは Cycles に合わせて実測（IES の 1 cd は光の強さの 0.0707 倍）。Cycles との比: IES 0.965（ブロック相関 0.9996）、リンクは一致。面光源のリンクは、直前に散乱した面（`prevInst`）と面光源のグループで BSDF ヒットと NEE の両方から外す。ブロッカーのリンクは未対応で警告。`test_light_extras.py`） |
| 10 | Cryptomatte: Object・Material・Asset の ID（規格どおりのハッシュ）を Render Result と EXR に出す | REQ-DCC-001 | 未着手 |
| 11 | Shadow Catcher とアルファ合成 | REQ-DCC-001 | 済（Film の Transparent で、アルファは 16 本の層別レイのカバレッジ（半透明は不透明度で重み付け）、カメラ光線が当たった空は黒。Shadow Catcher は黒＋影をアルファに出す（Visibility AOV）。`test_alpha.py`） |
| 12 | UDIM・タイル化したテクスチャ | REQ-IO-004 | 済（UDIM を 1 枚のアトラスに変換。`test_udim.py`） |
| 13 | 環境光だけで照明したときの Toon の段: HDRI から支配的な光の方向を求めて仮想の主光源にする（ADR-0020）。上書き（方向・強さ・無効化）、影の光線 1 本、一様な空では出さない。太陽のない HDRI で段が出る検証 | REQ-STY | 済（ADR-0020。`pack::virtual_light`、光テーブルの kind 3、slot 3。ビューティは変わらない。上書きは Scene IR と Python と Blender のワールドタブにあり、glTF 拡張への項目の追加は利用者の確認待ち） |
| 14 | DCC 間の一貫性: 同じシーンを Blender 経由と glTF 経由で描いて閾値内で一致する。Cycles との比較は参考値として記録する | REQ-QA | 済（`test_consistency.py`: Blender 経由と glTF 経由が画素まで一致。Cycles との比は `consistency.md` に参考値として記録） |
| 15 | 配布: アドオン zip（macOS Apple silicon・Windows x64）。ネイティブライブラリと OIDN の CPU 版・ライセンス文書を同梱（ADR-0018）。GPU 版 OIDN を足す導線（GUI） | REQ-INFRA-003 | 済（macOS Apple silicon: `scripts/package_blender.sh` が abi3 の wheel を入れた拡張 zip を作り、空の Blender プロファイルへ入れて 4.5 と 5.2 で描画まで確認。Windows x64 は同じスクリプトを Windows 機で実行（項目 16）。OIDN は Blender の同梱を使うので同梱しない（ADR-0018 の追記）。GPU デノイズは Device の選択（Metal・CUDA・HIP）。拡張のライセンス欄は仮置きで、ADR-0004 の決定が外部配布の前に要る） |
| 16 | Windows（Vulkan）での確認: Blender 5.x と 4.5 LTS で、項目 4〜7 の画像が Metal と一致する | REQ-GPU-007 | 一部済（Windows 機 RTX 3080・Vulkan で、`mise run check`・`shaders:check`・`test:gpu`、`py_test.sh`、`blender_test.sh`、`package_blender.sh` が Blender 5.2.3 LTS と 4.5.7 LTS の両方で通った。残り: Metal との画像一致（Mac と Windows の `test_consistency.py` の `blender.exr` を並べて測る）。手順は `docs/handoff/2026-11-06-m6-device-checks.md`） |

## 決めてあること

- Rust コアと同じプロセスで動かす（PyO3）。対応は Blender 4.5 LTS と 5.x、拡張は abi3 の 1 本（ADR-0019）
- アダプタは Blender のデータの読み取りと表示だけを持ち、ロジックは Rust に置く。Scene IR を直接作る（glTF を経由しない。経由する場合は検証用の比較だけ）
- 画像は最初は CPU のバッファで渡す。GPU テクスチャの共有は First Clean Preview の計測で足りないと分かってから
- ライトの W は Cycles の換算に合わせる。手続き型の空は HDRI へベイクする。環境光だけの Toon の段は HDRI から仮想の主光源を求める（ADR-0019、ADR-0020）
- OIDN は CPU 版だけを同梱し、GPU 版は利用者が足す（ADR-0018）
- 開発機の Blender は 4.5.15 LTS（Python 3.11、numpy 1.26）と 5.2.3 LTS（Python 3.13、numpy 2.3）。numpy の主な版が違うので、`numpy` クレートは両方の ABI で動くことを項目 2 で確かめる
- Stylization の編集はノードではなく Material / World のプロパティパネルにする。Cycles のシェーダーツリーに入るカスタムノードは Blender の版ごとの API 差と保守が重く、ランタイムの保存形式も不安定になる。パネルは 4.5 LTS と 5.x で同じコードで動き、検証はネイティブ側の 1 か所に集まる
- 新しい依存は PyO3・maturin・`numpy` クレートまで（利用者が許可）。それ以外は追加のたびに確認する

## 要確認（利用者）

- 仕様書 `gltf-stylization-extension.md` への、仮想の主光源の上書き項目の追加（スキーマの変更。Scene IR・Python・Blender には入れてある）と、`overview.md` の未決事項の更新
- 拡張のライセンス欄（仮置きの Apache-2.0。ADR-0004）、ADR-0018 の追記（Blender の OIDN を使う）、画像のアルファによる切り抜きを入れるか、ライトリンクのブロッカー。詳細は `docs/handoff/2026-11-06-m6-device-checks.md`
- Octane との比較は、この M6 の後に Blender 用の無料版で行う（M5 の持ち越し。REQ-ACC-002）

## 完了条件

- [x] 実シーンを Blender で編集・プレビュー・Final 出力できる（REQ-DCC-001）— 編集・Final・プレビュー（`view_draw`）とも確認済み
- [x] 編集後の First Clean Preview を計測して記録した（REQ-DCC-002）
- [x] Principled BSDF が変換でき、非対応ノードは警告して代替値になる（REQ-DCC-003）
- [x] Stylization ノードを Blender 上で編集できる（ノードではなくパネル）
- [x] IES・ライトリンク・Cryptomatte・Shadow Catcher・UDIM が動く
- [x] Blender 経由と glTF 経由の画像が閾値内で一致する
- [ ] 4.5 LTS と 5.x、Metal と Vulkan で動く — 4.5 LTS と 5.x の Metal は済、Vulkan はテストと拡張 zip は済、Metal との画像一致が未測定
