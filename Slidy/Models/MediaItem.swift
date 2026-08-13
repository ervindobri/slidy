import Foundation
import UniformTypeIdentifiers

/// The only two things Slidy knows how to show.
enum MediaKind: Hashable {
    case image
    case video
}

struct MediaItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let kind: MediaKind

    var displayName: String {
        url.deletingPathExtension().lastPathComponent
    }
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
