# 引き継ぎ: M1 は項目 9（render-cli）か 11（Reference モード）から再開

## 済み
- `main` 反映済み（b5464a1）: Mitsuba 3 照合（`mise run crosscheck`、5 シーン合格）、シェーダの視線側クランプ、AOV（Albedo・Depth・ObjectId、EXR 出力）。項目 8 は済、REQ-IO-003 受入条件チェック済み
- ブランチ `fix/smooth-normal-aov`（未マージ・未 push）: 法線 AOV を頂点法線の補間値に変更（1565e77）、README 更新（b4d10b4）。`mise run check` 通過

## 決めたこと
- 照合: 平均輝度の最悪チャンネル 1% 以内かつ 4x4 ブロック平均 2% 以内が合格。PSNR は表示のみ。CI には載せない（GPU 要）。クランプ値 0.05 は 0.01〜0.2 で鈍感なので維持
- 発光は両面に放射（仕様として既知の制限に記載済み）
- 実物の HDRI 照合は見送り（素材はユーザーが選んでから）

## 未解決
- CI の結果が未確認（Mitsuba・Python 3.12 を mise に追加した影響を含む）
- 項目 1・3・5・6 を「完了」にする判断。REQ-CORE-002〜005 の受入条件は未更新
- 未了: 白炉テスト、FLIP、実物の HDRI 照合、実ファイルの glTF（Khronos サンプル、法線マップ付き）確認
- M4 Pro 実機確認はユーザーが後日（README の「M4 Pro 未確認」を残す）
- 薄レンズのボケ量、ADR-0002 の SPIR-V 側は後回し

## 次の一手
1. `fix/smooth-normal-aov` を `main` にマージして push（ユーザーの確認待ち）
2. CI の結果確認
3. 項目 9（render-cli）または 11（Reference モード）に着手

## 進め方の合意（従来どおり）
- スライスごとに新規ブランチ、論理単位でコミット（英語 1 行・prefix）、PR なしで `main` にマージ、push は毎回確認
- 新しい依存・ツールは頼まれたときだけ。docs の更新はユーザーに確認。コマンドの終了コードは直接確認

## 新しい会話の最初の一言
「docs/handoff/2026-11-04-m1-renderer-next-3.md を読んで、次の着手から進めて」
