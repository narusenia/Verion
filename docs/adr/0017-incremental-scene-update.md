# ADR-0017: シーンの差分更新は変更の種類で決め、履歴は編集で捨てる

- 状態: 採用
- 日付: 2026-11-06

## 背景

M5 の IPR（REQ-VIEW-003）と差分更新エンジン（REQ-ACC-003）。M2 までの Viewer は、材質やライトを 1 つ編集するたびに Backend を作り直していた（BLAS・TLAS・全テーブル・シェーダーのコンパイル）。

## 決定

- **変更の記録は Scene が持つ**。`Scene::take_changes` が、前回の呼び出し以降の変更を `Changes`（形状の追加、変形したメッシュ、Transform か材質が変わった Instance、物理が変わった材質、ライト、カメラ）で返す。消費者は 1 つ。revision カウンタは、比べるだけの利用者のために残す
- 材質は `base`（物理）が変わったときだけ記録する。Stylization レイヤーは GPU のデータではない（後段のパス）ので、再蓄積も要らない
- メッシュの変形は、三角形（インデックス）と頂点数が同じで頂点データだけが変わったものを指す。それ以外のメッシュの変更は形状の変更として全体を作り直す
- **更新範囲の表は `verion-gpu::pack::UpdatePlan` に 1 か所だけ置く**（テスト付き）。Backend はこの計画に従う:

| 変更 | 再利用 | 更新 |
|---|---|---|
| Camera | すべて | ビュー |
| Material | BLAS・TLAS・頂点表 | 材質表、Emitter、Instance 表（画像が変わったときだけテクスチャ表） |
| Light | BLAS・TLAS・各表 | ライト表、空、環境マップ（画像と倍率が変わったときだけ） |
| Instance の Transform | すべての BLAS | Instance 表、TLAS、Emitter |
| Mesh Deformation | 他のすべての BLAS | 頂点表（その範囲だけ書き換え）、その BLAS、TLAS、Emitter |
| 形状の追加 | パイプライン | それ以外すべて |
| Resolution | Scene と AS | Accumulation（Scene の更新ではない） |

- 変形した BLAS は refit せず作り直す。品質の低下と分岐を避けるため
- **履歴は編集で捨てる**。更新のあとは新しい蓄積を始める。ReSTIR の Reservoir は蓄積と同じ寿命なので、同時に空になる。間接光は遠くまで伝わるので、局所のキャッシュだけを無効にしても正確にならない。永続するキャッシュ（NRC）は M7 で、Version・Confidence・検証サンプルと合わせて扱う
- **検証**は「更新後の画像が、編集後のシーンから作り直した Renderer の画像とビット一致する」こと（`tests/update.rs`）。壁の色を変えたとき、編集していない面の画像（遠距離の間接光）が変わることも確かめる。BLAS と TLAS を作り直した数は `UpdateReport` で数える

## 測定

Apple M4 Pro（`update_bench`）。500 万三角形の scale シーンで全体の再構築は 0.94 s。更新は材質・ライトでほぼ 0（最初の実装は 4K テクスチャのミップを毎回作り直して 0.48 s かかった）、Transform は 0.3 ms、1 メッシュの変形は 0.19 s（BLAS の再構築）。

## 結果

- Viewer は `rebuild` をやめて `update` を呼ぶ。Instances 欄で位置を動かせる
- Vulkan の `update` は Windows 機で、同じ `UpdatePlan` に従って実装する
