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

DI → GI を M5 で導入し、PT は M7 の NRC の測定と並べて導入を評価する（ADR-0016）。可視性・PDF・再投影の整合を保つ。

### 受入条件

- [x] 同画質到達時間が改善することを実測する（REQ-PERF-001。Metal で多光源・間接光が支配的なシーンで 1.8〜4.9 倍。ADR-0016）
- [x] 鏡面・屈折・Motion Blur・DoF では Fallback する（ガラスを通る経路は GI の再利用から外す。Metal のテストで確認）
- [ ] Vulkan でも同じことが動く（実装と移植したテストは済、RTX 3080 での実行待ち）
- [ ] Octane との同画質到達時間を比較する（Blender 連携後に、Blender 用の無料版 Octane で同種のシーンを組んで比べる）

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

- [x] 変更種別ごとの再利用範囲が表のとおりに動く（Metal。`UpdateReport` で数える）
- [x] 間接光の遠距離伝播に対する検証サンプルがある（壁の色の更新と再構築の画像がビット一致。ADR-0017）
- [ ] Vulkan でも同じことが動く（実装と移植したテストは済、RTX 3080 での実行待ち）

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

## REQ-ACC-007: 画素単位の Adaptive Sampling

| 項目 | 内容 |
|------|------|
| ID | REQ-ACC-007 |
| 優先度 | Should |
| ステータス | Draft |

### 説明

収束した画素のサンプルを止め、残りの GPU 時間を収束していない画素に回す。画素ごとに輝度の平均と分散を持ち、平均の標準誤差が平均に対して閾値以下になった画素を止める。自分の推定値で止めるため僅かに偏るので、出力は非物理として記録する。どの手法で描くかを選ぶ REQ-ACC-006 とは別で、こちらはサンプル数の配分だけを扱う。ADR-0015。

### 受入条件

- [x] Megakernel と Wavefront の両方で動き、両者の画像が一致する（`Renderer::set_adaptive`。閾値 0 は一様サンプリングとビット一致）
- [x] 非物理として記録し、画素ごとのサンプル数を出力する（EXR の `verion/adaptiveThreshold`・`verion/physical = false`・`SampleCount` チャネル）
- [x] 同じ GPU 時間で一様サンプリングと比べる（`scripts/eval_adaptive.sh`。難しさが画面内で偏るシーンで PSNR が上がり、一様なシーンでは下がる。ADR-0015）
- [x] CLI と Viewer から使える（`render-cli --adaptive`、Viewer の Render 欄と Samples ビュー）

### 依存要件

- REQ-GPU-005
- REQ-IO-003
