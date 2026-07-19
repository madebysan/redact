<p><img src="assets/app-icon.png" width="128" height="128" alt="Redact app icon"></p>

<h1>Redact</h1>

<p>Edit spoken video and audio as text.<br>
Cut takes, tighten pauses, clean up speech, and export without a timeline.</p>

<p><strong>Version 2.0.0</strong> · macOS 14+ · Apple Silicon</p>

<p>
  <img src="https://img.shields.io/badge/Swift-f05138" alt="Swift">
  <img src="https://img.shields.io/badge/AppKit-0066cc" alt="AppKit">
  <img src="https://img.shields.io/badge/WhisperKit-0066cc" alt="WhisperKit">
  <img src="https://img.shields.io/badge/ffmpeg-007808" alt="ffmpeg">
</p>

<p><a href="https://github.com/madebysan/redact/releases/latest">Download Redact</a></p>

![Redact 2 showing its transcript-first editor, video preview, and editing toolbar](assets/screenshot.png)

Redact is a native macOS editor for podcasts, interviews, tutorials, pitch videos, and other spoken media. Instead of cutting clips on a timeline, you edit the transcript and preview the result.

## Features

- **Edit by deleting words.** Select any part of the transcript and press Delete. Removed words stay visible and can be restored or undone.
- **Review automatic cleanup.** Clean Up finds clear filler words, adjacent repetitions, and long pauses. Choose categories or individual suggestions before applying everything as one undoable edit.
- **Edit with Codex or Claude Code.** Redact can prepare a privacy-safe transcript snapshot and copy a ready-made connection prompt. Paste it into the agent, wait for it to confirm the snapshot is connected, then describe the edit there. You review the exact words and projected duration before Redact applies the proposal as one undoable edit.
- **Correct the transcript.** Fix a mistaken word without changing its timing or your edit decisions.
- **Review every cut.** Jump to the previous or next edit, see how much time was removed, scrub with exact edited-time feedback, and inspect removed ranges on the source waveform.
- **Preview the finished pacing.** Playback, transcript highlighting, edited duration, volume, full-screen video, and the waveform stay mapped to the same cut decisions.
- **Find, copy, and select normally.** Redact uses native macOS text selection and the system Find panel.
- **Enhance audio.** A simple export switch reduces steady background noise and balances loudness. It is local, optional, and off by default.
- **Control the output.** Review the format, dimensions, speed, and final duration before export. Redact remembers compatible choices and can create a matching SRT subtitle file beside the media.
- **Save work in progress.** Projects use the `.rdt` format. If the original media moves, the transcript remains editable and Redact can relink the file.
- **Keep media private by default.** Transcription, editing, preview generation, and export happen on your Mac. Edit with Agent is an explicit opt-in that shares transcript text with the cloud agent you choose; source media and project paths are excluded.

## How it works

1. Import an MP4, MKV, WebM, MOV, AVI, MP3, WAV, or M4A file.
2. [WhisperKit](https://github.com/argmaxinc/WhisperKit) transcribes it on your Mac with word-level timing. The selected model downloads automatically the first time you use it.
3. Delete words manually, correct transcription mistakes, use **Clean Up**, or choose **Edit > Edit with Agent…** to copy a connection prompt for Codex or Claude Code. Ask for the edit in that agent conversation after it connects.
4. Press Space to preview the edited result. Review cut transitions with Previous/Next Edit, inspect cut markers on the waveform, or enter full-screen preview. Hide the preview when you want the transcript to use the full window.
5. Save the project as an `.rdt` file. If the source media moves, Redact opens the transcript and lets you relink it.
6. Export video as MP4, MKV, or WebM; audio as M4A, MP3, or WAV; or adjusted subtitles as SRT.

Preview, saved projects, subtitles, and media export all use the same edit decisions. The waveform stays available for scrubbing, and the preview can be hidden when you want more room for the transcript.

Redact does not upload your media or transcript during its normal editing workflow. WhisperKit may use the network to download model files. Audio extraction and final rendering run through your local FFmpeg installation. If you choose Edit with Agent, Redact shows a disclosure before creating a sanitized transcript snapshot for the selected cloud agent; the snapshot excludes media, paths, bookmarks, and fingerprints.

## Export formats

| Output | Video | Audio |
|---|---|---|
| MP4 | H.264 | AAC |
| MKV | H.264 | AAC |
| WebM | VP9 | Opus |
| M4A | — | AAC |
| MP3 | — | MP3 |
| WAV | — | PCM |
| SRT | Adjusted subtitle timing | — |

## Install

Install FFmpeg first:

```bash
brew install ffmpeg
```

Open the Redact DMG, drag Redact to Applications, and launch it.

Redact 2 is built for Apple Silicon and requires macOS 14 or newer. It is distributed outside the Mac App Store and uses a user-installed FFmpeg executable for media processing.

## Shortcuts and preferences

| Action | Shortcut |
|---|---|
| Open project | Cmd+O |
| Import media | Cmd+Shift+O |
| Save project | Cmd+S |
| Export media | Cmd+Option+E |
| Export SRT | Cmd+Shift+E |
| Undo / Redo | Cmd+Z / Cmd+Shift+Z |
| Delete selected | Delete |
| Review automatic cleanup | Edit > Clean Up Transcript |
| Copy an agent connection prompt | Edit > Edit with Agent |
| Correct selected word | Edit > Correct Selected Word |
| Restore selected words | Edit > Restore Selected Words |
| Find in transcript | Cmd+F |
| Select all | Cmd+A |
| Play / Pause | Space |
| Skip back / forward 5 seconds | Left / Right arrow |
| Previous / next edit | Playback menu or preview controls |
| Hide / show preview | Cmd+Option+P |
| Full-screen preview | View > Enter Full Screen Preview |
| Settings | Cmd+, |

Redact uses a dark interface only. Settings include a dropdown of 14 built-in macOS transcript fonts with adjustable text size, letter spacing, line spacing, playback highlight color, a transcript-only Restore Defaults action, and clearly labeled Whisper model trade-offs. Format, quality, speed, audio enhancement, and optional subtitle export are remembered for the next compatible export.

## Build from source

From the repository root:

```bash
brew install ffmpeg
./script/build_and_run.sh
```

The native UI uses Swift and AppKit. AVFoundation handles preview playback and timeline mapping, [DSWaveformImage](https://github.com/dmrschmidt/DSWaveformImage) renders the waveform, and FFmpeg handles extraction and final media export.

Release helpers live in `scripts/`:

```bash
./scripts/build-release.sh sign
./scripts/build-release.sh dmg
./scripts/build-release.sh release
```

## Feedback

Found a bug or have a feature idea? [Open an issue](https://github.com/madebysan/redact/issues).

## License

[MIT](LICENSE)

Made by [santiagoalonso.com](https://santiagoalonso.com)
