import SwiftUI
import Photos
import SwiftData
import CoreLocation
import UIKit
import AVFoundation

struct SwipeDeckView: View {
    @EnvironmentObject private var auth: PhotoAuthorizationService
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: SwipeDeckViewModel

    @State private var showAllPhotos = false
    @State private var showToDelete = false
    @State private var showInspector = false
    @State private var dragOffset: CGSize = .zero
    @State private var showLimitedPicker = false
    @State private var swipeToast: SwipeToast?
    @State private var toastTask: Task<Void, Never>?
    @State private var infoToast: InfoToast?
    @State private var infoToastTask: Task<Void, Never>?
    @State private var copyPulseLabel: String?
    @State private var sharePayload: SharePayload?
    @State private var showCredits = false
    @State private var sheetLift: CGFloat = 0
    @State private var sheetDragStart: CGFloat = 0
    @State private var isDraggingSheet = false

    init(modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: SwipeDeckViewModel(modelContext: modelContext))
    }

    var body: some View {
        ZStack {
            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    topBar

                    if auth.isLimited {
                        limitedAccessBanner
                    }

                    ZStack {
                        GeometryReader { geo in
                            let maxCardHeight = cardAreaHeight(availableHeight: geo.size.height)
                            let sheetProgress = sheetProgress(availableHeight: geo.size.height)
                            ZStack(alignment: .bottom) {
                                VStack(spacing: 8) {
                                    if let assetId = viewModel.currentAssetId {
                                        cardArea(assetId: assetId, height: maxCardHeight)
                                        actionIconRow
                                            .padding(.horizontal, 24)
                                    } else {
                                        emptyState
                                            .padding(.horizontal, 16)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .blur(radius: sheetProgress > 0.05 ? 3 : 0)

                                if let assetId = viewModel.currentAssetId {
                                    metadataSheet(assetId: assetId, availableHeight: geo.size.height)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }

            if showInspector, let assetId = viewModel.currentAssetId {
                InspectorView(assetId: assetId,
                              metadataService: viewModel.metadataService,
                              gifService: viewModel.gifService,
                              onDismiss: { showInspector = false })
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .sheet(isPresented: $showAllPhotos) {
            AllPhotosGridView(viewModel: viewModel)
        }
        .sheet(isPresented: $showToDelete) {
            ToDeleteView(viewModel: viewModel)
        }
        .sheet(isPresented: $showCredits) {
            CreditsUsageView(viewModel: viewModel)
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: payload.items)
        }
        .sheet(isPresented: $showLimitedPicker) {
            LimitedLibraryPickerPresenter(isPresented: $showLimitedPicker)
                .ignoresSafeArea()
        }
        .onChange(of: showLimitedPicker) { _, newValue in
            if !newValue { auth.refresh() }
        }
        .task {
            await viewModel.load()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await viewModel.refreshLibrary() }
            }
        }
        .onChange(of: viewModel.currentAssetId) { _, _ in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                sheetLift = 0
            }
        }
        .onChange(of: viewModel.commitToastMessage) { _, message in
            guard let message else { return }
            showInfoToast(text: message, color: .green)
            viewModel.commitToastMessage = nil
        }
        .alert("Error", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { _ in viewModel.errorMessage = nil })) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var topBar: some View {
        HStack {
            Button("All Photos") {
                showAllPhotos = true
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)

            Spacer()

            counterView

            Spacer()

            Button {
                showToDelete = true
            } label: {
                HStack(spacing: 6) {
                    Text("To Delete")
                    if viewModel.deletionSet.count > 0 {
                        Text("\(viewModel.deletionSet.count)")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.85))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
        .padding(.horizontal, 16)
    }

    private var limitedAccessBanner: some View {
        HStack {
            Text("Limited Photo Access")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button("Manage") {
                showLimitedPicker = true
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
        .background(Color.yellow.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
    }

    private func cardView(assetId: String, cardSize: CGSize) -> some View {
        let isGif = viewModel.gifService.isGIF(assetId: assetId)
        let metadata = viewModel.metadataService.metadata(assetId: assetId)
        let isVideo = metadata?.mediaType == .video

        return ZStack(alignment: .topLeading) {
            AssetThumbnailView(assetId: assetId,
                               targetSize: cardSize,
                               thumbnailService: viewModel.thumbnailService,
                               fill: false,
                               deliveryMode: .highQualityFormat)
                .frame(width: cardSize.width, height: cardSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 8)
            .offset(x: dragOffset.width)
            .rotationEffect(.degrees(Double(dragOffset.width / 12)))
            .gesture(
                DragGesture()
                    .onChanged { dragOffset = $0.translation }
                    .onEnded { value in
                        if value.translation.width < -120 {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                                handleSwipeLeft()
                            }
                        } else if value.translation.width > 120 {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                                handleSwipeRight()
                            }
                        }
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                            dragOffset = .zero
                        }
                    }
            )
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.22)) {
                    showInspector = true
                }
            }
            .animation(.spring(response: 0.24, dampingFraction: 0.85), value: dragOffset)

            VStack(alignment: .leading, spacing: 6) {
                if viewModel.metadataService.isFavorite(assetId: assetId) {
                    badge("Favorite", systemImage: "heart.fill")
                }
                if metadata?.mediaSubtypes.contains(.photoScreenshot) == true {
                    badge("Screenshot")
                }
                if isGif {
                    badge("GIF")
                }
            }
            .padding(12)

            if isVideo == true {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 3)
                    .frame(width: cardSize.width, height: cardSize.height, alignment: .center)
                    .allowsHitTesting(false)
            }

            if viewModel.deletionSet.contains(assetId) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.red)
                    .clipShape(Circle())
                    .padding(12)
                    .allowsHitTesting(false)
                    .frame(width: cardSize.width, height: cardSize.height, alignment: .topTrailing)
            }
        }
        .id(assetId)
        .transition(.opacity.combined(with: .scale))
    }

    private func cardArea(assetId: String, height: CGFloat) -> some View {
        GeometryReader { geo in
            let stageSize = geo.size
            let metadata = viewModel.metadataService.metadata(assetId: assetId)
            let cardSize = fittedCardSize(stage: stageSize, metadata: metadata)
            ZStack {
                Color.clear
                cardView(assetId: assetId, cardSize: cardSize)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) {
            toastStack
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.85), value: viewModel.currentAssetId)
    }

    private func metadataSheet(assetId: String, availableHeight: CGFloat) -> some View {
        let metadata = viewModel.metadataService.metadata(assetId: assetId)
        let albums = viewModel.albumTagService.albumTags(assetId: assetId)
        let collapsedHeight: CGFloat = collapsedSheetHeight
        let expandedHeight = min(availableHeight * 0.58, 380)
        let maxLift = max(0, expandedHeight - collapsedHeight)
        let limitedLift = maxLift * 0.5
        let currentLift = min(max(sheetLift, 0), limitedLift)
        let yOffset = maxLift - currentLift
        let progress = limitedLift == 0 ? 1 : currentLift / limitedLift
        let debugLift = true
        if debugLift {
            print("[MetadataSheet] maxLift=\(maxLift) limitedLift=\(limitedLift) currentLift=\(currentLift) yOffset=\(yOffset)")
        }

        return VStack(spacing: 10) {
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 44, height: 5)
                .padding(.top, 8)

            HStack(spacing: 18) {
                if let metadata {
                    Text(dateString(metadata.creationDate))
                        .font(.title3.weight(.semibold))
                } else {
                    Text("—")
                        .font(.title3.weight(.semibold))
                }
                Spacer()
                Button {
                    handleToggleFavorite(assetId: assetId)
                } label: {
                    Image(systemName: viewModel.metadataService.isFavorite(assetId: assetId) ? "heart.fill" : "heart")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(viewModel.metadataService.isFavorite(assetId: assetId) ? .red : .secondary)
                }
                Button {
                    handleShare(assetId: assetId)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Button {
                    showCredits = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.trailing, 14)
            }

            LocationRow(assetId: assetId,
                        metadataService: viewModel.metadataService)

            Divider()
                .opacity(progress)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    if let metadata {
                        metadataLine(label: "Type", value: typeString(metadata))
                        if metadata.mediaType == .video {
                            metadataLine(label: "Duration", value: durationString(metadata.duration))
                        }
                        metadataLine(label: "Modified", value: dateString(metadata.modificationDate))
                        metadataLine(label: "Resolution", value: "\(metadata.pixelWidth) x \(metadata.pixelHeight)")
                        if let filename = viewModel.metadataService.fileName(assetId: assetId) {
                            metadataMultilineWithCopy(label: "Filename", value: filename)
                        }
                        metadataMultilineWithCopy(label: "Identifier", value: metadata.localIdentifier)
                    }

                    if !albums.isEmpty {
                        metadataMultiline(label: "Albums", value: albums.joined(separator: "\n"))
                    }
                }
                .font(.subheadline)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
            .opacity(progress)
            .scrollDisabled(progress < 0.2)
            .allowsHitTesting(progress > 0.05)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .frame(height: expandedHeight)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: -2)
        .offset(y: yOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if !isDraggingSheet {
                        sheetDragStart = sheetLift
                        isDraggingSheet = true
                    }
                    let proposed = sheetDragStart + (-value.translation.height)
                    sheetLift = min(max(proposed, 0), limitedLift)
                    if debugLift {
                        print("[MetadataSheet] dragging lift=\(sheetLift)")
                    }
                }
                .onEnded { value in
                    isDraggingSheet = false
                    let predicted = -value.predictedEndTranslation.height
                    let newLift = min(max(sheetLift, 0), limitedLift)
                    let shouldExpand = predicted > limitedLift * 0.4 || newLift > limitedLift * 0.5
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        sheetLift = shouldExpand ? limitedLift : 0
                    }
                    if debugLift {
                        print("[MetadataSheet] ended newLift=\(newLift) shouldExpand=\(shouldExpand)")
                    }
                }
        )
    }

    private func metadataView(assetId: String) -> some View {
        let metadata = viewModel.metadataService.metadata(assetId: assetId)
        let albums = viewModel.albumTagService.albumTags(assetId: assetId)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let metadata {
                    Text(dateString(metadata.creationDate))
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Button {
                        handleToggleFavorite(assetId: assetId)
                    } label: {
                        Image(systemName: viewModel.metadataService.isFavorite(assetId: assetId) ? "heart.fill" : "heart")
                            .foregroundStyle(viewModel.metadataService.isFavorite(assetId: assetId) ? .red : .secondary)
                    }
                }
            }

            if let metadata {
                if !albums.isEmpty {
                    metadataMultiline(label: "Albums", value: albums.joined(separator: "\n"))
                        .font(.subheadline)
                }

                VStack(alignment: .leading, spacing: 6) {
                    LocationRow(assetId: assetId,
                                metadataService: viewModel.metadataService)
                    metadataLine(label: "Type", value: typeString(metadata))
                    metadataLine(label: "Modified", value: dateString(metadata.modificationDate))
                    metadataLine(label: "Resolution", value: "\(metadata.pixelWidth) x \(metadata.pixelHeight)")
                    metadataMultiline(label: "Identifier", value: metadata.localIdentifier)
                }
                .font(.subheadline)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No Photos")
                .font(.headline)
            Text("Your library appears empty or no assets are accessible.")
                .foregroundStyle(.secondary)
        }
        .frame(maxHeight: .infinity)
    }

    private func badge(_ text: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
            }
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.6))
        .foregroundStyle(.white)
        .clipShape(Capsule())
    }

    private func dateString(_ date: Date?) -> String {
        guard let date else { return "N/A" }
        return Self.dateFormatter.string(from: date)
    }

    private func durationString(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func typeString(_ metadata: AssetMetadata) -> String {
        if metadata.mediaType == .video { return "Video" }
        if metadata.mediaSubtypes.contains(.photoLive) { return "Live Photo" }
        if metadata.mediaSubtypes.contains(.photoScreenshot) { return "Screenshot" }
        return "Photo"
    }

    private func locationString(_ location: CLLocation?) -> String {
        guard let location else { return "N/A" }
        return String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude)
    }

    private func metadataLine(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: metadataLabelWidth, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metadataMultiline(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: metadataLabelWidth, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private func cardAreaHeight(availableHeight: CGFloat) -> CGFloat {
        let reserved = collapsedSheetHeight + 44
        let maxAvailable = max(240, availableHeight - reserved)
        let target = min(760, availableHeight * 0.8)
        return max(300, min(target, maxAvailable))
    }

    private var metadataLabelWidth: CGFloat { 92 }
    private var collapsedSheetHeight: CGFloat { 78 }

    private func sheetProgress(availableHeight: CGFloat) -> CGFloat {
        let expandedHeight = min(availableHeight * 0.58, 380)
        let maxLift = max(0, expandedHeight - collapsedSheetHeight)
        let limitedLift = maxLift * 0.5
        let currentLift = min(max(sheetLift, 0), limitedLift)
        return limitedLift == 0 ? 0 : currentLift / limitedLift
    }

    private var counterView: some View {
        let total = viewModel.assetIds.count
        let current = total == 0 ? 0 : min(viewModel.currentIndex + 1, total)
        return VStack(spacing: 2) {
            Text(total == 0 ? "—" : "\(formatCount(current)) /")
            Text(total == 0 ? "—" : formatCount(total))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .monospacedDigit()
        .frame(minWidth: 90)
    }

    private var actionIconRow: some View {
        HStack {
            HStack(spacing: 12) {
                Image(systemName: "trash")
                Image(systemName: "arrow.left")
            }
            Spacer()
            HStack(spacing: 12) {
                Image(systemName: "arrow.right")
                Image(systemName: "checkmark")
            }
        }
        .font(.title3.weight(.semibold))
        .foregroundStyle(Color.secondary.opacity(0.7))
        .allowsHitTesting(false)
    }

    private func metadataMultilineWithCopy(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: metadataLabelWidth, alignment: .leading)
            HStack(alignment: .top, spacing: 8) {
                Text(value)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(copyPulseLabel == label ? 0.25 : 1)
                    .animation(.easeInOut(duration: 0.18), value: copyPulseLabel == label)
                Image(systemName: "doc.on.doc")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            handleCopy(label: label, value: value)
        }
    }

    private func formatCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func fittedCardSize(stage: CGSize, metadata: AssetMetadata?) -> CGSize {
        let padding: CGFloat = 12
        let maxWidth = max(1, stage.width - padding * 2)
        let maxHeight = max(1, stage.height - padding * 2)
        guard let metadata, metadata.pixelWidth > 0, metadata.pixelHeight > 0 else {
            return CGSize(width: maxWidth, height: maxHeight)
        }

        let aspect = CGFloat(metadata.pixelWidth) / CGFloat(metadata.pixelHeight)
        var width = maxWidth
        var height = width / aspect
        if height > maxHeight {
            height = maxHeight
            width = height * aspect
        }
        return CGSize(width: width, height: height)
    }

    private func handleSwipeLeft() {
        viewModel.swipeLeft()
        showToast(text: "Marked for Deletion", color: .red)
    }

    private func handleSwipeRight() {
        viewModel.swipeRight()
        showToast(text: "Kept", color: .green)
    }

    private func showToast(text: String, color: Color) {
        let toast = SwipeToast(text: text, color: color)
        toastTask?.cancel()
        toastTask = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            swipeToast = toast
        }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if Task.isCancelled { return }
            if swipeToast?.id == toast.id {
                withAnimation(.easeInOut(duration: 0.2)) {
                    swipeToast = nil
                }
            }
        }
    }

    private func toastView(_ toast: SwipeToast) -> some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                viewModel.undo()
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                swipeToast = nil
            }
        } label: {
            HStack(spacing: 6) {
                Text(toast.text)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "arrow.uturn.backward")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(toast.color)
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .shadow(color: toast.color.opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Undo")
    }

    private var toastStack: some View {
        VStack(spacing: 8) {
            if let toast = swipeToast {
                toastView(toast)
                    .transition(.opacity)
            }
            if let toast = infoToast {
                infoToastView(toast)
                    .transition(.opacity)
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: swipeToast?.id)
        .animation(.easeInOut(duration: 0.2), value: infoToast?.id)
    }

    private struct SwipeToast: Identifiable {
        let id = UUID()
        let text: String
        let color: Color
    }

    private func showInfoToast(text: String, color: Color) {
        let toast = InfoToast(text: text, color: color)
        infoToastTask?.cancel()
        infoToastTask = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            infoToast = toast
        }
        infoToastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if Task.isCancelled { return }
            if infoToast?.id == toast.id {
                withAnimation(.easeInOut(duration: 0.2)) {
                    infoToast = nil
                }
            }
        }
    }

    private func infoToastView(_ toast: InfoToast) -> some View {
        HStack(spacing: 6) {
            Text(toast.text)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(toast.color)
        .foregroundStyle(.white)
        .clipShape(Capsule())
        .shadow(color: toast.color.opacity(0.4), radius: 8, x: 0, y: 4)
    }

    private func handleCopy(label: String, value: String) {
        UIPasteboard.general.string = value
        copyPulseLabel = label
        showInfoToast(text: "\(label) copied", color: .blue)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            if copyPulseLabel == label {
                copyPulseLabel = nil
            }
        }
    }

    private func handleToggleFavorite(assetId: String) {
        let wasFavorite = viewModel.metadataService.isFavorite(assetId: assetId)
        Task {
            await viewModel.toggleFavorite(assetId: assetId)
            let message = wasFavorite ? "Removed from Favorites" : "Added to Favorites"
            let color: Color = wasFavorite ? .gray : .red
            showInfoToast(text: message, color: color)
        }
    }

    private func handleShare(assetId: String) {
        Task {
            if let items = await shareItems(for: assetId) {
                await MainActor.run {
                    sharePayload = SharePayload(items: items)
                }
            } else {
                await MainActor.run {
                    showInfoToast(text: "Unable to share", color: .gray)
                }
            }
        }
    }

    private func shareItems(for assetId: String) async -> [Any]? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        if asset.mediaType == .video {
            let opts = PHVideoRequestOptions()
            opts.isNetworkAccessAllowed = true
            return await withCheckedContinuation { cont in
                PHImageManager.default().requestAVAsset(forVideo: asset, options: opts) { avAsset, _, _ in
                    if let urlAsset = avAsset as? AVURLAsset {
                        cont.resume(returning: [urlAsset.url])
                    } else {
                        cont.resume(returning: nil)
                    }
                }
            }
        }

        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat
        opts.isNetworkAccessAllowed = true
        opts.resizeMode = .none

        return await withCheckedContinuation { cont in
            PHImageManager.default().requestImage(for: asset,
                                                  targetSize: PHImageManagerMaximumSize,
                                                  contentMode: .aspectFit,
                                                  options: opts) { image, _ in
                if let image {
                    cont.resume(returning: [image])
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private struct LocationRow: View {
        let assetId: String
        @ObservedObject var metadataService: MetadataService

        @State private var display: String = "No location"
        @State private var hasLocation = false

        var body: some View {
            Text(display)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(hasLocation ? .primary : .secondary)
            .task(id: assetId) {
                if let value = await metadataService.locationDisplay(assetId: assetId) {
                    display = value
                    hasLocation = true
                } else {
                    display = "No location"
                    hasLocation = false
                }
            }
        }
    }

    private struct InfoToast: Identifiable {
        let id = UUID()
        let text: String
        let color: Color
    }

    private struct SharePayload: Identifiable {
        let id = UUID()
        let items: [Any]
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
