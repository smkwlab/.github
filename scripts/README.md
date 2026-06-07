# scripts

smkwlab organization 運用補助スクリプト。

## distribute-claude-review.sh

Claude Code Review の caller ワークフローを、指定したリポジトリ群へ配布します。
caller は共有 reusable
`smkwlab/.github/.github/workflows/claude-code-review.yml@<ref>` を呼び出します。

### 設計（安全側の既定）

- **明示したリポジトリにのみ作用**します（org 全体への一括適用はしません）
- **既定は dry-run**。実際に変更するには `--apply` が必要
- **冪等**: 既に caller があるリポジトリはスキップ
- **既定は Pull Request 配布**（`--direct` でデフォルトブランチへ直接コミット）

### 前提

- `gh`（GitHub CLI）が対象リポジトリへの write 権限を持つアカウントで認証済み
- org シークレット `ANTHROPIC_API_KEY` が各対象リポジトリで利用可能であること
  （Org Settings → Secrets → Actions）。**本スクリプトはシークレットを管理しません**

### 使い方

```bash
# 候補（非アーカイブの smkwlab リポジトリ）を一覧
scripts/distribute-claude-review.sh --list-candidates

# 1) まず1リポジトリで dry-run（何も変更しない）
scripts/distribute-claude-review.sh sotsuron-template

# 2) 問題なければ --apply で実行（重要リポジトリは opus）。まずここで検証する
scripts/distribute-claude-review.sh --apply --model opus sotsuron-template

# 3) PR が正常にレビューを起動することを確認してから、横展開（sonnet）
scripts/distribute-claude-review.sh --apply \
  wr-template sotsuron-report-template ise-report-template latex-template
```

### オプション

| オプション | 既定 | 説明 |
|-----------|------|------|
| `--apply` | （dry-run） | 実際に変更する |
| `--model <m>` | `sonnet` | `sonnet` / `opus` / `haiku`。卒論・修論など重要リポジトリは `opus` |
| `--ref <ref>` | `v1` | 呼び出す reusable の参照（タグ/ブランチ/SHA） |
| `--language <lang>` | `日本語` | `review_language` の値 |
| `--direct` | （PR） | デフォルトブランチへ直接コミット（branch protection の無いリポジトリ向け） |
| `--branch <name>` | `add-claude-code-review` | PR 用ブランチ名 |
| `--list-candidates` | — | 非アーカイブの smkwlab リポジトリを表示して終了 |
| `-h`, `--help` | — | ヘルプ |

### 配布後の確認

caller を追加したら、対象リポジトリで PR を1つ作成（または既存 PR を更新）し、
Claude のレビューコメントが日本語で付くことを確認してください。`ANTHROPIC_API_KEY`
が未設定のリポジトリでは reusable 側が安全にスキップします。

### 注意

- **まず1リポジトリで検証**してから横展開すること（ブリーフの方針）
- 学生リポジトリはテンプレートから生成されるため、テンプレートに caller を入れると
  以降の新規リポジトリへ伝播します。既存の学生リポジトリへ反映するには
  `thesis-student-registry` の `propagate-workflow`（registry-manager）を併用します
- 安定運用のため `--ref` はタグ（`v1`）または SHA を推奨（`main` 直参照は避ける）
