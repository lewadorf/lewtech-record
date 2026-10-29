import AppKit
@preconcurrency import AVFoundation
import ScreenCaptureKit
import Combine

@MainActor
final class CaptureController: NSObject, ObservableObject, SCStreamDelegate {
    @Published var state: RecordingState = .idle
    @Published var mode: CaptureMode = .screenAndCamera
    @Published var displays: [DisplayChoice] = []
    @Published var windows: [WindowChoice] = []
    @Published var cameras: [DeviceChoice] = []
    @Published var microphones: [DeviceChoice] = []
    @Published var selectedDisplayID = ""
    @Published var selectedWindowID = ""
    @Published var cameraID = ""
    @Published var microphoneID = ""
    @Published var microphoneEnabled = true
    @Published var elapsed: TimeInterval = 0
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var audioLevel: Float = 0
    @Published var countdown: Int?
    @Published var cameraPreview: CGImage?
    @Published var bubbleShape: FacecamShape = .circle
    @Published var bubbleScale: CGFloat = 0.24
    @Published var outputDimensions = CGSize(width: 1920, height: 1080)
    @Published var needsScreenAccess = false
    @Published var bubblePosition = CGPoint(x: 0.04, y: 0.06)
    @Published var screenPreview: CGImage?
    @Published var previewMessage: String?
    private var livePreview: LivePreview?
    private var previewTask: Task<Void, Never>?
    private var previewGeneration = UUID()

    var previewKey: String {
        [mode.rawValue, selectedDisplayID, selectedWindowID, cameraID, microphoneID,
         String(microphoneEnabled), String(describing: state)].joined(separator: "|")
    }

    func updatePreview(visible: Bool) {
        let generation = UUID(); previewGeneration = generation
        let previous = previewTask
        previous?.cancel()
        // Clear immediately: never label the old source's image as the new one.
        if state == .idle { screenPreview = nil; cameraPreview = nil; audioLevel = 0 }
        previewTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await self.livePreview?.stop(); self.livePreview = nil
            guard !Task.isCancelled, visible, self.state == .idle else { return }
            do {
                try await Task.sleep(nanoseconds: 180_000_000)
                await self.beginPreview(generation)
            } catch { }
        }
    }

    private func stopPreview() async {
        updatePreview(visible: false)
        await previewTask?.value
        screenPreview = nil; cameraPreview = nil; audioLevel = 0; previewMessage = nil
    }

    private func beginPreview(_ generation: UUID) async {
        let preview = LivePreview(); livePreview = preview
        previewMessage = L10n.tr("Starter forhåndsvisning …")
        statusMessage = nil; needsScreenAccess = false
        if mode == .camera { outputDimensions = CGSize(width: 1920, height: 1080) }
        func current() -> Bool { previewGeneration == generation && state == .idle && !Task.isCancelled }
        preview.frames.screen = { [weak self] image in Task { @MainActor in
            guard let self, self.previewGeneration == generation, self.state == .idle else { return }
            self.screenPreview = image
        } }
        preview.frames.camera = { [weak self] image in Task { @MainActor in
            guard let self, self.previewGeneration == generation, self.state == .idle else { return }
            self.cameraPreview = image
        } }
        preview.frames.level = { [weak self] value in Task { @MainActor in
            guard let self, self.previewGeneration == generation, self.state == .idle else { return }
            self.audioLevel = value
        } }
        preview.onFailure = { [weak self] message in
            guard let self, self.previewGeneration == generation else { return }
            self.screenPreview = nil; self.previewMessage = message
        }
        var failures: [String] = []
        if mode != .camera {
            do {
                try await updateScreenSources()
                guard current() else { return }
                let (filter, size) = try screenSelection()
                try await preview.startScreen(filter: filter, size: size)
            } catch {
                needsScreenAccess = true
                failures.append(L10n.tr("Skjermbildet er ikke tilgjengelig. Åpne skjermtilgang og slå på Lewtech Record. Hvis den allerede er på, avslutt og åpne appen igjen etter at du har gitt tilgang. macOS: \(error.localizedDescription)"))
            }
        }
        guard current() else { return }
        var video: String?; var audio: String?
        if mode != .screen {
            do { try await requestPermission(.video, label: L10n.tr("kamera")); video = cameraID }
            catch { failures.append(error.localizedDescription) }
        }
        guard current() else { return }
        if microphoneEnabled {
            do { try await requestPermission(.audio, label: L10n.tr("mikrofon")); audio = microphoneID }
            catch { failures.append(error.localizedDescription) }
        }
        guard current() else { return }
        do { try await preview.startDevices(cameraID: video, microphoneID: audio) }
        catch { failures.append(error.localizedDescription) }
        guard current() else { return }
        previewMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    private func screenSelection() throws -> (SCContentFilter, (Int, Int)) {
        guard let content else { throw CaptureFailure.message(L10n.tr("Ingen skjermkilde er tilgjengelig.")) }
        if !selectedWindowID.isEmpty {
            guard let window = content.windows.first(where: { String($0.windowID) == selectedWindowID }) else { throw CaptureFailure.message(L10n.tr("Vinduet er lukket. Velg et nytt vindu.")) }
            let size = recordingOutputSize(width: window.frame.width * 2, height: window.frame.height * 2)
            outputDimensions = CGSize(width: size.0, height: size.1)
            return (SCContentFilter(desktopIndependentWindow: window), size)
        }
        guard let display = content.displays.first(where: { String($0.displayID) == selectedDisplayID }) else { throw CaptureFailure.message(L10n.tr("Velg en skjerm før du starter.")) }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let size = recordingOutputSize(width: Double(display.width) * 2, height: Double(display.height) * 2)
        outputDimensions = CGSize(width: size.0, height: size.1)
        return (SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: []), size)
    }
    var onUnexpectedStop: (() -> Void)?
    var onRecordingStarted: (() -> Void)?
    private var content: SCShareableContent?
    private var stream: SCStream?
    private var session: AVCaptureSession?
    private var pipeline: RecordingPipeline?
    private var timer: Timer?
    private var preparationID = UUID()
    private var observations: [NSObjectProtocol] = []
    private let sessionQueue = DispatchQueue(label: "no.lewtech.record.devices", qos: .userInitiated)
    var recordingDirectory = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("Lewtech Record/.incomplete", isDirectory: true)
    private var preparationFailure: String?
    private var recordingActivity: NSObjectProtocol?

    override init() {
        super.init()
        observations.append(NotificationCenter.default.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main) { [weak self] note in
            guard let device = note.object as? AVCaptureDevice else { return }
            Task { @MainActor in
                guard let self, self.state == .recording || self.state == .paused || self.state == .preparing else { return }
                if device.uniqueID == self.cameraID && self.mode != .screen || device.uniqueID == self.microphoneID && self.microphoneEnabled {
                    self.handleSourceFailure(L10n.tr("\(device.localizedName) ble koblet fra. Opptaket avsluttes."))
                }
            }
        })
        observations.append(NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: nil, queue: .main) { [weak self] note in
            let sourceSession = note.object as? AVCaptureSession
            let description = (note.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription ?? L10n.tr("Kameraet eller mikrofonen ble avbrutt.")
            Task { @MainActor in
                guard let self, let sourceSession, self.session === sourceSession else { return }
                self.handleSourceFailure(description)
            }
        })
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observations.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.handleSourceFailure(L10n.tr("Mac-en gikk i hvile eller byttet brukerøkt. Opptaket avsluttes og lagres.")) }
            })
        }
    }

    func refreshSources() async {
        guard state == .idle else { return }
        let cameraDevices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera], mediaType: .video, position: .unspecified).devices
        let micDevices = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
        cameras = cameraDevices.map { DeviceChoice(id: $0.uniqueID, title: $0.localizedName) }
        microphones = micDevices.map { DeviceChoice(id: $0.uniqueID, title: $0.localizedName) }
        if !cameras.contains(where: { $0.id == cameraID }) { cameraID = cameras.first?.id ?? "" }
        if !microphones.contains(where: { $0.id == microphoneID }) { microphoneID = AVCaptureDevice.default(for: .audio)?.uniqueID ?? microphones.first?.id ?? "" }
        // Listing device names is permission-free. Screen content is queried only
        // after the user grants recording access, avoiding prompts on launch.
        if CGPreflightScreenCaptureAccess() {
            do { try await updateScreenSources() } catch { errorMessage = error.localizedDescription }
        } else {
            displays = NSScreen.screens.compactMap { screen in
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
                return DisplayChoice(id: number.stringValue, title: screen.localizedName)
            }
            if selectedDisplayID.isEmpty { selectedDisplayID = displays.first?.id ?? "" }
            statusMessage = nil
        }
    }

    private func updateScreenSources() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        self.content = content
        displays = content.displays.map { display in
            let screen = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID }
            return DisplayChoice(id: String(display.displayID), title: screen?.localizedName ?? L10n.tr("Skjerm \(display.displayID)"))
        }
        windows = content.windows.filter { $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier && $0.windowLayer == 0 && !($0.title ?? "").isEmpty && $0.frame.width > 100 && $0.frame.height > 100 }.map {
            WindowChoice(id: String($0.windowID), title: "\($0.owningApplication?.applicationName ?? L10n.tr("App")) — \($0.title ?? L10n.tr("Vindu"))")
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        if selectedDisplayID.isEmpty { selectedDisplayID = displays.first?.id ?? "" }
        else if !displays.contains(where: { $0.id == selectedDisplayID }) {
            displays.append(DisplayChoice(id: selectedDisplayID, title: L10n.tr("Skjermen er frakoblet – velg en ny")))
        }
        // Never silently expand a closed-window selection to the entire display.
        if !selectedWindowID.isEmpty && !windows.contains(where: { $0.id == selectedWindowID }) {
            windows.append(WindowChoice(id: selectedWindowID, title: L10n.tr("Vinduet er lukket – velg en ny kilde")))
        }
    }

    func start() async {
        guard state == .idle else { return }
        state = .preparing; errorMessage = nil; statusMessage = nil; elapsed = 0; preparationFailure = nil
        let operation = UUID(); preparationID = operation
        await stopPreview()
        guard preparationID == operation, state == .preparing else { return }
        do {
            if mode != .camera {
                statusMessage = L10n.tr("Henter tilgjengelige skjermer og vinduer …")
                try await updateScreenSources()
                guard preparationID == operation, state == .preparing else { return }
            }
            if mode != .screen { statusMessage = L10n.tr("Kontrollerer kameratilgang …"); try await requestPermission(.video, label: L10n.tr("kamera")) }
            guard preparationID == operation, state == .preparing else { return }
            if microphoneEnabled { statusMessage = L10n.tr("Kontrollerer mikrofontilgang …"); try await requestPermission(.audio, label: L10n.tr("mikrofon")) }
            try Task.checkCancellation()
            guard preparationID == operation, state == .preparing else { return }
            let tempDirectory = recordingDirectory
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            if let available = try tempDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
               available < 500_000_000 { throw CaptureFailure.message(L10n.tr("Du trenger minst 500 MB ledig plass for å starte opptaket.")) }
            let url = tempDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
            var filter: SCContentFilter?
            var size = (1920, 1080)
            if mode != .camera {
                let selection = try screenSelection()
                filter = selection.0; size = selection.1
            }
            let pipeline = try RecordingPipeline(url: url, width: size.0, height: size.1, mode: mode, microphone: microphoneEnabled)
            self.pipeline = pipeline
            pipeline.setFacecam(shape: bubbleShape, scale: bubbleScale, position: bubblePosition)
            statusMessage = L10n.tr("Klargjør kamera og mikrofon …")
            pipeline.onLevel = { [weak self] value in Task { @MainActor in self?.audioLevel = value } }
            pipeline.onCameraPreview = { [weak self, weak pipeline] image in
                Task { @MainActor in
                    guard let self, let pipeline, self.pipeline === pipeline,
                          self.state == .preparing || self.state == .recording || self.state == .paused else { return }
                    self.cameraPreview = image
                }
            }
            pipeline.onScreenPreview = { [weak self, weak pipeline] image in
                Task { @MainActor in
                    guard let self, let pipeline, self.pipeline === pipeline else { return }
                    self.screenPreview = image
                }
            }
            pipeline.onFailure = { [weak self, weak pipeline] message in
                Task { @MainActor in
                    guard let self, let pipeline, self.pipeline === pipeline else { return }
                    self.errorMessage = message; self.onUnexpectedStop?()
                }
            }
            try await prepareDevices(pipeline)
            try Task.checkCancellation()
            guard preparationID == operation, state == .preparing else { return }
            if let filter {
                let config = SCStreamConfiguration()
                config.width = size.0; config.height = size.1
                config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                config.queueDepth = 5; config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = true; config.capturesAudio = false
                config.backgroundColor = CGColor.black
                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                try stream.addStreamOutput(pipeline, type: .screen, sampleHandlerQueue: pipeline.queue)
                self.stream = stream
                try await stream.startCapture()
            }
            for value in stride(from: 3, through: 1, by: -1) {
                if let preparationFailure { throw CaptureFailure.message(preparationFailure) }
                guard preparationID == operation, state == .preparing else { return }
                countdown = value
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
            if let preparationFailure { throw CaptureFailure.message(preparationFailure) }
            guard preparationID == operation, state == .preparing else { return }
            countdown = nil; statusMessage = nil; pipeline.begin(); state = .recording
            recordingActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: L10n.tr("Lagrer et skjerm- eller kameraopptak"))
            onRecordingStarted?()
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor in guard let self else { return }; self.elapsed = self.pipeline?.duration ?? 0 }
            }
            // Avoid showing success indefinitely when a source never delivers frames.
            Task { @MainActor [weak self, weak pipeline] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, self.state == .recording, let pipeline, !pipeline.hasFrames else { return }
                self.errorMessage = L10n.tr("Ingen bilder mottas fra valgt kilde. Kontroller kamera og skjermtilgang.")
                self.onUnexpectedStop?()
            }
        } catch {
            // cancel() owns resources of invalidated generations. An old
            // permission/countdown task must never clean up a newer recording.
            guard preparationID == operation else { return }
            if !(error is CancellationError) { errorMessage = error.localizedDescription }
            state = .finishing
            await cleanUp(discard: true); state = .idle; countdown = nil
        }
    }

    private func requestPermission(_ mediaType: AVMediaType, label: String) async throws {
        let status = AVCaptureDevice.authorizationStatus(for: mediaType)
        if status == .authorized { return }
        if status == .notDetermined, await AVCaptureDevice.requestAccess(for: mediaType) { return }
        throw CaptureFailure.message(L10n.tr("Gi Lewtech Record tilgang til \(label) i Systeminnstillinger → Personvern og sikkerhet, og prøv igjen."))
    }

    private func prepareDevices(_ pipeline: RecordingPipeline) async throws {
        guard mode != .screen || microphoneEnabled else { return }
        let captureSession = AVCaptureSession()
        captureSession.beginConfiguration(); captureSession.sessionPreset = .high
        if mode != .screen {
            guard let device = AVCaptureDevice(uniqueID: cameraID) else { throw CaptureFailure.message(L10n.tr("Velg et tilgjengelig kamera, eller bytt til Kun skjerm.")) }
            let input = try AVCaptureDeviceInput(device: device)
            guard captureSession.canAddInput(input) else { throw CaptureFailure.message(L10n.tr("Kameraet kan ikke åpnes. Kontroller om en annen app bruker det.")) }
            captureSession.addInput(input)
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(pipeline, queue: pipeline.queue)
            guard captureSession.canAddOutput(output) else { throw CaptureFailure.message(L10n.tr("Kamerabildet kunne ikke klargjøres.")) }
            captureSession.addOutput(output)
        }
        if microphoneEnabled {
            guard let device = AVCaptureDevice(uniqueID: microphoneID) else { throw CaptureFailure.message(L10n.tr("Velg en tilgjengelig mikrofon, eller slå av mikrofonen.")) }
            let input = try AVCaptureDeviceInput(device: device)
            guard captureSession.canAddInput(input) else { throw CaptureFailure.message(L10n.tr("Mikrofonen kunne ikke åpnes.")) }
            captureSession.addInput(input)
            let output = AVCaptureAudioDataOutput()
            output.setSampleBufferDelegate(pipeline, queue: pipeline.queue)
            guard captureSession.canAddOutput(output) else { throw CaptureFailure.message(L10n.tr("Mikrofonsporet kunne ikke klargjøres.")) }
            captureSession.addOutput(output)
        }
        captureSession.commitConfiguration()
        session = captureSession
        await withCheckedContinuation { continuation in sessionQueue.async { captureSession.startRunning(); continuation.resume() } }
        pipeline.setAudioClock(captureSession.synchronizationClock)
        guard captureSession.isRunning else { throw CaptureFailure.message(L10n.tr("Kamera eller mikrofon kunne ikke startes.")) }
    }

    func pause() { guard state == .recording else { return }; pipeline?.pause(); state = .paused }
    func resume() { guard state == .paused else { return }; pipeline?.resume(); state = .recording }

    func stop() async throws -> RecordingResult? {
        guard state == .recording || state == .paused else { return nil }
        state = .finishing; timer?.invalidate(); timer = nil
        endRecordingActivity()
        pipeline?.seal()
        await stopSources()
        guard let pipeline else { state = .idle; return nil }
        do {
            let result = try await pipeline.finish()
            self.pipeline = nil; state = .idle; audioLevel = 0
            return result
        } catch {
            // Retain incomplete files for inspection/recovery instead of deleting
            // potentially usable fragments after an unexpected write failure.
            self.pipeline = nil; state = .idle; audioLevel = 0
            throw error
        }
    }
    func cancel() async {
        guard state == .preparing || state == .recording || state == .paused else { return }
        preparationID = UUID()
        state = .finishing
        await cleanUp(discard: true)
        state = .idle; elapsed = 0; countdown = nil; statusMessage = L10n.tr("Opptaket ble forkastet.")
    }
    private func cleanUp(discard: Bool) async {
        timer?.invalidate(); timer = nil
        endRecordingActivity()
        let retiringPipeline = pipeline
        pipeline = nil
        await stopSources()
        if discard { await retiringPipeline?.discard() }
        audioLevel = 0
    }
    private func stopSources() async {
        let retiringStream = stream
        let retiringSession = session
        stream = nil; session = nil; cameraPreview = nil; screenPreview = nil
        if let retiringStream { try? await retiringStream.stopCapture() }
        if let session = retiringSession {
            await withCheckedContinuation { continuation in sessionQueue.async { session.stopRunning(); continuation.resume() } }
        }
    }
    func setBubblePosition(_ position: CGPoint) { bubblePosition = position; pipeline?.setBubblePosition(position) }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            guard self.stream === stream else { return }
            self.handleSourceFailure(L10n.tr("Skjermopptaket ble avbrutt: \(error.localizedDescription)"))
        }
    }
    private func handleSourceFailure(_ message: String) {
        if state == .preparing { preparationFailure = message }
        else if state == .recording || state == .paused { errorMessage = message; onUnexpectedStop?() }
    }
    private func endRecordingActivity() {
        if let recordingActivity { ProcessInfo.processInfo.endActivity(recordingActivity); self.recordingActivity = nil }
    }
    func openPrivacySettings(_ kind: String) {
        let anchor = kind == "camera" ? "Privacy_Camera" : kind == "microphone" ? "Privacy_Microphone" : "Privacy_ScreenCapture"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") { NSWorkspace.shared.open(url) }
    }
}
