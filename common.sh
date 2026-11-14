# common.sh - shared functions of archivectl and snapshotctl
#
# Sourced by each tool's dispatcher, which sets PROG (the tool's name),
# CONFIG (its configuration file) and SCRIPT_PATH, and defines usage.

readonly EXIT_ERROR=1
readonly EXIT_INVALID_ARGS=2
readonly EXIT_CONFIG_ERROR=3

# Patterns left out of a backup when the configuration sets no EXCLUDES
readonly DEFAULT_EXCLUDES=(".cache" "tmp" "__pycache__")

# Set by open_log only, so that a dry run never writes a log
LOG_FILE=""

# die MESSAGE [STATUS]: print MESSAGE on stderr and exit with STATUS (1)
die() {
    echo "$PROG: $1" >&2
    exit "${2:-$EXIT_ERROR}"
}

# say MESSAGE: print MESSAGE on stderr and append it to LOG_FILE, if open
say() {
    echo "$PROG: $1" >&2
    if [ -n "$LOG_FILE" ]; then
        echo "$(date '+%Y-%m-%dT%H:%M:%S') $1" >>"$LOG_FILE"
    fi
}

# safe_name PATH: PATH as one file name, % written %25, / %2F and a newline
# %0A, so that two paths never share a name
safe_name() {
    local name="${1//%/%25}"
    name="${name//\//%2F}"
    printf '%s\n' "${name//$'\n'/%0A}"
}

# old_safe_name PATH: the name hlinkctl and dedupctl gave PATH, every !
# doubled and every / a !, which two paths can share
old_safe_name() {
    printf '%s\n' "$1" | sed 's/!/!!/g; s|/|!|g'
}

# storage_for ROOT DIR: the storage path under ROOT for the source DIR; dies
# when ROOT holds storage under the old name of DIR, which may be DIR's own
# or another directory's
storage_for() {
    local new old
    new="$1/$(safe_name "$2")"
    old="$1/$(old_safe_name "$2")"
    if [ -e "$old" ] && [ ! -e "$new" ]; then
        die "$old exists, named the old way, under which two directories can share one name. If it holds the backups of $2, set it in $2/$CONFIG by hand; if not, move it away."
    fi
    printf '%s\n' "$new"
}

# open_log: log this run to $XDG_STATE_HOME/PROG/<REPO_ROOT as a name>.log,
# readable by the user only
open_log() {
    local dir="${XDG_STATE_HOME:-$HOME/.local/state}/$PROG"
    LOG_FILE="$dir/$(safe_name "$REPO_ROOT").log"
    ( umask 077 && mkdir -p "$dir" && : >>"$LOG_FILE" )
    chmod 700 "$dir"
    chmod 600 "$LOG_FILE"
}

# write_config FILE NAME=VALUE...: write the configuration FILE for
# REPO_ROOT, every value quoted for the shell that sources it
write_config() {
    local file="$1" pair
    shift
    {
        printf '# Backup repository configuration for %q\n' "$REPO_ROOT"
        for pair in "$@"; do
            printf '%s=%q\n' "${pair%%=*}" "${pair#*=}"
        done
    } >"$file"
}

# find_repo_root DIR NAME: the nearest directory at or above DIR holding NAME
find_repo_root() {
    local dir
    dir=$(realpath "$1")
    while [ "$dir" != / ]; do
        if [ -f "$dir/$2" ]; then
            echo "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    return 1
}

# require_config FILE VAR...: source FILE, which must set every VAR
require_config() {
    local file="$1" var
    shift
    [ -f "$file" ] || die "configuration file '$file' not found." $EXIT_CONFIG_ERROR
    source "$file"
    for var in "$@"; do
        [ -n "${!var:-}" ] || die "$file must set $var." $EXIT_CONFIG_ERROR
    done
}

# enter_repo VAR...: change into REPO_ROOT, the nearest directory at or
# above this one holding CONFIG, and read CONFIG, which must set every VAR
enter_repo() {
    REPO_ROOT=$(find_repo_root "$(pwd)" "$CONFIG") ||
        die "no $CONFIG in the current directory or its parents."
    cd "$REPO_ROOT"
    require_config "$CONFIG" "$@"
}

# build_exclude_params borg|rsync: EXCLUDE_PARAMS from EXCLUDES, else DEFAULT_EXCLUDES
build_exclude_params() {
    local pattern
    local -a patterns=("${DEFAULT_EXCLUDES[@]}")
    if declare -p EXCLUDES &>/dev/null; then
        patterns=("${EXCLUDES[@]}")
    fi
    EXCLUDE_PARAMS=()
    for pattern in "${patterns[@]}"; do
        case "$1" in
            borg) EXCLUDE_PARAMS+=(--exclude "$pattern") ;;
            rsync) EXCLUDE_PARAMS+=(--exclude="$pattern") ;;
        esac
    done
}

# reject_options CMD ARG...: -h prints the usage, any other argument is refused
reject_options() {
    local cmd="$1"
    shift
    case "${1:-}" in
        "") ;;
        -h|--help) usage 0 ;;
        *) die "$cmd takes no arguments: '$1'" $EXIT_INVALID_ARGS ;;
    esac
}

# parse_dry_run CMD ARG...: DRY_RUN=true on -n, any other argument is refused
parse_dry_run() {
    local cmd="$1"
    shift
    DRY_RUN=false
    while [ $# -gt 0 ]; do
        case "$1" in
            -n|--dry-run) DRY_RUN=true ;;
            -h|--help) usage 0 ;;
            *) die "$cmd: unknown argument '$1'" $EXIT_INVALID_ARGS ;;
        esac
        shift
    done
}

# parse_select_options ARG...: SELECT_OLDER and SELECT_NEWER in days,
# SELECT_FIRST and SELECT_LAST in records, from the options of the same name
parse_select_options() {
    SELECT_OLDER="" SELECT_NEWER="" SELECT_FIRST="" SELECT_LAST=""
    local name
    while [ $# -gt 0 ]; do
        case "$1" in
            --older|--newer|--first|--last)
                [[ "${2:-}" =~ ^[0-9]+$ ]] || die "$1 needs a number." $EXIT_INVALID_ARGS
                name="${1#--}"
                printf -v "SELECT_${name^^}" '%s' "$2"
                shift 2
                ;;
            -h|--help) usage 0 ;;
            *) die "list: unknown argument '$1'" $EXIT_INVALID_ARGS ;;
        esac
    done
}

# select_records: of the records "id<TAB>date..." read oldest first, print
# those older than SELECT_OLDER and newer than SELECT_NEWER days, then
# only the first SELECT_FIRST and the last SELECT_LAST of them
select_records() {
    local now older="" newer=""
    now=$(date +%s)
    if [ -n "$SELECT_OLDER" ]; then
        older=$(date -d "@$((now - SELECT_OLDER * 86400))" +%Y-%m-%dT%H:%M:%S)
    fi
    if [ -n "$SELECT_NEWER" ]; then
        newer=$(date -d "@$((now - SELECT_NEWER * 86400))" +%Y-%m-%dT%H:%M:%S)
    fi
    awk -F '\t' -v older="$older" -v newer="$newer" -v first="$SELECT_FIRST" -v last="$SELECT_LAST" '
        (older == "" || $2 < older) && (newer == "" || $2 > newer) { kept[++n] = $0 }
        END {
            from = 1; to = n
            if (first != "" && first + 0 < to) to = first + 0
            if (last != "" && to - last + 1 > from) from = to - last + 1
            for (i = from; i <= to; i++) print kept[i]
        }'
}

# read_ids: IDS, the first field of every line on stdin that is not blank, once each
read_ids() {
    mapfile -t IDS < <(cut -f1 | awk 'NF && !seen[$0]++')
}

# require_known ID...: die unless every ID is a line of stdin
require_known() {
    local known id
    local -a missing=()
    known=$(cat)
    for id in "$@"; do
        grep -qxF -e "$id" <<<"$known" || missing+=("$id")
    done
    [ ${#missing[@]} -eq 0 ] || die "no such id: ${missing[*]}"
}

# An awk function for every record printer: esc writes a backslash, tab or
# newline in a path as \\, \t or \n, so that a record stays one line.
AWK_ESCAPE='
function esc(s,    out, i, c) {
    if (s !~ /[\\\t\n]/) return s
    out = ""
    for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        out = out (c == "\\" ? "\\\\" : c == "\t" ? "\\t" : c == "\n" ? "\\n" : c)
    }
    return out
}'

# An awk program, run with LC_ALL=C, that turns the lines of rsync
# --8-bit-output --out-format="%i %n" into records "path<TAB>change";
# rsync writes a control character in a name as \#ooo.
AWK_RSYNC='
function unrsync(s,    out, i) {
    if (index(s, "\\#") == 0) return s
    out = ""
    for (i = 1; i <= length(s); i++) {
        if (substr(s, i, 2) == "\\#" && substr(s, i + 2, 3) ~ /^[0-7][0-7][0-7]$/) {
            out = out sprintf("%c", substr(s, i + 2, 1) * 64 + substr(s, i + 3, 1) * 8 + substr(s, i + 4, 1))
            i += 4
        } else out = out substr(s, i, 1)
    }
    return out
}
{
    flags = substr($0, 1, 11); name = substr($0, 13); sub(/\/$/, "", name)
    if (flags ~ /^\*deleting/) change = "removed"
    else if (flags !~ /^[<>ch][fdLDS]/) next
    else if (substr(flags, 3) == "+++++++++") change = "added"
    else change = "modified"
    print esc(unrsync(name)) "\t" change
}'

# rsync_records RSYNC_ARGUMENT...: run rsync --dry-run with ARGUMENTs and
# print a record "path<TAB>added|removed|modified" per change it would make
rsync_records() {
    rsync --dry-run --8-bit-output --out-format='%i %n' "$@" | LC_ALL=C awk "$AWK_ESCAPE$AWK_RSYNC"
}

# compare_trees OLD NEW [RSYNC_OPTION...]: one record "path<TAB>added",
# "removed" or "modified" per path whose content or type differs from OLD
# to NEW; rsync shows a path whose type changed as new, so one OLD holds too
# is modified
compare_trees() {
    local old="$1" new="$2" path change raw
    shift 2
    rsync_records --archive --checksum --delete "$@" "$new/" "$old/" |
        while IFS=$'\t' read -r path change; do
            if [ "$change" = added ]; then
                printf -v raw '%b' "$path"
                if [ -e "$old/$raw" ] || [ -L "$old/$raw" ]; then
                    change=modified
                fi
            fi
            printf '%s\t%s\n' "$path" "$change"
        done
}

# create_in_parent OPTION...: run "create OPTION..." in the nearest
# repository above REPO_ROOT, if there is one, its record going to stderr
create_in_parent() {
    local parent
    [ "$REPO_ROOT" != / ] || return 0
    parent=$(find_repo_root "$(dirname "$REPO_ROOT")" "$CONFIG") || return 0
    say "creating in the parent repository $parent"
    ( cd "$parent" && "$SCRIPT_PATH" create "$@" ) >&2
}
