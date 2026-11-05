# ロードマップ

進み具合は各マイルストーンの `M{n}-*/README.md` の表で管理する。順序の理由は ADR-0011。表現力を速度より先に作り、Metal を Vulkan より先に作る。

| Phase | 内容 | 完了条件 |
|-------|------|---------|
| M1 | Metal RT、glTF 入力、PBR パストレーシング、カラーマネジメント、EXR、GPU 計測、Mitsuba 3 照合 | Cornell Box・金属・ガラス・HDRI が参照画像と一致 |
| M2（v0.1） | HybridSurface・ToonRamp・ShadowPalette・StylizedSpecular・RimLight、写実材質の拡充、Lighting AOV、PostProcess の枠と最小の輪郭線、デノイズ、最小 Viewer | 写実から Toon までを連続調整でき、AOV を分離出力 |
| M3 | Wavefront、Queue Compaction | Megakernel との速度比較 |
| M4 | Vulkan Backend（RTX 3080）、SER、Octane 比較の基準値 | Metal と Vulkan の画像一致 |
| M5 | ReSTIR、差分更新、IPR 編集 | 同画質到達時間の短縮を実測 |
| M6 | Blender 連携（IPR、UDIM、IES、Cryptomatte など） | 実シーンの編集・プレビュー・最終出力 |
| M7 | NRC、Adaptive Integrator | 学習込みで高速化を実証 |
| M8 | Temporal 再利用、Motion Blur、輪郭・顔影・髪ハイライト、ブルーム・色収差 | 動画で安定 |
| M9 | Cinema 4D、Maya など | 複数 DCC で品質・性能を比較 |
| M10 | 体積、SSS、髪・カーブ、ディスプレイスメント、Out-of-core、マルチ GPU | 機能の穴を埋める |
| Research | Integrated Stylization、Style-aware Neural Rendering、スペクトルレンダリング（分光 Dispersion） | 画質・安定性・性能を測り段階採用 |
