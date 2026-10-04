import SwiftUI
import SISRKit

struct RenderFooter: View {
    var project: SequenceProject
    @Bindable var renderController: RenderController
    var frameCache: FrameCache

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if renderController.isRendering || (renderController.progress?.isFinished == true)
                || (renderController.progress?.isCancelled == true)
            {
                RenderProgressCard(controller: renderController)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ready to render")
                                .font(.subheadline.weight(.semibold))
                            Text(summaryLine)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }

                    Button {
                        renderController.start(project: project, frameCache: frameCache)
                    } label: {
                        Label("Render", systemImage: "film")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!project.hasSequence)
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
        }
    }

    private var summaryLine: String {
        let size = project.outputPixelSize.label
        let codec = project.render.codec.displayName
        let frames = project.selectedFrameCount
        return "\(size) · \(codec) · \(frames) frames"
    }
}

struct RenderProgressCard: View {
    @Bindable var controller: RenderController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                if let thumb = controller.progress?.latestThumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 76, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Theme.hairline, lineWidth: 1)
                        }
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.quaternary.opacity(0.5))
                            .frame(width: 76, height: 44)
                        Image(systemName: statusSymbol)
                            .foregroundStyle(.secondary)
                            .symbolRenderingMode(.hierarchical)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(.headline)
                    if let p = controller.progress {
                        let isAnalyzing = p.statusMessage?.contains("deflicker") == true
                        Text(
                            isAnalyzing
                                ? "\(p.framesDone) / \(p.framesTotal) frames analyzed"
                                : "\(p.framesDone) / \(p.framesTotal) · \(String(format: "%.1f", p.framesPerSecond)) fps"
                        )
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                        if let eta = p.eta, !p.isFinished, !p.isCancelled {
                            Text(isAnalyzing
                                 ? "About \(formatDuration(eta)) to finish analysis"
                                 : "About \(formatDuration(eta)) remaining")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            ProgressView(value: controller.progress?.fraction ?? 0)
                .tint(progressTint)

            HStack(spacing: 8) {
                if controller.isRendering {
                    Button("Cancel", role: .destructive) {
                        controller.cancel()
                    }
                    .controlSize(.small)
                }
                if controller.progress?.isFinished == true {
                    Button {
                        controller.revealInFinder()
                    } label: {
                        Label("Reveal", systemImage: "folder")
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    Button("Done") {
                        controller.progress = nil
                        controller.completedURL = nil
                    }
                    .controlSize(.small)
                }
                if controller.progress?.isCancelled == true {
                    Button("Dismiss") {
                        controller.progress = nil
                    }
                    .controlSize(.small)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.panelCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.panelCorner, style: .continuous)
                .strokeBorder(Theme.hairline.opacity(0.8), lineWidth: 1)
        }
    }

    private var statusTitle: String {
        if controller.progress?.isCancelled == true { return "Cancelled" }
        if controller.progress?.isFinished == true { return "Complete" }
        if controller.progress?.errorMessage != nil { return "Failed" }
        if let status = controller.progress?.statusMessage, !status.isEmpty {
            return status
        }
        return "Rendering…"
    }

    private var statusSymbol: String {
        if controller.progress?.isCancelled == true { return "xmark.circle" }
        if controller.progress?.isFinished == true { return "checkmark.circle" }
        if controller.progress?.errorMessage != nil { return "exclamationmark.triangle" }
        return "film"
    }

    private var progressTint: Color {
        if controller.progress?.isCancelled == true { return .secondary }
        if controller.progress?.errorMessage != nil { return .red }
        if controller.progress?.isFinished == true { return Theme.badgeNative }
        return .accentColor
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let s = Int(max(0, t))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
