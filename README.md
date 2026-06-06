# 🤖 Mr. Roboto v2.0

**The Autonomous Media Acquisition & Archival Agent**

A portable, self-healing PowerShell automation suite for high-fidelity media acquisition, transformation, and archival.

---

## ✨ Features

### 🔧 Self-Healing Architecture
- **Zero Configuration** - Works out of the box, no installation required
- **Auto-Download Dependencies** - Automatically fetches yt-dlp and FFmpeg on first run
- **Hardware Detection** - Automatically detects and uses GPU acceleration (NVENC/QSV/AMF)
- **Smart Fallbacks** - Gracefully handles missing hardware or network issues

### 🎯 Intelligent Automation
- **Quality Profiles** - Choose from Ultra (4K), High (1080p), or Mobile (720p)
- **Resume Capability** - Automatically resume interrupted downloads
- **Progress Tracking** - Real-time progress with speed and ETA
- **Error Recovery** - Automatic retry with exponential backoff

### 🎨 Polished Interface
- **Beautiful CLI** - Modern terminal UI with Unicode indicators
- **System Info Banner** - Shows GPU, FFmpeg, and yt-dlp versions
- **Color-Coded Logs** - Easy-to-read status messages
- **Professional Feedback** - Clear progress bars and status updates

---

## 🚀 Quick Start

### Prerequisites

**Windows 10/11**
- PowerShell 5.1 or later (built-in)
- Internet connection (for first run)

**Linux**
- PowerShell 7+ (`pwsh`) — [install guide](https://aka.ms/install-powershell)
- `tar` (pre-installed on all major distros)
- Internet connection (for first run)
- Optional: `lspci` (GPU detection on non-NVIDIA systems) — `sudo apt install pciutils`
- Optional: `nvidia-smi` (NVIDIA GPU detection) — install via your NVIDIA driver package

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/kwisdomk/msr.git
   cd msr
   ```

2. **Run Mr. Roboto**

   **Windows** — double-click `roboto.bat`, or from PowerShell:
   ```powershell
   .\roboto.bat
   ```
   > The bat file sets the execution policy automatically (process-scoped — no system-wide changes).

   **Linux**
   ```bash
   ./roboto.sh
   ```
   > `roboto.sh` requires `pwsh` (PowerShell 7+). It will error with an install link if `pwsh` is not found.

On first run, Mr. Roboto will:
- Create necessary directories
- Download yt-dlp and FFmpeg (platform-appropriate binaries)
- Detect your GPU capabilities
- **Prompt you to select a browser for YouTube cookie authentication**
- Present the interactive menu

---

## 📖 Usage

### Interactive Mode

Double-click **`roboto.bat`** and follow the prompts.

You'll see:

```
╔═══════════════════════════════════════════════════════╗
║          M R .  R O B O T O  v2.0                     ║
║      Autonomous Media Acquisition Agent               ║
╚═══════════════════════════════════════════════════════╝

  System Information
  ─────────────────────────────────────────────────────
  GPU      : NVIDIA GeForce RTX 3050
  Encoder  : h264_nvenc
  Arch     : x64
  yt-dlp   : 2026.01.28
  FFmpeg   : 7.0.2
  Mode     : Interactive

  ──────────────────────────────────────────────────────
  Ready to acquire media.

  ┌─────────────────────────────────────────────────────────┐
  │  Mr. Roboto — Acquisition Mode                          │
  ├─────────────────────────────────────────────────────────┤
  │  VIDEO                                                  │
  │  [1] Ultra   4K MKV     (maximum quality)               │
  │  [2] High    1080p MP4  (recommended)                   │
  │  [3] Mobile  720p MP4   (compact, portable)             │
  ├─────────────────────────────────────────────────────────┤
  │  AUDIO ONLY                                             │
  │  [4] FLAC    Lossless archive  (archival grade)         │
  │  [5] Opus    Hi-Fi native      (bit-perfect, smallest)  │
  │  [6] MP3     320 kbps          (universal compat)       │
  ├─────────────────────────────────────────────────────────┤
  │  [Q] Quit                                               │
  └─────────────────────────────────────────────────────────┘

  Choice:
```

### Quality Profiles

| Profile | Resolution | Container | Use Case |
|---------|-----------|-----------|----------|
| **Ultra** | 4K (2160p) | MKV | Maximum quality, archival |
| **High** | 1080p | MP4 | Recommended, balanced |
| **Mobile** | 720p | MP4 | Smaller files, portable |

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
    "libraryMode": false
  }
}
```

### Configuration Options

| Setting | Description | Default |
|---------|-------------|---------|
| `defaultQuality` | Default quality profile (ultra/high/mobile) | `high` |
| `autoUpdate` | Auto-update yt-dlp on startup | `true` |
| `offlineMode` | Skip update checks | `false` |
| `notifications` | Enable toast notifications (Phase 4) | `true` |
| `preferredContainer` | Default container format | `mp4` |
| `libraryMode` | Enable metadata sidecars (Phase 3) | `false` |

---

## 📁 Directory Structure

```
/MrRoboto/
├── roboto.bat              # ← Windows launcher (handles execution policy)
├── roboto.sh               # ← Linux/macOS launcher (requires pwsh)
├── roboto.ps1              # Core script (cross-platform)
├── config.json             # Configuration (includes browserCookies setting)
├── README.md               # This file
├── /bin/                   # Auto-downloaded binaries
│   ├── /x64/
│   │   ├── yt-dlp.exe      # Windows
│   │   ├── yt-dlp          # Linux
│   │   ├── ffmpeg.exe      # Windows
│   │   └── ffmpeg          # Linux
│   ├── /x86/               # Windows 32-bit only
│   └── /arm64/             # Linux ARM64 (Raspberry Pi, etc.)
├── /downloads/             # Your downloaded media
├── /logs/                  # Session logs
├── /state/                 # Resume data
└── /cache/                 # Temporary files
```

---

## 🎮 Hardware Acceleration

Mr. Roboto automatically detects and uses GPU acceleration:

**Windows**

| GPU Vendor | Encoder | Performance |
|------------|---------|-------------|
| **NVIDIA** | NVENC | ⚡⚡⚡ Fastest |
| **Intel** | QSV | ⚡⚡ Fast |
| **AMD** | AMF | ⚡⚡ Fast |
| **None** | libx264 | ⚡ Software |

**Linux**

| GPU Vendor | Encoder | Detection Method |
|------------|---------|-----------------|
| **NVIDIA** | NVENC | `nvidia-smi` |
| **Intel** | QSV | `lspci` |
| **AMD** | VA-API | `lspci` |
| **None** | libx264 | Fallback |

> On Linux, AMD uses `h264_vaapi` (VA-API) rather than AMF, which is the standard hardware video acceleration API on Linux.

No configuration needed - it just works!

---

## 🔄 Resume Downloads

If a download is interrupted:

1. Restart Mr. Roboto
2. You'll be prompted to resume
3. Download continues from where it left off

Resume data is stored in `/state/session.json`

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
- Windows: manually download from https://github.com/BtbN/FFmpeg-Builds/releases
- Linux: `sudo apt install ffmpeg` (or your distro's equivalent) then re-run

### "Download failed" / YouTube bot detection
- Mr. Roboto will detect the bot-detection error automatically and escalate to browser cookies
- Make sure you are **logged into YouTube** in the browser you select
- Close the browser before running Mr. Roboto (some browsers lock the cookie database)
- **Linux**: supported browsers for cookie auth are `firefox`, `chrome`, `chromium`, `brave`, `vivaldi`, `opera` — at least one must be installed
- **Windows**: defaults to `edge`
- Check `/logs/` for the full error output

### "GPU not detected"
- Mr. Roboto will fallback to software encoding (`libx264`)
- **Windows**: update GPU drivers and check Device Manager
- **Linux (NVIDIA)**: ensure the NVIDIA driver is installed — `nvidia-smi` should return GPU info
- **Linux (AMD/Intel)**: install `pciutils` (`sudo apt install pciutils`) so `lspci` is available

### Linux: "pwsh not found"
Install PowerShell 7:
```bash
# Ubuntu/Debian
sudo apt-get install -y wget apt-transport-https
wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb"
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update && sudo apt-get install -y powershell
```
Or visit: https://aka.ms/install-powershell

### Linux: Permission denied on `roboto.sh`
```bash
chmod +x roboto.sh
```

---

## 🗺️ Roadmap

### ✅ Phase 1-2: MVP (Current)
- [x] Self-healing bootstrapper
- [x] GPU detection
- [x] Interactive menu
- [x] Quality profiles
- [x] Resume capability
- [x] Browser cookie authentication (YouTube bot detection bypass)
- [x] Audio-only profiles (FLAC / Opus / MP3)

### 🚧 Phase 3: Library Mode (Next)
- [ ] Thumbnail embedding
- [ ] JSON metadata sidecars
- [ ] SHA-256 hashing
- [ ] Playlist-aware folders

### 📋 Phase 4: Automation
- [ ] Clipboard listener daemon
- [ ] Toast notifications
- [ ] Background processing

### 🎯 Phase 5: Profiles & Presets
- [ ] Custom quality profiles
- [ ] Research/mobile/archive modes
- [ ] Profile import/export

### 📈 Phase 6: Integrity & Audit
- [ ] Batch manifests
- [ ] Verification passes
- [ ] Acquisition reports

### 🔌 Phase 7: API/Headless Mode
- [ ] CLI entrypoints
- [ ] Pipeline integration
- [ ] Scriptable automation

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

- **Issues**: [GitHub Issues](https://github.com/kwisdomk/msr/issues)
- **Discussions**: [GitHub Discussions](https://github.com/kwisdomk/msr/discussions)
- **Documentation**: [Wiki](https://github.com/kwisdomk/msr/wiki)

---

## 🎯 Project Goals

Mr. Roboto is designed to be:

1. **Reliable** - Self-healing, automatic recovery
2. **Portable** - Zero installation, works anywhere
3. **Intelligent** - Hardware-aware, optimized processing
4. **Professional** - Polished UX, comprehensive logging
5. **Extensible** - Modular architecture, future-proof

---

**Made with ❤️ for digital archivists, researchers, and media enthusiasts**

*"Domo arigato, Mr. Roboto!"* 🤖