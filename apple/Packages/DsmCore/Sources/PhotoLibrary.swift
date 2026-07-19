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

    public init?(_ file: FileItem) {
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
    }

    public var isFolder: Bool {
        kind == .folder
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
    public let scannedFolderCount: Int
    public let skippedFolderPaths: [String]

    public init(items: [PhotoLibraryItem], scannedFolderCount: Int, skippedFolderPaths: [String] = []) {
        self.items = items
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
        onUpdate: @escaping @Sendable (PhotoTimelineScanUpdate) async -> Void
    ) async throws
}

public extension PhotoLibraryRepository {
    func scanTimeline(
        in space: PhotoSpace,
        onUpdate: @escaping @Sendable (PhotoTimelineScanUpdate) async -> Void
    ) async throws {
        try await scanTimeline(in: space, startingAt: [space.rootPath], onUpdate: onUpdate)
    }
}
