#!/usr/bin/env bash
# =============================================================================
# Mr. Roboto v2.0 — Native Linux/macOS launcher
# No PowerShell required. Requires: bash, curl or wget, tar.
# =============================================================================
set -euo pipefail

VERSION="2.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Architecture ──────────────────────────────────────────────────────────────
case "$(uname -m)" in
    x86_64)  ARCH="x64";   YTDLP_SUFFIX="linux";         FFMPEG_SUFFIX="linux64"    ;;
    aarch64) ARCH="arm64"; YTDLP_SUFFIX="linux_aarch64";  FFMPEG_SUFFIX="linuxarm64" ;;
    armv7l)  ARCH="arm";   YTDLP_SUFFIX="linux_armv7l";   FFMPEG_SUFFIX="linux64"    ;;
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

    local bin_dir
    bin_dir=$(find "$extract" -name 'ffmpeg' -type f | head -1 | xargs -I{} dirname {})
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
    ytver=$("$ytdlp" --version 2>/dev/null || printf '?')
    ffver=$("$ffmpeg" -version 2>/dev/null | awk 'NR==1{print $3}')
    printf '\n'
    printf '%s\n' "${C}  +=========================================================+${N}"
    printf '%s\n' "${C}  |          M R .  R O B O T O  v${VERSION}               |${N}"
    printf '%s\n' "${C}  |      Autonomous Media Acquisition Agent               |${N}"
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

save_state() {
    cat > "$STATE_FILE" <<EOF
{"url":"$1","profile":"$2","downloadDir":"$3","status":"in_progress","timestamp":"$(date -Iseconds)"}
EOF
    log DEBUG "State saved"
}

clear_state() { rm -f "$STATE_FILE"; }

_json_field() {
    local file="$1" field="$2"
    if command -v python3 &>/dev/null; then
        python3 -c "import json; d=json.load(open('$file')); print(d.get('$field',''))" 2>/dev/null || true
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
        stale=$(python3 -c "
from datetime import datetime, timezone, timedelta
try:
    ts = datetime.fromisoformat('$ts')
    if ts.tzinfo is None: ts = ts.replace(tzinfo=timezone.utc)
    print('yes' if (datetime.now(timezone.utc)-ts) > timedelta(hours=2) else 'no')
except: print('no')
" 2>/dev/null || printf 'no')
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

save_history() {
    local title="$1" url="$2" profile="$3" dir="$4"
    command -v python3 &>/dev/null || return 0
    python3 - "$HISTORY_FILE" <<PYEOF
import json, sys, os
f = sys.argv[1]
rec = {"title": """$title""", "url": """$url""",
       "profile": """$profile""", "path": """$dir""",
       "time": "$(date '+%Y-%m-%d %H:%M:%S')", "status": "completed"}
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

select_download_location() {
    local profile="$1" label default_dir xdg_result

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

    printf '\n'
    printf '  %s\n' "${D}Default save location (${label}): ${default_dir}${N}"
    printf '  %s\n' "${D}Press Enter to accept, or type a custom path:${N}"
    read -r -p "  Path: " custom
    [[ -n "$custom" ]] && default_dir="$custom"

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
# Browser Detection
# =============================================================================

get_cookie_browser() {
    for b in firefox chrome chromium brave vivaldi opera; do
        command -v "$b" &>/dev/null && printf '%s' "$b" && return 0
    done
    return 1
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
    local playlist_flag="--no-playlist"
    if [[ "$url" == *list=* ]]; then
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

    # ── Retry loop ───────────────────────────────────────────────────────────
    local cookie_browser=""
    get_cookie_browser && cookie_browser=$(get_cookie_browser) || true

    local attempt=1 max=3 success=false use_cookies=false

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

        local exit_code=0
        "$ytdlp" "${run_args[@]}" || exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            log INFO "Download completed successfully."
            printf '\n  %s\n' "${G}Download complete!${N}"
            save_history "$(basename "$dir")" "$url" "$profile" "$dir"
            clear_state
            success=true
        else
            log WARN "yt-dlp exited with code $exit_code."

            if ! $use_cookies && [[ -n "$cookie_browser" ]]; then
                printf '\n  %s\n' "${Y}Download failed. YouTube may require sign-in.${N}"
                read -r -p "  Retry with $cookie_browser cookies? [Y/N]: " try_auth
                if [[ "$try_auth" =~ ^[Yy] ]]; then
                    use_cookies=true
                    log INFO "Cookie auth enabled: $cookie_browser"
                else
                    printf '  %s\n' "${R}Download failed. Check logs/ for details.${N}"
                    break
                fi
            elif ! $use_cookies && [[ -z "$cookie_browser" ]]; then
                printf '\n  %s\n' "${R}Download failed. No supported browser found for cookie auth.${N}"
                printf '  %s\n'   "${Y}Install Firefox or Chrome to enable authentication fallback.${N}"
                log ERROR "Download failed; no browser available for cookie escalation."
                break
            elif [[ $attempt -lt $max ]]; then
                printf '\n  %s\n' "${Y}Retrying in 5 seconds...${N}"
                sleep 5
            else
                printf '\n  %s\n' "${R}Download failed after $max attempts.${N}"
                printf '  %s\n'   "${Y}Check logs/ for details.${N}"
                log ERROR "Download failed after $max attempts."
                break
            fi
        fi

        ((attempt++)) || true
    done

    $success || log ERROR "Acquisition ended without success for: $url"
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
        # Direct / headless mode: ./roboto.sh <url> [profile]
        local url="$1" profile="${2:-high}"
        if ! validate_url "$url"; then
            printf '%s\n' "${R}[ERROR] Invalid URL: $url${N}" >&2; exit 1
        fi
        select_download_location "$profile"
        start_acquisition "$url" "$profile" "$DOWNLOAD_DIR"
    else
        start_interactive
    fi

    log INFO "Session ended."
}

main "$@"
