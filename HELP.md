# Mr. Roboto Help Guide

Mr. Roboto is a portable media downloader powered by yt-dlp and FFmpeg.

## Platform status

- Windows: stable
- Linux: beta

Linux support is new. If you experience an issue, please report the command you ran, the full terminal output, and the latest log file when possible.

## Quick start

### Windows

Run:

```powershell
.\roboto.bat
```

Or:

```powershell
.\roboto.ps1
```

### Linux beta

Run:

```bash
chmod +x roboto.sh
./roboto.sh
```

Direct mode, if supported by your build:

```bash
./roboto.sh "https://example.com/video" high
```

## Profiles

Available profiles:

- `ultra` — highest video quality profile (4K MKV)
- `high` — default 1080p-oriented profile (MP4)
- `mobile` — smaller 720p-oriented profile (MP4)
- `audio-flac` — audio extraction to FLAC
- `audio-opus` — audio extraction to Opus
- `audio-mp3` — audio extraction to MP3

## Folders

Mr. Roboto may create these folders:

- `bin/` — downloaded yt-dlp and FFmpeg binaries
- `downloads/` — local fallback output folder
- `logs/` — session logs
- `state/` — resume/session state
- `cache/` — temporary files

On Windows, downloads may default to your Videos or Music folder.

On Linux beta, downloads may default to your Videos or Music directory depending on profile and environment.

## Common issues

### Windows execution policy warning

Use:

```powershell
.\roboto.bat
```

The batch launcher handles the execution policy for the current run.

### Permission denied on Linux

Run:

```bash
chmod +x roboto.sh
./roboto.sh
```

### yt-dlp or FFmpeg failed to download

Check your internet connection and rerun Mr. Roboto.

If the problem continues, report:
- operating system
- command used
- full terminal output
- latest file from `logs/`

### Sign-in or bot-detection errors

Some sites require browser cookies or a logged-in browser session. Mr. Roboto automatically attempts to fall back to browser cookies (Edge on Windows, Chrome/Firefox on Linux). 

Make sure you are logged in to the target site in your browser. Report the full yt-dlp error text when opening an issue.

### Resume did not work

Report:
- command used
- whether the download was interrupted with Ctrl+C
- latest log file
- contents of `state/session.json` if it exists

## Reporting Linux beta issues

When reporting Linux beta issues, include:
- Linux distribution and version
- CPU architecture, such as x86_64, arm64, or armv7l
- shell used
- command run
- full terminal output
- latest log file from `logs/`
- whether the issue happened in interactive mode or direct mode
