# 引き継ぎ: M6 の Windows（Vulkan）確認の結果と、Mac に残る作業

`2026-11-06-m6-device-checks.md` の Windows 側を終えた。状態の正本は `docs/implementation/M6-blender/README.md` の表（項目 7 は済、項目 16 は一部済）。

## Windows で確認できたこと

環境: RTX 3080（10 GB）、Blender 5.2.3 LTS と 4.5.7 LTS（`E:\apps\blender\stable`）。

- `mise run check`、`shaders:check`、`test:gpu` が通る
- `py_test.sh`（素の Python と両 Blender）、`blender_test.sh`（12 本、両 Blender）が通る。最後の `engine.py` の修正後は 5.2.3 だけで再実行した
- `package_blender.sh` が両 Blender で `SMOKE ok`（`windows-x64`）
- Blender 5.2.3 の GUI で、画像の表示、追従、色、編集への追従、Viewport Denoise（CUDA）、移動中の低解像度、リサイズ、ノードツリーを見て問題なし。4.5 LTS の GUI は見ていない

## Windows で直したこと（Mac にも効く）

- `engine.py`: Rendered → Solid → Rendered で止まる。`engine → viewport → report（engine._warn）→ engine` の循環参照で、古いエンジンの `__del__`（GPU の解放）が循環 GC まで遅れ、新しいエンジンが VRAM を確保できず `OutOfMemory` になった。report を `WeakMethod` にして解消した。1 ビューポートが約 4.2 GB を使うので、VRAM が小さい機ほど効く。Mac のユニファイドメモリでも、解放の遅れは同じ形で起きうる
- `viewport.py`: ジョブがエラーで終わっても黙って止まっていた。終了を見たら一度だけ `job.result()` を読み、`Verion: the viewport job stopped: ...` を報告する。止まったジョブの自動再起動はしていない
- `native.py`: Windows の Blender は OIDN を `blender.shared/OpenImageDenoise.dll` に置く。候補に足した
- `scripts/py_test.sh`: Windows の Blender は Git Bash の `/e/...` を読めない。`pwd -W` で作ったパスを使う
- `scripts/package_blender.sh`: `extension validate/build` に `--factory-startup` を足した。ユーザー設定の他のアドオン（Gscatter）が Blender 4.5 をクラッシュさせていた。Mac でも害はない

Mac で `blender_test.sh` と `package_blender.sh` を回して、上の変更で壊れていないことを確かめてほしい。

## Mac に残る作業

### 1. Metal との画像一致（項目 16 の残り、REQ-GPU-007）

`test_consistency.py` のシーンを Mac でも描き、Windows の `blender.exr` と並べる。

1. Windows 側の `blender.exr` は `%TEMP%\verion_consistency_*\blender.exr`（このディレクトリは `test_consistency.py` を走らせるたびに増える）。最新のものを Mac へ持っていくか、Mac で描いた `blender.exr` を Windows に持ってきて比べる
2. `verion.read_image` で読み、平均の比とブロック相関を出す（Mac 同士の値は平均の比 1.0000、相関 1.00000）
3. 目安は高 spp（256 以上）で平均の比 0.99〜1.01、ブロック相関 0.999 以上。超えたら値を見て決め直す
4. 結果は `docs/implementation/M6-blender/consistency.md` に足し、README の項目 16 と完了条件の最後の項目を「済」にする

注意: 画像を比べるときの spp は `test_consistency.py` の `SPP` で決まる。両機で同じ値にすること。

### 2. 任意

- Windows の 4.5 LTS の GUI は未確認。Mac の 4.5 LTS では確認済みなので、急がない
- Windows の GPU 版 OIDN（CUDA）は Viewport Denoise の GUI でしか見ていない。`--denoise-device` 相当を `render-cli` で見る手順は未整備

## VRAM の固定費を消した（Mac で確認が要る）

Windows で 1 ビューポートが約 4.2 GB の VRAM を使っていた。内訳は、Engine が約 0.4 GB、最初のジョブの固定費が約 3 GB（画像サイズ・シーン・積分器に依存しない）。原因は、BSDF の albedo 表（GGX・sheen・粗い誘電体、合計 5888 float）が Slang の `static const` 配列で、呼び出し箇所ごとにスレッドごとのローカル変数になっていたこと（SPIR-V の関数内変数が 245 KB）。NVIDIA のドライバは、スレッドごとのローカルメモリ × 同時に動くスレッド数を確保する（RTX 3080 で約 3 GB）。

直し方: 表を `lights` バッファのライト表の直後に置き、シェーダーは `albedoAt` で読む（バインディングも `params` の語数も増やさない）。`recvMask` / `emitMask` の位置は表の分だけずれる。表の元データは `crates/verion-gpu/tables/*.f32`、生成スクリプトは `scripts/gen_*_albedo.py` が `.f32` と定数だけの `.slang` を出す。

結果（Windows、Vulkan）: 最初のジョブの VRAM が約 3 GB → ほぼ 0。関数内変数は 245 KB → 3 KB。画像は変更前後でビット単位まで一致（megakernel と wavefront）。副産物として、変更前は `ERROR_DEVICE_LOST` で落ちた「多重散乱オン + 粗い透過材質」が描画できるようになった。`test:gpu` の所要時間も縮んだ（例: 18.5 s → 2.1 s。他の負荷の影響があり得る参考値）。

**Mac でやること**: MSL（`crates/verion-gpu-metal/shaders/*.metal`）は Windows で再生成してコミットしたが、Metal では動かしていない。`mise run check`、Metal のテスト、`blender_test.sh` を回し、画像が変わっていないこと（Metal の既存の基準との一致）を確かめてほしい。`mise run shaders:check` で SPIR-V の鮮度は見られる。

## 利用者の確認が要るもの

`2026-11-06-m6-device-checks.md` の「3. 利用者の確認が要るもの」から変わらない。
