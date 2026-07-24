import DsmCore
import Foundation

private enum DsmDynamicJSON: Decodable, Sendable {
    case object([String: DsmDynamicJSON])
    case array([DsmDynamicJSON])
    case string(String)
    case number(Double)
    case boolean(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: DsmDynamicJSON].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([DsmDynamicJSON].self))
        }
    }

    var object: [String: DsmDynamicJSON]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var array: [DsmDynamicJSON]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    subscript(key: String) -> DsmDynamicJSON? {
        object?[key]
    }

    func string(_ keys: [String]) -> String? {
        guard let object else { return scalarString }
        for key in keys {
            if let value = object[key]?.scalarString, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    var scalarString: String? {
        switch self {
        case .string(let value):
            value
        case .number(let value):
            value.rounded() == value ? String(Int64(value)) : String(value)
        case .boolean(let value):
            value ? "true" : "false"
        default:
            nil
        }
    }

    func number(_ keys: [String]) -> Double? {
        guard let object else { return scalarNumber }
        for key in keys {
            if let value = object[key]?.scalarNumber {
                return value
            }
        }
        return nil
    }

    var scalarNumber: Double? {
        switch self {
        case .number(let value):
            value
        case .string(let value):
            Double(value)
        case .boolean(let value):
            value ? 1 : 0
        default:
            nil
        }
    }

    func integer(_ keys: [String]) -> Int64? {
        number(keys).map(Int64.init)
    }

    func boolean(_ keys: [String]) -> Bool? {
        guard let object else { return scalarBoolean }
        for key in keys {
            if let value = object[key]?.scalarBoolean {
                return value
            }
        }
        return nil
    }

    var scalarBoolean: Bool? {
        switch self {
        case .boolean(let value):
            value
        case .number(let value):
            value != 0
        case .string(let value):
            ["true", "yes", "1", "enabled"].contains(value.lowercased())
        default:
            nil
        }
    }

    func objects(_ key: String) -> [[String: DsmDynamicJSON]] {
        self[key]?.array?.compactMap(\.object) ?? []
    }
}

/// DSM 的 NAS 管理内部接口适配器。当前只实现读取，不提供任何修改、启动、停止或删除操作。
public actor DsmNasAdministrationRepository: NasSettingsRepository {
    private let profileName: String
    private let capabilities: CapabilitySet
    private let credential: DsmSessionCredential
    private let client: DsmAPIClient

    public init(
        profile: NasProfile,
        capabilities: CapabilitySet,
        session: AuthSession,
        transport: (any DsmHTTPTransport)? = nil
    ) throws {
        let resolvedTransport = transport ?? URLSessionTransport(
            expectedHost: profile.host,
            pinnedCertificateSHA256: profile.pinnedCertificateSHA256,
            requiresSystemCertificateTrust: DsmQuickConnectResolver.isTrustedRelayHost(profile.host)
        )
        profileName = profile.displayName
        self.capabilities = capabilities
        credential = DsmSessionCredential(sid: session.sid, synoToken: session.synoToken)
        client = DsmAPIClient(
            baseURL: try DsmEndpoint.baseURL(for: profile),
            transport: resolvedTransport
        )
    }

    public func loadSystemOverview() async throws -> NasSystemOverview {
        let value = try await call(DsmAPIName.coreSystem, method: "info")
        let coreCount = value.string(["cpu_cores"]).flatMap(Int.init)
            ?? value.number(["cpu_cores"]).map(Int.init)
        let rawMemory = value.integer(["ram_size"])
        let temperatureWarning = value.boolean([
            "temperature_warning",
            "sys_tempwarn",
            "systempwarn"
        ]) ?? false

        return NasSystemOverview(
            serverName: profileName,
            model: value.string(["model"]),
            version: value.string(["firmware_ver"]),
            uptimeSeconds: Self.uptimeSeconds(from: value.string(["up_time"])),
            cpuModel: value.string(["cpu_series", "cpu_family"]),
            cpuCoreCount: coreCount,
            cpuClockMHz: value.number(["cpu_clock_speed"]).map(Int.init),
            memoryBytes: rawMemory.map(Self.memoryBytes),
            temperatureCelsius: value.number(["sys_temp"]),
            hasTemperatureWarning: temperatureWarning
        )
    }

    public func loadPerformanceSnapshot() async throws -> NasPerformanceSnapshot {
        let value = try await call(
            DsmAPIName.coreSystemUtilization,
            method: "get",
            parameters: [
                "resource": .string("all"),
                "type": .string("current")
            ]
        )
        let cpu = value["cpu"] ?? .object([:])
        let memory = value["memory"] ?? .object([:])
        let networkRows = value.objects("network")
        let totalNetwork = networkRows.first {
            DsmDynamicJSON.object($0).string(["device"])?.lowercased() == "total"
        }.map(DsmDynamicJSON.object) ?? .object([:])
        let diskTotal = value["disk"]?["total"] ?? .object([:])
        let volumeTotal = value["space"]?["total"] ?? .object([:])
        let nfsRows = value.objects("nfs").map(DsmDynamicJSON.object)
        let userCPU = cpu.number(["user_load"]) ?? 0
        let systemCPU = cpu.number(["system_load"]) ?? 0
        let otherCPU = cpu.number(["other_load"]) ?? 0
        let timestamp = value.number(["time"]).map(Date.init(timeIntervalSince1970:)) ?? Date()

        return NasPerformanceSnapshot(
            recordedAt: timestamp,
            cpuUsage: Self.percent(userCPU + systemCPU + otherCPU),
            cpuUserUsage: Self.percent(userCPU),
            cpuSystemUsage: Self.percent(systemCPU),
            cpuOtherUsage: Self.percent(otherCPU),
            memoryUsage: Self.percent(memory.number(["real_usage"]) ?? 0),
            swapUsage: Self.percent(memory.number(["swap_usage"]) ?? 0),
            networkReceivedBytesPerSecond: totalNetwork.integer(["rx"]) ?? 0,
            networkSentBytesPerSecond: totalNetwork.integer(["tx"]) ?? 0,
            diskReadBytesPerSecond: diskTotal.integer(["read_byte"]) ?? 0,
            diskWriteBytesPerSecond: diskTotal.integer(["write_byte"]) ?? 0,
            volumeReadBytesPerSecond: volumeTotal.integer(["read_byte"]) ?? 0,
            volumeWriteBytesPerSecond: volumeTotal.integer(["write_byte"]) ?? 0,
            diskUtilization: Self.percent(diskTotal.number(["utilization"]) ?? 0),
            nfsReadOperationsPerSecond: nfsRows.reduce(0) { $0 + ($1.integer(["read_OPS"]) ?? 0) },
            nfsWriteOperationsPerSecond: nfsRows.reduce(0) { $0 + ($1.integer(["write_OPS"]) ?? 0) }
        )
    }

    public func loadStorage() async throws -> NasStorageSnapshot {
        let value = try await call(DsmAPIName.storageOverview, method: "load_info")
        let disks = value.objects("disks").enumerated().map { index, raw in
            let item = DsmDynamicJSON.object(raw)
            let id = item.string(["id", "device", "name"]) ?? "disk-\(index)"
            return NasDisk(
                id: id,
                name: item.string(["longName", "name", "device"]) ?? "硬盘 \(index + 1)",
                model: item.string(["model"]),
                type: item.string(["diskType", "portType"]),
                totalBytes: item.integer(["size_total"]),
                status: item.string([
                    "summary_status_key",
                    "drive_status_key",
                    "overview_status",
                    "status"
                ]),
                smartStatus: item.string(["smart_status"]),
                temperatureCelsius: item.number(["temp"]),
                isSSD: item.boolean(["isSsd"]) ?? false,
                usedBy: item.string(["used_by", "allocation_role"]),
                supportsSmartTest: item.boolean(["smart_test_support"]) ?? false
            )
        }
        let pools = value.objects("storagePools").enumerated().map { index, raw in
            let item = DsmDynamicJSON.object(raw)
            let id = item.string(["id", "uuid", "num_id"]) ?? "pool-\(index)"
            let size = item["size"] ?? .object([:])
            return NasStoragePool(
                id: id,
                name: item.string(["desc", "vol_desc"]) ?? "存储池 \(index + 1)",
                raidType: item.string(["raidType", "device_type"]),
                status: item.string(["summary_status", "status", "space_status"]),
                totalBytes: size.integer(["total"]),
                usedBytes: size.integer(["used"]),
                isWritable: item.boolean(["is_writable"]) ?? false,
                isScrubbing: item.boolean(["data_scrubbing", "is_actioning"]) ?? false,
                nextScrubbingDate: Self.date(from: item.string(["next_schedule_time"]))
            )
        }
        let volumes = value.objects("volumes").enumerated().map { index, raw in
            let item = DsmDynamicJSON.object(raw)
            let id = item.string(["id", "uuid", "vol_path"]) ?? "volume-\(index)"
            let size = item["size"] ?? .object([:])
            return NasVolume(
                id: id,
                name: item.string(["vol_desc", "desc", "vol_path"]) ?? "存储空间 \(index + 1)",
                fileSystem: item.string(["fs_type"]),
                status: item.string(["summary_status", "status", "space_status"]),
                totalBytes: size.integer(["total"]),
                usedBytes: size.integer(["used"]),
                isEncrypted: item.boolean(["is_encrypted"]) ?? false,
                isWritable: item.boolean(["is_writable"]) ?? false
            )
        }
        return NasStorageSnapshot(
            overallStatus: value["overview_data"]?.string(["status_level"])
                ?? value["env"]?.string(["status"]),
            disks: disks,
            pools: pools,
            volumes: volumes
        )
    }

    public func loadPackages() async throws -> [NasPackage] {
        let value = try await call(
            DsmAPIName.corePackage,
            method: "list",
            parameters: [
                "offset": .integer(0),
                "limit": .integer(1_000),
                "additional": .stringArray([
                    "status",
                    "description",
                    "install_type"
                ])
            ]
        )

        let baseURL = client.baseURL

        return value.objects("packages").compactMap { raw -> NasPackage? in
            let item = DsmDynamicJSON.object(raw)
            guard let id = item.string(["id", "name"]) else { return nil }
            let additional = item["additional"] ?? .object([:])
            let rawStatus = additional.string(["status", "status_code"])
            let rawOrigin = additional.string(["status_origin"])
            let rawDesc = additional.string(["status_description"])
            let isRunning = (rawStatus?.lowercased() == "running" || rawStatus?.lowercased() == "active" || rawOrigin?.lowercased().contains("active") == true)
            let canUpgrade = additional.boolean(["can_upgrade", "upgrade"]) ?? false

            // 精细化清洗后台底层状态日志，避免暴露英文调试文本
            let formattedStatusDesc = cleanPackageStatusDescription(status: rawStatus, rawOrigin: rawOrigin, rawDesc: rawDesc)

            // 解析套件图标 URL（使用 DSM 官方公开 Icon API，并自动挂载认证凭据）
            let resolvedIconURL: URL?
            let sidParam = "_sid=\(credential.sid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? credential.sid)"

            if let iconPath = additional.string(["icon", "icon_120", "icon_72"]), !iconPath.isEmpty {
                if iconPath.hasPrefix("http://") || iconPath.hasPrefix("https://") {
                    resolvedIconURL = URL(string: iconPath)
                } else {
                    let cleanPath = iconPath.hasPrefix("/") ? String(iconPath.dropFirst()) : iconPath
                    let delimiter = cleanPath.contains("?") ? "&" : "?"
                    resolvedIconURL = URL(string: "\(cleanPath)\(delimiter)\(sidParam)", relativeTo: baseURL)
                }
            } else {
                resolvedIconURL = URL(string: "entry.cgi?api=SYNO.Core.Package&version=1&method=get_icon&id=\(id)&\(sidParam)", relativeTo: baseURL)
                    ?? URL(string: "webapi/entry.cgi?api=SYNO.Core.Package&version=1&method=get_icon&id=\(id)&\(sidParam)", relativeTo: baseURL)
            }

            return NasPackage(
                id: id,
                name: item.string(["name"]) ?? id,
                version: item.string(["version"]),
                status: rawStatus,
                statusDescription: formattedStatusDesc,
                packageDescription: additional.string(["description"]),
                installType: additional.string(["install_type"]),
                installedAt: item.number(["timestamp"]).map {
                    Date(timeIntervalSince1970: $0 > 10_000_000_000 ? $0 / 1_000 : $0)
                },
                iconURL: resolvedIconURL,
                canStart: !isRunning,
                canStop: isRunning,
                canUpgrade: canUpgrade
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func controlPackage(id: String, action: NasPackageAction) async throws {
        let method: String
        switch action {
        case .start: method = "start"
        case .stop: method = "stop"
        case .uninstall: method = "uninstall"
        case .upgrade: method = "upgrade"
        }
        _ = try await call(
            DsmAPIName.corePackage,
            method: method,
            parameters: ["id": .string(id)]
        )
    }

    public func performPowerAction(_ action: NasPowerAction) async throws {
        let method: String
        switch action {
        case .shutdown: method = "shutdown"
        case .reboot: method = "reboot"
        }
        _ = try await call(
            DsmAPIName.coreSystem,
            method: method,
            parameters: [:]
        )
    }

    public func checkSystemUpdate() async throws -> NasSystemUpdateInfo {
        do {
            let value = try await call(
                DsmAPIName.coreSystem,
                method: "info",
                parameters: [:]
            )
            let version = value.string(["firmware_ver", "version"]) ?? "DSM 7.x"
            return NasSystemUpdateInfo(
                isUpdateAvailable: false,
                currentVersion: version,
                latestVersion: version,
                releaseNotes: "当前系统固件已是最新版本"
            )
        } catch {
            return NasSystemUpdateInfo(isUpdateAvailable: false)
        }
    }

    public func loadScheduledTasks() async throws -> [NasScheduledTask] {
        let value = try await call(
            DsmAPIName.coreTaskScheduler,
            method: "list",
            parameters: [
                "start": .integer(0),
                "limit": .integer(1_000)
            ]
        )
        return value.objects("tasks").enumerated().compactMap { index, raw in
            let item = DsmDynamicJSON.object(raw)
            guard let name = item.string(["name"]) else { return nil }
            return NasScheduledTask(
                id: item.string(["id"]) ?? "task-\(index)-\(name)",
                name: name,
                owner: item.string(["real_owner", "owner"]),
                type: item.string(["type"]),
                action: item.string(["action"]),
                isEnabled: item.boolean(["enable"]) ?? false,
                nextTriggerDescription: item.string(["next_trigger_time"]),
                canRun: item.boolean(["can_run"]) ?? false,
                canEdit: item.boolean(["can_edit"]) ?? false
            )
        }
    }

    public func loadAccountsAndGroups() async throws -> NasAccountDirectory {
        async let usersValue = call(
            DsmAPIName.coreUser,
            method: "list",
            parameters: [
                "offset": .integer(0),
                "limit": .integer(1_000),
                "additional": .stringArray([
                    "uid",
                    "description",
                    "email",
                    "expired"
                ])
            ]
        )
        async let groupsValue = call(
            DsmAPIName.coreGroup,
            method: "list",
            parameters: [
                "offset": .integer(0),
                "limit": .integer(1_000),
                "additional": .stringArray(["description"])
            ]
        )

        let usersPayload = try await usersValue
        let groupsPayload = try await groupsValue
        let users = usersPayload.objects("users").compactMap { raw -> NasAccount? in
            let item = DsmDynamicJSON.object(raw)
            guard let name = item.string(["name"]) else { return nil }
            return NasAccount(
                id: "user:\(name)",
                name: name,
                kind: .user,
                numericID: item.integer(["uid"]),
                description: item.string(["description"]),
                email: item.string(["email"]),
                isExpired: item.boolean(["expired"]) ?? false
            )
        }
        let groups = groupsPayload.objects("groups").compactMap { raw -> NasAccount? in
            let item = DsmDynamicJSON.object(raw)
            guard let name = item.string(["name"]) else { return nil }
            return NasAccount(
                id: "group:\(name)",
                name: name,
                kind: .group,
                numericID: item.integer(["gid"]),
                description: item.string(["description"])
            )
        }
        return NasAccountDirectory(users: users, groups: groups)
    }

    public func loadLogs(offset: Int, limit: Int) async throws -> NasLogPage {
        // Log Center 可能已安装但没有历史记录；系统日志是 DSM 默认页面的数据源。
        let value = try await call(
            DsmAPIName.coreSystemLog,
            method: "list",
            parameters: [
                "offset": .integer(max(0, offset)),
                "limit": .integer(min(500, max(1, limit)))
            ]
        )
        let entries = value.objects("items").enumerated().compactMap { index, raw -> NasLogEntry? in
            let item = DsmDynamicJSON.object(raw)
            guard let message = item.string(["descr", "message", "msg"]) else { return nil }
            let rawTime = item.string(["time"])
            return NasLogEntry(
                id: "log:\(offset + index):\(rawTime ?? "")",
                date: Self.date(from: rawTime),
                source: item.string(["logtype", "orginalLogType"]),
                level: item.string(["level"]),
                account: item.string(["who"]),
                message: message
            )
        }
        return NasLogPage(
            entries: entries,
            total: Int(value.number(["total"]) ?? Double(entries.count)),
            infoCount: value.number(["infoCount"]).map(Int.init),
            warningCount: value.number(["warnCount"]).map(Int.init),
            errorCount: value.number(["errorCount"]).map(Int.init)
        )
    }

    public func loadConnections(offset: Int, limit: Int) async throws -> NasConnectionPage {
        let value = try await call(
            DsmAPIName.coreCurrentConnection,
            method: "list",
            parameters: [
                "start": .integer(max(0, offset)),
                "limit": .integer(min(500, max(1, limit))),
                "sort": .string("time"),
                "sort_by": .string("time"),
                "sort_direction": .string("DESC")
            ]
        )
        let connections = value.objects("items").enumerated().compactMap {
            index, raw -> NasConnection? in
            let item = DsmDynamicJSON.object(raw)
            guard let account = item.string(["who"]) else { return nil }
            let pid = item.string(["pid"]) ?? "\(index)"
            let time = item.string(["time"])
            return NasConnection(
                id: "connection:\(pid):\(account):\(time ?? "")",
                account: account,
                source: item.string(["from"]),
                location: item.string(["location"]),
                protocolName: item.string(["protocol"]),
                type: item.string(["type"]),
                connectedAt: Self.date(from: time),
                description: item.string(["descr"]),
                isCurrentConnection: item.boolean(["is_current_connected"]) ?? false
            )
        }
        return NasConnectionPage(
            connections: connections,
            total: Int(value.number(["total"]) ?? Double(connections.count))
        )
    }

    public func loadInstalledServices() async throws -> [NasPackage] {
        try await loadPackages()
    }

    private func call(
        _ name: String,
        method: String,
        parameters: [String: DsmParameterValue] = [:]
    ) async throws -> DsmDynamicJSON {
        guard let capability = capabilities[name],
              let version = capability.selectedVersion else {
            throw unavailableError()
        }
        do {
            return try await client.call(
                path: capability.path,
                api: capability.name,
                version: version,
                method: method,
                requestFormat: capability.requestFormat,
                parameters: parameters,
                credential: credential,
                as: DsmDynamicJSON.self
            )
        } catch let error as DsmNetworkError {
            throw DsmErrorMapper.map(error)
        }
    }

    private func unavailableError() -> AppError {
        AppError(
            category: .apiUnavailable,
            isRetryable: false,
            safeUserMessage: "这台 NAS 暂不提供此项信息。"
        )
    }

    private static func percent(_ value: Double) -> Double {
        min(100, max(0, value))
    }

    private static func memoryBytes(_ value: Int64) -> Int64 {
        // DSM `ram_size` 当前返回 MiB；保留对未来直接返回字节的兼容。
        value < 1_000_000 ? value * 1_024 * 1_024 : value
    }

    private static func uptimeSeconds(from value: String?) -> Int64? {
        guard let value else { return nil }
        if let seconds = Int64(value) {
            return seconds
        }
        let parts = value.split(separator: ":").compactMap { Int64($0) }
        guard parts.count == 3 else { return nil }
        return parts[0] * 3_600 + parts[1] * 60 + parts[2]
    }

    private static func date(from value: String?) -> Date? {
        guard let value, !value.isEmpty, value != "--" else { return nil }
        if let seconds = Double(value) {
            return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1_000 : seconds)
        }
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: value) {
            return date
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy/MM/dd HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    private func cleanPackageStatusDescription(status: String?, rawOrigin: String?, rawDesc: String?) -> String {
        let raw = [rawOrigin, rawDesc].compactMap { $0 }.joined(separator: " ").lowercased()
        if raw.contains("script status is not 0 but the unit is active") {
            return "后台响应中（状态自检异常）"
        }
        if raw.contains("retrieve from status script") {
            return "服务活跃"
        }
        if let status = status?.lowercased() {
            if status == "running" || status == "active" { return "运行中" }
            if status == "stop" || status == "stopped" { return "已停用" }
            if status == "error" || status == "failed" { return "运行异常" }
        }
        if let rawDesc = rawDesc, !rawDesc.isEmpty, !rawDesc.contains("retrieve from status script") {
            return rawDesc
        }
        return "运行中"
    }
}
