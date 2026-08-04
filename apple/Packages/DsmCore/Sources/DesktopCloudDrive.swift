import CryptoKit
import Foundation

public enum DesktopDriveScope: Codable, Equatable, Sendable {
    case allShares
    case folder(path: String)
}

public enum DesktopDriveAccessMode: String, Codable, Sendable {
    case readOnly
}

public enum DesktopDriveCacheLocation: Codable, Equatable, Sendable {
    case systemDefault
    case eligibleVolume(id: String)
}

public struct DesktopDriveCachePolicy: Codable, Equatable, Sendable {
    public static let defaultTemporaryLimitBytes: Int64 = 10 * 1_024 * 1_024 * 1_024
    public static let minimumFreeReserveBytes: Int64 = 2 * 1_024 * 1_024 * 1_024
    public static let maximumFreeReserveBytes: Int64 = 20 * 1_024 * 1_024 * 1_024

    public let location: DesktopDriveCacheLocation
    public let temporaryLimitBytes: Int64

    public init(
        location: DesktopDriveCacheLocation = .systemDefault,
        temporaryLimitBytes: Int64 = Self.defaultTemporaryLimitBytes
    ) {
        self.location = location
        self.temporaryLimitBytes = max(temporaryLimitBytes, 0)
    }
}

public enum DesktopDriveMappingState: String, Codable, CaseIterable, Sendable {
    case preparing
    case available
    case checking
    case paused
    case offline
    case authenticationRequired
    case cacheVolumeUnavailable
    case insufficientLocalSpace
    case degraded
    case recoveryRequired
    case removing
    case failed

    public func canTransition(to target: Self) -> Bool {
        guard self != target else { return true }
        switch self {
        case .preparing:
            return [
                .available, .paused, .offline, .authenticationRequired,
                .cacheVolumeUnavailable, .insufficientLocalSpace,
                .recoveryRequired, .removing, .failed,
            ].contains(target)
        case .available:
            return [
                .checking, .paused, .offline, .authenticationRequired,
                .cacheVolumeUnavailable, .insufficientLocalSpace, .degraded,
                .recoveryRequired, .removing, .failed,
            ].contains(target)
        case .checking:
            return [
                .available, .paused, .offline, .authenticationRequired,
                .cacheVolumeUnavailable, .insufficientLocalSpace, .degraded,
                .recoveryRequired, .removing, .failed,
            ].contains(target)
        case .paused:
            return [.checking, .recoveryRequired, .removing, .failed].contains(target)
        case .offline:
            return [
                .checking, .paused, .authenticationRequired,
                .recoveryRequired, .removing, .failed,
            ].contains(target)
        case .authenticationRequired:
            return [.checking, .paused, .recoveryRequired, .removing, .failed].contains(target)
        case .cacheVolumeUnavailable:
            return [.checking, .paused, .recoveryRequired, .removing, .failed].contains(target)
        case .insufficientLocalSpace:
            return [.checking, .paused, .recoveryRequired, .removing, .failed].contains(target)
        case .degraded:
            return [
                .checking, .available, .paused, .offline, .authenticationRequired,
                .cacheVolumeUnavailable, .insufficientLocalSpace,
                .recoveryRequired, .removing, .failed,
            ].contains(target)
        case .recoveryRequired:
            return [.checking, .removing, .failed].contains(target)
        case .removing:
            return [.failed].contains(target)
        case .failed:
            return [.preparing, .checking, .removing].contains(target)
        }
    }
}

public enum DesktopDriveItemAvailabilityState: String, Codable, CaseIterable, Sendable {
    case onlineOnly
    case downloading
    case temporarilyAvailable
    case pinnedPending
    case availableOffline
    case releasing
    case unavailable
    case failed
}

public enum DesktopDriveCacheEntryKind: String, Codable, Sendable {
    case temporary
    case keptOffline
}

public struct DesktopDriveCacheEntry: Codable, Equatable, Sendable {
    public let remotePath: String
    public let kind: DesktopDriveCacheEntryKind
    public let logicalSizeBytes: Int64
    public let allocatedSizeBytes: Int64
    public let lastAccessedAt: Date
    public let updatedAt: Date

    public init(
        remotePath: String,
        kind: DesktopDriveCacheEntryKind,
        logicalSizeBytes: Int64,
        allocatedSizeBytes: Int64,
        lastAccessedAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.remotePath = remotePath
        self.kind = kind
        self.logicalSizeBytes = max(logicalSizeBytes, 0)
        self.allocatedSizeBytes = max(allocatedSizeBytes, 0)
        self.lastAccessedAt = lastAccessedAt
        self.updatedAt = updatedAt
    }
}

public enum DesktopDriveCacheEvictionPlanner {
    public static func temporaryPathsToEvict(
        entries: [DesktopDriveCacheEntry],
        limitBytes: Int64
    ) -> [String] {
        let limit = max(limitBytes, 0)
        let temporary = entries
            .filter { $0.kind == .temporary }
            .sorted {
                if $0.lastAccessedAt == $1.lastAccessedAt {
                    return $0.remotePath < $1.remotePath
                }
                return $0.lastAccessedAt < $1.lastAccessedAt
            }
        var total = temporary.reduce(Int64(0)) { partial, entry in
            let sum = partial.addingReportingOverflow(entry.allocatedSizeBytes)
            return sum.overflow ? .max : sum.partialValue
        }
        guard total > limit else { return [] }

        var paths: [String] = []
        for entry in temporary {
            paths.append(entry.remotePath)
            total = max(total - entry.allocatedSizeBytes, 0)
            if total <= limit {
                break
            }
        }
        return paths
    }
}

public struct DesktopDriveMappingRuntime: Codable, Equatable, Sendable {
    public var state: DesktopDriveMappingState
    public var isManuallyPaused: Bool
    public var lastSuccessfulCheckAt: Date?
    public var pinnedPaths: [String]
    public var cacheEntries: [String: DesktopDriveCacheEntry]

    public init(
        state: DesktopDriveMappingState = .preparing,
        isManuallyPaused: Bool = false,
        lastSuccessfulCheckAt: Date? = nil,
        pinnedPaths: [String] = [],
        cacheEntries: [String: DesktopDriveCacheEntry] = [:]
    ) {
        self.state = state
        self.isManuallyPaused = isManuallyPaused
        self.lastSuccessfulCheckAt = lastSuccessfulCheckAt
        self.pinnedPaths = pinnedPaths
        self.cacheEntries = cacheEntries
    }

    public func keepsOffline(_ remotePath: String) -> Bool {
        guard let normalized = DesktopDrivePath.normalized(remotePath) else {
            return false
        }
        return pinnedPaths.contains { candidate in
            guard let root = DesktopDrivePath.normalized(candidate) else {
                return false
            }
            return DesktopDrivePath.isAncestorOrSame(root, of: normalized)
        }
    }
}

public struct DesktopDriveMapping: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let profileID: UUID
    public let displayName: String
    public let scope: DesktopDriveScope
    public let accessMode: DesktopDriveAccessMode
    public let cachePolicy: DesktopDriveCachePolicy
    public let launchAtLogin: Bool
    public let providerDomainIdentifier: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        profileID: UUID,
        displayName: String,
        scope: DesktopDriveScope,
        accessMode: DesktopDriveAccessMode = .readOnly,
        cachePolicy: DesktopDriveCachePolicy = .init(),
        launchAtLogin: Bool = true,
        providerDomainIdentifier: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.profileID = profileID
        self.displayName = displayName
        self.scope = scope
        self.accessMode = accessMode
        self.cachePolicy = cachePolicy
        self.launchAtLogin = launchAtLogin
        self.providerDomainIdentifier = providerDomainIdentifier
        self.createdAt = createdAt
    }

    public func overlaps(_ other: Self) -> Bool {
        guard profileID == other.profileID else { return false }
        switch (scope, other.scope) {
        case (.allShares, _), (_, .allShares):
            return true
        case (.folder(let left), .folder(let right)):
            guard let normalizedLeft = DesktopDrivePath.normalized(left),
                  let normalizedRight = DesktopDrivePath.normalized(right) else {
                return false
            }
            return DesktopDrivePath.isAncestorOrSame(normalizedLeft, of: normalizedRight)
                || DesktopDrivePath.isAncestorOrSame(normalizedRight, of: normalizedLeft)
        }
    }

    public func replacing(
        displayName: String? = nil,
        cachePolicy: DesktopDriveCachePolicy? = nil,
        launchAtLogin: Bool? = nil,
        providerDomainIdentifier: String? = nil
    ) -> Self {
        Self(
            id: id,
            profileID: profileID,
            displayName: displayName ?? self.displayName,
            scope: scope,
            accessMode: accessMode,
            cachePolicy: cachePolicy ?? self.cachePolicy,
            launchAtLogin: launchAtLogin ?? self.launchAtLogin,
            providerDomainIdentifier:
                providerDomainIdentifier ?? self.providerDomainIdentifier,
            createdAt: createdAt
        )
    }
}

public enum DesktopDrivePath {
    public static func normalized(_ path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.contains(where: { $0 == "." || $0 == ".." }) else { return nil }
        return components.isEmpty ? "/" : "/" + components.joined(separator: "/")
    }

    public static func isAncestorOrSame(_ candidate: String, of path: String) -> Bool {
        candidate == "/" || candidate == path || path.hasPrefix(candidate + "/")
    }
}

public enum DesktopDriveItemIdentity {
    public static func identifier(
        mappingID: UUID,
        remotePath: String
    ) -> String? {
        guard let path = DesktopDrivePath.normalized(remotePath) else {
            return nil
        }
        var input = Data(mappingID.uuidString.lowercased().utf8)
        input.append(0)
        input.append(contentsOf: path.utf8)
        let digest = SHA256.hash(data: input)
        return "item:" + digest.map { String(format: "%02x", $0) }.joined()
    }
}

public enum DesktopDriveStagingIdentity {
    public static func contentFileName(
        mappingID: UUID,
        remotePath: String,
        sizeBytes: Int64?,
        modifiedAt: Date?
    ) -> String? {
        guard let path = DesktopDrivePath.normalized(remotePath) else {
            return nil
        }
        let value = [
            mappingID.uuidString.lowercased(),
            path,
            String(sizeBytes ?? -1),
            String(modifiedAt?.timeIntervalSince1970 ?? 0),
        ].joined(separator: "\u{0}")
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".content"
    }
}

public struct DesktopDriveCacheCandidate: Equatable, Sendable {
    public let sizeBytes: Int64?
    public let locallyAvailableBytes: Int64

    public init(sizeBytes: Int64?, locallyAvailableBytes: Int64 = 0) {
        self.sizeBytes = sizeBytes
        self.locallyAvailableBytes = max(locallyAvailableBytes, 0)
    }
}

public enum DesktopDriveCacheSpaceDecision: Equatable, Sendable {
    case allowed(requiredBytes: Int64, availableBytes: Int64)
    case insufficient(requiredBytes: Int64, availableBytes: Int64, shortageBytes: Int64)
    case unknownSize
    case invalidCapacity
}

public enum DesktopDriveCacheSpaceCalculator {
    public static func evaluate(
        candidates: [DesktopDriveCacheCandidate],
        volumeCapacityBytes: Int64,
        availableCapacityBytes: Int64,
        transientPeakBytes: Int64? = nil
    ) -> DesktopDriveCacheSpaceDecision {
        guard volumeCapacityBytes >= 0, availableCapacityBytes >= 0 else {
            return .invalidCapacity
        }

        var missingBytes: Int64 = 0
        var largestMissingItem: Int64 = 0
        for candidate in candidates {
            guard let sizeBytes = candidate.sizeBytes, sizeBytes >= 0 else {
                return .unknownSize
            }
            let missing = max(sizeBytes - min(candidate.locallyAvailableBytes, sizeBytes), 0)
            guard let updatedMissing = adding(missingBytes, missing) else {
                return overflowDecision(availableCapacityBytes: availableCapacityBytes)
            }
            missingBytes = updatedMissing
            largestMissingItem = max(largestMissingItem, missing)
        }

        let transientPeak = max(transientPeakBytes ?? largestMissingItem, 0)
        let reserve = safetyReserve(volumeCapacityBytes: volumeCapacityBytes)
        guard let withTransient = adding(missingBytes, transientPeak),
              let required = adding(withTransient, reserve) else {
            return overflowDecision(availableCapacityBytes: availableCapacityBytes)
        }

        guard required <= availableCapacityBytes else {
            return .insufficient(
                requiredBytes: required,
                availableBytes: availableCapacityBytes,
                shortageBytes: required - availableCapacityBytes
            )
        }
        return .allowed(requiredBytes: required, availableBytes: availableCapacityBytes)
    }

    public static func safetyReserve(volumeCapacityBytes: Int64) -> Int64 {
        guard volumeCapacityBytes > 0 else {
            return DesktopDriveCachePolicy.minimumFreeReserveBytes
        }
        let fivePercent = volumeCapacityBytes / 20
        return min(
            max(fivePercent, DesktopDriveCachePolicy.minimumFreeReserveBytes),
            DesktopDriveCachePolicy.maximumFreeReserveBytes
        )
    }

    private static func adding(_ left: Int64, _ right: Int64) -> Int64? {
        let result = left.addingReportingOverflow(right)
        return result.overflow ? nil : result.partialValue
    }

    private static func overflowDecision(
        availableCapacityBytes: Int64
    ) -> DesktopDriveCacheSpaceDecision {
        .insufficient(
            requiredBytes: .max,
            availableBytes: availableCapacityBytes,
            shortageBytes: .max
        )
    }
}
