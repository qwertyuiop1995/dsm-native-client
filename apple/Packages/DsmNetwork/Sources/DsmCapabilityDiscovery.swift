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
    public static let fileStationCreateFolder = "SYNO.FileStation.CreateFolder"
    public static let fileStationRename = "SYNO.FileStation.Rename"
    public static let fileStationCopyMove = "SYNO.FileStation.CopyMove"
    public static let fileStationCompress = "SYNO.FileStation.Compress"
    public static let fileStationExtract = "SYNO.FileStation.Extract"
    public static let fileStationSearch = "SYNO.FileStation.Search"
    public static let fileStationFavorite = "SYNO.FileStation.Favorite"
    public static let fileStationSharing = "SYNO.FileStation.Sharing"
    public static let fileStationVirtualFolder = "SYNO.FileStation.VirtualFolder"
    /// DSM File Station 的未公开挂载接口；只在能力发现明确返回时启用。
    public static let fileStationMount = "SYNO.FileStation.Mount"
    /// Synology Chat 套件内部接口；仅在 DSM 能力发现明确返回时启用。
    public static let chatChannel = "SYNO.Chat.Channel"
    /// Synology Chat 命名会话内部接口；用于创建群聊和邀请成员。
    public static let chatChannelNamed = "SYNO.Chat.Channel.Named"
    /// Synology Chat 匿名会话内部接口；用于首次创建一对一会话。
    public static let chatChannelAnonymous = "SYNO.Chat.Channel.Anonymous"
    /// Synology Chat 用户目录内部接口。
    public static let chatUser = "SYNO.Chat.User"
    /// Synology Chat 用户头像内部接口；仅用于读取当前账号可见的头像。
    public static let chatUserAvatar = "SYNO.Chat.User.Avatar"
    /// Synology Chat 消息内部接口。
    public static let chatPost = "SYNO.Chat.Post"
    /// Synology Chat 附件读取内部接口；当前只登记能力，不在界面暴露协议细节。
    public static let chatPostFile = "SYNO.Chat.Post.File"
    /// Synology Chat 消息提醒内部接口。
    public static let chatPostReminder = "SYNO.Chat.Post.Reminder"
    /// Synology Chat 投票内部接口。
    public static let chatPostVote = "SYNO.Chat.Post.Vote"
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
        DsmAPIName.fileStationCreateFolder,
        DsmAPIName.fileStationRename,
        DsmAPIName.fileStationCopyMove,
        DsmAPIName.fileStationCompress,
        DsmAPIName.fileStationExtract,
        DsmAPIName.fileStationSearch,
        DsmAPIName.fileStationFavorite,
        DsmAPIName.fileStationSharing,
        DsmAPIName.fileStationVirtualFolder,
        DsmAPIName.fileStationMount,
        DsmAPIName.chatChannel,
        DsmAPIName.chatChannelNamed,
        DsmAPIName.chatChannelAnonymous,
        DsmAPIName.chatUser,
        DsmAPIName.chatUserAvatar,
        DsmAPIName.chatPost,
        DsmAPIName.chatPostFile,
        DsmAPIName.chatPostReminder,
        DsmAPIName.chatPostVote
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
                    safeUserMessage: "NAS 返回的信息无法读取，请确认 DSM 已更新到受支持版本。"
                )
            }

            var capability = ApiCapability(
                name: name,
                path: path,
                minVersion: payload.minVersion,
                maxVersion: payload.maxVersion,
                requestFormat: payload.requestFormat
            )

            if let supportedRange = Self.supportedRanges[name] {
                capability = (try? capability.selectingVersion(in: supportedRange)) ?? capability
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

    private static let supportedRanges: [String: ClosedRange<Int>] = [
        DsmAPIName.authentication: 3...6,
        DsmAPIName.fileStationInfo: 1...2,
        DsmAPIName.fileStationList: 1...2,
        DsmAPIName.fileStationThumbnail: 1...2,
        DsmAPIName.fileStationCheckPermission: 1...3,
        DsmAPIName.fileStationDownload: 1...2,
        DsmAPIName.fileStationUpload: 1...2,
        DsmAPIName.fileStationDelete: 1...2,
        DsmAPIName.fileStationCreateFolder: 1...2,
        DsmAPIName.fileStationRename: 1...2,
        DsmAPIName.fileStationCopyMove: 1...3,
        DsmAPIName.fileStationCompress: 3...3,
        DsmAPIName.fileStationExtract: 2...2,
        DsmAPIName.fileStationSearch: 1...2,
        DsmAPIName.fileStationFavorite: 1...2,
        DsmAPIName.fileStationSharing: 1...3,
        DsmAPIName.fileStationVirtualFolder: 1...2,
        DsmAPIName.fileStationMount: 1...1,
        // Chat Server 没有公开普通用户聊天契约，范围按运行时返回值与已验证实现取交集。
        DsmAPIName.chatChannel: 1...5,
        DsmAPIName.chatChannelNamed: 1...1,
        DsmAPIName.chatChannelAnonymous: 1...2,
        DsmAPIName.chatUser: 1...3,
        DsmAPIName.chatUserAvatar: 1...1,
        DsmAPIName.chatPost: 1...8,
        DsmAPIName.chatPostFile: 1...2,
        DsmAPIName.chatPostReminder: 1...1,
        DsmAPIName.chatPostVote: 1...1
    ]
}
