# M5: 差分更新・IPR 編集と ReSTIR

目標: シーンの編集に追従する対話的プレビューを作り（差分更新エンジン、Viewer の IPR）、多光源のシーンで ReSTIR により同画質到達時間を縮める。
依存: M1〜M4（パストレーサ・Wavefront・Adaptive・2 つの Backend）。方針: ADR-0011 / 0014 / 0016 / 0017。

順序は差分更新を先にする。ReSTIR の履歴（Reservoir）は光源・材質・形状の変更で無効になるため、変更の種類を知る仕組みが先に要る。

| # | 項目 | REQ | 状態 |
|---|------|-----|------|
| 1 | Scene の変更追跡（`Changes`）。Camera / Material / Light / Transform / Mesh Deformation / 形状の追加を区別し、材質は物理（`base`）が変わったときだけ記録する | REQ-ACC-003 / REQ-CORE-001 | 済（`Scene::take_changes`。テストで種別ごとの記録を確認） |
| 2 | `pack` を表ごとの関数に分け、変更種別から更新範囲を決める計画（`UpdatePlan`）を `verion-gpu` に置く。`pack()` の出力は変えない | REQ-ACC-003 | 済（`pack_geometry`・`pack_emitters`・`pack_instances`・`pack_materials`・`pack_lights`、`UpdatePlan`） |
| 3 | `RayTracingBackend::update`。Metal: 材質・ライト・Emitter・Instance 表の差し替え、変形メッシュだけの BLAS 再構築、TLAS 再構築。形状の追加は表とAS を作り直すが、パイプラインは使い回す | REQ-ACC-003 | 済（`tests/update.rs`: 更新後の画像が完全再構築とビット一致。材質・ライトは BLAS / TLAS を作らず、Transform は TLAS だけ、変形は該当 BLAS と TLAS だけ） |
| 4 | Vulkan の `update`（同じ計画に従う） | REQ-ACC-003 / REQ-GPU-006 | Windows 待ち（Mac では Vulkan をビルドできないため、Windows 機で実装と確認を行う） |
| 5 | 検証: 更新後の画像が完全再構築と一致する。Cornell Box の壁の色を変えて反対側の面の間接光まで変わること（遠距離伝播）、更新で BLAS を作り直さないことを数える | REQ-ACC-003 | 未 |
| 6 | Viewer の IPR: 材質・ライト・Instance の移動の編集を `update` で反映し、First Clean Preview（編集から N spp まで）を計測して記録する | REQ-VIEW-003 | 未 |
| 7 | ReSTIR DI（Emitter 三角形と環境マップ）: 初期候補の RIS、Temporal / Spatial 再利用、最終シェードで可視性を再確認。鏡面・屈折・被写界深度・Lighting AOV では Fallback し、Reference では無効 | REQ-ACC-002 | 未 |
| 8 | ReSTIR DI の Vulkan 版（同じ Slang を使う） | REQ-ACC-002 / REQ-GPU-006 | Windows 待ち（Slang と共通のホスト側は Mac で済ませ、Vulkan のバインドと実機確認を Windows で行う） |
| 9 | 多光源の評価シーンと、同画質到達時間の実測（`scripts/eval_restir.sh`） | REQ-ACC-002 / REQ-PERF-001 | 未 |
| 10 | ReSTIR GI（1 回目の間接光）と検証サンプル | REQ-ACC-002 | 未 |
| 11 | ReSTIR PT の扱いの決定（ADR-0016 に記録） | REQ-ACC-002 | 未 |
| 12 | metrics に Reservoir の時間とメモリ、出力メタデータに ReSTIR の有効・非物理の印 | REQ-GPU-004 / REQ-CORE | 未 |

## 決めてあること

- 履歴は変更で無効にする（ADR-0017）。光源・材質・形状のどれかが変わったら Reservoir と蓄積を捨てる。キャッシュの永続は M7 の NRC で扱う
- ReSTIR は選択式で既定は無効。Reference モードは通らない（REQ-CORE）。再利用は偏りを持つので、有効なら出力に非物理の印を付ける
- BSDF サンプリングで Emitter に当たった寄与は、ReSTIR の画素では 0 とする（光源サンプルが全 Emitter を覆うため）。つや消し以上の面だけを対象にするのはこのため
- 変形メッシュの BLAS は再構築する（refit はしない）。形状の品質低下と実装の分岐を避ける

## 要確認（利用者）

- Octane との同画質到達時間の比較（環境は保留中）
- RTX 3080 機での Vulkan の実機確認（ReSTIR と `update`。この開発機は Mac のため、コンパイルと SPIR-V の生成までしか確認できない）

## 完了条件

- [ ] 変更種別ごとの再利用範囲が表のとおりに動く
- [ ] 間接光の遠距離伝播に対する検証サンプルがある
- [ ] Camera・Material・Light・Transform の変更に Viewer が追従する
- [ ] 同画質到達時間が改善することを実測する（多光源シーン）
- [ ] 鏡面・屈折・DoF では Fallback する
