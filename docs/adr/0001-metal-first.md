# ADR-0001: Metal を先行バックエンドにする

- 状態: 採用
- 日付: 2026-11-04

## 背景

草案は Vulkan RT を共通基盤として先行させる。開発機は M4 Pro MacBook Pro、M5 MacBook Pro、RTX 3080 Windows。macOS の MoltenVK は Vulkan RT に対応しない。

## 決定

- 最初のバックエンドは Metal RT（M3 以降のハードウェア RT）
- Vulkan は M4 で追加する。2 つ目を早く作ることで GPU 抽象の誤りを早期に見つける
- Octane 比較は Windows の RTX 3080 が主なので、Vulkan 完成後に行う

## 結果

- 草案の M1（Vulkan）と M7（Metal）が逆転する
- NRC の CUDA 経路は NVIDIA 機での作業を待つ（M7）
