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
    /// DSM 内部接口使用的硬盘设备标识；与界面列表使用的稳定 `id` 不一定相同。
    public let deviceID: String
    public let name: String
    public let vendor: String?
    public let model: String?
    public let type: String?
    public let totalBytes: Int64?
    public let status: String?
    public let smartStatus: String?
    public let temperatureCelsius: Double?
    public let isSSD: Bool
    public let usedBy: String?
    public let supportsSmartTest: Bool
    public let serialNumber: String?
    public let firmwareVersion: String?
    public let location: String?
    public let is4KNative: Bool?
    public let estimatedLifePercent: Int?
    public let badSectorCount: Int?

    public init(
        id: String,
        deviceID: String? = nil,
        name: String,
        vendor: String? = nil,
        model: String?,
        type: String?,
        totalBytes: Int64?,
        status: String?,
        smartStatus: String?,
        temperatureCelsius: Double?,
        isSSD: Bool,
        usedBy: String?,
        supportsSmartTest: Bool,
        serialNumber: String? = nil,
        firmwareVersion: String? = nil,
        location: String? = nil,
        is4KNative: Bool? = nil,
        estimatedLifePercent: Int? = nil,
        badSectorCount: Int? = nil
    ) {
        self.id = id
        self.deviceID = deviceID ?? id
        self.name = name
        self.vendor = vendor
        self.model = model
        self.type = type
        self.totalBytes = totalBytes
        self.status = status
        self.smartStatus = smartStatus
        self.temperatureCelsius = temperatureCelsius
        self.isSSD = isSSD
        self.usedBy = usedBy
        self.supportsSmartTest = supportsSmartTest
        self.serialNumber = serialNumber
        self.firmwareVersion = firmwareVersion
        self.location = location
        self.is4KNative = is4KNative
        self.estimatedLifePercent = estimatedLifePercent
        self.badSectorCount = badSectorCount
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
    public let diskIDs: [String]
    public let spareDiskIDs: [String]
    public let supportsMultipleVolumes: Bool?

    public init(
        id: String,
        name: String,
        raidType: String?,
        status: String?,
        totalBytes: Int64?,
        usedBytes: Int64?,
        isWritable: Bool,
        isScrubbing: Bool,
        nextScrubbingDate: Date?,
        diskIDs: [String] = [],
        spareDiskIDs: [String] = [],
        supportsMultipleVolumes: Bool? = nil
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
        self.diskIDs = diskIDs
        self.spareDiskIDs = spareDiskIDs
        self.supportsMultipleVolumes = supportsMultipleVolumes
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
    public let poolID: String?
    public let path: String?

    public init(
        id: String,
        name: String,
        fileSystem: String?,
        status: String?,
        totalBytes: Int64?,
        usedBytes: Int64?,
        isEncrypted: Bool,
        isWritable: Bool,
        poolID: String? = nil,
        path: String? = nil
    ) {
        self.id = id
        self.name = name
        self.fileSystem = fileSystem
        self.status = status
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.isEncrypted = isEncrypted
        self.isWritable = isWritable
        self.poolID = poolID
        self.path = path
    }
}

public enum NasDiskTestType: String, CaseIterable, Equatable, Sendable {
    case quick
    case extended
}

public struct NasDiskTestStatus: Equatable, Sendable {
    public let diskID: String
    public let isRunning: Bool
    public let isBusyWithOtherTest: Bool
    public let runningType: NasDiskTestType?
    public let progressDescription: String?
    public let lastQuickTest: String?
    public let lastExtendedTest: String?
    public let lastResult: String?
    public let isHistoryAvailable: Bool

    public init(
        diskID: String,
        isRunning: Bool,
        isBusyWithOtherTest: Bool = false,
        runningType: NasDiskTestType? = nil,
        progressDescription: String? = nil,
        lastQuickTest: String? = nil,
        lastExtendedTest: String? = nil,
        lastResult: String? = nil,
        isHistoryAvailable: Bool = true
    ) {
        self.diskID = diskID
        self.isRunning = isRunning
        self.isBusyWithOtherTest = isBusyWithOtherTest
        self.runningType = runningType
        self.progressDescription = progressDescription
        self.lastQuickTest = lastQuickTest
        self.lastExtendedTest = lastExtendedTest
        self.lastResult = lastResult
        self.isHistoryAvailable = isHistoryAvailable
    }
}

public struct NasScheduledTaskResult: Identifiable, Equatable, Sendable {
    public let id: String
    public let taskName: String
    public let startedAt: Date?
    public let stoppedAt: Date?
    public let exitType: String?
    public let exitCode: Int?
    public let triggerEvent: String?

    public init(
        id: String,
        taskName: String,
        startedAt: Date?,
        stoppedAt: Date?,
        exitType: String?,
        exitCode: Int?,
        triggerEvent: String?
    ) {
        self.id = id
        self.taskName = taskName
        self.startedAt = startedAt
        self.stoppedAt = stoppedAt
        self.exitType = exitType
        self.exitCode = exitCode
        self.triggerEvent = triggerEvent
    }
}

public struct NasScheduledTaskResultOutput: Equatable, Sendable {
    public let command: String?
    public let output: String?

    public init(command: String?, output: String?) {
        self.command = command
        self.output = output
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
    public let iconData: Data?
    public let canStart: Bool
    public let canStop: Bool
    public let canUninstall: Bool
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
        iconData: Data? = nil,
        canStart: Bool = true,
        canStop: Bool = true,
        canUninstall: Bool = false,
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
        self.iconData = iconData
        self.canStart = canStart
        self.canStop = canStop
        self.canUninstall = canUninstall
        self.canUpgrade = canUpgrade
    }
}

public struct NasScheduledTask: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let owner: String?
    public let realOwner: String?
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
        realOwner: String? = nil,
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
        self.realOwner = realOwner
        self.type = type
        self.action = action
        self.isEnabled = isEnabled
        self.nextTriggerDescription = nextTriggerDescription
        self.canRun = canRun
        self.canEdit = canEdit
    }
}

public struct NasTaskSchedule: Equatable, Sendable {
    public var dateType: Int
    public var weekDays: String
    public var date: String?
    public var repeatDate: Int
    public var monthlyWeek: [Int]
    public var hour: Int
    public var minute: Int
    public var repeatHour: Int
    public var repeatMinute: Int
    public var lastWorkHour: Int

    public init(
        dateType: Int = 0,
        weekDays: String = "0,1,2,3,4,5,6",
        date: String? = nil,
        repeatDate: Int = 1001,
        monthlyWeek: [Int] = [],
        hour: Int = 0,
        minute: Int = 0,
        repeatHour: Int = 0,
        repeatMinute: Int = 0,
        lastWorkHour: Int = 0
    ) {
        self.dateType = dateType
        self.weekDays = weekDays
        self.date = date
        self.repeatDate = repeatDate
        self.monthlyWeek = monthlyWeek
        self.hour = hour
        self.minute = minute
        self.repeatHour = repeatHour
        self.repeatMinute = repeatMinute
        self.lastWorkHour = lastWorkHour
    }
}

public struct NasScheduledTaskDraft: Equatable, Sendable {
    public var id: Int?
    public var name: String
    public var owner: String
    public var realOwner: String?
    public var isEnabled: Bool
    public var script: String
    public var notifyOnError: Bool
    public var notificationEmails: String
    public var schedule: NasTaskSchedule

    public init(
        id: Int? = nil,
        name: String = "",
        owner: String,
        realOwner: String? = nil,
        isEnabled: Bool = true,
        script: String = "",
        notifyOnError: Bool = false,
        notificationEmails: String = "",
        schedule: NasTaskSchedule = NasTaskSchedule()
    ) {
        self.id = id
        self.name = name
        self.owner = owner
        self.realOwner = realOwner
        self.isEnabled = isEnabled
        self.script = script
        self.notifyOnError = notifyOnError
        self.notificationEmails = notificationEmails
        self.schedule = schedule
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
    public let groups: [String]?
    public let isExpired: Bool
    public let canEdit: Bool
    public let canDelete: Bool

    public init(
        id: String,
        name: String,
        kind: Kind,
        numericID: Int64?,
        description: String?,
        email: String? = nil,
        groups: [String]? = nil,
        isExpired: Bool = false,
        canEdit: Bool = false,
        canDelete: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.numericID = numericID
        self.description = description
        self.email = email
        self.groups = groups
        self.isExpired = isExpired
        self.canEdit = canEdit
        self.canDelete = canDelete
    }
}

public struct NasAccountDraft: Equatable, Sendable {
    public let originalName: String?
    public var name: String
    public var description: String
    public var email: String
    public var isExpired: Bool
    public var groups: [String]?
    public var password: String
    public var passwordConfirmation: String

    public init(
        originalName: String? = nil,
        name: String = "",
        description: String = "",
        email: String = "",
        isExpired: Bool = false,
        groups: [String]? = nil,
        password: String = "",
        passwordConfirmation: String = ""
    ) {
        self.originalName = originalName
        self.name = name
        self.description = description
        self.email = email
        self.isExpired = isExpired
        self.groups = groups
        self.password = password
        self.passwordConfirmation = passwordConfirmation
    }
}

public struct NasGroupDraft: Equatable, Sendable {
    public let originalName: String?
    public var name: String
    public var description: String

    public init(
        originalName: String? = nil,
        name: String = "",
        description: String = ""
    ) {
        self.originalName = originalName
        self.name = name
        self.description = description
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
    public let processID: String?
    public let deviceID: String?
    public let account: String
    public let source: String?
    public let location: String?
    public let protocolName: String?
    public let type: String?
    public let connectedAt: Date?
    public let description: String?
    public let isCurrentConnection: Bool
    public let canDisconnect: Bool

    public init(
        id: String,
        processID: String? = nil,
        deviceID: String? = nil,
        account: String,
        source: String?,
        location: String?,
        protocolName: String?,
        type: String?,
        connectedAt: Date?,
        description: String?,
        isCurrentConnection: Bool,
        canDisconnect: Bool = false
    ) {
        self.id = id
        self.processID = processID
        self.deviceID = deviceID
        self.account = account
        self.source = source
        self.location = location
        self.protocolName = protocolName
        self.type = type
        self.connectedAt = connectedAt
        self.description = description
        self.isCurrentConnection = isCurrentConnection
        self.canDisconnect = canDisconnect
    }
}

/// NAS 文件共享服务设置。`nil` 表示当前 NAS 未提供对应能力，不能展示为可修改。
public struct NasFileServiceSettings: Hashable, Sendable {
    public var isSMBEnabled: Bool?
    public var isNFSEnabled: Bool?
    public var isFTPEnabled: Bool?
    public var isFTPSEnabled: Bool?
    public var ftpPort: Int?
    public var isSFTPEnabled: Bool?
    public var sftpPort: Int?
    public var isSSDPEnabled: Bool?
    public var isBonjourEnabled: Bool?
    public var isSMBTimeMachineEnabled: Bool?

    public init(
        isSMBEnabled: Bool?,
        isNFSEnabled: Bool?,
        isFTPEnabled: Bool?,
        isFTPSEnabled: Bool?,
        ftpPort: Int?,
        isSFTPEnabled: Bool?,
        sftpPort: Int?,
        isSSDPEnabled: Bool? = nil,
        isBonjourEnabled: Bool? = nil,
        isSMBTimeMachineEnabled: Bool? = nil
    ) {
        self.isSMBEnabled = isSMBEnabled
        self.isNFSEnabled = isNFSEnabled
        self.isFTPEnabled = isFTPEnabled
        self.isFTPSEnabled = isFTPSEnabled
        self.ftpPort = ftpPort
        self.isSFTPEnabled = isSFTPEnabled
        self.sftpPort = sftpPort
        self.isSSDPEnabled = isSSDPEnabled
        self.isBonjourEnabled = isBonjourEnabled
        self.isSMBTimeMachineEnabled = isSMBTimeMachineEnabled
    }
}

/// NAS 远程终端设置。端口只有在当前设备返回有效值时才允许修改。
public struct NasTerminalSettings: Hashable, Sendable {
    public var isSSHEnabled: Bool
    public var isTelnetEnabled: Bool
    public var sshPort: Int?

    public init(isSSHEnabled: Bool, isTelnetEnabled: Bool, sshPort: Int?) {
        self.isSSHEnabled = isSSHEnabled
        self.isTelnetEnabled = isTelnetEnabled
        self.sshPort = sshPort
    }
}

/// NAS 访问互联网时使用的代理设置。密码不会从 NAS 读取或保存在客户端。
public struct NasProxySettings: Hashable, Sendable {
    public var isEnabled: Bool
    public var host: String
    public var port: Int?

    public init(isEnabled: Bool, host: String, port: Int?) {
        self.isEnabled = isEnabled
        self.host = host
        self.port = port
    }
}

public struct NasEthernetInterface: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let status: String?
    public var usesDHCP: Bool
    public var address: String
    public var subnetMask: String
    public var gateway: String
    public var dnsServers: String
    public var isDefaultGateway: Bool
    public var mtu: Int
    public var isVLANEnabled: Bool
    public var vlanID: Int?

    public init(
        id: String,
        displayName: String,
        status: String?,
        usesDHCP: Bool,
        address: String,
        subnetMask: String,
        gateway: String,
        dnsServers: String,
        isDefaultGateway: Bool,
        mtu: Int,
        isVLANEnabled: Bool,
        vlanID: Int?
    ) {
        self.id = id
        self.displayName = displayName
        self.status = status
        self.usesDHCP = usesDHCP
        self.address = address
        self.subnetMask = subnetMask
        self.gateway = gateway
        self.dnsServers = dnsServers
        self.isDefaultGateway = isDefaultGateway
        self.mtu = mtu
        self.isVLANEnabled = isVLANEnabled
        self.vlanID = vlanID
    }
}

/// 当前设备实际提供的基础硬件设置。
public struct NasUPSSettings: Hashable, Sendable {
    public var isEnabled: Bool
    public var mode: String
    public var safeModeDelaySeconds: Int?
    public var waitsUntilLowBattery: Bool?
    public var shutsDownUPSAfterSafeMode: Bool?
    public var networkServerAddress: String?
    public var snmpServerAddress: String?

    public init(
        isEnabled: Bool,
        mode: String,
        safeModeDelaySeconds: Int?,
        waitsUntilLowBattery: Bool?,
        shutsDownUPSAfterSafeMode: Bool?,
        networkServerAddress: String?,
        snmpServerAddress: String?
    ) {
        self.isEnabled = isEnabled
        self.mode = mode
        self.safeModeDelaySeconds = safeModeDelaySeconds
        self.waitsUntilLowBattery = waitsUntilLowBattery
        self.shutsDownUPSAfterSafeMode = shutsDownUPSAfterSafeMode
        self.networkServerAddress = networkServerAddress
        self.snmpServerAddress = snmpServerAddress
    }
}

public struct NasHardwareSettings: Hashable, Sendable {
    public var restartsAfterPowerFailure: Bool?
    public var ledBrightness: Int?
    public let ledBrightnessRange: ClosedRange<Int>?
    public var fanMode: String?
    public var isFanFailureAlertEnabled: Bool?
    public var isVolumeFailureAlertEnabled: Bool?
    public var isPowerOnSoundEnabled: Bool?
    public var isPowerOffSoundEnabled: Bool?
    public var isResetSoundEnabled: Bool?
    public var isExternalDriveDeepSleepEnabled: Bool?
    public var isWakeUpLogEnabled: Bool?
    public var isSATASleepEnabled: Bool?
    public var ignoresNetworkDiscoveryDuringSleep: Bool?
    public var isAutomaticPowerOffEnabled: Bool?
    public var ups: NasUPSSettings?

    public init(
        restartsAfterPowerFailure: Bool?,
        ledBrightness: Int?,
        ledBrightnessRange: ClosedRange<Int>?,
        fanMode: String? = nil,
        isFanFailureAlertEnabled: Bool? = nil,
        isVolumeFailureAlertEnabled: Bool? = nil,
        isPowerOnSoundEnabled: Bool? = nil,
        isPowerOffSoundEnabled: Bool? = nil,
        isResetSoundEnabled: Bool? = nil,
        isExternalDriveDeepSleepEnabled: Bool? = nil,
        isWakeUpLogEnabled: Bool? = nil,
        isSATASleepEnabled: Bool? = nil,
        ignoresNetworkDiscoveryDuringSleep: Bool? = nil,
        isAutomaticPowerOffEnabled: Bool? = nil,
        ups: NasUPSSettings? = nil
    ) {
        self.restartsAfterPowerFailure = restartsAfterPowerFailure
        self.ledBrightness = ledBrightness
        self.ledBrightnessRange = ledBrightnessRange
        self.fanMode = fanMode
        self.isFanFailureAlertEnabled = isFanFailureAlertEnabled
        self.isVolumeFailureAlertEnabled = isVolumeFailureAlertEnabled
        self.isPowerOnSoundEnabled = isPowerOnSoundEnabled
        self.isPowerOffSoundEnabled = isPowerOffSoundEnabled
        self.isResetSoundEnabled = isResetSoundEnabled
        self.isExternalDriveDeepSleepEnabled = isExternalDriveDeepSleepEnabled
        self.isWakeUpLogEnabled = isWakeUpLogEnabled
        self.isSATASleepEnabled = isSATASleepEnabled
        self.ignoresNetworkDiscoveryDuringSleep = ignoresNetworkDiscoveryDuringSleep
        self.isAutomaticPowerOffEnabled = isAutomaticPowerOffEnabled
        self.ups = ups
    }
}

/// QuickConnect 远程访问设置。`nil` 表示当前设备未提供对应能力。
public struct NasRemoteAccessSettings: Hashable, Sendable {
    public var isRelayEnabled: Bool?
    public var isRouterConfigurationEnabled: Bool?
    public let canDisableRelay: Bool

    public init(
        isRelayEnabled: Bool?,
        isRouterConfigurationEnabled: Bool?,
        canDisableRelay: Bool
    ) {
        self.isRelayEnabled = isRelayEnabled
        self.isRouterConfigurationEnabled = isRouterConfigurationEnabled
        self.canDisableRelay = canDisableRelay
    }
}

/// 登录失败自动封锁设置。
public struct NasDoSProtectionSetting: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public var isEnabled: Bool

    public init(id: String, displayName: String, isEnabled: Bool) {
        self.id = id
        self.displayName = displayName
        self.isEnabled = isEnabled
    }
}

public struct NasSecuritySettings: Hashable, Sendable {
    public var isAutoBlockEnabled: Bool
    public var failedAttempts: Int
    public var withinMinutes: Int
    /// `nil` 表示封锁不会自动过期。
    public var expirationDays: Int?
    public var dosProtection: [NasDoSProtectionSetting]
    public var isFirewallEnabled: Bool?
    public var firewallProfileName: String?
    public var isPortScanProtectionEnabled: Bool?

    public init(
        isAutoBlockEnabled: Bool,
        failedAttempts: Int,
        withinMinutes: Int,
        expirationDays: Int?,
        dosProtection: [NasDoSProtectionSetting] = [],
        isFirewallEnabled: Bool? = nil,
        firewallProfileName: String? = nil,
        isPortScanProtectionEnabled: Bool? = nil
    ) {
        self.isAutoBlockEnabled = isAutoBlockEnabled
        self.failedAttempts = failedAttempts
        self.withinMinutes = withinMinutes
        self.expirationDays = expirationDays
        self.dosProtection = dosProtection
        self.isFirewallEnabled = isFirewallEnabled
        self.firewallProfileName = firewallProfileName
        self.isPortScanProtectionEnabled = isPortScanProtectionEnabled
    }
}

/// NAS 区域与网络校时设置。时区选项只使用设备实际返回的值。
public struct NasTimeZoneOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public struct NasRegionSettings: Hashable, Sendable {
    public var dateFormat: String
    public var timeFormat: String
    public var timeZone: String
    public var isNetworkTimeEnabled: Bool
    public var timeServers: [String]
    public var manualDate: Date?
    public let timeZones: [NasTimeZoneOption]

    public init(
        dateFormat: String,
        timeFormat: String,
        timeZone: String,
        isNetworkTimeEnabled: Bool,
        timeServers: [String],
        manualDate: Date?,
        timeZones: [NasTimeZoneOption]
    ) {
        self.dateFormat = dateFormat
        self.timeFormat = timeFormat
        self.timeZone = timeZone
        self.isNetworkTimeEnabled = isNetworkTimeEnabled
        self.timeServers = timeServers
        self.manualDate = manualDate
        self.timeZones = timeZones
    }
}

public struct NasDDNSProvider: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public struct NasDDNSRecord: Identifiable, Hashable, Sendable {
    public let id: String
    public let providerID: String
    public let providerName: String
    public let hostname: String
    public let address: String?
    public let status: String?
    public let lastUpdated: String?
    public let isEnabled: Bool
    public let username: String?
    public let networkType: String?
    public let ipv4: String?
    public let ipv6: String?
    public let interfaceV4: String?
    public let interfaceV6: String?
    public let heartbeat: Bool

    public init(
        id: String,
        providerID: String,
        providerName: String,
        hostname: String,
        address: String?,
        status: String?,
        lastUpdated: String?,
        isEnabled: Bool,
        username: String?,
        networkType: String?,
        ipv4: String?,
        ipv6: String?,
        interfaceV4: String?,
        interfaceV6: String?,
        heartbeat: Bool
    ) {
        self.id = id
        self.providerID = providerID
        self.providerName = providerName
        self.hostname = hostname
        self.address = address
        self.status = status
        self.lastUpdated = lastUpdated
        self.isEnabled = isEnabled
        self.username = username
        self.networkType = networkType
        self.ipv4 = ipv4
        self.ipv6 = ipv6
        self.interfaceV4 = interfaceV4
        self.interfaceV6 = interfaceV6
        self.heartbeat = heartbeat
    }
}

public struct NasDDNSDirectory: Hashable, Sendable {
    public let providers: [NasDDNSProvider]
    public let records: [NasDDNSRecord]

    public init(providers: [NasDDNSProvider], records: [NasDDNSRecord]) {
        self.providers = providers
        self.records = records
    }
}

/// DDNS 密码只用于本次提交，客户端不会从 NAS 读取或持久化。
public struct NasDDNSDraft: Hashable, Sendable {
    public var originalProviderID: String?
    public var providerID: String
    public var hostname: String
    public var username: String
    public var password: String
    public var isEnabled: Bool
    public var networkType: String
    public var ipv4: String
    public var ipv6: String
    public var interfaceV4: String
    public var interfaceV6: String
    public var heartbeat: Bool

    public init(
        originalProviderID: String? = nil,
        providerID: String,
        hostname: String,
        username: String,
        password: String = "",
        isEnabled: Bool = true,
        networkType: String = "auto",
        ipv4: String = "0.0.0.0",
        ipv6: String = "0:0:0:0:0:0:0:0",
        interfaceV4: String = "",
        interfaceV6: String = "",
        heartbeat: Bool = false
    ) {
        self.originalProviderID = originalProviderID
        self.providerID = providerID
        self.hostname = hostname
        self.username = username
        self.password = password
        self.isEnabled = isEnabled
        self.networkType = networkType
        self.ipv4 = ipv4
        self.ipv6 = ipv6
        self.interfaceV4 = interfaceV4
        self.interfaceV6 = interfaceV6
        self.heartbeat = heartbeat
    }
}

/// NAS 设置主要使用 DSM 内部接口。写操作必须先完成能力、权限与目标状态检查。
public protocol NasSettingsRepository: Sendable {
    func loadSystemOverview() async throws -> NasSystemOverview
    func loadPerformanceSnapshot() async throws -> NasPerformanceSnapshot
    func loadStorage() async throws -> NasStorageSnapshot
    func loadDiskTestStatus(diskID: String) async throws -> NasDiskTestStatus
    func startDiskTest(diskID: String, type: NasDiskTestType) async throws -> NasDiskTestStatus
    func stopDiskTest(diskID: String) async throws -> NasDiskTestStatus
    func loadPackages() async throws -> [NasPackage]
    func loadScheduledTasks() async throws -> [NasScheduledTask]
    func loadScheduledTaskDraft(id: Int?, realOwner: String?) async throws -> NasScheduledTaskDraft
    func loadScheduledTaskResults(taskName: String) async throws -> [NasScheduledTaskResult]
    func loadScheduledTaskResultOutput(
        taskName: String,
        resultID: String
    ) async throws -> NasScheduledTaskResultOutput
    func saveScheduledTask(_ draft: NasScheduledTaskDraft) async throws
    func setScheduledTaskEnabled(id: Int, realOwner: String?, enabled: Bool) async throws
    func runScheduledTask(id: Int, realOwner: String?) async throws
    func deleteScheduledTask(id: Int, realOwner: String?) async throws
    func loadAccountsAndGroups() async throws -> NasAccountDirectory
    func saveAccount(_ draft: NasAccountDraft) async throws
    func deleteAccount(name: String) async throws
    func saveGroup(_ draft: NasGroupDraft) async throws
    func deleteGroup(name: String) async throws
    func loadLogs(offset: Int, limit: Int) async throws -> NasLogPage
    func loadConnections(offset: Int, limit: Int) async throws -> NasConnectionPage
    func disconnectConnection(_ connection: NasConnection) async throws
    func loadFileServiceSettings() async throws -> NasFileServiceSettings
    func saveFileServiceSettings(_ settings: NasFileServiceSettings) async throws
    func loadTerminalSettings() async throws -> NasTerminalSettings
    func saveTerminalSettings(_ settings: NasTerminalSettings) async throws
    func loadProxySettings() async throws -> NasProxySettings
    func saveProxySettings(_ settings: NasProxySettings) async throws
    func loadEthernetInterfaces() async throws -> [NasEthernetInterface]
    func saveEthernetInterface(_ interface: NasEthernetInterface) async throws
    func loadHardwareSettings() async throws -> NasHardwareSettings
    func saveHardwareSettings(_ settings: NasHardwareSettings) async throws
    func loadRemoteAccessSettings() async throws -> NasRemoteAccessSettings
    func saveRemoteAccessSettings(_ settings: NasRemoteAccessSettings) async throws
    func loadSecuritySettings() async throws -> NasSecuritySettings
    func saveSecuritySettings(_ settings: NasSecuritySettings) async throws
    func loadRegionSettings() async throws -> NasRegionSettings
    func saveRegionSettings(_ settings: NasRegionSettings) async throws
    func loadDDNS() async throws -> NasDDNSDirectory
    func saveDDNS(_ draft: NasDDNSDraft) async throws
    func deleteDDNS(providerID: String) async throws
    func refreshDDNS() async throws
    func controlPackage(id: String, action: NasPackageAction) async throws
    func performPowerAction(_ action: NasPowerAction) async throws
    func checkSystemUpdate() async throws -> NasSystemUpdateInfo
}

public extension NasSettingsRepository {
    func loadDiskTestStatus(diskID: String) async throws -> NasDiskTestStatus {
        throw AppError(
            category: .apiUnavailable,
            isRetryable: false,
            safeUserMessage: "这台 NAS 暂不能读取硬盘检测状态。"
        )
    }
    func startDiskTest(
        diskID: String,
        type: NasDiskTestType
    ) async throws -> NasDiskTestStatus {
        throw AppError(
            category: .apiUnavailable,
            isRetryable: false,
            safeUserMessage: "这台 NAS 暂不能启动硬盘检测。"
        )
    }
    func stopDiskTest(diskID: String) async throws -> NasDiskTestStatus {
        throw AppError(
            category: .apiUnavailable,
            isRetryable: false,
            safeUserMessage: "这台 NAS 暂不能停止硬盘检测。"
        )
    }
    func controlPackage(id: String, action: NasPackageAction) async throws {
        throw unsupportedManagementOperation()
    }
    func loadScheduledTaskDraft(id: Int?, realOwner: String?) async throws -> NasScheduledTaskDraft {
        throw AppError(
            category: .apiUnavailable,
            isRetryable: false,
            safeUserMessage: "这台 NAS 暂不能管理计划任务。"
        )
    }
    func loadScheduledTaskResults(taskName: String) async throws -> [NasScheduledTaskResult] {
        throw unsupportedManagementOperation()
    }
    func loadScheduledTaskResultOutput(
        taskName: String,
        resultID: String
    ) async throws -> NasScheduledTaskResultOutput {
        throw unsupportedManagementOperation()
    }
    func saveAccount(_ draft: NasAccountDraft) async throws {
        throw unsupportedManagementOperation()
    }
    func deleteAccount(name: String) async throws {
        throw unsupportedManagementOperation()
    }
    func saveGroup(_ draft: NasGroupDraft) async throws {
        throw unsupportedManagementOperation()
    }
    func deleteGroup(name: String) async throws {
        throw unsupportedManagementOperation()
    }
    func saveScheduledTask(_ draft: NasScheduledTaskDraft) async throws {
        throw unsupportedManagementOperation()
    }
    func setScheduledTaskEnabled(id: Int, realOwner: String?, enabled: Bool) async throws {
        throw unsupportedManagementOperation()
    }
    func runScheduledTask(id: Int, realOwner: String?) async throws {
        throw unsupportedManagementOperation()
    }
    func deleteScheduledTask(id: Int, realOwner: String?) async throws {
        throw unsupportedManagementOperation()
    }
    func disconnectConnection(_ connection: NasConnection) async throws {
        throw unsupportedManagementOperation()
    }
    func loadFileServiceSettings() async throws -> NasFileServiceSettings {
        throw unsupportedManagementOperation()
    }
    func saveFileServiceSettings(_ settings: NasFileServiceSettings) async throws {
        throw unsupportedManagementOperation()
    }
    func loadTerminalSettings() async throws -> NasTerminalSettings {
        throw unsupportedManagementOperation()
    }
    func saveTerminalSettings(_ settings: NasTerminalSettings) async throws {
        throw unsupportedManagementOperation()
    }
    func loadProxySettings() async throws -> NasProxySettings {
        throw unsupportedManagementOperation()
    }
    func saveProxySettings(_ settings: NasProxySettings) async throws {
        throw unsupportedManagementOperation()
    }
    func loadEthernetInterfaces() async throws -> [NasEthernetInterface] {
        throw unsupportedManagementOperation()
    }
    func saveEthernetInterface(_ interface: NasEthernetInterface) async throws {
        throw unsupportedManagementOperation()
    }
    func loadHardwareSettings() async throws -> NasHardwareSettings {
        throw unsupportedManagementOperation()
    }
    func saveHardwareSettings(_ settings: NasHardwareSettings) async throws {
        throw unsupportedManagementOperation()
    }
    func loadRemoteAccessSettings() async throws -> NasRemoteAccessSettings {
        throw unsupportedManagementOperation()
    }
    func saveRemoteAccessSettings(_ settings: NasRemoteAccessSettings) async throws {
        throw unsupportedManagementOperation()
    }
    func loadSecuritySettings() async throws -> NasSecuritySettings {
        throw unsupportedManagementOperation()
    }
    func saveSecuritySettings(_ settings: NasSecuritySettings) async throws {
        throw unsupportedManagementOperation()
    }
    func loadRegionSettings() async throws -> NasRegionSettings {
        throw unsupportedManagementOperation()
    }
    func saveRegionSettings(_ settings: NasRegionSettings) async throws {
        throw unsupportedManagementOperation()
    }
    func loadDDNS() async throws -> NasDDNSDirectory {
        throw unsupportedManagementOperation()
    }
    func saveDDNS(_ draft: NasDDNSDraft) async throws {
        throw unsupportedManagementOperation()
    }
    func deleteDDNS(providerID: String) async throws {
        throw unsupportedManagementOperation()
    }
    func refreshDDNS() async throws {
        throw unsupportedManagementOperation()
    }
    func performPowerAction(_ action: NasPowerAction) async throws {
        throw unsupportedManagementOperation()
    }
    func checkSystemUpdate() async throws -> NasSystemUpdateInfo {
        throw unsupportedManagementOperation()
    }

    private func unsupportedManagementOperation() -> AppError {
        AppError(
            category: .apiUnavailable,
            isRetryable: false,
            safeUserMessage: "这台 NAS 暂不能完成此操作。"
        )
    }
}
