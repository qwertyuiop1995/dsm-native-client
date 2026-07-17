import Foundation

public enum NasAddressKind: Equatable, Sendable {
    case direct
    case quickConnect
}

public struct ParsedNasAddress: Equatable, Sendable {
    public let host: String
    public let port: Int
    public let kind: NasAddressKind
    public let hasExplicitPort: Bool

    public init(
        host: String,
        port: Int,
        kind: NasAddressKind,
        hasExplicitPort: Bool = false
    ) {
        self.host = host
        self.port = port
        self.kind = kind
        self.hasExplicitPort = hasExplicitPort
    }
}

public enum NasAddressInputError: Error, Equatable, Sendable {
    case empty
    case invalid
    case insecure
}

extension NasAddressInputError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .empty:
            "请输入 NAS 地址或 QuickConnect ID。"
        case .invalid:
            "无法识别这个地址。你可以粘贴浏览器中的完整地址，或输入 IP、域名和 QuickConnect ID。"
        case .insecure:
            "为了保护登录信息，请使用 HTTPS 地址。"
        }
    }
}

public enum NasAddressParser {
    public static func parse(_ input: String, defaultPort: Int) throws -> ParsedNasAddress {
        guard (1...65_535).contains(defaultPort) else {
            throw NasAddressInputError.invalid
        }

        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NasAddressInputError.empty
        }

        let hasExplicitScheme = trimmed.contains("://")
        let value = hasExplicitScheme ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: value),
              let rawHost = components.host,
              !rawHost.isEmpty,
              components.user == nil,
              components.password == nil else {
            throw NasAddressInputError.invalid
        }

        let host = rawHost.lowercased()
        if let quickConnectID = quickConnectID(host: host, path: components.path) {
            guard isPotentialQuickConnectID(quickConnectID) else {
                throw NasAddressInputError.invalid
            }
            return ParsedNasAddress(
                host: quickConnectID,
                port: 5_001,
                kind: .quickConnect,
                hasExplicitPort: false
            )
        }

        guard components.scheme?.lowercased() == "https" else {
            throw NasAddressInputError.insecure
        }

        let port = components.port ?? (hasExplicitScheme ? 443 : defaultPort)
        guard (1...65_535).contains(port) else {
            throw NasAddressInputError.invalid
        }

        return ParsedNasAddress(
            host: host,
            port: port,
            kind: isPotentialQuickConnectID(host) ? .quickConnect : .direct,
            hasExplicitPort: components.port != nil
        )
    }

    public static func isPotentialQuickConnectID(_ value: String) -> Bool {
        guard (1...64).contains(value.count),
              !value.contains("."),
              !value.contains(":"),
              value.first != "-",
              value.last != "-" else {
            return false
        }
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-"
        )
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func quickConnectID(host: String, path: String) -> String? {
        let portalHosts = ["quickconnect.cn", "quickconnect.to"]
        if portalHosts.contains(host) {
            return path.split(separator: "/").first.map(String.init)?.lowercased()
        }

        for suffix in portalHosts {
            let expectedSuffix = ".\(suffix)"
            if host.hasSuffix(expectedSuffix),
               host.split(separator: ".").count == 3 {
                return String(host.dropLast(expectedSuffix.count)).lowercased()
            }
        }
        return nil
    }
}
