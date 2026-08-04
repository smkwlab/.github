#!/bin/bash
#
# TeXLive image tag audit
#
# config/texlive-tag-refs.json の source of truth と、各リポジトリが名乗って
# いる ghcr.io/smkwlab/texlive-ja-textlint のタグを突き合わせる（issue #128）。
#
# タグは複数のリポジトリの複数のファイルに散らばっており、揃っている保証が
# 無い。しかもずれても何も壊れない。古いイメージは存在し続けるので参照は解決
# するし、ビルドも通る。実例として latex-release-action の test.yml は配布物と
# 3 世代違う環境で CI を回していた（.github#128）。
#
# Usage:
#   ./audit-texlive-tags.sh              # 乖離があれば非ゼロで終了
#   ./audit-texlive-tags.sh --quiet      # 一致したリポジトリを出さない
#
# Environment:
#   ORG          対象 org（default: smkwlab）
#   CONFIG_PATH  宣言のパス
#                （default: このスクリプトから見た ../config/texlive-tag-refs.json）
#
# 必要な権限:
#   対象リポジトリへの contents: read。読み取りのみで、何も書き換えない。
#   是正はイメージ更新の PR として人が出す。
#
# 分類:
#   drift     バージョン形式のタグが source of truth と違う
#   skipped   latest など、版を固定していないタグ（比較対象外）
#   errors    リポジトリを取得できなかった（判定保留）

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${CONFIG_PATH:-${SCRIPT_DIR}/../config/texlive-tag-refs.json}"
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
    echo "宣言が見つからない: $CONFIG_PATH" >&2
    exit 1
fi

# extra_patterns は \K を使う PCRE で書く。GNU grep 以外では動かないので、
# 黙って取りこぼさないよう先に確かめる
if ! echo x | grep -qP x 2>/dev/null; then
    echo "grep が PCRE (-P) に対応していない。GNU grep が要る" >&2
    exit 1
fi

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

image=$(jq -r '.image' "$CONFIG_PATH")
sot_repo=$(jq -r '.source_of_truth.repo' "$CONFIG_PATH")
sot_path=$(jq -r '.source_of_truth.path' "$CONFIG_PATH")
count=$(jq '.repositories | length' "$CONFIG_PATH")

if [ "$count" -eq 0 ]; then
    log "宣言が 0 件。CONFIG_PATH を確認すること"
    exit 1
fi

workdir=$(mktemp -d)
err_file=$(mktemp)
trap 'rm -rf "$workdir" "$err_file"' EXIT

# バージョン形式のタグから版の部分だけを取り出す。派生タグ（2026d-alpine）は
# 版が同じなら一致とみなす。形式に合わないタグは空を返す
version_of() {
    printf '%s' "${1%%-*}" | grep -Eo '^[0-9]{4}[a-z]*$' || true
}

# source of truth。ここが読めなければ比較の基準が無いので、続けても意味が無い
if ! sot_json=$(gh api "repos/${ORG}/${sot_repo}/contents/${sot_path}" 2>"$err_file"); then
    log "ERROR: source of truth を取得できなかった: ${sot_repo}/${sot_path}"
    cat "$err_file" >&2
    exit 1
fi
expected=$(printf '%s' "$sot_json" | jq -r '.content' | base64 -d \
    | grep -Eo "${image}:[A-Za-z0-9._-]+" | head -1 | sed "s|^${image}:||")
if [ -z "$(version_of "$expected")" ]; then
    log "ERROR: source of truth からバージョン形式のタグを取り出せなかった (取得値: '${expected:-空}')"
    log "  ${sot_repo}/${sot_path} が ${image}:<tag> を含んでいるか確認すること"
    exit 1
fi

log "宣言: $CONFIG_PATH"
log "source of truth: ${sot_repo}/${sot_path} → ${expected}"
log "対象: ${count} リポジトリ (org: ${ORG})"

drift=0
skipped=0
errors=0

repos=$(jq -c '.repositories[]' "$CONFIG_PATH")

while IFS= read -r spec; do
    [ -z "$spec" ] && continue
    name=$(printf '%s' "$spec" | jq -r '.name')
    repo_dir="${workdir}/${name}"

    # 追跡ファイルだけを見たいので clone する。code search API は索引の遅れで
    # 直近の変更を見落とすし、tarball は .gitignore 済みの成果物を含みうる
    if ! gh repo clone "${ORG}/${name}" "$repo_dir" -- --depth 1 --quiet >"$err_file" 2>&1; then
        errors=$((errors + 1))
        log "  ERROR: ${name} — clone できなかった: $(tr '\n' ' ' < "$err_file")"
        continue
    fi

    # 除外パスは grep の後で落とす。git ls-files に渡して絞ると、宣言した
    # パスが消えていても気付けない
    ignore=$(printf '%s' "$spec" | jq -r '.ignore // [] | .[]')

    # 「file:line:tag」の形に正規化して集める。ls-files が返すのは repo root
    # からの相対パスなので、grep も repo root で走らせる
    # cd の失敗は握り潰さない。空の結果は「一致している」と区別が付かず、
    # 何も見ていない監査が ok を出すことになる
    hits=$(
        cd "$repo_dir" || exit 1
        git ls-files -z \
            | xargs -0 grep -EoHn "${image}:[A-Za-z0-9._-]+" 2>/dev/null \
            | sed "s|:${image}:|:|" || true
    )

    extra=$(printf '%s' "$spec" | jq -r '.extra_patterns // [] | .[]')
    while IFS= read -r pattern; do
        [ -z "$pattern" ] && continue
        found=$(
            cd "$repo_dir" || exit 1
            git ls-files -z | xargs -0 grep -oHnP "$pattern" 2>/dev/null || true
        )
        [ -n "$found" ] && hits=$(printf '%s\n%s' "$hits" "$found")
    done <<EOF
$extra
EOF

    repo_drift=0
    repo_skipped=0
    while IFS= read -r hit; do
        [ -z "$hit" ] && continue
        file=${hit%%:*}
        rest=${hit#*:}
        line=${rest%%:*}
        tag=${rest#*:}

        ignored=false
        while IFS= read -r path; do
            [ -z "$path" ] && continue
            [ "$file" = "$path" ] && ignored=true
        done <<EOF
$ignore
EOF
        [ "$ignored" = true ] && continue

        version=$(version_of "$tag")
        if [ -z "$version" ]; then
            skipped=$((skipped + 1))
            repo_skipped=$((repo_skipped + 1))
            continue
        fi
        if [ "$version" != "$expected" ]; then
            drift=$((drift + 1))
            repo_drift=$((repo_drift + 1))
            log "  drift: ${name}/${file}:${line} — ${tag}（期待: ${expected}）"
        fi
    done <<EOF
$hits
EOF

    if [ "$repo_drift" -eq 0 ] && [ "$QUIET" != "true" ]; then
        log "  ok: ${name}（比較対象外: ${repo_skipped} 件）"
    fi
done <<EOF
$repos
EOF

log "---"
log "drift: ${drift} 件 / 比較対象外: ${skipped} 件 / errors: ${errors} 件"

if [ "$drift" -gt 0 ]; then
    log "source of truth（${expected}）と一致しない箇所がある。イメージ更新の PR で是正すること"
fi
if [ "$errors" -gt 0 ]; then
    log "確認できなかったリポジトリがある。宣言のリポジトリ名と、トークンの contents: read を確認すること"
fi
if [ "$drift" -gt 0 ] || [ "$errors" -gt 0 ]; then
    exit 1
fi
log "すべて ${expected} で揃っている"
