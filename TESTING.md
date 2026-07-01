# Manual Testing Checklist

Before merging pull requests, complete the following manual tests to ensure stability.

## 1. Windows Smoke Test
- [ ] Run `roboto.bat`.
- [ ] Verify the script launches, initializes the environment, and displays the main menu without errors.

## 2. Dependency Bootstrap Test
- [ ] Delete or rename the `bin/` folder.
- [ ] Run `roboto.bat`.
- [ ] Verify that yt-dlp and FFmpeg are downloaded successfully and placed in the correct `bin/x64/` or `bin/x86/` subdirectories.

## 3. Direct Mode Test
- [ ] Open PowerShell.
- [ ] Run `.\roboto.ps1 -Url "https://youtube.com/watch?v=..." -Profile mobile`.
- [ ] Verify the script prompts for a save location and successfully completes the download.

## 4. Resume / Interrupted Download Test
- [ ] Start a large download in interactive mode.
- [ ] Press `Ctrl+C` midway through the download.
- [ ] Restart `roboto.bat`.
- [ ] Verify the script detects the interrupted session and resumes the download from where it left off.

## 5. Browser-Cookie Retry Test
- [ ] Attempt to download an age-restricted or members-only video.
- [ ] Verify the script detects the authentication failure and attempts to escalate using Microsoft Edge cookies.

## Linux beta checklist

Run these on a Linux VM before beta release:

- [ ] Fresh clone
- [ ] `chmod +x roboto.sh`
- [ ] `./roboto.sh` launches
- [ ] yt-dlp bootstraps successfully
- [ ] FFmpeg bootstraps successfully
- [ ] A short public media URL downloads successfully
- [ ] Direct mode works, if supported: `./roboto.sh "<url>" high`
- [ ] Ctrl+C interruption saves state
- [ ] Resume restores the correct output path
- [ ] Logs are written under `logs/`

## PR Merge Requirements
- [ ] **Windows Test:** Required for all PRs.
- [ ] **Linux Test:** Required only for Linux-specific PRs (when Linux support is merged).
- [ ] **Documentation Accuracy:** Required. Ensure no inaccurate claims are added.
- [ ] **No Generated Markdown Dumps:** Required. Keep documentation concise, practical, and truthful.