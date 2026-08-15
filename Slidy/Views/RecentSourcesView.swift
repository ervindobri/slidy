import SwiftUI

/// The shortcut list under the two open buttons on the empty screen.
struct RecentSourcesView: View {
    let entries: [RecentSource]
    let open: (RecentSource) -> Void
    let remove: (RecentSource) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recently opened")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .textCase(.uppercase)
                .padding(.leading, 6)

            // Scrolls rather than growing: the list is capped at eight, which is
            // still taller than an iPhone has room for under the buttons.
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(entries) { entry in
                        RecentSourceRow(entry: entry) { open(entry) }
                            .contextMenu {
                                Button("Remove from Recents", role: .destructive) { remove(entry) }
                            }
                    }
                }
            }
            .frame(maxHeight: 190)
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: 340)
    }
}

private struct RecentSourceRow: View {
    let entry: RecentSource
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: entry.symbolName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(entry.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(isHovering ? 0.14 : 0.06))
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(entry.detail)
    }
}

#Preview {
    RecentSourcesView(
        entries: [
            RecentSource(
                id: "1",
                kind: .files,
                title: "Iceland 2025",
                detail: "~/Pictures",
                openedAt: .now,
                paths: ["/Users/me/Pictures/Iceland 2025"]
            ),
            RecentSource(
                id: "2",
                kind: .photos,
                title: "24 photo library items",
                detail: "Photo Library",
                openedAt: .now,
                assetIdentifiers: ["a", "b"]
            )
        ],
        open: { _ in },
        remove: { _ in }
    )
    .padding(40)
    .background(.black)
}
