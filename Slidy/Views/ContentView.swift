import SwiftUI
import UniformTypeIdentifiers
// PhotosPicker is macOS 13+ / iOS 16+, so the library button is not iOS-only.
import PhotosUI

struct ContentView: View {
    @Environment(MediaLibrary.self) private var library
    @Environment(RecentSources.self) private var recents

    @State private var isPresentingImporter = false
    @State private var isDropTargeted = false
    @State private var isImportingPhotos = false
    @State private var notice: String?
    
    @Namespace private var namespace

    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var isPresentingPhotoPicker = false

    /// Everything Slidy will open: stills, movies, and folders of them.
    private var openableTypes: [UTType] { [.image, .movie, .folder] }

    private var noticeBinding: Binding<Bool> {
        Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
    }

    /// The window's title bar is hidden on macOS, so the top bar has to step
    /// around the close/minimise/zoom buttons.
    private var leadingChromeInset: CGFloat {
        #if os(macOS)
        78
        #else
        16
        #endif
    }

    /// The title pill is roomy on a Mac and tight on a phone, where the same
    /// padding leaves the buttons nowhere to go.
    private var titlePadding: CGFloat {
        #if os(macOS)
        16
        #else
        10
        #endif
    }

    /// iOS draws the bar under the status bar, which is already padding.
    private var topBarVerticalPadding: CGFloat {
        #if os(macOS)
        12
        #else
        6
        #endif
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if library.isEmpty {
                EmptyStateView(isDropTargeted: isDropTargeted) {
                    
                    VStack(spacing: 0.0) {
                        CapsuleActionLabel(title: "Open Files", systemImage: "folder") {
                            isPresentingImporter = true
                        }
                        // Presented from a plain button rather than wrapping the
                        // pill in a PhotosPicker: CapsuleActionLabel is itself a
                        // Button, and a Button inside a picker's label eats the
                        // tap, so the picker never comes up.
                        CapsuleActionLabel(title: "Photo Library", systemImage: "photo") {
                            isPresentingPhotoPicker = true
                        }
                        if !recents.isEmpty {
                            Spacer().frame(maxHeight: 24.0)
                            RecentSourcesView(
                                entries: recents.entries,
                                open: { entry in reopen(entry) },
                                remove: { recents.remove($0) }
                            )
                        }
                    }
                }
            } else {
                MediaPagerView()
                overlay
            }

            if isImportingPhotos {
                importProgress
            }
        }
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
        .dropDestination(for: URL.self) { urls, _ in
            open(urls: urls)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .fileImporter(
            isPresented: $isPresentingImporter,
            allowedContentTypes: openableTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): open(urls: urls)
            case .failure(let error): notice = error.localizedDescription
            }
        }
        .photosPicker(
            isPresented: $isPresentingPhotoPicker,
            selection: $photoSelection,
            maxSelectionCount: nil,
            selectionBehavior: .ordered,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: photoSelection) { _, selection in
            guard !selection.isEmpty else { return }
            Task { await importFromPhotos(selection) }
        }
        .alert("Nothing to show", isPresented: noticeBinding, presenting: notice) { _ in
            Button("OK", role: .cancel) {}
        } message: { text in
            Text(text)
        }
    }

    // MARK: - Chrome

    private var overlay: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            bottomBar
        }
        .ignoresSafeArea(edges: .horizontal)
    }
    
    
    private var itemTitle: some View {
        Text(library.currentItem?.displayFileName ?? "")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.75))
            .lineLimit(1)
            .truncationMode(.middle)
            .id(library.currentItem) // Tells SwiftUI to replace the view when 'count' changes
                            .transition(.asymmetric(
                                insertion: .push(from: .bottom), // Slides in from bottom
                                removal: .push(from: .bottom)    // Pushes old text up
                            ))
    }

    private var topBar: some View {

        
        HStack(spacing: 10) {
            if #available(macOS 26.0, iOS 26.0, *) {
                GlassEffectContainer {
                    itemTitle
                        .padding(.horizontal, titlePadding)
                        .padding(.vertical, titlePadding * 0.6)
                        .glassEffect()
                }
                // The filename is the one thing here that can be any length, so
                // it's what gives way when the row runs out of room. Without
                // this the buttons are the ones that get squeezed, and on a
                // phone they end up overlapping.
                .layoutPriority(-1)
            } else {
                // Fallback on earlier versions
                itemTitle
                    .layoutPriority(-1)
            }

            // Keeps the controls against the trailing edge rather than trailing
            // the title around as it changes length.
            Spacer(minLength: 8)

            Button { isPresentingPhotoPicker = true } label: {
                GlassIcon(systemName: "photo")
            }
            .help("Open from your photo library")
            if #available(macOS 26.0, iOS 26.0, *) {
                // The container's own `spacing` is how close two pieces of glass
                // have to be before they flow into one — it lays nothing out. Its
                // contents still need a stack, or all three buttons land on top
                // of each other in the corner.
                GlassEffectContainer(spacing: 24.0) {
                    HStack(spacing: 8) {
                        slideshowButton
                            .buttonStyle(.smallLiquidGlass)
                            .glassEffectUnion(id: "1", namespace: namespace)

                        Button { isPresentingImporter = true } label: {
                            GlassIcon(systemName: "folder")
                        }
                        .buttonStyle(.smallLiquidGlass)
                        .glassEffectUnion(id: "1", namespace: namespace)
                        .help("Open files or a folder")

                        Button { library.clear() } label: {
                            GlassIcon(systemName: "xmark")
                        }
                        .buttonStyle(.smallLiquidGlass)
                        .glassEffectUnion(id: "1", namespace: namespace)
                        .help("Close")
                    }
                }
            } else {
                // Fallback on earlier versions
                slideshowButton

                Button { isPresentingImporter = true } label: {
                    GlassIcon(systemName: "folder")
                }
                .help("Open files or a folder")

                Button { library.clear() } label: {
                    GlassIcon(systemName: "xmark")
                }
                .help("Close")
            }
        }
        .buttonStyle(.borderless)
        .padding(.leading, leadingChromeInset)
        .padding(.trailing, 16)
        .padding(.vertical, topBarVerticalPadding)
        .background {
            LinearGradient(
                colors: [.black.opacity(0.55), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
    }

    /// Starts and stops the hands-off run through the open media.
    private var slideshowButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { library.toggleSlideshow() }
        } label: {
            GlassIcon(systemName: library.isSlideshowRunning ? "pause.fill" : "play.fill")
        }
        .help(library.isSlideshowRunning ? "Stop slideshow" : "Play slideshow")
        .disabled(library.items.count < 2)
    }

    private var bottomBar: some View {
        VStack(spacing: 14) {
            MediaActions()
            MediaProgressIndicator(index: library.currentIndex, count: library.items.count)
        }
        .padding(.top, 16)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        // The scrim covers the whole bar, actions included. Hung on the stack
        // rather than on the indicator alone, which left the buttons sitting
        // over bare photo with nothing behind them to read against.
        .background {
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
    }

    private var importProgress: some View {
        ProgressView()
            .controlSize(.large)
            .tint(.white)
            .padding(26)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Loading

    private func open(urls: [URL]) {
        let added = library.open(urls: urls)
        if added == 0 {
            notice = "That selection didn't contain any images or videos."
            return
        }
        recents.remember(urls: urls)
    }

    /// Opens a shortcut from the recents list.
    private func reopen(_ entry: RecentSource) {
        switch entry.kind {
        case .files:
            reopenFiles(entry)
        case .photos:
            Task { await reopenPhotos(entry) }
        }
    }

    private func reopenFiles(_ entry: RecentSource) {
        var urls: [URL] = []
        var refreshed: [Data] = []
        var didGoStale = false

        for bookmark in entry.bookmarks {
            guard let resolved = FileBookmark.resolve(bookmark) else { continue }
            urls.append(resolved.url)

            // A stale bookmark still resolves — the file has just moved or the
            // volume was remounted — but it won't keep doing so forever, so it's
            // written back while we hold access to the URL it points at.
            if resolved.isStale, let fresh = FileBookmark.data(for: resolved.url) {
                refreshed.append(fresh)
                didGoStale = true
            } else {
                refreshed.append(bookmark)
            }
        }

        guard !urls.isEmpty else {
            // Nothing left to point at: drop the shortcut rather than leave a
            // row that does nothing when tapped.
            recents.remove(entry)
            notice = "\(entry.title) has moved or is no longer available."
            return
        }

        let added = library.open(urls: urls)
        if added == 0 {
            notice = "\(entry.title) no longer contains any images or videos."
            return
        }

        if didGoStale { recents.refresh(entry, bookmarks: refreshed) }
        recents.touch(entry)
    }

    private func reopenPhotos(_ entry: RecentSource) async {
        isImportingPhotos = true
        defer { isImportingPhotos = false }

        do {
            let urls = try await PhotoLibraryImport.copyToTemporary(identifiers: entry.assetIdentifiers)
            let added = library.open(urls: urls, temporary: true)
            if added == 0 {
                notice = "Those items couldn't be loaded from your library."
                return
            }
            recents.touch(entry)
        } catch {
            notice = error.localizedDescription
        }
    }

    private func importFromPhotos(_ selection: [PhotosPickerItem]) async {
        isImportingPhotos = true
        defer {
            isImportingPhotos = false
            photoSelection = []
        }

        var urls: [URL] = []
        var identifiers: [String] = []
        var failure: String?
        for item in selection {
            do {
                if let picked = try await item.loadTransferable(type: PickedMedia.self) {
                    urls.append(picked.url)
                    // The copy under `picked.url` is deleted when the library is
                    // cleared, so the identifier is the only part of this worth
                    // remembering.
                    if let identifier = item.itemIdentifier { identifiers.append(identifier) }
                }
            } catch {
                // Keep going through the rest of the selection, but hold on to
                // the reason so a total failure says something more useful than
                // "couldn't be loaded".
                failure = failure ?? error.localizedDescription
            }
        }

        let added = library.open(urls: urls, temporary: true)
        if added == 0 {
            notice = failure ?? "Those items couldn't be loaded from your library."
            return
        }
        recents.rememberPhotos(identifiers: identifiers)
    }
}




/// Small translucent round button face used by the top bar.
struct GlassIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(.ultraThinMaterial, in: Circle())
            .contentShape(Circle())
    }
}

#Preview {
    ContentView()
        .environment(MediaLibrary())
        .environment(RecentSources())
}
