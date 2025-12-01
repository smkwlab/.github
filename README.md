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
| `ai-reviewer.yml` | Gemini AI による PR 自動レビュー | 全テンプレート |
| `notify-ml-on-pr.yml` | PR 作成時にメーリングリストへ通知 | 卒論・ISE レポート |

### HTML 関連

| Workflow | 説明 | 用途 |
|----------|------|------|
| `html-validation.yml` | HTML5 W3C 準拠・アクセシビリティチェック | ISE レポート |

### Elixir 開発支援

| Workflow | 説明 | 用途 |
|----------|------|------|
| `elixir-ci.yml` | Elixir プロジェクト向け CI | Elixir プロジェクト |
| `dependency-update.yml` | 依存関係の自動更新 PR 作成 | Elixir プロジェクト |
| `security.yml` | 依存関係監査・シークレットスキャン | Elixir プロジェクト |

## 使い方

各リポジトリのワークフローから以下のように参照します：

```yaml
jobs:
  build:
    uses: smkwlab/.github/.github/workflows/<workflow-name>.yml@main
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
    uses: smkwlab/.github/.github/workflows/latex-build.yml@main
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
    uses: smkwlab/.github/.github/workflows/notify-ml-on-pr.yml@main
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
    uses: smkwlab/.github/.github/workflows/ai-reviewer.yml@main
    secrets: inherit
```

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

### dependency-update.yml

Elixir 依存関係を自動更新し、PR を作成します。

**入力パラメータ:**
| パラメータ | 必須 | デフォルト | 説明 |
|-----------|:----:|-----------|------|
| `otp-version` | No | `28.2` | OTP バージョン |
| `elixir-version` | No | `1.19.4` | Elixir バージョン |
| `timeout-minutes` | No | `30` | タイムアウト（分） |

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
