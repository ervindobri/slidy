import Foundation
import Observation

/// Something the user opened before and can open again in one tap.
///
/// Paths alone aren't enough under the sandbox: permission to read a folder
/// dies with the launch that picked it. What survives is a security-scoped
/// bookmark, so that — not the path — is what gets stored. Photo-library
/// selections have no path to store at all; what persists there is the set of
/// asset identifiers, which are re-exported on demand.
struct RecentSource: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case files
        case photos
    }

    let id: String
    var kind: Kind
    var title: String
    var detail: String
    var openedAt: Date

    /// `files` only. One per URL the user picked.
    var bookmarks: [Data] = []

    /// `files` only. Kept alongside the bookmarks purely so an entry can still
    /// name itself when its bookmark no longer resolves.
    var paths: [String] = []

    /// `photos` only. `PHAsset` local identifiers.
    var assetIdentifiers: [String] = []

    var symbolName: String {
        switch kind {
        case .photos: "photo.stack"
        case .files: isSingleFolder ? "folder" : "doc.on.doc"
        }
    }

    /// A single directory reopens exactly as it was; a hand-picked list of files
    /// only reopens as far as its bookmarks still resolve.
    var isSingleFolder: Bool {
        guard kind == .files, paths.count == 1, let path = paths.first else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

/// The shortcut list on the empty screen, persisted in `UserDefaults`.
@MainActor
@Observable
final class RecentSources {

    /// Long enough to cover a few days of work, short enough to stay a shortcut
    /// rather than a file browser.
    static let limit = 8

    private static let defaultsKey = "recentSources"

    private(set) var entries: [RecentSource] = []

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    var isEmpty: Bool { entries.isEmpty }

    // MARK: - Recording

    /// Remembers a set of picked files or folders.
    ///
    /// Anything that can't be bookmarked is dropped rather than remembered as a
    /// path that would fail to open later.
    func remember(urls: [URL]) {
        let bookmarked = urls.compactMap { url -> (URL, Data)? in
            guard let data = FileBookmark.data(for: url) else { return nil }
            return (url, data)
        }
        guard !bookmarked.isEmpty else { return }

        let urls = bookmarked.map(\.0)
        let paths = urls.map(\.standardizedFileURL.path)

        insert(
            RecentSource(
                id: "files:" + paths.joined(separator: "\u{1}"),
                kind: .files,
                title: Self.title(for: urls),
                detail: Self.detail(for: urls),
                openedAt: .now,
                bookmarks: bookmarked.map(\.1),
                paths: paths
            )
        )
    }

    /// Remembers a photo-library selection by asset identifier.
    ///
    /// Items the picker gave no identifier for — which is what happens under
    /// limited library access — can't be fetched again, so a selection that has
    /// none of them isn't offered as a shortcut.
    func rememberPhotos(identifiers: [String]) {
        guard !identifiers.isEmpty else { return }

        insert(
            RecentSource(
                id: "photos:" + identifiers.joined(separator: "\u{1}"),
                kind: .photos,
                title: identifiers.count == 1 ? "1 photo library item" : "\(identifiers.count) photo library items",
                detail: "Photo Library",
                openedAt: .now,
                assetIdentifiers: identifiers
            )
        )
    }

    /// Moves an entry back to the top after it's opened again.
    func touch(_ entry: RecentSource) {
        guard var existing = entries.first(where: { $0.id == entry.id }) else { return }
        existing.openedAt = .now
        insert(existing)
    }

    /// Swaps in a bookmark that had gone stale, so the next open doesn't have to
    /// resolve it the slow way again.
    func refresh(_ entry: RecentSource, bookmarks: [Data]) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].bookmarks = bookmarks
        save()
    }

    // MARK: - Removing

    func remove(_ entry: RecentSource) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func removeAll() {
        entries.removeAll()
        save()
    }

    // MARK: - Storage

    private func insert(_ entry: RecentSource) {
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let stored = try? JSONDecoder().decode([RecentSource].self, from: data) else { return }
        entries = stored
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    // MARK: - Naming

    private static func title(for urls: [URL]) -> String {
        guard let first = urls.first else { return "Files" }
        if urls.count == 1 { return first.lastPathComponent }
        return "\(first.lastPathComponent) + \(urls.count - 1) more"
    }

    private static func detail(for urls: [URL]) -> String {
        guard let first = urls.first else { return "" }
        let folder = first.deletingLastPathComponent().path

        // Home-relative on the Mac, where the full path is long and the row is
        // narrow. On iOS the container path means nothing to anyone, but it's
        // also the only thing there is to show.
        #if os(macOS)
        return folder.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        #else
        return folder
        #endif
    }
}

/// Security-scoped bookmarks, which is how a sandboxed app gets to reopen a
/// folder it was given permission to read in an earlier launch.
enum FileBookmark {

    static func data(for url: URL) -> Data? {
        // The URL may or may not already be under access here — `open` starts it
        // for everything it takes in. Starting it again is fine as long as the
        // stop is balanced, and it's what makes this work when it isn't.
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }

        #if os(macOS)
        return try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        return try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    /// - Returns: the URL, and whether the bookmark should be written afresh.
    static func resolve(_ data: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false

        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif

        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: options,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        return (url, isStale)
    }
}
