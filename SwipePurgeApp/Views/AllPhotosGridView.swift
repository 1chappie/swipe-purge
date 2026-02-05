import SwiftUI
import UIKit
import Photos

struct AllPhotosGridView: View {
    @ObservedObject var viewModel: SwipeDeckViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var scrollTask: Task<Void, Never>?
    @State private var isAutoScrolling = false
    private let debugAutoscroll = true

    private let gridSpacing: CGFloat = 10
    private let columnsCount: CGFloat = 3

    var body: some View {
        NavigationView {
            GeometryReader { geo in
                let size = cellSize(availableWidth: geo.size.width)
                ScrollViewReader { proxy in
                    ZStack {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: gridSpacing) {
                                ForEach(gridItems) { item in
                                    switch item {
                                    case .header(let id, let title):
                                        Text(title)
                                            .font(.headline)
                                            .padding(.horizontal, 8)
                                            .id(id)
                                    case .row(let rowId, let ids):
                                        HStack(spacing: gridSpacing) {
                                            ForEach(ids, id: \.self) { id in
                                                let isVideo = viewModel.metadataService.mediaType(assetId: id) == .video
                                                ZStack(alignment: .topTrailing) {
                                                    AssetThumbnailView(assetId: id,
                                                                       targetSize: CGSize(width: size, height: size),
                                                                       thumbnailService: viewModel.thumbnailService,
                                                                       deliveryMode: .fastFormat)
                                                        .frame(width: size, height: size)
                                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                                        .overlay(cursorOverlay(id: id))
                                                        .contentShape(RoundedRectangle(cornerRadius: 8))
                                                        .onTapGesture {
                                                            viewModel.jump(to: id)
                                                            dismiss()
                                                        }

                                                    if isVideo {
                                                        Image(systemName: "play.circle.fill")
                                                            .font(.system(size: 24, weight: .bold))
                                                            .foregroundStyle(.white)
                                                            .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 2)
                                                            .frame(width: size, height: size, alignment: .center)
                                                    }

                                                    if viewModel.deletionSet.contains(id) {
                                                        Image(systemName: "trash.fill")
                                                            .font(.system(size: 16, weight: .bold))
                                                            .foregroundStyle(.white)
                                                            .frame(width: 36, height: 36)
                                                            .background(Color.red)
                                                            .clipShape(Circle())
                                                            .padding(6)
                                                    }
                                                }
                                                .animation(.easeInOut(duration: 0.2), value: viewModel.deletionSet)
                                                .id(id)
                                            }

                                            if ids.count < Int(columnsCount) {
                                                ForEach(0..<(Int(columnsCount) - ids.count), id: \.self) { _ in
                                                    Color.clear
                                                        .frame(width: size, height: size)
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 6)
                                        .id(rowId)
                                    }
                                }
                            }
                            .padding(.top, 12)
                        }

                        if isAutoScrolling {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.large)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.black.opacity(0.05))
                                .allowsHitTesting(false)
                        }
                    }
                    .background(ScrollViewSpeedLimiter(speedFactor: 0.35, isEnabled: !isAutoScrolling))
                    .onAppear {
                        log("onAppear monthSections=\(viewModel.monthSections.count) assetIds=\(viewModel.assetIds.count)")
                        scheduleScroll(proxy: proxy)
                    }
                    .onChange(of: viewModel.currentAssetId) { _, _ in
                        log("currentAssetId changed")
                        scheduleScroll(proxy: proxy)
                    }
                    .onChange(of: viewModel.monthSections.count) { _, _ in
                        log("monthSections count changed")
                        scheduleScroll(proxy: proxy)
                    }
                    .navigationTitle("All Photos")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { dismiss() }
                        }
                    }
                }
            }
        }
    }

    private func cursorOverlay(id: String) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(viewModel.currentAssetId == id ? Color.blue : Color.clear, lineWidth: 4)
    }

    private func cellSize(availableWidth: CGFloat) -> CGFloat {
        let horizontalPadding: CGFloat = 12
        let totalSpacing = gridSpacing * (columnsCount - 1)
        let raw = (availableWidth - totalSpacing - horizontalPadding) / columnsCount
        return max(1, floor(raw))
    }

    private func scheduleScroll(proxy: ScrollViewProxy) {
        scrollTask?.cancel()
        isAutoScrolling = true
        scrollTask = Task { @MainActor in
            defer { isAutoScrolling = false }
            guard let current = viewModel.currentAssetId else {
                return
            }
            let rowId = rowIdForAsset(current)
            let estimate = estimatedAssetId(for: current)
            log("scheduleScroll current=\(current) rowId=\(rowId ?? "nil") estimate=\(estimate ?? "nil")")
            try? await Task.sleep(nanoseconds: 220_000_000)
            if let rowId {
                withAnimation(.easeInOut(duration: 0.45)) {
                    log("scrollTo rowId \(rowId)")
                    proxy.scrollTo(rowId, anchor: .top)
                }
            } else if let estimate {
                withAnimation(.easeInOut(duration: 0.45)) {
                    log("scrollTo estimate \(estimate)")
                    proxy.scrollTo(estimate, anchor: .top)
                }
            }
            try? await Task.sleep(nanoseconds: 420_000_000)
            withAnimation(.easeInOut(duration: 0.35)) {
                log("scrollTo current")
                proxy.scrollTo(current, anchor: UnitPoint(x: 0.5, y: 0.7))
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    private func rowIdForAsset(_ assetId: String) -> String? {
        for section in viewModel.monthSections {
            if let index = section.assetIds.firstIndex(of: assetId) {
                let rowIndex = index / Int(columnsCount)
                return rowId(sectionId: section.id, rowIndex: rowIndex)
            }
        }
        return nil
    }

    private func estimatedAssetId(for assetId: String) -> String? {
        guard let index = viewModel.assetIds.firstIndex(of: assetId) else { return nil }
        let rowStartIndex = max(0, (index / Int(columnsCount)) * Int(columnsCount))
        return viewModel.assetIds.indices.contains(rowStartIndex) ? viewModel.assetIds[rowStartIndex] : nil
    }

    private func rowId(sectionId: String, rowIndex: Int) -> String {
        "\(sectionId)-row-\(rowIndex)"
    }

    private var gridItems: [GridItemRow] {
        var items: [GridItemRow] = []
        for section in viewModel.monthSections {
            items.append(.header(id: section.id, title: section.title))
            let rows = chunked(section.assetIds)
            for (rowIndex, row) in rows.enumerated() {
                let id = rowId(sectionId: section.id, rowIndex: rowIndex)
                items.append(.row(id: id, ids: row))
            }
        }
        return items
    }

    private func chunked(_ ids: [String]) -> [[String]] {
        guard !ids.isEmpty else { return [] }
        let size = Int(columnsCount)
        var result: [[String]] = []
        var index = 0
        while index < ids.count {
            let end = min(index + size, ids.count)
            result.append(Array(ids[index..<end]))
            index = end
        }
        return result
    }

    private func log(_ message: String) {
        guard debugAutoscroll else { return }
        print("[AllPhotosGridView] \(message)")
    }
}

private enum GridItemRow: Identifiable {
    case header(id: String, title: String)
    case row(id: String, ids: [String])

    var id: String {
        switch self {
        case .header(let id, _): return id
        case .row(let id, _): return id
        }
    }
}

private struct ScrollViewSpeedLimiter: UIViewRepresentable {
    let speedFactor: CGFloat
    let isEnabled: Bool

    func makeUIView(context: Context) -> UIView {
        UIView()
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            guard let scrollView = findScrollView(from: uiView) else { return }
            guard isEnabled else { return }
            scrollView.decelerationRate = UIScrollView.DecelerationRate(rawValue: 0.6)
            scrollView.panGestureRecognizer.maximumNumberOfTouches = 1
        }
    }

    private func findScrollView(from view: UIView) -> UIScrollView? {
        var current: UIView? = view
        while let node = current {
            if let scrollView = node as? UIScrollView {
                return scrollView
            }
            current = node.superview
        }
        return nil
    }

}
