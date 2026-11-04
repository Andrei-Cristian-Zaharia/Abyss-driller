#if DEBUG && canImport(UIKit)
import AVFoundation
import UIKit

// MARK: - Director capture (Debug builds only)
//
// `-scenarioCapture <seconds>` records the scenario offline instead of
// leaving it to `simctl io recordVideo`. A screen recording of the CI
// simulator (no GPU, software rendering) only gets the frames the simulator
// manages to draw in real time, ~30 of them per second, so a "60 fps" file
// was mostly duplicates. Here every video frame is one exact 1/60 s step:
//
//   1. wait until the screen shows virtual frame n (the world canvas drew
//      the clock's date; `Director.captureFrameOnScreen`),
//   2. draw the key window (world, HUD, overlays) into a pixel buffer and
//      append it at presentation time n/60,
//   3. advance the game, the autopilot and the clock by exactly 1/60 s
//      (`Director.captureAdvance`), which makes SwiftUI draw frame n+1.
//
// Capturing slower than real time only makes the job take longer; the clip
// always has 60 unique frames per second at normal game speed. The H.264
// file is written at the window's pixel size (CI re-encodes it to
// 1080x1920) to Documents/DirectorCapture/capture.mp4; the last log line is
// `[Director] CAPTURE done …` or `[Director] CAPTURE failed …`.

final class DirectorRecorder: NSObject {
    private let fps: Int
    private let totalFrames: Int
    let url: URL

    private var link: CADisplayLink?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var pointSize = CGSize.zero
    private var pixelWidth = 0
    private var pixelHeight = 0

    private var frame = 0
    private var waits = 0
    private var staleFrames = 0
    private var encoderWaits = 0
    private var finished = false
    private var realStart = 0.0
    private var lastReport = 0.0
    private var lastReportFrame = 0

    /// Callbacks to wait for the canvas before capturing a frame anyway
    /// (counted as `staleFrames`, which CI reports).
    private let maxWaits = 30

    init(seconds: Double, fps: Int) {
        self.fps = fps
        totalFrames = max(1, Int((seconds * Double(fps)).rounded()))
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DirectorCapture", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("capture.mp4")
        super.init()
    }

    func start() {
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
        realStart = CACurrentMediaTime()
        lastReport = realStart
        Director.shared.log("CAPTURE start frames=\(totalFrames) fps=\(fps) file=\(url.path)")
    }

    private var window: UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }

    @objc private func step() {
        guard !finished, let window, window.bounds.width > 0 else { return }
        if writer == nil, !setUpWriter(for: window) { return }
        guard let input, let adaptor, let writer else { return }
        guard input.isReadyForMoreMediaData else { encoderWaits += 1; return }
        if !Director.shared.captureFrameOnScreen(frame) {
            waits += 1
            if waits < maxWaits { return }
            staleFrames += 1
        }
        waits = 0

        guard let buffer = render(window, pool: adaptor.pixelBufferPool) else {
            fail("could not render frame \(frame)")
            return
        }
        let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))
        guard adaptor.append(buffer, withPresentationTime: time) else {
            fail("append failed at frame \(frame): \(writer.error.map { "\($0)" } ?? "unknown")")
            return
        }
        frame += 1
        report()
        if frame >= totalFrames {
            finish()
            return
        }
        Director.shared.captureAdvance(to: frame)
    }

    private func setUpWriter(for window: UIWindow) -> Bool {
        pointSize = window.bounds.size
        let scale = window.traitCollection.displayScale
        // H.264 wants even dimensions.
        pixelWidth = Int((pointSize.width * scale).rounded()) & ~1
        pixelHeight = Int((pointSize.height * scale).rounded()) & ~1
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let compression: [String: Any] = [
                AVVideoAverageBitRateKey: 40_000_000,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps,
                AVVideoAllowFrameReorderingKey: false,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ]
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: pixelWidth,
                AVVideoHeightKey: pixelHeight,
                AVVideoCompressionPropertiesKey: compression,
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = false
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: pixelWidth,
                kCVPixelBufferHeightKey as String: pixelHeight,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            ])
            guard writer.canAdd(input) else {
                fail("the writer refused a \(pixelWidth)x\(pixelHeight) H.264 input")
                return false
            }
            writer.add(input)
            guard writer.startWriting() else {
                fail("startWriting: \(writer.error.map { "\($0)" } ?? "unknown")")
                return false
            }
            writer.startSession(atSourceTime: .zero)
            self.writer = writer
            self.input = input
            self.adaptor = adaptor
            Director.shared.log("CAPTURE writer \(pixelWidth)x\(pixelHeight) h264 \(fps) fps")
            return true
        } catch {
            fail("AVAssetWriter: \(error)")
            return false
        }
    }

    /// The key window as it is on screen now (world canvas, HUD, overlays).
    private func render(_ window: UIWindow, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        }
        if buffer == nil {
            CVPixelBufferCreate(nil, pixelWidth, pixelHeight, kCVPixelFormatType_32BGRA,
                                [kCVPixelBufferCGBitmapContextCompatibilityKey as String: true] as CFDictionary, &buffer)
        }
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: pixelWidth, height: pixelHeight,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        // UIKit draws top-down in points.
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: CGFloat(pixelWidth) / pointSize.width, y: -CGFloat(pixelHeight) / pointSize.height)
        UIGraphicsPushContext(context)
        window.drawHierarchy(in: CGRect(origin: .zero, size: pointSize), afterScreenUpdates: false)
        UIGraphicsPopContext()
        return buffer
    }

    /// Every ~5 real seconds: how fast capture runs (it may be below 60).
    private func report() {
        let now = CACurrentMediaTime()
        guard now - lastReport >= 5 else { return }
        let rate = Double(frame - lastReportFrame) / (now - lastReport)
        Director.shared.log(String(format: "CAPTURE frame %d/%d (%.1f s of video), capturing at %.1f frames per real second, stale=%d",
                                   frame, totalFrames, Double(frame) / Double(fps), rate, staleFrames))
        lastReport = now
        lastReportFrame = frame
    }

    private func finish() {
        finished = true
        link?.invalidate()
        link = nil
        guard let writer, let input else { return }
        input.markAsFinished()
        let frames = frame, rate = self.fps, stale = staleFrames, waitedOnEncoder = self.encoderWaits
        let real = CACurrentMediaTime() - realStart
        let runFrom = Director.shared.captureRunFrom.map(String.init) ?? "none"
        let path = url.path
        Task { @MainActor in
            await writer.finishWriting()
            if writer.status == .completed {
                Director.shared.log(String(format: "CAPTURE done frames=%d fps=%d seconds=%.3f realSeconds=%.1f "
                                           + "staleFrames=%d encoderWaits=%d runFrom=%@ file=%@",
                                           frames, rate, Double(frames) / Double(rate), real,
                                           stale, waitedOnEncoder, runFrom, path))
            } else {
                Director.shared.log("CAPTURE failed: finishWriting status=\(writer.status.rawValue) "
                                    + (writer.error.map { "\($0)" } ?? ""))
            }
        }
    }

    private func fail(_ reason: String) {
        finished = true
        link?.invalidate()
        link = nil
        writer?.cancelWriting()
        Director.shared.log("CAPTURE failed: \(reason)")
    }
}
#endif
