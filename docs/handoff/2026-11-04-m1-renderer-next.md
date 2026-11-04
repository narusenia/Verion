# 引き継ぎ: M1 項目 6 の残りから再開

## 済み（`main` に push 済み、CI は 6d まで成功を確認）
- 項目 3〜5: `verion-gpu-metal`（Device/BLAS/TLAS）、`verion-scene`（IR・revision）、`verion-render-io`（glTF）
- 項目 6: `shaders/{normals,pathtrace}.slang` と `Renderer`。Diffuse・GGX・ガラス・点/平行光源・面光源 MIS・HDRI 重点サンプリング・テクスチャ+ミップ
- 検査: `mise run check`、`mise run shaders:check`（生成 MSL の同期。pre-commit のみ）、実機テスト 23 件（M5）
- 目視: `cargo run --release -p verion-gpu-metal --example render_ppm -- <out_dir>`（PPM。PNG 化は標準ライブラリの Python で）

## 未完了
- 項目 6 の残り: Normal マップ、頂点法線によるスムースシェーディング、Spot ライト
- 項目 7 以降は `docs/implementation/M1-metal-pt/README.md` の表。項目 6・5・3・1 は「進行中」
- 既知の制限は同 README の末尾に記録済み（単一散乱 GGX、屈折の NEE なし、巻き方向依存など）

## 未確認
- M4 Pro など他環境での GPU テスト、Mitsuba 3 照合（項目 12）、実ファイルの glTF、薄レンズのボケ量
- ADR-0002 の SPIR-V 側とデバッグ性
- REQ-CORE-002/003/004 の受入条件チェックは未更新（照合後）

## 次の一手
- 次の着手をユーザーに確認する: Normal マップ / スムースシェーディング / 項目 7（カラーマネジメント）
- HDRI ファイル読み込みの依存は項目 8（EXR）と同時に決める（承認が要る）

## 進め方の合意
- スライスごとに新規ブランチ、論理単位でコミット（英語 1 行・prefix）、PR は作らず `main` にマージ。push は毎回確認を取る
- 新しい依存・ツールは頼まれたときだけ。docs の更新はユーザーに確認する

## 新しい会話の最初の一言
「docs/handoff/2026-11-04-m1-renderer-next.md を読んで、次の着手を相談して」
