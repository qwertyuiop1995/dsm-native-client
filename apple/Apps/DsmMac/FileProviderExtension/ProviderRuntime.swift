import DsmCore
import DsmNetwork
import FileProvider
import Foundation

struct ProviderRequestedVersion: Equatable, Sendable {
    let content: Data
    let metadata: Data
}

actor ProviderRuntime {
    private let mappingID: UUID?
    private let configurationStore = DesktopDriveConfigurationStore()
    private let sessionStore = SharedKeychainSessionStore()
    private let metadata = DesktopDriveMetadataCoordinator()

    init(mappingIdentifier: String) {
        mappingID = UUID(uuidString: mappingIdentifier)
    }

    func invalidate() async {
        await metadata.invalidate(cancelInFlight: true)
    }

    func item(
        for identifier: NSFileProviderItemIdentifier
    ) async throws -> ProviderItem {
        let context = try await makeContext()
        let runtime = try await configurationStore.runtime(
            mappingID: context.configuration.mapping.id
        )
        if identifier == .rootContainer {
            let rootPath = Self.rootPath(
                for: context.configuration.mapping
            )
            return ProviderItem.root(
                configuration: context.configuration,
                keptOffline: runtime.keepsOffline(rootPath)
            )
        }
        let path = try await remotePath(for: identifier)
        guard let item = try await metadata.item(path: path, loader: {
            try await context.repository.getInfo(paths: [path]).first
        }) else {
            throw NSFileProviderError(.noSuchItem)
        }
        return ProviderItem(
            fileItem: item,
            mapping: context.configuration.mapping,
            keptOffline: runtime.keepsOffline(path)
        )
    }

    func enumerate(
        containerIdentifier: NSFileProviderItemIdentifier,
        offset: Int,
        limit: Int
    ) async throws -> (items: [ProviderItem], nextOffset: Int?) {
        let context = try await makeContext()
        let runtime = try await configurationStore.runtime(
            mappingID: context.configuration.mapping.id
        )
        let folderPath = containerIdentifier == .rootContainer
            ? nil
            : try await remotePath(for: containerIdentifier)
        let pageKey = DesktopDriveMetadataCoordinator.PageKey(
            containerIdentifier: containerIdentifier.rawValue,
            offset: offset,
            limit: limit
        )
        let page = try await metadata.page(key: pageKey) {
            if let folderPath {
                return try await context.repository.listFolder(
                    path: folderPath,
                    offset: offset,
                    limit: limit
                )
            }
            switch context.configuration.mapping.scope {
            case .allShares:
                return try await context.repository.listShares(
                    offset: offset,
                    limit: limit
                )
            case .folder(let path):
                return try await context.repository.listFolder(
                    path: path,
                    offset: offset,
                    limit: limit
                )
            }
        }
        try await configurationStore.registerItemPaths(
            mappingID: context.configuration.mapping.id,
            remotePaths: page.items.map(\.path)
        )
        let items = page.items.map {
            ProviderItem(
                fileItem: $0,
                mapping: context.configuration.mapping,
                keptOffline: runtime.keepsOffline($0.path)
            )
        }
        return (
            items,
            page.hasMore ? page.offset + page.items.count : nil
        )
    }

    func fetchContents(
        for identifier: NSFileProviderItemIdentifier,
        requestedVersion: ProviderRequestedVersion?,
        progress: @escaping FileTransferProgress
    ) async throws -> (URL, ProviderItem) {
        let context = try await makeContext()
        let path = try await remotePath(for: identifier)
        guard let remoteItem = try await metadata.item(path: path, ttl: 0, loader: {
            try await context.repository.getInfo(paths: [path]).first
        }),
              !remoteItem.isDirectory else {
            throw NSFileProviderError(.noSuchItem)
        }
        let providerItem = ProviderItem(
            fileItem: remoteItem,
            mapping: context.configuration.mapping,
            keptOffline: false
        )
        let currentVersion = ProviderRequestedVersion(
            content: providerItem.itemVersion.contentVersion,
            metadata: providerItem.itemVersion.metadataVersion
        )
        if let requestedVersion, requestedVersion != currentVersion {
            throw NSFileProviderError(.versionNoLongerAvailable)
        }
        guard let fileName = DesktopDriveStagingIdentity.contentFileName(
            mappingID: context.configuration.mapping.id,
            remotePath: path,
            sizeBytes: remoteItem.sizeBytes,
            modifiedAt: remoteItem.times?.modifiedAt
        ) else {
            throw NSFileProviderError(.noSuchItem)
        }
        let domain = Self.domain(for: context.configuration.mapping)
        guard let manager = NSFileProviderManager(for: domain) else {
            throw NSFileProviderError(.providerNotFound)
        }
        let stagingDirectory = try manager.temporaryDirectoryURL()
            .appendingPathComponent("LanStashStaging", isDirectory: true)
        try FileManager.default.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true
        )
        let temporaryURL = stagingDirectory
            .appendingPathComponent(fileName, isDirectory: false)
        progress(0, remoteItem.sizeBytes)
        do {
            if try isCompleteFile(
                at: temporaryURL,
                expectedSize: remoteItem.sizeBytes
            ) {
                let result = try await recordMaterializedFile(
                    at: temporaryURL,
                    remoteItem: remoteItem,
                    remotePath: path,
                    configuration: context.configuration
                )
                progress(result.sizeBytes, remoteItem.sizeBytes)
                return (temporaryURL, result.item)
            }
            try ensureCacheSpace(
                expectedSize: remoteItem.sizeBytes,
                at: temporaryURL.deletingLastPathComponent()
            )
            try await context.repository.download(
                remotePath: path,
                to: temporaryURL,
                expectedSize: remoteItem.sizeBytes,
                progress: progress
            )
            let result = try await recordMaterializedFile(
                at: temporaryURL,
                remoteItem: remoteItem,
                remotePath: path,
                configuration: context.configuration
            )
            scheduleTemporaryCacheMaintenance(
                mapping: context.configuration.mapping
            )
            return (temporaryURL, result.item)
        } catch {
            if !(error is CancellationError),
               (error as? AppError)?.category != .cancelled {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
            throw error
        }
    }

    private func isCompleteFile(
        at url: URL,
        expectedSize: Int64?
    ) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }
        guard let expectedSize else {
            return false
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? -1) == expectedSize
    }

    private func recordMaterializedFile(
        at url: URL,
        remoteItem: FileItem,
        remotePath: String,
        configuration: DesktopDriveProviderConfiguration
    ) async throws -> (item: ProviderItem, sizeBytes: Int64) {
        let values = try url.resourceValues(
            forKeys: [.fileSizeKey, .fileAllocatedSizeKey]
        )
        let actualSize = Int64(values.fileSize ?? 0)
        if let expectedSize = remoteItem.sizeBytes,
           actualSize != expectedSize {
            throw CocoaError(.fileReadCorruptFile)
        }
        let runtime = try await configurationStore.runtime(
            mappingID: configuration.mapping.id
        )
        let entry = DesktopDriveCacheEntry(
            remotePath: remotePath,
            kind: runtime.keepsOffline(remotePath) ? .keptOffline : .temporary,
            logicalSizeBytes: actualSize,
            allocatedSizeBytes: Int64(
                values.fileAllocatedSize ?? values.fileSize ?? 0
            )
        )
        try await configurationStore.recordCacheEntry(
            entry,
            mappingID: configuration.mapping.id
        )
        return (
            ProviderItem(
                fileItem: remoteItem,
                mapping: configuration.mapping,
                keptOffline: runtime.keepsOffline(remotePath)
            ),
            actualSize
        )
    }

    private func scheduleTemporaryCacheMaintenance(
        mapping: DesktopDriveMapping
    ) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            await self?.enforceTemporaryCacheLimit(mapping: mapping)
        }
    }

    private func enforceTemporaryCacheLimit(
        mapping: DesktopDriveMapping
    ) async {
        guard let runtime = try? await configurationStore.runtime(
            mappingID: mapping.id
        ) else {
            return
        }
        let paths = DesktopDriveCacheEvictionPlanner.temporaryPathsToEvict(
            entries: Array(runtime.cacheEntries.values),
            limitBytes: mapping.cachePolicy.temporaryLimitBytes
        )
        guard !paths.isEmpty else { return }
        let domain = Self.domain(for: mapping)
        guard let manager = NSFileProviderManager(for: domain) else { return }
        var released: [String] = []
        for path in paths {
            guard let identifier = DesktopDriveItemIdentity.identifier(
                mappingID: mapping.id,
                remotePath: path
            ) else {
                continue
            }
            do {
                try await evict(
                    identifier: NSFileProviderItemIdentifier(identifier),
                    manager: manager
                )
                released.append(path)
            } catch {
                // 文件可能仍被前台程序占用，保留记录供下一轮维护重试。
            }
        }
        try? await configurationStore.removeCacheEntries(
            remotePaths: released,
            mappingID: mapping.id
        )
    }

    private func evict(
        identifier: NSFileProviderItemIdentifier,
        manager: NSFileProviderManager
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            manager.evictItem(identifier: identifier) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func ensureCacheSpace(
        expectedSize: Int64?,
        at directory: URL
    ) throws {
        let values = try directory.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ])
        guard let totalCapacity = values.volumeTotalCapacity,
              let availableCapacity = values.volumeAvailableCapacityForImportantUsage else {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        let decision = DesktopDriveCacheSpaceCalculator.evaluate(
            candidates: [.init(sizeBytes: expectedSize)],
            volumeCapacityBytes: Int64(totalCapacity),
            availableCapacityBytes: availableCapacity
        )
        guard case .allowed = decision else {
            throw CocoaError(.fileWriteOutOfSpace)
        }
    }

    private func makeContext() async throws -> (
        configuration: DesktopDriveProviderConfiguration,
        repository: DsmFileRepository
    ) {
        guard let mappingID,
              let configuration = try await configurationStore.configuration(
            mappingID: mappingID
        ) else {
            throw NSFileProviderError(.noSuchItem)
        }
        guard try await configurationStore.isProviderAvailable() else {
            throw NSFileProviderError(.serverUnreachable)
        }
        let runtime = try await configurationStore.runtime(mappingID: mappingID)
        guard !runtime.isManuallyPaused else {
            throw NSFileProviderError(.serverUnreachable)
        }
        guard let session: AuthSession = try await sessionStore.load(
            for: configuration.mapping.profileID
        ) else {
            throw NSFileProviderError(.notAuthenticated)
        }
        let repository = try DsmFileRepository(
            profile: configuration.connection.profile,
            capabilities: configuration.connection.capabilitySet,
            session: session
        )
        return (configuration, repository)
    }

    private func remotePath(
        for identifier: NSFileProviderItemIdentifier
    ) async throws -> String {
        guard let mappingID else {
            throw NSFileProviderError(.noSuchItem)
        }
        if let path = try await configurationStore.remotePath(
            mappingID: mappingID,
            itemIdentifier: identifier.rawValue
        ) {
            return path
        }
        // 仅用于迁移开发阶段已经物化的旧标识；新标识始终是不透明摘要。
        let legacyPrefix = "path:"
        guard identifier.rawValue.hasPrefix(legacyPrefix),
              let path = DesktopDrivePath.normalized(
                String(identifier.rawValue.dropFirst(legacyPrefix.count))
              ) else {
            throw NSFileProviderError(.noSuchItem)
        }
        try await configurationStore.registerItemPaths(
            mappingID: mappingID,
            remotePaths: [path]
        )
        return path
    }

    private static func rootPath(
        for mapping: DesktopDriveMapping
    ) -> String {
        switch mapping.scope {
        case .allShares:
            return "/"
        case .folder(let path):
            return DesktopDrivePath.normalized(path) ?? "/"
        }
    }

    private static func domain(
        for mapping: DesktopDriveMapping
    ) -> NSFileProviderDomain {
        NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(
                mapping.providerDomainIdentifier ?? mapping.id.uuidString
            ),
            displayName: mapping.displayName
        )
    }
}
