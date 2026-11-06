# M4: Vulkan Backend と Backend 間の画像一致

目標: RTX 3080（Windows）で Metal と同じ画像を出す 2 つ目の Backend を作り、SER の効果と Octane との比較の基準値を測る。
依存: M1〜M3（パストレーサ・Lighting AOV・Wavefront・Adaptive Sampling）。方針: ADR-0001 / 0002 / 0010 / 0014 / 0015。

| # | 項目 | REQ | 状態 |
|---|------|-----|------|
| 1 | `verion-gpu` を作り、CLI と Viewer が使う面（シーンの読み込み、カメラと設定、Accumulation、AOV、メモリ）を `RayTracingBackend` として切り出す。Metal は実装を移すだけで、画像はビット一致のまま | REQ-GPU-003 | 済（`crates/verion-gpu`。trait は `RayTracingBackend` と `Accumulation`、共有型は `Integrator`・`Adaptive`・`Aovs`・`LightingAovs`・`MemoryUsage`。Context とエラーは Backend の関連型。切り出し前後で Stylized と Adaptive の画素が一致） |
| 2 | Slang → SPIR-V の生成と検査を `mise run shaders` / `shaders:check` に足す。MSL と同じく生成物をコミットし、ビルドに slangc を要らなくする | REQ-GPU-002 | 済（`crates/verion-gpu-vulkan/shaders/*.spv`。SPIR-V 1.5 + ray query に固定し、slangc がコンパイル時に検証する。クレートは今は SPIR-V を埋め込むだけで、形式と全シェーダーの揃いをテストする） |
| 3 | `verion-gpu-vulkan`: Instance・Device・Queue と機能検出（ray query、acceleration structure、SER、timestamp）。必須機能がない環境は明示エラー、SER がなければ使わずに動く | REQ-GPU-006 / REQ-INFRA-006 | 済（`context.rs`。ray query・acceleration structure・bufferDeviceAddress が必須で、足りなければ `Error::Unsupported` が名前を挙げる。SER・timestamp・`VK_EXT_memory_budget` は任意。RTX 3080 は Vulkan 1.4.351、ドライバ 616.92、ray query / AS / EXT 版 SER に対応。ただし SER の reorder hint は `NONE`（Ampere は並べ替えない）） |
| 4 | BLAS / TLAS の構築と、メッシュ・材質・ライト・テクスチャ・環境マップの転送 | REQ-GPU-006 | 済（`accel.rs`・`buffer.rs`。BLAS はシェーダーも読む連結済みの頂点・インデックス表を直接入力にして、ジオメトリを GPU に 1 つだけ持つ。転送は 1 回の submit にまとめる。メモリは `gpu-allocator`。BLAS の圧縮はしない） |
| 5 | Megakernel（compute + ray query）、Accumulation、法線と Albedo / Depth / ID の AOV。Metal と同じ `pt_core.slang` を使う | REQ-GPU-006 | 済（`renderer.rs`。パラメータブロックは Dispatch ごとの領域を持つストレージバッファに置き、dynamic offset で渡す。1 回の `accumulate` は 1 回の submit。descriptor のレイアウトは SPIR-V の反射（`reflect.rs`）から作る） |
| 6 | Wavefront と Adaptive Sampling。両形式の画像が Vulkan の中でビット一致する | REQ-GPU-005 / REQ-ACC-007 | 済（`renderer/wavefront.rs`。`tests/gpu.rs` が Beauty・Lighting AOV・Adaptive の画素数と平均をビットで比べる。バリアは Dispatch ごとの全体メモリバリアで、間接 Dispatch の引数も同じバリアで区切る） |
| 7 | Lighting AOV と Stylized。Stylization Pass は CPU 側の共通コードをそのまま使う | REQ-STY-006 / 007 | 済（`render-cli --mode stylized` が Vulkan で動き、トーンの帯と輪郭線が出る） |
| 8 | CLI と Viewer の Backend 選択と Windows ビルド（`--backend metal\|vulkan`、既定は OS で決める） | REQ-GPU-003 / REQ-VIEW | 済（CLI は `--backend` と、Backend に対してジェネリックな `run_with`。Viewer は OS ごとに型を切り替える。OS ごとに 1 つしかビルドしないので Viewer に実行時の切替は置かない。Viewer は Windows で起動して動き続けるところまで確認した） |
| 9 | Backend 間の画像比較スクリプトと閾値の決定（初回実測で決め、REQ-GPU-007 に記録）。Beauty と Stylization AOV の両方を比べる | REQ-GPU-007 / REQ-QA-003 | 済（`scripts/backend_render.sh` が各機で同じ画像セットを描き、`scripts/backend_diff.sh` が `exr_diff` で比べる。Stylization AOV は Stylized の出力で比べる。初回実測は Mac M4 Pro の Metal と RTX 3080 の Vulkan、4096 spp、5 枚すべて PASS で、最悪値はチャンネル平均 0.05%・4×4 ブロック 0.34%（`showcase_stylized`）。閾値はチャンネル平均 0.1%、ブロック 0.5% とし、REQ-GPU-007 に記録した） |
| 10 | SER: レイトレーシングパイプライン版の Megakernel（raygen で `HitObject` と材質による `ReorderThread`）を作り、compute + ray query 版と比べる。結果で ADR-0014 を見直す | REQ-GPU-006 / REQ-GPU-005 | 見送り（実装はブランチ `experiment/ser-raygen`。RTX 3080 はそもそも reorder hint が `NONE` で効果が出ない。raygen 版は NEE を含めると 616.92 ドライバで TDR になる。詳細は ADR-0014 の追記） |
| 11 | GPU 計測（timestamp query）とメモリのメトリクスを Metal と同じ metrics 項目で出す | REQ-GPU-004 / REQ-PERF-006 | 済（`accumulate` ごとの timestamp。Wavefront の段別は Dispatch ごとの timestamp 対。メモリは `VK_EXT_memory_budget`、なければ自前の集計。`--metrics` の項目は Metal と同じで `backend` を足した） |
| 12 | RTX 3080 のベンチ基準（`benchmarks/baseline/`）と退行ゲート | REQ-PERF-001 / 002 | 済（`benchmarks/baseline/nvidia-geforce-rtx-3080-ac.json`: cube 0.0506 s、scale 0.0923 s。M5 の同条件は 0.335 s と 0.402 s。`mise run bench` が 10% の退行ゲート） |
| 13 | Windows での OIDN（DLL の探索。CUDA デバイスが使えるなら比較） | REQ-ACC-001 | 済（OIDN 2.5.1 の Windows zip で確認。Cornell 16 spp のデノイズは CPU 0.34 s、CUDA 0.15 s、画質は同じ。`--denoise-device cpu\|cuda`。GPU デバイスにはホスト画像を直接渡せないので OIDN バッファ経由。DLL は `VERION_OIDN_LIB` で指定する） |
| 14 | Octane 比較の基準値: 比較条件（ハードウェア・解像度・シーン・画質の合わせ方・デノイズ）を決めて記録する | REQ-PERF-004 | 条件は記録済（下の「Octane 比較の条件」）。Octane の環境は利用者が後で用意する（保留） |
| 15 | CI に Windows のビルドとテスト（GPU 不要の範囲）を足す | REQ-INFRA-002 | 済（M4 以前から `ci.yml` が `windows-latest` で `mise run check` を通している。Vulkan の依存を足したら同じ CI で確かめる） |

## 決めてあること

- Slang のバインド番号は SPIR-V でもそのまま使われ、descriptor set 0 の binding が Metal の buffer index と同じ番号になる（項目 2 で確認）。エントリポイント名は `main`

- Vulkan のバインディングは `ash`（MIT / Apache-2.0）を第一候補にする。メモリ割り当ては、必要になった時点で自前か `gpu-allocator`（MIT / Apache-2.0）かを決める。どちらも導入時に `mise run deny` で確かめる
- macOS では Vulkan Backend をビルドしない。MoltenVK はレイトレーシングに対応しない（ADR-0001）ので、Mac での実行確認は対象外
- Metal と Vulkan は浮動小数点の演算順や交差判定の精度が違うので、ビット一致は求めない。比較は高 spp の画像どうしで、M1 の Mitsuba 照合と同じ方式（`exr_diff` のチャンネル平均と 4×4 ブロック）から始める
- SER は compute + ray query では使えず、レイトレーシングパイプラインの raygen シェーダーが要る。まず compute 版で画像一致を取り、SER 版はその後に別のエントリとして足す
- 速度の目標は置かない（ADR-0014）。RTX 3080 の基準値は退行ゲートと M5 の同画質到達時間の比較に使う

## 実装で決めたこと

- パラメータブロック（36 語）は、1 回の `accumulate` が使う Dispatch 分を並べたストレージバッファに置き、dynamic offset で選ぶ。push constant にすると Backend ごとにシェーダーを分けることになる
- Wavefront は Dispatch ごとに全体メモリバリア（compute と間接引数の読み出しと転送）を入れる。キューは深さの偶奇で 2 本を入れ替え、`wf_select` は深さ 0 の入力キューへ書く
- メモリ割り当ては `gpu-allocator`（MIT / Apache-2.0、`deny` 通過）。1 バッファ 1 割り当てだと割り当て数の上限とページの無駄が出て、メッシュの多いシーンで困るため
- `scripts/shaders.sh check` は SPIR-V をバイト比較しない。slangc の出力は同じ機械なら決定的だが、macOS と Windows で定数の並びが違う。SPIR-V の古さは Slang ソースのチェックサム（`sources.cksum`、改行を無視）で見て、MSL はこれまでどおりバイト比較する
- ホスト側のシーン整形（頂点・材質・ライト・環境マップ・パラメータ・読み戻し）は `verion-gpu`（`pack`・`readback`・`wavefront`）に出し、Metal と Vulkan が同じバイト列を使う。Metal 側の置き換えは CI の macOS（`mise run check`）でコンパイル・clippy・テストが通ることを確認した。Metal の画像が変わっていないことの実機確認は Mac で行う

## 未決

- Backend 間の画像一致の閾値（項目 9）: Metal の参照セットを Mac で作ってから、初回実測で決める
- SER の再評価: Ada 以降の GPU（reorder hint が `NONE` でないもの）と、raygen のハングが直ったドライバで、ブランチ `experiment/ser-raygen` から再開する

## Octane 比較の条件（項目 14）

- 機材: 同じ Windows 機（RTX 3080、ドライバ 616.92）。Octane は CUDA / RTX で動かす
- シーン: `scenes/cornell_box.gltf` と `scenes/showcase.gltf`（Reference）。カメラ・光源・HDRI を Octane 側で同じに組む。材質は Principled 相当への対応表を作って記録する
- 設定: 1024×768、最大 8 バウンス、環境光とトーンマップなしの線形出力、デノイズなし
- 画質の合わせ方: 16384 spp 以上の自分の画像を基準に、平均絶対誤差（`exr_diff` の mae/mean）が同じになるまでの時間で比べる。M4 では 1 spp あたりの GPU 時間（`gpu_s`）だけを記録し、同画質到達時間は M5 で出す
- デノイズ: オフの比較を主にし、オン（Verion は OIDN、Octane は AI Denoiser）は別表にする
- 計測: Verion は `--metrics` の `gpu_s`、Octane は自身のログの描画時間。ウォームアップを 1 回捨てて 5 回の最小値を取る（`scripts/bench.sh` と同じ）

## 要確認（利用者）

- Octane の利用環境（保留）: まだ課金していない。利用者が C4D / Blender + Octane の環境を用意してから、上の条件で比較を始める
- Verion のライセンス判断（ADR-0004 は「M4 前後、NVIDIA SDK 等の条件確認後」）。M4 では NVIDIA SDK を使っていない（OIDN の CUDA モジュールは OIDN の DLL に含まれる）ので、判断の時期だけが残る
- OIDN の DLL の配布方法（Windows 向けに同梱するか、利用者に置いてもらうか）
- Mac での確認: Metal の参照画像セットの作成（項目 9）と、置き換え前後で Metal の画像が変わっていないことの確認

## 完了条件

- [ ] 同じシーンで Metal と Vulkan が描画でき、画像が決めた閾値内で一致する（Beauty と Stylization AOV）。Vulkan 側は完了、Metal の参照セットと閾値の決定が Mac 待ち
- [x] 非対応の拡張（SER など）がない環境でも Fallback で動く（SER は任意で、既定で使わない）
- [x] SER の有無による速度を測り、ADR に記録する（RTX 3080 では効果が出ないことと raygen 版のハングを ADR-0014 に記録）
- [x] RTX 3080 のベンチ基準と、Octane 比較の条件を記録する（Octane の環境確認は残る）
