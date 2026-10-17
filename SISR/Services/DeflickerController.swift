import Foundation
import Observation
import SISRKit

/// Owns the measured deflicker stats for the open sequence and the solved corrections
/// for the current settings / in-out range, so the viewer and chart update instantly.
@Observable
@MainActor
final class DeflickerController {
    private(set) var analysis: DeflickerAnalysis?
    private(set) var isAnalyzing = false
    private(set) var progressDone = 0
    private(set) var progressTotal = 0
    /// Corrections for `solutionRange`; nil until analyzed or when the analysis is stale.
    private(set) var solution: DeflickerSolution?
    private(set) var solutionRange: TimelineRange?
    /// Bumps whenever `solution` changes (cheap equality for views).
    private(set) var solutionVersion = 0

    private var analyzeTask: Task<Void, Never>?
    private var solveTask: Task<Void, Never>?
    private var solvedInputs: SolveInputs?

    private struct SolveInputs: Equatable {
        var settings: DeflickerSettings
        var range: TimelineRange
        var key: DeflickerAnalysisKey
    }

    var progressFraction: Double {
        progressTotal > 0 ? Double(progressDone) / Double(progressTotal) : 0
    }

    /// True when stats exist but no longer match the crop / grade / range.
    func isStale(for project: SequenceProject) -> Bool {
        guard let analysis else { return false }
        guard let (key, range) = Self.keyAndRange(project) else { return true }
        return analysis.stats(for: range, key: key) == nil
    }

    func correction(at sequenceIndex: Int) -> DeflickerCorrection? {
        guard let solution, let range = solutionRange,
              sequenceIndex >= range.inIndex, sequenceIndex <= range.outIndex
        else { return nil }
        let i = sequenceIndex - range.inIndex
        return solution.corrections.indices.contains(i) ? solution.corrections[i] : nil
    }

    func analyze(project: SequenceProject) {
        guard let sequence = project.sequence, let (key, range) = Self.keyAndRange(project) else { return }
        cancelAnalysis()
        let snapshot = SequenceProjectSnapshot(from: project)
        let urls = sequence.frames[range.inIndex...range.outIndex].map(\.url)
        isAnalyzing = true
        progressDone = 0
        progressTotal = urls.count

        let report: @Sendable (Int, Int) -> Void = { [weak self] done, total in
            Task { @MainActor in
                guard let self, self.isAnalyzing else { return }
                self.progressDone = done
                self.progressTotal = total
            }
        }
        analyzeTask = Task { [weak self] in
            do {
                let stats = try await DeflickerAnalyzer().analyze(
                    urls: urls,
                    crop: snapshot.crop,
                    adjustments: snapshot.adjustments,
                    outputSize: snapshot.outputSize,
                    progress: report,
                    isCancelled: { Task.isCancelled }
                )
                guard let self, !Task.isCancelled else { return }
                self.analysis = DeflickerAnalysis(key: key, startIndex: range.inIndex, stats: stats)
                self.isAnalyzing = false
                self.refresh(project: project)
            } catch {
                self?.isAnalyzing = false
            }
        }
    }

    func cancelAnalysis() {
        analyzeTask?.cancel()
        analyzeTask = nil
        isAnalyzing = false
    }

    /// Drop everything (sequence closed or a new one opened).
    func reset() {
        cancelAnalysis()
        solveTask?.cancel()
        analysis = nil
        solvedInputs = nil
        setSolution(nil, range: nil)
    }

    /// Re-solve after settings, range, crop, or grade changes. Solving runs off the main actor.
    func refresh(project: SequenceProject) {
        let settings = project.adjustments.deflicker
        guard settings.enabled,
              let analysis,
              let (key, range) = Self.keyAndRange(project),
              let stats = analysis.stats(for: range, key: key)
        else {
            solveTask?.cancel()
            solvedInputs = nil
            setSolution(nil, range: nil)
            return
        }
        let inputs = SolveInputs(settings: settings, range: range, key: key)
        guard inputs != solvedInputs else { return }
        solvedInputs = inputs
        solveTask?.cancel()
        let reference = settings.referenceFrame.map { $0 - range.inIndex }
        solveTask = Task { [weak self] in
            let solved = await Task.detached(priority: .userInitiated) {
                DeflickerSolver.solve(stats: stats, settings: settings, referenceIndex: reference)
            }.value
            guard let self, !Task.isCancelled, self.solvedInputs == inputs else { return }
            self.setSolution(solved, range: range)
        }
    }

    private func setSolution(_ solved: DeflickerSolution?, range: TimelineRange?) {
        guard solved != nil || solution != nil else { return }
        solution = solved
        solutionRange = range
        solutionVersion &+= 1
    }

    private static func keyAndRange(_ project: SequenceProject) -> (DeflickerAnalysisKey, TimelineRange)? {
        let snapshot = SequenceProjectSnapshot(from: project)
        guard let sequence = snapshot.sequence, let key = DeflickerAnalysisKey(project: snapshot) else {
            return nil
        }
        return (key, snapshot.timeline.clamped(to: sequence.frameCount))
    }
}
