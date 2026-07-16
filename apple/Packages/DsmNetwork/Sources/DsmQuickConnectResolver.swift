import DsmCore
import Foundation

public struct QuickConnectEndpoint: Equatable, Sendable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }
}

public enum QuickConnectResolutionError: Error, Equatable, Sendable {
    case notFound
    case offline
    case noDirectRoute
    case serviceUnavailable
    case invalidResponse
}

extension QuickConnectResolutionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notFound:
            "没有找到这个 QuickConnect ID，请检查拼写和 NAS 中的 QuickConnect 设置。"
        case .offline:
            "QuickConnect 找到了这台 NAS，但设备目前不在线。"
        case .noDirectRoute:
            "QuickConnect 暂时无法建立直连。请确认 Mac 与 NAS 位于同一网络，或改用 NAS 的 IP 和域名。"
        case .serviceUnavailable:
            "QuickConnect 暂时没有响应，请稍后重试。"
        case .invalidResponse:
            "QuickConnect 返回的信息无法读取，请稍后重试。"
        }
    }
}

public protocol QuickConnectResolving: Sendable {
    func resolve(id: String) async throws -> QuickConnectEndpoint
}

private struct QuickConnectCommand: Encodable {
    let version = 1
    let command = "get_server_info"
    let stopWhenError = false
    let stopWhenSuccess = false
    let id = "mainapp_https"
    let serverID: String
    let isGofile = false
    let path = ""

    private enum CodingKeys: String, CodingKey {
        case version
        case command
        case stopWhenError = "stop_when_error"
        case stopWhenSuccess = "stop_when_success"
        case id
        case serverID
        case isGofile = "is_gofile"
        case path
    }
}

private struct QuickConnectResponse: Decodable {
    let errno: Int
    let server: Server?
    let service: Service?
    let smartDNS: SmartDNS?

    struct Server: Decodable {
        let state: String?

        private enum CodingKeys: String, CodingKey {
            case state = "ds_state"
        }
    }

    struct Service: Decodable {
        let port: Int?
    }

    struct SmartDNS: Decodable {
        let host: String?
        let lan: [String]?
    }

    private enum CodingKeys: String, CodingKey {
        case errno
        case server
        case service
        case smartDNS = "smartdns"
    }
}

public actor DsmQuickConnectResolver: QuickConnectResolving {
    private let session: URLSession
    private let controlURLs: [URL]
    private let maximumResponseBytes = 1_024 * 1_024

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)

        let isChina = Locale.current.region?.identifier.uppercased() == "CN"
        let domains = isChina
            ? ["global.quickconnect.cn", "global.quickconnect.to"]
            : ["global.quickconnect.to", "global.quickconnect.cn"]
        controlURLs = domains.compactMap { URL(string: "https://\($0)/Serv.php") }
    }

    public func resolve(id: String) async throws -> QuickConnectEndpoint {
        guard NasAddressParser.isPotentialQuickConnectID(id) else {
            throw QuickConnectResolutionError.notFound
        }

        let body = try JSONEncoder().encode([QuickConnectCommand(serverID: id)])
        var lastError: Error = QuickConnectResolutionError.serviceUnavailable

        for controlURL in controlURLs {
            do {
                var request = URLRequest(url: controlURL)
                request.httpMethod = "POST"
                request.timeoutInterval = 10
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.httpBody = body

                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    throw QuickConnectResolutionError.serviceUnavailable
                }
                guard data.count <= maximumResponseBytes else {
                    throw QuickConnectResolutionError.invalidResponse
                }
                return try Self.decodeEndpoint(from: data)
            } catch let error as QuickConnectResolutionError {
                lastError = error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = QuickConnectResolutionError.serviceUnavailable
            }
        }

        throw lastError
    }

    static func decodeEndpoint(from data: Data) throws -> QuickConnectEndpoint {
        let responses: [QuickConnectResponse]
        do {
            responses = try JSONDecoder().decode([QuickConnectResponse].self, from: data)
        } catch {
            throw QuickConnectResolutionError.invalidResponse
        }

        guard let response = responses.first(where: { $0.errno == 0 }) else {
            throw QuickConnectResolutionError.notFound
        }
        guard response.server?.state?.uppercased() == "CONNECTED" else {
            throw QuickConnectResolutionError.offline
        }
        guard let port = response.service?.port,
              (1...65_535).contains(port) else {
            throw QuickConnectResolutionError.noDirectRoute
        }

        let candidates = (response.smartDNS?.lan ?? []) + [response.smartDNS?.host].compactMap { $0 }
        guard let host = candidates
            .map({ $0.lowercased() })
            .first(where: Self.isTrustedDirectHost) else {
            throw QuickConnectResolutionError.noDirectRoute
        }
        return QuickConnectEndpoint(host: host, port: port)
    }

    private static func isTrustedDirectHost(_ host: String) -> Bool {
        host.hasSuffix(".direct.quickconnect.cn")
            || host.hasSuffix(".direct.quickconnect.to")
    }
}
