import Foundation
import CoreMedia
import AudioToolbox

enum RecordingState: String { case idle, preparing, recording, paused, finishing }
enum CaptureMode: String, CaseIterable, Identifiable {
    case screen, screenAndCamera, camera
    var id: String { rawValue }
    var title: String {
        switch self { case .screen: return "Kun skjerm"; case .screenAndCamera: return "Skjerm og kamera"; case .camera: return "Kun kamera" }
    }
}
struct DisplayChoice: Identifiable { let id: String; let title: String }
struct WindowChoice: Identifiable { let id: String; let title: String }
struct DeviceChoice: Identifiable { let id: String; let title: String }
struct RecordingResult { let url: URL; let duration: Double }

enum CaptureFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// All media timestamps use the host clock. Paused wall time is removed from
/// both tracks using the same offset; samples inside a pause are discarded.
struct RecordingTimeline {
    private(set) var origin: Double?
    private(set) var pausedAt: Double?
    private(set) var accumulatedPause: Double = 0
    mutating func start(at time: Double) { if origin == nil { origin = time; accumulatedPause = 0 } }
    mutating func pause(at time: Double) { if pausedAt == nil { pausedAt = time } }
    mutating func resume(at time: Double) {
        if let pausedAt { accumulatedPause += max(0, time - pausedAt); self.pausedAt = nil }
    }
    func timestamp(for time: Double) -> Double? {
        guard let origin, pausedAt == nil else { return nil }
        let result = time - origin - accumulatedPause
        return result >= 0 ? result : nil
    }
    func elapsed(at time: Double) -> Double {
        guard let origin else { return 0 }
        return max(0, (pausedAt ?? time) - origin - accumulatedPause)
    }
}

func recordingOutputSize(width: Double, height: Double) -> (Int, Int) {
    let safeWidth = max(2, width), safeHeight = max(2, height)
    let scale = min(1, 1920 / safeWidth, 1080 / safeHeight)
    return (max(2, Int(safeWidth * scale) / 2 * 2), max(2, Int(safeHeight * scale) / 2 * 2))
}


enum FacecamShape: String, CaseIterable, Identifiable {
    case circle, square
    var id: String { rawValue }
    var title: String { self == .circle ? "Rund" : "Firkantet" }
}

/// Same geometry for setup preview and encoded pixels. Position is the lower
/// left corner in normalized output coordinates (Core Image's coordinate space).
func facecamRect(canvas: CGSize, position: CGPoint, scale: CGFloat) -> CGRect {
    let side = min(canvas.width, canvas.height) * max(0.12, min(0.5, scale))
    let padding = min(16, min(canvas.width, canvas.height) * 0.1)
    return CGRect(x: max(padding, min(canvas.width - side - padding, position.x * canvas.width)),
                  y: max(padding, min(canvas.height - side - padding, position.y * canvas.height)),
                  width: side, height: side)
}

/// Resize from the bottom-right handle while retaining the top-left anchor.
/// Translation is in output pixels, with positive Y pointing down like SwiftUI.
func resizedFacecamRect(origin: CGRect, canvas: CGSize, translation: CGSize) -> CGRect {
    let shortest = min(canvas.width, canvas.height)
    let padding = min(16, shortest * 0.1)
    let desired = origin.width + (translation.width + translation.height) / 2
    let available = min(canvas.width - origin.minX - padding, origin.maxY - padding)
    let side = max(shortest * 0.12, min(shortest * 0.5, available, desired))
    return CGRect(x: origin.minX, y: origin.maxY - side, width: side, height: side)
}


/// Peak level mapped from -60...0 dBFS to 0...1. Unlike a boosted RMS
/// indicator, this leaves visible headroom before digital overload.
func microphoneLevel(peak: Float) -> Float {
    guard peak.isFinite, peak > 0 else { return 0 }
    return max(0, min(1, (20 * log10(peak) + 60) / 60))
}

struct MicrophoneMeter {
    private var peak: Float = 0
    private var lastUpdate: Double = 0

    mutating func read(_ buffer: CMSampleBuffer, at now: Double) -> Float? {
        guard let data = buffer.dataBuffer, let format = buffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              asbd.mFormatID == kAudioFormatLinearPCM else { return nil }
        let length = CMBlockBufferGetDataLength(data)
        var bytes = [UInt8](repeating: 0, count: length)
        guard length > 0, CMBlockBufferCopyDataBytes(data, atOffset: 0, dataLength: length, destination: &bytes) == noErr else { return nil }
        bytes.withUnsafeBytes { raw in
            if asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 && asbd.mBitsPerChannel == 32 {
                for offset in stride(from: 0, to: length - 3, by: 4) {
                    let sample = raw.loadUnaligned(fromByteOffset: offset, as: Float.self)
                    if sample.isFinite { peak = max(peak, abs(sample)) }
                }
            } else if asbd.mBitsPerChannel == 16 {
                for offset in stride(from: 0, to: length - 1, by: 2) {
                    peak = max(peak, abs(Float(raw.loadUnaligned(fromByteOffset: offset, as: Int16.self))) / 32768)
                }
            }
        }
        guard now - lastUpdate >= 0.1 else { return nil }
        lastUpdate = now
        let level = microphoneLevel(peak: peak); peak = 0
        return level
    }
}
