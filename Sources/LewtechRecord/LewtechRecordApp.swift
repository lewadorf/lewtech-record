import SwiftUI

@main
struct LewtechRecordApp: App {
    @ObservedObject private var languageSettings = LanguageSettings.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Lewtech Record", id: "main") {
            RootView(model: model)
                .environment(\.locale, languageSettings.locale)
                .task { delegate.model = model; await RecordingDiagnostics.runIfRequested(model: model) }
        }
        .defaultSize(width: 1180, height: 780)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu(L10n.tr("Opptak")) {
                Button(L10n.tr("Start opptak")) { Task { await model.record() } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(model.capture.state != .idle || model.saving)
                Button(L10n.tr("Pause / fortsett")) {
                    if model.capture.state == .recording { model.capture.pause() }
                    else { model.capture.resume() }
                }.keyboardShortcut("p", modifiers: [.command, .shift])
                Button(L10n.tr("Stopp og lagre")) { Task { await model.finish() } }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
        MenuBarExtra("Lewtech Record", systemImage: "record.circle") {
            MenuBarControls(model: model, capture: model.capture)
        }
    }
}

private struct MenuBarControls: View {
    @ObservedObject private var languageSettings = LanguageSettings.shared
    @ObservedObject var model: AppModel
    @ObservedObject var capture: CaptureController
    var body: some View {
        Button(L10n.tr("Åpne Lewtech Record")) { model.showMainWindow() }
        Divider()
        if capture.state == .recording || capture.state == .paused {
            Text("\(capture.state == .paused ? L10n.tr("Pause") : L10n.tr("Tar opp")) · \(Int(capture.elapsed) / 60):\(String(format: "%02d", Int(capture.elapsed) % 60))")
            Button(capture.state == .paused ? L10n.tr("Fortsett") : L10n.tr("Pause")) { capture.state == .paused ? capture.resume() : capture.pause() }
            Button(L10n.tr("Stopp og lagre")) { Task { await model.finish() } }
        } else if capture.state == .idle {
            Button(L10n.tr("Start opptak")) { Task { await model.record() } }.disabled(model.saving)
        } else { Text(capture.state == .finishing ? L10n.tr("Lagrer …") : L10n.tr("Klargjør …")) }
        Divider()
        Button(L10n.tr("Avslutt Lewtech Record")) { NSApp.terminate(nil) }
    }
}
