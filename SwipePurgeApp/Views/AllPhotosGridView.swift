import SwiftUI
import UIKit
import Photos

struct AllPhotosGridView: View {
    @ObservedObject var viewModel: SwipeDeckViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var scrollTask: Task<Void, Never>?
    @State private var isAutoScrolling = false
    @State private var activeJumpTarget: MonthJumpTarget?
    @State private var cachedGridItems: [GridItemRow] = []
    private let debugAutoscroll = true

    private let gridSpacing: CGFloat = 10
    private let columnsCount: CGFloat = 3

    var body: some View {
        ZStack(alignment: .top) {
            NavigationView {
                GeometryReader { geo in
                    let size = cellSize(availableWidth: geo.size.width)
                    ScrollViewReader { proxy in
                        ZStack {
                            ScrollView(showsIndicators: false) {
                                LazyVStack(alignment: .leading, spacing: gridSpacing) {
                                    ForEach(cachedGridItems) { item in
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
                            .opacity(isAutoScrolling ? 0 : 1)

                            if isAutoScrolling {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .controlSize(.large)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .allowsHitTesting(false)
                            }

                            if let initialTarget = activeJumpTarget {
                                jumpOverlay(initialTarget: initialTarget)
                            }
                        }
                        .background(ScrollViewSpeedLimiter(speedFactor: 0.35, isEnabled: !isAutoScrolling))
                        .onAppear {
                            log("onAppear monthSections=\(viewModel.monthSections.count) assetIds=\(viewModel.assetIds.count)")
                            refreshGridItems()
                            scheduleScroll(proxy: proxy)
                        }
                        .onChange(of: viewModel.currentAssetId) { _, _ in
                            log("currentAssetId changed")
                            scheduleScroll(proxy: proxy)
                        }
                        .onChange(of: monthSectionSnapshot) { _, _ in
                            log("monthSections changed")
                            refreshGridItems()
                            scheduleScroll(proxy: proxy)
                        }
                    }
                }
                .navigationTitle("All Photos")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                            .disabled(activeJumpTarget != nil)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Jump To") {
                            openJumpPicker()
                        }
                        .disabled(jumpTargets.isEmpty || activeJumpTarget != nil)
                    }
                }
            }

            dragHandle
                .opacity(activeJumpTarget == nil ? 1 : 0)
                .padding(.top, 8)
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.18), value: activeJumpTarget != nil)
    }

    private var dragHandle: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 44, height: 5)
    }

    private var jumpTargets: [MonthJumpTarget] {
        viewModel.monthSections.compactMap { MonthJumpTarget(section: $0) }
    }

    private var monthSectionSnapshot: [String] {
        viewModel.monthSections.map { section in
            "\(section.id)|\(section.assetIds.count)|\(section.assetIds.first ?? "")|\(section.assetIds.last ?? "")"
        }
    }

    private var initialJumpTarget: MonthJumpTarget? {
        if let currentId = viewModel.currentAssetId {
            for section in viewModel.monthSections where section.assetIds.contains(currentId) {
                if let target = MonthJumpTarget(section: section) {
                    return target
                }
            }
        }
        return jumpTargets.last ?? jumpTargets.first
    }

    private func openJumpPicker() {
        guard let target = initialJumpTarget else { return }
        scrollTask?.cancel()
        isAutoScrolling = false
        withAnimation(.easeInOut(duration: 0.18)) {
            activeJumpTarget = target
        }
    }

    private func closeJumpPicker() {
        withAnimation(.easeInOut(duration: 0.18)) {
            activeJumpTarget = nil
        }
    }

    private func jump(to target: MonthJumpTarget) {
        closeJumpPicker()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            viewModel.jump(to: target.assetId)
        }
    }

    private func jumpOverlay(initialTarget: MonthJumpTarget) -> some View {
        ZStack {
            Color.black.opacity(0.24)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    closeJumpPicker()
                }

            MonthYearJumpPopup(targets: jumpTargets,
                               initialTarget: initialTarget,
                               onCancel: closeJumpPicker,
                               onJump: jump)
                .padding(.horizontal, 24)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zIndex(5)
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

    private func refreshGridItems() {
        cachedGridItems = gridItems
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
            if Task.isCancelled { return }
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
            if Task.isCancelled { return }
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

private struct MonthJumpTarget: Identifiable, Equatable {
    let id: String
    let assetId: String
    let year: Int
    let month: Int

    init?(section: MonthSection) {
        guard section.id != "unknown", let assetId = section.assetIds.first else { return nil }
        let parts = section.id.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              (1...12).contains(month) else {
            return nil
        }

        self.id = section.id
        self.assetId = assetId
        self.year = year
        self.month = month
    }

    var monthTitle: String {
        Self.monthNames[month - 1]
    }

    static let monthNames: [String] = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]
}

private struct MonthYearJumpPopup: View {
    let targets: [MonthJumpTarget]
    let initialTarget: MonthJumpTarget
    let onCancel: () -> Void
    let onJump: (MonthJumpTarget) -> Void

    @State private var selectedYear: Int
    @State private var selectedMonth: Int

    init(targets: [MonthJumpTarget],
         initialTarget: MonthJumpTarget,
         onCancel: @escaping () -> Void,
         onJump: @escaping (MonthJumpTarget) -> Void) {
        self.targets = targets
        self.initialTarget = initialTarget
        self.onCancel = onCancel
        self.onJump = onJump
        _selectedYear = State(initialValue: initialTarget.year)
        _selectedMonth = State(initialValue: initialTarget.month)
    }

    var body: some View {
        VStack(spacing: 18) {
            Text("Jump To")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                selectorCard(title: "Month") {
                    Menu {
                        ForEach(monthsForSelectedYear, id: \.self) { month in
                            Button(MonthJumpTarget.monthNames[month - 1]) {
                                selectedMonth = month
                            }
                        }
                    } label: {
                        selectorLabel(value: selectedMonthTitle)
                    }
                    .tint(.white)
                }

                selectorCard(title: "Year") {
                    Menu {
                        ForEach(years.reversed(), id: \.self) { year in
                            Button(String(year)) {
                                selectedYear = year
                                let validMonths = months(for: year)
                                if !validMonths.contains(selectedMonth), let fallback = validMonths.last {
                                    selectedMonth = fallback
                                }
                            }
                        }
                    } label: {
                        selectorLabel(value: String(selectedYear))
                    }
                    .tint(.white)
                }
            }

            HStack(spacing: 12) {
                popupButton(title: "Cancel", action: onCancel)

                popupButton(title: "Jump", tint: Color.blue.opacity(0.10)) {
                    if let target = selectedTarget {
                        onJump(target)
                    }
                }
                .disabled(selectedTarget == nil)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 22)
        .frame(width: 332)
        .background {
            RoundedRectangle(cornerRadius: 28)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(Color.white.opacity(0.08))
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.16), radius: 18, x: 0, y: 14)
    }

    private var years: [Int] {
        Array(Set(targets.map(\.year))).sorted()
    }

    private var monthsForSelectedYear: [Int] {
        months(for: selectedYear)
    }

    private var selectedTarget: MonthJumpTarget? {
        targets.first { $0.year == selectedYear && $0.month == selectedMonth }
    }

    private var selectedMonthTitle: String {
        MonthJumpTarget.monthNames[selectedMonth - 1]
    }

    private func months(for year: Int) -> [Int] {
        targets
            .filter { $0.year == year }
            .map(\.month)
            .sorted()
    }

    private func selectorCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.06))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
    }

    private func selectorLabel(value: String) -> some View {
        HStack(spacing: 8) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 8)

            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func popupButton(
        title: String,
        tint: Color = Color.white.opacity(0.06),
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
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
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
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
