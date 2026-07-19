import AppKit
import AVFoundation
import DsmCore
import Foundation
import ImageIO
import Observation

protocol PhotoThumbnailFallbackProviding: Sendable {
    func canGenerateThumbnail(for item: PhotoLibraryItem) -> Bool
    func thumbnailData(for item: PhotoLibraryItem) async -> Data?
}

/// 当 File Station 无法生成 HEIC 或 MOV 缩略图时，使用系统媒体框架在本机生成。
struct LocalPhotoThumbnailFallback: PhotoThumbnailFallbackProviding {
    private static let imageDownloadLimit: Int64 = 40 * 1_024 * 1_024
    private static let maximumPixelSize = 480

    private let files: any FileRepository

    init(files: any FileRepository) {
        self.files = files
    }

    func canGenerateThumbnail(for item: PhotoLibraryItem) -> Bool {
        switch Self.fileExtension(for: item) {
        case "heic", "heif", "mov": true
        default: false
        }
    }

    func thumbnailData(for item: PhotoLibraryItem) async -> Data? {
        let fileExtension = Self.fileExtension(for: item)
        switch fileExtension {
        case "heic", "heif":
            return await downloadedImageThumbnailData(for: item, fileExtension: fileExtension)
        case "mov":
            return await streamedVideoThumbnailData(for: item)
        default:
            return nil
        }
    }

    private func downloadedImageThumbnailData(
        for item: PhotoLibraryItem,
        fileExtension: String
    ) async -> Data? {
        guard let sizeBytes = item.sizeBytes,
              sizeBytes > 0,
              sizeBytes <= Self.imageDownloadLimit else {
            return nil
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lanstash-photo-thumbnail-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)

        do {
            try await files.download(
                remotePath: item.path,
                to: temporaryURL,
                expectedSize: sizeBytes,
                progress: { _, _ in }
            )
            try Task.checkCancellation()

            let data = Self.imageThumbnailData(at: temporaryURL)
            try? FileManager.default.removeItem(at: temporaryURL)
            return data
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            await files.removePartialDownload(to: temporaryURL)
            return nil
        }
    }

    private func streamedVideoThumbnailData(for item: PhotoLibraryItem) async -> Data? {
        do {
            let source = try await files.mediaStreamSource(
                remotePath: item.path,
                fileExtension: item.fileExtension,
                expectedContentLength: item.sizeBytes
            )
            let delegate = DsmAVAssetResourceLoaderDelegate(
                source: source,
                onFailure: { _ in },
                onLoadingMetrics: { _, _ in }
            )
            defer { delegate.cancelAll() }

            guard let assetURL = URL(
                string: "lanstash-thumbnail://stream/\(UUID().uuidString).mov"
            ) else { return nil }
            let asset = AVURLAsset(url: assetURL)
            asset.resourceLoader.setDelegate(
                delegate,
                queue: DispatchQueue(label: "io.github.qwertyuiop1995.lanstash.thumbnail-loader")
            )
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(
                width: Self.maximumPixelSize,
                height: Self.maximumPixelSize
            )
            generator.requestedTimeToleranceBefore = .positiveInfinity
            generator.requestedTimeToleranceAfter = .positiveInfinity
            let result = try await generator.image(
                at: CMTime(seconds: 0.1, preferredTimescale: 600)
            )
            return Self.jpegData(from: result.image)
        } catch {
            return nil
        }
    }

    private static func imageThumbnailData(at url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
                  ] as CFDictionary
              ) else { return nil }
        return jpegData(from: image)
    }

    private static func jpegData(from image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.82]
        )
    }

    private static func fileExtension(for item: PhotoLibraryItem) -> String {
        (item.fileExtension ?? URL(fileURLWithPath: item.name).pathExtension).lowercased()
    }
}

@MainActor
@Observable
final class PhotoLibraryModel {
    private(set) var spaces: [PhotoSpace] = []
    var selectedSpaceID: PhotoSpaceKind?
    private(set) var currentPath = ""
    private(set) var items: [PhotoLibraryItem] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var hasMore = false
    private(set) var sourceTotal = 0
    private(set) var errorMessage: String?
    var browseMode: PhotoBrowseMode = .timeline {
        didSet { restartThumbnailPrefetchIfPossible() }
    }
    var mediaFilter: PhotoMediaFilter = .all {
        didSet { restartThumbnailPrefetchIfPossible() }
    }
    var searchText = "" {
        didSet { restartThumbnailPrefetchIfPossible() }
    }
    var selection: Set<PhotoLibraryItem.ID> = []
    private(set) var timelineItems: [PhotoLibraryItem] = []
    private(set) var isLoadingTimeline = false
    private(set) var isRetryingTimelineFolders = false
    private(set) var timelineScannedFolderCount = 0
    private(set) var timelineSkippedFolderPaths: [String] = []
    private(set) var timelineRetryMessage: String?

    @ObservationIgnored private let repository: any PhotoLibraryRepository
    @ObservationIgnored private var history: [String] = []
    @ObservationIgnored private var nextOffset = 0
    @ObservationIgnored private var navigationGeneration = 0
    @ObservationIgnored private var thumbnailCache: [PhotoLibraryItem.ID: Data] = [:]
    @ObservationIgnored private var unavailableThumbnails: Set<PhotoLibraryItem.ID> = []
    @ObservationIgnored private let thumbnailRequestGate = ThumbnailRequestGate(limit: 6)
    @ObservationIgnored private let fallbackThumbnailRequestGate = ThumbnailRequestGate(limit: 2)
    @ObservationIgnored private let thumbnailFallback: (any PhotoThumbnailFallbackProviding)?
    @ObservationIgnored private var visibleThumbnailIDs: Set<PhotoLibraryItem.ID> = []
    @ObservationIgnored private var loadingVisibleThumbnailIDs: Set<PhotoLibraryItem.ID> = []
    @ObservationIgnored private var thumbnailPrefetchTask: Task<Void, Never>?
    @ObservationIgnored private var thumbnailPrefetchGeneration = 0
    @ObservationIgnored private var timelineTask: Task<Void, Never>?
    @ObservationIgnored private var timelineGeneration = 0

    init(
        repository: any PhotoLibraryRepository,
        thumbnailFallback: (any PhotoThumbnailFallbackProviding)? = nil
    ) {
        self.repository = repository
        self.thumbnailFallback = thumbnailFallback
    }

    var selectedSpace: PhotoSpace? {
        guard let selectedSpaceID else { return nil }
        return spaces.first { $0.id == selectedSpaceID }
    }

    var canGoBack: Bool {
        !history.isEmpty
    }

    var canGoUp: Bool {
        guard let selectedSpace else { return false }
        return currentPath != selectedSpace.rootPath
            && currentPath.hasPrefix(selectedSpace.rootPath + "/")
    }

    var locationTitle: String {
        guard let selectedSpace else { return "照片" }
        guard currentPath != selectedSpace.rootPath else { return selectedSpace.title }
        return URL(fileURLWithPath: currentPath).lastPathComponent
    }

    var displayedItems: [PhotoLibraryItem] {
        let source = browseMode == .timeline ? timelineItems : items
        return source.filter { item in
            let matchesType: Bool
            switch mediaFilter {
            case .all: matchesType = true
            case .images: matchesType = item.kind == .image || item.isFolder
            case .videos: matchesType = item.kind == .video || item.isFolder
            }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            return matchesType && (query.isEmpty || item.name.localizedCaseInsensitiveContains(query))
        }
    }

    var selectedItems: [PhotoLibraryItem] {
        displayedItems.filter { selection.contains($0.id) }
    }

    var timelineSkippedFolderCount: Int {
        timelineSkippedFolderPaths.count
    }

    func loadIfNeeded() async {
        guard spaces.isEmpty, !isLoading else { return }
        await reloadSpaces()
    }

    func reloadSpaces() async {
        navigationGeneration += 1
        let generation = navigationGeneration
        isLoading = true
        errorMessage = nil
        defer {
            if generation == navigationGeneration {
                isLoading = false
            }
        }

        do {
            let discovered = try await repository.discoverSpaces()
            guard generation == navigationGeneration else { return }
            spaces = discovered
            guard let destination = discovered.first(where: { $0.id == selectedSpaceID })
                    ?? discovered.first else {
                selectedSpaceID = nil
                currentPath = ""
                items = []
                hasMore = false
                sourceTotal = 0
                return
            }
            selectedSpaceID = destination.id
            history.removeAll()
            await loadFolder(destination.rootPath, recordingHistory: false)
            if browseMode == .timeline { await loadTimeline() }
        } catch {
            guard generation == navigationGeneration else { return }
            errorMessage = Self.userMessage(for: error)
            spaces = []
            items = []
        }
    }

    func selectSpace(_ id: PhotoSpaceKind) async {
        guard let space = spaces.first(where: { $0.id == id }), selectedSpaceID != id else {
            return
        }
        selectedSpaceID = id
        history.removeAll()
        timelineItems = []
        selection.removeAll()
        cancelTimelineScan()
        await loadFolder(space.rootPath, recordingHistory: false)
        if browseMode == .timeline { await loadTimeline() }
    }

    func open(_ item: PhotoLibraryItem) async {
        guard item.isFolder else { return }
        await loadFolder(item.path, recordingHistory: true)
    }

    func goBack() async {
        guard let previous = history.popLast() else { return }
        await loadFolder(previous, recordingHistory: false)
    }

    func goUp() async {
        guard canGoUp, let selectedSpace else { return }
        let parent = URL(fileURLWithPath: currentPath).deletingLastPathComponent().path
        let destination = parent.count < selectedSpace.rootPath.count ? selectedSpace.rootPath : parent
        await loadFolder(destination, recordingHistory: true)
    }

    func refreshAll() async {
        if spaces.isEmpty {
            await reloadSpaces()
        } else if !currentPath.isEmpty {
            await loadFolder(currentPath, recordingHistory: false)
            if browseMode == .timeline { await loadTimeline() }
        }
    }

    func setBrowseMode(_ mode: PhotoBrowseMode) async {
        browseMode = mode
        selection.removeAll()
        if mode == .timeline {
            if timelineItems.isEmpty { await loadTimeline() }
        } else {
            cancelTimelineScan()
        }
    }

    func loadTimeline() async {
        guard let selectedSpace else { return }
        cancelTimelineScan()
        timelineGeneration += 1
        let generation = timelineGeneration
        timelineItems = []
        timelineScannedFolderCount = 0
        timelineSkippedFolderPaths = []
        timelineRetryMessage = nil
        errorMessage = nil
        isLoadingTimeline = true

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await repository.scanTimeline(in: selectedSpace) { [weak self] update in
                    await MainActor.run {
                        guard let self, generation == self.timelineGeneration else { return }
                        let knownIDs = Set(self.timelineItems.map(\.id))
                        self.timelineItems.append(contentsOf: update.items.filter { !knownIDs.contains($0.id) })
                        self.timelineItems.sort(by: Self.timelineSort)
                        self.timelineScannedFolderCount = update.scannedFolderCount
                        self.timelineSkippedFolderPaths = update.skippedFolderPaths
                    }
                }
            } catch is CancellationError {
                // 用户切换到文件夹浏览时正常结束，不显示错误。
            } catch {
                await MainActor.run {
                    guard generation == self.timelineGeneration else { return }
                    self.errorMessage = Self.userMessage(for: error)
                }
            }

            await MainActor.run {
                guard generation == self.timelineGeneration else { return }
                self.isLoadingTimeline = false
            }
        }
        timelineTask = task
        await task.value
        if generation == timelineGeneration { timelineTask = nil }
    }

    func retrySkippedTimelineFolders() async {
        guard let selectedSpace,
              !timelineSkippedFolderPaths.isEmpty,
              !isLoadingTimeline,
              !isRetryingTimelineFolders else { return }

        let targetPaths = timelineSkippedFolderPaths
        let generation = timelineGeneration
        isRetryingTimelineFolders = true
        timelineRetryMessage = nil

        do {
            try await repository.scanTimeline(in: selectedSpace, startingAt: targetPaths) { [weak self] update in
                await MainActor.run {
                    guard let self, generation == self.timelineGeneration else { return }
                    let knownIDs = Set(self.timelineItems.map(\.id))
                    self.timelineItems.append(contentsOf: update.items.filter { !knownIDs.contains($0.id) })
                    self.timelineItems.sort(by: Self.timelineSort)
                    self.timelineSkippedFolderPaths = update.skippedFolderPaths
                }
            }
        } catch is CancellationError {
            // 用户离开时间线时正常结束，不显示错误。
        } catch {
            guard generation == timelineGeneration else { return }
            timelineSkippedFolderPaths = targetPaths
            timelineRetryMessage = Self.userMessage(for: error)
        }

        if generation == timelineGeneration {
            isRetryingTimelineFolders = false
        }
    }

    func cancelTimelineScan() {
        timelineTask?.cancel()
        timelineTask = nil
        timelineGeneration += 1
        isLoadingTimeline = false
        isRetryingTimelineFolders = false
    }

    func select(_ item: PhotoLibraryItem, extending: Bool) {
        guard !item.isFolder else { return }
        if extending {
            if selection.contains(item.id) { selection.remove(item.id) }
            else { selection.insert(item.id) }
        } else {
            selection = [item.id]
        }
    }

    func clearSelection() {
        selection.removeAll()
    }

    func cachedThumbnailData(for item: PhotoLibraryItem) -> Data? {
        thumbnailCache[item.id]
    }

    func thumbnailBecameVisible(_ item: PhotoLibraryItem) {
        guard !item.isFolder else { return }
        visibleThumbnailIDs.insert(item.id)
        cancelThumbnailPrefetch()
        if thumbnailCache[item.id] == nil, !unavailableThumbnails.contains(item.id) {
            loadingVisibleThumbnailIDs.insert(item.id)
        } else {
            loadingVisibleThumbnailIDs.remove(item.id)
        }
    }

    func thumbnailBecameHidden(_ item: PhotoLibraryItem) {
        visibleThumbnailIDs.remove(item.id)
        loadingVisibleThumbnailIDs.remove(item.id)
        restartThumbnailPrefetchIfPossible()
    }

    func thumbnailRequestDidFinish(for item: PhotoLibraryItem) {
        loadingVisibleThumbnailIDs.remove(item.id)
        scheduleThumbnailPrefetchIfPossible()
    }

    /// 删除任务已由 NAS 确认并复查后，只更新受影响的本地集合，避免重新扫描整个照片空间。
    func removeDeletedItems(at paths: [String]) {
        guard !paths.isEmpty else { return }
        let normalizedPaths = paths.map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
        let isDeleted: (PhotoLibraryItem) -> Bool = { item in
            normalizedPaths.contains { path in
                item.path == path || item.path.hasPrefix(path + "/")
            }
        }

        let removedFolderItems = items.filter(isDeleted)
        let removedTimelineItems = timelineItems.filter(isDeleted)
        items.removeAll(where: isDeleted)
        timelineItems.removeAll(where: isDeleted)

        let removedIDs = Set((removedFolderItems + removedTimelineItems).map(\.id))
        selection.subtract(removedIDs)
        for id in removedIDs {
            thumbnailCache[id] = nil
            unavailableThumbnails.remove(id)
        }

        sourceTotal = max(0, sourceTotal - removedFolderItems.count)
        nextOffset = max(0, nextOffset - removedFolderItems.count)
        visibleThumbnailIDs.subtract(removedIDs)
        loadingVisibleThumbnailIDs.subtract(removedIDs)
        restartThumbnailPrefetchIfPossible()
    }

    func loadMore() async {
        guard let selectedSpace, hasMore, !isLoadingMore, !currentPath.isEmpty else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let result = try await fetchVisiblePage(
                in: selectedSpace,
                path: currentPath,
                offset: nextOffset
            )
            let existing = Set(items.map(\.id))
            items.append(contentsOf: result.items.filter { !existing.contains($0.id) })
            nextOffset = result.nextOffset
            hasMore = result.hasMore
            sourceTotal = result.sourceTotal
        } catch {
            errorMessage = Self.userMessage(for: error)
        }
    }

    func thumbnailData(for item: PhotoLibraryItem) async -> Data? {
        guard !item.isFolder else { return nil }
        if let cached = thumbnailCache[item.id] { return cached }
        guard !unavailableThumbnails.contains(item.id) else { return nil }
        guard let requestToken = await thumbnailRequestGate.acquire() else { return nil }

        var repositoryError: AppError?
        var repositoryData: Data?
        do {
            repositoryData = try await repository.getThumbnail(for: item, size: .small)
        } catch is CancellationError {
            repositoryData = nil
        } catch let error as AppError {
            repositoryError = error
        } catch {
            repositoryData = nil
        }
        await thumbnailRequestGate.release(requestToken)

        if let repositoryData,
           !Task.isCancelled,
           Self.isDisplayableImageData(repositoryData) {
            cacheThumbnail(repositoryData, for: item.id)
            return repositoryData
        }

        guard !Task.isCancelled,
              let thumbnailFallback,
              thumbnailFallback.canGenerateThumbnail(for: item) else {
            if repositoryError?.isRetryable == false {
                unavailableThumbnails.insert(item.id)
            } else if repositoryData != nil {
                unavailableThumbnails.insert(item.id)
            }
            return nil
        }
        guard let fallbackToken = await fallbackThumbnailRequestGate.acquire() else { return nil }
        let fallbackData = await thumbnailFallback.thumbnailData(for: item)
        await fallbackThumbnailRequestGate.release(fallbackToken)

        guard !Task.isCancelled,
              let fallbackData,
              Self.isDisplayableImageData(fallbackData) else {
            // HEIC/MOV 的本机生成可能因文件大小或临时连接失败，保留后续重试机会。
            return nil
        }
        cacheThumbnail(fallbackData, for: item.id)
        return fallbackData
    }

    private func cacheThumbnail(_ data: Data, for id: PhotoLibraryItem.ID) {
        if thumbnailCache.count >= 300 {
            let removableKeys = thumbnailCache.keys.filter { !visibleThumbnailIDs.contains($0) }
            for key in removableKeys.prefix(60) {
                thumbnailCache[key] = nil
            }
        }
        thumbnailCache[id] = data
    }

    private func restartThumbnailPrefetchIfPossible() {
        cancelThumbnailPrefetch()
        scheduleThumbnailPrefetchIfPossible()
    }

    private func cancelThumbnailPrefetch() {
        thumbnailPrefetchGeneration += 1
        thumbnailPrefetchTask?.cancel()
        thumbnailPrefetchTask = nil
    }

    private func scheduleThumbnailPrefetchIfPossible() {
        guard thumbnailPrefetchTask == nil,
              !visibleThumbnailIDs.isEmpty,
              loadingVisibleThumbnailIDs.isEmpty else { return }

        let orderedMedia = displayedItems.filter { !$0.isFolder }
        let visibleIndexes = orderedMedia.indices.filter {
            visibleThumbnailIDs.contains(orderedMedia[$0].id)
        }
        guard let lastVisibleIndex = visibleIndexes.max(), lastVisibleIndex + 1 < orderedMedia.count else {
            return
        }

        // 只预取视窗之后的一小段，防止长时间空闲时把整个照片库读入缓存。
        let candidates = orderedMedia[(lastVisibleIndex + 1)...]
            .filter {
                thumbnailCache[$0.id] == nil
                    && !unavailableThumbnails.contains($0.id)
                    && !visibleThumbnailIDs.contains($0.id)
            }
            .prefix(48)
        guard !candidates.isEmpty else { return }

        thumbnailPrefetchGeneration += 1
        let generation = thumbnailPrefetchGeneration
        thumbnailPrefetchTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await Task.yield()
            for item in candidates {
                guard !Task.isCancelled,
                      generation == thumbnailPrefetchGeneration,
                      loadingVisibleThumbnailIDs.isEmpty else { return }
                _ = await thumbnailData(for: item)
            }
            guard generation == thumbnailPrefetchGeneration else { return }
            thumbnailPrefetchTask = nil
        }
    }

    private static func isDisplayableImageData(_ data: Data) -> Bool {
        !data.isEmpty && NSImage(data: data) != nil
    }

    private func loadFolder(_ path: String, recordingHistory: Bool) async {
        guard let selectedSpace else { return }
        let previousPath = currentPath
        navigationGeneration += 1
        let generation = navigationGeneration
        isLoading = true
        errorMessage = nil

        do {
            let result = try await fetchVisiblePage(in: selectedSpace, path: path, offset: 0)
            guard generation == navigationGeneration else { return }
            if recordingHistory, !previousPath.isEmpty, previousPath != path {
                history.append(previousPath)
            }
            currentPath = path
            items = result.items
            selection.removeAll()
            nextOffset = result.nextOffset
            hasMore = result.hasMore
            sourceTotal = result.sourceTotal
            isLoading = false
        } catch {
            guard generation == navigationGeneration else { return }
            isLoading = false
            errorMessage = Self.userMessage(for: error)
        }
    }

    private func fetchVisiblePage(
        in space: PhotoSpace,
        path: String,
        offset: Int
    ) async throws -> PhotoLibraryPage {
        var page = try await repository.listFolder(
            in: space,
            path: path,
            offset: offset,
            limit: 300
        )
        var visibleItems = page.items
        var attempts = 1

        while visibleItems.isEmpty, page.hasMore, attempts < 4 {
            try Task.checkCancellation()
            page = try await repository.listFolder(
                in: space,
                path: path,
                offset: page.nextOffset,
                limit: 300
            )
            visibleItems.append(contentsOf: page.items)
            attempts += 1
        }

        return PhotoLibraryPage(
            folderPath: page.folderPath,
            items: visibleItems,
            offset: offset,
            nextOffset: page.nextOffset,
            sourceTotal: page.sourceTotal,
            hasMore: page.hasMore
        )
    }

    private static func userMessage(for error: Error) -> String {
        if let error = error as? AppError {
            return error.safeUserMessage
        }
        return "照片暂时无法读取，请检查连接后重试。"
    }

    private static func timelineSort(_ lhs: PhotoLibraryItem, _ rhs: PhotoLibraryItem) -> Bool {
        let left = lhs.createdAt ?? lhs.modifiedAt ?? .distantPast
        let right = rhs.createdAt ?? rhs.modifiedAt ?? .distantPast
        if left != right { return left > right }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}

/// 限制缩略图并发，并允许离开可视区域的等待任务立即让出队列位置。
private actor ThumbnailRequestGate {
    private struct Waiter {
        let token: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let limit: Int
    private var activeCount = 0
    private var waiters: [Waiter] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func acquire() async -> UUID? {
        guard !Task.isCancelled else { return nil }
        let token = UUID()
        if activeCount < limit {
            activeCount += 1
            return token
        }

        let granted = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters.append(Waiter(token: token, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiting(token) }
        }

        guard granted else { return nil }
        guard !Task.isCancelled else {
            release(token)
            return nil
        }
        return token
    }

    func release(_ token: UUID) {
        guard activeCount > 0 else { return }
        activeCount -= 1
        resumeNextWaiter()
    }

    private func cancelWaiting(_ token: UUID) {
        guard let index = waiters.firstIndex(where: { $0.token == token }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(returning: false)
    }

    private func resumeNextWaiter() {
        guard !waiters.isEmpty, activeCount < limit else { return }
        let waiter = waiters.removeFirst()
        activeCount += 1
        waiter.continuation.resume(returning: true)
    }
}
