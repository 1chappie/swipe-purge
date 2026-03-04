import SwiftUI
import Photos
import AVKit
import AVFoundation
import UIKit

struct InspectorView: View {
    let assetId: String
    @ObservedObject var metadataService: MetadataService
    @ObservedObject var gifService: GIFService
    let onDismiss: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var animatedImage: UIImage?
    @State private var isLoading: Bool = true
    @State private var dragOffset: CGFloat = 0

    init(assetId: String,
         metadataService: MetadataService,
         gifService: GIFService,
         onDismiss: (() -> Void)? = nil) {
        self.assetId = assetId
        self.metadataService = metadataService
        self.gifService = gifService
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            contentView
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            closeHint
        }
        .offset(y: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    } else {
                        dragOffset = 0
                    }
                }
                .onEnded { value in
                    let vertical = value.translation.height
                    let predicted = value.predictedEndTranslation.height
                    if vertical > 120 || predicted > 200 {
                        dismissView()
                        dragOffset = 0
                    } else {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .task {
            await loadAsset()
        }
    }

    private var closeHint: some View {
        VStack(spacing: 6) {
            Text("Swipe down to close")
                .font(.caption.weight(.semibold))
            Image(systemName: "chevron.down")
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(.white.opacity(0.82))
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(
            LinearGradient(colors: [Color.clear, Color.black.opacity(0.24)],
                           startPoint: .top,
                           endPoint: .bottom)
        )
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var contentView: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
            } else if let animatedImage {
                Image(uiImage: animatedImage)
                    .resizable()
                    .scaledToFit()
            } else if let image {
                ZoomableImageView(image: image)
            }

            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.large)
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadAsset() async {
        isLoading = true
        if gifService.isGIF(assetId: assetId) {
            animatedImage = await gifService.animatedImage(assetId: assetId)
            if animatedImage != nil {
                isLoading = false
                return
            }
        }

        if let metadata = metadataService.metadata(assetId: assetId), metadata.mediaType == .video {
            player = await loadVideoPlayer(assetId: assetId)
            if player != nil {
                isLoading = false
                return
            }
        }

        image = await loadHighQualityImage(assetId: assetId)
        isLoading = false
    }

    private func loadHighQualityImage(assetId: String) async -> UIImage? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat
        opts.isNetworkAccessAllowed = true
        opts.resizeMode = .none

        return await withCheckedContinuation { cont in
            PHImageManager.default().requestImage(for: asset,
                                                  targetSize: PHImageManagerMaximumSize,
                                                  contentMode: .aspectFit,
                                                  options: opts) { image, _ in
                cont.resume(returning: image)
            }
        }
    }

    private func loadVideoPlayer(assetId: String) async -> AVPlayer? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        configureAudioSession()
        let opts = PHVideoRequestOptions()
        opts.isNetworkAccessAllowed = true

        return await withCheckedContinuation { cont in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: opts) { avAsset, _, _ in
                if let avAsset {
                    let player = AVPlayer(playerItem: AVPlayerItem(asset: avAsset))
                    player.volume = 1.0
                    player.isMuted = false
                    cont.resume(returning: player)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [])
        try? session.setActive(true, options: [])
    }

    private func dismissView() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }
}
