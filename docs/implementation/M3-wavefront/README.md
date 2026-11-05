# M3: Wavefront と Queue Compaction

目標: Megakernel と同じ画像を出す Wavefront 形式を作り、速度を比べて採否を決める。
依存: M1（パストレーサ）・M2（Lighting AOV）。方針: ADR-0010 / 0014。

| # | 項目 | REQ | 状態 |
|---|------|-----|------|
| 1 | パスの処理を関数に分ける（生成・最近接交差・シェード・終了）。Megakernel と Wavefront が同じコードと同じ乱数列を使う | REQ-GPU-005 | 済（`shaders/include/pt_core.slang`。Megakernel は組み替え前とビット一致し、速度も変わらない（旧版と交互に計測して差なし）） |
| 2 | Path State の SoA とキュー | REQ-GPU-005 | 済（`shaders/include/wf_state.slang`。1 パス 16 語（Lighting AOV ありは 33 語）。深さ 0 は状態を持たず、各段がカメラ光線を画素から作り直す（書いて読むより安い）。1024×768 で約 69 MB） |
| 3 | Queue Compaction と間接 Dispatch | REQ-GPU-005 | 済（shade が生き残ったパスを atomic で次の深さのキューへ詰める。`wf_args` がキューの長さから dispatch の大きさを GPU 上で決めるので、深さの間に CPU は待たない。SIMD 単位で atomic をまとめる案は速度が変わらず採らなかった） |
| 4 | 画質の一致 | REQ-GPU-005 | 済（全シーンで Megakernel とビット一致（`exr_diff` で PSNR ∞）。Lighting AOV と Stylized も一致） |
| 5 | シーン規模別の速度比較 | REQ-GPU-005 | 済（`scripts/bench_integrators.sh`。下の表） |
| 6 | trace / shade の時間の分離 | REQ-GPU-004 | 済（`render-cli --integrator wavefront --stage-timing` で metrics に `extend_s`・`shade_s`。段ごとに command buffer を分けて測るので合計は 1 割ほど遅くなる） |
| 7 | Memory Budget の使用量メトリクス | REQ-PERF-006 | 済（手順 2。`MetalContext::memory()` と metrics の `gpu_budget_bytes`・`gpu_peak_bytes`・`upload_bytes`・`wavefront_bytes`。挙動は変えない。ピークは段の境目で測った最大値） |
| 8 | 採否の決定 | REQ-GPU-005 | 済（ADR-0014: Metal の既定は Megakernel のまま。Wavefront は選択肢として残し、M4 の Vulkan（SER）と M5 以降の段の分離で再評価） |
| 9 | Viewer と CLI からの切替 | （補助） | 済（`render-cli --integrator`、Viewer の Render 欄の「integrator」） |
| 10 | 画素単位の Adaptive Sampling | REQ-ACC-007 | 済（ADR-0015。判定は `pt_core.slang` の `pixelActive`。Wavefront は `wf_select` で深さ 0 のキューを作り、Megakernel は収束した画素で戻る。両者ビット一致。`render-cli --adaptive`、EXR の `SampleCount`、Viewer の Render 欄と Samples ビュー） |
| 11 | 一様サンプリングとの等時間比較 | REQ-ACC-007 | 済（`scripts/eval_adaptive.sh`。空の多いシーンで PSNR +2.2 dB、一様な cornell_box では −1.0 dB。既定は無効） |
| 12 | Megakernel の 1 スレッド複数サンプル | REQ-GPU-005 | 済（最大 8 サンプルを続けて処理。画像は変わらず 7〜37% 速い。下の表の再計測） |

## 速度比較（2026-11-06、Apple M5、AC 電源、1024×768、256 spp、3 回の最小値）

| シーン | 三角形 | 光 | Megakernel s | Wavefront s | 比 |
|---|---|---|---|---|---|
| cube | 14 | 一様な空 | 0.173 | 0.294 | 1.70 |
| cornell_box | 18,444 | 面光源 | 2.931 | 3.577 | 1.22 |
| showcase | 55,298 | sunny HDRI | 2.003 | 2.304 | 1.15 |
| glass_compare | 55,298 | sunny HDRI | 2.518 | 2.835 | 1.13 |
| toon_compare（Stylized） | 55,298 | sunny HDRI | 2.498 | 3.907 | 1.56 |
| scale | 5,000,002 | 一様な空 | 0.226 | 0.364 | 1.61 |

再計測（2026-11-06、項目 12 の後、2 回の最小値）:

| シーン | Megakernel s | Wavefront s | 比 |
|---|---|---|---|
| cube | 0.110 | 0.298 | 2.71 |
| cornell_box | 2.708 | 3.688 | 1.36 |
| showcase | 1.836 | 2.386 | 1.30 |
| glass_compare | 2.266 | 2.827 | 1.25 |
| toon_compare（Stylized） | 2.046 | 3.722 | 1.82 |
| scale | 0.142 | 0.332 | 2.34 |

- 段の内訳（64 spp）: showcase は extend 0.18 s・shade 0.48 s、scale は extend 0.05 s・shade 0.06 s
- 差はパス状態の読み書き（メモリ帯域）で、解像度に比例する（cube で 256 幅 1.5 倍、2048 幅 4.2 倍だったものが、深さ 0 の状態を省いて 1.7 倍まで縮んだ）。バウンスが多く 1 パスの計算が重いシーンほど差が小さい
- Lighting AOV を持つと状態が倍になり、差が広がる（toon_compare）

## 完了条件

- [x] Megakernel との速度比較（上の表。採否は ADR-0014）
- [x] 画素単位の Adaptive Sampling と一様サンプリングとの等時間比較（ADR-0015）
