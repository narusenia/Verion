# ADR-0005: 差別化の軸を Stylization に置く

- 状態: 採用
- 日付: 2026-11-04

## 背景

草案は物理・AI 高速化・Stylization の 3 コアを並列に掲げ、Octane 超えの数値目標も置く。個人開発では全並走できない。Octane は長年最適化されており、MVP 段階で速度で勝つのは難しい。

## 決定

- 優先順位は 表現力 > 速度。速度も追うが、表現力を妨げない範囲に限る
- v0.1 の成功は、Metal 上の PBR パストレース（Reference と一致）と、HybridSurface による写実〜Toon の連続調整 + AOV 分離出力
- Octane 比較は v0.1 の成功条件に含めない。ReSTIR / NRC の導入後に評価する
- Stylization（草案の M2.5）を Wavefront（M2）より前に置く

## 結果

- ロードマップは ADR-0011
