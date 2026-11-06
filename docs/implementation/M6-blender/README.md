# M6: Blender 連携

目標: Blender の実シーンを Verion で編集・プレビュー・最終出力できるようにする。IES・ライトリンク・Cryptomatte・Shadow Catcher・UDIM もこの段階で入れる。
依存: M1〜M5（特に M5 の `update` と Interactive モード）。方針: ADR-0003 / 0009 / 0011 / 0017 / 0018 / 0019。

順序は「つなぐ → 見える → 編集に追従 → 機能を足す → 配る」。アダプタは薄く保ち、ロジックは Rust のコアに置く（M9 で Cinema 4D・Maya が同じコアを使うため）。

| # | 項目 | REQ | 状態 |
|---|------|-----|------|
| 1 | Blender の本体を用意する（4.5 LTS と 5.x。`blender -b` で Python を実行できること） | — | 済（`~/Applications/Blender/stable/` に 4.5.15 LTS と 5.2.3 LTS。Python は 3.11.15 と 3.13.13、numpy は 1.26.4 と 2.3.4） |
| 2 | `verion-py`（PyO3、abi3）: Scene IR の構築 API（メッシュ・Instance・材質・ライト・カメラを numpy で受ける）、Renderer と Accumulation、結果を numpy で返す。`maturin` でビルド。Blender 抜きの Python スクリプトで glTF と同じ画像になる | REQ-DCC-001 | 未着手 |
| 3 | アドオンの骨格 `plugins/blender/`: `RenderEngine` の登録、プロパティ（spp・モード・ReSTIR・Adaptive・デノイズ）、拡張の読み込みと版の確認。4.5 LTS と 5.x の API 差は薄い層に閉じる | REQ-DCC-001 | 未着手 |
| 4 | シーン同期（Final）: depsgraph からメッシュ（三角形化・法線・UV）、Instance（Transform・材質の割り当て）、カメラ（センサーフィット・シフト・被写界深度）、ライト（Point / Spot / Sun / Area）、ワールド（色・HDRI）。同じシーンを glTF 経由の `render-cli` と比べて一致する | REQ-DCC-001 / REQ-CORE-001 | 未着手 |
| 5 | 材質変換: Principled BSDF を Base BSDF に変換（色・金属・粗さ・透過・IOR・発光・コート・シーン・アルファ・ノーマルマップ・画像）。非対応ノードは警告して代替値にし、プロシージャルはベイク | REQ-DCC-003 | 未着手 |
| 6 | Final 出力: Render Result に Combined と AOV（Lighting AOV・Depth・Normal・Albedo・SampleCount）。進捗とキャンセル、OIDN のデノイズ、EXR のメタデータ（非物理の印） | REQ-DCC-001 / REQ-ACC-001 | 未着手 |
| 7 | ビューポートレンダ: `view_update` を `Changes` に変換して `update` を呼び、`view_draw` で表示する。Interactive モード（ReSTIR）を使う。描画中も UI を止めない（GIL を放して別スレッド）。First Clean Preview を計測して記録する | REQ-DCC-002 / REQ-VIEW-003 | 未着手 |
| 8 | Stylization ノード: Blender のノードで Stylization レイヤー（ToonRamp・ShadowPalette など）を編集し、glTF 拡張と同じスキーマの IR に変換する | REQ-DCC-001 / REQ-STY | 未着手 |
| 9 | IES とライトリンク: `.ies` の配光を Spot / Point に使う。ライトごとの対象 Instance の絞り込み（TLAS のマスク）。NEE と MIS を保つ | REQ-CORE-004 / REQ-DCC-001 | 未着手 |
| 10 | Cryptomatte: Object・Material・Asset の ID（規格どおりのハッシュ）を Render Result と EXR に出す | REQ-DCC-001 | 未着手 |
| 11 | Shadow Catcher とアルファ合成 | REQ-DCC-001 | 未着手 |
| 12 | UDIM・タイル化したテクスチャ | REQ-IO-004 | 未着手 |
| 13 | 環境光だけで照明したときの Toon の段（HDRI から求めた支配的な光の方向を仮想の主光源にする案。overview.md の未決事項）。M6 の最初に方針を決め、ADR に記録する | REQ-STY | 未着手 |
| 14 | DCC 間の一貫性: 同じシーンを Blender 経由と glTF 経由で描いて閾値内で一致する。Cycles との比較は参考値として記録する | REQ-QA | 未着手 |
| 15 | 配布: アドオン zip（macOS Apple silicon・Windows x64）。ネイティブライブラリと OIDN の CPU 版・ライセンス文書を同梱（ADR-0018）。GPU 版 OIDN を足す導線（GUI） | REQ-INFRA-003 | 未着手 |
| 16 | Windows（Vulkan）での確認: Blender 5.x と 4.5 LTS で、項目 4〜7 の画像が Metal と一致する | REQ-GPU-007 | 未着手（Windows 機の作業。`docs/handoff/` に手順を残す） |

## 決めてあること

- Rust コアと同じプロセスで動かす（PyO3）。対応は Blender 4.5 LTS と 5.x、拡張は abi3 の 1 本（ADR-0019）
- アダプタは Blender のデータの読み取りと表示だけを持ち、ロジックは Rust に置く。Scene IR を直接作る（glTF を経由しない。経由する場合は検証用の比較だけ）
- 画像は最初は CPU のバッファで渡す。GPU テクスチャの共有は First Clean Preview の計測で足りないと分かってから
- OIDN は CPU 版だけを同梱し、GPU 版は利用者が足す（ADR-0018）
- 開発機の Blender は 4.5.15 LTS（Python 3.11、numpy 1.26）と 5.2.3 LTS（Python 3.13、numpy 2.3）。numpy の主な版が違うので、`numpy` クレートは両方の ABI で動くことを項目 2 で確かめる
- 新しい依存は PyO3・maturin・`numpy` クレートまで（利用者が許可）。それ以外は追加のたびに確認する

## 要確認（利用者）

- 項目 13: 環境光だけの Toon の段の方針（案が複数あるため、M6 の最初に決める）
- Octane との比較は、この M6 の後に Blender 用の無料版で行う（M5 の持ち越し。REQ-ACC-002）

## 完了条件

- [ ] 実シーンを Blender で編集・プレビュー・Final 出力できる（REQ-DCC-001）
- [ ] 編集後の First Clean Preview を計測して記録した（REQ-DCC-002）
- [ ] Principled BSDF が変換でき、非対応ノードは警告して代替値になる（REQ-DCC-003）
- [ ] Stylization ノードを Blender 上で編集できる
- [ ] IES・ライトリンク・Cryptomatte・Shadow Catcher・UDIM が動く
- [ ] Blender 経由と glTF 経由の画像が閾値内で一致する
- [ ] 4.5 LTS と 5.x、Metal と Vulkan で動く
