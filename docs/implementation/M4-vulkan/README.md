# M4: Vulkan Backend と Backend 間の画像一致

目標: RTX 3080（Windows）で Metal と同じ画像を出す 2 つ目の Backend を作り、SER の効果と Octane との比較の基準値を測る。
依存: M1〜M3（パストレーサ・Lighting AOV・Wavefront・Adaptive Sampling）。方針: ADR-0001 / 0002 / 0010 / 0014 / 0015。

| # | 項目 | REQ | 状態 |
|---|------|-----|------|
| 1 | `verion-gpu` を作り、CLI と Viewer が使う面（シーンの読み込み、カメラと設定、Accumulation、AOV、メモリ）を `RayTracingBackend` として切り出す。Metal は実装を移すだけで、画像はビット一致のまま | REQ-GPU-003 | 済（`crates/verion-gpu`。trait は `RayTracingBackend` と `Accumulation`、共有型は `Integrator`・`Adaptive`・`Aovs`・`LightingAovs`・`MemoryUsage`。Context とエラーは Backend の関連型。切り出し前後で Stylized と Adaptive の画素が一致） |
| 2 | Slang → SPIR-V の生成と検査を `mise run shaders` / `shaders:check` に足す。MSL と同じく生成物をコミットし、ビルドに slangc を要らなくする | REQ-GPU-002 | 未着手 |
| 3 | `verion-gpu-vulkan`: Instance・Device・Queue と機能検出（ray query、acceleration structure、SER、timestamp）。必須機能がない環境は明示エラー、SER がなければ使わずに動く | REQ-GPU-006 / REQ-INFRA-006 | 未着手 |
| 4 | BLAS / TLAS の構築と、メッシュ・材質・ライト・テクスチャ・環境マップの転送 | REQ-GPU-006 | 未着手 |
| 5 | Megakernel（compute + ray query）、Accumulation、法線と Albedo / Depth / ID の AOV。Metal と同じ `pt_core.slang` を使う | REQ-GPU-006 | 未着手 |
| 6 | Wavefront と Adaptive Sampling。両形式の画像が Vulkan の中でビット一致する | REQ-GPU-005 / REQ-ACC-007 | 未着手 |
| 7 | Lighting AOV と Stylized。Stylization Pass は CPU 側の共通コードをそのまま使う | REQ-STY-006 / 007 | 未着手 |
| 8 | CLI と Viewer の Backend 選択と Windows ビルド（`--backend metal\|vulkan`、既定は OS で決める） | REQ-GPU-003 / REQ-VIEW | 未着手 |
| 9 | Backend 間の画像比較スクリプトと閾値の決定（初回実測で決め、REQ-GPU-007 に記録）。Beauty と Stylization AOV の両方を比べる | REQ-GPU-007 / REQ-QA-003 | 未着手 |
| 10 | SER: レイトレーシングパイプライン版の Megakernel（raygen で `HitObject` と材質による `ReorderThread`）を作り、compute + ray query 版と比べる。結果で ADR-0014 を見直す | REQ-GPU-006 / REQ-GPU-005 | 未着手 |
| 11 | GPU 計測（timestamp query）とメモリのメトリクスを Metal と同じ metrics 項目で出す | REQ-GPU-004 / REQ-PERF-006 | 未着手 |
| 12 | RTX 3080 のベンチ基準（`benchmarks/baseline/`）と退行ゲート | REQ-PERF-001 / 002 | 未着手 |
| 13 | Windows での OIDN（DLL の探索。CUDA デバイスが使えるなら比較） | REQ-ACC-001 | 未着手 |
| 14 | Octane 比較の基準値: 比較条件（ハードウェア・解像度・シーン・画質の合わせ方・デノイズ）を決めて記録する | REQ-PERF-004 | 未着手 |
| 15 | CI に Windows のビルドとテスト（GPU 不要の範囲）を足す | REQ-INFRA-002 | 未着手 |

## 決めてあること

- Vulkan のバインディングは `ash`（MIT / Apache-2.0）を第一候補にする。メモリ割り当ては、必要になった時点で自前か `gpu-allocator`（MIT / Apache-2.0）かを決める。どちらも導入時に `mise run deny` で確かめる
- macOS では Vulkan Backend をビルドしない。MoltenVK はレイトレーシングに対応しない（ADR-0001）ので、Mac での実行確認は対象外
- Metal と Vulkan は浮動小数点の演算順や交差判定の精度が違うので、ビット一致は求めない。比較は高 spp の画像どうしで、M1 の Mitsuba 照合と同じ方式（`exr_diff` のチャンネル平均と 4×4 ブロック）から始める
- SER は compute + ray query では使えず、レイトレーシングパイプラインの raygen シェーダーが要る。まず compute 版で画像一致を取り、SER 版はその後に別のエントリとして足す
- 速度の目標は置かない（ADR-0014）。RTX 3080 の基準値は退行ゲートと M5 の同画質到達時間の比較に使う

## 未決（実装中に決める）

- パラメータブロック（36 語）の渡し方: push constant か、Dispatch ごとのバッファか
- Slang のバインド番号と Vulkan の descriptor set の対応（Metal は宣言順の `[[buffer(n)]]`）
- Wavefront の間接 Dispatch とキューを、Vulkan のバリアでどう区切るか

## 要確認（利用者）

- Octane の利用環境（ライセンスと、比較用シーンを Octane 側で組む手段）。項目 14 の前に確認する
- 実装と GPU テストは RTX 3080 の Windows 機で行う。その機材での作業の進め方（この会話の Mac からはビルド確認まで）
- Verion のライセンス判断（ADR-0004 は「M4 前後、NVIDIA SDK 等の条件確認後」）。M4 で NVIDIA SDK を使わない場合も含めて、判断の時期

## 完了条件

- [ ] 同じシーンで Metal と Vulkan が描画でき、画像が決めた閾値内で一致する（Beauty と Stylization AOV）
- [ ] 非対応の拡張（SER など）がない環境でも Fallback で動く
- [ ] SER の有無による速度を測り、ADR に記録する
- [ ] RTX 3080 のベンチ基準と、Octane 比較の条件を記録する
