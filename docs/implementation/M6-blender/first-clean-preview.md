# First Clean Preview（Blender ビューポート）

REQ-DCC-002。編集から 16 spp が溜まるまでの時間。`plugins/blender/tests/measure_fcp.py` で測る（ビューポートの `Viewport` クラスを 3D ビューなしで動かす。画像の受け渡しは CPU バッファ）。

条件: Mac（Apple silicon、Metal）、Interactive モード（ReSTIR DI+GI）、面光源 1 つ・球 7 つ・床、Blender 5.2.3。

| 編集 | 960×540 初回画像 / 16 spp | 1920×1080 初回画像 / 16 spp |
|---|---|---|
| 最初の構築 | 0.017 s / 0.079 s | 0.053 s / 0.266 s |
| ライトを動かす | 0.013 s / 0.068 s | 0.076 s / 0.299 s |
| Instance を動かす | 0.013 s / 0.032 s | 0.036 s / 0.102 s |
| 材質の色を変える | 0.011 s / 0.029 s | 0.035 s / 0.100 s |
| カメラを動かす | 16 spp まで 0.130 s | 0.505 s |

`update` 自体は 1 ms 未満。支配的なのは累積のやり直し（1080p で 16 spp に 0.1〜0.3 s）。CPU バッファの受け渡し（RGBA の float をテクスチャへ）は 1080p で約 32 MB。実機のビューポートでの体感（描画コストを含む）は未確認で、GPU テクスチャ共有を検討するかどうかはその確認の後に決める。
