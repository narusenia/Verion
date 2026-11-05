# アーキテクチャ

クレートの依存方向を定める（REQ-INFRA-001）。クレートは `crates/` に置き、名前は `verion-` で始める。構成の元は草案 §10 で、必要になった時点でクレートを足す。

## 依存の方向

```
verion-scene ─┐
              ├─> verion-integrator ─> verion-gpu ─> verion-gpu-metal / verion-gpu-vulkan
verion-material ─┘
```

- `verion-scene`、`verion-geometry`、`verion-material` は GPU API に依存しない。入力形式（glTF など）の型も公開 API に出さない
- `verion-stylization` は Stylization Pass（ADR-0008、REQ-STY-007）を持つ。`verion-scene` だけに依存し、GPU API には依存しない。Backend が出す AOV を入力に最終色を合成し、Reference モードは呼ばない
- `verion-gpu` が Backend の共通の契約（`RayTracingBackend`、`NeuralBackend`、Capabilities）を持つ。抽象は最小限にし、バッファや同期の違いは隠しすぎない
- `verion-gpu-metal` と `verion-gpu-vulkan` は互いに依存しない。GPU API を直接呼ぶので、`unsafe` を使ってよいのはこの 2 つのクレートと `verion-denoise` だけ
- `verion-denoise` は OIDN（ADR-0013）を実行時に読み込む（`libloading`）。C API を呼ぶので `unsafe` を許す。GPU API にも他の Verion クレートにも依存しない。OIDN が無い環境でもビルドでき、デノイズだけが使えない。読み込み先は `VERION_OIDN_LIB`、既定の検索パス、Homebrew の順
- `verion-render-io` が入力（glTF）と出力（画像）を扱い、`verion-scene` に依存する。glTF の型はこのクレートの外へ出さない。`verion-scene` は逆に `verion-render-io` を知らない
- シェーダーは Slang で `shaders/` に置き、Backend ごとに MSL と SPIR-V へ変換する。1 ファイル 1 エントリポイント（ファイル名と同名）で、共通部は `shaders/include/` に置く。パストレーサは `include/pt_core.slang`（バインド 0〜17 とパスの各段）を Megakernel（`pathtrace`）と Wavefront（`wf_*`、バインド 18 以降は `include/wf_state.slang`）が共有する

## 検査

- `unsafe` の制限は、ワークスペースの lint（`unsafe_code = "deny"`）と、GPU クレート側の上書きで守る
- クレート間の依存規則を機械的に検査する `deps` タスクは、クレートが増えた時点で `mise.toml` に足す

## GPU を使うテスト

GitHub のホストランナーには GPU がない。CI は GPU 不要の検査だけを回し、GPU を使うテストとベンチは開発機（M4 Pro、M5、RTX 3080）で実行する。
