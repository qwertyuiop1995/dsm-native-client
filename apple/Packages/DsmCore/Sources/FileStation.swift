import Foundation

public enum FileKind: String, Codable, Sendable {
    case file
    case directory
    case symlink
    case unknown
}

public struct FileTimes: Codable, Hashable, Sendable {
    public let modifiedAt: Date?
    public let createdAt: Date?
    public let accessedAt: Date?

    public init(modifiedAt: Date?, createdAt: Date?, accessedAt: Date?) {
        self.modifiedAt = modifiedAt
        self.createdAt = createdAt
        self.accessedAt = accessedAt
    }
}

public struct FilePermissions: Codable, Hashable, Sendable {
    public let canRead: Bool
    public let canWrite: Bool
    public let canDelete: Bool
    public let posixMode: Int?

    public init(canRead: Bool, canWrite: Bool, canDelete: Bool, posixMode: Int?) {
        self.canRead = canRead
        self.canWrite = canWrite
        self.canDelete = canDelete
        self.posixMode = posixMode
    }
}

public struct FileItem: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let profileID: UUID
    public let name: String
    public let path: String
    public let kind: FileKind
    public let sizeBytes: Int64?
    public let mimeType: String?
    public let fileExtension: String?
    public let owner: String?
    public let group: String?
    public let times: FileTimes?
    public let permissions: FilePermissions?
    public let thumbnailAvailable: Bool?
    public let isRecyclePath: Bool
    public let rawType: String?
    public let mountPointType: String?

    public init(
        profileID: UUID,
        name: String,
        path: String,
        kind: FileKind,
        sizeBytes: Int64? = nil,
        mimeType: String? = nil,
        fileExtension: String? = nil,
        owner: String? = nil,
        group: String? = nil,
        times: FileTimes? = nil,
        permissions: FilePermissions? = nil,
        thumbnailAvailable: Bool? = nil,
        isRecyclePath: Bool? = nil,
        rawType: String? = nil,
        mountPointType: String? = nil
    ) {
        self.id = "\(profileID.uuidString):\(path)"
        self.profileID = profileID
        self.name = name
        self.path = path
        self.kind = kind
        self.sizeBytes = sizeBytes
        self.mimeType = mimeType
        self.fileExtension = fileExtension ?? URL(fileURLWithPath: name).pathExtension.lowercased()
        self.owner = owner
        self.group = group
        self.times = times
        self.permissions = permissions
        self.thumbnailAvailable = thumbnailAvailable
        self.isRecyclePath = isRecyclePath ?? path.split(separator: "/").contains("#recycle")
        self.rawType = rawType
        self.mountPointType = mountPointType
    }

    public var isDirectory: Bool {
        kind == .directory
    }
}

public struct FavoriteLocation: Identifiable, Codable, Hashable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

public struct FileShareLink: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    public let url: String
    public let hasPassword: Bool
    public let expiresAt: String?

    public init(
        id: String,
        name: String,
        path: String,
        url: String,
        hasPassword: Bool = false,
        expiresAt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.url = url
        self.hasPassword = hasPassword
        self.expiresAt = expiresAt
    }
}

public struct FilePage: Codable, Equatable, Sendable {
    public let folderPath: String
    public let items: [FileItem]
    public let offset: Int
    public let total: Int
    public let hasMore: Bool
    public let loadedAt: Date

    public init(
        folderPath: String,
        items: [FileItem],
        offset: Int,
        total: Int,
        hasMore: Bool,
        loadedAt: Date = Date()
    ) {
        self.folderPath = folderPath
        self.items = items
        self.offset = offset
        self.total = total
        self.hasMore = hasMore
        self.loadedAt = loadedAt
    }
}

public enum ThumbnailSize: String, Codable, Sendable {
    case small
    case medium
    case large
}

public enum PreviewKind: String, Codable, Sendable {
    case image
    case pdf
    case text
    case video
    case audio
    case unsupported

    public static func classify(_ item: FileItem) -> PreviewKind {
        let ext = item.fileExtension?.lowercased() ?? ""
        if ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tif", "tiff", "bmp"].contains(ext) {
            return .image
        }
        if ext == "pdf" {
            return .pdf
        }
        if [
            "txt", "md", "markdown", "json", "xml", "yaml", "yml", "log", "csv", "tsv",
            "swift", "kt", "kts", "java", "cs", "js", "tsx", "jsx", "html", "css",
            "py", "rb", "go", "rs", "sh", "zsh", "ini", "conf", "toml"
        ].contains(ext) {
            return .text
        }
        if ext == "ts" {
            // `.ts` 同时可能是 TypeScript 或 MPEG 传输流；这里只采信服务端明确类型，
            // 未知时由预览流程读取文件头判断，不能用文件大小猜测。
            if item.mimeType?.lowercased().hasPrefix("video/") == true {
                return .video
            }
            return .text
        }
        if ["mp4", "mkv", "mov", "avi", "flv", "webm", "m4v", "3gp", "mts", "m2ts"].contains(ext) {
            return .video
        }
        if ["mp3", "wav", "m4a", "aac", "flac", "ogg", "wma"].contains(ext) {
            return .audio
        }
        return .unsupported
    }
}

public enum FileContentSniffer {
    /// 根据文件头区分 MPEG 传输流与文本。传输流包以 0x47 同步字节按固定间隔重复。
    public static func classifyTypeScriptOrTransportStream(_ data: Data) -> PreviewKind {
        guard !data.isEmpty else { return .text }
        let bytes = [UInt8](data)
        for packetSize in [188, 192, 204] {
            let maximumOffset = min(packetSize, 16)
            for offset in 0..<maximumOffset {
                var matches = 0
                var index = offset
                while index < bytes.count, matches < 4 {
                    guard bytes[index] == 0x47 else { break }
                    matches += 1
                    index += packetSize
                }
                if matches >= 3 { return .video }
            }
        }
        return .text
    }
}

public struct RecycleLocation: Equatable, Sendable {
    public let recycleRoot: String
    public let relativePath: String
    public let originalPath: String
    public let originalParentPath: String

    public init?(recyclePath: String) {
        let normalized = recyclePath.hasPrefix("/") ? recyclePath : "/\(recyclePath)"
        let components = normalized.split(separator: "/").map(String.init)
        guard let recycleIndex = components.firstIndex(of: "#recycle"),
              recycleIndex == 1,
              components.count > recycleIndex + 1 else {
            return nil
        }

        let share = components[0]
        let tail = components.dropFirst(recycleIndex + 1)
        recycleRoot = "/\(share)/#recycle"
        relativePath = "/" + tail.joined(separator: "/")
        originalPath = "/\(share)/" + tail.joined(separator: "/")
        originalParentPath = URL(fileURLWithPath: originalPath).deletingLastPathComponent().path
    }
}

public typealias FileTransferProgress = @Sendable (_ completedBytes: Int64, _ totalBytes: Int64?) -> Void

/// 只在内存中交给媒体播放器使用。请求头可能包含短期会话信息，不得记录或持久化。
public struct MediaStreamSource: @unchecked Sendable {
    public let request: URLRequest
    public let fileExtension: String?
    public let expectedContentLength: Int64?
    public let expectedHost: String
    public let pinnedCertificateSHA256: String?

    public init(
        request: URLRequest,
        fileExtension: String?,
        expectedContentLength: Int64?,
        expectedHost: String,
        pinnedCertificateSHA256: String?
    ) {
        self.request = request
        self.fileExtension = fileExtension
        self.expectedContentLength = expectedContentLength
        self.expectedHost = expectedHost
        self.pinnedCertificateSHA256 = pinnedCertificateSHA256
    }
}

public protocol FileRepository: Sendable {
    var profileID: UUID { get }
    var allowsVerifiedRestore: Bool { get }

    func listShares(offset: Int, limit: Int) async throws -> FilePage
    func listFolder(path: String, offset: Int, limit: Int) async throws -> FilePage
    func getInfo(paths: [String]) async throws -> [FileItem]
    func getThumbnail(path: String, size: ThumbnailSize) async throws -> Data
    func readPrefix(remotePath: String, maximumLength: Int) async throws -> Data
    func checkWritePermission(folderPath: String, filename: String, createOnly: Bool) async throws
    func mediaStreamSource(
        remotePath: String,
        fileExtension: String?,
        expectedContentLength: Int64?
    ) async throws -> MediaStreamSource
    func download(
        remotePath: String,
        to localURL: URL,
        expectedSize: Int64?,
        progress: @escaping FileTransferProgress
    ) async throws
    func downloadArchive(
        remotePaths: [String],
        to localURL: URL,
        progress: @escaping FileTransferProgress
    ) async throws
    func removePartialDownload(to localURL: URL) async
    func upload(
        localURL: URL,
        to folderPath: String,
        overwrite: Bool,
        progress: @escaping FileTransferProgress
    ) async throws
    func delete(paths: [String], progress: @escaping FileTransferProgress) async throws
    func createFolder(parentPath: String, name: String) async throws
    func rename(path: String, newName: String) async throws
    func copy(
        paths: [String],
        to destinationFolder: String,
        overwrite: Bool,
        progress: @escaping FileTransferProgress
    ) async throws
    func move(
        paths: [String],
        to destinationFolder: String,
        overwrite: Bool,
        progress: @escaping FileTransferProgress
    ) async throws
    func compress(
        paths: [String],
        destinationFilePath: String,
        format: ArchiveFormat,
        level: ArchiveCompressionLevel,
        password: String?,
        progress: @escaping FileTransferProgress
    ) async throws
    func extract(
        filePath: String,
        destinationFolder: String,
        overwrite: Bool,
        keepDirectoryStructure: Bool,
        createSubfolder: Bool,
        codepage: String?,
        password: String?,
        progress: @escaping FileTransferProgress
    ) async throws
    func listArchiveItems(filePath: String, codepage: String?, password: String?) async throws -> [ArchiveItem]
    func search(folderPath: String, query: String) async throws -> [FileItem]
    func listFavorites() async throws -> [FavoriteLocation]
    func addFavorite(path: String, name: String) async throws
    func removeFavorite(path: String) async throws
    func listShareLinks() async throws -> [FileShareLink]
    func createShareLink(paths: [String], password: String?, expiresAt: String?) async throws -> FileShareLink
    func deleteShareLinks(ids: [String]) async throws
}

public extension FileRepository {
    func readPrefix(remotePath: String, maximumLength: Int) async throws -> Data {
        throw AppError(
            category: .apiUnavailable,
            isRetryable: false,
            safeUserMessage: "暂时无法识别这个文件的内容。"
        )
    }

    func rename(path: String, newName: String) async throws {
        throw AppError(
            category: .apiUnavailable,
            isRetryable: false,
            safeUserMessage: "当前连接暂不支持重命名，请更新 DSM 后重试。"
        )
    }

    func compress(
        paths: [String],
        destinationFilePath: String,
        format: ArchiveFormat,
        level: ArchiveCompressionLevel,
        password: String?,
        progress: @escaping FileTransferProgress
    ) async throws {
        throw AppError(
            category: .apiUnavailable,
            isRetryable: false,
            safeUserMessage: "当前连接暂不支持压缩，请更新 DSM 后重试。"
        )
    }

    func extract(
        filePath: String,
        destinationFolder: String,
        overwrite: Bool,
        keepDirectoryStructure: Bool,
        createSubfolder: Bool,
        codepage: String?,
        password: String?,
        progress: @escaping FileTransferProgress
    ) async throws {
        throw AppError(
            category: .apiUnavailable,
            isRetryable: false,
            safeUserMessage: "当前连接暂不支持解压缩，请更新 DSM 后重试。"
        )
    }

    func listArchiveItems(filePath: String, codepage: String?, password: String?) async throws -> [ArchiveItem] {
        throw AppError(
            category: .apiUnavailable,
            isRetryable: false,
            safeUserMessage: "当前连接暂不支持读取压缩包内容，请更新 DSM 后重试。"
        )
    }
}

public struct ArchiveItem: Sendable, Equatable {
    public let id: Int
    public let name: String
    public let path: String
    public let isDirectory: Bool

    public init(id: Int, name: String, path: String, isDirectory: Bool) {
        self.id = id
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
    }
}

public enum ArchiveFormat: String, Codable, CaseIterable, Sendable {
    case zip
    case sevenZip = "7z"
}

public enum ArchiveCompressionLevel: String, Codable, CaseIterable, Sendable {
    case moderate
    case store
    case fastest
    case best
}
