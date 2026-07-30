import Darwin
import Foundation

public enum DesktopDriveSharedContainer {
    public static let appGroupIdentifier =
        "group.io.github.qwertyuiop1995.dsmnativeclient"
}

public struct DesktopDriveProviderConnection: Codable, Equatable, Sendable {
    public let profile: NasProfile
    public let capabilities: [ApiCapability]

    public init(profile: NasProfile, capabilities: CapabilitySet) {
        self.profile = profile
        self.capabilities = capabilities.all
    }

    public var capabilitySet: CapabilitySet {
        CapabilitySet(Dictionary(uniqueKeysWithValues: capabilities.map { ($0.name, $0) }))
    }
}

public struct DesktopDriveProviderConfiguration: Codable, Equatable, Sendable {
    public let mapping: DesktopDriveMapping
    public let connection: DesktopDriveProviderConnection

    public init(
        mapping: DesktopDriveMapping,
        connection: DesktopDriveProviderConnection
    ) {
        self.mapping = mapping
        self.connection = connection
    }
}

public enum DesktopDriveConfigurationStoreError: Error, Equatable, Sendable {
    case sharedContainerUnavailable
    case connectionUnavailable
}

public actor DesktopDriveConfigurationStore {
    private struct Snapshot: Codable {
        var version = 2
        var connections: [UUID: DesktopDriveProviderConnection] = [:]
        var mappings: [UUID: DesktopDriveMapping] = [:]
        var itemPaths: [UUID: [String: String]]?
        var runtimes: [UUID: DesktopDriveMappingRuntime]?
        var providerAvailable: Bool?
    }

    private let directoryURL: URL?
    private let fileManager: FileManager
    private let writeOptions: Data.WritingOptions

    public init(
        appGroupIdentifier: String = DesktopDriveSharedContainer.appGroupIdentifier,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        writeOptions = [.atomic, .completeFileProtection]
        directoryURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
    }

    public init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        writeOptions = [.atomic]
    }

    public func saveConnection(
        profile: NasProfile,
        capabilities: CapabilitySet
    ) throws {
        try updateSnapshot { snapshot in
            snapshot.connections[profile.id] = DesktopDriveProviderConnection(
                profile: profile,
                capabilities: capabilities
            )
        }
    }

    public func saveMapping(_ mapping: DesktopDriveMapping) throws {
        try updateSnapshot { snapshot in
            guard snapshot.connections[mapping.profileID] != nil else {
                throw DesktopDriveConfigurationStoreError.connectionUnavailable
            }
            snapshot.mappings[mapping.id] = mapping
        }
    }

    public func configuration(
        mappingID: UUID
    ) throws -> DesktopDriveProviderConfiguration? {
        try readSnapshot { snapshot in
            guard let mapping = snapshot.mappings[mappingID],
                  let connection = snapshot.connections[mapping.profileID] else {
                return nil
            }
            return DesktopDriveProviderConfiguration(
                mapping: mapping,
                connection: connection
            )
        }
    }

    public func mappings(profileID: UUID? = nil) throws -> [DesktopDriveMapping] {
        try readSnapshot { snapshot in
            snapshot.mappings.values
                .filter { profileID == nil || $0.profileID == profileID }
                .sorted { $0.createdAt < $1.createdAt }
        }
    }

    public func removeMapping(id: UUID) throws {
        try updateSnapshot { snapshot in
            snapshot.mappings.removeValue(forKey: id)
            snapshot.itemPaths?[id] = nil
            snapshot.runtimes?[id] = nil
        }
    }

    public func removeConnection(profileID: UUID) throws {
        try updateSnapshot { snapshot in
            snapshot.connections.removeValue(forKey: profileID)
            let removedIDs = snapshot.mappings.values
                .filter { $0.profileID == profileID }
                .map(\.id)
            snapshot.mappings = snapshot.mappings.filter {
                $0.value.profileID != profileID
            }
            for mappingID in removedIDs {
                snapshot.itemPaths?[mappingID] = nil
                snapshot.runtimes?[mappingID] = nil
            }
        }
    }

    public func registerItemPaths(
        mappingID: UUID,
        remotePaths: [String]
    ) throws {
        try updateSnapshot { snapshot in
            guard snapshot.mappings[mappingID] != nil else {
                return
            }
            var index = snapshot.itemPaths?[mappingID] ?? [:]
            for rawPath in remotePaths {
                guard let path = DesktopDrivePath.normalized(rawPath),
                      let identifier = DesktopDriveItemIdentity.identifier(
                        mappingID: mappingID,
                        remotePath: path
                      ) else {
                    continue
                }
                index[identifier] = path
            }
            if snapshot.itemPaths == nil {
                snapshot.itemPaths = [:]
            }
            snapshot.itemPaths?[mappingID] = index
        }
    }

    public func remotePath(
        mappingID: UUID,
        itemIdentifier: String
    ) throws -> String? {
        try readSnapshot {
            $0.itemPaths?[mappingID]?[itemIdentifier]
        }
    }

    public func runtime(
        mappingID: UUID
    ) throws -> DesktopDriveMappingRuntime {
        try readSnapshot {
            $0.runtimes?[mappingID] ?? .init()
        }
    }

    public func saveRuntime(
        _ runtime: DesktopDriveMappingRuntime,
        mappingID: UUID
    ) throws {
        try updateSnapshot { snapshot in
            guard snapshot.mappings[mappingID] != nil else {
                return
            }
            if snapshot.runtimes == nil {
                snapshot.runtimes = [:]
            }
            snapshot.runtimes?[mappingID] = runtime
        }
    }

    public func setMappingState(
        _ state: DesktopDriveMappingState,
        mappingID: UUID,
        successfulCheckAt: Date? = nil
    ) throws {
        try updateSnapshot { snapshot in
            guard snapshot.mappings[mappingID] != nil else {
                return
            }
            var runtime = snapshot.runtimes?[mappingID] ?? .init()
            runtime.state = state
            if let successfulCheckAt {
                runtime.lastSuccessfulCheckAt = successfulCheckAt
            }
            if snapshot.runtimes == nil {
                snapshot.runtimes = [:]
            }
            snapshot.runtimes?[mappingID] = runtime
        }
    }

    public func setMappingPaused(
        _ isPaused: Bool,
        mappingID: UUID
    ) throws {
        try updateSnapshot { snapshot in
            guard snapshot.mappings[mappingID] != nil else {
                return
            }
            var runtime = snapshot.runtimes?[mappingID] ?? .init()
            runtime.isManuallyPaused = isPaused
            runtime.state = isPaused ? .paused : .checking
            if snapshot.runtimes == nil {
                snapshot.runtimes = [:]
            }
            snapshot.runtimes?[mappingID] = runtime
        }
    }

    public func setPinnedPaths(
        _ remotePaths: [String],
        mappingID: UUID
    ) throws {
        try updateSnapshot { snapshot in
            guard snapshot.mappings[mappingID] != nil else {
                return
            }
            var runtime = snapshot.runtimes?[mappingID] ?? .init()
            runtime.pinnedPaths = Array(
                Set(remotePaths.compactMap(DesktopDrivePath.normalized))
            ).sorted()
            if snapshot.runtimes == nil {
                snapshot.runtimes = [:]
            }
            snapshot.runtimes?[mappingID] = runtime
        }
    }

    public func recordCacheEntry(
        _ entry: DesktopDriveCacheEntry,
        mappingID: UUID
    ) throws {
        try updateSnapshot { snapshot in
            guard snapshot.mappings[mappingID] != nil else {
                return
            }
            var runtime = snapshot.runtimes?[mappingID] ?? .init()
            runtime.cacheEntries[entry.remotePath] = entry
            if snapshot.runtimes == nil {
                snapshot.runtimes = [:]
            }
            snapshot.runtimes?[mappingID] = runtime
        }
    }

    public func removeCacheEntries(
        remotePaths: [String],
        mappingID: UUID
    ) throws {
        try updateSnapshot { snapshot in
            guard snapshot.mappings[mappingID] != nil else {
                return
            }
            var runtime = snapshot.runtimes?[mappingID] ?? .init()
            for path in remotePaths {
                runtime.cacheEntries.removeValue(forKey: path)
            }
            if snapshot.runtimes == nil {
                snapshot.runtimes = [:]
            }
            snapshot.runtimes?[mappingID] = runtime
        }
    }

    public func setProviderAvailable(_ isAvailable: Bool) throws {
        try updateSnapshot { snapshot in
            snapshot.providerAvailable = isAvailable
        }
    }

    public func isProviderAvailable() throws -> Bool {
        try readSnapshot {
            $0.providerAvailable ?? true
        }
    }

    private func readSnapshot<T>(
        _ body: (Snapshot) throws -> T
    ) throws -> T {
        try withFileLock(exclusive: false) {
            try body(loadSnapshotUnlocked())
        }
    }

    private func updateSnapshot(
        _ body: (inout Snapshot) throws -> Void
    ) throws {
        try withFileLock(exclusive: true) {
            var snapshot = try loadSnapshotUnlocked()
            try body(&snapshot)
            try saveSnapshotUnlocked(snapshot)
        }
    }

    private func loadSnapshotUnlocked() throws -> Snapshot {
        guard let fileURL else {
            throw DesktopDriveConfigurationStoreError.sharedContainerUnavailable
        }
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return Snapshot()
        }
        return try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: fileURL))
    }

    private func saveSnapshotUnlocked(_ snapshot: Snapshot) throws {
        guard let directoryURL, let fileURL else {
            throw DesktopDriveConfigurationStoreError.sharedContainerUnavailable
        }
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: writeOptions)
    }

    private func withFileLock<T>(
        exclusive: Bool,
        _ body: () throws -> T
    ) throws -> T {
        guard let directoryURL, let lockURL else {
            throw DesktopDriveConfigurationStoreError.sharedContainerUnavailable
        }
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(descriptor) }
        guard flock(descriptor, exclusive ? LOCK_EX : LOCK_SH) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }

    private var fileURL: URL? {
        directoryURL?.appendingPathComponent(
            "desktop-drive-config-v1.json",
            isDirectory: false
        )
    }

    private var lockURL: URL? {
        directoryURL?.appendingPathComponent(
            "desktop-drive-config-v1.lock",
            isDirectory: false
        )
    }
}
