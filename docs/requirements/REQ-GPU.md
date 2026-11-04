# GPU 要件定義（バックエンド・Shader・スケジューラ）

対象クレート: `verion-gpu` / `verion-gpu-metal` / `verion-gpu-vulkan` / `verion-scheduler`、`shaders/`

## REQ-GPU-001: Metal RT バックエンド

| 項目 | 内容 |
|------|------|
| ID | REQ-GPU-001 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

Apple Silicon M3 以降のハードウェア RT を使う最初のバックエンド（ADR-0001）。Rust から `objc2-metal` で扱う。

### 受入条件

- [ ] M4 Pro と M5 の MacBook Pro で BLAS / TLAS の構築とレイトレースが動く
- [ ] 非対応チップは機能検出で明示エラーにする

### 依存要件

- REQ-GPU-002

## REQ-GPU-002: Slang による Shader 一本化

| 項目 | 内容 |
|------|------|
| ID | REQ-GPU-002 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

共通の BSDF・Integrator・Stylization を Slang で書き、MSL と SPIR-V にコンパイルする（ADR-0002）。M1 の最初に「Slang → MSL で Metal RT が動く」スパイクを行い、不可なら MSL ネイティブへ切り替える。

### 受入条件

- [ ] スパイクの結論（採用 / 撤退）を ADR に記録する
- [ ] Backend 固有の差分は隔離されている

### 依存要件

なし

## REQ-GPU-003: 最小の Backend 抽象と Capabilities

| 項目 | 内容 |
|------|------|
| ID | REQ-GPU-003 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

GPU API の抽象は最小限にする。`RayTracingBackend` と `NeuralBackend` を独立した Capabilities で選ぶ。共通化するのはデータモデル・アルゴリズムの契約・テストで、バッファと同期は Backend 別。

### 受入条件

- [ ] 機能検出による Fallback がある
- [ ] 2 つ目の Backend（REQ-GPU-006）を追加するときに抽象を壊さない

### 依存要件

- REQ-GPU-001

## REQ-GPU-004: GPU 計測

| 項目 | 内容 |
|------|------|
| ID | REQ-GPU-004 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

GPU タイムスタンプで trace / shade / 合計を測る。拡張項目（reservoir・neural・denoise・VRAM）は各機能の追加時に足す。

### 受入条件

- [ ] 計測値を JSON で出力できる（部分: 合計 `gpu_s` のみ。trace / shade の分離は REQ-GPU-005 の Wavefront 化が前提）

### 依存要件

- REQ-GPU-001

## REQ-GPU-005: Wavefront と Compaction

| 項目 | 内容 |
|------|------|
| ID | REQ-GPU-005 |
| 優先度 | Should |
| ステータス | Draft |

### 説明

Path State を SoA で持ち、間接 Dispatch と Queue Counter で CPU 待機を避ける。Megakernel との定量比較で採否を決める。

### 受入条件

- [ ] 同一シーンで Megakernel と同一画質（REQ-QA-001 の閾値内）
- [ ] シーン規模別の速度比較を記録する

### 依存要件

- REQ-CORE-002
- REQ-PERF-001

## REQ-GPU-006: Vulkan RT バックエンド

| 項目 | 内容 |
|------|------|
| ID | REQ-GPU-006 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

RTX 3080（Windows）で動く 2 つ目のバックエンド。SER は拡張を検出して有効にする。

### 受入条件

- [ ] 同一シーンで Metal と Vulkan が描画できる
- [ ] 非対応拡張は Fallback で動く

### 依存要件

- REQ-GPU-003

## REQ-GPU-007: Backend 間の画像一致

| 項目 | 内容 |
|------|------|
| ID | REQ-GPU-007 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

同じシーン・同じ設定で Metal と Vulkan の見た目が一致する。

### 受入条件

- [ ] 画素差分が閾値内（閾値は初回実測で決める）
- [ ] Stylization AOV も一致する

### 依存要件

- REQ-GPU-006

## REQ-GPU-008: Render Graph

| 項目 | 内容 |
|------|------|
| ID | REQ-GPU-008 |
| 優先度 | Should |
| ステータス | Draft |

### 説明

Pass 依存、Hazard、Transient メモリの寿命、非同期 Queue を管理する。NVIDIA の外部セマフォ同期は NRC（REQ-ACC-004）で統合する。

### 受入条件

- [ ] Transient バッファを Pass 間で再利用できる

### 依存要件

- REQ-GPU-003
