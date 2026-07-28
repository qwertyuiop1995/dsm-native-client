import DsmCore
import Foundation
import DsmLocalization

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

    func strings(_ keys: [String]) -> [String] {
        guard let object else {
            if let value = scalarString {
                return value.split(separator: " ").map(String.init)
            }
            return array?.compactMap(\.scalarString) ?? []
        }
        for key in keys {
            guard let value = object[key] else { continue }
            if let values = value.array?.compactMap(\.scalarString), !values.isEmpty {
                return values
            }
            if let scalar = value.scalarString, !scalar.isEmpty {
                return scalar.split(separator: " ").map(String.init)
            }
        }
        return []
    }
}

private struct PackageControlMetadata: Sendable {
    let dsmApps: [String]
}

private struct DiskTestHistorySnapshot: Sendable {
    let lastQuickTest: String?
    let lastExtendedTest: String?
    let latestResult: String?
    let isAvailable: Bool

    static let unavailable = DiskTestHistorySnapshot(
        lastQuickTest: nil,
        lastExtendedTest: nil,
        latestResult: nil,
        isAvailable: false
    )
}

/// DSM 的 NAS 管理内部接口适配器。所有写操作都先执行能力与可行性检查。
public actor DsmNasAdministrationRepository: NasSettingsRepository {
    private let profileName: String
    private let currentUsername: String?
    private let capabilities: CapabilitySet
    private let credential: DsmSessionCredential
    private let client: DsmAPIClient
    private let transport: any DsmHTTPTransport
    private let isConnectedThroughQuickConnectRelay: Bool
    private var packageControlMetadata: [String: PackageControlMetadata] = [:]
    private var packageIconCache: [String: Data] = [:]
    private var storageDisks: [String: NasDisk] = [:]
    private var diskTestHistories: [String: DiskTestHistorySnapshot] = [:]
    private var beepVolumeFieldName: String?

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
        currentUsername = profile.usernameHint
        isConnectedThroughQuickConnectRelay =
            DsmQuickConnectResolver.isTrustedRelayHost(profile.host)
        self.capabilities = capabilities
        credential = DsmSessionCredential(sid: session.sid, synoToken: session.synoToken)
        self.transport = resolvedTransport
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

    public func loadFileServiceSettings() async throws -> NasFileServiceSettings {
        let hasSMB = capabilities[DsmAPIName.coreFileServiceSMB]?.selectedVersion != nil
        let hasNFS = capabilities[DsmAPIName.coreFileServiceNFS]?.selectedVersion != nil
        let hasFTP = capabilities[DsmAPIName.coreFileServiceFTP]?.selectedVersion != nil
        let hasSFTP = capabilities[DsmAPIName.coreFileServiceSFTP]?.selectedVersion != nil
        let hasWebDiscovery = capabilities[DsmAPIName.coreWebDSM]?.selectedVersion != nil
        let hasFileDiscovery =
            capabilities[DsmAPIName.coreFileServiceDiscovery]?.selectedVersion != nil
        guard hasSMB || hasNFS || hasFTP || hasSFTP
                || hasWebDiscovery || hasFileDiscovery else {
            throw unavailableError()
        }

        let smb = hasSMB ? try await call(DsmAPIName.coreFileServiceSMB, method: "get") : nil
        let nfs = hasNFS ? try await call(DsmAPIName.coreFileServiceNFS, method: "get") : nil
        let ftp = hasFTP ? try await call(DsmAPIName.coreFileServiceFTP, method: "get") : nil
        let sftp = hasSFTP ? try await call(DsmAPIName.coreFileServiceSFTP, method: "get") : nil
        let webDiscovery = hasWebDiscovery
            ? try await call(DsmAPIName.coreWebDSM, method: "get", version: 2)
            : nil
        let fileDiscovery = hasFileDiscovery
            ? try await call(DsmAPIName.coreFileServiceDiscovery, method: "get")
            : nil

        return NasFileServiceSettings(
            isSMBEnabled: smb?.boolean(["enable_samba"]),
            isNFSEnabled: nfs?.boolean(["enable_nfs"]),
            isFTPEnabled: ftp?.boolean(["enable_ftp"]),
            isFTPSEnabled: ftp?.boolean(["enable_ftps"]),
            ftpPort: ftp?.number(["portnum"]).map(Int.init),
            isSFTPEnabled: sftp?.boolean(["enable"]),
            sftpPort: sftp?.number(["portnum", "sftp_portnum"]).map(Int.init),
            isSSDPEnabled: webDiscovery?.boolean(["enable_ssdp"]),
            isBonjourEnabled: webDiscovery?.boolean(["enable_avahi"]),
            isSMBTimeMachineEnabled: fileDiscovery?.boolean(["enable_smb_time_machine"])
        )
    }

    public func saveFileServiceSettings(_ settings: NasFileServiceSettings) async throws {
        let current = try await loadFileServiceSettings()
        if let enabled = settings.isSMBEnabled, enabled != current.isSMBEnabled {
            try await callVoid(
                DsmAPIName.coreFileServiceSMB,
                method: "set",
                parameters: ["enable_samba": .boolean(enabled)]
            )
        }
        if let enabled = settings.isNFSEnabled, enabled != current.isNFSEnabled {
            try await callVoid(
                DsmAPIName.coreFileServiceNFS,
                method: "set",
                parameters: ["enable_nfs": .boolean(enabled)]
            )
        }
        if settings.isFTPEnabled != current.isFTPEnabled
            || settings.isFTPSEnabled != current.isFTPSEnabled
            || settings.ftpPort != current.ftpPort {
            var parameters: [String: DsmParameterValue] = [:]
            if let enabled = settings.isFTPEnabled {
                parameters["enable_ftp"] = .boolean(enabled)
            }
            if let enabled = settings.isFTPSEnabled {
                parameters["enable_ftps"] = .boolean(enabled)
            }
            if let port = settings.ftpPort {
                try Self.validatePort(port)
                parameters["portnum"] = .integer(port)
            }
            try await callVoid(
                DsmAPIName.coreFileServiceFTP,
                method: "set",
                parameters: parameters
            )
        }
        if settings.isSFTPEnabled != current.isSFTPEnabled
            || settings.sftpPort != current.sftpPort {
            var parameters: [String: DsmParameterValue] = [:]
            if let enabled = settings.isSFTPEnabled {
                parameters["enable"] = .boolean(enabled)
            }
            if let port = settings.sftpPort {
                try Self.validatePort(port)
                parameters["portnum"] = .integer(port)
            }
            try await callVoid(
                DsmAPIName.coreFileServiceSFTP,
                method: "set",
                parameters: parameters
            )
        }
        if settings.isSSDPEnabled != current.isSSDPEnabled
            || settings.isBonjourEnabled != current.isBonjourEnabled {
            var parameters: [String: DsmParameterValue] = [:]
            if let enabled = settings.isSSDPEnabled {
                parameters["enable_ssdp"] = .boolean(enabled)
            }
            if let enabled = settings.isBonjourEnabled {
                parameters["enable_avahi"] = .boolean(enabled)
            }
            try await callVoid(
                DsmAPIName.coreWebDSM,
                method: "set",
                version: 2,
                parameters: parameters
            )
        }
        if let enabled = settings.isSMBTimeMachineEnabled,
           enabled != current.isSMBTimeMachineEnabled {
            try await callVoid(
                DsmAPIName.coreFileServiceDiscovery,
                method: "set",
                parameters: ["enable_smb_time_machine": .boolean(enabled)]
            )
        }

        let verified = try await loadFileServiceSettings()
        guard Self.fileServiceSettings(verified, match: settings) else {
            throw verificationError(L10n.string("shared.86dc93229dc74567"))
        }
    }

    public func loadTerminalSettings() async throws -> NasTerminalSettings {
        let value = try await call(DsmAPIName.coreTerminal, method: "get")
        guard let ssh = value.boolean(["enable_ssh"]),
              let telnet = value.boolean(["enable_telnet"]) else {
            throw verificationError(L10n.string("shared.e53ee9190654879c"))
        }
        return NasTerminalSettings(
            isSSHEnabled: ssh,
            isTelnetEnabled: telnet,
            sshPort: value.number(["ssh_port"]).map(Int.init)
        )
    }

    public func saveTerminalSettings(_ settings: NasTerminalSettings) async throws {
        if let port = settings.sshPort {
            try Self.validatePort(port)
        }
        let current = try await loadTerminalSettings()
        guard current != settings else { return }

        var parameters: [String: DsmParameterValue] = [
            "enable_ssh": .boolean(settings.isSSHEnabled),
            "enable_telnet": .boolean(settings.isTelnetEnabled)
        ]
        if let port = settings.sshPort {
            parameters["ssh_port"] = .integer(port)
        }
        try await callVoid(
            DsmAPIName.coreTerminal,
            method: "set",
            parameters: parameters
        )

        let verified = try await loadTerminalSettings()
        guard verified == settings else {
            throw verificationError(L10n.string("shared.373e3c888e7ebf52"))
        }
    }

    public func loadProxySettings() async throws -> NasProxySettings {
        let value = try await call(DsmAPIName.coreNetworkProxy, method: "get")
        guard let enabled = value.boolean(["enable"]) else {
            throw verificationError(L10n.string("shared.21598082fdbb7d65"))
        }
        return NasProxySettings(
            isEnabled: enabled,
            host: value.string(["http_host"]) ?? "",
            port: value.number(["http_port"]).map(Int.init)
        )
    }

    public func saveProxySettings(_ settings: NasProxySettings) async throws {
        let host = settings.host.trimmingCharacters(in: .whitespacesAndNewlines)
        if settings.isEnabled {
            guard !host.isEmpty, let port = settings.port else {
                throw verificationError(L10n.string("shared.ee6423ab7d6992c8"))
            }
            try Self.validatePort(port)
        }
        let normalized = NasProxySettings(
            isEnabled: settings.isEnabled,
            host: host,
            port: settings.port
        )
        let current = try await loadProxySettings()
        guard current != normalized else { return }

        var parameters: [String: DsmParameterValue] = [
            "enable": .boolean(normalized.isEnabled)
        ]
        if normalized.isEnabled, let port = normalized.port {
            parameters["http_host"] = .string(normalized.host)
            parameters["http_port"] = .integer(port)
        }
        try await callVoid(
            DsmAPIName.coreNetworkProxy,
            method: "set",
            parameters: parameters
        )
        let verified = try await loadProxySettings()
        guard verified.isEnabled == normalized.isEnabled,
              !normalized.isEnabled
                || (verified.host == normalized.host && verified.port == normalized.port) else {
            throw verificationError(L10n.string("shared.d29407101028f890"))
        }
    }

    public func loadEthernetInterfaces() async throws -> [NasEthernetInterface] {
        let list = try await call(
            DsmAPIName.coreNetworkEthernet,
            method: "list",
            version: 2
        )
        var rows = list.objects("interfaces")
        if rows.isEmpty {
            rows = list.array?.compactMap(\.object) ?? []
        }
        var result: [NasEthernetInterface] = []
        for row in rows {
            guard let id = row["ifname"]?.scalarString
                    ?? row["id"]?.scalarString,
                  id.hasPrefix("eth") else {
                continue
            }
            let detail = try await call(
                DsmAPIName.coreNetworkEthernet,
                method: "get",
                version: 1,
                parameters: ["ifname": .string(id)]
            )
            guard let item = Self.ethernetInterface(
                from: detail,
                fallback: row,
                id: id
            ) else {
                continue
            }
            result.append(item)
        }
        return result
    }

    public func saveEthernetInterface(_ interface: NasEthernetInterface) async throws {
        guard interface.id.hasPrefix("eth"),
              interface.id.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
                      .contains($0)
              }) else {
            throw verificationError(L10n.string("shared.e08a7f16a91c9932"))
        }
        guard (576...9_000).contains(interface.mtu) else {
            throw verificationError(L10n.string("shared.bd04fc72d0e308c0"))
        }
        if interface.isVLANEnabled {
            guard let vlanID = interface.vlanID, (1...4_094).contains(vlanID) else {
                throw verificationError(L10n.string("shared.e5be64194f7d7959"))
            }
        }
        if !interface.usesDHCP {
            guard Self.isValidIPv4(interface.address),
                  Self.isValidIPv4(interface.subnetMask),
                  (interface.gateway.isEmpty || Self.isValidIPv4(interface.gateway)) else {
                throw verificationError(L10n.string("shared.e4338b64530bcbcc"))
            }
        }
        let current = try await loadEthernetInterfaces()
        guard let existing = current.first(where: { $0.id == interface.id }) else {
            throw verificationError(L10n.string("shared.f0a75be9d773f2a6"))
        }
        guard existing != interface else { return }
        var config: [String: DsmJSONValue] = [
            "ifname": .string(interface.id),
            "use_dhcp": .boolean(interface.usesDHCP),
            "is_default_gateway": .boolean(interface.isDefaultGateway),
            "mtu": .integer(interface.mtu),
            "enable_vlan": .boolean(interface.isVLANEnabled)
        ]
        if !interface.usesDHCP {
            config["ip"] = .string(interface.address)
            config["mask"] = .string(interface.subnetMask)
            config["gateway"] = .string(interface.gateway)
            config["dns"] = .string(interface.dnsServers)
        }
        if interface.isVLANEnabled, let vlanID = interface.vlanID {
            config["vlan_id"] = .integer(vlanID)
        }
        try await callVoid(
            DsmAPIName.coreNetworkEthernet,
            method: "set",
            version: 1,
            parameters: ["configs": .objectArray([config])]
        )
        let verifiedValue = try await call(
            DsmAPIName.coreNetworkEthernet,
            method: "get",
            version: 1,
            parameters: ["ifname": .string(interface.id)]
        )
        guard let verified = Self.ethernetInterface(
            from: verifiedValue,
            fallback: [:],
            id: interface.id
        ), Self.ethernetInterface(verified, matches: interface) else {
            throw verificationError(L10n.string("shared.648300d4688b5c30"))
        }
    }

    public func loadHardwareSettings() async throws -> NasHardwareSettings {
        let hasPowerRecovery =
            capabilities[DsmAPIName.coreHardwarePowerRecovery]?.selectedVersion != nil
        let hasLED =
            capabilities[DsmAPIName.coreHardwareLEDBrightness]?.selectedVersion != nil
        let hasFan = capabilities[DsmAPIName.coreHardwareFanSpeed]?.selectedVersion != nil
        let hasBeep = capabilities[DsmAPIName.coreHardwareBeepControl]?.selectedVersion != nil
        let hasHibernation =
            capabilities[DsmAPIName.coreHardwareHibernation]?.selectedVersion != nil
        let hasUPS = capabilities[DsmAPIName.coreExternalDeviceUPS]?.selectedVersion != nil
        guard hasPowerRecovery || hasLED || hasFan || hasBeep || hasHibernation || hasUPS else {
            throw unavailableError()
        }

        let power = hasPowerRecovery
            ? try await call(DsmAPIName.coreHardwarePowerRecovery, method: "get")
            : nil
        let led = hasLED
            ? try await call(DsmAPIName.coreHardwareLEDBrightness, method: "get")
            : nil
        let ledStatic = hasLED
            ? try await call(
                DsmAPIName.coreHardwareLEDBrightness,
                method: "get_static_data"
            )
            : nil
        let fan = hasFan
            ? try await call(DsmAPIName.coreHardwareFanSpeed, method: "get")
            : nil
        let beep = hasBeep
            ? try await call(DsmAPIName.coreHardwareBeepControl, method: "get")
            : nil
        let hibernation = hasHibernation
            ? try await call(DsmAPIName.coreHardwareHibernation, method: "get")
            : nil
        let ups = hasUPS
            ? try await call(DsmAPIName.coreExternalDeviceUPS, method: "get")
            : nil
        if beep?["volume_or_cache_crash"] != nil {
            beepVolumeFieldName = "volume_or_cache_crash"
        } else if beep?["volume_crash"] != nil {
            beepVolumeFieldName = "volume_crash"
        }
        let minimum = ledStatic?.number(["min"]).map(Int.init)
        let maximum = ledStatic?.number(["max"]).map(Int.init)
        let range = minimum.flatMap { minValue in
            maximum.flatMap { maxValue in
                minValue <= maxValue ? minValue...maxValue : nil
            }
        }
        return NasHardwareSettings(
            restartsAfterPowerFailure: power?.boolean(["rc_power_config"]),
            ledBrightness: led?.number(["led_brightness"]).map(Int.init),
            ledBrightnessRange: range,
            fanMode: fan?.string(["dual_fan_speed"]),
            isFanFailureAlertEnabled: beep?.boolean(["fan_fail"]),
            isVolumeFailureAlertEnabled: beep?.boolean([
                "volume_or_cache_crash",
                "volume_crash"
            ]),
            isPowerOnSoundEnabled: beep?.boolean(["poweron_beep"]),
            isPowerOffSoundEnabled: beep?.boolean(["poweroff_beep"]),
            isResetSoundEnabled: beep?.boolean(["reset_beep"]),
            isExternalDriveDeepSleepEnabled: hibernation?.boolean(["eunit_deep_sleep"]),
            isWakeUpLogEnabled: hibernation?.boolean(["enable_log"]),
            isSATASleepEnabled: hibernation?.boolean(["sata_deep_sleep"]),
            ignoresNetworkDiscoveryDuringSleep: hibernation?.boolean([
                "ignore_netbios_broadcast"
            ]),
            isAutomaticPowerOffEnabled: hibernation?.boolean(["auto_poweroff_enable"]),
            ups: Self.upsSettings(from: ups)
        )
    }

    public func saveHardwareSettings(_ settings: NasHardwareSettings) async throws {
        let current = try await loadHardwareSettings()
        if let value = settings.restartsAfterPowerFailure,
           value != current.restartsAfterPowerFailure {
            try await callVoid(
                DsmAPIName.coreHardwarePowerRecovery,
                method: "set",
                parameters: ["rc_power_config": .boolean(value)]
            )
        }
        if let brightness = settings.ledBrightness,
           brightness != current.ledBrightness {
            guard let range = current.ledBrightnessRange, range.contains(brightness) else {
                throw verificationError(L10n.string("shared.e7bc95903e2c1a21"))
            }
            try await callVoid(
                DsmAPIName.coreHardwareLEDBrightness,
                method: "set_current_brightness",
                parameters: ["led_brightness": .integer(brightness)]
            )
            try await callVoid(
                DsmAPIName.coreHardwareLEDBrightness,
                method: "update"
            )
        }
        if let fanMode = settings.fanMode,
           fanMode != current.fanMode {
            let supportedModes = Set([
                "highfan",
                "lowfan",
                "fullfan",
                "coolfan",
                "quietfan",
                "quietstopfan"
            ])
            guard supportedModes.contains(fanMode) else {
                throw verificationError(L10n.string("shared.f57a2aff1b6f5542"))
            }
            try await callVoid(
                DsmAPIName.coreHardwareFanSpeed,
                method: "set",
                parameters: ["dual_fan_speed": .string(fanMode)]
            )
        }
        var beepParameters: [String: DsmParameterValue] = [:]
        Self.appendChangedBoolean(
            settings.isFanFailureAlertEnabled,
            current.isFanFailureAlertEnabled,
            key: "fan_fail",
            to: &beepParameters
        )
        if let volumeField = beepVolumeFieldName {
            Self.appendChangedBoolean(
                settings.isVolumeFailureAlertEnabled,
                current.isVolumeFailureAlertEnabled,
                key: volumeField,
                to: &beepParameters
            )
        }
        Self.appendChangedBoolean(
            settings.isPowerOnSoundEnabled,
            current.isPowerOnSoundEnabled,
            key: "poweron_beep",
            to: &beepParameters
        )
        Self.appendChangedBoolean(
            settings.isPowerOffSoundEnabled,
            current.isPowerOffSoundEnabled,
            key: "poweroff_beep",
            to: &beepParameters
        )
        Self.appendChangedBoolean(
            settings.isResetSoundEnabled,
            current.isResetSoundEnabled,
            key: "reset_beep",
            to: &beepParameters
        )
        if !beepParameters.isEmpty {
            try await callVoid(
                DsmAPIName.coreHardwareBeepControl,
                method: "set",
                parameters: beepParameters
            )
        }
        var hibernationParameters: [String: DsmParameterValue] = [:]
        Self.appendChangedBoolean(
            settings.isExternalDriveDeepSleepEnabled,
            current.isExternalDriveDeepSleepEnabled,
            key: "eunit_deep_sleep",
            to: &hibernationParameters
        )
        Self.appendChangedBoolean(
            settings.isWakeUpLogEnabled,
            current.isWakeUpLogEnabled,
            key: "enable_log",
            to: &hibernationParameters
        )
        Self.appendChangedBoolean(
            settings.isSATASleepEnabled,
            current.isSATASleepEnabled,
            key: "sata_deep_sleep",
            to: &hibernationParameters
        )
        Self.appendChangedBoolean(
            settings.ignoresNetworkDiscoveryDuringSleep,
            current.ignoresNetworkDiscoveryDuringSleep,
            key: "ignore_netbios_broadcast",
            to: &hibernationParameters
        )
        Self.appendChangedBoolean(
            settings.isAutomaticPowerOffEnabled,
            current.isAutomaticPowerOffEnabled,
            key: "auto_poweroff_enable",
            to: &hibernationParameters
        )
        if !hibernationParameters.isEmpty {
            try await callVoid(
                DsmAPIName.coreHardwareHibernation,
                method: "set",
                parameters: hibernationParameters
            )
        }
        if let expectedUPS = settings.ups, let currentUPS = current.ups,
           expectedUPS != currentUPS {
            let supportedModes = Set(["USB", "SNMP", "SLAVE"])
            guard supportedModes.contains(expectedUPS.mode) else {
                throw verificationError(L10n.string("shared.6c49d4a3c0dca3eb"))
            }
            if let delay = expectedUPS.safeModeDelaySeconds,
               !(0...604_800).contains(delay) {
                throw verificationError(L10n.string("shared.6fc94869ad264ba7"))
            }
            if expectedUPS.mode == "SLAVE",
               expectedUPS.isEnabled,
               (expectedUPS.networkServerAddress?
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                throw verificationError(L10n.string("shared.47b0ea4e9e53c8c1"))
            }
            if expectedUPS.mode == "SNMP",
               expectedUPS.isEnabled,
               (expectedUPS.snmpServerAddress?
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                throw verificationError(L10n.string("shared.0ac712a773c6795f"))
            }
            var upsParameters: [String: DsmParameterValue] = [
                "enable": .boolean(expectedUPS.isEnabled),
                "mode": .string(expectedUPS.mode)
            ]
            if let delay = expectedUPS.safeModeDelaySeconds {
                upsParameters["delay_time"] = .integer(delay)
            }
            Self.appendChangedBoolean(
                expectedUPS.waitsUntilLowBattery,
                currentUPS.waitsUntilLowBattery,
                key: "ups_set_safemode_until_lowbatt",
                to: &upsParameters
            )
            Self.appendChangedBoolean(
                expectedUPS.shutsDownUPSAfterSafeMode,
                currentUPS.shutsDownUPSAfterSafeMode,
                key: "shutdown_device",
                to: &upsParameters
            )
            if let address = expectedUPS.networkServerAddress {
                upsParameters["net_server_ip"] = .string(
                    address.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            if let address = expectedUPS.snmpServerAddress {
                upsParameters["snmp_server_ip"] = .string(
                    address.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            try await callVoid(
                DsmAPIName.coreExternalDeviceUPS,
                method: "set",
                parameters: upsParameters
            )
        } else if settings.ups != nil || current.ups != nil {
            guard settings.ups != nil, current.ups != nil else {
                throw verificationError(L10n.string("shared.4b3caf9ebe49fe9e"))
            }
        }
        let verified = try await loadHardwareSettings()
        guard (settings.restartsAfterPowerFailure == nil
                || verified.restartsAfterPowerFailure == settings.restartsAfterPowerFailure),
              (settings.ledBrightness == nil
                || verified.ledBrightness == settings.ledBrightness),
              (settings.fanMode == nil || verified.fanMode == settings.fanMode),
              (settings.isFanFailureAlertEnabled == nil
                || verified.isFanFailureAlertEnabled == settings.isFanFailureAlertEnabled),
              (settings.isVolumeFailureAlertEnabled == nil
                || verified.isVolumeFailureAlertEnabled
                    == settings.isVolumeFailureAlertEnabled),
              (settings.isPowerOnSoundEnabled == nil
                || verified.isPowerOnSoundEnabled == settings.isPowerOnSoundEnabled),
              (settings.isPowerOffSoundEnabled == nil
                || verified.isPowerOffSoundEnabled == settings.isPowerOffSoundEnabled),
              (settings.isResetSoundEnabled == nil
                || verified.isResetSoundEnabled == settings.isResetSoundEnabled),
              (settings.isExternalDriveDeepSleepEnabled == nil
                || verified.isExternalDriveDeepSleepEnabled
                    == settings.isExternalDriveDeepSleepEnabled),
              (settings.isWakeUpLogEnabled == nil
                || verified.isWakeUpLogEnabled == settings.isWakeUpLogEnabled),
              (settings.isSATASleepEnabled == nil
                || verified.isSATASleepEnabled == settings.isSATASleepEnabled),
              (settings.ignoresNetworkDiscoveryDuringSleep == nil
                || verified.ignoresNetworkDiscoveryDuringSleep
                    == settings.ignoresNetworkDiscoveryDuringSleep),
              (settings.isAutomaticPowerOffEnabled == nil
                || verified.isAutomaticPowerOffEnabled
                    == settings.isAutomaticPowerOffEnabled),
              Self.upsSettings(verified.ups, match: settings.ups) else {
            throw verificationError(L10n.string("shared.9e2bef35ff2e4491"))
        }
    }

    public func loadRemoteAccessSettings() async throws -> NasRemoteAccessSettings {
        let hasQuickConnect = capabilities[DsmAPIName.coreQuickConnect]?.selectedVersion != nil
        let hasUPnP = capabilities[DsmAPIName.coreQuickConnectUPnP]?.selectedVersion != nil
        guard hasQuickConnect || hasUPnP else {
            throw unavailableError()
        }
        let quickConnect = hasQuickConnect
            ? try await call(
                DsmAPIName.coreQuickConnect,
                method: "get_misc_config",
                version: 3
            )
            : nil
        let upnp = hasUPnP
            ? try await call(DsmAPIName.coreQuickConnectUPnP, method: "get")
            : nil
        return NasRemoteAccessSettings(
            isRelayEnabled: quickConnect?.boolean(["relay_enabled"]),
            isRouterConfigurationEnabled: upnp?.boolean(["enabled"]),
            canDisableRelay: !isConnectedThroughQuickConnectRelay
        )
    }

    public func saveRemoteAccessSettings(_ settings: NasRemoteAccessSettings) async throws {
        let current = try await loadRemoteAccessSettings()
        if settings.isRelayEnabled == false,
           current.isRelayEnabled == true,
           !current.canDisableRelay {
            throw AppError(
                category: .conflict,
                isRetryable: false,
                safeUserMessage: L10n.string("shared.0ca30ab13245d805")
            )
        }
        if let enabled = settings.isRelayEnabled,
           enabled != current.isRelayEnabled {
            try await callVoid(
                DsmAPIName.coreQuickConnect,
                method: "set_misc_config",
                version: 3,
                parameters: ["relay_enabled": .boolean(enabled)]
            )
        }
        if let enabled = settings.isRouterConfigurationEnabled,
           enabled != current.isRouterConfigurationEnabled {
            try await callVoid(
                DsmAPIName.coreQuickConnectUPnP,
                method: "set",
                parameters: ["enabled": .boolean(enabled)]
            )
        }
        let verified = try await loadRemoteAccessSettings()
        guard (settings.isRelayEnabled == nil
                || verified.isRelayEnabled == settings.isRelayEnabled),
              (settings.isRouterConfigurationEnabled == nil
                || verified.isRouterConfigurationEnabled
                    == settings.isRouterConfigurationEnabled) else {
            throw verificationError(L10n.string("shared.259c1e687815c0a7"))
        }
    }

    public func loadSecuritySettings() async throws -> NasSecuritySettings {
        let value = try await call(DsmAPIName.coreSecurityAutoBlock, method: "get")
        guard let enabled = value.boolean(["enable"]),
              let attempts = value.number(["attempts"]).map(Int.init),
              let withinMinutes = value.number(["within_mins"]).map(Int.init) else {
            throw verificationError(L10n.string("shared.2ab8b77714bc123d"))
        }
        let rawExpiration = value.number(["expire_day"]).map(Int.init) ?? 0
        var dosProtection: [NasDoSProtectionSetting] = []
        let firewall = capabilities[DsmAPIName.coreSecurityFirewall]?.selectedVersion != nil
            ? try await call(DsmAPIName.coreSecurityFirewall, method: "get")
            : nil
        let firewallConf =
            capabilities[DsmAPIName.coreSecurityFirewallConf]?.selectedVersion != nil
                ? try await call(DsmAPIName.coreSecurityFirewallConf, method: "get")
                : nil
        if capabilities[DsmAPIName.coreNetworkEthernet]?.selectedVersion != nil,
           capabilities[DsmAPIName.coreSecurityDoS]?.selectedVersion != nil {
            let ethernet = try await call(DsmAPIName.coreNetworkEthernet, method: "list")
            var adapters = ethernet.objects("interfaces")
            if adapters.isEmpty {
                adapters = ethernet.objects("adapters")
            }
            if adapters.isEmpty {
                adapters = ethernet.array?.compactMap(\.object) ?? []
            }
            let adapterIDs = adapters.compactMap {
                $0["id"]?.scalarString
                    ?? $0["ifname"]?.scalarString
                    ?? $0["name"]?.scalarString
            }
            if !adapterIDs.isEmpty {
                let configs = adapterIDs.map { ["adapter": DsmJSONValue.string($0)] }
                let dos = try await call(
                    DsmAPIName.coreSecurityDoS,
                    method: "get",
                    version: 2,
                    parameters: ["configs": .objectArray(configs)]
                )
                var dosObjects = dos.array?.compactMap(\.object) ?? []
                if dosObjects.isEmpty {
                    dosObjects = dos.objects("configs")
                }
                let enabledPairs: [(String, Bool)] = dosObjects.compactMap {
                    guard let id = $0["adapter"]?.scalarString,
                          let enabled = $0["dos_protect_enable"]?.scalarBoolean else {
                        return nil
                    }
                    return (id, enabled)
                }
                // DSM 的内部接口在部分版本中会重复返回同一网卡，后返回的状态应覆盖旧值。
                let enabledByAdapter = enabledPairs.reduce(into: [String: Bool]()) {
                    $0[$1.0] = $1.1
                }
                dosProtection = adapters.compactMap { adapter in
                    guard let id = adapter["id"]?.scalarString
                            ?? adapter["ifname"]?.scalarString
                            ?? adapter["name"]?.scalarString,
                          let enabled = enabledByAdapter[id] else {
                        return nil
                    }
                    return NasDoSProtectionSetting(
                        id: id,
                        displayName: adapter["display"]?.scalarString
                            ?? adapter["display_name"]?.scalarString
                            ?? id,
                        isEnabled: enabled
                    )
                }
            }
        }
        return NasSecuritySettings(
            isAutoBlockEnabled: enabled,
            failedAttempts: attempts,
            withinMinutes: withinMinutes,
            expirationDays: rawExpiration > 0 ? rawExpiration : nil,
            dosProtection: dosProtection,
            isFirewallEnabled: firewall?.boolean(["enable_firewall"]),
            firewallProfileName: firewall?.string(["profile_name"]),
            isPortScanProtectionEnabled: firewallConf?.boolean(["enable_port_check"])
        )
    }

    public func saveSecuritySettings(_ settings: NasSecuritySettings) async throws {
        guard settings.failedAttempts > 0, settings.failedAttempts <= 9_999 else {
            throw verificationError(L10n.string("shared.7172e0328c485e2d"))
        }
        guard settings.withinMinutes > 0, settings.withinMinutes <= 9_999_999 else {
            throw verificationError(L10n.string("shared.6b3faa04b8983fea"))
        }
        if let days = settings.expirationDays, !(1...999).contains(days) {
            throw verificationError(L10n.string("shared.eb7055df43bef6c1"))
        }
        let current = try await loadSecuritySettings()
        guard current != settings else { return }
        if settings.isAutoBlockEnabled != current.isAutoBlockEnabled
            || settings.failedAttempts != current.failedAttempts
            || settings.withinMinutes != current.withinMinutes
            || settings.expirationDays != current.expirationDays {
            try await callVoid(
                DsmAPIName.coreSecurityAutoBlock,
                method: "set",
                parameters: [
                    "enable": .boolean(settings.isAutoBlockEnabled),
                    "attempts": .integer(settings.failedAttempts),
                    "within_mins": .integer(settings.withinMinutes),
                    "expire_day": .integer(settings.expirationDays ?? 0)
                ]
            )
        }
        if settings.dosProtection != current.dosProtection {
            let currentIDs = Set(current.dosProtection.map(\.id))
            guard Set(settings.dosProtection.map(\.id)) == currentIDs else {
                throw verificationError(L10n.string("shared.106655f64c87e191"))
            }
            let configs: [[String: DsmJSONValue]] = settings.dosProtection.map {
                [
                    "adapter": .string($0.id),
                    "dos_protect_enable": .boolean($0.isEnabled)
                ]
            }
            try await callVoid(
                DsmAPIName.coreSecurityDoS,
                method: "set",
                version: 2,
                parameters: ["configs": .objectArray(configs)]
            )
        }
        if let expected = settings.isPortScanProtectionEnabled,
           expected != current.isPortScanProtectionEnabled {
            try await callVoid(
                DsmAPIName.coreSecurityFirewallConf,
                method: "set",
                parameters: ["enable_port_check": .boolean(expected)]
            )
        }
        if let expected = settings.isFirewallEnabled,
           expected != current.isFirewallEnabled {
            if expected {
                guard let profile = current.firewallProfileName, !profile.isEmpty else {
                    throw verificationError(L10n.string("shared.816830de0895450c"))
                }
                try await applyFirewallProfile(profile)
            } else {
                try await callVoid(
                    DsmAPIName.coreSecurityFirewall,
                    method: "set",
                    parameters: ["set_type": .string("disable")]
                )
            }
        }
        let verified = try await loadSecuritySettings()
        guard verified.isAutoBlockEnabled == settings.isAutoBlockEnabled,
              verified.failedAttempts == settings.failedAttempts,
              verified.withinMinutes == settings.withinMinutes,
              verified.expirationDays == settings.expirationDays,
              verified.dosProtection == settings.dosProtection,
              (settings.isFirewallEnabled == nil
                || verified.isFirewallEnabled == settings.isFirewallEnabled),
              (settings.isPortScanProtectionEnabled == nil
                || verified.isPortScanProtectionEnabled
                    == settings.isPortScanProtectionEnabled) else {
            throw verificationError(L10n.string("shared.879eb126a08e1b1c"))
        }
    }

    private func applyFirewallProfile(_ profile: String) async throws {
        let started = try await call(
            DsmAPIName.coreSecurityFirewallProfileApply,
            method: "start",
            parameters: [
                "name": .string(profile),
                "profile_applying": .boolean(false)
            ]
        )
        guard let taskID = started.string(["task_id"]), !taskID.isEmpty else {
            throw verificationError(L10n.string("shared.40d8f50f944fb5b6"))
        }
        var completed = false
        for attempt in 0..<30 {
            if attempt > 0 {
                try await Task.sleep(for: .seconds(1))
            }
            let status = try await call(
                DsmAPIName.coreSecurityFirewallProfileApply,
                method: "status",
                parameters: ["task_id": .string(taskID)]
            )
            if let success = status.boolean(["success"]) {
                guard success else {
                    try? await callVoid(
                        DsmAPIName.coreSecurityFirewallProfileApply,
                        method: "stop"
                    )
                    throw verificationError(L10n.string("shared.672df0d0489dd59a"))
                }
                completed = true
                break
            }
        }
        try? await callVoid(DsmAPIName.coreSecurityFirewallProfileApply, method: "stop")
        guard completed else {
            throw AppError(
                category: .serverBusy,
                isRetryable: true,
                safeUserMessage: L10n.string("shared.41454065abd301f9")
            )
        }
    }

    public func loadRegionSettings() async throws -> NasRegionSettings {
        let value = try await call(
            DsmAPIName.coreRegionNTP,
            method: "get",
            version: 3
        )
        let zonesValue = try await call(
            DsmAPIName.coreRegionNTP,
            method: "listzone",
            version: 1
        )
        guard let dateFormat = value.string(["date_format"]),
              let timeFormat = value.string(["time_format"]),
              let timeZone = value.string(["timezone"]),
              let rawMode = value.string(["enable_ntp"]) else {
            throw verificationError(L10n.string("shared.db6b9590023d51f5"))
        }
        let isNetworkTimeEnabled =
            ["ntp", "true", "yes", "1", "enabled"].contains(rawMode.lowercased())
        let serverText = value.string(["server"]) ?? ""
        let servers = serverText
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let zones = zonesValue.objects("zonedata").compactMap { zone -> NasTimeZoneOption? in
            guard let id = zone["value"]?.scalarString, !id.isEmpty else { return nil }
            return NasTimeZoneOption(
                id: id,
                displayName: zone["display"]?.scalarString ?? id
            )
        }
        let manualDate = Self.regionDate(
            date: value.string(["date"]),
            hour: value.number(["hour"]).map(Int.init),
            minute: value.number(["minute"]).map(Int.init),
            second: value.number(["second"]).map(Int.init)
        )
        return NasRegionSettings(
            dateFormat: dateFormat,
            timeFormat: timeFormat,
            timeZone: timeZone,
            isNetworkTimeEnabled: isNetworkTimeEnabled,
            timeServers: servers,
            manualDate: manualDate,
            timeZones: zones
        )
    }

    public func saveRegionSettings(_ settings: NasRegionSettings) async throws {
        let current = try await loadRegionSettings()
        let dateFormat = settings.dateFormat.trimmingCharacters(in: .whitespacesAndNewlines)
        let timeFormat = settings.timeFormat.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dateFormat.isEmpty, !timeFormat.isEmpty else {
            throw verificationError(L10n.string("shared.eabfe94b8908b899"))
        }
        guard settings.timeZones.contains(where: { $0.id == settings.timeZone }) else {
            throw verificationError(L10n.string("shared.0504b45ed9ebedd1"))
        }
        let servers = settings.timeServers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard servers.count <= 3 else {
            throw verificationError(L10n.string("shared.2c6b003fd894a371"))
        }
        if settings.isNetworkTimeEnabled {
            guard !servers.isEmpty, servers.allSatisfy(Self.isValidTimeServer) else {
                throw verificationError(L10n.string("shared.915c3cdb096109ad"))
            }
            if !current.isNetworkTimeEnabled || current.timeServers != servers {
                try await callVoid(
                    DsmAPIName.coreRegionNTP,
                    method: "sync",
                    version: 2,
                    parameters: ["servers": .stringArray(servers)]
                )
            }
        }

        var parameters: [String: DsmParameterValue] = [
            "date_format": .string(dateFormat),
            "time_format": .string(timeFormat),
            "timezone": .string(settings.timeZone),
            "enable_ntp": .string(settings.isNetworkTimeEnabled ? "ntp" : "manual"),
            "server": .string(servers.joined(separator: ","))
        ]
        if !settings.isNetworkTimeEnabled {
            guard let manualDate = settings.manualDate else {
                throw verificationError(L10n.string("shared.e580ef4793aaf3d6"))
            }
            let calendar = Calendar(identifier: .gregorian)
            let parts = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: manualDate
            )
            guard let year = parts.year, let month = parts.month, let day = parts.day,
                  let hour = parts.hour, let minute = parts.minute, let second = parts.second else {
                throw verificationError(L10n.string("shared.286f4090dc75cccc"))
            }
            parameters["date"] = .string("\(year)/\(month)/\(day)")
            parameters["hour"] = .integer(hour)
            parameters["minute"] = .integer(minute)
            parameters["second"] = .integer(second)
        }
        guard current.dateFormat != dateFormat
                || current.timeFormat != timeFormat
                || current.timeZone != settings.timeZone
                || current.isNetworkTimeEnabled != settings.isNetworkTimeEnabled
                || current.timeServers != servers
                || (!settings.isNetworkTimeEnabled
                    && current.manualDate != settings.manualDate) else {
            return
        }
        try await callVoid(
            DsmAPIName.coreRegionNTP,
            method: "set",
            version: 3,
            parameters: parameters
        )
        let verified = try await loadRegionSettings()
        guard verified.dateFormat == dateFormat,
              verified.timeFormat == timeFormat,
              verified.timeZone == settings.timeZone,
              verified.isNetworkTimeEnabled == settings.isNetworkTimeEnabled,
              (!settings.isNetworkTimeEnabled || verified.timeServers == servers) else {
            throw verificationError(L10n.string("shared.6c186cb11546be49"))
        }
    }

    public func loadDDNS() async throws -> NasDDNSDirectory {
        let providerValue = try await call(DsmAPIName.coreDDNSProvider, method: "list")
        let recordValue = try await call(DsmAPIName.coreDDNSRecord, method: "list")
        let providerObjects = providerValue.objects("providers")
        var providerOrder: [String] = []
        var providerByID: [String: NasDDNSProvider] = [:]
        for item in providerObjects {
            guard let id = item["id"]?.scalarString
                    ?? item["provider"]?.scalarString,
                  !id.isEmpty else {
                continue
            }
            let provider = NasDDNSProvider(
                id: id,
                displayName: item["display"]?.scalarString
                    ?? item["name"]?.scalarString
                    ?? id
            )
            if let existing = providerByID[id] {
                // DSM 可能按协议类型重复列出同一服务商；保留更友好的显示名称。
                if existing.displayName == id, provider.displayName != id {
                    providerByID[id] = provider
                }
            } else {
                providerOrder.append(id)
                providerByID[id] = provider
            }
        }
        let providers = providerOrder.compactMap { providerByID[$0] }
        let names = providers.reduce(into: [String: String]()) {
            $0[$1.id] = $1.displayName
        }
        let records = recordValue.objects("records").compactMap { item -> NasDDNSRecord? in
            guard let provider = item["provider"]?.scalarString,
                  let hostname = item["hostname"]?.scalarString,
                  !provider.isEmpty, !hostname.isEmpty else {
                return nil
            }
            let ipv4 = item["ip"]?.scalarString
            let ipv6 = item["ipv6"]?.scalarString
            let addresses = [ipv4, ipv6].compactMap { address -> String? in
                guard let address,
                      !["", "0.0.0.0", "0:0:0:0:0:0:0:0"].contains(address) else {
                    return nil
                }
                return address
            }
            return NasDDNSRecord(
                id: provider,
                providerID: provider,
                providerName: names[provider] ?? provider,
                hostname: hostname,
                address: addresses.isEmpty ? nil : addresses.joined(separator: " / "),
                status: item["status"]?.scalarString,
                lastUpdated: item["lastupdated"]?.scalarString,
                isEnabled: item["enable"]?.scalarBoolean ?? false,
                username: item["username"]?.scalarString,
                networkType: item["net"]?.scalarString,
                ipv4: ipv4,
                ipv6: ipv6,
                interfaceV4: item["interface_v4"]?.scalarString,
                interfaceV6: item["interface_v6"]?.scalarString,
                heartbeat: item["heartbeat"]?.scalarBoolean ?? false
            )
        }
        return NasDDNSDirectory(providers: providers, records: records)
    }

    public func saveDDNS(_ draft: NasDDNSDraft) async throws {
        let directory = try await loadDDNS()
        guard directory.providers.contains(where: { $0.id == draft.providerID }) else {
            throw verificationError(L10n.string("shared.1ba0507d4c0c3090"))
        }
        let hostname = draft.hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = draft.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidHostname(hostname) else {
            throw verificationError(L10n.string("shared.9e1b725d1515431e"))
        }
        guard !username.isEmpty else {
            throw verificationError(L10n.string("shared.888eb410ef3a01da"))
        }
        if draft.originalProviderID == nil {
            guard draft.providerID == "Synology" || !draft.password.isEmpty else {
                throw verificationError(L10n.string("shared.bc264628bb87388d"))
            }
            guard !directory.records.contains(where: { $0.providerID == draft.providerID }) else {
                throw AppError(
                    category: .conflict,
                    isRetryable: false,
                    safeUserMessage: L10n.string("shared.864f876a4eadf507")
                )
            }
        }
        var parameters = Self.ddnsParameters(draft, hostname: hostname, username: username)
        if draft.password.isEmpty, draft.providerID != "Synology" {
            parameters.removeValue(forKey: "passwd")
        }
        try await callVoid(
            DsmAPIName.coreDDNSRecord,
            method: "test",
            parameters: parameters
        )
        try await callVoid(
            DsmAPIName.coreDDNSRecord,
            method: draft.originalProviderID == nil ? "create" : "set",
            parameters: parameters
        )
        try await callVoid(
            DsmAPIName.coreDDNSRecord,
            method: "update_ip_address",
            parameters: ["id": .string(draft.providerID)]
        )
        let verified = try await loadDDNS()
        guard let saved = verified.records.first(where: { $0.providerID == draft.providerID }),
              saved.hostname == hostname,
              saved.username == username,
              saved.isEnabled == draft.isEnabled else {
            throw verificationError(L10n.string("shared.dd472a06a448e1b0"))
        }
    }

    public func deleteDDNS(providerID: String) async throws {
        let current = try await loadDDNS()
        guard current.records.contains(where: { $0.providerID == providerID }) else { return }
        try await callVoid(
            DsmAPIName.coreDDNSRecord,
            method: "delete",
            parameters: ["id": .stringArray([providerID])]
        )
        let verified = try await loadDDNS()
        guard !verified.records.contains(where: { $0.providerID == providerID }) else {
            throw verificationError(L10n.string("shared.60be7160962c7372"))
        }
    }

    public func refreshDDNS() async throws {
        try await callVoid(DsmAPIName.coreDDNSRecord, method: "update_ip_address")
        _ = try await loadDDNS()
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
            let smartStatus = item.string(["smart_status"])
            return NasDisk(
                id: id,
                deviceID: item.string(["device"]) ?? id,
                name: item.string(["longName", "name", "device"]) ?? L10n.string("shared.c89654ab90e80308", String(describing: index + 1)),
                vendor: item.string(["vendor"]),
                model: item.string(["model"]),
                type: item.string(["diskType", "portType"]),
                totalBytes: item.integer(["size_total"]),
                status: item.string([
                    "summary_status_key",
                    "drive_status_key",
                    "overview_status",
                    "status"
                ]),
                smartStatus: smartStatus,
                temperatureCelsius: item.number(["temp"]),
                isSSD: item.boolean(["isSsd"]) ?? false,
                usedBy: item.string(["used_by", "allocation_role"]),
                supportsSmartTest: item.boolean(["smart_test_support"]) ?? (smartStatus != nil),
                serialNumber: item.string(["serial"]),
                firmwareVersion: item.string(["firm"]),
                location: item["container"]?.string(["str"]),
                is4KNative: item.boolean(["is4Kn"]),
                estimatedLifePercent: item.integer(["remain_life"]).flatMap { value in
                    value >= 0 ? Int(value) : nil
                },
                badSectorCount: item.integer(["unc"]).flatMap { value in
                    value >= 0 ? Int(value) : nil
                }
            )
        }
        storageDisks = disks.reduce(into: [:]) { result, disk in
            result[disk.id] = disk
        }
        let pools = value.objects("storagePools").enumerated().map { index, raw in
            let item = DsmDynamicJSON.object(raw)
            let id = item.string(["id", "uuid", "num_id"]) ?? "pool-\(index)"
            let size = item["size"] ?? .object([:])
            return NasStoragePool(
                id: id,
                name: item.string(["desc", "vol_desc"]) ?? L10n.string("shared.cecdcf599fc46c06", String(describing: index + 1)),
                raidType: item.string(["raidType", "device_type"]),
                status: item.string(["summary_status", "status", "space_status"]),
                totalBytes: size.integer(["total"]),
                usedBytes: size.integer(["used"]),
                isWritable: item.boolean(["is_writable"]) ?? false,
                isScrubbing: item.boolean(["data_scrubbing", "is_actioning"]) ?? false,
                nextScrubbingDate: Self.date(from: item.string(["next_schedule_time"])),
                diskIDs: item.strings(["disks"]),
                spareDiskIDs: item.strings(["spares"]),
                supportsMultipleVolumes: item.string(["raidType"]).map { $0 != "single" }
            )
        }
        let volumes = value.objects("volumes").enumerated().map { index, raw in
            let item = DsmDynamicJSON.object(raw)
            let id = item.string(["id", "uuid", "vol_path"]) ?? "volume-\(index)"
            let size = item["size"] ?? .object([:])
            return NasVolume(
                id: id,
                name: item.string(["vol_desc", "desc", "vol_path"]) ?? L10n.string("shared.e2687545daa50cb0", String(describing: index + 1)),
                fileSystem: item.string(["fs_type"]),
                status: item.string(["summary_status", "status", "space_status"]),
                totalBytes: size.integer(["total"]),
                usedBytes: size.integer(["used"]),
                isEncrypted: item.boolean(["is_encrypted"]) ?? false,
                isWritable: item.boolean(["is_writable"]) ?? false,
                poolID: item.string(["pool_path"]),
                path: item.string(["vol_path"])
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

    public func loadDiskTestStatus(diskID: String) async throws -> NasDiskTestStatus {
        let disk = try await validatedStorageDisk(id: diskID)
        guard disk.supportsSmartTest else {
            throw AppError(
                category: .apiUnavailable,
                isRetryable: false,
                safeUserMessage: L10n.string("shared.edb18b7e9cd3b114")
            )
        }
        return try await loadDiskTestStatus(for: disk, includesHistory: true)
    }

    private func loadDiskTestStatus(
        for disk: NasDisk,
        includesHistory: Bool
    ) async throws -> NasDiskTestStatus {
        let value = try await call(
            DsmAPIName.coreStorageDisk,
            method: "get_smart_test_log",
            parameters: ["device": .string(disk.deviceID)]
        )
        let latest = value.objects("testInfo").first.map(DsmDynamicJSON.object)
        let isRunning = latest?.boolean(["testing", "is_testing"]) ?? false
        let isBusyWithOtherTest = !isRunning && (
            latest?.boolean(["ihm_testing"]) == true
                || latest?.boolean(["perf_testing"]) == true
        )
        let rawType = latest?.string(["test_type", "testType", "type"])?.lowercased()
        let runningType: NasDiskTestType?
        if rawType == "quick" {
            runningType = .quick
        } else if rawType == "extend" || rawType == "extended" {
            runningType = .extended
        } else {
            runningType = nil
        }
        let history: DiskTestHistorySnapshot
        if includesHistory {
            history = try await loadDiskTestHistory(for: disk)
            diskTestHistories[disk.id] = history
        } else {
            history = diskTestHistories[disk.id] ?? .unavailable
        }
        return NasDiskTestStatus(
            diskID: disk.id,
            isRunning: isRunning,
            isBusyWithOtherTest: isBusyWithOtherTest,
            runningType: isRunning ? runningType : nil,
            progressDescription: latest?.string(["remain", "progress"]),
            lastQuickTest: history.lastQuickTest,
            lastExtendedTest: history.lastExtendedTest,
            lastResult: latest?.string(["latest_test_result", "result"])
                ?? history.latestResult,
            isHistoryAvailable: history.isAvailable
        )
    }

    private func loadDiskTestHistory(for disk: NasDisk) async throws -> DiskTestHistorySnapshot {
        let value: DsmDynamicJSON
        do {
            value = try await call(
                DsmAPIName.coreStorageDisk,
                method: "disk_test_log_get",
                parameters: [
                    "device": .string(disk.deviceID),
                    "offset": .integer(0),
                    "limit": .integer(100),
                    "sort_by": .string("time"),
                    "sort_direction": .string("DESC"),
                    "type": .string("smart")
                ]
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .unavailable
        }

        let logs = value.objects("testLog").map(DsmDynamicJSON.object)
        let smartLogs = logs.filter {
            $0.string(["type"])?.lowercased() == "smart"
                || $0.string(["test_type"]) != nil
        }
        let quick = smartLogs.first { $0.string(["test_type"])?.lowercased() == "quick" }
        let extended = smartLogs.first {
            let type = $0.string(["test_type"])?.lowercased()
            return type == "extend" || type == "extended"
        }
        return DiskTestHistorySnapshot(
            lastQuickTest: quick?.string(["time"]),
            lastExtendedTest: extended?.string(["time"]),
            latestResult: smartLogs.first?.string(["result"]),
            isAvailable: true
        )
    }

    public func startDiskTest(
        diskID: String,
        type: NasDiskTestType
    ) async throws -> NasDiskTestStatus {
        let disk = try await validatedStorageDisk(id: diskID)
        guard disk.supportsSmartTest else {
            throw AppError(
                category: .apiUnavailable,
                isRetryable: false,
                safeUserMessage: L10n.string("shared.edb18b7e9cd3b114")
            )
        }
        let current = try await loadDiskTestStatus(for: disk, includesHistory: false)
        guard !current.isRunning else {
            throw AppError(
                category: .conflict,
                isRetryable: true,
                safeUserMessage: L10n.string("shared.0eb619b75fdbcff5")
            )
        }
        guard !current.isBusyWithOtherTest else {
            throw AppError(
                category: .conflict,
                isRetryable: true,
                safeUserMessage: L10n.string("shared.b8c5b11d9fc2c1f5")
            )
        }

        try await callVoid(
            DsmAPIName.coreStorageDisk,
            method: "do_smart_test",
            parameters: [
                "device": .string(disk.deviceID),
                "type": .string(type == .quick ? "quick" : "extend")
            ]
        )

        for attempt in 0..<6 {
            if attempt > 0 {
                try await Task.sleep(for: .seconds(1))
            }
            let verified = try await loadDiskTestStatus(for: disk, includesHistory: false)
            if verified.isRunning {
                return verified
            }
        }
        throw AppError(
            category: .conflict,
            isRetryable: true,
            safeUserMessage: L10n.string("shared.ddef2b60c5d885df")
        )
    }

    public func stopDiskTest(diskID: String) async throws -> NasDiskTestStatus {
        let disk = try await validatedStorageDisk(id: diskID)
        guard disk.supportsSmartTest else {
            throw AppError(
                category: .apiUnavailable,
                isRetryable: false,
                safeUserMessage: L10n.string("shared.edb18b7e9cd3b114")
            )
        }
        let current = try await loadDiskTestStatus(for: disk, includesHistory: false)
        guard current.isRunning else {
            return current
        }

        try await callVoid(
            DsmAPIName.coreStorageDisk,
            method: "do_smart_test",
            parameters: [
                "device": .string(disk.deviceID),
                "type": .string("stop")
            ]
        )

        for attempt in 0..<6 {
            if attempt > 0 {
                try await Task.sleep(for: .seconds(1))
            }
            let verified = try await loadDiskTestStatus(for: disk, includesHistory: false)
            if !verified.isRunning {
                return verified
            }
        }
        throw AppError(
            category: .conflict,
            isRetryable: true,
            safeUserMessage: L10n.string("shared.9681fb468adf10c2")
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
                    "install_type",
                    "startable",
                    "dsm_apps",
                    "available_operation",
                    "ctl_uninstall"
                ])
            ]
        )

        var metadata: [String: PackageControlMetadata] = [:]
        var packages = value.objects("packages").compactMap { raw -> NasPackage? in
            let item = DsmDynamicJSON.object(raw)
            guard let id = item.string(["id", "name"]) else { return nil }
            let additional = item["additional"] ?? .object([:])
            let rawStatus = additional.string(["status", "status_code"])
            let rawOrigin = additional.string(["status_origin"])
            let rawDesc = additional.string(["status_description"])
            let isRunning = (rawStatus?.lowercased() == "running" || rawStatus?.lowercased() == "active" || rawOrigin?.lowercased().contains("active") == true)
            let startable = additional.boolean(["startable"]) ?? true
            let installType = additional.string(["install_type"])
            let availableOperations = Set(additional.strings(["available_operation"]).map {
                $0.lowercased()
            })
            let hasOperationList = !availableOperations.isEmpty
            let canStart = startable && !isRunning
                && (!hasOperationList || availableOperations.contains("start"))
            let canStop = startable && isRunning
                && (!hasOperationList || availableOperations.contains("stop"))
            let canUninstall = installType?.lowercased() != "system"
                && (additional.boolean(["ctl_uninstall"]) ?? true)
                && (!hasOperationList || availableOperations.contains("uninstall"))

            metadata[id] = PackageControlMetadata(
                dsmApps: additional.strings(["dsm_apps"])
            )

            // 精细化清洗后台底层状态日志，避免暴露英文调试文本
            let formattedStatusDesc = cleanPackageStatusDescription(status: rawStatus, rawOrigin: rawOrigin, rawDesc: rawDesc)

            return NasPackage(
                id: id,
                name: item.string(["name"]) ?? id,
                version: item.string(["version"]),
                status: rawStatus,
                statusDescription: formattedStatusDesc,
                packageDescription: additional.string(["description"]),
                installType: installType,
                installedAt: item.number(["timestamp"]).map {
                    Date(timeIntervalSince1970: $0 > 10_000_000_000 ? $0 / 1_000 : $0)
                },
                iconData: nil,
                canStart: canStart,
                canStop: canStop,
                canUninstall: canUninstall,
                // 更新需要安装来源、空间与依赖检查，不能复用列表接口直接触发。
                canUpgrade: false
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        packageControlMetadata = metadata

        guard let iconCapability = capabilities[DsmAPIName.corePackageThumb],
              let iconVersion = iconCapability.selectedVersion else {
            return packages
        }
        for index in packages.indices {
            let key = Self.packageIconCacheKey(packages[index])
            if let cached = packageIconCache[key] {
                packages[index] = Self.package(packages[index], iconData: cached)
            }
        }
        let missingIndices = packages.indices.filter { packages[$0].iconData == nil }
        for batchStart in stride(from: 0, to: missingIndices.count, by: 8) {
            let indices = Array(
                missingIndices[batchStart..<min(batchStart + 8, missingIndices.count)]
            )
            let resolved = await withTaskGroup(
                of: (Int, Data?).self,
                returning: [Int: Data].self
            ) { group in
                for index in indices {
                    let package = packages[index]
                    group.addTask { [client, credential, transport] in
                        let data = await Self.loadPackageIcon(
                            package: package,
                            capability: iconCapability,
                            version: iconVersion,
                            baseURL: client.baseURL,
                            credential: credential,
                            transport: transport
                        )
                        return (index, data)
                    }
                }
                var icons: [Int: Data] = [:]
                for await (index, data) in group {
                    icons[index] = data
                }
                return icons
            }
            for index in indices {
                if let iconData = resolved[index] {
                    packageIconCache[Self.packageIconCacheKey(packages[index])] = iconData
                    packages[index] = Self.package(packages[index], iconData: iconData)
                }
            }
        }
        if packageIconCache.count > 256 {
            let currentKeys = Set(packages.map(Self.packageIconCacheKey))
            packageIconCache = packageIconCache.filter { currentKeys.contains($0.key) }
        }
        return packages
    }

    public func controlPackage(id: String, action: NasPackageAction) async throws {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else {
            throw AppError(
                category: .notFound,
                isRetryable: false,
                safeUserMessage: L10n.string("shared.86d86e549eb9d8ba")
            )
        }
        guard action != .upgrade else {
            throw AppError(
                category: .apiUnavailable,
                isRetryable: false,
                safeUserMessage: L10n.string("shared.c6caf25d12b5e5da")
            )
        }

        let checkType: String
        switch action {
        case .start: checkType = "start_check"
        case .stop: checkType = "stop_check"
        case .uninstall: checkType = "uninstall_check"
        case .upgrade: return
        }
        try await callVoid(
            DsmAPIName.corePackage,
            method: "feasibility_check",
            parameters: [
                "type": .string(checkType),
                "packages": .stringArray([normalizedID])
            ]
        )

        let metadata = packageControlMetadata[normalizedID]
        switch action {
        case .start:
            try await callVoid(
                DsmAPIName.corePackageControl,
                method: "start",
                parameters: [
                    "id": .string(normalizedID),
                    "dsm_apps": .stringArray(metadata?.dsmApps ?? [])
                ]
            )
        case .stop:
            try await callVoid(
                DsmAPIName.corePackageControl,
                method: "stop",
                parameters: ["id": .string(normalizedID)]
            )
        case .uninstall:
            try await callVoid(
                DsmAPIName.corePackageUninstallation,
                method: "uninstall",
                parameters: [
                    "id": .string(normalizedID),
                    "dsm_apps": .stringArray(metadata?.dsmApps ?? [])
                ]
            )
        case .upgrade:
            return
        }
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
        let system = try await call(
            DsmAPIName.coreSystem,
            method: "info",
            parameters: [:]
        )
        let updateResponse = try await call(
            DsmAPIName.coreUpgradeServer,
            method: "check",
            version: 3,
            parameters: [
                "user_reading": .boolean(true),
                "need_auto_smallupdate": .boolean(true),
                "need_promotion": .boolean(false)
            ]
        )
        let update = updateResponse["update"] ?? .null
        let latestVersion = update.string(["version"])
        return NasSystemUpdateInfo(
            isUpdateAvailable: latestVersion?.isEmpty == false,
            currentVersion: system.string(["firmware_ver", "version"]),
            latestVersion: latestVersion,
            releaseNotes: update.string([
                "release_note",
                "release_notes",
                "whats_new",
                "description"
            ])
        )
    }

    public func loadScheduledTasks() async throws -> [NasScheduledTask] {
        let value = try await call(
            DsmAPIName.coreTaskScheduler,
            method: "list",
            version: 3,
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
                realOwner: item.string(["real_owner"]),
                type: item.string(["type"]),
                action: item.string(["action"]),
                isEnabled: item.boolean(["enable"]) ?? false,
                nextTriggerDescription: item.string(["next_trigger_time"]),
                canRun: item.boolean(["can_run"]) ?? false,
                canEdit: item.boolean(["can_edit"]) ?? false
            )
        }
    }

    public func loadScheduledTaskDraft(
        id: Int?,
        realOwner: String?
    ) async throws -> NasScheduledTaskDraft {
        var parameters: [String: DsmParameterValue] = [
            "id": .integer(id ?? -1)
        ]
        if let realOwner, !realOwner.isEmpty {
            parameters["real_owner"] = .string(realOwner)
        }
        if id == nil {
            parameters["type"] = .string("script")
        }
        let value = try await call(
            DsmAPIName.coreTaskScheduler,
            method: "get",
            version: 4,
            parameters: parameters
        )
        let schedule = value["schedule"] ?? .object([:])
        let extra = value["extra"] ?? .object([:])
        return NasScheduledTaskDraft(
            id: id,
            name: value.string(["name"]) ?? "",
            owner: value.string(["owner", "real_owner"]) ?? realOwner ?? "",
            realOwner: value.string(["real_owner"]) ?? realOwner,
            isEnabled: value.boolean(["enable"]) ?? true,
            script: extra.string(["script"]) ?? "",
            notifyOnError: extra.boolean(["notify_if_error"]) ?? false,
            notificationEmails: extra.string(["notify_mail"]) ?? "",
            schedule: NasTaskSchedule(
                dateType: Int(schedule.number(["date_type"]) ?? 0),
                weekDays: schedule.string(["week_day"]) ?? "0,1,2,3,4,5,6",
                date: schedule.string(["date"]),
                repeatDate: Int(schedule.number(["repeat_date"]) ?? 1001),
                monthlyWeek: schedule["monthly_week"]?.array?.compactMap {
                    $0.scalarNumber.map(Int.init)
                } ?? [],
                hour: Int(schedule.number(["hour"]) ?? 0),
                minute: Int(schedule.number(["minute"]) ?? 0),
                repeatHour: Int(schedule.number(["repeat_hour"]) ?? 0),
                repeatMinute: Int(schedule.number(["repeat_min"]) ?? 0),
                lastWorkHour: Int(schedule.number(["last_work_hour"]) ?? 0)
            )
        )
    }

    public func loadScheduledTaskResults(
        taskName: String
    ) async throws -> [NasScheduledTaskResult] {
        let name = taskName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw AppError(
                category: .invalidResponse,
                isRetryable: false,
                safeUserMessage: L10n.string("shared.06669846e8a043c1")
            )
        }
        let value = try await call(
            DsmAPIName.coreEventScheduler,
            method: "result_list",
            parameters: ["task_name": .string(name)]
        )
        let rows = value.array ?? value["results"]?.array ?? []
        return Array(rows.compactMap { raw -> NasScheduledTaskResult? in
            guard let resultID = raw.string(["result_id", "id"]) else { return nil }
            let exitInfo = raw["exit_info"] ?? .object([:])
            return NasScheduledTaskResult(
                id: resultID,
                taskName: raw.string(["task_name"]) ?? name,
                startedAt: Self.date(from: raw.string(["start_time"])),
                stoppedAt: Self.date(from: raw.string(["stop_time"])),
                exitType: exitInfo.string(["exit_type"]) ?? raw.string(["exit_type"]),
                exitCode: (
                    exitInfo.integer(["exit_code"])
                        ?? raw.integer(["exit_code"])
                ).map(Int.init),
                triggerEvent: raw.string(["trigger_event"])
            )
        }.reversed())
    }

    public func loadScheduledTaskResultOutput(
        taskName: String,
        resultID: String
    ) async throws -> NasScheduledTaskResultOutput {
        let name = taskName.trimmingCharacters(in: .whitespacesAndNewlines)
        let identifier = resultID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !identifier.isEmpty else {
            throw AppError(
                category: .invalidResponse,
                isRetryable: false,
                safeUserMessage: L10n.string("shared.e72bfeedb9c72727")
            )
        }
        let value = try await call(
            DsmAPIName.coreEventScheduler,
            method: "result_get_file",
            parameters: [
                "task_name": .string(name),
                "result_id": .string(identifier)
            ]
        )
        return NasScheduledTaskResultOutput(
            command: value.string(["script_in"]),
            output: value.string(["script_out"])
        )
    }

    public func saveScheduledTask(_ draft: NasScheduledTaskDraft) async throws {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOwner = draft.owner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedOwner.isEmpty, !draft.script.isEmpty else {
            throw AppError(
                category: .invalidResponse,
                isRetryable: false,
                safeUserMessage: L10n.string("shared.56b9ed2bd4038953")
            )
        }

        var parameters: [String: DsmParameterValue] = [
            "name": .string(trimmedName),
            "owner": .string(trimmedOwner),
            "enable": .boolean(draft.isEnabled),
            "type": .string("script"),
            "schedule": .object(Self.taskScheduleParameters(draft.schedule)),
            "extra": .object([
                "script": .string(draft.script),
                "notify_enable": .boolean(
                    draft.notifyOnError || !draft.notificationEmails.isEmpty
                ),
                "notify_if_error": .boolean(draft.notifyOnError),
                "notify_mail": .string(draft.notificationEmails)
            ])
        ]
        if let id = draft.id {
            parameters["id"] = .integer(id)
        }
        if let realOwner = draft.realOwner, !realOwner.isEmpty {
            parameters["real_owner"] = .string(realOwner)
        }
        try await callVoid(
            DsmAPIName.coreTaskScheduler,
            method: draft.id == nil ? "create" : "set",
            version: 4,
            parameters: parameters
        )
    }

    public func setScheduledTaskEnabled(
        id: Int,
        realOwner: String?,
        enabled: Bool
    ) async throws {
        try await taskCommand(
            method: "set_enable",
            id: id,
            realOwner: realOwner,
            additional: ["enable": .boolean(enabled)]
        )
    }

    public func runScheduledTask(id: Int, realOwner: String?) async throws {
        try await taskCommand(method: "run", id: id, realOwner: realOwner)
    }

    public func deleteScheduledTask(id: Int, realOwner: String?) async throws {
        try await taskCommand(method: "delete", id: id, realOwner: realOwner)
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
                    "expired",
                    "groups",
                    "can_edit",
                    "can_delete"
                ])
            ]
        )
        async let groupsValue = call(
            DsmAPIName.coreGroup,
            method: "list",
            parameters: [
                "offset": .integer(0),
                "limit": .integer(1_000),
                "additional": .stringArray([
                    "gid",
                    "description",
                    "can_edit",
                    "can_delete"
                ])
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
                groups: item["groups"] == nil ? nil : item.strings(["groups"]),
                isExpired: item.boolean(["expired"]) ?? false,
                canEdit: item.boolean(["can_edit"]) ?? true,
                canDelete: item.boolean(["can_delete"])
                    ?? !["admin", "guest"].contains(name.lowercased())
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
                description: item.string(["description"]),
                canEdit: item.boolean(["can_edit"]) ?? true,
                canDelete: item.boolean(["can_delete"])
                    ?? !["administrators", "users", "http"].contains(name.lowercased())
            )
        }
        return NasAccountDirectory(users: users, groups: groups)
    }

    public func saveAccount(_ draft: NasAccountDraft) async throws {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw AppError(
                category: .invalidResponse,
                isRetryable: false,
                safeUserMessage: L10n.string("shared.f4697c2ce8685eba")
            )
        }
        if draft.originalName == nil {
            guard !draft.password.isEmpty,
                  draft.password == draft.passwordConfirmation else {
                throw AppError(
                    category: .invalidResponse,
                    isRetryable: false,
                    safeUserMessage: L10n.string("shared.9c544f72c057fa2f")
                )
            }
        } else if !draft.password.isEmpty,
                  draft.password != draft.passwordConfirmation {
            throw AppError(
                category: .invalidResponse,
                isRetryable: false,
                safeUserMessage: L10n.string("shared.e4a4a3382011b139")
            )
        }

        var parameters: [String: DsmParameterValue] = [
            "name": .string(draft.originalName ?? name),
            "description": .string(draft.description),
            "email": .string(draft.email),
            "expired": .boolean(draft.isExpired)
        ]
        if let groups = draft.groups {
            parameters["groups"] = .stringArray(groups)
        }
        if draft.originalName == nil {
            parameters["password"] = .string(draft.password)
            parameters["password_confirm"] = .string(draft.passwordConfirmation)
        } else if !draft.password.isEmpty {
            parameters["password"] = .string(draft.password)
            parameters["password_confirm"] = .string(draft.passwordConfirmation)
        }
        try await callVoid(
            DsmAPIName.coreUser,
            method: draft.originalName == nil ? "create" : "set",
            parameters: parameters
        )
    }

    public func deleteAccount(name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !["admin", "guest"].contains(trimmed.lowercased()) else {
            throw AppError(
                category: .permissionDenied,
                isRetryable: false,
                safeUserMessage: L10n.string("shared.917cb22bc73cc211")
            )
        }
        try await callVoid(
            DsmAPIName.coreUser,
            method: "delete",
            parameters: ["name": .stringArray([trimmed])]
        )
    }

    public func saveGroup(_ draft: NasGroupDraft) async throws {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw AppError(
                category: .invalidResponse,
                isRetryable: false,
                safeUserMessage: L10n.string("shared.56a567d51676e519")
            )
        }
        try await callVoid(
            DsmAPIName.coreGroup,
            method: draft.originalName == nil ? "create" : "set",
            parameters: [
                "name": .string(draft.originalName ?? name),
                "description": .string(draft.description)
            ]
        )
    }

    public func deleteGroup(name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !["administrators", "users", "http"].contains(trimmed.lowercased()) else {
            throw AppError(
                category: .permissionDenied,
                isRetryable: false,
                safeUserMessage: L10n.string("shared.966bbfaa2a0d098a")
            )
        }
        try await callVoid(
            DsmAPIName.coreGroup,
            method: "delete",
            parameters: ["name": .stringArray([trimmed])]
        )
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
                processID: item.string(["pid"]),
                deviceID: item.string(["did"]),
                account: account,
                source: item.string(["from"]),
                location: item.string(["location"]),
                protocolName: item.string(["protocol"]),
                type: item.string(["type"]),
                connectedAt: Self.date(from: time),
                description: item.string(["descr"]),
                isCurrentConnection: item.boolean(["is_current_connected"])
                    ?? (item.string(["who"]) == currentUsername),
                canDisconnect: item.boolean(["can_be_kicked"]) ?? false
            )
        }
        return NasConnectionPage(
            connections: connections,
            total: Int(value.number(["total"]) ?? Double(connections.count))
        )
    }

    public func disconnectConnection(_ connection: NasConnection) async throws {
        guard connection.canDisconnect else {
            throw AppError(
                category: .permissionDenied,
                isRetryable: false,
                safeUserMessage: L10n.string("shared.59ee3335304d8042")
            )
        }

        let common: [String: DsmJSONValue] = [
            "who": .string(connection.account),
            "from": .string(connection.source ?? "")
        ]
        let serviceConnections: [[String: DsmJSONValue]]
        let httpConnections: [[String: DsmJSONValue]]
        if connection.type?.uppercased() == "HTTP/HTTPS" {
            guard let deviceID = connection.deviceID, !deviceID.isEmpty else {
                throw unavailableError()
            }
            serviceConnections = []
            httpConnections = [
                common.merging([
                    "did": .string(deviceID),
                    "descr": .string(connection.description ?? "")
                ]) { _, new in new }
            ]
        } else {
            guard let processID = connection.processID, !processID.isEmpty else {
                throw unavailableError()
            }
            serviceConnections = [
                common.merging([
                    "pid": .string(processID),
                    "type": .string(connection.type ?? "")
                ]) { _, new in new }
            ]
            httpConnections = []
        }

        try await callVoid(
            DsmAPIName.coreCurrentConnection,
            method: "kick_connection",
            parameters: [
                "service_conn": .objectArray(serviceConnections),
                "http_conn": .objectArray(httpConnections)
            ]
        )
    }

    private func validatedStorageDisk(id: String) async throws -> NasDisk {
        if let disk = storageDisks[id] {
            return disk
        }
        _ = try await loadStorage()
        guard let disk = storageDisks[id] else {
            throw AppError(
                category: .conflict,
                isRetryable: false,
                safeUserMessage: L10n.string("shared.e8513b25080428db")
            )
        }
        return disk
    }

    private func call(
        _ name: String,
        method: String,
        version requestedVersion: Int? = nil,
        parameters: [String: DsmParameterValue] = [:]
    ) async throws -> DsmDynamicJSON {
        guard let capability = capabilities[name],
              let selectedVersion = capability.selectedVersion else {
            throw unavailableError()
        }
        let version = requestedVersion ?? selectedVersion
        guard capability.minVersion...capability.maxVersion ~= version else {
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

    private func taskCommand(
        method: String,
        id: Int,
        realOwner: String?,
        additional: [String: DsmParameterValue] = [:]
    ) async throws {
        var parameters = additional
        parameters["id"] = .integer(id)
        if let realOwner, !realOwner.isEmpty {
            parameters["real_owner"] = .string(realOwner)
        }
        try await callVoid(
            DsmAPIName.coreTaskScheduler,
            method: method,
            version: 3,
            parameters: parameters
        )
    }

    private static func taskScheduleParameters(
        _ schedule: NasTaskSchedule
    ) -> [String: DsmJSONValue] {
        var result: [String: DsmJSONValue] = [
            "date_type": .integer(schedule.dateType),
            "week_day": .string(schedule.weekDays),
            "repeat_date": .integer(schedule.repeatDate),
            "monthly_week": .array(schedule.monthlyWeek.map(DsmJSONValue.integer)),
            "hour": .integer(schedule.hour),
            "minute": .integer(schedule.minute),
            "repeat_hour": .integer(schedule.repeatHour),
            "repeat_min": .integer(schedule.repeatMinute),
            "last_work_hour": .integer(schedule.lastWorkHour),
            "repeat_min_store_config": .array([1, 5, 10, 15, 20, 30].map(DsmJSONValue.integer)),
            "repeat_hour_store_config": .array(
                Array(1...23).map(DsmJSONValue.integer)
            )
        ]
        if let date = schedule.date, !date.isEmpty {
            result["date"] = .string(date)
        }
        return result
    }

    private func callVoid(
        _ name: String,
        method: String,
        version requestedVersion: Int? = nil,
        parameters: [String: DsmParameterValue] = [:]
    ) async throws {
        guard let capability = capabilities[name],
              let selectedVersion = capability.selectedVersion else {
            throw unavailableError()
        }
        let version = requestedVersion ?? selectedVersion
        guard capability.minVersion...capability.maxVersion ~= version else {
            throw unavailableError()
        }
        do {
            try await client.callVoid(
                path: capability.path,
                api: capability.name,
                version: version,
                method: method,
                requestFormat: capability.requestFormat,
                parameters: parameters,
                credential: credential
            )
        } catch let error as DsmNetworkError {
            throw DsmErrorMapper.map(error)
        }
    }

    private func unavailableError() -> AppError {
        AppError(
            category: .apiUnavailable,
            isRetryable: false,
            safeUserMessage: L10n.string("shared.45f2d65c5f20a7b9")
        )
    }

    private func verificationError(_ message: String) -> AppError {
        AppError(
            category: .invalidResponse,
            isRetryable: true,
            safeUserMessage: message
        )
    }

    private static func validatePort(_ port: Int) throws {
        guard 1...65_535 ~= port else {
            throw AppError(
                category: .invalidResponse,
                isRetryable: false,
                safeUserMessage: L10n.string("shared.8a6549bde9979b57")
            )
        }
    }

    private static func appendChangedBoolean(
        _ expected: Bool?,
        _ current: Bool?,
        key: String,
        to parameters: inout [String: DsmParameterValue]
    ) {
        if let expected, expected != current {
            parameters[key] = .boolean(expected)
        }
    }

    private static func regionDate(
        date: String?,
        hour: Int?,
        minute: Int?,
        second: Int?
    ) -> Date? {
        guard let date else { return nil }
        let parts = date.split(separator: "/").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = hour ?? 0
        components.minute = minute ?? 0
        components.second = second ?? 0
        return components.date
    }

    private static func isValidTimeServer(_ value: String) -> Bool {
        guard value.count <= 253, !value.isEmpty,
              value.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:")
                      .contains($0)
              }) else {
            return false
        }
        return !value.hasPrefix(".") && !value.hasSuffix(".") && !value.contains("..")
    }

    private static func isValidHostname(_ value: String) -> Bool {
        guard value.count <= 253, !value.isEmpty,
              value.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
                      .contains($0)
              }) else {
            return false
        }
        return !value.hasPrefix(".") && !value.hasSuffix(".") && !value.contains("..")
    }

    private static func ddnsParameters(
        _ draft: NasDDNSDraft,
        hostname: String,
        username: String
    ) -> [String: DsmParameterValue] {
        var result: [String: DsmParameterValue] = [
            "enable": .boolean(draft.isEnabled),
            "provider": .string(draft.providerID),
            "hostname": .string(hostname),
            "username": .string(username),
            "net": .string(draft.networkType),
            "ip": .string(draft.ipv4),
            "ipv6": .string(draft.ipv6),
            "interface_v4": .string(draft.interfaceV4),
            "interface_v6": .string(draft.interfaceV6),
            "heartbeat": .boolean(draft.heartbeat)
        ]
        if let original = draft.originalProviderID {
            result["id"] = .string(original)
        }
        if draft.providerID == "Synology" {
            result["passwd"] = .string("Synology")
        } else if !draft.password.isEmpty {
            result["passwd"] = .string(draft.password)
        }
        return result
    }

    private static func upsSettings(from value: DsmDynamicJSON?) -> NasUPSSettings? {
        guard let value,
              let enabled = value.boolean(["enable"]),
              let mode = value.string(["mode"]),
              ["USB", "SNMP", "SLAVE"].contains(mode) else {
            return nil
        }
        return NasUPSSettings(
            isEnabled: enabled,
            mode: mode,
            safeModeDelaySeconds: value.number(["delay_time"]).map(Int.init),
            waitsUntilLowBattery: value.boolean(["ups_set_safemode_until_lowbatt"]),
            shutsDownUPSAfterSafeMode: value.boolean(["shutdown_device"]),
            networkServerAddress: value.string(["net_server_ip"]),
            snmpServerAddress: value.string(["snmp_server_ip"])
        )
    }

    private static func upsSettings(
        _ actual: NasUPSSettings?,
        match expected: NasUPSSettings?
    ) -> Bool {
        guard let expected else { return true }
        guard let actual else { return false }
        return actual.isEnabled == expected.isEnabled
            && actual.mode == expected.mode
            && actual.safeModeDelaySeconds == expected.safeModeDelaySeconds
            && actual.waitsUntilLowBattery == expected.waitsUntilLowBattery
            && actual.shutsDownUPSAfterSafeMode == expected.shutsDownUPSAfterSafeMode
            && normalizedOptionalText(actual.networkServerAddress)
                == normalizedOptionalText(expected.networkServerAddress)
            && normalizedOptionalText(actual.snmpServerAddress)
                == normalizedOptionalText(expected.snmpServerAddress)
    }

    private static func normalizedOptionalText(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func ethernetInterface(
        from value: DsmDynamicJSON,
        fallback: [String: DsmDynamicJSON],
        id: String
    ) -> NasEthernetInterface? {
        let prefix = "ethernet_"
        func field(_ name: String) -> DsmDynamicJSON? {
            value[name] ?? value[prefix + name] ?? fallback[name] ?? fallback[prefix + name]
        }
        guard let usesDHCP = field("use_dhcp")?.scalarBoolean else { return nil }
        let displayName = field("title")?.scalarString
            ?? field("display")?.scalarString
            ?? id
        return NasEthernetInterface(
            id: id,
            displayName: displayName,
            status: field("status")?.scalarString,
            usesDHCP: usesDHCP,
            address: field("ip")?.scalarString ?? "",
            subnetMask: field("mask")?.scalarString ?? "",
            gateway: field("gateway")?.scalarString ?? "",
            dnsServers: field("dns")?.scalarString ?? "",
            isDefaultGateway: field("is_default_gateway")?.scalarBoolean ?? false,
            mtu: Int(field("mtu")?.scalarNumber
                ?? field("mtu_config")?.scalarNumber
                ?? 1_500),
            isVLANEnabled: field("enable_vlan")?.scalarBoolean ?? false,
            vlanID: field("vlan_id")?.scalarNumber.map(Int.init)
        )
    }

    private static func ethernetInterface(
        _ actual: NasEthernetInterface,
        matches expected: NasEthernetInterface
    ) -> Bool {
        actual.id == expected.id
            && actual.usesDHCP == expected.usesDHCP
            && (expected.usesDHCP || actual.address == expected.address)
            && (expected.usesDHCP || actual.subnetMask == expected.subnetMask)
            && (expected.usesDHCP || actual.gateway == expected.gateway)
            && (expected.usesDHCP || actual.dnsServers == expected.dnsServers)
            && actual.isDefaultGateway == expected.isDefaultGateway
            && actual.mtu == expected.mtu
            && actual.isVLANEnabled == expected.isVLANEnabled
            && (!expected.isVLANEnabled || actual.vlanID == expected.vlanID)
    }

    private static func isValidIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isNumber),
                  let number = Int(part), (0...255).contains(number) else {
                return false
            }
            return String(number) == part || part == "0"
        }
    }

    private static func fileServiceSettings(
        _ actual: NasFileServiceSettings,
        match expected: NasFileServiceSettings
    ) -> Bool {
        func matches<T: Equatable>(_ actual: T?, _ expected: T?) -> Bool {
            expected == nil || actual == expected
        }
        return matches(actual.isSMBEnabled, expected.isSMBEnabled)
            && matches(actual.isNFSEnabled, expected.isNFSEnabled)
            && matches(actual.isFTPEnabled, expected.isFTPEnabled)
            && matches(actual.isFTPSEnabled, expected.isFTPSEnabled)
            && matches(actual.ftpPort, expected.ftpPort)
            && matches(actual.isSFTPEnabled, expected.isSFTPEnabled)
            && matches(actual.sftpPort, expected.sftpPort)
            && matches(actual.isSSDPEnabled, expected.isSSDPEnabled)
            && matches(actual.isBonjourEnabled, expected.isBonjourEnabled)
            && matches(actual.isSMBTimeMachineEnabled, expected.isSMBTimeMachineEnabled)
    }

    private static func package(_ package: NasPackage, iconData: Data?) -> NasPackage {
        NasPackage(
            id: package.id,
            name: package.name,
            version: package.version,
            status: package.status,
            statusDescription: package.statusDescription,
            packageDescription: package.packageDescription,
            installType: package.installType,
            installedAt: package.installedAt,
            iconData: iconData,
            canStart: package.canStart,
            canStop: package.canStop,
            canUninstall: package.canUninstall,
            canUpgrade: package.canUpgrade
        )
    }

    private static func packageIconCacheKey(_ package: NasPackage) -> String {
        "\(package.id)|\(package.version ?? "")"
    }

    private static func loadPackageIcon(
        package: NasPackage,
        capability: ApiCapability,
        version: Int,
        baseURL: URL,
        credential: DsmSessionCredential,
        transport: any DsmHTTPTransport
    ) async -> Data? {
        guard let request = try? DsmRequestBuilder.build(
            baseURL: baseURL,
            path: capability.path,
            api: capability.name,
            version: version,
            method: "get",
            requestFormat: capability.requestFormat,
            parameters: [
                "name": .string(package.id),
                "ver": .string(package.version ?? ""),
                "size": .integer(128)
            ],
            credential: nil,
            httpMethod: "GET"
        ) else { return nil }
        var imageRequest = request
        imageRequest.setValue("image/*", forHTTPHeaderField: "Accept")
        if let cookie = credential.cookieHeaderValue {
            imageRequest.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        if let synoToken = credential.synoToken, !synoToken.isEmpty {
            imageRequest.setValue(synoToken, forHTTPHeaderField: "X-SYNO-TOKEN")
        }
        guard let response = try? await transport.send(imageRequest),
              (200..<300).contains(response.statusCode),
              !response.data.isEmpty,
              response.data.count <= 2 * 1_024 * 1_024 else { return nil }
        let contentType = response.headers.first {
            $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame
        }?.value.lowercased()
        guard contentType?.hasPrefix("image/") == true
                || hasKnownImageSignature(response.data) else {
            return nil
        }
        return response.data
    }

    private static func hasKnownImageSignature(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return true }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return true }
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) { return true }
        if bytes.count >= 12,
           bytes[0...3] == [0x52, 0x49, 0x46, 0x46],
           bytes[8...11] == [0x57, 0x45, 0x42, 0x50] {
            return true
        }
        return false
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
            return L10n.string("shared.0c1dfe694215dfd3")
        }
        if raw.contains("retrieve from status script") {
            return L10n.string("shared.bef163e84a4d4676")
        }
        if let status = status?.lowercased() {
            if status == "running" || status == "active" { return L10n.string("shared.1f0eb99b7ed094be") }
            if status == "stop" || status == "stopped" { return L10n.string("shared.a8c3698b5b8c485d") }
            if status == "error" || status == "failed" { return L10n.string("shared.65350ffbd5f562ce") }
        }
        if let rawDesc = rawDesc, !rawDesc.isEmpty, !rawDesc.contains("retrieve from status script") {
            return rawDesc
        }
        return L10n.string("shared.1f0eb99b7ed094be")
    }
}
