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
    public let portOverride: Int?
    public let usernameHint: String?
    public let pinnedCertificateSHA256: String?
    public let lastDsmBuild: String?

    public init(
        id: UUID = UUID(),
        displayName: String,
        scheme: NasScheme = .https,
        host: String,
        port: Int,
        portOverride: Int? = nil,
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
        if let portOverride, !(1...65_535).contains(portOverride) {
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
        self.portOverride = portOverride
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
        portOverride: Int? = nil,
        clearPortOverride: Bool = false,
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
            portOverride: clearPortOverride ? nil : (portOverride ?? self.portOverride),
            usernameHint: usernameHint ?? self.usernameHint,
            pinnedCertificateSHA256: clearCertificatePin
                ? nil
                : (pinnedCertificateSHA256 ?? self.pinnedCertificateSHA256),
            lastDsmBuild: lastDsmBuild
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case scheme
        case host
        case port
        case portOverride
        case usernameHint
        case pinnedCertificateSHA256
        case lastDsmBuild
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedPort = try container.decode(Int.self, forKey: .port)
        let decodedOverride: Int?
        if container.contains(.portOverride) {
            decodedOverride = try container.decodeIfPresent(Int.self, forKey: .portOverride)
        } else {
            decodedOverride = decodedPort == 5_001 ? nil : decodedPort
        }
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            displayName: container.decode(String.self, forKey: .displayName),
            scheme: container.decodeIfPresent(NasScheme.self, forKey: .scheme) ?? .https,
            host: container.decode(String.self, forKey: .host),
            port: decodedPort,
            portOverride: decodedOverride,
            usernameHint: container.decodeIfPresent(String.self, forKey: .usernameHint),
            pinnedCertificateSHA256: container.decodeIfPresent(
                String.self,
                forKey: .pinnedCertificateSHA256
            ),
            lastDsmBuild: container.decodeIfPresent(String.self, forKey: .lastDsmBuild)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(scheme, forKey: .scheme)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        if let portOverride {
            try container.encode(portOverride, forKey: .portOverride)
        } else {
            try container.encodeNil(forKey: .portOverride)
        }
        try container.encodeIfPresent(usernameHint, forKey: .usernameHint)
        try container.encodeIfPresent(
            pinnedCertificateSHA256,
            forKey: .pinnedCertificateSHA256
        )
        try container.encodeIfPresent(lastDsmBuild, forKey: .lastDsmBuild)
    }
}
