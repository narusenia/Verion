# Verion

> English: [`README.md`](README.md)

Verion は、Blender・Cinema 4D・Maya などの DCC から使うことを想定した、Rust 製の GPU レンダラーである。物理ベースのパストレーシングで光を正しく計算したうえで、写実的な絵からゲーム風、セルルックまでをアーティストが自分で調整できるようにする。

現在は計画段階で、コードはまだ無い。

## 目指す表現

写実の絵とアニメ調の絵を別々の仕組みで作るのではなく、1 つのレンダラーの中で連続的に行き来できるようにする。光の向きや遮蔽、間接光といった物理の情報は残したまま、見た目の決め手になる部分だけを様式化する。

目標にする絵は次の 4 種類である。

- **Stylized PBR**: 物理ベースの質感を保ちつつ、影の色や彩度を調整した絵
- **Cinematic Toon**: 映画のような陰影を、段のはっきりした影で表現した絵
- **Painterly Realism**: 写実的な形と光に、絵画のような色の置き方を加えた絵
- **Anime Cinematic**: 顔や髪、輪郭線を作画に近づけた、アニメ調の絵

これらを作るために、次の表現を制御できるようにする。

| 表現 | できること | 予定 |
|---|---|---|
| 影の段 | 段の数、境目のぼかし、色のパレット | v0.1 |
| 影の色 | 直接光の影と間接光の影を別々に色補正する | v0.1 |
| ハイライト | 帯状・楕円・手描き風などの形にする | v0.1 |
| リム光 | 法線・視線・光の向きに応じた縁の光を足す | v0.1 |
| 写実との混合 | 拡散・鏡面・間接光・影のそれぞれの写実度をマテリアルごとに決める | v0.1 |
| 輪郭線 | シルエット、折れ目、マテリアルの境目に線を引く | 後続 |
| 顔の影 | 顔専用のマップで、角度が変わっても影が崩れないようにする | 後続 |
| 髪のハイライト | 髪の流れに沿った帯状のハイライトにする | 後続 |
| 反射の先のスタイル | 鏡や屈折に映る像にもスタイルを掛ける | 研究 |

## 使う技術

| 領域 | 技術 | 選んだ理由 |
|---|---|---|
| 言語 | Rust | GPU バッファの寿命や同期を型で守れる |
| GPU | Metal Ray Tracing（M3 以降）、のちに Vulkan Ray Tracing（RTX） | 開発機が Mac なので Metal を先に作る |
| シェーダー | Slang（MSL と SPIR-V に変換） | BSDF やスタイルの計算を 1 回だけ書く |
| レンダリング | パストレーシング（NEE と MIS）。Megakernel と、パスのキューを詰める Wavefront の 2 形式 | 物理ベースの基準になる。2 形式は同じコードを使い、同じ画像になる |
| Adaptive Sampling | 画素単位。収束した画素を止め、残りの画素にサンプルを回す（`--adaptive`） | 既定は無効。僅かに偏るので、出力は非物理として記録する |
| 入力 | glTF 2.0 とスタイル用の拡張 JSON | 既存のテストシーンをそのまま使える |
| 色 | OCIO / ACES | 出力全体に影響するので最初から入れる |
| 出力 | OpenEXR（Beauty と AOV を 1 ファイル） | スタイルを後段で掛けるため成分を分けて残す |
| ノイズ除去 | OIDN（実行時に読み込む。動画向けの MetalFX は後続） | スタイルを掛ける前の Lighting AOV に掛けて Toon の境目を保つ |
| 高速化（後続） | ReSTIR、Neural Radiance Cache、差分更新 | 同じ画質に届く時間を縮める |
| 検証 | Mitsuba 3 との画像比較、白炉テスト | 物理の正しさを機械的に確かめる |
| DCC 連携（後続） | Blender、Cinema 4D、Maya | Blender から始める |
| 開発環境 | mise、cargo-deny、lefthook | 検証の入口を `mise run check` に揃える |

スタイルは、カメラから最初に見える面で、光ごとの寄与を別々に計算し、成分ごとの AOV に分けて出力する。最後の合成の段階で、この AOV にスタイルを掛ける。Reference モードでは、スタイルと AI による近似をすべて切って、パストレーシングだけで描く。

## ドキュメント

最初に [`docs/requirements/overview.md`](docs/requirements/overview.md) を読むとよい。計画は [`docs/implementation/roadmap.md`](docs/implementation/roadmap.md)、各判断の理由は [`docs/adr/`](docs/adr)、研究仮説を含む最初の構想は [`docs/drafts/draft_arch.md`](docs/drafts/draft_arch.md) にある。草案と要件が食い違う場合は、要件を正とする。

## 開発環境

ツールとタスクは [mise](https://mise.jdx.dev) で管理する。`mise install` でツールを入れ、`mise run check` で整形・lint・ライセンス検査・テストをまとめて実行できる。ノイズ除去には Intel Open Image Denoise 2.x が要る（`brew install open-image-denoise`、または `VERION_OIDN_LIB` でライブラリを指す）。無くてもビルドでき、`--denoise` だけが使えない。

## ライセンス

まだ決めていない。外部への配布も視野に入れていて、オープンコアに近い形を検討している。NVIDIA の SDK などの再配布条件が分かる M4 のころに決める予定で、それまでは商用での再配布が可能なライセンスの依存だけを使う。詳しくは [ADR-0004](docs/adr/0004-positioning-and-license-deferral.md) を参照。
