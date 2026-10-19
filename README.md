<p><img src="assets/app-icon.png" width="128" height="128" alt="Redact app icon"></p>

<h1>Redact</h1>

<p>Edit videos by trimming the transcript.<br>
Cut takes, tighten pauses, clean up speech, and export without a timeline.</p>

<p><strong>Version 2.0.1</strong> · macOS 14+ · Apple Silicon</p>

<p>
  <img src="https://img.shields.io/badge/Swift-f05138" alt="Swift">
  <img src="https://img.shields.io/badge/AppKit-0066cc" alt="AppKit">
  <img src="https://img.shields.io/badge/WhisperKit-0066cc" alt="WhisperKit">
  <img src="https://img.shields.io/badge/ffmpeg-007808" alt="ffmpeg">
</p>

<p><a href="https://github.com/madebysan/redact/releases/latest">Download Redact</a></p>

![Redact's welcome tour introducing transcript-first editing](assets/intro.gif)

Redact is a Mac editor for podcasts, interviews, tutorials and other spoken media: you edit the words, and the video follows.

- Select words in the transcript and press Delete to cut them.
- Clean Up finds filler words, repeats and long pauses for you to review.
- Ask Codex or Claude Code for an edit and approve the proposed cuts.

## How it works

Import a video or audio file and Redact transcribes it on your Mac with [WhisperKit](https://github.com/argmaxinc/WhisperKit). Delete words, run Clean Up, or describe an edit to an agent; every change previews before you apply it and can be undone. Export as MP4, MKV, WebM, M4A, MP3 or WAV, as subtitles with adjusted timing, or as an EDL or Final Cut Pro XML cut list for Premiere Pro, Final Cut Pro and DaVinci Resolve. Features, formats and preferences are in [docs/how-it-works.md](docs/how-it-works.md).

## Privacy

Transcription and editing stay on your Mac. Agent editing is opt-in and shares only a transcript snapshot with the agent you choose, never the media or file paths. Redact checks for updates through [Sparkle](https://sparkle-project.org).

## Install

Download Redact from the [latest release](https://github.com/madebysan/redact/releases/latest) and drag it to Applications. It needs Apple Silicon and macOS 14. The first time you import or export, Redact offers to download FFmpeg (about 57 MB) and keeps it in its own Application Support folder; if you already have FFmpeg from Homebrew, Redact uses that instead. To build it, run `./script/build_and_run.sh`.

---

[MIT](LICENSE). Third-party components and their licenses are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Made by [santiagoalonso.com](https://santiagoalonso.com)
