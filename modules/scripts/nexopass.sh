#!/usr/bin/env bash
# NexoPass: passwords derived from one master, nothing stored in plain text.
#
# password = Argon2id(master, site + version + mode + user). The same input
# always gives the same password, so no password is ever saved anywhere.
# The vault only remembers which sites you use, their current version and the
# archive of old versions. It is encrypted (GnuPG, AES-256) with a key that is
# also derived from the master.
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

die() { echo "[!] $*" >&2; exit 1; }
info() { echo "[*] $*" >&2; }

usage() {
    cat <<'EOF'
NexoPass - passwords derived from one master, nothing stored in plain text.

Usage: nexopass [command] [site] [options]

Commands:
  get <site>       Show the password for a site (adds the site on first use)
  rotate <site>    After a breach: switch to the next version, archive the old one
  list             List your sites with their current version
  history <site>   Show all versions of a site, old ones included
  remove <site>    Remove a site from the list (passwords themselves don't change)
  new-master       Generate a random 6-word master
  help             Show this help

  nexopass <site>  Same as: nexopass get <site>
  nexopass         Interactive session: master asked once, then type commands

Options:
  -u, --user NAME    Account name, for several accounts on one site
  -n, --length N     Random characters (12-64) instead of words, for sites
                     with a length limit; set when adding or rotating a site
  -v, --version N    Start a new site at version N (e.g. already rotated on phone)
  -c, --copy         Copy to clipboard (cleared after 30 s) instead of printing
  -s, --show         With list/history: also show the passwords
  -h, --help         Show this help
EOF
}

# --- site names -------------------------------------------------------------

# 'https://www.Allegro.pl/konto' -> 'allegro', 'Discord' -> 'discord'
normalize_site() {
    local s="${1,,}" n
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
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
    local u="${1,,}"
    u="${u#"${u%%[![:space:]]*}"}"
    u="${u%"${u##*[![:space:]]}"}"
    [[ $u != *[[:cntrl:]]* ]] || return 1
    printf '%s' "$u"
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
    local _num word
    while IFS=$'\t' read -r _num word; do
        WORDS+=("$word")
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

# --- output -----------------------------------------------------------------

label() {
    local s="$1 v$3"
    [[ -n $2 ]] && s="$1 ($2) v$3"
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
        echo "[+] $1: copied, clipboard clears in $CLIP_SECONDS s."
    else
        echo "[+] $1:"
        printf '%s\n' "$PASSWORD"
    fi
}

ask_yes() {
    local answer
    read -rp "$1 [y/N] " answer </dev/tty
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
    if find_current "$SITE" "$USER_NAME"; then
        i=$REPLY
        [[ -z $LENGTH || ${R_MODE[i]} == "chars$LENGTH" ]] ||
            info "Length is fixed per version; use 'rotate -n $LENGTH' to change it."
        [[ -z $VERSION_ARG || $VERSION_ARG == "${R_VER[i]}" ]] ||
            die "$(label "$SITE" "$USER_NAME" "${R_VER[i]}") is already saved; use rotate to move to a newer version."
    else
        mode=words
        [[ -n $LENGTH ]] && mode="chars$LENGTH"
        ask_yes "'$SITE' is not on your list yet. Add it?" || die "Cancelled."
        add_record "$SITE" "$USER_NAME" "${VERSION_ARG:-1}" "$mode"
        vault_save
        i=$((${#R_SITE[@]} - 1))
        echo "[+] Added $(label "$SITE" "$USER_NAME" "${R_VER[i]}")."
    fi
    make_password "$SITE" "$USER_NAME" "${R_VER[i]}" "${R_MODE[i]}"
    output_password "$(label "$SITE" "$USER_NAME" "${R_VER[i]}")"
}

cmd_rotate() {
    need_site
    vault_load
    find_current "$SITE" "$USER_NAME" || die "'$SITE' is not on your list. Use: nexopass get $SITE_ARG"
    local i=$REPLY mode version
    mode=${R_MODE[i]}
    [[ -n $LENGTH ]] && mode="chars$LENGTH"
    version=$((R_VER[i] + 1))
    R_UNTIL[i]=$(date +%F)
    add_record "$SITE" "$USER_NAME" "$version" "$mode"
    vault_save
    echo "[+] Version ${R_VER[i]} archived. Change the password on the site to:"
    make_password "$SITE" "$USER_NAME" "$version" "$mode"
    output_password "$(label "$SITE" "$USER_NAME" "$version")"
}

print_rows() {
    local i
    printf '%-20s %-18s %-4s %-8s %-10s %s\n' SITE USER VER MODE SINCE UNTIL
    for i in "$@"; do
        printf '%-20s %-18s %-4s %-8s %-10s %s\n' "${R_SITE[i]}" "${R_USER[i]:--}" "v${R_VER[i]}" \
            "${R_MODE[i]}" "${R_SINCE[i]}" "${R_UNTIL[i]:-current}"
        if ((SHOW)); then
            make_password "${R_SITE[i]}" "${R_USER[i]}" "${R_VER[i]}" "${R_MODE[i]}"
            printf '    %s\n' "$PASSWORD"
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
    local -a rows=()
    local i
    while IFS= read -r i; do rows+=("$i"); done < <(
        for i in "${!R_SITE[@]}"; do
            [[ ${R_SITE[i]} == "$SITE" ]] && printf '%s\t%s\t%s\n' "${R_USER[i]}" "${R_VER[i]}" "$i"
        done | sort -t $'\t' -k1,1 -k2,2n | cut -f3
    )
    ((${#rows[@]})) || die "'$SITE' is not on your list."
    print_rows "${rows[@]}"
}

cmd_remove() {
    need_site
    vault_load
    find_current "$SITE" "$USER_NAME" || die "'$SITE' is not on your list."
    ask_yes "Remove $(label "$SITE" "$USER_NAME" "${R_VER[REPLY]}") and its history from the list?" || die "Cancelled."
    local i
    local -a keep=()
    for i in "${!R_SITE[@]}"; do
        [[ ${R_SITE[i]} == "$SITE" && ${R_USER[i]} == "$USER_NAME" ]] || keep+=("$i")
    done
    local -a s=() u=() v=() m=() a=() b=()
    for i in "${keep[@]}"; do
        s+=("${R_SITE[i]}") u+=("${R_USER[i]}") v+=("${R_VER[i]}") m+=("${R_MODE[i]}") a+=("${R_SINCE[i]}") b+=("${R_UNTIL[i]}")
    done
    R_SITE=("${s[@]}") R_USER=("${u[@]}") R_VER=("${v[@]}") R_MODE=("${m[@]}") R_SINCE=("${a[@]}") R_UNTIL=("${b[@]}")
    vault_save
    echo "[+] Removed."
}

cmd_new_master() {
    local -a pick6
    mapfile -t pick6 < <(printf '%s\n' "${WORDS[@]}" | shuf -n 6 --random-source=/dev/urandom)
    echo "${pick6[*]}"
}

# --- argument handling ------------------------------------------------------

parse_args() {
    CMD="" SITE_ARG="" USER_NAME="" LENGTH="" VERSION_ARG="" COPY=0 SHOW=0
    while (($#)); do
        case $1 in
        -u | --user | -n | --length | -v | --version)
            (($# >= 2)) || die "$1 needs a value."
            case $1 in
            -u | --user) USER_NAME=$(normalize_user "$2") || die "Invalid user name." ;;
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
                CMD=$1
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
    read -rsp "Master: " MASTER </dev/tty
    echo >&2
    [[ -n $MASTER ]] || die "Empty master."
    ((${#MASTER} <= 127)) || die "Master is too long (max 127 bytes)."
    if [[ ! -f $VAULT ]]; then
        local again
        read -rsp "No vault yet, so this is your first run. Repeat master: " again </dev/tty
        echo >&2
        [[ $MASTER == "$again" ]] || die "Masters don't match."
        info "Check words: $(check_words)"
        info "Remember them: the phone app shows the same words for the same master."
    fi
    info "Unlocking..."
    VAULT_KEY=$(derive_hex "$SALT_PREFIX:vault" 32) || die "Argon2 failed."
    vault_load
}

session() {
    echo "[+] Unlocked. Commands: <site>, get, rotate, list, history, remove, help, quit"
    local line
    local -a words
    while IFS= read -rep "nexopass> " line; do
        read -ra words <<<"$line"
        ((${#words[@]})) || continue
        case ${words[0]} in
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
    esac
    read_master
    if [[ -z $CMD ]]; then
        session
    else
        run_command
    fi
}

main "$@"
