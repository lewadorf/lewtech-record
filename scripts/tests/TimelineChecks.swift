import Foundation

func runTimelineChecks() throws -> Int {
    var timeline = RecordingTimeline()
    try verificationRequire(timeline.timestamp(for: 100) == nil, "No media timestamp before origin")
    timeline.start(at: 100)
    try verificationRequire(timeline.timestamp(for: 99) == nil, "Reject audio before video origin")
    timeline.pause(at: 105)
    try verificationRequire(timeline.timestamp(for: 107) == nil, "Drop paused audio/video")
    try verificationRequire(timeline.elapsed(at: 110) == 5, "Timer freezes during pause")
    timeline.resume(at: 115)
    try verificationRequire(timeline.timestamp(for: 116) == 6, "Remove first pause")
    timeline.pause(at: 120); timeline.pause(at: 121); timeline.resume(at: 123)
    try verificationRequire(timeline.timestamp(for: 125) == 12, "Multiple pauses share one offset")
    try verificationRequire(abs(timeline.timestamp(for: 125.02)! - 12.02) < 0.00001, "Audio remains aligned after pause")
    var late = RecordingTimeline()
    late.pause(at: 1); late.resume(at: 4); late.start(at: 5)
    try verificationRequire(late.timestamp(for: 5) == 0, "Pausing before first frame must not lose media")
    let landscape = recordingOutputSize(width: 5120, height: 2880)
    try verificationRequire(landscape.0 == 1920 && landscape.1 == 1080, "4K scaled to 1080p")
    let portrait = recordingOutputSize(width: 1001, height: 2001)
    try verificationRequire(portrait.1 == 1080 && portrait.0 % 2 == 0, "Even codec dimensions")
    try verificationRequire(abs(Double(portrait.0) / Double(portrait.1) - 1001.0 / 2001) < 0.002, "Preserve portrait aspect ratio")
    return 11
}
