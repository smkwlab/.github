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
| `sync-next-draft.yml` | draft ブランチへの push（suggestion 受け入れ等）を後続の draft ブランチへ自動 merge | 卒論・ISE レポート |
| `prevent-draft-merge.yml` | draft ブランチの誤マージを防止 | 卒論・ISE レポート |
| `auto-final-merge.yml` | final-* タグ push 時に承認済み PR を自動マージ | 卒論テンプレート |
| `ai-review.yml` | ワンショット LLM（Claude/Gemini）による PR 自動レビュー（CODE / ACADEMIC） | 全テンプレート |
| `claude-qa.yml` | `@claude` メンションへのワンショット QA 回答（質問＋diff＋変更 `.tex` 全文＋会話履歴 → Messages API 1回、エージェントなし） | 全テンプレート |
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
    # synchronize で push のたびに再レビュー。コストが問題なら synchronize を外す。
    types: [opened, reopened, ready_for_review, synchronize]

concurrency:
  group: ai-code-review-${{ github.event.pull_request.number }}
  cancel-in-progress: true   # 連続 push 時は古い実行をキャンセル

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

caller テンプレートは `scripts/distribute-workflow.sh`（`ai-code-review` / `ai-paper-review`）で各リポジトリへ配布できます（次節）。

## 任意のリポジトリへ自動レビューを導入する

`scripts/distribute-workflow.sh` で、共有 caller を任意の smkwlab リポジトリへ配布できます。caller は `smkwlab/.github` の reusable `ai-review.yml@v1` を呼ぶ薄いワークフローです。

### どの caller を使うか

| caller | 用途 | 種別 |
|--------|------|------------|
| `ai-code-review` | コード／一般リポジトリ | CODE（inline・バグ/ロジック） |
| `ai-paper-review` | LaTeX 文書（卒論・修論・ポスター等） | ACADEMIC（要約コメント） |
| `claude-qa` | `@claude` メンションでの質問・助言（全リポジトリ種別） | ワンショット QA |

いずれも既定モデルは `claude-sonnet-4-6`、言語は日本語。プロバイダは `--model gemini-...` で Gemini にも切替可。

### 前提

- 対象リポジトリで org secret `ANTHROPIC_API_KEY` が利用可能であること（未配布なら reusable 側で安全にスキップ）
- `gh`（GitHub CLI）が対象へ write 権限を持つアカウントで認証済みであること

### 手順（まず1リポジトリで検証 → 横展開）

```bash
# 1) dry-run（何も変更しない）。コード repo にコードレビューを入れる例
scripts/distribute-workflow.sh ai-code-review my-repo

# 2) 問題なければ --apply（既定は PR で配布）
scripts/distribute-workflow.sh --apply ai-code-review my-repo

# 3) 動作確認後に横展開（複数指定可）
scripts/distribute-workflow.sh --apply ai-code-review repo-a repo-b repo-c

# LaTeX 文書リポジトリには ai-paper-review を使う
scripts/distribute-workflow.sh --apply ai-paper-review sotsuron-template

# branch protection の無いリポジトリは PR ではなく直接コミットも可
scripts/distribute-workflow.sh --apply --direct ai-code-review my-repo
```

既存の別レビュー（旧 `ai-reviewer.yml` 等）がある場合は、配布で追加した後に旧 caller を削除してください（二重レビュー回避）。

### draft ベースの学生リポジトリ

テンプレートに caller を入れると以降の新規リポジトリへ伝播します。既存の学生リポジトリ（`Nth-draft` ブランチ運用）へ反映するには、配布後に `thesis-student-registry` の `registry-manager` で draft ブランチ群へ伝播します。

```bash
# thesis-student-registry のチェックアウト直下で（escript は要ビルド）
./registry_manager/registry-manager propagate-workflow <repo>
```

### 手動で入れる場合

スクリプトを使わず、対象リポジトリに直接 caller ワークフローを置いても構いません（「使い方」セクションの「AI レビュー: Claude（ワンショット）」の例をコピーし、`ai-code-review.yml` / `ai-paper-review.yml` として `.github/workflows/` に設置）。

詳細なオプション（`--ref` / `--var` / `--branch` / caller テンプレートの追加方法）は **[`scripts/README.md`](scripts/README.md)** を参照。

## バージョニング規約

このリポジトリは**複数の reusable workflow を単一のリポジトリタグでまとめてバージョン管理**します（GitHub の reusable workflow にはファイル単位のタグが無く、`uses: ...@<ref>` の `<ref>` はリポジトリ全体の git ref のため）。

### タグ運用

- **`v1`（floating major）**: 利用側はこれを参照する（`uses: smkwlab/.github/.github/workflows/<name>.yml@v1`）。非破壊の変更ごとに最新コミットへ付け替える
- **`vX.Y.Z`（不変リリース）**: 各リリース時点を固定。変更内容はリリースノートに記録（どのワークフローが変わったかを明記する）

floating `@v1` を使う理由は、**修正を再配布なしに全利用リポジトリ（テンプレートから生成された多数の学生リポジトリを含む）へ自動伝播**させるため。利用側を `@vX.Y.Z` や SHA にピン留めすると、修正のたび全リポジトリの caller を更新する必要が生じ、運用が破綻する。

### 🚨 `v1` を動かしてよい変更（厳守）

`v1` の付け替え・`vX.Y.Z` の発行は、**そのリポジトリに含まれる全ワークフローに対して非破壊**な変更のときだけ行う（機能追加・バグ修正など）。これは SemVer メジャーの契約そのもの。`v1` を共有しているため、1 つのワークフローでも破壊的変更を含めて `v1` を動かすと、無関係なワークフローの `@v1` 利用者まで巻き込む。

「非破壊」の目安:

- **OK（`v1` を動かせる）**: 任意入力の追加（既定値あり）、バグ修正、内部実装の変更、出力の追加
- **NG（破壊的。`v1` を動かさない）**: 入力の削除・リネーム・必須化、**既定値の意味を変える変更**（既存利用者の挙動が変わる）、出力の削除・リネーム、トリガ条件の後方非互換な変更

判断に迷う場合は破壊的とみなし、下記「ファイル名バージョニング」で切り出す。

### 単一ワークフローの破壊的変更 → ファイル名バージョニング

あるワークフローだけ後方非互換な変更が必要になったら、`v2` を切る代わりに **`<name>-v2.yml` を新設**する。

- 旧 `<name>.yml@v1` 利用者はそのまま（影響なし）
- 新規利用者だけ `<name>-v2.yml@v1` に opt-in
- floating `@v1` の自動伝播を壊さず、ワークフロー単位で破壊的変更を切り出せる

リポジトリ全体に及ぶ大規模な破壊的変更のときに限り、例外的に `v2` を切る。手順の目安:

1. `v1` を**最後の安定コミットに凍結**（以後 `v1` は動かさない）
2. `v2` を新設し、Issue／リリースノートで**移行期間を設けて告知**
3. 旧バージョンの README・リリースノートに**非推奨（deprecated）と移行先**を明記
4. 利用側（テンプレート→生成された学生リポジトリ）の caller 更新は `propagate-workflow` 等で計画的に展開
5. 移行期間の経過後に `v1` 利用が無いことを確認

### action の参照

reusable から外部 action（例 `smkwlab/ai-academic-paper-reviewer`）を参照する場合は、**ピン留めしたマイナータグ**（例 `@v1.6`）を使う。action のリリースを reusable の bump という明示的なチェックポイントを経て取り込むことで、action の回帰が org 全体へ無言で伝播するのを防ぐ。

**SHA ピン留めとのトレードオフ**: サプライチェーンの安全性では `@<commit-sha>` が最も堅牢（タグは書き換え可能なため）。本組織は first-party（自組織が管理）の action に限り、**可読性と bump の運用コスト**を優先してマイナータグを採用している。third-party action を参照する場合や、より厳密な固定が必要な場合は SHA ピンを採用する。

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

### claude-qa.yml

`@claude` メンションに **ワンショット**（Messages API 1回、エージェントループなし）で回答します。旧 `claude-mention.yml`（claude-code-action）の後継で、品質同等（文書質問）・約4倍高速・OIDC 不要です（#50）。

**仕組み（自己完結）:** イベント解析 → 文脈収集（PR→diff＋**変更された `.tex` の全文**（head 時点・変更量上位3ファイル・全文予算 120k 文字）／Issue→本文／レビューコメント→対象 file/line＋スレッド／会話履歴）→ Messages API 1回 → 返信投稿（レビューコメントにはスレッド返信、それ以外は issue コメント）＋👀 リアクション。checkout もエージェントも無いため、構造的に編集・コミット不能です。

全文同梱により、論文全体の構成・バランスに関する質問にも diff の断片からの推測でなく実際の文書全体を根拠に回答できます。サイズは 2025 年度実績（最終 `.tex` 最大 180,926 バイト ≈ 約11万文字）が全文予算に収まるよう設計しています。

**旧 `claude-mention.yml`（エージェント版）との違い:**
- リポジトリの read/search はできず、渡された文脈のみで回答（不足時は何が分かれば答えられるかを明示）
- OIDC（`id-token: write`）・max-turns・セッション暴走の懸念が無く、高速・低コスト
- `@claude` 検出と author 権限ガードは caller の `if:` で行う（claude-mention と同一）

**使い分け（エージェント版が必要になるケース）:**

#50 の実機 A/B 比較（3ラウンド・6質問、記録は [PR #59](https://github.com/smkwlab/.github/pull/59)）に基づく質問タイプ別の評価:

| 質問タイプ | ワンショット（claude-qa） | エージェント（旧 claude-mention） |
|-----------|:---------------------:|:----------------------------:|
| diff 近傍の質問（コード・文書とも） | ◎ 同等 | ◎ |
| 文書全体の構成・バランス | ◎ 同等（`.tex` 全文同梱で対応） | ◎ |
| リポジトリ規約・diff 外の文書参照 | △ 「何が分かれば答えられるか」を提示 | ◎ |
| リポジトリ横断のコード質問 | ✗ 回答不可（誤答はせず、不足情報を明示） | ◎ repo を read/search |

所要時間はワンショット約30秒・エージェント約2〜3分。学生リポジトリ（卒論・修論・レポート）の用途は上2行が中心のため、**原則ワンショットで足ります**。

リポジトリ横断のコード質問が常用される repo（管理ツール等）で支障が出る場合に限り、エージェント版 caller を例外的に設置します。caller テンプレートは削除済みのため、以下の最小例を参考に手動設置してください:

```yaml
# .github/workflows/claude-mention.yml — エージェント版（例外設置）
name: Claude Mention
on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  issues:
    types: [opened]
jobs:
  claude:
    if: >
      (github.event_name == 'issue_comment' &&
        contains(github.event.comment.body, '@claude') &&
        contains(fromJSON('["OWNER","MEMBER","COLLABORATOR"]'), github.event.comment.author_association)) ||
      (github.event_name == 'pull_request_review_comment' &&
        contains(github.event.comment.body, '@claude') &&
        contains(fromJSON('["OWNER","MEMBER","COLLABORATOR"]'), github.event.comment.author_association)) ||
      (github.event_name == 'issues' &&
        contains(github.event.issue.body, '@claude') &&
        contains(fromJSON('["OWNER","MEMBER","COLLABORATOR"]'), github.event.issue.author_association))
    # 不変タグを参照する（エージェント版 reusable は main から削除済み・#62）
    uses: smkwlab/.github/.github/workflows/claude-mention.yml@v1.18.0
    permissions:
      contents: read         # 助言のみ: エージェントだが編集・コミットはしない
      pull-requests: write
      issues: write
      id-token: write        # claude-code-action が OIDC で必要とする
    secrets:
      anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
    with:
      model: sonnet
      language: 日本語
```

> [!NOTE]
> エージェント版 reusable（`claude-mention.yml`）は #62 で main から削除済みです。上の最小例は reusable が最後に含まれていた**不変タグ `v1.18.0`** を参照しているため、削除後もこのまま動作します（floating `v1` では解決できない点に注意）。

**入力パラメータ:**
| パラメータ | 必須 | デフォルト | 説明 |
|-----------|:----:|-----------|------|
| `model` | No | `claude-sonnet-4-6` | Messages API に渡すモデルコード |
| `language` | No | `日本語` | 応答の言語 |
| `timeout_minutes` | No | `10` | ジョブタイムアウト（分） |

**必要なシークレット:**
- `anthropic_api_key`: Console 発行の `ANTHROPIC_API_KEY`

**必要な権限:** `contents: read` / `pull-requests: write` / `issues: write`（`id-token` 不要）。

### create-next-draft.yml

draft ブランチからの PR 作成時に、次の draft ブランチを自動作成します。

**対応ブランチパターン:**
- `1st-draft` → `2nd-draft` → `3rd-draft` → ...
- `abstract-1st` → `abstract-2nd` → ...
- `0th-draft` → `1st-draft`

### sync-next-draft.yml

draft ブランチへ push されたコミット（レビュー PR で suggestion を受け入れた場合を含む）を、後続の draft ブランチへ連鎖的に自動 merge します。PR 作成時に次稿ブランチが先行作成されるため、その後に受け入れた suggestion が次稿に反映されない問題（sotsuron-template#110）への対応です。

**動作:**

- `1st-draft` への push → `2nd-draft` が存在すれば merge → `3rd-draft` … と存在する限り伝播（GITHUB_TOKEN による push は新しい workflow run を発火しないため、1 回の実行でチェーン全体を処理）
- コンフリクト時: 前稿→次稿の同期 PR（例: head `1st-draft` / base `2nd-draft`）を自動作成し、前稿のレビュー PR へコメントで通知。学生はブラウザの「Resolve conflicts」で解決して同期 PR を merge する（`prevent-draft-merge.yml` は draft→draft の同期 PR を許可）
- 成功時は PR コメントしない（Actions の step summary にのみ記録）

**caller 例:**

```yaml
name: Sync Suggestions to Next Draft
on:
  push:
    branches:
      - '*-draft'
      - 'abstract-*'

jobs:
  sync:
    permissions:
      contents: write
      pull-requests: write
    uses: smkwlab/.github/.github/workflows/sync-next-draft.yml@v1
```

> [!NOTE]
> `push` トリガーは **push されたブランチ上の**ワークフローファイルを参照します。既存リポジトリへ配布する際は default branch だけでなく、既存の draft ブランチにも caller を配置してください（`registry-manager propagate-workflow` 等で伝播）。

### prevent-draft-merge.yml

draft ブランチの誤マージを防止します。`final-*` タグが付いている場合のみマージを許可。また、base も draft ブランチである同期 PR（`sync-next-draft.yml` がコンフリクト時に作成）はマージを許可します。

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
