# ADR-0003: v0.1 のシーン入力は glTF 2.0 + 独自拡張

- 状態: 採用
- 日付: 2026-11-04

## 背景

Blender 連携（M6）の前に、シーンを入力する経路が要る。候補は glTF、USD（+ MaterialX）、独自形式。

## 決定

- 入力は glTF 2.0 と HDRI。Stylization は材質の `extensions` に JSON 拡張で載せる
- Scene IR は glTF に縛られない内部型として分離する。Blender / C4D アダプタは IR を直接生成する
- USD は必須にしない。M9 で USD / Hydra delegate を再評価する

## 結果

- Cornell Box や既存のテストシーンをすぐ使える
- 材質表現は glTF PBR + 拡張に限られる
