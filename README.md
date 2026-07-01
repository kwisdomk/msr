# Mr. Roboto

Mr. Roboto is a portable media downloader powered by [yt-dlp](https://github.com/yt-dlp/yt-dlp) and [FFmpeg](https://ffmpeg.org/).

## Platform status

- Windows: stable
- Linux: beta

Linux support is new. Please report issues with the command used, full terminal output, and latest log file where possible.

For troubleshooting and platform-specific help, see [HELP.md](HELP.md).

## Features
- Downloads yt-dlp and FFmpeg automatically on the first run if they are missing.
- Provides an interactive terminal menu for selecting quality profiles.
- Supports resuming interrupted downloads.
- Falls back to browser cookies if a download requires authentication (Edge on Windows; Firefox/Chrome on Linux).
- Uses stream-copy muxing to preserve original codec quality (GPU detection does not perform re-encoding).

## Directory Structure
- `roboto.bat` - Windows launcher.
- `roboto.sh` - Linux native bash launcher.
- `roboto.ps1` - Core PowerShell script (Windows).
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

## Quick Start (Linux)

Run the native bash script from your terminal:

```bash
chmod +x roboto.sh
./roboto.sh
```

*Prerequisites: `bash`, `curl` or `wget`, and `tar` (pre-installed on most distributions).*

## PowerShell Usage (Direct Mode - Windows)

You can run Mr. Roboto directly from PowerShell for single-command execution:

```powershell
.\roboto.ps1 -Url "https://youtube.com/watch?v=..." -Profile high
```

*Note: Direct mode is not fully headless and may still prompt the user to confirm the save location.*
