import AppKit
import SwiftUI
import SISRKit

enum AppAppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Always Light"
        case .dark: return "Always Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum Theme {
    /// Near-black canvas so grading reads accurately in both appearances.
    static let viewerCanvas = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(calibratedWhite: 0.043, alpha: 1) // ~#0B0B0C
        }
        return NSColor(calibratedWhite: 0.12, alpha: 1)
    })

    static let filmstripTrack = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(calibratedWhite: 0.07, alpha: 1)
        }
        return NSColor(calibratedWhite: 0.16, alpha: 1)
    })

    /// Dim the out-of-crop region while keeping the full frame readable.
    static let cropVeil = Color.black.opacity(0.55)
    static let cropGuide = Color.white.opacity(0.85)
    static let hairline = Color(nsColor: .separatorColor)

    static let badgeNative = Color.green
    static let badgeUpscaled = Color.orange
    static let badgeTooSmall = Color.red

    static let panelCorner: CGFloat = 12
    static let controlCorner: CGFloat = 8
}

// MARK: - Shared chrome

struct PanelSectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            .symbolRenderingMode(.hierarchical)
    }
}

struct MetricPill: View {
    let text: String
    var tone: Color = .secondary

    var body: some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced).weight(.medium))
            .foregroundStyle(tone)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tone.opacity(0.12), in: Capsule(style: .continuous))
    }
}

struct FitnessBadge: View {
    let label: String
    let fitness: ResolutionFitness

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule(style: .continuous))
            .foregroundStyle(color)
    }

    private var color: Color {
        switch fitness {
        case .native: return Theme.badgeNative
        case .upscaled: return Theme.badgeUpscaled
        case .tooSmall: return Theme.badgeTooSmall
        }
    }
}

struct SoftDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.hairline.opacity(0.7))
            .frame(height: 1)
    }
}

struct AdjustmentSliderRow: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var resetValue: Double = 0
    var format: FloatingPointFormatStyle<Double> = .number.precision(.fractionLength(2))
    /// Optional unit shown after the numeric field (e.g. "°").
    var unit: String? = nil
    var fieldWidth: CGFloat = 56
    /// When false, typed values may leave `range`; the slider still stays within it.
    var clampInput: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.callout)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    TextField(
                        "",
                        value: fieldBinding,
                        format: format
                    )
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: fieldWidth)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if clampInput {
                            value = clamped(value)
                        } else if !value.isFinite {
                            value = resetValue
                        }
                    }
                    if let unit {
                        Text(unit)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Slider(value: sliderBinding, in: range)
                .controlSize(.small)
                .onTapGesture(count: 2) { value = resetValue }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var fieldBinding: Binding<Double> {
        Binding(
            get: { value },
            set: { next in
                guard next.isFinite else {
                    value = resetValue
                    return
                }
                value = clampInput ? clamped(next) : next
            }
        )
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: { clamped(value) },
            set: { value = $0 }
        )
    }

    private func clamped(_ v: Double) -> Double {
        guard v.isFinite else { return resetValue }
        return min(max(v, range.lowerBound), range.upperBound)
    }
}

struct DisclosureLabel: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.subheadline.weight(.medium))
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct PathBrowserRow: View {
    let path: String?
    let placeholder: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
                .imageScale(.medium)
            VStack(alignment: .leading, spacing: 2) {
                Text(folderTitle)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if let path, !path.isEmpty {
                    Text(path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            Button("Browse…", action: action)
                .controlSize(.small)
        }
    }

    private var folderTitle: String {
        guard let path, !path.isEmpty else { return placeholder }
        return URL(fileURLWithPath: path).lastPathComponent
    }
}

struct EmptyPanelHint: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}
