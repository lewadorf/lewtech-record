import SwiftUI
import AppKit
import Combine

@MainActor
final class AppModel: ObservableObject {
    let capture = CaptureController()
    let library: LibraryStore
    @Published var saving = false
    private var overlay: RecordingOverlay?
    private var captureChanges: AnyCancellable?

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--library"), arguments.indices.contains(index + 1) {
            library = LibraryStore(directory: URL(fileURLWithPath: arguments[index + 1], isDirectory: true))
        } else { library = LibraryStore() }
        capture.recordingDirectory = library.directory.appendingPathComponent(".incomplete", isDirectory: true)
        Task { await library.recoverInterruptedRecordings() }
        capture.onUnexpectedStop = { [weak self] in Task { await self?.finish() } }
        captureChanges = capture.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        capture.onRecordingStarted = { [weak self] in
            guard let self else { return }
            self.overlay = RecordingOverlay(model: self)
            self.overlay?.show()
        }
    }
    func record() async {
        guard !saving else { return }
        await capture.start()
    }
    func finish() async {
        guard !saving, capture.state == .recording || capture.state == .paused else { return }
        saving = true; overlay?.close(); overlay = nil
        defer { saving = false }
        do {
            if let result = try await capture.stop() {
                try await library.addRecording(fileURL: result.url, duration: result.duration)
                capture.statusMessage = L10n.tr("Opptaket er lagret i videobiblioteket.")
                showMainWindow()
            }
        } catch {
            capture.errorMessage = error.localizedDescription
            library.errorMessage = library.errorMessage ?? L10n.tr("Opptaket kunne ikke legges til: \(error.localizedDescription) Eventuelle videodata ligger i .incomplete-mappen i biblioteket.")
            showMainWindow()
        }
    }
    func cancel() async {
        guard !saving else { return }
        overlay?.close(); overlay = nil; await capture.cancel()
    }
    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "Lewtech Record" })?.makeKeyAndOrderFront(nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        if model.saving || model.capture.state == .finishing { return .terminateCancel }
        guard model.capture.state != .idle else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = L10n.tr("Et opptak pågår")
        alert.informativeText = L10n.tr("Lagre opptaket før du avslutter Lewtech Record?")
        alert.addButton(withTitle: L10n.tr("Lagre og avslutt"))
        alert.addButton(withTitle: L10n.tr("Fortsett"))
        alert.addButton(withTitle: L10n.tr("Forkast og avslutt"))
        let answer = alert.runModal()
        if answer == .alertSecondButtonReturn { return .terminateCancel }
        Task { @MainActor in
            if answer == .alertFirstButtonReturn && (model.capture.state == .recording || model.capture.state == .paused) {
                await model.finish()
                // A failed save must remain visible; don't exit over an error.
                NSApp.reply(toApplicationShouldTerminate: model.capture.errorMessage == nil)
            } else { await model.cancel(); NSApp.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model?.showMainWindow(); return true
    }
}
