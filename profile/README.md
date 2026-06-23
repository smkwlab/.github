# 下川研究室 (smkwlab)

**九州産業大学 理工学部 情報科学科 下川研究室**のソフトウェア開発・教育基盤の組織アカウントです。以下を公開しています。

- **DNS/Elixir ソフトウェア群** — 研究で開発している DNS スタック
- **LaTeX 文書基盤** — 卒業論文・レポート作成を支えるテンプレートとツール
- **競技プログラミング演習環境** — AtCoder 参加用の開発環境
- **CI / AI レビュー基盤** — 上記を横断する共通ワークフロー

---

## 🌐 DNS / Elixir エコシステム

Elixir/OTP で実装した DNS ソフトウェア群です。低レベルのパケット処理ライブラリを土台に、CLI ツール・サーバー・ロギング基盤を組み合わせられる構成になっています。

```mermaid
graph LR
  tdig["tdig (CLI)"] --> tenbin_dns
  tenbin_ex["🔒 tenbin_ex (server)"] --> tenbin_dns
  tenbin_ex --> elixir_dnstap
  tenbin_cache["🔒 tenbin_cache (cache proxy)"] --> tenbin_dns
  tenbin_cache --> elixir_dnstap

  tenbin_dns["tenbin_dns (packet library)"]
  elixir_dnstap["elixir_dnstap (DNSTap logging)"]
```

> 🔒 付きのノード（`tenbin_ex` / `tenbin_cache`）は研究用途で開発中のサーバーコンポーネントで、現在は非公開です。

### ユースケース別の選び方

| やりたいこと | プロジェクト | 公開状況 |
|---|---|---|
| DNS パケットを Elixir で解析・生成したい | [**tenbin_dns**](https://github.com/smkwlab/tenbin_dns) — 19+ レコードタイプ・DNSSEC・EDNS0 対応のパース/生成ライブラリ | ✅ 公開 |
| コマンドラインで DNS を引きたい（`dig` 互換） | [**tdig**](https://github.com/smkwlab/tdig) — dig 互換出力の CLI。ビルド済みバイナリ配布あり | ✅ 公開 |
| DNSTap ロギングを組み込みたい | [**elixir_dnstap**](https://github.com/smkwlab/elixir_dnstap) — Frame Streams 対応の DNSTap ロギングライブラリ（Hex 公開） | ✅ 公開 |
| ポリシーベースの DNS サーバーを動かしたい | **tenbin_ex** — 動的応答ポリシーを差し込める権威サーバー | 🔒 研究用（非公開） |
| 透過型 DNS キャッシュプロキシが欲しい | **tenbin_cache** — 無加工転送に特化した薄いキャッシュプロキシ | 🔒 研究用（非公開） |

---

## 📄 文書作成エコシステム（LaTeX / HTML）

卒業論文・修士論文・ポスターを LaTeX で、情報科学演習レポートを HTML で——再現性のある環境で作成し、PR ベースのレビューと自動ビルドに載せるための基盤です。

| プロジェクト | 役割 |
|---|---|
| [latex-template](https://github.com/smkwlab/latex-template) | 汎用 LaTeX ドキュメントテンプレート |
| [ise-report-template](https://github.com/smkwlab/ise-report-template) | 情報科学演習レポート用テンプレート（HTML5） |
| [sotsuron-template](https://github.com/smkwlab/sotsuron-template) | 卒業論文テンプレート（draft ブランチ運用） |
| [poster-template](https://github.com/smkwlab/poster-template) | 学会発表用 A0 ポスターテンプレート（tikzposter・日本語対応） |
| [split-sentences](https://github.com/smkwlab/split-sentences) | LaTeX 文書を 1 文 1 行に整形し diff を見やすくするツール |
| [texlive-ja-textlint](https://github.com/smkwlab/texlive-ja-textlint) | 日本語 LaTeX コンパイル用の Docker イメージ（TeX Live + textlint）。下記環境の土台 |
| [latex-environment](https://github.com/smkwlab/latex-environment) | Dev Container ベースの再現可能な TeX 執筆環境（各テンプレートに組み込まれ自動的に使われる） |
| [aldc](https://github.com/smkwlab/aldc) | 既存テンプレートに LaTeX 用 Dev Container を追加する CLI ツール |
| [latex-release-action](https://github.com/smkwlab/latex-release-action) | LaTeX ビルド & PDF リリースを自動化する GitHub Action |
| [latex-ecosystem](https://github.com/smkwlab/latex-ecosystem) | LaTeX テンプレート群とツールの全体管理 |

---

## 🏆 競技プログラミング演習環境

AtCoder への参加を VS Code 上で完結させる、学生の競技プログラミング演習向け環境です。Dev Container を開くだけで、新規コンテスト作成・テスト・提出までをタスクで実行できます。

| プロジェクト | 役割 |
|---|---|
| [atcoder-env](https://github.com/smkwlab/atcoder-env) | AtCoder 参加用の Dev Container 環境。VS Code で開くと acc / oj や独自タスク込みの環境が構築され、新規コンテスト作成・テスト・提出まで完結 |
| [atcoder-container](https://github.com/smkwlab/atcoder-container) | atcoder-env が利用する AtCoder 用コンテナイメージ。8 言語（Java/Python/C++/Rust/Ruby/Elixir/Erlang/JS）＋AC Library 等の競技用ライブラリ込み、lite / full の 2 版を提供 |

---

## ⚙️ 共通 CI / 開発基盤

複数リポジトリ・多数の学生リポジトリに共通機能を配布・運用するための仕組みです。

| プロジェクト | 役割 |
|---|---|
| [.github](https://github.com/smkwlab/.github) | org 共通の Reusable Workflows（CI・LaTeX ビルド・AI レビュー・メーリングリスト通知 等）と community health files |

---

## 🚀 各プロジェクトの始め方

各プロジェクトの README 冒頭にセットアップ・動作確認の手順を用意しています。とくに DNS/Elixir 群の README には、3 ステップで動作確認できる **Quick Start** があります。

- DNS ライブラリ／ツール: [tenbin_dns](https://github.com/smkwlab/tenbin_dns) / [tdig](https://github.com/smkwlab/tdig) / [elixir_dnstap](https://github.com/smkwlab/elixir_dnstap)（各 README の Quick Start を参照）
- LaTeX 執筆環境: [latex-environment](https://github.com/smkwlab/latex-environment) → 各テンプレート
- 競技プログラミング: [atcoder-env](https://github.com/smkwlab/atcoder-env) を VS Code で開く

---

## 🛠 共通開発規約

- **ブランチ**: 機能ごとに feature ブランチを作成（英語・説明的な名前）
- **コミット / PR / Issue タイトル**: 英語
- **CI**: `.github` の Reusable Workflows を各リポジトリから参照（Elixir CI・security 監査・AI コードレビュー 等）
- **Elixir プロジェクトの品質ゲート**: `mix format` / `mix test` / `mix credo --strict`（Lefthook でコミット時に自動実行）

ワークフローの利用方法・バージョニング規約は [.github リポジトリの README](https://github.com/smkwlab/.github) を参照してください。

---

## 📜 ライセンス

各リポジトリのライセンス表記に従います（DNS/Elixir 群は BSD 3-Clause 等、リポジトリごとに `LICENSE` を確認してください）。
