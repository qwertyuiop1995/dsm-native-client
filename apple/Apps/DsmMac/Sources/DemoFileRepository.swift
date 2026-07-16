import CoreGraphics
import DsmCore
import Foundation

actor DemoFileRepository: FileRepository {
    nonisolated let profileID: UUID
    nonisolated let isDemo = true
    nonisolated let allowsVerifiedRestore = true

    private var folders: [String: [FileItem]]

    init(profileID: UUID) {
        self.profileID = profileID
        folders = Self.makeFolders(profileID: profileID)
    }

    func listShares(offset: Int, limit: Int) async throws -> FilePage {
        let shares = [
            item(name: "home", path: "/home", kind: .directory),
            item(name: "photo", path: "/photo", kind: .directory),
            item(name: "projects", path: "/projects", kind: .directory)
        ]
        return FilePage(
            folderPath: "/",
            items: Array(shares.dropFirst(offset).prefix(limit)),
            offset: offset,
            total: shares.count,
            hasMore: offset + limit < shares.count
        )
    }

    func listFolder(path: String, offset: Int, limit: Int) async throws -> FilePage {
        guard let content = folders[path] else {
            throw AppError(
                category: .notFound,
                isRetryable: false,
                safeUserMessage: "演示目录不存在。"
            )
        }
        let page = Array(content.dropFirst(offset).prefix(limit))
        return FilePage(
            folderPath: path,
            items: page,
            offset: offset,
            total: content.count,
            hasMore: offset + page.count < content.count
        )
    }

    func getInfo(paths: [String]) async throws -> [FileItem] {
        let wanted = Set(paths)
        return folders.values.flatMap { $0 }.filter { wanted.contains($0.path) }
    }

    func getThumbnail(path: String, size: ThumbnailSize) async throws -> Data {
        guard let data = Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ) else {
            throw AppError(
                category: .invalidResponse,
                isRetryable: false,
                safeUserMessage: "演示缩略图不可用。"
            )
        }
        return data
    }

    func checkWritePermission(folderPath: String, filename: String, createOnly: Bool) async throws {
        guard folders[folderPath] != nil else {
            throw AppError(
                category: .notFound,
                isRetryable: false,
                safeUserMessage: "目标目录不存在。"
            )
        }
        if createOnly, folders[folderPath]?.contains(where: { $0.name == filename }) == true {
            throw AppError(
                category: .conflict,
                isRetryable: false,
                safeUserMessage: "目标目录已有同名文件。"
            )
        }
    }

    func mediaStreamSource(
        remotePath: String,
        fileExtension: String?,
        expectedContentLength: Int64?
    ) async throws -> MediaStreamSource {
        guard let url = URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4") else {
            throw AppError(
                category: .invalidResponse,
                isRetryable: false,
                safeUserMessage: "示例视频地址不可用。"
            )
        }
        return MediaStreamSource(
            request: URLRequest(url: url),
            fileExtension: fileExtension,
            expectedContentLength: expectedContentLength,
            expectedHost: url.host ?? "commondatastorage.googleapis.com",
            pinnedCertificateSHA256: nil
        )
    }

    func download(
        remotePath: String,
        to localURL: URL,
        progress: @escaping FileTransferProgress
    ) async throws {
        guard let file = folders.values.flatMap({ $0 }).first(where: { $0.path == remotePath }) else {
            throw AppError(
                category: .notFound,
                isRetryable: false,
                safeUserMessage: "演示文件不存在。"
            )
        }
        let data: Data
        switch PreviewKind.classify(file) {
        case .pdf:
            data = Self.makePDF()
        case .text:
            data = Data(Self.demoText(for: file).utf8)
        case .image:
            data = try await getThumbnail(path: remotePath, size: .large)
        case .video:
            data = Data()
        case .audio:
            data = Data()
        case .unsupported:
            data = Data("LanStash demo file\n".utf8)
        }
        progress(0, Int64(data.count))
        try await Task.sleep(for: .milliseconds(350))
        try data.write(to: localURL, options: .atomic)
        progress(Int64(data.count), Int64(data.count))
    }

    func upload(
        localURL: URL,
        to folderPath: String,
        overwrite: Bool,
        progress: @escaping FileTransferProgress
    ) async throws {
        try await checkWritePermission(
            folderPath: folderPath,
            filename: localURL.lastPathComponent,
            createOnly: !overwrite
        )
        let size = Int64((try? localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        progress(0, size)
        try await Task.sleep(for: .milliseconds(500))
        if overwrite {
            folders[folderPath]?.removeAll { $0.name == localURL.lastPathComponent }
        }
        folders[folderPath, default: []].append(
            item(
                name: localURL.lastPathComponent,
                path: "\(folderPath)/\(localURL.lastPathComponent)",
                kind: .file,
                size: size
            )
        )
        progress(size, size)
    }

    func delete(paths: [String], progress: @escaping FileTransferProgress) async throws {
        let total = Int64(paths.count)
        progress(0, total)
        for (index, path) in paths.enumerated() {
            try Task.checkCancellation()
            guard let parent = parentContaining(path: path),
                  let itemIndex = folders[parent]?.firstIndex(where: { $0.path == path }),
                  let removed = folders[parent]?.remove(at: itemIndex) else {
                continue
            }
            if !removed.isRecyclePath,
               let share = path.split(separator: "/").first.map(String.init) {
                let recycleRoot = "/\(share)/#recycle"
                let recycled = item(
                    name: removed.name,
                    path: "\(recycleRoot)/\(removed.name)",
                    kind: removed.kind,
                    size: removed.sizeBytes ?? 0,
                    modifiedAt: removed.times?.modifiedAt
                )
                folders[recycleRoot, default: []].append(recycled)
            }
            try await Task.sleep(for: .milliseconds(220))
            progress(Int64(index + 1), total)
        }
    }

    func move(
        paths: [String],
        to destinationFolder: String,
        overwrite: Bool,
        progress: @escaping FileTransferProgress
    ) async throws {
        guard folders[destinationFolder] != nil else {
            throw AppError(
                category: .notFound,
                isRetryable: false,
                safeUserMessage: "恢复目标目录不存在。"
            )
        }
        let total = Int64(paths.count)
        progress(0, total)
        for (index, path) in paths.enumerated() {
            guard let parent = parentContaining(path: path),
                  let itemIndex = folders[parent]?.firstIndex(where: { $0.path == path }),
                  let source = folders[parent]?[itemIndex] else {
                continue
            }
            if folders[destinationFolder]?.contains(where: { $0.name == source.name }) == true {
                guard overwrite else {
                    throw AppError(
                        category: .conflict,
                        isRetryable: false,
                        safeUserMessage: "目标目录已有同名项目。"
                    )
                }
                folders[destinationFolder]?.removeAll { $0.name == source.name }
            }
            folders[parent]?.remove(at: itemIndex)
            folders[destinationFolder, default: []].append(
                item(
                    name: source.name,
                    path: "\(destinationFolder)/\(source.name)",
                    kind: source.kind,
                    size: source.sizeBytes ?? 0,
                    modifiedAt: source.times?.modifiedAt
                )
            )
            try await Task.sleep(for: .milliseconds(300))
            progress(Int64(index + 1), total)
        }
    }

    private func parentContaining(path: String) -> String? {
        folders.first(where: { _, items in items.contains(where: { $0.path == path }) })?.key
    }

    private func item(
        name: String,
        path: String,
        kind: FileKind,
        size: Int64 = 0,
        modifiedAt: Date? = Date()
    ) -> FileItem {
        FileItem(
            profileID: profileID,
            name: name,
            path: path,
            kind: kind,
            sizeBytes: kind == .directory ? nil : size,
            owner: "demo",
            group: "users",
            times: FileTimes(modifiedAt: modifiedAt, createdAt: modifiedAt, accessedAt: modifiedAt),
            permissions: FilePermissions(canRead: true, canWrite: true, canDelete: true, posixMode: 0o755),
            thumbnailAvailable: PreviewKind.classify(
                FileItem(profileID: profileID, name: name, path: path, kind: kind)
            ) == .image
        )
    }

    private static func makeFolders(profileID: UUID) -> [String: [FileItem]] {
        func make(
            _ name: String,
            _ path: String,
            _ kind: FileKind,
            _ size: Int64 = 0,
            daysAgo: Double = 0
        ) -> FileItem {
            let date = Date().addingTimeInterval(-daysAgo * 86_400)
            return FileItem(
                profileID: profileID,
                name: name,
                path: path,
                kind: kind,
                sizeBytes: kind == .directory ? nil : size,
                owner: "demo",
                group: "users",
                times: FileTimes(modifiedAt: date, createdAt: date, accessedAt: date),
                permissions: FilePermissions(canRead: true, canWrite: true, canDelete: true, posixMode: 0o755),
                thumbnailAvailable: ["jpg", "jpeg", "png", "heic"].contains(URL(fileURLWithPath: name).pathExtension.lowercased())
            )
        }

        return [
            "/home": [
                make("Documents", "/home/Documents", .directory),
                make("Downloads", "/home/Downloads", .directory),
                make("欢迎使用岚仓.txt", "/home/欢迎使用岚仓.txt", .file, 2_048)
            ],
            "/home/Documents": [
                make("家庭预算.csv", "/home/Documents/家庭预算.csv", .file, 48_120, daysAgo: 2),
                make("NAS 使用说明.md", "/home/Documents/NAS 使用说明.md", .file, 12_880, daysAgo: 1)
            ],
            "/home/Downloads": [],
            "/home/#recycle": [
                make("旧笔记.txt", "/home/#recycle/旧笔记.txt", .file, 1_024, daysAgo: 14)
            ],
            "/photo": [
                make("家庭相册", "/photo/家庭相册", .directory),
                make("夏日旅行.jpg", "/photo/夏日旅行.jpg", .file, 4_820_000, daysAgo: 4),
                make("山间日落.heic", "/photo/山间日落.heic", .file, 6_240_000, daysAgo: 7)
            ],
            "/photo/家庭相册": [
                make("周末野餐.png", "/photo/家庭相册/周末野餐.png", .file, 3_120_000, daysAgo: 10)
            ],
            "/photo/#recycle": [
                make("模糊照片.jpg", "/photo/#recycle/模糊照片.jpg", .file, 2_400_000, daysAgo: 21)
            ],
            "/projects": [
                make("LanStash", "/projects/LanStash", .directory),
                make("产品路线图.pdf", "/projects/产品路线图.pdf", .file, 1_240_000, daysAgo: 1),
                make("README.md", "/projects/README.md", .file, 8_420),
                make("release-notes.txt", "/projects/release-notes.txt", .file, 4_096, daysAgo: 3)
            ],
            "/projects/LanStash": [
                make("AppModel.swift", "/projects/LanStash/AppModel.swift", .file, 24_800),
                make("Architecture.md", "/projects/LanStash/Architecture.md", .file, 16_200, daysAgo: 2)
            ],
            "/projects/#recycle": [
                make("旧方案.pdf", "/projects/#recycle/旧方案.pdf", .file, 820_000, daysAgo: 30)
            ]
        ]
    }

    private static func demoText(for file: FileItem) -> String {
        """
        # \(file.name)

        这是岚仓的本地演示内容。

        - 使用原生 SwiftUI 三栏布局
        - 支持共享目录与回收站浏览
        - 支持图片、文本和 PDF 预览
        - 支持上传、下载、删除与传输中心
        - 危险操作始终要求确认

        连接你自己的 NAS 后，这里会显示设备中的文件内容。
        """
    }

    private static func makePDF() -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else {
            return Data()
        }
        var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 0.97, green: 0.98, blue: 1, alpha: 1))
        context.fill(mediaBox)
        context.setFillColor(CGColor(red: 0.15, green: 0.39, blue: 0.92, alpha: 1))
        context.fill(CGRect(x: 48, y: 730, width: 499, height: 64))
        context.setFillColor(CGColor(gray: 0.82, alpha: 1))
        for row in 0..<8 {
            context.fill(CGRect(x: 64, y: 650 - CGFloat(row * 58), width: 450 - CGFloat((row % 3) * 60), height: 8))
        }
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}
