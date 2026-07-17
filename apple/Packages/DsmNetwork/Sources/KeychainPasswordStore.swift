import DsmCore
import Foundation
import Security

public actor KeychainPasswordStore: PasswordSecureStoring {
    private let service: String
    private let fallbackStore = LocalFileSecureStore()

    private var useKeychain: Bool {
        if UserDefaults.standard.object(forKey: "LanStash_UseKeychainSecureStorage") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "LanStash_UseKeychainSecureStorage")
    }

    public init(service: String = "io.github.qwertyuiop1995.dsmnativeclient.password") {
        self.service = service
    }

    public func save(_ password: String, for profileID: UUID) async throws {
        guard useKeychain else {
            try await fallbackStore.save(password, for: profileID)
            return
        }
        
        do {
            let data = Data(password.utf8)
            let query = baseQuery(for: profileID)
            let status = SecItemUpdate(
                query as CFDictionary,
                [kSecValueData: data] as CFDictionary
            )
            if status == errSecSuccess {
                return
            }
            guard status == errSecItemNotFound else {
                throw KeychainSessionStoreError.operationFailed(status: status)
            }

            var addQuery = query
            addQuery[kSecValueData] = data
            addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainSessionStoreError.operationFailed(status: addStatus)
            }
        } catch {
            try await fallbackStore.save(password, for: profileID)
        }
    }

    public func load(for profileID: UUID) async throws -> String? {
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
            guard status == errSecSuccess,
                  let data = result as? Data,
                  let password = String(data: data, encoding: .utf8) else {
                throw KeychainSessionStoreError.invalidStoredValue
            }
            return password
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
