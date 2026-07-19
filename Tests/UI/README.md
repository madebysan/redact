# UI smoke tests

Run the packaged-app smoke suite with:

```bash
./scripts/run-ui-smoke-tests.sh
```

The harness builds the release app, launches it with window restoration and the recurring welcome sheet disabled for that test process, and drives observable macOS accessibility actions through System Events. It generates a short synthetic video and temporary `.rdt` project under `.build/`; no private media or transcript is read or committed.

The initial window readiness check allows up to 30 seconds so a freshly built bundle is not mistaken for a launch failure while macOS performs cold-start validation and indexing. Interaction checks retain their shorter timeouts.

Current coverage:

- empty-window launch and the Import Media file chooser;
- deterministic project opening and transcript rendering;
- automatic transcript focus plus keyboard selection, menu deletion, and keyboard undo;
- keyboard preview play and pause;
- edit persistence, close, reopen, and restore;
- focused export configuration, completion action, and SRT, MP4 video, and MP3 audio output validation;
- focused cleanup categories plus reviewed filler, repetition, and long-pause cleanup with saved edit validation;
- missing-media detection and relinking.

The shell running the suite must have permission to control System Events. A missing permission fails the suite rather than changing macOS privacy settings.
