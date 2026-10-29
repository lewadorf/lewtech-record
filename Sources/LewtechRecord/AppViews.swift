import SwiftUI
import AppKit
import AVFoundation

private enum WorkspaceSection: String {
    case library, record, settings
}

struct RootView: View {
    @ObservedObject private var languageSettings = LanguageSettings.shared
    @ObservedObject var model: AppModel
    @ObservedObject private var capture: CaptureController
    @State private var section: WorkspaceSection = .library

    init(model: AppModel) {
        self.model = model
        self.capture = model.capture
        LT.registerFonts()
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(LT.border).frame(width: 1)
            Group {
                switch section {
                case .library:
                    LibraryView(store: model.library, onNew: { section = .record })
                case .record:
                    RecordingSetupView(model: model, capture: capture)
                case .settings:
                    LocalSettingsView(capture: capture, directory: model.library.directory)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LT.paper)
        }
        .frame(minWidth: 960, minHeight: 650)
        .font(LT.font(13))
        .foregroundStyle(LT.ink)
        .tint(LT.ink)
        .preferredColorScheme(.light)
        .task { await capture.refreshSources() }
        .onChange(of: capture.state) { _, new in
            // Menu-bar and keyboard recording commands must expose setup,
            // permission errors and the countdown even from the library.
            if new == .preparing { section = .record }
        }
        .onChange(of: model.saving) { old, new in
            // Capture finishing precedes library import. Only leave the studio
            // once the durable file and metadata have both been saved.
            if old && !new && capture.state == .idle && capture.errorMessage == nil {
                section = .library
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                LewtechWordmark()
                Text(L10n.tr("RECORD")).font(LT.font(10, weight: .semibold))
                    .tracking(3).foregroundStyle(LT.secondary)
                    .padding(.leading, 9)
            }
            .padding(.top, 21).padding(.bottom, 29)

            Button { section = .record } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                    Text(L10n.tr("Nytt opptak"))
                    Spacer()
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut("n", modifiers: [.command])
            .padding(.bottom, 28)

            Text(L10n.tr("ARBEIDSOMRÅDE"))
                .font(LT.font(9, weight: .semibold)).tracking(1.4)
                .foregroundStyle(LT.secondary).padding(.horizontal, 12).padding(.bottom, 10)
            navigationItem(L10n.tr("Videobibliotek"), symbol: "rectangle.stack", section: .library)
            navigationItem(L10n.tr("Opptaksstudio"), symbol: "record.circle", section: .record)

            Spacer(minLength: 24)

            if capture.state == .recording || capture.state == .paused {
                Button { section = .record } label: {
                    HStack(spacing: 10) {
                        Circle().fill(capture.state == .paused ? LT.accent : Color.red.opacity(0.8)).frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(capture.state == .paused ? L10n.tr("Opptak på pause") : L10n.tr("Tar opp"))
                                .font(LT.font(11, weight: .semibold))
                            Text(recordingTime(capture.elapsed))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 10))
                    }
                    .padding(12).background(LT.paper, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain).padding(.bottom, 14)
            }

            navigationItem(L10n.tr("Innstillinger"), symbol: "slider.horizontal.3", section: .settings)
            Rectangle().fill(LT.border).frame(height: 1).padding(.vertical, 19)
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "internaldrive").font(.system(size: 14)).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("Bare på denne Mac-en"))
                        .font(LT.font(10, weight: .medium))
                    Text(L10n.tr("Digitalt, med omtanke."))
                        .font(LT.font(10)).foregroundStyle(LT.secondary)
                }
            }
            .padding(.horizontal, 9).padding(.bottom, 22)
        }
        .padding(.horizontal, 19)
        .frame(width: 218)
        .background(LT.surface)
    }

    private func navigationItem(_ title: String, symbol: String, section target: WorkspaceSection) -> some View {
        Button { section = target } label: {
            HStack(spacing: 11) {
                Image(systemName: symbol).font(.system(size: 15, weight: .regular)).frame(width: 19)
                Text(title).font(LT.font(12, weight: section == target ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
            .background(section == target ? LT.paper : Color.clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).padding(.bottom, 4)
        .accessibilityAddTraits(section == target ? .isSelected : [])
    }
}

private struct RecordingSetupView: View {
    @ObservedObject private var languageSettings = LanguageSettings.shared
    @ObservedObject var model: AppModel
    @ObservedObject var capture: CaptureController
    @State private var confirmCancel = false

    private var isIdle: Bool { capture.state == .idle && !model.saving }
    private var isCapturing: Bool { capture.state == .recording || capture.state == .paused }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(L10n.tr("OPPTAKSSTUDIO")).font(LT.font(10, weight: .semibold)).tracking(1.6).foregroundStyle(LT.secondary)
                        Text(isCapturing ? L10n.tr("Du har ordet.") : L10n.tr("Vis det. Fortell det."))
                            .font(LT.font(29, weight: .medium)).tracking(-1)
                        Text(isCapturing ? L10n.tr("Ta den tiden du trenger. Videoen lagres lokalt når du stopper.") : L10n.tr("Velg hva du vil ta opp. Vi tar vare på resten, lokalt."))
                            .font(LT.font(12)).foregroundStyle(LT.secondary)
                    }
                    Spacer(minLength: 12)
                    Label(L10n.tr("LOKALT"), systemImage: "lock")
                        .font(LT.font(9, weight: .semibold)).tracking(0.7)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(LT.ink.opacity(0.06), in: Capsule())
                }

                if let error = capture.errorMessage {
                    InlineNotice(message: error, isError: true)
                }
                if let message = capture.statusMessage, !message.isEmpty, capture.errorMessage == nil {
                    InlineNotice(message: message, isError: false)
                }

                if isIdle, let message = capture.previewMessage {
                    InlineNotice(message: message, isError: false)
                    if capture.needsScreenAccess {
                        Button(L10n.tr("Åpne skjermtilgang i macOS")) { capture.openPrivacySettings("screen") }
                            .buttonStyle(QuietButtonStyle())
                    }
                    Button(L10n.tr("Prøv forhåndsvisning igjen")) { capture.updatePreview(visible: true) }
                        .buttonStyle(.plain)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        preview.frame(minWidth: 300, maxWidth: .infinity)
                        controls.frame(width: 270)
                    }
                    VStack(spacing: 24) {
                        preview
                        controls
                    }
                }

                if isCapturing || capture.state == .preparing || capture.state == .finishing || model.saving {
                    activeControls
                } else {
                    HStack(spacing: 16) {
                        Button {
                            Task { await model.record() }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "record.circle")
                                Text(L10n.tr("Start opptak"))
                                Image(systemName: "arrow.right").font(.system(size: 12))
                            }.frame(minWidth: 155)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!isIdle)
                        .keyboardShortcut("r", modifiers: [.command, .shift])

                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.tr("Tre sekunder til å gjøre deg klar"))
                                .font(LT.font(11, weight: .medium))
                            Text(L10n.tr("1080p · 30 bilder/sek · MP4"))
                                .font(LT.font(10)).foregroundStyle(LT.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }

                Divider().overlay(LT.border)
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lightbulb").font(.system(size: 15)).foregroundStyle(LT.accent)
                    Text(L10n.tr("Et lite tips: Lukk det du ikke vil vise, og slå av varsler før du starter. Opptakskontrollene blir ikke med i videoen."))
                        .font(LT.font(11)).foregroundStyle(LT.secondary).lineSpacing(4)
                }
            }
            .padding(32).frame(maxWidth: 1150, alignment: .leading).frame(maxWidth: .infinity)
        }
        .task(id: capture.previewKey) { capture.updatePreview(visible: true) }
        .onDisappear { capture.updatePreview(visible: false) }
        .confirmationDialog(L10n.tr("Forkaste dette opptaket?"), isPresented: $confirmCancel, titleVisibility: .visible) {
            Button(L10n.tr("Forkast opptak"), role: .destructive) { Task { await model.cancel() } }
            Button(L10n.tr("Fortsett opptaket"), role: .cancel) { }
        } message: {
            Text(L10n.tr("Dette opptaket blir ikke lagt til i biblioteket."))
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(LT.dark)
                if let image = capture.mode == .camera ? capture.cameraPreview : capture.screenPreview {
                    CapturePreview(image: image, fill: false).clipShape(RoundedRectangle(cornerRadius: 18))
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: capture.mode == .camera ? "video" : "display")
                            .font(.system(size: 43, weight: .ultraLight))
                            .foregroundStyle(LT.muted)
                        VStack(spacing: 6) {
                            Text(previewTitle).font(LT.font(14, weight: .medium)).foregroundStyle(LT.surface)
                                .multilineTextAlignment(.center).lineLimit(2)
                            Text(L10n.tr("Venter på levende bilde fra valgt kilde …"))
                                .font(LT.font(10)).foregroundStyle(LT.muted)
                        }
                    }.padding(30)
                }

                if capture.mode == .screenAndCamera {
                    FacecamEditor(capture: capture, editable: isIdle)
                }

                if let countdown = capture.countdown {
                    LT.dark.opacity(0.5).clipShape(RoundedRectangle(cornerRadius: 18))
                    Text("\(countdown)").font(LT.font(72, weight: .semibold)).foregroundStyle(LT.surface)
                }

                VStack {
                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(isCapturing ? Color.red.opacity(0.85) : LT.muted).frame(width: 5, height: 5)
                            Text(previewStatus).font(LT.font(9, weight: .semibold)).tracking(0.8)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .foregroundStyle(LT.surface).background(LT.ink.opacity(0.7), in: Capsule())
                        Spacer()
                    }
                    Spacer()
                }.padding(16)
            }
            .coordinateSpace(name: "recordingPreview")
            .aspectRatio(previewAspect, contentMode: .fit)
            .accessibilityLabel("\(previewTitle). \(previewStatus)")

            HStack(spacing: 6) {
                Image(systemName: capture.mode == .screenAndCamera ? "arrow.up.left.and.arrow.down.right" : "checkmark.circle")
                    .font(.system(size: 10))
                Text(captureScope)
                    .font(LT.font(10))
            }.foregroundStyle(LT.secondary)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 9) {
                fieldTitle(L10n.tr("OPPTAKSMODUS"))
                HStack(spacing: 5) {
                    modeButton(.screenAndCamera, title: L10n.tr("Begge"), icon: "rectangle.inset.bottomleft.filled")
                    modeButton(.screen, title: L10n.tr("Skjerm"), icon: "display")
                    modeButton(.camera, title: L10n.tr("Kamera"), icon: "video")
                }
            }

            if capture.mode != .camera {
                VStack(alignment: .leading, spacing: 8) {
                    fieldTitle(L10n.tr("SKJERM ELLER VINDU"))
                    Picker(L10n.tr("Skjerm"), selection: Binding(get: { capture.selectedDisplayID }, set: { capture.selectedWindowID = ""; capture.selectedDisplayID = $0 })) {
                        if capture.displays.isEmpty { Text(L10n.tr("Ingen skjermer tilgjengelig")).tag("") }
                        ForEach(capture.displays) { display in Text(display.title).tag(display.id) }
                    }
                    .labelsHidden().frame(maxWidth: .infinity).controlSize(.large)
                    if capture.windows.isEmpty {
                        Text(L10n.tr("Vinduene vises etter at skjermtilgang er gitt. Oppdater enhetene hvis et vindu mangler."))
                            .font(LT.font(10)).foregroundStyle(LT.secondary).lineSpacing(3)
                    }
                    Picker(L10n.tr("Vindu"), selection: $capture.selectedWindowID) {
                        Text(L10n.tr("Hele den valgte skjermen")).tag("")
                        ForEach(capture.windows) { window in Text(window.title).tag(window.id) }
                    }
                    .labelsHidden().frame(maxWidth: .infinity).controlSize(.large)
                }
            }

            if capture.mode != .screen {
                VStack(alignment: .leading, spacing: 8) {
                    fieldTitle(L10n.tr("KAMERA"))
                    Picker(L10n.tr("Kamera"), selection: $capture.cameraID) {
                        if capture.cameras.isEmpty { Text(L10n.tr("Ingen kameraer funnet")).tag("") }
                        ForEach(capture.cameras) { camera in Text(camera.title).tag(camera.id) }
                    }
                    .labelsHidden().frame(maxWidth: .infinity).controlSize(.large)
                    if capture.cameras.isEmpty {
                        Text(L10n.tr("Koble til et kamera, eller velg kun skjerm."))
                            .font(LT.font(10)).foregroundStyle(LT.accent)
                    }
                }
            }

            if capture.mode == .screenAndCamera {
                VStack(alignment: .leading, spacing: 9) {
                    fieldTitle(L10n.tr("FACECAM"))
                    Picker(L10n.tr("Form"), selection: $capture.bubbleShape) {
                        ForEach(FacecamShape.allCases) { shape in Text(shape.title).tag(shape) }
                    }.pickerStyle(.segmented)
                    HStack {
                        Text(L10n.tr("Størrelse")).font(LT.font(10))
                        Spacer()
                        Button { capture.bubbleScale = max(0.12, capture.bubbleScale - 0.02) } label: { Image(systemName: "minus") }.help(L10n.tr("Mindre facecam"))
                        Button { capture.bubbleScale = min(0.5, capture.bubbleScale + 0.02) } label: { Image(systemName: "plus") }.help(L10n.tr("Større facecam"))
                        Text("\(Int(capture.bubbleScale * 100)) %").font(LT.font(10)).monospacedDigit().frame(width: 38)
                    }
                    Text(L10n.tr("Dra bildet for å flytte. Dra hjørnehåndtaket for å endre størrelsen."))
                        .font(LT.font(10)).foregroundStyle(LT.secondary)
                    HStack {
                        Button(L10n.tr("Nede til venstre")) { capture.setBubblePosition(CGPoint(x: 0.04, y: 0.06)) }
                        Button(L10n.tr("Nede til høyre")) { capture.setBubblePosition(CGPoint(x: 1, y: 0.06)) }
                    }.buttonStyle(.plain).font(LT.font(9))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    fieldTitle(L10n.tr("MIKROFON"))
                    Spacer()
                    Toggle(L10n.tr("Bruk mikrofon"), isOn: $capture.microphoneEnabled)
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                }
                if capture.microphoneEnabled {
                    Picker(L10n.tr("Mikrofon"), selection: $capture.microphoneID) {
                        if capture.microphones.isEmpty { Text(L10n.tr("Ingen mikrofoner funnet")).tag("") }
                        ForEach(capture.microphones) { mic in Text(mic.title).tag(mic.id) }
                    }
                    .labelsHidden().frame(maxWidth: .infinity).controlSize(.large)
                    MicrophoneLevelView(level: capture.audioLevel)
                    Text(isCapturing ? L10n.tr("Mikrofonen er aktiv") : L10n.tr("Snakk for å teste mikrofonen · ingen lyd lagres"))
                        .font(LT.font(9)).foregroundStyle(LT.secondary)
                } else {
                    Text(L10n.tr("Videoen tas opp uten mikrofon."))
                        .font(LT.font(10)).foregroundStyle(LT.secondary)
                }
            }

            if isIdle {
                Button { Task { await capture.refreshSources(); capture.updatePreview(visible: true) } } label: {
                    Label(L10n.tr("Oppdater enheter"), systemImage: "arrow.clockwise")
                        .font(LT.font(10, weight: .medium))
                }.buttonStyle(.plain).foregroundStyle(LT.secondary)
            }
        }
        .disabled(!isIdle)
    }

    private var activeControls: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(recordingTime(capture.elapsed))
                    .font(.system(size: 30, weight: .light, design: .monospaced))
                    .monospacedDigit()
                Text(capture.state == .paused ? L10n.tr("Pausetiden blir ikke med i videoen") : capture.state == .finishing || model.saving ? L10n.tr("Lagrer videoen i biblioteket …") : capture.state == .preparing ? L10n.tr("Gjør opptaket klart …") : L10n.tr("Opptak pågår"))
                    .font(LT.font(10)).foregroundStyle(LT.secondary)
            }
            Spacer()
            if isCapturing {
                Button {
                    if capture.state == .paused { capture.resume() } else { capture.pause() }
                } label: {
                    Label(capture.state == .paused ? L10n.tr("Fortsett") : L10n.tr("Pause"), systemImage: capture.state == .paused ? "play.fill" : "pause.fill")
                }.buttonStyle(QuietButtonStyle())
                Button { Task { await model.finish() } } label: {
                    Label(L10n.tr("Stopp og lagre"), systemImage: "stop.fill")
                }.buttonStyle(PrimaryButtonStyle())
                Button { confirmCancel = true } label: {
                    Image(systemName: "trash").font(.system(size: 14))
                }.buttonStyle(.plain).foregroundStyle(LT.secondary).help(L10n.tr("Forkast opptaket"))
            } else if capture.state == .preparing {
                Button(L10n.tr("Avbryt")) { Task { await model.cancel() } }.buttonStyle(QuietButtonStyle())
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(20).background(LT.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private func fieldTitle(_ text: String) -> some View {
        Text(text).font(LT.font(9, weight: .semibold)).tracking(1).foregroundStyle(LT.secondary)
    }

    private func modeButton(_ mode: CaptureMode, title: String, icon: String) -> some View {
        Button { capture.mode = mode } label: {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 18, weight: .light))
                Text(title).font(LT.font(10, weight: .medium))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 11)
            .foregroundStyle(capture.mode == mode ? LT.surface : LT.secondary)
            .background(capture.mode == mode ? LT.ink : LT.surface, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(capture.mode == mode ? Color.clear : LT.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(capture.mode == mode ? .isSelected : [])
    }

    private var previewAspect: CGFloat {
        capture.outputDimensions.width / capture.outputDimensions.height
    }

    private var captureScope: String {
        let source = capture.mode == .camera ? L10n.tr("Kun kamera · ingen skjerm filmes") :
            capture.selectedWindowID.isEmpty ? L10n.tr("Hele «\(previewTitle)» · kun denne skjermen") : L10n.tr("Kun vinduet «\(previewTitle)»")
        return source + (capture.mode == .screenAndCamera ? L10n.tr(" · med kameraboble") : "")
    }

    private var previewTitle: String {
        if capture.mode == .camera {
            return capture.cameras.first { $0.id == capture.cameraID }?.title ?? L10n.tr("Ditt kamera")
        }
        if !capture.selectedWindowID.isEmpty {
            return capture.windows.first { $0.id == capture.selectedWindowID }?.title ?? L10n.tr("Valgt vindu")
        }
        return capture.displays.first { $0.id == capture.selectedDisplayID }?.title ?? L10n.tr("Din skjerm")
    }

    private var previewStatus: String {
        if model.saving { return L10n.tr("LAGRER") }
        switch capture.state {
        case .idle: return (capture.mode == .camera ? capture.cameraPreview : capture.screenPreview) == nil ? L10n.tr("VENTER PÅ BILDE") : L10n.tr("DIREKTE · IKKE OPPTAK")
        case .preparing: return L10n.tr("GJØR KLART")
        case .recording: return L10n.tr("TAR OPP")
        case .paused: return L10n.tr("PAUSE")
        case .finishing: return L10n.tr("LAGRER")
        }
    }
}

/// Gesture translations are measured in the stationary preview canvas. Using
/// the moving camera view's local coordinates feeds its own movement back into
/// the next drag event and makes the image oscillate under the pointer.
private struct FacecamEditor: View {
    @ObservedObject private var languageSettings = LanguageSettings.shared
    @ObservedObject var capture: CaptureController
    let editable: Bool
    @State private var moveOrigin: CGRect?
    @State private var resizeOrigin: CGRect?

    var body: some View {
        GeometryReader { geometry in
            let canvas = capture.outputDimensions
            let rect = facecamRect(canvas: canvas, position: capture.bubblePosition, scale: capture.bubbleScale)
            let zoom = geometry.size.width / canvas.width
            let side = rect.width * zoom
            let shape = RoundedRectangle(cornerRadius: capture.bubbleShape == .circle ? side / 2 : 0)
            ZStack {
                ZStack {
                    shape.fill(LT.paper)
                    if let image = capture.cameraPreview {
                        CapturePreview(image: image).allowsHitTesting(false).clipShape(shape)
                    } else {
                        Image(systemName: "video.slash").foregroundStyle(LT.ink)
                    }
                }
                .frame(width: side, height: side)
                .overlay(shape.stroke(editable ? Color.white.opacity(0.65) : .clear, lineWidth: 1))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("recordingPreview"))
                    .onChanged { value in
                        guard editable else { return }
                        if moveOrigin == nil { moveOrigin = rect }
                        guard let origin = moveOrigin else { return }
                        let requested = CGPoint(x: (origin.minX + value.translation.width / zoom) / canvas.width,
                                                y: (origin.minY - value.translation.height / zoom) / canvas.height)
                        let next = facecamRect(canvas: canvas, position: requested, scale: capture.bubbleScale)
                        capture.setBubblePosition(CGPoint(x: next.minX / canvas.width, y: next.minY / canvas.height))
                    }.onEnded { _ in moveOrigin = nil })
                .help(L10n.tr("Dra for å flytte facecam"))
                .position(x: rect.midX * zoom, y: geometry.size.height - rect.midY * zoom)

                if editable {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(LT.ink)
                        .frame(width: 22, height: 22)
                        .background(LT.surface, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(LT.ink.opacity(0.25)))
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("recordingPreview"))
                            .onChanged { value in
                                if resizeOrigin == nil { resizeOrigin = rect }
                                guard let origin = resizeOrigin else { return }
                                let next = resizedFacecamRect(origin: origin, canvas: canvas,
                                    translation: CGSize(width: value.translation.width / zoom, height: value.translation.height / zoom))
                                capture.bubbleScale = next.width / min(canvas.width, canvas.height)
                                capture.setBubblePosition(CGPoint(x: next.minX / canvas.width, y: next.minY / canvas.height))
                            }.onEnded { _ in resizeOrigin = nil })
                        .accessibilityLabel(L10n.tr("Dra for å endre størrelsen på facecam"))
                        .help(L10n.tr("Dra hjørnet for å endre størrelse"))
                        .position(x: rect.maxX * zoom, y: geometry.size.height - rect.minY * zoom)
                }
            }
            .transaction { $0.animation = nil }
        }
    }
}

private struct MicrophoneLevelView: View {
    @ObservedObject private var languageSettings = LanguageSettings.shared
    let level: Float
    private let green = Color(red: 0.19, green: 0.49, blue: 0.31)
    private let yellow = Color(red: 0.72, green: 0.50, blue: 0.12)
    private let red = Color(red: 0.77, green: 0.24, blue: 0.19)

    private func color(at value: Float) -> Color {
        value >= 0.9 ? red : value >= 0.8 ? yellow : green
    }
    private var guidance: String {
        if level < 0.05 { return L10n.tr("Ingen tydelig lyd · snakk for å teste") }
        if level < 0.5 { return L10n.tr("Lavt nivå · snakk nærmere mikrofonen") }
        if level < 0.8 { return L10n.tr("Passe talenivå") }
        if level < 0.9 { return L10n.tr("Høyt nivå · trekk deg litt tilbake") }
        return L10n.tr("For høyt · senk inngangsnivået eller flytt deg unna")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                ForEach(0..<30, id: \.self) { index in
                    let threshold = Float(index + 1) / 30
                    Capsule().fill(color(at: Float(index) / 30).opacity(level >= threshold ? 1 : 0.16))
                        .frame(height: 6)
                }
            }
            HStack {
                Text(L10n.tr("Lavt")).foregroundStyle(LT.secondary)
                Spacer()
                Text(L10n.tr("Passe")).foregroundStyle(green)
                Spacer()
                Text(L10n.tr("Høyt")).foregroundStyle(yellow)
                Text(L10n.tr("For høyt")).foregroundStyle(red)
            }.font(LT.font(8))
            Label(guidance, systemImage: level >= 0.9 ? "exclamationmark.triangle.fill" : level >= 0.5 && level < 0.8 ? "checkmark.circle" : "waveform")
                .font(LT.font(9, weight: .medium))
                .foregroundStyle(level < 0.5 ? LT.secondary : color(at: level))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.tr("Mikrofonnivå. \(guidance)"))
        .help(L10n.tr("Veiledende talenivå. Grønt målområde: −30 til −12 dBFS. Gult: −12 til −6 dBFS. Rødt: over −6 dBFS, med fare for overstyring nær 0 dBFS."))
    }
}

private struct InlineNotice: View {
    @ObservedObject private var languageSettings = LanguageSettings.shared
    let message: String
    let isError: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isError ? "exclamationmark.circle" : "info.circle").padding(.top, 1)
            Text(message).font(LT.font(12)).lineSpacing(3).textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .foregroundStyle(isError ? LT.accent : LT.ink)
        .padding(14).background(isError ? LT.accent.opacity(0.08) : LT.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

private struct LocalSettingsView: View {
    @ObservedObject private var languageSettings = LanguageSettings.shared
    @ObservedObject var capture: CaptureController
    let directory: URL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.tr("DITT ARBEIDSOMRÅDE")).font(LT.font(10, weight: .semibold)).tracking(1.6).foregroundStyle(LT.secondary)
                    Text(L10n.tr("Enkelt. Og helt ditt.")).font(LT.font(29, weight: .medium)).tracking(-1)
                    Text(L10n.tr("Opptakene dine blir på Mac-en. Ingen konto, ingen opplasting."))
                        .font(LT.font(12)).foregroundStyle(LT.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label(L10n.tr("Språk"), systemImage: "globe").font(LT.font(16, weight: .medium))
                    Picker(L10n.tr("Språk"), selection: $languageSettings.selection) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }.pickerStyle(.menu).id(languageSettings.selection).frame(maxWidth: 340, alignment: .leading)
                    Text(L10n.tr("Språket endres med én gang og huskes neste gang du åpner appen."))
                        .font(LT.font(12)).foregroundStyle(LT.secondary)
                    Text(L10n.tr("Menyer og systemdialoger fra macOS følger Mac-ens egne språkinnstillinger."))
                        .font(LT.font(10)).foregroundStyle(LT.secondary)
                }
                .padding(24).background(LT.surface, in: RoundedRectangle(cornerRadius: 15))

                VStack(alignment: .leading, spacing: 18) {
                    Label(L10n.tr("Lokal lagring"), systemImage: "internaldrive").font(LT.font(16, weight: .medium))
                    Text(L10n.tr("Videoer, miniatyrbilder og bibliotekoversikt lagres samlet her:"))
                        .font(LT.font(12)).foregroundStyle(LT.secondary)
                    Text(directory.path).font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(LT.paper, in: RoundedRectangle(cornerRadius: 8))
                    Button { NSWorkspace.shared.open(directory) } label: {
                        Label(L10n.tr("Åpne opptaksmappen"), systemImage: "folder")
                    }.buttonStyle(QuietButtonStyle())
                }
                .padding(24).background(LT.surface, in: RoundedRectangle(cornerRadius: 15))

                VStack(alignment: .leading, spacing: 18) {
                    Label(L10n.tr("Tillatelser på Mac"), systemImage: "hand.raised").font(LT.font(16, weight: .medium))
                    Text(L10n.tr("macOS ber om tilgang første gang du bruker skjerm, kamera og mikrofon. Hvis du har sagt nei, kan du endre det i Systeminnstillinger."))
                        .font(LT.font(12)).foregroundStyle(LT.secondary).lineSpacing(4)
                    permissionRow(L10n.tr("Skjermopptak"), subtitle: L10n.tr("For å ta opp en skjerm eller et vindu"), icon: "display", kind: "screen")
                    Divider()
                    permissionRow(L10n.tr("Kamera"), subtitle: L10n.tr("For kameraboblen og kameraopptak"), icon: "video", kind: "camera")
                    Divider()
                    permissionRow(L10n.tr("Mikrofon"), subtitle: L10n.tr("For stemmen din i videoen"), icon: "mic", kind: "microphone")
                }
                .padding(24).background(LT.surface, in: RoundedRectangle(cornerRadius: 15))

                HStack(alignment: .top, spacing: 16) {
                    LewtechWordmark().scaleEffect(0.65, anchor: .leading).frame(width: 120, height: 34, alignment: .leading)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Lewtech Record").font(LT.font(12, weight: .semibold))
                        Text(L10n.tr("Laget for å vise, forklare og komme videre."))
                            .font(LT.font(11)).foregroundStyle(LT.secondary)
                    }
                    Spacer()
                }.padding(.top, 4)
            }
            .padding(32).frame(maxWidth: 850, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func permissionRow(_ title: String, subtitle: String, icon: String, kind: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon).font(.system(size: 18, weight: .light)).frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(LT.font(12, weight: .medium))
                Text(subtitle).font(LT.font(10)).foregroundStyle(LT.secondary)
            }
            Spacer()
            Button { capture.openPrivacySettings(kind) } label: {
                Label(L10n.tr("Åpne"), systemImage: "arrow.up.right").font(LT.font(11, weight: .medium))
            }.buttonStyle(QuietButtonStyle())
        }
    }
}

/// Display a sampled camera image without attaching preview outputs to the
/// capture session from the main thread. Session configuration stays isolated.
struct CapturePreview: NSViewRepresentable {
    let image: CGImage
    var fill = true
    func makeNSView(context: Context) -> CameraImageView {
        let view = CameraImageView()
        view.wantsLayer = true
        view.layer?.contentsGravity = fill ? .resizeAspectFill : .resizeAspect
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.layer?.masksToBounds = true
        view.layer?.contents = image
        return view
    }
    func updateNSView(_ view: CameraImageView, context: Context) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.layer?.contentsGravity = fill ? .resizeAspectFill : .resizeAspect
        view.layer?.contents = image
        CATransaction.commit()
    }
}

final class CameraImageView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

private func recordingTime(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
    return String(format: "%02d:%02d", total / 60, total % 60)
}
