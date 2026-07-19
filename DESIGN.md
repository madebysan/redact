# Redact Design System

## Product intent

Redact is a native macOS editor for removing spoken words from audio and video by editing a transcript. The interface should feel direct, quiet, and dependable: open media, read what was said, remove what should not remain, preview the result, and export it.

The transcript is the product's primary editing surface. Video, waveform, transport, and export controls support that task without competing with it.

## Design principles

1. **Transcript first.** Give the words the most useful space and make every edit state legible in place.
2. **One edit, one result.** Selection, duration, preview, subtitles, saved projects, and export must all reflect the same edit decision list.
3. **Native and discoverable.** Prefer standard macOS controls, menus, keyboard behavior, focus, and accessibility. Icon-only actions require familiar SF Symbols, precise tooltips, VoiceOver labels, and an equivalent menu command.
4. **Calm during long work.** Keep surfaces neutral and motion restrained. Progress and errors should explain what is happening without obscuring the document.
5. **Fast by default.** Loading and editing long transcripts must feel immediate. Work that cannot finish immediately must be cancellable and report its stage accurately.

## Atmosphere

The current visual language is dark, low-contrast, and tool-like, with a single blue accent and red reserved for removal and errors. V2 should preserve that restrained native character. It should not resemble a multitrack video editor, a dashboard, or a decorative AI product.

Keywords: focused, editorial, native, precise, quiet, trustworthy.

## Color

Colors are centralized in `Sources/Theme.swift`. Redact currently ships in Dark Aqua only. The unused light token values remain compatibility scaffolding until a separate code-cleanup pass; they are not a supported product appearance.

| Token | Dark | Use |
| --- | --- | --- |
| `surface0` | `#0A0A0A` | Window and video background |
| `surface1` | `#141414` | Controls, waveform, settings cards |
| `surface2` | `#1A1A1A` | Raised or selected secondary surfaces |
| `surface3` | `#2A2A2A` | Stronger separation and hover states |
| `accent` | `#3B82F6` | Selection, current time, primary emphasis |
| `error` | `#EF4444` | Errors and deleted-word strike-through |
| `textPrimary` | `#D4D4D4` | Transcript and primary labels |
| `textSecondary` | `#999999` | Secondary labels |
| `textTertiary` | `#808080` | Time and supporting metadata |
| `textDimmed` | `#595959` | Disabled and low-priority text |
| `divider` | `#262626` | Panel boundaries |

Deleted transcript words use primary text at 35% opacity with a red strike-through. Selected words use the accent at 30% opacity. The current playback word uses the configured highlight color at 20% opacity.

Do not add new product colors for individual states when opacity, a native control state, or an existing semantic token communicates the difference.

## Typography

Redact offers a curated dropdown of built-in macOS font families using their real names. Avenir Next at 15 pt, -0.2 pt letter spacing, and 4 pt line spacing is the default; serif, sans-serif, humanist, and monospaced alternatives can be compared in the live sample. Font choice, size, letter spacing, and line spacing are independent so changing one never resets the others.

| Role | Current specification |
| --- | --- |
| Transcript body | One of 14 curated macOS families; adjustable 10–24 pt; regular |
| Transcript silence | Transcript size minus 2 pt, light |
| Transcript timestamp | Monospaced digits, transcript size minus 3 pt |
| Empty-state title | System 18 pt, medium |
| Progress state | System 16 pt, medium |
| Standard label | System 13 pt, regular or medium by hierarchy |
| Supporting text | System 11-12 pt |
| Transport time | Monospaced digits 11 pt |

V2 may refine sizes after long-transcript usability testing, but it must preserve Dynamic Type-equivalent user control through the transcript size setting and must not encode information through typography alone.

## Shape, borders, and depth

- The main workspace is flat and separated by surface changes and 1 pt dividers, not shadows.
- Native buttons, menus, sliders, sheets, and focus rings retain system rendering.
- Preference cards use a 10 pt corner radius.
- Export content currently uses a 12 pt corner radius.
- The drag-and-drop target uses a 12 pt corner radius with a 1.5 pt dashed accent border.
- Avoid nested cards in the editor. Transcript blocks are content, not containers.
- Reserve shadows for native window and sheet behavior. Do not add ornamental drop shadows inside the workspace.

## Spacing and sizing

The current implementation uses a practical 4 pt base rhythm with common steps at 4, 8, 12, 16, and 24 pt.

- Main window default: 1400 × 900 pt.
- Main window minimum: 1000 × 700 pt.
- Editing panels: minimum 250 pt each.
- Initial preview panel: 35% of window width.
- Transport row: 84 pt high; waveform row: 60 pt high.
- Export sheet: 520 × 400 pt.
- Settings window: 500 × 560 pt.
- Transcript inset: 24 pt on both axes.
- Transcript row spacing: adjustable 4–18 pt; wrapped-line spacing is one fifth of that value.
- Standard sheet/card outer inset: 24 pt.
- Standard control-row minimum: 36 pt.
- Error banner: 36 pt high.

The transcript receives the larger share of the default window. The preview remains resizable, collapses completely through View > Hide Preview, and restores the user's saved divider ratio across windows and launches. Side-by-side panels never shrink below a usable 250 pt width.

## Layout and responsive behavior

### Editing workspace

The v2 default hierarchy is:

1. Document and state controls in the native titlebar/toolbar.
2. Transcript as the dominant scrollable editor.
3. Adjustable preview and transport as a supporting panel.
4. A shared playback position/waveform treatment derived from the canonical timeline.

The native toolbar uses an opaque unified titlebar at the reference's taller native height, with two 36 pt-tall bordered capsules inspired by compact pro-app command bars. Automatic window tabbing stays disabled so the titlebar remains a single quiet command surface. Clean Up and Agent form the two-icon editing capsule beside the traffic lights using the native toolbar spacing. Save Project, the media-aware Export Video or Export Audio action, Settings, and Close form the four-icon project capsule on the right, with Close always last. Each action uses a 38 × 32 pt icon target, a medium-weight template symbol, a restrained hover fill, a precise tooltip, a VoiceOver label, and an equivalent menu command. Native SF Symbols cover every action except Save Project, which uses a matching monochrome floppy-disk template because macOS does not provide that symbol. The capsules use the existing dark surface and divider tokens; the center remains empty and draggable. The logical window title still carries the project or media name while its visible title stays hidden. Import remains in the empty state and File menu; Undo and Redo remain in the Edit menu with their standard keyboard shortcuts.

At the 1000 pt minimum width, controls must remain usable without clipping. Secondary labels may shorten before primary actions disappear. Below the width needed for a useful side-by-side preview, the preview may move to a compact overlay or collapsible panel after that behavior is prototyped and tested.

### Empty and process states

Empty, importing, transcribing, missing-media, relinking, recovery, and export states should each identify:

- what Redact is doing or needs;
- whether the document is safe;
- the next available action;
- how to cancel or recover when applicable.

Do not replace the whole document with an indeterminate spinner if usable transcript content is already available.

Audio extraction names the file and remains cancellable before transcription starts. Missing source media keeps the transcript editable and presents a persistent 48 pt recovery bar stating that the work is safe, with a direct Relink Media action. Transient relink failures still use the error banner. Export keeps its configuration, progress, cancellation, failure, and completion states inside the modal sheet.

During transcription, keep the state visually quiet: show the native spinner, the exact completed-word count when available, and Cancel. Do not render partial or raw model output; incomplete Whisper text can contain control tokens and is not yet an editable transcript.

### First-launch walkthrough

Each launch presents a 560 × 520 pt native welcome sheet before the empty document unless the user has selected `Do not show again`. Four pages explain only the concepts the main interface cannot teach in place: Redact's transcript-first model, reversible word deletion, reviewed local cleanup, and the optional Claude Code or Codex handoff. Import and Export remain contextual in the main interface rather than adding tour pages.

The walkthrough uses the app icon and the same SF Symbols as the related controls, supports Back, Next, Skip, Return, Escape, and arrow-key navigation, and exposes page progress to VoiceOver. Completing or skipping closes the sheet without suppressing future launches unless `Do not show again` is selected; that opt-out is stored in `UserDefaults`. Help > Welcome to Redact always replays the walkthrough and lets the user change that preference.

## Motion

Motion should explain state changes, not decorate them.

- Current error presentation fades in over 250 ms with ease-out and fades out over 200 ms with ease-in.
- Panel resizing follows the pointer without animation.
- Playback position updates continuously without transition effects.
- V2 progress and completion transitions should use native AppKit timing and honor Reduce Motion.
- Avoid animated transcript reflow after edits. Update affected words and timeline state in place.

## Interaction patterns

### Transcript editing

- Click selects a word.
- Drag selects a contiguous range.
- Shift-click extends from the last selection anchor.
- Command-click adds or removes a word from the selection.
- Command-C copies the native text selection, and Command-F searches the transcript with the system Find panel.
- Double-click a spoken word, or use Edit > Correct Selected Word, to correct display text without changing timing or cut decisions.
- Delete removes the selected spoken range.
- Clicking a deleted word restores it.
- Edit > Restore Selected Words provides the keyboard-only restore path.
- Clean Up analyzes the current non-deleted transcript for clear filler words, adjacent repeated words, and multi-token long pauses. It opens a review sheet before changing the project.
- The cleanup sheet selects all suggestions initially, supports category-level and row-level exclusion, shows local context and approximate removed duration, and applies the reviewed set as one undoable edit.
- Edit > Edit with Agent prepares a sanitized transcript snapshot for Codex or Claude Code only after an explicit cloud-sharing disclosure and a successful project save, then copies a connection prompt.
- The preparation sheet asks only which agent will receive the prompt. The user describes the edit in that agent conversation after the agent confirms the snapshot is connected; the request returns in the proposal as its reviewable goal.
- Agent proposals are deletion-only, attributed but unauthenticated, validated as untrusted input, and reviewed in Redact before one undoable Apply. Agents never write `.rdt` files or invoke Apply, Undo, or Export.
- The agent review distinguishes required, optional, and invalid suggestions; synchronizes checked rows with temporary transcript highlights; and reports authoritative projected duration through `RenderPlan`.
- Long-pause cleanup retains one silence token so pacing is tightened rather than flattened.
- Opening an editor focuses the transcript for immediate keyboard navigation and native Find.
- Space toggles playback when the editor owns keyboard focus.
- Command-Option-E opens Export Media without replacing the native Command-E text-finding behavior.
- Undo and redo must restore both content state and the visible selection/result consistently.

Deleted words remain visible so edits are reversible and understandable. Playback highlighting, selection, deletion, search, and accessibility focus must be distinguishable from one another.

### Edited preview

- View > Hide Preview (Command-Option-P) gives the transcript the full workspace; the same command restores the preview at the saved width ratio.
- Build preview media from the canonical `RenderPlan`, not from a separate deletion calculation.
- Debounce composition rebuilds by 150 ms and keep the previous preview available until the replacement is ready.
- Preserve the current source position when replacing the player item.
- Show current edited time, edited duration, and original source duration in the transport. Keep transcript highlighting and the source waveform mapped through `TimelineMap`.
- Derive the compact cut count, removed duration, final duration, and previous/next edit targets from the current `RenderPlan`. Previous and Next Edit land 1.5 seconds before the cut transition when possible.
- Show removed source-time ranges as restrained red overlays on the source waveform. These are review markers, not draggable timeline clips.
- Keep preview volume and mute as app preferences rather than project data. Moving the volume slider unmutes the preview.
- While the user scrubs, show the target edited time without replacing the canonical playback mapping.
- The preview exposes an overlay full-screen control and an equivalent View-menu command. If the preview is hidden, the command restores it before entering full screen.
- Use the original asset directly when there are no cuts.

### Feedback and errors

- Use inline document states for missing media, relinking, recovery, and export validation.
- Use the 36 pt error banner for transient, recoverable failures.
- Error copy must name the failed action and a useful recovery step when one exists.
- Destructive or irreversible actions require a native confirmation dialog. Ordinary transcript deletions remain immediately undoable and need no confirmation.

### Accessibility

- Preserve keyboard-only import, navigation, selection, delete, cleanup review, restore, undo, save, preview, and export paths.
- Editor and modal transitions focus the first meaningful control and provide an explicit key-view loop.
- Preserve VoiceOver-readable transcript order and state.
- Every symbol-only button needs an accessibility description and tooltip where discovery is not guaranteed.
- Transport controls expose explicit Play, Pause, and five-second skip labels to VoiceOver and macOS UI automation.
- Never rely only on red, opacity, or strike-through to announce an edit state to assistive technology.
- Honor system contrast, focus, and Reduce Motion settings while keeping Redact in Dark Aqua.

## Shared component inventory

| Component | Variants and sizes | Source | Current use |
| --- | --- | --- | --- |
| `Theme` | Dynamic light/dark semantic colors | `Sources/Theme.swift` | All app surfaces and text |
| `EmptyStateView` | Full-window import target | `Sources/Views/EmptyStateView.swift` | Empty document |
| `TranscriptView` | TextKit 2 viewport layout, native selection and Find, configurable type | `Sources/Views/TranscriptView.swift` | Editing workspace |
| `VideoPreviewView` | Empty placeholder or borderless AV player with full-screen overlay action | `Sources/Views/VideoPreviewView.swift` | Editing preview |
| `TransportControlsView` | 84 pt; edit navigation, skip/play, speed, volume, canonical edit summary, seek feedback, edited and original time | `Sources/Views/TransportControlsView.swift` | Editing preview footer |
| `WaveformView` | 60 pt source waveform, 1.5 pt cursor, canonical removed-range overlays | `Sources/Views/WaveformView.swift` | Editing timeline footer |
| `ErrorBannerView` | 36 pt transient error | `Sources/Views/ErrorBannerView.swift` | Window-level failures |
| `TranscribeProgressView` | Spinner, exact progress, cancel | `Sources/Views/TranscribeProgressView.swift` | Transcription |
| `MissingMediaNoticeView` | 48 pt persistent notice with Relink action | `Sources/Views/MissingMediaNoticeView.swift` | Missing source media recovery |
| `CleanupReviewView` | 700 × 520 pt review sheet | `Sources/Views/CleanupReviewView.swift` | Filler, repetition, and long-pause suggestions before one-step application |
| `AgentPreparationView` | 540 × 280 pt disclosure sheet | `Sources/Views/AgentPreparationView.swift` | Agent choice, privacy disclosure, and copy-ready connection prompt |
| `CleanupReviewView` agent mode | 760 × 560 pt review sheet | `Sources/Views/CleanupReviewView.swift` | Attributed required/optional agent proposals, validation issues, and exact projected duration |
| `ExportSheetView` | 520 × 400 pt options/progress sheet | `Sources/Views/ExportSheetView.swift` | Export summary, format, quality, speed, audio enhancement, optional subtitle sidecar, and progress |
| `WelcomeWalkthroughView` | 560 × 520 pt, four pages | `Sources/Views/WelcomeWalkthroughView.swift` | Launch welcome with persistent opt-out and Help-menu replay |
| Settings cards | 10 pt cards, 36 pt rows, 24 pt insets | `Sources/Views/SettingsWindowController.swift` | Transcript controls with Restore Defaults and clearly labeled transcription models |

Before adding a new shared component, search this inventory and nearby AppKit views. Promote a pattern only when it repeats or establishes a durable interaction contract.

Settings are deliberately limited to transcript typography and highlight color plus Whisper model selection. Appearance is not configurable: Redact uses Dark Aqua regardless of the macOS appearance. The transcript section provides a 14-family font dropdown, precise size and spacing controls, and a live sample; changes also update every open transcript. Voice generation, crossfade, and other off-loop controls do not belong in the v2 settings surface.

## Performance contract

All timings are measured on san's Apple Silicon Mac with a release-like warm process unless a test states otherwise. Synthetic transcript fixtures are deterministic and contain no private media.

| Operation | V2 target at 100K words |
| --- | --- |
| Build canonical `RenderPlan` | under 50 ms |
| Build `TranscriptIndex` | under 50 ms |
| Apply a single edit and update affected transcript state | under 16 ms on the main thread |
| Rebuild a debounced preview composition after editing stops | under 150 ms, off the main thread where possible |
| Scroll an already-loaded transcript | sustained 60 fps with no repeated full-document styling pass |

The Phase 1 synthetic baseline is recorded in `Tests/Performance/README.md`. Later phases must compare against the same fixtures and record media-specific preview/export measurements separately. Private benchmark media must never be committed.

Representative-media acceptance uses the same cut matrix at 0, 10, 100, and 500 cuts. Export duration must stay within 250 ms of the canonical timeline. A 500-cut preview must build within 750 ms, and a long 500-cut export must remain below 1.5 GB peak RSS. Repeated samples must not show a sustained increase in memory, and success, failure, and cancellation must leave no export-batch workspace behind.

## Export contract

Redact probes the source before import and offers only presets supported by its audio and video streams. Audio-only sources never enter the video filter path.

Preview, displayed duration, SRT timestamps, and final export all receive the same canonical `RenderPlan`. Cut ranges are joined without overlapping crossfades because an overlap shortens the final timeline and makes those consumers disagree.

| Output | Video codec | Audio codec |
| --- | --- | --- |
| MP4 video | H.264 | AAC |
| MKV video | H.264 | AAC |
| WebM video | VP9 | Opus |
| M4A audio | None | AAC |
| MP3 audio | None | MP3 |
| WAV audio | None | PCM 16-bit |

The checked-in unit tests validate this matrix and the filter plan. The opt-in FFmpeg integration test renders every offered preset from deterministic synthetic media and probes each result; it does not use or commit private media.

The export sheet states the selected output codecs before export. When an HEVC source will be converted to H.264, it warns that the output may be larger. During export it shows exact progress, elapsed time, and an estimated time remaining. Audio cleanup remains one native `Enhance audio` switch, off by default, with a short description of its effect. It does not expose filter names or strength levels. On applies Redact's light local chain after edits and speed changes: a 70 Hz high-pass, gentle FFT denoising, EBU R128 loudness normalization to -16 LUFS, and a final 48 kHz resample. Off preserves the existing audio path.

Before export, a compact summary states the selected container, output dimensions, speed, and speed-adjusted final duration. Redact remembers the last compatible format, quality, speed, audio-enhancement, and subtitle choices in `UserDefaults`; unsupported saved choices fall back safely. `Also export subtitles` writes a matching SRT sidecar from the same `RenderPlan` after media export succeeds and asks before replacing an existing sidecar. Standalone File > Export SRT remains available.

Export uses six bounded strategies:

- stream-copy unchanged media when the selected container accepts the source codecs and no quality, speed, or audio enhancement transform is requested;
- when audio enhancement is the only transform, copy compatible video and process only its audio;
- seek and transcode a single kept range without constructing a complex filter graph;
- use the canonical kept-range filter graph for ordinary multi-range and variable-frame-rate exports;
- for 2-50 likely constant-frame-rate ranges, use one video selector with sample-level audio segmentation and bounded audio concatenation;
- above 50 likely constant-frame-rate ranges, render sequential batches of at most 50 ranges into private temporary Matroska files with PCM audio, then concatenate with canonical duration directives, stream-copy the video, and encode and optionally enhance the assembled audio once.

## Agent implementation guide

When changing the interface:

1. Read this file, `Sources/Theme.swift`, and the nearest existing view.
2. Keep transcript semantics and `RenderPlan` behavior independent from AppKit presentation.
3. Use existing semantic colors, native controls, and the spacing rhythm before adding tokens or custom drawing.
4. Test the Dark Aqua interface at the 1400 × 900 default and 1000 × 700 minimum window sizes, including while macOS itself uses Light appearance.
5. Verify keyboard operation, focus, VoiceOver labels, Reduce Motion behavior, empty/error/progress states, and a 100K-word transcript where relevant.
6. Update this file when a durable visual or interaction decision changes. Do not use it as a change log.

Run `./scripts/run-ui-smoke-tests.sh` after changing the editor shell, menus, transcript selection, or transport controls. The harness uses generated media only and records its current coverage in `Tests/UI/README.md`.

## Do and do not

### Do

- Make the current edit and its effect obvious.
- Keep deleted words visible and reversible.
- Use labeled primary actions and native menus/shortcuts.
- Keep long-running work cancellable and revision-aware.
- Prefer delta updates over rebuilding the complete transcript.

### Do not

- Introduce a multitrack timeline or pro-video-editor chrome.
- Add decorative gradients, glass cards, oversized marketing type, or unnecessary animation.
- Hide primary import, save, relink, preview, or export behavior behind ambiguous symbols.
- Let preview, subtitles, duration, save, and export calculate edits independently.
- Store secrets or private media in project files, preferences, fixtures, or the repository.

## Decisions

| Date | Decision | Reason |
| --- | --- | --- |
| 2026-07-15 | Make the transcript the dominant v2 workspace and keep preview adjustable. | Redact's core value is editing speech as text; the preview verifies the edit rather than defining it. |
| 2026-07-15 | Preserve the native AppKit visual language and current semantic palette. | The existing interface is familiar and restrained; v2 needs stronger hierarchy and behavior, not a visual rebrand. |
| 2026-07-15 | Require one canonical edit interpretation across every consumer. | Visible trust depends on preview, subtitles, saved work, duration, and export agreeing exactly. |
| 2026-07-15 | Treat 100K words as the long-transcript performance fixture. | It gives later architecture work a stable, reproducible stress case without committing private media. |
| 2026-07-15 | Run transport on edited time and map it back to source time for transcript and waveform feedback. | The composition has no deleted spans, while words and the source waveform retain their original timestamps. |
| 2026-07-15 | Keep the transcript in a TextKit 2 text view with an indexed word-selection bridge. | Viewport layout scales without giving up native keyboard selection, copying, Find, or accessibility semantics. |
| 2026-07-15 | Treat display-text correction as a transcript revision, not a timing edit. | Corrected words should persist and participate in Undo/Redo without changing preview composition or cut boundaries. |
| 2026-07-15 | Default the preview to 35%, let it collapse from the View menu, and restore its saved ratio. | The transcript stays primary while preview remains immediately available, adjustable, and recoverable. |
| 2026-07-15 | Show labels alongside toolbar icons. | Primary document actions should be understandable at a glance and the complete toolbar fits at the 1000 pt minimum width. |
| 2026-07-18 | Use a compact, workflow-ordered native toolbar. | One labeled-button treatment, consistent type and symbol metrics, clear group spacing, and Close last make the editor quieter without hiding primary work. |
| 2026-07-18 | Replace toolbar labels with two grouped icon capsules. | The supplied pro-app reference creates a calmer title bar while tooltips, VoiceOver labels, menus, and shortcuts preserve discoverability. This supersedes the visible-label treatment. |
| 2026-07-15 | Keep missing-media recovery persistent and make extraction cancellable. | A durable document problem cannot rely on a temporary error, and every long-running import stage needs an exit. |
| 2026-07-18 | Ship Redact in Dark Aqua only. | Light mode is not visually reliable enough to maintain; removing the switch keeps the supported interface focused while old dynamic-color scaffolding can be cleaned separately. |
| 2026-07-15 | Keep only transcript readability, playback highlight, and transcription model preferences. | Every setting must directly support the transcript-edit-preview-export loop or accessibility; retired voice, appearance, and crossfade controls stay removed. |
| 2026-07-15 | Make each project an `NSDocument` with native change tracking and autosave. | Save, Save As, close protection, recovery, and restored windows should follow macOS document behavior instead of bespoke panels and discard paths. |
| 2026-07-15 | Store `.rdt` v2 as a bounded canonical transcript plus edit decisions and durable media reference. | Versioned validation, fingerprints, relative paths, and security-scoped bookmarks preserve work without retaining the v1 absolute-path contract. |
| 2026-07-15 | Probe source streams and expose a fixed, tested export preset matrix. | The UI must not promise invalid container and codec combinations, and audio-only sources need a real audio-only render path. |
| 2026-07-15 | Keep cut timing canonical and use bounded export fast paths. | Crossfade overlap made preview, subtitles, duration, and export disagree; stream copy and single-range seek avoid unnecessary work without changing the edited timeline. |
| 2026-07-15 | Expose audio enhancement as one on/off export switch. | The approved light cleanup is useful without making people choose algorithms or strengths; unchanged compatible video remains stream-copied while its audio is processed. |
| 2026-07-15 | Make automatic transcript cleanup reviewed and undoable. | Filler, repetition, and pause detection can save time, but users need context, per-suggestion control, and one-step reversal before automatic cuts are trustworthy. |
| 2026-07-18 | Add agent editing through a sanitized local file exchange, with Redact as the only project writer. | A snapshot-and-proposal contract gives Codex and Claude Code enough context to suggest cuts without exposing media references, racing document autosave, or granting agents mutation authority. |
| 2026-07-19 | Add a compact review layer instead of a permanent inspector. | Previous/next edit, a canonical summary, scrub feedback, volume, waveform cut markers, and full-screen preview fit the existing supporting panel at both supported window sizes without reducing transcript width. |
| 2026-07-19 | Remember explicit export choices and offer an optional SRT sidecar. | Repeated exports become faster to configure while media, subtitles, preview, and displayed duration continue to share one canonical edit interpretation. |
