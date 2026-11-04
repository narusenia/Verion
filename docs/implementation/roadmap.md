# ロードマップ

マイルストーンと完了条件だけを置く。状態は各 `M{n}-*/README.md` の表で管理する（REQ-INFRA-004）。方針は ADR-0011。

| Phase | 内容 | 完了条件 |
|-------|------|---------|
| M1 | Metal RT、glTF 入力、PBR、NEE / MIS、基本ライト、カラーマネジメント、EXR、GPU 計測、Mitsuba 照合、Slang → MSL スパイク | Cornell Box・金属・ガラス・HDRI が参照画像と一致 |
| M2 (= v0.1) | HybridSurface・ToonRamp・ShadowPalette・StylizedSpecular・RimLight、Lighting AOV、最小 Viewer、デノイズ | 写実〜Toon を連続調整でき、AOV を分離出力 |
| M3 | Wavefront、Queue Compaction、計測拡充（Metal） | Megakernel との定量比較 |
| M4 | Vulkan Backend（RTX 3080）、SER、Octane 比較ベースライン | Metal / Vulkan の画像一致 |
| M5 | ReSTIR DI → GI → PT、差分更新、IPR 編集 | 同画質到達時間の改善を実測 |
| M6 | Blender RenderEngine・IPR、UDIM、IES・ライトリンク、Cryptomatte、Shadow Catcher、材質変換 | 実シーンの編集・プレビュー・Final 出力 |
| M7 | NRC（CUDA / Metal Tensor）、Adaptive Integrator | 学習込みで高速化を実証 |
| M8 | Temporal 再利用、Motion Blur、Outline・顔影・髪ハイライト | アニメーションの安定性を検証 |
| M9 | Cinema 4D、Maya 等（USD / Hydra 評価）、OptiX 比較 | 複数 DCC で品質・性能を比較 |
| M10 | 体積、SSS、髪・カーブ、ディスプレイスメント、Out-of-core、マルチ GPU | 機能の穴を埋める |
| Research | Integrated Stylization、Style-aware Neural Rendering | 画質・安定性・性能を測り段階採用 |
