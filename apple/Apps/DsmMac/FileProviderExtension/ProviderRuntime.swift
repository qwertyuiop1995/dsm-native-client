import DsmCore
import DsmNetwork
import FileProvider
import Foundation

actor ProviderRuntime {
    private let mappingID: UUID?
    private let configurationStore = DesktopDriveConfigurationStore()
    private let sessionStore = SharedKeychainSessionStore()

    init(mappingIdentifier: String) {
        mappingID = UUID(uuidString: mappingIdentifier)
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
        guard let item = try await context.repository.getInfo(paths: [path]).first else {
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
        let page: FilePage
        if containerIdentifier == .rootContainer {
            switch context.configuration.mapping.scope {
            case .allShares:
                page = try await context.repository.listShares(
                    offset: offset,
                    limit: limit
                )
            case .folder(let path):
                page = try await context.repository.listFolder(
                    path: path,
                    offset: offset,
                    limit: limit
                )
            }
        } else {
            page = try await context.repository.listFolder(
                path: try await remotePath(for: containerIdentifier),
                offset: offset,
                limit: limit
            )
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
        for identifier: NSFileProviderItemIdentifier
    ) async throws -> (URL, ProviderItem) {
        let context = try await makeContext()
        let path = try await remotePath(for: identifier)
        guard let remoteItem = try await context.repository.getInfo(paths: [path]).first,
              !remoteItem.isDirectory else {
            throw NSFileProviderError(.noSuchItem)
        }
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        do {
            try ensureCacheSpace(
                expectedSize: remoteItem.sizeBytes,
                at: temporaryURL.deletingLastPathComponent()
            )
            try await context.repository.download(
                remotePath: path,
                to: temporaryURL,
                expectedSize: remoteItem.sizeBytes,
                progress: { _, _ in }
            )
            let values = try temporaryURL.resourceValues(
                forKeys: [.fileSizeKey, .fileAllocatedSizeKey]
            )
            let actualSize = Int64(values.fileSize ?? 0)
            if let expectedSize = remoteItem.sizeBytes,
               actualSize != expectedSize {
                throw CocoaError(.fileReadCorruptFile)
            }
            let runtime = try await configurationStore.runtime(
                mappingID: context.configuration.mapping.id
            )
            let entry = DesktopDriveCacheEntry(
                remotePath: path,
                kind: runtime.keepsOffline(path) ? .keptOffline : .temporary,
                logicalSizeBytes: actualSize,
                allocatedSizeBytes: Int64(values.fileAllocatedSize ?? values.fileSize ?? 0)
            )
            try await configurationStore.recordCacheEntry(
                entry,
                mappingID: context.configuration.mapping.id
            )
            scheduleTemporaryCacheMaintenance(
                mapping: context.configuration.mapping
            )
            return (
                temporaryURL,
                ProviderItem(
                    fileItem: remoteItem,
                    mapping: context.configuration.mapping,
                    keptOffline: runtime.keepsOffline(path)
                )
            )
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
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
        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(
                mapping.providerDomainIdentifier ?? mapping.id.uuidString
            ),
            displayName: mapping.displayName
        )
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
}
