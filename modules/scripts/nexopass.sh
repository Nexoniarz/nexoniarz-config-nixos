#!/usr/bin/env bash
# NexoPass: passwords derived from one master, nothing stored in plain text.
#
# password = Argon2id(master, site + version + mode + user). The same input
# always gives the same password, so no password is ever saved anywhere.
# The vault only remembers which sites you use, their current version and the
# archive of old versions. It is encrypted (GnuPG, AES-256) with a key that is
# also derived from the master.
#
# Case never matters: the master, site names and account names are lowercased.
# The master is a list of words: any whitespace between them counts as one space.
#
# Must stay byte-for-byte compatible with the NexoPass Android app.

set -euo pipefail
export LC_ALL=C

WORDLIST="${NEXOPASS_WORDLIST:-$(dirname "$(readlink -f "$0")")/eff_large_wordlist.txt}"
WORDLIST_SHA256="addd35536511597a02fa0a9ff1e5284677b8883b83e986e43f15a3db996b903e"
VAULT="${NEXOPASS_VAULT:-${XDG_DATA_HOME:-$HOME/.local/share}/nexopass/vault.gpg}"

# Changing any of these changes every password.
SALT_PREFIX="nexopass:v1"
ARGON_T=3
ARGON_M=16 # 2^16 KiB = 64 MiB
ARGON_P=1
SITE_BYTES=1024
WORD_COUNT=5
UPPER="ABCDEFGHJKLMNPQRSTUVWXYZ"
LOWER="abcdefghijkmnopqrstuvwxyz"
DIGITS="23456789"
SYMBOLS='!@#$%&*?-_+='
TWO_PART_TLDS="com.pl net.pl org.pl edu.pl gov.pl info.pl biz.pl co.uk org.uk ac.uk com.au co.jp com.br"

CLIP_SECONDS=30
SEP=$'\x1f'
VAULT_HEADER="# nexopass vault v1"

if [[ -t 1 && -t 2 && -z ${NO_COLOR:-} ]]; then
    RST=$'\e[0m' BOLD=$'\e[1m' DIM=$'\e[2m' RED=$'\e[31m' GREEN=$'\e[32m'
    YELLOW=$'\e[33m' MAGENTA=$'\e[35m' CYAN=$'\e[36m'
else
    RST="" BOLD="" DIM="" RED="" GREEN="" YELLOW="" MAGENTA="" CYAN=""
fi

die() { echo "${RED}[!]${RST} $*" >&2; exit 1; }
info() { echo "${CYAN}[*]${RST} $*" >&2; }
warn() { echo "${YELLOW}[!]${RST} $*" >&2; }
ok() { echo "${GREEN}[+]${RST} $*"; }

usage() {
    cat <<EOF
${BOLD}${MAGENTA}NexoPass${RST} - passwords derived from one master, nothing stored in plain text.

${BOLD}Usage:${RST} nexopass [command] [site] [options]

${BOLD}Commands:${RST}
  ${CYAN}get${RST} <site>       Show the password for a site (adds the site on first use)
  ${CYAN}rotate${RST} <site>    After a breach: switch to the next version, archive the old one
  ${CYAN}list${RST}             List your sites with their current version
  ${CYAN}history${RST} <site>   Show all versions of a site, old ones included
  ${CYAN}remove${RST} <site>    Remove a site from the list (passwords themselves don't change)
  ${CYAN}new-master${RST} [N]   Generate a random master of N words (default 6)
  ${CYAN}help${RST}             Show this help

  nexopass <site>  Same as: nexopass get <site>
  nexopass         Interactive session: master asked once, then type commands

${BOLD}Options:${RST}
  -u, --user NAME    Account name, for several accounts on one site
  -n, --length N     Random characters (12-64) instead of words, for sites
                     with a length limit; set when adding or rotating a site
  -v, --version N    Start a new site at version N (e.g. already rotated on phone)
  -c, --copy         Copy to clipboard (cleared after $CLIP_SECONDS s) instead of printing
  -s, --show         With list/history: also show the passwords
  -h, --help         Show this help

Upper and lower case never matter. The master is one or more words separated by
spaces; 5-6 random words are recommended.
EOF
}

# --- normalization ----------------------------------------------------------

trim() {
    local s=$1
    s="${s#"${s%%[![:space:]]*}"}"
    printf '%s' "${s%"${s##*[![:space:]]}"}"
}

# Unicode-aware lowercase. Runs in a subshell with builtins only, so the value
# never reaches the process list.
lower() {
    (
        LC_ALL=C.UTF-8
        printf '%s' "${1,,}"
    )
}

# 'https://www.Allegro.pl/konto' -> 'allegro', 'Discord' -> 'discord'
normalize_site() {
    local s n
    s=$(trim "${1,,}")
    [[ $s == *://* ]] && s="${s#*://}"
    s="${s%%[/?#]*}"
    s="${s##*@}"
    s="${s%%:*}"
    s="${s#www.}"
    s="${s%.}"
    [[ -n $s && $s != .* && $s != *. && $s != *..* ]] || return 1
    local -a l
    IFS=. read -ra l <<<"$s"
    n=${#l[@]}
    if ((n >= 3)) && [[ " $TWO_PART_TLDS " == *" ${l[n - 2]}.${l[n - 1]} "* ]]; then
        s=${l[n - 3]}
    elif ((n >= 2)); then
        s=${l[n - 2]}
    fi
    [[ $s =~ ^[a-z0-9-]+$ ]] || return 1
    printf '%s' "$s"
}

normalize_user() {
    local u
    u=$(trim "$(lower "$1")")
    [[ $u != *[[:cntrl:]]* ]] || return 1
    printf '%s' "$u"
}

# Lowercase, and any run of spaces/tabs/newlines becomes a single space.
normalize_master() {
    local -a w
    read -ra w <<<"$(lower "$1")"
    local IFS=' '
    MASTER="${w[*]}"
}

# Warns about masters that someone with one leaked password could guess.
master_strength() {
    local -a w
    read -ra w <<<"$MASTER"
    local word all_eff=1
    for word in "${w[@]}"; do
        [[ -n ${WORD_SET[$word]:-} ]] || all_eff=0
    done
    if ((all_eff && ${#w[@]} < 5)) || ((${#MASTER} < 16)); then
        warn "Weak master: ${#w[@]} word(s), ${#MASTER} characters."
        warn "If one site leaks your password, a master this short can be guessed. 5-6 random words are recommended."
        return 1
    fi
}

# --- key derivation ---------------------------------------------------------

# derive_hex <salt> <bytes>: Argon2id(master, salt) as hex. The master goes
# through a pipe from a builtin, so it never shows up in the process list.
derive_hex() {
    printf '%s' "$MASTER" | argon2 "$1" -id -t "$ARGON_T" -m "$ARGON_M" -p "$ARGON_P" -l "$2" -r
}

# Turns hex into a list of 32-bit numbers that pick() consumes in order.
load_ints() {
    local hex=$1 i
    INTS=()
    POS=0
    for ((i = 0; i < ${#hex}; i += 8)); do
        INTS+=($((16#${hex:i:8})))
    done
}

# pick <n>: unbiased number 0..n-1 into REPLY.
pick() {
    local n=$1 limit x
    limit=$((4294967296 - 4294967296 % n))
    while ((POS < ${#INTS[@]})); do
        x=${INTS[POS]}
        POS=$((POS + 1))
        if ((x < limit)); then
            REPLY=$((x % n))
            return
        fi
    done
    die "Ran out of random data (should never happen)."
}

load_words() {
    [[ -f $WORDLIST ]] || die "Word list not found: $WORDLIST"
    local sum
    sum=$(sha256sum "$WORDLIST")
    [[ ${sum%% *} == "$WORDLIST_SHA256" ]] || die "Word list differs from the EFF original, passwords would not match."
    WORDS=()
    declare -gA WORD_SET=()
    local _num word
    while IFS=$'\t' read -r _num word; do
        WORDS+=("$word")
        WORD_SET[$word]=1
    done <"$WORDLIST"
}

# make_password <site> <user> <version> <mode>: result in PASSWORD.
make_password() {
    local site=$1 user=$2 version=$3 mode=$4 hex i j t
    hex=$(derive_hex "$SALT_PREFIX:site:$site:$version:$mode:$user" "$SITE_BYTES") || die "Argon2 failed."
    load_ints "$hex"
    PASSWORD=""
    if [[ $mode == words ]]; then
        for ((i = 0; i < WORD_COUNT; i++)); do
            pick "${#WORDS[@]}"
            PASSWORD+="${PASSWORD:+-}${WORDS[REPLY]^}"
        done
        pick "${#DIGITS}"
        PASSWORD+="${DIGITS:REPLY:1}"
    else
        # One character from each group, the rest from all of them, then shuffle.
        local len=${mode#chars} all="$UPPER$LOWER$DIGITS$SYMBOLS" group
        local -a c=()
        for group in "$UPPER" "$LOWER" "$DIGITS" "$SYMBOLS"; do
            pick "${#group}"
            c+=("${group:REPLY:1}")
        done
        for ((i = 4; i < len; i++)); do
            pick "${#all}"
            c+=("${all:REPLY:1}")
        done
        for ((i = len - 1; i > 0; i--)); do
            pick $((i + 1))
            j=$REPLY
            t=${c[i]}
            c[i]=${c[j]}
            c[j]=$t
        done
        PASSWORD=$(printf '%s' "${c[@]}")
    fi
}

# Two words that are always the same for the same master. Same on the phone.
check_words() {
    local hex
    hex=$(derive_hex "$SALT_PREFIX:check" 32) || die "Argon2 failed."
    load_ints "$hex"
    pick "${#WORDS[@]}"
    local a=${WORDS[REPLY]}
    pick "${#WORDS[@]}"
    printf '%s %s' "$a" "${WORDS[REPLY]}"
}

# --- vault ------------------------------------------------------------------
# Plain text inside the encryption: one line per version, fields separated by
# 0x1F: site, user, version, mode, since, until (empty until = current).

gpg_with_key() {
    gpg --batch --quiet --no-symkey-cache --pinentry-mode loopback \
        --passphrase-fd 3 "$@" 3< <(printf '%s\n' "$VAULT_KEY")
}

vault_load() {
    R_SITE=() R_USER=() R_VER=() R_MODE=() R_SINCE=() R_UNTIL=()
    [[ -f $VAULT ]] || return 0
    local plain line
    plain=$(gpg_with_key --decrypt "$VAULT" 2>/dev/null) || die "Cannot open the vault: wrong master?"
    while IFS= read -r line; do
        [[ -z $line || $line == \#* ]] && continue
        local -a f
        IFS=$SEP read -ra f <<<"$line$SEP"
        R_SITE+=("${f[0]}") R_USER+=("${f[1]:-}") R_VER+=("${f[2]}")
        R_MODE+=("${f[3]}") R_SINCE+=("${f[4]}") R_UNTIL+=("${f[5]:-}")
    done <<<"$plain"
}

vault_save() {
    local dir tmp i
    dir=$(dirname "$VAULT")
    (umask 077 && mkdir -p "$dir")
    tmp=$(mktemp "$dir/.vault.XXXXXX")
    {
        echo "$VAULT_HEADER"
        for i in "${!R_SITE[@]}"; do
            printf '%s\n' "${R_SITE[i]}$SEP${R_USER[i]}$SEP${R_VER[i]}$SEP${R_MODE[i]}$SEP${R_SINCE[i]}$SEP${R_UNTIL[i]}"
        done
    } | gpg_with_key --yes --symmetric --cipher-algo AES256 --output "$tmp" || {
        rm -f "$tmp"
        die "Could not save the vault."
    }
    [[ -f $VAULT ]] && cp -p "$VAULT" "$VAULT.bak"
    mv "$tmp" "$VAULT"
}

# find_current <site> <user>: index of the current version into REPLY, or fail.
find_current() {
    local i
    for i in "${!R_SITE[@]}"; do
        if [[ ${R_SITE[i]} == "$1" && ${R_USER[i]} == "$2" && -z ${R_UNTIL[i]} ]]; then
            REPLY=$i
            return 0
        fi
    done
    return 1
}

add_record() {
    R_SITE+=("$1") R_USER+=("$2") R_VER+=("$3") R_MODE+=("$4") R_SINCE+=("$(date +%F)") R_UNTIL+=("")
}

# --- typo suggestions -------------------------------------------------------

# distance <a> <b>: edit distance into REPLY, a swap of two letters counts as one.
distance() {
    local a=$1 b=$2 la=${#1} lb=${#2} w i j cost v
    w=$((lb + 1))
    local -a d=()
    for ((i = 0; i <= la; i++)); do d[i * w]=$i; done
    for ((j = 0; j <= lb; j++)); do d[j]=$j; done
    for ((i = 1; i <= la; i++)); do
        for ((j = 1; j <= lb; j++)); do
            cost=1
            [[ ${a:i-1:1} == "${b:j-1:1}" ]] && cost=0
            v=$((d[(i - 1) * w + j] + 1))
            ((d[i * w + j - 1] + 1 < v)) && v=$((d[i * w + j - 1] + 1))
            ((d[(i - 1) * w + j - 1] + cost < v)) && v=$((d[(i - 1) * w + j - 1] + cost))
            if ((i > 1 && j > 1)) && [[ ${a:i-1:1} == "${b:j-2:1}" && ${a:i-2:1} == "${b:j-1:1}" ]]; then
                ((d[(i - 2) * w + j - 2] + 1 < v)) && v=$((d[(i - 2) * w + j - 2] + 1))
            fi
            d[i * w + j]=$v
        done
    done
    REPLY=${d[la * w + lb]}
}

# If SITE/USER_NAME is not on the list but something close is, asks whether
# that was meant and switches to it. An exact match never asks anything.
resolve_typo() {
    find_current "$SITE" "$USER_NAME" && return 0
    local i limit=2 n=0 ans
    ((${#SITE} <= 4)) && limit=1
    local -a cand=()
    while IFS=' ' read -r _ i; do
        [[ -n $i ]] && cand+=("$i")
    done < <(
        for i in "${!R_SITE[@]}"; do
            [[ -z ${R_UNTIL[i]} ]] || continue
            if ((${#SITE} - ${#R_SITE[i]} > limit || ${#R_SITE[i]} - ${#SITE} > limit)); then continue; fi
            distance "$SITE" "${R_SITE[i]}"
            ((REPLY <= limit)) && echo "$REPLY $i"
        done | sort -n | head -5
    )
    ((${#cand[@]})) || return 1
    echo "${YELLOW}?${RST} '$(label "$SITE" "$USER_NAME")' is not on your list. Did you mean:" >&2
    for i in "${cand[@]}"; do
        n=$((n + 1))
        echo "  ${BOLD}$n)${RST} $(label "${R_SITE[i]}" "${R_USER[i]}")" >&2
    done
    echo "  ${BOLD}0)${RST} no, '$(label "$SITE" "$USER_NAME")' is a different site" >&2
    read -rp "Choice [1]: " ans </dev/tty
    ans=${ans:-1}
    [[ $ans =~ ^[0-9]{1,2}$ ]] || return 1
    ((ans >= 1 && ans <= ${#cand[@]})) || return 1
    i=${cand[ans - 1]}
    SITE=${R_SITE[i]} USER_NAME=${R_USER[i]}
    find_current "$SITE" "$USER_NAME"
}

# --- output -----------------------------------------------------------------

label() {
    local s=$1
    [[ -n $2 ]] && s="$1 ($2)"
    [[ -n ${3:-} ]] && s+=" v$3"
    printf '%s' "$s"
}

output_password() {
    if ((COPY)); then
        printf '%s' "$PASSWORD" | wl-copy
        local pw=$PASSWORD
        (
            sleep "$CLIP_SECONDS"
            [[ "$(wl-paste -n 2>/dev/null)" == "$pw" ]] && wl-copy --clear
        ) &>/dev/null &
        disown
        ok "${BOLD}$1${RST}: copied, clipboard clears in $CLIP_SECONDS s."
    else
        ok "${BOLD}$1${RST}:"
        printf '    %s\n' "${BOLD}${MAGENTA}$PASSWORD${RST}"
    fi
}

ask_yes() {
    local answer
    read -rp "${YELLOW}?${RST} $1 [y/N] " answer </dev/tty
    [[ $answer == [yY]* ]]
}

# --- commands ---------------------------------------------------------------

need_site() {
    [[ -n $SITE_ARG ]] || die "Which site? e.g. nexopass $CMD discord"
    SITE=$(normalize_site "$SITE_ARG") || die "Not a valid site name: $SITE_ARG"
}

cmd_get() {
    need_site
    vault_load
    local i mode
    if resolve_typo; then
        i=$REPLY
        [[ -z $LENGTH || ${R_MODE[i]} == "chars$LENGTH" ]] ||
            info "Length is fixed per version; use 'rotate -n $LENGTH' to change it."
        [[ -z $VERSION_ARG || $VERSION_ARG == "${R_VER[i]}" ]] ||
            die "$(label "$SITE" "$USER_NAME" "${R_VER[i]}") is already saved; use rotate to move to a newer version."
    else
        mode=words
        [[ -n $LENGTH ]] && mode="chars$LENGTH"
        ask_yes "Add '$(label "$SITE" "$USER_NAME")' to your list?" || die "Cancelled."
        add_record "$SITE" "$USER_NAME" "${VERSION_ARG:-1}" "$mode"
        vault_save
        i=$((${#R_SITE[@]} - 1))
        ok "Added $(label "$SITE" "$USER_NAME" "${R_VER[i]}")."
    fi
    make_password "$SITE" "$USER_NAME" "${R_VER[i]}" "${R_MODE[i]}"
    output_password "$(label "$SITE" "$USER_NAME" "${R_VER[i]}")"
}

cmd_rotate() {
    need_site
    vault_load
    resolve_typo || die "'$SITE' is not on your list. Use: nexopass get $SITE_ARG"
    local i=$REPLY mode version
    mode=${R_MODE[i]}
    [[ -n $LENGTH ]] && mode="chars$LENGTH"
    version=$((R_VER[i] + 1))
    ask_yes "Archive version ${R_VER[i]} of $(label "$SITE" "$USER_NAME") and switch to version $version?" || die "Cancelled."
    R_UNTIL[i]=$(date +%F)
    add_record "$SITE" "$USER_NAME" "$version" "$mode"
    vault_save
    ok "Version ${R_VER[i]} archived. Now change the password on the site to:"
    make_password "$SITE" "$USER_NAME" "$version" "$mode"
    output_password "$(label "$SITE" "$USER_NAME" "$version")"
}

print_rows() {
    local i state
    printf '%s%-20s %-18s %-5s %-8s %-10s %s%s\n' "$DIM" SITE USER VER MODE SINCE UNTIL "$RST"
    for i in "$@"; do
        state="${GREEN}current${RST}"
        [[ -n ${R_UNTIL[i]} ]] && state="${DIM}${R_UNTIL[i]}${RST}"
        printf '%s%-20s%s %-18s %s%-5s%s %-8s %-10s %s\n' "$BOLD" "${R_SITE[i]}" "$RST" "${R_USER[i]:--}" \
            "$CYAN" "v${R_VER[i]}" "$RST" "${R_MODE[i]}" "${R_SINCE[i]}" "$state"
        if ((SHOW)); then
            make_password "${R_SITE[i]}" "${R_USER[i]}" "${R_VER[i]}" "${R_MODE[i]}"
            printf '    %s\n' "${MAGENTA}$PASSWORD${RST}"
        fi
    done
}

cmd_list() {
    vault_load
    local -a rows=()
    local i
    while IFS= read -r i; do rows+=("$i"); done < <(
        for i in "${!R_SITE[@]}"; do
            [[ -z ${R_UNTIL[i]} ]] && printf '%s\t%s\t%s\n' "${R_SITE[i]}" "${R_USER[i]}" "$i"
        done | sort | cut -f3
    )
    ((${#rows[@]})) || {
        info "No sites yet. Add one with: nexopass get <site>"
        return
    }
    print_rows "${rows[@]}"
}

cmd_history() {
    need_site
    vault_load
    resolve_typo || die "'$SITE' is not on your list."
    local -a rows=()
    local i
    while IFS= read -r i; do rows+=("$i"); done < <(
        for i in "${!R_SITE[@]}"; do
            [[ ${R_SITE[i]} == "$SITE" && ${R_USER[i]} == "$USER_NAME" ]] && printf '%s\t%s\n' "${R_VER[i]}" "$i"
        done | sort -n | cut -f2
    )
    print_rows "${rows[@]}"
}

cmd_remove() {
    need_site
    vault_load
    resolve_typo || die "'$SITE' is not on your list."
    ask_yes "Remove $(label "$SITE" "$USER_NAME") and its history from the list?" || die "Cancelled."
    local i
    local -a s=() u=() v=() m=() a=() b=()
    for i in "${!R_SITE[@]}"; do
        [[ ${R_SITE[i]} == "$SITE" && ${R_USER[i]} == "$USER_NAME" ]] && continue
        s+=("${R_SITE[i]}") u+=("${R_USER[i]}") v+=("${R_VER[i]}") m+=("${R_MODE[i]}") a+=("${R_SINCE[i]}") b+=("${R_UNTIL[i]}")
    done
    R_SITE=("${s[@]}") R_USER=("${u[@]}") R_VER=("${v[@]}") R_MODE=("${m[@]}") R_SINCE=("${a[@]}") R_UNTIL=("${b[@]}")
    vault_save
    ok "Removed."
}

cmd_new_master() {
    local count=${SITE_ARG:-6}
    [[ $count =~ ^[1-9][0-9]?$ ]] || die "Number of words must be 1-99."
    local -a picked
    mapfile -t picked < <(printf '%s\n' "${WORDS[@]}" | shuf -n "$count" --random-source=/dev/urandom)
    echo "${BOLD}${MAGENTA}${picked[*]}${RST}"
    ((count >= 5)) || warn "Fewer than 5 words is weak, see 'nexopass help'."
}

# --- argument handling ------------------------------------------------------

parse_args() {
    CMD="" SITE_ARG="" USER_NAME="" LENGTH="" VERSION_ARG="" COPY=0 SHOW=0
    while (($#)); do
        case $1 in
        -u | --user | -n | --length | -v | --version)
            (($# >= 2)) || die "$1 needs a value."
            case $1 in
            -u | --user) USER_NAME=$(normalize_user "$2") || die "Invalid account name." ;;
            -n | --length) LENGTH=$2 ;;
            -v | --version) VERSION_ARG=$2 ;;
            esac
            shift 2
            ;;
        -c | --copy) COPY=1 && shift ;;
        -s | --show) SHOW=1 && shift ;;
        -h | --help) CMD=help && shift ;;
        -*) die "Unknown option: $1 (see nexopass help)" ;;
        *)
            if [[ -z $CMD ]]; then
                CMD=${1,,}
            elif [[ -z $SITE_ARG ]]; then
                SITE_ARG=$1
            else
                die "Unexpected argument: $1"
            fi
            shift
            ;;
        esac
    done
    case $CMD in
    get | rotate | list | history | remove | new-master | help | "") ;;
    *) SITE_ARG=$CMD CMD=get ;;
    esac
    if [[ -n $LENGTH ]]; then
        [[ $LENGTH =~ ^[1-6][0-9]$ ]] || die "Length must be 12-64."
        ((LENGTH >= 12 && LENGTH <= 64)) || die "Length must be 12-64."
    fi
    if [[ -n $VERSION_ARG ]]; then
        [[ $VERSION_ARG =~ ^[1-9][0-9]{0,3}$ ]] || die "Version must be a number from 1."
    fi
}

run_command() {
    case $CMD in
    get) cmd_get ;;
    rotate) cmd_rotate ;;
    list) cmd_list ;;
    history) cmd_history ;;
    remove) cmd_remove ;;
    new-master) cmd_new_master ;;
    help) usage ;;
    esac
}

read_master() {
    local raw
    read -rsp "${BOLD}Master:${RST} " raw </dev/tty
    echo >&2
    normalize_master "$raw"
    [[ -n $MASTER ]] || die "Empty master."
    ((${#MASTER} <= 127)) || die "Master is too long (max 127 bytes)."
    if [[ ! -f $VAULT ]]; then
        local first=$MASTER
        read -rsp "No vault yet, so this is your first run. Repeat master: " raw </dev/tty
        echo >&2
        normalize_master "$raw"
        [[ $MASTER == "$first" ]] || die "Masters don't match."
        master_strength || ask_yes "Use it anyway?" || die "Cancelled."
        info "Check words: ${BOLD}$(check_words)${RST}"
        info "Remember them: the phone app shows the same words for the same master."
    fi
    info "Unlocking..."
    VAULT_KEY=$(derive_hex "$SALT_PREFIX:vault" 32) || die "Argon2 failed."
    vault_load
}

banner() {
    echo "${MAGENTA}${BOLD}  ╭──────────────────╮${RST}"
    echo "${MAGENTA}${BOLD}  │${RST}  ${BOLD}N E X O P A S S${RST} ${MAGENTA}${BOLD}│${RST}"
    echo "${MAGENTA}${BOLD}  ╰──────────────────╯${RST}"
}

session() {
    ok "Unlocked. Commands: ${CYAN}<site>  get  rotate  list  history  remove  help  quit${RST}"
    local line
    local -a words
    while IFS= read -rep "${MAGENTA}nexopass›${RST} " line; do
        read -ra words <<<"$line"
        ((${#words[@]})) || continue
        case ${words[0],,} in
        quit | exit | q) break ;;
        esac
        (
            parse_args "${words[@]}"
            [[ -n $CMD ]] && run_command
        ) || true
    done
}

main() {
    load_words
    parse_args "$@"
    case $CMD in
    help) usage && return ;;
    new-master) cmd_new_master && return ;;
    "") banner ;;
    esac
    read_master
    if [[ -z $CMD ]]; then
        session
    else
        run_command
    fi
}

main "$@"
