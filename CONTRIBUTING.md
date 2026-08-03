# Contributing / 開発ガイド

下川研究室（smkwlab）org のリポジトリ共通の貢献ガイドです。**このファイルは org 全体のデフォルト**で、個別リポに `CONTRIBUTING.md` が無い場合に GitHub が自動適用します（Issue / PR 作成時の「Contributing」リンク）。個別リポに固有ルールがある場合はそのリポの `CONTRIBUTING.md` / `README.md` / `CLAUDE.md` が優先します。

以下のうち **Elixir リポ限定**の項目は明記します（DNS/Elixir 群: `tenbin_dns` / `tdig` / `tenbin_ex` / `tenbin_cache` / `elixir_dnstap`）。LaTeX・競技プログラミング等のリポは該当部を読み替えてください。

## ブランチ戦略

- **`main` への直接 push / commit は禁止**。必ず作業ブランチを切って PR 経由でマージする。
- `main` から feature ブランチを作成する。命名は内容が分かる形にし、Issue に紐づく場合は **`issue-<番号>-<短い内容>`**（例: `issue-42-fix-parser`）。
- 1 ブランチ 1 目的。無関係な変更を混ぜない。

## コミットメッセージ

- **Conventional Commits** を使う: `type(scope): summary`
  - `type`: `feat` / `fix` / `docs` / `chore` / `ci` / `refactor` / `test` など
  - 例: `fix(parser): guard against zero-length RDATA (#120)` / `docs(README): add Quick Start`
- **英語・命令形**（"add" であって "added"/"adds" ではない）で簡潔に。
- **Issue 番号を含める**（`(#123)` または本文に `resolve #123`）。
- AI / bot 支援で作成したコミットは、その旨を `Co-Authored-By:` トレーラで明示する慣行。メールアドレス等は**使用したツールの規約に従う**（例: Renovate は `renovate[bot] <…@users.noreply.github.com>`、Claude は Anthropic の指定アドレス）:
  ```
  Co-Authored-By: <ツール / モデル名> <ツールが指定するアドレス>
  ```

## Pull Request

1. feature ブランチを push し、`main` 宛に PR を作成する。
2. PR 本文に **何を・なぜ** を書く。Issue を閉じる場合は `resolve #<番号>` を含める（tracking issue など閉じたくない場合は `Refs #<番号>` にする）。
3. **すべての CI チェックが green** になること（下記「CI」参照）。
4. レビュー指摘は、**盲信も却下もせず**、docs / 実コード / 実機動作で裏取りしてから対応する。恒常的でない LOW 指摘は根拠を添えて in-thread 返信で収束させてよい。
5. マージは原則 **squash merge**。マージ後は作業ブランチを削除する。
   - `smkwlab/.github` は **up-to-date-branch ルールセット**があるため、`main` が先行した PR は先にブランチ更新してからマージする（`gh pr update-branch <PR番号>`、未対応の gh バージョンなら `gh api -X PUT repos/OWNER/REPO/pulls/N/update-branch`）。

## テスト / Lint（Elixir リポ）

コミット時に **Lefthook** が pre-commit で自動実行する（`lefthook install` 済みのローカルで有効）:

| 順 | コマンド | 内容 |
|----|----------|------|
| 1 | `mix format` | フォーマット（差分は自動適用されるので確認して commit） |
| 2 | `mix test` | テスト |
| 3 | `mix credo --strict` | 静的解析 |

- 一時的にスキップする場合のみ `LEFTHOOK=0 git commit -m "..."`。
- PR CI でも同等の検証（テスト / Code Quality / セキュリティ）が走るので、ローカルで通してから push すると往復が減る。
- 型チェックは `mix dialyzer`（初回は PLT 生成に時間がかかる）。

## CI（Elixir リポ）

各リポは `smkwlab/.github` の再利用ワークフローを `@v1` で呼び出す:

- **`elixir-ci.yml`** — Code Quality（format/credo）＋ **OTP/Elixir マトリクス（LTS + latest の2組）** でのテスト。coverage（Codecov）・Dialyzer も含む。
  - 具体的な OTP/Elixir 版は各 caller の workflow が渡す（**版の定義元は caller 側の workflow**）。実際に使われている版は各リポの CI ジョブ名「Test on OTP … / Elixir …」で確認できる。
- **`security.yml`** — 依存監査 + trufflehog によるシークレットスキャン。
- **`ai-review.yml`**（caller: `ai-code-review.yml`）— AI コードレビュー（`review / review` ジョブ）。

再利用ワークフローや共有設定は `@v1`（タグ）参照。共有設定の落とし穴は [依存管理基盤（Renovate 一本化）](https://github.com/smkwlab/latex-ecosystem/blob/main/docs/DEPENDENCY-MANAGEMENT.md) 参照。

## 依存関係の更新

- **GitHub Actions / ライブラリの依存更新は Renovate が一元管理**（Dependabot は不使用）。
  - minor/patch/digest は grouped PR で自動マージ、**major は個別 PR で必ずレビュー**。
  - **マージするのは Renovate bot**。その PR の全チェックが green になったことを Renovate 自身が確認して squash マージする。GitHub の auto-merge は使わない（ブランチ保護の要件を満たした時点でマージするため、required status check の無いリポジトリでは CI 完了前に入ってしまう）。
  - required status check は**人手マージの床**であって自動マージの条件ではない。リポジトリごとの設定は下記ガイド参照。
  - 手で `mix deps.update` や action バージョンを上げる PR は原則不要（Renovate に任せる）。緊急のセキュリティ修正等はこの限りではない。
- git 依存（`tenbin_dns` 等）は **不変リリースタグに pin**（`branch:` や移動しうる ref は使わない）。
- 詳細は [依存管理基盤（Renovate 一本化）](https://github.com/smkwlab/latex-ecosystem/blob/main/docs/DEPENDENCY-MANAGEMENT.md) 参照。

## ライセンス

ライセンスはリポジトリごとに異なる（例: `tdig` は BSD 3-Clause）。各リポの `LICENSE` を確認すること。貢献した内容は当該リポジトリのライセンス下で提供したものとみなす。
