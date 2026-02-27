<p align="center">
  <img src="assets/app-icon.png" width="128" height="128" alt="Redact app icon">
</p>
<h1 align="center">Redact</h1>
<p align="center">Remove unwanted words from video.<br>
Click words in the transcript to delete them — Redact cuts them from the video.</p>
<p align="center"><strong>Version 1.0.0</strong> · macOS 14+ · Apple Silicon & Intel</p>
<p align="center"><a href="https://github.com/madebysan/Redact-Swift/releases/latest"><strong>Download Redact</strong></a></p>

---

## How it works

1. **Import** a video or audio file (MP4, MKV, WebM, MOV, AVI, MP3, WAV, M4A)
2. **Transcription** runs automatically via [faster-whisper](https://github.com/SYSTRAN/faster-whisper) — word-level timestamps
3. **Click words** to select, then press Delete to mark them for removal
4. **Play** — deleted sections are skipped in real-time with smooth audio fades
5. **Export** — FFmpeg renders the final video with deleted sections cut out

## Features

- Word-level transcript editing with click, drag, shift-click, and cmd-click selection
- Real-time preview — plays through edits with 70ms audio crossfades
- Waveform visualization with click-to-seek
- Unlimited undo/redo
- Export to MP4, MKV, or WebM with quality and speed options
- Export SRT subtitles (timestamps adjusted for deletions)
- Save/load `.rdt` project files
- Native macOS app — no Electron, no browser

## Prerequisites

Redact uses external tools for transcription and video processing. Install them before first use:

### FFmpeg (required)

```bash
brew install ffmpeg
```

### Python 3 + faster-whisper (required for transcription)

```bash
brew install python3
pip3 install faster-whisper
```

Or use a virtual environment:

```bash
python3 -m venv ~/.venv/whisper
source ~/.venv/whisper/bin/activate
pip install faster-whisper
```

Redact looks for a venv at `~/Projects/redact/.venv` and `~/Projects/Redact-Swift/.venv`, or falls back to system Python.

## Install

1. Download the latest `.dmg` from [Releases](https://github.com/madebysan/Redact-Swift/releases/latest)
2. Open the DMG and drag **Redact** to Applications
3. Launch Redact — if macOS blocks it, go to System Settings > Privacy & Security and click "Open Anyway"

## Keyboard shortcuts

| Action | Shortcut |
|--------|----------|
| Import media | Cmd+O |
| Save project | Cmd+S |
| Export video | Cmd+E |
| Export SRT | Cmd+Shift+E |
| Undo | Cmd+Z |
| Redo | Cmd+Shift+Z |
| Delete selected | Delete |
| Select all | Cmd+A |
| Play / Pause | Space |
| Skip back 5s | Left arrow |
| Skip forward 5s | Right arrow |

## Building from source

```bash
git clone https://github.com/madebysan/Redact-Swift.git
cd Redact-Swift
swift build
swift run Redact
```

Release build:

```bash
./scripts/build-release.sh          # Build unsigned .app
./scripts/build-release.sh sign      # Build + code sign
./scripts/build-release.sh release   # Build + sign + notarize + DMG
```

## Tech stack

- **Swift + AppKit** — native macOS UI
- **AVFoundation** — video playback with CVDisplayLink-driven 60fps sync
- **DSWaveformImage** — waveform visualization (only external dependency)
- **FFmpeg** (subprocess) — audio extraction and video export
- **faster-whisper** (Python subprocess) — speech-to-text with word timestamps

## License

MIT License — see [LICENSE](LICENSE) for details.

---

<p align="center">Made by <a href="https://santiagoalonso.com">santiagoalonso.com</a></p>
