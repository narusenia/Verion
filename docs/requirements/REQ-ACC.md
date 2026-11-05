# ACC 要件定義（高速化）

対象クレート: `verion-denoise` / `verion-restir` / `verion-neural` / `verion-cache`

速度は表現力を妨げない範囲で追う（ADR-0005）。高速化は Reference モードで常に無効化できる。

## REQ-ACC-001: デノイズ

| 項目 | 内容 |
|------|------|
| ID | REQ-ACC-001 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

Albedo / Normal 等の AOV を供給してデノイズする。まず OIDN。Metal 向けは OIDN と MetalFX を比較して選ぶ。

### 受入条件

- [x] Toon 境界と意図したテクスチャを消さない（`verion-denoise` が OIDN を実行時に読み込む。`render-cli --denoise`（Stylized は既定で Pass の入力側）と Viewer の「Denoise when done」。評価は REQ-QA-003）
- [x] 選定結果を ADR に記録する（ADR-0013: まず OIDN、MetalFX は M5 以降に再評価）

### 依存要件

- REQ-STY-006

## REQ-ACC-002: ReSTIR

| 項目 | 内容 |
|------|------|
| ID | REQ-ACC-002 |
| 優先度 | Should |
| ステータス | Draft |

### 説明

DI → GI → PT の順で導入する。可視性・PDF・再投影の整合を保つ。M5。

### 受入条件

- [ ] 同画質到達時間が改善することを実測する（REQ-PERF-001）
- [ ] 鏡面・屈折・Motion Blur・DoF では Fallback する

### 依存要件

- REQ-GPU-005

## REQ-ACC-003: 差分更新エンジン

| 項目 | 内容 |
|------|------|
| ID | REQ-ACC-003 |
| 優先度 | Should |
| ステータス | Draft |

### 説明

Camera / Material / Light / Transform / Mesh Deformation / Resolution の変更ごとに、再利用できる BLAS・キャッシュを残して部分更新する（草案 §5）。revision・Confidence・検証サンプルで無効化を制御する。M5。

### 受入条件

- [ ] 変更種別ごとの再利用範囲が表のとおりに動く
- [ ] 間接光の遠距離伝播に対する検証サンプルがある

### 依存要件

- REQ-CORE-001

## REQ-ACC-004: Neural Radiance Cache

| 項目 | 内容 |
|------|------|
| ID | REQ-ACC-004 |
| 優先度 | Should |
| ステータス | Draft |

### 説明

NVIDIA は CUDA、Apple は Metal Tensor を評価する。学習・推論コスト込みで速くならない場合は無効化する。物理 Radiance と後段のスタイル変換を分離する。M7。

### 受入条件

- [ ] 学習・推論時間込みで Time to Quality が改善する
- [ ] Specular・Caustics・変更直後の領域は物理 PT に Fallback する

### 依存要件

- REQ-ACC-002
- REQ-GPU-008

## REQ-ACC-005: Temporal 再利用と Motion Blur

| 項目 | 内容 |
|------|------|
| ID | REQ-ACC-005 |
| 優先度 | Should |
| ステータス | Draft |

### 説明

Motion Vector・Depth・Normal・ID による再投影と履歴破棄。Motion Blur はここで導入する。M8。

### 受入条件

- [ ] ちらつきを定量評価する（REQ-QA-003）

### 依存要件

- REQ-ACC-003

## REQ-ACC-006: Adaptive Integrator（研究）

| 項目 | 内容 |
|------|------|
| ID | REQ-ACC-006 |
| 優先度 | Could |
| ステータス | Draft |

### 説明

領域ごとに Physical PT / ReSTIR / NRC を選ぶ。初期はヒューリスティック。

### 受入条件

- [ ] 選択が単独方式より改善することを実測する

### 依存要件

- REQ-ACC-002
- REQ-ACC-004
