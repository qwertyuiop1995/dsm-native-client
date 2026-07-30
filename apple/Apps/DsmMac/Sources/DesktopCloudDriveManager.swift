import AppKit
import DsmCore
import DsmLocalization
import FileProvider
import Foundation
import Observation

enum DesktopCloudDriveAvailability {
    static var isAvailable: Bool {
        guard let plugInsURL = Bundle.main.builtInPlugInsURL else {
            return false
        }
        let extensionURL = plugInsURL.appendingPathComponent(
            "LanStashFileProvider.appex",
            isDirectory: true
        )
        return evaluate(
            hasFileProviderExtension:
                FileManager.default.fileExists(atPath: extensionURL.path),
            sharedContainerURL: FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier:
                    DesktopDriveSharedContainer.appGroupIdentifier
            )
        )
    }

    static func evaluate(
        hasFileProviderExtension: Bool,
        sharedContainerURL: URL?
    ) -> Bool {
        hasFileProviderExtension && sharedContainerURL != nil
    }
}

actor DesktopDriveSessionBridge {
    private let profileID: UUID
    private let session: AuthSession
    private let store: any SessionSecureStoring

    init(
        profileID: UUID,
        session: AuthSession,
        store: any SessionSecureStoring
    ) {
        self.profileID = profileID
        self.session = session
        self.store = store
    }

    func publish() async throws {
        try await store.save(session, for: profileID)
    }

    func remove() async throws {
        try await store.remove(for: profileID)
    }
}

enum DesktopDriveOfflinePhase: Equatable {
    case planning
    case checkingSpace
    case requesting
    case downloading
    case completed
    case cancelled
    case failed
}

struct DesktopDriveOfflineProgress: Equatable {
    var phase: DesktopDriveOfflinePhase
    var discoveredFolders = 0
    var discoveredFiles = 0
    var discoveredBytes: Int64 = 0
    var completedFiles = 0
    var totalFiles = 0
    var completedBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var requiredBytes: Int64?
    var availableBytes: Int64?
    var shortageBytes: Int64?
    var volumeName: String?
}

struct DesktopDriveCacheSummary: Equatable {
    var temporaryBytes: Int64 = 0
    var keptOfflineBytes: Int64 = 0
    var temporaryItemCount = 0
    var keptOfflineItemCount = 0

    var totalBytes: Int64 {
        temporaryBytes + keptOfflineBytes
    }
}

@MainActor
@Observable
final class DesktopCloudDriveManager {
    private(set) var mappings: [DesktopDriveMapping] = []
    private(set) var isBusy = false
    private(set) var isAvailable: Bool
    private(set) var statusMessage: String?
    private(set) var statusIsError = false
    private(set) var cacheBytes: [UUID: Int64] = [:]
    private(set) var cacheSummaries: [UUID: DesktopDriveCacheSummary] = [:]
    private(set) var runtimes: [UUID: DesktopDriveMappingRuntime] = [:]
    private(set) var offlineProgress: [UUID: DesktopDriveOfflineProgress] = [:]

    private let profile: NasProfile
    private let repository: any FileRepository
    private let store: DesktopDriveConfigurationStore
    private let sessionBridge: DesktopDriveSessionBridge?
    @ObservationIgnored private var offlineTasks: [UUID: Task<Void, Never>] = [:]

    init(
        profile: NasProfile,
        repository: any FileRepository,
        store: DesktopDriveConfigurationStore = .init(),
        sessionBridge: DesktopDriveSessionBridge? = nil,
        isAvailable: Bool = DesktopCloudDriveAvailability.isAvailable
    ) {
        self.profile = profile
        self.repository = repository
        self.store = store
        self.sessionBridge = sessionBridge
        self.isAvailable = isAvailable
    }

    func load() async {
        guard isAvailable else {
            mappings = []
            statusMessage = nil
            statusIsError = false
            return
        }
        do {
            try await store.setProviderAvailable(true)
            mappings = try await store.mappings(profileID: profile.id)
            if mappings.isEmpty {
                try? await sessionBridge?.remove()
            } else {
                try await sessionBridge?.publish()
            }
            for mapping in mappings {
                runtimes[mapping.id] = try await store.runtime(mappingID: mapping.id)
            }
            await refreshCacheSizes()
            await restoreDomains()
            for mapping in mappings {
                await enforceTemporaryLimit(mapping)
            }
        } catch {
            mappings = []
            setError("desktopDrive.error.load")
        }
    }

    func addAllShares() async {
        await add(
            displayName: profile.displayName,
            scope: .allShares,
            cachePolicy: .init()
        )
    }

    func addFolder(path: String) async {
        guard let normalized = DesktopDrivePath.normalized(path),
              normalized != "/" else {
            setError("desktopDrive.error.folder")
            return
        }
        let folderName = normalized.split(separator: "/").last.map(String.init)
            ?? profile.displayName
        await add(
            displayName: "\(profile.displayName) — \(folderName)",
            scope: .folder(path: normalized),
            cachePolicy: .init()
        )
    }

    func addMapping(
        displayName: String,
        scope: DesktopDriveScope,
        cachePolicy: DesktopDriveCachePolicy
    ) async {
        let trimmedName = displayName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedName.isEmpty else {
            setError("desktopDrive.error.name")
            return
        }
        await add(
            displayName: trimmedName,
            scope: scope,
            cachePolicy: cachePolicy
        )
    }

    @available(macOS 15.0, *)
    func eligibleCacheLocation(
        selectedURL: URL
    ) throws -> DesktopDriveCacheLocation {
        let volumeURL = try selectedURL.resourceValues(
            forKeys: [.volumeURLForRemountingKey]
        ).volumeURLForRemounting ?? selectedURL
        guard case .eligible =
                try NSFileProviderManager.checkDomainsCanBeStoredOnVolume(
                    at: volumeURL
                ),
              let identifier = try volumeURL.resourceValues(
                forKeys: [.volumeUUIDStringKey]
              ).volumeUUIDString,
              !identifier.isEmpty else {
            throw CocoaError(.fileWriteUnsupportedScheme)
        }
        return .eligibleVolume(id: identifier)
    }

    func cacheLocationText(_ mapping: DesktopDriveMapping) -> String {
        switch mapping.cachePolicy.location {
        case .systemDefault:
            return L10n.string("desktopDrive.cache.location.system")
        case .eligibleVolume(let identifier):
            guard #available(macOS 15.0, *),
                  let volumeURL = Self.mountedVolumeURL(identifier: identifier),
                  let volumeName = try? volumeURL.resourceValues(
                    forKeys: [.volumeNameKey]
                  ).volumeName else {
                return L10n.string("desktopDrive.cache.location.unavailable")
            }
            return L10n.string(
                "desktopDrive.cache.location.external",
                volumeName
            )
        }
    }

    func remove(_ mapping: DesktopDriveMapping) async {
        guard isAvailable, !isBusy else { return }
        cancelOffline(mapping)
        isBusy = true
        defer { isBusy = false }
        do {
            try await removeDomain(domain(for: mapping))
            try await store.removeMapping(id: mapping.id)
            mappings.removeAll { $0.id == mapping.id }
            if mappings.isEmpty {
                try? await sessionBridge?.remove()
            }
            runtimes[mapping.id] = nil
            cacheSummaries[mapping.id] = nil
            cacheBytes[mapping.id] = nil
            offlineProgress[mapping.id] = nil
            setSuccess("desktopDrive.status.removed")
        } catch {
            setError("desktopDrive.error.remove")
        }
    }

    func reveal(_ mapping: DesktopDriveMapping) async {
        guard let manager = NSFileProviderManager(for: domain(for: mapping)) else {
            setError("desktopDrive.error.open")
            return
        }
        do {
            let url = try await userVisibleURL(manager: manager)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            setError("desktopDrive.error.open")
        }
    }

    func clearCache(_ mapping: DesktopDriveMapping) async {
        guard !isBusy,
              let manager = NSFileProviderManager(for: domain(for: mapping)) else {
            setError("desktopDrive.error.clearCache")
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let runtime = try await store.runtime(mappingID: mapping.id)
            let paths = runtime.cacheEntries.values
                .filter { $0.kind == .temporary }
                .map(\.remotePath)
            var released: [String] = []
            var failureCount = 0
            for path in paths {
                do {
                    try await evict(
                        identifier: itemIdentifier(path: path, mapping: mapping),
                        manager: manager
                    )
                    released.append(path)
                } catch {
                    failureCount += 1
                }
            }
            try await store.removeCacheEntries(
                remotePaths: released,
                mappingID: mapping.id
            )
            await refreshCacheSize(mapping)
            if failureCount == 0 {
                setSuccess("desktopDrive.status.cacheCleared")
            } else {
                setError("desktopDrive.error.cachePartiallyCleared")
            }
        } catch {
            setError("desktopDrive.error.clearCache")
        }
    }

    func setTemporaryCacheLimit(
        _ limitBytes: Int64,
        mapping: DesktopDriveMapping
    ) async {
        guard limitBytes >= 0 else {
            setError("desktopDrive.error.cacheLimit")
            return
        }
        let updated = mapping.replacing(
            cachePolicy: DesktopDriveCachePolicy(
                location: mapping.cachePolicy.location,
                temporaryLimitBytes: limitBytes
            )
        )
        do {
            try await store.saveMapping(updated)
            if let index = mappings.firstIndex(where: { $0.id == mapping.id }) {
                mappings[index] = updated
            }
            await enforceTemporaryLimit(updated)
            setSuccess("desktopDrive.status.cacheLimitUpdated")
        } catch {
            setError("desktopDrive.error.cacheLimit")
        }
    }

    func enforceTemporaryLimit(_ mapping: DesktopDriveMapping) async {
        guard let manager = NSFileProviderManager(for: domain(for: mapping)),
              let runtime = try? await store.runtime(mappingID: mapping.id) else {
            return
        }
        let paths = DesktopDriveCacheEvictionPlanner.temporaryPathsToEvict(
            entries: Array(runtime.cacheEntries.values),
            limitBytes: mapping.cachePolicy.temporaryLimitBytes
        )
        guard !paths.isEmpty else {
            await refreshCacheSize(mapping)
            return
        }
        var released: [String] = []
        for path in paths {
            do {
                try await evict(
                    identifier: itemIdentifier(path: path, mapping: mapping),
                    manager: manager
                )
                released.append(path)
            } catch {
                // 仍被其他 App 使用的文件暂时保留，下次维护时再次尝试。
            }
        }
        try? await store.removeCacheEntries(
            remotePaths: released,
            mappingID: mapping.id
        )
        await refreshCacheSize(mapping)
    }

    func keepMappingOffline(_ mapping: DesktopDriveMapping) {
        startKeepOffline(
            mapping: mapping,
            folderRoots: [rootPath(mapping)],
            directFiles: [],
            pinRoots: [rootPath(mapping)]
        )
    }

    func keepOffline(_ items: [FileItem]) {
        guard !items.isEmpty,
              let mapping = mapping(containing: items.map(\.path)) else {
            setError("desktopDrive.error.notMapped")
            return
        }
        let folderRoots = items
            .filter(\.isDirectory)
            .compactMap { DesktopDrivePath.normalized($0.path) }
        var directFiles: [DesktopDrivePlannedFile] = []
        for item in items where !item.isDirectory {
            guard let path = DesktopDrivePath.normalized(item.path),
                  let size = item.sizeBytes, size >= 0 else {
                setError("desktopDrive.error.unknownSize")
                return
            }
            directFiles.append(
                DesktopDrivePlannedFile(
                    remotePath: path,
                    sizeBytes: size,
                    modifiedAt: item.times?.modifiedAt
                )
            )
        }
        startKeepOffline(
            mapping: mapping,
            folderRoots: folderRoots,
            directFiles: directFiles,
            pinRoots: items.compactMap {
                DesktopDrivePath.normalized($0.path)
            }
        )
    }

    func releaseOffline(_ items: [FileItem]) async {
        guard !items.isEmpty,
              let mapping = mapping(containing: items.map(\.path)),
              let manager = NSFileProviderManager(for: domain(for: mapping)) else {
            setError("desktopDrive.error.notMapped")
            return
        }
        let targets = items.compactMap { DesktopDrivePath.normalized($0.path) }
        guard targets.count == items.count else {
            setError("desktopDrive.error.releaseOffline")
            return
        }
        do {
            let runtime = try await store.runtime(mappingID: mapping.id)
            let remainingPins = runtime.pinnedPaths.filter { pin in
                !targets.contains {
                    DesktopDrivePath.isAncestorOrSame($0, of: pin)
                }
            }
            let stillCovered = targets.contains { target in
                remainingPins.contains {
                    DesktopDrivePath.isAncestorOrSame($0, of: target)
                }
            }
            guard !stillCovered else {
                setError("desktopDrive.error.releaseCoveredByParent")
                return
            }
            let cachedPaths = runtime.cacheEntries.values
                .filter { entry in
                    entry.kind == .keptOffline
                        && targets.contains {
                            DesktopDrivePath.isAncestorOrSame(
                                $0,
                                of: entry.remotePath
                            )
                        }
                }
                .map(\.remotePath)
            try await store.setPinnedPaths(remainingPins, mappingID: mapping.id)
            try await signalRoot(manager)
            var released: [String] = []
            var failureCount = 0
            for path in cachedPaths {
                do {
                    try await evict(
                        identifier: itemIdentifier(path: path, mapping: mapping),
                        manager: manager
                    )
                    released.append(path)
                } catch {
                    failureCount += 1
                }
            }
            try await store.removeCacheEntries(
                remotePaths: released,
                mappingID: mapping.id
            )
            await refreshCacheSize(mapping)
            if failureCount == 0 {
                setSuccess("desktopDrive.status.offlineReleased")
            } else {
                setError("desktopDrive.error.offlinePartiallyReleased")
            }
        } catch {
            setError("desktopDrive.error.releaseOffline")
        }
    }

    func mapping(containing paths: [String]) -> DesktopDriveMapping? {
        let normalizedPaths = paths.compactMap(DesktopDrivePath.normalized)
        guard normalizedPaths.count == paths.count else { return nil }
        return mappings.first { mapping in
            normalizedPaths.allSatisfy { path in
                switch mapping.scope {
                case .allShares:
                    return path != "/"
                case .folder(let root):
                    guard let normalizedRoot = DesktopDrivePath.normalized(root) else {
                        return false
                    }
                    return DesktopDrivePath.isAncestorOrSame(
                        normalizedRoot,
                        of: path
                    )
                }
            }
        }
    }

    func isKeepingOffline(_ mapping: DesktopDriveMapping) -> Bool {
        offlineTasks[mapping.id] != nil
    }

    func itemsAreKeptOffline(_ items: [FileItem]) -> Bool {
        guard !items.isEmpty,
              let mapping = mapping(containing: items.map(\.path)),
              let runtime = runtimes[mapping.id] else {
            return false
        }
        return items.allSatisfy { runtime.keepsOffline($0.path) }
    }

    private func startKeepOffline(
        mapping: DesktopDriveMapping,
        folderRoots: [String],
        directFiles: [DesktopDrivePlannedFile],
        pinRoots: [String]
    ) {
        guard offlineTasks[mapping.id] == nil else { return }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runKeepOffline(
                mapping,
                folderRoots: folderRoots,
                directFiles: directFiles,
                pinRoots: pinRoots
            )
        }
        offlineTasks[mapping.id] = task
    }

    func cancelOffline(_ mapping: DesktopDriveMapping) {
        offlineTasks[mapping.id]?.cancel()
    }

    func releaseOffline(_ mapping: DesktopDriveMapping) async {
        guard !isBusy,
              let manager = NSFileProviderManager(for: domain(for: mapping)) else {
            setError("desktopDrive.error.releaseOffline")
            return
        }
        cancelOffline(mapping)
        isBusy = true
        defer { isBusy = false }
        do {
            let runtime = try await store.runtime(mappingID: mapping.id)
            let keptPaths = runtime.cacheEntries.values
                .filter { $0.kind == .keptOffline }
                .map(\.remotePath)
            try await store.setPinnedPaths([], mappingID: mapping.id)
            try await signalRoot(manager)
            var released: [String] = []
            var failureCount = 0
            for path in keptPaths {
                do {
                    try await evict(
                        identifier: itemIdentifier(path: path, mapping: mapping),
                        manager: manager
                    )
                    released.append(path)
                } catch {
                    failureCount += 1
                }
            }
            try await store.removeCacheEntries(
                remotePaths: released,
                mappingID: mapping.id
            )
            await refreshCacheSize(mapping)
            if failureCount == 0 {
                setSuccess("desktopDrive.status.offlineReleased")
            } else {
                setError("desktopDrive.error.offlinePartiallyReleased")
            }
        } catch {
            setError("desktopDrive.error.releaseOffline")
        }
    }

    func pause(_ mapping: DesktopDriveMapping) async {
        guard let manager = NSFileProviderManager(for: domain(for: mapping)) else {
            setError("desktopDrive.error.pause")
            return
        }
        cancelOffline(mapping)
        do {
            try await disconnect(manager)
            try await store.setMappingPaused(true, mappingID: mapping.id)
            await refreshRuntime(mapping)
            setSuccess("desktopDrive.status.paused")
        } catch {
            setError("desktopDrive.error.pause")
        }
    }

    func resume(_ mapping: DesktopDriveMapping) async {
        guard let manager = NSFileProviderManager(for: domain(for: mapping)) else {
            setError("desktopDrive.error.resume")
            return
        }
        do {
            try await reconnect(manager)
            try await store.setMappingPaused(false, mappingID: mapping.id)
            try await verifyReadable(mapping)
            try await store.setMappingState(
                .available,
                mappingID: mapping.id,
                successfulCheckAt: Date()
            )
            await refreshRuntime(mapping)
            setSuccess("desktopDrive.status.resumed")
        } catch {
            try? await store.setMappingState(.offline, mappingID: mapping.id)
            await refreshRuntime(mapping)
            setError("desktopDrive.error.resume")
        }
    }

    private func add(
        displayName: String,
        scope: DesktopDriveScope,
        cachePolicy: DesktopDriveCachePolicy
    ) async {
        guard isAvailable, !isBusy, let sessionBridge else {
            setError("desktopDrive.error.unavailable")
            return
        }
        isBusy = true
        defer { isBusy = false }
        var mapping = DesktopDriveMapping(
            profileID: profile.id,
            displayName: displayName,
            scope: scope,
            cachePolicy: cachePolicy
        )
        guard !mappings.contains(where: { $0.overlaps(mapping) }) else {
            setError("desktopDrive.error.overlap")
            return
        }
        do {
            try await verifyReadable(mapping)
            try await sessionBridge.publish()
            let newDomain = try domainForCreation(mapping)
            if newDomain.identifier.rawValue != mapping.id.uuidString {
                mapping = mapping.replacing(
                    providerDomainIdentifier: newDomain.identifier.rawValue
                )
            }
            try await store.saveMapping(mapping)
            try await store.setMappingState(
                .available,
                mappingID: mapping.id,
                successfulCheckAt: Date()
            )
            do {
                try await addDomain(newDomain)
            } catch {
                try? await store.removeMapping(id: mapping.id)
                throw error
            }
            mappings.append(mapping)
            mappings.sort { $0.createdAt < $1.createdAt }
            runtimes[mapping.id] = try await store.runtime(mappingID: mapping.id)
            setSuccess("desktopDrive.status.added")
        } catch {
            let remainingMappings =
                (try? await store.mappings(profileID: profile.id)) ?? mappings
            if remainingMappings.isEmpty {
                try? await sessionBridge.remove()
            }
            setError("desktopDrive.error.add")
        }
    }

    private func domain(
        for mapping: DesktopDriveMapping
    ) -> NSFileProviderDomain {
        NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(
                mapping.providerDomainIdentifier ?? mapping.id.uuidString
            ),
            displayName: mapping.displayName
        )
    }

    private func domainForCreation(
        _ mapping: DesktopDriveMapping
    ) throws -> NSFileProviderDomain {
        switch mapping.cachePolicy.location {
        case .systemDefault:
            return domain(for: mapping)
        case .eligibleVolume(let identifier):
            guard #available(macOS 15.0, *),
                  let volumeURL = Self.mountedVolumeURL(
                    identifier: identifier
                  ) else {
                throw CocoaError(.fileNoSuchFile)
            }
            guard case .eligible =
                    try NSFileProviderManager.checkDomainsCanBeStoredOnVolume(
                        at: volumeURL
                    ) else {
                throw CocoaError(.fileWriteUnsupportedScheme)
            }
            return NSFileProviderDomain(
                displayName: mapping.displayName,
                userInfo: ["mappingID": mapping.id.uuidString],
                volumeURL: volumeURL
            )
        }
    }

    @available(macOS 15.0, *)
    private static func mountedVolumeURL(
        identifier: String
    ) -> URL? {
        let keys: [URLResourceKey] = [.volumeUUIDStringKey]
        return FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        )?.first {
            (try? $0.resourceValues(forKeys: Set(keys)).volumeUUIDString)
                == identifier
        }
    }

    private func addDomain(_ domain: NSFileProviderDomain) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            NSFileProviderManager.add(domain) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func removeDomain(_ domain: NSFileProviderDomain) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            NSFileProviderManager.remove(domain) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func userVisibleURL(
        manager: NSFileProviderManager
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            manager.getUserVisibleURL(for: .rootContainer) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: CocoaError(.fileNoSuchFile))
                }
            }
        }
    }

    private func refreshCacheSizes() async {
        for mapping in mappings {
            await refreshCacheSize(mapping)
        }
    }

    private func refreshCacheSize(_ mapping: DesktopDriveMapping) async {
        guard let runtime = try? await store.runtime(mappingID: mapping.id) else {
            cacheBytes[mapping.id] = 0
            cacheSummaries[mapping.id] = .init()
            return
        }
        var summary = DesktopDriveCacheSummary()
        for entry in runtime.cacheEntries.values {
            switch entry.kind {
            case .temporary:
                summary.temporaryBytes += entry.allocatedSizeBytes
                summary.temporaryItemCount += 1
            case .keptOffline:
                summary.keptOfflineBytes += entry.allocatedSizeBytes
                summary.keptOfflineItemCount += 1
            }
        }
        cacheSummaries[mapping.id] = summary
        cacheBytes[mapping.id] = summary.totalBytes
        runtimes[mapping.id] = runtime
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

    private func requestDownload(
        identifier: NSFileProviderItemIdentifier,
        manager: NSFileProviderManager
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            manager.requestDownloadForItem(
                withIdentifier: identifier,
                requestedRange: NSRange(location: NSNotFound, length: 0)
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func setSuccess(_ key: String) {
        statusIsError = false
        statusMessage = L10n.string(key)
    }

    private func setError(_ key: String) {
        statusIsError = true
        statusMessage = L10n.string(key)
    }

    private func runKeepOffline(
        _ mapping: DesktopDriveMapping,
        folderRoots: [String],
        directFiles: [DesktopDrivePlannedFile],
        pinRoots: [String]
    ) async {
        defer { offlineTasks[mapping.id] = nil }
        let previousRuntime = (try? await store.runtime(mappingID: mapping.id))
            ?? .init()
        do {
            offlineProgress[mapping.id] = .init(phase: .planning)
            let plan = await DesktopDriveTreePlanner.build(
                rootFolders: folderRoots,
                rootFiles: directFiles,
                loadPage: { [repository] path, offset, limit in
                    if path == "/", case .allShares = mapping.scope {
                        return try await repository.listShares(
                            offset: offset,
                            limit: limit
                        )
                    }
                    return try await repository.listFolder(
                        path: path,
                        offset: offset,
                        limit: limit
                    )
                },
                progress: { [weak self] progress in
                    Task { @MainActor in
                        guard var value = self?.offlineProgress[mapping.id] else {
                            return
                        }
                        value.discoveredFolders = progress.folderCount
                        value.discoveredFiles = progress.fileCount
                        value.discoveredBytes = progress.discoveredBytes
                        self?.offlineProgress[mapping.id] = value
                    }
                }
            )
            try Task.checkCancellation()
            guard plan.isComplete else {
                if plan.issues.contains(where: { $0.kind == .cancelled }) {
                    throw CancellationError()
                }
                try await store.setMappingState(.degraded, mappingID: mapping.id)
                offlineProgress[mapping.id]?.phase = .failed
                setError("desktopDrive.error.planIncomplete")
                await refreshRuntime(mapping)
                return
            }
            guard let manager = NSFileProviderManager(for: domain(for: mapping)) else {
                throw CocoaError(.fileNoSuchFile)
            }
            offlineProgress[mapping.id]?.phase = .checkingSpace
            let rootURL = try await userVisibleURL(manager: manager)
            let volume = try rootURL.resourceValues(forKeys: [
                .volumeNameKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
            ])
            guard let totalCapacity = volume.volumeTotalCapacity,
                  let availableCapacity = volume.volumeAvailableCapacityForImportantUsage else {
                throw CocoaError(.fileWriteOutOfSpace)
            }
            let candidates = plan.files.map { file in
                DesktopDriveCacheCandidate(
                    sizeBytes: file.sizeBytes,
                    locallyAvailableBytes:
                        previousRuntime.cacheEntries[file.remotePath]?.logicalSizeBytes ?? 0
                )
            }
            let decision = DesktopDriveCacheSpaceCalculator.evaluate(
                candidates: candidates,
                volumeCapacityBytes: Int64(totalCapacity),
                availableCapacityBytes: availableCapacity,
                transientPeakBytes: plan.largestFileBytes
            )
            switch decision {
            case .allowed(let required, let available):
                offlineProgress[mapping.id]?.requiredBytes = required
                offlineProgress[mapping.id]?.availableBytes = available
            case .insufficient(let required, let available, let shortage):
                offlineProgress[mapping.id]?.requiredBytes = required
                offlineProgress[mapping.id]?.availableBytes = available
                offlineProgress[mapping.id]?.shortageBytes = shortage
                offlineProgress[mapping.id]?.volumeName = volume.volumeName
                offlineProgress[mapping.id]?.phase = .failed
                try await store.setMappingState(
                    .insufficientLocalSpace,
                    mappingID: mapping.id
                )
                await refreshRuntime(mapping)
                setError("desktopDrive.error.insufficientSpace")
                return
            case .unknownSize, .invalidCapacity:
                throw CocoaError(.fileWriteOutOfSpace)
            }

            let allPins = Array(
                Set(previousRuntime.pinnedPaths + pinRoots)
            )
            try await store.registerItemPaths(
                mappingID: mapping.id,
                remotePaths: plan.files.map(\.remotePath)
            )
            try await store.setPinnedPaths(allPins, mappingID: mapping.id)
            try await store.setMappingState(.checking, mappingID: mapping.id)
            try await signalRoot(manager)

            offlineProgress[mapping.id]?.phase = .requesting
            offlineProgress[mapping.id]?.totalFiles = plan.files.count
            offlineProgress[mapping.id]?.totalBytes = plan.totalBytes
            for (index, file) in plan.files.enumerated() {
                try Task.checkCancellation()
                try await requestDownload(
                    identifier: itemIdentifier(
                        path: file.remotePath,
                        mapping: mapping
                    ),
                    manager: manager
                )
                offlineProgress[mapping.id]?.completedFiles = index + 1
            }

            offlineProgress[mapping.id]?.phase = .downloading
            var previousCompletedCount = -1
            var lastProgressAt = Date()
            while true {
                try Task.checkCancellation()
                let runtime = try await store.runtime(mappingID: mapping.id)
                let completed = plan.files.filter { file in
                    guard let entry = runtime.cacheEntries[file.remotePath] else {
                        return false
                    }
                    return entry.logicalSizeBytes == file.sizeBytes
                }
                let completedBytes = completed.reduce(Int64(0)) {
                    $0 + $1.sizeBytes
                }
                offlineProgress[mapping.id]?.completedFiles = completed.count
                offlineProgress[mapping.id]?.completedBytes = completedBytes
                if completed.count != previousCompletedCount {
                    previousCompletedCount = completed.count
                    lastProgressAt = Date()
                } else if Date().timeIntervalSince(lastProgressAt) > 600 {
                    throw URLError(.timedOut)
                }
                if completed.count == plan.files.count {
                    offlineProgress[mapping.id]?.phase = .completed
                    try await store.setMappingState(
                        .available,
                        mappingID: mapping.id,
                        successfulCheckAt: Date()
                    )
                    await refreshCacheSize(mapping)
                    setSuccess("desktopDrive.status.offlineReady")
                    return
                }
                try await Task.sleep(for: .seconds(1))
            }
        } catch is CancellationError {
            try? await store.setPinnedPaths(
                previousRuntime.pinnedPaths,
                mappingID: mapping.id
            )
            if let manager = NSFileProviderManager(for: domain(for: mapping)) {
                try? await signalRoot(manager)
            }
            offlineProgress[mapping.id]?.phase = .cancelled
            try? await store.setMappingState(.available, mappingID: mapping.id)
            await refreshRuntime(mapping)
            setSuccess("desktopDrive.status.offlineCancelled")
        } catch {
            offlineProgress[mapping.id]?.phase = .failed
            try? await store.setMappingState(.degraded, mappingID: mapping.id)
            await refreshRuntime(mapping)
            setError("desktopDrive.error.keepOffline")
        }
    }

    private func restoreDomains() async {
        for mapping in mappings {
            guard let manager = NSFileProviderManager(for: domain(for: mapping)),
                  let runtime = runtimes[mapping.id] else {
                continue
            }
            if runtime.isManuallyPaused {
                try? await disconnect(manager)
                continue
            }
            do {
                try await reconnect(manager)
                try await verifyReadable(mapping)
                try await store.setMappingState(
                    .available,
                    mappingID: mapping.id,
                    successfulCheckAt: Date()
                )
            } catch {
                try? await store.setMappingState(.offline, mappingID: mapping.id)
            }
            await refreshRuntime(mapping)
        }
    }

    private func refreshRuntime(_ mapping: DesktopDriveMapping) async {
        if let runtime = try? await store.runtime(mappingID: mapping.id) {
            runtimes[mapping.id] = runtime
        }
    }

    private func verifyReadable(_ mapping: DesktopDriveMapping) async throws {
        switch mapping.scope {
        case .allShares:
            _ = try await repository.listShares(offset: 0, limit: 1)
        case .folder(let path):
            guard let item = try await repository.getInfo(paths: [path]).first,
                  item.isDirectory,
                  item.permissions?.canRead != false else {
                throw CocoaError(.fileReadNoPermission)
            }
        }
    }

    private func rootPath(_ mapping: DesktopDriveMapping) -> String {
        switch mapping.scope {
        case .allShares:
            return "/"
        case .folder(let path):
            return DesktopDrivePath.normalized(path) ?? "/"
        }
    }

    private func itemIdentifier(
        path: String,
        mapping: DesktopDriveMapping
    ) -> NSFileProviderItemIdentifier {
        NSFileProviderItemIdentifier(
            DesktopDriveItemIdentity.identifier(
                mappingID: mapping.id,
                remotePath: path
            ) ?? "invalid"
        )
    }

    private func signalRoot(_ manager: NSFileProviderManager) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            manager.signalEnumerator(for: .rootContainer) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func disconnect(_ manager: NSFileProviderManager) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            manager.disconnect(
                reason: L10n.string("desktopDrive.pause.reason"),
                options: [.temporary]
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func reconnect(_ manager: NSFileProviderManager) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            manager.reconnect { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
