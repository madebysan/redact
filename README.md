<p><img src="assets/app-icon.png" width="128" height="128" alt="Redact app icon"></p>

<h1>Redact</h1>

<p>Edit videos by trimming the transcript.<br>
Cut takes, tighten pauses, clean up speech, and export without a timeline.</p>

<p><strong>Version 2.1.0</strong> · macOS 14+ · Apple Silicon</p>

<p>
  <img src="https://img.shields.io/badge/Swift-f05138" alt="Swift">
  <img src="https://img.shields.io/badge/AppKit-0066cc" alt="AppKit">
  <img src="https://img.shields.io/badge/WhisperKit-0066cc" alt="WhisperKit">
  <img src="https://img.shields.io/badge/ffmpeg-007808" alt="ffmpeg">
</p>

<p><a href="https://github.com/madebysan/redact/releases/latest">Download Redact</a></p>

![Redact editing the public-domain trailer for His Girl Friday (1940): the transcript in paragraphs with a filler and one line struck out, pause chips between lines, the floating preview showing Cary Grant and Rosalind Russell, and the waveform below with the cuts marked](assets/screenshot.png)

Redact is a Mac editor for podcasts, interviews, tutorials and other spoken media. You read the transcript like a document, cut the words you don't want, and the video follows.

- Select words and press Delete, or press X to cut the whole sentence.
- Remove filler words, repeats and long pauses in one click each.
- Ask Codex or Claude Code for an edit, then approve the cuts it proposes.

## How it works

Import a video or audio file and Redact transcribes it on your Mac with [WhisperKit](https://github.com/argmaxinc/WhisperKit). The transcript reads as paragraphs, each with its start time in the margin, and pauses show as small length chips you can click to tighten. The preview floats in a corner and plays the edited result; drag it aside or hide it while you read. The waveform along the bottom shows what is kept and what is cut.

You can play every change before you export it, and undo any of them. Export as MP4, MKV, WebM, M4A, MP3 or WAV, as subtitles with adjusted timing, or as an EDL or Final Cut Pro XML cut list for Premiere Pro, Final Cut Pro and DaVinci Resolve. Features, formats and preferences are in [docs/how-it-works.md](docs/how-it-works.md).

## Privacy

Transcription and editing stay on your Mac. Redact goes online for three things: the first transcription downloads the Whisper model from Hugging Face, FFmpeg is downloaded only if you accept the offer, and [Sparkle](https://sparkle-project.org) checks for updates. Agent editing is opt-in and shares only a transcript snapshot with the agent you choose, never the media or file paths.

## Install

Download Redact from the [latest release](https://github.com/madebysan/redact/releases/latest) and drag it to Applications. It needs Apple Silicon and macOS 14. The first time you import or export, Redact offers to download FFmpeg (about 57 MB, October 2026) into its own Application Support folder; if you already have FFmpeg from Homebrew, it uses that. To build it yourself, run `./script/build_and_run.sh`.

---

[MIT](LICENSE). Third-party components and their licenses are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Made by [santiagoalonso.com](https://santiagoalonso.com)
