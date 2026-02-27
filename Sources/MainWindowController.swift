import AppKit
import UniformTypeIdentifiers

class MainWindowController: NSWindowController {
    private var splitViewController: MainSplitViewController!
    let project = ProjectDocument()
    let ffmpegService = FFmpegService()
    let whisperService = WhisperService()
    let playbackController = PlaybackController()
    let wordSelectionController = WordSelectionController()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 1000, height: 700)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = Theme.surface0
        window.title = "Redact"
        window.center()
        window.isMovableByWindowBackground = true

        self.init(window: window)

        splitViewController = MainSplitViewController()
        window.contentViewController = splitViewController

        setupToolbar()
    }

    // MARK: - Toolbar

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.showsBaselineSeparator = false
        window?.toolbar = toolbar
    }

    // MARK: - Actions (menu + toolbar targets)

    @objc func importMedia(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.supportedMediaTypes
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a video or audio file to edit"

        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.handleImportedFile(url)
        }
    }

    @objc func saveProject(_ sender: Any?) {
        guard project.appState == .editing else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "rdt")].compactMap { $0 }
        panel.nameFieldStringValue = "project.rdt"
        panel.message = "Save Redact project"

        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url, let proj = self?.project else { return }
            let json = serializeProject(
                segments: proj.segments,
                language: proj.language,
                duration: proj.duration,
                videoFilePath: proj.filePath ?? ""
            )
            do {
                try json.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                proj.errorMessage = "Failed to save: \(error.localizedDescription)"
            }
        }
    }

    @objc func exportVideo(_ sender: Any?) {
        guard project.appState == .editing, let inputPath = project.filePath else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = URL(fileURLWithPath: inputPath).deletingPathExtension().lastPathComponent + "_edited.mp4"
        panel.message = "Export edited video"

        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }

            let keptRanges = buildKeptRanges(self.project.allWords, totalDuration: self.project.duration)
            let editedDuration = calculateEditedDuration(self.project.allWords, totalDuration: self.project.duration)

            self.project.appState = .exporting
            self.project.exportProgress = 0

            Task {
                do {
                    try await self.ffmpegService.exportVideo(
                        inputPath: inputPath,
                        outputPath: url.path,
                        segments: keptRanges,
                        onProgress: { [weak self] percent in
                            DispatchQueue.main.async {
                                self?.project.exportProgress = percent
                            }
                        },
                        totalDuration: editedDuration
                    )
                    await MainActor.run {
                        self.project.appState = .editing
                        self.project.exportProgress = nil
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } catch {
                    await MainActor.run {
                        self.project.appState = .editing
                        self.project.exportProgress = nil
                        self.showError(error.localizedDescription)
                    }
                }
            }
        }
    }

    @objc func exportSRT(_ sender: Any?) {
        guard project.appState == .editing else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "srt")].compactMap { $0 }
        let baseName = project.filePath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? "transcript"
        panel.nameFieldStringValue = baseName + ".srt"
        panel.message = "Export SRT subtitles"

        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }

            let srt = generateSrt(words: self.project.allWords, totalDuration: self.project.duration)
            do {
                try srt.write(to: url, atomically: true, encoding: .utf8)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                self.showError("Failed to export SRT: \(error.localizedDescription)")
            }
        }
    }

    @objc func performUndo(_ sender: Any?) {
        guard project.appState == .editing else { return }
        project.undo()
        playbackController.updateWords(project.allWords)
        wordSelectionController.refreshAllWordAppearances()
    }

    @objc func performRedo(_ sender: Any?) {
        guard project.appState == .editing else { return }
        project.redo()
        playbackController.updateWords(project.allWords)
        wordSelectionController.refreshAllWordAppearances()
    }

    @objc func deleteSelected(_ sender: Any?) {
        guard project.appState == .editing else { return }
        project.deleteSelected()
        playbackController.updateWords(project.allWords)
        wordSelectionController.refreshAllWordAppearances()
    }

    @objc func selectAllWords(_ sender: Any?) {
        guard project.appState == .editing else { return }
        project.selectAll()
        wordSelectionController.refreshAllWordAppearances()
    }

    @objc func togglePlayPause(_ sender: Any?) {
        guard project.appState == .editing else { return }
        playbackController.togglePlayPause()
    }

    @objc func skipBack(_ sender: Any?) {
        guard project.appState == .editing else { return }
        playbackController.skip(seconds: -5)
    }

    @objc func skipForward(_ sender: Any?) {
        guard project.appState == .editing else { return }
        playbackController.skip(seconds: 5)
    }

    // MARK: - File Handling

    func handleImportedFile(_ url: URL) {
        let ext = url.pathExtension.lowercased()

        if ext == "rdt" {
            loadProjectFile(url)
            return
        }

        // Media file — transition to importing state
        project.appState = .importing
        project.filePath = url.path
        splitViewController.showImporting(fileName: url.lastPathComponent)
        updateWindowTitle(fileName: url.lastPathComponent)

        // Extract audio via FFmpeg
        Task {
            do {
                let audioPath = try await ffmpegService.extractAudio(from: url.path)
                await MainActor.run {
                    self.project.audioPath = audioPath
                    self.project.appState = .transcribing
                    self.splitViewController.showTranscribing()
                }
                // Start transcription
                self.startTranscription(audioPath: audioPath)
            } catch {
                await MainActor.run {
                    self.showError(error.localizedDescription)
                    self.project.appState = .empty
                    splitViewController.showEmptyState()
                    updateWindowTitle(fileName: nil)
                }
            }
        }
    }

    private func loadProjectFile(_ url: URL) {
        do {
            let json = try String(contentsOf: url, encoding: .utf8)
            let projectFile = try deserializeProject(json)

            project.loadProject(
                segments: projectFile.segments,
                language: projectFile.language,
                duration: projectFile.duration,
                filePath: url.path
            )

            updateWindowTitle(fileName: projectFile.videoFile)
            splitViewController.showEditing(segments: project.segments)
            setupEditingBindings()
            enableEditingToolbar()
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func startTranscription(audioPath: String) {
        Task {
            do {
                let transcript = try await whisperService.transcribe(audioPath: audioPath) { [weak self] progress in
                    DispatchQueue.main.async {
                        self?.project.transcribeProgress = progress
                        self?.splitViewController.updateTranscribeProgress(progress)
                    }
                }
                await MainActor.run {
                    self.project.setTranscript(transcript)
                    self.splitViewController.showEditing(segments: self.project.segments)
                    self.setupEditingBindings()
                    self.enableEditingToolbar()
                }
            } catch let error where (error as? WhisperError)?.isCancelled == true {
                // User cancelled — return to empty
                await MainActor.run {
                    self.project.reset()
                    self.splitViewController.showEmptyState()
                    self.updateWindowTitle(fileName: nil)
                }
            } catch {
                await MainActor.run {
                    self.showError(error.localizedDescription)
                    self.project.appState = .empty
                    self.splitViewController.showEmptyState()
                    self.updateWindowTitle(fileName: nil)
                }
            }
        }
    }

    func cancelTranscription() {
        whisperService.cancel()
    }

    private func setupEditingBindings() {
        // Load video into player
        if let filePath = project.filePath {
            let url = URL(fileURLWithPath: filePath)
            playbackController.loadMedia(url: url)
            splitViewController.videoPreviewView?.player = playbackController.player
        }

        // Wire playback callbacks
        playbackController.updateWords(project.allWords)

        playbackController.onTimeUpdate = { [weak self] time in
            guard let self else { return }
            self.project.currentTime = time
            self.splitViewController.transportControlsView?.updateTime(current: time, total: self.project.duration)
            self.splitViewController.waveformView?.updateCursor(time: time)
        }

        playbackController.onHighlightWord = { [weak self] wordId in
            guard let self else { return }
            self.project.highlightedWordId = wordId
            self.splitViewController.transcriptView?.highlightWord(id: wordId)
        }

        playbackController.onPlayingChanged = { [weak self] playing in
            guard let self else { return }
            self.project.isPlaying = playing
            self.splitViewController.transportControlsView?.updatePlayingState(playing)
        }

        // Wire waveform
        if let audioPath = project.audioPath {
            splitViewController.waveformView?.loadAudio(
                url: URL(fileURLWithPath: audioPath),
                duration: project.duration
            )
        }
        splitViewController.waveformView?.onSeek = { [weak self] time in
            self?.playbackController.seekToWord(start: time)
        }

        // Wire transport controls
        splitViewController.transportControlsView?.onPlayPause = { [weak self] in
            self?.togglePlayPause(nil)
        }
        splitViewController.transportControlsView?.onSkipBack = { [weak self] in
            self?.skipBack(nil)
        }
        splitViewController.transportControlsView?.onSkipForward = { [weak self] in
            self?.skipForward(nil)
        }
        splitViewController.transportControlsView?.onSpeedChange = { [weak self] rate in
            self?.playbackController.setRate(rate)
            self?.project.playbackRate = Double(rate)
        }
        splitViewController.transportControlsView?.onSeek = { [weak self] time in
            self?.playbackController.seekToWord(start: time)
        }

        // Wire word selection
        wordSelectionController.project = project
        wordSelectionController.transcriptView = splitViewController.transcriptView
        wordSelectionController.onWordClicked = { [weak self] word in
            self?.playbackController.seekToWord(start: word.start)
        }

        // Add mouse tracking to transcript view
        setupTranscriptMouseTracking()
    }

    private func setupTranscriptMouseTracking() {
        guard splitViewController.transcriptView != nil else { return }

        // Use NSEvent local monitor for mouse events on the transcript
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self,
                  let transcriptView = self.splitViewController.transcriptView,
                  let eventWindow = event.window,
                  eventWindow == self.window else { return event }

            let locationInView = transcriptView.convert(event.locationInWindow, from: nil)
            guard transcriptView.bounds.contains(locationInView) else { return event }

            if let wordId = transcriptView.wordId(at: locationInView) {
                if self.wordSelectionController.handleMouseDown(wordId: wordId, event: event) {
                    return nil // Consume event
                }
            }
            return event
        }

        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            guard let self,
                  let transcriptView = self.splitViewController.transcriptView,
                  let eventWindow = event.window,
                  eventWindow == self.window else { return event }

            let locationInView = transcriptView.convert(event.locationInWindow, from: nil)
            if let wordId = transcriptView.wordId(at: locationInView) {
                self.wordSelectionController.handleMouseDragged(wordId: wordId)
            }
            return event
        }

        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            self?.wordSelectionController.handleMouseUp()
            return event
        }
    }

    private func enableEditingToolbar() {
        guard let toolbar = window?.toolbar else { return }
        for item in toolbar.items {
            switch item.itemIdentifier {
            case Self.saveItem, Self.exportItem, Self.undoItem, Self.redoItem:
                item.isEnabled = true
            default:
                break
            }
        }
    }

    func updateWindowTitle(fileName: String?) {
        if let name = fileName {
            window?.title = "Redact — \(name)"
        } else {
            window?.title = "Redact"
        }
    }

    func showError(_ message: String) {
        project.errorMessage = message
        splitViewController.showError(message)
    }

    // MARK: - Supported Types

    static let supportedVideoExtensions = ["mp4", "mkv", "webm", "mov", "avi"]
    static let supportedAudioExtensions = ["mp3", "wav", "m4a"]
    static let supportedProjectExtensions = ["rdt"]

    static var supportedMediaTypes: [UTType] {
        var types: [UTType] = [
            .mpeg4Movie, .quickTimeMovie, .avi, .mpeg4Audio, .mp3, .wav,
        ]
        if let mkv = UTType(filenameExtension: "mkv") { types.append(mkv) }
        if let webm = UTType(filenameExtension: "webm") { types.append(webm) }
        if let m4a = UTType(filenameExtension: "m4a") { types.append(m4a) }
        if let rdt = UTType(filenameExtension: "rdt") { types.append(rdt) }
        return types
    }

    static let allSupportedExtensions = supportedVideoExtensions + supportedAudioExtensions + supportedProjectExtensions
}

// MARK: - NSToolbarDelegate

extension MainWindowController: NSToolbarDelegate {
    static let importItem = NSToolbarItem.Identifier("import")
    static let saveItem = NSToolbarItem.Identifier("save")
    static let exportItem = NSToolbarItem.Identifier("export")
    static let undoItem = NSToolbarItem.Identifier("undo")
    static let redoItem = NSToolbarItem.Identifier("redo")
    static let flexibleSpace = NSToolbarItem.Identifier.flexibleSpace

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        switch itemIdentifier {
        case Self.importItem:
            item.label = "Import"
            item.toolTip = "Import media file"
            item.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Import")
            item.action = #selector(importMedia(_:))
            item.target = self

        case Self.saveItem:
            item.label = "Save"
            item.toolTip = "Save project"
            item.image = NSImage(systemSymbolName: "square.and.arrow.down.on.square", accessibilityDescription: "Save")
            item.action = #selector(saveProject(_:))
            item.target = self
            item.isEnabled = false

        case Self.exportItem:
            item.label = "Export"
            item.toolTip = "Export video"
            item.image = NSImage(systemSymbolName: "film", accessibilityDescription: "Export")
            item.action = #selector(exportVideo(_:))
            item.target = self
            item.isEnabled = false

        case Self.undoItem:
            item.label = "Undo"
            item.toolTip = "Undo last edit"
            item.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Undo")
            item.action = #selector(performUndo(_:))
            item.target = self
            item.isEnabled = false

        case Self.redoItem:
            item.label = "Redo"
            item.toolTip = "Redo last edit"
            item.image = NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: "Redo")
            item.action = #selector(performRedo(_:))
            item.target = self
            item.isEnabled = false

        default:
            return nil
        }

        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.importItem, Self.flexibleSpace, Self.undoItem, Self.redoItem, Self.flexibleSpace, Self.saveItem, Self.exportItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.importItem, Self.saveItem, Self.exportItem, Self.undoItem, Self.redoItem, Self.flexibleSpace]
    }
}
