import AppKit
import AVKit
import SwiftUI
import UniformTypeIdentifiers

private enum LibraryPalette {
    static let ink = LT.ink
    static let muted = LT.secondary
    static let paper = LT.paper
    static let line = LT.border
}

struct LibraryView: View {
    @ObservedObject var store: LibraryStore
    var onNew: () -> Void
    @State private var query = ""
    @State private var sort: LibrarySort = .newest
    @State private var selectedItem: RecordingItem?
    @State private var renamingItem: RecordingItem?
    @State private var newTitle = ""
    @State private var trashingItem: RecordingItem?
    @State private var localError: String?
    @State private var exporting = false
    @State private var exportedName: String?

    private enum LibrarySort: String, CaseIterable, Identifiable {
        case newest = "Nyeste først", oldest = "Eldste først", name = "Navn A–Å"
        var id: String { rawValue }
    }

    private var filteredItems: [RecordingItem] {
        let matching = store.items.filter { query.isEmpty || $0.title.localizedStandardContains(query) }
        return matching.sorted {
            switch sort {
            case .newest: return $0.createdAt > $1.createdAt
            case .oldest: return $0.createdAt < $1.createdAt
            case .name: return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            header
            if let message = localError ?? store.errorMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.circle")
                    Text(message).font(LT.font(12)).textSelection(.enabled)
                    Spacer(minLength: 4)
                    Button { localError = nil; store.errorMessage = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("Lukk melding")
                }.foregroundStyle(Color(red: 0.55, green: 0.23, blue: 0.12))
                    .padding(13).background(Color(red: 0.97, green: 0.91, blue: 0.84), in: RoundedRectangle(cornerRadius: 10))
            }
            if let message = store.recoveryMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.clockwise.circle")
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message).font(LT.font(12)).textSelection(.enabled)
                        if FileManager.default.fileExists(atPath: store.recoveryDirectory.path) {
                            Button("Vis gjenopprettingsmappe i Finder") { NSWorkspace.shared.open(store.recoveryDirectory) }
                                .font(LT.font(11, weight: .semibold)).buttonStyle(.plain).underline()
                        }
                    }
                    Spacer(minLength: 4)
                    if !store.recoveringInterruptedRecordings {
                        Button { store.recoveryMessage = nil } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).accessibilityLabel("Lukk gjenopprettingsmelding")
                    }
                }.foregroundStyle(LT.ink).padding(13)
                    .background(LT.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(LT.border, lineWidth: 1))
            }
            if store.items.isEmpty {
                emptyLibrary
            } else {
                filters
                if filteredItems.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").font(LT.font(28, weight: .light))
                        Text("Ingen opptak med dette navnet").font(LT.font(17, weight: .medium))
                        Button("Tøm søket") { query = "" }.buttonStyle(.plain).underline()
                    }.foregroundStyle(LibraryPalette.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 400), spacing: 22)], alignment: .leading, spacing: 26) {
                            ForEach(filteredItems) { item in
                                recordingCard(item)
                            }
                        }.padding(.bottom, 20)
                    }
                }
            }
            footer
        }
        .padding(30)
        .background(LibraryPalette.paper)
        .foregroundStyle(LibraryPalette.ink)
        .sheet(item: $selectedItem) { item in
            RecordingPlayerSheet(item: store.items.first(where: { $0.id == item.id }) ?? item, url: store.url(for: item), exporting: exporting,
                                 exportFeedback: localError ?? exportedName.map { "Eksportert: \($0)" }, exportFailed: localError != nil,
                                 onExport: { export(item) })
        }
        .alert("Gi opptaket et nytt navn", isPresented: Binding(get: { renamingItem != nil }, set: { if !$0 { renamingItem = nil } })) {
            TextField("Navn på opptaket", text: $newTitle)
            Button("Avbryt", role: .cancel) { renamingItem = nil }
            Button("Lagre") {
                guard let item = renamingItem else { return }
                do { try store.rename(item, to: newTitle) } catch { localError = error.localizedDescription }
                renamingItem = nil
            }
        }
        .alert("Flytte opptaket til papirkurven?", isPresented: Binding(get: { trashingItem != nil }, set: { if !$0 { trashingItem = nil } })) {
            Button("Avbryt", role: .cancel) { trashingItem = nil }
            Button("Flytt til papirkurven", role: .destructive) {
                guard let item = trashingItem else { return }
                do { try store.trash(item) } catch { localError = error.localizedDescription }
                trashingItem = nil
            }
        } message: {
            Text("«\(trashingItem?.title ?? "Opptaket")» kan hentes tilbake fra papirkurven i Finder.")
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text("DITT ARKIV").font(LT.font(10, weight: .semibold)).tracking(2).foregroundStyle(LibraryPalette.muted)
                Text("Videobibliotek").font(LT.font(30, weight: .medium)).tracking(-0.8)
                Text("Ideene dine, klare til å spilles av.").font(LT.font(13)).foregroundStyle(LibraryPalette.muted)
            }
            Spacer()
            Button(action: onNew) {
                Label("Nytt opptak", systemImage: "plus").font(LT.font(13, weight: .semibold))
                    .padding(.horizontal, 17).padding(.vertical, 12)
                    .foregroundStyle(.white).background(LibraryPalette.ink, in: Capsule())
            }.buttonStyle(.plain)
        }
    }

    private var filters: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(LibraryPalette.muted)
                TextField("Søk i opptakene dine", text: $query).textFieldStyle(.plain).font(LT.font(13))
                    .accessibilityLabel("Søk i videobibliotek")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(LibraryPalette.muted) }
                        .buttonStyle(.plain).accessibilityLabel("Tøm søk")
                }
            }.padding(12).background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(LibraryPalette.line, lineWidth: 1))
                .frame(maxWidth: 360)
            Spacer()
            Picker("Sortering", selection: $sort) {
                ForEach(LibrarySort.allCases) { value in Text(value.rawValue).tag(value) }
            }.labelsHidden().frame(width: 150)
        }
    }

    private var emptyLibrary: some View {
        VStack(spacing: 17) {
            ZStack {
                RoundedRectangle(cornerRadius: 28).fill(Color(red: 0.91, green: 0.90, blue: 0.85)).frame(width: 106, height: 90).rotationEffect(.degrees(-7))
                RoundedRectangle(cornerRadius: 22).fill(.white).frame(width: 100, height: 80)
                    .overlay(Image(systemName: "play.rectangle").font(LT.font(33, weight: .ultraLight)).foregroundStyle(LibraryPalette.ink))
                    .shadow(color: .black.opacity(0.04), radius: 18, y: 8)
            }.padding(.bottom, 8)
            Text("Det starter med et opptak.").font(LT.font(24, weight: .medium)).tracking(-0.5)
            Text("Vis en idé, forklar en prosess eller ta noen gjennom arbeidet ditt.\nVideoene lagres her, på din egen Mac.")
                .font(LT.font(13)).lineSpacing(5).foregroundStyle(LibraryPalette.muted).multilineTextAlignment(.center)
            Button(action: onNew) {
                Label("Lag ditt første opptak", systemImage: "record.circle")
                    .font(LT.font(13, weight: .semibold)).padding(.horizontal, 20).padding(.vertical, 12)
                    .foregroundStyle(.white).background(LibraryPalette.ink, in: Capsule())
            }.buttonStyle(.plain).padding(.top, 6)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func recordingCard(_ item: RecordingItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { selectedItem = item } label: {
                ZStack(alignment: .bottomTrailing) {
                    LibraryThumbnail(url: store.thumbnailURL(for: item))
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.black.opacity(0.06), lineWidth: 1))
                    Text(item.durationLabel).font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .foregroundStyle(.white).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 5)).padding(9)
                }
            }.buttonStyle(.plain).accessibilityLabel("Spill av \(item.title)")
            HStack(alignment: .top, spacing: 5) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(LT.font(13, weight: .medium)).lineLimit(2)
                    Text(item.createdAt.formatted(.dateTime.day().month(.abbreviated).year()))
                        .font(LT.font(11)).foregroundStyle(LibraryPalette.muted)
                }
                Spacer(minLength: 0)
                Menu {
                    Button("Spill av", systemImage: "play") { selectedItem = item }
                    Button("Endre navn", systemImage: "pencil") { newTitle = item.title; renamingItem = item }
                    Button("Eksporter MP4…", systemImage: "square.and.arrow.up") { export(item) }.disabled(exporting)
                    Button("Vis i Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([store.url(for: item)]) }
                    Divider()
                    Button("Flytt til papirkurven", systemImage: "trash", role: .destructive) { trashingItem = item }
                } label: {
                    Image(systemName: "ellipsis").font(LT.font(16)).frame(width: 24, height: 20)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Valg for \(item.title)")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: "internaldrive").font(LT.font(11))
            Text(exporting ? "Eksporterer videofil…" : exportedName.map { "Eksportert: \($0)" } ?? "\(store.items.count) opptak · Lagret på denne Mac-en")
                .font(LT.font(11)).lineLimit(1)
            Spacer()
            Button("Åpne mappe") { NSWorkspace.shared.open(store.directory) }
                .font(LT.font(11)).buttonStyle(.plain)
                .accessibilityLabel("Åpne bibliotekmappen i Finder")
        }.foregroundStyle(LibraryPalette.muted)
    }

    private func export(_ item: RecordingItem) {
        guard !exporting else { return }
        localError = nil
        let source = store.url(for: item)
        guard FileManager.default.fileExists(atPath: source.path) else { localError = LibraryStore.LibraryError.missingRecording.localizedDescription; return }
        let panel = NSSavePanel()
        panel.title = "Eksporter opptak"
        panel.prompt = "Eksporter"
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = item.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + ".mp4"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        guard destination.standardizedFileURL != source.standardizedFileURL else { localError = "Velg en annen plassering enn originalfilen i biblioteket."; return }
        exporting = true
        exportedName = nil
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    let manager = FileManager.default
                    let temporary = destination.deletingLastPathComponent().appendingPathComponent(".lewtech-export-\(UUID().uuidString).mp4")
                    defer { try? manager.removeItem(at: temporary) }
                    try manager.copyItem(at: source, to: temporary)
                    if manager.fileExists(atPath: destination.path) {
                        _ = try manager.replaceItemAt(destination, withItemAt: temporary)
                    } else {
                        try manager.moveItem(at: temporary, to: destination)
                    }
                }.value
                exportedName = destination.lastPathComponent
            } catch {
                localError = "Eksporten mislyktes: \(error.localizedDescription)"
            }
            exporting = false
        }
    }
}

private struct LibraryThumbnail: View {
    var url: URL?
    @State private var image: NSImage?
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.89, green: 0.89, blue: 0.84)
                if let image {
                    Image(nsImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
                } else {
                    Image(systemName: "play.rectangle").font(LT.font(30, weight: .ultraLight)).foregroundStyle(LibraryPalette.muted)
                }
            }
        }
        .task(id: url) {
            image = nil
            guard let url else { return }
            let data = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
            guard !Task.isCancelled else { return }
            if let data { image = NSImage(data: data) }
        }
    }
}

private struct RecordingPlayerSheet: View {
    let item: RecordingItem
    let url: URL
    var exporting: Bool
    var exportFeedback: String?
    var exportFailed: Bool
    var onExport: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(LT.font(18, weight: .medium)).lineLimit(2)
                    Text("\(item.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(item.durationLabel)")
                        .font(LT.font(11)).foregroundStyle(LibraryPalette.muted)
                }
                Spacer()
                Button { player?.pause(); dismiss() } label: {
                    Image(systemName: "xmark").font(LT.font(13, weight: .medium)).frame(width: 28, height: 28)
                }.buttonStyle(.plain).accessibilityLabel("Lukk avspilling").keyboardShortcut(.escape, modifiers: [])
            }.padding(24)
            ZStack {
                Color.black
                if let failure {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                        Text(failure).multilineTextAlignment(.center).frame(maxWidth: 440)
                    }.foregroundStyle(.white).padding(28)
                } else if let player {
                    NativeRecordingPlayer(player: player)
                } else {
                    ProgressView("Åpner video…").tint(.white).foregroundStyle(.white)
                }
            }.frame(minHeight: 340, maxHeight: .infinity)
            HStack {
                if let exportFeedback {
                    Text(exportFeedback).font(LT.font(11)).foregroundStyle(exportFailed ? LT.accent : LibraryPalette.muted)
                        .textSelection(.enabled).lineLimit(3).frame(maxWidth: 400, alignment: .leading)
                } else {
                    Label("Lagret lokalt", systemImage: "internaldrive").font(LT.font(12)).foregroundStyle(LibraryPalette.muted)
                }
                Spacer()
                Button("Vis i Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Button(exporting ? "Eksporterer…" : "Eksporter MP4…", action: onExport).disabled(exporting || failure != nil)
            }.padding(20)
        }
        .frame(minWidth: 720, idealWidth: 860, minHeight: 510, idealHeight: 620)
        .background(LibraryPalette.paper).foregroundStyle(LibraryPalette.ink)
        .task {
            let asset = AVURLAsset(url: url)
            do {
                guard FileManager.default.fileExists(atPath: url.path) else { throw LibraryStore.LibraryError.missingRecording }
                guard try await asset.load(.isPlayable) else { throw LibraryStore.LibraryError.invalidVideo }
                guard !Task.isCancelled else { return }
                player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
                player?.play()
            } catch { failure = error.localizedDescription }
        }
        .onDisappear { player?.pause(); player?.replaceCurrentItem(with: nil); player = nil }
    }
}

/// Use AVPlayerView directly. This also creates an explicit AVKit link in
/// SwiftPM builds instead of relying on the SwiftUI overlay's lazy metadata.
private struct NativeRecordingPlayer: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.videoGravity = .resizeAspect
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) { view.player = player }
    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) { view.player = nil }
}
