# 引き継ぎ: 画像アルファの切り抜き（M7 の A1〜A5）の Windows 確認

Mac（Metal）では A1〜A4 が済で、A5 は Vulkan の画像一致だけが残っている。状態の正本は `docs/implementation/M7-nrc-adaptive-integrator/README.md` の A の表。

## 変わったこと
- 材質に `opacity_texture`（画像の赤チャンネルが不透明度に掛かる）。`MATERIAL_WORDS` は 24。語 23 が `opacity_texture` + 1
- シェーダー: `opacityAt`（`pt_core.slang` と `aov.slang`）。1 次ヒットの素通し、影の光線、カバレッジ AOV に効く。SPIR-V は再生成してコミット済み（Mac で生成。`mise run shaders:check` は通る）
- glTF: ベースカラーのテクスチャの A を `BLEND`（不透明度）と `MASK`（しきい値で 0 か 1）に使う。灰色の画像を足す
- Blender: Principled の Alpha ← Image Texture の Alpha、Verion Surface の Opacity ← Verion Image の `Alpha` 出力
- `PARAM_WORDS` は MORT のスパイクのブランチ（`experiments/mort-spike`）で 50 にしているが、main は 43 のまま

## Windows でやること
1. `mise run check`、`shaders:check`、`mise run test:gpu`
2. `sh scripts/blender_test.sh`（Blender 4.5 と 5.2）。`test_materials.py` の `test_image_alpha_cuts_out_a_cube`、`test_nodes.py` の `test_image_alpha_feeds_opacity`、`test_consistency.py`（葉の板を足した）が通ること
3. Metal との画像一致（REQ-GPU-007）: `test_consistency.py` の `blender.exr` を Mac の値と並べる（Mac は平均の比 1.0000、ブロック相関 1.00000 で Blender 経由と glTF 経由が一致。Windows でも同じ値になるはず。Metal と Vulkan を直接比べるなら `scripts/backend_diff.sh`）
4. ベンチ: `scripts/bench.sh` または `render-cli` の `gpu_s` を、変更前（`dfef3d1`）と並べる。Mac の Metal では、アルファ付きテクスチャのないシーンで +2%（cornell_box 0.623 → 0.638 s、many_lights 0.701 → 0.715 s。512×384、128 spp）。Vulkan で同程度か確かめる。退行が大きければ、特殊化定数でテクスチャなしのコードを消す（M5 の `restirCompiled` と同じ。Metal の関数定数とピペラインのキャッシュ、Vulkan の特殊化定数を足す）
5. 結果を `docs/implementation/M6-blender/consistency.md` と M7 README の A5 に足し、完了条件の最初の項目を済にする
