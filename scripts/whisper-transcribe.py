#!/usr/bin/env python3
"""
Whisper transcription script for Redact.
Uses faster-whisper with stable-ts for improved word-level timestamps.
Outputs JSON transcript to stdout, progress to stderr.
"""

import argparse
import json
import sys
import os


def log(msg: str):
    """Print progress to stderr (parsed by main process)."""
    print(msg, file=sys.stderr, flush=True)


def main():
    parser = argparse.ArgumentParser(description="Transcribe audio with Whisper")
    parser.add_argument("--file", required=True, help="Path to audio/video file")
    parser.add_argument("--model", default="small", help="Whisper model size")
    parser.add_argument("--language", default=None, help="Language code (auto-detect if not set)")
    args = parser.parse_args()

    if not os.path.exists(args.file):
        log(f"Error: File not found: {args.file}")
        sys.exit(1)

    # Redirect stdout to stderr while importing/running libraries,
    # so any library print() calls don't pollute the JSON output.
    real_stdout = sys.stdout
    sys.stdout = sys.stderr

    # Try stable-ts first (better word boundaries), fall back to faster-whisper
    use_stable_ts = False
    try:
        import stable_whisper
        use_stable_ts = True
        log("Using stable-ts for improved timestamps")
    except ImportError:
        log("stable-ts not available, using faster-whisper directly")

    if use_stable_ts:
        result = transcribe_stable_ts(args)
    else:
        result = transcribe_faster_whisper(args)

    # Restore stdout for JSON output
    sys.stdout = real_stdout

    # Output JSON result to stdout
    json.dump(result, sys.stdout, ensure_ascii=False)


def transcribe_stable_ts(args):
    """Transcribe using stable-ts (wraps faster-whisper with better word alignment)."""
    import stable_whisper

    log(f"Loading model: {args.model}")
    model = stable_whisper.load_faster_whisper(args.model)

    log("Transcribing...")
    transcribe_kwargs = {"word_timestamps": True}
    if args.language:
        transcribe_kwargs["language"] = args.language

    result = model.transcribe_stable(args.file, **transcribe_kwargs)

    log("Refining word timestamps...")
    result.adjust_by_silence(args.file)

    segments = []
    detected_language = ""

    for i, segment in enumerate(result.segments):
        words = []
        for word_info in segment.words:
            words.append({
                "word": word_info.word.strip(),
                "start": round(word_info.start, 3),
                "end": round(word_info.end, 3),
                "confidence": round(getattr(word_info, "probability", 0.9), 3),
                "deleted": False,
            })

        if words:
            segments.append({"id": i, "words": words})

    # Get language from result
    if hasattr(result, "language"):
        detected_language = result.language or ""

    # Estimate duration from last word
    duration = 0
    if segments:
        last_seg = segments[-1]
        if last_seg["words"]:
            duration = last_seg["words"][-1]["end"]

    log("Transcription complete")
    return {
        "segments": segments,
        "language": detected_language,
        "duration": round(duration, 3),
    }


def transcribe_faster_whisper(args):
    """Transcribe using faster-whisper directly."""
    from faster_whisper import WhisperModel

    log(f"Loading model: {args.model}")
    model = WhisperModel(args.model, compute_type="int8")

    log("Transcribing...")
    transcribe_kwargs = {"word_timestamps": True}
    if args.language:
        transcribe_kwargs["language"] = args.language

    raw_segments, info = model.transcribe(args.file, **transcribe_kwargs)

    segments = []
    detected_language = info.language or ""

    for i, segment in enumerate(raw_segments):
        words = []
        if segment.words:
            for word_info in segment.words:
                words.append({
                    "word": word_info.word.strip(),
                    "start": round(word_info.start, 3),
                    "end": round(word_info.end, 3),
                    "confidence": round(word_info.probability, 3),
                    "deleted": False,
                })

        if words:
            segments.append({"id": i, "words": words})

        # Report progress
        if info.duration and info.duration > 0:
            progress = min(100, int((segment.end / info.duration) * 100))
            log(f"{progress}% - Processing segment {i + 1}")

    duration = info.duration or 0
    if not duration and segments:
        last_seg = segments[-1]
        if last_seg["words"]:
            duration = last_seg["words"][-1]["end"]

    log("Transcription complete")
    return {
        "segments": segments,
        "language": detected_language,
        "duration": round(duration, 3),
    }


if __name__ == "__main__":
    main()
