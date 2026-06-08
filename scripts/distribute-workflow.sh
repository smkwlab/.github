#!/usr/bin/env bash
#
# distribute-workflow.sh
#
# Distribute a shared caller workflow to one or more smkwlab repositories.
# Generic over the caller and over the workflow's domain: it knows nothing about
# Claude, reviews, secrets, or models. Pick a template from scripts/callers/ and
# it is installed as .github/workflows/<caller>.yml in each target, calling the
# matching reusable workflow in smkwlab/.github.
#
# Caller-specific details (tunable values, required secrets, PR notes) live with
# the caller under scripts/callers/, not in this script. To distribute a new
# shared workflow, add a template there — no script changes.
#
# Design goals: safe by default.
#   - Operates ONLY on repositories you name explicitly (no org-wide blast).
#   - Dry-run by default; you must pass --apply to make any change.
#   - Idempotent: skips a repo that already has the caller.
#   - Delivers via Pull Request by default (--direct to commit to the default
#     branch, e.g. for repos without branch protection).
#
# Prerequisite: gh (GitHub CLI) authenticated as a user with write access to the
# targets. (Any secrets a caller needs are the caller's concern — see its
# scripts/callers/<caller>.pr-note.md — and are NOT managed here.)
#
# Usage:
#   scripts/distribute-workflow.sh [options] <caller> <repo> [<repo> ...]
#
#   <caller>  Name of a template under scripts/callers/ (without .yml).
#             Installed in targets as .github/workflows/<caller>.yml.
#   <repo>    "name" (assumed under smkwlab/) or "owner/name".
#
# Options:
#   --apply               Actually make changes (default is dry-run).
#   --ref <ref>           Reusable workflow ref to pin (default: v1). Substituted
#                         for the __REF__ token in the template.
#   --var KEY=VALUE       Substitute __KEY__ with VALUE in the template/PR note.
#                         Repeatable. Lets a caller expose arbitrary knobs.
#   --model <m>           Convenience alias for --var MODEL=<m>.
#   --language <lang>     Convenience alias for --var LANGUAGE=<lang>.
#   --direct              Commit straight to the default branch instead of a PR.
#   --branch <name>       PR branch name (default: add-<caller>).
#   --list-callers        List available caller templates and exit.
#   --list-candidates     List non-archived smkwlab repos and exit.
#   -h, --help            Show this help.
#
# Examples:
#   scripts/distribute-workflow.sh --list-callers
#   scripts/distribute-workflow.sh claude-mention sotsuron-template          # dry-run
#   scripts/distribute-workflow.sh --apply --model opus claude-mention sotsuron-template
#   scripts/distribute-workflow.sh --apply --var FOO=bar some-workflow repo-a repo-b
#
set -euo pipefail

ORG="smkwlab"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CALLERS_DIR="${SCRIPT_DIR}/callers"

# Defaults
APPLY=false
REF="v1"
DIRECT=false
PR_BRANCH=""
declare -a VARS=()   # "KEY=VALUE" substitutions for __KEY__ tokens

die() { echo "error: $*" >&2; exit 1; }
info() { echo "  $*"; }

usage() { sed -n '2,60p' "$0" | sed 's/^# \{0,1\}//'; }

list_callers() {
  echo "Available caller templates (scripts/callers/):" >&2
  for f in "$CALLERS_DIR"/*.yml; do [ -e "$f" ] && echo "  $(basename "$f" .yml)"; done
}

list_candidates() {
  echo "Non-archived repositories under ${ORG}:" >&2
  gh repo list "$ORG" --no-archived --limit 200 \
    --json name,visibility,isArchived \
    --jq '.[] | select(.isArchived | not) | "  \(.name)\t(\(.visibility))"'
}

# --- parse args ---
CALLER=""
REPOS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=true; shift ;;
    --ref) REF="${2:?--ref needs a value}"; shift 2 ;;
    --var) [[ "${2:-}" == *=* ]] || die "--var needs KEY=VALUE"; VARS+=("$2"); shift 2 ;;
    --model) VARS+=("MODEL=${2:?--model needs a value}"); shift 2 ;;
    --language) VARS+=("LANGUAGE=${2:?--language needs a value}"); shift 2 ;;
    --direct) DIRECT=true; shift ;;
    --branch) PR_BRANCH="${2:?--branch needs a value}"; shift 2 ;;
    --list-callers) list_callers; exit 0 ;;
    --list-candidates) list_candidates; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --*) die "unknown option: $1" ;;
    *) if [[ -z "$CALLER" ]]; then CALLER="$1"; else REPOS+=("$1"); fi; shift ;;
  esac
done

command -v gh >/dev/null || die "gh (GitHub CLI) is required."
[[ -n "$CALLER" ]] || { echo "no caller given." >&2; list_callers; exit 2; }

TEMPLATE="${CALLERS_DIR}/${CALLER}.yml"
[[ -f "$TEMPLATE" ]] || { echo "error: unknown caller '$CALLER' (no ${TEMPLATE})" >&2; list_callers; exit 2; }
[[ ${#REPOS[@]} -gt 0 ]] || die "no repositories given. See --help or --list-candidates."

WORKFLOW_PATH=".github/workflows/${CALLER}.yml"
NOTE_FILE="${CALLERS_DIR}/${CALLER}.pr-note.md"
[[ -n "$PR_BRANCH" ]] || PR_BRANCH="add-${CALLER}"

# Build sed substitutions: __REF__ plus every KEY=VALUE from VARS as __KEY__.
# GitHub ${{ ... }} expressions contain no __X__ tokens and are left intact.
SED_ARGS=(-e "s|__REF__|${REF}|g")
for kv in "${VARS[@]}"; do
  SED_ARGS+=(-e "s|__${kv%%=*}__|${kv#*=}|g")
done
render() { sed "${SED_ARGS[@]}" "$1"; }   # render a file with substitutions

PR_TITLE="ci: add ${CALLER} caller"
pr_body() {
  echo "Adds the shared \`${CALLER}\` workflow as a caller of \`${ORG}/.github/${WORKFLOW_PATH}@${REF}\`."
  if [[ -f "$NOTE_FILE" ]]; then echo; render "$NOTE_FILE"; fi
}

echo "=== distribute-workflow ==="
echo "caller:  $CALLER  ->  $WORKFLOW_PATH"
echo "mode:    $([[ $APPLY == true ]] && echo APPLY || echo DRY-RUN)"
echo "deliver: $([[ $DIRECT == true ]] && echo 'direct commit to default branch' || echo "pull request ($PR_BRANCH)")"
echo "ref:     @$REF   vars: ${VARS[*]:-(none)}"
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

  if gh api "repos/${repo}/contents/${WORKFLOW_PATH}?ref=${default_branch}" >/dev/null 2>&1; then
    echo "  • already has ${WORKFLOW_PATH} — skipping"; skipped=$((skipped+1)); continue
  fi

  content_b64=$(render "$TEMPLATE" | base64 | tr -d '\n')

  if [[ $APPLY != true ]]; then
    info "would add ${WORKFLOW_PATH} (@${REF}${VARS:+, ${VARS[*]}})"
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
