import CoreGraphics
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// One image, fitted to the page.
struct ImagePageView: View {
    let item: MediaItem

    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?
    @State private var failed = false
    
    @Namespace var namespace

    var body: some View {
        ZStack(alignment: .bottom) {
            
        
        GeometryReader { proxy in
            ZStack {
                if let image {
                    // Fills the card so its rounded shape reads whatever the
                    // photo's proportions are. Cropping the photo itself would
                    // do the same job, but this is a viewer — the sharp copy on
                    // top is always the whole picture.
                    Image(decorative: image, scale: 1, orientation: .up)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 30, opaque: true)
                        .overlay(Color.black.opacity(0.45))

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
            // Explicit size and a clip, so the filling backdrop above can't
            // spill past the card it's meant to be lining.
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            // Keyed on the file as well as the width: SwiftUI can hand this
            // view a different item while reusing it, and keying on width alone
            // leaves the previous photo on screen for the new page.
            .task(id: "\(item.url.path)-\(item.revision)-\(Int(proxy.size.width))") {
                await load(containerSize: proxy.size)
            }
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
    ImagePageView(item: MediaItem(url: URL(fileURLWithPath: "/Users/ervindobri/Pictures/images/KODAK/100_2943.JPG"),
                                kind: .image))
        .background(.black)
}

/// A picture to preview against, written into the app's own temporary directory.
///
/// Previews run inside the app sandbox, which reaches user-selected files plus
/// `~/Pictures` and `~/Movies` — and nothing else. Pointing a preview at an
/// absolute path somewhere like `~/Documents` fails the read, `decode` returns
/// nil, and the page shows "Can't be displayed" rather than the photo. The
/// temporary directory is always readable, and generating the file keeps the
/// preview working on any machine instead of only the one it was written on.
enum PreviewSample {
    static let image: URL = {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("slidy-preview-sample.jpg")
        guard !FileManager.default.fileExists(atPath: url.path) else { return url }

        let width = 1600
        let height = 1000
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return url }

        let gradient = CGGradient(
            colorsSpace: space,
            colors: [
                CGColor(red: 0.10, green: 0.13, blue: 0.30, alpha: 1),
                CGColor(red: 0.90, green: 0.42, blue: 0.20, alpha: 1)
            ] as CFArray,
            locations: [0, 1]
        )
        if let gradient {
            context.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: width, y: height),
                options: []
            )
        }
        // A couple of landmarks, so it's obvious which way up it is and whether
        // it's being cropped.
        context.setFillColor(CGColor(gray: 1, alpha: 0.9))
        context.fillEllipse(in: CGRect(x: 1180, y: 700, width: 200, height: 200))
        context.setFillColor(CGColor(gray: 0, alpha: 0.4))
        context.fill(CGRect(x: 0, y: 0, width: width, height: 220))

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
              ) else { return url }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return url
    }()
}

#Preview("Unreadable") {
    UnreadableMediaView(name: "100_2943.JPG")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
}
