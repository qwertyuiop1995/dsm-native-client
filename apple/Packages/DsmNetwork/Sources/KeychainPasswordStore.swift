import DsmCore
import Foundation
import Security

public actor KeychainPasswordStore: PasswordSecureStoring {
    private let service: String

    public init(service: String = "io.github.qwertyuiop1995.dsmnativeclient.password") {
        self.service = service
    }

    public func save(_ password: String, for profileID: UUID) async throws {
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
    }

    public func load(for profileID: UUID) async throws -> String? {
        var query = baseQuery(for: profileID)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw KeychainSessionStoreError.invalidStoredValue
        }
        return password
    }

    public func remove(for profileID: UUID) async throws {
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
