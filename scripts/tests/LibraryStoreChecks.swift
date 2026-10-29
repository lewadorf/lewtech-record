import Foundation

/// Metadata checks use dummy file bytes deliberately. Only the separate media
/// pipeline suite creates playable videos; file-index tests do not claim playback.
@MainActor
func runLibraryStoreChecks() async throws -> Int {
    let manager = FileManager.default
    let parent = manager.temporaryDirectory.appendingPathComponent("LewtechLibraryChecks-\(UUID().uuidString)", isDirectory: true)
    defer { try? manager.removeItem(at: parent) }
    let directory = parent.appendingPathComponent("library")
    let store = LibraryStore(directory: directory)
    try verificationRequire(store.items.isEmpty && store.errorMessage == nil, "Empty library creation failed")

    let file = directory.appendingPathComponent("preserved.mp4")
    let originalData = Data([1, 2, 3, 4])
    try originalData.write(to: file)
    store.reload()
    guard let item = store.items.first else { throw VerificationFailure(message: "Orphaned media was not indexed") }
    try store.rename(item, to: "  Prosjektgjennomgang  ")
    let reopened = LibraryStore(directory: directory)
    try verificationRequire(reopened.items.count == 1 && reopened.items.first?.id == item.id && reopened.items.first?.title == "Prosjektgjennomgang", "Renamed recording did not survive reload")
    let preservedData = try Data(contentsOf: file)
    try verificationRequire(preservedData == originalData, "Rename changed the media file")

    do {
        try reopened.rename(item, to: " \n\t ")
        throw VerificationFailure(message: "Empty recording name was accepted")
    } catch LibraryStore.LibraryError.emptyTitle {}
    try verificationRequire(reopened.items.first?.title == "Prosjektgjennomgang", "Failed rename replaced the title")

    let manifest = directory.appendingPathComponent("library.json")
    let corruptData = Data("{interrupted metadata write".utf8)
    try corruptData.write(to: manifest)
    reopened.reload()
    try verificationRequire(reopened.items.count == 1 && reopened.errorMessage != nil, "Corrupt index was not recovered with a warning")
    let backups = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasPrefix("library-backup-") }
    guard backups.count == 1, let backup = backups.first else { throw VerificationFailure(message: "Corrupt index backup is missing") }
    let backupData = try Data(contentsOf: backup)
    try verificationRequire(backupData == corruptData, "Metadata backup changed original bytes")
    let recoveredData = try Data(contentsOf: file)
    try verificationRequire(recoveredData == originalData, "Recovery changed original media")

    let futureFormat = Data("{\"version\":99,\"items\":[]}".utf8)
    try futureFormat.write(to: manifest)
    reopened.reload()
    do {
        try reopened.rename(item, to: "New title")
        throw VerificationFailure(message: "Unknown future metadata version was writable")
    } catch LibraryStore.LibraryError.unsupportedVersion {}
    let unchangedFormat = try Data(contentsOf: manifest)
    try verificationRequire(unchangedFormat == futureFormat, "Future metadata was overwritten")

    let isolated = parent.appendingPathComponent("isolated")
    let unsafeStore = LibraryStore(directory: isolated)
    let outside = parent.appendingPathComponent("outside.mp4")
    try originalData.write(to: outside)
    let unsafeJSON = """
    {"version":1,"items":[{"id":"\(UUID().uuidString)","title":"Outside","createdAt":0,"duration":1,"fileName":"../outside.mp4"}]}
    """
    try Data(unsafeJSON.utf8).write(to: isolated.appendingPathComponent("library.json"))
    unsafeStore.reload()
    try verificationRequire(unsafeStore.items.isEmpty && unsafeStore.errorMessage != nil, "Unsafe relative media path was accepted")
    let outsideData = try Data(contentsOf: outside)
    try verificationRequire(outsideData == originalData, "Unsafe index modified a file outside the library")

    let invalidVideo = parent.appendingPathComponent("incomplete.mp4")
    let invalidData = Data("not a completed video".utf8)
    try invalidData.write(to: invalidVideo)
    var rejected = false
    do { try await unsafeStore.addRecording(fileURL: invalidVideo, duration: 20) } catch { rejected = true }
    try verificationRequire(rejected && unsafeStore.items.isEmpty, "Invalid media was imported as a completed recording")
    let retainedInvalidData = try Data(contentsOf: invalidVideo)
    try verificationRequire(retainedInvalidData == invalidData, "Rejected video import lost its original bytes")
    return 7
}
