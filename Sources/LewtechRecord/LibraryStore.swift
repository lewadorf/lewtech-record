import AppKit
import AVFoundation
import Combine
import Foundation

struct RecordingItem: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var createdAt: Date
    var duration: Double
    var fileName: String
    var thumbnailName: String?

    var durationLabel: String {
        let seconds = max(0, Int(duration.isFinite ? duration : 0))
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published var items: [RecordingItem] = []
    @Published var errorMessage: String?
    @Published var recoveryMessage: String?
    @Published private(set) var recoveringInterruptedRecordings = false
    let directory: URL
    var recoveryDirectory: URL { directory.appendingPathComponent(".incomplete", isDirectory: true) }
    private let interruptedCandidates: [URL]
    private var didAttemptRecovery = false
    private var enrichmentTask: Task<Void, Never>?
    private var storageFailure: Error?
    private let fileManager = FileManager.default
    private var manifestURL: URL { directory.appendingPathComponent("library.json") }
    private var thumbnailsDirectory: URL { directory.appendingPathComponent(".thumbnails", isDirectory: true) }

    private struct Manifest: Codable {
        var version = 1
        var items: [RecordingItem]
    }

    enum LibraryError: LocalizedError {
        case emptyTitle, missingRecording, invalidVideo, unsupportedVersion, invalidManifest
        var errorDescription: String? {
            switch self {
            case .emptyTitle: return L10n.tr("Gi opptaket et navn før du lagrer.")
            case .missingRecording: return L10n.tr("Videofilen finnes ikke på den lagrede plasseringen. Den kan ha blitt flyttet i Finder.")
            case .invalidVideo: return L10n.tr("Videofilen kunne ikke åpnes. Originalfilen er beholdt.")
            case .unsupportedVersion: return L10n.tr("Biblioteket er opprettet av en nyere versjon av Lewtech Record.")
            case .invalidManifest: return L10n.tr("Bibliotekets metadata inneholder en ugyldig filreferanse.")
            }
        }
    }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies/Lewtech Record", isDirectory: true)
        // Snapshot at initialization, before the app can start a new recording.
        // Later reloads never discover or import a currently active recording.
        self.interruptedCandidates = ((try? FileManager.default.contentsOfDirectory(
            at: self.directory.appendingPathComponent(".incomplete", isDirectory: true),
            includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? [])
            .filter { $0.pathExtension.lowercased() == "mp4" && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        reload()
    }

    /// Call once during app startup. Only the immutable startup snapshot is
    /// considered; incomplete or unplayable fragments are never deleted.
    @discardableResult
    func recoverInterruptedRecordings() async -> Int {
        guard !didAttemptRecovery else { return 0 }
        didAttemptRecovery = true
        guard !interruptedCandidates.isEmpty else { return 0 }
        guard storageFailure == nil else {
            recoveryMessage = L10n.tr("Fant \(interruptedCandidates.count) avbrutte opptak. Biblioteket må kunne åpnes før de kan gjenopprettes. Filene er bevart i \(recoveryDirectory.path).")
            return 0
        }
        recoveringInterruptedRecordings = true
        recoveryMessage = L10n.tr("Undersøker \(interruptedCandidates.count) opptak fra forrige kjøring…")
        defer { recoveringInterruptedRecordings = false }
        var restored = 0
        var failures: [String] = []
        for candidate in interruptedCandidates {
            guard fileManager.fileExists(atPath: candidate.path) else { continue }
            do {
                let asset = AVURLAsset(url: candidate)
                guard try await asset.load(.isPlayable) else { throw LibraryError.invalidVideo }
                let duration = try await asset.load(.duration).seconds
                try await addRecording(fileURL: candidate, duration: duration)
                restored += 1
            } catch {
                // addRecording leaves original bytes intact when validation fails.
                // A metadata-write failure may have moved the completed MP4 to the
                // library root; its exact path is surfaced through errorMessage.
                failures.append(error.localizedDescription)
            }
        }
        let remaining = interruptedCandidates.filter { fileManager.fileExists(atPath: $0.path) }.count
        var parts: [String] = []
        if restored > 0 { parts.append(L10n.tr("Gjenopprettet \(restored) opptak i biblioteket.")) }
        if remaining > 0 {
            parts.append(L10n.tr("\(remaining) avbrutte opptak kunne ikke gjenopprettes automatisk. Filene er beholdt i \(recoveryDirectory.path)."))
        }
        if !failures.isEmpty && remaining == 0 {
            parts.append(L10n.tr("En videofil ble bevart, men kunne ikke registreres ferdig. Se feilmeldingen for filplasseringen."))
        }
        if parts.isEmpty { parts.append(L10n.tr("De tidligere avbrutte opptakene er ikke lenger i gjenopprettingsmappen.")) }
        recoveryMessage = parts.joined(separator: " ")
        return restored
    }

    func reload() {
        enrichmentTask?.cancel()
        storageFailure = nil
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
            var loaded: [RecordingItem] = []
            if fileManager.fileExists(atPath: manifestURL.path) {
                do {
                    let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
                    guard manifest.version == 1 else { throw LibraryError.unsupportedVersion }
                    guard manifest.items.allSatisfy({ Self.safeFileName($0.fileName) && ($0.thumbnailName.map(Self.safeFileName) ?? true) }),
                          Set(manifest.items.map(\.id)).count == manifest.items.count,
                          Set(manifest.items.map(\.fileName)).count == manifest.items.count else { throw LibraryError.invalidManifest }
                    loaded = manifest.items
                } catch LibraryError.unsupportedVersion {
                    throw LibraryError.unsupportedVersion
                } catch {
                    // Keep the exact original before reconstructing the index from completed video files.
                    let backup = directory.appendingPathComponent("library-backup-\(UUID().uuidString).json")
                    try fileManager.copyItem(at: manifestURL, to: backup)
                    errorMessage = L10n.tr("Bibliotekoversikten måtte gjenopprettes fra videofilene. En kopi av den opprinnelige oversikten er bevart i bibliotekmappen.")
                }
            }
            let known = Set(loaded.map(\.fileName))
            let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles])
            for file in files where file.pathExtension.lowercased() == "mp4" && !known.contains(file.lastPathComponent) {
                let attributes = try file.resourceValues(forKeys: [.creationDateKey, .isRegularFileKey])
                guard attributes.isRegularFile == true else { continue }
                loaded.append(RecordingItem(id: UUID(), title: file.deletingPathExtension().lastPathComponent, createdAt: attributes.creationDate ?? Date(), duration: 0, fileName: file.lastPathComponent, thumbnailName: nil))
            }
            items = loaded.sorted { $0.createdAt > $1.createdAt }
            try persist()
            enrichmentTask = Task { [weak self] in
                guard let self else { return }
                for item in self.items where item.duration <= 0 || item.thumbnailName == nil {
                    guard !Task.isCancelled else { return }
                    await self.enrich(item)
                }
            }
        } catch {
            storageFailure = error
            errorMessage = L10n.tr("Kunne ikke åpne biblioteket: \(error.localizedDescription)")
        }
    }

    func addRecording(fileURL: URL, duration: Double) async throws {
        if let storageFailure { throw storageFailure }
        guard fileManager.fileExists(atPath: fileURL.path) else { throw LibraryError.missingRecording }
        let asset = AVURLAsset(url: fileURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let actualDuration = try await asset.load(.duration).seconds
        guard !tracks.isEmpty, actualDuration.isFinite, actualDuration > 0 else { throw LibraryError.invalidVideo }
        let id = UUID()
        let date = (try? fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        let name = L10n.tr("Opptak \(formatter.string(from: date))")
        let destination = directory.appendingPathComponent("\(id.uuidString).mp4")
        // Move only a completed recording. A failed metadata write leaves this MP4 recoverable on reload.
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.moveItem(at: fileURL, to: destination)
        }.value
        let item = RecordingItem(id: id, title: name, createdAt: date, duration: actualDuration, fileName: destination.lastPathComponent, thumbnailName: nil)
        items.insert(item, at: 0)
        do { try persist() } catch {
            errorMessage = L10n.tr("Videofilen er bevart i \(destination.path), men bibliotekoversikten kunne ikke lagres: \(error.localizedDescription)")
            throw error
        }
        await enrich(item)
    }

    func url(for item: RecordingItem) -> URL { directory.appendingPathComponent(item.fileName) }

    func thumbnailURL(for item: RecordingItem) -> URL? {
        item.thumbnailName.map { thumbnailsDirectory.appendingPathComponent($0) }
    }

    func rename(_ item: RecordingItem, to title: String) throws {
        if let storageFailure { throw storageFailure }
        let cleaned = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !cleaned.isEmpty else { throw LibraryError.emptyTitle }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let previous = items[index]
        items[index].title = cleaned
        do { try persist() } catch { items[index] = previous; throw error }
    }

    func trash(_ item: RecordingItem) throws {
        if let storageFailure { throw storageFailure }
        let videoURL = url(for: item)
        let previousItems = items
        var trashedURL: NSURL?
        if fileManager.fileExists(atPath: videoURL.path) {
            try fileManager.trashItem(at: videoURL, resultingItemURL: &trashedURL)
        }
        items.removeAll { $0.id == item.id }
        do { try persist() } catch {
            if let trashedURL {
                do { try fileManager.moveItem(at: trashedURL as URL, to: videoURL); items = previousItems }
                catch {
                    errorMessage = L10n.tr("Videoen ligger i papirkurven, men bibliotekoversikten kunne ikke oppdateres. Fil: \(trashedURL.path ?? item.fileName)")
                    throw error
                }
            } else { items = previousItems }
            throw error
        }
        if let thumbnail = thumbnailURL(for: item) { try? fileManager.removeItem(at: thumbnail) }
    }

    private func persist() throws {
        if let storageFailure { throw storageFailure }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Manifest(items: items)).write(to: manifestURL, options: .atomic)
    }

    private static func safeFileName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\")
    }

    private func enrich(_ item: RecordingItem) async {
        guard fileManager.fileExists(atPath: url(for: item).path) else { return }
        let asset = AVURLAsset(url: url(for: item))
        let duration = (try? await asset.load(.duration).seconds) ?? item.duration
        guard !Task.isCancelled else { return }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 400)
        var thumbnail: String?
        if let frame = try? await generator.image(at: CMTime(seconds: min(0.35, max(0, duration / 2)), preferredTimescale: 600)) {
            let bitmap = NSBitmapImageRep(cgImage: frame.image)
            if let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) {
                let name = "\(item.id.uuidString).jpg"
                if (try? data.write(to: thumbnailsDirectory.appendingPathComponent(name), options: .atomic)) != nil { thumbnail = name }
            }
        }
        guard !Task.isCancelled, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        if duration.isFinite, duration > 0 { items[index].duration = duration }
        if let thumbnail { items[index].thumbnailName = thumbnail }
        do { try persist() } catch { errorMessage = L10n.tr("Videofilen er bevart, men oversikten kunne ikke lagres: \(error.localizedDescription)") }
    }
}
