# M2: Stylization と最小 Viewer（v0.1）

目標: 写実から Toon までを連続調整でき、AOV を分離出力する。
依存: M1。方針: ADR-0005 / 0008 / 0009。

| # | 項目 | REQ | 状態 |
|---|------|-----|------|
| 1 | Stylization 用 glTF 拡張のスキーマ確定（仕様書） | REQ-IO-002 | 未着手 |
| 2 | Material IR の 3 分離と `ShadingContext` | REQ-STY-008 | 済（`Base BSDF` / `Stylization Layers` / `Output Channels` の分離は M1 から。`ShadingContext`（光ごとの成分を保持）と `Revisions.stylization`、EXR の `verion/stylizationRevision` を追加。`ShadingContext` の Slang 側対応は項目 3 以降） |
| 3 | HybridSurface | REQ-STY-001 | 進行中（IR の `HybridSurface` と検証は済。GPU 評価は未着手） |
| 4 | ToonRamp・ShadowPalette | REQ-STY-002 / 003 | 進行中（`ToonRamp` の IR と検証は済。`ShadowPalette` と GPU 評価は未着手） |
| 5 | StylizedSpecular・RimLight | REQ-STY-004 / 005 | 未着手 |
| 6 | Lighting AOV の分離出力 | REQ-STY-006 | 進行中（一次ヒットの DirectDiffuse・IndirectDiffuse・Specular・Transmission・Emission・Visibility を分離し、`render-cli --lighting-aovs` で EXR に出力。5 成分の和はビューティと一致。間接光は最初のバウンスのローブ側に入れる。Normal・Depth・Object ID は M1 から出力済み。Material ID も出力済み。Motion Vector は M5 に送る） |
| 7 | Stylization Pass（一次ヒット Hybrid） | REQ-STY-007 | 進行中（`verion-stylization` クレートに、AOV から最終色を合成する Pass（デノイズ抜き）を追加。`HybridSurface.diffuse` で直接拡散を `ToonRamp` に寄せる部分のみ。他の成分は物理のまま。ramp の入力は光ごとの N·L でなく AOV 合計からの近似。CLI への接続は項目 1（glTF 拡張）待ち） |
| 8 | デノイズ（OIDN / MetalFX の選定を ADR に記録） | REQ-ACC-001 | 未着手 |
| 9 | Viewer の GUI 技術を決める | REQ-VIEW-002 | 未着手 |
| 10 | 最小 Viewer（累積・AOV 切替・パラメータ変更→再累積） | REQ-VIEW-002 | 未着手 |
| 11 | Stylization 評価の初期版（Art Direction 一致・デノイズによる消失） | REQ-QA-003 | 未着手 |

## 完了条件

- 同一シーンを写実から Toon まで連続調整できる
- デノイズが Toon 境界を消さない
- Reference モードが Stylization をバイパスする
