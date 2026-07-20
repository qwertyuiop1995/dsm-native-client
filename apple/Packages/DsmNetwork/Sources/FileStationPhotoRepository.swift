import DsmCore
import Foundation

/// 只使用 Synology 官方登录和 File Station API 的基础照片库 Adapter。
public struct FileStationPhotoRepository: PhotoLibraryRepository, Sendable {
    private let files: any PhotoFileServing

    public init(files: any PhotoFileServing) {
        self.files = files
    }

    public func discoverSpaces() async throws -> [PhotoSpace] {
        let shares = try await files.listShares(offset: 0, limit: 500).items
        var result: [PhotoSpace] = []

        do {
            _ = try await files.listFolder(
                path: PhotoSpace.personal.rootPath,
                offset: 0,
                limit: 1
            )
            result.append(.personal)
        } catch let error as AppError where Self.spaceMayBeUnavailable(error) {
            // 个人空间可能未启用；这不应阻止共享空间继续使用。
        }

        if shares.contains(where: {
            $0.path.caseInsensitiveCompare(PhotoSpace.shared.rootPath) == .orderedSame
        }) {
            result.append(.shared)
        }

        return result
    }

    public func listFolder(
        in space: PhotoSpace,
        path: String,
        offset: Int,
        limit: Int
    ) async throws -> PhotoLibraryPage {
        guard Self.contains(path: path, in: space.rootPath) else {
            throw AppError(
                category: .permissionDenied,
                isRetryable: false,
                safeUserMessage: "无法打开这个位置，因为它不在当前照片空间中。"
            )
        }

        let page = try await files.listFolder(
            path: path,
            offset: max(0, offset),
            limit: max(1, limit)
        )
        return PhotoLibraryPage(
            folderPath: page.folderPath,
            items: page.items.compactMap { PhotoLibraryItem($0) },
            offset: page.offset,
            nextOffset: page.offset + page.items.count,
            sourceTotal: page.total,
            hasMore: page.hasMore
        )
    }

    public func getThumbnail(for item: PhotoLibraryItem, size: ThumbnailSize) async throws -> Data {
        guard !item.isFolder else {
            throw AppError(
                category: .invalidResponse,
                isRetryable: false,
                safeUserMessage: "文件夹没有可显示的照片缩略图。"
            )
        }
        return try await files.getThumbnail(path: item.path, size: size)
    }

    public func scanTimeline(
        in space: PhotoSpace,
        startingAt folderPaths: [String],
        existingFolderItemPaths: [String: [String]] = [:],
        onUpdate: @escaping @Sendable (PhotoTimelineScanUpdate) async -> Void
    ) async throws {
        guard !folderPaths.isEmpty,
              folderPaths.allSatisfy({ Self.contains(path: $0, in: space.rootPath) }) else {
            throw AppError(
                category: .permissionDenied,
                isRetryable: false,
                safeUserMessage: "只能读取当前照片空间中的文件夹。"
            )
        }

        // 批量聚合，降低每次扫描后 UI 重算的频率。
        // 每累积超过 500 个项目时统一刷新一次。
        let itemBatchThreshold = 500
        let concurrentFolderLimit = 6
        var visitedFolders = Set<String>()
        var skippedFolderPaths = Set<String>()
        var batchedItems: [PhotoLibraryItem] = []
        var batchedRemoved: [String] = []

        func flushBatch(isFinal: Bool = false) async {
            if batchedItems.isEmpty && batchedRemoved.isEmpty && !isFinal { return }
            await onUpdate(
                PhotoTimelineScanUpdate(
                    items: batchedItems,
                    removedPaths: batchedRemoved,
                    scannedFolderCount: visitedFolders.count,
                    skippedFolderPaths: skippedFolderPaths.sorted()
                )
            )
            batchedItems.removeAll(keepingCapacity: true)
            batchedRemoved.removeAll(keepingCapacity: true)
        }

        /// 按目录层级并发扫描：同一层级的文件夹用 TaskGroup 并行读取，
        /// 扫描完成后把子文件夹加入下一层级，直到没有新文件夹为止。
        var currentLevel = folderPaths
        while !currentLevel.isEmpty {
            try Task.checkCancellation()

            let toScan = currentLevel.compactMap { path -> String? in
                guard visitedFolders.insert(path).inserted else { return nil }
                return path
            }
            currentLevel.removeAll(keepingCapacity: true)

            let results: [TimelineScanFolderResult] = try await withThrowingTaskGroup(of: TimelineScanFolderResult.self) { group in
                for folderPath in toScan.prefix(concurrentFolderLimit) {
                    group.addTask {
                        await self.scanSingleFolder(
                            folderPath: folderPath,
                            in: space,
                            existingFolderItemPaths: existingFolderItemPaths
                        )
                    }
                }

                var remaining = Array(toScan.dropFirst(concurrentFolderLimit))
                var collected: [TimelineScanFolderResult] = []
                for try await result in group {
                    collected.append(result)
                    if let next = remaining.first {
                        remaining.removeFirst()
                        group.addTask {
                            await self.scanSingleFolder(
                                folderPath: next,
                                in: space,
                                existingFolderItemPaths: existingFolderItemPaths
                            )
                        }
                    }
                }
                return collected
            }

            for result in results {
                if result.skipped {
                    skippedFolderPaths.insert(result.folderPath)
                } else {
                    batchedItems.append(contentsOf: result.items)
                    batchedRemoved.append(contentsOf: result.removed)
                    currentLevel.append(contentsOf: result.subfolders)
                }
            }

            if batchedItems.count >= itemBatchThreshold {
                await flushBatch()
            }
        }

        await flushBatch(isFinal: true)
    }

    /// 扫描单个文件夹，返回照片项、子文件夹、删除项路径以及是否被跳过。
    private func scanSingleFolder(
        folderPath: String,
        in space: PhotoSpace,
        existingFolderItemPaths: [String: [String]]
    ) async -> TimelineScanFolderResult {
        do {
            try Task.checkCancellation()
            var offset = 0
            var discovered: [PhotoLibraryItem] = []
            var subfolders: [String] = []
            while true {
                try Task.checkCancellation()
                let page = try await files.listFolder(path: folderPath, offset: offset, limit: 500)
                for file in page.items {
                    if file.isDirectory {
                        guard !file.name.hasPrefix("@"), file.name != "#recycle" else { continue }
                        if Self.contains(path: file.path, in: space.rootPath) {
                            subfolders.append(file.path)
                        }
                    } else if let item = PhotoLibraryItem(file) {
                        discovered.append(item)
                    }
                }

                let nextOffset = page.offset + page.items.count
                guard page.hasMore, nextOffset > offset else { break }
                offset = nextOffset
            }

            let currentPaths = Set(discovered.map(\.path))
            let previousPaths = Set(existingFolderItemPaths[folderPath] ?? [])
            let removed = Array(previousPaths.subtracting(currentPaths))

            return TimelineScanFolderResult(
                items: discovered,
                subfolders: subfolders,
                removed: removed,
                skipped: false,
                folderPath: folderPath
            )
        } catch is CancellationError {
            return TimelineScanFolderResult(
                items: [],
                subfolders: [],
                removed: [],
                skipped: true,
                folderPath: folderPath
            )
        } catch let error as AppError where folderPath != space.rootPath && Self.canSkipTimelineFolder(error) {
            return TimelineScanFolderResult(
                items: [],
                subfolders: [],
                removed: [],
                skipped: true,
                folderPath: folderPath
            )
        } catch {
            return TimelineScanFolderResult(
                items: [],
                subfolders: [],
                removed: [],
                skipped: folderPath != space.rootPath,
                folderPath: folderPath
            )
        }
    }

    private struct TimelineScanFolderResult: Sendable {
        let items: [PhotoLibraryItem]
        let subfolders: [String]
        let removed: [String]
        let skipped: Bool
        let folderPath: String
    }

    private static func contains(path: String, in rootPath: String) -> Bool {
        let candidate = path.split(separator: "/", omittingEmptySubsequences: true)
        let root = rootPath.split(separator: "/", omittingEmptySubsequences: true)
        guard candidate.count >= root.count,
              !candidate.contains("."),
              !candidate.contains("..") else {
            return false
        }
        return Array(candidate.prefix(root.count)) == root
    }

    private static func spaceMayBeUnavailable(_ error: AppError) -> Bool {
        error.category == .notFound || error.category == .permissionDenied
    }

    private static func canSkipTimelineFolder(_ error: AppError) -> Bool {
        switch error.category {
        case .invalidResponse, .notFound, .permissionDenied:
            true
        default:
            false
        }
    }
}
