# STY 要件定義（Stylization）

対象クレート: `verion-stylization`、`shaders/stylization/`

方式は一次ヒットの Hybrid（ADR-0008）。物理経路と非物理経路を出力メタデータで区別する。

## REQ-STY-001: HybridSurface

| 項目 | 内容 |
|------|------|
| ID | REQ-STY-001 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

PBR と Toon を成分別（Diffuse・Specular・GI・Shadow・Outline）にブレンドするマテリアル。各成分の写実 / スタイライズ度を個別に設定できる。

### 受入条件

- [ ] 写実から Toon までの連続調整ができる
- [ ] 成分別の設定が Material IR の `Stylization Layers` に入る

### 依存要件

- REQ-CORE-001

## REQ-STY-002: ToonRamp

| 項目 | 内容 |
|------|------|
| ID | REQ-STY-002 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

Shadow Band 数、閾値、Feather、色パレット、Light Wrap。

### 受入条件

- [ ] 光ごとの寄与に対して段階化できる

### 依存要件

- REQ-STY-006

## REQ-STY-003: ShadowPalette

| 項目 | 内容 |
|------|------|
| ID | REQ-STY-003 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

直射影・間接影の色補正（Hue Shift・彩度・明度）。

### 受入条件

- [ ] 直射影と間接影を別々に補正できる

### 依存要件

- REQ-STY-006

## REQ-STY-004: StylizedSpecular

| 項目 | 内容 |
|------|------|
| ID | REQ-STY-004 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

帯状・楕円・手描き風のハイライト形状。

### 受入条件

- [ ] 形状の種類と大きさをパラメータで指定できる

### 依存要件

- REQ-STY-006

## REQ-STY-005: RimLight

| 項目 | 内容 |
|------|------|
| ID | REQ-STY-005 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

法線・視線・ライト方向によるリム光。

### 受入条件

- [x] ライト方向に追従する（`followLight`。複数の光を 1 スロットにまとめた場合は方向が平均になる）

### 依存要件

- REQ-STY-006

## REQ-STY-006: Lighting AOV の分離出力

| 項目 | 内容 |
|------|------|
| ID | REQ-STY-006 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

Direct Diffuse・Indirect Diffuse・Specular・Transmission・Shadow/Visibility・Emission・Normal・Depth・Material ID・Object ID・Motion Vector を単一 RGB に合成せず保持して出力する。

### 受入条件

- [ ] EXR に AOV が分離して入る
- [ ] Normal / Depth / ID は v0.1 から出力する（Outline の準備）

### 依存要件

- REQ-CORE-002
- REQ-IO-003

## REQ-STY-007: Stylization Pass（一次ヒット Hybrid）

| 項目 | 内容 |
|------|------|
| ID | REQ-STY-007 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

一次ヒットで成分別に評価し、Stylization Pass が最終色を合成する。反射・屈折越しの像は物理のまま。Denoise は Stylization の前に適用でき、Toon 境界は AOV で保持する。

### 受入条件

- [ ] Reference モードと同じパストレースを共有する
- [ ] 写実材質と Toon 材質が同一シーンに混在しても、写実材質の出力は Reference と一致する（写実と Toon の混在を M3 以降の軸にする。反射・屈折越しの Toon は REQ-STY-010）
- [ ] デノイズが Toon 境界と意図したテクスチャを消さない（REQ-QA-003）

### 依存要件

- REQ-STY-001
- REQ-STY-006
- REQ-ACC-001

## REQ-STY-008: 将来拡張のための設計制約

| 項目 | 内容 |
|------|------|
| ID | REQ-STY-008 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

Integrated Stylization（REQ-STY-010）へ拡張できるよう、次を v0.1 から守る。

### 受入条件

- [ ] Stylization 関数は一次ヒット専用でなく、汎用の `ShadingContext`（位置・法線・光ごとの成分・深度）を受け取る
- [ ] Material IR が `Base BSDF` / `Stylization Layers` / `Output Channels` を分離している
- [ ] AOV とキャッシュ類に Stylization revision を持たせる
- [ ] `Stylization Layers` は 1 材質に複数の層を並べ、順に適用できる（ToonRamp・StylizedSpecular・RimLight などを重ねる）

### 依存要件

- REQ-CORE-001

## REQ-STY-009: Outline・顔影・髪ハイライト

| 項目 | 内容 |
|------|------|
| ID | REQ-STY-009 |
| 優先度 | Should |
| ステータス | Draft |

### 説明

`OutlineStyle`、`FaceShadowController`（Face SDF）、`HairHighlight`。独立 Pass に分け、時間的安定性を評価する。M8。ただし `OutlineStyle` の最小版（出力済みの Normal・Depth・Object ID・Material ID から画面空間で作る静止画の輪郭）は、REQ-STY-011 の最初の Pass として M2 で入れる。

### 受入条件

- [ ] カメラ・ライト・キャラ移動で線の跳ねと顔影の破綻が出ない（REQ-QA-003）

### 依存要件

- REQ-STY-007
- REQ-ACC-005

## REQ-STY-011: PostProcess

| 項目 | 内容 |
|------|------|
| ID | REQ-STY-011 |
| 優先度 | Should |
| ステータス | Draft |

### 説明

Stylization 後段の画面空間 Pass。M2 は Pass の枠と最小の色調整（ゲイン・彩度・ホワイトバランス）。ブルーム・色収差は M8 で扱う。背景合成は内部で行わず、アルファと Object ID を出して外部で合成する。PostProcess は非物理出力で、Reference モードでは無効にし、メタデータに記録する。

### 受入条件

- [ ] Stylization の後段に PostProcess の Pass を並べられる
- [ ] 色調整を適用でき、Reference モードでは無効になる
- [ ] 適用した PostProcess を EXR のメタデータに記録する

### 依存要件

- REQ-STY-007

## REQ-STY-010: Integrated Stylization（研究）

| 項目 | 内容 |
|------|------|
| ID | REQ-STY-010 |
| 優先度 | Could |
| ステータス | Draft |

### 説明

段階 A: 鏡面・屈折チェーン越しの 2 次ヒットでも Stylization 関数を呼ぶ。段階 B: BSDF / PDF / MIS 内でスタイルを評価する（収束性と不偏性が変わるため別アルゴリズム）。

### 受入条件

- [ ] 段階 A の実現性を検証し、結果を ADR に記録する

### 依存要件

- REQ-STY-008
