import AppKit
import Foundation
import Observation
import SISRKit
@preconcurrency import UserNotifications

@Observable
@MainActor
final class RenderController {
    var progress: RenderProgress?
    var isRendering = false
    var errorMessage: String?
    var completedURL: URL?

    /// When false, completion notifications are skipped (Settings → Notifications).
    var notifyOnRenderComplete = true

    private let renderer = Renderer()
    private var renderTask: Task<Void, Never>?
    private var lastProgressPublish = Date.distantPast
    private var pendingProgress: RenderProgress?
    private var publishTask: Task<Void, Never>?
    private let renderAccess = BookmarkStore.RenderAccess()
    private var didRequestNotificationAuth = false

    func start(project: SequenceProject, frameCache: FrameCache? = nil) {
        guard !isRendering, project.hasSequence else { return }

        project.clearOutputIfPointsAtSource()
        guard ensureOutputDirectory(project: project) else { return }

        if let accessError = renderAccess.begin(project: project) {
            errorMessage = accessError
            return
        }

        isRendering = true
        errorMessage = nil
        completedURL = nil
        progress = RenderProgress(framesTotal: project.selectedFrameCount, statusMessage: "Preparing…")
        lastProgressPublish = .distantPast
        pendingProgress = nil
        publishTask?.cancel()
        frameCache?.pauseForRender()
        let snapshot = SequenceProjectSnapshot(from: project)

        renderTask = Task { [renderer, self] in
            do {
                let url = try await renderer.render(project: snapshot) { prog in
                    Task { @MainActor in
                        self.enqueueProgress(prog)
                    }
                }
                await MainActor.run {
                    self.publishTask?.cancel()
                    self.isRendering = false
                    self.completedURL = url
                    var final = self.progress ?? RenderProgress(framesTotal: snapshot.timeline.frameCount)
                    final.isFinished = true
                    final.outputURL = url
                    final.framesDone = final.framesTotal
                    final.latestThumbnail = nil
                    final.statusMessage = nil
                    self.progress = final
                    self.renderAccess.release()
                    frameCache?.resumeAfterRender()
                    NSApp.dockTile.badgeLabel = nil
                    NSApp.dockTile.display()
                    self.notifyCompletion(url: url)
                }
            } catch RenderError.cancelled {
                await MainActor.run {
                    self.publishTask?.cancel()
                    self.isRendering = false
                    self.progress?.isCancelled = true
                    self.progress?.latestThumbnail = nil
                    self.progress?.statusMessage = nil
                    self.renderAccess.release()
                    frameCache?.resumeAfterRender()
                    NSApp.dockTile.badgeLabel = nil
                }
            } catch {
                await MainActor.run {
                    self.publishTask?.cancel()
                    self.isRendering = false
                    self.errorMessage = error.localizedDescription
                    self.progress?.errorMessage = error.localizedDescription
                    self.progress?.latestThumbnail = nil
                    self.progress?.statusMessage = nil
                    self.renderAccess.release()
                    frameCache?.resumeAfterRender()
                    NSApp.dockTile.badgeLabel = nil
                }
            }
        }
    }

    func cancel() {
        renderTask?.cancel()
        Task { await renderer.cancel() }
    }

    func revealInFinder() {
        guard let url = completedURL ?? progress?.outputURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Coalesce high-frequency renderer callbacks so SwiftUI / Dock aren't flooded
    /// with full progress structs (and NSImages) every frame.
    private func enqueueProgress(_ prog: RenderProgress) {
        var merged = prog
        if merged.latestThumbnail == nil {
            merged.latestThumbnail = progress?.latestThumbnail ?? pendingProgress?.latestThumbnail
        }
        // Keep a prior status only when the new sample is a silent encode tick at 0;
        // never sticky-hold "Analyzing…" over a newer phase label.
        if merged.statusMessage == nil,
           prog.framesDone == 0,
           progress?.statusMessage != "Analyzing deflicker…"
        {
            merged.statusMessage = progress?.statusMessage ?? pendingProgress?.statusMessage
        }
        pendingProgress = merged

        let now = Date()
        let force = prog.isFinished || prog.isCancelled || prog.errorMessage != nil
        let elapsed = now.timeIntervalSince(lastProgressPublish)
        // Deflicker emits often — publish at least ~8×/sec so the bar moves.
        let interval: TimeInterval = (prog.statusMessage?.contains("deflicker") == true) ? 0.08 : 0.12
        if force || elapsed >= interval {
            flushProgress()
            return
        }

        if publishTask == nil {
            let delay = 0.12 - elapsed
            publishTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(max(0.01, delay) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self.flushProgress()
            }
        }
    }

    private func flushProgress() {
        publishTask = nil
        guard var next = pendingProgress else { return }
        pendingProgress = nil
        lastProgressPublish = Date()

        if next.latestThumbnail == nil {
            next.latestThumbnail = progress?.latestThumbnail
        }
        progress = next

        if next.isFinished {
            NSApp.dockTile.badgeLabel = nil
        } else {
            NSApp.dockTile.badgeLabel = "\(Int(next.fraction * 100))"
        }
        NSApp.dockTile.display()
    }

    /// Prompts for an output folder when none is set. Returns `false` if the user cancels.
    @discardableResult
    private func ensureOutputDirectory(project: SequenceProject) -> Bool {
        if project.hasOutputDirectory { return true }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder for the rendered video (not the image sequence folder)."
        panel.prompt = "Use Folder"
        if let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first {
            panel.directoryURL = movies
        }

        guard panel.runModal() == .OK, let url = panel.url else { return false }

        project.render.outputDirectoryPath = url.path
        project.render.outputDirectoryBookmark = BookmarkStore.bookmark(for: url)
        _ = url.startAccessingSecurityScopedResource()
        return true
    }

    private func notifyCompletion(url: URL) {
        guard notifyOnRenderComplete else { return }

        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                self.postRenderNotification(url: url)
            case .notDetermined:
                guard !self.didRequestNotificationAuth else { return }
                self.didRequestNotificationAuth = true
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
                if granted {
                    self.postRenderNotification(url: url)
                }
            default:
                break
            }
        }
    }

    private func postRenderNotification(url: URL) {
        let content = UNMutableNotificationContent()
        content.title = "Render complete"
        content.body = url.lastPathComponent
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }
}
