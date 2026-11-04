# ADR-0008: Stylization は一次ヒットの Hybrid 方式で始める

- 状態: 採用
- 日付: 2026-11-04

## 背景

P0 の各ノードをどこで計算するかが未確定だった。候補は、純 Post（AOV の後段合成）、一次ヒットでの成分別評価 + AOV 合成（Hybrid）、BSDF / MIS 内の Integrated。

## 決定

- 一次ヒットで光ごとの成分を評価して AOV に出し、Stylization Pass で最終色を合成する
- 反射・屈折越しの像は物理のまま（v0.1 の制限）
- Integrated への拡張のため、次を v0.1 から守る（REQ-STY-008）:
  - Stylization 関数は汎用の `ShadingContext` を受け取り、任意の bounce から呼べる
  - Material IR を `Base BSDF` / `Stylization Layers` / `Output Channels` に分ける
  - AOV とキャッシュに Stylization revision を持たせる
- 拡張は 2 段階。段階 A は 2 次ヒットでも関数を呼んで AOV に書く（配管のみ）。段階 B は BSDF / PDF / MIS 内の評価で、収束性が変わるため別アルゴリズム（Research）

## 結果

- Reference モードと同じパストレースを共有できる
- 段階 B では v0.1 の合成 Pass の一部が不要になる可能性があり、作り直しゼロは保証しない
