# M5: 差分更新・IPR 編集と ReSTIR

目標: シーンの編集に追従する対話的プレビューを作り（差分更新エンジン、Viewer の IPR）、多光源のシーンで ReSTIR により同画質到達時間を縮める。
依存: M1〜M4（パストレーサ・Wavefront・Adaptive・2 つの Backend）。方針: ADR-0011 / 0014 / 0016 / 0017。

順序は差分更新を先にする。ReSTIR の履歴（Reservoir）は光源・材質・形状の変更で無効になるため、変更の種類を知る仕組みが先に要る。

| # | 項目 | REQ | 状態 |
|---|------|-----|------|
| 1 | Scene の変更追跡（`Changes`）。Camera / Material / Light / Transform / Mesh Deformation / 形状の追加を区別し、材質は物理（`base`）が変わったときだけ記録する | REQ-ACC-003 / REQ-CORE-001 | 済（`Scene::take_changes`。テストで種別ごとの記録を確認） |
| 2 | `pack` を表ごとの関数に分け、変更種別から更新範囲を決める計画（`UpdatePlan`）を `verion-gpu` に置く。`pack()` の出力は変えない | REQ-ACC-003 | 済（`pack_geometry`・`pack_emitters`・`pack_instances`・`pack_materials`・`pack_lights`、`UpdatePlan`） |
| 3 | `RayTracingBackend::update`。Metal: 材質・ライト・Emitter・Instance 表の差し替え、変形メッシュだけの BLAS 再構築、TLAS 再構築。形状の追加は表とAS を作り直すが、パイプラインは使い回す | REQ-ACC-003 | 済（`tests/update.rs`: 更新後の画像が完全再構築とビット一致。材質・ライトは BLAS / TLAS を作らず、Transform は TLAS だけ、変形は該当 BLAS と TLAS だけ） |
| 4 | Vulkan の `update`（同じ計画に従う） | REQ-ACC-003 / REQ-GPU-006 | 一部（`update` は `UpdatePlan` に従う差分更新で、材質・ライト・Emitter・Instance・変形・形状追加に対応。テストは Metal から移植（`tests/update.rs`）。型検査と clippy は Mac で cfg を外して通した。実機では未実行） |
| 5 | 検証: 更新後の画像が完全再構築と一致する。Cornell Box の壁の色を変えて反対側の面の間接光まで変わること（遠距離伝播）、更新で BLAS を作り直さないことを数える | REQ-ACC-003 | 済（`tests/update.rs`。壁の色を変えた更新と再構築の画像がビット一致し、編集していない面の画像が変わることも確かめる。BLAS と TLAS の再構築数は `UpdateReport` で数える） |
| 6 | Viewer の IPR: 材質・ライト・Instance の移動の編集を `update` で反映し、First Clean Preview（編集から N spp まで）を計測して記録する | REQ-VIEW-003 | 済（Viewer は `rebuild` をやめて `update` を呼び、Instances 欄で位置を動かせる。計測は下の表） |
| 7 | ReSTIR DI（Emitter 三角形）: 初期候補の RIS、前フレームの同じ画素と近傍の再利用、勝者の影を 1 本で確認。鏡面・屈折・被写界深度では Fallback し、Reference では使えない（環境マップは通常の光サンプリングのまま） | REQ-ACC-002 | 済（ADR-0016。`tests/restir.rs`: 通常の画像へ収束（平均 3% 以内）、両積分器でビット一致、鋭い面は ReSTIR の有無でビット一致。`render-cli --mode interactive`、Viewer のスイッチ） |
| 8 | ReSTIR DI の Vulkan 版（同じ Slang を使う） | REQ-ACC-002 / REQ-GPU-006 | 一部（バインディング 19 と Wavefront の 20〜25、Reservoir のバッファ、1 Dispatch 1 サンプル、設定の切替エラーを実装済み。型検査と clippy は Mac で通した。テストは `tests/restir.rs` に移植済みで、実機での実行は Windows 機） |
| 9 | 多光源の評価シーンと、同画質到達時間の実測（`scripts/eval_restir.sh`） | REQ-ACC-002 / REQ-PERF-001 | 済（`scenes/many_lights*.gltf`。結果は下の表と ADR-0016） |
| 10 | ReSTIR GI（1 回目の間接光） | REQ-ACC-002 | 済（ADR-0016。つなぎ替えと Jacobian、可視性の確認。テスト: 通常の画像へ収束、両積分器で一致、鋭い面は無変化。間接光が支配的な室内で同誤差まで 3〜5 倍） |
| 11 | ReSTIR PT の扱いの決定 | REQ-ACC-002 | 決定済（ADR-0016: M5 では入れず、M7 の NRC の測定と並べて判断。REQ-ACC-002 の書き換えは利用者の確認待ち） |
| 12 | metrics に Reservoir のメモリ、出力メタデータに ReSTIR の有効・非物理の印 | REQ-GPU-004 / REQ-CORE | 済（`restir_bytes`、EXR の `verion/restir`。Reservoir だけの時間は、シェードの中で処理されるため分離できず `gpu_s` に含まれる） |

## 差分更新の計測（2026-11-06、Apple M4 Pro、`update_bench`、512×384 の 4 spp）

`cargo run --release -p verion-gpu-metal --example update_bench -- シーン.gltf 4`

| シーン | 編集 | 更新 s | 作り直した BLAS / TLAS | 編集から 4 spp まで s | 全体の再構築 s |
|---|---|---|---|---|---|
| scale（500 万三角形・4K×4） | 材質 | 0.0000 | 0 / なし | 0.123 | 0.94 |
| | ライト | 0.0000 | 0 / なし | 0.001 | |
| | Transform | 0.0003 | 0 / あり | 0.002 | |
| | 変形（500 万三角形の 1 メッシュ） | 0.19 | 1 / あり | 0.003 | |
| showcase（5.5 万三角形） | 材質 | 0.0000 | 0 / なし | 0.014 | 0.014 |
| | 変形 | 0.0023 | 1 / あり | 0.010 | |

材質の更新は、参照する画像が変わらない限りミップ連鎖を作り直さない。最初の実装は 4K テクスチャを毎回作り直して 0.48 s かかっていた。

## 同画質到達時間（2026-11-06、Apple M4 Pro、512×384、参照 4096 spp）

`sh scripts/eval_restir.sh`。Reference の 128 spp の誤差（mae/mean）に届くまでの GPU 時間。

| シーン | Reference | ReSTIR DI のみ | DI + GI |
|---|---|---|---|
| many_lights（間接光が支配的） | 0.903 s | 0.932 s（0.97 倍） | 0.184 s（4.90 倍） |
| many_lights_dark（直接光が支配的） | 0.415 s | 0.225 s（1.84 倍） | 0.222 s（1.87 倍） |
| cornell_box（光源 1 枚） | 0.610 s | 0.822 s（0.74 倍） | 0.210 s（2.91 倍） |
| showcase（HDRI だけ） | 0.388 s | 0.411 s（0.94 倍） | 0.436 s（0.89 倍） |

高 spp では偏りと相関で誤差の下限が出る（ADR-0016）。ReSTIR は低 spp の速さのための機能で、最終品質は Reference で出す。

## 決めてあること

- 履歴は変更で無効にする（ADR-0017）。光源・材質・形状のどれかが変わったら Reservoir と蓄積を捨てる。キャッシュの永続は M7 の NRC で扱う
- ReSTIR は選択式で既定は無効（CLI は `--mode interactive` で DI と GI が有効）。Reference モードは通らない（REQ-CORE）。再利用は偏りを持つので、有効なら出力に非物理の印を付ける
- BSDF サンプリングで Emitter に当たる寄与は、光サンプリングの密度との Power Heuristic で重みを付けたまま残す（ADR-0016。外した版は外れ値が出た）
- 変形メッシュの BLAS は再構築する（refit はしない）。形状の品質低下と実装の分岐を避ける

## 要確認（利用者）

- Octane との同画質到達時間の比較（環境は保留中）
- RTX 3080 機での Vulkan の移植と実機確認（`update`、ReSTIR のバインディング。Mac では Vulkan のクレートをビルドできない。手順は `docs/handoff/2026-11-06-m5-windows.md`）
- Metal の画像が ReSTIR 無効時に変わっていないことは、既存の Metal テスト 48 件とベンチ（`mise run bench` が基準内）で確認済み

## 完了条件

- [x] 変更種別ごとの再利用範囲が表のとおりに動く（Metal。`UpdateReport` で数える）
- [x] 間接光の遠距離伝播に対する検証がある（壁の色の更新と再構築の画像がビット一致し、編集していない面が変わる。ADR-0017）
- [x] Camera・Material・Light・Transform の変更に Viewer が追従する
- [x] 同画質到達時間が改善することを実測する（上の表。多光源または間接光が支配的なシーンで 1.8〜4.9 倍）
- [x] 鏡面・屈折・DoF では Fallback する（テスト）
- [ ] Vulkan で同じことが動く（Windows 待ち）
