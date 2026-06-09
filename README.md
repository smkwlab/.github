# smkwlab/.github

smkwlab organization の共通設定および Reusable Workflows を管理するリポジトリです。

## 概要

このリポジトリは以下を提供します：

- **Reusable Workflows**: 複数リポジトリで共通利用する GitHub Actions ワークフロー
- **Organization 設定**: コミュニティヘルスファイル（CONTRIBUTING.md、CODE_OF_CONDUCT.md 等）

## Reusable Workflows

### LaTeX 関連

| Workflow | 説明 | 用途 |
|----------|------|------|
| `latex-build.yml` | LaTeX ドキュメントをビルドしリリースを作成 | 卒論・修論テンプレート |
| `latex-build-modified.yml` | 変更された TeX ファイルのみをビルド | 週報リポジトリ |

### PR レビューワークフロー

| Workflow | 説明 | 用途 |
|----------|------|------|
| `create-next-draft.yml` | PR 作成時に次の draft ブランチを自動作成 | 卒論・ISE レポート |
| `prevent-draft-merge.yml` | draft ブランチの誤マージを防止 | 卒論・ISE レポート |
| `auto-final-merge.yml` | final-* タグ push 時に承認済み PR を自動マージ | 卒論テンプレート |
| `ai-review.yml` | ワンショット LLM（Claude/Gemini）による PR 自動レビュー（CODE / ACADEMIC） | 全テンプレート |
| `claude-mention.yml` | `@claude` メンションによる対話（質問・助言、read-only。claude-code-action） | 全テンプレート |
| `ai-reviewer.yml` | Gemini AI による PR 自動レビュー（旧基盤・`ai-review.yml` に統合予定） | 既存リポジトリ |
| `notify-ml-on-pr.yml` | PR 作成時にメーリングリストへ通知 | 卒論・ISE レポート |

### HTML 関連

| Workflow | 説明 | 用途 |
|----------|------|------|
| `html-validation.yml` | HTML5 W3C 準拠・アクセシビリティチェック | ISE レポート |

### Elixir 開発支援

| Workflow | 説明 | 用途 |
|----------|------|------|
| `elixir-ci.yml` | Elixir プロジェクト向け CI | Elixir プロジェクト |
| `security.yml` | 依存関係監査・シークレットスキャン | Elixir プロジェクト |

依存関係の自動更新は Renovate Bot に一元化しました（各リポジトリの `renovate.json` を参照）。

## 使い方

各リポジトリのワークフローから以下のように参照します：

```yaml
jobs:
  build:
    uses: smkwlab/.github/.github/workflows/<workflow-name>.yml@v1
```

### 使用例

#### LaTeX ビルド

```yaml
name: Build PDF
on:
  push:
    branches: [main]

jobs:
  build:
    uses: smkwlab/.github/.github/workflows/latex-build.yml@v1
    with:
      files: "sotsuron, gaiyou"
```

#### ML 通知（シークレット継承が必要）

```yaml
name: Notify ML
on:
  pull_request:
    types: [opened]

jobs:
  notify:
    uses: smkwlab/.github/.github/workflows/notify-ml-on-pr.yml@v1
    secrets: inherit
```

#### AI レビュー（シークレット継承が必要）

```yaml
name: AI Review
on:
  pull_request:
    types: [opened, synchronize]

jobs:
  review:
    uses: smkwlab/.github/.github/workflows/ai-reviewer.yml@v1
    secrets: inherit
```

#### AI レビュー: Claude（ワンショット・シークレットを明示的に渡す）

```yaml
name: AI Code Review
on:
  pull_request:
    types: [opened, reopened, ready_for_review]

concurrency:
  group: ai-code-review-${{ github.event.pull_request.number }}
  cancel-in-progress: true

jobs:
  review:
    uses: smkwlab/.github/.github/workflows/ai-review.yml@v1
    permissions:
      contents: read
      pull-requests: write
    secrets:
      anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
    with:
      model_code: claude-sonnet-4-6
      review_mode: CODE
```

caller テンプレートは `scripts/distribute-workflow.sh`（`ai-code-review` / `ai-paper-review`）で各リポジトリへ配布できます。

## ワークフロー詳細

### latex-build.yml

LaTeX ドキュメントをビルドし、PDF をリリースとして公開します。

**入力パラメータ:**
| パラメータ | 必須 | デフォルト | 説明 |
|-----------|:----:|-----------|------|
| `files` | No | `main` | ビルドする TeX ファイル（カンマ区切り、拡張子なし） |
| `cleanup` | No | `true` | ビルド後に中間ファイルを削除 |

### latex-build-modified.yml

直前のコミットで変更された TeX ファイルのみをビルドします。週報リポジトリ向け。

**入力パラメータ:** なし（自動検出）

### notify-ml-on-pr.yml

PR 作成時にメーリングリストへ通知メールを送信します。

**入力パラメータ:**
| パラメータ | 必須 | デフォルト | 説明 |
|-----------|:----:|-----------|------|
| `skip-draft` | No | `true` | Draft PR の通知をスキップ |

**必要なシークレット:**
- `SMTP_SERVER`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`
- `LAB_ML_ADDRESS`, `SMTP_FROM`

### ai-reviewer.yml

Gemini AI を使用して PR の自動レビューを行います。

**入力パラメータ:**
| パラメータ | 必須 | デフォルト | 説明 |
|-----------|:----:|-----------|------|
| `language` | No | `Japanese` | レビュー言語 |
| `exclude-paths` | No | `_build/**,deps/**,cover/**,log/**` | レビュー対象外パス |
| `timeout-minutes` | No | `10` | タイムアウト（分） |

**必要なシークレット:**
- `GEMINI_API_KEY`

### ai-review.yml

ワンショット LLM 呼び出し（エージェントループではない）で PR の自動レビューを行います。`smkwlab/ai-academic-paper-reviewer` action を利用し、`model_code` でプロバイダ（`claude-*` → Anthropic / `gemini-*` → Google）を、`review_mode` でレビュー種別（`CODE` インライン / `ACADEMIC` 論文）を切り替えます。低速・高コストだった claude-code-action 版（旧 `claude-code-review.yml` / `claude-paper-review.yml`）を置き換えました。

**入力パラメータ:**
| パラメータ | 必須 | デフォルト | 説明 |
|-----------|:----:|-----------|------|
| `model_code` | No | `claude-sonnet-4-6` | モデル。`claude-*`（Anthropic）または `gemini-*`（Google） |
| `review_mode` | No | `CODE` | `CODE`（インライン・バグ/ロジック）または `ACADEMIC`（論文レビュー） |
| `single_comment` | No | `false` | インラインではなく要約コメント1件で投稿（`ACADEMIC` 推奨） |
| `language` | No | `Japanese` | レビュー言語 |
| `exclude_paths` | No | `""` | 除外パス glob（カンマ区切り、例 `*.bib,*.sty,*.cls`） |
| `timeout_minutes` | No | `10` | ジョブタイムアウト（分） |

**必要なシークレット:** 選んだプロバイダのキーのみ渡せば可（他方は省略可）。
- `anthropic_api_key`: `claude-*` 用。Console 発行の `ANTHROPIC_API_KEY`（従量課金）。Claude Max の OAuth トークンは使用不可
- `gemini_api_key`: `gemini-*` 用

**必要な権限:** caller 側のジョブに `contents: read` / `pull-requests: write`。

**挙動:**
- draft PR はスキップ（`github.event.pull_request.draft == false` ガード。`workflow_call` でも caller の `pull_request` イベントを継承するため機能する）
- fork PR では secret が渡らないため、キー不在を検出して安全にスキップ

### claude-mention.yml

`@claude` メンションによる対話を行います。Issue / PR コメントで `@claude` に話しかけると、リポジトリを読んで質問に回答し、具体的な修正提案を返します。

**助言のみ（read-only）:** ファイルの編集・コミットは行いません（`contents: read`）。修正は提案を見て本人が適用します。卒論・修論など学習目的のリポジトリで「学生が自分で書く」を尊重するための設計です（#49）。応答に repo の read/search が要るため、レビュー（`ai-review.yml`）と違いエージェント（claude-code-action）を維持しています（ワンショット QA 化は別途検討）。

**必要なシークレット:**
- `anthropic_api_key`: Console 発行の `ANTHROPIC_API_KEY`

**必要な権限:** `contents: read` / `pull-requests: write` / `issues: write` / `id-token: write`。

### create-next-draft.yml

draft ブランチからの PR 作成時に、次の draft ブランチを自動作成します。

**対応ブランチパターン:**
- `1st-draft` → `2nd-draft` → `3rd-draft` → ...
- `abstract-1st` → `abstract-2nd` → ...
- `0th-draft` → `1st-draft`

### prevent-draft-merge.yml

draft ブランチの誤マージを防止します。`final-*` タグが付いている場合のみマージを許可。

### auto-final-merge.yml

`final-*` タグが push された際に、承認済み PR を自動的にマージしリリースを作成します。

### html-validation.yml

HTML ファイルの品質チェックを実行します。

**チェック内容:**
- HTML5 W3C 準拠（html5validator）
- HTMLHint によるコード品質
- アクセシビリティ（alt 属性、セマンティック見出し）
- CSS 構文チェック

### elixir-ci.yml

Elixir プロジェクト向けの CI ワークフローです。LTS と最新版の2つの環境でテストを実行します。

**入力パラメータ:**
| パラメータ | 必須 | デフォルト | 説明 |
|-----------|:----:|-----------|------|
| `otp-version-lts` | No | `27.3.4.4` | OTP LTS バージョン |
| `elixir-version-lts` | No | `1.17.3` | Elixir LTS バージョン |
| `otp-version-latest` | No | `28.2` | OTP 最新バージョン |
| `elixir-version-latest` | No | `1.19.4` | Elixir 最新バージョン |
| `dialyzer-enabled` | No | `true` | Dialyzer 静的解析を有効化 |
| `timeout-minutes` | No | `15` | ジョブタイムアウト（分） |
| `dialyzer-timeout-minutes` | No | `20` | Dialyzer タイムアウト（分） |

### security.yml

セキュリティ監査を実行します。

**チェック内容:**
- 依存関係の脆弱性監査（mix_audit）
- シークレットスキャン（trufflehog）

**入力パラメータ:**
| パラメータ | 必須 | デフォルト | 説明 |
|-----------|:----:|-----------|------|
| `otp-version` | No | `28.2` | OTP バージョン |
| `elixir-version` | No | `1.19.4` | Elixir バージョン |

## 参考資料

- [GitHub Docs: Reusing workflows](https://docs.github.com/en/actions/using-workflows/reusing-workflows)
- [GitHub Docs: Creating a default community health file](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file)
