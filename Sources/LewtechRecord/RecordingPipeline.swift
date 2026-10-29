import AVFoundation
import ScreenCaptureKit
import CoreImage
import CoreImage.CIFilterBuiltins
import AudioToolbox

/// One serial queue owns media buffers, the timeline, compositor and writer.
/// A steady video clock repeats static screen frames so camera movement and
/// audio continue to be recorded when ScreenCaptureKit reports idle frames.
final class RecordingPipeline: NSObject, SCStreamOutput, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "no.lewtech.record.media", qos: .userInitiated)
    let outputURL: URL
    let width: Int
    let height: Int
    let mode: CaptureMode
    var onLevel: ((Float) -> Void)?
    var onScreenPreview: ((CGImage) -> Void)?
    private var lastScreenPreviewTime: Double = 0
    var onCameraPreview: ((CGImage) -> Void)?
    var onFailure: ((String) -> Void)?
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var timer: DispatchSourceTimer?
    private var screenBuffer: CVPixelBuffer?
    private var cameraBuffer: CVPixelBuffer?
    private var timeline = RecordingTimeline()
    private var accepting = false
    private var started = false
    private var failed = false
    private var frameCount = 0
    private var lastPTS = CMTime.invalid
    private var lastAudioPTS = CMTime.invalid
    private var bubbleScale: CGFloat = 0.24
    private var bubbleShape: FacecamShape = .circle
    private var bubblePosition = CGPoint(x: 0.04, y: 0.06)
    private var microphoneMeter = MicrophoneMeter()
    private var lastPreviewTime = 0.0
    private var audioClock: CMClock?
    private var sealedDuration: Double?

    init(url: URL, width: Int, height: Int, mode: CaptureMode, microphone: Bool) throws {
        self.outputURL = url; self.width = width; self.height = height; self.mode = mode
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        writer.movieFragmentInterval = CMTime(seconds: 5, preferredTimescale: 600)
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(2_000_000, width * height * 4),
                AVVideoExpectedSourceFrameRateKey: 30,
                // Real-time frames have variable arrival intervals. B-frame
                // reordering can produce non-monotonic decode times across
                // MP4 fragments (MovieHeaderMaker -16341). Keep decode order
                // equal to presentation order for this live recorder.
                AVVideoAllowFrameReorderingKey: false,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ])
        videoInput.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        if microphone {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128_000
            ])
            input.expectsMediaDataInRealTime = true
            audioInput = input
        } else { audioInput = nil }
        super.init()
        guard writer.canAdd(videoInput) else { throw CaptureFailure.message(L10n.tr("Kunne ikke opprette videospor.")) }
        writer.add(videoInput)
        if let audioInput {
            guard writer.canAdd(audioInput) else { throw CaptureFailure.message(L10n.tr("Kunne ikke opprette lydspor.")) }
            writer.add(audioInput)
        }
    }

    static var now: Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

    func begin() {
        queue.sync {
            accepting = true
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .nanoseconds(33_333_333), leeway: .milliseconds(2))
            timer.setEventHandler { [weak self] in self?.writeVideoFrame() }
            self.timer = timer
            timer.resume()
        }
    }
    func pause() { queue.sync { timeline.pause(at: Self.now) } }
    func resume() { queue.sync { timeline.resume(at: Self.now) } }
    var duration: Double { queue.sync { timeline.elapsed(at: Self.now) } }
    var hasFrames: Bool { queue.sync { frameCount > 0 } }
    func setBubblePosition(_ position: CGPoint) { queue.async { self.bubblePosition = position } }
    func setFacecam(shape: FacecamShape, scale: CGFloat, position: CGPoint) {
        queue.async { self.bubbleShape = shape; self.bubbleScale = scale; self.bubblePosition = position }
    }
    func setAudioClock(_ clock: CMClock?) { queue.sync { audioClock = clock } }
    /// Freeze the timeline at the user's Stop action, before device shutdown.
    func seal() { queue.sync { accepting = false; timer?.cancel(); timer = nil; sealedDuration = timeline.elapsed(at: Self.now) } }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int else { return }
        if accepting && (status == SCFrameStatus.suspended.rawValue || status == SCFrameStatus.stopped.rawValue) {
            fail(L10n.tr("Skjermkilden er ikke lenger tilgjengelig. Opptaket avsluttes og lagres."))
            return
        }
        guard status == SCFrameStatus.complete.rawValue, let image = buffer.imageBuffer else { return }
        receiveScreenFrame(image)
    }
    /// Called on the media queue; also used by deterministic compositor checks.
    func receiveScreenFrame(_ image: CVPixelBuffer) {
        screenBuffer = image
        if onScreenPreview != nil, Self.now - lastScreenPreviewTime >= 0.1 {
            lastScreenPreviewTime = Self.now
            let source = CIImage(cvPixelBuffer: image)
            let scale = min(1, 960 / source.extent.width)
            let preview = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            if let image = context.createCGImage(preview, from: preview.extent) { onScreenPreview?(image) }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output is AVCaptureVideoDataOutput {
            cameraBuffer = buffer.imageBuffer
            if let cameraBuffer, onCameraPreview != nil, Self.now - lastPreviewTime >= 0.1 {
                lastPreviewTime = Self.now
                let input = CIImage(cvPixelBuffer: cameraBuffer)
                let scale = min(1, 640 / input.extent.width)
                let preview = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                if let image = context.createCGImage(preview, from: preview.extent) { onCameraPreview?(image) }
            }
        }
        else { writeAudio(buffer) }
    }

    private func writeVideoFrame() {
        guard accepting, !failed, timeline.pausedAt == nil else { return }
        guard let source = mode == .camera ? cameraBuffer : screenBuffer else { return }
        // Never silently produce a screen-only file for a screen+camera request.
        if mode == .screenAndCamera && cameraBuffer == nil { return }
        let hostTime = Self.now
        if !started {
            guard writer.startWriting() else { fail(writer.error?.localizedDescription ?? L10n.tr("Videoopptaket kunne ikke startes.")); return }
            writer.startSession(atSourceTime: .zero)
            timeline.start(at: hostTime)
            started = true
        }
        guard let elapsed = timeline.timestamp(for: hostTime), videoInput.isReadyForMoreMediaData,
              let pool = adaptor.pixelBufferPool else { return }
        let pts = CMTime(seconds: elapsed, preferredTimescale: 60_000)
        guard !lastPTS.isValid || pts > lastPTS else { return }
        var output: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &output) == kCVReturnSuccess,
              let output else { fail(L10n.tr("Kunne ikke reservere minne til videobildet.")); return }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        var composed = fit(CIImage(cvPixelBuffer: source), into: bounds)
        if mode == .screenAndCamera, let cameraBuffer {
            let rect = facecamRect(canvas: bounds.size, position: bubblePosition, scale: bubbleScale)
            let camera = fill(CIImage(cvPixelBuffer: cameraBuffer), into: rect)
            let mask = CIFilter.roundedRectangleGenerator()
            mask.extent = rect; mask.radius = bubbleShape == .circle ? Float(rect.width / 2) : 0; mask.color = CIColor.white
            let blend = CIFilter.blendWithMask()
            blend.inputImage = camera; blend.backgroundImage = composed; blend.maskImage = mask.outputImage
            composed = blend.outputImage ?? composed
        }
        context.render(composed, to: output, bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())
        guard adaptor.append(output, withPresentationTime: pts) else {
            fail(writer.error?.localizedDescription ?? L10n.tr("Kunne ikke skrive videobildet til disk.")); return
        }
        lastPTS = pts; frameCount += 1
        if frameCount % 150 == 0 {
            if let available = try? outputURL.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
               available < 200_000_000 { fail(L10n.tr("Det er lite ledig diskplass. Opptaket avsluttes og lagres.")) }
        }
    }

    private func fit(_ image: CIImage, into rect: CGRect) -> CIImage {
        let scale = min(rect.width / image.extent.width, rect.height / image.extent.height)
        let scaled = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY)).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let centered = scaled.transformed(by: CGAffineTransform(translationX: rect.midX - scaled.extent.midX, y: rect.midY - scaled.extent.midY))
        return centered.composited(over: CIImage(color: .black).cropped(to: rect)).cropped(to: rect)
    }
    private func fill(_ image: CIImage, into rect: CGRect) -> CIImage {
        let scale = max(rect.width / image.extent.width, rect.height / image.extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return scaled.transformed(by: CGAffineTransform(translationX: rect.midX - scaled.extent.midX, y: rect.midY - scaled.extent.midY)).cropped(to: rect)
    }

    private func writeAudio(_ buffer: CMSampleBuffer) {
        meter(buffer)
        guard accepting, started, !failed, let audioInput, audioInput.isReadyForMoreMediaData,
              let audioClock else { return }
        let hostPTS = CMSyncConvertTime(buffer.presentationTimeStamp, from: audioClock, to: CMClockGetHostTimeClock())
        guard hostPTS.isValid, let mapped = timeline.timestamp(for: hostPTS.seconds) else { return }
        let pts = CMTime(seconds: mapped, preferredTimescale: 60_000)
        guard !lastAudioPTS.isValid || pts > lastAudioPTS else { return }
        var count = 0
        guard CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count) == noErr, count > 0 else { return }
        var timings = Array(repeating: CMSampleTimingInfo(), count: count)
        let timingStatus = timings.withUnsafeMutableBufferPointer {
            CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: count, arrayToFill: $0.baseAddress, entriesNeededOut: &count)
        }
        guard timingStatus == noErr else { return }
        let offset = buffer.presentationTimeStamp - pts
        for index in timings.indices {
            timings[index].presentationTimeStamp = timings[index].presentationTimeStamp - offset
            if timings[index].decodeTimeStamp.isValid { timings[index].decodeTimeStamp = timings[index].decodeTimeStamp - offset }
        }
        var adjusted: CMSampleBuffer?
        let result = timings.withUnsafeBufferPointer {
            CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: buffer, sampleTimingEntryCount: count, sampleTimingArray: $0.baseAddress!, sampleBufferOut: &adjusted)
        }
        guard result == noErr, let adjusted else { fail(L10n.tr("Kunne ikke synkronisere mikrofonsporet.")); return }
        if !audioInput.append(adjusted) { fail(writer.error?.localizedDescription ?? L10n.tr("Kunne ikke lagre mikrofonsporet.")) }
        lastAudioPTS = pts
    }

    private func meter(_ buffer: CMSampleBuffer) {
        if let level = microphoneMeter.read(buffer, at: Self.now) { onLevel?(level) }
    }

    private func fail(_ message: String) {
        guard !failed else { return }; failed = true; onFailure?(message)
    }

    func finish() async throws -> RecordingResult {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.accepting = false; self.timer?.cancel(); self.timer = nil
                let duration = self.sealedDuration ?? self.timeline.elapsed(at: Self.now)
                self.screenBuffer = nil; self.cameraBuffer = nil
                guard self.started, self.frameCount > 0 else {
                    self.writer.cancelWriting()
                    continuation.resume(throwing: CaptureFailure.message(L10n.tr("Ingen videobilder ble mottatt. Kontroller kilde og tillatelser, og prøv igjen."))); return
                }
                guard self.writer.status == .writing else {
                    continuation.resume(throwing: self.writer.error ?? CaptureFailure.message(L10n.tr("Videofilen kunne ikke ferdigstilles."))); return
                }
                self.writer.endSession(atSourceTime: CMTime(seconds: max(duration, self.lastPTS.seconds + 1.0 / 30), preferredTimescale: 60_000))
                self.videoInput.markAsFinished(); self.audioInput?.markAsFinished()
                self.writer.finishWriting {
                    if self.writer.status == .completed {
                        continuation.resume(returning: RecordingResult(url: self.outputURL, duration: duration))
                    } else {
                        continuation.resume(throwing: self.writer.error ?? CaptureFailure.message(L10n.tr("Lagring av videoen mislyktes.")))
                    }
                }
            }
        }
    }
    func discard() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.accepting = false; self.timer?.cancel(); self.timer = nil
                self.writer.cancelWriting(); self.screenBuffer = nil; self.cameraBuffer = nil
                try? FileManager.default.removeItem(at: self.outputURL)
                continuation.resume()
            }
        }
    }
}
