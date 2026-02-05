import Foundation
import Photos

@MainActor
final class DeletionService {
    func commitDeletion(assetIds: [String]) async throws {
        if assetIds.isEmpty { return }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIds, options: nil)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets(assets)
            }, completionHandler: { success, error in
                if let error { cont.resume(throwing: error); return }
                if success {
                    cont.resume(returning: ())
                } else {
                    cont.resume(throwing: NSError(domain: "SwipePurge", code: 1, userInfo: [NSLocalizedDescriptionKey: "Deletion failed"]))
                }
            })
        }
    }
}
