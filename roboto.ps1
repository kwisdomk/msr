#Requires -Version 5.1
<#
.SYNOPSIS
    Mr. Roboto v2.0 - Autonomous Media Acquisition Agent

.DESCRIPTION
    A portable, self-healing PowerShell automation suite for high-fidelity
    media acquisition, transformation, and archival.

.PARAMETER Url
    Media URL to download (optional, can be provided interactively)

.PARAMETER Profile
    Quality profile: ultra, high, or mobile (default: high)

.PARAMETER OfflineMode
    Skip dependency downloads and work offline

.EXAMPLE
    .\roboto.ps1
    Interactive mode with menu

.EXAMPLE
    .\roboto.ps1 -Url "https://youtube.com/watch?v=..." -Profile high
    Direct download mode

.NOTES
    Version: 2.0.0
    Author: Mr. Roboto Team
    License: MIT
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)][string]$Url,
    [Parameter(Mandatory = $false)]
    [ValidateSet('ultra', 'high', 'mobile', 'audio-flac', 'audio-opus', 'audio-mp3')]
    [string]$Profile = 'high',
    [Parameter(Mandatory = $false)][switch]$OfflineMode
)

# ── Force TLS 1.2 (TLS 1.3 enum absent on PS5.1/.NET 4.x — bug #6 fixed) ──
try {
    [Net.ServicePointManager]::SecurityProtocol =
    [Net.SecurityProtocolType]::Tls12 -bor
    [Net.SecurityProtocolType]::Tls11 -bor
    [Net.SecurityProtocolType]::Tls
    # Upgrade to Tls13 only if the enum exists (PS7+ / .NET5+)
    $tls13 = [Net.SecurityProtocolType]::Tls13
    [Net.ServicePointManager]::SecurityProtocol =
    [Net.ServicePointManager]::SecurityProtocol -bor $tls13
}
catch { <# Tls13 not available on this runtime — harmless #> }

# ── Script-level state ──────────────────────────────────────────────────────
$script:Version = "2.0.0"
$script:ScriptRoot = $PSScriptRoot
$script:ConfigPath = Join-Path $ScriptRoot "config.json"
$script:LogPath = Join-Path $ScriptRoot "logs"
$script:LogFile = $null
$script:Config = $null
$script:Hardware = $null   # cached once; Show-Banner reuses this
$script:DownloadDir = $null   # set once per session via Select-DownloadLocation

# ══════════════════════════════════════════════════════════════════════════════
#region  ANIMATIONS
# ══════════════════════════════════════════════════════════════════════════════

function Show-Typewriter {
    <# Prints $Text one character at a time. Lightweight — no threads. #>
    param([string]$Text, [int]$DelayMs = 18, [string]$Color = 'Green')
    foreach ($ch in $Text.ToCharArray()) {
        Write-Host $ch -NoNewline -ForegroundColor $Color
        Start-Sleep -Milliseconds $DelayMs
    }
    Write-Host ''
}

function Show-Spinner {
    <#
    Displays a braille spinner beside $Message for $Seconds seconds.
    Single-threaded — uses carriage-return overwrite. Safe, no jobs.
    #>
    param([string]$Message = 'Working...', [int]$Seconds = 2)
    $frames = [char[]]@([char]0x280B, [char]0x2819, [char]0x2839, [char]0x2838,
        [char]0x283C, [char]0x2834, [char]0x2826, [char]0x2827,
        [char]0x2807, [char]0x280F)
    $end = (Get-Date).AddSeconds($Seconds)
    $i = 0
    while ((Get-Date) -lt $end) {
        Write-Host -NoNewline "`r  $($frames[$i % $frames.Length]) $Message"
        Start-Sleep -Milliseconds 80
        $i++
    }
    Write-Host "`r  ✔ $Message" -ForegroundColor Green
}

#endregion

# ══════════════════════════════════════════════════════════════════════════════
#region  LOGGING
# ══════════════════════════════════════════════════════════════════════════════

function Write-Log {
    param(
        [Parameter(Mandatory)][ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')][string]$Level,
        [Parameter(Mandatory)][string]$Message
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$Level] $Message"

    if ($script:LogFile) {
        try { Add-Content -Path $script:LogFile -Value $entry -ErrorAction Stop } catch {}
    }

    $color = switch ($Level) {
        'DEBUG' { 'DarkGray' }
        'INFO' { 'White' }
        'WARN' { 'Yellow' }
        'ERROR' { 'Red' }
    }
    Write-Host $entry -ForegroundColor $color
}

function Initialize-Logging {
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $script:LogFile = Join-Path $script:LogPath "session_$ts.log"

    # Rotate: delete logs older than 30 days
    $cutoff = (Get-Date).AddDays(-30)
    Get-ChildItem $script:LogPath -Filter "session_*.log" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt $cutoff } |
    Remove-Item -Force -ErrorAction SilentlyContinue

    Write-Log "INFO" "=== Mr. Roboto v$($script:Version) ==="
    Write-Log "INFO" "Session started  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Log "INFO" "PowerShell       : $($PSVersionTable.PSVersion)"
    Write-Log "INFO" "OS               : $([Environment]::OSVersion.VersionString)"
}

#endregion

# ══════════════════════════════════════════════════════════════════════════════
#region  ENVIRONMENT INIT
# ══════════════════════════════════════════════════════════════════════════════

function Initialize-Config {
    $defaultConfig = [ordered]@{
        version  = "2.0.0"
        settings = [ordered]@{
            defaultQuality     = "high"
            autoUpdate         = $true
            offlineMode        = $false
            notifications      = $true
            preferredContainer = "mp4"
            libraryMode        = $false
        }
        profiles = [ordered]@{
            ultra        = [ordered]@{
                format      = "bestvideo[height<=2160]+bestaudio/best"
                container   = "mkv"
                videoCodec  = "auto"
                audioCodec  = "aac"
                description = "4K MKV (best quality)"
            }
            high         = [ordered]@{
                format      = "bestvideo[height<=1080]+bestaudio/best"
                container   = "mp4"
                videoCodec  = "auto"
                audioCodec  = "aac"
                description = "1080p MP4 (recommended)"
            }
            mobile       = [ordered]@{
                format      = "bestvideo[height<=720]+bestaudio/best"
                container   = "mp4"
                videoCodec  = "h264"
                audioCodec  = "aac"
                description = "720p MP4 (smaller size)"
            }
            # ── Audio-only profiles ──────────────────────────────────────
            # YouTube sources are lossy (Opus/AAC). These profiles give you
            # the best possible extraction at each fidelity/size trade-off.
            "audio-flac" = [ordered]@{
                format       = "bestaudio"
                container    = "flac"
                audioOnly    = $true
                audioFormat  = "flac"
                audioQuality = "0"
                description  = "Lossless Archive — best source → FLAC (archival grade)"
            }
            "audio-opus" = [ordered]@{
                format       = "bestaudio[ext=webm]/bestaudio"
                container    = "opus"
                audioOnly    = $true
                audioFormat  = "opus"
                audioQuality = "0"
                description  = "High-Fidelity — Opus native, zero re-encode (bit-perfect source)"
            }
            "audio-mp3"  = [ordered]@{
                format       = "bestaudio"
                container    = "mp3"
                audioOnly    = $true
                audioFormat  = "mp3"
                audioQuality = "320K"
                description  = "Universal — MP3 320kbps (maximum device compatibility)"
            }
        }
        # Use quoted key access to survive ConvertFrom-Json round-trips
        binaries = [ordered]@{
            "yt-dlp" = [ordered]@{
                x64 = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
                x86 = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_x86.exe"
            }
            ffmpeg   = [ordered]@{
                x64 = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
                x86 = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win32-gpl.zip"
            }
        }
    }
    try {
        $defaultConfig | ConvertTo-Json -Depth 10 | Set-Content $script:ConfigPath -Encoding UTF8
        Write-Host "[INFO] Created default config.json" -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Could not write config.json: $_" -ForegroundColor Red
        throw
    }
}

function Initialize-Environment {
    $dirs = @('bin/x64', 'bin/x86', 'downloads', 'metadata', 'logs', 'state', 'cache')
    foreach ($d in $dirs) {
        $p = Join-Path $script:ScriptRoot $d
        if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
    }

    if (-not (Test-Path $script:ConfigPath)) { Initialize-Config }

    try {
        $script:Config = Get-Content $script:ConfigPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Host "[ERROR] Failed to load config.json: $_" -ForegroundColor Red
        throw
    }

    Initialize-Logging
    Write-Log "INFO" "Environment ready."
}

#endregion

# ══════════════════════════════════════════════════════════════════════════════
#region  HARDWARE DETECTION
# ══════════════════════════════════════════════════════════════════════════════

function Get-HardwareCapabilities {
    Write-Log "INFO" "Detecting hardware..."
    $arch = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }

    try {
        $allGpus = Get-CimInstance Win32_VideoController -ErrorAction Stop |
        Where-Object { $_.Name -notlike "*Microsoft*" -and $_.Name -notlike "*Remote*" }

        # Prefer discrete GPUs: NVIDIA > AMD > Intel iGPU > first available
        $gpu = $allGpus | Where-Object { $_.Name -match "NVIDIA|GeForce|GTX|RTX|Quadro" } | Select-Object -First 1
        if (-not $gpu) { $gpu = $allGpus | Where-Object { $_.Name -match "AMD|Radeon|RX " }   | Select-Object -First 1 }
        if (-not $gpu) { $gpu = $allGpus | Select-Object -First 1 }

        if ($gpu) {
            $gpuName = $gpu.Name
            $encoder = if ($gpuName -match "NVIDIA|GeForce|GTX|RTX|Quadro") { "h264_nvenc" }
            elseif ($gpuName -match "AMD|Radeon|RX ") { "h264_amf" }
            elseif ($gpuName -match "Intel|HD Graphics|UHD|Iris") { "h264_qsv" }
            else { "libx264" }
            Write-Log "INFO" "GPU: $gpuName → Encoder: $encoder"
        }
        else {
            $gpuName = "None (Software)"
            $encoder = "libx264"
            Write-Log "WARN" "No dedicated GPU found; falling back to libx264."
        }
    }
    catch {
        $gpuName = "Detection Failed"
        $encoder = "libx264"
        Write-Log "WARN" "GPU query error: $($_.Exception.Message)"
    }

    return @{ GPU = $gpuName; Encoder = $encoder; Architecture = $arch }
}

#endregion

# ══════════════════════════════════════════════════════════════════════════════
#region  BINARY MANAGEMENT
# ══════════════════════════════════════════════════════════════════════════════

function Find-Binary {
    param([Parameter(Mandatory)][string]$Name)

    $arch = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
    $localPath = Join-Path $script:ScriptRoot "bin/$arch/$Name.exe"

    if (Test-Path $localPath) {
        Write-Log "DEBUG" "$Name found in local bin: $localPath"
        return $localPath
    }

    $sys = Get-Command $Name -ErrorAction SilentlyContinue
    if ($sys) {
        Write-Log "DEBUG" "$Name found in PATH: $($sys.Source)"
        return $sys.Source
    }

    Write-Log "DEBUG" "$Name not found."
    return $null
}

function Get-BinaryVersion {
    param([string]$BinaryPath, [string]$Name)
    try {
        $ver = switch ($Name) {
            'yt-dlp' { & $BinaryPath --version 2>$null }
            'ffmpeg' {
                $raw = & $BinaryPath -version 2>&1 | Select-Object -First 1
                if ($raw -match 'ffmpeg version (\S+)') { $matches[1] } else { '?' }
            }
            default { '?' }
        }
        return ($ver -join '').Trim()
    }
    catch { return '?' }
}

function Install-Binary {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('yt-dlp', 'ffmpeg')]
        [string]$Name
    )

    $arch = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
    $binDir = Join-Path $script:ScriptRoot "bin/$arch"

    # Bug #4 fixed: bracket notation for hyphenated key 'yt-dlp'
    $url = $script:Config.binaries."$Name"."$arch"

    if (-not $url) {
        Write-Log "ERROR" "No download URL found for $Name ($arch) in config.json."
        throw "Missing URL for $Name"
    }

    Write-Log "INFO" "Downloading $Name from $url ..."

    try {
        if ($Name -eq 'yt-dlp') {
            $dest = Join-Path $binDir "yt-dlp.exe"
            Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
            Write-Log "INFO" "yt-dlp installed → $dest"
        }
        else {
            # FFmpeg arrives as a zip; BtbN layout: ffmpeg-master-*/bin/{ffmpeg,ffprobe}.exe
            $zipDest = Join-Path $script:ScriptRoot "cache/ffmpeg_download.zip"
            $cacheDir = Join-Path $script:ScriptRoot "cache/ffmpeg_extract"

            Invoke-WebRequest -Uri $url -OutFile $zipDest -UseBasicParsing

            # Clean extract target to avoid stale trees (bug #5 fixed)
            if (Test-Path $cacheDir) { Remove-Item $cacheDir -Recurse -Force }
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
            Expand-Archive -Path $zipDest -DestinationPath $cacheDir -Force

            $innerBin = Get-ChildItem $cacheDir -Recurse -Filter "ffmpeg.exe" |
            Select-Object -First 1

            if (-not $innerBin) { throw "ffmpeg.exe not found inside the zip archive." }

            $ffBinDir = $innerBin.DirectoryName
            foreach ($exe in @('ffmpeg.exe', 'ffprobe.exe')) {
                $src = Join-Path $ffBinDir $exe
                if (Test-Path $src) {
                    Copy-Item $src $binDir -Force
                    Write-Log "INFO" "$exe installed → $binDir"
                }
            }

            Remove-Item $zipDest  -Force -ErrorAction SilentlyContinue
            Remove-Item $cacheDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "INFO" "FFmpeg installed successfully."
        }
    }
    catch {
        Write-Log "ERROR" "Failed to install $Name : $($_.Exception.Message)"
        throw
    }
}

function Install-Dependencies {
    if ($OfflineMode) {
        Write-Log "WARN" "Offline mode — skipping dependency check."
        return
    }

    Write-Log "INFO" "Checking dependencies..."

    foreach ($bin in @('yt-dlp', 'ffmpeg')) {
        if (-not (Find-Binary $bin)) {
            Write-Log "WARN" "$bin not found. Downloading..."
            Install-Binary -Name $bin
        }
        else {
            Write-Log "INFO" "$bin is present."
        }
    }

    Write-Log "INFO" "All dependencies ready."
}

#endregion

# ══════════════════════════════════════════════════════════════════════════════
#region  BANNER
# ══════════════════════════════════════════════════════════════════════════════

function Show-Banner {
    # Bug #9 fixed: reuse $script:Hardware; do NOT call Get-HardwareCapabilities again
    $hw = $script:Hardware

    $ytdlpPath = Find-Binary 'yt-dlp'
    $ffmpegPath = Find-Binary 'ffmpeg'
    $ytVer = if ($ytdlpPath) { Get-BinaryVersion $ytdlpPath  'yt-dlp' } else { 'not installed' }
    $ffVer = if ($ffmpegPath) { Get-BinaryVersion $ffmpegPath 'ffmpeg' } else { 'not installed' }

    # Bug #10 fixed: actual version strings shown
    $c = 'Cyan'; $w = 'White'; $y = 'Yellow'
    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════════════╗" -ForegroundColor $c
    Write-Host "  ║          M R .  R O B O T O  v$($script:Version)               ║" -ForegroundColor $c
    Write-Host "  ║      Autonomous Media Acquisition Agent               ║" -ForegroundColor $c
    Write-Host "  ╚═══════════════════════════════════════════════════════╝" -ForegroundColor $c
    Write-Host ""
    Write-Host "  System Information" -ForegroundColor $y
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ("  GPU      : {0}" -f $hw.GPU)           -ForegroundColor $w
    Write-Host ("  Encoder  : {0}" -f $hw.Encoder)       -ForegroundColor $w
    Write-Host ("  Arch     : {0}" -f $hw.Architecture)  -ForegroundColor $w
    Write-Host ("  yt-dlp   : {0}" -f $ytVer)            -ForegroundColor $w
    Write-Host ("  FFmpeg   : {0}" -f $ffVer)            -ForegroundColor $w
    $mode = if ($Url) { 'Direct' } else { 'Interactive' }
    Write-Host ("  Mode     : {0}" -f $mode) -ForegroundColor $w
    Write-Host ""
    Write-Host "  ──────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host -NoNewline '  '
    Show-Typewriter -Text 'Ready to acquire media.' -DelayMs 22 -Color 'Green'
    Write-Host ''
}

#endregion

# ══════════════════════════════════════════════════════════════════════════════
#region  STATE / RESUME
# ══════════════════════════════════════════════════════════════════════════════

function Save-DownloadState {
    param([hashtable]$Data)
    $statePath = Join-Path $script:ScriptRoot "state/session.json"
    try {
        $Data | ConvertTo-Json -Depth 5 | Set-Content $statePath -Encoding UTF8
        Write-Log "DEBUG" "State saved → $statePath"
    }
    catch {
        Write-Log "WARN" "Could not save state: $($_.Exception.Message)"
    }
}

function Get-DownloadState {
    $statePath = Join-Path $script:ScriptRoot "state/session.json"
    if (-not (Test-Path $statePath)) { return $null }
    try {
        return Get-Content $statePath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Log "WARN" "Could not read state file."
        return $null
    }
}

function Clear-DownloadState {
    $statePath = Join-Path $script:ScriptRoot "state/session.json"
    Remove-Item $statePath -Force -ErrorAction SilentlyContinue
}

#endregion

# ══════════════════════════════════════════════════════════════════════════════
#region  URL VALIDATION
# ══════════════════════════════════════════════════════════════════════════════

function Test-MediaUrl {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    if ($Url -notmatch '^https?://[^\s]+$') { return $false }
    # Reject non-http schemes sometimes smuggled in
    foreach ($bad in @('file://', 'javascript:', 'data:')) {
        if ($Url -like "*$bad*") { return $false }
    }
    return $true
}

#endregion

# ══════════════════════════════════════════════════════════════════════════════
#region  DOWNLOAD ORCHESTRATION
# ══════════════════════════════════════════════════════════════════════════════

function Start-MediaAcquisition {
    param(
        [Parameter(Mandatory)][string]$TargetUrl,
        # Bug #8 fixed: renamed from $Profile to avoid colliding with $Profile automatic variable
        [Parameter(Mandatory)][string]$QualityProfile
    )

    Write-Log "INFO" "Acquisition started — URL: $TargetUrl  Profile: $QualityProfile"

    $ytdlpPath = Find-Binary 'yt-dlp'
    $ffmpegPath = Find-Binary 'ffmpeg'

    if (-not $ytdlpPath) { Write-Log "ERROR" "yt-dlp not found. Run without -OfflineMode to auto-install."; return }
    if (-not $ffmpegPath) { Write-Log "ERROR" "ffmpeg not found. Run without -OfflineMode to auto-install."; return }

    # Access profile from config (ConvertFrom-Json returns PSCustomObject)
    $prof = $script:Config.profiles.$QualityProfile
    if (-not $prof) { Write-Log "ERROR" "Unknown profile: $QualityProfile"; return }

    $downloadDir = $script:DownloadDir  # set by Select-DownloadLocation
    $ffmpegDir = Split-Path $ffmpegPath -Parent

    # Save state before starting (resume support)
    $sessionId = Get-Date -Format "yyyyMMdd_HHmmss"
    Save-DownloadState @{
        sessionId = $sessionId
        url       = $TargetUrl
        profile   = $QualityProfile
        status    = "in_progress"
        timestamp = (Get-Date -Format "o")
    }

    # Detect audio-only mode (profile has audioOnly flag)
    $isAudioOnly = $prof.PSObject.Properties.Name -contains 'audioOnly' -and $prof.audioOnly

    # Build yt-dlp argument list
    $ytArgs = [System.Collections.Generic.List[string]]@(
        $TargetUrl,
        '--format', $prof.format,
        '--ffmpeg-location', $ffmpegDir,
        '--continue',
        '--progress',
        '--newline'
    )

    if ($isAudioOnly) {
        # Audio-only path: extract + convert, no video muxing
        $ytArgs.Add('--extract-audio')
        $ytArgs.Add('--audio-format'); $ytArgs.Add($prof.audioFormat)
        $ytArgs.Add('--audio-quality'); $ytArgs.Add($prof.audioQuality)
        $ytArgs.Add('--output'); $ytArgs.Add("$downloadDir/%(title)s.%(ext)s")
        Write-Log "INFO" "Audio-only mode: $($prof.audioFormat.ToUpper()) @ $($prof.audioQuality)"
    }
    else {
        # Video path: merge streams into chosen container
        $ytArgs.Add('--output'); $ytArgs.Add("$downloadDir/%(title)s.%(ext)s")
        $ytArgs.Add('--merge-output-format'); $ytArgs.Add($prof.container)
        # Hardware acceleration (skip for software fallback)
        if ($script:Hardware.Encoder -ne 'libx264') {
            $ytArgs.Add('--postprocessor-args')
            $ytArgs.Add("ffmpeg:-c:v $($script:Hardware.Encoder)")
            Write-Log "INFO" "Using HW encoder: $($script:Hardware.Encoder)"
        }
    }

    Write-Host ''
    Write-Host "  ▶ Downloading..." -ForegroundColor Green
    Write-Host "    Profile  : $QualityProfile ($($prof.description))" -ForegroundColor DarkGray
    Write-Host "    Output   : $downloadDir" -ForegroundColor DarkGray
    Write-Host ''

    try {
        & $ytdlpPath @ytArgs
        if ($LASTEXITCODE -ne 0) { throw "yt-dlp exited with code $LASTEXITCODE" }
        Write-Log "INFO" "Download completed successfully."
        Write-Host ""
        Write-Host "  ✔ Download complete!" -ForegroundColor Green
        Clear-DownloadState
    }
    catch {
        Write-Log "ERROR" "Download failed: $($_.Exception.Message)"
        # State file left intact so the user can resume
        Write-Host ""
        Write-Host "  ✘ Download failed. State saved for resume. Check logs for details." -ForegroundColor Red
    }
}

#endregion

# ══════════════════════════════════════════════════════════════════════════════
#region  DOWNLOAD LOCATION
# ══════════════════════════════════════════════════════════════════════════════

function Select-DownloadLocation {
    <#
    Determines where downloaded files will land.
    Audio profiles → OS Music folder; video profiles → OS Videos folder.
    User can override with a custom path at the prompt.
    Sets $script:DownloadDir which Start-MediaAcquisition reads.
    #>
    param([Parameter(Mandatory)][string]$QualityProfile)

    $isAudio = $QualityProfile -like 'audio-*'

    if ($isAudio) {
        $nativeDir = [Environment]::GetFolderPath('MyMusic')
        $label = 'Music'
    }
    else {
        $nativeDir = [Environment]::GetFolderPath('MyVideos')
        $label = 'Videos'
    }

    # Fallback to local /downloads if the OS shell folder is unavailable
    if ([string]::IsNullOrWhiteSpace($nativeDir)) {
        $nativeDir = Join-Path $script:ScriptRoot 'downloads'
    }

    Write-Host ''
    Write-Host ("  Default save location ({0}): {1}" -f $label, $nativeDir) -ForegroundColor DarkGray
    Write-Host '  Press Enter to accept, or type a custom path:' -ForegroundColor DarkGray
    $custom = (Read-Host '  Path').Trim()

    if (-not [string]::IsNullOrWhiteSpace($custom)) { $nativeDir = $custom }

    # Create the directory if it doesn't already exist
    if (-not (Test-Path $nativeDir)) {
        try {
            New-Item -ItemType Directory -Path $nativeDir -Force | Out-Null
            Write-Log 'INFO' "Created download directory: $nativeDir"
        }
        catch {
            Write-Log 'WARN' "Could not create '$nativeDir' — falling back to local downloads folder."
            $nativeDir = Join-Path $script:ScriptRoot 'downloads'
        }
    }

    $script:DownloadDir = $nativeDir
    Write-Log 'INFO' "Download location set: $script:DownloadDir"
}

#endregion

# ══════════════════════════════════════════════════════════════════════════════
#region  INTERACTIVE MODE
# ══════════════════════════════════════════════════════════════════════════════

function Start-InteractiveMode {
    # Check for interrupted session
    $state = Get-DownloadState
    if ($state -and $state.status -eq "in_progress") {
        Write-Host ""
        Write-Host "  ⚠ Interrupted download detected:" -ForegroundColor Yellow
        Write-Host "    URL     : $($state.url)" -ForegroundColor White
        Write-Host "    Profile : $($state.profile)" -ForegroundColor White
        $ans = Read-Host "  Resume this download? [Y/N]"
        if ($ans -match '^[Yy]') {
            Start-MediaAcquisition -TargetUrl $state.url -QualityProfile $state.profile
        }
        else {
            Clear-DownloadState
        }
    }

    while ($true) {
        Write-Host ""
        Write-Host "  ┌─────────────────────────────────────────────────────────┐" -ForegroundColor DarkGray
        Write-Host "  │  Mr. Roboto — Acquisition Mode                          │" -ForegroundColor Cyan
        Write-Host "  ├─────────────────────────────────────────────────────────┤" -ForegroundColor DarkGray
        Write-Host "  │  VIDEO                                                  │" -ForegroundColor DarkGray
        Write-Host "  │  [1] Ultra   4K MKV     (maximum quality)               │" -ForegroundColor White
        Write-Host "  │  [2] High    1080p MP4  (recommended)                   │" -ForegroundColor Green
        Write-Host "  │  [3] Mobile  720p MP4   (compact, portable)             │" -ForegroundColor Yellow
        Write-Host "  ├─────────────────────────────────────────────────────────┤" -ForegroundColor DarkGray
        Write-Host "  │  AUDIO ONLY                                             │" -ForegroundColor DarkGray
        Write-Host "  │  [4] FLAC    Lossless archive  (archival grade)          │" -ForegroundColor Magenta
        Write-Host "  │  [5] Opus    Hi-Fi native      (bit-perfect, smallest)  │" -ForegroundColor Cyan
        Write-Host "  │  [6] MP3     320 kbps          (universal compatibility) │" -ForegroundColor Blue
        Write-Host "  ├─────────────────────────────────────────────────────────┤" -ForegroundColor DarkGray
        Write-Host "  │  [Q] Quit                                               │" -ForegroundColor Red
        Write-Host "  └─────────────────────────────────────────────────────────┘" -ForegroundColor DarkGray
        Write-Host ""

        $choice = (Read-Host "  Choice").Trim().ToUpper()

        $selectedProfile = switch ($choice) {
            '1' { 'ultra' }
            'U' { 'ultra' }
            '2' { 'high' }
            'H' { 'high' }
            '3' { 'mobile' }
            'M' { 'mobile' }
            '4' { 'audio-flac' }
            'F' { 'audio-flac' }
            '5' { 'audio-opus' }
            'O' { 'audio-opus' }
            '6' { 'audio-mp3' }
            'P' { 'audio-mp3' }
            'Q' { Write-Host "  Goodbye.`n" -ForegroundColor Cyan; return }
            default {
                Write-Host "  Invalid choice — try again." -ForegroundColor Red
                $null
            }
        }

        if (-not $selectedProfile) { continue }

        $inputUrl = (Read-Host "`n  Enter media URL").Trim()

        if (-not (Test-MediaUrl $inputUrl)) {
            Write-Host '  Invalid URL. Must start with http:// or https://' -ForegroundColor Red
            continue
        }

        # Ask where to save (audio defaults to Music, video to Videos)
        Select-DownloadLocation -QualityProfile $selectedProfile

        Start-MediaAcquisition -TargetUrl $inputUrl -QualityProfile $selectedProfile

        Write-Host ""
        $again = (Read-Host "  Download another? [Y/N]").Trim().ToUpper()
        if ($again -ne 'Y') {
            Write-Host "  Goodbye.`n" -ForegroundColor Cyan
            break
        }
    }
}

#endregion

# ══════════════════════════════════════════════════════════════════════════════
#region  MAIN ENTRY POINT
# ══════════════════════════════════════════════════════════════════════════════

function Main {
    try {
        Initialize-Environment
        Show-Spinner -Message 'Checking dependencies...' -Seconds 1
        Install-Dependencies
        $script:Hardware = Get-HardwareCapabilities
        Show-Banner
        
        if ($Url) {
            if (-not (Test-MediaUrl $Url)) {
                Write-Log "ERROR" "Invalid URL supplied via -Url parameter."
                exit 1
            }
            Select-DownloadLocation -QualityProfile $Profile
            Start-MediaAcquisition -TargetUrl $Url -QualityProfile $Profile
        }
        else {
            Start-InteractiveMode
        }

        Write-Log "INFO" "Session ended."
    }
    catch {
        Write-Log "ERROR" "Fatal: $($_.Exception.Message)"
        Write-Host "`n  FATAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Check logs at: $script:LogPath`n"       -ForegroundColor Yellow
        exit 1
    }
}

Main

#endregion
