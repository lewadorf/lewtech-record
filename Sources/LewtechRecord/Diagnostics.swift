import Foundation
import AVFoundation
import AppKit

/// Explicit local verification mode. Never runs during normal app use.
/// Launch with --verify-recording SECONDS --report /absolute/report.json.
@MainActor
enum RecordingDiagnostics {
    private static var started = false
    static func runIfRequested(model: AppModel) async {
        let args = ProcessInfo.processInfo.arguments
        guard !started, let index = args.firstIndex(of: "--verify-recording"), args.indices.contains(index + 1),
              let seconds = Double(args[index + 1]), seconds >= 3,
              let reportIndex = args.firstIndex(of: "--report"), args.indices.contains(reportIndex + 1) else { return }
        started = true
        let reportURL = URL(fileURLWithPath: args[reportIndex + 1])
        var report: [String: Any] = ["kind": "real-hardware-recording", "requestedActiveSeconds": seconds, "startedAt": ISO8601DateFormatter().string(from: Date()), "status": "preparing"]
        func write() {
            try? FileManager.default.createDirectory(at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: reportURL, options: .atomic) }
        }
        await model.capture.refreshSources()
        let capture = model.capture
        if let modeIndex = args.firstIndex(of: "--verify-mode"), args.indices.contains(modeIndex + 1), let mode = CaptureMode(rawValue: args[modeIndex + 1]) { capture.mode = mode }
        if args.contains("--no-mic") { capture.microphoneEnabled = false }
        if let micIndex = args.firstIndex(of: "--verify-mic"), args.indices.contains(micIndex + 1) {
            let query = args[micIndex + 1]
            if let mic = capture.microphones.first(where: { $0.id == query || $0.title.localizedCaseInsensitiveContains(query) }) { capture.microphoneID = mic.id }
        }
        if let windowIndex = args.firstIndex(of: "--verify-window"), args.indices.contains(windowIndex + 1) {
            let query = args[windowIndex + 1]
            if let window = capture.windows.first(where: { $0.id == query || $0.title.localizedCaseInsensitiveContains(query) }) { capture.selectedWindowID = window.id }
            else { report["status"] = "failed"; report["error"] = "Requested window not found"; write(); return }
        }
        report["mode"] = capture.mode.rawValue
        report["microphoneEnabled"] = capture.microphoneEnabled
        report["cameras"] = capture.cameras.map { ["id": $0.id, "title": $0.title] }
        report["microphones"] = capture.microphones.map { ["id": $0.id, "title": $0.title] }
        report["selectedMicrophone"] = capture.microphoneID
        write()
        await model.record()
        guard capture.state == .recording else { report["status"] = "failed"; report["error"] = capture.errorMessage ?? "Recording did not start"; write(); return }
        let begin = Date()
        report["status"] = "recording"; write()
        var pauses = 0
        var nextProgress = 10.0
        while capture.elapsed < seconds && (capture.state == .recording || capture.state == .paused) {
            if (pauses == 0 && capture.elapsed >= min(10, seconds / 3)) || (pauses == 1 && capture.elapsed >= seconds * 0.65) {
                capture.pause(); report["status"] = "paused"; report["elapsed"] = capture.elapsed; write()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                capture.resume(); pauses += 1
            }
            if capture.elapsed >= nextProgress { report["status"] = "recording"; report["elapsed"] = capture.elapsed; write(); nextProgress += 10 }
            if Date().timeIntervalSince(begin) > seconds + 35 { report["timeout"] = true; break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        report["wallSeconds"] = Date().timeIntervalSince(begin)
        report["elapsedBeforeStop"] = capture.elapsed
        report["pauseCycles"] = pauses
        await model.finish()
        if let error = capture.errorMessage { report["error"] = error }
        guard let item = model.library.items.first else { report["status"] = "failed"; report["error"] = capture.errorMessage ?? model.library.errorMessage ?? "No recording in library"; write(); return }
        let url = model.library.url(for: item)
        report["file"] = url.path
        do {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            let video = try await asset.loadTracks(withMediaType: .video)
            let audio = try await asset.loadTracks(withMediaType: .audio)
            report["duration"] = duration; report["videoTracks"] = video.count; report["audioTracks"] = audio.count
            if let track = video.first {
                let size = try await track.load(.naturalSize)
                report["width"] = size.width; report["height"] = size.height
                report["nominalFrameRate"] = try await track.load(.nominalFrameRate)
            }
            if let audioTrack = audio.first { report["audioTimeRangeDuration"] = try await audioTrack.load(.timeRange).duration.seconds }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            var frames: [String] = []
            for (number, second) in [min(0.5, duration / 3), duration / 2, max(0, duration - 0.5)].enumerated() {
                let frame = try await generator.image(at: CMTime(seconds: second, preferredTimescale: 600))
                let destination = reportURL.deletingLastPathComponent().appendingPathComponent("\(reportURL.deletingPathExtension().lastPathComponent)-frame-\(number).png")
                if let data = NSBitmapImageRep(cgImage: frame.image).representation(using: .png, properties: [:]) { try data.write(to: destination); frames.append(destination.path) }
            }
            report["decodedFrames"] = frames
            let durationOK = abs(duration - seconds) < 1.5
            let tracksOK = !video.isEmpty && (!capture.microphoneEnabled || !audio.isEmpty)
            report["status"] = durationOK && tracksOK && capture.errorMessage == nil ? "passed" : "failed"
            report["durationWithinTolerance"] = durationOK
            report["note"] = "Structural verification with real capture. Decoded frames and microphone audio still require visual/listening inspection."
        } catch { report["status"] = "failed"; report["error"] = error.localizedDescription }
        write()
    }
}
