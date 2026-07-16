import Foundation

public enum NasScheme: String, Codable, Sendable {
    case https
}

public enum NasProfileValidationError: Error, Equatable, Sendable {
    case emptyDisplayName
    case invalidHost
    case invalidPort
}

extension NasProfileValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyDisplayName:
            "请输入设备显示名称。"
        case .invalidHost:
            "请输入不含协议、端口和路径的 NAS 主机名或 IP。"
        case .invalidPort:
            "端口必须位于 1 到 65535 之间。"
        }
    }
}

public struct NasProfile: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let displayName: String
    public let scheme: NasScheme
    public let host: String
    public let port: Int
    public let lastDsmBuild: String?

    public init(
        id: UUID = UUID(),
        displayName: String,
        scheme: NasScheme = .https,
        host: String,
        port: Int,
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

        self.id = id
        self.displayName = normalizedName
        self.scheme = scheme
        self.host = normalizedHost
        self.port = port
        self.lastDsmBuild = lastDsmBuild
    }
}
