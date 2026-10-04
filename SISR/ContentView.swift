import AppKit
import SwiftUI
import SISRKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RecentDocumentsStore.self) private var recent

    @State private var project = SequenceProject()
    @State private var renderController = RenderController()
    @State private var frameCache = FrameCache()
    @State private var showInspector = true
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var playback = PlaybackController()
    @State private var autosaveTask: Task<Void, Never>?
    @State private var showRenderError = false

    var body: some View {
        mainSplit
            .toolbar { toolbarContent }
            .navigationTitle(project.displayTitle)
            .navigationSubtitle(project.subtitle)
            .onAppear(perform: setupOnAppear)
            .onChange(of: settings.notifyOnRenderComplete) { _, enabled in
                renderController.notifyOnRenderComplete = enabled
            }
            .modifier(ProjectSessionNotificationsModifier(
                project: project,
                renderController: renderController,
                frameCache: frameCache,
                openSequence: openSequence,
                openDirectory: loadDirectory,
                closeSequence: closeSequence,
                scheduleAutosave: scheduleAutosave
            ))
            .modifier(PlaybackTransportNotificationsModifier(
                project: project,
                playback: playback
            ))
            .onChange(of: project.crop) { _, _ in scheduleAutosave() }
            .onChange(of: project.adjustments) { _, _ in scheduleAutosave() }
            .onChange(of: project.render) { _, _ in scheduleAutosave() }
            // Skip playhead autosave while playing — it was hitching every frame.
            .onChange(of: project.playheadIndex) { _, _ in
                guard !playback.isPlaying else { return }
                scheduleAutosave()
            }
            .onChange(of: playback.isPlaying) { _, playing in
                if !playing {
                    scheduleAutosave()
                }
            }
            .onChange(of: renderController.errorMessage) { _, newValue in
                showRenderError = newValue != nil
            }
            .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
            .alert("Render Error", isPresented: $showRenderError) {
                Button("Copy Details") { copyErrorDetails() }
                Button("OK", role: .cancel) { renderController.errorMessage = nil }
            } message: {
                Text(renderController.errorMessage ?? "")
            }
    }

    private var mainSplit: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(project: project, renderController: renderController, frameCache: frameCache)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
        } detail: {
            detailColumn
        }
    }

    private var detailColumn: some View {
        VStack(spacing: 0) {
            ViewerView(
                project: project,
                frameCache: frameCache,
                playback: playback
            )
            TimelineView(
                project: project,
                frameCache: frameCache,
                playback: playback
            )
            .frame(height: 120)
        }
        .background(Theme.viewerCanvas)
        .inspector(isPresented: $showInspector) {
            InspectorView(project: project)
                .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button(action: openSequence) {
                Label("Open", systemImage: "folder")
            }
            .help("Open image sequence (⌘O)")

            Button(action: closeSequence) {
                Label("Close", systemImage: "xmark.circle")
            }
            .help("Close sequence (⇧⌘W)")
            .disabled(!project.hasSequence || renderController.isRendering)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            ControlGroup {
                Toggle(isOn: showOriginalBinding) {
                    Label("Original", systemImage: "square.split.2x1")
                }
                .help("Before / After (\\)")

                Menu {
                    Button("Fit") { playback.zoomMode = .fit }
                    Button("100%") { playback.zoomMode = .actual }
                    Button("200%") { playback.zoomMode = .double }
                } label: {
                    Label("Zoom", systemImage: "plus.magnifyingglass")
                }
            }

            Toggle(isOn: $showInspector) {
                Label("Inspector", systemImage: "sidebar.trailing")
            }

            if renderController.isRendering {
                ProgressView(value: renderController.progress?.fraction ?? 0)
                    .controlSize(.small)
                    .frame(width: 110)
                    .help(renderController.progress?.statusMessage ?? "Rendering…")
            }

            Button {
                renderController.start(project: project, frameCache: frameCache)
            } label: {
                Label("Render", systemImage: "film")
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!project.hasSequence || renderController.isRendering)
        }
    }

    private var showOriginalBinding: Binding<Bool> {
        Binding(
            get: { project.showOriginal },
            set: { newValue in
                project.showOriginal = newValue
                if newValue {
                    project.previewOutputFull = false
                }
            }
        )
    }

    private func setupOnAppear() {
        frameCache = FrameCache(countLimit: settings.previewCacheLimit)
        project.render.fps = settings.defaultFPS
        project.render.codec = settings.defaultCodec
        renderController.notifyOnRenderComplete = settings.notifyOnRenderComplete
        // Do not apply a path-only default output folder — without a security-scoped
        // bookmark the sandbox cannot overwrite files there (permission errors on render).
    }

    private func openSequence() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder containing a numbered image sequence"
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadDirectory(url)
    }

    private func closeSequence() {
        guard !renderController.isRendering else { return }
        playback.stop()
        project.close()
        frameCache.clear()
        renderController.progress = nil
        renderController.completedURL = nil
        renderController.errorMessage = nil
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let path = String(data: data, encoding: .utf8),
                  let url = URL(string: path)
            else { return }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue
            else { return }
            Task { @MainActor in
                loadDirectory(url)
            }
        }
        return true
    }

    private func loadDirectory(_ url: URL) {
        let bookmark = BookmarkStore.bookmark(for: url)
        _ = url.startAccessingSecurityScopedResource()
        do {
            try project.load(directory: url, bookmark: bookmark)
            if let saved = ProjectPersistence.load(forSourcePath: url.path) {
                project.restore(saved)
            }
            recent.add(url: url, bookmark: bookmark)
            frameCache.clear()
            scheduleAutosave()
        } catch {
            project.loadError = error.localizedDescription
        }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            ProjectPersistence.save(project.persistedState)
        }
    }

    private func copyErrorDetails() {
        guard let msg = renderController.errorMessage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(msg, forType: .string)
    }
}

/// File / render / mark notifications — kept separate for faster type-checking.
private struct ProjectSessionNotificationsModifier: ViewModifier {
    var project: SequenceProject
    var renderController: RenderController
    var frameCache: FrameCache
    var openSequence: () -> Void
    var openDirectory: (URL) -> Void
    var closeSequence: () -> Void
    var scheduleAutosave: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .sisrOpenSequence)) { _ in
                openSequence()
            }
            .onReceive(NotificationCenter.default.publisher(for: .sisrOpenDirectoryURL)) { note in
                if let url = note.object as? URL {
                    openDirectory(url)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .sisrCloseSequence)) { _ in
                closeSequence()
            }
            .onReceive(NotificationCenter.default.publisher(for: .sisrRender)) { _ in
                renderController.start(project: project, frameCache: frameCache)
            }
            .onReceive(NotificationCenter.default.publisher(for: .sisrSetIn)) { _ in
                project.setInPoint()
                scheduleAutosave()
            }
            .onReceive(NotificationCenter.default.publisher(for: .sisrSetOut)) { _ in
                project.setOutPoint()
                scheduleAutosave()
            }
            .onReceive(NotificationCenter.default.publisher(for: .sisrClearInOut)) { _ in
                project.clearInOut()
                scheduleAutosave()
            }
            .onReceive(NotificationCenter.default.publisher(for: .sisrToggleOriginal)) { _ in
                project.showOriginal.toggle()
            }
    }
}

/// Playhead / shuttle notifications — kept separate for faster type-checking.
private struct PlaybackTransportNotificationsModifier: ViewModifier {
    var project: SequenceProject
    var playback: PlaybackController

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .sisrGoToStart)) { _ in
                playback.goToStart(project: project)
            }
            .onReceive(NotificationCenter.default.publisher(for: .sisrGoToIn)) { _ in
                playback.goToIn(project: project)
            }
            .onReceive(NotificationCenter.default.publisher(for: .sisrGoToOut)) { _ in
                playback.goToOut(project: project)
            }
            .onReceive(NotificationCenter.default.publisher(for: .sisrGoToEnd)) { _ in
                playback.goToEnd(project: project)
            }
            .onReceive(NotificationCenter.default.publisher(for: .sisrTogglePlay)) { _ in
                playback.toggle(project: project)
            }
            .onReceive(NotificationCenter.default.publisher(for: .sisrTogglePlayInOut)) { _ in
                playback.toggleInOut(project: project)
            }
            .onReceive(NotificationCenter.default.publisher(for: .sisrShuttleReverse)) { _ in
                playback.shuttle(project: project, direction: -1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .sisrShuttleStop)) { _ in
                playback.shuttle(project: project, direction: 0)
            }
            .onReceive(NotificationCenter.default.publisher(for: .sisrShuttleForward)) { _ in
                playback.shuttle(project: project, direction: 1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .sisrStepBack)) { _ in
                playback.step(project: project, delta: -1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .sisrStepForward)) { _ in
                playback.step(project: project, delta: 1)
            }
    }
}
