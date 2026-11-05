# ADR-0011: ロードマップの再編

- 状態: 採用
- 日付: 2026-11-04

## 背景

ADR-0001 / 0005 / 0009 の決定で、草案 §11 の順序が変わる。

## 決定

草案からの差分:

- Stylization（草案 M2.5）を M2 に前倒しし、Wavefront は M3 へ
- 画素単位の Adaptive Sampling（草案 `adaptive_sampling_scheduler_plan.md` の Pixel レベル）を M3 に追加（2026-11-06、ADR-0015）
- Vulkan を M4 に新設（草案は M1 / M2 に混在）
- ReSTIR（M5）の後に NRC（M7）。Metal / CUDA の両方を見て判断する
- Blender は M6。Cinema 4D と Maya 等は M9（USD / Hydra の評価を含む）
- 草案に無かった機能（カラーマネジメント、ライト種別、Cryptomatte、Shadow Catcher、UDIM、体積、SSS、髪・カーブ、Out-of-core、マルチ GPU）を M1 / M6 / M10 に割り当てる

全体は `docs/implementation/roadmap.md`。

## 結果

- 分散・ネットワークレンダリングは対象外
