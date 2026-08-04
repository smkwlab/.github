#!/bin/bash
#
# Dev Infra Protection Audit
#
# config/dev-infra-protection.json の desired state と GitHub の実設定を
# 突き合わせ、乖離を報告する（issue #118）。
#
# 開発インフラリポジトリのブランチ保護はコード管理されておらず、GitHub 上に
# しか存在しない。設定が消されても、リポジトリが増えて設定漏れても、誰も
# 気付かない。実例として student-repo-management の
# bypass_pull_request_allowances は「設定しているつもりで入っていない」状態が
# 長く続いた（smkwlab/student-repo-management#577）。
#
# Usage:
#   ./audit-repo-protection.sh              # 乖離があれば非ゼロで終了
#   ./audit-repo-protection.sh --quiet      # 一致した項目を出さない
#
# Environment:
#   ORG          対象 org（default: config の owner。未指定なら smkwlab）
#   CONFIG_PATH  desired state のパス
#                （default: このスクリプトから見た ../config/dev-infra-protection.json）
#
# 必要な権限:
#   対象リポジトリへの administration: read。読み取りのみで、設定は変更しない。
#   適用は apply-repo-protection.sh が行う。
#
# 分類:
#   missing   ブランチ保護そのものが無い
#   drift     保護はあるが desired state と値が違う
#   errors    一時的なエラーで確認できなかった（判定保留）

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${CONFIG_PATH:-${SCRIPT_DIR}/../config/dev-infra-protection.json}"
ORG="${ORG:-smkwlab}"

QUIET=false
if [ "${1:-}" = "--quiet" ]; then
    QUIET=true
elif [ -n "${1:-}" ]; then
    echo "不明な引数: $1" >&2
    echo "Usage: $0 [--quiet]" >&2
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
# require_pull_request が true のリポジトリに期待する中身
review_settings=$(jq -cS '.review_settings' "$CONFIG_PATH")

log "desired state: $CONFIG_PATH"
log "対象: ${count} リポジトリ (org: ${ORG}, branch: ${branch})"

if [ "$count" -eq 0 ]; then
    log "宣言が 0 件。CONFIG_PATH を確認すること"
    exit 1
fi

drift=0
missing=0
errors=0

# gh api の stderr の置き場。成功時の stdout(JSON) に混ざると壊れるので
# 2>&1 でまとめず、別ファイルに分ける
err_file=$(mktemp)
trap 'rm -f "$err_file"' EXIT

# jq -c で 1 行 1 リポジトリにして読む。パイプではなく here-doc から読むのは、
# カウンタをループの外へ持ち出すため（パイプだとサブシェルになって消える）
repos=$(jq -c '.repositories[]' "$CONFIG_PATH")

repo_drift=0
report() {
    drift=$((drift + 1))
    repo_drift=$((repo_drift + 1))
    log "  drift: $1"
}

while IFS= read -r spec; do
    [ -z "$spec" ] && continue
    name=$(printf '%s' "$spec" | jq -r '.name')
    repo_drift=0

    # リポジトリ設定（allow_auto_merge）
    if ! repo_json=$(gh api "repos/${ORG}/${name}" 2>"$err_file"); then
        errors=$((errors + 1))
        log "  ERROR: ${name} — リポジトリ情報を取得できなかった: $(cat "$err_file")"
        continue
    fi

    want_am=$(printf '%s' "$spec" | jq -r '.allow_auto_merge')
    got_am=$(printf '%s' "$repo_json" | jq -r '.allow_auto_merge')
    if [ "$want_am" != "$got_am" ]; then
        report "${name}: allow_auto_merge want=${want_am} got=${got_am}"
    fi

    # ブランチ保護。
    # 「保護が無い」と「確認できなかった」は別物なので分ける。権限エラーを
    # missing として報告すると、保護を付け直す方向へ誘導してしまう。
    #
    # ステータスコードでは判別できない。GitHub は設定の存在を漏らさないため、
    # admin 権限が無い場合も 403 ではなく 404 を返す。3 通りとも 404 で、
    # 区別できるのはメッセージ本文だけ:
    #   Branch not protected  … 保護が無い          → missing
    #   Branch not found      … ブランチ自体が無い  → ERROR（宣言側の誤り）
    #   Not Found             … 権限不足 / repo 無し → ERROR
    if ! prot=$(gh api "repos/${ORG}/${name}/branches/${branch}/protection" 2>"$err_file"); then
        api_err=$(cat "$err_file")
        if printf '%s' "$api_err" | grep -q 'Branch not protected'; then
            missing=$((missing + 1))
            log "  missing: ${name} — ${branch} が保護されていない"
        else
            errors=$((errors + 1))
            log "  ERROR: ${name} — 保護設定を確認できなかった: ${api_err}"
        fi
        continue
    fi

    want_admins=$(printf '%s' "$spec" | jq -r '.enforce_admins')
    got_admins=$(printf '%s' "$prot" | jq -r '.enforce_admins.enabled')
    if [ "$want_admins" != "$got_admins" ]; then
        report "${name}: enforce_admins want=${want_admins} got=${got_admins}"
    fi

    # 「Require a pull request before merging」の有無。これが外れると main へ
    # 直接 push できるようになるが、PR も check run も出ないので気付く手段が無い
    want_pr=$(printf '%s' "$spec" | jq -r '.require_pull_request')
    got_pr=$(printf '%s' "$prot" | jq -r '.required_pull_request_reviews != null')
    if [ "$want_pr" != "$got_pr" ]; then
        report "${name}: require_pull_request want=${want_pr} got=${got_pr}"
    elif [ "$want_pr" = "true" ]; then
        got_reviews=$(printf '%s' "$prot" | jq -cS '.required_pull_request_reviews | {
            required_approving_review_count,
            dismiss_stale_reviews,
            require_code_owner_reviews
        }')
        if [ "$review_settings" != "$got_reviews" ]; then
            report "${name}: review settings want=${review_settings} got=${got_reviews}"
        fi
    fi

    want_strict=$(printf '%s' "$spec" | jq -r '.required_status_checks.strict')
    # `// "なし"` は使えない。jq の // は false も空として扱うため、
    # strict=false が「なし」に化ける
    got_strict=$(printf '%s' "$prot" | jq -r '
        if .required_status_checks == null then "なし"
        else (.required_status_checks.strict | tostring) end')
    if [ "$want_strict" != "$got_strict" ]; then
        report "${name}: required_status_checks.strict want=${want_strict} got=${got_strict}"
    fi

    # contexts は順序を無視して比較する。
    # API は同じ内容を checks[].context（現行）と contexts（legacy）の両方で返す。
    # legacy 側はいずれ落ちうるので checks を優先し、無ければ contexts に戻る。
    # checks の app_id（どの App が報告した check かの固定）は宣言しないので見ない
    want_ctx=$(printf '%s' "$spec" | jq -c '.required_status_checks.contexts | sort')
    got_ctx=$(printf '%s' "$prot" | jq -c '
        (.required_status_checks.checks // [] | map(.context)) as $new
        | (if ($new | length) > 0 then $new
           else (.required_status_checks.contexts // []) end) | sort')
    if [ "$want_ctx" != "$got_ctx" ]; then
        report "${name}: contexts want=${want_ctx} got=${got_ctx}"
    fi

    if [ "$repo_drift" -eq 0 ] && [ "$QUIET" != "true" ]; then
        log "  ok: ${name}"
    fi
done <<EOF
$repos
EOF

log "---"
log "drift: ${drift} 件 / missing: ${missing} 件 / errors: ${errors} 件"

if [ "$drift" -gt 0 ] || [ "$missing" -gt 0 ] || [ "$errors" -gt 0 ]; then
    log "desired state と一致しない。apply-repo-protection.sh --apply で是正できる"
    exit 1
fi
log "すべて desired state と一致"
