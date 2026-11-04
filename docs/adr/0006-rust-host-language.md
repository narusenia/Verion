# ADR-0006: ホスト言語は Rust を継続する

- 状態: 採用
- 日付: 2026-11-04

## 背景

Metal の新 API 追従、OptiX、Cinema 4D の C++ SDK では C++ が有利な面がある。一方、Render Graph の寿命・同期管理と個人開発の保守性では Rust が強い。

## 決定

- 本体は Rust。モノレポ構成は草案 §10 に従う
- NVIDIA / OptiX と Cinema 4D だけ C++ の薄層（C ABI）で隔離する
- Metal 新 API の追従が不足した場合は、局所的に C++ / Swift へ逃がす

## 結果

- Cinema 4D アダプタは M9 で C++ 薄層 + C ABI が必須
