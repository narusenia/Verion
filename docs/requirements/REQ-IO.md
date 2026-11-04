# IO 要件定義（入力・出力）

対象クレート: `verion-render-io`

## REQ-IO-001: glTF 2.0 入力

| 項目 | 内容 |
|------|------|
| ID | REQ-IO-001 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

v0.1 のシーン入力は glTF 2.0 と HDRI（ADR-0003）。glTF を読んで Scene IR を作る。Scene IR は glTF に縛られない。

### 受入条件

- [ ] メッシュ・インスタンス・PBR 材質・テクスチャ・カメラ・ライト（`KHR_lights_punctual`）を読める
- [x] 未対応の拡張は警告して無視する

### 依存要件

- REQ-CORE-001

## REQ-IO-002: Stylization 用 glTF 拡張

| 項目 | 内容 |
|------|------|
| ID | REQ-IO-002 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

材質の `extensions` に HybridSurface の設定を載せる JSON 拡張。スキーマの詳細は M2 着手時に仕様書で決める。

### 受入条件

- [ ] JSON Schema を公開する
- [ ] 拡張がないシーンは通常の PBR として描画する

### 依存要件

- REQ-IO-001
- REQ-STY-001

## REQ-IO-003: EXR 多チャンネル出力

| 項目 | 内容 |
|------|------|
| ID | REQ-IO-003 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

Beauty と AOV を 1 つの多チャンネル EXR に出力する。物理 / 非物理の別とレンダ設定をメタデータに入れる。

### 受入条件

- [ ] 外部の EXR ビューアで AOV を確認できる

### 依存要件

- REQ-CORE-005

## REQ-IO-004: UDIM・タイル化・オンデマンド読込

| 項目 | 内容 |
|------|------|
| ID | REQ-IO-004 |
| 優先度 | Should |
| ステータス | Draft |

### 説明

Blender の実シーンで必要になる。M6。

### 受入条件

- [ ] UDIM テクスチャを描画できる

### 依存要件

- REQ-DCC-001

## REQ-IO-005: USD の評価

| 項目 | 内容 |
|------|------|
| ID | REQ-IO-005 |
| 優先度 | Could |
| ステータス | Draft |

### 説明

M9 で、USD / MaterialX / Hydra delegate により複数 DCC を 1 本で拾えるかを評価する。Rust の対応状況とライセンスを確認する。

### 受入条件

- [ ] 採否を ADR に記録する

### 依存要件

- REQ-DCC-004
