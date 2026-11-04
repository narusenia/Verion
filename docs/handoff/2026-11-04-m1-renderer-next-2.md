# 引き継ぎ: M1 項目 8 の目視確認と Mitsuba 3 照合から再開

## 済み（`main` に push 済み、9645bfd。CI は未確認）
- 項目 6: スムースシェーディング・法線マップ（UV 導出の接線）・Spot ライト・HDRI（`.hdr` 自前 / `.exr`）
- 項目 7: `ColorSpace`（Rec.709 / ACEScg）、`OutputTransform`、glTF 取り込み時の色変換（`load_gltf_in`）
- 項目 8: `write_exr`（Beauty + Normal、メタデータ、chromaticities）。`exr` crate 追加、`deny.toml` に paste の例外
- メモ済み: `docs/implementation/M1-metal-pt/README.md` の項目表と既知の制限

## 協議で決めたこと
- EXR 目視確認: `verion-render-io` を `verion-gpu-metal` の **dev-dependency** にして example（`render_ppm` など）から EXR を出し、外部ビューアで AOV を確認する。production の依存方向は変えない
- Mitsuba 3 照合（項目 12）: やる。導入は新ソフトなので方法（pip / brew 等）をユーザーに確認してから
- M4 Pro 実機確認: **後日**（ユーザーが実施。それまで README の「M4 Pro 未確認」を残す）
- 薄レンズのボケ量、ADR-0002 の SPIR-V 側: 後回し

## 未完了
- 項目 8: 外部ビューアでの目視確認、Albedo・Depth・ObjectId AOV
- 項目 6・5・3・1 を「完了」にする判断（Mitsuba 3 照合の後）
- REQ-CORE-002〜005・REQ-IO-003 の受入条件チェックは未更新（照合後）
- 実ファイルの glTF（Khronos サンプル、法線マップ付き）未確認

## 次の一手
1. ブランチ `feat/exr-example`（案）: dev-dependency を足して example で EXR を出力 → 目視確認をユーザーに依頼
2. Mitsuba 3 の導入方法を確認 → 同一シーンを glTF で用意して比較

## 進め方の合意（従来どおり）
- スライスごとに新規ブランチ、論理単位でコミット（英語 1 行・prefix）、PR なしで `main` にマージ、push は毎回確認
- 新しい依存・ツールは頼まれたときだけ。docs の更新はユーザーに確認。コマンドの終了コードは直接確認（パイプで隠さない）

## 新しい会話の最初の一言
「docs/handoff/2026-11-04-m1-renderer-next-2.md を読んで、次の着手から進めて」
