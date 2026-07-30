import Foundation

public struct DesktopDrivePlannedFile: Equatable, Sendable {
    public let remotePath: String
    public let sizeBytes: Int64
    public let modifiedAt: Date?

    public init(
        remotePath: String,
        sizeBytes: Int64,
        modifiedAt: Date?
    ) {
        self.remotePath = remotePath
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
    }
}

public enum DesktopDrivePlanIssueKind: String, Codable, Hashable, Sendable {
    case inaccessibleFolder
    case unknownFileSize
    case invalidPath
    case itemLimitReached
    case sizeOverflow
    case cancelled
}

public struct DesktopDrivePlanIssue: Equatable, Sendable {
    public let kind: DesktopDrivePlanIssueKind
    public let remotePath: String?

    public init(kind: DesktopDrivePlanIssueKind, remotePath: String? = nil) {
        self.kind = kind
        self.remotePath = remotePath
    }
}

public struct DesktopDriveCachePlan: Equatable, Sendable {
    public let files: [DesktopDrivePlannedFile]
    public let issues: [DesktopDrivePlanIssue]
    public let totalBytes: Int64
    public let largestFileBytes: Int64
    public let folderCount: Int

    public init(
        files: [DesktopDrivePlannedFile],
        issues: [DesktopDrivePlanIssue],
        totalBytes: Int64,
        largestFileBytes: Int64,
        folderCount: Int
    ) {
        self.files = files
        self.issues = issues
        self.totalBytes = totalBytes
        self.largestFileBytes = largestFileBytes
        self.folderCount = folderCount
    }

    public var isComplete: Bool { issues.isEmpty }
}

public struct DesktopDrivePlanningProgress: Equatable, Sendable {
    public let folderCount: Int
    public let fileCount: Int
    public let discoveredBytes: Int64

    public init(
        folderCount: Int,
        fileCount: Int,
        discoveredBytes: Int64
    ) {
        self.folderCount = folderCount
        self.fileCount = fileCount
        self.discoveredBytes = discoveredBytes
    }
}

public enum DesktopDriveTreePlanner {
    public typealias PageLoader = @Sendable (
        _ folderPath: String,
        _ offset: Int,
        _ limit: Int
    ) async throws -> FilePage

    public static func build(
        rootFolders: [String],
        rootFiles: [DesktopDrivePlannedFile] = [],
        itemLimit: Int = 1_000_000,
        pageSize: Int = 500,
        loadPage: @escaping PageLoader,
        progress: @escaping @Sendable (DesktopDrivePlanningProgress) -> Void = { _ in }
    ) async -> DesktopDriveCachePlan {
        guard itemLimit > 0, pageSize > 0 else {
            return DesktopDriveCachePlan(
                files: [],
                issues: [.init(kind: .itemLimitReached)],
                totalBytes: 0,
                largestFileBytes: 0,
                folderCount: 0
            )
        }

        var queue = rootFolders
        var nextFolderIndex = 0
        var visited = Set<String>()
        var visitedFiles = Set<String>()
        var files: [DesktopDrivePlannedFile] = []
        var issues: [DesktopDrivePlanIssue] = []
        var totalBytes: Int64 = 0
        var largestFileBytes: Int64 = 0

        for file in rootFiles {
            guard files.count < itemLimit else {
                issues.append(.init(kind: .itemLimitReached))
                break
            }
            guard let path = DesktopDrivePath.normalized(file.remotePath) else {
                issues.append(.init(kind: .invalidPath, remotePath: file.remotePath))
                continue
            }
            guard file.sizeBytes >= 0 else {
                issues.append(.init(kind: .unknownFileSize, remotePath: path))
                continue
            }
            guard visitedFiles.insert(path).inserted else { continue }
            let sum = totalBytes.addingReportingOverflow(file.sizeBytes)
            guard !sum.overflow else {
                issues.append(.init(kind: .sizeOverflow))
                totalBytes = .max
                largestFileBytes = max(largestFileBytes, file.sizeBytes)
                break
            }
            totalBytes = sum.partialValue
            largestFileBytes = max(largestFileBytes, file.sizeBytes)
            files.append(
                DesktopDrivePlannedFile(
                    remotePath: path,
                    sizeBytes: file.sizeBytes,
                    modifiedAt: file.modifiedAt
                )
            )
        }
        progress(
            DesktopDrivePlanningProgress(
                folderCount: 0,
                fileCount: files.count,
                discoveredBytes: totalBytes
            )
        )

        while nextFolderIndex < queue.count {
            do {
                try Task.checkCancellation()
            } catch {
                issues.append(.init(kind: .cancelled))
                break
            }
            let rawFolder = queue[nextFolderIndex]
            nextFolderIndex += 1
            guard let folder = DesktopDrivePath.normalized(rawFolder) else {
                issues.append(.init(kind: .invalidPath, remotePath: rawFolder))
                continue
            }
            guard visited.insert(folder).inserted else { continue }
            var offset = 0
            var folderFailed = false

            repeat {
                do {
                    try Task.checkCancellation()
                    let page = try await loadPage(folder, offset, pageSize)
                    for item in page.items {
                        if visited.count + files.count >= itemLimit {
                            issues.append(.init(kind: .itemLimitReached))
                            return result(
                                files: files,
                                issues: issues,
                                totalBytes: totalBytes,
                                largestFileBytes: largestFileBytes,
                                folderCount: visited.count
                            )
                        }
                        if item.isDirectory {
                            queue.append(item.path)
                            continue
                        }
                        guard let normalizedPath = DesktopDrivePath.normalized(item.path) else {
                            issues.append(
                                .init(kind: .invalidPath, remotePath: item.path)
                            )
                            continue
                        }
                        guard visitedFiles.insert(normalizedPath).inserted else {
                            continue
                        }
                        guard let size = item.sizeBytes, size >= 0 else {
                            issues.append(
                                .init(kind: .unknownFileSize, remotePath: normalizedPath)
                            )
                            continue
                        }
                        let sum = totalBytes.addingReportingOverflow(size)
                        guard !sum.overflow else {
                            issues.append(.init(kind: .sizeOverflow))
                            return result(
                                files: files,
                                issues: issues,
                                totalBytes: .max,
                                largestFileBytes: max(largestFileBytes, size),
                                folderCount: visited.count
                            )
                        }
                        totalBytes = sum.partialValue
                        largestFileBytes = max(largestFileBytes, size)
                        files.append(
                            DesktopDrivePlannedFile(
                                remotePath: normalizedPath,
                                sizeBytes: size,
                                modifiedAt: item.times?.modifiedAt
                            )
                        )
                    }
                    progress(
                        DesktopDrivePlanningProgress(
                            folderCount: visited.count,
                            fileCount: files.count,
                            discoveredBytes: totalBytes
                        )
                    )
                    let nextOffset = page.offset + page.items.count
                    if !page.hasMore || nextOffset <= offset || page.items.isEmpty {
                        break
                    }
                    offset = nextOffset
                } catch is CancellationError {
                    issues.append(.init(kind: .cancelled))
                    return result(
                        files: files,
                        issues: issues,
                        totalBytes: totalBytes,
                        largestFileBytes: largestFileBytes,
                        folderCount: visited.count
                    )
                } catch {
                    issues.append(
                        .init(kind: .inaccessibleFolder, remotePath: folder)
                    )
                    folderFailed = true
                }
            } while !folderFailed
        }

        return result(
            files: files,
            issues: issues,
            totalBytes: totalBytes,
            largestFileBytes: largestFileBytes,
            folderCount: visited.count
        )
    }

    private static func result(
        files: [DesktopDrivePlannedFile],
        issues: [DesktopDrivePlanIssue],
        totalBytes: Int64,
        largestFileBytes: Int64,
        folderCount: Int
    ) -> DesktopDriveCachePlan {
        DesktopDriveCachePlan(
            files: files,
            issues: issues,
            totalBytes: totalBytes,
            largestFileBytes: largestFileBytes,
            folderCount: folderCount
        )
    }
}
