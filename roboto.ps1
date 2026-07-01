#Requires -Version 5.1
<#
.SYNOPSIS
    Mr. Roboto v2.0 - Portable PowerShell media downloader

.DESCRIPTION
    A portable PowerShell script that downloads media via yt-dlp and FFmpeg,
    with GPU encoder detection, stream-copy muxing, resume support, and session logging.

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

# Polyfill $IsWindows / $IsLinux / $IsMacOS for PowerShell 5.1 (Windows-only runtime)
if ($null -eq (Get-Variable 'IsWindows' -ErrorAction SilentlyContinue)) {
    New-Variable -Name IsWindows -Value $true  -Scope Script -Force
    New-Variable -Name IsLinux   -Value $false -Scope Script -Force
    New-Variable -Name IsMacOS   -Value $false -Scope Script -Force
}

#  Force TLS 1.2 (TLS 1.3 enum absent on PS5.1/.NET 4.x - bug #6 fixed)
#  Not needed on Linux/.NET 6+ which negotiates TLS natively.
if ($IsWindows) {
    try {
        [Net.ServicePointManager]::SecurityProtocol =
        [Net.SecurityProtocolType]::Tls12 -bor
        [Net.SecurityProtocolType]::Tls11 -bor
        [Net.SecurityProtocolType]::Tls
        $tls13 = [Net.SecurityProtocolType]::Tls13
        [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor $tls13
    }
    catch { <# Tls13 not available on this runtime - harmless #> }
}

#  Script-level state 
enum DownloadMode {
    Public
    EscalatedAuth
    TransientFailure
}
$script:DownloadMode = [DownloadMode]::Public
$script:Version = "2.0.0"
$script:ScriptRoot = $PSScriptRoot
$script:ConfigPath = Join-Path $ScriptRoot "config.json"
$script:LogPath = Join-Path $ScriptRoot "logs"
$script:LogFile = $null
$script:Config = $null
$script:Hardware = $null   # cached once; Show-Banner reuses this
$script:DownloadDir = $null   # set once per session via Select-DownloadLocation

# 
#region  ANIMATIONS
# 

function Show-Typewriter {
    <# Prints $Text one character at a time. Lightweight - no threads. #>
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
    Single-threaded - uses carriage-return overwrite. Safe, no jobs.
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
    Write-Host "`r  [OK] $Message" -ForegroundColor Green
}

#endregion

# 
#region  LOGGING
# 

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

# 
#region  ENVIRONMENT INIT
# 

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
            #  Audio-only profiles 
            # YouTube sources are lossy (Opus/AAC). These profiles give you
            # the best possible extraction at each fidelity/size trade-off.
            "audio-flac" = [ordered]@{
                format       = "bestaudio"
                container    = "flac"
                audioOnly    = $true
                audioFormat  = "flac"
                audioQuality = "0"
                description  = "Lossless Archive - best source to FLAC (archival grade)"
            }
            "audio-opus" = [ordered]@{
                format       = "bestaudio[ext=webm]/bestaudio"
                container    = "opus"
                audioOnly    = $true
                audioFormat  = "opus"
                audioQuality = "0"
                description  = "High-Fidelity - Opus native, zero re-encode (bit-perfect source)"
            }
            "audio-mp3"  = [ordered]@{
                format       = "bestaudio"
                container    = "mp3"
                audioOnly    = $true
                audioFormat  = "mp3"
                audioQuality = "320K"
                description  = "Universal - MP3 320kbps (maximum device compatibility)"
            }
        }
        # Use quoted key access to survive ConvertFrom-Json round-trips
        binaries = [ordered]@{
            "yt-dlp" = [ordered]@{
                x64           = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
                x86           = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_x86.exe"
                "linux-x64"   = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux"
                "linux-arm64" = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux_aarch64"
            }
            ffmpeg   = [ordered]@{
                x64           = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
                x86           = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win32-gpl.zip"
                "linux-x64"   = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz"
                "linux-arm64" = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linuxarm64-gpl.tar.xz"
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

# 
#region  HARDWARE DETECTION
#

function Get-ArchInfo {
    <# Returns @{ Arch = 'x64'; ConfigKey = 'x64' } on Windows,
       @{ Arch = 'x64'; ConfigKey = 'linux-x64' } on Linux, etc. #>
    if ($IsMacOS) {
        throw "macOS is not supported yet because no macOS binaries are configured."
    }
    if ($IsLinux) {
        $cpu = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString().ToLower()
        return @{ Arch = $cpu; ConfigKey = "linux-$cpu" }
    }
    $a = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
    return @{ Arch = $a; ConfigKey = $a }
}

function Get-HardwareCapabilities {
    Write-Log "INFO" "Detecting hardware..."
    $arch = (Get-ArchInfo).Arch

    $gpuName = "None (Software)"
    $encoder = "libx264"

    if ($IsWindows) {
        try {
            $allGpus = Get-CimInstance Win32_VideoController -ErrorAction Stop |
            Where-Object { $_.Name -notlike "*Microsoft*" -and $_.Name -notlike "*Remote*" }

            # Prefer discrete GPUs: NVIDIA > AMD > Intel iGPU > first available
            $gpu = $allGpus | Where-Object { $_.Name -match "NVIDIA|GeForce|GTX|RTX|Quadro" } | Select-Object -First 1
            if (-not $gpu) { $gpu = $allGpus | Where-Object { $_.Name -match "AMD|Radeon|RX " }   | Select-Object -First 1 }
            if (-not $gpu) { $gpu = $allGpus | Select-Object -First 1 }

            if ($gpu) {
                $gpuName = $gpu.Name
                $encoder = if     ($gpuName -match "NVIDIA|GeForce|GTX|RTX|Quadro") { "h264_nvenc" }
                           elseif ($gpuName -match "AMD|Radeon|RX ")                { "h264_amf"   }
                           elseif ($gpuName -match "Intel|HD Graphics|UHD|Iris")    { "h264_qsv"   }
                           else                                                      { "libx264"    }
                Write-Log "INFO" "GPU: $gpuName  Encoder: $encoder"
            }
            else {
                Write-Log "WARN" "No dedicated GPU found; falling back to libx264."
            }
        }
        catch {
            $gpuName = "Detection Failed"
            Write-Log "WARN" "GPU query error: $($_.Exception.Message)"
        }
    }
    elseif ($IsLinux) {
        # NVIDIA: nvidia-smi is the most reliable source
        $nvSmi = Get-Command 'nvidia-smi' -ErrorAction SilentlyContinue
        if ($nvSmi) {
            $detected = & nvidia-smi --query-gpu=name --format=csv,noheader 2>$null | Select-Object -First 1
            if ($null -ne $detected) { $detected = $detected.Trim() }
            $gpuName  = if ($detected) { $detected } else { 'NVIDIA GPU' }
            $encoder  = 'h264_nvenc'
            Write-Log "INFO" "NVIDIA GPU detected via nvidia-smi: $gpuName"
        }
        else {
            # Fallback: parse lspci for VGA/3D/Display controllers
            $lspci = Get-Command 'lspci' -ErrorAction SilentlyContinue
            if ($lspci) {
                $vgaMatch = & lspci 2>$null | Select-String -Pattern 'VGA|3D|Display' | Select-Object -First 1
                $vgaLine = if ($null -ne $vgaMatch) { $vgaMatch.ToString() } else { $null }
                if ($vgaLine) {
                    $gpuName = if ($vgaLine -match ':\s+(.+)$') { $matches[1].Trim() } else { $vgaLine.Trim() }
                    $encoder = if     ($vgaLine -match 'NVIDIA|GeForce|GTX|RTX|Quadro') { 'h264_nvenc' }
                               elseif ($vgaLine -match 'AMD|Radeon|ATI')                { 'h264_vaapi' }
                               elseif ($vgaLine -match 'Intel')                         { 'h264_qsv'   }
                               else                                                      { 'libx264'    }
                    Write-Log "INFO" "GPU (lspci): $gpuName  Encoder: $encoder"
                }
                else {
                    Write-Log "WARN" "No VGA/Display device found in lspci; falling back to libx264."
                }
            }
            else {
                Write-Log "WARN" "lspci not found; GPU detection skipped. Falling back to libx264."
            }
        }
    }

    return @{ GPU = $gpuName; Encoder = $encoder; Architecture = $arch }
}

#endregion

# 
#region  BINARY MANAGEMENT
# 

function Find-Binary {
    param([Parameter(Mandatory)][string]$Name)

    $arch = (Get-ArchInfo).Arch
    $ext  = if ($IsWindows) { '.exe' } else { '' }
    $localPath = Join-Path $script:ScriptRoot "bin/$arch/$Name$ext"

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

    $archInfo  = Get-ArchInfo
    $binDir    = Join-Path $script:ScriptRoot "bin/$($archInfo.Arch)"
    $configKey = $archInfo.ConfigKey

    $url = $script:Config.binaries."$Name"."$configKey"

    if (-not $url) {
        Write-Log "ERROR" "No download URL found for $Name ($configKey) in config.json."
        throw "Missing URL for $Name"
    }

    Write-Log "INFO" "Downloading $Name from $url ..."

    try {
        if ($Name -eq 'yt-dlp') {
            $ext  = if ($IsWindows) { '.exe' } else { '' }
            $dest = Join-Path $binDir "yt-dlp$ext"
            Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
            if (-not $IsWindows) { & chmod +x $dest }
            Write-Log "INFO" "yt-dlp installed  $dest"
        }
        else {
            $cacheDir = Join-Path $script:ScriptRoot "cache/ffmpeg_extract"
            if (Test-Path $cacheDir) { Remove-Item $cacheDir -Recurse -Force }
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null

            if ($IsWindows) {
                # Windows: BtbN zip  →  ffmpeg-master-*/bin/{ffmpeg,ffprobe}.exe
                $archiveDest = Join-Path $script:ScriptRoot "cache/ffmpeg_download.zip"
                Invoke-WebRequest -Uri $url -OutFile $archiveDest -UseBasicParsing
                Expand-Archive -Path $archiveDest -DestinationPath $cacheDir -Force

                $innerBin = Get-ChildItem $cacheDir -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1
                if (-not $innerBin) { throw "ffmpeg.exe not found inside the zip archive." }
                $ffBinDir = $innerBin.DirectoryName
                foreach ($exe in @('ffmpeg.exe', 'ffprobe.exe')) {
                    $src = Join-Path $ffBinDir $exe
                    if (Test-Path $src) { Copy-Item $src $binDir -Force; Write-Log "INFO" "$exe installed  $binDir" }
                }
                Remove-Item $archiveDest -Force -ErrorAction SilentlyContinue
            }
            else {
                # Linux: BtbN tar.xz  →  ffmpeg-master-*/bin/{ffmpeg,ffprobe}
                $archiveDest = Join-Path $script:ScriptRoot "cache/ffmpeg_download.tar.xz"
                Invoke-WebRequest -Uri $url -OutFile $archiveDest -UseBasicParsing
                & tar -xJf $archiveDest -C $cacheDir

                $innerBin = Get-ChildItem $cacheDir -Recurse -Filter "ffmpeg" |
                            Where-Object { -not $_.PSIsContainer } | Select-Object -First 1
                if (-not $innerBin) { throw "ffmpeg binary not found inside the tar archive." }
                $ffBinDir = $innerBin.DirectoryName
                foreach ($bin in @('ffmpeg', 'ffprobe')) {
                    $src = Join-Path $ffBinDir $bin
                    if (Test-Path $src) {
                        Copy-Item $src $binDir -Force
                        & chmod +x (Join-Path $binDir $bin)
                        Write-Log "INFO" "$bin installed  $binDir"
                    }
                }
                Remove-Item $archiveDest -Force -ErrorAction SilentlyContinue
            }

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
        Write-Log "WARN" "Offline mode - skipping dependency check."
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

    # JS runtime check - yt-dlp requires Deno (or Node/PhantomJS) for full format
    # extraction. Without it some formats are silently missing and a WARNING fires
    # mid-download. Deno is the only runtime enabled by default in recent yt-dlp.
    $denoPath = Get-Command 'deno' -ErrorAction SilentlyContinue
    if ($denoPath) {
        $denoVer = (& $denoPath.Source --version 2>$null | Select-Object -First 1) -replace 'deno ','' 
        Write-Log "INFO" "Deno JS runtime: $denoVer"
    }
    else {
        Write-Log "WARN" "Deno JS runtime not found. Some YouTube formats may be missing."
        Write-Host ''
        Write-Host '  [WARN] Deno runtime not detected.' -ForegroundColor Yellow
        Write-Host '  yt-dlp uses Deno for JavaScript extraction. Without it,' -ForegroundColor DarkYellow
        Write-Host '  some formats are silently skipped and quality may degrade.' -ForegroundColor DarkYellow
        $denoHint = if ($IsWindows) { 'winget install DenoLand.Deno' } else { 'curl -fsSL https://deno.land/install.sh | sh' }
        Write-Host "  Install: $denoHint  (then restart this terminal)" -ForegroundColor Cyan
        Write-Host ''
    }

    Write-Log "INFO" "All dependencies ready."
}

#endregion

# 
#region  BANNER
# 

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
    Write-Host "  +=========================================================+" -ForegroundColor $c
    Write-Host "  |          M R .  R O B O T O  v$($script:Version)               |" -ForegroundColor $c
    Write-Host "  |      Portable Media Downloader                      |" -ForegroundColor $c
    Write-Host "  +=========================================================+" -ForegroundColor $c
    Write-Host ""
    Write-Host "  System Information" -ForegroundColor $y
    Write-Host "  -----------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ("  GPU      : {0}" -f $hw.GPU)           -ForegroundColor $w
    Write-Host ("  Encoder  : {0}" -f $hw.Encoder)       -ForegroundColor $w
    Write-Host ("  Arch     : {0}" -f $hw.Architecture)  -ForegroundColor $w
    Write-Host ("  yt-dlp   : {0}" -f $ytVer)            -ForegroundColor $w
    Write-Host ("  FFmpeg   : {0}" -f $ffVer)            -ForegroundColor $w
    $mode = if ($Url) { 'Direct' } else { 'Interactive' }
    Write-Host ("  Mode     : {0}" -f $mode) -ForegroundColor $w
    Write-Host ""
    Write-Host "  -----------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host -NoNewline '  '
    Show-Typewriter -Text 'Ready to download.' -DelayMs 22 -Color 'Green'
    Write-Host ''
}

#endregion

# 
#region  STATE / RESUME
# 

function Save-DownloadState {
    param([hashtable]$Data)
    $statePath = Join-Path $script:ScriptRoot "state/session.json"
    try {
        $Data | ConvertTo-Json -Depth 5 | Set-Content $statePath -Encoding UTF8
        Write-Log "DEBUG" "State saved  $statePath"
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

function Show-DownloadHistory {
    $historyFile = Join-Path $script:ScriptRoot "state/download_history.json"

    if (-not (Test-Path $historyFile)) {
        Write-Host "`n  No downloads yet.`n" -ForegroundColor Yellow
        return
    }

    try {
        $history = Get-Content $historyFile -Raw | ConvertFrom-Json
        if ($history -isnot [array]) { $history = @($history) }

        Write-Host "`n=== Previous Downloads ===`n" -ForegroundColor Cyan

        $history | ForEach-Object {
            $t = if ([string]::IsNullOrWhiteSpace($_.title)) { "Unknown Title" } else { $_.title }
            Write-Host "• $t" -ForegroundColor Cyan
            Write-Host "  $($_.time) | $($_.profile)" -ForegroundColor DarkGray
            Write-Host "  $($_.url)`n" -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Host "`n  Failed to read history.`n" -ForegroundColor Red
    }
}

#endregion

# 
#region  URL VALIDATION
# 

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

function Get-FailureType {
    param(
        [int]$ExitCode,
        [string]$Output,
        [string]$Url
    )

    if ($ExitCode -eq 0) { return "Success" }
    if ([string]::IsNullOrWhiteSpace($Output)) { return "Unknown" }

    # Step 1: Check HTTP layer hints (403/401/429)
    if ($Output -match "HTTP Error 429") { return "Transient" }
    if ($Output -match "HTTP Error 401|HTTP Error 403") { return "Auth" }

    # Step 2: Check extractor message patterns
    $authSignatures = @(
        "Sign in to confirm",
        "requires authentication",
        "private video"
    )

    $transientSignatures = @(
        "extract error",
        "NameResolutionFailure",
        "timeout",
        "Connection refused"
    )

    foreach ($sig in $authSignatures) {
        if ($Output -match "(?i)$sig") { return "Auth" }
    }

    foreach ($sig in $transientSignatures) {
        if ($Output -match "(?i)$sig") { return "Transient" }
    }

    # Step 3: Confirm with context (e.g., if exit code is 1 and URL has auth hints)
    if ($ExitCode -eq 1 -and $Url -match "(?i)members|premium|age|private") {
        return "Auth"
    }

    return "Unknown"
}

#endregion

#
#region  DOWNLOAD ORCHESTRATION
#

function Get-DefaultCookieBrowser {
    <# Returns the first available browser name for --cookies-from-browser, or $null. #>
    if ($IsWindows) { return 'edge' }
    foreach ($b in @('firefox', 'chrome', 'chromium', 'brave', 'vivaldi', 'opera')) {
        if (Get-Command $b -ErrorAction SilentlyContinue) { return $b }
    }
    return $null
}

function Start-MediaAcquisition {
    param(
        [Parameter(Mandatory)][string]$TargetUrl,
        # Bug #8 fixed: renamed from $Profile to avoid colliding with $Profile automatic variable
        [Parameter(Mandatory)][string]$QualityProfile
    )

    Write-Log "INFO" "Acquisition started - URL: $TargetUrl  Profile: $QualityProfile"

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
        sessionId   = $sessionId
        url         = $TargetUrl
        profile     = $QualityProfile
        downloadDir = $downloadDir
        status      = "in_progress"
        timestamp   = (Get-Date -Format "o")
    }

    # Detect audio-only mode (profile has audioOnly flag)
    $isAudioOnly = $prof.PSObject.Properties.Name -contains 'audioOnly' -and $prof.audioOnly

    # Build yt-dlp core argument list
    $coreArgs = [System.Collections.Generic.List[string]]@(
        $TargetUrl,
        '--format', $prof.format,
        '--ffmpeg-location', $ffmpegDir,
        '--no-part',
        '--continue',
        '--progress',
        '--newline'
    )

    if ($isAudioOnly) {
        # Audio-only path: extract + convert, no video muxing
        $coreArgs.Add('--extract-audio')
        $coreArgs.Add('--audio-format'); $coreArgs.Add($prof.audioFormat)
        $coreArgs.Add('--audio-quality'); $coreArgs.Add($prof.audioQuality)
        $coreArgs.Add('--output'); $coreArgs.Add("$downloadDir/%(title)s.%(ext)s")
        Write-Log "INFO" "Audio-only mode: $($prof.audioFormat.ToUpper()) @ $($prof.audioQuality)"
    }
    else {
        # Video path: merge streams into chosen container
        $coreArgs.Add('--output'); $coreArgs.Add("$downloadDir/%(title)s.%(ext)s")
        $coreArgs.Add('--merge-output-format'); $coreArgs.Add($prof.container)
        # Stream-copy: mux without re-encoding to preserve original codec quality
        if ($script:Hardware.Encoder -ne 'libx264') {
            $coreArgs.Add('--postprocessor-args')
            $coreArgs.Add("merger+ffmpeg:-c copy")
            Write-Log "INFO" "Stream-copy mode (no re-encode). HW encoder available: $($script:Hardware.Encoder)"
        }
    }

    # Media enrichment - thumbnails and metadata (all profiles)
    $coreArgs.AddRange([string[]]@(
            '--embed-thumbnail',
            '--embed-metadata'
        ))

    # Playlist interceptor - default to single video, prompt only when needed
    $playlistFlag = '--no-playlist'
    if ($TargetUrl -match 'list=') {
        Write-Host ""
        Write-Host "  WARNING: Playlist detected in URL." -ForegroundColor Yellow
        Write-Host "  Generating preview..." -ForegroundColor DarkGray

        $peekArgs = @(
            "--flat-playlist",
            "--playlist-end", "5",
            "--print", "%(playlist_index)s: %(title)s",
            $TargetUrl
        )
        try {
            $peek = & $ytdlpPath @peekArgs 2>$null
            if ($peek) {
                Write-Host ""
                Write-Host "  Playlist preview (first 5):" -ForegroundColor Cyan
                $peek | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
            }
        }
        catch {
            Write-Host "  Preview unavailable." -ForegroundColor DarkGray
        }

        Write-Host ""
        Write-Host "  [1] Single video (recommended)" -ForegroundColor Green
        Write-Host "  [2] Full playlist" -ForegroundColor Yellow
        Write-Host ""
        $plChoice = (Read-Host "  Choice [1]").Trim()
        if ($plChoice -eq '2') {
            $playlistFlag = '--yes-playlist'
            Write-Log "INFO" "Playlist mode enabled by user."
            Write-Host "  Playlist mode enabled." -ForegroundColor Cyan
        }
        else {
            Write-Log "INFO" "Single video mode enforced (playlist URL)."
            Write-Host "  Single video mode enforced." -ForegroundColor Cyan
        }
        Write-Host ""
    }
    $coreArgs.Add($playlistFlag)

    # Pre-build decoupled argument pipelines
    $publicArgs = New-Object System.Collections.Generic.List[string]
    $publicArgs.AddRange($coreArgs)
    $publicArgs.Add('--no-cookies')

    $cookieBrowser = Get-DefaultCookieBrowser
    $authArgs = New-Object System.Collections.Generic.List[string]
    $authArgs.AddRange($coreArgs)
    if ($cookieBrowser) {
        $authArgs.Add('--cookies-from-browser')
        $authArgs.Add($cookieBrowser)
    }

    # Start unconditionally in Public Mode
    $script:DownloadMode = [DownloadMode]::Public
    $maxAttempts = 3
    $attempt = 1
    $success = $false

    while ($attempt -le $maxAttempts -and -not $success) {
        $color = switch ($script:DownloadMode) {
            'Public' { 'Green' }
            'EscalatedAuth' { 'Red' }
            'TransientFailure' { 'Magenta' }
            default { 'Cyan' }
        }

        Write-Host ''
        Write-Host "  - Downloading (Attempt $attempt/$maxAttempts)..." -ForegroundColor $color
        Write-Host "    Mode     : $($script:DownloadMode)" -ForegroundColor $color
        Write-Host "    Profile  : $QualityProfile ($($prof.description))" -ForegroundColor DarkGray
        Write-Host "    Output   : $downloadDir" -ForegroundColor DarkGray
        Write-Host ''

        $activeArgs = if ($script:DownloadMode -eq [DownloadMode]::EscalatedAuth) { $authArgs } else { $publicArgs }

        try {
            $errCapture = ""
            $outCapture = ""
            & $ytdlpPath @activeArgs 2>&1 | ForEach-Object {
                $line = $_.ToString()
                $outCapture += $line + "`n"
                if     ($line -match '^\[download\]') { Write-Host "  $line" }
                elseif ($line -match '^ERROR:')       { $errCapture += $line + "`n" }
            }
            $exitCode = $LASTEXITCODE

            if ($exitCode -eq 0) {
                $title = $TargetUrl
                if ($outCapture -match 'Destination:\s*.*[\\/]([^\\/]+)\.\w+$') {
                    $title = $matches[1]
                }
                elseif ($outCapture -match 'Adding metadata to\s*".*[\\/]([^\\/]+)\.\w+"') {
                    $title = $matches[1]
                }

                Write-Log "INFO" "Download completed successfully."
                Write-Host "`n   Download complete!" -ForegroundColor Green

                $historyFile = Join-Path $script:ScriptRoot "state/download_history.json"
                $record = [PSCustomObject]@{
                    title   = $title
                    url     = $TargetUrl
                    profile = $QualityProfile
                    path    = $downloadDir
                    time    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    status  = "completed"
                }

                $history = @()
                if (Test-Path $historyFile) {
                    try {
                        $parsed = Get-Content $historyFile -Raw | ConvertFrom-Json
                        if ($parsed -isnot [array]) { $history = @($parsed) } else { $history = $parsed }
                    }
                    catch {}
                }
                $history += $record
                try {
                    $history | ConvertTo-Json -Depth 5 | Set-Content $historyFile -Encoding UTF8
                }
                catch { Write-Log "WARN" "Failed to write download history." }

                Clear-DownloadState
                $success = $true
                break
            }

            # If we reached here, execution failed
            Write-Log "WARN" "yt-dlp exited with code $exitCode."
            $failType = Get-FailureType -ExitCode $exitCode -Output $errCapture -Url $TargetUrl
            Write-Log "WARN" "Failure classified as: $failType"

            if ($failType -eq "Auth") {
                if ($cookieBrowser) {
                    Write-Host "  Sign-in required. Escalating to $cookieBrowser cookies..." -ForegroundColor Yellow
                    $script:DownloadMode = [DownloadMode]::EscalatedAuth
                }
                else {
                    Write-Host "  Sign-in required but no supported browser found for cookie auth." -ForegroundColor Red
                    Write-Host "  Install Firefox or Chrome, then retry." -ForegroundColor Yellow
                    break
                }
            }
            elseif ($failType -eq "Transient") {
                Write-Host "  Network issue. Retrying in 5s..." -ForegroundColor Magenta
                $script:DownloadMode = [DownloadMode]::TransientFailure
                Start-Sleep -Seconds 5
            }
            else {
                Write-Host "  Download failed - see logs/ for details." -ForegroundColor Red
                break
            }
        }
        catch {
            Write-Log "ERROR" "Execution error: $($_.Exception.Message)"
            break
        }
        $attempt++
    }

    if (-not $success) {
        Write-Log "ERROR" "Download failed after $attempt attempts."
        Write-Host "`n   Download failed. State saved for resume. Check logs for details." -ForegroundColor Red
    }
}

#endregion



# 
#region  DOWNLOAD LOCATION
# 

function Select-DownloadLocation {
    <#
    Determines where downloaded files will land.
    Audio profiles -> OS Music folder; video profiles -> OS Videos folder.
    User can override with a custom path at the prompt.
    Sets $script:DownloadDir which Start-MediaAcquisition reads.
    #>
    param([Parameter(Mandatory)][string]$QualityProfile)

    $isAudio = $QualityProfile -like 'audio-*'
    $label   = if ($isAudio) { 'Music' } else { 'Videos' }

    if ($IsWindows) {
        $nativeDir = if ($isAudio) {
            [Environment]::GetFolderPath('MyMusic')
        } else {
            [Environment]::GetFolderPath('MyVideos')
        }
    }
    else {
        # Linux/macOS: prefer XDG user dirs, fall back to ~/Music or ~/Videos
        $xdgKey    = if ($isAudio) { 'MUSIC' } else { 'VIDEOS' }
        $xdgResult = try { (& xdg-user-dir $xdgKey 2>$null).Trim() } catch { '' }
        $nativeDir = if (-not [string]::IsNullOrWhiteSpace($xdgResult)) {
            $xdgResult
        } else {
            Join-Path $HOME (if ($isAudio) { 'Music' } else { 'Videos' })
        }
    }

    # Fallback to local /downloads if still empty
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
            Write-Log 'WARN' "Could not create '$nativeDir' - falling back to local downloads folder."
            $nativeDir = Join-Path $script:ScriptRoot 'downloads'
        }
    }

    $script:DownloadDir = $nativeDir
    Write-Log 'INFO' "Download location set: $script:DownloadDir"
}

#endregion

# 
#region  INTERACTIVE MODE
# 

function Start-InteractiveMode {
    # Check for interrupted session; discard stale state (>2h) to avoid spurious prompts
    $state = Get-DownloadState
    if ($state -and $state.status -eq 'in_progress') {
        if (((Get-Date) - [datetime]$state.timestamp).TotalHours -gt 2) {
            Clear-DownloadState; $state = $null
        }
    }
    if ($state -and $state.status -eq "in_progress") {
        Write-Host ""
        Write-Host "   Interrupted download detected:" -ForegroundColor Yellow
        Write-Host "    URL     : $($state.url)" -ForegroundColor White
        Write-Host "    Profile : $($state.profile)" -ForegroundColor White
        $ans = Read-Host "  Resume this download? [Y/N]"
        if ($ans -match '^[Yy]') {
            # Restore download directory from state; fall back to Select-DownloadLocation if missing
            if (-not [string]::IsNullOrWhiteSpace($state.downloadDir)) {
                $script:DownloadDir = $state.downloadDir
                Write-Log 'INFO' "Restored download directory from state: $script:DownloadDir"
            }
            else {
                Select-DownloadLocation -QualityProfile $state.profile
            }
            Start-MediaAcquisition -TargetUrl $state.url -QualityProfile $state.profile
        }
        else {
            Clear-DownloadState
        }
    }

    while ($true) {
        Write-Host ""
        Write-Host "  +-----------------------------------------------------------+" -ForegroundColor DarkGray
        Write-Host "  |  Mr. Roboto - Acquisition Mode                          |" -ForegroundColor Cyan
        Write-Host "  +-----------------------------------------------------------+" -ForegroundColor DarkGray
        Write-Host "  |  VIDEO                                                  |" -ForegroundColor DarkGray
        Write-Host "  |  [1] Ultra   4K MKV     (maximum quality)               |" -ForegroundColor White
        Write-Host "  |  [2] High    1080p MP4  (recommended)                   |" -ForegroundColor Green
        Write-Host "  |  [3] Mobile  720p MP4   (compact, portable)             |" -ForegroundColor Yellow
        Write-Host "  +-----------------------------------------------------------+" -ForegroundColor DarkGray
        Write-Host "  |  AUDIO ONLY                                             |" -ForegroundColor DarkGray
        Write-Host "  |  [4] FLAC    Lossless archive  (archival grade)          |" -ForegroundColor Magenta
        Write-Host "  |  [5] Opus    Hi-Fi native      (bit-perfect, smallest)  |" -ForegroundColor Cyan
        Write-Host "  |  [6] MP3     320 kbps          (universal compatibility) |" -ForegroundColor Blue
        Write-Host "  +-----------------------------------------------------------+" -ForegroundColor DarkGray
        Write-Host "  |  [7] View Download History                              |" -ForegroundColor Cyan
        Write-Host "  |  [Q] Quit                                               |" -ForegroundColor Red
        Write-Host "  +-----------------------------------------------------------+" -ForegroundColor DarkGray
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
            '7' { Show-DownloadHistory; continue }
            'Q' { Write-Host "  Goodbye.`n" -ForegroundColor Cyan; return }
            default {
                Write-Host "  Invalid choice - try again." -ForegroundColor Red
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

# 
#region  MAIN ENTRY POINT
# 

function Main {
    # PS 5.1 is Windows-only; Linux/macOS require PS 7+
    if ((-not $IsWindows) -and ($PSVersionTable.PSVersion.Major -lt 7)) {
        Write-Host "[ERROR] Mr. Roboto requires PowerShell 7+ on Linux/macOS." -ForegroundColor Red
        Write-Host "  Install: https://aka.ms/install-powershell" -ForegroundColor Yellow
        exit 1
    }

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
