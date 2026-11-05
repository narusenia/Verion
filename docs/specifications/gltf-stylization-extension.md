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
- 閾値が見る値（応答）は、光ごとの cosθ × 可視性（0〜1）。光の強さは含まない。したがって光を強くしても段の位置は変わらず、影になった光は最も暗いバンドに入る。光ごとに段階化して足す
- 点・平行・スポットは光ごとに、面光源（発光メッシュ）と環境光は 1 つにまとめて扱う。まとめた分の応答は、寄与で重み付けしたサンプル平均になり、面光源の柔らかい境界は平均化される。点・平行・スポットが 4 つ以上あると、3 つ目以降は同じ枠を共有する（`LIGHT_SLOTS`）

### `shadowPalette`（REQ-STY-003）

影になった部分の色補正。直接影と間接影を別々に指定する。省略した側と、省略した項目は補正なし。

| プロパティ | 型 | 内容 |
|---|---|---|
| `direct` | object | 直接拡散の影の補正 |
| `indirect` | object | 間接拡散（影を埋める回り込み光）の補正 |

`direct` と `indirect` は同じ形で、各項目は省略できる。

| プロパティ | 型 | 範囲 | 既定 |
|---|---|---|---|
| `hueShift` | number | −180〜180（度） | 0 |
| `saturation` | number | 0 以上（彩度の倍率） | 1 |
| `value` | number | 0 以上（明度の倍率） | 1 |

### `rimLight`（REQ-STY-005）

輪郭付近に出る縁取りの光。非物理で、色と強さは光の強さに依存しない。

| プロパティ | 型 | 範囲 | 既定 | 内容 |
|---|---|---|---|---|
| `color` | number[3] | 各値 0 以上の有限値 | [1, 1, 1] | リムの色（線形 Rec.709） |
| `width` | number | 0〜1 | 0.3 | リム帯の幅 |
| `feather` | number | 0〜1 | 0.05 | 帯の縁のぼかし幅 |
| `followLight` | number | 0〜1 | 1 | 0 は全周に出る、1 は光に面した側だけに出る |
| `strength` | number | 0 以上の有限値 | 1 | 加算の強さ。0 で無効 |

- すべて省略できる。`rimLight` を書くと、既定値でリムが有効になる
- `hybridSurface` には依存しない（`strength` が強さを決める）

### `stylizedSpecular`（REQ-STY-004）

鏡面ハイライトを、光ごとの帯状の形に置き換える。非物理。v0.1 の形状は帯状のみ。

| プロパティ | 型 | 範囲 | 既定 | 内容 |
|---|---|---|---|---|
| `shape` | string | `"band"` のみ | `"band"` | 形状の種類。ほかの値は取り込みエラー（楕円・手描き風は後続） |
| `size` | number | 0〜1 | 0.05 | ハイライトの大きさ。`1 − N·H` が `size` 以下の範囲 |
| `feather` | number | 0〜1 | 0.02 | 縁のぼかし幅 |
| `color` | number[3] | 各値 0 以上の有限値 | [1, 1, 1] | ハイライトの色（線形 Rec.709） |
| `strength` | number | 0 以上の有限値 | 1 | ハイライトの強さ。光の強さには依存しない |
| `ramp` | object | `toonRamp` と同じ形 | なし | ハイライトを複数の段にする（芯と暈など）。省略すると 1 本の帯 |

- すべて省略できる。`hybridSurface.specular` が 0 より大きいときだけ効く
- `ramp` があるとき、帯の代わりに段で決める。応答は `clamp(1 − (1 − N·H) / size, 0, 1)`（ハイライトの中心が 1、`size` の縁が 0）で、`thresholds` はこの値に対する境界。`palette` はハイライトの色の乗数で、`palette[0]` がハイライトの外側の値（通常は [0, 0, 0]）。`feather` と `lightWrap` も `toonRamp` と同じ意味で効く。`size` は応答の範囲を決める

### `outlineStyle`（REQ-STY-009 の最小版）

物体の輪郭と折れ目に線を引く。非物理で、隣の画素を見る後段（PostProcess）で作る。

| プロパティ | 型 | 範囲 | 既定 | 内容 |
|---|---|---|---|---|
| `color` | number[3] | 各値 0 以上の有限値 | [0, 0, 0] | 線の色（線形 Rec.709） |
| `width` | number | 1〜8（画素） | 2 | 線の太さ。物体の内側へ伸びる |
| `depthThreshold` | number | 0〜1 | 0.05 | 隣との深度差の割合。超えると輪郭 |
| `creaseAngle` | number | 0〜180（度） | 45 | 隣との法線の角度差。超えると折れ目 |

- すべて省略できる。線の不透明度は `hybridSurface.outline`（0 で線なし、1 で完全）。`outlineStyle` を書いても `outline` が 0 なら線は出ない

## 解釈

- 輪郭線は PostProcess で、画素ごとの Stylization の後に、Depth・Normal・Object ID・Material ID の AOV から作る。各画素について、半径 `width` 画素の隣接を見て、次のどれかなら輪郭画素にする
  - 隣が背景（Material ID が 0）
  - 隣の深度が、自分の深度より `depthThreshold`（割合）以上遠い。別の物体でも同じ物体でもよい
  - 同じ物体で、隣との法線の角度差が `creaseAngle` を超える（折れ目）
- 線は近いほうの物体の画素に描く。背景の画素は変えない。線の色は、その画素の材質の `outlineStyle`。`outlineStyle` のない材質は線が出ない。ビューティを `線の色` と `hybridSurface.outline` の割合で混ぜる
- `stylizedSpecular` は、物理の鏡面（直接光のハイライト）を、`hybridSurface.specular` で Toon のハイライトへ混ぜる。光ごとのスロットで、半ベクトル H（光の方向と視線から作る）を使う
  - 光 k のハイライト: `color × strength × 帯(1 − N·H) × 可視性`。帯は `size`・`feather` の smoothstep を反転したもの（縁の内側が 1）。`ramp` があるときは、帯の代わりに `ramp` の段の値（色の乗数）を使う
  - 光が鏡面を持たないスロット（鏡面の寄与がほぼ 0。Lambert など）は出さない
  - 全スロットのハイライトを足す。結果と物理の鏡面を `physical + (stylized − physical) × specular` で混ぜる
  - 環境の映り込みなど、直接光でない鏡面（間接鏡面）は、物理の鏡面に含まれたまま。`hybridSurface.specular` が 1 のときは、直接光のハイライトだけでなく間接鏡面も含めて置き換わる（v0.1 の制限）
- `rimLight` は最終色にリムを加算する。法線 N、視線 V、光の方向 L から次で求める
  - 帯: `x = 1 − max(N·V, 0)` を、閾値 `1 − width`、ぼかし幅 `feather` の smoothstep にかけた値。`width` が大きいほど内側まで出る
  - 光への追従: `lerp(1, saturate(N·L), followLight)`。L は光ごとのスロットの方向
  - 光の分担: スロットごとの寄与（拡散と鏡面の輝度の和）を、全スロットの寄与で割った値。合計が 1 なので、光が複数あっても明るさは増えない
  - 出力への加算: `color × strength × 帯 × Σ(分担 × 追従 × 可視性)`。可視性は、そのスロットの光が遮られていない割合。影に入った光のリムは出ない
- `toonRamp` は `hybridSurface.diffuse` が 0 より大きいときだけ効く。拡散成分に対して、物理値と Toon の値を `diffuse` で混ぜる
- `shadowPalette` は `hybridSurface.shadow` が 0 より大きいときだけ効く。補正の強さは `shadow` に比例する
  - 影の度合い `w` は、直接拡散が光から受け取れる量にどれだけ届いていないか（0 は全面照明、1 は完全な影）。直接拡散と間接拡散を、それぞれ `補正前 + (補正後 − 補正前) × w × shadow` に置き換える
  - 色相・彩度・明度は、最大チャンネルを明度とする HSV で扱う。黒は補正しても黒のまま（影が真っ黒になる材質では、直接影は色が付かない。`toonRamp` の暗いバンドで色を持たせる）
- `hybridSurface.gi` は間接拡散を平坦にする。間接拡散を「アルベド × その材質の一定の環境光」へ `gi` の割合で置き換える。一定の環境光は、フレーム内でその材質の画素すべてについて、間接拡散の和 ÷ アルベドの和（チャンネルごと）。層（`shadowPalette` など）が間接拡散を補正する前に適用する。材質を共有する物体は同じ値を共有し、視点が変わると値も変わる（動画での安定は M8）
- 効くのは `hybridSurface` のすべての成分（`outline` は `outlineStyle` と組で）、`toonRamp`、`shadowPalette`、`rimLight`、`stylizedSpecular`、`outlineStyle` だけ
- 層は材質に書いた順に適用する。同じ種類の層を複数書いても、順に適用する（glTF 拡張では種類ごとに 1 つ）
- パレットの色は glTF の色係数と同じく線形 Rec.709 で書く。取り込み時に作業色空間へ変換する
- Reference モードは拡張を読み込んでも適用しない（ADR-0008）。拡張の有無で Reference の画は変わらない
- 拡張を持つ材質を足すと、Scene の stylization revision が増える

## 検証

取り込み時に `StylizationLayer::validate` と同じ規則で検査する。JSON Schema で表せない次の条件も含む。

- `thresholds` が厳密に増加する
- `palette` の長さが `thresholds` の長さ + 1 になる
- `rimLight.color` と `rimLight.strength` が 0 以上の有限値になる
- `stylizedSpecular.color` と `stylizedSpecular.strength` が 0 以上の有限値になる。`stylizedSpecular.shape` が `"band"` である
- `stylizedSpecular.ramp` は `toonRamp` と同じ規則で検査する
- `outlineStyle.color` が 0 以上の有限値になる

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
        },
        "rimLight": {"color": [0.9, 0.95, 1.0], "width": 0.25, "followLight": 1.0}
      }
    }
  }],
  "extensionsUsed": ["VERION_materials_stylization"]
}
```

## 未決

- 楕円・手描き風のハイライト形状（REQ-STY-004）。楕円は接線、手描き風はテクスチャが要る

## 決定済みの近似

- 間接影: 間接拡散そのものに補正をかけ、影の度合いで重みを付ける。間接光の遮蔽（AO 的）は取らない。取るのは M2 の範囲外
- ライトスロットは 4 枠（`LIGHT_SLOTS`）。点・平行・スポット光はライト番号順に slot 0〜2 へ入れ、3 個目以降は slot 2 に合算する。発光三角形と環境光は slot 3 に同居する
- 面光源・環境光: slot 3 の ramp 入力は、サンプルごとの cosθ × 遮蔽を寄与で重み付けして平均した値。代表方向は持たない
- Visibility AOV: 直接光の輝度で重み付けした、遮蔽されていない割合（lit / total）

## 既知の制限

- ライトスロットは、拡散 `u`・鏡面 `s`・光の方向・可視性を持つ。複数の光を 1 つのスロットにまとめた場合（点・平行・スポットが 4 つ以上、または面光源・環境光）、方向は平均になる。RimLight の向きは曖昧になり、方向が打ち消し合うと弱まる
- 環境光は寄与加重の平均なので、太陽のような強い光源があれば段が出る（実画像で確認済み）。太陽のない拡散した HDRI では平均で段が潰れる可能性がある（未確認）
- 輪郭線の `width` は画素単位なので、解像度を上げると画面に対して細くなる。細い面や、同じ物体の浅い折れ目は拾えないことがある（未検証）。時間的な安定は M8（REQ-STY-009）
- 光が 4 つ以上あると、3 個目以降の光は slot 2 で平均され、ramp の入力が混ざる。ライト番号順で見た目が変わる
- 寄与の大きい順に割り当てる方式と、環境光の独立スロットは見送った。割り当てが画素ごとに入れ替わると段の境界が跳ねるため。画素あたりの容量も増える
