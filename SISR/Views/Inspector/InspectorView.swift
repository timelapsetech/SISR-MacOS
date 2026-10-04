import SwiftUI
import SISRKit

struct InspectorView: View {
    @Bindable var project: SequenceProject

    var body: some View {
        Form {
            Section {
                Toggle(isOn: previewOutputFullBinding) {
                    Text("Preview full")
                }
                .help("Fit the cropped output as large as possible in the viewer — what the render will look like.")
                .disabled(!project.hasSequence || project.showOriginal)
            }

            CropSection(project: project)
            TransformSection(project: project)
            ColorSection(project: project)
            DetailSection(project: project)
            DeflickerSection(project: project)
        }
        .formStyle(.grouped)
        .background(.regularMaterial)
    }

    private var previewOutputFullBinding: Binding<Bool> {
        Binding(
            get: { project.previewOutputFull },
            set: { newValue in
                project.previewOutputFull = newValue
                if newValue {
                    project.showOriginal = false
                }
            }
        )
    }
}

// MARK: - Crop & Frame

struct CropSection: View {
    @Bindable var project: SequenceProject
    @AppStorage("sisr.ui.cropAlign") private var showAlign = false
    @AppStorage("sisr.ui.cropFitness") private var showFitness = false

    /// All output sizes, with Native / Scale fit first and Custom last.
    private let sizePresets: [OutputPreset] = [
        .original, .fitWithin,
        .uhd8k, .dci4k, .uhd4k, .p1440, .p1080, .p720, .p480, .p360,
        .ntsc, .pal,
        .instagramStory, .square, .portrait4x5,
        .custom,
    ]

    private let scaleFitPresets: [(label: String, width: Int?, height: Int?)] = [
        ("1920 wide", 1920, nil),
        ("1280 wide", 1280, nil),
        ("3840 wide", 3840, nil),
        ("1920 tall", nil, 1920),
        ("1080×1080", 1080, 1080),
    ]

    var body: some View {
        Section {
            Picker("Aspect", selection: Binding(
                get: { project.crop.aspectLock },
                set: { project.crop.setAspectLock($0, sourceSize: project.orientedSourceSize) }
            )) {
                ForEach(AspectRatioLock.allCases) { lock in
                    Text(lock.displayName).tag(lock)
                }
            }
            .disabled(project.render.preset.locksAspect)

            VStack(alignment: .leading, spacing: 8) {
                Text("Output size")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(sizePresets, id: \.self) { preset in
                            let selected = project.render.preset == preset
                            Button {
                                applySizePreset(preset)
                            } label: {
                                Text(chipLabel(for: preset))
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        selected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06),
                                        in: Capsule(style: .continuous)
                                    )
                                    .overlay {
                                        Capsule(style: .continuous)
                                            .strokeBorder(
                                                selected ? Color.accentColor.opacity(0.55) : Color.clear,
                                                lineWidth: 1
                                            )
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(preset.displayName)
                        }
                    }
                }
            }

            if project.render.preset == .custom {
                HStack(spacing: 8) {
                    TextField("Width", value: $project.render.customSize.width, format: .number)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                    Text("×")
                        .foregroundStyle(.tertiary)
                    TextField("Height", value: $project.render.customSize.height, format: .number)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                }
            }

            if project.render.preset == .fitWithin {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scale to fit limits")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Max width")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            TextField("Optional", text: optionalIntBinding(
                                get: { project.render.maxWidth },
                                set: { project.render.maxWidth = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                        }
                        Text("×")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 18)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Max height")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            TextField("Optional", text: optionalIntBinding(
                                get: { project.render.maxHeight },
                                set: { project.render.maxHeight = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    Text("Set width, height, or both. Aspect stays the same; blank means no limit on that side.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(scaleFitPresets, id: \.label) { item in
                                let selected =
                                    project.render.maxWidth == item.width
                                    && project.render.maxHeight == item.height
                                Button {
                                    project.render.maxWidth = item.width
                                    project.render.maxHeight = item.height
                                    if project.render.preset != .fitWithin {
                                        project.applyScaledFullFrame(
                                            maxWidth: item.width,
                                            maxHeight: item.height
                                        )
                                    } else {
                                        project.resetCropToFullFrame()
                                    }
                                } label: {
                                    Text(item.label)
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            selected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06),
                                            in: Capsule(style: .continuous)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.top, 2)
            }

            if project.render.preset == .original || project.render.preset == .fitWithin {
                Button {
                    project.resetCropToFullFrame()
                } label: {
                    Label("Reset crop to full frame", systemImage: "rectangle.dashed")
                }
                .controlSize(.small)
            }

            LabeledContent("Crop pixels") {
                Text(project.cropPixelSize.label)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Output pixels") {
                Text(project.outputPixelSize.label)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if let current = project.currentOutputResolutionCheck {
                if current.willUpscale {
                    UpscaleWarningBanner(text: current.warningSummary, fitness: current.fitness)
                } else if current.preset.fixedPixelSize != nil {
                    HStack {
                        FitnessBadge(label: current.badgeLabel, fitness: current.fitness)
                        Spacer()
                    }
                }
            }

            DisclosureGroup(isExpanded: $showAlign) {
                AdjustmentSliderRow(
                    title: "Zoom",
                    value: Binding(get: { zoomValue }, set: { setZoom($0) }),
                    range: 1...4,
                    resetValue: 1,
                    format: .number.precision(.fractionLength(2)),
                    unit: "×"
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Align")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        alignButton("Top", systemImage: "rectangle.tophalf.filled", .top)
                        alignButton("Center", systemImage: "rectangle.center.inset.filled", .center)
                        alignButton("Bottom", systemImage: "rectangle.bottomhalf.filled", .bottom)
                    }
                    HStack(spacing: 6) {
                        alignButton("Left", systemImage: "rectangle.lefthalf.filled", .left)
                        alignButton("Right", systemImage: "rectangle.righthalf.filled", .right)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.top, 4)
            } label: {
                DisclosureLabel(title: "Align & zoom", subtitle: showAlign ? nil : "Zoom and edge alignment")
            }

            if !project.resolutionChecks.isEmpty {
                DisclosureGroup(isExpanded: $showFitness) {
                    ForEach(project.resolutionChecks) { check in
                        Button {
                            project.applyPreset(check.preset)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: project.render.preset == check.preset
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(project.render.preset == check.preset
                                                     ? AnyShapeStyle(Color.accentColor)
                                                     : AnyShapeStyle(.tertiary))
                                    .imageScale(.small)
                                Text(check.preset.displayName)
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 4)
                                Text(check.target.label)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                FitnessBadge(label: check.badgeLabel, fitness: check.fitness)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } label: {
                    DisclosureLabel(
                        title: "Resolution fitness",
                        subtitle: showFitness ? nil : "Compare output sizes vs crop"
                    )
                }
            }
        } header: {
            PanelSectionHeader(title: "Crop & Frame", systemImage: "crop")
        }
    }

    private func chipLabel(for preset: OutputPreset) -> String {
        switch preset {
        case .original: return "Native"
        case .fitWithin: return "Scale fit"
        default: return preset.displayName
        }
    }

    private func applySizePreset(_ preset: OutputPreset) {
        switch preset {
        case .original:
            project.applyNativeFullFrameOutput()
        case .fitWithin:
            project.applyScaledFullFrame(
                maxWidth: project.render.maxWidth,
                maxHeight: project.render.maxHeight
            )
        default:
            project.applyPreset(preset)
        }
    }

    private var zoomValue: Double {
        let size = project.orientedSourceSize
        let full = size.width * size.height
        let crop = CGFloat(project.cropPixelSize.width * project.cropPixelSize.height)
        guard crop > 0 else { return 1 }
        return Double(sqrt(full / crop))
    }

    private func setZoom(_ value: Double) {
        var crop = project.crop
        if let lock = project.render.preset.aspectLock {
            crop.aspectLock = lock
        }
        let size = project.orientedSourceSize
        crop.normalizedRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        crop.applyAspectConstraint(sourceSize: size, align: .center)
        crop.zoom(factor: CGFloat(value), sourceSize: size)
        project.crop = crop
    }

    private func alignButton(_ title: String, systemImage: String, _ align: CropAlign) -> some View {
        Button {
            project.crop.align(align, sourceSize: project.orientedSourceSize)
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
    }

    /// Empty field ↔ `nil`; positive integers only.
    private func optionalIntBinding(
        get: @escaping () -> Int?,
        set: @escaping (Int?) -> Void
    ) -> Binding<String> {
        Binding(
            get: {
                guard let value = get(), value > 0 else { return "" }
                return String(value)
            },
            set: { text in
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    set(nil)
                    return
                }
                if let value = Int(trimmed), value > 0 {
                    set(value)
                }
            }
        )
    }
}

// MARK: - Transform

struct TransformSection: View {
    @Bindable var project: SequenceProject
    @AppStorage("sisr.ui.transformMore") private var showMore = false

    private let quarterTurnOptions = [0, 1, 2, 3]

    var body: some View {
        Section {
            AdjustmentSliderRow(
                title: "Straighten",
                value: $project.crop.straightenDegrees,
                range: -45...45,
                resetValue: 0,
                format: .number.precision(.fractionLength(1)),
                unit: "°",
                fieldWidth: 52
            )

            DisclosureGroup(isExpanded: $showMore) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rotate 90°")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(quarterTurnOptions, id: \.self) { turns in
                            let degrees = turns * 90
                            let selected = project.crop.rotationDegrees == degrees
                            Button {
                                applyQuarterTurns(turns)
                            } label: {
                                Text("\(degrees)°")
                                    .font(.caption.weight(.medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                                    .background(
                                        selected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06),
                                        in: Capsule(style: .continuous)
                                    )
                                    .overlay {
                                        Capsule(style: .continuous)
                                            .strokeBorder(
                                                selected ? Color.accentColor.opacity(0.55) : Color.clear,
                                                lineWidth: 1
                                            )
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Rotate \(degrees) degrees")
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    HStack(spacing: 8) {
                        Button {
                            applyQuarterTurns(project.crop.rotationQuarterTurns - 1)
                        } label: {
                            Label("Left 90°", systemImage: "rotate.left")
                                .frame(maxWidth: .infinity)
                        }
                        Button {
                            applyQuarterTurns(project.crop.rotationQuarterTurns + 1)
                        } label: {
                            Label("Right 90°", systemImage: "rotate.right")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                }

                Toggle(isOn: $project.crop.flipHorizontal) {
                    Label("Flip Horizontal", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                }
                Toggle(isOn: $project.crop.flipVertical) {
                    Label("Flip Vertical", systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down")
                }
                Button("Reset Transform") {
                    project.crop.straightenDegrees = 0
                    project.crop.rotationQuarterTurns = 0
                    project.crop.flipHorizontal = false
                    project.crop.flipVertical = false
                }
                .controlSize(.small)
            } label: {
                DisclosureLabel(
                    title: "Rotate & flips",
                    subtitle: showMore ? nil : moreSummary
                )
            }
        } header: {
            PanelSectionHeader(title: "Transform", systemImage: "rotate.right")
        }
        .onAppear {
            if project.crop.flipHorizontal
                || project.crop.flipVertical
                || project.crop.rotationQuarterTurns != 0
            {
                showMore = true
            }
        }
    }

    private var moreSummary: String {
        var parts: [String] = []
        if project.crop.rotationQuarterTurns != 0 {
            parts.append("\(project.crop.rotationDegrees)°")
        }
        if project.crop.flipHorizontal { parts.append("H") }
        if project.crop.flipVertical { parts.append("V") }
        return parts.isEmpty ? "90° rotate, mirror, reset" : "Active: \(parts.joined(separator: " · "))"
    }

    /// Rotate in 90° steps, then re-fit a locked crop to the oriented frame.
    private func applyQuarterTurns(_ turns: Int) {
        project.crop.setQuarterTurns(turns)
        let size = project.orientedSourceSize
        guard GeometryUtil.isValidSize(size), project.crop.aspectLock != .free else { return }
        project.crop.applyAspectConstraint(sourceSize: size, align: .center, preferLargest: true)
    }
}

// MARK: - Color

struct ColorSection: View {
    @Bindable var project: SequenceProject
    @AppStorage("sisr.ui.colorControls") private var showColor = false

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $showColor) {
                AdjustmentSliderRow(title: "Exposure", value: $project.adjustments.color.exposure, range: -2...2)
                AdjustmentSliderRow(title: "Contrast", value: $project.adjustments.color.contrast, range: -1...1)
                AdjustmentSliderRow(title: "Highlights", value: $project.adjustments.color.highlights, range: -1...1)
                AdjustmentSliderRow(title: "Shadows", value: $project.adjustments.color.shadows, range: -1...1)
                AdjustmentSliderRow(title: "Saturation", value: $project.adjustments.color.saturation, range: -1...1)
                AdjustmentSliderRow(title: "Vibrance", value: $project.adjustments.color.vibrance, range: -1...1)
                AdjustmentSliderRow(title: "Temperature", value: $project.adjustments.color.temperature, range: -1...1)
                AdjustmentSliderRow(title: "Tint", value: $project.adjustments.color.tint, range: -1...1)

                HStack(spacing: 8) {
                    Button("Auto") {
                        project.adjustments.color.shadows = 0.15
                        project.adjustments.color.contrast = 0.08
                        project.adjustments.color.vibrance = 0.1
                        showColor = true
                    }
                    .controlSize(.small)
                    Spacer()
                    Button("Reset", role: .destructive) {
                        project.adjustments.color = .identity
                    }
                    .controlSize(.small)
                }
            } label: {
                DisclosureLabel(
                    title: "Color",
                    subtitle: showColor ? nil : colorSummary
                )
            }
        }
        .onAppear {
            if !project.adjustments.color.isIdentity { showColor = true }
        }
        .onChange(of: project.adjustments.color) { _, color in
            if !color.isIdentity { showColor = true }
        }
    }

    private var colorSummary: String {
        project.adjustments.color.isIdentity
            ? "Exposure, contrast, white balance…"
            : "Adjustments active"
    }
}

// MARK: - Detail

struct DetailSection: View {
    @Bindable var project: SequenceProject
    @AppStorage("sisr.ui.detail") private var showDetail = false

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $showDetail) {
                AdjustmentSliderRow(
                    title: "Sharpen",
                    value: $project.adjustments.detail.sharpen,
                    range: 0...1,
                    resetValue: 0
                )
                AdjustmentSliderRow(
                    title: "Noise Reduction",
                    value: $project.adjustments.detail.noiseReduction,
                    range: 0...1,
                    resetValue: 0
                )
                AdjustmentSliderRow(
                    title: "Vignette",
                    value: $project.adjustments.detail.vignette,
                    range: 0...1,
                    resetValue: 0
                )
                Button("Reset Detail") {
                    project.adjustments.detail = .identity
                }
                .controlSize(.small)
            } label: {
                DisclosureLabel(
                    title: "Detail",
                    subtitle: showDetail ? nil : detailSummary
                )
            }
        }
        .onAppear {
            if !project.adjustments.detail.isIdentity { showDetail = true }
        }
        .onChange(of: project.adjustments.detail) { _, detail in
            if !detail.isIdentity { showDetail = true }
        }
    }

    private var detailSummary: String {
        project.adjustments.detail.isIdentity
            ? "Sharpen, noise reduction, vignette"
            : "Adjustments active"
    }
}

// MARK: - Deflicker

struct DeflickerSection: View {
    @Bindable var project: SequenceProject
    @AppStorage("sisr.ui.deflicker") private var showDeflicker = false

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $showDeflicker) {
                Toggle(isOn: $project.adjustments.deflicker.enabled) {
                    Label("Enabled", systemImage: "sun.max.trianglebadge.exclamationmark")
                }
                if project.adjustments.deflicker.enabled {
                    HStack {
                        Text("Window")
                        Spacer()
                        TextField(
                            "",
                            value: Binding(
                                get: { Double(project.adjustments.deflicker.windowSize) },
                                set: {
                                    let odd = Int($0.rounded())
                                    project.adjustments.deflicker.windowSize = max(3, odd | 1)
                                }
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
                            in: 3...61,
                            step: 2
                        )
                        .labelsHidden()
                    }
                    AdjustmentSliderRow(
                        title: "Strength",
                        value: $project.adjustments.deflicker.strength,
                        range: 0...1,
                        resetValue: 0.75
                    )
                }
            } label: {
                DisclosureLabel(
                    title: "Deflicker",
                    subtitle: showDeflicker ? nil : deflickerSummary
                )
            }
        }
        .onAppear {
            if project.adjustments.deflicker.enabled { showDeflicker = true }
        }
        .onChange(of: project.adjustments.deflicker.enabled) { _, enabled in
            if enabled { showDeflicker = true }
        }
    }

    private var deflickerSummary: String {
        project.adjustments.deflicker.enabled
            ? "On — smooths brightness before encoding"
            : "Smooths brightness across the in/out range"
    }
}

struct UpscaleWarningBanner: View {
    let text: String
    let fitness: ResolutionFitness

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: fitness == .tooSmall
                  ? "exclamationmark.triangle.fill"
                  : "arrow.up.left.and.arrow.down.right")
                .foregroundStyle(color)
                .symbolRenderingMode(.hierarchical)
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.controlCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.controlCorner, style: .continuous)
                .strokeBorder(color.opacity(0.28), lineWidth: 1)
        }
        .accessibilityLabel(text)
    }

    private var color: Color {
        switch fitness {
        case .native: return Theme.badgeNative
        case .upscaled: return Theme.badgeUpscaled
        case .tooSmall: return Theme.badgeTooSmall
        }
    }
}
