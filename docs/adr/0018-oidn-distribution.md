# ADR-0018: OIDN は CPU 版だけを同梱し、GPU 版は利用者が手動で足す

- 状態: 採用（方針のみ。同梱と GUI の導線は配布形態を作るときに実装する）
- 日付: 2026-11-06

## 背景

M4 から持ち越している判断が 2 つあった。OIDN の DLL をどう配布するか、Verion 自体のライセンス判断をいつにするか（ADR-0004）。

## 確認したこと

一次情報は OIDN の公式リポジトリ（README、`LICENSE.txt`、`third-party-programs.txt`。2026-11-06 に取得）。

- OIDN 本体は Apache 2.0。商用再配布できる（AGENTS.md の条件を満たす）
- 第三者の記載は oneTBB（Apache 2.0）、CUTLASS（BSD-3）、LLVM / DPC++（Apache 2.0 + LLVM 例外）。PyTorch・pytorch-msssim・Catch2 は学習とテスト用の記載
- Verion は `libloading` で実行時に読み込み、リンクしない。OIDN は Verion 自体のライセンス選びを縛らない
- **未確認**: GPU モジュール（CUDA など）が含むベンダーのランタイムの再配布条件。学習済みの重みの出所が、公式バイナリの配布物でどう記載されているか

## 決定

- 配布物には OIDN の **CPU 版だけ**を、公式のバイナリのまま改変せずに同梱する。Apache 2.0 の `LICENSE.txt` と、`third-party-programs.txt`（oneTBB などの文書を含む）を、配布物のライセンス文書の置き場に一緒に置く
- GPU 版（CUDA など）は同梱しない。利用者が手動で足せるようにし、その導線は Viewer などの GUI に用意する（導入の案内と、`VERION_OIDN_LIB` に入れる場所の指定）。ベンダーのランタイムの再配布条件を、配布物から外せる
- 速度の差は小さい（Cornell 16 spp のデノイズが CPU 0.34 s、CUDA 0.15 s。M4）。CPU だけでも既定の用途に足りる
- 実行時の読み込み（`VERION_OIDN_LIB` の指定と既定の探索）は今のまま残す
- Verion 自体のライセンス判断（ADR-0004）は **最初の外部配布の前まで**に決める（バイナリでもソースの公開でも）。ADR-0004 が待っていた NVIDIA SDK は使っていないので、OIDN は期限の理由にならない。それまでは保留のまま

## 結果

- 配布物を作るときの手順: 公式の OIDN バイナリ（CPU）、そのライセンス文書、バージョン番号を記録する。そのときに、配布物が OIDN のライセンス条件（Apache 2.0 の通知の維持）を満たすことを確認する
- GPU 版の導線の実装と、GPU 版を足したときの動作確認（M4 では Windows の CUDA で確認済み）は、配布形態を決めるときに計画へ入れる
- GPU 版を同梱に変える場合は、ベンダーのランタイムの再配布条件を原文で確認してから、この ADR を改める

## 追記（2026-11-06、M6 の配布。利用者が承認）

Blender のアドオンでは、OIDN を同梱しない。Blender が自分の OIDN（CPU のモジュールと、その環境の GPU モジュール。macOS は Metal、Windows と Linux は CUDA・HIP など）を同梱しているので、アドオンはその場所を `verion.set_oidn_library` で渡して使う（`native.py`。探す順は `VERION_OIDN_LIB`、Blender の同梱、システムの既定）。

- 再配布するものがないので、アドオンの zip に OIDN のライセンス文書は要らない（Blender 側の配布物に付いている）
- GPU 版を足す手作業と GUI の導線は要らなくなった。デノイズの Device の選択（CPU・Metal・CUDA・HIP）が導線になる
- Blender の外で配る場合（`render-cli`、Viewer）は、この ADR の本文どおり CPU 版を同梱する。そのときに手順と文書を作る

