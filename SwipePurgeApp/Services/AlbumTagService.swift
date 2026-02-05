import Foundation
import Photos
import Combine

@MainActor
final class AlbumTagService: ObservableObject {
    private var cache: [String: [String]] = [:]
    var cacheCount: Int { cache.count }

    func albumTags(assetId: String) -> [String] {
        if let cached = cache[assetId] { return cached }

        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = fetch.firstObject else { return [] }

        let collections = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
        var names: [String] = []
        collections.enumerateObjects { collection, _, _ in
            guard collection.assetCollectionType == .album else { return }
            if collection.assetCollectionSubtype == .albumRegular || collection.assetCollectionSubtype == .albumCloudShared {
                if let title = collection.localizedTitle { names.append(title) }
            }
        }

        let filtered = names.filter { name in
            name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "others"
        }

        cache[assetId] = filtered
        return filtered
    }

    func prefetch(assetIds: [String]) {
        for id in assetIds where cache[id] == nil {
            _ = albumTags(assetId: id)
        }
    }
}
