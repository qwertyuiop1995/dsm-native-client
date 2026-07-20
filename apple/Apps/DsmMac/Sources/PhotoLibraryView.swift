import AppKit
import DsmCore
import SwiftUI

struct PhotoLibraryView: View {
    @Bindable var model: PhotoLibraryModel
    let onPreview: (PhotoLibraryItem) -> Void
    let onDownload: ([PhotoLibraryItem]) -> Void
    let onDelete: ([PhotoLibraryItem]) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 12, alignment: .top)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if shouldShowTimelineScanStatus {
                timelineScanStatus
                Divider()
            }
            content
        }
        .task { await model.loadIfNeeded() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label(
                model.browseMode == .timeline ? "时间线" : model.locationTitle,
                systemImage: model.browseMode == .timeline ? "clock" : "photo.on.rectangle"
            )
            .font(.headline)
            .lineLimit(1)

            Picker("浏览方式", selection: browseModeSelection) {
                Label("文件夹", systemImage: "folder").tag(PhotoBrowseMode.folders)
                Label("时间线", systemImage: "clock").tag(PhotoBrowseMode.timeline)
            }
            .pickerStyle(.segmented)
            .fixedSize()

            mediaStatsBadge

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索照片或视频", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 180)
                if !model.searchText.isEmpty {
                    Button("清除搜索", systemImage: "xmark.circle.fill") {
                        model.searchText = ""
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 7))

            Menu {
                Picker("媒体类型", selection: $model.mediaFilter) {
                    Label("全部", systemImage: "photo.on.rectangle.angled").tag(PhotoMediaFilter.all)
                    Label("照片", systemImage: "photo").tag(PhotoMediaFilter.images)
                    Label("视频", systemImage: "video").tag(PhotoMediaFilter.videos)
                }
            } label: {
                Label(mediaFilterTitle, systemImage: "line.3.horizontal.decrease.circle")
            }
            .help("按照片或视频筛选")

            if model.spaces.count > 1 {
                Picker("照片空间", selection: spaceSelection) {
                    ForEach(model.spaces) { space in
                        Text(space.title).tag(Optional(space.id))
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityHint("切换个人照片和共享照片")
            } else if let space = model.selectedSpace {
                Text(space.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var mediaStatsBadge: some View {
        let stats = model.mediaStats
        return HStack(spacing: 5) {
            Label {
                Text("\(Self.formattedNumber(stats.total))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "photo.stack.fill")
                    .foregroundStyle(Color.accentColor)
            }

            Text("(")
                .foregroundStyle(.secondary.opacity(0.6))

            Label("\(Self.formattedNumber(stats.images))", systemImage: "photo")
                .foregroundStyle(.secondary)

            Text("·")
                .foregroundStyle(.secondary.opacity(0.6))

            Label("\(Self.formattedNumber(stats.videos))", systemImage: "video")
                .foregroundStyle(.secondary)

            Text(")")
                .foregroundStyle(.secondary.opacity(0.6))
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.55), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("媒体库共计 \(stats.total) 项，包含 \(stats.images) 张照片，\(stats.videos) 个视频")
    }

    private static func formattedNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoadingTimeline && model.displayedItems.isEmpty {
            timelineLoadingState
        } else if model.isLoading && model.displayedItems.isEmpty {
            loadingGrid
        } else if model.spaces.isEmpty {
            VStack(spacing: 0) {
                Spacer().frame(height: 36)
                ContentUnavailableView {
                    Label("没有可浏览的照片空间", systemImage: "photo.badge.exclamationmark")
                } description: {
                    Text(model.errorMessage ?? "请确认个人照片空间或共享照片空间已在 NAS 中启用，并允许当前账号访问。")
                } actions: {
                    Button("重新检查") { Task { await model.reloadSpaces() } }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if let errorMessage = model.errorMessage, model.displayedItems.isEmpty {
            VStack(spacing: 0) {
                Spacer().frame(height: 36)
                ContentUnavailableView {
                    Label("照片暂时无法显示", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重新扫描全部照片") { Task { await model.refreshAll() } }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if model.displayedItems.isEmpty {
            VStack(spacing: 0) {
                Spacer().frame(height: 36)
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: model.searchText.isEmpty ? "photo" : "magnifyingglass")
                } description: {
                    Text(emptyDescription)
                } actions: {
                    if !model.searchText.isEmpty || model.mediaFilter != .all {
                        Button("清除筛选") {
                            model.searchText = ""
                            model.mediaFilter = .all
                        }
                    } else {
                        Button("重新扫描全部照片") { Task { await model.refreshAll() } }
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            GeometryReader { viewport in
                ScrollView {
                    if let errorMessage = model.errorMessage {
                        errorBanner(errorMessage)
                    }

                    if model.timelineSkippedFolderCount > 0 || model.isRetryingTimelineFolders {
                        timelineNoticeBanner
                    }

                    if model.browseMode == .timeline {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(model.timelineSections) { section in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(section.title)
                                        .font(.headline)
                                        .accessibilityAddTraits(.isHeader)
                                    photoGrid(section.items)
                                }
                            }
                        }
                        .padding(16)
                    } else {
                        photoGrid(model.displayedItems)
                            .padding(16)
                    }

                    if model.isLoadingMore {
                        ProgressView("正在载入更多照片…")
                            .controlSize(.small)
                            .padding(.bottom, 20)
                    }
                }
            }
        }
    }

    private var shouldShowTimelineScanStatus: Bool {
        model.browseMode == .timeline
            && (model.isLoadingTimeline || model.isSyncingTimeline)
            && !model.timelineItems.isEmpty
    }

    private var timelineScanStatus: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(
                    "正在检查照片变更，已载入 \(model.timelineItems.count) 项，已检查 \(model.timelineScannedFolderCount) 个文件夹"
                )

            Text("正在检查照片变更")
                .font(.callout.weight(.medium))
                .accessibilityHidden(true)

            Text("已载入 \(model.timelineItems.count) 项 · 已检查 \(model.timelineScannedFolderCount) 个文件夹")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Spacer(minLength: 8)

            Button("改用文件夹浏览") {
                Task { await model.setBrowseMode(.folders) }
            }
            .buttonStyle(.borderless)
            .accessibilityHint("停止当前时间线扫描并切换到文件夹浏览")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.35))
    }

    private var timelineLoadingState: some View {
        ContentUnavailableView {
            ProgressView()
                .controlSize(.large)
                .accessibilityLabel("正在建立照片时间线")
        } description: {
            VStack(spacing: 6) {
                Text("正在建立照片时间线…")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("已扫描 \(model.timelineScannedFolderCount) 个文件夹。首次打开会花一些时间，之后仍可切换到文件夹浏览。")
            }
        } actions: {
            Button("改用文件夹浏览") {
                Task { await model.setBrowseMode(.folders) }
            }
        }
    }

    private func photoGrid(_ items: [PhotoLibraryItem]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(items) { item in
                PhotoLibraryCell(
                    model: model,
                    item: item,
                    isSelected: model.selection.contains(item.id),
                    onPreview: onPreview,
                    onDownload: onDownload,
                    onDelete: onDelete
                )
                .task {
                    if model.browseMode == .folders, item.id == model.displayedItems.last?.id {
                        await model.loadMore()
                    }
                }
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .accessibilityAddTraits(.isStaticText)
    }

    private var timelineNoticeBanner: some View {
        HStack(spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    if model.isRetryingTimelineFolders {
                        Text("正在重试未读取的文件夹…")
                    } else {
                        Text("有 \(model.timelineSkippedFolderCount) 个文件夹本次未能读取，其他照片已正常显示。")
                    }
                    if let message = model.timelineRetryMessage {
                        Text(message)
                            .font(.caption)
                    }
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Button("重试这些文件夹") {
                Task { await model.retrySkippedTimelineFolders() }
            }
            .buttonStyle(.bordered)
            .disabled(model.isRetryingTimelineFolders)
            .accessibilityHint("只重新读取本次失败的文件夹，不会重新扫描整个照片库")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var loadingGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(0..<18, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 7) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.quaternary)
                            .aspectRatio(1, contentMode: .fit)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.quaternary)
                            .frame(height: 12)
                    }
                    .redacted(reason: .placeholder)
                    .accessibilityHidden(true)
                }
            }
            .padding(16)
        }
        .accessibilityLabel("正在读取照片")
    }

    private var browseModeSelection: Binding<PhotoBrowseMode> {
        Binding(
            get: { model.browseMode },
            set: { mode in Task { await model.setBrowseMode(mode) } }
        )
    }

    private var spaceSelection: Binding<PhotoSpaceKind?> {
        Binding(
            get: { model.selectedSpaceID },
            set: { id in
                guard let id else { return }
                Task { await model.selectSpace(id) }
            }
        )
    }

    private var mediaFilterTitle: String {
        switch model.mediaFilter {
        case .all: "全部"
        case .images: "照片"
        case .videos: "视频"
        }
    }

    private var emptyTitle: String {
        if !model.searchText.isEmpty { return "没有找到匹配项目" }
        if model.mediaFilter != .all { return "没有符合筛选条件的项目" }
        return "这里还没有照片"
    }

    private var emptyDescription: String {
        if !model.searchText.isEmpty || model.mediaFilter != .all {
            return "换一个关键词或清除筛选后再试。"
        }
        return "使用工具栏的“上传”把照片或视频添加到当前位置。"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct PhotoTimelineSection: Identifiable {
    let date: Date
    let title: String
    let items: [PhotoLibraryItem]
    var id: Date { date }
}

private struct PhotoLibraryCell: View {
    @Bindable var model: PhotoLibraryModel
    let item: PhotoLibraryItem
    let isSelected: Bool
    let onPreview: (PhotoLibraryItem) -> Void
    let onDownload: ([PhotoLibraryItem]) -> Void
    let onDelete: ([PhotoLibraryItem]) -> Void

    var body: some View {
        Button {
            if item.isFolder {
                Task { await model.open(item) }
            } else {
                let extending = NSEvent.modifierFlags.intersection([.command, .shift]).isEmpty == false
                model.select(item, extending: extending)
            }
        } label: {
            cellContents
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                if !item.isFolder { onPreview(item) }
            }
        )
        .contextMenu {
            if item.isFolder {
                Button("打开文件夹") { Task { await model.open(item) } }
            } else {
                Button("打开预览") { onPreview(item) }
            }

            Divider()

            Button {
                onDownload(contextTargets)
            } label: {
                Label(contextTargets.count > 1 ? "下载 \(contextTargets.count) 项" : "下载", systemImage: "square.and.arrow.down")
            }

            Button(role: .destructive) {
                onDelete(contextTargets)
            } label: {
                Label(contextTargets.count > 1 ? "删除 \(contextTargets.count) 项…" : "删除…", systemImage: "trash")
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(item.isFolder ? "打开这个照片文件夹" : "单击选择，双击打开预览")
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var cellContents: some View {
        VStack(alignment: .leading, spacing: 7) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    ZStack(alignment: .topTrailing) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(item.isFolder ? Color.accentColor.opacity(0.09) : Color.secondary.opacity(0.08))

                        if item.isFolder {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(.blue)
                        } else {
                            PhotoGridThumbnail(
                                model: model,
                                item: item
                            )
                        }

                        if item.isLivePhoto {
                            VStack {
                                Spacer()
                                HStack {
                                    HStack(spacing: 3) {
                                        Image(systemName: "livephoto")
                                            .font(.caption2.weight(.bold))
                                        Text("LIVE")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 3)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.3), radius: 2)
                                    .padding(6)
                                    Spacer()
                                }
                            }
                        }

                        let isMultiSelecting = model.selection.count > 1
                        if isSelected && isMultiSelecting {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.accentColor)
                                .padding(7)
                                .accessibilityHidden(true)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                            .padding(-6)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isSelected ? (model.selection.count > 1 ? Color.accentColor : Color.accentColor.opacity(0.6)) : Color(nsColor: .separatorColor).opacity(0.55),
                                lineWidth: isSelected ? (model.selection.count > 1 ? 3 : 1.5) : 0.5
                            )
                    }
                }

            Text(item.name)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30, alignment: .topLeading)
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var accessibilityLabel: String {
        if item.isFolder { return "文件夹，\(item.name)" }
        return "\(item.kind == .video ? "视频" : "照片")，\(item.name)\(isSelected ? "，已选择" : "")"
    }

    private var contextTargets: [PhotoLibraryItem] {
        if model.selection.contains(item.id) {
            let selected = model.selectedItems
            if !selected.isEmpty { return selected }
        }
        return [item]
    }
}

private struct PhotoGridThumbnail: View {
    @Bindable var model: PhotoLibraryModel
    let item: PhotoLibraryItem
    @State private var data: Data?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let data, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Image(systemName: item.kind == .video ? "video.fill" : "photo.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                        .frame(width: geo.size.width, height: geo.size.height)
                }

                if item.kind == .video {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 28))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.48))
                        .shadow(radius: 2)
                }
            }
        }
        .task(priority: .userInitiated) {
            model.thumbnailBecameVisible(item)
            if let cached = await model.cachedThumbnailData(for: item) {
                data = cached
                model.thumbnailRequestDidFinish(for: item)
                return
            }
            let loadedData = await model.thumbnailData(for: item)
            model.thumbnailRequestDidFinish(for: item)
            guard !Task.isCancelled else { return }
            data = loadedData
        }
        .onDisappear {
            // 离屏时取消可见标记，并立即清空 data，释放像素位图内存
            model.thumbnailBecameHidden(item)
            data = nil
        }
    }
}

private enum PhotoViewportCoordinateSpace {
    static let name = "photo-library-viewport"
}
