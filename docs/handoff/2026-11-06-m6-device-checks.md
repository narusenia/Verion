# 引き継ぎ: M6 の実機確認（Windows の Vulkan と Blender の GUI）

M6 は Mac（Metal）で、実機確認が要る所まで終わった。状態の正本は `docs/implementation/M6-blender/README.md` の表。ここに残るのは次の 2 つで、どちらも実機でしか確かめられない。

- 項目 16: Windows 機（RTX 3080、Vulkan）で、Blender 5.x と 4.5 LTS のとき項目 4〜7 の画像が Metal と一致する
- 項目 7 の表示: Blender の 3D ビューにビューポートレンダ（`view_draw`）が出る

## 1. Windows（Vulkan）

### 前提
- Git for Windows（`sh`、`awk`、`tr` が要る。以下はすべて Git Bash で実行する）、mise（Rust・Python 3.12・maturin を入れる）、Vulkan のレイトレーシングに対応したドライバ
- Blender 5.x（5.0 以降）と 4.5 LTS を入れておく。実行ファイルのパスを `BLENDER` に `;` 区切りで渡す。例: `export BLENDER="/c/Program Files/Blender Foundation/Blender 5.0/blender.exe;/c/Program Files/Blender Foundation/Blender 4.5/blender.exe"`
- SPIR-V は再生成してコミット済みなので `slangc` は要らない（`mise run shaders:check` は走らせる）

### 手順
1. `mise run check`、`mise run shaders:check`、`mise run test:gpu`。M6 で `PARAM_WORDS` が 43、`MATERIAL_WORDS` が 23 になり、`lights` バッファの末尾（インスタンスごとのライトリンクのマスクと IES）、AOV のカバレッジ（バインディング 12）、材質の `opacity`、影の光線の半透明対応が増えた。Vulkan のテストで落ちたら、まず `crates/verion-gpu-vulkan/src/renderer.rs` のバインディングと `pack.rs` の語数を疑う
2. `sh scripts/py_build.sh`（`target/py` に abi3 の wheel を展開する）。そのあと `sh scripts/py_test.sh`（素の Python と `BLENDER` の各 Blender）
3. `sh scripts/blender_test.sh`。Metal 専用のテスト（`test_denoise_on_the_gpu_device_blender_ships`）は Windows では飛ばす。`test_consistency.py` は `target/debug/render-cli.exe` を使う
4. Blender の OIDN: アドオンは Blender の同梱（`blender.exe` と同じフォルダの `OpenImageDenoise.dll`）を使う（`native.py` の `blender_oidn`）。Windows の Blender の配置が違うと見つからないので、`test_denoise_runs_and_is_marked` が落ちたらそのパスを直す。CUDA の Device（`--denoise-device cuda` 相当の `CUDA`）が Blender の同梱モジュールで動くことも見る
5. `sh scripts/package_blender.sh`。`target/blender-extension/verion-0.0.0.zip` ができ、空のプロファイルへ入れて描画できること（スクリプトの最後が `SMOKE ok`）。`platforms` が `windows-x64` になる
6. Metal との画像一致（REQ-GPU-007）: Mac と Windows で同じ `test_consistency.py` のシーンを描く。`TMP` の `blender.exr` を両機から持ち寄り、`verion.read_image` で読んで平均の比とブロック相関を出す（Mac の値は平均の比 1.0000、相関 1.00000）。Metal と Vulkan は乱数の流れが同じでも浮動小数の丸めが違うので、画素までは一致しない。高 spp（256 以上）で平均の比 0.99〜1.01、ブロック相関 0.999 以上を目安にし、超えるなら値を見て決め直す
7. 4.5 LTS と 5.x の両方で 2〜6 を行う

### 終わったら
- `docs/implementation/M6-blender/README.md` の項目 16 と完了条件の最後（「4.5 LTS と 5.x、Metal と Vulkan で動く」）を「済」にする。測定値は `docs/implementation/M6-blender/consistency.md` に足す
- Windows で拡張 zip を作ったときは、Mac の zip と並べて配布の形を決める（ライセンス欄は仮置きなので、ADR-0004 を先に決める）

## 2. Blender の GUI（Mac で確認する）

ヘッドレスのテスト（`test_viewport.py`）は、`Viewport` の更新・再開・First Clean Preview の計測までを見ている。`view_draw` の表示は GUI でないと確かめられない。

1. Blender を `~/Applications/Blender/stable/` のどちらかで起動し、アドオンを `target/py` の開発モードか拡張 zip で有効にする。レンダーエンジンを Verion にして、3D ビューをレンダープレビューにする
2. 画像が出ること（黒でも崩れでもない）。ウィンドウのリサイズ、軌道の回転・パン・ズーム、正投影、カメラビューで追従すること
3. 色: ビューのトーンマップ（Filmic/AgX/Standard）と見た目が自然であること。`view_draw` は表示の色変換を Blender に任せる設計なので、白飛びや暗すぎがないか
4. 編集への追従: オブジェクトを動かす、材質の色、ライトの強さを変える。ステータスバーの First Clean Preview（`clean_samples` 到達までの時間）が出ること。`first-clean-preview.md` の値と大きく違わないこと
5. Stylization のパネル（マテリアルタブ）と、ワールドタブの仮想の主光源の設定を触って、ビューポートに反映されること（Stylized モード）
6. 見つかったことは `docs/implementation/M6-blender/README.md` の項目 7 に書き、直す。済になったら完了条件の「実シーンを Blender で編集・プレビュー・Final 出力できる」を埋める

## 3. 利用者の確認が要るもの（M6 の実装で残ったもの）

- **拡張のライセンス欄**: `blender_manifest.toml` の `license` は仮置きの Apache-2.0。ADR-0004（ライセンスは未決）を外部配布の前に決める
- **ADR-0018 の追記**: Blender のアドオンでは OIDN を同梱せず、Blender の同梱を使う（GPU 版の導線は Device の選択になった）。ADR の本文（CPU 版を同梱）と違うので、追記を確認してほしい。Blender の外（`render-cli`・Viewer）で配るときは本文どおり
- **glTF 拡張へ仮想の主光源の上書き項目を足す**（ADR-0020）: Scene IR・Python・Blender には入れた。glTF のスキーマ（`gltf-stylization-extension.md` と JSON Schema）の変更は、確認を取ってから
- **画像のアルファによる切り抜き**: 材質の `opacity`（定数のアルファ、Transparent BSDF）は入れた。アルファテクスチャ（葉の切り抜きなど）は、IR の画像がアルファを持たないため未対応で、警告して不透明にする。IR の画像にアルファを足し、`opacity` に掛ける作業になる。次の段階に入れるか判断してほしい
- **Blender の Light Linking のブロッカー**（影を落とす側の絞り込み）は未対応で警告する
- **Octane との比較**は M6 の後に Blender 用の無料版で行う（M5 の持ち越し。REQ-ACC-002）
- `git push` は毎回確認を取る（AGENTS.md）
