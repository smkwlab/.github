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
# require_pull_request が true のリポジトリに送る中身。有効な側は設定が全て同じ
# なので宣言では 1 箇所にまとめてある
review_settings=$(jq -c '.review_settings' "$CONFIG_PATH")

log "desired state: $CONFIG_PATH"
log "対象: ${count} リポジトリ (org: ${ORG}, branch: ${branch})"
if [ "$APPLY" = "true" ]; then
    log "モード: --apply（実際に適用する）"
else
    log "モード: dry-run（適用するには --apply を付ける）"
    # このスクリプトは desired state を一方的に送るだけで、現状との差は見ない。
    # 「今どこがずれているか」は audit の担当
    log "現状との差は audit-repo-protection.sh で確認すること"
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
    pr_required=$(printf '%s' "$spec" | jq -r '.require_pull_request')

    if [ "$APPLY" != "true" ]; then
        log "  would apply: ${name} — allow_auto_merge=${am} enforce_admins=${admins} require_pull_request=${pr_required} checks=${checks}"
        applied=$((applied + 1))
        continue
    fi

    ok=true

    # 2>&1 >/dev/null で stderr だけ拾う。書き込みが落ちた時に HTTP ステータスや
    # API のエラーメッセージが残らないと、管理者が原因に辿り着けない
    if ! err=$(gh api -X PATCH "repos/${ORG}/${name}" -F "allow_auto_merge=${am}" 2>&1 >/dev/null); then
        ok=false
        log "  ERROR: ${name} — allow_auto_merge を設定できなかった: ${err}"
    fi

    # required_pull_request_reviews は宣言から組み立てる。PUT は全項目置換なので、
    # ここを無条件に null にすると「Require a pull request before merging」が外れ、
    # main へ直接 push できる状態になる。宣言している 11 リポジトリのうち 9 つが
    # この設定を持っており、null 固定は保護を落とす操作だった
    body=$(printf '%s' "$spec" | jq --argjson reviews "$review_settings" '{
        required_status_checks: .required_status_checks,
        enforce_admins: .enforce_admins,
        required_pull_request_reviews: (if .require_pull_request then $reviews else null end),
        restrictions: null
    }')
    if ! err=$(printf '%s' "$body" | gh api -X PUT \
        "repos/${ORG}/${name}/branches/${branch}/protection" --input - 2>&1 >/dev/null); then
        ok=false
        log "  ERROR: ${name} — ブランチ保護を設定できなかった: ${err}"
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
