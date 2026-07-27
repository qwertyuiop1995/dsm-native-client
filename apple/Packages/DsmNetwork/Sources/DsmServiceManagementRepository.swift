import DsmCore
import Foundation

private enum ServiceJSON: Decodable, Sendable {
    case object([String: ServiceJSON])
    case array([ServiceJSON])
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
        } else if let value = try? container.decode([String: ServiceJSON].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([ServiceJSON].self))
        }
    }

    subscript(key: String) -> ServiceJSON? {
        guard case .object(let value) = self else { return nil }
        return value[key]
    }

    var object: [String: ServiceJSON]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var array: [ServiceJSON]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        switch self {
        case .string(let value): value
        case .number(let value): value.rounded() == value ? String(Int64(value)) : String(value)
        case .boolean(let value): value ? "true" : "false"
        default: nil
        }
    }

    var numberValue: Double? {
        switch self {
        case .number(let value): value
        case .string(let value): Double(value)
        case .boolean(let value): value ? 1 : 0
        default: nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .boolean(let value): value
        case .number(let value): value != 0
        case .string(let value): ["1", "true", "yes", "running", "in_use"].contains(value.lowercased())
        default: nil
        }
    }

    func firstString(_ keys: [String]) -> String? {
        for key in keys {
            if let value = self[key]?.stringValue, !value.isEmpty { return value }
        }
        return nil
    }

    func firstInteger(_ keys: [String]) -> Int64? {
        for key in keys {
            if let value = self[key]?.numberValue { return Int64(value) }
        }
        return nil
    }

    func firstDouble(_ keys: [String]) -> Double? {
        for key in keys {
            if let value = self[key]?.numberValue { return value }
        }
        return nil
    }

    func firstBoolean(_ keys: [String]) -> Bool? {
        for key in keys {
            if let value = self[key]?.boolValue { return value }
        }
        return nil
    }

    func objects(for keys: [String], depth: Int = 0) -> [[String: ServiceJSON]] {
        guard depth < 4 else { return [] }
        if case .array(let values) = self {
            return values.compactMap(\.object)
        }
        guard case .object(let object) = self else { return [] }

        for key in keys {
            guard let child = object[key] else { continue }
            if let values = child.array?.compactMap(\.object) {
                return values
            }
            let nested = child.objects(for: keys, depth: depth + 1)
            if !nested.isEmpty {
                return nested
            }
        }
        for wrapper in ["data", "result", "items"] where !keys.contains(wrapper) {
            guard let child = object[wrapper] else { continue }
            let nested = child.objects(for: keys, depth: depth + 1)
            if !nested.isEmpty {
                return nested
            }
        }
        return []
    }
}

private struct ServiceVoidEnvelope: Decodable {
    struct Failure: Decodable {
        let code: Int
    }

    let success: Bool
    let error: Failure?
}

/// Download Station、VMM 与 Container Manager 的套件适配器。
/// Container Manager 以及无公开接口时的套件分支均属于 DSM 内部接口。
public actor DsmServiceManagementRepository: ServiceManagementRepository {
    private let capabilities: CapabilitySet
    private let credential: DsmSessionCredential
    private let baseURL: URL
    private let client: DsmAPIClient
    private let transport: any DsmHTTPTransport

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
        let baseURL = try DsmEndpoint.baseURL(for: profile)
        self.capabilities = capabilities
        credential = DsmSessionCredential(sid: session.sid, synoToken: session.synoToken)
        self.baseURL = baseURL
        self.transport = resolvedTransport
        client = DsmAPIClient(
            baseURL: baseURL,
            transport: resolvedTransport
        )
    }

    public func loadDownloadStation() async throws -> DownloadStationSnapshot {
        let usesOfficial = capabilities[DsmAPIName.downloadStationTask]?.selectedVersion != nil
        let taskAPI = usesOfficial
            ? DsmAPIName.downloadStationTask
            : DsmAPIName.downloadStation2Task
        let taskValue = try await call(
            taskAPI,
            method: "list",
            parameters: usesOfficial
                ? [
                    "offset": .integer(0),
                    "limit": .integer(1_000),
                    "additional": .stringArray(["detail", "transfer"])
                ]
                : ["offset": .integer(0), "limit": .integer(1_000)]
        )

        let taskObjects = taskValue.objects(for: ["tasks", "task", "items", "list"])
        let tasks = taskObjects.compactMap(Self.downloadTask)
        let statisticAPI = usesOfficial
            ? DsmAPIName.downloadStationStatistic
            : DsmAPIName.downloadStation2Statistic
        let statisticMethod = usesOfficial ? "getinfo" : "get"
        let statistic = try? await call(statisticAPI, method: statisticMethod)
        let location = usesOfficial
            ? nil
            : try? await call(DsmAPIName.downloadStation2Location, method: "get")

        return DownloadStationSnapshot(
            source: usesOfficial ? .official : .internalAPI,
            tasks: tasks,
            downloadBytesPerSecond: statistic?.firstInteger([
                "download_rate", "download_speed", "speed_download"
            ]) ?? 0,
            uploadBytesPerSecond: statistic?.firstInteger([
                "upload_rate", "upload_speed", "speed_upload"
            ]) ?? 0,
            defaultDestination: location?.firstString(["destination", "path", "default_destination"])
        )
    }

    public func createDownloadTask(uri: String, destination: String?) async throws {
        let normalized = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: normalized),
              ["http", "https", "ftp", "magnet"].contains(url.scheme?.lowercased() ?? "") else {
            throw validationError("请输入有效的下载链接或磁力链接。")
        }
        let api = preferredDownloadTaskAPI()
        var parameters: [String: DsmParameterValue] = ["uri": .string(normalized)]
        if let destination = Self.nonEmpty(destination) {
            parameters["destination"] = .string(destination)
        }
        try await callVoid(api, method: "create", parameters: parameters)
    }

    public func createDownloadTask(
        fileURL: URL,
        destination: String?,
        unzipPassword: String?
    ) async throws {
        guard capabilities[DsmAPIName.downloadStationTask]?.selectedVersion != nil else {
            throw AppError(
                category: .apiUnavailable,
                isRetryable: false,
                safeUserMessage: "这台 NAS 暂时不能从 Mac 上传下载任务文件，请改用网址添加。"
            )
        }
        guard let binaryTransport = transport as? any DsmBinaryHTTPTransport else {
            throw unavailableError()
        }

        let normalizedURL = fileURL.standardizedFileURL
        let allowedExtensions = ["torrent", "nzb", "txt"]
        guard normalizedURL.isFileURL,
              allowedExtensions.contains(normalizedURL.pathExtension.lowercased()) else {
            throw validationError("请选择 .torrent、.nzb 或包含下载网址的 .txt 文件。")
        }

        let accessed = normalizedURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                normalizedURL.stopAccessingSecurityScopedResource()
            }
        }
        let values = try normalizedURL.resourceValues(
            forKeys: [.isRegularFileKey, .isReadableKey, .fileSizeKey]
        )
        guard values.isRegularFile == true, values.isReadable != false else {
            throw validationError("无法读取所选文件，请重新选择。")
        }
        guard (values.fileSize ?? 0) <= 100 * 1_024 * 1_024 else {
            throw validationError("任务文件不能超过 100 MB。")
        }

        guard let capability = capabilities[DsmAPIName.downloadStationTask],
              capability.selectedVersion != nil else {
            throw unavailableError()
        }
        let boundary = "LanStashDownload-\(UUID().uuidString)"
        var multipartFields: [String: String] = [:]
        if let destination = Self.nonEmpty(destination) {
            multipartFields["destination"] = destination
        }
        if let unzipPassword = Self.nonEmpty(unzipPassword) {
            multipartFields["unzip_password"] = unzipPassword
        }
        let bodyURL = try createDownloadMultipartBody(
            localURL: normalizedURL,
            boundary: boundary,
            fields: multipartFields
        )
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        var endpoint = apiURL(path: capability.path)
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw validationError("无法准备下载任务。")
        }
        let queryItems = [
            URLQueryItem(name: "api", value: capability.name),
            URLQueryItem(name: "version", value: String(capability.selectedVersion ?? 1)),
            URLQueryItem(name: "method", value: "create")
        ]
        components.queryItems = queryItems
        guard let resolvedEndpoint = components.url else {
            throw validationError("无法准备下载任务。")
        }
        endpoint = resolvedEndpoint

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        if let cookie = credential.cookieHeaderValue {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        if let synoToken = credential.synoToken, !synoToken.isEmpty {
            request.setValue(synoToken, forHTTPHeaderField: "X-SYNO-TOKEN")
        }
        let bodySize = try bodyURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        request.setValue(String(bodySize), forHTTPHeaderField: "Content-Length")

        let response = try await binaryTransport.upload(request, from: bodyURL) { _, _ in }
        guard (200..<300).contains(response.statusCode),
              let envelope = try? JSONDecoder().decode(ServiceVoidEnvelope.self, from: response.data)
        else {
            throw AppError(
                category: .invalidResponse,
                isRetryable: true,
                safeUserMessage: "任务文件没有上传成功，请稍后重试。"
            )
        }
        if let code = envelope.error?.code {
            throw DsmErrorMapper.map(.api(code: code, requestID: UUID()))
        }
        guard envelope.success else {
            throw AppError(
                category: .invalidResponse,
                isRetryable: true,
                safeUserMessage: "任务文件没有上传成功，请稍后重试。"
            )
        }
    }

    public func loadDownloadStationSettings() async throws -> DownloadStationSettings {
        let config = try await call(DsmAPIName.downloadStationInfo, method: "getconfig")
        let schedule = try? await call(DsmAPIName.downloadStationSchedule, method: "getconfig")
        return Self.downloadSettings(config: config, schedule: schedule)
    }

    public func saveDownloadStationSettings(_ settings: DownloadStationSettings) async throws {
        let limits = [
            settings.btDownloadLimit,
            settings.btUploadLimit,
            settings.httpDownloadLimit,
            settings.ftpDownloadLimit,
            settings.nzbDownloadLimit,
            settings.emuleDownloadLimit,
            settings.emuleUploadLimit
        ]
        guard limits.allSatisfy({ $0 >= 0 && $0 <= 1_000_000 }) else {
            throw validationError("速度限制必须是 0 到 1,000,000 KB/s 之间的整数。")
        }

        try await callVoid(
            DsmAPIName.downloadStationInfo,
            method: "setserverconfig",
            parameters: [
                "default_destination": .string(
                    settings.defaultDestination.trimmingCharacters(
                        in: CharacterSet(charactersIn: "/")
                    )
                ),
                "emule_enabled": .boolean(settings.isEMuleEnabled),
                "unzip_service_enabled": .boolean(settings.isAutoExtractEnabled),
                "bt_max_download": .integer(settings.btDownloadLimit),
                "bt_max_upload": .integer(settings.btUploadLimit),
                "http_max_download": .integer(settings.httpDownloadLimit),
                "ftp_max_download": .integer(settings.ftpDownloadLimit),
                "nzb_max_download": .integer(settings.nzbDownloadLimit),
                "emule_max_download": .integer(settings.emuleDownloadLimit),
                "emule_max_upload": .integer(settings.emuleUploadLimit)
            ]
        )
        if capabilities[DsmAPIName.downloadStationSchedule]?.selectedVersion != nil {
            try await callVoid(
                DsmAPIName.downloadStationSchedule,
                method: "setconfig",
                parameters: [
                    "enabled": .boolean(settings.isScheduleEnabled),
                    "emule_enabled": .boolean(settings.isEMuleScheduleEnabled)
                ]
            )
        }

        let confirmed = try await loadDownloadStationSettings()
        guard confirmed == settings else {
            throw verificationError("NAS 返回的设置与本次保存不一致，请刷新后检查。")
        }
    }

    public func controlDownloadTasks(
        ids: [String],
        action: DownloadStationTaskAction
    ) async throws {
        let ids = try validatedIDs(ids)
        try await callVoid(
            preferredDownloadTaskAPI(),
            method: action.rawValue,
            parameters: ["id": .string(ids.joined(separator: ","))]
        )
    }

    public func deleteDownloadTasks(ids: [String], removeData: Bool) async throws {
        let ids = try validatedIDs(ids)
        try await callVoid(
            preferredDownloadTaskAPI(),
            method: "delete",
            parameters: [
                "id": .string(ids.joined(separator: ",")),
                "force_complete": .boolean(removeData)
            ]
        )
        let remaining = try await loadDownloadStation().tasks.map(\.id)
        guard ids.allSatisfy({ !remaining.contains($0) }) else {
            throw verificationError("NAS 尚未确认下载任务已删除，请刷新后重试。")
        }
    }

    public func loadContainerManager() async throws -> ContainerManagerSnapshot {
        async let containersValue = call(
            DsmAPIName.dockerContainer,
            method: "list",
            parameters: [
                "offset": .integer(0),
                "limit": .integer(-1),
                "type": .string("all")
            ]
        )
        async let imagesValue = supplementaryCall(DsmAPIName.dockerImage, method: "list")
        async let networksValue = supplementaryCall(DsmAPIName.dockerNetwork, method: "list")
        async let projectsValue = supplementaryCall(DsmAPIName.dockerProject, method: "list")
        async let eventsValue = supplementaryCall(
            DsmAPIName.dockerLog,
            method: "list",
            parameters: ["offset": .integer(0), "limit": .integer(200)]
        )
        let (containerJSON, imageJSON, networkJSON, projectJSON, eventJSON) =
            try await (containersValue, imagesValue, networksValue, projectsValue, eventsValue)

        return ContainerManagerSnapshot(
            containers: containerJSON.objects(for: ["containers", "container", "data", "list"])
                .compactMap(Self.container),
            images: imageJSON?.objects(for: ["images", "image", "data", "list"])
                .compactMap(Self.image) ?? [],
            networks: networkJSON?.objects(for: ["networks", "network", "data", "list"])
                .compactMap(Self.containerNetwork) ?? [],
            projects: projectJSON?.objects(for: ["projects", "project", "data", "list"])
                .compactMap(Self.project) ?? [],
            events: eventJSON?.objects(for: ["logs", "events", "data", "list"])
                .enumerated().map {
                    Self.event(offset: $0.offset, element: $0.element)
                } ?? []
        )
    }

    public func controlContainers(ids: [String], action: ContainerAction) async throws {
        let ids = try validatedIDs(ids)
        for id in ids {
            try await callVoid(
                DsmAPIName.dockerContainer,
                method: action.rawValue,
                parameters: ["id": .string(id)]
            )
        }
    }

    public func deleteContainers(ids: [String]) async throws {
        let ids = try validatedIDs(ids)
        for id in ids {
            try await callVoid(
                DsmAPIName.dockerContainer,
                method: "delete",
                parameters: ["id": .string(id)]
            )
        }
        let remaining = try await loadContainerManager().containers.map(\.id)
        guard ids.allSatisfy({ !remaining.contains($0) }) else {
            throw verificationError("NAS 尚未确认容器已删除，请刷新后重试。")
        }
    }

    public func searchContainerImages(query: String) async throws -> [ContainerRegistryImage] {
        let query = try validatedName(query, message: "请输入要搜索的映像名称。")
        let value = try await call(
            DsmAPIName.dockerRegistry,
            method: "search",
            parameters: [
                "offset": .integer(0),
                "limit": .integer(50),
                "page_size": .integer(50),
                "q": .string(query)
            ]
        )
        return value.objects(for: ["data", "items", "results"])
            .compactMap(Self.registryImage)
    }

    public func loadContainerImageTags(repository: String) async throws -> [String] {
        let repository = try validatedName(repository, message: "请先选择一个映像。")
        let value = try await call(
            DsmAPIName.dockerRegistry,
            method: "tags",
            parameters: ["repo": .string(repository)]
        )
        return value.objects(for: ["data", "tags", "items"])
            .compactMap { ServiceJSON.object($0).firstString(["tag", "name"]) }
            .reduce(into: []) { result, tag in
                if !result.contains(tag) {
                    result.append(tag)
                }
            }
    }

    public func pullContainerImage(repository: String, tag: String) async throws {
        let repository = try validatedName(repository, message: "请输入映像名称。")
        let tag = try validatedName(tag, message: "请输入映像标签。")
        try await callVoid(
            DsmAPIName.dockerImage,
            method: "pull_start",
            parameters: ["repository": .string(repository), "tag": .string(tag)]
        )
    }

    public func deleteContainerImages(ids: [String]) async throws {
        let ids = try validatedIDs(ids)
        for id in ids {
            try await callVoid(
                DsmAPIName.dockerImage,
                method: "delete",
                parameters: ["id": .string(id)]
            )
        }
    }

    public func createContainerNetwork(name: String, driver: String) async throws {
        let name = try validatedName(name, message: "请输入网络名称。")
        let driver = try validatedName(driver, message: "请选择网络类型。")
        try await callVoid(
            DsmAPIName.dockerNetwork,
            method: "create",
            parameters: ["name": .string(name), "driver": .string(driver)]
        )
        let networks = try await loadContainerManager().networks
        guard networks.contains(where: { $0.name == name }) else {
            throw verificationError("NAS 尚未确认网络已创建，请刷新后重试。")
        }
    }

    public func deleteContainerNetworks(ids: [String]) async throws {
        let ids = try validatedIDs(ids)
        for id in ids {
            try await callVoid(
                DsmAPIName.dockerNetwork,
                method: "remove",
                parameters: ["id": .string(id)]
            )
        }
    }

    public func loadVirtualMachineManager() async throws -> VirtualMachineManagerSnapshot {
        let (official, guestJSON) = try await loadVirtualMachineList()
        // 创建向导需要内部资源接口返回的主机归属和容量字段；缺失时再退回公开只读接口。
        let hostAPI = capabilities[DsmAPIName.virtualizationHost]?.selectedVersion != nil
            ? DsmAPIName.virtualizationHost
            : DsmAPIName.virtualizationAPIHost
        let storageAPI = capabilities[DsmAPIName.virtualizationRepo]?.selectedVersion != nil
            ? DsmAPIName.virtualizationRepo
            : DsmAPIName.virtualizationAPIStorage
        let networkAPI = capabilities[DsmAPIName.virtualizationNetwork]?.selectedVersion != nil
            ? DsmAPIName.virtualizationNetwork
            : DsmAPIName.virtualizationAPINetwork
        let imageAPI = capabilities[DsmAPIName.virtualizationGuestImage]?.selectedVersion != nil
            ? DsmAPIName.virtualizationGuestImage
            : DsmAPIName.virtualizationAPIGuestImage

        async let hostsValue = supplementaryCall(hostAPI, method: "list")
        async let storagesValue = supplementaryCall(storageAPI, method: "list")
        async let networksValue = supplementaryCall(networkAPI, method: "list")
        async let imagesValue = supplementaryCall(imageAPI, method: "list")
        async let plansValue = supplementaryCall(
            DsmAPIName.virtualizationProtectionPlan,
            method: "list"
        )
        async let eventsValue = supplementaryCall(
            DsmAPIName.virtualizationLog,
            method: "list",
            parameters: ["offset": .integer(0), "limit": .integer(200)]
        )
        let (hostJSON, storageJSON, networkJSON, imageJSON, planJSON, eventJSON) =
            try await (
                hostsValue, storagesValue, networksValue, imagesValue, plansValue, eventsValue
            )

        return VirtualMachineManagerSnapshot(
            source: official ? .official : .internalAPI,
            machines: guestJSON.objects(for: ["guests", "guest", "vms", "data", "list"])
                .compactMap(Self.machine),
            hosts: Self.resources(hostJSON, keys: ["hosts", "host", "data", "list"]),
            storages: Self.resources(storageJSON, keys: ["repos", "storages", "data", "list"]),
            networks: Self.resources(networkJSON, keys: ["networks", "network", "data", "list"]),
            images: Self.resources(imageJSON, keys: ["images", "image", "data", "list"]),
            protectionPlans: Self.resources(planJSON, keys: ["plans", "plan", "data", "list"]),
            events: eventJSON?.objects(for: ["logs", "events", "data", "list"])
                .enumerated().map {
                    Self.event(offset: $0.offset, element: $0.element)
                } ?? []
        )
    }

    /// VMM 官方界面使用的内部创建契约；只有能力发现明确返回该接口时才启用。
    public func createVirtualMachine(_ configuration: VirtualMachineCreation) async throws {
        let name = try validatedName(configuration.name, message: "请输入虚拟机名称。")
        guard (1...64).contains(configuration.cpuCount) else {
            throw validationError("处理器数量应在 1 到 64 之间。")
        }
        guard (128...1_048_576).contains(configuration.memoryMiB) else {
            throw validationError("内存容量应在 128 MB 到 1 TB 之间。")
        }
        guard (1...1_048_576).contains(configuration.diskGiB) else {
            throw validationError("虚拟磁盘容量应在 1 GB 到 1 PB 之间。")
        }
        let storageID = try validatedName(
            configuration.storageID,
            message: "请选择存储空间。"
        )
        let networkID = try validatedName(
            configuration.networkID,
            message: "请选择网络。"
        )
        guard capabilities[DsmAPIName.virtualizationGuest]?.selectedVersion != nil else {
            throw unavailableError()
        }
        let snapshot = try await loadVirtualMachineManager()
        guard !snapshot.machines.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw validationError("已有同名虚拟机，请换一个名称。")
        }
        guard let storage = snapshot.storages.first(where: { $0.id == storageID }) else {
            throw validationError("所选存储空间已不可用，请刷新后重新选择。")
        }
        guard let hostID = Self.nonEmpty(storage.hostID),
              let hostName = Self.nonEmpty(storage.hostName) else {
            throw unavailableError()
        }
        guard snapshot.networks.contains(where: { $0.id == networkID }) else {
            throw validationError("所选网络已不可用，请刷新后重新选择。")
        }
        if let imageID = configuration.bootImageID,
           !imageID.isEmpty,
           !snapshot.images.contains(where: { $0.id == imageID }) {
            throw validationError("所选安装映像已不可用，请刷新后重新选择。")
        }

        let isWindows = configuration.operatingSystem == .windows
        let usesUEFI = configuration.firmware == .uefi
        let bootImages = [configuration.bootImageID ?? "", ""]
        let disk: [String: DsmJSONValue] = [
            "type": .string("add"),
            "vdisk_mode": .integer(1),
            "name": .string("虚拟盘 1"),
            "unmap": .boolean(false),
            "iops_enable": .boolean(false),
            "dev_limit": .integer(0),
            "dev_reservation": .integer(0),
            "dev_weight": .integer(3),
            "vdisk_size": .integer(configuration.diskGiB),
            "idx": .integer(0)
        ]
        let network: [String: DsmJSONValue] = [
            "prefer_sriov": .boolean(false),
            "vnic_type": .integer(1),
            "type": .string("add"),
            "mac": .string(Self.randomVirtualMACAddress()),
            "network_id": .string(networkID)
        ]
        var parameters: [String: DsmParameterValue] = [
            "guest_privilege": .objectArray([]),
            "iso_images": .stringArray(bootImages),
            "autorun": .integer(configuration.autoStart ? 1 : 0),
            "boot_from": .string(configuration.bootImageID == nil ? "disk" : "iso"),
            "bios": .string(usesUEFI ? "uefi" : "legacy"),
            "kb_layout": .string("Default"),
            "usb_version": .integer(0),
            "usbs": .stringArray(["", "", "", ""]),
            "is_windows_vm": .boolean(isWindows),
            "use_ovmf": .boolean(usesUEFI),
            "vnics": .objectArray([network]),
            "is_general_vm": .boolean(true),
            "increaseAllocatedSize": .integer(configuration.diskGiB),
            "vdisks": .objectArray([disk]),
            "auto_switch": .integer(0),
            "vdisk_struct": .objectArray([]),
            "name": .string(name),
            "vcpu_num": .integer(configuration.cpuCount),
            "vram_size": .integer(configuration.memoryMiB),
            "video_card": .string(isWindows ? "vga" : "vmvga"),
            "cpu_weight": .integer(256),
            "desc": .string(configuration.description ?? ""),
            "cpu_passthru": .boolean(true),
            "hyperv_enlighten": .boolean(true),
            "cpu_pin_num": .integer(0),
            "repo_id": .string(storage.id),
            "repo_name": .string(storage.name),
            "host_id": .string(hostID),
            "repo_host_name": .string(hostName),
            "poweron_after_create": .boolean(configuration.powerOnAfterCreation),
            "synovmm_ui_id": .string(UUID().uuidString.lowercased())
        ]
        if let allocated = storage.allocatedBytes {
            parameters["allocated_size"] = .string(String(allocated))
        }
        if let capacity = storage.capacityBytes {
            parameters["size"] = .string(String(capacity))
        }

        try await callVoid(
            DsmAPIName.virtualizationGuest,
            method: "create",
            parameters: parameters
        )
        let updated = try await loadVirtualMachineManager()
        guard updated.machines.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw verificationError("NAS 尚未确认虚拟机已创建，请刷新后重试。")
        }
    }

    /// VMM 官方界面使用的内部修改契约；运行中的虚拟机只提交允许在线调整的字段。
    public func updateVirtualMachine(
        id: String,
        configuration: VirtualMachineUpdate
    ) async throws {
        let id = try validatedIDs([id])[0]
        guard capabilities[DsmAPIName.virtualizationGuest]?.selectedVersion != nil else {
            throw unavailableError()
        }
        let snapshot = try await loadVirtualMachineManager()
        guard let current = snapshot.machines.first(where: { $0.id == id }) else {
            throw validationError("找不到这台虚拟机，请刷新后重试。")
        }
        var parameters: [String: DsmParameterValue] = [
            "guest_id": .string(id),
            "synovmm_ui_id": .string(UUID().uuidString.lowercased())
        ]
        if let name = configuration.name {
            let name = try validatedName(name, message: "请输入虚拟机名称。")
            guard !snapshot.machines.contains(where: {
                $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame
            }) else {
                throw validationError("已有同名虚拟机，请换一个名称。")
            }
            parameters["name"] = .string(name)
        }
        if let description = configuration.description {
            guard description.count <= 1_024 else {
                throw validationError("描述不能超过 1024 个字符。")
            }
            parameters["desc"] = .string(description)
        }
        if let cpuWeight = configuration.cpuWeight {
            guard (1...512).contains(cpuWeight) else {
                throw validationError("虚拟机优先级设置无效，请重新选择。")
            }
            parameters["cpu_weight"] = .integer(cpuWeight)
        }
        if let autoStart = configuration.autoStart {
            parameters["autorun"] = .integer(autoStart ? 1 : 0)
        }

        let isRunning = Self.isVirtualMachineRunning(current.status)
        if configuration.cpuCount != nil || configuration.memoryMiB != nil {
            guard !isRunning else {
                throw validationError("请先正常关机，再修改处理器或内存。")
            }
            if let cpuCount = configuration.cpuCount {
                guard (1...64).contains(cpuCount) else {
                    throw validationError("处理器数量应在 1 到 64 之间。")
                }
                parameters["vcpu_num"] = .integer(cpuCount)
            }
            if let memoryMiB = configuration.memoryMiB {
                guard (128...1_048_576).contains(memoryMiB) else {
                    throw validationError("内存容量应在 128 MB 到 1 TB 之间。")
                }
                parameters["vram_size"] = .integer(memoryMiB)
            }
        }
        guard parameters.count > 2 else {
            throw validationError("没有需要保存的修改。")
        }

        try await callVoid(
            DsmAPIName.virtualizationGuest,
            method: "set",
            parameters: parameters
        )
        let updated = try await loadVirtualMachineManager()
        guard let verified = updated.machines.first(where: { $0.id == id }),
              configuration.name.map({ verified.name == $0 }) ?? true,
              configuration.cpuCount.map({ verified.cpuCount == $0 }) ?? true,
              configuration.memoryMiB.map({
                  verified.memoryBytes == Int64($0) * 1_024 * 1_024
              }) ?? true else {
            throw verificationError("NAS 尚未确认设置已保存，请刷新后重试。")
        }
    }

    public func openVirtualMachineConsole(id: String) async throws -> VirtualMachineConsoleSession {
        let id = try validatedIDs([id])[0]
        let snapshot = try await loadVirtualMachineManager()
        guard let machine = snapshot.machines.first(where: { $0.id == id }) else {
            throw validationError("找不到这台虚拟机，请刷新后重试。")
        }
        guard Self.isVirtualMachineRunning(machine.status) else {
            throw validationError("请先启动虚拟机，再打开远程控制台。")
        }
        var components = URLComponents(
            url: baseURL
                .appendingPathComponent("webman", isDirectory: true)
                .appendingPathComponent("3rdparty", isDirectory: true)
                .appendingPathComponent("Virtualization", isDirectory: true)
                .appendingPathComponent("noVNC", isDirectory: true)
                .appendingPathComponent("vnc.html"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "autoconnect", value: "true"),
            URLQueryItem(name: "reconnect", value: "true"),
            URLQueryItem(name: "path", value: "synovirtualization/ws/\(id)"),
            URLQueryItem(name: "title", value: machine.name),
            URLQueryItem(name: "app_id", value: UUID().uuidString.lowercased()),
            URLQueryItem(
                name: "kb_layout",
                value: machine.keyboardLayout == "Default"
                    ? "en-us"
                    : machine.keyboardLayout ?? "en-us"
            ),
            URLQueryItem(name: "app_alias", value: "")
        ]
        guard let url = components?.url else {
            throw verificationError("无法准备远程控制台，请刷新后重试。")
        }
        return VirtualMachineConsoleSession(
            url: url,
            sessionCookieValue: credential.sid
        )
    }

    public func controlVirtualMachines(
        ids: [String],
        action: VirtualMachinePowerAction
    ) async throws {
        let ids = try validatedIDs(ids)
        if capabilities[DsmAPIName.virtualizationAPIGuestAction]?.selectedVersion != nil {
            let method: String = switch action {
            case .powerOn: "poweron"
            case .shutdown: "shutdown"
            case .powerOff: "poweroff"
            case .restart: "reboot"
            }
            try await callVoid(
                DsmAPIName.virtualizationAPIGuestAction,
                method: method,
                parameters: ["guest_id": .string(ids.joined(separator: ","))]
            )
        } else {
            let command: String = switch action {
            case .powerOn: "on"
            case .shutdown: "shutdown"
            case .powerOff: "off"
            case .restart: "reboot"
            }
            for id in ids {
                try await callVoid(
                    DsmAPIName.virtualizationGuestAction,
                    method: "pwr_ctl",
                    parameters: ["guest_id": .string(id), "action": .string(command)]
                )
            }
        }
    }

    public func deleteVirtualMachines(ids: [String]) async throws {
        let ids = try validatedIDs(ids)
        let api = capabilities[DsmAPIName.virtualizationAPIGuest]?.selectedVersion != nil
            ? DsmAPIName.virtualizationAPIGuest
            : DsmAPIName.virtualizationGuest
        try await callVoid(
            api,
            method: "delete",
            parameters: ["guest_id": .string(ids.joined(separator: ","))]
        )
        let remaining = try await loadVirtualMachineManager().machines.map(\.id)
        guard ids.allSatisfy({ !remaining.contains($0) }) else {
            throw verificationError("NAS 尚未确认虚拟机已删除，请刷新后重试。")
        }
    }

    private func preferredDownloadTaskAPI() -> String {
        capabilities[DsmAPIName.downloadStationTask]?.selectedVersion != nil
            ? DsmAPIName.downloadStationTask
            : DsmAPIName.downloadStation2Task
    }

    private func apiURL(path: String) -> URL {
        var url = baseURL.appendingPathComponent("webapi", isDirectory: true)
        for segment in path.split(separator: "/") {
            url.appendPathComponent(String(segment), isDirectory: false)
        }
        return url
    }

    private func createDownloadMultipartBody(
        localURL: URL,
        boundary: String,
        fields: [String: String]
    ) throws -> URL {
        let bodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LanStashDownload-\(UUID().uuidString).multipart")
        guard FileManager.default.createFile(atPath: bodyURL.path, contents: nil) else {
            throw AppError(
                category: .localStorageFull,
                isRetryable: false,
                safeUserMessage: "无法准备任务文件，请检查这台 Mac 的可用空间。"
            )
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: bodyURL.path
        )

        do {
            let output = try FileHandle(forWritingTo: bodyURL)
            defer { try? output.close() }
            func write(_ string: String) throws {
                guard let data = string.data(using: .utf8) else {
                    throw DsmRequestError.parameterEncodingFailed
                }
                try output.write(contentsOf: data)
            }

            for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
                try write("--\(boundary)\r\n")
                try write("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
                try write("\(value)\r\n")
            }

            let safeFilename = localURL.lastPathComponent
                .replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\"", with: "'")
            try write("--\(boundary)\r\n")
            try write(
                "Content-Disposition: form-data; name=\"file\"; filename=\"\(safeFilename)\"\r\n"
            )
            try write("Content-Type: application/octet-stream\r\n\r\n")
            let input = try FileHandle(forReadingFrom: localURL)
            defer { try? input.close() }
            while true {
                let data = try input.read(upToCount: 1_024 * 1_024) ?? Data()
                if data.isEmpty { break }
                try output.write(contentsOf: data)
            }
            try write("\r\n--\(boundary)--\r\n")
            return bodyURL
        } catch {
            try? FileManager.default.removeItem(at: bodyURL)
            throw error
        }
    }

    private static func downloadSettings(
        config: ServiceJSON,
        schedule: ServiceJSON?
    ) -> DownloadStationSettings {
        DownloadStationSettings(
            defaultDestination: config.firstString(["default_destination"]) ?? "",
            isEMuleEnabled: config.firstBoolean(["emule_enabled"]) ?? false,
            isAutoExtractEnabled: config.firstBoolean(["unzip_service_enabled"]) ?? false,
            btDownloadLimit: Int(config.firstInteger(["bt_max_download"]) ?? 0),
            btUploadLimit: Int(config.firstInteger(["bt_max_upload"]) ?? 0),
            httpDownloadLimit: Int(config.firstInteger(["http_max_download"]) ?? 0),
            ftpDownloadLimit: Int(config.firstInteger(["ftp_max_download"]) ?? 0),
            nzbDownloadLimit: Int(config.firstInteger(["nzb_max_download"]) ?? 0),
            emuleDownloadLimit: Int(config.firstInteger(["emule_max_download"]) ?? 0),
            emuleUploadLimit: Int(config.firstInteger(["emule_max_upload"]) ?? 0),
            isScheduleEnabled: schedule?.firstBoolean(["enabled"]) ?? false,
            isEMuleScheduleEnabled: schedule?.firstBoolean(["emule_enabled"]) ?? false
        )
    }

    private func loadVirtualMachineList() async throws -> (usesOfficialAPI: Bool, value: ServiceJSON) {
        if capabilities[DsmAPIName.virtualizationAPIGuest]?.selectedVersion != nil {
            do {
                return (
                    true,
                    try await call(DsmAPIName.virtualizationAPIGuest, method: "list")
                )
            } catch let error as AppError {
                guard shouldFallBackFromOfficialVirtualizationAPI(error),
                      capabilities[DsmAPIName.virtualizationGuest]?.selectedVersion != nil else {
                    throw error
                }
                return (
                    false,
                    try await call(DsmAPIName.virtualizationGuest, method: "list")
                )
            }
        }
        return (
            false,
            try await call(DsmAPIName.virtualizationGuest, method: "list")
        )
    }

    private func shouldFallBackFromOfficialVirtualizationAPI(_ error: AppError) -> Bool {
        switch error.category {
        case .apiUnavailable, .versionUnsupported, .invalidResponse, .notFound, .unknown:
            true
        default:
            false
        }
    }

    private func supplementaryCall(
        _ name: String,
        method: String,
        parameters: [String: DsmParameterValue] = [:]
    ) async throws -> ServiceJSON? {
        guard capabilities[name]?.selectedVersion != nil else { return nil }
        do {
            return try await call(name, method: method, parameters: parameters)
        } catch let error as AppError {
            switch error.category {
            case .authenticationRequired, .otpRequired, .tlsUntrusted,
                 .tlsCertificateChanged, .cancelled:
                throw error
            default:
                return nil
            }
        }
    }

    private func call(
        _ name: String,
        method: String,
        parameters: [String: DsmParameterValue] = [:]
    ) async throws -> ServiceJSON {
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
                as: ServiceJSON.self
            )
        } catch let error as DsmNetworkError {
            throw DsmErrorMapper.map(error)
        }
    }

    private func callVoid(
        _ name: String,
        method: String,
        parameters: [String: DsmParameterValue]
    ) async throws {
        guard let capability = capabilities[name],
              let version = capability.selectedVersion else {
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

    private func validatedIDs(_ values: [String]) throws -> [String] {
        let ids = values.compactMap(Self.nonEmpty)
        guard ids.count == values.count, !ids.isEmpty else {
            throw validationError("请先选择要操作的项目。")
        }
        return Array(Set(ids)).sorted()
    }

    private func validatedName(_ value: String, message: String) throws -> String {
        guard let value = Self.nonEmpty(value), value.count <= 255 else {
            throw validationError(message)
        }
        return value
    }

    private func unavailableError() -> AppError {
        AppError(
            category: .apiUnavailable,
            isRetryable: false,
            safeUserMessage: "这台 NAS 当前无法使用此功能，请确认对应套件已安装并允许当前账号访问。"
        )
    }

    private func validationError(_ message: String) -> AppError {
        AppError(category: .conflict, isRetryable: false, safeUserMessage: message)
    }

    private func verificationError(_ message: String) -> AppError {
        AppError(category: .conflict, isRetryable: true, safeUserMessage: message)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? nil : normalized
    }

    private static func date(_ value: ServiceJSON, keys: [String]) -> Date? {
        guard let seconds = value.firstDouble(keys), seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1_000 : seconds)
    }

    private static func downloadTask(_ object: [String: ServiceJSON]) -> DownloadStationTask? {
        let value = ServiceJSON.object(object)
        guard let id = value.firstString(["id", "task_id", "taskId"]) else { return nil }
        let detail = value["additional"]?["detail"] ?? value["detail"]
        let transfer = value["additional"]?["transfer"] ?? value["transfer"]
        return DownloadStationTask(
            id: id,
            title: value.firstString(["title", "name", "filename"]) ?? "未命名下载",
            status: value.firstString(["status", "state"]) ?? "unknown",
            sizeBytes: value.firstInteger(["size", "total_size"]),
            downloadedBytes: transfer?.firstInteger(["size_downloaded", "downloaded", "completed"])
                ?? value.firstInteger(["size_downloaded", "downloaded", "completed"]),
            uploadedBytes: transfer?.firstInteger(["size_uploaded", "uploaded"]),
            downloadBytesPerSecond: transfer?.firstInteger(["speed_download", "download_rate"]),
            uploadBytesPerSecond: transfer?.firstInteger(["speed_upload", "upload_rate"]),
            destination: value.firstString(["destination"])
                ?? detail?.firstString(["destination"]),
            errorDescription: value.firstString(["error", "error_detail", "message"])
        )
    }

    private static func container(_ object: [String: ServiceJSON]) -> ContainerInstance? {
        let value = ServiceJSON.object(object)
        guard let id = value.firstString(["id", "container_id", "Id"]) else { return nil }
        return ContainerInstance(
            id: id,
            name: value.firstString(["name", "Names"]) ?? String(id.prefix(12)),
            image: value.firstString(["image", "image_name", "Image"]) ?? "—",
            project: value.firstString(["project", "project_name"]),
            status: value.firstString(["status", "state", "State"]) ?? "unknown",
            cpuUsage: value.firstDouble(["cpu", "cpu_usage", "cpu_percent"]),
            memoryBytes: value.firstInteger(["memory", "memory_usage", "memory_bytes"]),
            createdAt: date(value, keys: ["created", "created_at", "CreateTime"])
        )
    }

    private static func image(_ object: [String: ServiceJSON]) -> ContainerImage? {
        let value = ServiceJSON.object(object)
        guard let id = value.firstString(["id", "image_id", "Id"]) else { return nil }
        let repository = value.firstString(["repository", "repo", "name", "RepoTags"]) ?? "—"
        return ContainerImage(
            id: id,
            repository: repository,
            tag: value.firstString(["tag"]) ?? "latest",
            sizeBytes: value.firstInteger(["size", "virtual_size", "Size"]),
            createdAt: date(value, keys: ["created", "created_at", "Created"]),
            isInUse: value.firstBoolean(["in_use", "is_used", "using"]) ?? false
        )
    }

    private static func registryImage(
        _ object: [String: ServiceJSON]
    ) -> ContainerRegistryImage? {
        let value = ServiceJSON.object(object)
        guard let name = value.firstString(["name", "repository", "repo"]) else { return nil }
        return ContainerRegistryImage(
            name: name,
            registry: value.firstString(["registry"]) ?? "docker.io",
            description: value.firstString(["description"]),
            starCount: Int(value.firstInteger(["star_count", "stars"]) ?? 0),
            isOfficial: value.firstBoolean(["is_official", "official"]) ?? false,
            isAutomated: value.firstBoolean(["is_automated", "automated"]) ?? false,
            isTrusted: value.firstBoolean(["is_trusted", "trusted"]) ?? false
        )
    }

    private static func containerNetwork(
        _ object: [String: ServiceJSON]
    ) -> ContainerNetwork? {
        let value = ServiceJSON.object(object)
        guard let id = value.firstString(["id", "network_id", "Id"]) else { return nil }
        return ContainerNetwork(
            id: id,
            name: value.firstString(["name", "Name"]) ?? String(id.prefix(12)),
            driver: value.firstString(["driver", "Driver", "type"]) ?? "—",
            connectedContainerCount: Int(value.firstInteger([
                "container_count", "containers_count", "using"
            ]) ?? 0)
        )
    }

    private static func project(_ object: [String: ServiceJSON]) -> ContainerProject? {
        let value = ServiceJSON.object(object)
        guard let name = value.firstString(["name", "project_name", "id"]) else { return nil }
        return ContainerProject(
            id: value.firstString(["id", "project_id"]) ?? name,
            name: name,
            status: value.firstString(["status", "state"]) ?? "unknown",
            containerCount: Int(value.firstInteger(["container_count", "services"]) ?? 0)
        )
    }

    private static func machine(_ object: [String: ServiceJSON]) -> VirtualMachine? {
        let value = ServiceJSON.object(object)
        guard let id = value.firstString(["guest_id", "id", "vm_id"]) else { return nil }
        let memoryBytes = value.firstInteger(["memory", "memory_size", "ram"])
            ?? value.firstInteger(["vram_size"]).map { $0 * 1_024 * 1_024 }
        let reportedStorageBytes = value.firstInteger([
            "storage", "disk_size", "virtual_disk_size"
        ])
        let virtualDiskSizes = value["vdisks"]?.array?.compactMap {
            $0.firstInteger(["vdisk_size"])
        } ?? []
        let virtualDiskBytes = virtualDiskSizes.isEmpty
            ? nil
            : virtualDiskSizes.reduce(0, +) * 1_024 * 1_024
        let storageBytes = reportedStorageBytes ?? virtualDiskBytes
        return VirtualMachine(
            id: id,
            name: value.firstString(["guest_name", "name", "vm_name"]) ?? String(id.prefix(12)),
            status: value.firstString(["status", "state", "power_state"]) ?? "unknown",
            description: value.firstString(["desc", "description"]),
            hostID: value.firstString(["host_id"]),
            host: value.firstString(["host_name", "host", "node"]),
            storageID: value.firstString(["repo_id", "storage_id"]),
            cpuCount: value.firstInteger(["vcpu_num", "cpu", "cpu_count"]).map(Int.init),
            memoryBytes: memoryBytes,
            storageBytes: storageBytes,
            ipAddress: value.firstString(["ip", "ip_address", "guest_ip"]),
            keyboardLayout: value.firstString(["kb_layout", "keyboard_layout"]),
            autoStart: value.firstBoolean(["autorun", "auto_start"]) ?? false,
            cpuWeight: value.firstInteger(["cpu_weight"]).map(Int.init)
        )
    }

    private static func resources(
        _ value: ServiceJSON?,
        keys: [String]
    ) -> [VirtualizationResource] {
        value?.objects(for: keys).compactMap { object in
            let value = ServiceJSON.object(object)
            guard let name = value.firstString([
                "name", "host_name", "storage_name", "repo_name",
                "network_name", "image_name", "id"
            ]) else {
                return nil
            }
            return VirtualizationResource(
                id: value.firstString([
                    "id", "storage_id", "repo_id", "network_id", "image_id", "host_id"
                ])
                    ?? name,
                name: name,
                status: value.firstString(["status", "state", "health"]),
                detail: value.firstString(["description", "type", "path", "volume_path"]),
                hostID: value.firstString(["host_id"]),
                hostName: value.firstString(["host_name"]),
                allocatedBytes: value.firstInteger([
                    "allocated_size", "allocated_bytes", "used_size"
                ]),
                capacityBytes: value.firstInteger(["size", "capacity", "total_size"])
            )
        } ?? []
    }

    private static func randomVirtualMACAddress() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = [UInt8(0x02)] + (0..<5).map { _ in UInt8.random(in: 0...255, using: &generator) }
        return bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    private static func isVirtualMachineRunning(_ status: String) -> Bool {
        ["running", "started", "up", "online"].contains(status.lowercased())
    }

    private static func event(
        offset: Int,
        element: [String: ServiceJSON]
    ) -> ServiceEvent {
        let value = ServiceJSON.object(element)
        let timestamp = date(value, keys: ["time", "timestamp", "date"])
        let message = value.firstString(["event", "message", "description"]) ?? "—"
        return ServiceEvent(
            id: value.firstString(["id", "log_id"])
                ?? "\(timestamp?.timeIntervalSince1970 ?? 0)-\(offset)-\(message.hashValue)",
            timestamp: timestamp,
            level: value.firstString(["level", "severity"]) ?? "信息",
            user: value.firstString(["user", "username", "owner"]),
            message: message
        )
    }
}
