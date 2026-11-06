# ADR-0019: Blender 連携は PyO3 で同じプロセスに入れ、4.5 LTS と 5.x を対象にする

- 状態: 採用（方針。実装は M6）
- 日付: 2026-11-06

## 背景

M6 で Blender 連携を作る（REQ-DCC-001 / 002 / 003）。決めることは、Rust コアと Blender の結合の仕方、対応する Blender の範囲、新しい依存の可否。

## 決定

- **結合**: `bpy.types.RenderEngine` を実装するアドオンが、PyO3 で作った Python 拡張（新クレート `verion-py`）を呼ぶ。Blender と同じプロセスで Scene IR を直接組み立て、`update` と `accumulate` を呼ぶ（REQ-DCC-001、草案の方針どおり）
- **別プロセスにしない理由**: IPR の応答性（編集のたびに大きなデータを送れない）と、`update`（ADR-0017）に変更だけを渡す設計が、同じプロセスなら直接使えるため。代わりに、描画中も Blender の UI を止めない（GIL を放して別スレッドで回す）、クラッシュが Blender ごと落ちる点を受け入れる
- **対応する Blender**: 4.5 LTS と 5.x（利用者の選択）。Python の版が違うので、拡張は abi3（Python 3.11 以降）で 1 本のバイナリにする。API の差はアドオン側の薄い層に閉じ込め、両方でテストする
- **依存の追加**（利用者が許可）: PyO3、maturin（ビルド）、numpy の受け渡しに `numpy` クレート。いずれも商用再配布できるライセンスであることを確認し、`mise run deny` を通す。Python 側のテストは標準の `unittest` で足りる範囲にとどめ、テスト用の新しいパッケージは足さない
- **配布**: アドオン zip にネイティブライブラリを入れる。OIDN は ADR-0018 のとおり CPU 版だけを同梱し、GPU 版は利用者が足す
- **画像の受け渡し**: 最初は CPU のバッファを Blender に渡す。GPU テクスチャの直接共有は、First Clean Preview の計測で足りないと分かってから検討する

## 結果

- `verion-py` は Scene IR の構築、描画、結果の取り出しだけを持つ。ロジックは Rust のコアに置き、Python のアドオンは Blender のデータの読み取りと表示だけにする（DCC を増やす M9 で薄いまま使い回すため）
- 開発機の Blender は `~/Applications/Blender/stable/` の 4.5.15 LTS（Python 3.11.15、numpy 1.26.4）と 5.2.3 LTS（Python 3.13.13、numpy 2.3.4）。numpy の主な版が違うので、`numpy` クレートが両方で動くことを `verion-py` の最初に確かめる
