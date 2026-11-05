# PERF 要件定義（性能）

方針は ADR-0010。v0.1 は絶対速度目標を置かず、ベースラインを記録して退行を検出する。

## REQ-PERF-001: ベンチハーネス

| 項目 | 内容 |
|------|------|
| ID | REQ-PERF-001 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

`benchmarks/` に固定シーン・固定設定のベンチを置く。GPU 計測値（REQ-GPU-004）を JSON で出す。

### 受入条件

- [ ] M4 Pro と M5 でそれぞれベースラインを記録する

### 依存要件

- REQ-GPU-004
- REQ-VIEW-001

## REQ-PERF-002: 退行検知

| 項目 | 内容 |
|------|------|
| ID | REQ-PERF-002 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

前回比 −10% を超える退行で警告する。

### 受入条件

- [x] ベンチ結果の比較が自動で行える（`mise run bench`、チップ別ベースラインとの `gpu_s` 比較）

### 依存要件

- REQ-PERF-001

## REQ-PERF-003: 規模の下限

| 項目 | 内容 |
|------|------|
| ID | REQ-PERF-003 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

5M 三角形と複数の 4K テクスチャを、M4 Pro / M5 のユニファイドメモリ内で扱える。数値は仮置きで、M1 のベンチで見直す。VRAM 超過時は明示エラーとする。v0.1 ではストリーミングを対象外とし、Texture のみ後続で扱う（REQ-PERF-006）。Geometry は全常駐のままで、欠けたまま描画することはしない。

### 受入条件

- [x] 規模下限のシーンが動く（M5 で 500 万三角形・4K×4 を描画、ピーク約 4.5GB。M4 Pro は未確認）
- [x] 超過時のエラーが分かりやすい（`Error::OutOfMemory`。閾値判定のテストのみで、実機での超過は未確認）

### 依存要件

- REQ-PERF-001

## REQ-PERF-004: Octane 比較

| 項目 | 内容 |
|------|------|
| ID | REQ-PERF-004 |
| 優先度 | Should |
| ステータス | Draft |

### 説明

M4 以降。RTX 3080 で、同一ハードウェア・解像度・実質一致のシーン・比較可能な画質を前提に、Time to Quality・Final Render Time・First Clean Preview・Animation Throughput・GPU リソースを比べる。Octane 側のデノイズも含めて公平に評価する。

### 受入条件

- [ ] 比較条件と結果を記録する

### 依存要件

- REQ-GPU-006

## REQ-PERF-005: 研究目標（保証しない）

| 項目 | 内容 |
|------|------|
| ID | REQ-PERF-005 |
| 優先度 | Could |
| ステータス | Draft |

### 説明

静止画で同画質到達時間 2 倍、時間的再利用に適したアニメーションで総時間 3 倍。研究仮説であり保証値ではない。効果は単純に乗算されない。

### 受入条件

- [ ] 到達 / 未到達を実測で記録する

### 依存要件

- REQ-ACC-002
- REQ-ACC-004

## REQ-PERF-006: Texture Out-of-Core

| 項目 | 内容 |
|------|------|
| ID | REQ-PERF-006 |
| 優先度 | Should |
| ステータス | Draft |

### 説明

段階化した方針（`docs/drafts/verion_gpu_performance_optimization_plan.md` の P0〜P2 を基にする）。

1. 全常駐と明示エラー（REQ-PERF-003）。M1
2. Memory Budget の抽象と使用量メトリクス（VRAM ピーク、アップロード量）。挙動は変えない。M3 の Queue 容量決定と同時
3. Texture のみ Out-of-Core（Mip・タイル単位）。M10
4. Geometry の Residency・BLAS 管理は研究扱いで、ロードマップに入れない

3 の着手条件は実測。実アセットで GPU の作業セットを超える、またはピークが作業セットの半分を超えること。Final 品質では未常駐ページを低 LOD で代用せず、データを待つ。

### 受入条件

- [x] Memory Budget とピーク使用量がメトリクスに出る（`gpu_budget_bytes`・`gpu_peak_bytes`・`upload_bytes`・`wavefront_bytes`。M3）
- [ ] 着手条件を満たす実アセットまたは規模シーンを用意し、結果を記録する
- [ ] VRAM 内外のテクスチャシーンで、Out-of-Core 有無の画像が一致する（REQ-QA-001 の閾値内）
- [ ] VRAM 内に収まるシーンでのオーバーヘッドを測る

### 依存要件

- REQ-PERF-003
- REQ-GPU-004
