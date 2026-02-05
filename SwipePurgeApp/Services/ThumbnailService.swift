import Foundation
import Photos
import UIKit
import Combine

@MainActor
final class ThumbnailService: ObservableObject {
    private let manager = PHCachingImageManager()
    private let imageCache = NSCache<NSString, UIImage>()
    private var memoryKeys: Set<String> = []
    private let diskQueue = DispatchQueue(label: "ThumbnailService.DiskCache")
    private let diskCacheURL: URL

    init() {
        imageCache.countLimit = 500
        imageCache.totalCostLimit = 80 * 1024 * 1024
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = caches.appendingPathComponent("SwipePurgeThumbCache", isDirectory: true)
        diskCacheURL = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
    }

    func thumbnail(assetId: String, targetSize: CGSize, contentMode: PHImageContentMode, deliveryMode: PHImageRequestOptionsDeliveryMode) async -> UIImage? {
        let cacheKey = cacheKeyFor(assetId: assetId, targetSize: targetSize, deliveryMode: deliveryMode, contentMode: contentMode)
        if let cached = imageCache.object(forKey: cacheKey as NSString) { return cached }
        if let diskImage = await loadDiskImageIfNeeded(cacheKey: cacheKey, targetSize: targetSize, deliveryMode: deliveryMode) {
            imageCache.setObject(diskImage, forKey: cacheKey as NSString, cost: imageCost(diskImage))
            memoryKeys.insert(cacheKey)
            return diskImage
        }

        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        let opts = PHImageRequestOptions()
        opts.deliveryMode = deliveryMode
        opts.resizeMode = (deliveryMode == .highQualityFormat) ? .exact : .fast
        opts.isNetworkAccessAllowed = true
        opts.version = .current

        let pixelSize = scaledSize(targetSize)

        return await withCheckedContinuation { cont in
            var didResume = false
            manager.requestImage(for: asset,
                                 targetSize: pixelSize,
                                 contentMode: contentMode,
                                 options: opts) { [weak self] image, info in
                if didResume { return }
                if let image {
                    self?.imageCache.setObject(image, forKey: cacheKey as NSString, cost: self?.imageCost(image) ?? 0)
                    self?.memoryKeys.insert(cacheKey)
                    self?.storeDiskImageIfNeeded(image, cacheKey: cacheKey, targetSize: targetSize, deliveryMode: deliveryMode)
                    didResume = true
                    cont.resume(returning: image)
                    return
                }
                if (info?[PHImageCancelledKey] as? Bool) == true {
                    didResume = true
                    cont.resume(returning: nil)
                    return
                }
                didResume = true
                Task { @MainActor in
                    let fallback = await self?.fallbackImage(asset: asset)
                    if let fallback {
                        self?.imageCache.setObject(fallback, forKey: cacheKey as NSString, cost: self?.imageCost(fallback) ?? 0)
                        self?.memoryKeys.insert(cacheKey)
                        self?.storeDiskImageIfNeeded(fallback, cacheKey: cacheKey, targetSize: targetSize, deliveryMode: deliveryMode)
                    }
                    cont.resume(returning: fallback)
                }
            }
        }
    }

    func startPrefetch(assetIds: [String], targetSize: CGSize, contentMode: PHImageContentMode, deliveryMode: PHImageRequestOptionsDeliveryMode) {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIds, options: nil)
        var arr: [PHAsset] = []
        arr.reserveCapacity(assets.count)
        assets.enumerateObjects { a, _, _ in arr.append(a) }

        let opts = PHImageRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.deliveryMode = deliveryMode
        opts.resizeMode = (deliveryMode == .highQualityFormat) ? .exact : .fast
        opts.version = .current

        manager.startCachingImages(for: arr,
                                   targetSize: scaledSize(targetSize),
                                   contentMode: contentMode,
                                   options: opts)
    }

    private func scaledSize(_ size: CGSize) -> CGSize {
        let scale = UIScreen.main.scale
        return CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
    }

    private func cacheKeyFor(assetId: String, targetSize: CGSize, deliveryMode: PHImageRequestOptionsDeliveryMode, contentMode: PHImageContentMode) -> String {
        let sizeKey = "\(Int(targetSize.width))x\(Int(targetSize.height))"
        return "\(assetId)|\(sizeKey)|\(deliveryMode.rawValue)|\(contentMode.rawValue)"
    }

    private func loadDiskImageIfNeeded(cacheKey: String, targetSize: CGSize, deliveryMode: PHImageRequestOptionsDeliveryMode) async -> UIImage? {
        guard shouldUseDiskCache(targetSize: targetSize, deliveryMode: deliveryMode),
              let url = diskURL(for: cacheKey) else { return nil }
        return await withCheckedContinuation { cont in
            diskQueue.async {
                let image = UIImage(contentsOfFile: url.path)
                cont.resume(returning: image)
            }
        }
    }

    private func storeDiskImageIfNeeded(_ image: UIImage, cacheKey: String, targetSize: CGSize, deliveryMode: PHImageRequestOptionsDeliveryMode) {
        guard shouldUseDiskCache(targetSize: targetSize, deliveryMode: deliveryMode),
              let url = diskURL(for: cacheKey) else { return }
        diskQueue.async {
            guard let data = image.jpegData(compressionQuality: 0.85) else { return }
            try? data.write(to: url, options: [.atomic])
        }
    }

    private func shouldUseDiskCache(targetSize: CGSize, deliveryMode: PHImageRequestOptionsDeliveryMode) -> Bool {
        guard deliveryMode == .fastFormat else { return false }
        let maxDimension = max(targetSize.width, targetSize.height)
        return maxDimension <= 600
    }

    private func diskURL(for cacheKey: String) -> URL? {
        let safe = safeFileName(cacheKey)
        return diskCacheURL.appendingPathComponent(safe).appendingPathExtension("jpg")
    }

    private func safeFileName(_ value: String) -> String {
        let data = Data(value.utf8).base64EncodedString()
        return data
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

    private func imageCost(_ image: UIImage) -> Int {
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        return Int(pixels * 4)
    }

    private func fallbackImage(asset: PHAsset) async -> UIImage? {
        let opts = PHImageRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.deliveryMode = .highQualityFormat
        opts.resizeMode = .none
        opts.version = .current

        return await withCheckedContinuation { cont in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts) { data, _, _, _ in
                guard let data = data else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: UIImage(data: data))
            }
        }
    }

    var memoryCacheCount: Int { memoryKeys.count }

    func diskCacheCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: nil))?.count ?? 0
    }
}
