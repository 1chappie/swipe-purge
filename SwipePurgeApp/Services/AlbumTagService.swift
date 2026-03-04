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

    func invalidate(assetId: String) {
        cache[assetId] = nil
    }
}

struct AlbumShortcut: Identifiable, Equatable {
    let albumId: String
    let title: String

    var id: String { albumId }
}

struct AlbumShortcutChoice: Identifiable, Equatable {
    let albumId: String
    let title: String

    var id: String { albumId }
}

@MainActor
final class AlbumShortcutStore: ObservableObject {
    @Published private(set) var shortcuts: [AlbumShortcut] = []
    @Published private(set) var availableAlbums: [AlbumShortcutChoice] = []
    @Published var includeHidden: Bool = false

    private let storageKey = "SwipePurge.AlbumShortcutIDs"
    private let includeHiddenKey = "SwipePurge.IncludeHiddenAssets"
    private let limit = 10
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        includeHidden = defaults.bool(forKey: includeHiddenKey)
        refreshAlbums()
    }

    var maxShortcuts: Int { limit }

    var hasReachedLimit: Bool {
        shortcuts.count >= limit
    }

    func setIncludeHidden(_ shouldInclude: Bool) {
        guard includeHidden != shouldInclude else { return }
        includeHidden = shouldInclude
        defaults.set(shouldInclude, forKey: includeHiddenKey)
    }

    func refreshAlbums() {
        let choices = fetchAlbumChoices()
        let choiceMap = Dictionary(uniqueKeysWithValues: choices.map { ($0.albumId, $0) })
        let storedIds = loadStoredShortcutIDs()
        let resolvedShortcuts: [AlbumShortcut] = storedIds.compactMap { id in
            guard let choice = choiceMap[id] else { return nil }
            return AlbumShortcut(albumId: choice.albumId, title: choice.title)
        }

        availableAlbums = choices
        if resolvedShortcuts != shortcuts {
            shortcuts = resolvedShortcuts
        }

        let resolvedIds = resolvedShortcuts.map { $0.albumId }
        if resolvedIds != storedIds {
            saveShortcutIDs(resolvedIds)
        }
    }

    func addShortcut(albumId: String) {
        guard !shortcuts.contains(where: { $0.albumId == albumId }), shortcuts.count < limit else { return }
        guard let choice = availableAlbums.first(where: { $0.albumId == albumId }) else { return }
        shortcuts.append(AlbumShortcut(albumId: choice.albumId, title: choice.title))
        saveCurrentShortcuts()
    }

    func removeShortcut(albumId: String) {
        guard shortcuts.contains(where: { $0.albumId == albumId }) else { return }
        shortcuts.removeAll { $0.albumId == albumId }
        saveCurrentShortcuts()
    }

    func moveShortcut(albumId: String, by offset: Int) {
        guard let index = shortcuts.firstIndex(where: { $0.albumId == albumId }) else { return }
        let destination = index + offset
        guard shortcuts.indices.contains(destination) else { return }
        let shortcut = shortcuts.remove(at: index)
        shortcuts.insert(shortcut, at: destination)
        saveCurrentShortcuts()
    }

    func moveShortcut(albumId: String, to targetAlbumId: String) {
        guard albumId != targetAlbumId else { return }
        guard let sourceIndex = shortcuts.firstIndex(where: { $0.albumId == albumId }) else { return }
        guard let targetIndex = shortcuts.firstIndex(where: { $0.albumId == targetAlbumId }) else { return }

        let shortcut = shortcuts.remove(at: sourceIndex)
        shortcuts.insert(shortcut, at: min(targetIndex, shortcuts.count))
        saveCurrentShortcuts()
    }

    func containsAsset(_ assetId: String, in albumId: String) -> Bool {
        let fetch = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumId], options: nil)
        guard let collection = fetch.firstObject else { return false }

        let options = PHFetchOptions()
        options.fetchLimit = 1
        options.predicate = NSPredicate(format: "localIdentifier == %@", assetId)
        let matching = PHAsset.fetchAssets(in: collection, options: options)
        return matching.count > 0
    }

    func setAsset(_ assetId: String, in albumId: String, shouldContain: Bool) async throws {
        let assetFetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        let albumFetch = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumId], options: nil)
        guard let collection = albumFetch.firstObject, assetFetch.count > 0 else {
            throw NSError(domain: "SwipePurge", code: 3, userInfo: [NSLocalizedDescriptionKey: "Album not available"])
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                guard let request = PHAssetCollectionChangeRequest(for: collection) else { return }
                if shouldContain {
                    request.addAssets(assetFetch)
                } else {
                    request.removeAssets(assetFetch)
                }
            }, completionHandler: { success, error in
                if let error {
                    cont.resume(throwing: error)
                } else if success {
                    cont.resume(returning: ())
                } else {
                    cont.resume(throwing: NSError(domain: "SwipePurge", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unable to update album membership"]))
                }
            })
        }
    }

    private func fetchAlbumChoices() -> [AlbumShortcutChoice] {
        let fetch = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        var choices: [AlbumShortcutChoice] = []
        choices.reserveCapacity(fetch.count)

        fetch.enumerateObjects { collection, _, _ in
            guard collection.assetCollectionType == .album else { return }
            guard collection.assetCollectionSubtype == .albumRegular || collection.assetCollectionSubtype == .albumCloudShared else { return }
            let title = (collection.localizedTitle ?? "Untitled Album").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return }
            if title.lowercased() == "others" { return }
            choices.append(AlbumShortcutChoice(albumId: collection.localIdentifier, title: title))
        }

        return choices.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func loadStoredShortcutIDs() -> [String] {
        (defaults.array(forKey: storageKey) as? [String]) ?? []
    }

    private func saveCurrentShortcuts() {
        saveShortcutIDs(shortcuts.map(\.albumId))
    }

    private func saveShortcutIDs(_ ids: [String]) {
        defaults.set(ids, forKey: storageKey)
    }
}
