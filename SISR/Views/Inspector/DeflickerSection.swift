import Charts
import SwiftUI
import SISRKit

struct DeflickerSection: View {
    @Bindable var project: SequenceProject
    var controller: DeflickerController
    @AppStorage("sisr.ui.deflicker") private var showDeflicker = false
    @AppStorage("sisr.ui.deflickerAdvanced") private var showAdvanced = false

    private var settings: DeflickerSettings { project.adjustments.deflicker }

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $showDeflicker) {
                Toggle(isOn: $project.adjustments.deflicker.enabled) {
                    Label("Enabled", systemImage: "sun.max.trianglebadge.exclamationmark")
                }
                if settings.enabled {
                    modePicker
                    Text(DeflickerPreset.matching(settings).summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    AdjustmentSliderRow(
                        title: "Strength",
                        value: $project.adjustments.deflicker.strength,
                        range: 0...1,
                        resetValue: 1
                    )
                    targetControls
                    analysisPanel
                    DisclosureGroup(isExpanded: $showAdvanced) {
                        advancedControls
                    } label: {
                        DisclosureLabel(title: "Advanced", subtitle: showAdvanced ? nil : advancedSummary)
                    }
                }
            } label: {
                DisclosureLabel(
                    title: "Deflicker",
                    subtitle: showDeflicker ? nil : deflickerSummary
                )
            }
        }
        .onAppear {
            if settings.enabled { showDeflicker = true }
        }
        .onChange(of: settings.enabled) { _, enabled in
            if enabled { showDeflicker = true }
        }
    }

    // MARK: - Mode

    private var modePicker: some View {
        let current = DeflickerPreset.matching(settings)
        return Picker("Mode", selection: Binding(
            get: { current },
            set: { project.adjustments.deflicker = $0.settings(from: project.adjustments.deflicker) }
        )) {
            ForEach(DeflickerPreset.tuned) { preset in
                Text(preset.displayName).tag(preset)
            }
            if current == .custom {
                Divider()
                Text(DeflickerPreset.custom.displayName).tag(DeflickerPreset.custom)
            }
        }
    }

    // MARK: - Target

    @ViewBuilder
    private var targetControls: some View {
        Picker("Balance to", selection: $project.adjustments.deflicker.target) {
            ForEach(DeflickerTarget.allCases) { target in
                Text(target.displayName).tag(target)
            }
        }
        .pickerStyle(.segmented)
        .help("Follow scene keeps slow changes like sunsets. Lock look matches every frame to one reference.")

        switch settings.target {
        case .followScene:
            windowRow
        case .locked:
            referenceRows
        }
    }

    private var windowRow: some View {
        HStack {
            Text("Window")
            Spacer()
            TextField(
                "",
                value: Binding(
                    get: { Double(settings.windowSize) },
                    set: { project.adjustments.deflicker.windowSize = DeflickerSettings.normalizedWindow(Int($0.rounded())) }
                ),
                format: .number.precision(.fractionLength(0))
            )
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .frame(width: 48)
            .textFieldStyle(.roundedBorder)
            Text("frames")
                .foregroundStyle(.secondary)
            Stepper(
                "",
                value: $project.adjustments.deflicker.windowSize,
                in: 3...121,
                step: 2
            )
            .labelsHidden()
        }
        .help("Frames considered around each frame. Wider removes slower flicker but follows real light changes less closely.")
    }

    @ViewBuilder
    private var referenceRows: some View {
        LabeledContent("Reference") {
            Text(referenceLabel)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        HStack(spacing: 8) {
            Button("Use current frame") {
                project.adjustments.deflicker.referenceFrame = project.playheadIndex
            }
            Button("Use median") {
                project.adjustments.deflicker.referenceFrame = nil
            }
            .disabled(settings.referenceFrame == nil)
        }
        .controlSize(.small)
    }

    private var referenceLabel: String {
        guard let index = settings.referenceFrame else { return "Median of in/out" }
        let range = project.timeline.clamped(to: project.frameCount)
        guard let sequence = project.sequence, sequence.frames.indices.contains(index) else {
            return "Median of in/out"
        }
        let number = String(format: "%0\(sequence.numberWidth)d", sequence.frames[index].frameNumber)
        let inside = index >= range.inIndex && index <= range.outIndex
        return inside ? "Frame \(number)" : "Frame \(number) (outside in/out — median)"
    }

    // MARK: - Analysis

    @ViewBuilder
    private var analysisPanel: some View {
        if controller.isAnalyzing {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: controller.progressFraction) {
                    Text("Analyzing \(controller.progressDone) of \(controller.progressTotal) frames…")
                        .font(.caption)
                }
                Button("Cancel", role: .cancel) { controller.cancelAnalysis() }
                    .controlSize(.small)
            }
        } else if let solution = controller.solution, let range = controller.solutionRange {
            VStack(alignment: .leading, spacing: 6) {
                DeflickerChart(
                    solution: solution,
                    version: controller.solutionVersion,
                    rangeStart: range.inIndex,
                    playhead: project.playheadIndex,
                    onScrub: { project.playheadIndex = $0 }
                )
                HStack(spacing: 6) {
                    MetricPill(
                        text: String(
                            format: "Flicker %.2f → %.2f EV",
                            solution.measuredFlicker,
                            solution.correctedFlicker
                        ),
                        tone: .green
                    )
                    MetricPill(text: String(format: "max ±%.2f EV", solution.maxAbsExposure))
                    Spacer(minLength: 0)
                }
                Button {
                    controller.analyze(project: project)
                } label: {
                    Label("Re-analyze", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    controller.analyze(project: project)
                } label: {
                    Label("Analyze sequence", systemImage: "waveform.path.ecg")
                }
                .disabled(!project.hasSequence)
                Text(controller.isStale(for: project)
                     ? "Crop, grade, or in/out changed since the last analysis."
                     : "Measures every frame so the viewer previews the correction and the curve shows what changes. Render analyzes automatically if needed.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Advanced

    @ViewBuilder
    private var advancedControls: some View {
        Picker("Smoothing", selection: $project.adjustments.deflicker.smoothing) {
            ForEach(DeflickerSmoothing.allCases) { Text($0.displayName).tag($0) }
        }
        .help("Robust ignores one-off frames (a lone sun burst, headlights). Gaussian is smoothest for steady flicker.")
        Picker("Metering", selection: $project.adjustments.deflicker.metering) {
            ForEach(DeflickerMetering.allCases) { Text($0.displayName).tag($0) }
        }
        .help("Region that drives brightness and color. Ignore sky when racing clouds read as flicker.")
        Picker("Regional", selection: $project.adjustments.deflicker.localGrid) {
            ForEach(DeflickerLocalGrid.allCases) { Text($0.displayName).tag($0) }
        }
        .help("Evens out cloud shadows that cover only part of the frame with a smooth gain map.")
        Toggle("Match contrast", isOn: $project.adjustments.deflicker.matchContrast)
            .help("Matches each frame's tonal distribution, so hard-sun frames and flat overcast frames look alike.")
        Toggle("Balance color", isOn: $project.adjustments.deflicker.balanceColor)
            .help("Smooths white-balance shifts between warm sun, blue shade, and auto-WB jumps.")
        Toggle("Use camera exposure (EXIF)", isOn: $project.adjustments.deflicker.useCameraExposure)
            .help("For Manual-mode ramps (Holy Grail): removes shutter / ISO / aperture steps. Leave off for Av or auto-ISO — those cameras write rounded EXIF values.")
        AdjustmentSliderRow(
            title: "Max correction",
            value: $project.adjustments.deflicker.maxCorrectionEV,
            range: 0.25...4,
            resetValue: 2,
            unit: "EV"
        )
    }

    private var advancedSummary: String {
        var parts = [settings.smoothing.displayName]
        if settings.matchContrast { parts.append("contrast") }
        if settings.balanceColor { parts.append("color") }
        if settings.localGrid != .off { parts.append("regional") }
        if settings.useCameraExposure { parts.append("EXIF") }
        return parts.joined(separator: " · ")
    }

    private var deflickerSummary: String {
        settings.enabled
            ? "On — \(DeflickerPreset.matching(settings).displayName)"
            : "Balances brightness, contrast, and color frame to frame"
    }
}

// MARK: - Chart

/// Measured, target, and corrected brightness across the in/out range. Drag to scrub.
struct DeflickerChart: View {
    let solution: DeflickerSolution
    let version: Int
    let rangeStart: Int
    let playhead: Int
    let onScrub: (Int) -> Void

    var body: some View {
        let count = solution.measured.count
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    DeflickerChartPlot(solution: solution, version: version)
                        .equatable()
                    if count > 1, playhead >= rangeStart, playhead < rangeStart + count {
                        Rectangle()
                            .fill(Color.primary.opacity(0.55))
                            .frame(width: 1, height: geo.size.height)
                            .offset(x: CGFloat(playhead - rangeStart) / CGFloat(count - 1) * geo.size.width)
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    guard count > 1 else { return }
                    let t = min(1, max(0, value.location.x / max(1, geo.size.width)))
                    onScrub(rangeStart + Int((t * CGFloat(count - 1)).rounded()))
                })
            }
            .frame(height: 96)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            HStack(spacing: 10) {
                legend("Measured", DeflickerChartPlot.measuredColor)
                legend("Target", DeflickerChartPlot.targetColor)
                legend("Corrected", DeflickerChartPlot.correctedColor)
                Spacer(minLength: 0)
                Text(String(format: "±%.1f EV", DeflickerChartPlot.span(for: solution)))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Deflicker brightness curve")
        .accessibilityValue(String(
            format: "Flicker reduced from %.2f to %.2f stops",
            solution.measuredFlicker,
            solution.correctedFlicker
        ))
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct DeflickerChartPlot: View, Equatable {
    let solution: DeflickerSolution
    let version: Int

    static let measuredColor = Color.orange
    static let targetColor = Color.accentColor
    static let correctedColor = Color.green
    private static let maxPoints = 400

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.version == rhs.version }

    static func span(for solution: DeflickerSolution) -> Double {
        let peak = (solution.measured + solution.target + solution.corrected).map(abs).max() ?? 0
        return max(0.25, peak * 1.1)
    }

    private struct Point: Identifiable {
        let id: Int
        let frame: Int
        let stops: Double
        let series: String
    }

    var body: some View {
        let count = solution.measured.count
        let step = max(1, count / Self.maxPoints)
        let frames = Array(stride(from: 0, to: count, by: step))
        let span = Self.span(for: solution)
        let series: [(String, [Double], Color)] = [
            ("Measured", solution.measured, Self.measuredColor),
            ("Target", solution.target, Self.targetColor),
            ("Corrected", solution.corrected, Self.correctedColor),
        ]
        Chart {
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Color.primary.opacity(0.12))
            ForEach(series, id: \.0) { name, values, color in
                ForEach(frames, id: \.self) { frame in
                    LineMark(
                        x: .value("Frame", frame),
                        y: .value("Stops", values[frame]),
                        series: .value("Series", name)
                    )
                    .foregroundStyle(color.opacity(name == "Measured" ? 0.75 : 1))
                    .lineStyle(StrokeStyle(lineWidth: name == "Target" ? 1.5 : 1, dash: name == "Target" ? [4, 3] : []))
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXScale(domain: 0...max(1, count - 1))
        .chartYScale(domain: -span...span)
    }
}
