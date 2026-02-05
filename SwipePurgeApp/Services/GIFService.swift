import Foundation
import Photos
import UIKit
import ImageIO
import Combine

@MainActor
final class GIFService: ObservableObject {
    private var cache: [String: Bool] = [:]

    func isGIF(assetId: String) -> Bool {
        if let cached = cache[assetId] { return cached }

        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = fetch.firstObject else { return false }

        let resources = PHAssetResource.assetResources(for: asset)
        let isGif = resources.contains { res in
            let uti = res.uniformTypeIdentifier.lowercased()
            if uti.contains("gif") { return true }
            if res.originalFilename.lowercased().hasSuffix(".gif") { return true }
            return false
        }

        cache[assetId] = isGif
        return isGif
    }

    func animatedImage(assetId: String) async -> UIImage? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        let opts = PHImageRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.deliveryMode = .highQualityFormat
        opts.isSynchronous = false

        return await withCheckedContinuation { cont in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts) { data, _, _, _ in
                guard let data = data else {
                    cont.resume(returning: nil)
                    return
                }
                let image = UIImage.gif(data: data)
                cont.resume(returning: image)
            }
        }
    }
}

private extension UIImage {
    static func gif(data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        if count <= 1 {
            return UIImage(data: data)
        }

        var images: [UIImage] = []
        var duration: TimeInterval = 0

        for index in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            let frameDuration = UIImage.frameDuration(at: index, source: source)
            duration += frameDuration
            images.append(UIImage(cgImage: cgImage))
        }

        if duration == 0 { duration = Double(count) * 0.1 }
        return UIImage.animatedImage(with: images, duration: duration)
    }

    static func frameDuration(at index: Int, source: CGImageSource) -> TimeInterval {
        var frameDuration = 0.1
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gifDict = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return frameDuration
        }

        if let unclampedDelay = gifDict[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber {
            frameDuration = unclampedDelay.doubleValue
        } else if let delay = gifDict[kCGImagePropertyGIFDelayTime] as? NSNumber {
            frameDuration = delay.doubleValue
        }

        if frameDuration < 0.02 { frameDuration = 0.1 }
        return frameDuration
    }
}
