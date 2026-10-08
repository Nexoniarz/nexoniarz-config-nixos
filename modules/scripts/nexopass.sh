#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Nexoniarz
#
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

NEXOPASS_VERSION="1.1.0"
WORDLIST="${NEXOPASS_WORDLIST:-$(dirname "$(readlink -f "$0")")/eff_large_wordlist.txt}"
WORDLIST_SHA256="addd35536511597a02fa0a9ff1e5284677b8883b83e986e43f15a3db996b903e"
VAULT="${NEXOPASS_VAULT:-${XDG_DATA_HOME:-$HOME/.local/share}/nexopass/vault.gpg}"
DATA_DIR=$(dirname "$VAULT")
QUICK="$DATA_DIR/quick.gpg"
QUICK_META="$DATA_DIR/quick.meta"
CONFIG="${NEXOPASS_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/nexopass/config}"

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

# Quick unlock keys are slower on purpose: a PIN has few combinations.
QUICK_T=4
QUICK_M=18 # 2^18 KiB = 256 MiB

MIN_MASTER_WORDS=3
MIN_MASTER_BYTES=12
SEP=$'\x1f'
VAULT_HEADER="# nexopass vault v1"

die() { echo "${RED:-}[!]${RST:-} $*" >&2; exit 1; }
info() { echo "${CYAN}[*]${RST} $*" >&2; }
warn() { echo "${YELLOW}[!]${RST} $*" >&2; }
ok() { echo "${GREEN}[+]${RST} $*"; }

setup_colors() {
    if [[ $CFG_COLOR != never && -t 1 && -t 2 && -z ${NO_COLOR:-} ]]; then
        RST=$'\e[0m' BOLD=$'\e[1m' DIM=$'\e[2m' RED=$'\e[31m' GREEN=$'\e[32m'
        YELLOW=$'\e[33m' MAGENTA=$'\e[35m' CYAN=$'\e[36m'
    else
        RST="" BOLD="" DIM="" RED="" GREEN="" YELLOW="" MAGENTA="" CYAN=""
    fi
}

usage() {
    cat <<EOF
${BOLD}${MAGENTA}NexoPass${RST} $NEXOPASS_VERSION - passwords derived from one master, nothing stored in plain text.

${BOLD}Usage:${RST} nexopass [command] [site] [options]

${BOLD}Passwords:${RST}
  ${CYAN}get${RST} <site>        Show the password for a site (adds the site on first use)
  ${CYAN}rotate${RST} <site>     After a breach: switch to the next version, archive the old one
  ${CYAN}list${RST}              List your sites with their current version
  ${CYAN}history${RST} <site>    Show all versions of a site, old ones included
  ${CYAN}remove${RST} <site>     Remove a site from the list (passwords themselves don't change)

${BOLD}Vault and security:${RST}
  ${CYAN}settings${RST}          Quick unlock (PIN/password), auto-lock, clipboard, defaults...
  ${CYAN}export${RST} [file]     Save an encrypted copy of your site list (opens on the phone too)
  ${CYAN}import${RST} <file>     Merge an exported site list into this one
  ${CYAN}lock${RST}              Forget the remembered master right now
  ${CYAN}show-master${RST}       Show your master (needs your PIN/password)
  ${CYAN}new-master${RST} [N]    Generate a random master of N words (default 6)
  ${CYAN}about${RST}             Version, author, license

  nexopass <site>   Same as: nexopass get <site>
  nexopass          Interactive session: unlock once, then type commands

${BOLD}Options:${RST}
  -u, --user NAME    Account name, for several accounts on one site
  -n, --length N     Random characters (12-64) instead of words, for sites
                     with a length limit; set when adding or rotating a site
  -v, --version N    Start a new site at version N (e.g. already rotated on phone)
  -c, --copy         Copy to clipboard instead of printing
  -s, --show         With list/history: also show the passwords
  -h, --help         Show this help

Case never matters. The master is ${MIN_MASTER_WORDS}+ words separated by spaces:
3 is the minimum, 4 recommended, 6 the safest.
EOF
}

about() {
    cat <<EOF
${BOLD}${MAGENTA}NexoPass${RST} $NEXOPASS_VERSION
Passwords derived from one master, nothing stored in plain text.
Compatible with the NexoPass Android app.

Made by ${BOLD}Nexoniarz${RST}
License: Apache License 2.0
EOF
}

# --- settings ---------------------------------------------------------------
# Plain key=value file, nothing secret in it. Unknown or invalid lines are ignored.

load_config() {
    CFG_CACHE=5 CFG_CLIP=30 CFG_LENGTH=0 CFG_COLOR=auto CFG_ATTEMPTS=5
    [[ -f $CONFIG ]] || return 0
    local k v
    while IFS='=' read -r k v; do
        case $k in
        cache_minutes) [[ $v =~ ^(0|1|5|15|30|60)$ ]] && CFG_CACHE=$v ;;
        clip_seconds) [[ $v =~ ^(10|15|30|60|120)$ ]] && CFG_CLIP=$v ;;
        default_length) [[ $v == 0 || $v =~ ^(1[2-9]|[2-5][0-9]|6[0-4])$ ]] && CFG_LENGTH=$v ;;
        color) [[ $v =~ ^(auto|never)$ ]] && CFG_COLOR=$v ;;
        max_attempts) [[ $v =~ ^(3|5|10)$ ]] && CFG_ATTEMPTS=$v ;;
        esac
    done <"$CONFIG"
}

save_config() {
    mkdir -p "$(dirname "$CONFIG")"
    printf '%s\n' "# NexoPass settings, change with: nexopass settings" \
        "cache_minutes=$CFG_CACHE" "clip_seconds=$CFG_CLIP" "default_length=$CFG_LENGTH" \
        "color=$CFG_COLOR" "max_attempts=$CFG_ATTEMPTS" >"$CONFIG.tmp"
    mv "$CONFIG.tmp" "$CONFIG"
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

# Prints the strength label; fails when the master is below the minimum.
master_strength() {
    local -a w
    read -ra w <<<"$MASTER"
    local n=${#w[@]}
    if ((n < MIN_MASTER_WORDS || ${#MASTER} < MIN_MASTER_BYTES)); then
        echo "too short: at least $MIN_MASTER_WORDS words and $MIN_MASTER_BYTES characters"
        return 1
    fi
    case $n in
    3) echo "3 words: minimum" ;;
    4) echo "4 words: recommended" ;;
    5) echo "5 words: strong" ;;
    *) echo "$n words: safest" ;;
    esac
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

# --- gpg helpers ------------------------------------------------------------

# gpg_pass <passphrase> <gpg args...>: the passphrase goes in through fd 3.
gpg_pass() {
    local pass=$1
    shift
    gpg --batch --quiet --no-symkey-cache --pinentry-mode loopback \
        --passphrase-fd 3 "$@" 3< <(printf '%s\n' "$pass")
}

# --- vault ------------------------------------------------------------------
# Plain text inside the encryption: one line per version, fields separated by
# 0x1F: site, user, version, mode, since, until (empty until = current).

# parse_records <text> <prefix>: fills <prefix>_SITE, _USER... arrays.
parse_records() {
    local -n ps=${2}_SITE pu=${2}_USER pv=${2}_VER pm=${2}_MODE pa=${2}_SINCE pb=${2}_UNTIL
    ps=() pu=() pv=() pm=() pa=() pb=()
    local line site
    while IFS= read -r line; do
        [[ -z $line || $line == \#* ]] && continue
        local -a f
        IFS=$SEP read -ra f <<<"$line$SEP"
        ((${#f[@]} >= 5)) || continue
        [[ ${f[2]} =~ ^[1-9][0-9]{0,3}$ ]] || continue
        site=$(normalize_site "${f[0]}") || continue
        [[ $site == "${f[0]}" ]] || continue
        ps+=("${f[0]}") pu+=("${f[1]:-}") pv+=("${f[2]}") pm+=("${f[3]}") pa+=("${f[4]}") pb+=("${f[5]:-}")
    done <<<"$1"
}

vault_text() {
    local i
    echo "$VAULT_HEADER"
    for i in "${!R_SITE[@]}"; do
        printf '%s\n' "${R_SITE[i]}$SEP${R_USER[i]}$SEP${R_VER[i]}$SEP${R_MODE[i]}$SEP${R_SINCE[i]}$SEP${R_UNTIL[i]}"
    done
}

vault_load() {
    R_SITE=() R_USER=() R_VER=() R_MODE=() R_SINCE=() R_UNTIL=()
    [[ -f $VAULT ]] || return 0
    local plain
    plain=$(gpg_pass "$VAULT_KEY" --decrypt "$VAULT" 2>/dev/null) || return 1
    parse_records "$plain" R
}

vault_save() {
    local tmp
    (umask 077 && mkdir -p "$DATA_DIR")
    tmp=$(mktemp "$DATA_DIR/.vault.XXXXXX")
    vault_text | gpg_pass "$VAULT_KEY" --yes --symmetric --cipher-algo AES256 --output "$tmp" || {
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

# Merges the I_* arrays into R_*. Per site and account the highest version is
# the current one, every lower version is archived. Same rule as the app.
merge_records() {
    local -a lines=()
    local i
    mapfile -t lines < <(
        {
            for i in "${!R_SITE[@]}"; do
                printf '%s\n' "${R_SITE[i]}$SEP${R_USER[i]}$SEP${R_VER[i]}$SEP${R_MODE[i]}$SEP${R_SINCE[i]}$SEP${R_UNTIL[i]}"
            done
            for i in "${!I_SITE[@]}"; do
                printf '%s\n' "${I_SITE[i]}$SEP${I_USER[i]}$SEP${I_VER[i]}$SEP${I_MODE[i]}$SEP${I_SINCE[i]}$SEP${I_UNTIL[i]}"
            done
        } | sort -t "$SEP" -k1,1 -k2,2 -k3,3n
    )
    R_SITE=() R_USER=() R_VER=() R_MODE=() R_SINCE=() R_UNTIL=()
    local line n
    for line in "${lines[@]}"; do
        local -a f
        IFS=$SEP read -ra f <<<"$line$SEP"
        n=$((${#R_SITE[@]} - 1))
        if ((n >= 0)) && [[ ${R_SITE[n]} == "${f[0]}" && ${R_USER[n]} == "${f[1]:-}" && ${R_VER[n]} == "${f[2]}" ]]; then
            # Same version twice: keep the archived copy, it knows its end date.
            [[ -z ${R_UNTIL[n]} ]] && R_UNTIL[n]=${f[5]:-}
            continue
        fi
        R_SITE+=("${f[0]}") R_USER+=("${f[1]:-}") R_VER+=("${f[2]}") R_MODE+=("${f[3]}") R_SINCE+=("${f[4]}") R_UNTIL+=("${f[5]:-}")
    done
    for i in "${!R_SITE[@]}"; do
        n=$((i + 1))
        if ((n < ${#R_SITE[@]})) && [[ ${R_SITE[n]} == "${R_SITE[i]}" && ${R_USER[n]} == "${R_USER[i]}" ]]; then
            [[ -z ${R_UNTIL[i]} ]] && R_UNTIL[i]=${R_SINCE[n]}
        else
            R_UNTIL[i]=""
        fi
    done
}

# --- unlocking --------------------------------------------------------------
# Order: master remembered in the kernel keyring (if "stay unlocked" is on),
# then quick unlock (PIN/password), then the master itself.

cache_name() {
    local h
    h=$(printf '%s' "$VAULT" | sha256sum)
    printf 'nexopass:%s' "${h:0:16}"
}

cache_get() {
    ((CFG_CACHE > 0)) || return 1
    local id
    id=$(keyctl search @u user "$(cache_name)" 2>/dev/null) || return 1
    MASTER=$(keyctl pipe "$id" 2>/dev/null) || return 1
    keyctl timeout "$id" $((CFG_CACHE * 60)) &>/dev/null || true
}

cache_put() {
    ((CFG_CACHE > 0)) || return 0
    local id
    id=$(printf '%s' "$MASTER" | keyctl padd user "$(cache_name)" @u) || return 0
    keyctl timeout "$id" $((CFG_CACHE * 60)) &>/dev/null || true
}

cache_clear() {
    local id
    id=$(keyctl search @u user "$(cache_name)" 2>/dev/null) || return 0
    keyctl unlink "$id" @u &>/dev/null || true
}

quick_method() {
    [[ -f $QUICK && -f $QUICK_META ]] || return 1
    sed -n 's/^method=//p' "$QUICK_META"
}

quick_meta_get() { sed -n "s/^$1=//p" "$QUICK_META"; }

quick_meta_set_failed() {
    local m s
    m=$(quick_meta_get method)
    s=$(quick_meta_get salt)
    printf 'method=%s\nsalt=%s\nfailed=%s\n' "$m" "$s" "$1" >"$QUICK_META"
}

quick_key() {
    printf '%s' "$1" | argon2 "$2" -id -t "$QUICK_T" -m "$QUICK_M" -p 1 -l 32 -r
}

quick_remove() {
    rm -f "$QUICK" "$QUICK_META"
}

# Asks for the PIN/password until it works or the attempts run out.
# Fails (so the caller asks for the master) on empty input.
quick_unlock() {
    local method name secret key salt failed left
    method=$(quick_method) || return 1
    name=PIN
    [[ $method == password ]] && name=Password
    salt=$(quick_meta_get salt)
    while true; do
        read -rsp "${BOLD}$name${RST} ${DIM}(Enter = use master)${RST}: " secret </dev/tty
        echo >&2
        [[ -n $secret ]] || return 1
        info "Unlocking..."
        key=$(quick_key "$secret" "$salt") || die "Argon2 failed."
        if MASTER=$(gpg_pass "$key" --decrypt "$QUICK" 2>/dev/null); then
            quick_meta_set_failed 0
            return 0
        fi
        failed=$(($(quick_meta_get failed) + 1))
        left=$((CFG_ATTEMPTS - failed))
        if ((left <= 0)); then
            quick_remove
            warn "Too many wrong attempts: quick unlock removed. Use your master, then set it up again in settings."
            return 1
        fi
        quick_meta_set_failed "$failed"
        warn "Wrong ${name,,}. $left attempt(s) left."
    done
}

# Asks for the PIN/password once without counting it as unlock; for show-master.
quick_verify() {
    local method name secret key
    method=$(quick_method) || return 1
    name=PIN
    [[ $method == password ]] && name=Password
    read -rsp "${BOLD}$name${RST}: " secret </dev/tty
    echo >&2
    key=$(quick_key "$secret" "$(quick_meta_get salt)") || return 1
    QUICK_MASTER=$(gpg_pass "$key" --decrypt "$QUICK" 2>/dev/null)
}

quick_setup() {
    local method=$1 name secret again salt key
    name=PIN
    [[ $method == password ]] && name=password
    if [[ $method == pin ]]; then
        warn "This PC has no TPM chip, so anyone who copies your quick-unlock file can try"
        warn "PINs offline. A 6-digit PIN holds for days, not years. A password is safer."
    fi
    read -rsp "New $name: " secret </dev/tty
    echo >&2
    if [[ $method == pin ]]; then
        [[ $secret =~ ^[0-9]{6,32}$ ]] || die "A PIN is 6 to 32 digits."
    else
        ((${#secret} >= 8)) || die "A password needs at least 8 characters."
    fi
    read -rsp "Repeat $name: " again </dev/tty
    echo >&2
    [[ $secret == "$again" ]] || die "They don't match."
    info "Saving..."
    salt=$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')
    key=$(quick_key "$secret" "$salt") || die "Argon2 failed."
    (umask 077 && mkdir -p "$DATA_DIR")
    printf '%s' "$MASTER" | gpg_pass "$key" --yes --symmetric --cipher-algo AES256 --output "$QUICK.tmp" ||
        die "Could not save quick unlock."
    mv "$QUICK.tmp" "$QUICK"
    printf 'method=%s\nsalt=%s\nfailed=0\n' "$method" "$salt" >"$QUICK_META"
    chmod 600 "$QUICK" "$QUICK_META"
    ok "Quick unlock with a $name is on. Your master still works too."
}

read_master() {
    local raw
    read -rsp "${BOLD}Master:${RST} " raw </dev/tty
    echo >&2
    normalize_master "$raw"
    [[ -n $MASTER ]] || die "Empty master."
    ((${#MASTER} <= 127)) || die "Master is too long (max 127 bytes)."
}

# First run: the master is typed twice, must meet the minimum, and the vault
# is created right away.
create_vault() {
    local first strength raw choice
    echo "${BOLD}Welcome to NexoPass.${RST} No vault yet, so let's create one."
    echo "Your master is ${MIN_MASTER_WORDS}+ words: 3 is the minimum, 4 recommended, 6 the safest."
    echo "Need one? Run: ${CYAN}nexopass new-master${RST}"
    read_master
    first=$MASTER
    strength=$(master_strength) || die "Master is $strength."
    read -rsp "Repeat master: " raw </dev/tty
    echo >&2
    normalize_master "$raw"
    [[ $MASTER == "$first" ]] || die "Masters don't match."
    info "Master strength: ${BOLD}$strength${RST}"
    info "Check words: ${BOLD}$(check_words)${RST} (the phone app shows the same for the same master)"
    VAULT_KEY=$(derive_hex "$SALT_PREFIX:vault" 32) || die "Argon2 failed."
    R_SITE=() R_USER=() R_VER=() R_MODE=() R_SINCE=() R_UNTIL=()
    vault_save
    ok "Vault created."
    read -rp "Set up quick unlock so you don't type the master every time? [p]assword / P[I]N / [n]o: " choice </dev/tty
    case ${choice,,} in
    p*) quick_setup password ;;
    i*) quick_setup pin ;;
    esac
}

unlock() {
    if [[ ! -f $VAULT ]]; then
        create_vault
        cache_put
        return
    fi
    local from=typed
    if cache_get; then
        from=cache
    elif quick_unlock; then
        from=quick
    else
        read_master
    fi
    [[ $from == typed ]] && info "Unlocking..."
    VAULT_KEY=$(derive_hex "$SALT_PREFIX:vault" 32) || die "Argon2 failed."
    if ! vault_load; then
        [[ $from == cache ]] && cache_clear
        die "Cannot open the vault: wrong master?"
    fi
    cache_put
    UNLOCKED=1
}

ensure_unlocked() {
    ((${UNLOCKED:-0})) || unlock
    UNLOCKED=1
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
            sleep "$CFG_CLIP"
            [[ "$(wl-paste -n 2>/dev/null)" == "$pw" ]] && wl-copy --clear
        ) &>/dev/null &
        disown
        ok "${BOLD}$1${RST}: copied, clipboard clears in $CFG_CLIP s."
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

mode_label() {
    if [[ $1 == words ]]; then echo "words"; else echo "${1#chars} characters"; fi
}

# --- commands ---------------------------------------------------------------

need_site() {
    [[ -n $SITE_ARG ]] || die "Which site? e.g. nexopass $CMD discord"
    SITE=$(normalize_site "$SITE_ARG") || die "Not a valid site name: $SITE_ARG"
}

cmd_get() {
    need_site
    local i mode
    if resolve_typo; then
        i=$REPLY
        [[ -z $LENGTH || ${R_MODE[i]} == "chars$LENGTH" ]] ||
            info "Length is fixed per version; use 'rotate -n $LENGTH' to change it."
        [[ -z $VERSION_ARG || $VERSION_ARG == "${R_VER[i]}" ]] ||
            die "$(label "$SITE" "$USER_NAME" "${R_VER[i]}") is already saved; use rotate to move to a newer version."
    else
        mode=words
        ((CFG_LENGTH)) && mode="chars$CFG_LENGTH"
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

cmd_export() {
    local file=${SITE_ARG:-$HOME/nexopass-$(date +%F).pgp} pass
    [[ -e $file ]] && { ask_yes "$file exists. Overwrite?" || die "Cancelled."; }
    pass=$(derive_hex "$SALT_PREFIX:export" 32) || die "Argon2 failed."
    vault_text | gpg_pass "$pass" --yes --symmetric --cipher-algo AES256 --output "$file" || die "Export failed."
    ok "Exported ${#R_SITE[@]} entries to ${BOLD}$file${RST}"
    info "Encrypted: it opens only with the same master, here or in the phone app."
}

cmd_import() {
    [[ -n $SITE_ARG ]] || die "Which file? e.g. nexopass import ~/nexopass-2026-10-08.pgp"
    [[ -f $SITE_ARG ]] || die "No such file: $SITE_ARG"
    local pass plain before
    pass=$(derive_hex "$SALT_PREFIX:export" 32) || die "Argon2 failed."
    plain=$(gpg_pass "$pass" --decrypt "$SITE_ARG" 2>/dev/null) || die "Cannot open it: exported with a different master, or not a NexoPass export."
    I_SITE=() I_USER=() I_VER=() I_MODE=() I_SINCE=() I_UNTIL=()
    parse_records "$plain" I
    ((${#I_SITE[@]})) || die "The file has no sites in it."
    before=${#R_SITE[@]}
    merge_records
    vault_save
    ok "Imported. ${#I_SITE[@]} entries read, list went from $before to ${#R_SITE[@]} entries."
}

cmd_show_master() {
    quick_method >/dev/null || die "Quick unlock is off, so nothing is stored: your master is only in your head."
    warn "Make sure nobody is looking at your screen."
    quick_verify || die "Wrong PIN/password."
    echo "    ${BOLD}${MAGENTA}$QUICK_MASTER${RST}"
}

cmd_lock() {
    cache_clear
    ok "Locked. Next time you'll be asked again."
}

cmd_new_master() {
    local count=${SITE_ARG:-6}
    [[ $count =~ ^[1-9][0-9]?$ ]] || die "Number of words must be 3-99."
    ((count >= MIN_MASTER_WORDS)) || die "At least $MIN_MASTER_WORDS words (4 recommended, 6 safest)."
    local -a picked
    mapfile -t picked < <(printf '%s\n' "${WORDS[@]}" | shuf -n "$count" --random-source=/dev/urandom)
    echo "${BOLD}${MAGENTA}${picked[*]}${RST}"
}

# --- settings menu ----------------------------------------------------------

choose() { # choose <prompt> <options...>: REPLY gets the picked option
    local prompt=$1 ans
    shift
    read -rp "$prompt [$*]: " ans </dev/tty
    for opt in "$@"; do
        if [[ $ans == "$opt" ]]; then
            REPLY=$opt
            return 0
        fi
    done
    warn "Not changed."
    return 1
}

cmd_settings() {
    local ans method
    while true; do
        method=$(quick_method || echo off)
        echo
        echo "${BOLD}${MAGENTA}NexoPass settings${RST}"
        printf '  %s1)%s Quick unlock ............. %s\n' "$BOLD" "$RST" "$method"
        printf '  %s2)%s Stay unlocked for ........ %s\n' "$BOLD" "$RST" "$( ((CFG_CACHE)) && echo "$CFG_CACHE min" || echo "off (always ask)")"
        printf '  %s3)%s Clipboard clears after ... %s s\n' "$BOLD" "$RST" "$CFG_CLIP"
        printf '  %s4)%s New sites use ............ %s\n' "$BOLD" "$RST" "$( ((CFG_LENGTH)) && echo "$CFG_LENGTH characters" || echo "words")"
        printf '  %s5)%s Wrong attempts allowed ... %s\n' "$BOLD" "$RST" "$CFG_ATTEMPTS"
        printf '  %s6)%s Colors ................... %s\n' "$BOLD" "$RST" "$CFG_COLOR"
        printf '  %s7)%s Show master\n' "$BOLD" "$RST"
        printf '  %s8)%s Export vault\n' "$BOLD" "$RST"
        printf '  %s9)%s Import vault\n' "$BOLD" "$RST"
        printf '  %sl)%s Lock now\n' "$BOLD" "$RST"
        printf '  %sa)%s About\n' "$BOLD" "$RST"
        printf '  %sq)%s Done\n' "$BOLD" "$RST"
        read -rp "Choice: " ans </dev/tty || return 0
        (
            case ${ans,,} in
            1)
                choose "Quick unlock" password pin off || exit 0
                case $REPLY in
                off) quick_remove && ok "Quick unlock is off." ;;
                *) ensure_unlocked && quick_setup "$REPLY" ;;
                esac
                ;;
            2) choose "Stay unlocked for (minutes, 0 = always ask)" 0 1 5 15 30 60 && CFG_CACHE=$REPLY && save_config && { ((CFG_CACHE)) || cache_clear; } ;;
            3) choose "Clear clipboard after (seconds)" 10 15 30 60 120 && CFG_CLIP=$REPLY && save_config ;;
            4) choose "New sites use (0 = words, or a length 12-64)" 0 12 16 20 24 32 64 && CFG_LENGTH=$REPLY && save_config ;;
            5) choose "Wrong PIN/password attempts before quick unlock is removed" 3 5 10 && CFG_ATTEMPTS=$REPLY && save_config ;;
            6) choose "Colors" auto never && CFG_COLOR=$REPLY && save_config ;;
            7) cmd_show_master ;;
            8) ensure_unlocked && SITE_ARG="" && cmd_export ;;
            9)
                read -rp "File to import: " SITE_ARG </dev/tty
                SITE_ARG=${SITE_ARG/#\~/$HOME}
                ensure_unlocked && cmd_import
                ;;
            l) cmd_lock ;;
            a) about ;;
            q | "") exit 3 ;;
            *) warn "Unknown choice." ;;
            esac
        ) || {
            [[ $? == 3 ]] && return 0
            true
        }
        load_config
    done
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
    get | rotate | list | history | remove | export | import | settings | lock | show-master | new-master | about | help | "") ;;
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

# Commands that work without unlocking.
run_plain() {
    case $CMD in
    help) usage ;;
    about) about ;;
    new-master) cmd_new_master ;;
    lock) cmd_lock ;;
    settings) cmd_settings ;;
    show-master) cmd_show_master ;;
    *) return 1 ;;
    esac
}

run_command() {
    run_plain && return
    ensure_unlocked
    case $CMD in
    get) cmd_get ;;
    rotate) cmd_rotate ;;
    list) cmd_list ;;
    history) cmd_history ;;
    remove) cmd_remove ;;
    export) cmd_export ;;
    import) cmd_import ;;
    esac
}

banner() {
    echo "${MAGENTA}${BOLD}  ╭──────────────────╮${RST}"
    echo "${MAGENTA}${BOLD}  │${RST}  ${BOLD}N E X O P A S S${RST} ${MAGENTA}${BOLD}│${RST}"
    echo "${MAGENTA}${BOLD}  ╰──────────────────╯${RST}"
    echo "  ${DIM}made by Nexoniarz${RST}"
}

session() {
    ok "Unlocked. Commands: ${CYAN}<site>  get  rotate  list  history  remove  settings  export  import  help  quit${RST}"
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
        load_config
        setup_colors
        # A command may have changed the vault (or settings); reload it.
        vault_load || die "Cannot open the vault anymore."
    done
}

main() {
    load_words
    load_config
    setup_colors
    parse_args "$@"
    if [[ -z $CMD ]]; then
        banner
        ensure_unlocked
        session
    else
        run_command
    fi
}

main "$@"
