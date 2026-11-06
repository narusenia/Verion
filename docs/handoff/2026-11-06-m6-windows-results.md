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

## 利用者の確認が要るもの

`2026-11-06-m6-device-checks.md` の「3. 利用者の確認が要るもの」から変わらない。

追加で 1 件: 1 ビューポートの VRAM が約 4.2 GB（1280×720 の `test_scene.blend`、Vulkan）と大きい。内訳は未調査。VRAM が 10 GB の機では、ブラウザなど他のアプリが使っていると、エンジンが 1 つでも足りなくなることがある。バッファの内訳を調べて削れるか見るかどうかを決めてほしい。
