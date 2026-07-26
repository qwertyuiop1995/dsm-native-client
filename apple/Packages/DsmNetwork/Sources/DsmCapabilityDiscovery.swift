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
    /// Synology Chat 会话成员内部接口；用于读取当前账号可见的群成员。
    public static let chatChannelMember = "SYNO.Chat.Channel.Member"
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
    /// Synology Chat 定时消息内部接口。
    public static let chatPostSchedule = "SYNO.Chat.Post.Schedule"
    // 以下均为 DSM 内部只读接口，仅在能力发现明确返回时使用。
    public static let coreSystem = "SYNO.Core.System"
    public static let coreSystemUtilization = "SYNO.Core.System.Utilization"
    public static let storageOverview = "SYNO.Storage.CGI.Storage"
    public static let storageSmart = "SYNO.Storage.CGI.Smart"
    public static let storageVolume = "SYNO.Core.Storage.Volume"
    /// DSM 存储管理器内部硬盘检测接口；仅在能力发现明确返回时启用。
    public static let coreStorageDisk = "SYNO.Core.Storage.Disk"
    public static let corePackage = "SYNO.Core.Package"
    /// DSM 套件启停内部接口。
    public static let corePackageControl = "SYNO.Core.Package.Control"
    /// DSM 套件卸载内部接口。
    public static let corePackageUninstallation = "SYNO.Core.Package.Uninstallation"
    /// DSM 已安装套件图标内部接口。
    public static let corePackageThumb = "SYNO.Core.Package.Thumb"
    public static let coreTaskScheduler = "SYNO.Core.TaskScheduler"
    /// DSM 计划任务运行结果内部接口。
    public static let coreEventScheduler = "SYNO.Core.EventScheduler"
    /// DSM 系统更新检查内部接口；客户端只读取可用更新，不执行下载或安装。
    public static let coreUpgradeServer = "SYNO.Core.Upgrade.Server"
    public static let coreUser = "SYNO.Core.User"
    public static let coreGroup = "SYNO.Core.Group"
    public static let coreCurrentConnection = "SYNO.Core.CurrentConnection"
    public static let coreSystemLog = "SYNO.Core.SyslogClient.Log"
    public static let logCenterHistory = "SYNO.LogCenter.History"
    /// DSM 控制面板内部接口：终端服务。
    public static let coreTerminal = "SYNO.Core.Terminal"
    /// DSM 控制面板内部接口：SMB 文件服务。
    public static let coreFileServiceSMB = "SYNO.Core.FileServ.SMB"
    /// DSM 控制面板内部接口：NFS 文件服务。
    public static let coreFileServiceNFS = "SYNO.Core.FileServ.NFS"
    /// DSM 控制面板内部接口：FTP/FTPS 文件服务。
    public static let coreFileServiceFTP = "SYNO.Core.FileServ.FTP"
    /// DSM 控制面板内部接口：SFTP 文件服务。
    public static let coreFileServiceSFTP = "SYNO.Core.FileServ.FTP.SFTP"
    /// DSM 控制面板内部接口：互联网代理。
    public static let coreNetworkProxy = "SYNO.Core.Network.Proxy"
    /// DSM 控制面板内部接口：断电恢复。
    public static let coreHardwarePowerRecovery = "SYNO.Core.Hardware.PowerRecovery"
    /// DSM 控制面板内部接口：设备灯光亮度。
    public static let coreHardwareLEDBrightness = "SYNO.Core.Hardware.Led.Brightness"
    /// DSM 控制面板内部接口：风扇模式。
    public static let coreHardwareFanSpeed = "SYNO.Core.Hardware.FanSpeed"
    /// DSM 控制面板内部接口：设备提示音。
    public static let coreHardwareBeepControl = "SYNO.Core.Hardware.BeepControl"
    /// DSM 控制面板内部接口：硬盘休眠与自动关机。
    public static let coreHardwareHibernation = "SYNO.Core.Hardware.Hibernation"
    /// DSM 控制面板内部接口：QuickConnect 基础设置。
    public static let coreQuickConnect = "SYNO.Core.QuickConnect"
    /// DSM 控制面板内部接口：QuickConnect 路由器自动配置。
    public static let coreQuickConnectUPnP = "SYNO.Core.QuickConnect.Upnp"
    /// DSM 控制面板内部接口：登录失败自动封锁。
    public static let coreSecurityAutoBlock = "SYNO.Core.Security.AutoBlock"
    /// DSM 控制面板内部接口：局域网设备发现。
    public static let coreWebDSM = "SYNO.Core.Web.DSM"
    /// DSM 控制面板内部接口：文件服务发现。
    public static let coreFileServiceDiscovery = "SYNO.Core.FileServ.ServiceDiscovery"
    /// DSM 控制面板内部接口：网卡列表。
    public static let coreNetworkEthernet = "SYNO.Core.Network.Ethernet"
    /// DSM 控制面板内部接口：按网卡配置拒绝服务攻击防护。
    public static let coreSecurityDoS = "SYNO.Core.Security.DoS"
    /// DSM 控制面板内部接口：区域、时区与网络校时。
    public static let coreRegionNTP = "SYNO.Core.Region.NTP"
    /// DSM 控制面板内部接口：DDNS 服务提供商与记录。
    public static let coreDDNSProvider = "SYNO.Core.DDNS.Provider"
    public static let coreDDNSRecord = "SYNO.Core.DDNS.Record"
    /// DSM 控制面板内部接口：UPS 安全关机设置。
    public static let coreExternalDeviceUPS = "SYNO.Core.ExternalDevice.UPS"
    /// DSM 控制面板内部接口：防火墙启停、端口扫描防护与配置应用。
    public static let coreSecurityFirewall = "SYNO.Core.Security.Firewall"
    public static let coreSecurityFirewallConf = "SYNO.Core.Security.Firewall.Conf"
    public static let coreSecurityFirewallProfileApply =
        "SYNO.Core.Security.Firewall.Profile.Apply"
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
        DsmAPIName.chatChannelMember,
        DsmAPIName.chatUser,
        DsmAPIName.chatUserAvatar,
        DsmAPIName.chatPost,
        DsmAPIName.chatPostFile,
        DsmAPIName.chatPostReminder,
        DsmAPIName.chatPostVote,
        DsmAPIName.chatPostSchedule,
        DsmAPIName.coreSystem,
        DsmAPIName.coreSystemUtilization,
        DsmAPIName.storageOverview,
        DsmAPIName.storageSmart,
        DsmAPIName.storageVolume,
        DsmAPIName.coreStorageDisk,
        DsmAPIName.corePackage,
        DsmAPIName.corePackageControl,
        DsmAPIName.corePackageUninstallation,
        DsmAPIName.corePackageThumb,
        DsmAPIName.coreTaskScheduler,
        DsmAPIName.coreEventScheduler,
        DsmAPIName.coreUpgradeServer,
        DsmAPIName.coreUser,
        DsmAPIName.coreGroup,
        DsmAPIName.coreCurrentConnection,
        DsmAPIName.coreSystemLog,
        DsmAPIName.logCenterHistory,
        DsmAPIName.coreTerminal,
        DsmAPIName.coreFileServiceSMB,
        DsmAPIName.coreFileServiceNFS,
        DsmAPIName.coreFileServiceFTP,
        DsmAPIName.coreFileServiceSFTP,
        DsmAPIName.coreNetworkProxy,
        DsmAPIName.coreHardwarePowerRecovery,
        DsmAPIName.coreHardwareLEDBrightness,
        DsmAPIName.coreHardwareFanSpeed,
        DsmAPIName.coreHardwareBeepControl,
        DsmAPIName.coreHardwareHibernation,
        DsmAPIName.coreQuickConnect,
        DsmAPIName.coreQuickConnectUPnP,
        DsmAPIName.coreSecurityAutoBlock,
        DsmAPIName.coreWebDSM,
        DsmAPIName.coreFileServiceDiscovery,
        DsmAPIName.coreNetworkEthernet,
        DsmAPIName.coreSecurityDoS,
        DsmAPIName.coreRegionNTP,
        DsmAPIName.coreDDNSProvider,
        DsmAPIName.coreDDNSRecord,
        DsmAPIName.coreExternalDeviceUPS,
        DsmAPIName.coreSecurityFirewall,
        DsmAPIName.coreSecurityFirewallConf,
        DsmAPIName.coreSecurityFirewallProfileApply
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
        DsmAPIName.chatChannelMember: 1...1,
        DsmAPIName.chatUser: 1...3,
        DsmAPIName.chatUserAvatar: 1...1,
        DsmAPIName.chatPost: 1...8,
        DsmAPIName.chatPostFile: 1...2,
        DsmAPIName.chatPostReminder: 1...1,
        DsmAPIName.chatPostVote: 1...1,
        DsmAPIName.chatPostSchedule: 1...1,
        // 内部接口版本以运行时能力发现为准；这里仅限制已知的兼容区间。
        DsmAPIName.coreSystem: 1...3,
        DsmAPIName.coreSystemUtilization: 1...1,
        DsmAPIName.storageOverview: 1...1,
        DsmAPIName.storageSmart: 1...1,
        DsmAPIName.storageVolume: 1...1,
        DsmAPIName.coreStorageDisk: 1...1,
        DsmAPIName.corePackage: 1...2,
        DsmAPIName.corePackageControl: 1...1,
        DsmAPIName.corePackageUninstallation: 1...1,
        DsmAPIName.corePackageThumb: 1...1,
        DsmAPIName.coreTaskScheduler: 1...4,
        DsmAPIName.coreEventScheduler: 1...1,
        DsmAPIName.coreUpgradeServer: 1...4,
        DsmAPIName.coreUser: 1...1,
        DsmAPIName.coreGroup: 1...1,
        DsmAPIName.coreCurrentConnection: 1...1,
        DsmAPIName.coreSystemLog: 1...1,
        DsmAPIName.logCenterHistory: 1...1,
        DsmAPIName.coreTerminal: 1...3,
        DsmAPIName.coreFileServiceSMB: 1...3,
        DsmAPIName.coreFileServiceNFS: 1...3,
        DsmAPIName.coreFileServiceFTP: 1...1,
        DsmAPIName.coreFileServiceSFTP: 1...1,
        DsmAPIName.coreNetworkProxy: 1...1,
        DsmAPIName.coreHardwarePowerRecovery: 1...1,
        DsmAPIName.coreHardwareLEDBrightness: 1...1,
        DsmAPIName.coreHardwareFanSpeed: 1...1,
        DsmAPIName.coreHardwareBeepControl: 1...1,
        DsmAPIName.coreHardwareHibernation: 1...1,
        DsmAPIName.coreQuickConnect: 1...3,
        DsmAPIName.coreQuickConnectUPnP: 1...1,
        DsmAPIName.coreSecurityAutoBlock: 1...1,
        DsmAPIName.coreWebDSM: 1...2,
        DsmAPIName.coreFileServiceDiscovery: 1...1,
        DsmAPIName.coreNetworkEthernet: 1...2,
        DsmAPIName.coreSecurityDoS: 1...2,
        DsmAPIName.coreRegionNTP: 1...3,
        DsmAPIName.coreDDNSProvider: 1...1,
        DsmAPIName.coreDDNSRecord: 1...1,
        DsmAPIName.coreExternalDeviceUPS: 1...1,
        DsmAPIName.coreSecurityFirewall: 1...1,
        DsmAPIName.coreSecurityFirewallConf: 1...1,
        DsmAPIName.coreSecurityFirewallProfileApply: 1...1
    ]
}
