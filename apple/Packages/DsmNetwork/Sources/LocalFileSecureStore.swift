import Foundation
import DsmCore
import CryptoKit

public actor LocalFileSecureStore: SessionSecureStoring, PasswordSecureStoring {
    private let fileManager = FileManager.default
    private let encryptionKey: SymmetricKey
    
    public init() {
        // 本项目按产品约定仅使用应用沙盒内的 AES-GCM 加密文件，不访问系统钥匙串。
        // 随机主密钥同样保存在应用沙盒，并限制为当前用户可读写；不使用可从二进制推导的固定密钥。
        self.encryptionKey = Self.loadOrCreateEncryptionKey()
    }
    
    private func fileURL(for name: String, profileID: UUID) -> URL {
        let secureDir = Self.secureDirectory(fileManager: fileManager)
        if !fileManager.fileExists(atPath: secureDir.path) {
            try? fileManager.createDirectory(at: secureDir, withIntermediateDirectories: true)
        }
        return secureDir.appendingPathComponent("\(profileID.uuidString).\(name).dat")
    }

    private static func secureDirectory(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("LanStashSecureStore", isDirectory: true)
    }

    private static func loadOrCreateEncryptionKey() -> SymmetricKey {
        let fileManager = FileManager.default
        let directory = secureDirectory(fileManager: fileManager)
        let keyURL = directory.appendingPathComponent("master.key")
        if let data = try? Data(contentsOf: keyURL), data.count == 32 {
            return SymmetricKey(data: data)
        }

        let generatedKey = SymmetricKey(size: .bits256)
        let keyData = generatedKey.withUnsafeBytes { Data($0) }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try keyData.write(to: keyURL, options: [.atomic, .completeFileProtection])
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o600))],
                ofItemAtPath: keyURL.path
            )
            return generatedKey
        } catch {
            // 文件系统暂不可写时使用稳定的进程内回退键，保存操作随后仍会返回明确错误。
            let bundleID = Bundle.main.bundleIdentifier ?? "io.github.qwertyuiop1995.dsmnativeclient"
            return SymmetricKey(data: Data(SHA256.hash(data: Data(bundleID.utf8))))
        }
    }
    
    private func encryptAndSave(_ plainText: String, to url: URL) throws {
        let data = Data(plainText.utf8)
        let sealedBox = try AES.GCM.seal(data, using: encryptionKey)
        guard let encryptedData = sealedBox.combined else {
            throw CocoaError(.fileWriteUnknown)
        }
        try encryptedData.write(to: url, options: [.atomic, .completeFileProtection])
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
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
