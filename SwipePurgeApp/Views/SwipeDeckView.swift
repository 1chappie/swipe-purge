import Foundation
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
    @State private var showCounterAsPercent = false
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
                                    } else {
                                        emptyState
                                            .padding(.horizontal, 16)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .blur(radius: sheetProgress > 0.05 ? 3 : 0)

                                if sheetLift > 1 {
                                    sheetDismissLayer
                                }

                                if let assetId = viewModel.currentAssetId {
                                    metadataSheet(assetId: assetId, availableHeight: geo.size.height)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }

            if sheetLift > 1 && !showInspector {
                sheetDismissTopOverlay
            }

            if showInspector, let assetId = viewModel.currentAssetId {
                InspectorView(assetId: assetId,
                              metadataService: viewModel.metadataService,
                              gifService: viewModel.gifService,
                              onDismiss: {
                                  withAnimation(.easeInOut(duration: 0.22)) {
                                      showInspector = false
                                  }
                              })
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
        let deleteCount = viewModel.deletionSet.count
        let deleteLabel = deleteCount > 999 ? "To Del." : "To Delete"

        return ZStack {
            HStack {
                Button {
                    showAllPhotos = true
                } label: {
                    glassCapsule {
                        Text("All Photos")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    showToDelete = true
                } label: {
                    glassCapsule {
                        HStack(spacing: 6) {
                            Text(deleteLabel)
                            if deleteCount > 0 {
                                Text("\(deleteCount)")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red.opacity(0.85))
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
            }

            counterView
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    private var limitedAccessBanner: some View {
        glassRoundedPanel(cornerRadius: 16, tint: Color.yellow.opacity(0.08)) {
            HStack {
                Text("Limited Photo Access")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    showLimitedPicker = true
                } label: {
                    glassCapsule(paddingH: 12, paddingV: 8, tint: Color.yellow.opacity(0.08)) {
                        Text("Manage")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(12)
        }
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
                glassCircleControl(size: 72, tint: Color.white.opacity(0.12)) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: cardSize.width, height: cardSize.height, alignment: .center)
                .allowsHitTesting(false)
            }

            VStack(alignment: .trailing, spacing: 8) {
                if let metadata, isVideo {
                    glassCapsule(paddingH: 10, paddingV: 4, tint: Color.white.opacity(0.08)) {
                        Text(durationString(metadata.duration))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }

                if viewModel.deletionSet.contains(assetId) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.red)
                        .clipShape(Circle())
                }
            }
            .padding(12)
            .allowsHitTesting(false)
            .frame(width: cardSize.width, height: cardSize.height, alignment: .topTrailing)
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
                    .allowsHitTesting(sheetLift <= 1)
                swipeEdgeHints(for: dragOffset.width)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
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
        let limitedLift = maxLift * 0.76
        let currentLift = min(max(sheetLift, 0), limitedLift)
        let yOffset = maxLift - currentLift
        let progress = limitedLift == 0 ? 1 : currentLift / limitedLift
        let debugLift = true
        if debugLift {
            print("[MetadataSheet] maxLift=\(maxLift) limitedLift=\(limitedLift) currentLift=\(currentLift) yOffset=\(yOffset)")
        }

        return VStack(spacing: 4) {
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 44, height: 5)
                .padding(.top, 8)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    if let metadata {
                        Text(dateString(metadata.creationDate))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                    } else {
                        Text("—")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                    }

                    LocationRow(assetId: assetId,
                                metadataService: viewModel.metadataService)
                        .font(.subheadline)
                }
                Spacer(minLength: 8)
                metadataActionPill(assetId: assetId)
                Button {
                    showCredits = true
                } label: {
                    glassCircleControl {
                        Image(systemName: "gearshape")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }
            .padding(.top, 12)

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
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color.white.opacity(0.06))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
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

    private func metadataActionPill(assetId: String) -> some View {
        let favoriteActive = viewModel.metadataService.isFavorite(assetId: assetId)

        return HStack(spacing: 4) {
            metadataActionButton(systemImage: favoriteActive ? "heart.fill" : "heart",
                                 accent: favoriteActive ? .red : .primary) {
                handleToggleFavorite(assetId: assetId)
            }

            Menu {
                Button {
                    handleShare(assetId: assetId)
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .tint(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                }
        }
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 4)
    }

    private func metadataActionButton(
        systemImage: String,
        accent: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
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
        glassRoundedPanel(cornerRadius: 20, tint: Color.white.opacity(0.05)) {
            VStack(spacing: 12) {
                Text("No Photos")
                    .font(.headline)
                Text("Your library appears empty or no assets are accessible.")
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    private func glassCapsule<Content: View>(
        paddingH: CGFloat = 14,
        paddingV: CGFloat = 10,
        tint: Color = Color.white.opacity(0.08),
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, paddingH)
            .padding(.vertical, paddingV)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .fill(tint)
                    }
            }
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
    }

    private func glassCircleControl<Content: View>(
        size: CGFloat = 42,
        tint: Color = Color.white.opacity(0.08),
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle()
                            .fill(tint)
                    }
            }
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
    }

    private func glassRoundedPanel<Content: View>(
        cornerRadius: CGFloat = 16,
        tint: Color = Color.white.opacity(0.08),
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(tint)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
    }

    private func badge(_ text: String, systemImage: String? = nil) -> some View {
        glassCapsule(paddingH: 8, paddingV: 4, tint: Color.black.opacity(0.16)) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                }
                Text(text)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
        }
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
        let reserved = collapsedSheetHeight + 14
        let maxAvailable = max(240, availableHeight - reserved)
        let target = min(820, availableHeight * 0.86)
        return max(300, min(target, maxAvailable))
    }

    private var metadataLabelWidth: CGFloat { 92 }
    private var collapsedSheetHeight: CGFloat { 76 }

    private func sheetProgress(availableHeight: CGFloat) -> CGFloat {
        let expandedHeight = min(availableHeight * 0.58, 380)
        let maxLift = max(0, expandedHeight - collapsedSheetHeight)
        let limitedLift = maxLift * 0.76
        let currentLift = min(max(sheetLift, 0), limitedLift)
        return limitedLift == 0 ? 0 : currentLift / limitedLift
    }


    private var sheetDismissLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .allowsHitTesting(true)
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        let vertical = value.translation.height
                        let predicted = value.predictedEndTranslation.height
                        if vertical > 20 || predicted > 50 {
                            collapseSheet()
                        }
                    }
            )
            .onTapGesture {
                collapseSheet()
            }
    }

    private var sheetDismissTopOverlay: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .contentShape(Rectangle())
                .allowsHitTesting(true)
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onEnded { value in
                            let vertical = value.translation.height
                            let predicted = value.predictedEndTranslation.height
                            if vertical > 20 || predicted > 50 {
                                collapseSheet()
                            }
                        }
                )
                .onTapGesture {
                    collapseSheet()
                }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func collapseSheet() {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            sheetLift = 0
        }
    }

    private var counterView: some View {
        let total = viewModel.assetIds.count
        let current = total == 0 ? 0 : min(viewModel.currentIndex + 1, total)
        let progressPercent = total == 0 ? 0 : (Double(current) / Double(total) * 100)
        let progressPercentText = total == 0 ? "—" : String(format: "%.1f%%", progressPercent)

        return Group {
            if showCounterAsPercent {
                Text(progressPercentText)
            } else {
                VStack(spacing: 2) {
                    Text(total == 0 ? "—" : "\(formatCount(current)) /")
                    Text(total == 0 ? "—" : formatCount(total))
                }
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .monospacedDigit()
        .frame(minWidth: 90)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.16)) {
                showCounterAsPercent.toggle()
            }
        }
    }

    private func swipeEdgeHints(for width: CGFloat) -> some View {
        let progress = min(max(abs(width) / 90, 0), 1)

        return ZStack {
            if width < -6 {
                edgeBulge(systemImage: "trash.fill",
                          alignment: .leading,
                          progress: progress,
                          tint: Color.red.opacity(0.22))
            }

            if width > 6 {
                edgeBulge(systemImage: "checkmark",
                          alignment: .trailing,
                          progress: progress,
                          tint: Color.green.opacity(0.22))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.12), value: width)
    }

    private func edgeBulge(
        systemImage: String,
        alignment: Alignment,
        progress: CGFloat,
        tint: Color
    ) -> some View {
        let hiddenOffset: CGFloat = alignment == .leading ? -136 : 136
        let visibleOffset: CGFloat = alignment == .leading ? 22 : -22
        let xOffset = hiddenOffset + (visibleOffset - hiddenOffset) * progress

        return glassCapsule(paddingH: 28, paddingV: 20, tint: tint) {
            Image(systemName: systemImage)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .offset(x: xOffset)
        .opacity(progress)
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
            glassCapsule(paddingH: 12, paddingV: 8, tint: toast.color.opacity(0.24)) {
                HStack(spacing: 6) {
                    Text(toast.text)
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 6)
                }
                .foregroundStyle(.white)
            }
            .shadow(color: toast.color.opacity(0.22), radius: 8, x: 0, y: 4)
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
        .padding(.bottom, 36)
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
        glassCapsule(paddingH: 12, paddingV: 8, tint: toast.color.opacity(0.24)) {
            HStack(spacing: 6) {
                Text(toast.text)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
        }
        .shadow(color: toast.color.opacity(0.22), radius: 8, x: 0, y: 4)
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
