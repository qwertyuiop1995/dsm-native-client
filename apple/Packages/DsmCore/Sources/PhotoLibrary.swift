import Foundation

public enum PhotoSpaceKind: String, Codable, CaseIterable, Sendable {
    case personal
    case shared
}

public struct PhotoSpace: Identifiable, Codable, Hashable, Sendable {
    public var id: PhotoSpaceKind { kind }
    public let kind: PhotoSpaceKind
    public let title: String
    public let rootPath: String

    public init(kind: PhotoSpaceKind, title: String, rootPath: String) {
        self.kind = kind
        self.title = title
        self.rootPath = rootPath
    }

    public static let personal = PhotoSpace(
        kind: .personal,
        title: "个人空间",
        rootPath: "/home/Photos"
    )

    public static let shared = PhotoSpace(
        kind: .shared,
        title: "共享空间",
        rootPath: "/photo"
    )
}

public enum PhotoLibraryItemKind: String, Codable, Sendable {
    case folder
    case image
    case video
}

public enum PhotoBrowseMode: String, Codable, CaseIterable, Sendable {
    case folders
    case timeline
    case albums
}

public enum PhotoMediaFilter: String, Codable, CaseIterable, Sendable {
    case all
    case images
    case videos
}

public struct PhotoLibraryItem: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let profileID: UUID
    public let name: String
    public let path: String
    public let kind: PhotoLibraryItemKind
    public let sizeBytes: Int64?
    public let createdAt: Date?
    public let modifiedAt: Date?
    public let fileExtension: String?
    public let thumbnailAvailable: Bool?
    public var livePhotoVideoPath: String?

    public init?(_ file: FileItem, livePhotoVideoPath: String? = nil) {
        let itemKind: PhotoLibraryItemKind
        if file.isDirectory {
            itemKind = .folder
        } else {
            switch PreviewKind.classify(file) {
            case .image:
                itemKind = .image
            case .video:
                itemKind = .video
            default:
                return nil
            }
        }

        id = file.id
        profileID = file.profileID
        name = file.name
        path = file.path
        kind = itemKind
        sizeBytes = file.sizeBytes
        createdAt = file.times?.createdAt
        modifiedAt = file.times?.modifiedAt
        fileExtension = file.fileExtension
        thumbnailAvailable = file.thumbnailAvailable
        self.livePhotoVideoPath = livePhotoVideoPath
    }

    public init(
        id: String,
        profileID: UUID,
        name: String,
        path: String,
        kind: PhotoLibraryItemKind,
        sizeBytes: Int64?,
        createdAt: Date?,
        modifiedAt: Date?,
        fileExtension: String?,
        thumbnailAvailable: Bool?,
        livePhotoVideoPath: String? = nil
    ) {
        self.id = id
        self.profileID = profileID
        self.name = name
        self.path = path
        self.kind = kind
        self.sizeBytes = sizeBytes
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.fileExtension = fileExtension
        self.thumbnailAvailable = thumbnailAvailable
        self.livePhotoVideoPath = livePhotoVideoPath
    }

    public var isFolder: Bool {
        kind == .folder
    }

    public var isLivePhoto: Bool {
        livePhotoVideoPath != nil
    }

    public var fileItem: FileItem {
        FileItem(
            profileID: profileID,
            name: name,
            path: path,
            kind: isFolder ? .directory : .file,
            sizeBytes: sizeBytes,
            fileExtension: fileExtension,
            times: FileTimes(modifiedAt: modifiedAt, createdAt: createdAt, accessedAt: nil),
            thumbnailAvailable: thumbnailAvailable
        )
    }

    /// 自动匹配同一目录下同名的图片 (.heic/.jpg) 与短视频 (.mov/.mp4) 为动态照片 Live Photo
    /// - Parameter isCancelled: 可选的取消检查闭包，用于大量数据在后台计算时尽早停止。
    public static func pairLivePhotos(
        _ items: [PhotoLibraryItem],
        isCancelled: (@Sendable () -> Bool)? = nil
    ) -> [PhotoLibraryItem] {
        var videosByStem: [String: PhotoLibraryItem] = [:]
        for item in items where item.kind == .video {
            if isCancelled?() == true { return [] }
            let directory = (item.path as NSString).deletingLastPathComponent
            let stem = ((item.name as NSString).deletingPathExtension).lowercased()
            let key = "\(directory)/\(stem)"
            videosByStem[key] = item
        }

        var pairedVideoPaths: Set<String> = []
        var result: [PhotoLibraryItem] = []

        for item in items {
            if isCancelled?() == true { return [] }
            if item.kind == .image {
                let directory = (item.path as NSString).deletingLastPathComponent
                let stem = ((item.name as NSString).deletingPathExtension).lowercased()
                let key = "\(directory)/\(stem)"
                if let videoItem = videosByStem[key] {
                    pairedVideoPaths.insert(videoItem.path)
                    var pairedItem = item
                    pairedItem.livePhotoVideoPath = videoItem.path
                    result.append(pairedItem)
                } else {
                    result.append(item)
                }
            } else if item.kind == .video {
                if !pairedVideoPaths.contains(item.path) {
                    result.append(item)
                }
            } else {
                result.append(item)
            }
        }

        return result.filter { item in
            if item.kind == .video && pairedVideoPaths.contains(item.path) {
                return false
            }
            return true
        }
    }
}

public struct PhotoLibraryPage: Codable, Equatable, Sendable {
    public let folderPath: String
    public let items: [PhotoLibraryItem]
    public let offset: Int
    public let nextOffset: Int
    public let sourceTotal: Int
    public let hasMore: Bool

    public init(
        folderPath: String,
        items: [PhotoLibraryItem],
        offset: Int,
        nextOffset: Int,
        sourceTotal: Int,
        hasMore: Bool
    ) {
        self.folderPath = folderPath
        self.items = items
        self.offset = offset
        self.nextOffset = nextOffset
        self.sourceTotal = sourceTotal
        self.hasMore = hasMore
    }
}

public struct PhotoTimelineScanUpdate: Sendable {
    public let items: [PhotoLibraryItem]
    public let removedPaths: [String]
    public let scannedFolderCount: Int
    public let skippedFolderPaths: [String]

    public init(
        items: [PhotoLibraryItem],
        removedPaths: [String] = [],
        scannedFolderCount: Int,
        skippedFolderPaths: [String] = []
    ) {
        self.items = items
        self.removedPaths = removedPaths
        self.scannedFolderCount = scannedFolderCount
        self.skippedFolderPaths = skippedFolderPaths
    }

    public var skippedFolderCount: Int {
        skippedFolderPaths.count
    }
}

/// 照片基础能力所需的最小官方文件接口，便于与完整文件管理 Repository 解耦测试。
public protocol PhotoFileServing: Sendable {
    func listShares(offset: Int, limit: Int) async throws -> FilePage
    func listFolder(path: String, offset: Int, limit: Int) async throws -> FilePage
    func getThumbnail(path: String, size: ThumbnailSize) async throws -> Data
    func search(folderPath: String, query: String) async throws -> [FileItem]
}

public protocol PhotoLibraryRepository: Sendable {
    func discoverSpaces() async throws -> [PhotoSpace]
    func listFolder(
        in space: PhotoSpace,
        path: String,
        offset: Int,
        limit: Int
    ) async throws -> PhotoLibraryPage
    func getThumbnail(for item: PhotoLibraryItem, size: ThumbnailSize) async throws -> Data
    func scanTimeline(
        in space: PhotoSpace,
        startingAt folderPaths: [String],
        existingFolderItemPaths: [String: [String]],
        onUpdate: @escaping @Sendable (PhotoTimelineScanUpdate) async -> Void
    ) async throws
}

public extension PhotoLibraryRepository {
    func scanTimeline(
        in space: PhotoSpace,
        startingAt folderPaths: [String],
        onUpdate: @escaping @Sendable (PhotoTimelineScanUpdate) async -> Void
    ) async throws {
        try await scanTimeline(
            in: space,
            startingAt: folderPaths,
            existingFolderItemPaths: [:],
            onUpdate: onUpdate
        )
    }

    func scanTimeline(
        in space: PhotoSpace,
        onUpdate: @escaping @Sendable (PhotoTimelineScanUpdate) async -> Void
    ) async throws {
        try await scanTimeline(
            in: space,
            startingAt: [space.rootPath],
            existingFolderItemPaths: [:],
            onUpdate: onUpdate
        )
    }

    func scanTimeline(
        in space: PhotoSpace,
        existingFolderItemPaths: [String: [String]],
        onUpdate: @escaping @Sendable (PhotoTimelineScanUpdate) async -> Void
    ) async throws {
        try await scanTimeline(
            in: space,
            startingAt: [space.rootPath],
            existingFolderItemPaths: existingFolderItemPaths,
            onUpdate: onUpdate
        )
    }
}

public struct PhotoTimelineSection: Identifiable, Sendable {
    public let date: Date
    public let title: String
    public let items: [PhotoLibraryItem]
    public var id: Date { date }

    public init(date: Date, title: String, items: [PhotoLibraryItem]) {
        self.date = date
        self.title = title
        self.items = items
    }
}
