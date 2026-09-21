#!/bin/bash
#
# Org Settings Audit
#
# Renovate と secret scanning の稼働は、リポジトリ側のファイルと GitHub 上の
# 設定が揃って初めて成立する。後者はバージョン管理外にあり、欠けても何も
# 言わない。実例が二度あった（issue #198）:
#
#   - Renovate App の対象から 11 リポジトリが漏れ、4 か月気付かれなかった
#   - それが解消されたことにも 26 日気付かなかった
#
# どちらも「状態を誰も見ていない」ことが原因で、欠落と解消の両方を見落として
# いる。この監査は org の全リポジトリを起点に、宣言と実態を突き合わせる。
#
# Usage:
#   ./audit-org-settings.sh              # 乖離があれば非ゼロで終了
#   ./audit-org-settings.sh --quiet      # 一致した項目を出さない
#
# Environment:
#   ORG   対象 org（default: smkwlab）
#
# 必要な権限:
#   metadata: read（リポジトリ一覧）、contents: read（設定ファイルの有無）、
#   issues: read（Dependency Dashboard の有無）。読み取りのみ。
#   この監査を動かすトークンは org の全リポジトリを見られる必要がある。
#   見えないリポジトリは「対象外」と区別が付かず、監査自身が盲点を持つ。
#
# 分類:
#   drift     宣言と実態が食い違っている。是正方法が明確
#   leak      学生リポジトリが renovate 設定を持っている。テンプレートの内容は
#             生成物にそのままコピーされるため、テンプレートに置いたものは
#             学生リポジトリにも配られる。方針上、学生リポジトリに Renovate は
#             無いので、この設定は動かないまま残る
#   unknown   権限やレスポンスの都合で確認できなかった。0 件として数えない
#   info      判断待ち。異常ではないが、目に入り続けるべきもの

set -eu

ORG="${ORG:-smkwlab}"
# 「稼働中」の境界。info 一覧を読める長さに保つためのもので、判定には使わない。
ACTIVE_SINCE="${ACTIVE_SINCE:-$(date -u -d '90 days ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-90d '+%Y-%m-%d')}"

QUIET=false
if [ "${1:-}" = "--quiet" ]; then
    QUIET=true
elif [ -n "${1:-}" ]; then
    echo "不明な引数: $1" >&2
    echo "Usage: $0 [--quiet]" >&2
    exit 1
fi

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"; }

drift=0
leak=0
unknown=0
report() { drift=$((drift + 1)); log "  drift: $1"; }
leaked() { leak=$((leak + 1)); log "  leak: $1"; }
unsure() { unknown=$((unknown + 1)); log "  unknown: $1"; }

# 学生リポジトリは Renovate の対象外（方針）。命名規約で見分ける。
# 規約が変われば見分けが付かなくなるが、宣言リストを別に持つと、その
# リストが今度は誰も見ていない設定になる（#198 本文）。
is_student() { [[ $1 =~ ^k[0-9]{2} ]]; }

err_file=$(mktemp)
repos_file=$(mktemp)
trap 'rm -f "$err_file" "$repos_file"' EXIT

# 起点は org のリポジトリ一覧。search/code は使わない。レート制限や索引の
# 遅れで 0 件を返し、それが「該当なし」と区別できないため（#198 本文）。
if ! gh api "orgs/${ORG}/repos?per_page=100" --paginate \
        --jq '.[] | select(.archived == false) | {name, visibility, pushed: .pushed_at, ss: (.security_and_analysis.secret_scanning.status // null)} | @json' \
        > "$repos_file" 2>"$err_file"; then
    log "ERROR: リポジトリ一覧を取得できなかった: $(cat "$err_file")"
    exit 1
fi

total=$(wc -l < "$repos_file" | tr -d ' ')
log "対象: ${total} リポジトリ (org: ${ORG}, アーカイブ除く)"

no_renovate=""

while read -r line; do
    # 1 リポジトリあたり jq を 4 回呼ぶと 195 回分の起動コストになる。
    # 1 回の @tsv でまとめて取り出す。
    IFS=$'\t' read -r name vis pushed ss <<<"$(printf '%s' "$line" \
        | jq -r '[.name, .visibility, (.pushed | .[0:10]), (.ss // "unknown")] | @tsv')"

    # 1. Renovate の設定ファイルがあるのに Dependency Dashboard が無い
    #    = App の対象から漏れている。dependencyDashboard は default preset に
    #    あるので、Renovate が一度でも走れば issue が立つ。
    has_config=false
    # org の慣行は .github/renovate.json なので先に見る。見つかれば 1 回で済む。
    for path in ".github/renovate.json" "renovate.json"; do
        if gh api "repos/${ORG}/${name}/contents/${path}" --jq '.name' >/dev/null 2>&1; then
            has_config=true
            break
        fi
    done

    if [ "$has_config" = true ] && is_student "$name"; then
        # App に入っていないのは正しい。設定ファイルが配られていることが問題。
        leaked "${name}: 学生リポジトリに renovate 設定がある（テンプレート由来）"
    elif [ "$has_config" = true ]; then
        # --paginate が要る。open issue が 100 件を超えるリポジトリでは
        # Dashboard があっても 1 ページ目に無く、drift と誤報する。
        # 「見つからない」と「見えていない」を混同しないのがこの監査の主旨
        # なので、監査自身がそれをやってはいけない。
        # 取得と判定を分ける。パイプで繋ぐと終了ステータスが後段のものになり、
        # gh の失敗が jq の出す 0 に化けて「Dashboard が無い」と誤報する。
        if pages=$(gh api "repos/${ORG}/${name}/issues?state=open&per_page=100" --paginate \
                     --jq '[.[] | select(.title == "Dependency Dashboard")] | length' 2>"$err_file"); then
            # --paginate はページごとに 1 行出すので合算する
            dash=$(printf '%s\n' "$pages" | jq -s 'add // 0')
            if [ "$dash" -eq 0 ]; then
                report "${name}: renovate 設定はあるが Dependency Dashboard が無い（App の対象外の可能性）"
            elif [ "$QUIET" != "true" ]; then
                log "  ok: ${name} — renovate 稼働"
            fi
        else
            unsure "${name}: issue を取得できなかった: $(tr '\n' ' ' < "$err_file" | cut -c1-120)"
        fi
    elif ! is_student "$name" && [ "$pushed" \> "$ACTIVE_SINCE" ]; then
        no_renovate="${no_renovate}${name} "
    fi

    # 2. public なのに secret scanning が無効
    #    未取得（権限で見えない）と disabled を混同しない。
    if [ "$vis" = "public" ]; then
        case "$ss" in
            enabled) [ "$QUIET" = "true" ] || log "  ok: ${name} — secret scanning 有効" ;;
            unknown) unsure "${name}: secret scanning の状態を取得できなかった（権限不足の可能性）" ;;
            *)       report "${name}: public だが secret scanning が ${ss}" ;;
        esac
    fi
done < "$repos_file"

# 3. Renovate の対象外リポジトリを毎回見せる。異常ではないが、一覧が目に
#    入り続けることが、新しいリポジトリが増えたときに気付く唯一の手段になる。
#    枠の中だけを数えていたために org の 1/3 が誰の視界にも入っていなかった、
#    というのが #198 の発端だった。
# 休眠リポジトリまで並べると 170 行になり、読まれない一覧は無いのと同じに
# なる。直近に動いているものだけに絞る。新しく作られたリポジトリはここに
# 出るので、気付く手段としては保たれる。
if [ -n "$no_renovate" ]; then
    n=$(printf '%s' "$no_renovate" | wc -w | tr -d ' ')
    log "---"
    log "info: renovate 設定を持たない稼働中リポジトリ ${n} 件（${ACTIVE_SINCE} 以降に push。対象外の判断は人が行う）"
    printf '%s' "$no_renovate" | tr ' ' '\n' | grep -v '^$' | sort | paste -sd' ' - | fold -w 100 -s | sed 's/^/    /'
fi

log "---"
log "drift: ${drift} 件 / leak: ${leak} 件 / unknown: ${unknown} 件"

if [ "$drift" -gt 0 ] || [ "$leak" -gt 0 ] || [ "$unknown" -gt 0 ]; then
    log "宣言と実態が一致しない、または確認できない項目がある"
    exit 1
fi
log "すべて一致"
