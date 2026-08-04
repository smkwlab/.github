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

## audit-repo-protection.sh / apply-repo-protection.sh

開発インフラリポジトリのブランチ保護とマージ設定を、
[`config/dev-infra-protection.json`](../config/dev-infra-protection.json) の desired state
として持ち、実設定と突き合わせる・適用する 2 本組です。方針の背景は
[依存管理基盤（Renovate 一本化）](https://github.com/smkwlab/latex-ecosystem/blob/main/docs/DEPENDENCY-MANAGEMENT.md)
にあります。

対象は `texlive-ja-textlint` / `latex-environment` / `latex-release-action` /
`ai-academic-paper-reviewer` / `student-repo-management` / `.github` の 6 つ。学生
リポジトリは対象外で、`student-repo-management` の `setup-branch-protection.sh` が
別に管理します。

```bash
# 乖離があれば非ゼロ終了（読み取りのみ）
scripts/audit-repo-protection.sh
scripts/audit-repo-protection.sh --quiet   # 一致した項目を出さない

# 何を変えるか出すだけ（既定）
scripts/apply-repo-protection.sh
# 実際に適用する
scripts/apply-repo-protection.sh --apply
```

各値をなぜその値にしているかは desired state の `invariants` に書いてあります。設定を
変えるときは JSON を直してから apply し、audit で一致を確認してください。

### 週次監査

`.github/workflows/audit-repo-protection.yml` が毎週月曜 09:00 JST に audit を回し、
乖離があれば本リポジトリに Issue を起票します（既存の報告があればコメントを追記）。
是正は書き込みなので自動化せず、Issue の指示に従って管理者が apply を実行します。

有効化には `APP_ID` / `APP_PRIVATE_KEY` をこのリポジトリの secret に置くか、org
secret にしてこのリポジトリから参照できるようにする必要があります。ワークフロー側の
記述はどちらでも `${{ secrets.APP_ID }}` で変わりません。GitHub App には対象 6
リポジトリへの `administration: read` が要ります（ブランチ保護の参照に必要な権限）。

secret が未設定のときは skip せず失敗します。何も見ていない監査が success を返すと
「確認済み」と誤読されるためです。

### 注意

- **apply は GitHub App のトークンで実行しない**こと。App token だとブランチ保護の
  一部フィールドが黙って落ちる事例が出ています（smkwlab/student-repo-management#577）。
  管理者の PAT で手動実行してください。audit は読み取りのみなので App token でも動きます
- ブランチ保護の PUT は**全項目置換**です。desired state が宣言していない項目は消えます。
  宣言を増やすときは apply スクリプトの送信ペイロードも合わせて広げること
- `contexts` には**その PR で必ず check run が生成されるジョブだけ**を並べます。
  workflow レベルの `paths:` / `branches:` フィルタで発火しない workflow を required に
  すると、非該当 PR が永久 pending になります（job レベルの `if:` による skip は
  `conclusion=skipped` の check run が出るので指定して構いません）

## audit-texlive-tags.sh

`ghcr.io/smkwlab/texlive-ja-textlint` のタグが各リポジトリで揃っているかを
[`config/texlive-tag-refs.json`](../config/texlive-tag-refs.json) の宣言と突き合わせます。

タグは複数のリポジトリの複数のファイルに散らばっているうえ、**ずれても何も壊れません**。
古いイメージは残り続けるので参照は解決し、ビルドも通ります。そのため上げ忘れに誰も
気付きません。実例として `latex-release-action` の `test.yml` は、配布物と 3 世代違う
環境で CI を回していました。

```bash
# 乖離があれば非ゼロ終了（読み取りのみ）
scripts/audit-texlive-tags.sh
scripts/audit-texlive-tags.sh --quiet   # 一致したリポジトリを出さない
```

期待値は `latex-environment` の `.devcontainer/devcontainer.json` から取ります。各所の
記述が既に「devcontainer と揃えている」と名乗っているため、そこを正とすると宣言が
既存の意図と一致します。

比較するのはカレンダーバージョン形式のタグだけです。西暦 4 桁に小文字を続けた形
（`2026d`、無印の `2026` も可）を版とみなし、ハイフン以降は派生（`2026d-alpine`）として
落としてから比較します。`latest` のように版を固定していないタグはこの形に当たらないので、
比較対象外として数だけ報告します。タグの付け方をこの形から変えるときは、
`scripts/audit-texlive-tags.sh` の `version_of` も直してください。

### 宣言の直しかた

| 状況 | 直す場所 |
|---|---|
| 参照を持つリポジトリが増えた | `repositories` に名前を足す |
| 意図的に古い版を書いている（手順の説明など） | そのリポジトリの `ignore` にパスを足す（repo root からの**完全一致**。`docs/` のようなディレクトリ指定は効かないので、ファイルごとに並べる） |
| イメージ名とタグが離れて書かれていて拾えない | そのリポジトリの `extra_patterns` に PCRE を足す |

`extra_patterns` は `\K` でタグの直前まで読み飛ばし、**タグだけにマッチする**形で書きます
（`ECOSYSTEM.md` のバージョン互換性の表がこの形です）。既定の検出はイメージの完全な参照
（`ghcr.io/smkwlab/texlive-ja-textlint:<tag>`）だけを見るため、表組みのようにイメージ名と
タグが別の列に分かれている箇所は拾えません。

`texlive-ja-textlint` 自身は対象に入れていません。新しいイメージを発行してから
`latex-environment` が追随するまでの間、producer の文書は正しく「先行」した状態になり、
毎回 drift として報告されてしまうためです。producer 側の README 追随は同リポジトリの
`update-readme-issue.yml` が別に見ています。

### 週次監査

`.github/workflows/audit-texlive-tags.yml` が毎週月曜 09:30 JST に audit を回し、
乖離があれば本リポジトリに Issue を起票します（既存の報告があればコメントを追記）。
ブランチ保護の監査と同じ月曜に走るので、報告 Issue が同時に立たないよう 30 分ずらして
います。

必要な権限は対象リポジトリへの `contents: read` です。secret の扱いと、未設定時に
skip せず失敗する理由は
[ブランチ保護の週次監査](#週次監査)と同じです。

**是正は自動化しません。** イメージ更新は textlint のルールが変わって学生の lint 結果に
直接効くため（`latex-template` の見本が新ルールで 11 件の指摘を受ける問題を配布前に
潰した例があります）、上げてよいかは人が判断して PR を出します。
