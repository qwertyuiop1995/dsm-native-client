import DsmCore
import Foundation
import Security

actor KeychainSessionStore: SessionSecureStoring {
    private let service = "io.github.qwertyuiop1995.dsmnativeclient.session"

    func save(_ session: AuthSession, for profileID: UUID) async throws {
        let data = try JSONEncoder().encode(session)
        let base = query(profileID)
        SecItemDelete(base as CFDictionary)
        var values = base
        values[kSecValueData as String] = data
        values[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(values as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AppError(
                category: .unknown,
                isRetryable: false,
                safeUserMessage: "无法安全保存登录状态。"
            )
        }
    }

    func load(for profileID: UUID) async throws -> AuthSession? {
        var values = query(profileID)
        values[kSecReturnData as String] = true
        values[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(values as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw AppError(
                category: .authenticationRequired,
                isRetryable: false,
                safeUserMessage: "无法读取保存的登录状态，请重新登录。"
            )
        }
        return try JSONDecoder().decode(AuthSession.self, from: data)
    }

    func remove(for profileID: UUID) async throws {
        let status = SecItemDelete(query(profileID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError(
                category: .unknown,
                isRetryable: false,
                safeUserMessage: "无法删除本机登录状态。"
            )
        }
    }

    private func query(_ profileID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID.uuidString
        ]
    }
}

actor KeychainPasswordStore: PasswordSecureStoring {
    private let service = "io.github.qwertyuiop1995.dsmnativeclient.password"

    func save(_ password: String, for profileID: UUID) async throws {
        let data = Data(password.utf8)
        let base = query(profileID)
        SecItemDelete(base as CFDictionary)
        var values = base
        values[kSecValueData as String] = data
        values[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(values as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AppError(
                category: .unknown,
                isRetryable: false,
                safeUserMessage: "无法安全保存密码，请关闭“记住密码”后重试。"
            )
        }
    }

    func load(for profileID: UUID) async throws -> String? {
        var values = query(profileID)
        values[kSecReturnData as String] = true
        values[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(values as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw AppError(
                category: .unknown,
                isRetryable: false,
                safeUserMessage: "无法读取已保存的密码，请重新输入。"
            )
        }
        return password
    }

    func remove(for profileID: UUID) async throws {
        let status = SecItemDelete(query(profileID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError(
                category: .unknown,
                isRetryable: false,
                safeUserMessage: "无法删除已保存的密码。"
            )
        }
    }

    private func query(_ profileID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID.uuidString
        ]
    }
}
