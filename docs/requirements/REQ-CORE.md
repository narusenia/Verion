# CORE 要件定義（Scene IR・Integrator・色）

対象クレート: `verion-scene` / `verion-geometry` / `verion-material` / `verion-integrator` / `verion-render-core`

## REQ-CORE-001: Scene IR と変更 revision

| 項目 | 内容 |
|------|------|
| ID | REQ-CORE-001 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

Geometry・Instance・Material・Light・Camera を持つ、入力形式に依存しない内部表現。geometry / material / lighting / camera の revision カウンタを最初から持つ（camera は BLAS・材質・ライトに影響しない変更の判別用）。マテリアルの Stylization レイヤーが変わったときは、material revision に加えて stylization revision も増やす（REQ-STY-008。出力メタデータとキャッシュが物理結果と区別するため）。後の差分更新（REQ-ACC-003）と IPR の土台になる。

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

- [x] Cornell Box で参照画像と一致する（REQ-QA-001。平均輝度の偏差 0.19%）
- [x] 累積サンプル数に対して分散が単調に減る（`variance_decreases_with_samples`）
- [x] Megakernel 形式で動く（Wavefront は REQ-GPU-005）

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

Diffuse、GGX Conductor、Dielectric（透過）。glTF の metallic-roughness と transmission を表現できる。写実側の品質のため、多重散乱の補償、clearcoat・sheen、Dispersion（RGB 近似）を追加する。これらは Reference モードにも含める。スペクトルレンダリングは対象外（Research）。

### 受入条件

- [x] 白炉テストでエネルギー保存が許容誤差内（REQ-QA-002。多重散乱補正なしの損失を除く）
- [x] 金属・ガラスの基礎シーンが参照画像と一致する（Cornell Box の金属・ガラスを Mitsuba 3 で照合）
- [x] GGX 金属に多重散乱の補償を入れ、粗い金属の白炉テストが 1 に戻る（方式は鏡面ローブへの係数 `1 + F0 (1/E − 1)`。E は単一散乱 GGX の方向アルベドの表。既定で有効、`--no-multiscatter` で単一散乱に戻せる。Mitsuba 3 の照合は無効で行う。不透明な誘電体の鏡面は未対応で、粗さ 1 でも損失は 2.8%）
- [x] 粗い透過（すりガラス）に多重散乱の補償を入れ、ガラス球の白炉テストが 1 に戻る（反射＋透過の合計アルベド E(cosθ, 粗さ, IOR, 外→内 / 内→外) の表（`scripts/gen_dielectric_albedo.py`）で、サンプリング重みと反射の評価を 1/E 倍する。反射と透過の比は保つ。粗さ 1 で 0.36 → 1.00、粗さ 0.3〜1.0 で 0.986 以上。既定で有効、`--no-multiscatter` で戻せる。E の下限は 0.1）
- [x] clearcoat と sheen を glTF 拡張から読み、追加ローブとして評価できる（`gltf` クレート 1.4 は未対応のため自前でパースする。clearcoat・sheen は済: `KHR_materials_clearcoat` は IOR 1.5 の GGX 層、`KHR_materials_sheen` は Charlie 分布の層（基底を方向アルベドで減衰。表は `scripts/gen_sheen_albedo.py`）。層の順は基底 → sheen → coat。clearcoat は Mitsuba 3 の `roughplastic`（拡散 0）と照合済みで、平均差 0.06%・ブロック差 0.22%（`crosscheck` の `coat`。sheen は対応 BSDF がなく解析テストと参照画像で代替）。層間の屈折・吸収は省略。テクスチャは未対応）
- [x] Dispersion を IOR のチャンネル別の値で近似できる（`KHR_materials_dispersion`。IOR は R `ior−h`・G `ior`・B `ior+h`、`h = (ior−1)·0.025·dispersion`（仕様の実装メモの式）。パスが最初の分散ヒットで 1 チャンネルを選んで追従する。`KHR_materials_volume` は未対応）

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

- [x] 各ライト種別に NEE と MIS が効く（delta ライトは NEE のみ。MIS は面光源・HDRI。IES とライトリンクは対象外）
- [x] HDRI は重点サンプリングする（輝度 × sin θ の周辺・条件 CDF）

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

- [x] 作業色空間を設定で選べる（`render-cli --working-space rec709|acescg`、Scene では `set_working_space`）
- [x] 表示と EXR 出力でそれぞれ色空間変換が指定できる（`OutputTransform`、`render-cli --output-space`。OCIO は未実装で、Rec.709 と ACEScg を自前の行列で持つ）

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
