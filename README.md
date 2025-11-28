# smkwlab/.github

smkwlab organization の共通設定およびReusable Workflowsを管理するリポジトリです。

## 概要

このリポジトリは以下を提供します：

- **Reusable Workflows**: 複数リポジトリで共通利用するGitHub Actionsワークフロー
- **Organization設定**: コミュニティヘルスファイル（CONTRIBUTING.md、CODE_OF_CONDUCT.md等）

## Reusable Workflows

| Workflow | 説明 |
|----------|------|
| `elixir-ci.yml` | Elixirプロジェクト向けCIワークフロー |

詳細は各ワークフローファイルのコメントを参照してください。

## 使い方

各リポジトリのワークフローから以下のように参照します：

```yaml
jobs:
  ci:
    uses: smkwlab/.github/.github/workflows/<workflow-name>.yml@main
```

## 参考資料

- [GitHub Docs: Reusing workflows](https://docs.github.com/en/actions/using-workflows/reusing-workflows)
- [GitHub Docs: Creating a default community health file](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file)
