import Foundation
import AVFoundation
import AppKit

@main
struct InspectVideo {
    static func main() async throws {
        guard CommandLine.arguments.count == 3 else {
            print("Usage: inspect-video /absolute/video.mp4 /absolute/report-directory")
            return
        }
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let destination = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let asset = AVURLAsset(url: input)
        let duration = try await asset.load(.duration).seconds
        var report: [String: Any] = ["file": input.path, "duration": duration, "playable": try await asset.load(.isPlayable)]
        var tracks: [[String: Any]] = []
        for track in try await asset.load(.tracks) {
            let range = try await track.load(.timeRange)
            let size = try await track.load(.naturalSize)
            tracks.append(["mediaType": track.mediaType.rawValue, "start": range.start.seconds, "duration": range.duration.seconds, "width": size.width, "height": size.height, "fps": try await track.load(.nominalFrameRate)])
        }
        report["tracks"] = tracks
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 800)
        var frames: [String] = []
        for (index, second) in [min(1, duration / 4), duration / 2, max(0, duration - 1)].enumerated() {
            let frame = try await generator.image(at: CMTime(seconds: second, preferredTimescale: 600))
            let url = destination.appendingPathComponent("frame-\(index).png")
            if let data = NSBitmapImageRep(cgImage: frame.image).representation(using: .png, properties: [:]) { try data.write(to: url); frames.append(url.path) }
        }
        report["decodedFrames"] = frames
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: destination.appendingPathComponent("report.json"), options: .atomic)
        print(String(decoding: data, as: UTF8.self))
    }
}
