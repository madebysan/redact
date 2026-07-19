# Private release acceptance

Use this checklist with the newest private Redact candidate. It covers the judgments that automated tests cannot make reliably: speech quality, real agent behavior, complete keyboard and assistive-technology behavior, and first run on another Mac.

Do not record private filenames, paths, transcript text, or media hashes. Use a disposable copy whenever a test asks you to move source media.

## Test record

- Date:
- Redact version:
- macOS and Mac model:
- Short, medium, or long class:
- Result: Pass / Fail
- Anonymized notes:

Repeat the golden loop for short, medium, and long representative speech.

## Golden loop

- [ ] Import finishes and the first editable transcript appears.
- [ ] Correct one word, delete a spoken range, Undo, and Redo. The transcript, duration, preview, and waveform remain aligned.
- [ ] Listen across several cuts. No clipped syllables, clicks, gaps, repeated fragments, or drift are audible.
- [ ] Scrub and play at normal speed and at one non-default speed. Highlighting and time remain aligned with speech.
- [ ] Save, quit Redact, reopen the project, and confirm the same transcript and edits return.
- [ ] Using a disposable media copy, move the source, reopen the project, and relink it. The project remains editable and previews correctly.
- [ ] Export video, subtitles, plain audio, and enhanced audio. Each output opens, reaches the expected ending, and reflects the same cuts.
- [ ] Compare plain and enhanced audio in foreground listening. Speech remains natural and intelligible; enhancement introduces no pumping, metallic tone, harsh sibilance, or clipped words.

## Keyboard and accessibility

- [ ] With a video open, confirm the left capsule contains Clean Up and Agent, and the right capsule contains Save Project, Export Video, Settings, and Close in that order. Confirm every icon has a clear tooltip and VoiceOver label, Close is last, Import/Undo/Redo are absent from the toolbar, and audio-only projects expose Export Audio.
- [ ] Open Settings with Command-comma. Open the Font dropdown and confirm it lists 14 real macOS family names from SF Pro through Times New Roman. Compare several serif, sans-serif, and monospaced choices in the live sample and an open transcript; then adjust text size, letter spacing, and line spacing. Confirm font changes do not reset those values, every change updates immediately, and the configuration persists after relaunch.
- [ ] Complete import, transcript navigation and selection, Delete, restore, Undo, Save, preview playback, cleanup review, agent preparation/review, and Export Media (Command-Option-E) without using the pointer.
- [ ] Tab and Shift-Tab move focus in a logical order, focus remains visible, and no control traps focus.
- [ ] With VoiceOver enabled, the transcript is read in order and deleted, selected, and current-playback states are distinguishable.
- [ ] VoiceOver announces Play/Pause, five-second skips, export format, quality, speed, enhancement, progress, and timing with useful labels and values.
- [ ] With Reduce Motion enabled in macOS Accessibility settings, import, error, preview, and export state changes remain understandable without distracting transitions.
- [ ] Redact remains in Dark Aqua when macOS uses either Light or Dark appearance. Settings contains no appearance switcher, and the interface remains readable at the 1400 × 900 default and 1000 × 700 minimum window sizes.

## Agent editing

Use a synthetic transcript with no private names, media, or conversation content.

- [ ] Choose Edit > Edit with Agent…, read the cloud-sharing disclosure, select Codex, and choose Prepare & Copy Prompt. Confirm the sheet does not ask what the agent should change.
- [ ] Paste the copied prompt into Codex. Confirm it loads the snapshot, says it is connected, and asks what you want changed before proposing edits.
- [ ] Confirm the copied prompt points only to Redact's Agent Exchange folder. Confirm `snapshot.json` contains transcript words, timing, deletion state, duration, policy, agent, snapshot ID, and digest, with no edit goal, media path, bookmark, fingerprint, source media, or credentials.
- [ ] Describe the edit in Codex. Confirm the resulting proposal records that request as its goal and Redact shows it in review.
- [ ] Paste the prompt into Codex. After it writes `proposal.json`, Redact opens an attributed review with required/optional status, category controls, temporary transcript highlights, and an exact projected duration.
- [ ] Cancel the review. Confirm the project is unchanged, quit and reopen Redact, and confirm the pending review returns.
- [ ] Apply the reviewed selection. Confirm transcript, duration, waveform, preview, save, subtitles, and export agree, and one Undo restores the complete agent edit.
- [ ] Prepare another synthetic snapshot, change one targeted word in Redact before the proposal arrives, and confirm the stale proposal is blocked rather than silently applied.
- [ ] Repeat with Claude Code, then choose Reject Proposal. Confirm the project is unchanged and the completed exchange is removed.

## Clean Mac

- [ ] Copy the DMG to a Mac that has not built Redact and does not have the project checkout.
- [ ] Mount the DMG, drag Redact to Applications, and launch it normally.
- [ ] Gatekeeper permits the first launch without an unidentified-developer or damaged-app warning.
- [ ] The four-page welcome walkthrough appears before first import. Read every page, use Back and Next, finish with Get Started, and confirm the app lands on the existing import state.
- [ ] Quit and relaunch. Confirm the walkthrough does not appear again, then choose Help > Welcome to Redact and confirm it reopens. Escape closes the replay.
- [ ] Import representative media, edit it, save and reopen the project, and complete one video and one audio export.
- [ ] Quit and relaunch Redact. The app starts normally and the saved project remains usable.

Only mark the corresponding `[needs-san]` items in `backlog.md` complete when every applicable item above passes. Record failures with the media class, exact step, expected result, actual result, and whether the issue reproduces.
