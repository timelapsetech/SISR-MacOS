import AVFoundation
import CoreImage
import Foundation

public final class VideoWriter {
    private(set) var outputURL: URL
    private let size: PixelSize
    private let fps: Double
    private let codec: OutputCodec
    private let encode: VideoEncodeSettings
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var frameIndex: Int = 0

    public init(
        outputURL: URL,
        size: PixelSize,
        fps: Double,
        codec: OutputCodec,
        encode: VideoEncodeSettings = .automatic
    ) {
        self.outputURL = outputURL
        self.size = size
        self.fps = fps
        self.codec = codec
        self.encode = encode
    }

    public func start() throws {
        // May rewrite outputURL to a unique sibling if the original can't be removed.
        outputURL = try OutputFile.prepareWritableURL(outputURL)

        let fileType: AVFileType = (codec == .prores || codec == .proresHQ) ? .mov : .mp4
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: fileType)

        let videoSettings = try makeVideoSettings()
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false

        // Prefer CPU-backed pool buffers — IOSurface pools compete with JPEG decode
        // and were exhausting under 4K renders (IOSurface creation failed: e00002c2).
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: attrs
        )

        guard writer.canAdd(input) else {
            throw RenderError.writerFailed("Cannot add video input to writer.")
        }
        writer.add(input)

        guard writer.startWriting() else {
            throw RenderError.writerFailed(writer.error?.localizedDescription ?? "startWriting failed")
        }
        writer.startSession(atSourceTime: .zero)

        self.writer = writer
        self.input = input
        self.adaptor = adaptor
        self.frameIndex = 0
    }

    /// Render a CIImage straight into a pooled pixel buffer (avoids a full-size CGImage copy).
    public func append(ciImage: CIImage, context: CIContext) throws {
        guard let input, let adaptor, let writer else {
            throw RenderError.writerFailed("Writer not started.")
        }
        if writer.status == .failed {
            throw RenderError.writerFailed(writer.error?.localizedDescription ?? "Writer failed")
        }

        while !input.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.002)
        }

        guard let pool = adaptor.pixelBufferPool else {
            throw RenderError.writerFailed("Missing pixel buffer pool.")
        }
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard status == kCVReturnSuccess, let pixelBuffer = buffer else {
            throw RenderError.writerFailed("Could not create pixel buffer.")
        }

        let bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        context.render(
            ciImage,
            to: pixelBuffer,
            bounds: bounds,
            colorSpace: colorSpace
        )

        let presentation = presentationTime(for: frameIndex)
        if !adaptor.append(pixelBuffer, withPresentationTime: presentation) {
            throw RenderError.writerFailed(writer.error?.localizedDescription ?? "append failed")
        }
        frameIndex += 1
    }

    public func append(cgImage: CGImage) throws {
        guard let input, let adaptor, let writer else {
            throw RenderError.writerFailed("Writer not started.")
        }
        if writer.status == .failed {
            throw RenderError.writerFailed(writer.error?.localizedDescription ?? "Writer failed")
        }

        while !input.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.002)
        }

        guard let pool = adaptor.pixelBufferPool else {
            throw RenderError.writerFailed("Missing pixel buffer pool.")
        }
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard status == kCVReturnSuccess, let pixelBuffer = buffer else {
            throw RenderError.writerFailed("Could not create pixel buffer.")
        }

        try copy(cgImage: cgImage, to: pixelBuffer)

        let presentation = presentationTime(for: frameIndex)
        if !adaptor.append(pixelBuffer, withPresentationTime: presentation) {
            throw RenderError.writerFailed(writer.error?.localizedDescription ?? "append failed")
        }
        frameIndex += 1
    }

    public func finish() async throws {
        guard let input, let writer else { return }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            throw RenderError.writerFailed(writer.error?.localizedDescription ?? "finishWriting failed")
        }
    }

    public func cancel() {
        writer?.cancelWriting()
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
    }

    private func presentationTime(for index: Int) -> CMTime {
        let timescale: CMTimeScale
        if abs(fps - 29.97) < 0.01 {
            timescale = 30000
        } else if abs(fps - 23.976) < 0.01 {
            timescale = 24000
        } else {
            timescale = 60000
        }
        let frameDuration = CMTime(value: CMTimeValue(Double(timescale) / fps), timescale: timescale)
        return CMTimeMultiply(frameDuration, multiplier: Int32(index))
    }

    private func makeVideoSettings() throws -> [String: Any] {
        var compression: [String: Any] = [:]
        let codecType: AVVideoCodecType
        switch codec {
        case .h264:
            codecType = .h264
            applyBitrateQuality(to: &compression)
            compression[AVVideoMaxKeyFrameIntervalKey] = 30
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
            compression[AVVideoAllowFrameReorderingKey] = true
            compression[AVVideoExpectedSourceFrameRateKey] = fps
        case .hevc:
            codecType = .hevc
            applyBitrateQuality(to: &compression)
            compression[AVVideoMaxKeyFrameIntervalKey] = 30
            compression[AVVideoAllowFrameReorderingKey] = true
            compression[AVVideoExpectedSourceFrameRateKey] = fps
        case .prores:
            codecType = .proRes422
        case .proresHQ:
            codecType = .proRes422HQ
        case .gif:
            throw RenderError.writerFailed("GIF uses GIFWriter, not VideoWriter.")
        }

        var settings: [String: Any] = [
            AVVideoCodecKey: codecType,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
        ]
        if !compression.isEmpty {
            settings[AVVideoCompressionPropertiesKey] = compression
        }
        return settings
    }

    private func applyBitrateQuality(to compression: inout [String: Any]) {
        let averageBps = encode.resolvedAverageBitsPerSecond(
            codec: codec,
            width: size.width,
            height: size.height
        )
        let maxBps = encode.resolvedMaxBitsPerSecond(
            codec: codec,
            width: size.width,
            height: size.height
        )
        compression[AVVideoAverageBitRateKey] = averageBps

        // VideoToolbox data-rate limit: [bytes per second, measurement window in seconds].
        let maxBytesPerSecond = max(1, maxBps / 8)
        compression["DataRateLimits"] = [maxBytesPerSecond, 1]

        if let quality = encode.resolvedQuality {
            compression[AVVideoQualityKey] = quality
        }
    }

    private func copy(cgImage: CGImage, to pixelBuffer: CVPixelBuffer) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw RenderError.writerFailed("Could not create CGContext for pixel buffer.")
        }
        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
    }
}
