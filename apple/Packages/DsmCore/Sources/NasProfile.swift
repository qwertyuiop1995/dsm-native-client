import Foundation

public enum NasScheme: String, Codable, Sendable {
    case https
}

public enum NasProfileValidationError: Error, Equatable, Sendable {
    case emptyDisplayName
    case invalidHost
    case invalidPort
    case invalidCertificateFingerprint
}

extension NasProfileValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyDisplayName:
            "请输入设备名称。"
        case .invalidHost:
            "请输入 NAS 地址，例如 192.168.1.20 或 nas.local。地址中不要包含 https://、端口或路径。"
        case .invalidPort:
            "请输入 1 到 65535 之间的端口号。"
        case .invalidCertificateFingerprint:
            "保存的安全信息格式有误，请重新确认这台 NAS。"
        }
    }
}

public struct NasProfile: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let displayName: String
    public let scheme: NasScheme
    public let host: String
    public let port: Int
    public let usernameHint: String?
    public let pinnedCertificateSHA256: String?
    public let lastDsmBuild: String?

    public init(
        id: UUID = UUID(),
        displayName: String,
        scheme: NasScheme = .https,
        host: String,
        port: Int,
        usernameHint: String? = nil,
        pinnedCertificateSHA256: String? = nil,
        lastDsmBuild: String? = nil
    ) throws {
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw NasProfileValidationError.emptyDisplayName
        }

        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let forbidden = CharacterSet(charactersIn: "/?#@")
            .union(.whitespacesAndNewlines)
        guard !normalizedHost.isEmpty,
              normalizedHost.rangeOfCharacter(from: forbidden) == nil,
              !normalizedHost.contains("://") else {
            throw NasProfileValidationError.invalidHost
        }

        guard (1...65_535).contains(port) else {
            throw NasProfileValidationError.invalidPort
        }

        let normalizedUsername = usernameHint?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFingerprint = pinnedCertificateSHA256?
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if let normalizedFingerprint, !normalizedFingerprint.isEmpty {
            let allowed = CharacterSet(charactersIn: "0123456789ABCDEF")
            guard normalizedFingerprint.count == 64,
                  normalizedFingerprint.unicodeScalars.allSatisfy(allowed.contains) else {
                throw NasProfileValidationError.invalidCertificateFingerprint
            }
        }

        self.id = id
        self.displayName = normalizedName
        self.scheme = scheme
        self.host = normalizedHost
        self.port = port
        self.usernameHint = normalizedUsername?.isEmpty == false ? normalizedUsername : nil
        self.pinnedCertificateSHA256 = normalizedFingerprint?.isEmpty == false
            ? normalizedFingerprint
            : nil
        self.lastDsmBuild = lastDsmBuild
    }

    public func updating(
        displayName: String? = nil,
        host: String? = nil,
        port: Int? = nil,
        usernameHint: String? = nil,
        pinnedCertificateSHA256: String? = nil,
        clearCertificatePin: Bool = false
    ) throws -> NasProfile {
        try NasProfile(
            id: id,
            displayName: displayName ?? self.displayName,
            scheme: scheme,
            host: host ?? self.host,
            port: port ?? self.port,
            usernameHint: usernameHint ?? self.usernameHint,
            pinnedCertificateSHA256: clearCertificatePin
                ? nil
                : (pinnedCertificateSHA256 ?? self.pinnedCertificateSHA256),
            lastDsmBuild: lastDsmBuild
        )
    }
}
