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

        var pendingFolders = folderPaths
        var visitedFolders = Set<String>()
        var nextFolderIndex = 0
        var skippedFolderPaths = Set<String>()

        while nextFolderIndex < pendingFolders.count {
            try Task.checkCancellation()
            let folderPath = pendingFolders[nextFolderIndex]
            nextFolderIndex += 1
            guard visitedFolders.insert(folderPath).inserted else { continue }

            var offset = 0
            var discoveredInFolder: [PhotoLibraryItem] = []
            do {
                while true {
                    try Task.checkCancellation()
                    let page = try await files.listFolder(path: folderPath, offset: offset, limit: 500)
                    for file in page.items {
                        if file.isDirectory {
                            guard !file.name.hasPrefix("@"), file.name != "#recycle" else { continue }
                            if Self.contains(path: file.path, in: space.rootPath) {
                                pendingFolders.append(file.path)
                            }
                        } else if let item = PhotoLibraryItem(file) {
                            discoveredInFolder.append(item)
                        }
                    }

                    let nextOffset = page.offset + page.items.count
                    guard page.hasMore, nextOffset > offset else { break }
                    offset = nextOffset
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as AppError where folderPath != space.rootPath && Self.canSkipTimelineFolder(error) {
                skippedFolderPaths.insert(folderPath)
            }

            // 计算在此文件夹中，历史上存在但最新扫描已不存在的文件路径（即删除项目）
            let currentPaths = Set(discoveredInFolder.map(\.path))
            let previousPaths = Set(existingFolderItemPaths[folderPath] ?? [])
            let removedInFolder = Array(previousPaths.subtracting(currentPaths))

            await onUpdate(
                PhotoTimelineScanUpdate(
                    items: discoveredInFolder,
                    removedPaths: removedInFolder,
                    scannedFolderCount: visitedFolders.count,
                    skippedFolderPaths: skippedFolderPaths.sorted()
                )
            )
        }
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
