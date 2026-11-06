# 引き継ぎ: M4 Vulkan を Windows 機で終えた

前の引き継ぎ（`2026-11-06-m4-windows-start.md`）の続き。M4 の項目 3〜8・11〜13・15 を RTX 3080 の Windows 機で終えた。状態は `docs/implementation/M4-vulkan/README.md` の表が正本。

## できたこと
- `verion-gpu-vulkan`: ash + gpu-allocator。Megakernel・Wavefront・Adaptive・Lighting AOV・法線と AOV。Wavefront は Megakernel とビット一致（`mise run test:gpu`）
- ホスト側のシーン整形・パラメータ・読み戻しを `verion-gpu`（`pack`・`readback`・`wavefront`）に出した。Metal もこれを使う形に置き換えた（Mac で未検証）
- `render-cli --backend`、Viewer の Windows ビルド、`--denoise-device cpu|cuda`（OIDN 2.5.1、DLL は `VERION_OIDN_LIB`）
- `benchmarks/baseline/nvidia-geforce-rtx-3080-ac.json`、`scripts/backend_render.sh` と `backend_diff.sh`
- SER は見送り: RTX 3080 は reorder hint が `NONE`、raygen 版は 616.92 ドライバで TDR。ブランチ `experiment/ser-raygen` に残した（ADR-0014 の追記）

## Mac でやること
1. pull して `mise run check`（`verion-gpu-metal` の置き換えのコンパイル確認。CI の macOS でも確かめられる）
2. `mise run shaders` を回す（SPIR-V のバイトは OS で違うので、差分が出るのは正常。`shaders:check` は `sources.cksum` を見る）
3. 同じ画像セットを Mac で作る: `sh scripts/backend_render.sh DIR` を両機で実行し、`sh scripts/backend_diff.sh` で比べる。閾値を決めて REQ-GPU-007 に書く（項目 9）
4. `mise run bench` が Metal の基準に対して通ること（`bench.sh` の分岐を足したため）

## 要確認（利用者）
- Octane の利用環境（項目 14）: 保留。まだ課金しておらず、利用者が C4D / Blender + Octane の環境を後で用意する
- Verion のライセンス判断の時期（ADR-0004）
- OIDN の DLL の配布方法

## 注意
- `mise run` のシェルタスクは `sh scripts/…` で呼ぶ（Windows の mise は .sh を直接実行できない）
- Windows の Git は改行を CRLF に直す警告を出すが、Slang・シェルスクリプトの内容は LF のまま扱われる。`sources_sum` は CR を無視する
- push は毎回確認を取る（このセッションでは push していない）
