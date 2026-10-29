import SwiftUI

@main
struct LewtechRecordApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Lewtech Record", id: "main") {
            RootView(model: model)
                .task { delegate.model = model; await RecordingDiagnostics.runIfRequested(model: model) }
        }
        .defaultSize(width: 1180, height: 780)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Opptak") {
                Button("Start opptak") { Task { await model.record() } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(model.capture.state != .idle || model.saving)
                Button("Pause / fortsett") {
                    if model.capture.state == .recording { model.capture.pause() }
                    else { model.capture.resume() }
                }.keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Stopp og lagre") { Task { await model.finish() } }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
        MenuBarExtra("Lewtech Record", systemImage: "record.circle") {
            MenuBarControls(model: model, capture: model.capture)
        }
    }
}

private struct MenuBarControls: View {
    @ObservedObject var model: AppModel
    @ObservedObject var capture: CaptureController
    var body: some View {
        Button("Åpne Lewtech Record") { model.showMainWindow() }
        Divider()
        if capture.state == .recording || capture.state == .paused {
            Text("\(capture.state == .paused ? "Pause" : "Tar opp") · \(Int(capture.elapsed) / 60):\(String(format: "%02d", Int(capture.elapsed) % 60))")
            Button(capture.state == .paused ? "Fortsett" : "Pause") { capture.state == .paused ? capture.resume() : capture.pause() }
            Button("Stopp og lagre") { Task { await model.finish() } }
        } else if capture.state == .idle {
            Button("Start opptak") { Task { await model.record() } }.disabled(model.saving)
        } else { Text(capture.state == .finishing ? "Lagrer …" : "Klargjør …") }
        Divider()
        Button("Avslutt Lewtech Record") { NSApp.terminate(nil) }
    }
}
