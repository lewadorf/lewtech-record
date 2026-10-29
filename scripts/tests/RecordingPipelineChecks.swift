import AVFoundation
import AudioToolbox
import CoreImage
import Foundation

/// Synthetic media only: this runs the real compositor, H.264/AAC encoder and
/// decoder without opening a camera, microphone or ScreenCaptureKit stream.
func runSyntheticPipelineChecks() async throws -> Int {
    let manager = FileManager.default
    let artifactRoot = ProcessInfo.processInfo.environment["LEWTECH_TEST_ARTIFACTS"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    let directory = (artifactRoot ?? manager.temporaryDirectory).appendingPathComponent("synthetic-pipeline-\(UUID().uuidString)", isDirectory: true)
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { if artifactRoot == nil { try? manager.removeItem(at: directory) } }
    let output = directory.appendingPathComponent("synthetic-camera-pause.mp4")
    let pipeline = try RecordingPipeline(url: output, width: 320, height: 180, mode: .camera, microphone: true)
    let videoOutput = AVCaptureVideoDataOutput()
    let audioOutput = AVCaptureAudioDataOutput()
    let videoConnection = AVCaptureConnection(inputPorts: [], output: videoOutput)
    let audioConnection = AVCaptureConnection(inputPorts: [], output: audioOutput)
    let red = try syntheticVideoSample(red: 220, green: 20, blue: 15)
    let blue = try syntheticVideoSample(red: 15, green: 20, blue: 220)
    let audioFormat = try syntheticPCMFormat()
    pipeline.setAudioClock(CMClockGetHostTimeClock())
    pipeline.queue.sync { pipeline.captureOutput(videoOutput, didOutput: red, from: videoConnection) }
    pipeline.begin()
    let wallStart = RecordingPipeline.now
    do {
        try await feedSyntheticAudio(pipeline: pipeline, output: audioOutput, connection: audioConnection, format: audioFormat, packetCount: 50, firstPacket: 0)
        try verificationRequire(pipeline.hasFrames, "Synthetic input did not produce video frames")
        pipeline.pause()
        let pausedDuration = pipeline.duration
        let pauseStart = RecordingPipeline.now
        // Continue delivering PCM during pause to verify that paused samples are discarded.
        try await feedSyntheticAudio(pipeline: pipeline, output: audioOutput, connection: audioConnection, format: audioFormat, packetCount: 15, firstPacket: 50)
        let pauseLength = RecordingPipeline.now - pauseStart
        try verificationRequire(abs(pipeline.duration - pausedDuration) < 0.02, "Recording duration advanced during a pause")
        pipeline.queue.sync { pipeline.captureOutput(videoOutput, didOutput: blue, from: videoConnection) }
        pipeline.resume()
        try await feedSyntheticAudio(pipeline: pipeline, output: audioOutput, connection: audioConnection, format: audioFormat, packetCount: 50, firstPacket: 65)
        let expectedDuration = RecordingPipeline.now - wallStart - pauseLength
        pipeline.seal()
        // Slow device shutdown must not extend a sealed recording.
        try await Task.sleep(nanoseconds: 300_000_000)
        let result = try await pipeline.finish()
        try verificationRequire(abs(result.duration - expectedDuration) < 0.18, "Synthetic recording retained pause or shutdown time (\(result.duration) vs \(expectedDuration))")

        let asset = AVURLAsset(url: result.url)
        let playable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration).seconds
        try verificationRequire(playable, "Encoded MP4 is not playable")
        try verificationRequire(abs(duration - result.duration) < 0.12, "MP4 duration differs from sealed recording duration")
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard videoTracks.count == 1, let videoTrack = videoTracks.first else { throw VerificationFailure(message: "Expected one encoded video track") }
        let dimensions = try await videoTrack.load(.naturalSize)
        try verificationRequire(dimensions == CGSize(width: 320, height: 180), "Encoded video dimensions changed")
        let videoFormats = try await videoTrack.load(.formatDescriptions)
        try verificationRequire(videoFormats.first.map { CMFormatDescriptionGetMediaSubType($0) } == kCMVideoCodecType_H264, "Video track is not H.264")

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard audioTracks.count == 1, let audioTrack = audioTracks.first else { throw VerificationFailure(message: "Synthetic PCM did not create an audio track") }
        let audioRange = try await audioTrack.load(.timeRange)
        let audioFormats = try await audioTrack.load(.formatDescriptions)
        try verificationRequire(audioFormats.first.map { CMFormatDescriptionGetMediaSubType($0) } == kAudioFormatMPEG4AAC, "Audio track is not AAC")
        try verificationRequire(audioRange.duration.seconds > expectedDuration - 0.20 && audioRange.duration.seconds < expectedDuration + 0.12, "Audio track duration \(audioRange.duration.seconds), start \(audioRange.start.seconds), end \(audioRange.end.seconds) versus active \(expectedDuration), video \(duration)")
        try verificationRequire(abs(audioRange.end.seconds - duration) < 0.18, "Audio/video end divergence: audio start \(audioRange.start.seconds), end \(audioRange.end.seconds), length \(audioRange.duration.seconds), video \(duration), active \(expectedDuration)")

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.08, preferredTimescale: 600)
        let first = try await generator.image(at: CMTime(seconds: 0.4, preferredTimescale: 600)).image
        let secondTime = min(duration - 0.2, pausedDuration + 0.4)
        let second = try await generator.image(at: CMTime(seconds: secondTime, preferredTimescale: 600)).image
        let redPixel = try centerRGB(first)
        let bluePixel = try centerRGB(second)
        try verificationRequire(redPixel.0 > 150 && redPixel.2 < 80, "Decoded first segment lost its synthetic red frame")
        try verificationRequire(bluePixel.2 > 150 && bluePixel.0 < 80, "Decoded resumed segment lost its synthetic blue frame")
        try verifyAudibleDecodedPCM(asset: asset, track: audioTrack)
        let compositorChecks = try await runSyntheticCompositorChecks(directory: directory)
        let recoveryChecks = try await verifyRecoveryWithSyntheticVideo(sourceURL: result.url, directory: directory.appendingPathComponent("recovery-fixture", isDirectory: true))
        return 12 + compositorChecks + recoveryChecks
    } catch {
        await pipeline.discard()
        throw error
    }
}

@MainActor
private func verifyRecoveryWithSyntheticVideo(sourceURL: URL, directory: URL) async throws -> Int {
    let manager = FileManager.default
    let incomplete = directory.appendingPathComponent(".incomplete", isDirectory: true)
    try manager.createDirectory(at: incomplete, withIntermediateDirectories: true)
    let recoverable = incomplete.appendingPathComponent("recover.mp4")
    let invalid = incomplete.appendingPathComponent("invalid-fragment.mp4")
    let invalidBytes = Data("synthetic incomplete fragment, intentionally not playable".utf8)
    try manager.copyItem(at: sourceURL, to: recoverable)
    try invalidBytes.write(to: invalid)
    let store = LibraryStore(directory: directory)

    // Created after initialization: this must be treated as a potential active
    // recording even though the fixture deliberately contains a completed MP4.
    let late = incomplete.appendingPathComponent("late-active-recording.mp4")
    try manager.copyItem(at: sourceURL, to: late)
    let recovered = await store.recoverInterruptedRecordings()
    try verificationRequire(recovered == 1 && store.items.count == 1, "Recovery did not import exactly one playable startup recording")
    guard let item = store.items.first else { throw VerificationFailure(message: "Recovered library item is missing") }
    let recoveredURL = store.url(for: item)
    let playable = try await AVURLAsset(url: recoveredURL).load(.isPlayable)
    let sourceBytes = try Data(contentsOf: sourceURL)
    let recoveredBytes = try Data(contentsOf: recoveredURL)
    try verificationRequire(playable && recoveredBytes == sourceBytes && !manager.fileExists(atPath: recoverable.path), "Recovery lost or changed the playable video bytes")

    let reopened = LibraryStore(directory: directory)
    try verificationRequire(reopened.items.count == 1 && reopened.items.first?.id == item.id && reopened.items.first?.fileName == item.fileName, "Recovered recording was not persisted in the library index")
    let retainedFragment = try Data(contentsOf: invalid)
    try verificationRequire(retainedFragment == invalidBytes && store.recoveryMessage != nil, "Unrecoverable fragment was modified or its recovery warning was hidden")
    let repeated = await store.recoverInterruptedRecordings()
    let lateBytes = try Data(contentsOf: late)
    try verificationRequire(repeated == 0 && store.items.count == 1 && lateBytes == sourceBytes, "One-shot recovery consumed a recording created after initialization")
    return 5
}

private func runSyntheticCompositorChecks(directory: URL) async throws -> Int {
    let output = directory.appendingPathComponent("synthetic-screen-camera-bubble.mp4")
    let pipeline = try RecordingPipeline(url: output, width: 320, height: 180, mode: .screenAndCamera, microphone: false)
    let cameraOutput = AVCaptureVideoDataOutput()
    let cameraConnection = AVCaptureConnection(inputPorts: [], output: cameraOutput)
    let camera = try syntheticVideoSample(red: 220, green: 20, blue: 15)
    let screen = try syntheticVideoSample(red: 15, green: 20, blue: 220)
    guard let screenPixels = screen.imageBuffer else { throw VerificationFailure(message: "Synthetic screen pixels unavailable") }
    pipeline.queue.sync {
        pipeline.receiveScreenFrame(screenPixels)
        pipeline.captureOutput(cameraOutput, didOutput: camera, from: cameraConnection)
    }
    pipeline.begin()
    do {
        try await Task.sleep(nanoseconds: 600_000_000)
        try verificationRequire(pipeline.hasFrames, "Screen + camera compositor did not output frames")
        let moveAt = pipeline.duration
        pipeline.setBubblePosition(CGPoint(x: 0.7, y: 0.7))
        try await Task.sleep(nanoseconds: 600_000_000)
        let squareAt = pipeline.duration
        pipeline.setFacecam(shape: .square, scale: 0.4, position: CGPoint(x: 0.5, y: 0.3))
        try await Task.sleep(nanoseconds: 600_000_000)
        pipeline.seal()
        let result = try await pipeline.finish()
        let asset = AVURLAsset(url: result.url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.08, preferredTimescale: 600)
        let before = try await generator.image(at: CMTime(seconds: 0.25, preferredTimescale: 600)).image
        let after = try await generator.image(at: CMTime(seconds: moveAt + 0.25, preferredTimescale: 600)).image
        let first = try analyzeBubblePixels(before)
        let second = try analyzeBubblePixels(after)
        // The 43.2-pixel circle has an ideal area of 1466 pixels. The tolerance
        // allows H.264 chroma subsampling around the anti-aliased circle edge.
        try verificationRequire((1000...1900).contains(first.redCount) && (1000...1900).contains(second.redCount), "Camera was not burned into both exported frames as a bounded bubble (\(first.redCount), \(second.redCount) red pixels)")
        try verificationRequire(first.blueFraction > 0.90 && second.blueFraction > 0.90, "Camera composition replaced or damaged the screen background")
        try verificationRequire(first.circleFillRatio > 0.65 && first.circleFillRatio < 0.88 && second.circleFillRatio > 0.65 && second.circleFillRatio < 0.88, "Camera shape is not circular in exported MP4")
        try verificationRequire(first.cornersAreBlue && second.cornersAreBlue, "Screen corners changed outside the camera bubble")
        try verificationRequire(abs(first.centroidX - 37.6) < 5 && abs(second.centroidX - 245.6) < 5, "Exported camera bubble did not follow its requested horizontal position")
        // A CGContext raster can expose the vertical axis in either convention;
        // compare displacement rather than assuming top-left image coordinates.
        try verificationRequire(second.centroidX - first.centroidX > 180 && abs(second.centroidY - first.centroidY) > 80, "Moving the camera bubble did not change its exported centroid")
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        try verificationRequire(audioTracks.isEmpty, "Microphone-disabled recording unexpectedly contains an audio track")
        let squareImage = try await generator.image(at: CMTime(seconds: squareAt + 0.25, preferredTimescale: 600)).image
        let square = try analyzeBubblePixels(squareImage)
        try verificationRequire(square.circleFillRatio > 0.94, "Square facecam was still masked as a circle")
        try verificationRequire((4800...5500).contains(square.redCount), "Facecam size did not reach the exported MP4")
        try verificationRequire(abs(square.centroidX - 196) < 4, "Square facecam position differed from the selected composition")
        return 11
    } catch {
        await pipeline.discard()
        throw error
    }
}

private struct BubblePixelAnalysis {
    let redCount: Int
    let blueFraction: Double
    let centroidX: Double
    let centroidY: Double
    let circleFillRatio: Double
    let cornersAreBlue: Bool
}

private func analyzeBubblePixels(_ image: CGImage) throws -> BubblePixelAnalysis {
    let width = image.width, height = image.height
    try verificationRequire(width == 320 && height == 180, "Decoded compositor frame has unexpected dimensions")
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let rendered = pixels.withUnsafeMutableBytes { storage -> Bool in
        guard let context = CGContext(data: storage.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard rendered else { throw VerificationFailure(message: "Unable to inspect decoded camera bubble pixels") }
    var redCount = 0, blueCount = 0, sumX = 0, sumY = 0
    var minX = width, maxX = -1, minY = height, maxY = -1
    for y in 0..<height {
        for x in 0..<width {
            let index = (y * width + x) * 4
            let red = pixels[index], green = pixels[index + 1], blue = pixels[index + 2]
            if red > 140 && green < 80 && blue < 80 {
                redCount += 1; sumX += x; sumY += y
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
            if blue > 140 && red < 80 && green < 80 { blueCount += 1 }
        }
    }
    let corners = [(2, 2), (width - 3, 2), (2, height - 3), (width - 3, height - 3)]
    let cornersAreBlue = corners.allSatisfy { x, y in
        let index = (y * width + x) * 4
        return pixels[index + 2] > 140 && pixels[index] < 80
    }
    let boundingArea = max(1, (maxX - minX + 1) * (maxY - minY + 1))
    return BubblePixelAnalysis(redCount: redCount, blueFraction: Double(blueCount) / Double(width * height),
                              centroidX: Double(sumX) / Double(max(1, redCount)), centroidY: Double(sumY) / Double(max(1, redCount)),
                              circleFillRatio: Double(redCount) / Double(boundingArea), cornersAreBlue: cornersAreBlue)
}

private func feedSyntheticAudio(pipeline: RecordingPipeline, output: AVCaptureAudioDataOutput, connection: AVCaptureConnection, format: CMAudioFormatDescription, packetCount: Int, firstPacket: Int) async throws {
    var previous = CMClockGetTime(CMClockGetHostTimeClock())
    var frameCursor = firstPacket * 960
    for packet in firstPacket..<(firstPacket + packetCount) {
        try await Task.sleep(nanoseconds: 20_000_000)
        // A real microphone supplies every sample, even when delegate scheduling
        // is late. Fill the entire elapsed interval instead of fabricating gaps
        // by assuming Task.sleep wakes at exactly 20 ms.
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        let frames = max(1, Int(((now - previous).seconds * 48_000).rounded()))
        let sample = try syntheticAudioSample(format: format, timestamp: previous, firstFrame: frameCursor, frameCount: frames)
        previous = previous + CMTime(value: Int64(frames), timescale: 48_000)
        frameCursor += frames
        pipeline.queue.sync { pipeline.captureOutput(output, didOutput: sample, from: connection) }
        _ = packet
    }
}

private func syntheticVideoSample(red: UInt8, green: UInt8, blue: UInt8) throws -> CMSampleBuffer {
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(kCFAllocatorDefault, 320, 180, kCVPixelFormatType_32BGRA,
                                    [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &pixelBuffer)
    guard status == kCVReturnSuccess, let pixelBuffer else { throw VerificationFailure(message: "Synthetic pixel buffer allocation failed: \(status)") }
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { CVPixelBufferUnlockBaseAddress(pixelBuffer, []); throw VerificationFailure(message: "Synthetic pixel buffer has no storage") }
    let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
    for y in 0..<180 {
        let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
        for x in 0..<320 { row[x * 4] = blue; row[x * 4 + 1] = green; row[x * 4 + 2] = red; row[x * 4 + 3] = 255 }
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    var description: CMVideoFormatDescription?
    let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &description)
    guard formatStatus == noErr, let description else { throw VerificationFailure(message: "Synthetic video format failed") }
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescription: description, sampleTiming: &timing, sampleBufferOut: &sample)
    guard sampleStatus == noErr, let sample else { throw VerificationFailure(message: "Synthetic video sample failed") }
    return sample
}

private func syntheticPCMFormat() throws -> CMAudioFormatDescription {
    var description: CMAudioFormatDescription?
    var format = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
                                            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                                            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
                                            mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
    let status = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &format, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &description)
    guard status == noErr, let description else { throw VerificationFailure(message: "Synthetic PCM format failed: \(status)") }
    return description
}

private func syntheticAudioSample(format: CMAudioFormatDescription, timestamp: CMTime, firstFrame: Int, frameCount: Int) throws -> CMSampleBuffer {
    let samples: [Int16] = (0..<frameCount).map { Int16(sin(2 * Double.pi * 440 * Double(firstFrame + $0) / 48_000) * 10_000) }
    var block: CMBlockBuffer?
    let allocationStatus = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: samples.count * 2, blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: samples.count * 2, flags: 0, blockBufferOut: &block)
    guard allocationStatus == noErr, let block else { throw VerificationFailure(message: "Synthetic PCM buffer allocation failed") }
    let copyStatus = samples.withUnsafeBytes { raw in
        CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: raw.count)
    }
    guard copyStatus == noErr else { throw VerificationFailure(message: "Synthetic PCM copy failed") }
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000), presentationTimeStamp: timestamp, decodeTimeStamp: .invalid)
    var sampleSize = 2
    var sample: CMSampleBuffer?
    let status = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: frameCount, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &sample)
    guard status == noErr, let sample else { throw VerificationFailure(message: "Synthetic PCM sample failed: \(status)") }
    return sample
}

private func centerRGB(_ image: CGImage) throws -> (UInt8, UInt8, UInt8) {
    var pixel = [UInt8](repeating: 0, count: 4)
    let succeeded = pixel.withUnsafeMutableBytes { storage -> Bool in
        guard let context = CGContext(data: storage.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return true
    }
    guard succeeded else { throw VerificationFailure(message: "Decoded image color check could not create a context") }
    return (pixel[0], pixel[1], pixel[2])
}

private func verifyAudibleDecodedPCM(asset: AVAsset, track: AVAssetTrack) throws {
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false, AVLinearPCMIsNonInterleaved: false
    ])
    guard reader.canAdd(output) else { throw VerificationFailure(message: "Cannot decode synthetic AAC track") }
    reader.add(output)
    guard reader.startReading() else { throw reader.error ?? VerificationFailure(message: "AAC decoder did not start") }
    var energy = 0.0
    var sampleCount = 0
    while let sample = output.copyNextSampleBuffer(), let block = sample.dataBuffer {
        let length = CMBlockBufferGetDataLength(block)
        var pcm = [Int16](repeating: 0, count: length / 2)
        let status = pcm.withUnsafeMutableBytes { storage in
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: storage.baseAddress!)
        }
        guard status == noErr else { throw VerificationFailure(message: "Decoded PCM samples are unavailable") }
        for value in pcm { let normalized = Double(value) / 32768; energy += normalized * normalized }
        sampleCount += pcm.count
    }
    try verificationRequire(reader.status == .completed, "AAC decode ended before completing")
    try verificationRequire(sampleCount > 48_000 && sqrt(energy / Double(max(1, sampleCount))) > 0.05, "Decoded synthetic tone is missing or silent")
}

/// Uses the same device-buffer delegates as idle preview, without constructing
/// an AVAssetWriter or requesting any device permissions.
func runPreviewChecks() throws -> Int {
    let frames = PreviewFrames()
    let video = AVCaptureVideoDataOutput()
    let connection = AVCaptureConnection(inputPorts: [], output: video)
    let red = try syntheticVideoSample(red: 220, green: 20, blue: 15)
    var image: CGImage?
    var level: Float = 0
    frames.camera = { image = $0 }
    frames.level = { level = $0 }
    frames.queue.sync { frames.captureOutput(video, didOutput: red, from: connection) }
    guard let image else { throw VerificationFailure(message: "Idle preview did not deliver camera pixels") }
    let rgb = try centerRGB(image)
    try verificationRequire(rgb.0 > 150 && rgb.2 < 80, "Camera preview lost source pixels")
    try verificationRequire(image.width <= 960, "Preview exceeded its display resolution budget")
    let audio = AVCaptureAudioDataOutput()
    let audioConnection = AVCaptureConnection(inputPorts: [], output: audio)
    let sample = try syntheticAudioSample(format: syntheticPCMFormat(), timestamp: .zero, firstFrame: 0, frameCount: 4800)
    frames.queue.sync { frames.captureOutput(audio, didOutput: sample, from: audioConnection) }
    try verificationRequire(level > 0 && level <= 1, "Idle microphone meter did not respond to PCM")
    let canvas = CGSize(width: 1920, height: 1080)
    let original = facecamRect(canvas: canvas, position: CGPoint(x: 0.2, y: 0.4), scale: 0.24)
    let larger = resizedFacecamRect(origin: original, canvas: canvas, translation: CGSize(width: 60, height: 60))
    try verificationRequire(larger.width > original.width && larger.minX == original.minX && larger.maxY == original.maxY, "Corner resize moved its opposite anchor")
    let smaller = resizedFacecamRect(origin: original, canvas: canvas, translation: CGSize(width: -60, height: -60))
    try verificationRequire(smaller.width < original.width && smaller.maxY == original.maxY, "Corner resize could not shrink smoothly")
    let huge = resizedFacecamRect(origin: original, canvas: canvas, translation: CGSize(width: 10000, height: 10000))
    try verificationRequire(huge.minY >= 16 && huge.maxX <= canvas.width - 16 && huge.width <= 540, "Corner resize escaped the recording canvas")
    let tiny = resizedFacecamRect(origin: original, canvas: canvas, translation: CGSize(width: -10000, height: -10000))
    try verificationRequire(abs(tiny.width - 129.6) < 0.01, "Corner resize lost the minimum usable size")
    try verificationRequire(microphoneLevel(peak: 0) == 0, "Silent microphone must not light a segment")
    try verificationRequire(abs(microphoneLevel(peak: pow(10, -12.0 / 20)) - 0.8) < 0.001, "Yellow meter threshold does not correspond to -12 dBFS")
    try verificationRequire(abs(microphoneLevel(peak: pow(10, -6.0 / 20)) - 0.9) < 0.001 && microphoneLevel(peak: 1) == 1, "Red meter threshold/headroom is incorrect")
    return 10
}

func runFragmentTimingChecks() async throws -> Int {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lewtech-timing-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let pipeline = try RecordingPipeline(url: directory.appendingPathComponent("jitter.mp4"), width: 1660, height: 1080, mode: .screenAndCamera, microphone: true)
    let video = AVCaptureVideoDataOutput(), audio = AVCaptureAudioDataOutput()
    let videoConnection = AVCaptureConnection(inputPorts: [], output: video)
    let audioConnection = AVCaptureConnection(inputPorts: [], output: audio)
    let camera = try syntheticVideoSample(red: 220, green: 20, blue: 15)
    let format = try syntheticPCMFormat()
    pipeline.setAudioClock(CMClockGetHostTimeClock())
    pipeline.queue.sync { pipeline.receiveScreenFrame(camera.imageBuffer!); pipeline.captureOutput(video, didOutput: camera, from: videoConnection) }
    pipeline.begin()
    let seconds = Double(ProcessInfo.processInfo.environment["LEWTECH_STRESS_SECONDS"] ?? "22") ?? 22
    let origin = CMClockGetTime(CMClockGetHostTimeClock())
    do {
        for packet in 0..<Int(seconds * 50) {
            try await Task.sleep(nanoseconds: 20_000_000)
            // Simulate a remote microphone whose clock has small corrections.
            // Starts remain increasing, but adjacent 20ms packets overlap/gap.
            let jitter = packet % 11 == 0 ? -0.001 : packet % 7 == 0 ? 0.001 : 0
            let stamp = origin + CMTime(seconds: Double(packet) * 0.02 + jitter, preferredTimescale: 48000)
            let sample = try syntheticAudioSample(format: format, timestamp: stamp, firstFrame: packet * 960, frameCount: 960)
            pipeline.queue.sync { pipeline.captureOutput(audio, didOutput: sample, from: audioConnection) }
        }
        pipeline.seal()
        let result = try await pipeline.finish()
        let asset = AVURLAsset(url: result.url)
        let playable = try await asset.load(.isPlayable)
        try verificationRequire(playable, "Fragment timing stress file is not playable")
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        try verificationRequire(tracks.count == 1, "Fragment timing stress lost microphone track")
        return 2
    } catch { await pipeline.discard(); throw error }
}
