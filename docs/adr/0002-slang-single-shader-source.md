# ADR-0002: Shader は Slang 一本化とし、M1 でスパイク検証する

- 状態: 採用
- 日付: 2026-11-04

## 背景

Metal 先行・Vulkan 後追いなので、BSDF・Integrator・Stylization を 2 回書くと Backend 間の見た目が崩れる（草案リスク 4）。

## 決定

- Shader は Slang で書き、MSL と SPIR-V にコンパイルする
- M1 の最初に「Slang → MSL で Metal RT が動く」スパイクを行う。不可なら MSL ネイティブへ切り替え、結論を ADR に記録する
- Rust の Metal バインディングは `objc2-metal` を想定する

## 結果

- Slang の制約に縛られる。デバッグ性はスパイクで確認する
