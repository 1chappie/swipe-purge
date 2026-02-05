import Foundation
import Photos
import CoreLocation
import Combine

struct AssetMetadata {
    let assetId: String
    let creationDate: Date?
    let mediaType: PHAssetMediaType
    let mediaSubtypes: PHAssetMediaSubtype
    let duration: TimeInterval
    let isFavorite: Bool
    let location: CLLocation?
    let pixelWidth: Int
    let pixelHeight: Int
    let modificationDate: Date?
    let localIdentifier: String
}

@MainActor
final class MetadataService: ObservableObject {
    private var cache: [String: AssetMetadata] = [:]
    private var locationCache: [String: String] = [:]
    private var fileNameCache: [String: String] = [:]
    private let geocoder = CLGeocoder()

    var cacheCount: Int { cache.count }
    var locationCacheCount: Int { locationCache.count }
    var fileNameCacheCount: Int { fileNameCache.count }

    func metadata(assetId: String) -> AssetMetadata? {
        if let cached = cache[assetId] { return cached }

        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        let metadata = AssetMetadata(
            assetId: asset.localIdentifier,
            creationDate: asset.creationDate,
            mediaType: asset.mediaType,
            mediaSubtypes: asset.mediaSubtypes,
            duration: asset.duration,
            isFavorite: asset.isFavorite,
            location: asset.location,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            modificationDate: asset.modificationDate,
            localIdentifier: asset.localIdentifier
        )

        cache[assetId] = metadata
        return metadata
    }

    func creationDate(assetId: String) -> Date? {
        metadata(assetId: assetId)?.creationDate
    }

    func isFavorite(assetId: String) -> Bool {
        metadata(assetId: assetId)?.isFavorite ?? false
    }

    func mediaType(assetId: String) -> PHAssetMediaType? {
        if let cached = cache[assetId] {
            return cached.mediaType
        }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        if let asset = fetch.firstObject {
            return asset.mediaType
        }
        return nil
    }

    func refresh(assetId: String) {
        cache[assetId] = nil
        locationCache[assetId] = nil
        fileNameCache[assetId] = nil
        _ = metadata(assetId: assetId)
    }

    func fileName(assetId: String) -> String? {
        if let cached = fileNameCache[assetId] { return cached }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = fetch.firstObject else { return nil }
        let resources = PHAssetResource.assetResources(for: asset)
        if let resource = resources.first {
            let name = resource.originalFilename
            fileNameCache[assetId] = name
            return name
        }
        return nil
    }

    func locationDisplay(assetId: String) async -> String? {
        if let cached = locationCache[assetId] { return cached }
        guard let location = metadata(assetId: assetId)?.location else { return nil }
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let place = placemarks.first {
                let city = place.locality ?? place.subAdministrativeArea ?? place.administrativeArea
                let country = place.country
                if let city, let country {
                    let value = "\(city), \(country)"
                    locationCache[assetId] = value
                    return value
                }
                if let country {
                    locationCache[assetId] = country
                    return country
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    func toggleFavorite(assetId: String) async throws {
            let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
            guard let asset = fetch.firstObject else { return }

            let newValue = !asset.isFavorite

            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.shared().performChanges({
                    let request = PHAssetChangeRequest(for: asset)
                    request.isFavorite = newValue
                }, completionHandler: { success, error in
                    if let error { cont.resume(throwing: error); return }
                    if success { cont.resume(returning: ()) }
                    else {
                        cont.resume(throwing: NSError(domain: "SwipePurge", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to update favorite"]))
                    }
                })
            }

            refresh(assetId: assetId)
        }
}
