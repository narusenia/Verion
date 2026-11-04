# VIEW 要件定義（CLI・Viewer）

対象: `apps/render-cli` / `apps/render-viewer`

## REQ-VIEW-001: render-cli

| 項目 | 内容 |
|------|------|
| ID | REQ-VIEW-001 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

`render-cli scene.gltf -o out.exr` の形でヘッドレスに描画する。サンプル数・モード・Stylization パラメータを引数で渡せる。QA とベンチの入口でもある。

### 受入条件

- [ ] CI のテストとベンチから呼べる（未: CI に Metal GPU が無く、呼び出しは未接続。ベンチ基盤は M1 項目 13）
- [x] 計測 JSON を出力できる（`--metrics`: 経過時間・`gpu_s`・mode）

### 依存要件

- REQ-CORE-002
- REQ-IO-003

## REQ-VIEW-002: 最小 Viewer

| 項目 | 内容 |
|------|------|
| ID | REQ-VIEW-002 |
| 優先度 | Must |
| ステータス | Draft |

### 説明

Metal レイヤーで累積（プログレッシブ）表示する。AOV を切り替えられ、Stylization パラメータのスライダで変更→再累積できる。GUI 技術は M2 着手時に決める。

### 受入条件

- [ ] 写実から Toon への連続調整を見ながら行える
- [ ] AOV を切り替えて表示できる
- [ ] シーン変更への追従は含まない（REQ-VIEW-003）

### 依存要件

- REQ-VIEW-001
- REQ-STY-007

## REQ-VIEW-003: IPR 編集

| 項目 | 内容 |
|------|------|
| ID | REQ-VIEW-003 |
| 優先度 | Should |
| ステータス | Draft |

### 説明

シーン変更を検知して部分更新する。M5 の差分更新エンジンに接続する。

### 受入条件

- [ ] Camera・Material・Light・Transform の変更に追従する

### 依存要件

- REQ-ACC-003
- REQ-VIEW-002
