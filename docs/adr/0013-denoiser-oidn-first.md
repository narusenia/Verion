# ADR-0013: デノイザーはまず OIDN にし、MetalFX は動画の段階で再評価する

- 状態: 採用（2026-11-06 に実装）
- 日付: 2026-11-05

## 背景

REQ-ACC-001 は、Metal 向けデノイザーを OIDN と MetalFX から選び、ADR に記録することを求めている。条件は次のとおり。

- 依存は商用再配布できるライセンスに限る（AGENTS.md）
- 入力に使える AOV（Albedo・Normal）は M1 から出力済み。Motion Vector は M5 に送っている（REQ-STY-006）
- 静止画の最終レンダーと Viewer の累積表示で使う。動画は M5 以降
- Stylization は累積後の CPU Pass で、デノイズは Toon 境界と意図したテクスチャを消してはならない（REQ-QA-003）
- 目視では、現在の粒状感は通常のパストレースのノイズで、サンプリングの改善では減らなかった（sheen のサンプリング変更の実験）

## 比較

一次情報は OIDN の README と変更履歴、Apple の MetalFX 文書（2026-11-05 時点）。

| 軸 | OIDN | MetalFX（`MTLFXTemporalDenoisedScaler`） |
|---|---|---|
| ライセンス | Apache 2.0（README 記載） | OS 同梱の API。再配布の問題なし |
| Apple 対応 | ARM64 CPU と Apple silicon GPU（M1 以降、macOS Ventura 以降）。v2.5.1 | macOS 26 以降 |
| 方式 | 1 フレームのデノイズ。Albedo・Normal を補助入力に取る | 時間方向。複数フレームを解析し、アップスケールと一体 |
| Metal との連携 | `oidnNewSharedBufferFromMetal` で MTLBuffer を直接渡せる | Metal 上の API |
| 静止画・累積表示 | そのまま使える | 前フレームと Motion Vector が要る |
| クロスプラットフォーム | Linux・Windows・CUDA・HIP・SYCL も対応（Vulkan 後続に使い回せる） | Apple のみ |

- OptiX Denoiser は NVIDIA GPU（CUDA / OptiX）専用で、Metal では動かないため M2 の比較対象にしていない。M4 の RTX 3080・Vulkan 側で、OIDN（CUDA 対応）の速度が足りないときに追加で比較する。SDK ライセンスの再配布条件は未確認で、採用を検討する時点で原文を確認する
- MetalFX は、入力の細目（Motion Vector・露出・ジッターなどの要件）を本文まで読んでいない。選定の根拠は「時間方向の方式で、アップスケールと一体」「macOS 26 以降」という概要レベル

## 決定

- まず OIDN を使う。静止画と Viewer の累積表示を対象にする
- MetalFX は採らない。Motion Vector が揃う M5 以降、動画・IPR の用途で再評価する
- 実装時の方針（実装を頼まれたときに確定する）:
  - 補助入力は Albedo と Normal（既存の出力）
  - Toon 境界を守るため、デノイズは Stylization の入力側（Lighting AOV の成分）に掛け、輪郭線と色調整は後段のまま残す。ビューティ全体に掛ける方式との比較は REQ-QA-003 で評価する
  - Reference モードでは、デノイズも非物理の処理として出力メタデータに記録する
  - OIDN は C++ ライブラリ。Rust との結合方法（既存の binding クレートか、自前の FFI か）と、出荷時の配布方法は実装時に決め、`mise run deny` を通す

## 結果

- 2026-11-06 に実装した。結合は自前の最小 FFI（`verion-denoise`、`libloading`（ISC）で実行時に読み込む）。OIDN が無い環境でもビルドでき、CI に C++ ライブラリが要らない。開発機は Homebrew の `open-image-denoise` 2.5.1（CPU デバイスのみ）を使う。出荷時の同梱方法は配布形態を決めるときに決める
- 補助入力の Albedo・Normal は画素中心 1 本の一次ヒットで、ノイズがないので `cleanAux` にする。アンチエイリアスされた色との差で輪郭がわずかに硬くなる。気になれば AOV を累積に変える
- Stylized は Lighting AOV の放射量（5 成分と光ごとのスロットの u・s）に掛け、比（応答・方向・可視性）には掛けない。面光源・環境のスロットの応答に残るノイズは帯の縁の粒として残る（REQ-QA-003 の保持率で許容範囲）
- Vulkan 側（ADR-0001）も同じデノイザーを使える見込み
- 未確認: Apple M4 Pro での OIDN の速度（M1 から継続の実機確認に含める）、Toon 境界の消失の程度
