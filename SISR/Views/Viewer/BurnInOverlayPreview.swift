import SwiftUI
import SISRKit

/// Live burn-in badge drawn inside the crop rect (matches encode placement).
struct BurnInOverlayPreview: View {
    @Bindable var project: SequenceProject
    let cropRect: CGRect

    var body: some View {
        let overlay = project.render.overlay
        Group {
            if overlay != .none, cropRect.width > 8, cropRect.height > 8 {
                let text = project.previewOverlayText(at: project.playheadIndex)
                let box = OverlayRenderer.topLeftBoxRect(
                    overlay: overlay,
                    text: text,
                    canvasSize: cropRect.size
                )
                let fontSize = OverlayRenderer.layoutMetrics(
                    overlay: overlay,
                    text: text,
                    canvasWidth: max(1, Int(cropRect.width.rounded())),
                    canvasHeight: max(1, Int(cropRect.height.rounded()))
                ).fontSize
                let opacity = RenderSettings.clampOpacity(project.render.overlayBackgroundOpacity)

                Text(text)
                    .font(.system(size: max(8, fontSize), design: .monospaced).weight(.regular))
                    .foregroundStyle(.white)
                    .padding(max(2, fontSize * 0.25))
                    .background(Color.black.opacity(opacity))
                    .position(
                        x: cropRect.minX + box.midX,
                        y: cropRect.minY + box.midY
                    )
                    .allowsHitTesting(false)
                    .accessibilityLabel("Burn-in preview")
                    .accessibilityValue(text)
            }
        }
    }
}
