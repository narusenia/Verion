# glTF 拡張 `VERION_materials_stylization`

材質に Stylization の設定を載せる glTF 拡張（REQ-IO-002）。取り込み先は Material IR の `Stylization Layers`（ADR-0003、ADR-0008）。機械可読な定義は [JSON Schema](schemas/VERION_materials_stylization.schema.json)。

## 置き場所と宣言

- 材質の `extensions.VERION_materials_stylization` に置く
- 使うファイルは `extensionsUsed` に宣言する。`extensionsRequired` には入れない（拡張を知らない処理系は、通常の PBR として描画できる）
- 拡張がない材質は通常の PBR。Stylization 層は空になる

## プロパティ

どちらも省略できる。

### `hybridSurface`（REQ-STY-001）

成分ごとの写実 / スタイライズ度。0 が物理、1 が完全な Toon。省略した成分は 0。

| プロパティ | 型 | 範囲 | 既定 |
|---|---|---|---|
| `diffuse` | number | 0〜1 | 0 |
| `specular` | number | 0〜1 | 0 |
| `gi` | number | 0〜1 | 0 |
| `shadow` | number | 0〜1 | 0 |
| `outline` | number | 0〜1 | 0 |

`hybridSurface` ごと省略した場合は、全成分 0 として扱う。

### `toonRamp`（REQ-STY-002）

光の寄与を段階化する。バンド数は `thresholds` の長さ + 1。バンドは暗い側から明るい側へ並ぶ。

| プロパティ | 型 | 内容 |
|---|---|---|
| `thresholds` | number の配列 | 各境界の値。各要素は 0〜1 で、厳密に増加する。空配列は 1 バンド |
| `feather` | number（0〜1、既定 0） | 各境界のぼかし幅。0 は階段 |
| `palette` | number[3] の配列 | バンドごとの線形 RGB 乗数。長さは `thresholds` の長さ + 1。各値は 0 以上の有限値 |
| `lightWrap` | number（0〜1、既定 0） | 光が境界線を越えて回り込む量 |

- `thresholds` と `palette` は必須
- 閾値が見る値（応答）は、単位強度の光が正面から当たったときに 1 になる量。現状は、直接拡散の輝度から albedo を割って求める近似で、光ごとの N·L ではない（`verion-stylization` の `stylize` を参照）

## 解釈

- `toonRamp` は `hybridSurface.diffuse` が 0 より大きいときだけ効く。拡散成分に対して、物理値と Toon の値を `diffuse` で混ぜる
- v0.1 で効くのは `hybridSurface.diffuse` と `toonRamp` だけ。他の成分の値は読み込んで保持するが、描画には効かない（REQ-STY-003〜005 の実装後に効く）
- パレットの色は glTF の色係数と同じく線形 Rec.709 で書く。取り込み時に作業色空間へ変換する
- Reference モードは拡張を読み込んでも適用しない（ADR-0008）。拡張の有無で Reference の画は変わらない
- 拡張を持つ材質を足すと、Scene の stylization revision が増える

## 検証

取り込み時に `StylizationLayer::validate` と同じ規則で検査する。JSON Schema で表せない次の条件も含む。

- `thresholds` が厳密に増加する
- `palette` の長さが `thresholds` の長さ + 1 になる

範囲外の値や上の条件違反は、そのファイルの取り込みエラーにする（黙って丸めない）。未知のプロパティは警告して無視する。

## 例

```json
{
  "materials": [{
    "pbrMetallicRoughness": {"baseColorFactor": [0.8, 0.5, 0.4, 1]},
    "extensions": {
      "VERION_materials_stylization": {
        "hybridSurface": {"diffuse": 1.0, "specular": 0.0},
        "toonRamp": {
          "thresholds": [0.3, 0.7],
          "feather": 0.05,
          "palette": [[0.35, 0.3, 0.5], [0.75, 0.7, 0.8], [1, 1, 1]],
          "lightWrap": 0.1
        }
      }
    }
  }],
  "extensionsUsed": ["VERION_materials_stylization"]
}
```

## 未決

- `ShadowPalette`、`StylizedSpecular`、`RimLight`（REQ-STY-003〜005）の記述は、実装時にこの仕様へ追加する
- 閾値の応答の定義は、光ごとの入力へ移した時点で改める。移行時は拡張の版を上げる
