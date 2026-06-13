# 🤖 Mr. Roboto v2.0

**Portable PowerShell media downloader**

A portable PowerShell script that downloads media via yt-dlp and FFmpeg, featuring GPU encoder detection, stream-copy muxing, resume support, and session logging.

---

## ✨ Features

### 🔧 Zero-Setup Bootstrap
- **No installation** - Works out of the box, no setup required
- **Downloads yt-dlp and FFmpeg when missing** - Fetches them on first run
- **Detects available GPU encoders** - Identifies NVENC/QSV/AMF when available
- **Graceful fallbacks** - Handles missing hardware or network issues

### 🎯 Download Features
- **Quality Profiles** - Choose from Ultra (4K), High (1080p), Mobile (720p), or audio-only formats (FLAC/Opus/MP3)
- **Resume support** - Continue interrupted downloads
- **Progress Tracking** - Real-time progress with speed and ETA
- **Error Recovery** - Automatic retry (up to 3 attempts) for transient and auth failures

### 🎨 Interactive Terminal Menu
- **Terminal UI** - Menu-driven interface with Unicode indicators
- **System Info Banner** - Shows GPU, FFmpeg, and yt-dlp versions
- **Session logging** - Timestamped log files for every run with 30-day rotation

---

## 🚀 Quick Start

### Prerequisites
- Windows 10 or 11 (x86 or x64)
- PowerShell 5.1 or later
- Internet connection (for first run)

### Installation

1. **Download Mr. Roboto**
   ```powershell
   # Clone or download this repository
   git clone https://github.com/kwisdomk/Mr.Roboto.git
   cd Mr.Roboto
   ```

2. **Run Mr. Roboto**

   **Double-click `roboto.bat`** — that's it.

   > ⚠️ **Always use `roboto.bat`**, not `roboto.ps1` directly.  
   > The bat file handles the PowerShell execution policy automatically (process-scoped bypass — no system-wide changes).

On first run, Mr. Roboto will:
- Create necessary directories
- Download yt-dlp and FFmpeg
- Detect your GPU capabilities
- Present the interactive menu

---

## 📖 Usage

### Interactive Mode

Double-click **`roboto.bat`** and follow the prompts.

You'll see: <img width="692" height="853" alt="image" src="https://github.com/user-attachments/assets/ba8ea997-09d9-4eeb-8a14-13edf3933db5" />


### Direct Mode

You can also run Mr. Roboto directly from PowerShell for single-command execution:
```powershell
.\roboto.ps1 -Url "https://youtube.com/watch?v=..." -Profile high
```

### Additional Runtime Features

- **Save Location:** The script prompts for a save location per-download, defaulting to the OS native `Videos` or `Music` folders based on the chosen profile.
- **Playlist Handling:** If a playlist URL is detected, Mr. Roboto automatically previews the first 5 items and lets you choose between downloading a single video or the entire playlist.
- **Metadata Embedding:** Automatically embeds thumbnails and metadata using `--embed-thumbnail` and `--embed-metadata`.
- **Deno Warning:** yt-dlp functions best with the Deno JS runtime installed. If Deno is missing, Mr. Roboto will output a warning with install instructions.

### Quality Profiles

| Profile | Resolution / Details | Container | Codec Details | Use Case |
|---------|-----------|-----------|---------------|----------|
| **Ultra** | 4K (2160p) | MKV | Stream copy | Maximum quality, archival |
| **High** | 1080p | MP4 | Stream copy | Recommended, balanced |
| **Mobile** | 720p | MP4 | Stream copy | Smaller files, portable |
| **audio-flac** | Lossless | FLAC | Native FLAC | Archival grade audio |
| **audio-opus** | High-Fidelity | OPUS | Native OPUS | Bit-perfect, smallest size |
| **audio-mp3** | 320 kbps | MP3 | MP3 320K | Universal compatibility |

*Note: Video profiles use ffmpeg's stream-copy (`-c copy`) to mux the audio and video streams together. This preserves the original codec quality and does not perform re-encoding.*

### Supported Sites

Mr. Roboto supports **1000+ websites** through yt-dlp, including:
- YouTube
- Vimeo
- Twitch
- Twitter/X
- Reddit
- And many more...

For a full list, visit: [yt-dlp supported sites](https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md)

---

## ⚙️ Configuration

Edit `config.json` to customize behavior:

```json
{
  "version": "2.0.0",
  "settings": {
    "defaultQuality": "high",
    "autoUpdate": true,
    "offlineMode": false,
    "notifications": true,
    "preferredContainer": "mp4",
    "libraryMode": false,
    "browserCookies": "brave"
  }
}
```

### Configuration Options

| Setting | Description | Status |
|---------|-------------|---------|
| `profiles` | Define quality profiles and formatting | ✅ Functional |
| `binaries` | Download locations for yt-dlp and FFmpeg | ✅ Functional |
| `defaultQuality` | Default quality profile | 🚧 Planned (currently defaults to `high` via CLI) |
| `autoUpdate` | Auto-update yt-dlp on startup | 🚧 Planned |
| `offlineMode` | Skip update checks | 🚧 Planned (currently handled via `-OfflineMode` CLI switch) |
| `notifications` | Enable toast notifications | 🚧 Planned (Phase 4) |
| `preferredContainer` | Default container format | 🚧 Planned (currently handled in profile definition) |
| `libraryMode` | Enable metadata sidecars | 🚧 Planned (Phase 3) |
| `browserCookies` | Browser choice for auth retry | 🚧 Planned (currently hardcoded to `edge`) |

---

## 📁 Directory Structure

```
/MrRoboto/
├── roboto.bat              # ← Launch this (handles execution policy)
├── roboto.ps1              # Core script (do not run directly)
├── config.json             # Configuration (includes browserCookies setting)
├── README.md               # This file
├── /bin/                   # Auto-downloaded binaries
│   ├── /x64/
│   │   ├── yt-dlp.exe
│   │   └── ffmpeg.exe
│   └── /x86/
├── /downloads/             # Your downloaded media
├── /logs/                  # Session logs
├── /state/                 # Resume data
└── /cache/                 # Temporary files
```

---

## 🎮 GPU Detection

Mr. Roboto detects available GPU encoders, but current downloads use stream-copy muxing (`-c copy`) without re-encoding. The original codec quality is preserved as-is.

| GPU Vendor | Detected Encoder |
|------------|---------|
| **NVIDIA** | NVENC |
| **Intel** | QSV |
| **AMD** | AMF |
| **None** | libx264 (Software) |

No configuration needed - detection happens automatically!

---

## 🔄 Resume Downloads

If a download is interrupted:

1. Restart Mr. Roboto
2. You'll be prompted to resume (unless the session is older than 2 hours)
3. Download continues from where it left off

Resume data is stored in `/state/session.json`. Stale sessions older than 2 hours are automatically discarded to prevent spurious prompts.

---

## 📊 Logging

All operations are logged to `/logs/session_YYYYMMDD_HHMMSS.log`

Log levels:
- `[INFO]` - Normal operations
- `[WARN]` - Non-critical issues
- `[ERROR]` - Failures requiring attention
- `[DEBUG]` - Verbose diagnostic info

---

## 🛠️ Troubleshooting

### "yt-dlp not found"
- Mr. Roboto will auto-download on first run
- Check your internet connection
- Manually download from: https://github.com/yt-dlp/yt-dlp/releases

### "FFmpeg not found"
- Mr. Roboto will auto-download on first run
- Check your internet connection
- Manually download from: https://github.com/BtbN/FFmpeg-Builds/releases

### "Download failed" / YouTube bot detection
- Mr. Roboto will detect the bot-detection error automatically and attempt to retry the download using your **Edge browser cookies**.
- Make sure you are **logged into YouTube** in Microsoft Edge.
- Close the Edge browser before running Mr. Roboto (some browsers lock the cookie database).
- Check `/logs/` for the full error output

### "GPU not detected"
- Mr. Roboto will fallback to software encoding
- Update your GPU drivers
- Check GPU is enabled in Device Manager

---

## 🗺️ Roadmap

### Current: Working Features
- [x] Dependency bootstrap for missing `yt-dlp` and FFmpeg
- [x] GPU vendor/encoder detection
- [x] Interactive terminal menu
- [x] Direct URL mode via `-Url`
- [x] Video profiles: Ultra, High, Mobile
- [x] Audio profiles: FLAC, Opus, MP3
- [x] Stream-copy muxing for video downloads
- [x] Thumbnail and metadata embedding
- [x] Resume support via saved session state and `--continue`
- [x] Download history viewer
- [x] Save-location prompt with Music/Videos defaults
- [x] Playlist detection with first-5 preview
- [x] Edge browser-cookie retry on auth failures
- [x] Per-session logging with 30-day rotation

### Planned: Config Cleanup
- [ ] Make `defaultQuality` control the default profile
- [ ] Make `offlineMode` config setting match the `-OfflineMode` switch
- [ ] Make `browserCookies` select the browser used for cookie auth
- [ ] Remove or implement unused config settings

### Planned: Library Mode
- [ ] JSON metadata sidecars
- [ ] SHA-256 hashing
- [ ] Playlist-aware folders
- [ ] Library organization mode

### Planned: Automation
- [ ] Clipboard listener
- [ ] Toast notifications
- [ ] Background queue

### Planned: Profiles & Presets
- [ ] Custom quality profile management
- [ ] Research/mobile/archive presets
- [ ] Profile import/export

### Planned: Integrity & Audit
- [ ] Batch manifests
- [ ] Verification passes
- [ ] Acquisition reports

### Planned: Headless/API Mode
- [ ] Non-interactive CLI options for all prompts
- [ ] Pipeline-friendly exit codes and output
- [ ] Scriptable/headless mode

---

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

---

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

---

## 🙏 Acknowledgments

- **yt-dlp** - The incredible media extraction engine
- **FFmpeg** - The Swiss Army knife of media processing
- **PowerShell Community** - For excellent tooling and support

---

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/kwisdomk/Mr.Roboto/issues)
- **Discussions**: [GitHub Discussions](https://github.com/kwisdomk/Mr.Roboto/discussions)
- **Documentation**: [Wiki](https://github.com/kwisdomk/Mr.Roboto/wiki)

---

## 🎯 Project Goals

Mr. Roboto is designed to be:

1. **Reliable** - Retries, fallbacks, and resume support
2. **Portable** - No installation, runs from any folder
3. **Hardware-aware** - Detects GPU encoders automatically
4. **Easy to use** - Interactive terminal menu with clear feedback
5. **Extensible** - Modular architecture, planned plugin system

---

**Made with ❤️ for digital archivists, researchers, and media enthusiasts**

*"Domo arigato, Mr. Roboto!"* 🤖
