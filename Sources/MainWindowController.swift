import AppKit
import UniformTypeIdentifiers

class MainWindowController: NSWindowController {
    private var splitViewController: MainSplitViewController!
    let project = ProjectDocument()
    let ffmpegService = FFmpegService()
    let whisperService = WhisperService()
    let elevenLabsService = ElevenLabsService()
    let playbackController = PlaybackController()
    private var exportSheetWindow: NSWindow?

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

        self.init(window: window)

        splitViewController = MainSplitViewController()
        window.contentViewController = splitViewController

        setupToolbar()
        setupKeyMonitor()
    }

    // MARK: - Key Monitor

    /// Intercepts Space and Delete before focused buttons can consume them.
    private func setupKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window == self.window else { return event }
            guard self.project.appState == .editing else { return event }

            switch event.keyCode {
            case 49: // Spacebar
                self.togglePlayPause(nil)
                return nil
            case 51: // Delete (backspace)
                self.deleteSelected(nil)
                return nil
            default:
                return event
            }
        }
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
        guard project.appState == .editing, let _ = project.filePath else { return }
        guard let mainWindow = window else { return }

        let sheetView = ExportSheetView(frame: NSRect(x: 0, y: 0, width: 420, height: 360))

        let sheetWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
                                   styleMask: [.titled],
                                   backing: .buffered,
                                   defer: false)
        sheetWindow.contentView = sheetView
        sheetWindow.title = "Export"
        self.exportSheetWindow = sheetWindow

        sheetView.onCancel = { [weak self] in
            guard let self, let sheet = self.exportSheetWindow else { return }
            self.window?.endSheet(sheet)
            self.exportSheetWindow = nil
        }

        sheetView.onExportSRT = { [weak self] in
            guard let self, let sheet = self.exportSheetWindow else { return }
            self.window?.endSheet(sheet)
            self.exportSheetWindow = nil
            self.exportSRT(nil)
        }

        sheetView.onExportVideo = { [weak self] format, quality, speed, voiceOption in
            guard let self, let inputPath = self.project.filePath else { return }

            // Determine file extension and content type
            let ext: String
            switch format {
            case "mkv": ext = "mkv"
            case "webm": ext = "webm"
            default: ext = "mp4"
            }

            let baseName = URL(fileURLWithPath: inputPath).deletingPathExtension().lastPathComponent
            let panel = NSSavePanel()
            if let uttype = UTType(filenameExtension: ext) {
                panel.allowedContentTypes = [uttype]
            }
            panel.nameFieldStringValue = "\(baseName)_edited.\(ext)"
            panel.message = "Export edited video"

            // End sheet before showing save panel
            if let sheet = self.exportSheetWindow {
                self.window?.endSheet(sheet)
            }

            panel.beginSheetModal(for: mainWindow) { [weak self] response in
                guard response == .OK, let url = panel.url, let self else {
                    self?.exportSheetWindow = nil
                    return
                }

                // Re-present the sheet in progress mode
                sheetView.showProgressMode(status: "Preparing export...")
                mainWindow.beginSheet(sheetWindow) { _ in }

                self.performExport(
                    inputPath: inputPath,
                    outputURL: url,
                    format: format,
                    quality: quality,
                    speed: speed,
                    voiceOption: voiceOption,
                    sheetView: sheetView
                )
            }
        }

        sheetView.onDismiss = { [weak self] in
            guard let self, let sheet = self.exportSheetWindow else { return }
            self.window?.endSheet(sheet)
            self.exportSheetWindow = nil
        }

        sheetView.onCancelExport = { [weak self, weak sheetView] in
            sheetView?.showCancelling()
            self?.ffmpegService.cancel()
        }

        mainWindow.beginSheet(sheetWindow) { _ in }
    }

    /// Performs the full export pipeline: video export + optional voice recreation.
    /// Updates the export sheet with progress, errors, and completion.
    private func performExport(
        inputPath: String,
        outputURL: URL,
        format: String,
        quality: String?,
        speed: Double,
        voiceOption: ExportVoiceOption,
        sheetView: ExportSheetView
    ) {
        let keptRanges = buildKeptRanges(project.allWords, totalDuration: project.duration)
        let editedDuration = calculateEditedDuration(project.allWords, totalDuration: project.duration)

        project.appState = .exporting
        project.exportProgress = 0

        Task {
            do {
                switch voiceOption {
                case .original:
                    await MainActor.run {
                        sheetView.updateProgress(0, status: "Exporting video...")
                    }

                    try await ffmpegService.exportVideo(
                        inputPath: inputPath,
                        outputPath: outputURL.path,
                        segments: keptRanges,
                        format: format,
                        quality: quality,
                        speed: speed,
                        onProgress: { [weak self] percent in
                            DispatchQueue.main.async {
                                self?.project.exportProgress = percent
                                sheetView.updateProgress(percent)
                            }
                        },
                        totalDuration: editedDuration
                    )

                case .elevenLabs(let voiceId):
                    let apiKey = Settings.shared.elevenLabsApiKey
                    guard !apiKey.isEmpty else {
                        throw ElevenLabsError.apiKeyMissing
                    }

                    // Phase 1: Export video to temp file (0–55%)
                    await MainActor.run {
                        sheetView.updateProgress(0, status: "Exporting video...")
                    }

                    let tempVideoPath = PathUtilities.tempDir + "/temp_export.\(format)"
                    try? FileManager.default.removeItem(atPath: tempVideoPath)

                    try await ffmpegService.exportVideo(
                        inputPath: inputPath,
                        outputPath: tempVideoPath,
                        segments: keptRanges,
                        format: format,
                        quality: quality,
                        speed: speed,
                        onProgress: { [weak self] percent in
                            DispatchQueue.main.async {
                                let scaled = percent * 0.55
                                self?.project.exportProgress = scaled
                                sheetView.updateProgress(scaled)
                            }
                        },
                        totalDuration: editedDuration
                    )

                    // Phase 2: Extract audio (55–60%)
                    await MainActor.run {
                        self.project.exportProgress = 55
                        sheetView.updateProgress(55, status: "Extracting audio...")
                    }

                    let tempAudioPath = try await ffmpegService.extractAudioForSTS(from: tempVideoPath)

                    // Phase 3: Send to ElevenLabs STS (60–85%)
                    await MainActor.run {
                        self.project.exportProgress = 60
                        sheetView.updateProgress(60, status: "Converting voice with ElevenLabs...")
                    }

                    let result = try await elevenLabsService.convertVoice(
                        audioPath: tempAudioPath,
                        voiceId: voiceId,
                        apiKey: apiKey,
                        onProgress: { status in
                            DispatchQueue.main.async {
                                sheetView.updateProgress(75, status: "Converting voice with ElevenLabs...")
                            }
                        }
                    )

                    // Phase 4: Replace audio in video (85–98%)
                    await MainActor.run {
                        self.project.exportProgress = 85
                        sheetView.updateProgress(85, status: "Replacing audio track...")
                    }

                    try await ffmpegService.replaceAudio(
                        videoPath: tempVideoPath,
                        audioPath: result.audioPath,
                        outputPath: outputURL.path,
                        onProgress: { [weak self] percent in
                            DispatchQueue.main.async {
                                let scaled = 85 + percent * 0.13
                                self?.project.exportProgress = scaled
                                sheetView.updateProgress(scaled)
                            }
                        },
                        totalDuration: editedDuration
                    )

                    // Phase 5: Delete history item from ElevenLabs (fire-and-forget)
                    await MainActor.run {
                        sheetView.updateProgress(98, status: "Cleaning up...")
                    }

                    if let historyId = result.historyItemId {
                        Task {
                            try? await self.elevenLabsService.deleteHistoryItem(
                                historyItemId: historyId,
                                apiKey: apiKey
                            )
                        }
                    }

                    // Clean up temp files
                    try? FileManager.default.removeItem(atPath: tempVideoPath)
                    try? FileManager.default.removeItem(atPath: tempAudioPath)
                    try? FileManager.default.removeItem(atPath: result.audioPath)
                }

                // Success
                await MainActor.run {
                    self.project.appState = .editing
                    self.project.exportProgress = nil
                    sheetView.showComplete()
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                }
            } catch {
                await MainActor.run {
                    self.project.appState = .editing
                    self.project.exportProgress = nil
                    sheetView.showError(error.localizedDescription)
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
        splitViewController.transcriptView?.refreshAllWordAppearances()
    }

    @objc func performRedo(_ sender: Any?) {
        guard project.appState == .editing else { return }
        project.redo()
        playbackController.updateWords(project.allWords)
        splitViewController.transcriptView?.refreshAllWordAppearances()
    }

    @objc func deleteSelected(_ sender: Any?) {
        guard project.appState == .editing else { return }
        project.deleteSelected()
        playbackController.updateWords(project.allWords)
        splitViewController.transcriptView?.refreshAllWordAppearances()
    }

    @objc func selectAllWords(_ sender: Any?) {
        guard project.appState == .editing else { return }
        project.selectAll()
        splitViewController.transcriptView?.refreshAllWordAppearances()
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

    @objc func closeProject(_ sender: Any?) {
        guard project.appState != .empty else { return }
        playbackController.player.pause()
        playbackController.player.replaceCurrentItem(with: nil)
        whisperService.cancel()
        project.reset()
        splitViewController.showEmptyState()
        updateToolbarState()
    }

    @objc func openSettings(_ sender: Any?) {
        SettingsWindowController.show()
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

            // Try to find the original video file
            let videoFileName = projectFile.videoFile
            let videoPath = resolveVideoPath(videoFileName: videoFileName, storedPath: projectFile.videoPath, rdtFileURL: url)

            if let videoPath {
                finishLoadingProject(projectFile: projectFile, videoPath: videoPath)
            } else {
                // Video not found — ask user to locate it
                promptForVideoFile(videoFileName: videoFileName) { [weak self] selectedPath in
                    guard let self else { return }
                    if let selectedPath {
                        self.finishLoadingProject(projectFile: projectFile, videoPath: selectedPath)
                    } else {
                        // User cancelled — load without video (transcript only)
                        self.finishLoadingProject(projectFile: projectFile, videoPath: nil)
                    }
                }
            }
        } catch {
            showError(error.localizedDescription)
        }
    }

    /// Search common locations for the original video file.
    private func resolveVideoPath(videoFileName: String, storedPath: String?, rdtFileURL: URL) -> String? {
        var candidates: [String] = []

        // First priority: the stored full path from the .rdt file
        if let storedPath, !storedPath.isEmpty {
            candidates.append(storedPath)
        }

        candidates += [
            // Same directory as the .rdt file
            rdtFileURL.deletingLastPathComponent().appendingPathComponent(videoFileName).path,
            // Desktop
            NSHomeDirectory() + "/Desktop/" + videoFileName,
            // Downloads
            NSHomeDirectory() + "/Downloads/" + videoFileName,
            // Projects folder
            NSHomeDirectory() + "/Projects/" + videoFileName,
        ]

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        return nil
    }

    /// Show an open panel asking the user to locate the video file.
    private func promptForVideoFile(videoFileName: String, completion: @escaping (String?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.supportedMediaTypes
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Locate the original video file: \(videoFileName)"
        panel.prompt = "Select Video"

        panel.beginSheetModal(for: window!) { response in
            if response == .OK, let url = panel.url {
                completion(url.path)
            } else {
                completion(nil)
            }
        }
    }

    /// Finish loading a project after the video path is resolved.
    private func finishLoadingProject(projectFile: ProjectFile, videoPath: String?) {
        project.loadProject(
            segments: projectFile.segments,
            language: projectFile.language,
            duration: projectFile.duration,
            filePath: videoPath ?? ""
        )

        updateWindowTitle(fileName: projectFile.videoFile)
        splitViewController.showEditing(segments: project.segments)
        setupEditingBindings()
        enableEditingToolbar()
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

        // Wire word selection directly into the transcript view.
        splitViewController.transcriptView?.project = project
        splitViewController.transcriptView?.onWordClicked = { [weak self] word in
            self?.playbackController.seekToWord(start: word.start)
        }
    }

    private func enableEditingToolbar() {
        guard let toolbar = window?.toolbar else { return }
        for item in toolbar.items {
            switch item.itemIdentifier {
            case Self.saveItem, Self.exportItem, Self.undoItem, Self.redoItem, Self.closeProjectItem:
                item.isEnabled = true
            default:
                break
            }
        }
    }

    func updateToolbarState() {
        guard let toolbar = window?.toolbar else { return }
        let editing = project.appState == .editing
        for item in toolbar.items {
            switch item.itemIdentifier {
            case Self.saveItem, Self.exportItem, Self.undoItem, Self.redoItem, Self.closeProjectItem:
                item.isEnabled = editing
            default:
                break
            }
        }
        window?.title = editing ? window?.title ?? "Redact" : "Redact"
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
    static let closeProjectItem = NSToolbarItem.Identifier("closeProject")
    static let settingsItem = NSToolbarItem.Identifier("settings")
    static let flexibleSpace = NSToolbarItem.Identifier.flexibleSpace

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        switch itemIdentifier {
        case Self.importItem:
            item.label = "Import"
            item.toolTip = "Import media file"
            item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Import")
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

        case Self.closeProjectItem:
            item.label = "Discard"
            item.toolTip = "Close current project"
            item.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Discard")
            item.action = #selector(closeProject(_:))
            item.target = self
            item.isEnabled = false

        case Self.settingsItem:
            item.label = "Settings"
            item.toolTip = "Open Preferences"
            item.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
            item.action = #selector(openSettings(_:))
            item.target = self

        default:
            return nil
        }

        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.flexibleSpace, Self.importItem, .space, Self.undoItem, Self.redoItem, .space, Self.saveItem, Self.exportItem, .space, Self.closeProjectItem, .space, Self.settingsItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.importItem, Self.saveItem, Self.exportItem, Self.undoItem, Self.redoItem, Self.closeProjectItem, Self.settingsItem, Self.flexibleSpace, .space]
    }
}
