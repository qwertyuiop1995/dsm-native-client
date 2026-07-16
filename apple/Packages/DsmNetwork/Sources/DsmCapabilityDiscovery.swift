import DsmCore
import Foundation

public enum DsmAPIName {
    public static let authentication = "SYNO.API.Auth"
    public static let fileStationInfo = "SYNO.FileStation.Info"
    public static let fileStationList = "SYNO.FileStation.List"
    public static let fileStationThumbnail = "SYNO.FileStation.Thumb"
    public static let fileStationCheckPermission = "SYNO.FileStation.CheckPermission"
    public static let fileStationDownload = "SYNO.FileStation.Download"
    public static let fileStationUpload = "SYNO.FileStation.Upload"
    public static let fileStationDelete = "SYNO.FileStation.Delete"
    public static let fileStationCopyMove = "SYNO.FileStation.CopyMove"
}

private struct CapabilityPayload: Decodable, Sendable {
    let path: String
    let minVersion: Int
    let maxVersion: Int
    let requestFormat: DsmRequestFormat

    private enum CodingKeys: String, CodingKey {
        case path
        case minVersion
        case maxVersion
        case requestFormat
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        minVersion = try container.decode(Int.self, forKey: .minVersion)
        maxVersion = try container.decode(Int.self, forKey: .maxVersion)

        let rawFormat = try container.decodeIfPresent(String.self, forKey: .requestFormat)
        requestFormat = DsmRequestFormat(rawValue: rawFormat?.uppercased() ?? "FORM") ?? .form
    }
}

public struct DsmCapabilityDiscovery: Sendable {
    public static let initialAPIs = [
        DsmAPIName.authentication,
        DsmAPIName.fileStationInfo,
        DsmAPIName.fileStationList,
        DsmAPIName.fileStationThumbnail,
        DsmAPIName.fileStationCheckPermission,
        DsmAPIName.fileStationDownload,
        DsmAPIName.fileStationUpload,
        DsmAPIName.fileStationDelete,
        DsmAPIName.fileStationCopyMove
    ]

    private let client: DsmAPIClient
    private let apiNames: [String]

    public init(
        client: DsmAPIClient,
        apiNames: [String] = DsmCapabilityDiscovery.initialAPIs
    ) {
        self.client = client
        self.apiNames = apiNames
    }

    public func discover() async throws -> CapabilitySet {
        do {
            let payloads = try await query(path: "entry.cgi")
            return try makeCapabilitySet(from: payloads)
        } catch let error as DsmNetworkError where Self.shouldUseLegacyEndpoint(after: error) {
            do {
                let payloads = try await query(path: "query.cgi")
                return try makeCapabilitySet(from: payloads)
            } catch let fallbackError as DsmNetworkError {
                throw DsmErrorMapper.map(fallbackError)
            }
        } catch let error as DsmNetworkError {
            throw DsmErrorMapper.map(error)
        }
    }

    private func query(path: String) async throws -> [String: CapabilityPayload] {
        try await client.call(
            path: path,
            api: "SYNO.API.Info",
            version: 1,
            method: "query",
            requestFormat: .form,
            parameters: ["query": .string(apiNames.joined(separator: ","))],
            as: [String: CapabilityPayload].self
        )
    }

    private func makeCapabilitySet(
        from payloads: [String: CapabilityPayload]
    ) throws -> CapabilitySet {
        var capabilities: [String: ApiCapability] = [:]
        for (name, payload) in payloads {
            guard payload.minVersion > 0,
                  payload.maxVersion >= payload.minVersion,
                  let path = DsmEndpoint.normalizeAPIPath(payload.path) else {
                throw AppError(
                    category: .invalidResponse,
                    isRetryable: false,
                    safeUserMessage: "DSM 返回了无效的 API 能力信息。"
                )
            }

            var capability = ApiCapability(
                name: name,
                path: path,
                minVersion: payload.minVersion,
                maxVersion: payload.maxVersion,
                requestFormat: payload.requestFormat
            )

            if name == DsmAPIName.authentication {
                capability = (try? capability.selectingVersion(in: 3...6)) ?? capability
            }
            capabilities[name] = capability
        }
        return CapabilitySet(capabilities)
    }

    private static func shouldUseLegacyEndpoint(after error: DsmNetworkError) -> Bool {
        switch error {
        case .httpStatus(let code, _):
            return code == 404 || code == 410
        case .api(let code, _):
            return code == 102 || code == 103
        default:
            return false
        }
    }
}
