# CORE 要件定義（Scene IR・Integrator・色）

対象クレート: `verion-scene` / `verion-geometry` / `verion-material` / `verion-integrator` / `verion-render-core`

## REQ-CORE-001: Scene IR と変更 revision

| 項目 | 内容 |
|------|------|
| ID | REQ-CORE-001 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

Geometry・Instance・Material・Light・Camera を持つ、入力形式に依存しない内部表現。geometry / material / lighting / camera の revision カウンタを最初から持つ（camera は BLAS・材質・ライトに影響しない変更の判別用）。Stylization の変更は material revision に含める（ADR-0008 の Stylization revision を分けるかは REQ-STY で決める）。後の差分更新（REQ-ACC-003）と IPR の土台になる。

### 受入条件

- [x] glTF 型を IR の公開 API に出さない
- [x] 各要素の変更で対応する revision が増える
- [x] Material IR は `Base BSDF` / `Stylization Layers` / `Output Channels` を分けて持つ

### 依存要件

なし

## REQ-CORE-002: パストレーシング Integrator

| 項目 | 内容 |
|------|------|
| ID | REQ-CORE-002 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

NEE と MIS を使うパストレーサー。Russian Roulette、薄レンズ DoF、累積（プログレッシブ）を持つ。初期は FP32。

### 受入条件

- [ ] Cornell Box で参照画像と一致する（REQ-QA-001）
- [ ] 累積サンプル数に対して分散が単調に減る
- [ ] Megakernel 形式で動く（Wavefront は REQ-GPU-005）

### 依存要件

- REQ-CORE-001
- REQ-CORE-003
- REQ-GPU-001

## REQ-CORE-003: 基本 BSDF

| 項目 | 内容 |
|------|------|
| ID | REQ-CORE-003 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

Diffuse、GGX Conductor、Dielectric（透過）。glTF の metallic-roughness と transmission を表現できる。

### 受入条件

- [ ] 白炉テストでエネルギー保存が許容誤差内（REQ-QA-002）
- [ ] 金属・ガラスの基礎シーンが参照画像と一致する

### 依存要件

- REQ-CORE-001

## REQ-CORE-004: テクスチャ・HDRI・ライト

| 項目 | 内容 |
|------|------|
| ID | REQ-CORE-004 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

BaseColor / Normal / MetallicRoughness / Emissive テクスチャとミップ。HDRI、Emissive Mesh、Point / Spot / Sun / Sky / Area ライト。IES とライトリンクは REQ-DCC-001 の段階で追加する。

### 受入条件

- [ ] 各ライト種別に NEE と MIS が効く
- [ ] HDRI は重点サンプリングする

### 依存要件

- REQ-CORE-002

## REQ-CORE-005: カラーマネジメント

| 項目 | 内容 |
|------|------|
| ID | REQ-CORE-005 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

作業色空間を持ち、OCIO / ACES に対応する。入力テクスチャの色空間と、出力 EXR・表示の変換を明示する。後付けにすると出力全体の手戻りになるため M1 で入れる。

### 受入条件

- [ ] 作業色空間を設定で選べる
- [ ] 表示と EXR 出力でそれぞれ色空間変換が指定できる

### 依存要件

- REQ-IO-001

## REQ-CORE-006: Reference モード

| 項目 | 内容 |
|------|------|
| ID | REQ-CORE-006 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

NPR と AI 近似を無効にし、物理パストレーシングだけで描く。誤差評価の基準経路。

### 受入条件

- [ ] 有効時に Stylization Pass・NRC・ReSTIR を通らない（現状は該当機能が未実装で構造的に満たすのみ。検証テストは REQ-STY-001 で変種が入る時点で追加）
- [x] 非物理処理の有無を出力メタデータに記録する（EXR の `physical`、mode 由来）

### 依存要件

- REQ-CORE-002

## REQ-CORE-007: レンダリングモード

| 項目 | 内容 |
|------|------|
| ID | REQ-CORE-007 |
| 優先度 | Should |
| ステータス | Draft |

### 説明

Interactive / Production / Reference の 3 モード。構成は草案 §9 に従う。v0.1 では Reference と、Stylization を含む標準構成だけを持つ。

### 受入条件

- [ ] モード切替で各機能の有効・無効が定義どおりに変わる

### 依存要件

- REQ-CORE-006
