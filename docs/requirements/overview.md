# 要件定義書: Verion

## プロジェクト概要

Verion は、Blender / Cinema 4D / Maya などの DCC から使える GPU レンダラーである。Rust で実装する。

- **Art-Directable Physical Rendering**: 写実から現代的なゲーム風、セルルックまでを、物理ベースの光輸送を保ったままアーティストが制御できる（最優先。ADR-0005）
- **物理レンダリング**: パストレーシングによる基準品質。AI 近似なしの Reference 経路を常に保持する
- **高速化**: ReSTIR・ニューラルキャッシュ・デノイズ・差分更新で、同一画質に到達する時間（Time to Quality）を縮める（表現力を妨げない範囲で追う）

構想の全体像と研究仮説は `docs/drafts/` にある（元の草案は `draft_arch.md`。ほかに GPU 性能計画、Adaptive Sampling 計画、リアルタイム版 Aerion の構想）。本書が要件の正本で、草案との差分は ADR に記録する。

## 位置づけ

- 個人の研究・開発プロジェクトとして始める。製品としての外部配布も視野に入れる（オープンコア寄り。ADR-0004）
- Verion 自体のライセンスは未決。依存は商用再配布が可能なものに限る
- 会社業務とは無関係

## スコープ

### v0.1（M1〜M2）

- Metal RT バックエンド（Apple Silicon M3 以降）
- glTF 2.0 入力と Stylization 用の拡張 JSON
- PBR パストレーシング（NEE / MIS、テクスチャ、HDRI、基本ライト、薄レンズ DoF）
- カラーマネジメント（OCIO / ACES）
- HybridSurface・ToonRamp・ShadowPalette・StylizedSpecular・RimLight（一次ヒットの Hybrid 方式）
- 写実材質の拡充（多重散乱補償、clearcoat・sheen、Dispersion の RGB 近似）
- Lighting AOV の分離出力、EXR 出力、デノイズ
- PostProcess の枠、最小の色調整、最小の輪郭線
- `render-cli` と最小 Viewer（累積表示、AOV 切替、Stylization パラメータ変更→再累積）
- Reference 検証（Mitsuba 3 照合、解析解テスト）、GPU 計測とベンチ

### v0.1 以降（ロードマップ順）

- Wavefront、Vulkan バックエンド（RTX 3080）、Octane 比較、ReSTIR、差分更新、IPR 編集
- Blender 連携、NRC、Temporal 再利用、Motion Blur、Outline / 顔影 / 髪ハイライト
- Cinema 4D、Maya 等の DCC（USD / Hydra の評価を含む）、OptiX 比較
- 体積、SSS、髪・カーブ、ディスプレイスメント、Out-of-core、マルチ GPU

### 対象外

- 自前の CPU 参照レンダラー（Mitsuba 3 照合で代替。不足したら再検討）
- 分散・ネットワークレンダリング
- 反射・屈折越しのスタイル適用と BSDF / MIS 内のスタイル評価（Integrated Stylization）は Research 扱い
- スタイル参照画像からの自動推定（Style-aware Neural Rendering）は Research 扱い
- スペクトルレンダリング（分光 Dispersion を含む）は Research 扱い。RGB 近似を先に入れる

## 要件一覧

| ID | タイトル | 優先度 | ステータス |
|----|---------|--------|-----------|
| REQ-CORE-001 | Scene IR と変更 revision | Must | Draft |
| REQ-CORE-002 | パストレーシング Integrator | Must | Draft |
| REQ-CORE-003 | 基本 BSDF | Must | Draft |
| REQ-CORE-004 | テクスチャ・HDRI・ライト | Must | Draft |
| REQ-CORE-005 | カラーマネジメント | Must | Draft |
| REQ-CORE-006 | Reference モード | Must | Draft |
| REQ-CORE-007 | レンダリングモード | Should | Draft |
| REQ-GPU-001 | Metal RT バックエンド | Must | Draft |
| REQ-GPU-002 | Slang による Shader 一本化 | Must | Draft |
| REQ-GPU-003 | 最小の Backend 抽象と Capabilities | Must | Draft |
| REQ-GPU-004 | GPU 計測 | Must | Draft |
| REQ-GPU-005 | Wavefront と Compaction | Should | Draft |
| REQ-GPU-006 | Vulkan RT バックエンド | Must | Draft |
| REQ-GPU-007 | Backend 間の画像一致 | Must | Draft |
| REQ-GPU-008 | Render Graph | Should | Draft |
| REQ-STY-001 | HybridSurface | Must | Draft |
| REQ-STY-002 | ToonRamp | Must | Draft |
| REQ-STY-003 | ShadowPalette | Must | Draft |
| REQ-STY-004 | StylizedSpecular | Must | Draft |
| REQ-STY-005 | RimLight | Must | Draft |
| REQ-STY-006 | Lighting AOV の分離出力 | Must | Draft |
| REQ-STY-007 | Stylization Pass（一次ヒット Hybrid） | Must | Draft |
| REQ-STY-008 | 将来拡張のための設計制約 | Must | Draft |
| REQ-STY-009 | Outline・顔影・髪ハイライト | Should | Draft |
| REQ-STY-010 | Integrated Stylization（研究） | Could | Draft |
| REQ-STY-011 | PostProcess | Should | Draft |
| REQ-STY-012 | MatCap | Should | Draft |
| REQ-IO-001 | glTF 2.0 入力 | Must | Draft |
| REQ-IO-002 | Stylization 用 glTF 拡張 | Must | Draft |
| REQ-IO-003 | EXR 多チャンネル出力 | Must | Draft |
| REQ-IO-004 | UDIM・タイル化・オンデマンド読込 | Should | Draft |
| REQ-IO-005 | USD の評価 | Could | Draft |
| REQ-ACC-001 | デノイズ | Must | Draft |
| REQ-ACC-002 | ReSTIR | Should | Draft |
| REQ-ACC-003 | 差分更新エンジン | Should | Draft |
| REQ-ACC-004 | Neural Radiance Cache | Should | Draft |
| REQ-ACC-005 | Temporal 再利用と Motion Blur | Should | Draft |
| REQ-ACC-006 | Adaptive Integrator（研究） | Could | Draft |
| REQ-ACC-007 | 画素単位の Adaptive Sampling | Should | Draft |
| REQ-DCC-001 | Blender RenderEngine | Must | Draft |
| REQ-DCC-002 | Blender IPR | Must | Draft |
| REQ-DCC-003 | 材質変換 | Should | Draft |
| REQ-DCC-004 | Cinema 4D | Should | Draft |
| REQ-DCC-005 | Maya などの DCC | Could | Draft |
| REQ-VIEW-001 | render-cli | Must | Draft |
| REQ-VIEW-002 | 最小 Viewer | Must | Draft |
| REQ-VIEW-003 | IPR 編集 | Should | Draft |
| REQ-QA-001 | 参照レンダラー照合 | Must | Draft |
| REQ-QA-002 | 解析解テスト | Must | Draft |
| REQ-QA-003 | Stylization 評価 | Should | Draft |
| REQ-QA-004 | テストシーン管理 | Must | Draft |
| REQ-PERF-001 | ベンチハーネス | Must | Draft |
| REQ-PERF-002 | 退行検知 | Must | Draft |
| REQ-PERF-003 | 規模の下限 | Must | Draft |
| REQ-PERF-004 | Octane 比較 | Should | Draft |
| REQ-PERF-005 | 研究目標（保証しない） | Could | Draft |
| REQ-PERF-006 | Texture Out-of-Core | Should | Draft |
| REQ-INFRA-001 | Cargo workspace とクレート構成 | Must | Draft |
| REQ-INFRA-002 | CI | Should | Draft |
| REQ-INFRA-003 | ライセンス方針と依存検査 | Must | Draft |
| REQ-INFRA-004 | ドキュメント構成と状態管理 | Must | Draft |
| REQ-INFRA-005 | エージェント向け規約と言語の使い分け | Must | Draft |
| REQ-INFRA-006 | 対応プラットフォーム | Must | Draft |
| REQ-INFRA-007 | 開発ツールチェーン（mise） | Should | Draft |

## 未決事項

| 項目 | 決める時期 |
|------|-----------|
| Verion のライセンス、オープンコアの境界 | 最初の外部配布の前（ADR-0004、ADR-0018） |
| Stylization 用 glTF 拡張のスキーマ詳細 | M2 着手時（仕様書で確定） |
| Viewer の GUI 技術 | M2 着手時 |
| ~~Metal 向けデノイザーの選定（OIDN / MetalFX）~~ | 決定済み（ADR-0013） |
| ~~絶対速度目標（ADR-0010 で M3 後に保留）~~ | 決定済み（ADR-0014: 置かず、退行ゲートと M5 の同画質到達時間で縛る） |
| M1/M2 チップ（RT 非搭載）の扱い | M7 まで保留。M3 以降のみ対象 |
| Linux 対応 | M4 以降 |
| ~~環境光だけで照明したときの Toon の段~~ | 決定済み（ADR-0020: HDRI から仮想の主光源を求める。実装は M6） |

## 用語集

| 用語 | 定義 |
|------|------|
| Time to Quality | 規定の画質誤差に到達するまでの時間 |
| Scene IR | DCC に依存しない内部のシーン表現 |
| HybridSurface | PBR と Toon を成分別にブレンドするマテリアル |
| Lighting AOV | Direct Diffuse・Indirect Diffuse・Specular・Shadow などの成分別出力 |
| Stylization Pass | Lighting AOV から最終色を合成する後段 |
| 一次ヒット | カメラレイが最初に当たる表面。v0.1 のスタイル評価の対象 |
| Reference モード | NPR と AI 近似を切った物理パストレーシング |
| NEE / MIS | 直接光サンプリング / 多重重点サンプリング |
| ReSTIR | 光サンプルの時空間再利用 |
| NRC | Neural Radiance Cache。間接光をネットワークで近似する |
| IPR | 編集に追従する対話的プレビュー |
