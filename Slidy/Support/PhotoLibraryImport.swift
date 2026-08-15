import Foundation
import Photos

/// Re-opens a photo-library selection from the asset identifiers a recent entry
/// kept.
///
/// The picker hands over a copy of the file and nothing else, so a "recently
/// opened" photo selection can't be reopened the way a folder can — the copy is
/// deleted the moment the library is cleared. What's stable is the asset's local
/// identifier, and fetching by identifier means asking the system for real
/// library access rather than the picker's one-shot handover.
enum PhotoLibraryImport {

    enum Failure: LocalizedError {
        case notAuthorized
        case nothingFound

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                "Slidy needs access to your photo library to reopen this. You can grant it in Settings."
            case .nothingFound:
                "Those items are no longer in your photo library."
            }
        }
    }

    /// Asks for library access, returning whether reading is allowed.
    static func authorize() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let granted = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return granted == .authorized || granted == .limited
        default:
            return false
        }
    }

    /// Writes the named assets into Slidy's temporary directory.
    ///
    /// - Returns: file URLs in the order the identifiers were given, skipping
    ///   assets that are gone. Callers open these as `temporary` so they're
    ///   cleaned up with the rest.
    static func copyToTemporary(identifiers: [String]) async throws -> [URL] {
        guard await authorize() else { throw Failure.notAuthorized }

        // The fetch comes back in the library's own order, so it's indexed by
        // identifier and read back in the order the user picked.
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assets: [String: PHAsset] = [:]
        fetched.enumerateObjects { asset, _, _ in assets[asset.localIdentifier] = asset }

        var urls: [URL] = []
        for identifier in identifiers {
            guard let asset = assets[identifier], let resource = primaryResource(for: asset) else { continue }
            // One asset failing shouldn't sink the rest of the selection.
            if let url = try? await write(resource) { urls.append(url) }
        }

        guard !urls.isEmpty else { throw Failure.nothingFound }
        return urls
    }

    /// The full-quality original where there is one, and the edited version
    /// where the user has cropped or filtered the shot.
    private static func primaryResource(for asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        let preferred: [PHAssetResourceType] = asset.mediaType == .video
            ? [.fullSizeVideo, .video]
            : [.fullSizePhoto, .photo]

        for type in preferred {
            if let match = resources.first(where: { $0.type == type }) { return match }
        }
        return resources.first
    }

    private static func write(_ resource: PHAssetResource) async throws -> URL {
        let destination = try TemporaryStore.slot(named: resource.originalFilename)

        let options = PHAssetResourceRequestOptions()
        // iCloud-only originals are the common case on a phone that's been in
        // use for a while; without this they simply fail.
        options.isNetworkAccessAllowed = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(for: resource, toFile: destination, options: options) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        return destination
    }
}
