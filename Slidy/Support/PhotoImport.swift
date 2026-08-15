import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A photo-library item copied into Slidy's temporary directory so it can be
/// played or decoded from a plain file URL.
struct PickedMedia: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            PickedMedia(url: try TemporaryStore.take(received.file))
        }
        FileRepresentation(importedContentType: .movie) { received in
            PickedMedia(url: try TemporaryStore.take(received.file))
        }
    }
}

enum TemporaryStore {
    /// Copies a transferred file into a private folder we are free to delete later.
    static func take(_ file: URL) throws -> URL {
        let destination = try slot(named: file.lastPathComponent)
        try FileManager.default.copyItem(at: file, to: destination)
        return destination
    }

    /// An unused path in a private folder, for callers that write the file
    /// themselves rather than copying one that already exists.
    static func slot(named name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SlidyImports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(name)
    }
}
