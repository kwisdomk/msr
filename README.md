# Mr. Roboto

Mr. Roboto is a portable media downloader powered by [yt-dlp](https://github.com/yt-dlp/yt-dlp) and [FFmpeg](https://ffmpeg.org/).

**Supported Platforms:** 
- Windows 10/11 (Stable)
- Linux (Planned / Upcoming Beta)

## Features
- Downloads yt-dlp and FFmpeg automatically on the first run if they are missing.
- Provides an interactive terminal menu for selecting quality profiles.
- Supports resuming interrupted downloads.
- Falls back to browser cookies (Microsoft Edge) if a download requires authentication.
- Uses stream-copy muxing to preserve original codec quality (GPU detection does not perform re-encoding).

## Directory Structure
- `roboto.bat` - Windows launcher.
- `roboto.ps1` - Core PowerShell script.
- `bin/` - Auto-downloaded yt-dlp and FFmpeg binaries.
- `downloads/` - Default save location for downloaded media.
- `logs/` - Session log files.
- `state/` - Resume data for interrupted downloads.
- `cache/` - Temporary files.

## Quick Start (Windows)

The simplest way to use Mr. Roboto on Windows is via the batch launcher:

1. Double-click `roboto.bat`.
2. Follow the interactive menu prompts.

*(Note: Always use `roboto.bat` for interactive use, as it automatically handles the PowerShell execution policy for the session).*

## PowerShell Usage (Direct Mode)

You can run Mr. Roboto directly from PowerShell for single-command execution:

```powershell
.\roboto.ps1 -Url "https://youtube.com/watch?v=..." -Profile high
```

*Note: Direct mode is not fully headless and may still prompt the user to confirm the save location.*
