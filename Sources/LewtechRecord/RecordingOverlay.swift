import SwiftUI
import AppKit
import AVFoundation

@MainActor
final class RecordingOverlay: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var controls: NSPanel?
    private var bubble: NSPanel?
    private var captureScreen: NSScreen?
    init(model: AppModel) { self.model = model }
    func show() {
        let screen = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue == model.capture.selectedDisplayID } ?? NSScreen.main
        captureScreen = screen
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let panel = makePanel(frame: CGRect(x: visible.midX - 156, y: visible.minY + 26, width: 312, height: 60))
        panel.contentView = NSHostingView(rootView: FloatingControls(model: model, capture: model.capture))
        panel.orderFrontRegardless(); controls = panel
        if model.capture.mode == .screenAndCamera {
            let frame = screen?.frame ?? visible
            let capture = model.capture
            let rect = facecamRect(canvas: capture.outputDimensions, position: capture.bubblePosition, scale: capture.bubbleScale)
            let scale = frame.width / capture.outputDimensions.width
            let side = rect.width * scale
            let panel = makePanel(frame: CGRect(x: frame.minX + rect.minX * scale, y: frame.minY + rect.minY * scale, width: side, height: side))
            let shape = RoundedRectangle(cornerRadius: capture.bubbleShape == .circle ? side / 2 : 0)
            panel.contentView = NSHostingView(rootView: BubblePreview(capture: capture).clipShape(shape))
            panel.delegate = self; panel.orderFrontRegardless(); bubble = panel
            // Preserve the exact composition selected before recording.
        }
    }
    private func makePanel(frame: CGRect) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true; panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        return panel
    }
    func windowDidMove(_ notification: Notification) { updatePosition() }
    private func updatePosition() {
        guard let bubble, let screen = captureScreen else { return }
        let frame = screen.frame
        model.capture.setBubblePosition(CGPoint(x: max(0, (bubble.frame.minX - frame.minX) / frame.width), y: max(0, (bubble.frame.minY - frame.minY) / frame.height)))
    }
    func close() { controls?.close(); bubble?.close(); controls = nil; bubble = nil }
}

private struct FloatingControls: View {
    @ObservedObject private var languageSettings = LanguageSettings.shared
    @ObservedObject var model: AppModel
    @ObservedObject var capture: CaptureController
    var body: some View {
        HStack(spacing: 16) {
            Circle().fill(capture.state == .paused ? LT.muted : Color(red: 0.92, green: 0.4, blue: 0.3)).frame(width: 8, height: 8)
            Text(String(format: "%02d:%02d", Int(capture.elapsed) / 60, Int(capture.elapsed) % 60))
                .font(.system(size: 15, weight: .medium, design: .monospaced)).frame(width: 65)
            Rectangle().fill(.white.opacity(0.2)).frame(width: 1, height: 22)
            Button { capture.state == .paused ? capture.resume() : capture.pause() } label: {
                Image(systemName: capture.state == .paused ? "play.fill" : "pause.fill").frame(width: 24, height: 30)
            }.help(capture.state == .paused ? L10n.tr("Fortsett opptaket") : L10n.tr("Pause opptaket"))
            Button { Task { await model.finish() } } label: {
                Image(systemName: "stop.fill").frame(width: 30, height: 30).background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }.help(L10n.tr("Stopp og lagre"))
            Button { model.showMainWindow() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 22, height: 30) }.help(L10n.tr("Åpne opptaksstudioet"))
        }
        .buttonStyle(.plain).foregroundStyle(.white)
        .padding(.horizontal, 20).frame(height: 56)
        .background(LT.ink, in: RoundedRectangle(cornerRadius: 18))
        .padding(2)
    }
}

private struct BubblePreview: View {
    @ObservedObject private var languageSettings = LanguageSettings.shared
    @ObservedObject var capture: CaptureController
    var body: some View {
        if let image = capture.cameraPreview { CapturePreview(image: image) }
        else { LT.ink }
    }
}
