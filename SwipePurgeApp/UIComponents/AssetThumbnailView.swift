import SwiftUI
import UIKit
import Photos

struct AssetThumbnailView: View {
    let assetId: String
    let targetSize: CGSize
    let fill: Bool
    let deliveryMode: PHImageRequestOptionsDeliveryMode
    @ObservedObject var thumbnailService: ThumbnailService

    @State private var image: UIImage?

    init(assetId: String,
         targetSize: CGSize,
         thumbnailService: ThumbnailService,
         fill: Bool = true,
         deliveryMode: PHImageRequestOptionsDeliveryMode = .fastFormat) {
        self.assetId = assetId
        self.targetSize = targetSize
        self.thumbnailService = thumbnailService
        self.fill = fill
        self.deliveryMode = deliveryMode
    }

    var body: some View {
        ZStack {
            if let image {
                if fill {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        ProgressView()
                            .progressViewStyle(.circular)
                    )
            }
        }
        .clipped()
        .task(id: taskId) {
            image = await thumbnailService.thumbnail(assetId: assetId,
                                                     targetSize: targetSize,
                                                     contentMode: fill ? .aspectFill : .aspectFit,
                                                     deliveryMode: deliveryMode)
        }
        .onDisappear {
            image = nil
        }
    }

    private var taskId: String {
        let sizeKey = "\(Int(targetSize.width))x\(Int(targetSize.height))"
        return "\(assetId)|\(sizeKey)|\(fill)|\(deliveryMode.rawValue)"
    }
}
