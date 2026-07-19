import AppKit
import UniformTypeIdentifiers

@MainActor
final class MainWindowController: NSWindowController {
    private var splitViewController: MainSplitViewController!
    let project: ProjectDocument
    private weak var redactDocument: RedactDocument?
    private let mediaProcessor = FFmpegService()
    private let transcriptionEngine = TranscriptionEngine()
    private let transcriptCache = TranscriptCache()
    let playbackController = PlaybackController()
    private let projectSession = ProjectSession()
    private lazy var importWorkflow: any ImportWorkflowProtocol = ImportWorkflow(
        mediaProcessor: mediaProcessor
    )
    private lazy var exportWorkflow: any ExportWorkflowProtocol = ExportWorkflow(
        mediaProcessor: mediaProcessor
    )
    private var currentRevision: SessionRevision?
    private var exportSheetWindow: NSWindow?
    private var cleanupSheetWindow: NSWindow?
    private var agentPreparationSheetWindow: NSWindow?
    private var agentReviewSheetWindow: NSWindow?
    private let agentExchangeStore: AgentExchangeStore
    private var agentExchangeWatcher: AgentExchangeWatcher?
    private var activeAgentExchange: PreparedAgentExchange?
    private var pendingAgentReview: AgentProposalReview?
    private var keyEventMonitor: Any?
    private var editReviewModel: EditReviewModel?
    private var currentEditedPlaybackTime: Double = 0
    private weak var cleanupToolbarButton: NSButton?
    private weak var agentToolbarButton: NSButton?
    private weak var saveToolbarButton: NSButton?
    private weak var exportToolbarButton: NSButton?
    private weak var settingsToolbarButton: NSButton?
    private weak var closeToolbarButton: NSButton?

    init(
        project: ProjectDocument,
        document: RedactDocument?,
        agentExchangeStore: AgentExchangeStore = .shared
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 1000, height: 700)
        window.tabbingMode = .disallowed
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .hidden
        window.backgroundColor = Theme.surface0
        window.title = "Redact"
        window.center()

        self.project = project
        redactDocument = document
        self.agentExchangeStore = agentExchangeStore
        super.init(window: window)

        splitViewController = MainSplitViewController()
        splitViewController.onRelinkRequested = { [weak self] in
            self?.relinkMedia(nil)
        }
        splitViewController.onCancelImportRequested = { [weak self] in
            self?.cancelTranscription()
        }
        window.contentViewController = splitViewController

        setupToolbar()
        setupKeyMonitor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
        }
        agentExchangeWatcher?.stop()
    }

    // MARK: - Key Monitor

    /// Intercepts Space and Delete before focused buttons can consume them.
    private func setupKeyMonitor() {
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window == self.window else { return event }
            guard self.project.hasEditableTranscript else { return event }

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
        toolbar.sizeMode = .regular
        toolbar.showsBaselineSeparator = false
        window?.toolbarStyle = .unified
        window?.toolbar = toolbar
        updateToolbarState()
    }

    // MARK: - Actions (menu + toolbar targets)

    @objc func importMedia(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.supportedSourceMediaTypes
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a video or audio file to edit"

        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.handleImportedFile(url)
        }
    }

    @objc func saveProject(_ sender: Any?) {
        guard project.hasEditableTranscript, let redactDocument else { return }
        redactDocument.save(sender)
    }

    @objc func togglePreview(_ sender: Any?) {
        splitViewController.togglePreview()
    }

    @objc func togglePreviewFullScreen(_ sender: Any?) {
        guard project.appState == .editing else { return }
        if !splitViewController.isPreviewVisible {
            splitViewController.togglePreview()
        }
        splitViewController.videoPreviewView?.toggleFullScreen()
    }

    @objc func saveProjectAs(_ sender: Any?) {
        guard project.hasEditableTranscript else { return }
        redactDocument?.saveAs(sender)
    }

    @objc func exportMedia(_ sender: Any?) {
        guard project.appState == .editing, project.filePath != nil else { return }
        guard let mainWindow = window else { return }
        guard let mediaInfo = project.mediaInfo else {
            showError("Redact has not finished reading this file's media streams.")
            return
        }
        let presets = ExportCatalog.presets(for: mediaInfo)
        guard !presets.isEmpty else {
            showError("This file has no supported audio stream to export.")
            return
        }
        guard let exportRenderPlan = project.renderPlan(policy: .mediaV1) else {
            showError("The edited timeline is not ready for export.")
            return
        }

        let sheetView = ExportSheetView(
            frame: NSRect(x: 0, y: 0, width: 520, height: 400),
            presets: presets,
            sourceInfo: mediaInfo,
            finalDuration: exportRenderPlan.editedDuration,
            canExportSubtitles: project.sourceTranscript != nil,
            settings: .shared
        )

        let sheetWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
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

        sheetView.onExport = { [weak self] preset, quality, speed, enhanceAudio, exportSubtitles in
            guard let self, let inputPath = self.project.filePath else { return }

            let baseName = URL(fileURLWithPath: inputPath).deletingPathExtension().lastPathComponent
            let panel = NSSavePanel()
            if let uttype = UTType(filenameExtension: preset.pathExtension) {
                panel.allowedContentTypes = [uttype]
            }
            panel.nameFieldStringValue = "\(baseName)_edited.\(preset.pathExtension)"
            panel.message = preset.mediaKind == .video ? "Export edited video" : "Export edited audio"

            if let sheet = self.exportSheetWindow {
                self.window?.endSheet(sheet)
            }

            panel.beginSheetModal(for: mainWindow) { [weak self] response in
                guard response == .OK, let url = panel.url, let self else {
                    self?.exportSheetWindow = nil
                    return
                }

                let startExport = {
                    sheetView.showProgressMode(status: "Preparing export...")
                    mainWindow.beginSheet(sheetWindow) { _ in }
                    self.performExport(
                        inputPath: inputPath,
                        outputURL: url,
                        preset: preset,
                        quality: quality,
                        speed: speed,
                        enhanceAudio: enhanceAudio,
                        exportSubtitles: exportSubtitles,
                        sheetView: sheetView
                    )
                }
                let subtitleURL = url.deletingPathExtension().appendingPathExtension("srt")
                guard exportSubtitles,
                      FileManager.default.fileExists(atPath: subtitleURL.path) else {
                    startExport()
                    return
                }

                let alert = NSAlert()
                alert.messageText = "Replace Existing Subtitle File?"
                alert.informativeText = "A subtitle file named \(subtitleURL.lastPathComponent) already exists beside the export."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Replace Subtitles")
                alert.addButton(withTitle: "Cancel")
                alert.beginSheetModal(for: mainWindow) { response in
                    if response == .alertFirstButtonReturn {
                        startExport()
                    } else {
                        mainWindow.beginSheet(sheetWindow) { _ in }
                        sheetView.focusInitialControl(in: sheetWindow)
                    }
                }
            }
        }

        sheetView.onDismiss = { [weak self] in
            guard let self, let sheet = self.exportSheetWindow else { return }
            self.window?.endSheet(sheet)
            self.exportSheetWindow = nil
        }

        sheetView.onCancelExport = { [weak self, weak sheetView] in
            sheetView?.showCancelling()
            guard let self else { return }
            Task { await self.projectSession.cancel(.export) }
        }

        mainWindow.beginSheet(sheetWindow) { _ in }
        sheetView.focusInitialControl(in: sheetWindow)
    }

    @objc func cleanUpTranscript(_ sender: Any?) {
        guard project.hasEditableTranscript, let mainWindow = window else { return }
        let suggestions = TranscriptCleanupAnalyzer.suggestions(for: project.allWords)
        guard !suggestions.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No Cleanup Suggestions"
            alert.informativeText = "Redact did not find filler words, adjacent repeated words, or long pauses that can be shortened safely."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.beginSheetModal(for: mainWindow)
            return
        }

        let sheetSize = NSSize(width: 700, height: 520)
        let sheetView = CleanupReviewView(
            frame: NSRect(origin: .zero, size: sheetSize),
            suggestions: suggestions
        )
        let sheetWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: sheetSize),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        sheetWindow.title = "Clean Up Transcript"
        sheetWindow.contentView = sheetView
        cleanupSheetWindow = sheetWindow

        sheetView.onCancel = { [weak self] in
            guard let self, let sheet = self.cleanupSheetWindow else { return }
            self.window?.endSheet(sheet)
            self.cleanupSheetWindow = nil
        }
        sheetView.onApply = { [weak self] wordIDs in
            guard let self, let sheet = self.cleanupSheetWindow else { return }
            self.window?.endSheet(sheet)
            self.cleanupSheetWindow = nil
            self.splitViewController.transcriptView?.clearTranscriptSelection()
            let changedWordIDs = self.project.deleteWords(wordIDs)
            guard !changedWordIDs.isEmpty else { return }
            self.redactDocument?.updateChangeCount(.changeDone)
            self.updateAfterProjectMutation(
                changedWordIDs: changedWordIDs,
                rebuildPreview: true
            )
            self.updateToolbarState()
        }

        mainWindow.beginSheet(sheetWindow)
        sheetView.focusInitialControl(in: sheetWindow)
    }

    @objc func editWithAgent(_ sender: Any?) {
        guard project.hasEditableTranscript, let mainWindow = window else { return }

        if let pendingAgentReview {
            presentAgentReview(pendingAgentReview)
            return
        }
        if let activeAgentExchange {
            copyAgentPrompt(activeAgentExchange.prompt)
            showAgentSnapshotReady(for: activeAgentExchange, in: mainWindow)
            return
        }
        guard agentPreparationSheetWindow == nil else { return }

        let sheetSize = NSSize(width: 540, height: 280)
        let sheetView = AgentPreparationView(
            frame: NSRect(origin: .zero, size: sheetSize)
        )
        let sheetWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: sheetSize),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        sheetWindow.title = "Edit with Agent"
        sheetWindow.contentView = sheetView
        agentPreparationSheetWindow = sheetWindow

        sheetView.onCancel = { [weak self] in
            guard let self, let sheet = self.agentPreparationSheetWindow else { return }
            self.window?.endSheet(sheet)
            self.agentPreparationSheetWindow = nil
        }
        sheetView.onPrepare = { [weak self] agent in
            guard let self, let sheet = self.agentPreparationSheetWindow else { return }
            self.window?.endSheet(sheet)
            self.agentPreparationSheetWindow = nil
            self.ensureDocumentSaved { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    self.prepareAgentExchange(agent: agent)
                case .failure(let error):
                    if (error as? CocoaError)?.code == .userCancelled {
                        return
                    }
                    self.showError("Redact could not save the project before preparing the agent snapshot. \(error.localizedDescription)")
                }
            }
        }

        mainWindow.beginSheet(sheetWindow)
        sheetView.focusInitialControl(in: sheetWindow)
    }

    private func ensureDocumentSaved(
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let redactDocument, let mainWindow = window else {
            completion(.failure(RedactDocumentError.transcriptUnavailable))
            return
        }

        func save(to url: URL, operation: NSDocument.SaveOperationType) {
            redactDocument.save(
                to: url,
                ofType: RedactDocument.typeIdentifier,
                for: operation
            ) { error in
                DispatchQueue.main.async {
                    if let error {
                        completion(.failure(error))
                    } else {
                        completion(.success(()))
                    }
                }
            }
        }

        if let fileURL = redactDocument.fileURL {
            save(to: fileURL, operation: .saveOperation)
            return
        }

        let panel = NSSavePanel()
        if let projectType = UTType(filenameExtension: "rdt") {
            panel.allowedContentTypes = [projectType]
        }
        panel.nameFieldStringValue = "project.rdt"
        panel.message = "Save this Redact project before preparing an agent snapshot"
        panel.beginSheetModal(for: mainWindow) { response in
            guard response == .OK, let url = panel.url else {
                completion(.failure(CocoaError(.userCancelled)))
                return
            }
            save(to: url, operation: .saveAsOperation)
        }
    }

    private func prepareAgentExchange(agent: AgentProvider) {
        guard let mainWindow = window else { return }
        do {
            try? agentExchangeStore.expireAbandonedExchanges(
                olderThan: Date().addingTimeInterval(-30 * 24 * 60 * 60)
            )
            let snapshot = try AgentSnapshotBuilder.make(
                project: project,
                agent: agent
            )
            let exchange = try agentExchangeStore.prepare(snapshot: snapshot)
            activeAgentExchange = exchange
            pendingAgentReview = nil
            copyAgentPrompt(exchange.prompt)
            startWatchingAgentExchange(exchange)
            showAgentSnapshotReady(for: exchange, in: mainWindow)
        } catch {
            showError("Redact could not prepare the agent snapshot. \(error.localizedDescription)")
        }
    }

    private func copyAgentPrompt(_ prompt: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
    }

    private func showAgentSnapshotReady(
        for exchange: PreparedAgentExchange,
        in mainWindow: NSWindow
    ) {
        let alert = NSAlert()
        alert.messageText = "\(exchange.snapshot.agent.displayName) Prompt Copied"
        alert.informativeText = "Paste it into \(exchange.snapshot.agent.displayName). When the agent confirms the Redact snapshot is connected, tell it what you want edited. Redact will keep watching for the proposal and open the review when it arrives."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: mainWindow) { [weak self] _ in
            guard let self, let pendingAgentReview = self.pendingAgentReview else { return }
            self.presentAgentReview(pendingAgentReview)
        }
    }

    private func startWatchingAgentExchange(_ exchange: PreparedAgentExchange) {
        agentExchangeWatcher?.stop()
        let watcher = AgentExchangeWatcher(directoryURL: exchange.paths.directoryURL) { [weak self] in
            Task { @MainActor in
                self?.checkForAgentProposal()
            }
        }
        do {
            try watcher.start()
            agentExchangeWatcher = watcher
        } catch {
            showError("Redact prepared the snapshot but could not watch for the proposal. Choose Edit with Agent again after the proposal is written.")
        }
        checkForAgentProposal()
    }

    private func checkForAgentProposal() {
        guard let activeAgentExchange else { return }
        do {
            guard let proposal = try agentExchangeStore.loadProposalIfChanged(
                snapshotID: activeAgentExchange.snapshot.snapshotID
            ) else {
                return
            }
            let review = try AgentProposalValidator.review(
                proposal,
                snapshot: activeAgentExchange.snapshot,
                project: project
            )
            pendingAgentReview = review
            if window?.attachedSheet == nil {
                presentAgentReview(review)
            }
        } catch AgentProposalError.malformedJSON {
            // Atomic writers should not expose partial content, but if one does,
            // wait for the next file change instead of flashing an error.
        } catch {
            showError("Redact could not review the agent proposal. \(error.localizedDescription)")
        }
    }

    private func presentAgentReview(_ review: AgentProposalReview) {
        guard let mainWindow = window,
              agentReviewSheetWindow == nil,
              mainWindow.attachedSheet == nil else {
            return
        }

        let suggestions = review.cleanupSuggestions(project: project)
        let baseDuration = project.renderPlan(policy: .mediaV1)?.editedDuration ?? 0
        let configuration = CleanupReviewConfiguration.agent(
            agentName: review.proposal.agent,
            goal: review.proposal.goal,
            initialSelectedSuggestionIDs: review.initiallySelectedGroupIDs,
            summaryProvider: { [weak self] wordIDs, selectedCount, totalCount in
                guard let self else { return "" }
                let projectedDuration = self.project.renderPlan(
                    deletingAdditionalWordIDs: wordIDs,
                    policy: .mediaV1
                )?.editedDuration ?? baseDuration
                return "\(selectedCount) of \(totalCount) changes selected • Projected result: \(formatAgentDuration(baseDuration)) → \(formatAgentDuration(projectedDuration))"
            }
        )
        let sheetSize = NSSize(width: 760, height: 560)
        let sheetView = CleanupReviewView(
            frame: NSRect(origin: .zero, size: sheetSize),
            suggestions: suggestions,
            configuration: configuration
        )
        let sheetWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: sheetSize),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        sheetWindow.title = "Review Agent Edits"
        sheetWindow.contentView = sheetView
        agentReviewSheetWindow = sheetWindow

        let initialWordIDs = review.selectedWordIDs(
            for: review.initiallySelectedGroupIDs
        )
        splitViewController.transcriptView?.setProposedWordIDs(initialWordIDs)
        sheetView.onSelectionChanged = { [weak self] wordIDs in
            self?.splitViewController.transcriptView?.setProposedWordIDs(wordIDs)
        }
        sheetView.onCancel = { [weak self] in
            self?.closeAgentReview(completeExchange: false)
        }
        sheetView.onReject = { [weak self] in
            self?.closeAgentReview(completeExchange: true)
        }
        sheetView.onApply = { [weak self] wordIDs in
            guard let self else { return }
            do {
                _ = try AgentProposalValidator.review(
                    review.proposal,
                    snapshot: review.snapshot,
                    project: self.project
                )
            } catch {
                self.showError(error.localizedDescription)
                return
            }

            guard let sheet = self.agentReviewSheetWindow else { return }
            self.window?.endSheet(sheet)
            self.agentReviewSheetWindow = nil
            self.splitViewController.transcriptView?.setProposedWordIDs([])
            self.splitViewController.transcriptView?.clearTranscriptSelection()
            let changedWordIDs = self.project.deleteWords(wordIDs)
            if !changedWordIDs.isEmpty {
                self.redactDocument?.updateChangeCount(.changeDone)
                self.updateAfterProjectMutation(
                    changedWordIDs: changedWordIDs,
                    rebuildPreview: true
                )
                self.updateToolbarState()
            }
            self.finishAgentExchange()
        }

        mainWindow.beginSheet(sheetWindow)
        sheetView.focusInitialControl(in: sheetWindow)
    }

    private func closeAgentReview(completeExchange: Bool) {
        guard let sheet = agentReviewSheetWindow else { return }
        window?.endSheet(sheet)
        agentReviewSheetWindow = nil
        splitViewController.transcriptView?.setProposedWordIDs([])
        if completeExchange {
            finishAgentExchange()
        }
    }

    private func finishAgentExchange() {
        if let snapshotID = activeAgentExchange?.snapshot.snapshotID {
            do {
                try agentExchangeStore.complete(snapshotID: snapshotID)
            } catch {
                showError("The proposal was handled, but Redact could not remove the local agent exchange. \(error.localizedDescription)")
            }
        }
        agentExchangeWatcher?.stop()
        agentExchangeWatcher = nil
        activeAgentExchange = nil
        pendingAgentReview = nil
    }

    private func resumePendingAgentExchange() {
        guard let digest = try? AgentSnapshotBuilder.digest(project: project),
              let exchange = agentExchangeStore.pendingExchange(baseDigest: digest) else {
            return
        }
        activeAgentExchange = exchange
        startWatchingAgentExchange(exchange)
    }

    private func performExport(
        inputPath: String,
        outputURL: URL,
        preset: ExportPreset,
        quality: String?,
        speed: Double,
        enhanceAudio: Bool,
        exportSubtitles: Bool,
        sheetView: ExportSheetView
    ) {
        guard let revision = currentRevision else {
            sheetView.showError("The project changed before export could start.")
            return
        }

        guard let renderPlan = project.renderPlan(policy: .mediaV1) else {
            sheetView.showError("The transcript is not ready for export.")
            return
        }
        guard let sourceInfo = project.mediaInfo else {
            sheetView.showError("Redact has not finished reading this file's media streams.")
            return
        }
        let request = ExportRequest(
            inputURL: URL(fileURLWithPath: inputPath),
            outputURL: outputURL,
            segments: renderPlan.keptRanges,
            preset: preset,
            sourceInfo: sourceInfo,
            sourceIsUnchanged: renderPlan.deletedRanges.isEmpty,
            quality: quality,
            speed: speed,
            enhanceAudio: enhanceAudio,
            totalDuration: renderPlan.editedDuration
        )
        let subtitleSidecar: SubtitleSidecar?
        if exportSubtitles, let transcript = project.sourceTranscript {
            subtitleSidecar = SubtitleSidecarBuilder.make(
                outputURL: outputURL,
                transcript: transcript,
                edits: project.editDecisionList,
                renderPlan: renderPlan
            )
        } else {
            subtitleSidecar = nil
        }

        project.appState = .exporting
        project.exportProgress = 0

        let workflow = exportWorkflow
        let session = projectSession
        Task {
            await session.start(.export, revision: revision) { [weak self] in
                guard let self else { return }
                await self.runExport(
                    request: request,
                    revision: revision,
                    workflow: workflow,
                    subtitleSidecar: subtitleSidecar,
                    sheetView: sheetView
                )
            }
        }
    }

    private func runExport(
        request: ExportRequest,
        revision: SessionRevision,
        workflow: any ExportWorkflowProtocol,
        subtitleSidecar: SubtitleSidecar?,
        sheetView: ExportSheetView
    ) async {
        let operation = ProcessOperation()

        do {
            let mediaName = request.preset.mediaKind == .video ? "video" : "audio"
            sheetView.updateProgress(0, status: "Exporting \(mediaName)...")
            try await workflow.export(
                request,
                operation: operation,
                onProgress: { [weak self, weak sheetView] percent in
                    Task { @MainActor in
                        guard let self,
                              let sheetView,
                              self.currentRevision == revision,
                              await self.projectSession.isCurrent(revision) else {
                            return
                        }
                        self.project.exportProgress = percent
                        sheetView.updateProgress(percent)
                    }
                }
            )

            guard currentRevision == revision,
                  await projectSession.isCurrent(revision) else {
                await projectSession.complete(.export, revision: revision)
                return
            }
            var revealedURLs = [request.outputURL]
            if let subtitleSidecar {
                do {
                    try subtitleSidecar.contents.write(
                        to: subtitleSidecar.url,
                        atomically: true,
                        encoding: .utf8
                    )
                    revealedURLs.append(subtitleSidecar.url)
                } catch {
                    project.appState = .editing
                    project.exportProgress = nil
                    sheetView.showError(
                        "Media exported, but subtitles could not be written. \(error.localizedDescription)"
                    )
                    NSWorkspace.shared.activateFileViewerSelecting([request.outputURL])
                    await projectSession.complete(.export, revision: revision)
                    return
                }
            }
            project.appState = .editing
            project.exportProgress = nil
            sheetView.showComplete()
            NSWorkspace.shared.activateFileViewerSelecting(revealedURLs)
        } catch {
            guard currentRevision == revision,
                  await projectSession.isCurrent(revision) else {
                await projectSession.complete(.export, revision: revision)
                return
            }
            project.appState = .editing
            project.exportProgress = nil
            if error is CancellationError || (error as? FFmpegError) == .cancelled {
                sheetView.showError("Export cancelled. The previous destination was not changed.")
            } else {
                sheetView.showError(error.localizedDescription)
            }
        }

        await projectSession.complete(.export, revision: revision)
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

            guard let transcript = self.project.sourceTranscript else {
                self.showError("The transcript is not ready for subtitle export.")
                return
            }
            guard let renderPlan = self.project.renderPlan(policy: .mediaV1) else {
                self.showError("The edited timeline is not ready for subtitle export.")
                return
            }
            let srt = generateSrt(
                transcript: transcript,
                edits: self.project.editDecisionList,
                renderPlan: renderPlan
            )
            do {
                try srt.write(to: url, atomically: true, encoding: .utf8)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                self.showError("Failed to export SRT: \(error.localizedDescription)")
            }
        }
    }

    @objc func performUndo(_ sender: Any?) {
        guard project.hasEditableTranscript else { return }
        let previousEdits = project.editDecisionList
        let changedWordIDs = project.undo()
        guard !changedWordIDs.isEmpty else { return }
        redactDocument?.updateChangeCount(.changeUndone)
        updateAfterProjectMutation(
            changedWordIDs: changedWordIDs,
            rebuildPreview: previousEdits != project.editDecisionList
        )
    }

    @objc func performRedo(_ sender: Any?) {
        guard project.hasEditableTranscript else { return }
        let previousEdits = project.editDecisionList
        let changedWordIDs = project.redo()
        guard !changedWordIDs.isEmpty else { return }
        redactDocument?.updateChangeCount(.changeRedone)
        updateAfterProjectMutation(
            changedWordIDs: changedWordIDs,
            rebuildPreview: previousEdits != project.editDecisionList
        )
    }

    @objc func deleteSelected(_ sender: Any?) {
        guard project.hasEditableTranscript else { return }
        let changedWordIDs = project.deleteSelected()
        guard !changedWordIDs.isEmpty else { return }
        redactDocument?.updateChangeCount(.changeDone)
        splitViewController.transcriptView?.clearTranscriptSelection()
        updateAfterProjectMutation(changedWordIDs: changedWordIDs, rebuildPreview: true)
    }

    private func restoreWord(_ wordID: String) {
        guard project.hasEditableTranscript else { return }
        let changedWordIDs = project.restoreWord(wordID)
        guard !changedWordIDs.isEmpty else { return }
        redactDocument?.updateChangeCount(.changeDone)
        updateAfterProjectMutation(changedWordIDs: changedWordIDs, rebuildPreview: true)
    }

    @objc func restoreSelectedWords(_ sender: Any?) {
        guard project.hasEditableTranscript else { return }
        let changedWordIDs = project.restoreSelected()
        guard !changedWordIDs.isEmpty else { return }
        redactDocument?.updateChangeCount(.changeDone)
        splitViewController.transcriptView?.clearTranscriptSelection()
        updateAfterProjectMutation(changedWordIDs: changedWordIDs, rebuildPreview: true)
    }

    @objc func correctSelectedWord(_ sender: Any?) {
        guard let word = selectedCorrectableWord else { return }
        presentCorrection(for: word)
    }

    private var selectedCorrectableWord: Word? {
        guard project.hasEditableTranscript,
              project.selectedWordIds.count == 1,
              let wordID = project.selectedWordIds.first,
              let word = project.word(withID: wordID),
              !word.deleted,
              !word.isActualSilence else {
            return nil
        }
        return word
    }

    private func presentCorrection(for word: Word) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Correct Transcript Word"
        alert.informativeText = "This changes the displayed text while preserving its timing and edit state."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Correct")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(string: word.word)
        textField.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
        textField.placeholderString = "Corrected text"
        textField.setAccessibilityLabel("Corrected transcript text")
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let changedWordIDs = self.project.correctWordText(
                id: word.id,
                text: textField.stringValue
            )
            guard !changedWordIDs.isEmpty else { return }
            self.redactDocument?.updateChangeCount(.changeDone)
            self.updateAfterProjectMutation(
                changedWordIDs: changedWordIDs,
                rebuildPreview: false
            )
        }
    }

    private func updateAfterProjectMutation(
        changedWordIDs: Set<String>,
        rebuildPreview: Bool
    ) {
        if let transcriptView = splitViewController.transcriptView {
            for wordID in changedWordIDs {
                guard let word = project.word(withID: wordID),
                      transcriptView.displayedWordText(id: wordID) != word.word else {
                    continue
                }
                transcriptView.updateCorrectedWord(
                    id: wordID,
                    text: word.word,
                    segments: project.segments
                )
            }
            transcriptView.updateWordAppearances(wordIDs: changedWordIDs)
        }
        guard rebuildPreview, project.appState == .editing else { return }
        guard let renderPlan = project.renderPlan(policy: .mediaV1) else {
            showError("Redact could not rebuild the edited preview.")
            return
        }
        updateEditReview(using: renderPlan)
        playbackController.updateEditState(
            words: project.allWords,
            renderPlan: renderPlan
        )
    }

    @objc func selectAllWords(_ sender: Any?) {
        guard project.hasEditableTranscript else { return }
        splitViewController.transcriptView?.selectAllTranscriptWords()
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

    @objc func previousEdit(_ sender: Any?) {
        guard project.appState == .editing,
              let target = editReviewModel?.previousTarget(from: currentEditedPlaybackTime) else {
            return
        }
        playbackController.seekToEditedTime(target)
    }

    @objc func nextEdit(_ sender: Any?) {
        guard project.appState == .editing,
              let target = editReviewModel?.nextTarget(from: currentEditedPlaybackTime) else {
            return
        }
        playbackController.seekToEditedTime(target)
    }

    @objc func closeProject(_ sender: Any?) {
        guard project.appState != .empty else { return }
        if redactDocument != nil {
            window?.performClose(sender)
            return
        }
        currentRevision = nil
        playbackController.close()
        Task {
            await transcriptionEngine.cancel()
            await projectSession.close()
        }
        project.reset()
        splitViewController.showEmptyState()
        updateToolbarState()
    }

    @objc func relinkMedia(_ sender: Any?) {
        guard project.appState == .missingMedia else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.supportedSourceMediaTypes
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose the source media for this Redact project"
        panel.prompt = "Relink"

        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            Task {
                do {
                    let mediaInfo = try await self.mediaProcessor.getMediaInfo(
                        filePath: url.path,
                        operation: ProcessOperation()
                    )
                    guard mediaInfo.hasAudio else {
                        throw MediaImportError.missingAudioStream
                    }
                    self.playbackController.close()
                    self.project.mediaInfo = mediaInfo
                    self.project.filePath = url.path
                    self.project.appState = .editing
                    self.redactDocument?.setResolvedMediaURL(url)
                    self.redactDocument?.updateChangeCount(.changeDone)
                    self.splitViewController.showEditing(segments: self.project.segments)
                    self.setupEditingBindings()
                    self.updateToolbarState()
                } catch {
                    self.showError("Redact could not relink this media. \(error.localizedDescription)")
                }
            }
        }
    }

    @objc func openSettings(_ sender: Any?) {
        SettingsWindowController.show()
    }

    // MARK: - File Handling

    func handleImportedFile(_ url: URL) {
        if url.pathExtension.lowercased() == "rdt" {
            do {
                try (NSApp.delegate as? AppDelegate)?.openDocument(at: url)
            } catch {
                showError(error.localizedDescription)
            }
            return
        }

        currentRevision = nil
        playbackController.close()
        Task { [weak self] in
            guard let self else { return }
            await self.transcriptionEngine.cancel()
            let revision = await self.projectSession.replaceProject()
            self.currentRevision = revision
            self.beginLoading(url, revision: revision)
        }
    }

    private func beginLoading(_ url: URL, revision: SessionRevision) {
        project.appState = .importing
        project.filePath = url.path
        redactDocument?.setSourceMediaURL(url)
        splitViewController.showImporting(fileName: url.lastPathComponent)
        updateWindowTitle(fileName: url.lastPathComponent)

        let workflow = importWorkflow
        let session = projectSession
        Task {
            await session.start(.importMedia, revision: revision) { [weak self] in
                guard let self else { return }
                await self.runMediaImport(
                    sourceURL: url,
                    revision: revision,
                    workflow: workflow
                )
            }
        }
    }

    private func runMediaImport(
        sourceURL: URL,
        revision: SessionRevision,
        workflow: any ImportWorkflowProtocol
    ) async {
        var activeOperation = ProjectOperation.importMedia

        do {
            let mediaInfo = try await workflow.probeMedia(
                at: sourceURL,
                operation: ProcessOperation()
            )
            guard mediaInfo.hasAudio else {
                throw MediaImportError.missingAudioStream
            }
            guard currentRevision == revision,
                  await projectSession.isCurrent(revision) else {
                await projectSession.complete(activeOperation, revision: revision)
                return
            }
            project.mediaInfo = mediaInfo

            let model = Settings.shared.whisperModel
            let fingerprint = try MediaFingerprint.make(for: sourceURL)
            let cacheKey = TranscriptCacheKey.current(
                fingerprint: fingerprint,
                model: model
            )

            if let cachedTranscript = try await transcriptCache.load(for: cacheKey) {
                guard currentRevision == revision,
                      await projectSession.isCurrent(revision) else {
                    await projectSession.complete(.importMedia, revision: revision)
                    return
                }
                project.setTranscript(cachedTranscript)
                redactDocument?.updateChangeCount(.changeDone)
                splitViewController.showEditing(segments: project.segments)
                setupEditingBindings()
                enableEditingToolbar()
                await projectSession.complete(.importMedia, revision: revision)
                return
            }

            let workspace = try await projectSession.makeWorkspace(
                for: .importMedia,
                revision: revision
            )
            let audioURL = try await workflow.extractAudio(
                from: sourceURL,
                workspace: workspace,
                operation: ProcessOperation(),
                onProgress: nil
            )

            guard currentRevision == revision,
                  await projectSession.isCurrent(revision) else {
                await projectSession.complete(.importMedia, revision: revision)
                return
            }

            guard await projectSession.transition(
                from: .importMedia,
                to: .transcription,
                revision: revision
            ) else {
                await projectSession.complete(.importMedia, revision: revision)
                return
            }
            activeOperation = .transcription

            project.audioPath = audioURL.path
            project.appState = .transcribing
            splitViewController.showTranscribing()

            let transcript = try await transcriptionEngine.transcribe(
                audioPath: audioURL.path,
                model: model
            ) { [weak self] progress in
                Task { @MainActor in
                    guard let self,
                          self.currentRevision == revision,
                          await self.projectSession.isCurrent(revision) else {
                        return
                    }
                    self.project.transcribeProgress = progress
                    self.splitViewController.updateTranscribeProgress(progress)
                }
            }

            guard currentRevision == revision,
                  await projectSession.isCurrent(revision) else {
                await projectSession.complete(activeOperation, revision: revision)
                return
            }

            project.audioPath = nil
            try? await transcriptCache.save(transcript, for: cacheKey)
            project.setTranscript(transcript)
            redactDocument?.updateChangeCount(.changeDone)
            splitViewController.showEditing(segments: project.segments)
            setupEditingBindings()
            enableEditingToolbar()
        } catch {
            guard currentRevision == revision,
                  await projectSession.isCurrent(revision) else {
                await projectSession.complete(activeOperation, revision: revision)
                return
            }

            project.reset()
            splitViewController.showEmptyState()
            updateWindowTitle(fileName: nil)

            let wasCancelled = error is CancellationError
                || (error as? WhisperError)?.isCancelled == true
                || (error as? FFmpegError) == .cancelled
            if !wasCancelled {
                showError(error.localizedDescription)
            }
        }

        await projectSession.complete(activeOperation, revision: revision)
    }

    func installLoadedProject(_ projectFile: ProjectFile, projectURL: URL) {
        Task { [weak self] in
            guard let self else { return }
            let revision = await projectSession.replaceProject()
            currentRevision = revision
            let videoURL = projectFile.media.resolvedURL(relativeTo: projectURL)
            if let videoURL {
                redactDocument?.setResolvedMediaURL(videoURL)
                project.mediaInfo = try? await mediaProcessor.getMediaInfo(
                    filePath: videoURL.path,
                    operation: ProcessOperation()
                )
            }
            finishLoadingProject(
                projectFile: projectFile,
                videoPath: videoURL?.path,
                revision: revision
            )
        }
    }

    /// Finish loading a project after the video path is resolved.
    private func finishLoadingProject(
        projectFile: ProjectFile,
        videoPath: String?,
        revision: SessionRevision
    ) {
        guard currentRevision == revision else { return }
        project.loadProject(
            transcript: projectFile.transcript,
            edits: projectFile.edits,
            segmentStartWordIDs: projectFile.segmentStartWordIDs,
            filePath: videoPath ?? ""
        )

        updateWindowTitle(fileName: projectFile.media.displayName)
        splitViewController.showEditing(
            segments: project.segments,
            showsMissingMediaNotice: project.appState == .missingMedia
        )
        setupEditingBindings()
        updateToolbarState()
        resumePendingAgentExchange()
    }

    func cancelTranscription() {
        Task {
            await transcriptionEngine.cancel()
            await projectSession.cancel(.importMedia)
            await projectSession.cancel(.transcription)
        }
    }

    private func setupEditingBindings() {
        currentEditedPlaybackTime = 0
        if let renderPlan = project.renderPlan(policy: .mediaV1) {
            updateEditReview(using: renderPlan)
        }

        // Load video into player
        if let filePath = project.filePath, !filePath.isEmpty,
           let renderPlan = project.renderPlan(policy: .mediaV1) {
            let url = URL(fileURLWithPath: filePath)
            playbackController.loadMedia(
                url: url,
                words: project.allWords,
                renderPlan: renderPlan
            )
            splitViewController.videoPreviewView?.player = playbackController.player
        }

        // Wire playback callbacks
        playbackController.onPositionUpdate = { [weak self] position in
            guard let self else { return }
            self.currentEditedPlaybackTime = position.editedTime
            self.project.currentTime = position.sourceTime
            self.splitViewController.transportControlsView?.updateTime(
                current: position.editedTime,
                total: position.editedDuration,
                original: self.project.duration
            )
            self.updateEditNavigationAvailability()
            self.splitViewController.waveformView?.updateCursor(time: position.sourceTime)
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
        playbackController.onPreviewError = { [weak self] message in
            self?.showError("Preview could not be rebuilt. \(message)")
        }

        // Wire waveform
        if let waveformPath = project.filePath ?? project.audioPath,
           !waveformPath.isEmpty {
            splitViewController.waveformView?.loadAudio(
                url: URL(fileURLWithPath: waveformPath),
                duration: project.duration
            )
        }
        splitViewController.waveformView?.onSeek = { [weak self] time in
            self?.playbackController.seekToSourceTime(time)
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
        splitViewController.transportControlsView?.onPreviousEdit = { [weak self] in
            self?.previousEdit(nil)
        }
        splitViewController.transportControlsView?.onNextEdit = { [weak self] in
            self?.nextEdit(nil)
        }
        splitViewController.transportControlsView?.onSpeedChange = { [weak self] rate in
            self?.playbackController.setRate(rate)
            self?.project.playbackRate = Double(rate)
        }
        splitViewController.transportControlsView?.onSeek = { [weak self] time in
            self?.playbackController.seekToEditedTime(time)
        }
        let settings = Settings.shared
        playbackController.setVolume(settings.playbackVolume)
        playbackController.setMuted(settings.playbackMuted)
        splitViewController.transportControlsView?.updateVolume(
            settings.playbackVolume,
            muted: settings.playbackMuted
        )
        splitViewController.transportControlsView?.onVolumeChange = { [weak self] volume in
            guard let self else { return }
            Settings.shared.playbackVolume = volume
            Settings.shared.playbackMuted = false
            self.playbackController.setVolume(volume)
            self.playbackController.setMuted(false)
            self.splitViewController.transportControlsView?.updateVolume(volume, muted: false)
        }
        splitViewController.transportControlsView?.onMuteToggle = { [weak self] in
            guard let self else { return }
            let muted = self.playbackController.toggleMuted()
            Settings.shared.playbackMuted = muted
            self.splitViewController.transportControlsView?.updateVolume(
                Settings.shared.playbackVolume,
                muted: muted
            )
        }

        // Wire word selection directly into the transcript view.
        splitViewController.transcriptView?.project = project
        splitViewController.transcriptView?.refreshAllWordAppearances()
        splitViewController.transcriptView?.onWordClicked = { [weak self] word in
            self?.playbackController.seekToSourceTime(word.start)
        }
        splitViewController.transcriptView?.onRestoreWord = { [weak self] wordID in
            self?.restoreWord(wordID)
        }
        splitViewController.transcriptView?.onCorrectWord = { [weak self] wordID in
            guard let self, let word = self.project.word(withID: wordID) else { return }
            self.presentCorrection(for: word)
        }
    }

    private func updateEditReview(using renderPlan: RenderPlan) {
        let model = EditReviewModel(
            renderPlan: renderPlan,
            sourceDuration: project.duration
        )
        editReviewModel = model
        splitViewController.transportControlsView?.updateReviewSummary(
            cutCount: model.cutCount,
            removed: model.removedDuration,
            final: model.finalDuration
        )
        splitViewController.waveformView?.updateDeletedRanges(
            renderPlan.deletedRanges,
            duration: project.duration
        )
        updateEditNavigationAvailability()
    }

    private func updateEditNavigationAvailability() {
        splitViewController.transportControlsView?.updateEditNavigation(
            previousEnabled: editReviewModel?.previousTarget(
                from: currentEditedPlaybackTime
            ) != nil,
            nextEnabled: editReviewModel?.nextTarget(
                from: currentEditedPlaybackTime
            ) != nil
        )
    }

    private func enableEditingToolbar() {
        updateToolbarState()
    }

    func updateToolbarState() {
        let hasTranscript = project.hasEditableTranscript
        let hasMedia = project.appState == .editing && project.filePath?.isEmpty == false
        let hasOpenProject = project.appState != .empty
        cleanupToolbarButton?.isEnabled = hasTranscript
        agentToolbarButton?.isEnabled = hasTranscript
        saveToolbarButton?.isEnabled = hasTranscript
        updateExportToolbarButton()
        exportToolbarButton?.isEnabled = hasMedia
        settingsToolbarButton?.isEnabled = true
        closeToolbarButton?.isEnabled = hasOpenProject
        window?.title = hasTranscript ? window?.title ?? "Redact" : "Redact"
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

    static var supportedSourceMediaTypes: [UTType] {
        supportedMediaTypes.filter { $0 != UTType(filenameExtension: "rdt") }
    }

    static let allSupportedExtensions = supportedVideoExtensions + supportedAudioExtensions + supportedProjectExtensions
}

// MARK: - Menu validation

extension MainWindowController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(saveProject(_:)), #selector(saveProjectAs(_:)):
            return project.hasEditableTranscript
        case #selector(relinkMedia(_:)):
            return project.appState == .missingMedia
        case #selector(exportMedia(_:)), #selector(exportSRT(_:)):
            return project.appState == .editing && project.filePath?.isEmpty == false
        case #selector(cleanUpTranscript(_:)):
            return project.hasEditableTranscript
        case #selector(editWithAgent(_:)):
            return project.hasEditableTranscript
        case #selector(correctSelectedWord(_:)):
            return selectedCorrectableWord != nil
        case #selector(restoreSelectedWords(_:)):
            return project.selectedWordIds.contains { project.word(withID: $0)?.deleted == true }
        case #selector(deleteSelected(_:)):
            return project.selectedWordIds.contains { project.word(withID: $0)?.deleted == false }
        case #selector(performUndo(_:)):
            return project.canUndo
        case #selector(performRedo(_:)):
            return project.canRedo
        case #selector(togglePreview(_:)):
            menuItem.title = splitViewController.isPreviewVisible ? "Hide Preview" : "Show Preview"
            return project.appState == .editing
        default:
            return true
        }
    }
}

// MARK: - NSToolbarDelegate

private final class ToolbarIconButton: NSButton {
    static let width: CGFloat = 38
    static let height: CGFloat = 32

    private var pointerIsInside = false
    private var trackingRegion: NSTrackingArea?

    init(
        identifier: NSToolbarItem.Identifier,
        image: NSImage?,
        title: String,
        toolTip: String,
        target: AnyObject?,
        action: Selector?
    ) {
        super.init(frame: .zero)
        self.identifier = NSUserInterfaceItemIdentifier(identifier.rawValue)
        self.image = image
        self.title = ""
        self.toolTip = toolTip
        self.target = target
        self.action = action
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        alignment = .center
        isBordered = false
        setButtonType(.momentaryChange)
        setAccessibilityLabel(title)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = 13
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.width),
            heightAnchor.constraint(equalToConstant: Self.height),
        ])
        updateVisualState()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.width, height: Self.height)
    }

    override var isEnabled: Bool {
        didSet { updateVisualState() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingRegion {
            removeTrackingArea(trackingRegion)
        }
        let region = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(region)
        trackingRegion = region
    }

    override func mouseEntered(with event: NSEvent) {
        pointerIsInside = true
        updateVisualState()
    }

    override func mouseExited(with event: NSEvent) {
        pointerIsInside = false
        updateVisualState()
    }

    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = Theme.surface3.withAlphaComponent(0.9).cgColor
        super.mouseDown(with: event)
        updateVisualState()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateVisualState()
    }

    private func updateVisualState() {
        alphaValue = isEnabled ? 1 : 0.34
        contentTintColor = isEnabled ? Theme.textPrimary : Theme.textDimmed
        layer?.backgroundColor = pointerIsInside && isEnabled
            ? Theme.surface3.withAlphaComponent(0.62).cgColor
            : NSColor.clear.cgColor
    }
}

private final class ToolbarCapsuleView: NSView {
    private let buttons: [ToolbarIconButton]

    init(buttons: [ToolbarIconButton]) {
        self.buttons = buttons
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        setAccessibilityElement(false)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(
                equalToConstant: CGFloat(buttons.count) * ToolbarIconButton.width + 12
            ),
            heightAnchor.constraint(equalToConstant: 36),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
        updateLayerColors()
    }

    required init?(coder: NSCoder) {
        buttons = []
        super.init(coder: coder)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: CGFloat(buttons.count) * ToolbarIconButton.width + 12,
            height: 36
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayerColors()
    }

    private func updateLayerColors() {
        layer?.cornerRadius = intrinsicContentSize.height / 2
        layer?.backgroundColor = Theme.surface1.withAlphaComponent(0.88).cgColor
        layer?.borderColor = Theme.divider.withAlphaComponent(0.9).cgColor
        layer?.borderWidth = 1
    }
}

extension MainWindowController: NSToolbarDelegate {
    static let saveItem = NSToolbarItem.Identifier("saveProject")
    static let exportItem = NSToolbarItem.Identifier("export")
    static let cleanupItem = NSToolbarItem.Identifier("cleanup")
    static let agentItem = NSToolbarItem.Identifier("agent")
    static let closeProjectItem = NSToolbarItem.Identifier("closeProject")
    static let settingsItem = NSToolbarItem.Identifier("settings")
    static let editGroupItem = NSToolbarItem.Identifier("editActionGroup")
    static let outputGroupItem = NSToolbarItem.Identifier("outputActionGroup")
    static let flexibleSpace = NSToolbarItem.Identifier.flexibleSpace

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        switch itemIdentifier {
        case Self.editGroupItem:
            let cleanup = makeToolbarButton(
                identifier: Self.cleanupItem,
                title: "Clean Up",
                symbolName: "wand.and.stars",
                toolTip: "Clean Up: Review filler words, repeated words, and long pauses",
                action: #selector(cleanUpTranscript(_:))
            )
            let agent = makeToolbarButton(
                identifier: Self.agentItem,
                title: "Agent",
                symbolName: "sparkles",
                toolTip: "Agent: Edit with Codex or Claude Code",
                action: #selector(editWithAgent(_:))
            )
            cleanupToolbarButton = cleanup
            agentToolbarButton = agent
            configureCapsuleItem(
                item,
                label: "Editing Actions",
                buttons: [cleanup, agent],
                visibilityPriority: .high
            )

        case Self.outputGroupItem:
            let save = makeToolbarButton(
                identifier: Self.saveItem,
                title: "Save Project",
                symbolName: "floppy.disk",
                toolTip: "Save Project: Save the editable Redact project",
                action: #selector(saveProject(_:))
            )
            let export = makeToolbarButton(
                identifier: Self.exportItem,
                title: "Export Media",
                symbolName: "square.and.arrow.up",
                toolTip: "Export Media: Export the edited media",
                action: #selector(exportMedia(_:))
            )
            let settings = makeToolbarButton(
                identifier: Self.settingsItem,
                title: "Settings",
                symbolName: "gearshape",
                toolTip: "Settings: Open transcript and transcription settings",
                action: #selector(openSettings(_:))
            )
            let close = makeToolbarButton(
                identifier: Self.closeProjectItem,
                title: "Close",
                symbolName: "xmark",
                toolTip: "Close: Close the current project",
                action: #selector(closeProject(_:))
            )
            saveToolbarButton = save
            exportToolbarButton = export
            settingsToolbarButton = settings
            closeToolbarButton = close
            configureCapsuleItem(
                item,
                label: "Project Actions",
                buttons: [save, export, settings, close],
                visibilityPriority: .user
            )

        default:
            return nil
        }

        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            Self.editGroupItem, Self.flexibleSpace, Self.outputGroupItem,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            Self.editGroupItem, Self.outputGroupItem, Self.flexibleSpace,
        ]
    }

    private func makeToolbarButton(
        identifier: NSToolbarItem.Identifier,
        title: String,
        symbolName: String,
        toolTip: String,
        action: Selector
    ) -> ToolbarIconButton {
        ToolbarIconButton(
            identifier: identifier,
            image: toolbarSymbol(named: symbolName, title: title),
            title: title,
            toolTip: toolTip,
            target: self,
            action: action
        )
    }

    private func configureCapsuleItem(
        _ item: NSToolbarItem,
        label: String,
        buttons: [ToolbarIconButton],
        visibilityPriority: NSToolbarItem.VisibilityPriority
    ) {
        item.label = label
        item.paletteLabel = label
        item.isBordered = false
        item.view = ToolbarCapsuleView(buttons: buttons)
        item.visibilityPriority = visibilityPriority
    }

    private func toolbarSymbol(
        named symbolName: String,
        title: String
    ) -> NSImage? {
        if symbolName == "floppy.disk" {
            return floppyDiskToolbarImage(accessibilityDescription: title)
        }
        let configuration = NSImage.SymbolConfiguration(
            pointSize: 14,
            weight: .medium
        )
        return NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: title
        )?.withSymbolConfiguration(configuration)
    }

    private func floppyDiskToolbarImage(accessibilityDescription: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { bounds in
            NSColor.labelColor.setStroke()

            let shell = NSBezierPath(
                roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5),
                xRadius: 2,
                yRadius: 2
            )
            shell.lineWidth = 1.5
            shell.stroke()

            let shutter = NSBezierPath(rect: NSRect(x: 5, y: 10, width: 8, height: 5))
            shutter.lineWidth = 1.5
            shutter.stroke()

            let label = NSBezierPath(
                roundedRect: NSRect(x: 4, y: 2.5, width: 10, height: 5),
                xRadius: 1,
                yRadius: 1
            )
            label.lineWidth = 1.5
            label.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    private func updateExportToolbarButton() {
        let title: String
        let symbolName: String
        if let mediaInfo = project.mediaInfo {
            title = mediaInfo.hasVideo ? "Export Video" : "Export Audio"
            symbolName = "square.and.arrow.up"
        } else {
            title = "Export Media"
            symbolName = "square.and.arrow.up"
        }
        guard let button = exportToolbarButton else { return }
        button.image = toolbarSymbol(named: symbolName, title: title)
        button.toolTip = "\(title): Export the edited \(mediaInfoDescription)"
        button.setAccessibilityLabel(title)
    }

    private var mediaInfoDescription: String {
        guard let mediaInfo = project.mediaInfo else { return "media" }
        return mediaInfo.hasVideo ? "video" : "audio"
    }
}

private func formatAgentDuration(_ duration: Double) -> String {
    let totalTenths = Int((max(0, duration) * 10).rounded())
    let minutes = totalTenths / 600
    let seconds = Double(totalTenths % 600) / 10
    return String(format: "%d:%04.1f", minutes, seconds)
}
