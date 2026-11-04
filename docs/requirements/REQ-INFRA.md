# INFRA 要件定義（基盤）

## REQ-INFRA-001: Cargo workspace とクレート構成

| 項目 | 内容 |
|------|------|
| ID | REQ-INFRA-001 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

草案 §10 の構成を基に、`verion-` 接頭辞のクレートでモノレポにする。GPU API の抽象は最小限。

### 受入条件

- [ ] クレート間の依存方向を `docs/specifications/architecture.md` に定義する
- [ ] GPU 非依存のクレート（scene・material 等）は GPU API に依存しない

### 依存要件

なし

## REQ-INFRA-002: CI

| 項目 | 内容 |
|------|------|
| ID | REQ-INFRA-002 |
| 優先度 | Should |
| ステータス | Draft |

### 説明

ビルド・lint・GPU 非依存テストを CI で回す。GPU を使うテストとベンチの実行環境（自前 runner 等）は M1 中に決める。

### 受入条件

- [ ] macOS と Windows でビルドが通る

### 依存要件

なし

## REQ-INFRA-003: ライセンス方針と依存検査

| 項目 | 内容 |
|------|------|
| ID | REQ-INFRA-003 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

Verion 自体のライセンスは M4 前後まで保留（オープンコア寄り。ADR-0004）。それまで、依存は商用再配布が可能なものに限る。`cargo-deny` で検査する。NVIDIA SDK・Slang・デノイザー・USD・DCC SDK の再配布条件は導入時に個別確認する。

### 受入条件

- [ ] `deny.toml` で許可ライセンスを定義し CI で検査する
- [ ] 依存追加時に再配布条件を確認した記録を残す

### 依存要件

なし

## REQ-INFRA-004: ドキュメント構成と状態管理

| 項目 | 内容 |
|------|------|
| ID | REQ-INFRA-004 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

`docs/requirements/`・`specifications/`・`implementation/`・`adr/`・`handoff/` に分ける。状態はマイルストーンの `README.md` の表だけで管理し、ファイル移動で表さない。

### 受入条件

- [ ] `AGENTS.md` に構成を書く

### 依存要件

なし

## REQ-INFRA-005: エージェント向け規約と言語の使い分け

| 項目 | 内容 |
|------|------|
| ID | REQ-INFRA-005 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

要件・計画・ADR は日本語。コード・コメント・コミットメッセージ・README は英語。`AGENTS.md` が正本で、`CLAUDE.md` は `@AGENTS.md` のみ。

### 受入条件

- [ ] 作業完了時に docs への影響を確認するルールを `AGENTS.md` に書く

### 依存要件

- REQ-INFRA-004

## REQ-INFRA-007: 開発ツールチェーン

| 項目 | 内容 |
|------|------|
| ID | REQ-INFRA-007 |
| 優先度 | Should |
| ステータス | Draft |

### 説明

ツールとタスクを mise で管理する（seimei と同じ運用）。`mise run check` が検証の正本で、CI と lefthook の pre-commit も同じタスクを呼ぶ。

### 受入条件

- [ ] `mise.toml` に Rust・lefthook・jq・cargo-deny を固定している
- [ ] `fmt` / `clippy` / `deny` / `test` / `check` / `hooks:install` のタスクがある
- [ ] `deps`（クレート依存規則）・`bench`・`qa` は対応コードの追加時にタスク化する

### 依存要件

- REQ-INFRA-001

## REQ-INFRA-006: 対応プラットフォーム

| 項目 | 内容 |
|------|------|
| ID | REQ-INFRA-006 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

macOS（Apple Silicon M3 以降）と Windows（RTX）を主対象とする。M1/M2 チップと Linux は初期は対象外。

### 受入条件

- [ ] 非対応環境は機能検出で明示エラーにする

### 依存要件

- REQ-GPU-003
