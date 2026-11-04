# 引き継ぎ: M1 項目 1（Slang → MSL スパイク）から再開

## 決定事項（詳細は docs/adr/0001〜0011）
- Metal RT を先行（M4 Pro / M5）、Vulkan は M4 で追加。シェーダーは Slang 一本化（スパイクで検証、不可なら MSL ネイティブ）
- 入力は glTF 2.0 + 拡張 JSON。優先順は表現力 > 速度。Stylization は一次ヒットの Hybrid 方式
- ライセンスは保留（オープンコア寄り）。依存は商用再配布可のみ（cargo-deny）

## 済み
- 要件・ADR・ロードマップ・README を作成。`main` に push 済み
- M1 項目 2: Cargo workspace（`verion-scene`）、CI（GPU 不要のみ）、`architecture.md`。`mise run check` 通過

## 未完了
- M1 項目 1: Slang → MSL で Metal RT が動くかのスパイク。結論を ADR に記録する（採用 / 撤退）
- 項目 3 以降は `docs/implementation/M1-metal-pt/README.md` の表を参照

## 次の一手
- `feat/slang-msl-rt-spike` ブランチを `main` から切る
- `slangc` を `mise.toml` に追加して導入（導入は承認済み）。Slang の配布物の版とライセンスを確認して記録する
- `objc2-metal` で最小の Metal RT（三角形 1 枚の交差判定）を動かす。`unsafe` が必要なので spike 用のクレートで `unsafe_code` を上書きする

## 進め方の合意
- スライスごとに新規ブランチ、論理単位でコミット（英語 1 行、prefix 付き）、PR は作らず `main` にマージ
- コミットとブランチの規約は `AGENTS.md` と `~/.claude/rules/commit-message.md`

## 注意
- GitHub Actions の初回実行結果は未確認。失敗していたら先に直す
- 新しいツール導入は頼まれたときだけ行う

## 新しい会話の最初の一言
「docs/handoff/2026-11-04-m1-slang-spike.md を読んで、M1 項目 1 のスパイクを始めて」
