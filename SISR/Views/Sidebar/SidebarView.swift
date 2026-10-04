import AppKit
import SwiftUI
import SISRKit

struct SidebarView: View {
    @Bindable var project: SequenceProject
    @Bindable var renderController: RenderController
    var frameCache: FrameCache
    @Environment(RecentDocumentsStore.self) private var recent

    var body: some View {
        VStack(spacing: 0) {
            Form {
                SequenceSection(project: project, recent: recent)
                EncodeSection(project: project)
                DestinationSection(project: project)
                OverlaySection(project: project)
            }
            .formStyle(.grouped)
            .disabled(renderController.isRendering)

            SoftDivider()

            RenderFooter(project: project, renderController: renderController, frameCache: frameCache)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
        .background(.regularMaterial)
    }
}

// MARK: - Sequence

struct SequenceSection: View {
    @Bindable var project: SequenceProject
    var recent: RecentDocumentsStore
    @AppStorage("sisr.ui.sequenceDetails") private var showDetails = false

    var body: some View {
        Section {
            if let sequence = project.sequence {
                LabeledContent("Folder") {
                    Text(sequence.displayName)
                        .fontWeight(.medium)
                }
                HStack(spacing: 8) {
                    MetricPill(text: "\(sequence.frameCount) frames")
                    if project.sourceSize.width > 0 {
                        MetricPill(
                            text: "\(Int(project.sourceSize.width))×\(Int(project.sourceSize.height))"
                        )
                    }
                }
                .padding(.vertical, 2)

                HStack(spacing: 8) {
                    Button {
                        NotificationCenter.default.post(name: .sisrOpenSequence, object: nil)
                    } label: {
                        Label("Open…", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        NotificationCenter.default.post(name: .sisrCloseSequence, object: nil)
                    } label: {
                        Label("Close", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                }

                DisclosureGroup(isExpanded: $showDetails) {
                    LabeledContent("Pattern") {
                        Text(sequence.pattern)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    if !recent.recent.isEmpty {
                        Menu {
                            ForEach(recent.recent) { item in
                                Button(item.displayName) { openRecent(item) }
                            }
                            Divider()
                            Button("Clear Menu", role: .destructive) { recent.clear() }
                        } label: {
                            Label("Open Recent", systemImage: "clock.arrow.circlepath")
                        }
                    }
                } label: {
                    DisclosureLabel(
                        title: "Details",
                        subtitle: showDetails ? nil : "Pattern and recent sequences"
                    )
                }
            } else {
                EmptyPanelHint(
                    systemImage: "square.stack.3d.up",
                    title: "No sequence",
                    message: "Open a folder of numbered stills, or drag one onto the viewer."
                )

                Button {
                    NotificationCenter.default.post(name: .sisrOpenSequence, object: nil)
                } label: {
                    Label("Open Sequence…", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if !recent.recent.isEmpty {
                    Menu {
                        ForEach(recent.recent) { item in
                            Button(item.displayName) { openRecent(item) }
                        }
                        Divider()
                        Button("Clear Menu", role: .destructive) { recent.clear() }
                    } label: {
                        Label("Open Recent", systemImage: "clock.arrow.circlepath")
                    }
                }
            }

            if let error = project.loadError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .symbolRenderingMode(.hierarchical)
            }
        } header: {
            PanelSectionHeader(title: "Sequence", systemImage: "square.stack.3d.up")
        }
    }

    private func openRecent(_ item: RecentDocumentsStore.RecentItem) {
        if let data = item.bookmark, let resolved = BookmarkStore.resolve(data) {
            try? project.load(directory: resolved.url, bookmark: data)
            if let saved = ProjectPersistence.load(forSourcePath: resolved.url.path) {
                project.restore(saved)
            }
            return
        }
        let url = URL(fileURLWithPath: item.path)
        try? project.load(directory: url)
    }
}

// MARK: - Encode

struct EncodeSection: View {
    @Bindable var project: SequenceProject
    @AppStorage("sisr.ui.encodeAdvanced") private var showAdvanced = false

    private let fpsPresets: [Double] = [23.976, 24, 25, 29.97, 30, 60]

    var body: some View {
        Section {
            Picker("Codec", selection: $project.render.codec) {
                ForEach(OutputCodec.allCases) { codec in
                    Text(codec.displayName).tag(codec)
                }
            }
            .onChange(of: project.render.codec) { _, codec in
                if codec == .gif, project.render.fps > 10 {
                    project.render.fps = 4
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Picker("Frame rate", selection: $project.render.fps) {
                    ForEach(fpsPresets, id: \.self) { fps in
                        Text(fpsLabel(fps)).tag(fps)
                    }
                }
                TextField("FPS", value: $project.render.fps, format: .number)
                    .labelsHidden()
                    .frame(width: 56)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
            }

            LabeledContent("Duration") {
                Text(durationLabel)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if supportsBitrateControls {
                DisclosureGroup(isExpanded: $showAdvanced) {
                    bitrateAdvancedControls
                } label: {
                    DisclosureLabel(
                        title: "Bitrate & quality",
                        subtitle: showAdvanced ? nil : bitrateSummary
                    )
                }
            }
        } header: {
            PanelSectionHeader(title: "Encode", systemImage: "film")
        }
    }

    @ViewBuilder
    private var bitrateAdvancedControls: some View {
        let size = project.outputPixelSize
        let codec = project.render.codec
        let autoAvg = VideoBitrate.defaultAverageMbps(
            codec: codec,
            width: size.width,
            height: size.height
        )
        let autoMax = VideoBitrate.defaultMaxMbps(averageMbps: autoAvg)

        VStack(alignment: .leading, spacing: 10) {
            bitrateField(
                title: "Target bitrate",
                value: $project.render.videoEncode.averageBitRateMbps,
                placeholder: autoAvg,
                unit: "Mbps"
            )
            bitrateField(
                title: "Max bitrate",
                value: $project.render.videoEncode.maxBitRateMbps,
                placeholder: autoMax,
                unit: "Mbps"
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Quality")
                    Spacer()
                    Text(qualityLabel)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: {
                            project.render.videoEncode.quality ?? VideoBitrate.defaultQualityHint
                        },
                        set: { project.render.videoEncode.quality = min(1, max(0, $0)) }
                    ),
                    in: 0...1
                )
                .controlSize(.small)
                Text("Optional encoder hint (0–1). Leave on Auto unless you need it — bitrate is the main control.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                if project.render.videoEncode.quality != nil {
                    Button("Quality: Auto") {
                        project.render.videoEncode.quality = nil
                    }
                    .controlSize(.small)
                }
                Spacer()
                Button("Reset to defaults") {
                    project.render.videoEncode.resetToDefaults()
                }
                .controlSize(.small)
                .disabled(project.render.videoEncode.usesAutomaticDefaults)
            }
        }
        .padding(.top, 4)
    }

    private func bitrateField(
        title: String,
        value: Binding<Double?>,
        placeholder: Double,
        unit: String
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(
                "",
                value: Binding(
                    get: { value.wrappedValue ?? placeholder },
                    set: { newValue in
                        let clamped = max(0.1, newValue)
                        // Treat matching the auto ladder as “clear override”.
                        if abs(clamped - placeholder) < 0.05 {
                            value.wrappedValue = nil
                        } else {
                            value.wrappedValue = (clamped * 10).rounded() / 10
                        }
                    }
                ),
                format: .number.precision(.fractionLength(1))
            )
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .frame(width: 64)
            .textFieldStyle(.roundedBorder)
            Text(unit)
                .foregroundStyle(.secondary)
            if value.wrappedValue == nil {
                Text("Auto")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var supportsBitrateControls: Bool {
        switch project.render.codec {
        case .h264, .hevc: return true
        case .prores, .proresHQ, .gif: return false
        }
    }

    private var bitrateSummary: String {
        let size = project.outputPixelSize
        let avg = project.render.videoEncode.resolvedAverageMbps(
            codec: project.render.codec,
            width: size.width,
            height: size.height
        )
        let max = project.render.videoEncode.resolvedMaxMbps(
            codec: project.render.codec,
            width: size.width,
            height: size.height
        )
        let auto = project.render.videoEncode.usesAutomaticDefaults ? "Auto · " : ""
        return String(format: "%@%.1f / %.1f Mbps", auto, avg, max)
    }

    private var qualityLabel: String {
        if let q = project.render.videoEncode.quality {
            return String(format: "%.2f", q)
        }
        return "Auto"
    }

    private func fpsLabel(_ fps: Double) -> String {
        if abs(fps - 29.97) < 0.01 { return "29.97" }
        if abs(fps - 23.976) < 0.01 { return "23.976" }
        if fps == fps.rounded() { return String(Int(fps)) }
        return String(fps)
    }

    private var durationLabel: String {
        let frames = project.selectedFrameCount
        let secs = project.durationSeconds
        return "\(frames) fr · \(String(format: "%.1f", secs)) s"
    }
}

// MARK: - Destination

struct DestinationSection: View {
    @Bindable var project: SequenceProject
    @AppStorage("sisr.ui.destinationDetails") private var showDetails = false

    var body: some View {
        Section {
            PathBrowserRow(
                path: project.render.outputDirectoryPath,
                placeholder: "Choose output folder…",
                action: pickOutputFolder
            )

            TextField("File name", text: $project.render.outputBaseName)
                .textFieldStyle(.roundedBorder)

            DisclosureGroup(isExpanded: $showDetails) {
                if let preview = previewFilename {
                    LabeledContent("Writes as") {
                        Text(preview)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } label: {
                DisclosureLabel(
                    title: "Filename preview",
                    subtitle: showDetails ? nil : previewFilename
                )
            }
        } header: {
            PanelSectionHeader(title: "Destination", systemImage: "folder")
        }
    }

    private var previewFilename: String? {
        guard !project.render.outputBaseName.isEmpty else { return nil }
        return OutputNaming.makeFilename(
            baseName: project.render.outputBaseName,
            settings: project.render,
            cropLabel: project.render.preset == .original ? nil : project.render.preset.rawValue,
            outputSize: project.outputPixelSize
        )
    }

    private func pickOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        project.render.outputDirectoryPath = url.path
        project.render.outputDirectoryBookmark = BookmarkStore.bookmark(for: url)
        _ = url.startAccessingSecurityScopedResource()
    }
}

// MARK: - Overlay

struct OverlaySection: View {
    @Bindable var project: SequenceProject

    var body: some View {
        Section {
            Picker("Burn-in", selection: $project.render.overlay) {
                ForEach(OverlayType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)

            if project.render.overlay == .date {
                VStack(alignment: .leading, spacing: 8) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 6) {
                        Toggle("Day", isOn: $project.render.dateParts.day)
                        Toggle("Month", isOn: $project.render.dateParts.month)
                        Toggle("Date", isOn: $project.render.dateParts.date)
                        Toggle("Year", isOn: $project.render.dateParts.year)
                        Toggle("Time", isOn: $project.render.dateParts.time)
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)

                    Text(sampleDate.isEmpty ? "—" : sampleDate)
                        .font(.system(.title3, design: .monospaced).weight(.medium))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.controlCorner, style: .continuous))
                }
            }

            if project.render.overlay == .frame {
                Picker("Numbering", selection: $project.render.frameNumberMode) {
                    Text("From in point").tag(FrameNumberMode.countFromInPoint)
                    Text("Source numbers").tag(FrameNumberMode.useSourceNumbers)
                }
            }

            if project.render.overlay != .none {
                AdjustmentSliderRow(
                    title: "Background",
                    value: Binding(
                        get: { project.render.overlayBackgroundOpacity * 100 },
                        set: { project.render.overlayBackgroundOpacity = RenderSettings.clampOpacity($0 / 100) }
                    ),
                    range: 0...100,
                    resetValue: 50,
                    format: .number.precision(.fractionLength(0)),
                    unit: "%",
                    fieldWidth: 44
                )
            }
        } header: {
            PanelSectionHeader(title: "Overlay", systemImage: "text.below.photo")
        }
    }

    private var sampleDate: String {
        if let raw = project.dateString(at: project.playheadIndex) {
            return DateOverlayFormatter.format(raw, parts: project.render.dateParts)
        }
        return DateOverlayFormatter.format("2024:01:05 13:30:00", parts: project.render.dateParts)
    }
}
