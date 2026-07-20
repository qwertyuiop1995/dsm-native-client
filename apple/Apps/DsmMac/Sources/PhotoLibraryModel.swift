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
    private(set) var items: [PhotoLibraryItem] = [] {
        didSet { updateDisplayedItems() }
    }
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var hasMore = false
    private(set) var sourceTotal = 0
    private(set) var errorMessage: String?
    var browseMode: PhotoBrowseMode = .timeline {
        didSet { scheduleDisplayedItemsUpdate() }
    }
    var mediaFilter: PhotoMediaFilter = .all {
        didSet { scheduleDisplayedItemsUpdate() }
    }
    var searchText = "" {
        didSet { scheduleDisplayedItemsUpdate() }
    }
    var selection: Set<PhotoLibraryItem.ID> = []
    private(set) var timelineItems: [PhotoLibraryItem] = [] {
        didSet { updateDisplayedItems() }
    }
    private(set) var displayedItems: [PhotoLibraryItem] = []
    private(set) var isLoadingTimeline = false
    private(set) var isSyncingTimeline = false
    private(set) var isRetryingTimelineFolders = false
    private(set) var timelineScannedFolderCount = 0
    private(set) var timelineSkippedFolderPaths: [String] = []
    private(set) var timelineRetryMessage: String?
    private(set) var activeProfileID: UUID?

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
    @ObservationIgnored private var displayedItemsUpdateTask: Task<Void, Never>?
    @ObservationIgnored private var timelineFolderItemPaths: [String: [String]] = [:]
    @ObservationIgnored private let cacheStore: PhotoLibraryCacheStore
    @ObservationIgnored private let thumbnailDiskCacheStore: PhotoThumbnailDiskCacheStore
    @ObservationIgnored private var cachedItemsCountOnDisk: Int = 0

    init(
        repository: any PhotoLibraryRepository,
        profileID: UUID? = nil,
        thumbnailFallback: (any PhotoThumbnailFallbackProviding)? = nil,
        cacheStore: PhotoLibraryCacheStore = PhotoLibraryCacheStore(),
        thumbnailDiskCacheStore: PhotoThumbnailDiskCacheStore = PhotoThumbnailDiskCacheStore()
    ) {
        self.repository = repository
        self.activeProfileID = profileID
        self.thumbnailFallback = thumbnailFallback
        self.cacheStore = cacheStore
        self.thumbnailDiskCacheStore = thumbnailDiskCacheStore
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

    var mediaStats: (total: Int, images: Int, videos: Int) {
        let mediaItems = PhotoLibraryItem.pairLivePhotos(displayedItems.isEmpty ? (browseMode == .timeline ? timelineItems : items) : displayedItems)
            .filter { !$0.isFolder }
        var imageCount = 0
        var videoCount = 0
        for item in mediaItems {
            if item.kind == .image { imageCount += 1 }
            else if item.kind == .video { videoCount += 1 }
        }
        return (mediaItems.count, imageCount, videoCount)
    }

    private(set) var timelineSections: [PhotoTimelineSection] = []

    /// 防抖调度显示项更新：搜索输入、筛选切换或浏览方式变化时不会立即重算，
    /// 等用户停止操作约 0.25 秒后再统一执行，减少大量数据时的卡顿。
    /// 测试运行时直接同步执行，避免 XCTest 断言时机问题。
    private func scheduleDisplayedItemsUpdate() {
        displayedItemsUpdateTask?.cancel()
        if Self.isRunningTests {
            restartThumbnailPrefetchIfPossible()
            updateDisplayedItems()
            return
        }
        displayedItemsUpdateTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            self.restartThumbnailPrefetchIfPossible()
            self.updateDisplayedItems()
        }
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    private func updateDisplayedItems() {
        let rawSource = browseMode == .timeline ? timelineItems : items
        let pairedSource = PhotoLibraryItem.pairLivePhotos(rawSource)
        displayedItems = pairedSource.filter { item in
            let matchesType: Bool
            switch mediaFilter {
            case .all: matchesType = true
            case .images: matchesType = item.kind == .image || item.isFolder
            case .videos: matchesType = (item.kind == .video && !item.isLivePhoto) || item.isFolder
            }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            return matchesType && (query.isEmpty || item.name.localizedCaseInsensitiveContains(query))
        }
        updateTimelineSections()
    }

    private func updateTimelineSections() {
        guard browseMode == .timeline else {
            timelineSections = []
            return
        }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: displayedItems) { item in
            calendar.startOfDay(for: item.createdAt ?? item.modifiedAt ?? .distantPast)
        }
        timelineSections = grouped.keys.sorted(by: >).map { date in
            PhotoTimelineSection(
                date: date,
                title: date == .distantPast ? "日期未知" : Self.dayFormatter.string(from: date),
                items: grouped[date] ?? []
            )
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

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
        saveCacheIfNeeded()
        selectedSpaceID = id
        history.removeAll()
        timelineItems = []
        timelineFolderItemPaths = [:]
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

    func loadTimeline(forceRescan: Bool = false) async {
        guard let selectedSpace else { return }
        cancelTimelineScan()
        timelineGeneration += 1
        let generation = timelineGeneration
        timelineRetryMessage = nil
        errorMessage = nil

        let profileID = activeProfileID ?? timelineItems.first?.profileID
        if let profileID {
            activeProfileID = profileID
        }

        // 优先尝试恢复本地持久化磁盘缓存，在后台 Task 中异步解码，避免卡死主线程
        if !forceRescan, let targetProfileID = activeProfileID ?? profileID {
            let store = cacheStore
            let spaceKind = selectedSpace.id
            let cached = await Task.detached(priority: .userInitiated) {
                store.load(profileID: targetProfileID, spaceKind: spaceKind)
            }.value

            if generation == timelineGeneration {
                if let cached, !cached.items.isEmpty {
                    if timelineItems.count < cached.items.count {
                        self.timelineItems = cached.items
                        self.timelineFolderItemPaths = cached.folderItemPaths
                        self.cachedItemsCountOnDisk = cached.items.count
                    }
                    self.isLoadingTimeline = false
                    self.isSyncingTimeline = true
                } else {
                    self.isLoadingTimeline = timelineItems.isEmpty
                    self.isSyncingTimeline = true
                }
            }
        } else {
            if forceRescan {
                self.timelineItems = []
                self.timelineFolderItemPaths = [:]
            }
            self.isLoadingTimeline = timelineItems.isEmpty
            self.isSyncingTimeline = true
        }

        timelineScannedFolderCount = 0
        timelineSkippedFolderPaths = []

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await repository.scanTimeline(
                    in: selectedSpace,
                    startingAt: [selectedSpace.rootPath],
                    existingFolderItemPaths: self.timelineFolderItemPaths
                ) { [weak self] update in
                    await MainActor.run {
                        guard let self, generation == self.timelineGeneration else { return }
                        // 1. 同步剔除已被删除的文件
                        if !update.removedPaths.isEmpty {
                            self.removeDeletedItems(at: update.removedPaths)
                        }

                        // 2. 增量归并新扫描到的项目，避免每批都重建字典并全局排序
                        if !update.items.isEmpty {
                            self.mergeTimelineItems(update.items)
                        }

                        // 3. 跟踪各个文件夹的文件路径映射
                        if let firstItem = update.items.first {
                            let folderPath = URL(fileURLWithPath: firstItem.path).deletingLastPathComponent().path
                            self.timelineFolderItemPaths[folderPath] = update.items.map(\.path)
                            if self.activeProfileID == nil {
                                self.activeProfileID = firstItem.profileID
                            }
                        }

                        self.timelineScannedFolderCount = update.scannedFolderCount
                        self.timelineSkippedFolderPaths = update.skippedFolderPaths
                        if self.isLoadingTimeline {
                            self.isLoadingTimeline = false
                        }
                        if !update.items.isEmpty || !update.removedPaths.isEmpty {
                            self.saveCacheIfNeeded()
                        }
                    }
                }

                await MainActor.run {
                    guard generation == self.timelineGeneration else { return }
                    self.saveCacheIfNeeded()
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard generation == self.timelineGeneration else { return }
                    self.saveCacheIfNeeded()
                }
            } catch {
                await MainActor.run {
                    guard generation == self.timelineGeneration else { return }
                    self.errorMessage = Self.userMessage(for: error)
                }
            }

            await MainActor.run {
                guard generation == self.timelineGeneration else { return }
                self.isLoadingTimeline = false
                self.isSyncingTimeline = false
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
            try await repository.scanTimeline(
                in: selectedSpace,
                startingAt: targetPaths,
                existingFolderItemPaths: timelineFolderItemPaths
            ) { [weak self] update in
                await MainActor.run {
                    guard let self, generation == self.timelineGeneration else { return }
                    if !update.removedPaths.isEmpty {
                        self.removeDeletedItems(at: update.removedPaths)
                    }
                    if !update.items.isEmpty {
                        self.mergeTimelineItems(update.items)
                    }
                    self.timelineSkippedFolderPaths = update.skippedFolderPaths
                }
            }
            await MainActor.run {
                guard generation == self.timelineGeneration else { return }
                self.saveCacheIfNeeded()
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
        saveCacheIfNeeded()
        timelineTask?.cancel()
        timelineTask = nil
        timelineGeneration += 1
        isLoadingTimeline = false
        isSyncingTimeline = false
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

    /// 将新扫描到的时间线项目按排序顺序增量归并到现有数组中，避免每批都重建字典并全局排序。
    private func mergeTimelineItems(_ newItems: [PhotoLibraryItem]) {
        let existingIDs = Set(timelineItems.map(\.id))
        let sortedNewItems = newItems.filter { !existingIDs.contains($0.id) }
            .sorted(by: Self.timelineSort)
        guard !sortedNewItems.isEmpty else { return }

        var merged = timelineItems
        var newIndex = 0
        var insertIndex = 0
        while insertIndex < merged.count && newIndex < sortedNewItems.count {
            if Self.timelineSort(sortedNewItems[newIndex], merged[insertIndex]) {
                merged.insert(sortedNewItems[newIndex], at: insertIndex)
                newIndex += 1
            }
            insertIndex += 1
        }
        if newIndex < sortedNewItems.count {
            merged.append(contentsOf: sortedNewItems[newIndex...])
        }
        timelineItems = merged
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

        for (folderPath, existingPaths) in timelineFolderItemPaths {
            timelineFolderItemPaths[folderPath] = existingPaths.filter { path in
                !normalizedPaths.contains { deleted in
                    path == deleted || path.hasPrefix(deleted + "/")
                }
            }
        }

        let removedIDs = Set((removedFolderItems + removedTimelineItems).map(\.id))
        selection.subtract(removedIDs)
        thumbnailCacheOrder.removeAll(where: { removedIDs.contains($0) })
        for id in removedIDs {
            thumbnailCache[id] = nil
            unavailableThumbnails.remove(id)
        }

        sourceTotal = max(0, sourceTotal - removedFolderItems.count)
        nextOffset = max(0, nextOffset - removedFolderItems.count)
        visibleThumbnailIDs.subtract(removedIDs)
        loadingVisibleThumbnailIDs.subtract(removedIDs)
        restartThumbnailPrefetchIfPossible()
        saveCacheIfNeeded()
    }

    private func saveCacheIfNeeded() {
        guard let selectedSpace else { return }
        let profileID = activeProfileID ?? timelineItems.first?.profileID
        guard let profileID else { return }
        if activeProfileID == nil {
            activeProfileID = profileID
        }

        // 防覆写安全屏障：使用内存记录的 cachedItemsCountOnDisk 进行快速对比，绝不在主线程反复同步读取 21MB 文件
        if cachedItemsCountOnDisk > (timelineItems.count + 50) && isSyncingTimeline {
            return
        }

        cachedItemsCountOnDisk = max(cachedItemsCountOnDisk, timelineItems.count)
        let cache = PhotoSpaceCache(
            items: timelineItems,
            folderItemPaths: timelineFolderItemPaths,
            lastScannedAt: Date()
        )
        let store = cacheStore
        let spaceKind = selectedSpace.id
        Task.detached(priority: .utility) {
            store.save(cache, profileID: profileID, spaceKind: spaceKind)
        }
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

    func thumbnailData(
        for item: PhotoLibraryItem,
        priority: ThumbnailRequestGate.Priority = .high
    ) async -> Data? {
        guard !item.isFolder else { return nil }
        if let cached = await cachedThumbnailData(for: item) { return cached }
        guard !unavailableThumbnails.contains(item.id) else { return nil }
        guard let requestToken = await thumbnailRequestGate.acquire(priority: priority) else { return nil }

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
            cacheThumbnail(repositoryData, for: item)
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
        cacheThumbnail(fallbackData, for: item)
        return fallbackData
    }

    @ObservationIgnored private var thumbnailCacheOrder: [PhotoLibraryItem.ID] = []

    func cachedThumbnailData(for item: PhotoLibraryItem) async -> Data? {
        if let data = thumbnailCache[item.id] {
            if let index = thumbnailCacheOrder.firstIndex(of: item.id) {
                thumbnailCacheOrder.remove(at: index)
                thumbnailCacheOrder.append(item.id)
            }
            return data
        }
        // 从磁盘加载缩略图持久化缓存，放到后台线程，避免阻塞主线程。
        let profileID = activeProfileID ?? item.profileID
        let diskStore = thumbnailDiskCacheStore
        let diskData = await Task.detached(priority: .userInitiated) {
            diskStore.load(profileID: profileID, itemID: item.id)
        }.value
        if let diskData {
            thumbnailCache[item.id] = diskData
            thumbnailCacheOrder.append(item.id)
            return diskData
        }
        return nil
    }

    private func cacheThumbnail(_ data: Data, for item: PhotoLibraryItem) {
        let id = item.id
        if let existingIndex = thumbnailCacheOrder.firstIndex(of: id) {
            thumbnailCacheOrder.remove(at: existingIndex)
        }
        thumbnailCacheOrder.append(id)
        thumbnailCache[id] = data

        // 异步写入磁盘落盘持久化
        let profileID = activeProfileID ?? item.profileID
        let diskStore = thumbnailDiskCacheStore
        Task.detached(priority: .utility) {
            diskStore.save(data, profileID: profileID, itemID: id)
        }

        if thumbnailCache.count > 1000 {
            let overflowCount = thumbnailCache.count - 1000
            var removedCount = 0
            var i = 0
            while i < thumbnailCacheOrder.count && removedCount < overflowCount {
                let key = thumbnailCacheOrder[i]
                if !visibleThumbnailIDs.contains(key) {
                    thumbnailCache[key] = nil
                    thumbnailCacheOrder.remove(at: i)
                    removedCount += 1
                } else {
                    i += 1
                }
            }
        }
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
                _ = await thumbnailData(for: item, priority: .low)
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
/// 支持高/低优先级：可见项使用高优先级，预取使用低优先级，避免滚动时预取抢占可见项。
internal actor ThumbnailRequestGate {
    enum Priority: Sendable {
        case high
        case low
    }

    private struct Waiter {
        let token: UUID
        let continuation: CheckedContinuation<Bool, Never>
        let priority: Priority
    }

    private let limit: Int
    private var activeCount = 0
    private var highPriorityWaiters: [Waiter] = []
    private var lowPriorityWaiters: [Waiter] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func acquire(priority: Priority = .high) async -> UUID? {
        guard !Task.isCancelled else { return nil }
        let token = UUID()
        if activeCount < limit {
            activeCount += 1
            return token
        }

        let granted = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let waiter = Waiter(token: token, continuation: continuation, priority: priority)
                if priority == .high {
                    highPriorityWaiters.append(waiter)
                } else {
                    lowPriorityWaiters.append(waiter)
                }
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
        if let index = highPriorityWaiters.firstIndex(where: { $0.token == token }) {
            let waiter = highPriorityWaiters.remove(at: index)
            waiter.continuation.resume(returning: false)
            return
        }
        if let index = lowPriorityWaiters.firstIndex(where: { $0.token == token }) {
            let waiter = lowPriorityWaiters.remove(at: index)
            waiter.continuation.resume(returning: false)
        }
    }

    private func resumeNextWaiter() {
        guard activeCount < limit else { return }
        if let waiter = highPriorityWaiters.first {
            highPriorityWaiters.removeFirst()
            activeCount += 1
            waiter.continuation.resume(returning: true)
            return
        }
        guard !lowPriorityWaiters.isEmpty else { return }
        let waiter = lowPriorityWaiters.removeFirst()
        activeCount += 1
        waiter.continuation.resume(returning: true)
    }
}
