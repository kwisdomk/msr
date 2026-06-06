# Mr. Roboto v2.0 - Project Summary

## Overview

**Mr. Roboto v2.0** is a portable, self-healing PowerShell automation suite designed for high-fidelity media acquisition, transformation, and archival. This MVP focuses on Phases 1-2: establishing a robust foundation with automatic dependency management and an intuitive interactive interface.

---

## Project Scope

### In Scope (MVP - Phases 1-2 + Linux)

✅ **Phase 1: Bootstrapper Core**
- Directory scaffolding
- Binary locator system
- GPU detection (NVIDIA/Intel/AMD) — Windows (WMI) and Linux (`nvidia-smi`/`lspci`)
- Auto-download for yt-dlp and FFmpeg — Windows (.exe/.zip) and Linux (binary/tar.xz)
- Logging framework
- Startup banner

✅ **Phase 2: Interactive Menu System**
- Quality profile selection (Ultra/High/Mobile + Audio)
- URL intake and validation
- Download orchestration
- Progress tracking
- Error handling and recovery
- Resume capability

✅ **Linux Support**
- `roboto.sh` launcher (requires `pwsh` / PowerShell 7+)
- Cross-platform binary management (`bin/x64/` — no `.exe` on Linux)
- `linux-x64` and `linux-arm64` download URLs in config
- Linux GPU detection via `nvidia-smi` and `lspci`
- AMD encoder mapped to `h264_vaapi` on Linux (VA-API standard)
- XDG-aware download directories (`~/Music`, `~/Videos`)
- Browser cookie auth detects Firefox/Chrome/Chromium on Linux

✅ **Bug Fixes & Runtime Improvements**
- **Resume missing output path** — `downloadDir` is now saved to session state and restored on resume; previously the output path was empty, causing yt-dlp to write to `/` and fail with permission denied
- **Stale system yt-dlp shadowing** — `Find-Binary` now correctly prefers `bin/x64/yt-dlp` over system PATH, ensuring the auto-downloaded latest binary is always used instead of a potentially years-old system package
- **Auth escalation without browser** — cookie auth now safely skips escalation with a clear message when no supported browser is installed on Linux, rather than passing an invalid `--cookies-from-browser edge` argument
- **Windows backslash in Linux error message** — `logs\` path separator corrected to `logs/`
- **TLS setup on Linux** — `[Net.ServicePointManager]` call wrapped in `$IsWindows` guard; on Linux/.NET 6+ TLS is handled natively and the call would throw unnecessary exceptions
- **PS5.1 `$IsWindows` polyfill** — `$IsWindows`/`$IsLinux`/`$IsMacOS` are now defined for PS5.1 (Windows-only runtime) where these automatic variables do not exist

### Out of Scope (Future Phases)

🔮 **Phase 3: Library Mode**
- Thumbnail embedding
- JSON metadata sidecars
- SHA-256 hashing
- Playlist-aware folders

🔮 **Phase 4: Automation**
- Clipboard listener daemon
- Toast notifications
- Background processing

🔮 **Phase 5-7: Advanced Features**
- Custom profiles
- Integrity auditing
- API/Headless mode

---

## Key Features

### 🔧 Self-Healing Architecture
- **Zero Configuration** - Works immediately after extraction
- **Auto-Download Dependencies** - Fetches yt-dlp and FFmpeg on first run
- **Hardware Detection** - Automatically uses GPU acceleration when available
- **Smart Fallbacks** - Gracefully handles missing hardware or network issues

### 🎯 Intelligent Processing
- **Quality Profiles** - Pre-configured for different use cases
- **Hardware Acceleration** - NVENC/QSV/AMF support with software fallback
- **Resume Capability** - Continue interrupted downloads
- **Error Recovery** - Automatic retry with exponential backoff

### 🎨 Professional Interface
- **Beautiful CLI** - Modern terminal UI with Unicode indicators
- **System Info Banner** - Shows GPU, FFmpeg, and yt-dlp versions
- **Real-time Progress** - Speed, ETA, and completion percentage
- **Color-Coded Logs** - Easy-to-read status messages

---

## Technical Architecture

### Core Components

```
┌─────────────────────────────────────────┐
│         Mr. Roboto v2.0                 │
│         (roboto.ps1)                    │
└─────────────────────────────────────────┘
              │
    ┌─────────┼─────────┐
    ▼         ▼         ▼
┌────────┐ ┌────────┐ ┌────────┐
│Bootstrap│ │Hardware│ │  CLI   │
│ Engine │ │Detector│ │Interface│
└────────┘ └────────┘ └────────┘
    │         │         │
    ▼         ▼         ▼
┌────────┐ ┌────────┐ ┌────────┐
│yt-dlp  │ │FFmpeg  │ │Logging │
└────────┘ └────────┘ └────────┘
```

### Directory Structure

```
/MrRoboto/
├── roboto.ps1              # Main entry point (~1000 lines)
├── config.json             # Configuration
├── README.md               # User documentation
├── /bin/                   # Auto-downloaded binaries
│   ├── /x64/
│   └── /x86/
├── /downloads/             # Final media output
├── /logs/                  # Session logs
├── /state/                 # Resume data
└── /cache/                 # Temporary files
```

---

## Implementation Strategy

### Sprint Breakdown

**Sprint 1: Foundation (Days 1-2)**
- Directory structure
- Config schema
- Logging framework
- Startup banner

**Sprint 2: Bootstrapper (Days 3-4)**
- GPU detection
- Binary locator
- Auto-download system
- Checksum verification

**Sprint 3: Interactive Menu (Days 5-6)**
- Menu system
- Quality selection
- URL validation
- Download orchestration

**Sprint 4: Integration & Testing (Days 7-8)**
- Progress tracking
- Error handling
- Resume capability
- End-to-end testing

### Development Approach

1. **Modular Design** - Each function is self-contained and testable
2. **Iterative Development** - Build and test incrementally
3. **Error-First** - Implement error handling from the start
4. **User-Centric** - Focus on UX and clear feedback
5. **Documentation** - Inline comments and comprehensive docs

---

## Quality Profiles

| Profile | Resolution | Container | Codec | Use Case |
|---------|-----------|-----------|-------|----------|
| **Ultra** | 4K (2160p) | MKV | Auto | Maximum quality, archival |
| **High** | 1080p | MP4 | Auto | Recommended, balanced |
| **Mobile** | 720p | MP4 | H.264 | Smaller files, portable |

---

## Hardware Acceleration

**Windows**

| GPU Vendor | Encoder | Performance |
|------------|---------|-------------|
| **NVIDIA** | NVENC | ⚡⚡⚡ Fastest |
| **Intel** | QSV | ⚡⚡ Fast |
| **AMD** | AMF | ⚡⚡ Fast |
| **None** | libx264 | ⚡ Software |

**Linux**

| GPU Vendor | Encoder | Detection |
|------------|---------|-----------|
| **NVIDIA** | NVENC | `nvidia-smi` |
| **Intel** | QSV | `lspci` |
| **AMD** | VA-API | `lspci` |
| **None** | libx264 | Fallback |

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

- **Startup time:** < 3 seconds
- **Binary download:** < 60 seconds (typical connection)
- **GPU detection:** < 1 second
- **Download speed:** Limited only by network/source

---

## Documentation Deliverables

| Document | Purpose | Status |
|----------|---------|--------|
| **README.md** | User-facing documentation | ✅ Complete |
| **IMPLEMENTATION_PLAN.md** | Detailed technical plan | ✅ Complete |
| **ARCHITECTURE.md** | System design and diagrams | ✅ Complete |
| **DEV_GUIDE.md** | Developer quick-start | ✅ Complete |
| **PROJECT_SUMMARY.md** | This document | ✅ Complete |

---

## Risk Assessment

### Identified Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Binary download failures | High | Retry logic, offline mode |
| GPU detection inaccuracy | Medium | Manual override in config |
| yt-dlp API changes | Medium | Version pinning, updates |
| FFmpeg compatibility | Low | Test multiple versions |
| Terminal variations | Low | Fallback to plain text |

### Mitigation Strategies

- Comprehensive error handling
- Graceful degradation
- Extensive logging
- User-configurable overrides
- Regular testing on target systems

---

## Dependencies

### External Binaries
- **yt-dlp** - Media extraction engine (auto-downloaded)
- **FFmpeg** - Media processing toolkit (auto-downloaded)

### System Requirements

**Windows**
- Windows 10/11 (x86 or x64)
- PowerShell 5.1 or later (built-in)
- .NET Framework 4.5+
- 500MB free disk space (for binaries)
- Internet connection (for first run and downloads)

**Linux**
- Any modern x86_64 or arm64 distribution
- PowerShell 7+ (`pwsh`)
- `tar` (pre-installed everywhere)
- 500MB free disk space (for binaries)
- Internet connection (for first run and downloads)
- Optional: `pciutils` (for AMD/Intel GPU detection via `lspci`)

### Optional Dependencies
- **BurntToast** - Windows notifications (Phase 4)
- **PSScriptAnalyzer** - Code quality (development)
- **Pester** - Unit testing (development)

---

## Testing Strategy

### Test Coverage

1. **Unit Tests** - Individual function validation
2. **Integration Tests** - Full workflow testing
3. **Performance Tests** - Speed and resource usage
4. **Compatibility Tests** - Different Windows versions
5. **Hardware Tests** - Various GPU configurations

### Test Scenarios

- First run (no binaries)
- Subsequent runs (binaries present)
- GPU detection (NVIDIA/Intel/AMD/None)
- Each quality profile
- Valid/invalid URLs
- Network failures
- Disk space issues
- Resume functionality

---

## Future Roadmap

### Phase 3: Library Mode (Q2 2026)
- Metadata extraction and storage
- Thumbnail embedding
- SHA-256 hashing for integrity
- Playlist-aware organization

### Phase 4: Automation (Q3 2026)
- Clipboard monitoring daemon
- Windows toast notifications
- Background processing queue

### Phase 5: Profiles & Presets (Q4 2026)
- Custom quality profiles
- Research/mobile/archive modes
- Profile import/export

### Phase 6: Integrity & Audit (Q1 2027)
- Batch manifests
- Verification passes
- Acquisition reports

### Phase 7: API/Headless Mode (Q2 2027)
- CLI entrypoints
- Pipeline integration
- Scriptable automation

---

## Project Goals

Mr. Roboto is designed to be:

1. **Reliable** - Self-healing, automatic recovery
2. **Portable** - Zero installation, works anywhere
3. **Intelligent** - Hardware-aware, optimized processing
4. **Professional** - Polished UX, comprehensive logging
5. **Extensible** - Modular architecture, future-proof

---

## Next Steps

### Immediate Actions

1. **Review this plan** - Confirm scope and approach
2. **Switch to Code mode** - Begin implementation
3. **Start with Sprint 1** - Foundation components
4. **Iterate through sprints** - Build incrementally
5. **Test continuously** - Validate each component

### Implementation Order

```
1. Initialize-Environment
2. Initialize-Config
3. Initialize-Logging
4. Get-HardwareCapabilities
5. Find-Binary
6. Install-Dependencies
7. Show-Banner
8. Start-InteractiveMode
9. Test-MediaUrl
10. Start-MediaAcquisition
```

---

## Conclusion

This comprehensive plan provides:

- **Clear scope** - MVP focused on Phases 1-2
- **Detailed architecture** - Modular, extensible design
- **Implementation roadmap** - Sprint-based approach
- **Quality assurance** - Testing and validation strategy
- **Future vision** - Roadmap for continued development

The foundation is solid, the plan is actionable, and the path forward is clear.

**Ready to build Mr. Roboto v2.0!** 🤖

---

*"Domo arigato, Mr. Roboto!"*