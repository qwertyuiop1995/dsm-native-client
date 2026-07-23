import Foundation

public struct NasSystemOverview: Equatable, Sendable {
    public let serverName: String
    public let model: String?
    public let version: String?
    public let uptimeSeconds: Int64?
    public let cpuModel: String?
    public let cpuCoreCount: Int?
    public let cpuClockMHz: Int?
    public let memoryBytes: Int64?
    public let temperatureCelsius: Double?
    public let hasTemperatureWarning: Bool

    public init(
        serverName: String,
        model: String? = nil,
        version: String? = nil,
        uptimeSeconds: Int64? = nil,
        cpuModel: String? = nil,
        cpuCoreCount: Int? = nil,
        cpuClockMHz: Int? = nil,
        memoryBytes: Int64? = nil,
        temperatureCelsius: Double? = nil,
        hasTemperatureWarning: Bool = false
    ) {
        self.serverName = serverName
        self.model = model
        self.version = version
        self.uptimeSeconds = uptimeSeconds
        self.cpuModel = cpuModel
        self.cpuCoreCount = cpuCoreCount
        self.cpuClockMHz = cpuClockMHz
        self.memoryBytes = memoryBytes
        self.temperatureCelsius = temperatureCelsius
        self.hasTemperatureWarning = hasTemperatureWarning
    }
}

public struct NasPerformanceSnapshot: Identifiable, Equatable, Sendable {
    public let id: Date
    public let recordedAt: Date
    public let cpuUsage: Double
    public let cpuUserUsage: Double
    public let cpuSystemUsage: Double
    public let cpuOtherUsage: Double
    public let memoryUsage: Double
    public let swapUsage: Double
    public let networkReceivedBytesPerSecond: Int64
    public let networkSentBytesPerSecond: Int64
    public let diskReadBytesPerSecond: Int64
    public let diskWriteBytesPerSecond: Int64
    public let volumeReadBytesPerSecond: Int64
    public let volumeWriteBytesPerSecond: Int64
    public let diskUtilization: Double
    public let nfsReadOperationsPerSecond: Int64
    public let nfsWriteOperationsPerSecond: Int64

    public init(
        recordedAt: Date,
        cpuUsage: Double,
        cpuUserUsage: Double,
        cpuSystemUsage: Double,
        cpuOtherUsage: Double,
        memoryUsage: Double,
        swapUsage: Double,
        networkReceivedBytesPerSecond: Int64,
        networkSentBytesPerSecond: Int64,
        diskReadBytesPerSecond: Int64,
        diskWriteBytesPerSecond: Int64,
        volumeReadBytesPerSecond: Int64,
        volumeWriteBytesPerSecond: Int64,
        diskUtilization: Double,
        nfsReadOperationsPerSecond: Int64,
        nfsWriteOperationsPerSecond: Int64
    ) {
        id = recordedAt
        self.recordedAt = recordedAt
        self.cpuUsage = cpuUsage
        self.cpuUserUsage = cpuUserUsage
        self.cpuSystemUsage = cpuSystemUsage
        self.cpuOtherUsage = cpuOtherUsage
        self.memoryUsage = memoryUsage
        self.swapUsage = swapUsage
        self.networkReceivedBytesPerSecond = networkReceivedBytesPerSecond
        self.networkSentBytesPerSecond = networkSentBytesPerSecond
        self.diskReadBytesPerSecond = diskReadBytesPerSecond
        self.diskWriteBytesPerSecond = diskWriteBytesPerSecond
        self.volumeReadBytesPerSecond = volumeReadBytesPerSecond
        self.volumeWriteBytesPerSecond = volumeWriteBytesPerSecond
        self.diskUtilization = diskUtilization
        self.nfsReadOperationsPerSecond = nfsReadOperationsPerSecond
        self.nfsWriteOperationsPerSecond = nfsWriteOperationsPerSecond
    }
}

public struct NasStorageSnapshot: Equatable, Sendable {
    public let overallStatus: String?
    public let disks: [NasDisk]
    public let pools: [NasStoragePool]
    public let volumes: [NasVolume]

    public init(
        overallStatus: String?,
        disks: [NasDisk],
        pools: [NasStoragePool],
        volumes: [NasVolume]
    ) {
        self.overallStatus = overallStatus
        self.disks = disks
        self.pools = pools
        self.volumes = volumes
    }
}

public struct NasDisk: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let model: String?
    public let type: String?
    public let totalBytes: Int64?
    public let status: String?
    public let smartStatus: String?
    public let temperatureCelsius: Double?
    public let isSSD: Bool
    public let usedBy: String?
    public let supportsSmartTest: Bool

    public init(
        id: String,
        name: String,
        model: String?,
        type: String?,
        totalBytes: Int64?,
        status: String?,
        smartStatus: String?,
        temperatureCelsius: Double?,
        isSSD: Bool,
        usedBy: String?,
        supportsSmartTest: Bool
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.type = type
        self.totalBytes = totalBytes
        self.status = status
        self.smartStatus = smartStatus
        self.temperatureCelsius = temperatureCelsius
        self.isSSD = isSSD
        self.usedBy = usedBy
        self.supportsSmartTest = supportsSmartTest
    }
}

public struct NasStoragePool: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let raidType: String?
    public let status: String?
    public let totalBytes: Int64?
    public let usedBytes: Int64?
    public let isWritable: Bool
    public let isScrubbing: Bool
    public let nextScrubbingDate: Date?

    public init(
        id: String,
        name: String,
        raidType: String?,
        status: String?,
        totalBytes: Int64?,
        usedBytes: Int64?,
        isWritable: Bool,
        isScrubbing: Bool,
        nextScrubbingDate: Date?
    ) {
        self.id = id
        self.name = name
        self.raidType = raidType
        self.status = status
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.isWritable = isWritable
        self.isScrubbing = isScrubbing
        self.nextScrubbingDate = nextScrubbingDate
    }
}

public struct NasVolume: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let fileSystem: String?
    public let status: String?
    public let totalBytes: Int64?
    public let usedBytes: Int64?
    public let isEncrypted: Bool
    public let isWritable: Bool

    public init(
        id: String,
        name: String,
        fileSystem: String?,
        status: String?,
        totalBytes: Int64?,
        usedBytes: Int64?,
        isEncrypted: Bool,
        isWritable: Bool
    ) {
        self.id = id
        self.name = name
        self.fileSystem = fileSystem
        self.status = status
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.isEncrypted = isEncrypted
        self.isWritable = isWritable
    }
}

public enum NasPackageAction: String, Sendable {
    case start
    case stop
    case uninstall
    case upgrade
}

public enum NasPowerAction: String, Sendable {
    case shutdown
    case reboot
}

public struct NasSystemUpdateInfo: Equatable, Sendable {
    public let isUpdateAvailable: Bool
    public let currentVersion: String?
    public let latestVersion: String?
    public let releaseNotes: String?

    public init(
        isUpdateAvailable: Bool,
        currentVersion: String? = nil,
        latestVersion: String? = nil,
        releaseNotes: String? = nil
    ) {
        self.isUpdateAvailable = isUpdateAvailable
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.releaseNotes = releaseNotes
    }
}

public struct NasPackage: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let version: String?
    public let status: String?
    public let statusDescription: String?
    public let packageDescription: String?
    public let installType: String?
    public let installedAt: Date?
    public let iconURL: URL?
    public let canStart: Bool
    public let canStop: Bool
    public let canUpgrade: Bool

    public init(
        id: String,
        name: String,
        version: String?,
        status: String?,
        statusDescription: String?,
        packageDescription: String?,
        installType: String?,
        installedAt: Date?,
        iconURL: URL? = nil,
        canStart: Bool = true,
        canStop: Bool = true,
        canUpgrade: Bool = false
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.status = status
        self.statusDescription = statusDescription
        self.packageDescription = packageDescription
        self.installType = installType
        self.installedAt = installedAt
        self.iconURL = iconURL
        self.canStart = canStart
        self.canStop = canStop
        self.canUpgrade = canUpgrade
    }
}

public struct NasScheduledTask: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let owner: String?
    public let type: String?
    public let action: String?
    public let isEnabled: Bool
    public let nextTriggerDescription: String?
    public let canRun: Bool
    public let canEdit: Bool

    public init(
        id: String,
        name: String,
        owner: String?,
        type: String?,
        action: String?,
        isEnabled: Bool,
        nextTriggerDescription: String?,
        canRun: Bool,
        canEdit: Bool
    ) {
        self.id = id
        self.name = name
        self.owner = owner
        self.type = type
        self.action = action
        self.isEnabled = isEnabled
        self.nextTriggerDescription = nextTriggerDescription
        self.canRun = canRun
        self.canEdit = canEdit
    }
}

public struct NasAccountDirectory: Equatable, Sendable {
    public let users: [NasAccount]
    public let groups: [NasAccount]

    public init(users: [NasAccount], groups: [NasAccount]) {
        self.users = users
        self.groups = groups
    }
}

public struct NasAccount: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        case user
        case group
    }

    public let id: String
    public let name: String
    public let kind: Kind
    public let numericID: Int64?
    public let description: String?
    public let email: String?
    public let isExpired: Bool

    public init(
        id: String,
        name: String,
        kind: Kind,
        numericID: Int64?,
        description: String?,
        email: String? = nil,
        isExpired: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.numericID = numericID
        self.description = description
        self.email = email
        self.isExpired = isExpired
    }
}

public struct NasLogPage: Equatable, Sendable {
    public let entries: [NasLogEntry]
    public let total: Int
    public let infoCount: Int?
    public let warningCount: Int?
    public let errorCount: Int?

    public init(
        entries: [NasLogEntry],
        total: Int,
        infoCount: Int?,
        warningCount: Int?,
        errorCount: Int?
    ) {
        self.entries = entries
        self.total = total
        self.infoCount = infoCount
        self.warningCount = warningCount
        self.errorCount = errorCount
    }
}

public struct NasLogEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let date: Date?
    public let source: String?
    public let level: String?
    public let account: String?
    public let message: String

    public init(
        id: String,
        date: Date?,
        source: String?,
        level: String?,
        account: String?,
        message: String
    ) {
        self.id = id
        self.date = date
        self.source = source
        self.level = level
        self.account = account
        self.message = message
    }
}

public struct NasConnectionPage: Equatable, Sendable {
    public let connections: [NasConnection]
    public let total: Int

    public init(connections: [NasConnection], total: Int) {
        self.connections = connections
        self.total = total
    }
}

public struct NasConnection: Identifiable, Equatable, Sendable {
    public let id: String
    public let account: String
    public let source: String?
    public let location: String?
    public let protocolName: String?
    public let type: String?
    public let connectedAt: Date?
    public let description: String?
    public let isCurrentConnection: Bool

    public init(
        id: String,
        account: String,
        source: String?,
        location: String?,
        protocolName: String?,
        type: String?,
        connectedAt: Date?,
        description: String?,
        isCurrentConnection: Bool
    ) {
        self.id = id
        self.account = account
        self.source = source
        self.location = location
        self.protocolName = protocolName
        self.type = type
        self.connectedAt = connectedAt
        self.description = description
        self.isCurrentConnection = isCurrentConnection
    }
}

/// NAS 设置使用 DSM 内部只读接口。接口缺失时实现应返回 `apiUnavailable`，不得猜测或执行写操作。
public protocol NasSettingsRepository: Sendable {
    func loadSystemOverview() async throws -> NasSystemOverview
    func loadPerformanceSnapshot() async throws -> NasPerformanceSnapshot
    func loadStorage() async throws -> NasStorageSnapshot
    func loadPackages() async throws -> [NasPackage]
    func loadScheduledTasks() async throws -> [NasScheduledTask]
    func loadAccountsAndGroups() async throws -> NasAccountDirectory
    func loadLogs(offset: Int, limit: Int) async throws -> NasLogPage
    func loadConnections(offset: Int, limit: Int) async throws -> NasConnectionPage
    func loadInstalledServices() async throws -> [NasPackage]
    func controlPackage(id: String, action: NasPackageAction) async throws
    func performPowerAction(_ action: NasPowerAction) async throws
    func checkSystemUpdate() async throws -> NasSystemUpdateInfo
}

public extension NasSettingsRepository {
    func controlPackage(id: String, action: NasPackageAction) async throws {}
    func performPowerAction(_ action: NasPowerAction) async throws {}
    func checkSystemUpdate() async throws -> NasSystemUpdateInfo {
        NasSystemUpdateInfo(isUpdateAvailable: false)
    }
}
