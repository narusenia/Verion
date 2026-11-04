# 引き継ぎ: M1 は docs 更新の確認から再開（項目 13 ベンチ基盤が次の大物）

## 済み（すべて `main` 反映・push 済み。5b69882）
- 項目 9 render-cli: `render-cli scene.gltf -o out.exr [--width --height --spp --hdri --mode --metrics]`。8spp ごとの進捗バー（indicatif）、glTF にカメラが無ければ境界球に合わせて +z 側へ自動配置
- 項目 11 Reference モード: `--mode reference`（唯一の値）、EXR の `physical` は mode から決定。「Stylization を通らない」の検証テストは `StylizationLayer` が空 enum で書けず、REQ-STY-001 待ち
- 項目 10 GPU 計測: `Accumulation::gpu_seconds`（コマンドバッファのタイムスタンプ）、`--metrics` の `gpu_s`。trace / shade の分離は 1 カーネルのため不可（REQ-GPU-005 Wavefront 後）
- 白炉テスト拡張: 粗い金属を GGX 単一散乱アルベドの数値積分と照合（8 点、0.01 以内）、拡散+鏡面の誘電体、粗いガラス
- FLIP: `mise run crosscheck` が HDR-FLIP の Mean/Max を表示（`pipx:flip-evaluator` 1.7、表示のみ）。値はノイズ床と同水準（box 0.0454 vs Mitsuba 同士 0.0444、spot 0.0778 vs 0.0742）
- crosscheck の不具合修正: EXR の `<root>` が 5 チャンネルになり全シーン FAIL していたのを RGB 3 チャンネル読みに修正
- 受入条件を更新: REQ-VIEW-001 の計測 JSON、REQ-CORE-006 のメタデータにチェック。REQ-GPU-004 は合計のみのため未チェック（注記済み）

## 決めたこと
- ガラスの白炉は球で測る（立方体は全反射トラップ＋深さ 8 の打ち切りで 0.75 になり BSDF の誤りと区別できない）
- FLIP・PSNR は表示のみ。合否は従来どおり（平均輝度の最悪チャンネル 1% 以内、4x4 ブロック平均 2% 以内）
- numpy は不要だった（flip-evaluator は引かない）。追加していない

## 未解決
- **docs 更新の確認待ち**: README 項目 12 に「白炉済み・FLIP 表示済み・粗いガラスの損失」を追記するか。REQ-QA-002 と REQ-CORE-002 の白炉チェックを付けるか（多重散乱補正なしの損失を許容誤差扱いにする前提）
- 粗いガラス（粗さ 0.6 で約 25% 暗い）と粗さ 1.0 の金属（約 60%）の損失は単一散乱の既知制限だが、README の「既知の制限」は粗さ 0.5 の金属「最大 10%」のみ
- push 後の CI 結果が未確認（`gh run list`）
- REQ-VIEW-001「CI のテストとベンチから呼べる」は未達（CI に Metal GPU が無い。ベンチ基盤は項目 13）
- 実物の HDRI 照合（素材はユーザーが選ぶ）、glTF 実ファイルの法線マップ確認（DamagedHelmet は取得・描画済みだが目視は自動フレーミング前後の 1 枚のみ）
- 項目 1・3・5・6 を「完了」にする判断と REQ-CORE-002〜005 の受入条件
- M4 Pro 実機確認はユーザーが後日（README の「M4 Pro 未確認」を残す）
- 後回し: 薄レンズのボケ量、ADR-0002 の SPIR-V 側、occlusion テクスチャ対応

## 次の一手
1. docs 更新（上記）の可否を確認して反映
2. CI の結果確認
3. 項目 13 ベンチ基盤（REQ-PERF-001〜003）。`render-cli --metrics` の JSON が入口になる

## 進め方の合意（従来どおり）
- スライスごとに新規ブランチ、論理単位でコミット（英語 1 行・prefix）、PR なしで `main` にマージ、push は毎回確認
- 新しい依存・ツールは頼まれたときだけ（今回は clap・indicatif・flip-evaluator を許可済み）。docs の更新はユーザーに確認。コマンドの終了コードは直接確認

## 新しい会話の最初の一言
「docs/handoff/2026-11-04-m1-renderer-next-4.md を読んで、次の着手から進めて」
