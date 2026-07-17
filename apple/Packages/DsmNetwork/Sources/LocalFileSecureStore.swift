import Foundation
import DsmCore
import CryptoKit

public actor LocalFileSecureStore: SessionSecureStoring, PasswordSecureStoring {
    private let fileManager = FileManager.default
    private let encryptionKey: SymmetricKey
    
    public init() {
        // 注意：当前使用硬编码 Salt 与 Bundle ID 派生密钥，仅提供混淆保护，
        // 不满足长期安全存储要求。后续应改为在 Keychain 中保存随机生成的
        // 主密钥，或仅在 Keychain 不可用时降级为不保存敏感数据。
        let salt = "LanStashSecureLocalSalt2026"
        let bundleID = Bundle.main.bundleIdentifier ?? "io.github.qwertyuiop1995.dsmnativeclient"
        let combined = "\(salt)\(bundleID)"
        let hash = SHA256.hash(data: Data(combined.utf8))
        self.encryptionKey = SymmetricKey(data: Data(hash))
    }
    
    private func fileURL(for name: String, profileID: UUID) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let secureDir = appSupport.appendingPathComponent("LanStashSecureStore", isDirectory: true)
        if !fileManager.fileExists(atPath: secureDir.path) {
            try? fileManager.createDirectory(at: secureDir, withIntermediateDirectories: true)
        }
        return secureDir.appendingPathComponent("\(profileID.uuidString).\(name).dat")
    }
    
    private func encryptAndSave(_ plainText: String, to url: URL) throws {
        let data = Data(plainText.utf8)
        let sealedBox = try AES.GCM.seal(data, using: encryptionKey)
        guard let encryptedData = sealedBox.combined else {
            throw CocoaError(.fileWriteUnknown)
        }
        try encryptedData.write(to: url, options: .atomic)
    }
    
    private func loadAndDecrypt(from url: URL) throws -> String? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let encryptedData = try Data(contentsOf: url)
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: encryptionKey)
        return String(data: decryptedData, encoding: .utf8)
    }
    
    // MARK: - SessionSecureStoring
    
    public func save(_ session: AuthSession, for profileID: UUID) async throws {
        let url = fileURL(for: "session", profileID: profileID)
        let json = try JSONEncoder().encode(session)
        if let jsonString = String(data: json, encoding: .utf8) {
            try encryptAndSave(jsonString, to: url)
        }
    }
    
    public func load(for profileID: UUID) async throws -> AuthSession? {
        let url = fileURL(for: "session", profileID: profileID)
        guard let decrypted = try? loadAndDecrypt(from: url),
              let data = decrypted.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }
    
    // MARK: - PasswordSecureStoring
    
    public func save(_ password: String, for profileID: UUID) async throws {
        let url = fileURL(for: "password", profileID: profileID)
        try encryptAndSave(password, to: url)
    }
    
    public func load(for profileID: UUID) async throws -> String? {
        let url = fileURL(for: "password", profileID: profileID)
        return try? loadAndDecrypt(from: url)
    }
    
    // MARK: - Combined Removal for protocols
    
    public func remove(for profileID: UUID) async throws {
        let sessionUrl = fileURL(for: "session", profileID: profileID)
        let passwordUrl = fileURL(for: "password", profileID: profileID)
        try? fileManager.removeItem(at: sessionUrl)
        try? fileManager.removeItem(at: passwordUrl)
    }
}
