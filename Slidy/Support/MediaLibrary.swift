import Foundation
import Observation

/// Holds the currently open set of media and the page the viewer is on.
///
/// Also owns the lifetime of the security-scoped URLs the user picked: access is
/// started when a file enters the library and stopped when it leaves.
@MainActor
@Observable
final class MediaLibrary {

    private(set) var items: [MediaItem] = []

    /// The page currently filling the screen. Bound to the pager's scroll position.
    var currentID: MediaItem.ID? {
        didSet {
            guard oldValue != currentID else { return }
            restartDwell()
        }
    }

    /// Whether pages are advancing on their own.
    var isSlideshowRunning = false

    /// How long a still is held before the slideshow moves on. Videos ignore
    /// this and run to their own end.
    static let stillSeconds: TimeInterval = 3

    private var scopedURLs: [URL] = []
    private var temporaryCopies: [URL] = []

    var isEmpty: Bool { items.isEmpty }

    var currentIndex: Int {
        guard let currentID, let index = items.firstIndex(where: { $0.id == currentID }) else { return 0 }
        return index
    }

    var currentItem: MediaItem? {
        items.indices.contains(currentIndex) ? items[currentIndex] : nil
    }

    // MARK: - Opening

    /// Replaces the library with the media found at `urls`.
    ///
    /// Directories are expanded; non-media files are ignored.
    /// - Parameter temporary: files Slidy itself created (e.g. Photos imports) and
    ///   should delete when they are no longer shown.
    /// - Returns: how many viewable files were found.
    @discardableResult
    func open(urls: [URL], temporary: Bool = false) -> Int {
        clear()
        return append(urls: urls, temporary: temporary)
    }

    /// Adds the media found at `urls` to the end of the library.
    /// - Returns: how many viewable files were added.
    @discardableResult
    func append(urls: [URL], temporary: Bool = false) -> Int {
        var discovered: [MediaItem] = []
        var seen = Set(items.map(\.url.standardizedFileURL))

        for url in urls {
            let needsScope = url.startAccessingSecurityScopedResource()
            if needsScope { scopedURLs.append(url) }
            if temporary { temporaryCopies.append(url) }

            for file in Self.expand(url) {
                let standardized = file.standardizedFileURL
                guard !seen.contains(standardized), let kind = MediaKind.classify(file) else { continue }
                seen.insert(standardized)
                discovered.append(MediaItem(url: file, kind: kind))
            }
        }

        guard !discovered.isEmpty else { return 0 }
        items.append(contentsOf: discovered)
        if currentID == nil { currentID = items.first?.id }
        return discovered.count
    }

    func clear() {
        items.removeAll()
        currentID = nil
        isSlideshowRunning = false
        ticker?.cancel()
        ticker = nil

        for url in scopedURLs { url.stopAccessingSecurityScopedResource() }
        scopedURLs.removeAll()

        for url in temporaryCopies { try? FileManager.default.removeItem(at: url) }
        temporaryCopies.removeAll()
    }
    
    // MARK: - Editing

    /// Why the last delete or rotate failed, for the UI to surface. Cleared on
    /// the next attempt.
    var actionError: String?

    /// Turns the current still a quarter turn clockwise and writes it back.
    ///
    /// - Returns: whether anything was rotated.
    @discardableResult
    func rotateImage() -> Bool {
        actionError = nil

        guard let item = currentItem, item.kind == .image else { return false }
        let index = currentIndex

        do {
            try ImageRotation.rotateClockwise(at: item.url)
        } catch {
            actionError = error.localizedDescription
            return false
        }

        // The file is at the same path as before, so nothing downstream would
        // notice it had changed without being told.
        items[index].markChanged()
        return true
    }

    // MARK: - Deleting

    /// Takes the current item out of the library and off the disk.
    ///
    /// - Returns: whether anything was deleted.
    @discardableResult
    func deleteCurrent() -> Bool {
        actionError = nil

        // Read the item *and* its index before touching the array. Removing
        // first leaves `currentID` pointing at something that no longer exists,
        // at which point `currentIndex` quietly answers 0 and `currentItem`
        // resolves to a different file — which is the one that would be erased.
        guard let item = currentItem else { return false }
        let index = currentIndex

        do {
            try discard(item)
        } catch {
            // The file is still there, so the item stays in the list too:
            // better to show a set that matches the disk than one that doesn't.
            actionError = error.localizedDescription
            return false
        }

        items.remove(at: index)
        selectAfterRemoval(at: index)
        return true
    }

    /// Sends a file to the Trash where there is one, and deletes it outright
    /// where there isn't.
    ///
    /// The original is what goes: for a converted clip `url` points at the
    /// re-encoded copy in our own container, and deleting only that would leave
    /// the file the user actually asked to be rid of sitting on the disk. The
    /// conversion goes too, or the cache keeps serving a deleted photo back.
    private func discard(_ item: MediaItem) throws {
        #if os(macOS)
        try FileManager.default.trashItem(at: item.originalURL, resultingItemURL: nil)
        #else
        try FileManager.default.removeItem(at: item.originalURL)
        #endif

        if item.isConverted {
            try? FileManager.default.removeItem(at: item.url)
        }
    }

    /// Moves to whatever slid into the deleted item's place, or the one before
    /// it if the last page was the one that went.
    ///
    /// Sets `currentID` directly rather than going through `step`, which takes
    /// a *delta* and measures it from a `currentIndex` that no longer resolves.
    private func selectAfterRemoval(at index: Int) {
        guard !items.isEmpty else {
            isSlideshowRunning = false
            ticker?.cancel()
            ticker = nil
            currentID = nil
            return
        }
        currentID = items[min(index, items.count - 1)].id
    }

    // MARK: - Navigation

    /// Moves `delta` pages, clamped to the ends.
    func step(_ delta: Int) {
        guard !items.isEmpty else { return }
        let target = min(max(currentIndex + delta, 0), items.count - 1)
        currentID = items[target].id
    }

    var canStepBackward: Bool { !items.isEmpty && currentIndex > 0 }
    var canStepForward: Bool { !items.isEmpty && currentIndex < items.count - 1 }

    // MARK: - Conversion

    /// Points an item at a playable conversion of itself.
    ///
    /// The item keeps its identity, so the page stays where it is in the strip
    /// and the viewer isn't scrolled somewhere else mid-conversion.
    func useConverted(_ url: URL, for id: MediaItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].url = url
    }

    // MARK: - Slideshow

    /// When the current still has had its turn.
    ///
    /// A deadline rather than a per-page timer task: the pager writes
    /// `currentID` back as it settles, so anything keyed on that identity gets
    /// torn down and restarted at unpredictable moments and can miss its turn
    /// entirely. `nil` while a video is showing — a video is timed by its own
    /// length — and while the slideshow is stopped.
    private var stillDeadline: Date?

    /// Drives the dwell while the slideshow runs.
    ///
    /// Owned here rather than by a view's `.task`: a view-attached task only
    /// restarts when its id changes, so if SwiftUI ever tears it down for its
    /// own reasons the slideshow silently stops and never comes back.
    @ObservationIgnored private var ticker: Task<Void, Never>?

    func toggleSlideshow() {
        guard !items.isEmpty else { return }
        isSlideshowRunning.toggle()
        restartDwell()

        if isSlideshowRunning {
            ticker?.cancel()
            ticker = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard let self, !Task.isCancelled, self.isSlideshowRunning else { return }
                    self.tickSlideshow()
                }
            }
        } else {
            ticker?.cancel()
            ticker = nil
        }
    }

    /// Gives the current page a fresh turn. Called on every page change, so a
    /// manual swipe mid-slideshow gets the full three seconds too.
    func restartDwell() {
        guard isSlideshowRunning, currentItem?.kind == .image else {
            stillDeadline = nil
            return
        }
        stillDeadline = Date().addingTimeInterval(Self.stillSeconds)
    }

    /// Driven by a steady tick while the slideshow runs.
    func tickSlideshow(now: Date = Date()) {
        guard isSlideshowRunning, let stillDeadline, now >= stillDeadline else { return }
        advanceSlideshow()
    }

    /// The slideshow's own advance: wraps to the start instead of stopping at
    /// the last page, so a folder plays round continuously.
    func advanceSlideshow() {
        guard isSlideshowRunning, !items.isEmpty else { return }
        currentID = items[(currentIndex + 1) % items.count].id
    }

    // MARK: - Discovery

    /// Returns the file itself, or every file inside it when `url` is a directory.
    private static func expand(_ url: URL) -> [URL] {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        guard isDirectory else { return [url] }

        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .contentTypeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        let files = (enumerator?.allObjects as? [URL]) ?? []
        return files
            .filter { ((try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) == false }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
