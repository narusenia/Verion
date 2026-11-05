# ADR-0015: 画素単位の Adaptive Sampling を M3 に入れ、既定は無効にする

- 状態: 採用
- 日付: 2026-11-06

## 背景

M3 で Wavefront のキューができ、「次のサンプルをどの画素に割くか」をキューで選べるようになった。草案 `docs/drafts/adaptive_sampling_scheduler_plan.md` の Pixel / Tile レベルにあたる。M7 の REQ-ACC-006（領域ごとに PT / ReSTIR / NRC を選ぶ）とは別物で、どこにも計画されていなかった。M4 の Vulkan 比較の前に入れておけば、両 Backend で同じ仕組みを比べられる。

## 決定

- REQ-ACC-007 として M3 に入れる（ADR-0011 のロードマップに追記）
- 停止の判定: 画素ごとにサンプル数・輝度の和・輝度の二乗和を持つ。最小サンプル数（既定 16）に達し、平均の標準誤差が `閾値 × max(平均, 0.05)` 以下になったら止める。判定は `pt_core.slang` の `pixelActive` 1 か所に置き、CPU 側の `Adaptive::active` が同じ式でアクティブ画素数を数える
- 両方の積分器で動かす。Wavefront は `wf_select` がアクティブ画素だけを深さ 0 のキューに入れる。Megakernel は収束した画素のスレッドがすぐ戻る。画像は両者でビット一致する
- Megakernel は 1 スレッドが自分の画素のサンプルを最大 8 個続けて処理する（`SAMPLES_PER_DISPATCH`）。画素の和に触れるのはそのスレッドだけなので、1 サンプル 1 Dispatch と同じ画像になる。Dispatch の起動と、Dispatch ごとに最も遅いパスを待つ時間が 1/8 になり、一様サンプリングでも 7〜37% 速くなった（M3 README の表）
- 自分の推定値で止めるため推定が僅かに偏る。出力は非物理（`verion/physical = false`）とし、`verion/adaptiveThreshold` と画素ごとの `SampleCount` を EXR に書く
- 既定は無効。`render-cli --adaptive <閾値>`（`--spp` が上限）と Viewer の Render 欄で有効にする

## 比較

Apple M5、512×384、閾値 0.02、上限 2048 spp、参照 8192 spp。Adaptive と同じ GPU 時間の一様サンプリング（Megakernel）と比べた（`scripts/eval_adaptive.sh`）:

| シーン | Adaptive の平均 spp | 同時間の一様 spp | Adaptive mae/mean・PSNR | 一様 mae/mean・PSNR |
|---|---|---|---|---|
| cornell_box | 1180 | 1871 | 0.0205・57.6 dB | 0.0166・58.6 dB |
| showcase | 582 | 1235 | 0.0222・68.2 dB | 0.0214・66.0 dB |
| glass_compare | 542 | 1288 | 0.0357・58.4 dB | 0.0383・56.2 dB |

- 空や平らな面で早く止まる画素が多いシーン（showcase、glass_compare）は PSNR が 2.2 dB 上がる。難しさが画面全体で揃っている cornell_box は下がる
- 1 サンプルあたりの費用は一様の約 1.6〜2 倍。収束していない画素が SIMD 内に散らばり、止まった画素の分の計算が空くため。Wavefront のキューで詰めても、状態の読み書きの費用で相殺され、Megakernel より速くはならなかった（cornell_box で 5.76 s 対 5.27 s）

## 結果

- 既定を無効にするのは、シーンによっては同時間で悪くなるため。プレビューや、空・背景の多い画で使う
- 判定の改良（タイル単位の判定、分散の重みの見直し、時間で区切った配分）は草案に沿って M5 の同画質到達時間（REQ-PERF-005）と合わせて評価する
- M4 の Vulkan でも同じ `pixelActive` を使い、SER と組み合わせたときの費用を測る
