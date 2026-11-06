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
| 5 | 材質変換: Principled BSDF を Base BSDF に変換（色・金属・粗さ・透過・IOR・発光・コート・シーン・アルファ・ノーマルマップ・画像）。非対応ノードは警告して代替値にし、プロシージャルはベイク | REQ-DCC-003 | 一部済（Principled・Diffuse・Glossy・Glass・Emission・Mix、画像・法線マップ・UDIM 対応。非対応は警告。手続き型の材質ベイクは未着手） |
| 6 | Final 出力: Render Result に Combined と AOV（Lighting AOV・Depth・Normal・Albedo・SampleCount）。進捗とキャンセル、OIDN のデノイズ、EXR のメタデータ（非物理の印） | REQ-DCC-001 / REQ-ACC-001 | 済（Combined と AOV、進捗とキャンセル、OIDN、EXR の非物理の印、レンダ範囲） |
| 7 | ビューポートレンダ: `view_update` を `Changes` に変換して `update` を呼び、`view_draw` で表示する。Interactive モード（ReSTIR）を使う。描画中も UI を止めない（GIL を放して別スレッド）。First Clean Preview を計測して記録する | REQ-DCC-002 / REQ-VIEW-003 | 実装済・実機確認待ち（`Viewport` のロジックはヘッドレスでテスト済み。3D ビューへの描画 `view_draw` は Blender の GUI での確認が必要。計測は `first-clean-preview.md`） |
| 8 | Stylization ノード: Blender のノードで Stylization レイヤー（ToonRamp・ShadowPalette など）を編集し、glTF 拡張と同じスキーマの IR に変換する | REQ-DCC-001 / REQ-STY | 済（マテリアルタブの Stylization パネル `stylization.py`: hybridSurface・Toon Ramp・Shadow Palette・Rim・Stylized Specular・Outline・MatCap。glTF 拡張と同じ JSON をネイティブの同じ検証に通す。ワールドタブに仮想の主光源の設定。`test_stylization.py`。ノードエディタのノードではなくパネル（理由は下の「決めてあること」）） |
| 9 | IES とライトリンク: `.ies` の配光を Spot / Point に使う。ライトごとの対象 Instance の絞り込み（TLAS のマスク）。NEE と MIS を保つ | REQ-CORE-004 / REQ-DCC-001 | 未着手 |
| 10 | Cryptomatte: Object・Material・Asset の ID（規格どおりのハッシュ）を Render Result と EXR に出す | REQ-DCC-001 | 未着手 |
| 11 | Shadow Catcher とアルファ合成 | REQ-DCC-001 | 未着手 |
| 12 | UDIM・タイル化したテクスチャ | REQ-IO-004 | 済（UDIM を 1 枚のアトラスに変換。`test_udim.py`） |
| 13 | 環境光だけで照明したときの Toon の段: HDRI から支配的な光の方向を求めて仮想の主光源にする（ADR-0020）。上書き（方向・強さ・無効化）、影の光線 1 本、一様な空では出さない。太陽のない HDRI で段が出る検証 | REQ-STY | 済（ADR-0020。`pack::virtual_light`、光テーブルの kind 3、slot 3。ビューティは変わらない。上書きは Scene IR と Python と Blender のワールドタブにあり、glTF 拡張への項目の追加は利用者の確認待ち） |
| 14 | DCC 間の一貫性: 同じシーンを Blender 経由と glTF 経由で描いて閾値内で一致する。Cycles との比較は参考値として記録する | REQ-QA | 未着手 |
| 15 | 配布: アドオン zip（macOS Apple silicon・Windows x64）。ネイティブライブラリと OIDN の CPU 版・ライセンス文書を同梱（ADR-0018）。GPU 版 OIDN を足す導線（GUI） | REQ-INFRA-003 | 未着手 |
| 16 | Windows（Vulkan）での確認: Blender 5.x と 4.5 LTS で、項目 4〜7 の画像が Metal と一致する | REQ-GPU-007 | 未着手（Windows 機の作業。`docs/handoff/` に手順を残す） |

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

- 仕様書 `gltf-stylization-extension.md` への、仮想の主光源の上書き項目の追加（スキーマの変更。項目 13 の実装時）と、`overview.md` の未決事項の更新
- Octane との比較は、この M6 の後に Blender 用の無料版で行う（M5 の持ち越し。REQ-ACC-002）

## 完了条件

- [ ] 実シーンを Blender で編集・プレビュー・Final 出力できる（REQ-DCC-001）
- [ ] 編集後の First Clean Preview を計測して記録した（REQ-DCC-002）
- [ ] Principled BSDF が変換でき、非対応ノードは警告して代替値になる（REQ-DCC-003）
- [ ] Stylization ノードを Blender 上で編集できる
- [ ] IES・ライトリンク・Cryptomatte・Shadow Catcher・UDIM が動く
- [ ] Blender 経由と glTF 経由の画像が閾値内で一致する
- [ ] 4.5 LTS と 5.x、Metal と Vulkan で動く
