# scripts

smkwlab organization 運用補助スクリプト。

## distribute-workflow.sh

共有 caller ワークフローを、指定したリポジトリ群へ配布する**汎用**スクリプト。
特定のワークフロー（レビュー等）やシークレット（`ANTHROPIC_API_KEY` 等）に依存せず、
`scripts/callers/<caller>.yml` のテンプレートを各対象リポジトリの
`.github/workflows/<caller>.yml` として設置し、`smkwlab/.github` 内の同名 reusable を
`@<ref>` で呼び出させます。

**新しい共有ワークフローを配布したくなったら、`scripts/callers/` にテンプレートを
1つ追加するだけ**です（スクリプト本体の変更は不要）。ワークフロー固有の事情（必要な
シークレット・PR 注記・可変値）は caller 側に置きます。

### 用意済みの caller テンプレート

| caller | 配布先ファイル | 役割 | 必要な前提 |
|--------|----------------|------|-----------|
| `ai-code-review` | `.github/workflows/ai-code-review.yml` | PR 自動コードレビュー（ワンショット・inline。Gemini/Claude） | org secret `ANTHROPIC_API_KEY` / `GEMINI_API_KEY` |
| `ai-paper-review` | `.github/workflows/ai-paper-review.yml` | PR 自動論文レビュー（ワンショット・要約。Gemini/Claude） | org secret `ANTHROPIC_API_KEY` / `GEMINI_API_KEY` |
| `claude-mention` | `.github/workflows/claude-mention.yml` | `@claude` 対話・修正依頼 | org secret `ANTHROPIC_API_KEY` |
| `claude-qa` | `.github/workflows/claude-qa.yml` | `@claude` 質問応答（回答のみ・修正なし） | org secret `ANTHROPIC_API_KEY` |
| `latex-build` | `.github/workflows/latex-build.yml` | PR で対象文書一式をビルド、タグでリリース作成 | `--var FILES="..."` の明示指定（既定なし） |
| `latex-build-modified` | `.github/workflows/latex-build-modified.yml` | push で変更された .tex だけビルド（週報向け） | なし |
| `create-next-draft` | `.github/workflows/create-next-draft.yml` | draft PR 作成時に次稿ブランチを自動作成 | draft ブランチ運用（無ければ休眠） |
| `prevent-draft-merge` | `.github/workflows/prevent-draft-merge.yml` | draft PR の誤マージ防止 | draft ブランチ運用（無ければ休眠） |
| `sync-next-draft` | `.github/workflows/sync-next-draft.yml` | 適用済み Suggestion を次稿ブランチへ伝播 | draft ブランチ運用（無ければ休眠） |
| `notify-ml-on-pr` | `.github/workflows/notify-ml-on-pr.yml` | PR 作成を研究室 ML へメール通知 | org secret `SMTP_*` / `LAB_ML_ADDRESS`（6 種） |

`scripts/distribute-workflow.sh --list-callers` で一覧できます。各 caller の前提は
`scripts/callers/<caller>.pr-note.md`（PR 本文に付く注記）にも書かれています。

### 設計（安全側の既定）

- **明示したリポジトリにのみ作用**します（org 全体への一括適用はしません）
- **既定は dry-run**。実際に変更するには `--apply` が必要
- **冪等**: 既に caller があるリポジトリはスキップ。`--update` を付けると、内容がテンプレートの描画結果と**異なる場合のみ**上書きします（一致していればスキップのままなので、繰り返し実行しても収束します）
- **既定は Pull Request 配布**（`--direct` でデフォルトブランチへ直接コミット）

### 前提

- `gh`（GitHub CLI）が対象リポジトリへの write 権限を持つアカウントで認証済みであること

これがスクリプト自体の唯一の前提です。**ワークフローが動くために必要なシークレット等は
caller ごとに異なり、本スクリプトは関与しません**（上表「必要な前提」を参照）。

### 使い方

```bash
# caller テンプレート / 配布候補を一覧
scripts/distribute-workflow.sh --list-callers
scripts/distribute-workflow.sh --list-candidates

# 1) まず1リポジトリで dry-run（何も変更しない）
scripts/distribute-workflow.sh claude-mention sotsuron-template

# 2) 問題なければ --apply で実行（重要リポジトリは opus）。まずここで検証する
scripts/distribute-workflow.sh --apply --model opus claude-mention sotsuron-template

# 3) 動作を確認してから横展開
scripts/distribute-workflow.sh --apply claude-mention \
  wr-template ise-report-template latex-template poster-template
```

### オプション

| オプション | 既定 | 説明 |
|-----------|------|------|
| `--apply` | （dry-run） | 実際に変更する |
| `--ref <ref>` | `v1` | 呼び出す reusable の参照（`__REF__` を置換）。タグ/ブランチ/SHA |
| `--var KEY=VALUE` | — | テンプレ/注記中の `__KEY__` を VALUE に置換（複数指定可）。caller 任意のつまみ。`--var` は `--ref`/`--model`/`--language` より優先（例: `--var REF=x` は `--ref` を上書き） |
| `--model <m>` | — | `--var MODEL=<m>` の別名（Claude caller 用の利便） |
| `--language <lang>` | — | `--var LANGUAGE=<lang>` の別名 |
| `--direct` | （PR） | デフォルトブランチへ直接コミット（branch protection の無いリポジトリ向け） |
| `--branch <name>` | `add-<caller>` | PR 用ブランチ名 |
| `--list-callers` | — | caller テンプレートを一覧して終了 |
| `--list-candidates` | — | 非アーカイブの smkwlab リポジトリを表示して終了 |
| `-h`, `--help` | — | ヘルプ |

### 新しい共有ワークフローを配布対象に追加するには

1. `smkwlab/.github` に reusable 本体（`.github/workflows/<name>.yml`、`workflow_call`）を用意する
2. `scripts/callers/<name>.yml` に caller テンプレートを置く
   - 設置先・呼び出し先は `<name>` で決まる（`uses: smkwlab/.github/.github/workflows/<name>.yml@__REF__`）
   - 可変値は `__REF__` や任意の `__KEY__` トークンで埋め込み、配布時に `--ref` / `--var` で与える
     （GitHub の `${{ ... }}` 式はそのまま残る）
3. （任意）`scripts/callers/<name>.pr-note.md` に PR 本文へ付ける注記（必要なシークレット等）を書く
4. `scripts/distribute-workflow.sh <name> <repos...>` で配布

### 配布後の確認

caller を追加したら対象リポジトリで動作を確認してください（確認方法は caller による：
レビューなら PR 作成、`@claude` なら mention コメント等）。必要な前提が満たされて
いないリポジトリでは reusable 側が安全にスキップする設計を推奨します。

### 注意

- **まず1リポジトリで検証**してから横展開すること
- 学生リポジトリはテンプレートから生成されるため、テンプレートに caller を入れると
  以降の新規リポジトリへ伝播します。既存の学生リポジトリへ反映するには
  `thesis-student-registry` の `propagate-workflow`（registry-manager）を併用します
- 安定運用のため `--ref` はタグ（`v1`）または SHA を推奨（`main` 直参照は避ける）
