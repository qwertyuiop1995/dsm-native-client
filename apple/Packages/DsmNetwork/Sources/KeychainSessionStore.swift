import DsmCore
import Foundation
import Security

enum KeychainSessionStoreError: Error, Sendable {
    case operationFailed(status: OSStatus)
    case invalidStoredValue
}

public actor KeychainSessionStore: SessionSecureStoring {
    private let service: String
    private let fallbackStore = LocalFileSecureStore()

    private var useKeychain: Bool {
        if UserDefaults.standard.object(forKey: "LanStash_UseKeychainSecureStorage") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "LanStash_UseKeychainSecureStorage")
    }

    public init(service: String = "io.github.qwertyuiop1995.dsmnativeclient.session") {
        self.service = service
    }

    public func save(_ session: AuthSession, for profileID: UUID) async throws {
        guard useKeychain else {
            try await fallbackStore.save(session, for: profileID)
            return
        }
        
        do {
            let data = try JSONEncoder().encode(session)
            let query = baseQuery(for: profileID)
            let update: [CFString: Any] = [kSecValueData: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)

            if updateStatus == errSecSuccess {
                return
            }
            guard updateStatus == errSecItemNotFound else {
                throw KeychainSessionStoreError.operationFailed(status: updateStatus)
            }

            var addQuery = query
            addQuery[kSecValueData] = data
            addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainSessionStoreError.operationFailed(status: addStatus)
            }
        } catch {
            try await fallbackStore.save(session, for: profileID)
        }
    }

    public func load(for profileID: UUID) async throws -> AuthSession? {
        guard useKeychain else {
            return try await fallbackStore.load(for: profileID)
        }
        
        do {
            var query = baseQuery(for: profileID)
            query[kSecReturnData] = true
            query[kSecMatchLimit] = kSecMatchLimitOne

            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound {
                return try await fallbackStore.load(for: profileID)
            }
            guard status == errSecSuccess, let data = result as? Data else {
                throw KeychainSessionStoreError.operationFailed(status: status)
            }

            do {
                return try JSONDecoder().decode(AuthSession.self, from: data)
            } catch {
                throw KeychainSessionStoreError.invalidStoredValue
            }
        } catch {
            return try await fallbackStore.load(for: profileID)
        }
    }

    public func remove(for profileID: UUID) async throws {
        try? await fallbackStore.remove(for: profileID)
        
        guard useKeychain else { return }
        let status = SecItemDelete(baseQuery(for: profileID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSessionStoreError.operationFailed(status: status)
        }
    }

    private func baseQuery(for profileID: UUID) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: profileID.uuidString
        ]
    }
}
