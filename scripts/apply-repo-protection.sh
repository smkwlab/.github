#!/bin/bash
#
# Dev Infra Protection Apply
#
# config/dev-infra-protection.json の desired state を GitHub に適用する
# （issue #118）。乖離の検出は audit-repo-protection.sh が行う。
#
# Usage:
#   ./apply-repo-protection.sh            # 何を変えるか出すだけ（既定）
#   ./apply-repo-protection.sh --apply    # 実際に適用する
#
# Environment:
#   ORG          対象 org（default: smkwlab）
#   CONFIG_PATH  desired state のパス
#                （default: このスクリプトから見た ../config/dev-infra-protection.json）
#
# 必要な権限:
#   対象リポジトリへの administration: write。
#
# **GitHub App のトークンで実行しないこと。** 学生リポジトリ側で、App token
# だとブランチ保護の一部フィールドが黙って落ちる事例が出ている
# （bypass_pull_request_allowances が反映されなかった。
# smkwlab/student-repo-management#577）。同じペイロードが PAT では通るため、
# このスクリプトは管理者の個人トークンで手動実行する前提にしている。
# 監査（読み取り）は App token でも問題ない。
#
# 注意:
#   ブランチ保護の PUT は全項目置換である。desired state が宣言していない項目
#   （required_pull_request_reviews など）は消える。開発インフラリポジトリは
#   レビュー必須にしていないため現状は問題ないが、宣言を増やす場合はここも
#   併せて宣言すること。

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${CONFIG_PATH:-${SCRIPT_DIR}/../config/dev-infra-protection.json}"
ORG="${ORG:-smkwlab}"

APPLY=false
if [ "${1:-}" = "--apply" ]; then
    APPLY=true
elif [ -n "${1:-}" ]; then
    echo "不明な引数: $1" >&2
    echo "Usage: $0 [--apply]" >&2
    exit 1
fi

if [ ! -f "$CONFIG_PATH" ]; then
    echo "desired state が見つからない: $CONFIG_PATH" >&2
    exit 1
fi

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

branch=$(jq -r '.branch' "$CONFIG_PATH")
count=$(jq '.repositories | length' "$CONFIG_PATH")

log "desired state: $CONFIG_PATH"
log "対象: ${count} リポジトリ (org: ${ORG}, branch: ${branch})"
if [ "$APPLY" = "true" ]; then
    log "モード: --apply（実際に適用する）"
else
    log "モード: dry-run（適用するには --apply を付ける）"
fi

if [ "$count" -eq 0 ]; then
    log "宣言が 0 件。CONFIG_PATH を確認すること"
    exit 1
fi

applied=0
errors=0
error_repos=""

repos=$(jq -c '.repositories[]' "$CONFIG_PATH")

while IFS= read -r spec; do
    [ -z "$spec" ] && continue
    name=$(printf '%s' "$spec" | jq -r '.name')

    am=$(printf '%s' "$spec" | jq -r '.allow_auto_merge')
    admins=$(printf '%s' "$spec" | jq -r '.enforce_admins')
    checks=$(printf '%s' "$spec" | jq -c '.required_status_checks')

    if [ "$APPLY" != "true" ]; then
        log "  would apply: ${name} — allow_auto_merge=${am} enforce_admins=${admins} checks=${checks}"
        applied=$((applied + 1))
        continue
    fi

    ok=true

    if ! gh api -X PATCH "repos/${ORG}/${name}" -F "allow_auto_merge=${am}" >/dev/null 2>&1; then
        ok=false
        log "  ERROR: ${name} — allow_auto_merge を設定できなかった"
    fi

    body=$(printf '%s' "$spec" | jq '{
        required_status_checks: .required_status_checks,
        enforce_admins: .enforce_admins,
        required_pull_request_reviews: null,
        restrictions: null
    }')
    if ! printf '%s' "$body" | gh api -X PUT \
        "repos/${ORG}/${name}/branches/${branch}/protection" --input - >/dev/null 2>&1; then
        ok=false
        log "  ERROR: ${name} — ブランチ保護を設定できなかった"
    fi

    if [ "$ok" = "true" ]; then
        applied=$((applied + 1))
        log "  applied: ${name}"
    else
        errors=$((errors + 1))
        error_repos="${error_repos}${name}"$'\n'
    fi
done <<EOF
$repos
EOF

log "---"
if [ "$APPLY" = "true" ]; then
    log "適用: ${applied} 件"
else
    log "適用対象: ${applied} 件（--apply で実行）"
fi

if [ "$errors" -gt 0 ]; then
    log "エラー: ${errors} 件"
    printf '%s' "$error_repos" | while IFS= read -r r; do
        [ -n "$r" ] && log "  - ${r}"
    done
    exit 1
fi

if [ "$APPLY" = "true" ]; then
    log "適用後は audit-repo-protection.sh で一致を確認すること"
fi
