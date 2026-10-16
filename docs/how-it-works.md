# How Redact works

Editing features, export formats, preferences and release tooling. The short version is the [README](../README.md).

## Editing

### Edit with Codex or Claude Code

Prepare a privacy-safe transcript snapshot, paste the connection prompt into Codex or Claude Code, and describe the edit you want. Redact shows the proposed cuts and new duration before applying everything as one undoable edit.

![Edit with Agent dialog for connecting Redact to Codex or Claude Code](../assets/edit-with-agent.png)

### Auto-trim pauses and filler words

Clean Up finds clear filler words, repeated words, and long pauses. Review every suggestion, choose what to keep, and apply the selected changes in one click.

![Automatic transcript cleanup with suggested repeated-word and long-pause edits](../assets/automatic-cleanup.png)

### Select, delete, and export

Highlight words and press Delete. Preview the finished pacing, restore any cut, then export the result as video, audio, or adjusted subtitles.

## Export formats

| Output | Video | Audio |
|---|---|---|
| MP4 | H.264 | AAC |
| MKV | H.264 | AAC |
| WebM | VP9 | Opus |
| M4A |: | AAC |
| MP3 |: | MP3 |
| WAV |: | PCM |
| SRT | Adjusted subtitle timing |: |

## Preferences

Redact includes keyboard shortcuts for common editing, playback, project, and export actions.

Redact uses a dark interface only. Settings include a dropdown of 14 built-in macOS transcript fonts with adjustable text size, letter spacing, line spacing, playback highlight color, a transcript-only Restore Defaults action, and clearly labeled Whisper model trade-offs. Format, quality, speed, audio enhancement, and optional subtitle export are remembered for the next compatible export.

## Building and releasing

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
./scripts/make-appcast.sh <dmg> <download-url> <release-notes.md>
```

Updates use [Sparkle](https://sparkle-project.org). `make-appcast.sh` writes `appcast.xml` for a notarized DMG, signed with the update key in the login keychain; upload it to the same GitHub release as the DMG.
