import DsmCore
import FileProvider
import Foundation

/// 集中封装文件提供器域的生命周期和系统回调，避免界面状态管理器承担平台适配细节。
@MainActor
struct DesktopDriveDomainController {
    func domain(for mapping: DesktopDriveMapping) -> NSFileProviderDomain {
        NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(
                mapping.providerDomainIdentifier ?? mapping.id.uuidString
            ),
            displayName: mapping.displayName
        )
    }

    func domainForCreation(
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

    func manager(
        for mapping: DesktopDriveMapping
    ) -> NSFileProviderManager? {
        NSFileProviderManager(for: domain(for: mapping))
    }

    @available(macOS 15.0, *)
    static func mountedVolumeURL(identifier: String) -> URL? {
        let keys: Set<URLResourceKey> = [.volumeUUIDStringKey]
        return FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: [.skipHiddenVolumes]
        )?.first {
            (try? $0.resourceValues(forKeys: keys).volumeUUIDString)
                == identifier
        }
    }

    func add(_ domain: NSFileProviderDomain) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            NSFileProviderManager.add(domain) { error in
                resume(continuation, error: error)
            }
        }
    }

    func remove(_ domain: NSFileProviderDomain) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            NSFileProviderManager.remove(domain) { error in
                resume(continuation, error: error)
            }
        }
    }

    func userVisibleURL(
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

    func evict(
        identifier: NSFileProviderItemIdentifier,
        manager: NSFileProviderManager
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            manager.evictItem(identifier: identifier) { error in
                resume(continuation, error: error)
            }
        }
    }

    func requestDownload(
        identifier: NSFileProviderItemIdentifier,
        manager: NSFileProviderManager
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            manager.requestDownloadForItem(
                withIdentifier: identifier,
                requestedRange: NSRange(location: NSNotFound, length: 0)
            ) { error in
                resume(continuation, error: error)
            }
        }
    }

    func signalRoot(_ manager: NSFileProviderManager) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            manager.signalEnumerator(for: .rootContainer) { error in
                resume(continuation, error: error)
            }
        }
    }

    func disconnect(
        _ manager: NSFileProviderManager,
        reason: String
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            manager.disconnect(
                reason: reason,
                options: [.temporary]
            ) { error in
                resume(continuation, error: error)
            }
        }
    }

    func reconnect(_ manager: NSFileProviderManager) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            manager.reconnect { error in
                resume(continuation, error: error)
            }
        }
    }

    nonisolated private func resume(
        _ continuation: CheckedContinuation<Void, Error>,
        error: Error?
    ) {
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}
