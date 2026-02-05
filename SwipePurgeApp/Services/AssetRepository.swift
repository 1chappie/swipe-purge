import Foundation
import Photos
import PhotosUI

struct MonthSection: Identifiable {
    let id: String
    let title: String
    let assetIds: [String]
}

final class AssetRepository {
    func fetchAllAssetIdsChronological() -> [String] {
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "isHidden == NO")
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let result = PHAsset.fetchAssets(with: opts)
        var withDate: [String] = []
        var withoutDate: [String] = []
        withDate.reserveCapacity(result.count)
        withoutDate.reserveCapacity(8)

        result.enumerateObjects { asset, _, _ in
            if asset.creationDate == nil {
                withoutDate.append(asset.localIdentifier)
            } else {
                withDate.append(asset.localIdentifier)
            }
        }

//        let recentlyDeleted = fetchRecentlyDeletedIds()
//        if recentlyDeleted.isEmpty {
//            return withDate + withoutDate
//        }
//
        let filtered = withDate/*.filter { !recentlyDeleted.contains($0) }*/
        let filteredNil = withoutDate/*.filter { !recentlyDeleted.contains($0) }*/
        return filtered + filteredNil
    }

    func buildMonthSections(assetIds: [String]) -> [MonthSection] {
        guard !assetIds.isEmpty else { return [] }

        let idToDate = creationDateMap(assetIds: assetIds)
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "LLLL yyyy"

        var sections: [MonthSection] = []
        var currentKey: String?
        var currentTitle: String = ""
        var currentIds: [String] = []
        var unknownIds: [String] = []

        for id in assetIds {
            guard let dateOpt = idToDate[id], let date = dateOpt else {
                unknownIds.append(id)
                continue
            }

            let comps = calendar.dateComponents([.year, .month], from: date)
            let year = comps.year ?? 0
            let month = comps.month ?? 0
            let key = String(format: "%04d-%02d", year, month)

            if key != currentKey {
                if !currentIds.isEmpty {
                    sections.append(MonthSection(id: currentKey ?? UUID().uuidString,
                                                 title: currentTitle,
                                                 assetIds: currentIds))
                }
                currentKey = key
                currentTitle = formatter.string(from: date)
                currentIds = []
            }
            currentIds.append(id)
        }

        if !currentIds.isEmpty {
            sections.append(MonthSection(id: currentKey ?? UUID().uuidString,
                                         title: currentTitle,
                                         assetIds: currentIds))
        }

        if !unknownIds.isEmpty {
            sections.append(MonthSection(id: "unknown", title: "Unknown Date", assetIds: unknownIds))
        }

        return sections
    }

    private func creationDateMap(assetIds: [String], batchSize: Int = 500) -> [String: Date?] {
        guard !assetIds.isEmpty else { return [:] }

        var map: [String: Date?] = [:]
        map.reserveCapacity(assetIds.count)

        var index = 0
        while index < assetIds.count {
            let end = min(index + batchSize, assetIds.count)
            let batch = Array(assetIds[index..<end])
            let fetch = PHAsset.fetchAssets(withLocalIdentifiers: batch, options: nil)
            fetch.enumerateObjects { asset, _, _ in
                map[asset.localIdentifier] = asset.creationDate
            }
            index = end
        }

        return map
    }

//    private func fetchRecentlyDeletedIds() -> Set<String> {
//        let collections = PHAssetCollection.fetchAssetCollections(with: .smartAlbum,
//                                                                  subtype: .smartAlbumRecentlyDeleted,
//                                                                  options: nil)
//        guard let collection = collections.firstObject else { return [] }
//
//        let assets = PHAsset.fetchAssets(in: collection, options: nil)
//        var ids: Set<String> = []
//        ids.reserveCapacity(assets.count)
//        assets.enumerateObjects { asset, _, _ in
//            ids.insert(asset.localIdentifier)
//        }
//        return ids
//    }
}
