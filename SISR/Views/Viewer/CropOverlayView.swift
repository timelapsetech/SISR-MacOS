import SwiftUI
import SISRKit

struct CropOverlayView: View {
    @Bindable var project: SequenceProject

    @State private var moveStart: CGRect?
    @State private var drawStart: CGPoint?
    @State private var draftRect: CGRect?
    @State private var activeHandle: CropState.Handle?

    var body: some View {
        GeometryReader { geo in
            let fitted = Self.fittedImageRect(sourceSize: project.orientedSourceSize, in: geo.size)
            let crop = displayedCropRect(fitted: fitted)

            ZStack {
                // Capture drags on the full frame to draw a new crop box.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(drawGesture(fitted: fitted))

                // Dim outside the crop — full frame stays visible underneath.
                Path { path in
                    path.addRect(fitted)
                    path.addRect(crop)
                }
                .fill(Theme.cropVeil, style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
                .frame(width: geo.size.width, height: geo.size.height)

                // Rule-of-thirds guides
                Path { path in
                    let thirdW = crop.width / 3
                    let thirdH = crop.height / 3
                    for i in 1...2 {
                        path.move(to: CGPoint(x: crop.minX + thirdW * CGFloat(i), y: crop.minY))
                        path.addLine(to: CGPoint(x: crop.minX + thirdW * CGFloat(i), y: crop.maxY))
                        path.move(to: CGPoint(x: crop.minX, y: crop.minY + thirdH * CGFloat(i)))
                        path.addLine(to: CGPoint(x: crop.maxX, y: crop.minY + thirdH * CGFloat(i)))
                    }
                }
                .stroke(Theme.cropGuide.opacity(0.35), lineWidth: 0.5)
                .allowsHitTesting(false)

                // Crop border + move
                Rectangle()
                    .stroke(Theme.cropGuide, lineWidth: 1.5)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                    .frame(width: max(1, crop.width), height: max(1, crop.height))
                    .position(x: crop.midX, y: crop.midY)
                    .contentShape(Rectangle())
                    .gesture(moveGesture(fitted: fitted))

                // Resize handles
                ForEach(CropState.Handle.allCases, id: \.rawValue) { handle in
                    handleView(handle, crop: crop, fitted: fitted)
                }

                // Live draft while drawing a new box
                if let draftRect {
                    Rectangle()
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .frame(width: draftRect.width, height: draftRect.height)
                        .position(x: draftRect.midX, y: draftRect.midY)
                        .allowsHitTesting(false)
                }

                // Burn-in placement preview (date / frame) inside the crop.
                if project.render.overlay != .none {
                    BurnInOverlayPreview(project: project, cropRect: crop)
                }
            }
        }
        .allowsHitTesting(project.hasSequence && !project.showOriginal)
    }

    // MARK: - Gestures

    private func moveGesture(fitted: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard activeHandle == nil, drawStart == nil else { return }
                if moveStart == nil {
                    moveStart = project.crop.normalizedRect
                }
                guard let start = moveStart, fitted.width > 0, fitted.height > 0 else { return }
                let dx = value.translation.width / fitted.width
                let dy = value.translation.height / fitted.height
                var r = start
                r.origin.x = GeometryUtil.clamp(start.origin.x + dx, min: 0, max: 1 - start.width)
                r.origin.y = GeometryUtil.clamp(start.origin.y + dy, min: 0, max: 1 - start.height)
                project.crop.normalizedRect = r
            }
            .onEnded { _ in moveStart = nil }
    }

    private func drawGesture(fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard activeHandle == nil, moveStart == nil else { return }
                if drawStart == nil {
                    // Only start a new box when the press is outside the current crop.
                    let current = cropRect(in: fitted)
                    if current.insetBy(dx: -4, dy: -4).contains(value.startLocation) {
                        return
                    }
                    drawStart = value.startLocation
                }
                guard let start = drawStart else { return }
                let end = value.location
                draftRect = CGRect(
                    x: min(start.x, end.x),
                    y: min(start.y, end.y),
                    width: abs(end.x - start.x),
                    height: abs(end.y - start.y)
                ).intersection(fitted)
            }
            .onEnded { _ in
                defer {
                    drawStart = nil
                    draftRect = nil
                }
                guard let draft = draftRect, draft.width > 8, draft.height > 8, fitted.width > 0 else { return }
                let source = project.orientedSourceSize
                let pixel = CGRect(
                    x: (draft.minX - fitted.minX) / fitted.width * source.width,
                    y: (draft.minY - fitted.minY) / fitted.height * source.height,
                    width: draft.width / fitted.width * source.width,
                    height: draft.height / fitted.height * source.height
                )
                project.crop.setPixelRect(pixel, sourceSize: source, constrainAspect: true)
            }
    }

    private func handleView(_ handle: CropState.Handle, crop: CGRect, fitted: CGRect) -> some View {
        let point = handlePoint(handle, in: crop)
        let isCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight].contains(handle)
        return Capsule()
            .fill(Color.white)
            .frame(width: isCorner ? 12 : 22, height: isCorner ? 12 : 6)
            .rotationEffect(handle == .left || handle == .right ? .degrees(90) : .degrees(0))
            .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
            .position(point)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        activeHandle = handle
                        moveStart = nil
                        drawStart = nil
                        let sourcePoint = viewToSource(value.location, fitted: fitted)
                        project.crop.resize(
                            handle: handle,
                            toPoint: sourcePoint,
                            sourceSize: project.orientedSourceSize
                        )
                    }
                    .onEnded { _ in activeHandle = nil }
            )
    }

    // MARK: - Geometry

    private func displayedCropRect(fitted: CGRect) -> CGRect {
        if let draftRect { return draftRect }
        return cropRect(in: fitted)
    }

    private func cropRect(in fitted: CGRect) -> CGRect {
        let n = project.crop.normalizedRect
        return CGRect(
            x: fitted.minX + n.origin.x * fitted.width,
            y: fitted.minY + n.origin.y * fitted.height,
            width: n.width * fitted.width,
            height: n.height * fitted.height
        )
    }

    private func viewToSource(_ point: CGPoint, fitted: CGRect) -> CGPoint {
        guard fitted.width > 0, fitted.height > 0 else { return .zero }
        let source = project.orientedSourceSize
        return CGPoint(
            x: (point.x - fitted.minX) / fitted.width * source.width,
            y: (point.y - fitted.minY) / fitted.height * source.height
        )
    }

    private func handlePoint(_ handle: CropState.Handle, in crop: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: crop.minX, y: crop.minY)
        case .topRight: return CGPoint(x: crop.maxX, y: crop.minY)
        case .bottomLeft: return CGPoint(x: crop.minX, y: crop.maxY)
        case .bottomRight: return CGPoint(x: crop.maxX, y: crop.maxY)
        case .top: return CGPoint(x: crop.midX, y: crop.minY)
        case .bottom: return CGPoint(x: crop.midX, y: crop.maxY)
        case .left: return CGPoint(x: crop.minX, y: crop.midY)
        case .right: return CGPoint(x: crop.maxX, y: crop.midY)
        }
    }

    static func fittedImageRect(sourceSize: CGSize, in size: CGSize) -> CGRect {
        guard sourceSize.width > 0, sourceSize.height > 0, size.width > 0, size.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        let aspect = sourceSize.width / sourceSize.height
        let viewAspect = size.width / size.height
        if viewAspect > aspect {
            let h = size.height
            let w = h * aspect
            return CGRect(x: (size.width - w) / 2, y: 0, width: w, height: h)
        } else {
            let w = size.width
            let h = w / aspect
            return CGRect(x: 0, y: (size.height - h) / 2, width: w, height: h)
        }
    }
}
