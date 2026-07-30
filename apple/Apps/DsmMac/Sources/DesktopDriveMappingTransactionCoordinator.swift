import DsmCore
import FileProvider
import Foundation

protocol DesktopDriveSessionBridging: Sendable {
    func publish() async throws
    func remove() async throws
}

protocol DesktopDriveConfigurationTransactionStoring: Sendable {
    func saveMapping(_ mapping: DesktopDriveMapping) async throws
    func removeMapping(id: UUID) async throws
    func mappings(profileID: UUID?) async throws -> [DesktopDriveMapping]
    func runtime(mappingID: UUID) async throws -> DesktopDriveMappingRuntime
    func setMappingState(
        _ state: DesktopDriveMappingState,
        mappingID: UUID,
        successfulCheckAt: Date?
    ) async throws
}

extension DesktopDriveConfigurationStore:
    DesktopDriveConfigurationTransactionStoring {}

@MainActor
protocol DesktopDriveDomainRegistrationControlling {
    func domain(for mapping: DesktopDriveMapping) -> NSFileProviderDomain
    func domainForCreation(
        _ mapping: DesktopDriveMapping
    ) throws -> NSFileProviderDomain
    func add(_ domain: NSFileProviderDomain) async throws
    func remove(_ domain: NSFileProviderDomain) async throws
    func registeredDomainIdentifiers() async throws -> Set<String>
    func removeRegisteredDomain(identifier: String) async throws
}

enum DesktopDriveMappingRecoveryResult: Equatable {
    case unchanged
    case activated
    case removed
    case needsCacheVolume
    case failed
}

struct DesktopDriveOrphanCleanupResult: Equatable {
    let removedCount: Int
    let failureCount: Int
}

/// 将映射创建、移除和启动恢复集中为可测试事务，系统回调失败时保留可恢复状态。
@MainActor
struct DesktopDriveMappingTransactionCoordinator {
    private let store: any DesktopDriveConfigurationTransactionStoring
    private let sessionBridge: (any DesktopDriveSessionBridging)?
    private let domainController: any DesktopDriveDomainRegistrationControlling

    init(
        store: any DesktopDriveConfigurationTransactionStoring,
        sessionBridge: (any DesktopDriveSessionBridging)?,
        domainController: any DesktopDriveDomainRegistrationControlling
    ) {
        self.store = store
        self.sessionBridge = sessionBridge
        self.domainController = domainController
    }

    func create(
        _ initialMapping: DesktopDriveMapping,
        verifyReadable: (DesktopDriveMapping) async throws -> Void
    ) async throws -> DesktopDriveMapping {
        guard let sessionBridge else {
            throw DesktopDriveConfigurationStoreError.connectionUnavailable
        }

        var mapping = initialMapping
        var mappingSaved = false
        var domainAdded = false
        do {
            try await sessionBridge.publish()
            let domain = try domainController.domainForCreation(mapping)
            if domain.identifier.rawValue != mapping.id.uuidString {
                mapping = mapping.replacing(
                    providerDomainIdentifier: domain.identifier.rawValue
                )
            }
            try await store.saveMapping(mapping)
            mappingSaved = true
            try await store.setMappingState(
                .preparing,
                mappingID: mapping.id,
                successfulCheckAt: nil
            )
            try await domainController.add(domain)
            domainAdded = true
            try await verifyReadable(mapping)
            try await store.setMappingState(
                .available,
                mappingID: mapping.id,
                successfulCheckAt: Date()
            )
            return mapping
        } catch {
            if domainAdded {
                do {
                    try await domainController.remove(
                        domainController.domain(for: mapping)
                    )
                    if mappingSaved {
                        try await store.removeMapping(id: mapping.id)
                    }
                } catch {
                    try? await store.setMappingState(
                        .removing,
                        mappingID: mapping.id,
                        successfulCheckAt: nil
                    )
                }
            } else if mappingSaved {
                do {
                    try await store.removeMapping(id: mapping.id)
                } catch {
                    try? await store.setMappingState(
                        .removing,
                        mappingID: mapping.id,
                        successfulCheckAt: nil
                    )
                }
            }
            await removeSessionIfUnused(profileID: mapping.profileID)
            throw error
        }
    }

    func remove(_ mapping: DesktopDriveMapping) async throws {
        try await store.setMappingState(
            .removing,
            mappingID: mapping.id,
            successfulCheckAt: nil
        )
        try await domainController.remove(domainController.domain(for: mapping))
        try await store.removeMapping(id: mapping.id)
        await removeSessionIfUnused(profileID: mapping.profileID)
    }

    func recover(
        _ mapping: DesktopDriveMapping,
        registeredDomainIdentifiers: Set<String>,
        verifyReadable: (DesktopDriveMapping) async throws -> Void
    ) async -> DesktopDriveMappingRecoveryResult {
        do {
            let runtime = try await store.runtime(mappingID: mapping.id)
            let identifier =
                mapping.providerDomainIdentifier ?? mapping.id.uuidString
            let isRegistered = registeredDomainIdentifiers.contains(identifier)

            if runtime.state == .removing {
                if isRegistered {
                    try await domainController.remove(
                        domainController.domain(for: mapping)
                    )
                }
                try await store.removeMapping(id: mapping.id)
                await removeSessionIfUnused(profileID: mapping.profileID)
                return .removed
            }

            if !isRegistered {
                switch mapping.cachePolicy.location {
                case .systemDefault:
                    try await domainController.add(
                        domainController.domain(for: mapping)
                    )
                case .eligibleVolume:
                    try await store.setMappingState(
                        .cacheVolumeUnavailable,
                        mappingID: mapping.id,
                        successfulCheckAt: nil
                    )
                    return .needsCacheVolume
                }
            }

            guard [
                DesktopDriveMappingState.preparing,
                .cacheVolumeUnavailable,
            ].contains(runtime.state) || !isRegistered else {
                return .unchanged
            }
            try await verifyReadable(mapping)
            try await store.setMappingState(
                .available,
                mappingID: mapping.id,
                successfulCheckAt: Date()
            )
            return .activated
        } catch {
            let currentState =
                try? await store.runtime(mappingID: mapping.id).state
            if currentState != .removing {
                try? await store.setMappingState(
                    .failed,
                    mappingID: mapping.id,
                    successfulCheckAt: nil
                )
            }
            return .failed
        }
    }

    func registeredDomainIdentifiers() async throws -> Set<String> {
        try await domainController.registeredDomainIdentifiers()
    }

    func removeOrphanedDomains(
        allMappings: [DesktopDriveMapping]
    ) async throws -> DesktopDriveOrphanCleanupResult {
        let configuredIdentifiers = Set(allMappings.map {
            $0.providerDomainIdentifier ?? $0.id.uuidString
        })
        let orphanedIdentifiers =
            try await domainController.registeredDomainIdentifiers()
                .subtracting(configuredIdentifiers)
        var removedCount = 0
        var failureCount = 0
        for identifier in orphanedIdentifiers.sorted() {
            do {
                try await domainController.removeRegisteredDomain(
                    identifier: identifier
                )
                removedCount += 1
            } catch {
                failureCount += 1
            }
        }
        return .init(
            removedCount: removedCount,
            failureCount: failureCount
        )
    }

    private func removeSessionIfUnused(profileID: UUID) async {
        guard let mappings = try? await store.mappings(profileID: profileID),
              mappings.isEmpty else {
            return
        }
        try? await sessionBridge?.remove()
    }
}
