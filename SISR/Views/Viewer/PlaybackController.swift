import Foundation
import Observation
import SISRKit

enum ViewerZoomMode: String {
    case fit
    case actual
    case double
}

@Observable
@MainActor
final class PlaybackController {
    var isPlaying = false
    /// True when the active play pass is limited to In→Out.
    var isPlayingInOut = false
    var zoomMode: ViewerZoomMode = .fit
    var shuttleRate: Int = 0 // -2…2 via J/K/L

    private var timer: Timer?

    func toggle(project: SequenceProject) {
        if isPlaying {
            stop()
        } else {
            play(project: project)
        }
    }

    /// Play the whole sequence from the current playhead (ignores In/Out).
    func play(project: SequenceProject) {
        let last = max(0, project.frameCount - 1)
        // At the last frame, wrap to the start of the sequence.
        if project.playheadIndex >= last {
            project.playheadIndex = 0
        }
        startPlayback(project: project, stopAt: last, playingInOut: false)
    }

    func toggleInOut(project: SequenceProject) {
        if isPlaying, isPlayingInOut {
            stop()
        } else {
            playInOut(project: project)
        }
    }

    /// Play only the In→Out range. Starts from the playhead when inside the range;
    /// otherwise (or when sitting on Out) jumps to In.
    func playInOut(project: SequenceProject) {
        let range = project.timeline.clamped(to: project.frameCount)
        if project.playheadIndex < range.inIndex || project.playheadIndex >= range.outIndex {
            project.playheadIndex = range.inIndex
        }
        startPlayback(project: project, stopAt: range.outIndex, playingInOut: true)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isPlaying = false
        isPlayingInOut = false
        shuttleRate = 0
    }

    func step(project: SequenceProject, delta: Int) {
        stop()
        let last = max(0, project.frameCount - 1)
        project.playheadIndex = min(last, max(0, project.playheadIndex + delta))
    }

    func goToStart(project: SequenceProject) {
        stop()
        project.playheadIndex = 0
    }

    func goToEnd(project: SequenceProject) {
        stop()
        project.playheadIndex = max(0, project.frameCount - 1)
    }

    func goToIn(project: SequenceProject) {
        stop()
        let range = project.timeline.clamped(to: project.frameCount)
        project.playheadIndex = range.inIndex
    }

    func goToOut(project: SequenceProject) {
        stop()
        let range = project.timeline.clamped(to: project.frameCount)
        project.playheadIndex = range.outIndex
    }

    func shuttle(project: SequenceProject, direction: Int) {
        // J = -1, K = stop, L = +1
        if direction == 0 {
            stop()
            return
        }
        shuttleRate = max(-2, min(2, shuttleRate + direction))
        if shuttleRate == 0 {
            stop()
            return
        }
        let rate = shuttleRate
        stopTimerKeepingPlayingFlag()
        isPlaying = true
        isPlayingInOut = false
        let baseFPS = max(0.01, project.render.fps)
        let interval = 1.0 / (baseFPS * Double(abs(rate)))
        startTimer(interval: interval) { [weak self] in
            guard let self else { return }
            let delta = rate > 0 ? 1 : -1
            let last = max(0, project.frameCount - 1)
            let next = project.playheadIndex + delta
            if next < 0 || next > last {
                self.stop()
                return
            }
            project.playheadIndex = next
        }
    }

    private func startPlayback(project: SequenceProject, stopAt: Int, playingInOut: Bool) {
        stopTimerKeepingPlayingFlag()
        isPlaying = true
        isPlayingInOut = playingInOut
        let fps = max(0.01, project.render.fps)
        startTimer(interval: 1.0 / fps) { [weak self] in
            guard let self else { return }
            if project.playheadIndex >= stopAt {
                self.stop()
                return
            }
            project.playheadIndex = min(stopAt, project.playheadIndex + 1)
        }
    }

    /// Invalidate timer without clearing `isPlaying` (used when restarting play/shuttle).
    private func stopTimerKeepingPlayingFlag() {
        timer?.invalidate()
        timer = nil
    }

    private func startTimer(interval: TimeInterval, fire: @escaping @MainActor () -> Void) {
        // Fire on the main run loop directly — avoid Task hops that bunch frames.
        let t = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated {
                fire()
            }
        }
        // Keep ticking during scroll tracking / modal run-loop modes.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
