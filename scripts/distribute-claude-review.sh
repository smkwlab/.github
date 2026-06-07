#!/usr/bin/env bash
#
# distribute-claude-review.sh
#
# Add the Claude Code Review caller workflow to one or more smkwlab repositories.
# The caller invokes the shared reusable workflow:
#   smkwlab/.github/.github/workflows/claude-code-review.yml@<ref>
#
# Design goals: safe by default.
#   - Operates ONLY on repositories you name explicitly (no org-wide blast).
#   - Dry-run by default; you must pass --apply to make any change.
#   - Idempotent: skips a repo that already has the caller.
#   - Delivers via Pull Request by default (use --direct to commit to the
#     default branch, e.g. for repos without branch protection).
#
# Prerequisites:
#   - gh (GitHub CLI) authenticated as a user with write access to the targets.
#   - The org secret ANTHROPIC_API_KEY must be available to each target repo
#     (Org Settings -> Secrets -> Actions). This script does NOT manage secrets.
#
# Usage:
#   scripts/distribute-claude-review.sh [options] <repo> [<repo> ...]
#
#   <repo> may be "name" (assumed under smkwlab/) or "owner/name".
#
# Options:
#   --apply               Actually make changes (default is dry-run).
#   --model <m>           Model for these repos: sonnet | opus | haiku (default: sonnet).
#   --ref <ref>           Reusable workflow ref to pin (default: v1).
#   --language <lang>     review_language value (default: 日本語).
#   --direct              Commit straight to the default branch instead of opening a PR.
#   --branch <name>       Branch name to use for the PR (default: add-claude-code-review).
#   --list-candidates     Print non-archived smkwlab repos and exit (helper for choosing).
#   -h, --help            Show this help.
#
# Examples:
#   # See what would happen for one template repo (dry-run):
#   scripts/distribute-claude-review.sh sotsuron-template
#
#   # Actually open a PR on one repo, using opus (verify here FIRST):
#   scripts/distribute-claude-review.sh --apply --model opus sotsuron-template
#
#   # Roll out to several document templates with sonnet:
#   scripts/distribute-claude-review.sh --apply \
#     wr-template sotsuron-report-template ise-report-template latex-template
#
set -euo pipefail

ORG="smkwlab"
WORKFLOW_PATH=".github/workflows/claude-code-review.yml"

# Defaults
APPLY=false
MODEL="sonnet"
REF="v1"
LANGUAGE="日本語"
DIRECT=false
PR_BRANCH="add-claude-code-review"

die() { echo "error: $*" >&2; exit 1; }
info() { echo "  $*"; }

usage() { sed -n '2,52p' "$0" | sed 's/^# \{0,1\}//'; }

list_candidates() {
  echo "Non-archived repositories under ${ORG}:" >&2
  gh repo list "$ORG" --no-archived --limit 200 \
    --json name,visibility,isArchived \
    --jq '.[] | select(.isArchived | not) | "  \(.name)\t(\(.visibility))"'
}

# --- parse args ---
REPOS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=true; shift ;;
    --model) MODEL="${2:?--model needs a value}"; shift 2 ;;
    --ref) REF="${2:?--ref needs a value}"; shift 2 ;;
    --language) LANGUAGE="${2:?--language needs a value}"; shift 2 ;;
    --direct) DIRECT=true; shift ;;
    --branch) PR_BRANCH="${2:?--branch needs a value}"; shift 2 ;;
    --list-candidates) list_candidates; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --*) die "unknown option: $1" ;;
    *) REPOS+=("$1"); shift ;;
  esac
done

command -v gh >/dev/null || die "gh (GitHub CLI) is required."
case "$MODEL" in sonnet|opus|haiku) ;; *) die "invalid --model: $MODEL (sonnet|opus|haiku)";; esac
[[ ${#REPOS[@]} -gt 0 ]] || die "no repositories given. See --help or --list-candidates."

# Caller workflow content (rendered per repo with the chosen model/ref/language).
render_caller() {
  cat <<YAML
name: Claude Code Review

on:
  pull_request:
    types: [opened, reopened, ready_for_review]   # no synchronize: avoid re-reviewing every push

concurrency:
  group: claude-review-\${{ github.event.pull_request.number }}
  cancel-in-progress: true

jobs:
  review:
    uses: ${ORG}/.github/${WORKFLOW_PATH}@${REF}
    permissions:
      contents: read
      pull-requests: write
      issues: write
      id-token: write
    secrets:
      anthropic_api_key: \${{ secrets.ANTHROPIC_API_KEY }}
    with:
      model: ${MODEL}
      review_language: ${LANGUAGE}
YAML
}

PR_TITLE="ci: add Claude Code Review caller"
pr_body() {
  cat <<MD
Adds the shared Claude Code Review workflow as a caller of
\`${ORG}/.github/${WORKFLOW_PATH}@${REF}\` (model: \`${MODEL}\`).

PR への自動レビュー（Claude）を有効化します。

- draft はスキップ（\`ready_for_review\` で起動）
- fork PR では secret が渡らないため安全にスキップ
- 動作には org シークレット \`ANTHROPIC_API_KEY\` がこのリポジトリで利用可能である必要があります
MD
}

echo "=== distribute-claude-review ==="
echo "mode:    $([[ $APPLY == true ]] && echo APPLY || echo DRY-RUN)"
echo "deliver: $([[ $DIRECT == true ]] && echo 'direct commit to default branch' || echo 'pull request')"
echo "model:   $MODEL   ref: @$REF   language: $LANGUAGE"
echo "targets: ${REPOS[*]}"
echo

processed=0 skipped=0 changed=0 failed=0

for raw in "${REPOS[@]}"; do
  repo="$raw"; [[ "$repo" == */* ]] || repo="${ORG}/${repo}"
  echo "--- ${repo} ---"
  processed=$((processed+1))

  if ! default_branch=$(gh api "repos/${repo}" --jq .default_branch 2>/dev/null); then
    echo "  ✗ cannot access repo (not found / no permission)"; failed=$((failed+1)); continue
  fi

  # Idempotency: skip if the caller already exists on the default branch.
  if gh api "repos/${repo}/contents/${WORKFLOW_PATH}?ref=${default_branch}" >/dev/null 2>&1; then
    echo "  • already has ${WORKFLOW_PATH} — skipping"; skipped=$((skipped+1)); continue
  fi

  content_b64=$(render_caller | base64 | tr -d '\n')

  if [[ $APPLY != true ]]; then
    info "would add ${WORKFLOW_PATH} (model=${MODEL}, @${REF})"
    info "would deliver via $([[ $DIRECT == true ]] && echo 'direct commit' || echo "PR ${PR_BRANCH} -> ${default_branch}")"
    changed=$((changed+1)); continue
  fi

  if [[ $DIRECT == true ]]; then
    if gh api -X PUT "repos/${repo}/contents/${WORKFLOW_PATH}" \
        -f message="${PR_TITLE}" -f branch="${default_branch}" \
        -f content="${content_b64}" >/dev/null 2>&1; then
      echo "  ✓ committed to ${default_branch}"; changed=$((changed+1))
    else
      echo "  ✗ commit failed"; failed=$((failed+1))
    fi
    continue
  fi

  # PR flow: create branch from default head, add file, open PR.
  head_sha=$(gh api "repos/${repo}/git/refs/heads/${default_branch}" --jq .object.sha)
  if gh api "repos/${repo}/git/refs/heads/${PR_BRANCH}" >/dev/null 2>&1; then
    echo "  ✗ branch ${PR_BRANCH} already exists — resolve manually"; failed=$((failed+1)); continue
  fi
  gh api -X POST "repos/${repo}/git/refs" \
    -f ref="refs/heads/${PR_BRANCH}" -f sha="${head_sha}" >/dev/null

  if ! gh api -X PUT "repos/${repo}/contents/${WORKFLOW_PATH}" \
      -f message="${PR_TITLE}" -f branch="${PR_BRANCH}" \
      -f content="${content_b64}" >/dev/null 2>&1; then
    echo "  ✗ failed to add file on ${PR_BRANCH}"; failed=$((failed+1)); continue
  fi

  if pr_url=$(gh pr create --repo "${repo}" --base "${default_branch}" --head "${PR_BRANCH}" \
      --title "${PR_TITLE}" --body "$(pr_body)" 2>/dev/null); then
    echo "  ✓ PR: ${pr_url}"; changed=$((changed+1))
  else
    echo "  ✗ file added to ${PR_BRANCH} but PR creation failed — create it manually"; failed=$((failed+1))
  fi
done

echo
echo "=== summary: ${processed} processed, ${changed} changed, ${skipped} skipped, ${failed} failed ==="
[[ $APPLY == true ]] || echo "(dry-run — re-run with --apply to make changes)"
[[ $failed -eq 0 ]]
