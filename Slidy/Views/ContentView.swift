import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif

struct ContentView: View {
    @Environment(MediaLibrary.self) private var library

    @State private var isPresentingImporter = false
    @State private var isDropTargeted = false
    @State private var isImportingPhotos = false
    @State private var notice: String?
    
    @Namespace private var namespace

    #if os(iOS)
    @State private var photoSelection: [PhotosPickerItem] = []
    #endif

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

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if library.isEmpty {
                EmptyStateView(isDropTargeted: isDropTargeted) {
                    
                    CapsuleActionLabel(title: "Open Files", systemImage: "folder") {
                        isPresentingImporter = true
                    }
                    #if os(iOS)
                    PhotosPicker(
                        selection: $photoSelection,
                        selectionBehavior: .ordered,
                        matching: .any(of: [.images, .videos])
                    ) {
                        CapsuleActionLabel(title: "Photo Library", systemImage: "photo")
                    }
                    #endif
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
        #if os(iOS)
        .onChange(of: photoSelection) { _, selection in
            guard !selection.isEmpty else { return }
            Task { await importFromPhotos(selection) }
        }
        #endif
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
        Text((library.currentItem?.displayName ?? "") + "." + (library.currentItem?.url.pathExtension ?? ""))
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
                        .padding(16.0).glassEffect()
                }
            } else {
                // Fallback on earlier versions
                itemTitle
            }

            Spacer(minLength: 12)

            #if os(iOS)
            PhotosPicker(
                selection: $photoSelection,
                selectionBehavior: .ordered,
                matching: .any(of: [.images, .videos])
            ) {
                GlassIcon(systemName: "photo")
            }
            #endif
            if #available(macOS 26.0, iOS 26.0, *) {
                GlassEffectContainer(spacing: 24.0) {
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
        .padding(.vertical, 12)
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
        MediaProgressIndicator(index: library.currentIndex, count: library.items.count)
            .padding(.top, 30)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity)
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
        }
    }

    #if os(iOS)
    private func importFromPhotos(_ selection: [PhotosPickerItem]) async {
        isImportingPhotos = true
        defer {
            isImportingPhotos = false
            photoSelection = []
        }

        var urls: [URL] = []
        for item in selection {
            if let picked = try? await item.loadTransferable(type: PickedMedia.self) {
                urls.append(picked.url)
            }
        }

        let added = library.open(urls: urls, temporary: true)
        if added == 0 {
            notice = "Those items couldn't be loaded from your library."
        }
    }
    #endif
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
}
