import AppKit
@preconcurrency import AVFoundation
import ScreenCaptureKit
import CoreImage

/// Preview owns no writer or file. All device configuration and lifecycle calls
/// use the same serial queue; SwiftUI receives immutable images only.
final class PreviewFrames: NSObject, SCStreamOutput, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "no.lewtech.record.preview.frames")
    var screen: ((CGImage) -> Void)?
    var camera: ((CGImage) -> Void)?
    var level: ((Float) -> Void)?
    private let context = CIContext()
    private var lastCamera: Double = 0
    private var lastScreen: Double = 0
    private var microphoneMeter = MicrophoneMeter()

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int,
              status == SCFrameStatus.complete.rawValue,
              let pixels = buffer.imageBuffer else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastScreen >= 0.09 else { return }; lastScreen = now
        if let image = image(pixels) { screen?(image) }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        if output is AVCaptureVideoDataOutput {
            guard now - lastCamera >= 0.09, let pixels = buffer.imageBuffer else { return }
            lastCamera = now
            if let image = image(pixels) { camera?(image) }
        } else {
            if let value = microphoneMeter.read(buffer, at: now) { level?(value) }
        }
    }

    private func image(_ pixels: CVPixelBuffer) -> CGImage? {
        let source = CIImage(cvPixelBuffer: pixels)
        let scale = min(1, 960 / source.extent.width)
        let scaled = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(scaled, from: scaled.extent)
    }
}

@MainActor
final class LivePreview: NSObject, SCStreamDelegate {
    let frames = PreviewFrames()
    var onFailure: ((String) -> Void)?
    private var stream: SCStream?
    private var session: AVCaptureSession?
    private let devices = DispatchQueue(label: "no.lewtech.record.preview.devices")

    func startScreen(filter: SCContentFilter, size: (Int, Int)) async throws {
        let config = SCStreamConfiguration()
        let scale = min(1, 960.0 / Double(size.0))
        config.width = Int(Double(size.0) * scale); config.height = Int(Double(size.1) * scale)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 10)
        config.queueDepth = 3; config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true; config.capturesAudio = false
        config.backgroundColor = CGColor.black
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = stream
        try stream.addStreamOutput(frames, type: .screen, sampleHandlerQueue: frames.queue)
        try await stream.startCapture()
    }

    func startDevices(cameraID: String?, microphoneID: String?) async throws {
        guard cameraID != nil || microphoneID != nil else { return }
        let session = AVCaptureSession(); self.session = session
        let frames = self.frames
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            devices.async {
                do {
                    session.beginConfiguration(); session.sessionPreset = .high
                    do {
                        if let cameraID {
                            guard let device = AVCaptureDevice(uniqueID: cameraID) else { throw CaptureFailure.message("Valgt kamera er ikke tilgjengelig.") }
                            let input = try AVCaptureDeviceInput(device: device)
                            let output = AVCaptureVideoDataOutput()
                            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                            output.alwaysDiscardsLateVideoFrames = true
                            output.setSampleBufferDelegate(frames, queue: frames.queue)
                            guard session.canAddInput(input), session.canAddOutput(output) else { throw CaptureFailure.message("Kameraet kunne ikke åpnes.") }
                            session.addInput(input); session.addOutput(output)
                        }
                        if let microphoneID {
                            guard let device = AVCaptureDevice(uniqueID: microphoneID) else { throw CaptureFailure.message("Valgt mikrofon er ikke tilgjengelig.") }
                            let input = try AVCaptureDeviceInput(device: device)
                            let output = AVCaptureAudioDataOutput()
                            output.setSampleBufferDelegate(frames, queue: frames.queue)
                            guard session.canAddInput(input), session.canAddOutput(output) else { throw CaptureFailure.message("Mikrofonen kunne ikke åpnes.") }
                            session.addInput(input); session.addOutput(output)
                        }
                        session.commitConfiguration()
                    } catch { session.commitConfiguration(); throw error }
                    session.startRunning()
                    guard session.isRunning else { throw CaptureFailure.message("Forhåndsvisning av kamera/mikrofon kunne ikke startes.") }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func stop() async {
        let stream = self.stream; self.stream = nil
        if let stream { try? await stream.stopCapture() }
        let session = self.session; self.session = nil
        if let session {
            await withCheckedContinuation { continuation in devices.async { session.stopRunning(); continuation.resume() } }
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            guard self.stream === stream else { return }
            self.onFailure?("Forhåndsvisningen ble avbrutt: \(error.localizedDescription)")
        }
    }
}
