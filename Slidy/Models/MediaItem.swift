import Foundation
import UniformTypeIdentifiers

/// The only two things Slidy knows how to show.
enum MediaKind: Hashable {
    case image
    case video
}

struct MediaItem: Identifiable, Hashable {
    let id = UUID()

    /// Where the file being shown lives. Not `let`: a video the system can't
    /// decode gets converted, and the item is then pointed at the conversion
    /// without losing its identity or its place in the run.
    var url: URL

    let kind: MediaKind

    /// The file this item was opened from, which stays put across a conversion.
    private(set) var originalURL: URL

    /// Bumped whenever the file changes underneath us. Rotating rewrites it in
    /// place, so the path on its own can't tell a page it needs decoding again.
    private(set) var revision = 0

    mutating func markChanged() { revision += 1 }

    init(url: URL, kind: MediaKind) {
        self.url = url
        self.kind = kind
        self.originalURL = url
    }

    /// The name is taken from the original, so a converted clip still shows up
    /// under the name the user knows it by rather than its cache filename.
    var displayName: String {
        originalURL.deletingPathExtension().lastPathComponent
    }

    /// Name as the user knows it, extension included — always the original's,
    /// so a converted clip doesn't appear to have changed on disk.
    var displayFileName: String { originalURL.lastPathComponent }

    var isConverted: Bool { url != originalURL }
}

extension MediaKind {
    /// Classifies a file, returning `nil` for anything that isn't viewable media.
    ///
    /// The on-disk content type is preferred over the path extension, so a
    /// mislabelled file can't sneak past as media.
    static func classify(_ url: URL) -> MediaKind? {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension.lowercased())

        guard let type else { return nil }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        return nil
    }
}
