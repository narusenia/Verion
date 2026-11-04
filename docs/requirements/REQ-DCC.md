# DCC 要件定義（連携）

対象: `plugins/blender` / `plugins/cinema4d` / `plugins/maya` 等。アダプタは薄く保ち、Scene IR を直接生成する。

## REQ-DCC-001: Blender RenderEngine

| 項目 | 内容 |
|------|------|
| ID | REQ-DCC-001 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

`bpy.types.RenderEngine` として登録し、Final 出力とビューポートレンダを行う。Python と Rust は PyO3 で接続する。M6。IES・ライトリンク・Cryptomatte・Shadow Catcher / アルファ合成もこの段階で扱う。

### 受入条件

- [ ] 実シーンを編集・プレビュー・Final 出力できる
- [ ] Stylization ノードを Blender 上で編集できる

### 依存要件

- REQ-CORE-001
- REQ-STY-001

## REQ-DCC-002: Blender IPR

| 項目 | 内容 |
|------|------|
| ID | REQ-DCC-002 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

`view_update` を差分更新エンジンへ接続する。

### 受入条件

- [ ] 編集後に実用的なプレビューが得られるまでの時間を計測する（First Clean Preview）

### 依存要件

- REQ-DCC-001
- REQ-ACC-003

## REQ-DCC-003: 材質変換

| 項目 | 内容 |
|------|------|
| ID | REQ-DCC-003 |
| 優先度 | Should |
| ステータス | Draft |

### 説明

Blender のノードを Material IR に変換する。プロシージャルは当面ベイクで対応する。

### 受入条件

- [ ] 非対応ノードは警告して代替値にする

### 依存要件

- REQ-DCC-001

## REQ-DCC-004: Cinema 4D

| 項目 | 内容 |
|------|------|
| ID | REQ-DCC-004 |
| 優先度 | Should |
| ステータス | Draft |

### 説明

C++ SDK の薄層から C ABI 経由で Rust コアを呼ぶ。M9。

### 受入条件

- [ ] Blender と同じシーンで見た目が一致する

### 依存要件

- REQ-DCC-001

## REQ-DCC-005: Maya などの DCC

| 項目 | 内容 |
|------|------|
| ID | REQ-DCC-005 |
| 優先度 | Could |
| ステータス | Draft |

### 説明

個別 SDK 対応と USD / Hydra delegate 対応のどちらが現実的かを評価してから着手する。M9。

### 受入条件

- [ ] 方式の選定結果を ADR に記録する

### 依存要件

- REQ-IO-005
