# common.sh - shared functions of archivectl and snapshotctl
#
# Sourced by each tool's dispatcher, which sets PROG (the tool's name),
# CONFIG (its configuration file) and SCRIPT_PATH, and defines usage; each
# command's module defines show_help, its own help.

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

# safe_name PATH: PATH as one file name that no other path shares: the
# leading / dropped, every other / written __, % as %25, a newline as %0A,
# and an _ that begins or ends a component or stands next to another _ as
# %5F, so that __ always stands for a /; / itself is %2F, and a ! that
# begins the name %21. A name longer
# than 199 bytes becomes its first 135 bytes, ~ and the SHA-256 of PATH,
# 200 bytes, which leaves room under NAME_MAX for a suffix and no short
# name can equal.
safe_name() {
    local LC_ALL=C path="${1#/}" name="" c i
    [ -n "$path" ] || name=%2F
    for ((i = 0; i < ${#path}; i++)); do
        c="${path:i:1}"
        case "$c" in
            /) name+=__ ;;
            %) name+=%25 ;;
            $'\n') name+=%0A ;;
            !) if [ "$i" -eq 0 ]; then name+=%21; else name+=!; fi ;;
            _)
                if [ "$i" -eq 0 ] || [ "$i" -eq $((${#path} - 1)) ] ||
                   [[ "${path:i-1:1}" == [/_] || "${path:i+1:1}" == [/_] ]]; then
                    name+=%5F
                else
                    name+=_
                fi
                ;;
            *) name+="$c" ;;
        esac
    done
    shorten "$name" "$1"
}

# shorten NAME PATH: NAME, or past 199 bytes its first 135 bytes, ~ and the
# SHA-256 of PATH
shorten() {
    local LC_ALL=C name="$1"
    if [ ${#name} -gt 199 ]; then
        name="${name:0:135}~$(printf '%s' "$2" | sha256sum | cut -c1-64)"
    fi
    printf '%s\n' "$name"
}

# storage_for ROOT DIR: the storage path under ROOT for the source DIR, named by safe_name
storage_for() {
    printf '%s\n' "$1/$(safe_name "$2")"
}

# default_root KIND OLD: where storage goes when the environment names no
# root, /data/backup/KIND when /data is mounted, else OLD
default_root() {
    if mountpoint -q /data 2>/dev/null; then
        printf '%s\n' "/data/backup/$1"
    else
        printf '%s\n' "$2"
    fi
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

# build_exclude_params borg|rsync: EXCLUDE_PATTERNS, the EXCLUDES or else
# DEFAULT_EXCLUDES, and EXCLUDE_PARAMS, the options that leave them out
build_exclude_params() {
    local pattern
    EXCLUDE_PATTERNS=("${DEFAULT_EXCLUDES[@]}")
    if declare -p EXCLUDES &>/dev/null; then
        EXCLUDE_PATTERNS=("${EXCLUDES[@]}")
    fi
    EXCLUDE_PARAMS=()
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        case "$1" in
            borg) EXCLUDE_PARAMS+=(--exclude "$pattern") ;;
            rsync) EXCLUDE_PARAMS+=(--exclude="$pattern") ;;
        esac
    done
}

# reject_options CMD ARG...: -h prints the command's help, any other argument is refused
reject_options() {
    local cmd="$1"
    shift
    case "${1:-}" in
        "") ;;
        -h|--help) show_help ;;
        *) die "$cmd takes no arguments: '$1'" $EXIT_INVALID_ARGS ;;
    esac
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
            -h|--help) show_help ;;
            *) die "list: unknown argument '$1'" $EXIT_INVALID_ARGS ;;
        esac
    done
}

# select_records: of the records "id<TAB>date..." read oldest first, the
# date YYYY-MM-DD HH:MM:SS, print
# those older than SELECT_OLDER and newer than SELECT_NEWER days, then only
# the first SELECT_FIRST and the last SELECT_LAST of them
select_records() {
    local now older="" newer=""
    now=$(date +%s)
    if [ -n "$SELECT_OLDER" ]; then
        older=$(date -d "@$((now - SELECT_OLDER * 86400))" '+%Y-%m-%d %H:%M:%S')
    fi
    if [ -n "$SELECT_NEWER" ]; then
        newer=$(date -d "@$((now - SELECT_NEWER * 86400))" '+%Y-%m-%d %H:%M:%S')
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

# read_ids [ID...]: IDS, the IDs given, or else the first field of every
# line on stdin that is not blank, once each; ids given while input is
# piped in, or neither, the input being a terminal, end the run with status 2
read_ids() {
    if [ $# -gt 0 ]; then
        [ ! -p /dev/stdin ] && [ ! -f /dev/stdin ] ||
            die "delete takes the ids as arguments or on standard input, not both." $EXIT_INVALID_ARGS
        mapfile -t IDS < <(printf '%s\n' "$@" | awk '!seen[$0]++')
        return 0
    fi
    [ ! -t 0 ] ||
        die "usage: $PROG delete [-n] <id>..., or the ids on standard input, as in: $PROG list --older 30 | $PROG delete -n" $EXIT_INVALID_ARGS
    mapfile -t IDS < <(cut -f1 | awk 'NF && !seen[$0]++')
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

# escaped TEXT: TEXT written the way esc writes a path in a record
escaped() {
    TEXT="$1" LC_ALL=C awk "$AWK_ESCAPE"'BEGIN { print esc(ENVIRON["TEXT"]) }'
}

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
