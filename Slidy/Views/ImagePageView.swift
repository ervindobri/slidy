import SwiftUI

/// One image, fitted to the page.
struct ImagePageView: View {
    let item: MediaItem

    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image {
                    Image(decorative: image, scale: 1, orientation: .up)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                } else if failed {
                    UnreadableMediaView(name: item.displayName)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Keyed on the file as well as the width: SwiftUI can hand this
            // view a different item while reusing it, and keying on width alone
            // leaves the previous photo on screen for the new page.
            .task(id: "\(item.url.path)-\(Int(proxy.size.width))") {
                await load(containerSize: proxy.size)
            }
        }
    }

    private func load(containerSize: CGSize) async {
        let longestEdge = max(containerSize.width, containerSize.height)
        guard longestEdge > 0 else { return }

        let target = longestEdge * displayScale
        let url = item.url

        let decoded = await ImageDecodeQueue.shared.decode(url: url, maxPixelSize: target)

        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            image = decoded
            failed = decoded == nil
        }
    }
}

/// Shown when a file can't be decoded — a broken JPEG, an unsupported codec.
struct UnreadableMediaView: View {
    let name: String
    var detail: String?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34, weight: .light))
            Text(name)
                .font(.callout)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(detail ?? "Can't be displayed")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.7))
        .padding(40)
    }
}

#Preview("Image") {
    // Point this at a real file on disk to preview decoding. `url` needs a URL,
    // not a String, and `~` isn't expanded — use an absolute path.
    ImagePageView(item: MediaItem(
        url: URL(fileURLWithPath: "/Users/ervindobri/Documents/images/KODAK/100_2943.JPG"),
        kind: .image
    ))
    .background(.black)
}

#Preview("Unreadable") {
    UnreadableMediaView(name: "100_2943.JPG")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
}
