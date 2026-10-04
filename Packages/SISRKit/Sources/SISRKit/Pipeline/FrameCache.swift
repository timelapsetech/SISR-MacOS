import AppKit
import Foundation
import ImageIO

public final class FrameCache: @unchecked Sendable {
    private let cache = NSCache<NSString, NSImage>()
    /// All ImageIO work runs here at user-initiated QoS so UI never waits on a Utility thread.
    private let decodeQueue = DispatchQueue(
        label: "com.sisr.framecache.decode",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private var prefetchTask: Task<Void, Never>?
    /// Inclusive range still being filled by the active prefetch task.
    private var prefetchCoverage: (start: Int, endExclusive: Int, maxPixel: Int)?
    /// When true, skip new decodes/prefetch so render can claim ImageIO / IOSurface budget.
    public var isPaused = false

    public init(countLimit: Int = 64) {
        cache.countLimit = countLimit
    }

    public func clear() {
        cache.removeAllObjects()
        prefetchTask?.cancel()
        prefetchTask = nil
        prefetchCoverage = nil
    }

    public func pauseForRender() {
        isPaused = true
        prefetchTask?.cancel()
        prefetchTask = nil
        prefetchCoverage = nil
        cache.removeAllObjects()
    }

    public func resumeAfterRender() {
        isPaused = false
    }

    /// Non-blocking cache lookup for synchronous view bodies.
    public func cachedThumbnail(for url: URL, maxPixelSize: CGFloat) -> NSImage? {
        cache.object(forKey: cacheKey(url: url, size: maxPixelSize) as NSString)
    }

    /// Decode (or return cached) thumbnail off the main thread.
    public func thumbnail(for url: URL, maxPixelSize: CGFloat) async -> NSImage? {
        let key = cacheKey(url: url, size: maxPixelSize)
        if let hit = cache.object(forKey: key as NSString) {
            return hit
        }
        if isPaused { return nil }

        return await withCheckedContinuation { continuation in
            decodeQueue.async {
                if self.isPaused {
                    continuation.resume(returning: nil)
                    return
                }
                if let hit = self.cache.object(forKey: key as NSString) {
                    continuation.resume(returning: hit)
                    return
                }
                let image = self.decodeThumbnail(url: url, maxPixelSize: maxPixelSize)
                if let image {
                    self.cache.setObject(image, forKey: key as NSString)
                }
                continuation.resume(returning: image)
            }
        }
    }

    /// Prefetch thumbnails around `index`. Use asymmetric windows while playing (more ahead).
    public func prefetch(
        urls: [URL],
        around index: Int,
        window: Int,
        maxPixelSize: CGFloat
    ) {
        prefetch(
            urls: urls,
            around: index,
            behind: window,
            ahead: window,
            maxPixelSize: maxPixelSize
        )
    }

    public func prefetch(
        urls: [URL],
        around index: Int,
        behind: Int,
        ahead: Int,
        maxPixelSize: CGFloat
    ) {
        guard !isPaused, !urls.isEmpty else { return }
        let start = max(0, index - max(0, behind))
        let end = min(urls.count, index + max(0, ahead) + 1)
        guard start < end else { return }

        let pixelKey = Int(maxPixelSize)
        // Keep an existing ahead-decode running when the playhead only nudged forward.
        if let coverage = prefetchCoverage,
           let task = prefetchTask,
           !task.isCancelled,
           coverage.maxPixel == pixelKey,
           index >= coverage.start,
           index + 10 < coverage.endExclusive
        {
            return
        }

        prefetchTask?.cancel()
        prefetchCoverage = (start, end, pixelKey)

        // Decode playhead first, then forward frames, then behind — better hit rate while playing.
        var ordered: [URL] = []
        if urls.indices.contains(index) {
            ordered.append(urls[index])
        }
        if index + 1 < end {
            ordered.append(contentsOf: urls[(index + 1)..<end])
        }
        if start < index {
            ordered.append(contentsOf: urls[start..<index].reversed())
        }

        prefetchTask = Task(priority: .userInitiated) { [weak self] in
            guard let self, !self.isPaused else { return }
            await withTaskGroup(of: Void.self) { group in
                var inFlight = 0
                let maxInFlight = 6
                for url in ordered {
                    if Task.isCancelled || self.isPaused { break }
                    group.addTask {
                        if Task.isCancelled || self.isPaused { return }
                        _ = await self.thumbnail(for: url, maxPixelSize: maxPixelSize)
                    }
                    inFlight += 1
                    if inFlight >= maxInFlight {
                        _ = await group.next()
                        inFlight -= 1
                    }
                }
            }
        }
    }

    private func cacheKey(url: URL, size: CGFloat) -> String {
        "\(url.path)#\(Int(size))"
    }

    private func decodeThumbnail(url: URL, maxPixelSize: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, Int(maxPixelSize)),
            kCGImageSourceCreateThumbnailWithTransform: true,
            // Avoid the shared ImageIO cache lock path that amplified QoS inversions.
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
