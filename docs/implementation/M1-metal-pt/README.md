# M1: Metal RT パストレーサー

目標: Metal 上で glTF の PBR シーンを描き、参照画像と一致させる。
依存: なし。方針: ADR-0001 / 0002 / 0003 / 0007。

| # | 項目 | REQ | 状態 |
|---|------|-----|------|
| 1 | Slang → MSL で Metal RT が動くスパイク（結論を ADR に記録） | REQ-GPU-002 | 進行中（ADR-0002 に暫定採用を記録。未検証点は ADR 参照） |
| 2 | workspace・mise・CI・deny の雛形、GPU CI の実行環境を決める | REQ-INFRA-001 / 002 / 003 | 済（CI は GPU 不要の検査のみ。GPU テストは開発機で実行） |
| 3 | Metal の Device / Queue / BLAS / TLAS | REQ-GPU-001 / 003 | 進行中（M5 で動作確認済み。別環境での確認が未了） |
| 4 | Scene IR と revision | REQ-CORE-001 | 済 |
| 5 | glTF 入力 | REQ-IO-001 | 進行中（BaseColor・MetallicRoughness・Emissive テクスチャは読める。Normal テクスチャ・spot ライトも対応済み。残りは未対応の拡張のみ） |
| 6 | BSDF・Integrator・テクスチャ・HDRI・ライト | REQ-CORE-002 / 003 / 004 | 進行中（HDRI の `.hdr` / `.exr` 読み込みは実装済み。Cornell Box・球 + 手続き生成 HDRI・Spot・法線マップは Mitsuba 3 照合済み。項目 12） |
| 7 | カラーマネジメント | REQ-CORE-005 | 進行中（作業色空間 Linear Rec.709 / ACEScg、glTF 取り込み時の入力変換、表示変換 = 目標色空間+Reinhard+sRGB OETF は実装済み。EXR 側の変換は項目 8 で接続） |
| 8 | EXR 多チャンネル出力 | REQ-IO-003 | 進行中（Beauty + Normal AOV、物理/非物理・spp・作業色空間のメタデータ、chromaticities、`exr` crate による書き出しは実装済み。外部ビューアでの目視確認は Beauty・Normal のみ済み。Albedo・Depth（カメラ前方軸の距離）・ObjectId（インスタンス番号 + 1、32bit 整数）は実装済みで目視確認は未） |
| 9 | render-cli | REQ-VIEW-001 | 未着手 |
| 10 | GPU 計測 | REQ-GPU-004 | 未着手 |
| 11 | Reference モード | REQ-CORE-006 | 未着手 |
| 12 | Mitsuba 3 照合・白炉テスト・テストシーン管理 | REQ-QA-001 / 002 / 004 | 進行中（Cornell Box（拡散・金属・ガラス・点光源・面光源）は `scripts/mitsuba_cornell.py` で照合済み。平均輝度の最悪チャンネル偏差 ±1% 以内で合格とし、実測は 0.19%。球 + 手続き生成 HDRI・Spot・法線マップ（最大傾き約 35°）も `scripts/mitsuba_cornell.py` のモード（`hdri` / `spot` / `normalmap`）で照合済み。最悪チャンネル偏差は 0.07% / 0.14% / 0.36%、4x4 ブロック平均の最悪は 0.19% / 1.89% / 1.39%。全シーンは開発機で `mise run crosscheck` が実行する（Metal GPU が要るため CI の対象外）。合否は平均輝度の最悪チャンネル 1% 以内かつ 4x4 ブロック平均 2% 以内で、PSNR は表示のみ（ノイズ支配のため）。実物の HDRI（外部アセットの選定後）・FLIP・白炉は未） |
| 13 | ベンチ基盤・ベースライン記録（規模下限の仮置きを見直す） | REQ-PERF-001 / 002 / 003 | 未着手 |

## 完了条件

- Cornell Box・金属・ガラス・HDRI が Mitsuba 3 照合の閾値内
- M4 Pro と M5 の両方でベースラインを記録

## 既知の制限（M1 の完了条件に入れない。Mitsuba 3 照合の結果を見て M2 以降で判断する）

- GGX は単一散乱のみ。粗さ 0.5 の白炉で最大 10% 暗くなる（多重散乱補正は未実装）
- ガラス越しの点光源・面光源の直接光は NEE で評価しない（屈折は BSDF サンプリングのみ）
- 閉じた誘電体メッシュは頂点の巻き方向（反時計回りが外側）で内外を判定する
- 法線 AOV（`render_normals`）は幾何法線のまま（本編のシェーディングは頂点法線・法線マップを使う）
- 法線マップの接線は三角形ごとの UV 微分から導出する（glTF の TANGENT 属性は読まない。MikkTSpace と差が出るメッシュがある）
- shading 法線が幾何面の裏へ曲げたサンプルは打ち切る（わずかなエネルギー損失）
- shading 法線は視線との内積が 0.05 以上になるよう視点側へ寄せる（法線マップで視点の反対へ曲がると、グレージング角でフレネルが 1 に近づき拡散が落ちるため）。0.05 は Mitsuba 3 との一致で確かめた値（0.01〜0.2 でも偏差 0.28〜0.46% で鈍感）。極端なグレージング角の BSDF 値は厳密ではない
- 発光は両面に放射する。発光テクスチャを持つ材質は面光源として NEE しない
- 環境マップは緯度経度の 1 枚のみ、最近傍サンプリング、回転なし。`.hdr` は自前パーサ（標準向き `-Y +X`・フラット/新 RLE のみ。旧 RLE と XYZE は非対応）、`.exr` は `exr` crate。`.hdr` は Rec.709 とみなし、`.exr` は chromaticities で ACEScg と Rec.709 を判別する
- 光線オフセットは 1e-4 固定（シーンのスケールに依存）
- 色空間は Linear Rec.709 と ACEScg の 2 つのみ。OCIO 連携、ACES RRT/ODT、Display P3 などは未対応（OCIO は同じ API の裏へ後から差し替える想定）
- シーン内の色はすべて作業色空間の値。glTF は取り込み時に変換するが、コードで直接作るシーン・sky・HDRI は呼び出し側が作業色空間の値を渡す。`Scene::set_working_space` は既存の色を変換しない
- ACEScg での描画は RGB 3 チャンネルの計算で、スペクトル計算とは結果が異なる。表示用トーンマップ（Reinhard）は物理ベースではなく、Reference の物理値は `OutputTransform::linear` で取り出す
- EXR 出力の AOV は Beauty・Normal・Albedo・Depth・ObjectId。Albedo・Depth・ObjectId は画素中心の 1 サンプルでアンチエイリアスしない（ID と深度を混ぜないため）。Albedo はベースカラー係数 × ベースカラーテクスチャ（レベル 0 のみ）で、発光・透過は反映しない。`exr` crate は `pulp` 経由で `paste`（メンテ終了、RUSTSEC-2024-0436）を引くため `deny.toml` で理由付きの例外にしている。`exr` 側の更新時に見直す
- GPU テストは M5 のみで確認。M4 Pro と、GPU を持たない CI 上でのスキップ以外の確認は未了
- 生成 MSL と `.slang` の一致は、ローカルの pre-commit（`mise run shaders:check`）でのみ検査する。CI は対象外
