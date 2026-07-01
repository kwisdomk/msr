#!/usr/bin/env bash
# =============================================================================
# Mr. Roboto v2.1 — Native Linux launcher
# No PowerShell required. Requires: bash, curl or wget, tar.
#
# CHANGELOG (v2.1.0) — fixes for PR review blockers:
#   1. Headless mode no longer prompts for save path, playlist choice, or
#      cookie retry — it now runs fully unattended.
#   2. Cookie escalation only fires on real auth-style failures (pattern
#      matched against yt-dlp's actual output), not on invalid/unsupported
#      URLs, truncated IDs, or generic network errors.
#   3. Ctrl+C is trapped globally. State is preserved (not cleared) and the
#      script exits cleanly instead of falling into the cookie-retry prompt.
#   4. save_history() now passes data through argv into a quoted heredoc
#      instead of interpolating shell variables into an unquoted heredoc —
#      closes a Python-injection hole: a title/URL containing `"""` broke
#      out of the generated Python string literal and ran as live code
#      (verified exploitable: a crafted URL triggered arbitrary command
#      execution via __import__("os").system(...)).
#   5. Fixed a duplicate get_cookie_browser() call that ran the function
#      once uncaptured (leaking the raw browser name to the terminal) and
#      once captured. Also added Snap/Flatpak-aware Brave profile
#      resolution so --cookies-from-browser works on Snap installs.
# =============================================================================
set -euo pipefail

VERSION="2.1.0-beta.1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Architecture ──────────────────────────────────────────────────────────────
case "$(uname -m)" in
    x86_64)  ARCH="x64";   YTDLP_SUFFIX="linux";         FFMPEG_SUFFIX="linux64"    ;;
    aarch64) ARCH="arm64"; YTDLP_SUFFIX="linux_aarch64";  FFMPEG_SUFFIX="linuxarm64" ;;
    armv7l)
        printf '%s\n' "armv7l is not currently supported because bundled FFmpeg downloads are only available for x86_64 and aarch64." >&2
        exit 1
        ;;
    *)       ARCH="x64";   YTDLP_SUFFIX="linux";          FFMPEG_SUFFIX="linux64"    ;;
esac

BIN_DIR="$SCRIPT_DIR/bin/$ARCH"
LOG_DIR="$SCRIPT_DIR/logs"
STATE_DIR="$SCRIPT_DIR/state"
CACHE_DIR="$SCRIPT_DIR/cache"
STATE_FILE="$STATE_DIR/session.json"
HISTORY_FILE="$STATE_DIR/download_history.json"

YTDLP_URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_${YTDLP_SUFFIX}"
FFMPEG_URL="https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-${FFMPEG_SUFFIX}-gpl.tar.xz"

# ── Colors (disabled when not writing to a terminal) ─────────────────────────
if [[ -t 1 ]]; then
    R=$'\033[0;31m' G=$'\033[0;32m' Y=$'\033[1;33m'
    C=$'\033[0;36m' W=$'\033[1;37m' D=$'\033[2;37m' N=$'\033[0m'
else
    R='' G='' Y='' C='' W='' D='' N=''
fi

# ── Script-level state ────────────────────────────────────────────────────────
LOG_FILE=""
DOWNLOAD_DIR=""
GPU_NAME="Unknown"
ENCODER="libx264"
USE_COOKIES="false"
HEADLESS_MODE=false

# ── Interrupt handling (fixes blocker #3) ─────────────────────────────────────
# Trapped globally so Ctrl+C is caught no matter where the script is —
# mid-download, mid-prompt, mid-dependency-install. We deliberately do NOT
# call clear_state here: the whole point is to preserve resume state.
on_sigint() {
    printf '\n\n  %s\n' "${Y}[!] Interrupted by user (Ctrl+C).${N}"
    printf '  %s\n\n' "${D}Any in-progress download state has been preserved — run again to resume.${N}"
    log WARN "Script interrupted via SIGINT; state preserved for resume."
    exit 130
}
trap on_sigint INT

# =============================================================================
# Logging
# =============================================================================

log() {
    [[ -n "$LOG_FILE" ]] || return 0
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" >> "$LOG_FILE"
}

init_logging() {
    local ts; ts=$(date '+%Y%m%d_%H%M%S')
    LOG_FILE="$LOG_DIR/session_${ts}.log"
    find "$LOG_DIR" -name 'session_*.log' -mtime +30 -delete 2>/dev/null || true
    log INFO "=== Mr. Roboto v${VERSION} (bash) ==="
    log INFO "Session started: $(date '+%Y-%m-%d %H:%M:%S')"
    log INFO "OS: $(uname -srm)"
}

# =============================================================================
# Environment Init
# =============================================================================

init_env() {
    for d in "$BIN_DIR" "$LOG_DIR" "$STATE_DIR" "$CACHE_DIR" \
              "$SCRIPT_DIR/downloads" "$SCRIPT_DIR/metadata"; do
        mkdir -p "$d"
    done
    # Sweep stray yt-dlp output captures from interrupted runs (see start_acquisition)
    find "$CACHE_DIR" -maxdepth 1 -name 'ytdlp_out.*' -mmin +60 -delete 2>/dev/null || true
    init_logging
    log INFO "Environment ready. Arch: $ARCH"
}

# =============================================================================
# GPU Detection
# =============================================================================

detect_gpu() {
    if command -v nvidia-smi &>/dev/null; then
        GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null \
                   | head -1 | xargs)
        [[ -z "$GPU_NAME" ]] && GPU_NAME="NVIDIA GPU"
        ENCODER="h264_nvenc"
    elif command -v lspci &>/dev/null; then
        local line
        line=$(lspci 2>/dev/null | grep -iE 'VGA|3D|Display' | head -1)
        if [[ -n "$line" ]]; then
            GPU_NAME=$(printf '%s' "$line" | sed 's/.*: //')
            if   printf '%s' "$line" | grep -qiE 'NVIDIA|GeForce|GTX|RTX|Quadro'; then
                ENCODER="h264_nvenc"
            elif printf '%s' "$line" | grep -qiE 'AMD|Radeon|ATI'; then
                ENCODER="h264_vaapi"
            elif printf '%s' "$line" | grep -qi 'Intel'; then
                ENCODER="h264_qsv"
            fi
        else
            GPU_NAME="None (Software)"
        fi
    else
        GPU_NAME="Unknown (install pciutils for detection)"
    fi
    log INFO "GPU: $GPU_NAME  Encoder: $ENCODER"
}

# =============================================================================
# Binary Management
# =============================================================================

find_binary() {
    if [[ -x "$BIN_DIR/$1" ]]; then
        printf '%s' "$BIN_DIR/$1"
    elif command -v "$1" &>/dev/null; then
        command -v "$1"
    fi
}

_download() {
    local url="$1" dest="$2"
    if command -v curl &>/dev/null; then
        curl -fsSL --progress-bar "$url" -o "$dest"
    elif command -v wget &>/dev/null; then
        wget -q --show-progress "$url" -O "$dest"
    else
        printf '%s\n' "${R}[ERROR] Neither curl nor wget found.${N}" >&2
        exit 1
    fi
}

install_ytdlp() {
    printf '  %s\n' "${Y}Downloading yt-dlp...${N}"
    log INFO "Downloading yt-dlp: $YTDLP_URL"
    _download "$YTDLP_URL" "$BIN_DIR/yt-dlp"
    chmod +x "$BIN_DIR/yt-dlp"
    log INFO "yt-dlp installed: $BIN_DIR/yt-dlp"
    printf '  %s\n' "${G}[OK] yt-dlp installed${N}"
}

install_ffmpeg() {
    printf '  %s\n' "${Y}Downloading FFmpeg (large file, please wait)...${N}"
    log INFO "Downloading FFmpeg: $FFMPEG_URL"
    local archive="$CACHE_DIR/ffmpeg.tar.xz"
    local extract="$CACHE_DIR/ffmpeg_extract"

    _download "$FFMPEG_URL" "$archive"

    printf '  %s\n' "${Y}Extracting FFmpeg...${N}"
    rm -rf "$extract"; mkdir -p "$extract"
    tar -xJf "$archive" -C "$extract"

    local bin_dir ffmpeg_path
    ffmpeg_path=$(find "$extract" -name 'ffmpeg' -type f | head -1)
    if [[ -n "$ffmpeg_path" ]]; then
        bin_dir=$(dirname "$ffmpeg_path")
    else
        bin_dir=""
    fi
    if [[ -z "$bin_dir" ]]; then
        log ERROR "ffmpeg binary not found in archive"
        printf '%s\n' "${R}[ERROR] ffmpeg not found in downloaded archive.${N}" >&2
        rm -f "$archive"; rm -rf "$extract"
        return 1
    fi
    for b in ffmpeg ffprobe; do
        if [[ -f "$bin_dir/$b" ]]; then
            cp "$bin_dir/$b" "$BIN_DIR/"
            chmod +x "$BIN_DIR/$b"
            log INFO "$b installed: $BIN_DIR/$b"
        fi
    done
    rm -f "$archive"; rm -rf "$extract"
    printf '  %s\n' "${G}[OK] FFmpeg installed${N}"
}

check_deps() {
    printf '  Checking dependencies...\n'
    log INFO "Checking dependencies..."

    [[ -z "$(find_binary yt-dlp)" ]] && install_ytdlp \
        || log INFO "yt-dlp: $(find_binary yt-dlp)"

    [[ -z "$(find_binary ffmpeg)" ]] && install_ffmpeg \
        || log INFO "ffmpeg: $(find_binary ffmpeg)"

    if ! command -v deno &>/dev/null; then
        log WARN "Deno not found. Some YouTube formats may be missing."
        printf '\n  %s\n' "${Y}[WARN] Deno runtime not detected.${N}"
        printf '  %s\n'   "${D}yt-dlp uses Deno for JavaScript extraction.${N}"
        printf '  %s\n'   "${D}Without it, some formats may be missing.${N}"
        printf '  %s\n\n' "${C}Install: curl -fsSL https://deno.land/install.sh | sh${N}"
    fi

    printf '  %s\n' "${G}[OK] Dependencies ready${N}"
    log INFO "All dependencies ready."
}

# =============================================================================
# Banner
# =============================================================================

show_banner() {
    local ytdlp ffmpeg ytver ffver
    ytdlp=$(find_binary yt-dlp); ffmpeg=$(find_binary ffmpeg)
    if [[ -n "$ytdlp" ]]; then ytver=$("$ytdlp" --version 2>/dev/null || printf '?'); else ytver="not installed"; fi
    if [[ -n "$ffmpeg" ]]; then ffver=$("$ffmpeg" -version 2>/dev/null | awk 'NR==1{print $3}'); else ffver="not installed"; fi
    printf '\n'
    printf '%s\n' "${C}  +=========================================================+${N}"
    printf '%s\n' "${C}  |          M R .  R O B O T O  v${VERSION}               |${N}"
    printf '%s\n' "${C}  |      Portable Media Downloader                        |${N}"
    printf '%s\n' "${C}  +=========================================================+${N}"
    printf '\n'
    printf '%s\n' "${Y}  System Information${N}"
    printf '%s\n' "${D}  -----------------------------------------------------------${N}"
    printf '  %-10s: %s\n' "GPU"     "$GPU_NAME"
    printf '  %-10s: %s\n' "Encoder" "$ENCODER"
    printf '  %-10s: %s\n' "Arch"    "$ARCH"
    printf '  %-10s: %s\n' "yt-dlp"  "$ytver"
    printf '  %-10s: %s\n' "FFmpeg"  "$ffver"
    printf '\n'
    printf '%s\n' "${D}  -----------------------------------------------------------${N}"
    printf '  %s\n\n' "${G}Ready to acquire media.${N}"
}

# =============================================================================
# State / Resume
# =============================================================================

_json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

save_state() {
    local url="$1" profile="$2" dir="$3" ts
    ts=$(date '+%Y-%m-%dT%H:%M:%S%z')
    if command -v python3 &>/dev/null; then
        python3 - "$url" "$profile" "$dir" "$ts" "$STATE_FILE" <<'PYEOF'
import sys, json
data = {"url": sys.argv[1], "profile": sys.argv[2], "downloadDir": sys.argv[3], "status": "in_progress", "timestamp": sys.argv[4]}
with open(sys.argv[5], 'w') as f: json.dump(data, f)
PYEOF
    else
        local safe_url safe_profile safe_dir
        safe_url=$(_json_escape "$url")
        safe_profile=$(_json_escape "$profile")
        safe_dir=$(_json_escape "$dir")
        cat > "$STATE_FILE" <<EOF
{"url":"${safe_url}","profile":"${safe_profile}","downloadDir":"${safe_dir}","status":"in_progress","timestamp":"${ts}"}
EOF
    fi
    log DEBUG "State saved"
}

clear_state() { rm -f "$STATE_FILE"; }

# Reads a single field out of a small JSON file. Values are passed to
# Python via argv (sys.argv), never interpolated into the heredoc body —
# same fix as save_history() below, applied here for consistency.
_json_field() {
    local file="$1" field="$2"
    if command -v python3 &>/dev/null; then
        python3 - "$file" "$field" <<'PYEOF' 2>/dev/null || true
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    print(d.get(sys.argv[2], ''))
except Exception:
    pass
PYEOF
    else
        grep -o "\"$field\":\"[^\"]*\"" "$file" 2>/dev/null | cut -d'"' -f4
    fi
}

check_resume() {
    [[ -f "$STATE_FILE" ]] || return 0
    local status; status=$(_json_field "$STATE_FILE" status)
    [[ "$status" == "in_progress" ]] || { clear_state; return 0; }

    # Discard state older than 2 hours
    if command -v python3 &>/dev/null; then
        local ts stale
        ts=$(_json_field "$STATE_FILE" timestamp)
        stale=$(python3 - "$ts" <<'PYEOF' 2>/dev/null || printf 'no'
import sys
from datetime import datetime, timezone, timedelta
try:
    ts = datetime.fromisoformat(sys.argv[1])
    if ts.tzinfo is None: ts = ts.replace(tzinfo=timezone.utc)
    print('yes' if (datetime.now(timezone.utc)-ts) > timedelta(hours=2) else 'no')
except: print('no')
PYEOF
)
        [[ "$stale" == "yes" ]] && { clear_state; return 0; }
    fi

    local url profile dir
    url=$(_json_field "$STATE_FILE" url)
    profile=$(_json_field "$STATE_FILE" profile)
    dir=$(_json_field "$STATE_FILE" downloadDir)

    printf '\n  %s\n' "${Y}Interrupted download detected:${N}"
    printf '    %-12s: %s\n' "URL"     "$url"
    printf '    %-12s: %s\n' "Profile" "$profile"
    read -r -p "  Resume this download? [Y/N]: " ans
    if [[ "$ans" =~ ^[Yy] ]]; then
        if [[ -n "$dir" ]]; then
            DOWNLOAD_DIR="$dir"
            log INFO "Restored download dir from state: $DOWNLOAD_DIR"
        else
            select_download_location "$profile"
        fi
        start_acquisition "$url" "$profile" "$DOWNLOAD_DIR"
    else
        clear_state
    fi
}

# =============================================================================
# Download History
# =============================================================================

# FIX (blocker #4): previously this used an UNQUOTED heredoc
# (`<<PYEOF` instead of `<<'PYEOF'`), so bash substituted $title/$url
# directly into the heredoc body before Python ever saw it, landing raw,
# un-escaped bytes inside Python triple-quoted string literals
# (`"""$title"""`, `"""$url"""`). Any title or URL containing `"""`
# breaks out of that string and the rest is parsed as live Python — e.g. a
# url of  a"""+__import__("os").system("...")+"""b  runs arbitrary shell
# commands the moment save_history() is called. Verified exploitable in
# testing. Fix: quote the heredoc delimiter (no shell expansion inside it
# at all) and pass all values through sys.argv instead, so they're always
# treated as opaque strings, never as source text.
save_history() {
    local title="$1" url="$2" profile="$3" dir="$4"
    command -v python3 &>/dev/null || return 0
    local now; now=$(date '+%Y-%m-%d %H:%M:%S')
    python3 - "$HISTORY_FILE" "$title" "$url" "$profile" "$dir" "$now" <<'PYEOF'
import json, sys, os

f, title, url, profile, dir_, ts = sys.argv[1:7]
rec = {"title": title, "url": url,
       "profile": profile, "path": dir_,
       "time": ts, "status": "completed"}
h = []
if os.path.exists(f):
    try:
        with open(f) as fp: h = json.load(fp)
        if not isinstance(h, list): h = [h]
    except Exception: pass
h.append(rec)
with open(f, 'w') as fp: json.dump(h, fp, indent=2)
PYEOF
}

show_history() {
    if [[ ! -f "$HISTORY_FILE" ]]; then
        printf '\n  %s\n\n' "${Y}No downloads yet.${N}"; return
    fi
    printf '\n%s\n\n' "${C}=== Previous Downloads ===${N}"
    if command -v python3 &>/dev/null; then
        python3 - "$HISTORY_FILE" <<'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f: h = json.load(f)
    if not isinstance(h, list): h = [h]
    for item in reversed(h[-20:]):
        print(f"  \033[36m• {item.get('title','Unknown')}\033[0m")
        print(f"    {item.get('time','')} | {item.get('profile','')}")
        print(f"    \033[2;37m{item.get('url','')}\033[0m\n")
except Exception as e:
    print(f"  Error reading history: {e}")
PYEOF
    else
        grep '"title"' "$HISTORY_FILE" \
            | sed 's/.*"title":"\([^"]*\)".*/  • \1/'
    fi
}

# =============================================================================
# Download Location
# =============================================================================

# FIX (blocker #1): accepts an optional pre-supplied directory and, in
# HEADLESS_MODE, never calls `read`. Headless runs either use the
# explicitly passed dir or fall back silently to the XDG default.
select_download_location() {
    local profile="$1" custom_dir="${2:-}" label default_dir xdg_result

    if [[ "$profile" == audio-* ]]; then
        label="Music"
        xdg_result=$(command -v xdg-user-dir &>/dev/null \
                     && xdg-user-dir MUSIC 2>/dev/null || true)
        default_dir="${xdg_result:-$HOME/Music}"
    else
        label="Videos"
        xdg_result=$(command -v xdg-user-dir &>/dev/null \
                     && xdg-user-dir VIDEOS 2>/dev/null || true)
        default_dir="${xdg_result:-$HOME/Videos}"
    fi

    if $HEADLESS_MODE; then
        [[ -n "$custom_dir" ]] && default_dir="$custom_dir"
        log INFO "Headless mode: using download location: $default_dir"
    else
        printf '\n'
        printf '  %s\n' "${D}Default save location (${label}): ${default_dir}${N}"
        printf '  %s\n' "${D}Press Enter to accept, or type a custom path:${N}"
        read -r -p "  Path: " custom
        if [[ -n "$custom" ]]; then
            # Strip any wrapping quote characters the user may have pasted in
            # (e.g. "/home/ian" → /home/ian, '/home/ian' → /home/ian).
            custom="${custom#\"}" ; custom="${custom%\"}"
            custom="${custom#\'}" ; custom="${custom%\'}"
            # Expand a leading ~ to $HOME so ~/Videos works as expected.
            # We do NOT use `eval` — just a simple prefix substitution.
            [[ "$custom" == "~" ]]   && custom="$HOME"
            # SC2088 is a false positive: we're matching the literal string "~/"
            # as a prefix pattern, not relying on tilde expansion in quotes.
            # shellcheck disable=SC2088
            [[ "$custom" == "~/"* ]] && custom="$HOME/${custom:2}"
            default_dir="$custom"
        fi
    fi

    if ! mkdir -p "$default_dir" 2>/dev/null; then
        log WARN "Could not create '$default_dir'; using $SCRIPT_DIR/downloads"
        default_dir="$SCRIPT_DIR/downloads"
        mkdir -p "$default_dir"
    fi

    DOWNLOAD_DIR="$default_dir"
    log INFO "Download location set: $DOWNLOAD_DIR"
}

# =============================================================================
# URL Validation
# =============================================================================

validate_url() {
    local url="$1"
    [[ -z "$url" ]] && return 1
    [[ "$url" =~ ^https?://[^[:space:]]+ ]] || return 1
    [[ "$url" == *file://* || "$url" == *javascript:* ]] && return 1
    return 0
}

# =============================================================================
# Browser Detection / Cookie Profile Resolution
# =============================================================================

# Brave installed via Snap (or Flatpak) does NOT live at the conventional
# ~/.config/BraveSoftware/Brave-Browser path that yt-dlp's browser-cookie
# code assumes by default — that path exists but is an empty stub
# (NativeMessagingHosts/ only). This walks the known native/Snap/Flatpak
# roots, finds the most recently modified Cookies file (Chromium >=96
# stores it at <profile>/Network/Cookies, older versions at
# <profile>/Cookies — we check for both and normalize to the profile dir),
# and returns that exact profile directory so yt-dlp doesn't have to guess.
#
# Override: set MR_ROBOTO_BRAVE_PROFILE to force an exact path if the
# heuristic ever picks the wrong profile (e.g. multiple Google accounts
# logged into different Brave profiles).
resolve_brave_profile() {
    if [[ -n "${MR_ROBOTO_BRAVE_PROFILE:-}" ]]; then
        printf '%s' "$MR_ROBOTO_BRAVE_PROFILE"
        return 0
    fi

    local roots=(
        "$HOME/.config/BraveSoftware/Brave-Browser"
        "$HOME/snap/brave/current/.config/BraveSoftware/Brave-Browser"
        "$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser"
    )
    local root cookie_file ts best="" best_ts=0

    for root in "${roots[@]}"; do
        [[ -d "$root" ]] || continue
        while IFS= read -r cookie_file; do
            ts=$(stat -c '%Y' "$cookie_file" 2>/dev/null || printf '0')
            if (( ts > best_ts )); then
                best_ts=$ts
                best=$(dirname "$cookie_file")
                [[ "$(basename "$best")" == "Network" ]] && best=$(dirname "$best")
            fi
        done < <(find "$root" -maxdepth 4 -iname 'Cookies' -type f 2>/dev/null)
    done

    [[ -n "$best" ]] && { printf '%s' "$best"; return 0; }
    return 1
}

# FIX (blocker #5): previously called twice —
#   get_cookie_browser && cookie_browser=$(get_cookie_browser) || true
# The first call ran for its exit status only, but the function's
# `printf '%s' "$b"` inside still wrote straight to the terminal
# (uncaptured), which is exactly the stray "firefox" line seen in review.
# Calling it once via command substitution fixes both the leak and halves
# the work. Also now resolves a full --cookies-from-browser spec
# (BROWSER[:PROFILE_PATH]) rather than a bare browser name.
get_cookie_browser() {
    local b
    for b in firefox chrome chromium brave vivaldi opera; do
        command -v "$b" &>/dev/null || continue
        if [[ "$b" == "brave" ]]; then
            local profile
            if profile=$(resolve_brave_profile); then
                printf '%s' "brave:${profile}"
            else
                printf '%s' "brave"
            fi
        else
            printf '%s' "$b"
        fi
        return 0
    done
    return 1
}

# =============================================================================
# Failure Classification (fixes blocker #2)
# =============================================================================
# yt-dlp doesn't expose a rich set of distinct exit codes per failure type,
# so we pattern-match its actual stdout/stderr. These lists are heuristics —
# expect to extend them as you hit new failure strings in the wild.

# Auth-style failures where retrying with browser cookies could plausibly help.
is_auth_failure() {
    grep -qiE \
        'sign in to confirm|requires authentication|private video|age[- ]restricted|http error 403|login required' \
        "$1"
}

# Failures where the URL/content itself is the problem — retrying or
# escalating to cookie auth will not help. Includes the truncated-ID case
# from the review ("Incomplete YouTube ID ___. URL ___ looks truncated.").
is_non_retryable() {
    grep -qiE \
        'unsupported url|incomplete .*id|looks truncated|no video formats found|video unavailable|this video has been removed|does not exist' \
        "$1"
}

# Detects a user-initiated interruption (Ctrl+C) rather than a real failure.
# Exit code 130 = 128+SIGINT, the standard shell convention. We also check
# the captured text in case yt-dlp caught the signal itself and exited 1
# with its own "Interrupted by user" message instead of dying to the signal.
is_user_interrupt() {
    local exit_code="$1" out_file="$2"
    [[ "$exit_code" -eq 130 ]] && return 0
    grep -qi 'interrupted by user' "$out_file"
}

# =============================================================================
# Acquisition
# =============================================================================

start_acquisition() {
    local url="$1" profile="$2" dir="$3"

    local ytdlp ffmpeg ffmpeg_dir
    ytdlp=$(find_binary yt-dlp); ffmpeg=$(find_binary ffmpeg)
    ffmpeg_dir=$(dirname "$ffmpeg")

    log INFO "Acquisition started — URL: $url  Profile: $profile"
    save_state "$url" "$profile" "$dir"

    # ── Profile → format args ────────────────────────────────────────────────
    local fmt container audio_only=false audio_fmt="" audio_q=""
    case "$profile" in
        ultra)      fmt="bestvideo[height<=2160]+bestaudio/best"; container="mkv" ;;
        high)       fmt="bestvideo[height<=1080]+bestaudio/best"; container="mp4" ;;
        mobile)     fmt="bestvideo[height<=720]+bestaudio/best";  container="mp4" ;;
        audio-flac) fmt="bestaudio";                   audio_only=true; audio_fmt="flac"; audio_q="0"    ;;
        audio-opus) fmt="bestaudio[ext=webm]/bestaudio"; audio_only=true; audio_fmt="opus"; audio_q="0"  ;;
        audio-mp3)  fmt="bestaudio";                   audio_only=true; audio_fmt="mp3";  audio_q="320K" ;;
        *) log ERROR "Unknown profile: $profile"; return 1 ;;
    esac

    # ── Playlist check ───────────────────────────────────────────────────────
    # FIX (part of blocker #1): this `read` would also hang a headless run.
    # In headless mode we default to single-video unless explicitly opted
    # into full-playlist mode via MR_ROBOTO_PLAYLIST=yes.
    local playlist_flag="--no-playlist"
    if [[ "$url" == *list=* ]]; then
        if $HEADLESS_MODE; then
            if [[ "${MR_ROBOTO_PLAYLIST:-}" == "yes" ]]; then
                playlist_flag="--yes-playlist"
                log INFO "Headless mode: full playlist enabled via MR_ROBOTO_PLAYLIST=yes."
            else
                log INFO "Headless mode: playlist URL detected, defaulting to single video (set MR_ROBOTO_PLAYLIST=yes to change)."
            fi
        else
            printf '\n  %s\n' "${Y}WARNING: Playlist detected in URL.${N}"
            printf '  [1] Single video (recommended)\n'
            printf '  [2] Full playlist\n\n'
            read -r -p "  Choice [1]: " pl_choice
            if [[ "$pl_choice" == "2" ]]; then
                playlist_flag="--yes-playlist"
                log INFO "Playlist mode enabled."
            else
                log INFO "Single video enforced (playlist URL)."
            fi
        fi
    fi

    # ── Build core arg array ─────────────────────────────────────────────────
    local -a core=(
        "$url"
        --format "$fmt"
        --ffmpeg-location "$ffmpeg_dir"
        --no-part --continue
        "$playlist_flag"
        --embed-thumbnail --embed-metadata
    )

    if $audio_only; then
        core+=(
            --extract-audio
            --audio-format "$audio_fmt"
            --audio-quality "$audio_q"
            --output "$dir/%(title)s.%(ext)s"
        )
        log INFO "Audio-only mode: $audio_fmt @ $audio_q"
    else
        core+=(
            --output "$dir/%(title)s.%(ext)s"
            --merge-output-format "$container"
        )
        if [[ "$ENCODER" != "libx264" ]]; then
            core+=(--postprocessor-args "merger+ffmpeg:-c copy")
            log INFO "Stream-copy mode. HW encoder available: $ENCODER"
        fi
    fi

    # ── Resolve cookie browser once (fixes blocker #5 leak) ─────────────────
    local cookie_browser=""
    cookie_browser=$(get_cookie_browser) || true

    # ── Retry loop ───────────────────────────────────────────────────────────
    local attempt=1 max=3 success=false use_cookies=false
    local out_file; out_file=$(mktemp "${CACHE_DIR}/ytdlp_out.XXXXXX")

    while [[ $attempt -le $max ]] && ! $success; do
        printf '\n  %s\n' "${G}- Downloading (Attempt ${attempt}/${max})...${N}"
        printf '    %-12s: %s\n' "Profile" "$profile"
        printf '    %-12s: %s\n\n' "Output" "$dir"

        local -a run_args=("${core[@]}")
        if $use_cookies && [[ -n "$cookie_browser" ]]; then
            run_args+=(--cookies-from-browser "$cookie_browser")
            log INFO "Using browser cookies: $cookie_browser"
        else
            run_args+=(--no-cookies)
        fi

        : > "$out_file"
        # Capture combined stdout+stderr to a file (for pattern matching)
        # while still streaming live to the terminal via tee. We toggle
        # errexit off around the pipeline so a non-zero yt-dlp exit doesn't
        # kill the script before we get a chance to classify it — and we
        # read PIPESTATUS immediately, before any other command can
        # clobber it.
        set +e
        "$ytdlp" "${run_args[@]}" 2>&1 | tee "$out_file"
        local exit_code=${PIPESTATUS[0]}
        set -e

        if [[ $exit_code -eq 0 ]]; then
            # Guard against the "empty playlist" false positive: yt-dlp exits 0
            # and prints "Downloading 0 items" when a channel redirect produces
            # no usable content (e.g. backslash-escaped URLs, region-blocked
            # channel pages). Treat that as a real failure so we don't print
            # "Download complete!" and write a junk history record.
            if grep -q 'Downloading 0 items' "$out_file"; then
                log WARN "yt-dlp exited 0 but downloaded 0 items — likely a bad URL or region block."
                printf '\n  %s\n' "${R}Download failed — no media found at that URL.${N}"
                printf '  %s\n'   "${D}Check the URL is correct and unescaped (no backslashes before ? or &).${N}"
                clear_state
                rm -f "$out_file"
                return 1
            fi
            log INFO "Download completed successfully."
            printf '\n  %s\n' "${G}Download complete!${N}"
            save_history "$(basename "$dir")" "$url" "$profile" "$dir"
            clear_state
            success=true
        elif is_user_interrupt "$exit_code" "$out_file"; then
            printf '\n  %s\n' "${Y}Download interrupted by user.${N}"
            printf '  %s\n' "${D}State preserved — resume available next run.${N}"
            log WARN "Download interrupted by user; state preserved."
            rm -f "$out_file"
            return 130
        elif is_non_retryable "$out_file"; then
            printf '\n  %s\n' "${R}Download failed — URL is invalid, unsupported, or unavailable.${N}"
            printf '  %s\n'   "${D}Retrying or using browser cookies will not help here.${N}"
            log ERROR "Non-retryable failure for $url"
            clear_state
            rm -f "$out_file"
            return 1
        else
            log WARN "yt-dlp exited with code $exit_code."

            if is_auth_failure "$out_file" && ! $use_cookies && [[ -n "$cookie_browser" ]]; then
                printf '\n  %s\n' "${Y}Download failed. YouTube requires sign-in.${N}"
                if $HEADLESS_MODE; then
                    if [[ "${MR_ROBOTO_COOKIES:-}" == "yes" ]]; then
                        use_cookies=true
                        log INFO "Headless cookie auth enabled (MR_ROBOTO_COOKIES=yes): $cookie_browser"
                    else
                        printf '  %s\n' "${R}Headless mode: skipping cookie retry. Set MR_ROBOTO_COOKIES=yes to allow.${N}"
                        log ERROR "Auth failure in headless mode; cookie retry not enabled."
                        rm -f "$out_file"
                        return 1
                    fi
                else
                    read -r -p "  Retry with $cookie_browser cookies? [Y/N]: " try_auth
                    if [[ "$try_auth" =~ ^[Yy] ]]; then
                        use_cookies=true
                        log INFO "Cookie auth enabled: $cookie_browser"
                    else
                        printf '  %s\n' "${R}Download failed. Check logs/ for details.${N}"
                        rm -f "$out_file"
                        return 1
                    fi
                fi
            elif is_auth_failure "$out_file" && [[ -z "$cookie_browser" ]]; then
                printf '\n  %s\n' "${R}Download failed (sign-in required). No supported browser found for cookie auth.${N}"
                printf '  %s\n'   "${Y}Install Firefox or Chrome to enable authentication fallback.${N}"
                log ERROR "Auth failure; no browser available for cookie escalation."
                rm -f "$out_file"
                return 1
            elif [[ $attempt -lt $max ]]; then
                printf '\n  %s\n' "${Y}Retrying in 5 seconds...${N}"
                sleep 5
            else
                printf '\n  %s\n' "${R}Download failed after $max attempts.${N}"
                printf '  %s\n'   "${Y}Check logs/ for details.${N}"
                log ERROR "Download failed after $max attempts."
                rm -f "$out_file"
                return 1
            fi
        fi

        ((attempt++)) || true
    done

    rm -f "$out_file"
    if $success; then
        return 0
    fi
    log ERROR "Acquisition ended without success for: $url"
    return 1
}

# =============================================================================
# Interactive Menu
# =============================================================================

show_menu() {
    printf '\n'
    printf '%s\n' "${D}  +-----------------------------------------------------------+${N}"
    printf '%s\n' "${C}  |  Mr. Roboto — Acquisition Mode                          |${N}"
    printf '%s\n' "${D}  +-----------------------------------------------------------+${N}"
    printf '%s\n' "${D}  |  VIDEO                                                  |${N}"
    printf '%s\n' "  |  [1] Ultra   4K MKV     (maximum quality)               |"
    printf '%s\n' "${G}  |  [2] High    1080p MP4  (recommended)                   |${N}"
    printf '%s\n' "${Y}  |  [3] Mobile  720p MP4   (compact, portable)             |${N}"
    printf '%s\n' "${D}  +-----------------------------------------------------------+${N}"
    printf '%s\n' "${D}  |  AUDIO ONLY                                             |${N}"
    printf '%s\n' "  |  [4] FLAC    Lossless archive  (archival grade)          |"
    printf '%s\n' "${C}  |  [5] Opus    Hi-Fi native      (bit-perfect, smallest)  |${N}"
    printf '%s\n' "  |  [6] MP3     320 kbps          (universal compatibility) |"
    printf '%s\n' "${D}  +-----------------------------------------------------------+${N}"
    printf '%s\n' "${C}  |  [7] View Download History                              |${N}"
    printf '%s\n' "${R}  |  [Q] Quit                                               |${N}"
    printf '%s\n' "${D}  +-----------------------------------------------------------+${N}"
    printf '\n'
}

start_interactive() {
    check_resume

    while true; do
        show_menu
        read -r -p "  Choice: " choice

        local profile=""
        case "${choice^^}" in
            1|U) profile="ultra"      ;;
            2|H) profile="high"       ;;
            3|M) profile="mobile"     ;;
            4|F) profile="audio-flac" ;;
            5|O) profile="audio-opus" ;;
            6|P) profile="audio-mp3"  ;;
            7)   show_history; continue ;;
            Q)   printf '  %s\n\n' "${C}Goodbye.${N}"; exit 0 ;;
            *)   printf '  %s\n' "${R}Invalid choice — try again.${N}"; continue ;;
        esac

        printf '\n'
        read -r -p "  Enter media URL: " raw_url
        # Strip any accidental whitespace from paste
        local url="${raw_url//[[:space:]]/}"

        if ! validate_url "$url"; then
            printf '  %s\n' "${R}Invalid URL. Must start with http:// or https://${N}"
            continue
        fi

        select_download_location "$profile"
        start_acquisition "$url" "$profile" "$DOWNLOAD_DIR"

        printf '\n'
        read -r -p "  Download another? [Y/N]: " again
        [[ "${again^^}" == "Y" ]] || { printf '  %s\n\n' "${C}Goodbye.${N}"; break; }
    done
}

# =============================================================================
# Entry Point
# =============================================================================

main() {
    init_env
    check_deps
    detect_gpu
    show_banner

    if [[ $# -gt 0 ]]; then
        # Direct / headless mode: ./roboto.sh <url> [profile] [output_dir]
        HEADLESS_MODE=true
        local url="$1" profile="${2:-high}" custom_dir="${3:-}"
        if ! validate_url "$url"; then
            printf '%s\n' "${R}[ERROR] Invalid URL: $url${N}" >&2; exit 1
        fi
        select_download_location "$profile" "$custom_dir"
        local rc=0
        start_acquisition "$url" "$profile" "$DOWNLOAD_DIR" || rc=$?
        log INFO "Session ended."
        exit $rc
    fi

    start_interactive
    log INFO "Session ended."
}

main "$@"