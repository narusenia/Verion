# M1: Metal RT パストレーサー

目標: Metal 上で glTF の PBR シーンを描き、参照画像と一致させる。
依存: なし。方針: ADR-0001 / 0002 / 0003 / 0007。

| # | 項目 | REQ | 状態 |
|---|------|-----|------|
| 1 | Slang → MSL で Metal RT が動くスパイク（結論を ADR に記録） | REQ-GPU-002 | 進行中（ADR-0002 に暫定採用を記録。未検証点は ADR 参照） |
| 2 | workspace・mise・CI・deny の雛形、GPU CI の実行環境を決める | REQ-INFRA-001 / 002 / 003 | 済（CI は GPU 不要の検査のみ。GPU テストは開発機で実行） |
| 3 | Metal の Device / Queue / BLAS / TLAS | REQ-GPU-001 / 003 | 進行中（M5 で動作確認済み。別環境での確認が未了） |
| 4 | Scene IR と revision | REQ-CORE-001 | 済 |
| 5 | glTF 入力 | REQ-IO-001 | 進行中（BaseColor・MetallicRoughness・Emissive テクスチャは読める。Normal テクスチャと spot ライトは未対応） |
| 6 | BSDF・Integrator・テクスチャ・HDRI・ライト | REQ-CORE-002 / 003 / 004 | 進行中（Normal マップ・HDRI ファイル読み込み・Spot ライトが未実装。Mitsuba 3 照合は項目 12） |
| 7 | カラーマネジメント | REQ-CORE-005 | 未着手 |
| 8 | EXR 多チャンネル出力 | REQ-IO-003 | 未着手 |
| 9 | render-cli | REQ-VIEW-001 | 未着手 |
| 10 | GPU 計測 | REQ-GPU-004 | 未着手 |
| 11 | Reference モード | REQ-CORE-006 | 未着手 |
| 12 | Mitsuba 3 照合・白炉テスト・テストシーン管理 | REQ-QA-001 / 002 / 004 | 未着手 |
| 13 | ベンチ基盤・ベースライン記録（規模下限の仮置きを見直す） | REQ-PERF-001 / 002 / 003 | 未着手 |

## 完了条件

- Cornell Box・金属・ガラス・HDRI が Mitsuba 3 照合の閾値内
- M4 Pro と M5 の両方でベースラインを記録

## 既知の制限（M1 の完了条件に入れない。Mitsuba 3 照合の結果を見て M2 以降で判断する）

- GGX は単一散乱のみ。粗さ 0.5 の白炉で最大 10% 暗くなる（多重散乱補正は未実装）
- ガラス越しの点光源・面光源の直接光は NEE で評価しない（屈折は BSDF サンプリングのみ）
- 閉じた誘電体メッシュは頂点の巻き方向（反時計回りが外側）で内外を判定する
- 頂点法線による滑らかなシェーディングは未実装（幾何法線のみ。球の映り込みが多角形に見える）
- 発光は両面に放射する。発光テクスチャを持つ材質は面光源として NEE しない
- 環境マップは緯度経度の 1 枚のみ、最近傍サンプリング、回転なし。`.hdr` / `.exr` の読み込みは項目 8 の EXR 実装と同時に依存を決める
- 光線オフセットは 1e-4 固定（シーンのスケールに依存）
- GPU テストは M5 のみで確認。M4 Pro と、GPU を持たない CI 上でのスキップ以外の確認は未了
- 生成 MSL と `.slang` の一致は、ローカルの pre-commit（`mise run shaders:check`）でのみ検査する。CI は対象外
