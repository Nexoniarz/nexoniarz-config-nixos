#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Nexoniarz
#
# NexoPass: passwords derived from a master, nothing stored in plain text.
#
# password = Argon2id(master, site + version + mode + user). The same input
# always gives the same password, so no password is ever saved anywhere.
#
# You can have several accounts, each with its own master and its own vault:
# the list of sites, their current version and an archive of old versions,
# encrypted (GnuPG, AES-256) with a key derived from that account's master.
# One app password (or PIN) unlocks NexoPass: it encrypts the keyring that
# holds every account's master, so a master is typed only to create or
# recover an account.
#
# Case never matters: masters, site names and account names are lowercased.
# A master is a list of words: any whitespace between them counts as one space.
#
# Must stay byte-for-byte compatible with the NexoPass Android app.

set -euo pipefail
export LC_ALL=C

NEXOPASS_VERSION="1.2.0"
WORDLIST="${NEXOPASS_WORDLIST:-$(dirname "$(readlink -f "$0")")/eff_large_wordlist.txt}"
WORDLIST_SHA256="addd35536511597a02fa0a9ff1e5284677b8883b83e986e43f15a3db996b903e"
BASE_DIR="${NEXOPASS_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/nexopass}"
ACCOUNTS_DIR="$BASE_DIR/accounts"
KEYRING="$BASE_DIR/keyring.gpg"
KEYRING_META="$BASE_DIR/keyring.meta"
CONFIG="${NEXOPASS_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/nexopass/config}"

# Changing any of these changes every password.
SALT_PREFIX="nexopass:v1"
ARGON_T=3
ARGON_M=16 # 2^16 KiB = 64 MiB
ARGON_P=1
SITE_BYTES=1024
WORD_COUNT=5 # "words" means 5; other counts are "words<N>" (5-15)
UPPER="ABCDEFGHJKLMNPQRSTUVWXYZ"
LOWER="abcdefghijkmnopqrstuvwxyz"
DIGITS="23456789"
SYMBOLS='!@#$%&*?-_+='
TWO_PART_TLDS="com.pl net.pl org.pl edu.pl gov.pl info.pl biz.pl co.uk org.uk ac.uk com.au co.jp com.br"

# The app password key is slower on purpose: a PIN has few combinations.
QUICK_T=4
QUICK_M=18 # 2^18 KiB = 256 MiB

MIN_MASTER_WORDS=3
MIN_MASTER_BYTES=12
SEP=$'\x1f'
VAULT_HEADER="# nexopass vault v1"

declare -A KR=() # account name -> master, while unlocked
QKEY=""          # key that encrypts the keyring, while unlocked
UNLOCKED=0

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
${BOLD}${MAGENTA}NexoPass${RST} $NEXOPASS_VERSION - passwords derived from a master, nothing stored in plain text.

${BOLD}Usage:${RST} nexopass [command] [site] [options]

${BOLD}Passwords:${RST}
  ${CYAN}get${RST} <site>          Show the password for a site (adds the site on first use)
  ${CYAN}rotate${RST} <site>       After a breach: switch to the next version, archive the old one
  ${CYAN}list${RST}                List your sites with their current version
  ${CYAN}history${RST} <site>      Show all versions of a site, old ones included
  ${CYAN}remove${RST} <site>       Remove a site and its history from the list
                      (with -v N: remove only archived version N)

${BOLD}Accounts${RST} (each has its own master and site list; one app password for all):
  ${CYAN}accounts${RST}                     List your accounts
  ${CYAN}account new${RST} <name>           Add an account: a new master, or one you use on the phone
  ${CYAN}account use${RST} <name>           Switch the default account
  ${CYAN}account rename${RST} <old> <new>   Rename an account
  ${CYAN}account detach${RST} [name]        Remove an account from this computer
                               (app password, its master and "yes"; offers a backup)

${BOLD}Security and data:${RST}
  ${CYAN}settings${RST}            App password, stay unlocked, clipboard, defaults...
  ${CYAN}passwd${RST}              Change the app password/PIN
  ${CYAN}show-master${RST}         Show the account's master (asks for the app password)
  ${CYAN}export${RST} [file]       Encrypted copy of the account's site list (opens on the phone too)
  ${CYAN}import${RST} <file>       Merge an export into the account's site list
  ${CYAN}lock${RST}                Lock now
  ${CYAN}new-master${RST} [N]      Generate a random master of N words (default 6)
  ${CYAN}about${RST}               Version, author, license

  nexopass <site>   Same as: nexopass get <site>
  nexopass          Interactive session: unlock once, then type commands

${BOLD}Options:${RST}
  -A, --account NAME Use this account for one command
  -u, --user NAME    Login name, for several logins on one site
  -w, --words N      Password of N words (5-15); when adding or rotating
  -n, --length N     Random characters (12-64) instead of words, for sites
                     with a length limit; when adding or rotating
  -v, --version N    New site: start at version N. remove: archived version N
  -c, --copy         Copy to clipboard instead of printing
  -s, --show         With list/history: also show the passwords
  -h, --help         Show this help

Case never matters. A master is ${MIN_MASTER_WORDS}+ words: 3 the minimum, 4 recommended, 6 the safest.
EOF
}

about() {
    cat <<EOF
${BOLD}${MAGENTA}NexoPass${RST} $NEXOPASS_VERSION
Passwords derived from a master, nothing stored in plain text.
Compatible with the NexoPass Android app.

Made by ${BOLD}Nexoniarz${RST}
License: Apache License 2.0
EOF
}

# --- settings ---------------------------------------------------------------
# Plain key=value file, nothing secret in it. Unknown or invalid lines are ignored.

load_config() {
    CFG_CACHE=5 CFG_CLIP=30 CFG_MODE=words CFG_COLOR=auto CFG_ATTEMPTS=5 CFG_ACCOUNT=main
    [[ -f $CONFIG ]] || return 0
    local k v
    while IFS='=' read -r k v; do
        case $k in
        cache_minutes) [[ $v =~ ^(0|1|5|15|30|60)$ ]] && CFG_CACHE=$v ;;
        clip_seconds) [[ $v =~ ^(10|15|30|60|120)$ ]] && CFG_CLIP=$v ;;
        default_mode) valid_mode "$v" && CFG_MODE=$v ;;
        color) [[ $v =~ ^(auto|never)$ ]] && CFG_COLOR=$v ;;
        max_attempts) [[ $v =~ ^(3|5|10)$ ]] && CFG_ATTEMPTS=$v ;;
        current_account) account_name_ok "$v" && CFG_ACCOUNT=$v ;;
        esac
    done <"$CONFIG"
    return 0
}

save_config() {
    mkdir -p "$(dirname "$CONFIG")"
    printf '%s\n' "# NexoPass settings, change with: nexopass settings" \
        "cache_minutes=$CFG_CACHE" "clip_seconds=$CFG_CLIP" "default_mode=$CFG_MODE" \
        "color=$CFG_COLOR" "max_attempts=$CFG_ATTEMPTS" "current_account=$CFG_ACCOUNT" >"$CONFIG.tmp"
    mv "$CONFIG.tmp" "$CONFIG"
}

# --- accounts ---------------------------------------------------------------
# Every account has its own folder with vault.gpg (its site list).

account_name_ok() { [[ $1 =~ ^[a-z0-9][a-z0-9_-]{0,31}$ ]]; }

select_account() {
    ACCOUNT=$1
    DATA_DIR="$ACCOUNTS_DIR/$1"
    VAULT="$DATA_DIR/vault.gpg"
    UNLOCKED=0
}

account_exists() { [[ -f $ACCOUNTS_DIR/$1/vault.gpg ]]; }

account_names() {
    local d
    for d in "$ACCOUNTS_DIR"/*/; do
        [[ -f $d/vault.gpg ]] && basename "$d"
    done
    return 0
}

# Older versions kept one vault directly in the data folder: it becomes the
# account "main". Its master is asked once, then the app password is set.
migrate_layout() {
    [[ -f $BASE_DIR/vault.gpg && ! -e $ACCOUNTS_DIR/main ]] || return 0
    (umask 077 && mkdir -p "$ACCOUNTS_DIR/main")
    mv "$BASE_DIR/vault.gpg" "$ACCOUNTS_DIR/main/vault.gpg"
    [[ -f $BASE_DIR/vault.gpg.bak ]] && mv "$BASE_DIR/vault.gpg.bak" "$ACCOUNTS_DIR/main/vault.gpg.bak"
    rm -f "$BASE_DIR/quick.gpg" "$BASE_DIR/quick.meta"
    MIGRATED=1
    return 0
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

valid_mode() {
    [[ $1 == words || $1 =~ ^words([6-9]|1[0-5])$ || $1 =~ ^chars(1[2-9]|[2-5][0-9]|6[0-4])$ ]]
}

# words_mode <n>: 5 stays "words" so older entries keep their passwords.
words_mode() {
    if (($1 == WORD_COUNT)); then echo words; else echo "words$1"; fi
}

# Mode for a new site or version: -w / -n win, else <fallback>.
pick_mode() {
    if [[ -n $WORDS_ARG ]]; then
        words_mode "$WORDS_ARG"
    elif [[ -n $LENGTH ]]; then
        echo "chars$LENGTH"
    else
        echo "$1"
    fi
}

# make_password <site> <user> <version> <mode>: result in PASSWORD.
make_password() {
    local site=$1 user=$2 version=$3 mode=$4 hex i j t
    hex=$(derive_hex "$SALT_PREFIX:site:$site:$version:$mode:$user" "$SITE_BYTES") || die "Argon2 failed."
    load_ints "$hex"
    PASSWORD=""
    if [[ $mode == words* ]]; then
        local count=${mode#words}
        count=${count:-$WORD_COUNT}
        for ((i = 0; i < count; i++)); do
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

# --- keyring and app password -----------------------------------------------
# keyring.gpg: one line per account, "name<0x1F>master", encrypted with QKEY =
# Argon2id(app password, random salt). keyring.meta: method, salt, failed tries.

keyring_method() {
    [[ -f $KEYRING && -f $KEYRING_META ]] || return 1
    sed -n 's/^method=//p' "$KEYRING_META"
}

keyring_meta_get() { sed -n "s/^$1=//p" "$KEYRING_META"; }

keyring_set_failed() {
    printf 'method=%s\nsalt=%s\nfailed=%s\n' "$(keyring_meta_get method)" "$(keyring_meta_get salt)" "$1" >"$KEYRING_META"
}

app_name() {
    if [[ $(keyring_method) == pin ]]; then echo PIN; else echo "app password"; fi
}

keyring_parse() {
    KR=()
    local line
    while IFS= read -r line; do
        [[ $line == *"$SEP"* ]] || continue
        KR[${line%%"$SEP"*}]=${line#*"$SEP"}
    done <<<"$1"
}

keyring_text() {
    local n
    for n in "${!KR[@]}"; do
        printf '%s\n' "$n$SEP${KR[$n]}"
    done
}

keyring_save() {
    [[ -n $QKEY ]] || die "Internal error: keyring key missing."
    (umask 077 && mkdir -p "$BASE_DIR")
    keyring_text | gpg_pass "$QKEY" --yes --symmetric --cipher-algo AES256 --output "$KEYRING.tmp" ||
        die "Could not save the keyring."
    mv "$KEYRING.tmp" "$KEYRING"
    chmod 600 "$KEYRING"
}

# Re-reads the keyring with the key we already have (after another command changed it).
keyring_reload() {
    [[ -n $QKEY && -f $KEYRING ]] || return 1
    local text
    text=$(gpg_pass "$QKEY" --decrypt "$KEYRING" 2>/dev/null) || return 1
    keyring_parse "$text"
}

app_key() {
    printf '%s' "$1" | argon2 "$2" -id -t "$QUICK_T" -m "$QUICK_M" -p 1 -l 32 -r
}

# app_try <secret>: 0 = unlocked, 1 = wrong, 2 = too many wrong (keyring removed).
app_try() {
    local key text failed left
    key=$(app_key "$1" "$(keyring_meta_get salt)") || die "Argon2 failed."
    if text=$(gpg_pass "$key" --decrypt "$KEYRING" 2>/dev/null); then
        QKEY=$key
        keyring_parse "$text"
        keyring_set_failed 0
        return 0
    fi
    failed=$(($(keyring_meta_get failed) + 1))
    left=$((CFG_ATTEMPTS - failed))
    if ((left <= 0)); then
        rm -f "$KEYRING" "$KEYRING_META"
        warn "Too many wrong attempts: the app password was removed. Recover with your master."
        return 2
    fi
    keyring_set_failed "$failed"
    warn "Wrong $(app_name). $left attempt(s) left."
    return 1
}

# Asks for the app password until it works. Fails on empty input (recover
# with the master) or when the attempts run out.
app_unlock() {
    local secret rc name
    name=$(app_name)
    while true; do
        read -rsp "${BOLD}${name^}${RST} ${DIM}(forgot it? press Enter to recover with your master)${RST}: " secret </dev/tty
        echo >&2
        [[ -n $secret ]] || return 1
        info "Unlocking..."
        rc=0
        app_try "$secret" || rc=$?
        case $rc in
        0) return 0 ;;
        2) return 1 ;;
        esac
    done
}

# Asks once for the current app password: for passwd, show-master, detach.
app_confirm() {
    local secret rc=0
    keyring_method >/dev/null || die "No app password is set yet."
    read -rsp "${BOLD}Current $(app_name)${RST}: " secret </dev/tty
    echo >&2
    app_try "$secret" || rc=$?
    ((rc == 0)) || die "Not confirmed."
}

# app_password_setup <password|pin>: new secret twice, new salt, keyring re-saved.
app_password_setup() {
    local method=$1 name secret again salt
    name=PIN
    [[ $method == password ]] && name=password
    if [[ $method == pin ]]; then
        warn "This PC has no TPM chip, so anyone who copies your keyring file can try"
        warn "PINs offline. A 6-digit PIN holds for days, not years. A password is safer."
    fi
    while true; do
        read -rsp "New $name: " secret </dev/tty
        echo >&2
        if [[ $method == pin && ! $secret =~ ^[0-9]{6,32}$ ]]; then
            warn "A PIN is 6 to 32 digits."
            continue
        elif [[ $method == password ]] && ((${#secret} < 8)); then
            warn "Use at least 8 characters."
            continue
        fi
        read -rsp "Repeat $name: " again </dev/tty
        echo >&2
        [[ $secret == "$again" ]] && break
        warn "They don't match, try again."
    done
    info "Saving..."
    salt=$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')
    QKEY=$(app_key "$secret" "$salt") || die "Argon2 failed."
    (umask 077 && mkdir -p "$BASE_DIR")
    printf 'method=%s\nsalt=%s\nfailed=0\n' "$method" "$salt" >"$KEYRING_META"
    chmod 600 "$KEYRING_META"
    keyring_save
    ok "From now on you unlock NexoPass with this $name."
}

choose_app_password() {
    local choice
    read -rp "Unlock NexoPass with a [p]assword (recommended) or a P[I]N? [p] " choice </dev/tty
    case ${choice,,} in
    i*) app_password_setup pin ;;
    *) app_password_setup password ;;
    esac
}

# --- "stay unlocked" --------------------------------------------------------
# The keyring key and the keyring stay in the kernel keyring for a few minutes.

cache_name() {
    local h
    h=$(printf '%s' "$BASE_DIR" | sha256sum)
    printf 'nexopass:%s' "${h:0:16}"
}

cache_get() {
    ((CFG_CACHE > 0)) || return 1
    local id data
    id=$(keyctl search @u user "$(cache_name)" 2>/dev/null) || return 1
    data=$(keyctl pipe "$id" 2>/dev/null) || return 1
    QKEY=${data%%$'\n'*}
    keyring_parse "${data#*$'\n'}"
    keyctl timeout "$id" $((CFG_CACHE * 60)) &>/dev/null || true
}

cache_put() {
    ((CFG_CACHE > 0)) && [[ -n $QKEY ]] || return 0
    local id
    id=$({
        printf '%s\n' "$QKEY"
        keyring_text
    } | keyctl padd user "$(cache_name)" @u) || return 0
    keyctl timeout "$id" $((CFG_CACHE * 60)) &>/dev/null || true
}

cache_clear() {
    local id
    id=$(keyctl search @u user "$(cache_name)" 2>/dev/null) || return 0
    keyctl unlink "$id" @u &>/dev/null || true
}

# --- unlocking --------------------------------------------------------------

read_master() {
    local raw
    read -rsp "${BOLD}${1:-Master}:${RST} " raw </dev/tty
    echo >&2
    normalize_master "$raw"
    [[ -n $MASTER ]] || die "Empty master."
    ((${#MASTER} <= 127)) || die "Master is too long (max 127 bytes)."
}

# Unlocks the app (keyring). Leaves KR empty when recovering with a master.
unlock_app() {
    [[ -n $QKEY ]] && return 0
    cache_get && return 0
    if keyring_method >/dev/null; then
        app_unlock && return 0
        RECOVERING=1
    fi
    return 0
}

# create_account <name>: master twice, vault created, master added to the keyring.
create_account() {
    local name=$1 first strength raw
    echo "Type the master for account ${BOLD}$name${RST}: a new one, or the one you already use"
    echo "on your phone. ${MIN_MASTER_WORDS}+ words: 3 the minimum, 4 recommended, 6 the safest."
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
    select_account "$name"
    VAULT_KEY=$(derive_hex "$SALT_PREFIX:vault" 32) || die "Argon2 failed."
    R_SITE=() R_USER=() R_VER=() R_MODE=() R_SINCE=() R_UNTIL=()
    vault_save
    KR[$name]=$MASTER
    ok "Account '$name' created. Keep its master in your head: it's the way to recover."
    if [[ -n $QKEY ]]; then
        keyring_save
    else
        choose_app_password
    fi
    UNLOCKED=1
}

first_run() {
    local name
    echo "${BOLD}Welcome to NexoPass.${RST} Let's create your first account."
    read -rp "Account name [main]: " name </dev/tty
    name=${name:-main}
    name=${name,,}
    account_name_ok "$name" || die "Use lowercase letters, digits, - or _."
    create_account "$name"
    CFG_ACCOUNT=$name
    save_config
}

# Opens the selected account: its master comes from the keyring, or is typed
# once (new since an update, skipped during recovery, or recovering).
open_account() {
    if ! account_exists "$ACCOUNT"; then
        if [[ -z $(account_names) && -z ${ACCOUNT_OPT:-} ]]; then
            first_run
            cache_put
            return
        fi
        die "No account '$ACCOUNT'. See: nexopass accounts"
    fi
    local typed=0
    MASTER=${KR[$ACCOUNT]:-}
    if [[ -z $MASTER ]]; then
        typed=1
        if ((${MIGRATED:-0})); then
            info "NexoPass now has accounts and an app password. Your vault is account 'main':"
            info "enter its master once, then choose the app password."
        elif ((${RECOVERING:-0})); then
            info "Recovering: enter the master of account '$ACCOUNT', then set a new app password."
            info "Your other accounts will ask for their master once, the next time you use them."
        elif [[ -n $QKEY ]]; then
            info "Account '$ACCOUNT' isn't in the keyring yet: enter its master once."
        else
            info "Enter the master of account '$ACCOUNT' once, then choose an app password."
        fi
        read_master "Master of '$ACCOUNT'"
        info "Unlocking..."
    fi
    VAULT_KEY=$(derive_hex "$SALT_PREFIX:vault" 32) || die "Argon2 failed."
    if ! vault_load; then
        ((typed)) && die "Cannot open account '$ACCOUNT': wrong master?"
        die "The saved master no longer opens '$ACCOUNT'. Detach and re-add it."
    fi
    if ((typed)); then
        KR[$ACCOUNT]=$MASTER
        if [[ -n $QKEY ]]; then keyring_save; else choose_app_password; fi
        RECOVERING=0
    fi
    cache_put
    UNLOCKED=1
}

ensure_unlocked() {
    ((UNLOCKED)) && return 0
    unlock_app
    open_account
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
    case $1 in
    words) echo "5 words" ;;
    words*) echo "${1#words} words" ;;
    *) echo "${1#chars} characters" ;;
    esac
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
        [[ -z $LENGTH$WORDS_ARG || ${R_MODE[i]} == "$(pick_mode "${R_MODE[i]}")" ]] ||
            info "Length is fixed per version; use rotate with -w/-n to change it."
        [[ -z $VERSION_ARG || $VERSION_ARG == "${R_VER[i]}" ]] ||
            die "$(label "$SITE" "$USER_NAME" "${R_VER[i]}") is already saved; use rotate to move to a newer version."
    else
        mode=$(pick_mode "$CFG_MODE")
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
    mode=$(pick_mode "${R_MODE[i]}")
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
    local cur=$REPLY only=""
    if [[ -n $WORDS_ARG ]]; then
        [[ $WORDS_ARG =~ ^([5-9]|1[0-5])$ ]] || die "Words must be 5-15."
        [[ -z $LENGTH ]] || die "Pick either -w (words) or -n (characters)."
    fi
    if [[ -n $VERSION_ARG ]]; then
        [[ $VERSION_ARG != "${R_VER[cur]}" ]] || die "v$VERSION_ARG is the current version; to drop it, rotate first or remove the whole site."
        local i found=0
        for i in "${!R_SITE[@]}"; do
            [[ ${R_SITE[i]} == "$SITE" && ${R_USER[i]} == "$USER_NAME" && ${R_VER[i]} == "$VERSION_ARG" ]] && found=1
        done
        ((found)) || die "$(label "$SITE" "$USER_NAME") has no archived v$VERSION_ARG."
        only=$VERSION_ARG
        ask_yes "Remove archived $(label "$SITE" "$USER_NAME" "$only") from the list?" || die "Cancelled."
    else
        ask_yes "Remove $(label "$SITE" "$USER_NAME") and its whole history from the list?" || die "Cancelled."
    fi
    local i
    local -a s=() u=() v=() m=() a=() b=()
    for i in "${!R_SITE[@]}"; do
        [[ ${R_SITE[i]} == "$SITE" && ${R_USER[i]} == "$USER_NAME" && (-z $only || ${R_VER[i]} == "$only") ]] && continue
        s+=("${R_SITE[i]}") u+=("${R_USER[i]}") v+=("${R_VER[i]}") m+=("${R_MODE[i]}") a+=("${R_SINCE[i]}") b+=("${R_UNTIL[i]}")
    done
    R_SITE=("${s[@]}") R_USER=("${u[@]}") R_VER=("${v[@]}") R_MODE=("${m[@]}") R_SINCE=("${a[@]}") R_UNTIL=("${b[@]}")
    vault_save
    ok "Removed."
}

cmd_export() {
    local file=${SITE_ARG:-$HOME/nexopass-$ACCOUNT-$(date +%F).pgp} pass
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
    account_exists "$ACCOUNT" || die "No account '$ACCOUNT'."
    keyring_method >/dev/null || die "No app password yet: unlock once to set it up."
    warn "Make sure nobody is looking at your screen."
    app_confirm
    [[ -n ${KR[$ACCOUNT]:-} ]] || die "The master of '$ACCOUNT' isn't in the keyring yet: open the account once."
    echo "    ${BOLD}${MAGENTA}${KR[$ACCOUNT]}${RST}"
}

cmd_passwd() {
    if keyring_method >/dev/null; then
        app_confirm
    else
        ensure_unlocked
        return
    fi
    choose_app_password
    cache_clear
    cache_put
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

# --- accounts commands ------------------------------------------------------

cmd_accounts() {
    local n mark
    local -a names
    mapfile -t names < <(account_names)
    ((${#names[@]})) || {
        info "No accounts yet. Run nexopass to create one."
        return
    }
    printf '%s  %-24s %s%s\n' "$DIM" ACCOUNT "CHANGED" "$RST"
    for n in "${names[@]}"; do
        mark=" "
        [[ $n == "$CFG_ACCOUNT" ]] && mark="${GREEN}*${RST}"
        printf '%s %s%-24s%s %s\n' "$mark" "$BOLD" "$n" "$RST" "$(date -r "$ACCOUNTS_DIR/$n/vault.gpg" +%F)"
    done
}

cmd_account() {
    local sub=${SITE_ARG,,} name=${ARG2,,} new=${ARG3,,}
    case $sub in
    "" | list) cmd_accounts ;;
    new)
        account_name_ok "$name" || die "Give it a name: lowercase letters, digits, - or _ (e.g. nexopass account new work)."
        account_exists "$name" && die "There is already an account called '$name'."
        unlock_app
        ((${RECOVERING:-0})) && die "Unlock with your app password first (or recover an existing account)."
        create_account "$name"
        cache_clear
        cache_put
        if [[ $CFG_ACCOUNT != "$name" ]] && ask_yes "Switch to '$name' now?"; then
            CFG_ACCOUNT=$name
            save_config
        fi
        ;;
    use)
        account_exists "$name" || die "No account '$name'. See: nexopass accounts"
        CFG_ACCOUNT=$name
        save_config
        ok "Now using account ${BOLD}$name${RST}."
        ;;
    rename)
        account_exists "$name" || die "No account '$name'."
        account_name_ok "$new" || die "New name: lowercase letters, digits, - or _."
        [[ -e $ACCOUNTS_DIR/$new ]] && die "There is already an account called '$new'."
        unlock_app
        mv "$ACCOUNTS_DIR/$name" "$ACCOUNTS_DIR/$new"
        if [[ -n $QKEY ]]; then
            if [[ -n ${KR[$name]:-} ]]; then
                KR[$new]=${KR[$name]}
                unset 'KR[$name]'
            fi
            keyring_save
            cache_clear
            cache_put
        fi
        if [[ $CFG_ACCOUNT == "$name" ]]; then
            CFG_ACCOUNT=$new
            save_config
        fi
        ok "Renamed '$name' to '$new'."
        ;;
    detach) cmd_detach "${name:-$ACCOUNT}" ;;
    *) die "Unknown: account $sub. Use: accounts, account new|use|rename|detach" ;;
    esac
}

# Removes an account from this computer: app password, its master and "yes".
cmd_detach() {
    local name=$1 ans rest=""
    account_exists "$name" || die "No account '$name'."
    select_account "$name"
    echo "${RED}${BOLD}Detach account '$name'${RST}"
    echo "This removes the account from this computer: its site list with the archive and its"
    echo "saved master. Your logins keep their passwords and the master can recreate them,"
    echo "but the site list is gone unless you have an export (or it's still on your phone)."
    if ask_yes "Export a backup of '$name' first?"; then
        ensure_unlocked
        SITE_ARG=""
        cmd_export
    fi
    keyring_method >/dev/null && app_confirm
    read_master "Master of '$name'"
    info "Checking the master..."
    VAULT_KEY=$(derive_hex "$SALT_PREFIX:vault" 32) || die "Argon2 failed."
    vault_load || die "Wrong master. Nothing was removed."
    read -rp "Type ${BOLD}yes${RST} to detach '$name': " ans </dev/tty
    [[ $ans == yes ]] || die "Cancelled. Nothing was removed."
    rm -rf "${ACCOUNTS_DIR:?}/$name"
    if [[ -n $QKEY ]]; then
        unset 'KR[$name]'
        keyring_save
    fi
    cache_clear
    if [[ $CFG_ACCOUNT == "$name" ]]; then
        rest=$(account_names | head -1)
        CFG_ACCOUNT=${rest:-main}
        save_config
    fi
    ok "Account '$name' detached."
    [[ -n $rest ]] && info "Now using account '$rest'."
    return 0
}

# --- settings menu ----------------------------------------------------------

choose() { # choose <prompt> <options...>: REPLY gets the picked option
    local prompt=$1 ans opt
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
        method=$(keyring_method || echo "not set")
        echo
        echo "${BOLD}${MAGENTA}NexoPass settings${RST}  ${DIM}account: $ACCOUNT${RST}"
        printf '  %s1)%s Change app password ...... %s\n' "$BOLD" "$RST" "$method"
        printf '  %s2)%s Stay unlocked for ........ %s\n' "$BOLD" "$RST" "$( ((CFG_CACHE)) && echo "$CFG_CACHE min" || echo "off (always ask)")"
        printf '  %s3)%s Clipboard clears after ... %s s\n' "$BOLD" "$RST" "$CFG_CLIP"
        printf '  %s4)%s New sites use ............ %s\n' "$BOLD" "$RST" "$(mode_label "$CFG_MODE")"
        printf '  %s5)%s Wrong attempts allowed ... %s\n' "$BOLD" "$RST" "$CFG_ATTEMPTS"
        printf '  %s6)%s Colors ................... %s\n' "$BOLD" "$RST" "$CFG_COLOR"
        printf '  %s7)%s Show master\n' "$BOLD" "$RST"
        printf '  %s8)%s Export site list\n' "$BOLD" "$RST"
        printf '  %s9)%s Import site list\n' "$BOLD" "$RST"
        printf '  %sa)%s Accounts\n' "$BOLD" "$RST"
        printf '  %sd)%s %sDetach this account%s\n' "$BOLD" "$RST" "$RED" "$RST"
        printf '  %sl)%s Lock now\n' "$BOLD" "$RST"
        printf '  %si)%s About\n' "$BOLD" "$RST"
        printf '  %sq)%s Done\n' "$BOLD" "$RST"
        read -rp "Choice: " ans </dev/tty || return 0
        (
            case ${ans,,} in
            1) cmd_passwd ;;
            2) choose "Stay unlocked for (minutes, 0 = always ask)" 0 1 5 15 30 60 && CFG_CACHE=$REPLY && save_config && { ((CFG_CACHE)) || cache_clear; } ;;
            3) choose "Clear clipboard after (seconds)" 10 15 30 60 120 && CFG_CLIP=$REPLY && save_config ;;
            4)
                read -rp "New sites use: words (5-15) or c + characters (c12-c64), e.g. 6 or c20: " ans </dev/tty
                if [[ $ans =~ ^([5-9]|1[0-5])$ ]]; then
                    CFG_MODE=$(words_mode "$ans")
                elif [[ $ans =~ ^c(1[2-9]|[2-5][0-9]|6[0-4])$ ]]; then
                    CFG_MODE="chars${ans#c}"
                else
                    warn "Not changed."
                    exit 0
                fi
                save_config
                ;;
            5) choose "Wrong app password attempts before it is removed" 3 5 10 && CFG_ATTEMPTS=$REPLY && save_config ;;
            6) choose "Colors" auto never && CFG_COLOR=$REPLY && save_config ;;
            7) cmd_show_master ;;
            8) ensure_unlocked && SITE_ARG="" && cmd_export ;;
            9)
                read -rp "File to import: " SITE_ARG </dev/tty
                SITE_ARG=${SITE_ARG/#\~/$HOME}
                ensure_unlocked && cmd_import
                ;;
            a)
                cmd_accounts
                echo "Manage them with: nexopass account new|use|rename|detach <name>"
                ;;
            d) cmd_detach "$ACCOUNT" && exit 3 ;;
            l) cmd_lock ;;
            i) about ;;
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
    CMD="" SITE_ARG="" ARG2="" ARG3="" USER_NAME="" LENGTH="" WORDS_ARG="" VERSION_ARG="" ACCOUNT_OPT="" COPY=0 SHOW=0
    while (($#)); do
        case $1 in
        -u | --user | -n | --length | -w | --words | -v | --version | -A | --account)
            (($# >= 2)) || die "$1 needs a value."
            case $1 in
            -u | --user) USER_NAME=$(normalize_user "$2") || die "Invalid login name." ;;
            -n | --length) LENGTH=$2 ;;
            -w | --words) WORDS_ARG=$2 ;;
            -v | --version) VERSION_ARG=$2 ;;
            -A | --account)
                ACCOUNT_OPT=${2,,}
                account_name_ok "$ACCOUNT_OPT" || die "Invalid account name: $2"
                ;;
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
            elif [[ $CMD == account && -z $ARG2 ]]; then
                ARG2=$1
            elif [[ $CMD == account && -z $ARG3 ]]; then
                ARG3=$1
            else
                die "Unexpected argument: $1"
            fi
            shift
            ;;
        esac
    done
    case $CMD in
    get | rotate | list | history | remove | export | import | settings | passwd | lock | show-master | \
        account | accounts | new-master | about | help | "") ;;
    *) SITE_ARG=$CMD CMD=get ;;
    esac
    if [[ -n $LENGTH ]]; then
        [[ $LENGTH =~ ^[1-6][0-9]$ ]] || die "Length must be 12-64."
        ((LENGTH >= 12 && LENGTH <= 64)) || die "Length must be 12-64."
    fi
    if [[ -n $WORDS_ARG ]]; then
        [[ $WORDS_ARG =~ ^([5-9]|1[0-5])$ ]] || die "Words must be 5-15."
        [[ -z $LENGTH ]] || die "Pick either -w (words) or -n (characters)."
    fi
    if [[ -n $VERSION_ARG ]]; then
        [[ $VERSION_ARG =~ ^[1-9][0-9]{0,3}$ ]] || die "Version must be a number from 1."
    fi
    select_account "${ACCOUNT_OPT:-$CFG_ACCOUNT}"
}

# Commands that do their own unlocking (or need none).
run_plain() {
    case $CMD in
    help) usage ;;
    about) about ;;
    new-master) cmd_new_master ;;
    lock) cmd_lock ;;
    settings) cmd_settings ;;
    passwd) cmd_passwd ;;
    account) cmd_account ;;
    accounts) cmd_accounts ;;
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
    ok "Unlocked. Commands: ${CYAN}<site>  get  rotate  list  history  remove  accounts  account  settings  help  quit${RST}"
    local line
    local -a words
    while IFS= read -rep "${MAGENTA}nexopass${RST}${DIM}[$ACCOUNT]${RST}${MAGENTA}›${RST} " line; do
        read -ra words <<<"$line"
        ((${#words[@]})) || continue
        case ${words[0],,} in
        quit | exit | q) break ;;
        esac
        (
            parse_args "${words[@]}"
            [[ -n $CMD ]] && run_command
        ) || true
        # A command may have changed settings, accounts or the keyring.
        load_config
        setup_colors
        keyring_reload || QKEY=""
        if [[ $CFG_ACCOUNT != "$ACCOUNT" ]] || ! account_exists "$ACCOUNT"; then
            select_account "$CFG_ACCOUNT"
            info "Account: ${BOLD}$ACCOUNT${RST}"
        fi
        UNLOCKED=0
        ensure_unlocked
    done
}

main() {
    load_words
    load_config
    setup_colors
    migrate_layout
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
