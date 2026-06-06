# Mr. Roboto v2.0 - MVP Implementation Plan

## Project Overview

**Goal:** Build a portable, self-healing PowerShell-based media acquisition agent with automatic dependency management and hardware-aware processing.

**Scope:** Phase 1 (Bootstrapper Core) + Phase 2 (Interactive Menu System)

**Target Platform:** Windows 10/11 (x86/x64) and Linux (x86_64/arm64)

**Primary Language:** PowerShell 5.1+ on Windows; PowerShell 7+ on Linux

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Mr. Roboto v2.0                      │
│                   (roboto.ps1)                          │
└─────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ Bootstrapper │    │   Hardware   │    │     CLI      │
│    Engine    │    │   Detection  │    │   Interface  │
└──────────────┘    └──────────────┘    └──────────────┘
        │                   │                   │
        │                   │                   │
        ▼                   ▼                   ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   yt-dlp     │    │    FFmpeg    │    │   Logging    │
│   (binary)   │    │   (binary)   │    │   System     │
└──────────────┘    └──────────────┘    └──────────────┘
```

---

## Directory Structure

```
/MrRoboto/
├── roboto.ps1              # Main entry point
├── config.json             # Configuration file
├── README.md               # User documentation
├── /bin/                   # Binaries (auto-downloaded)
│   ├── /x64/
│   │   ├── yt-dlp.exe
│   │   └── ffmpeg.exe
│   └── /x86/
│       ├── yt-dlp.exe
│       └── ffmpeg.exe
├── /downloads/             # Final media output
├── /metadata/              # JSON sidecars (Phase 3)
├── /logs/                  # Session and error logs
│   └── session_YYYYMMDD_HHMMSS.log
├── /state/                 # Resume checkpoints
│   └── session.json
└── /cache/                 # Temporary artifacts
```

---

## Phase 1: Bootstrapper Core

### 1.1 Directory Scaffolding

**Module:** `Initialize-Environment`

**Responsibilities:**
- Create directory structure if missing
- Validate write permissions
- Initialize config.json with defaults
- Set up logging infrastructure

**Implementation Details:**
```powershell
function Initialize-Environment {
    $requiredDirs = @('bin/x64', 'bin/x86', 'downloads', 'metadata', 'logs', 'state', 'cache')
    foreach ($dir in $requiredDirs) {
        $path = Join-Path $PSScriptRoot $dir
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }
}
```

### 1.2 Configuration Schema

**File:** `config.json`

```json
{
  "version": "2.0.0",
  "settings": {
    "defaultQuality": "high",
    "autoUpdate": true,
    "offlineMode": false,
    "notifications": true,
    "preferredContainer": "mp4",
    "libraryMode": false
  },
  "profiles": {
    "ultra": {
      "format": "bestvideo[height<=2160]+bestaudio/best",
      "container": "mkv",
      "videoCodec": "auto",
      "audioCodec": "aac"
    },
    "high": {
      "format": "bestvideo[height<=1080]+bestaudio/best",
      "container": "mp4",
      "videoCodec": "auto",
      "audioCodec": "aac"
    },
    "mobile": {
      "format": "bestvideo[height<=720]+bestaudio/best",
      "container": "mp4",
      "videoCodec": "h264",
      "audioCodec": "aac"
    }
  },
  "binaries": {
    "ytdlp": {
      "x64": "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe",
      "x86": "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_x86.exe"
    },
    "ffmpeg": {
      "x64": "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip",
      "x86": "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win32-gpl.zip"
    }
  }
}
```

### 1.3 GPU Detection Module

**Module:** `Get-HardwareCapabilities`

**Detection Strategy:**
1. Query WMI for GPU devices: `Get-CimInstance Win32_VideoController`
2. Parse vendor strings (NVIDIA, Intel, AMD)
3. Determine encoder priority:
   - NVIDIA → `h264_nvenc` / `hevc_nvenc`
   - Intel → `h264_qsv` / `hevc_qsv`
   - AMD → `h264_amf` / `hevc_amf`
   - Fallback → `libx264` / `libx265`

**Output:**
```powershell
@{
    GPU = "NVIDIA GeForce RTX 3050"
    Encoder = "h264_nvenc"
    Architecture = "x64"
}
```

### 1.4 Binary Locator System

**Module:** `Find-Binary`

**Search Order:**
1. Check `./bin/x64/` or `./bin/x86/` (architecture-aware)
2. Search `$env:PATH`
3. Return `$null` if not found

**Implementation:**
```powershell
function Find-Binary {
    param([string]$Name)
    
    $arch = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
    $localPath = Join-Path $PSScriptRoot "bin/$arch/$Name.exe"
    
    if (Test-Path $localPath) {
        return $localPath
    }
    
    $pathBinary = Get-Command $Name -ErrorAction SilentlyContinue
    if ($pathBinary) {
        return $pathBinary.Source
    }
    
    return $null
}
```

### 1.5 Auto-Download Bootstrapper

**Module:** `Install-Dependencies`

**Workflow:**
1. Detect missing binaries
2. Download from official sources (GitHub releases)
3. Extract archives (FFmpeg requires unzipping)
4. Verify SHA-256 checksums (optional but recommended)
5. Set executable permissions
6. Log installation results

**Key Considerations:**
- Use `Invoke-WebRequest` with progress tracking
- Handle network failures gracefully
- Support resume for partial downloads
- Extract FFmpeg from nested zip structure

### 1.6 Logging Framework

**Module:** `Write-Log`

**Log Levels:**
- `INFO` - General operations
- `WARN` - Non-critical issues
- `ERROR` - Failures requiring attention
- `DEBUG` - Verbose diagnostic info

**Log Format:**
```
[2026-01-30 21:30:00] [INFO] Mr. Roboto v2.0 initialized
[2026-01-30 21:30:01] [INFO] GPU detected: NVIDIA RTX 3050 (NVENC)
[2026-01-30 21:30:02] [WARN] yt-dlp not found, downloading...
[2026-01-30 21:30:15] [INFO] yt-dlp installed successfully
```

**Session Tracking:**
- Create new log file per session: `session_YYYYMMDD_HHMMSS.log`
- Maintain rolling logs (keep last 30 days)
- Write to both file and console (with color coding)

### 1.7 Startup Banner

**Module:** `Show-Banner`

**Display:**
```
╔═══════════════════════════════════════════════════════╗
║              Mr. Roboto v2.0                          ║
║        Autonomous Media Acquisition Agent             ║
╚═══════════════════════════════════════════════════════╝

System Information:
  GPU: NVIDIA GeForce RTX 3050 (NVENC)
  FFmpeg: 7.0.2
  yt-dlp: 2026.01.28
  Mode: Interactive
  Architecture: x64

Ready to acquire media.
```

**Implementation Notes:**
- Use ANSI escape codes for colors
- Detect terminal capabilities
- Fallback to plain text if needed

---

## Phase 2: Interactive Menu System

### 2.1 Quality Profile Selection

**Module:** `Select-QualityProfile`

**Menu:**
```
Select Quality Profile:
  [1] Ultra  - 4K MKV (best quality)
  [2] High   - 1080p MP4 (recommended)
  [3] Mobile - 720p MP4 (smaller size)
  [Q] Quit

Choice:
```

**Validation:**
- Accept numeric input (1-3) or letter shortcuts (U/H/M)
- Loop until valid selection
- Display profile details on selection

### 2.2 URL Intake & Validation

**Module:** `Get-MediaUrl`

**Workflow:**
1. Prompt for URL input
2. Validate URL format (regex)
3. Support multiple URLs (comma/newline separated)
4. Support playlist detection
5. Confirm with user before proceeding

**Supported Patterns:**
- YouTube: `youtube.com/watch?v=`, `youtu.be/`
- Vimeo: `vimeo.com/`
- Generic: Any valid HTTP/HTTPS URL

**Validation:**
```powershell
function Test-MediaUrl {
    param([string]$Url)
    return $Url -match '^https?://.+'
}
```

### 2.3 Download Orchestration

**Module:** `Start-MediaAcquisition`

**Workflow:**
```
User Input → Validate URL → Select Profile → Detect Hardware
     ↓
Build yt-dlp Command → Execute Download → Monitor Progress
     ↓
Post-Process with FFmpeg → Verify Output → Log Results
```

**yt-dlp Command Construction:**
```powershell
$ytdlpArgs = @(
    $url,
    '--format', $profile.format,
    '--output', "$downloadPath/%(title)s.%(ext)s",
    '--merge-output-format', $profile.container,
    '--ffmpeg-location', $ffmpegPath,
    '--progress',
    '--newline'
)

if ($hardwareEncoder) {
    $ytdlpArgs += '--postprocessor-args', "ffmpeg:-c:v $hardwareEncoder"
}
```

### 2.4 Progress Tracking

**Module:** `Show-Progress`

**Visual Feedback:**
```
Downloading: "Sample Video Title"
Progress: [████████████░░░░░░░░] 60% | 120MB/200MB | ETA: 00:02:30
Speed: 2.5 MB/s | Encoder: NVENC
```

**Implementation:**
- Parse yt-dlp output for progress data
- Update console line in-place (carriage return)
- Use Unicode block characters for progress bar
- Display speed, ETA, and encoder info

### 2.5 Error Handling

**Module:** `Handle-Error`

**Error Categories:**
1. **Network Errors** - Retry with exponential backoff
2. **Format Unavailable** - Fallback to lower quality
3. **Encoder Failure** - Switch to software encoding
4. **Disk Space** - Alert and abort
5. **Permission Denied** - Suggest elevation

**Recovery Strategy:**
```powershell
try {
    # Attempt download
} catch {
    Write-Log "ERROR" $_.Exception.Message
    
    if ($_.Exception -match "network") {
        # Retry logic
    } elseif ($_.Exception -match "format") {
        # Fallback to different format
    } else {
        # Log and exit gracefully
    }
}
```

### 2.6 Resume Capability

**Module:** `Resume-Download`

**State Tracking:**
- Detect `.part` files in downloads folder
- Read `state/session.json` for interrupted downloads
- Prompt user to resume or restart
- Pass `--continue` flag to yt-dlp

**State File Format:**
```json
{
  "sessionId": "20260130_213000",
  "url": "https://youtube.com/watch?v=...",
  "profile": "high",
  "status": "interrupted",
  "progress": 0.45,
  "timestamp": "2026-01-30T21:35:00Z"
}
```

---

## Implementation Sequence

### Sprint 1: Foundation (Days 1-2)
1. ✅ Create directory structure
2. ✅ Implement config.json schema
3. ✅ Build logging framework
4. ✅ Create startup banner

### Sprint 2: Bootstrapper (Days 3-4)
5. ✅ Implement GPU detection
6. ✅ Build binary locator
7. ✅ Create auto-download system
8. ✅ Add SHA-256 verification

### Sprint 3: Interactive Menu (Days 5-6)
9. ✅ Design menu system
10. ✅ Implement quality selection
11. ✅ Build URL intake/validation
12. ✅ Create download orchestration

### Sprint 4: Integration & Testing (Days 7-8)
13. ✅ Add progress tracking
14. ✅ Implement error handling
15. ✅ Build resume capability
16. ✅ End-to-end testing

---

## Testing Strategy

### Unit Testing
- Test each module independently
- Mock external dependencies (network, filesystem)
- Validate error handling paths

### Integration Testing
- Test full workflow with sample URLs
- Verify hardware detection on different systems
- Test resume functionality
- Validate output file integrity

### Test Cases
1. **First Run** - No binaries, auto-download
2. **GPU Detection** - NVIDIA, Intel, AMD, None
3. **Download Success** - Various quality profiles
4. **Network Failure** - Retry and recovery
5. **Resume** - Interrupted download continuation
6. **Invalid URL** - Graceful error handling

---

## Success Criteria

### MVP Completion Checklist
- [ ] Portable execution (no system dependencies)
- [ ] Auto-download yt-dlp and FFmpeg
- [ ] GPU detection and encoder selection
- [ ] Interactive quality profile menu
- [ ] Successful media download and processing
- [ ] Progress tracking with visual feedback
- [ ] Error handling and recovery
- [ ] Resume capability for interrupted downloads
- [ ] Comprehensive logging
- [ ] Professional CLI interface

### Performance Targets
- Startup time: < 3 seconds
- Binary download: < 60 seconds (on typical connection)
- GPU detection: < 1 second
- Download speed: Limited only by network/source

---

## Future Phases (Post-MVP)

### Phase 3: Library Mode
- Thumbnail embedding
- JSON metadata sidecars
- SHA-256 hashing
- Playlist-aware folder trees

### Phase 4: Automation
- Clipboard listener daemon
- Toast notifications
- Background processing

### Phase 5: Profiles & Presets
- Custom quality profiles
- Research/mobile/archive modes
- Profile import/export

### Phase 6: Integrity & Audit
- Batch manifests
- Verification passes
- Acquisition reports

### Phase 7: API/Headless Mode
- CLI entrypoints
- Pipeline integration
- Scriptable automation

---

## Technical Considerations

### PowerShell Best Practices
- Use approved verbs (Get-, Set-, New-, etc.)
- Implement proper error handling (`try/catch`)
- Support `-WhatIf` and `-Confirm` where applicable
- Use `[CmdletBinding()]` for advanced functions
- Follow PSScriptAnalyzer rules

### Security
- Validate all user input
- Sanitize file paths
- Verify binary checksums
- Avoid executing arbitrary code
- Log security-relevant events

### Performance
- Minimize disk I/O
- Use streaming where possible
- Implement parallel downloads (future)
- Cache GPU detection results
- Optimize log writing

### Compatibility
- Support PowerShell 5.1+ (Windows PowerShell)
- Test on Windows 10 and 11
- Handle both x86 and x64 architectures
- Graceful degradation on older systems

---

## Dependencies

### External Binaries
- **yt-dlp** - Media extraction engine
- **FFmpeg** - Media processing toolkit

### PowerShell Modules (Optional)
- **BurntToast** - Windows notifications (Phase 4)
- **PSScriptAnalyzer** - Code quality (development)

### System Requirements

**Windows**
- Windows 10/11 (x86/x64)
- PowerShell 5.1 or later
- .NET Framework 4.5+
- 500MB free disk space (for binaries)
- Internet connection (for downloads)

**Linux**
- Any modern x86_64 or arm64 distribution
- PowerShell 7+ (`pwsh`)
- `tar` (pre-installed)
- 500MB free disk space (for binaries)
- Internet connection (for downloads)

---

## Documentation Deliverables

1. **README.md** - User-facing documentation
2. **IMPLEMENTATION_PLAN.md** - This document
3. **ARCHITECTURE.md** - Technical deep-dive (future)
4. **API.md** - Headless mode reference (Phase 7)
5. **Inline Comments** - Code documentation

---

## Risk Mitigation

### Identified Risks
1. **Binary Download Failures** - Implement retry logic and offline mode
2. **GPU Detection Inaccuracy** - Provide manual override in config
3. **yt-dlp API Changes** - Version pinning and update notifications
4. **FFmpeg Compatibility** - Test with multiple versions
5. **Windows Terminal Variations** - Fallback to plain text

### Mitigation Strategies
- Comprehensive error handling
- Graceful degradation
- Extensive logging
- User-configurable overrides
- Regular testing on target systems

---

## Conclusion

This implementation plan provides a clear roadmap for building Mr. Roboto v2.0 MVP. By focusing on Phases 1-2, we establish a solid foundation with:

- **Reliability** through self-healing binaries
- **Portability** via zero-configuration deployment
- **User Experience** with polished CLI interface
- **Extensibility** for future enhancements

The modular architecture ensures each component can be developed, tested, and refined independently while maintaining cohesion with the overall system design.

**Next Steps:** Begin implementation with Sprint 1 (Foundation) and iterate through the defined sprints, validating each component before proceeding to the next.