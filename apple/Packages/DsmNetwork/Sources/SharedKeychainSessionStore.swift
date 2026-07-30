import DsmCore
import Foundation
import Security

/// 仅供主 App 与 File Provider 扩展共享最小必要会话，不保存登录密码。
public actor SharedKeychainSessionStore: SessionSecureStoring {
    private let accessGroup: String?
    private let servicePrefix: String

    public init(
        accessGroup: String? = Bundle.main.object(
            forInfoDictionaryKey: "LanStashSharedKeychainAccessGroup"
        ) as? String,
        servicePrefix: String = "io.github.qwertyuiop1995.dsmnativeclient.shared"
    ) {
        self.accessGroup = accessGroup
        self.servicePrefix = servicePrefix
    }

    public func save(_ session: AuthSession, for profileID: UUID) async throws {
        try save(
            try JSONEncoder().encode(session),
            service: sessionService,
            profileID: profileID
        )
    }

    public func load(for profileID: UUID) async throws -> AuthSession? {
        guard let data = try load(
            service: sessionService,
            profileID: profileID
        ) else {
            return nil
        }
        return try JSONDecoder().decode(AuthSession.self, from: data)
    }

    public func remove(for profileID: UUID) async throws {
        try remove(service: sessionService, profileID: profileID)
    }

    private var sessionService: String {
        "\(servicePrefix).session"
    }

    private func save(
        _ data: Data,
        service: String,
        profileID: UUID
    ) throws {
        try remove(service: service, profileID: profileID)
        var query = baseQuery(service: service, profileID: profileID)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainStoreError(status: status)
        }
    }

    private func load(service: String, profileID: UUID) throws -> Data? {
        var query = baseQuery(service: service, profileID: profileID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainStoreError(status: status)
        }
        return data
    }

    private func remove(service: String, profileID: UUID) throws {
        let status = SecItemDelete(
            baseQuery(service: service, profileID: profileID) as CFDictionary
        )
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError(status: status)
        }
    }

    private func baseQuery(
        service: String,
        profileID: UUID
    ) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID.uuidString,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

public struct KeychainStoreError: Error, Equatable, Sendable {
    public let status: OSStatus

    public init(status: OSStatus) {
        self.status = status
    }
}

/// 把短期版本迁入共享钥匙串的资料迁回应用内加密存储。
///
/// 迁移完成后共享钥匙串不再保留密码；只有仍存在 Finder 映射时才保留会话。
public actor DesktopSecureStoreRollbackMigrator {
    private let localStore: LocalFileSecureStore
    private let sharedSessionStore: SharedKeychainSessionStore
    private let configurationStore: DesktopDriveConfigurationStore
    private let legacyPasswordStore: LegacySharedKeychainPasswordStore
    private var migratedProfileIDs: Set<UUID> = []

    public init(
        localStore: LocalFileSecureStore,
        sharedSessionStore: SharedKeychainSessionStore,
        configurationStore: DesktopDriveConfigurationStore = .init()
    ) {
        self.localStore = localStore
        self.sharedSessionStore = sharedSessionStore
        self.configurationStore = configurationStore
        self.legacyPasswordStore = LegacySharedKeychainPasswordStore()
    }

    public func migrateIfNeeded(profileID: UUID) async {
        guard migratedProfileIDs.insert(profileID).inserted else {
            return
        }
        do {
            let localSession: AuthSession? = try await localStore.load(
                for: profileID
            )
            let localPassword: String? = try await localStore.load(
                for: profileID
            )
            let sharedSession = try await sharedSessionStore.load(
                for: profileID
            )
            let sharedPassword = try legacyPasswordStore.load(
                for: profileID
            )
            if localSession == nil, let sharedSession {
                try await localStore.save(sharedSession, for: profileID)
            }
            if localPassword == nil, let sharedPassword {
                try await localStore.save(sharedPassword, for: profileID)
            }
            if sharedPassword != nil {
                try legacyPasswordStore.remove(for: profileID)
            }
            let keepsSharedSession =
                ((try? await configurationStore.mappings(
                    profileID: profileID
                )) ?? []).isEmpty == false
            if !keepsSharedSession {
                try await sharedSessionStore.remove(for: profileID)
            }
        } catch {
            // 迁移失败时不删除源数据，避免造成凭据丢失。
        }
    }
}

private struct LegacySharedKeychainPasswordStore: Sendable {
    private let accessGroup: String? = Bundle.main.object(
        forInfoDictionaryKey: "LanStashSharedKeychainAccessGroup"
    ) as? String
    private let service =
        "io.github.qwertyuiop1995.dsmnativeclient.shared.password"

    func load(for profileID: UUID) throws -> String? {
        var query = baseQuery(profileID: profileID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainStoreError(status: status)
        }
        return String(data: data, encoding: .utf8)
    }

    func remove(for profileID: UUID) throws {
        let status = SecItemDelete(
            baseQuery(profileID: profileID) as CFDictionary
        )
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError(status: status)
        }
    }

    private func baseQuery(profileID: UUID) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID.uuidString,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
