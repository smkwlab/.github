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
#   ORG                  対象 org（default: smkwlab）
#   ACTIVE_SINCE         「稼働中」の境界（default: 90 日前）
#   AUDIT_LIST_DORMANT   休眠リポジトリを件数ではなく一覧で出す
#                        （"true" のみ有効。default: false）
#   REPO_LIST_LIMIT      生成元の対応表の取得上限（default: 2000）。org の
#                        リポジトリ総数に達したら打ち切りを疑って止める
#
# 必要な権限:
#   metadata: read（リポジトリ一覧）、contents: read（設定ファイルの有無）、
#   issues: read（Dependency Dashboard の有無）。読み取りのみ。
#
#   vulnerability_alerts: read は持っていない。そのため advisory の点検は
#   行っていない。休眠リポジトリに patch 付きの advisory が溜まっても、この
#   監査は気付かない（atcoder-container で実際に起きた）。権限を足せば
#   /repos/{repo}/dependabot/alerts を読んで点検を加えられる。
#   この監査を動かすトークンは org の全リポジトリを見られる必要がある。
#   見えないリポジトリは「対象外」と区別が付かず、監査自身が盲点を持つ。
#
# 分類:
#   drift     宣言と実態が食い違っている。是正方法が明確
#   leak      Renovate 対象外のリポジトリが renovate 設定を持っている。
#             テンプレートの内容は生成物にそのままコピーされるため、
#             テンプレートに置いたものは生成物にも配られる。方針上、文書
#             リポジトリに Renovate は無いので、この設定は動かないまま残る
#   unknown   権限やレスポンスの都合で確認できなかった。0 件として数えない
#   info      判断待ち。異常ではないが、目に入り続けるべきもの。Renovate の
#             対象か決まらないリポジトリもここに出す。判断待ちは乖離ではない
#             ので exit code は変えないが、件数は 0 でも出す

set -eu

ORG="${ORG:-smkwlab}"
# 「稼働中」の境界。info 一覧を読める長さに保つためのもので、判定には使わない。
# GNU date と BSD date で書式が違うので両方試す。どちらも駄目なら空になり、
# 文字列比較が常に真になって全リポジトリが info に並ぶ。静かに壊れるより
# 止める。
ACTIVE_SINCE="${ACTIVE_SINCE:-$(date -u -d '90 days ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-90d '+%Y-%m-%d' 2>/dev/null || true)}"
if ! printf '%s' "$ACTIVE_SINCE" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    echo "ERROR: ACTIVE_SINCE を決められなかった（GNU/BSD どちらの date も使えない）。YYYY-MM-DD を明示してください" >&2
    exit 1
fi

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
no_renovate=()
no_renovate_dormant=()
unclassified=()
unclassified_with_config=()
report() { drift=$((drift + 1)); log "  drift: $1"; }
leaked() { leak=$((leak + 1)); log "  leak: $1"; }
unsure() { unknown=$((unknown + 1)); log "  unknown: $1"; }

# Renovate の対象かどうかは方針の判定で、所有者の属性ではない。以前は
# is_student()（名前が ^k[0-9]{2} に一致するか）ひとつで決めていたが、方針上の
# 位置づけは名前に符号化されておらず、相関しているだけだった。学籍番号で
# 始まらない文書リポジトリが 10 件取り残されていた（#245 実測。うち 8 件が
# この判定で対象外になり、2 件は生成元が文書とも決まらないので判断待ちになる）。
#
# そこで事実は GitHub に聞く。templateRepository は生成時に記録される事実で、
# 宣言リストではなく、誰も保守しない。宣言リストを別に持つとそのリストが
# 今度は誰も見ていない設定になる（#198 本文）ので、宣言はテンプレート名だけに
# 留める。リポジトリの許可リストは作らない。org には Renovate が正しく入る
# べき非 LaTeX プロジェクトが多数あり、列挙を維持できないため。

# 文書テンプレート。生成物は方針上 Renovate 対象外。ECOSYSTEM.md の列挙と
# 一致させる。実在と is_template は起動時に検証するので、消えたテンプレートを
# 書き続けることはできない。
DOC_TEMPLATES="sotsuron-template ise-report-template wr-template latex-template sotsuron-report-template poster-template"

# 文書以外のテンプレート。生成物は通常のプロジェクトで、Renovate の対象。
PROJECT_TEMPLATES="webapp_devenv sql-webapp-template sql-webapp-vue-template"

# リポジトリ名が学籍番号で始まるか。先頭の k が無い世代の表記があるので k は
# 任意にする。学科コードは jk（2016 年学部入学まで）、rs（2017 年入学以降）、
# gjk（大学院）。この判定は生成元が記録されていないリポジトリにも効く。
#
# 母数の分だけ呼ぶので grep は使わない。bash の組み込みで済ませる。
student_named() { [[ $1 =~ ^k?[0-9]{2}(rs|jk|gjk)[0-9]+ ]]; }

# in_list <値> <空白区切りのリスト>
in_list() {
    local needle="$1" item
    for item in $2; do
        [ "$item" = "$needle" ] && return 0
    done
    return 1
}

# 方針の判定。yes / no / unknown を返す。unknown を黙って yes に寄せない。
# このヘッダが掲げている原則（見えないものを「対象外」と混同しない）は、
# 分類器自身にも適用する。
renovate_expected() {
    local name="$1" is_tmpl="$2" source="$3"

    # 文書・学生リポジトリは、生成元の記録の有無にかかわらず対象外
    if student_named "$name"; then echo no; return; fi
    # 自身がテンプレート = 保守対象の基盤。文書テンプレート由来であっても
    # テンプレートそのものは Renovate の対象（ipsj-template が該当）
    if [ "$is_tmpl" = "true" ]; then echo yes; return; fi
    # 生成物でない = 通常のプロジェクト
    if [ "$source" = "-" ]; then echo yes; return; fi
    if in_list "$source" "$DOC_TEMPLATES"; then echo no; return; fi
    if in_list "$source" "$PROJECT_TEMPLATES"; then echo yes; return; fi
    # 学生リポジトリをテンプレートに指定して作られたもの
    if student_named "$source"; then echo no; return; fi
    # 宣言されていないテンプレート由来。latex-environment のように文書とも
    # プロジェクトとも決まらないものがある。人が一度決めて宣言に足せば消える
    echo unknown
}

err_file=$(mktemp)
repos_file=$(mktemp)
map_file=$(mktemp)
audit_file=$(mktemp)
joined_file=$(mktemp)
trap 'rm -f "$err_file" "$repos_file" "$map_file" "$audit_file" "$joined_file"' EXIT

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

# 生成元は GraphQL でしか取れない。REST の orgs/{org}/repos には
# template_repository が入らない（has("template_repository") が false）。
# 1 クエリで全件取れるので、API 呼び出しは 1 回だけ増える。archived も
# 対応表には入れる。生成元が archived なテンプレートであっても、生成物の
# 分類には要るため。
REPO_LIST_LIMIT="${REPO_LIST_LIMIT:-2000}"
if ! gh repo list "$ORG" --limit "$REPO_LIST_LIMIT" \
        --json name,isTemplate,templateRepository \
        --jq '.[] | [.name, (.isTemplate | tostring), (.templateRepository.name // "-")] | @tsv' \
        > "$map_file" 2>"$err_file"; then
    log "ERROR: 生成元の対応表を取得できなかった: $(cat "$err_file")"
    exit 1
fi

# 上限で打ち切られたかは件数でしか分からない。打ち切られた分は対応表から
# 落ち、「生成元なし」と読めてしまう。黙って誤分類するより止める。
map_rows=$(wc -l < "$map_file" | tr -d ' ')
if [ "$map_rows" -ge "$REPO_LIST_LIMIT" ]; then
    log "ERROR: 生成元の対応表が上限 ${REPO_LIST_LIMIT} 件に達した。REPO_LIST_LIMIT を上げてください"
    exit 1
fi
# 0 件は「生成物が無い」ではなく取得の失敗。gh は成功して空を返すことがある。
# このまま進むと全リポジトリが対応表に無い扱いになり、unknown が母数と同じ
# 件数だけ並ぶ。0 件と数えていないを混同しないのがこの監査の主旨なので、
# 対応表についても同じように扱う。
if [ "$map_rows" -eq 0 ]; then
    log "ERROR: 生成元の対応表が空だった（org に 1 件もリポジトリが無いことはない）"
    exit 1
fi

# 宣言が腐ったことに気付けない形にはしない。宣言したテンプレートが実在し、
# かつ GitHub 上でテンプレート設定になっていることを起動時に確かめる。
# ここを通さないと、改名や削除のあと「どの生成物も対象外にならない」状態に
# 静かに移行する。
for declared in $DOC_TEMPLATES $PROJECT_TEMPLATES; do
    declared_is_tmpl=$(awk -F'\t' -v n="$declared" '$1 == n { print $2; exit }' "$map_file")
    if [ -z "$declared_is_tmpl" ]; then
        log "ERROR: 宣言されたテンプレート ${declared} が org に存在しない。宣言を更新してください"
        exit 1
    fi
    if [ "$declared_is_tmpl" != "true" ]; then
        log "ERROR: 宣言されたテンプレート ${declared} が GitHub 上でテンプレート設定になっていない"
        exit 1
    fi
done

# 1 リポジトリあたり jq を呼ぶと起動コストが母数の分だけ乗る。REST の JSON 行を
# 1 回でまとめて TSV にし、生成元の対応表と 1 回の awk で突き合わせる。
#
# pushed が null のリポジトリ（一度も push が無い）では空フィールドになり、
# IFS=$'\t' の read がタブを空白として畳むため以降の列がずれる。"-" を置く。
if ! jq -r '[.name, .visibility, (if .pushed then (.pushed | .[0:10]) else "-" end), (.ss // "unknown")] | @tsv' \
        < "$repos_file" > "$audit_file" 2>"$err_file"; then
    log "ERROR: リポジトリ一覧を展開できなかった: $(cat "$err_file")"
    exit 1
fi

# 対応表に無いリポジトリは "?" にする。分類を推測しない
awk -F'\t' -v OFS='\t' '
    NR == FNR { tmpl[$1] = $2; src[$1] = $3; next }
    { if ($1 in tmpl) print $0, tmpl[$1], src[$1]; else print $0, "?", "?" }
' "$map_file" "$audit_file" > "$joined_file"

while IFS=$'\t' read -r name vis pushed ss is_tmpl source; do

    # 分類は名前ではなく GitHub が記録した事実から決める。対応表に無いものは
    # 分類しない。推測して yes 側に寄せると、この監査が塞いだはずの穴になる。
    if [ "$is_tmpl" = "?" ]; then
        unsure "${name}: 生成元の対応表に無い（一覧の取得漏れの可能性）"
        expected=unverifiable
    else
        expected=$(renovate_expected "$name" "$is_tmpl" "$source")
    fi

    # 1. Renovate の設定ファイルがあるのに Dependency Dashboard が無い
    #    = App の対象から漏れている。dependencyDashboard は default preset に
    #    あるので、Renovate が一度でも走れば issue が立つ。
    has_config=false
    if [ "$expected" != "unverifiable" ]; then
        # org の慣行は .github/renovate.json なので先に見る。見つかれば 1 回で済む。
        for path in ".github/renovate.json" "renovate.json"; do
            if gh api "repos/${ORG}/${name}/contents/${path}" --jq '.name' >/dev/null 2>&1; then
                has_config=true
                break
            fi
        done
    fi

    case "$expected" in
    no)
        if [ "$has_config" = true ]; then
            # App に入っていないのは正しい。設定ファイルが配られていることが問題。
            leaked "${name}: Renovate 対象外のリポジトリに renovate 設定がある（テンプレート由来）"
        fi
        ;;
    yes)
        if [ "$has_config" = true ]; then
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
        # 稼働中と休眠を分ける。休眠側は一覧には出さないが、件数は出す。
        # 出さないと「居ない」のと区別が付かない
        elif [ "$pushed" \> "$ACTIVE_SINCE" ]; then
            no_renovate+=("$name")
        else
            no_renovate_dormant+=("$name")
        fi
        ;;
    unknown)
        # 宣言されていないテンプレート由来。leak とも drift とも言えないので
        # どちらにも数えず、判断待ちとして一覧に出す。
        # 一覧はコピーして使われるので名前を装飾しない。設定の有無は別に数える
        unclassified+=("$name")
        if [ "$has_config" = true ]; then
            unclassified_with_config+=("$name")
        fi
        ;;
    esac

    # 2. public なのに secret scanning が無効
    #    未取得（権限で見えない）と disabled を混同しない。
    if [ "$vis" = "public" ]; then
        case "$ss" in
            enabled) [ "$QUIET" = "true" ] || log "  ok: ${name} — secret scanning 有効" ;;
            unknown) unsure "${name}: secret scanning の状態を取得できなかった（権限不足の可能性）" ;;
            *)       report "${name}: public だが secret scanning が ${ss}" ;;
        esac
    fi
done < "$joined_file"

# 3. Renovate の対象外リポジトリを毎回見せる。異常ではないが、一覧が目に
#    入り続けることが、新しいリポジトリが増えたときに気付く唯一の手段になる。
#    枠の中だけを数えていたために org の 1/3 が誰の視界にも入っていなかった、
#    というのが #198 の発端だった。
# 休眠リポジトリまで並べると 170 行になり、読まれない一覧は無いのと同じに
# なる。直近に動いているものだけに絞る。新しく作られたリポジトリはここに
# 出るので、気付く手段としては保たれる。
# 件数は 0 でも出す。出さないと「0 件」と「数えていない」が同じ見え方になり、
# この監査が塞いだはずの穴を報告側で作ることになる。
log "---"
log "info: renovate 設定を持たない稼働中リポジトリ ${#no_renovate[@]} 件（${ACTIVE_SINCE} 以降に push。対象外の判断は人が行う）"
if [ "${#no_renovate[@]}" -gt 0 ]; then
    # fold -s は折り返し位置の空白を行末に残す。ログ上は見えないが、
    # コピーして使う人が末尾の空白を拾うので落とす。
    #
    # 一覧の printf は 0 件のとき通さない。set -u のもとで空配列を "${arr[@]}"
    # と展開すると bash 4.4 より前は unbound variable で落ちる（手元の macOS は 3.2）。
    printf '%s\n' "${no_renovate[@]}" | sort | paste -sd' ' - | fold -w 100 -s | sed -e 's/ *$//' -e 's/^/    /'
fi

# 4. 休眠側は件数だけ出す。一覧を絞った理由は読める長さを保つことだったが、
#    絞った結果ゼロ件と区別が付かなくなっていた。advisory は push ではなく
#    CVE の公開で増えるので、休眠は advisory を止めない。実例として
#    atcoder-container は最終 push が 4 か月前で、patch のある advisory を
#    2 件抱えたまま info にも出ていなかった。
#
#    advisory そのものはここで点検していない。この監査を動かす App に
#    vulnerability_alerts 権限が無く、/repos/{repo}/dependabot/alerts が
#    読めない。権限を足せば点検を加えられる。
log "info: 同じく休眠中（${ACTIVE_SINCE} より前が最終 push）${#no_renovate_dormant[@]} 件。一覧は AUDIT_LIST_DORMANT=true で出る"
log "      休眠は advisory を止めない。advisory 自体はこの監査では未点検（App に vulnerability_alerts 権限が無い）"
if [ "${AUDIT_LIST_DORMANT:-false}" = "true" ] && [ "${#no_renovate_dormant[@]}" -gt 0 ]; then
    printf '%s\n' "${no_renovate_dormant[@]}" | sort | paste -sd' ' - | fold -w 100 -s | sed -e 's/ *$//' -e 's/^/    /'
fi

# 5. 宣言されていないテンプレートから生成されたリポジトリ。方針が決まって
#    いないだけなので leak でも drift でもなく、exit code も変えない。ただし
#    黙って対象側に寄せると「誰も決めていない」ことを誰も知らないままになる。
#    人が一度決めて DOC_TEMPLATES / PROJECT_TEMPLATES に足せば消える。
#    件数は 0 でも出す。0 件と数えていないことを同じ見え方にしない。
log "info: Renovate の対象か判断が付かないリポジトリ ${#unclassified[@]} 件（宣言されていないテンプレート由来）"
if [ "${#unclassified[@]}" -gt 0 ]; then
    printf '%s\n' "${unclassified[@]}" | sort | paste -sd' ' - | fold -w 100 -s | sed -e 's/ *$//' -e 's/^/    /'
fi
# 設定を持つものは分類が決まれば leak か drift のどちらかになる。決まるまでは
# どちらとも言えないが、件数は分けて出す。名前を装飾すると上の一覧が
# リポジトリ名として貼れなくなるため、ここで別に出す。
log "      うち renovate 設定を持つもの ${#unclassified_with_config[@]} 件（分類が決まれば leak か drift のどちらかになる）"
if [ "${#unclassified_with_config[@]}" -gt 0 ]; then
    printf '%s\n' "${unclassified_with_config[@]}" | sort | paste -sd' ' - | fold -w 100 -s | sed -e 's/ *$//' -e 's/^/    /'
fi

log "---"
log "drift: ${drift} 件 / leak: ${leak} 件 / unknown: ${unknown} 件"

if [ "$drift" -gt 0 ] || [ "$leak" -gt 0 ] || [ "$unknown" -gt 0 ]; then
    log "宣言と実態が一致しない、または確認できない項目がある"
    exit 1
fi
log "すべて一致"
