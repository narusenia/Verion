# ADR-0014: Metal の既定は Megakernel のままにし、Wavefront は選択肢として残す

- 状態: 採用
- 日付: 2026-11-06

## 背景

REQ-GPU-005 は、Wavefront と Queue Compaction を作り、Megakernel との定量比較で採否を決めることを求めている。ADR-0010 は、絶対速度目標をこの比較の後に決めるとしている。

M3 で、パスの処理を関数に分けて両形式から同じコードを呼ぶ形にし、Wavefront（extend と shade の 2 段、SoA の状態、atomic によるキューの圧縮、間接 Dispatch）を実装した。画像は全シーンで Megakernel とビット一致する。

## 比較

Apple M5、1024×768、256 spp（`docs/implementation/M3-wavefront/README.md` の表）:

- Wavefront は 1.13〜1.70 倍遅い。重いシーン（ガラス・HDRI）ほど差が小さく、軽いシーン（cube）と状態の多い Stylized（Lighting AOV）で差が大きい
- 差の主因はパス状態の読み書き（解像度に比例）。深さ 0 の状態を省き、状態を 16 語に詰めて 1.5〜4.4 倍から縮めた。SIMD 単位の atomic は効果がなかった
- Apple の GPU には SER（シェーダー実行の並べ替え）がなく、Megakernel の分岐の不揃いを Wavefront で解く利点が出にくい。シーンの材質の種類が少ないことも Wavefront に不利

## 決定

- Metal の既定は Megakernel のままにする
- Wavefront は `Integrator::Wavefront` として残す（同じコードなので保守の費用は小さい）。次の時点で再評価する
  - M4: Vulkan（RTX 3080）で、SER と組み合わせた比較
  - M5 以降: ReSTIR や NRC のように、段の間でパスをまとめて扱う処理が入ったとき（段の分離がそのまま使える）
  - 材質の種類が多い実シーン（M6 の Blender 連携）での比較。材質での並べ替えはそのときに試す
- 絶対速度目標（ADR-0010 の保留）は置かない。理由: オフライン・逐次表示のレンダラーで、速度は機材でほぼ決まり、比較でも構造上の大きな伸びしろは見えなかった。代わりに、機材と電源ごとのベースライン（`benchmarks/baseline/`）に対する 10% の退行ゲートを続け、速度の目標は M5 の「同画質到達時間」（REQ-PERF-005 と M5 の完了条件）で相対的に置く

## 結果

- trace / shade の時間の分離（REQ-GPU-004）は Wavefront の段別計測（`--stage-timing`）で得られる。Megakernel の分離計測は持たない
- 追記（2026-11-06、ADR-0015）: Megakernel を 1 スレッド最大 8 サンプルにして 7〜37% 速くなり、Wavefront との差は 1.25〜2.71 倍に広がった。既定は変えない
- Wavefront の状態とキューは 1024×768 で約 69 MB（Lighting AOV ありで約 120 MB）。キューの容量は画素数で固定（1 パス / 画素）。複数サンプルを 1 回の波に載せる案は、同じ画素への加算が競合するので採っていない
