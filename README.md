<p align="center">
  <img src="assets/app-icon.png" width="128" height="128" alt="Redact app icon">
</p>
<h1 align="center">Redact</h1>
<p align="center">Trim video by deleting from its transcript.<br>
No timeline, no video editor. Select words, delete, export.</p>
<p align="center"><strong>Version 1.3.0</strong> · macOS 14+ · Apple Silicon & Intel</p>
<p align="center"><a href="https://github.com/madebysan/redact/releases/latest"><strong>Download Redact</strong></a></p>

---

<p align="center">
  <img src="assets/screenshot.png" width="720" alt="Redact app screenshot showing video preview, word-level transcript editing, and preferences panel">
</p>

---

Redact is what I wanted from a text-based video editor. Trim a clip by editing its transcript. Runs locally. Private. Free.

It's best for talking-head work where the edit is mostly "cut the bad takes and tighten the pacing". Podcasts, interviews, tutorials, pitch videos, anything where the cadence matters more than the visuals.

## How it works

1. Import a video or audio file. MP4, MKV, WebM, MOV, AVI, MP3, WAV, M4A all work.
2. [WhisperKit](https://github.com/argmaxinc/WhisperKit) transcribes on-device. Word-level timestamps.
3. Click words to select. Delete to mark them for removal. Click-drag, shift-click, and cmd-click all work the way they do in any text editor.
4. Hit Space to play. Deleted sections are skipped live with an audio crossfade so cuts don't sound like cuts.
5. Export. FFmpeg re-cuts the original to match your edited transcript. MP4, MKV, or WebM.

Transcription runs on-device through WhisperKit (CoreML + Metal under the hood, no Python, no cloud). You can switch models in Preferences. English-only and turbo variants both ship. The waveform sits along the bottom so you can click anywhere to scrub. Undo and redo are unlimited. Projects save as `.rdt` files when you want to come back to an edit.

## Export

- **Video.** MP4, MKV, or WebM. Quality and speed presets in Preferences.
- **SRT.** Subtitle file with timestamps already adjusted for your deletions.
- **Voice-over (optional).** If you set an ElevenLabs API key, you can export a re-read of the edited transcript in a voice you pick.

## Install

Download the latest `.dmg` from [Releases](https://github.com/madebysan/redact/releases/latest), open it, and drag **Redact** to Applications. If macOS blocks the first launch, open **System Settings → Privacy & Security** and click "Open Anyway".

One external dependency: **FFmpeg**.

```bash
brew install ffmpeg
```

WhisperKit is built in and downloads the selected model automatically on first use.

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
| Preferences | Cmd+, |

## Preferences

What you can tune: transcript font, size, and highlight color. Dark / Light / System theme. Whisper model. Audio crossfade duration on playback and export. Output video quality and encoder preset. ElevenLabs API key and voice for TTS export.

## Building from source

```bash
git clone https://github.com/madebysan/redact.git
cd redact
swift build
swift run Redact
```

Builds with Xcode 16+ targeting macOS 14+.

## Tech stack

- Swift + AppKit for the native macOS UI
- AVFoundation with a periodic time observer driving the live skip-and-fade loop
- [WhisperKit](https://github.com/argmaxinc/WhisperKit) for on-device speech-to-text (CoreML + Metal)
- [DSWaveformImage](https://github.com/dmrschmidt/DSWaveformImage) for waveform rendering
- FFmpeg (subprocess) for audio extraction and final video export

## Feedback

Found a bug or have a feature idea? [Open an issue](https://github.com/madebysan/redact/issues).

## License

[MIT](LICENSE)

---

Made by [santiagoalonso.com](https://santiagoalonso.com)
