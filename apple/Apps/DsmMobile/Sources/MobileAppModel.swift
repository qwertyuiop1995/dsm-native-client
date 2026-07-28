import DsmCore
import DsmNetwork
import Foundation
import Observation

enum MobileModule: String, CaseIterable, Identifiable {
    case files
    case photos
    case chat
    case downloads
    case containers
    case virtualMachines
    case nasSettings
    case transfers
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .files: "文件浏览器"
        case .photos: "照片"
        case .chat: "消息"
        case .downloads: "下载管理"
        case .containers: "容器管理"
        case .virtualMachines: "虚拟机管理"
        case .nasSettings: "NAS 设置"
        case .transfers: "传输中心"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .files: "folder"
        case .photos: "photo.on.rectangle.angled"
        case .chat: "bubble.left.and.bubble.right"
        case .downloads: "arrow.down.circle"
        case .containers: "shippingbox"
        case .virtualMachines: "desktopcomputer"
        case .nasSettings: "externaldrive"
        case .transfers: "arrow.up.arrow.down"
        case .settings: "gearshape"
        }
    }
}

@MainActor
@Observable
final class MobileAppModel {
    private struct DiscoveredConnection {
        let profile: NasProfile
        let capabilities: CapabilitySet
    }

    private let profileKey = "lanstash.mobile.profiles.v1"
    private let lastProfileKey = "lanstash.mobile.last-profile.v1"
    private let autoLoginKeyPrefix = "lanstash.mobile.auto-login.v1."
    private let defaults: UserDefaults
    private let sessionStore: any SessionSecureStoring
    private let passwordStore: any PasswordSecureStoring
    private let authRepository: any AuthRepository
    private let quickConnectResolver: any QuickConnectResolving

    var profiles: [NasProfile] = []
    var selectedProfileID: UUID?
    var displayName = "我的 NAS"
    var host = ""
    var port = ""
    var username = ""
    var password = ""
    var otpCode = ""
    var rememberPassword = false
    var autoLoginEnabled = false
    var needsOTP = false
    var isConnecting = false
    var loginError: String?
    var connectionStatus: String?

    var isConnected = false
    var activeProfile: NasProfile?
    var selectedModule: MobileModule = .files
    var isLoading = false
    var actionInProgress = false
    var message: String?

    var currentPath = ""
    var pathHistory: [String] = []
    var files: [FileItem] = []
    var downloadSnapshot: DownloadStationSnapshot?
    var containerSnapshot: ContainerManagerSnapshot?
    var virtualMachineSnapshot: VirtualMachineManagerSnapshot?
    var conversations: [ChatConversation] = []
    var systemOverview: NasSystemOverview?
    var storageSnapshot: NasStorageSnapshot?
    var packages: [NasPackage] = []
    var accountsAndGroups: NasAccountDirectory?
    var logs: NasLogPage?
    var connections: NasConnectionPage?

    private var capabilities: CapabilitySet?
    private var session: AuthSession?
    private var activeConnectionProfile: NasProfile?
    private var fileRepository: DsmFileRepository?
    private var serviceRepository: DsmServiceManagementRepository?
    private var chatRepository: DsmChatRepository?
    private var nasRepository: DsmNasAdministrationRepository?

    init(
        defaults: UserDefaults = .standard,
        sessionStore: any SessionSecureStoring = KeychainSessionStore(),
        passwordStore: any PasswordSecureStoring = KeychainPasswordStore(),
        authRepository: (any AuthRepository)? = nil,
        quickConnectResolver: any QuickConnectResolving = DsmQuickConnectResolver()
    ) {
        self.defaults = defaults
        self.sessionStore = sessionStore
        self.passwordStore = passwordStore
        self.authRepository = authRepository ?? DsmAuthRepository(sessionStore: sessionStore)
        self.quickConnectResolver = quickConnectResolver
        loadProfiles()
        if let profile = profiles.first(where: {
            $0.id.uuidString == defaults.string(forKey: lastProfileKey)
        }) ?? profiles.first {
            applyProfile(profile)
            Task { await loadSavedPassword(for: profile, attemptsAutoLogin: true) }
        }
    }

    func selectProfile(_ profile: NasProfile) {
        applyProfile(profile)
        Task { await loadSavedPassword(for: profile, attemptsAutoLogin: false) }
    }

    private func applyProfile(_ profile: NasProfile) {
        selectedProfileID = profile.id
        defaults.set(profile.id.uuidString, forKey: lastProfileKey)
        displayName = profile.displayName
        host = profile.host
        port = profile.portOverride.map(String.init) ?? ""
        username = profile.usernameHint ?? ""
        password = ""
        rememberPassword = false
        autoLoginEnabled = defaults.bool(forKey: autoLoginKeyPrefix + profile.id.uuidString)
        otpCode = ""
        loginError = nil
        connectionStatus = nil
    }

    func newProfile() {
        selectedProfileID = nil
        displayName = "我的 NAS"
        host = ""
        port = ""
        username = ""
        password = ""
        rememberPassword = false
        autoLoginEnabled = false
        otpCode = ""
        loginError = nil
        connectionStatus = nil
        defaults.removeObject(forKey: lastProfileKey)
    }

    func removeProfile(_ profile: NasProfile) {
        profiles.removeAll { $0.id == profile.id }
        persistProfiles()
        defaults.removeObject(forKey: autoLoginKeyPrefix + profile.id.uuidString)
        Task {
            try? await sessionStore.remove(for: profile.id)
            try? await passwordStore.remove(for: profile.id)
        }
        if selectedProfileID == profile.id {
            newProfile()
        }
    }

    func connect() {
        guard !isConnecting else { return }
        isConnecting = true
        loginError = nil
        connectionStatus = "正在检查 NAS…"
        Task {
            do {
                let profile = try makeProfile()
                let connection = try await discoverConnection(for: profile)
                connectionStatus = "已找到 NAS，正在登录…"
                let session = try await authRepository.login(
                    profile: connection.profile,
                    capabilities: connection.capabilities,
                    account: username.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password,
                    otpCode: otpCode.isEmpty ? nil : otpCode
                )
                if rememberPassword {
                    try await passwordStore.save(password, for: profile.id)
                } else {
                    try? await passwordStore.remove(for: profile.id)
                    autoLoginEnabled = false
                }
                defaults.set(
                    autoLoginEnabled && rememberPassword,
                    forKey: autoLoginKeyPrefix + profile.id.uuidString
                )
                defaults.set(profile.id.uuidString, forKey: lastProfileKey)
                try configureWorkspace(
                    profile: connection.profile,
                    capabilities: connection.capabilities,
                    session: session
                )
                saveProfile(profile)
                self.capabilities = connection.capabilities
                self.session = session
                activeConnectionProfile = connection.profile
                activeProfile = profile
                isConnected = true
                isConnecting = false
                connectionStatus = nil
                if !rememberPassword {
                    password = ""
                }
                await loadSelectedModule()
            } catch {
                let appError = error as? AppError
                needsOTP = appError?.category == .otpRequired
                loginError = appError?.safeUserMessage
                    ?? (error as? LocalizedError)?.errorDescription
                    ?? "无法连接到 NAS，请检查地址和登录信息后重试。"
                isConnecting = false
                connectionStatus = nil
            }
        }
    }

    func restore(_ profile: NasProfile, fallbackToPassword: Bool = false) {
        guard !isConnecting else { return }
        isConnecting = true
        loginError = nil
        connectionStatus = "正在恢复登录…"
        Task {
            do {
                guard let session = try await sessionStore.load(for: profile.id) else {
                    throw AppError(
                        category: .authenticationRequired,
                        isRetryable: false,
                        safeUserMessage: "请输入密码重新登录。"
                    )
                }
                let connection = try await discoverConnection(for: profile)
                try configureWorkspace(
                    profile: connection.profile,
                    capabilities: connection.capabilities,
                    session: session
                )
                _ = try await fileRepository?.listShares(offset: 0, limit: 1)
                self.capabilities = connection.capabilities
                self.session = session
                activeConnectionProfile = connection.profile
                activeProfile = profile
                isConnected = true
                isConnecting = false
                connectionStatus = nil
                await loadSelectedModule()
            } catch {
                try? await sessionStore.remove(for: profile.id)
                isConnecting = false
                connectionStatus = nil
                applyProfile(profile)
                await loadSavedPassword(for: profile, attemptsAutoLogin: false)
                if fallbackToPassword && autoLoginEnabled && !password.isEmpty {
                    connect()
                } else {
                    loginError = password.isEmpty
                        ? "保存的登录已失效，请输入密码重新登录。"
                        : "保存的登录已失效，密码已为你填好，请重新连接。"
                }
            }
        }
    }

    func logout() {
        guard let profile = activeProfile else { return }
        let connectionProfile = activeConnectionProfile ?? profile
        let capabilities = capabilities
        let session = session
        autoLoginEnabled = false
        defaults.set(false, forKey: autoLoginKeyPrefix + profile.id.uuidString)
        Task {
            if let capabilities, let session {
                try? await authRepository.logout(
                    profile: connectionProfile,
                    capabilities: capabilities,
                    session: session
                )
            }
            try? await sessionStore.remove(for: profile.id)
        }
        clearWorkspace()
    }

    func selectModule(_ module: MobileModule) {
        selectedModule = module
        Task { await loadSelectedModule() }
    }

    func loadSelectedModule() async {
        guard isConnected else { return }
        isLoading = true
        message = nil
        do {
            switch selectedModule {
            case .files, .photos:
                try await loadFiles()
            case .chat:
                conversations = try await chatRepository?.listConversations() ?? []
            case .downloads:
                downloadSnapshot = try await serviceRepository?.loadDownloadStation()
            case .containers:
                containerSnapshot = try await serviceRepository?.loadContainerManager()
            case .virtualMachines:
                virtualMachineSnapshot = try await serviceRepository?.loadVirtualMachineManager()
            case .nasSettings:
                try await loadNasSettings()
            case .transfers, .settings:
                break
            }
            isLoading = false
        } catch {
            message = userMessage(error)
            isLoading = false
        }
    }

    func openDirectory(_ item: FileItem) {
        guard item.isDirectory else { return }
        pathHistory.append(currentPath)
        currentPath = item.path
        Task { await loadSelectedModule() }
    }

    func goBackDirectory() {
        guard let previous = pathHistory.popLast() else { return }
        currentPath = previous
        Task { await loadSelectedModule() }
    }

    func searchFiles(_ query: String) {
        guard let fileRepository, !query.isEmpty else {
            Task { await loadSelectedModule() }
            return
        }
        isLoading = true
        Task {
            do {
                files = try await fileRepository.search(
                    folderPath: currentPath.isEmpty ? "/" : currentPath,
                    query: query
                )
                isLoading = false
            } catch {
                message = userMessage(error)
                isLoading = false
            }
        }
    }

    func createFolder(name: String) {
        perform("文件夹已创建") { [self] in
            try await fileRepository?.createFolder(
                parentPath: currentPath.isEmpty ? "/" : currentPath,
                name: name
            )
            try await loadFiles()
        }
    }

    func rename(_ item: FileItem, to name: String) {
        perform("名称已修改") { [self] in
            try await fileRepository?.rename(path: item.path, newName: name)
            try await loadFiles()
        }
    }

    func delete(_ items: [FileItem]) {
        perform("已提交删除") { [self] in
            guard let fileRepository else { return }
            try await fileRepository.delete(paths: items.map(\.path)) { _, _ in }
            try await loadFiles()
        }
    }

    func createDownload(uri: String, destination: String?) {
        perform("下载任务已创建") { [self] in
            try await serviceRepository?.createDownloadTask(uri: uri, destination: destination)
            downloadSnapshot = try await serviceRepository?.loadDownloadStation()
        }
    }

    func controlDownload(_ task: DownloadStationTask, action: DownloadStationTaskAction) {
        perform("下载任务已更新") { [self] in
            try await serviceRepository?.controlDownloadTasks(ids: [task.id], action: action)
            downloadSnapshot = try await serviceRepository?.loadDownloadStation()
        }
    }

    func deleteDownload(_ task: DownloadStationTask, removeData: Bool) {
        perform("下载任务已移除") { [self] in
            try await serviceRepository?.deleteDownloadTasks(
                ids: [task.id],
                removeData: removeData
            )
            downloadSnapshot = try await serviceRepository?.loadDownloadStation()
        }
    }

    func controlContainer(_ container: ContainerInstance, action: ContainerAction) {
        perform("容器状态已更新") { [self] in
            try await serviceRepository?.controlContainers(ids: [container.id], action: action)
            containerSnapshot = try await serviceRepository?.loadContainerManager()
        }
    }

    func deleteContainer(_ container: ContainerInstance) {
        perform("容器已删除") { [self] in
            try await serviceRepository?.deleteContainers(ids: [container.id])
            containerSnapshot = try await serviceRepository?.loadContainerManager()
        }
    }

    func deleteContainerImage(_ image: ContainerImage) {
        perform("映像已删除") { [self] in
            try await serviceRepository?.deleteContainerImages(ids: [image.id])
            containerSnapshot = try await serviceRepository?.loadContainerManager()
        }
    }

    func createContainerNetwork(name: String, driver: String) {
        perform("网络已创建") { [self] in
            try await serviceRepository?.createContainerNetwork(name: name, driver: driver)
            containerSnapshot = try await serviceRepository?.loadContainerManager()
        }
    }

    func deleteContainerNetwork(_ network: ContainerNetwork) {
        perform("网络已删除") { [self] in
            try await serviceRepository?.deleteContainerNetworks(ids: [network.id])
            containerSnapshot = try await serviceRepository?.loadContainerManager()
        }
    }

    func controlVirtualMachine(_ machine: VirtualMachine, action: VirtualMachinePowerAction) {
        perform("虚拟机状态已更新") { [self] in
            try await serviceRepository?.controlVirtualMachines(ids: [machine.id], action: action)
            virtualMachineSnapshot = try await serviceRepository?.loadVirtualMachineManager()
        }
    }

    func deleteVirtualMachine(_ machine: VirtualMachine) {
        perform("虚拟机已删除") { [self] in
            try await serviceRepository?.deleteVirtualMachines(ids: [machine.id])
            virtualMachineSnapshot = try await serviceRepository?.loadVirtualMachineManager()
        }
    }

    func updateVirtualMachineNetwork(_ network: VirtualizationResource, name: String) {
        perform("网络已修改") { [self] in
            try await serviceRepository?.updateVirtualMachineNetwork(
                id: network.id,
                configuration: VirtualMachineNetworkUpdate(name: name)
            )
            virtualMachineSnapshot = try await serviceRepository?.loadVirtualMachineManager()
        }
    }

    func deleteVirtualMachineNetwork(_ network: VirtualizationResource) {
        perform("网络已删除") { [self] in
            try await serviceRepository?.deleteVirtualMachineNetworks(ids: [network.id])
            virtualMachineSnapshot = try await serviceRepository?.loadVirtualMachineManager()
        }
    }

    func deleteVirtualMachineImage(_ image: VirtualizationResource) {
        perform("映像已删除") { [self] in
            try await serviceRepository?.deleteVirtualMachineImages(ids: [image.id])
            virtualMachineSnapshot = try await serviceRepository?.loadVirtualMachineManager()
        }
    }

    private func loadFiles() async throws {
        guard let fileRepository else { return }
        let page = if currentPath.isEmpty {
            try await fileRepository.listShares(offset: 0, limit: 500)
        } else {
            try await fileRepository.listFolder(path: currentPath, offset: 0, limit: 500)
        }
        files = page.items
    }

    private func loadNasSettings() async throws {
        guard let nasRepository else { return }
        async let overview = nasRepository.loadSystemOverview()
        async let storage = nasRepository.loadStorage()
        async let packageList = nasRepository.loadPackages()
        async let directory = nasRepository.loadAccountsAndGroups()
        async let logPage = nasRepository.loadLogs(offset: 0, limit: 200)
        async let connectionPage = nasRepository.loadConnections(offset: 0, limit: 200)
        systemOverview = try await overview
        storageSnapshot = try await storage
        packages = try await packageList
        accountsAndGroups = try await directory
        logs = try await logPage
        connections = try await connectionPage
    }

    private func configureWorkspace(
        profile: NasProfile,
        capabilities: CapabilitySet,
        session: AuthSession
    ) throws {
        fileRepository = try DsmFileRepository(
            profile: profile,
            capabilities: capabilities,
            session: session
        )
        serviceRepository = try DsmServiceManagementRepository(
            profile: profile,
            capabilities: capabilities,
            session: session
        )
        chatRepository = try DsmChatRepository(
            profile: profile,
            capabilities: capabilities,
            session: session
        )
        nasRepository = try DsmNasAdministrationRepository(
            profile: profile,
            capabilities: capabilities,
            session: session
        )
    }

    private func perform(_ success: String, operation: @escaping @MainActor () async throws -> Void) {
        guard !actionInProgress else { return }
        actionInProgress = true
        message = nil
        Task {
            do {
                try await operation()
                message = success
            } catch {
                message = userMessage(error)
            }
            actionInProgress = false
        }
    }

    private func makeProfile() throws -> NasProfile {
        let trimmedPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        let manualPort: Int?
        if trimmedPort.isEmpty {
            manualPort = nil
        } else {
            guard let parsed = Int(trimmedPort), (1...65_535).contains(parsed) else {
                throw NasProfileValidationError.invalidPort
            }
            manualPort = parsed
        }
        let parsedAddress = try NasAddressParser.parse(host, defaultPort: manualPort ?? 5_001)
        let portOverride = parsedAddress.hasExplicitPort ? parsedAddress.port : manualPort
        let effectivePort = portOverride ?? parsedAddress.port
        host = parsedAddress.host
        port = portOverride.map(String.init) ?? ""
        return try NasProfile(
            id: selectedProfileID ?? UUID(),
            displayName: displayName,
            host: parsedAddress.host,
            port: effectivePort,
            portOverride: portOverride,
            usernameHint: username
        )
    }

    private func discoverConnection(for profile: NasProfile) async throws -> DiscoveredConnection {
        let parsedAddress = try NasAddressParser.parse(profile.host, defaultPort: profile.port)
        guard parsedAddress.kind == .quickConnect else {
            return DiscoveredConnection(
                profile: profile,
                capabilities: try await authRepository.discover(profile: profile)
            )
        }

        connectionStatus = "正在通过 QuickConnect 查找 NAS…"
        let endpoints: [QuickConnectEndpoint]
        do {
            endpoints = try await quickConnectResolver.resolve(id: parsedAddress.host)
        } catch let error as QuickConnectResolutionError where error == .noDirectRoute {
            // 未找到直连地址时仍可尝试中继；此阶段不会发送账号或密码。
            endpoints = []
        }

        for endpoint in endpoints {
            connectionStatus = endpoint.kind == .local
                ? "正在尝试局域网连接…"
                : "正在尝试外网直接连接…"
            let endpointPort = profile.portOverride ?? endpoint.port
            let connectionProfile = try profile.updating(host: endpoint.host, port: endpointPort)
            do {
                return DiscoveredConnection(
                    profile: connectionProfile,
                    capabilities: try await authRepository.discover(profile: connectionProfile)
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // 只做能力发现，当前地址不可用时继续尝试，登录信息尚未发送。
                continue
            }
        }

        connectionStatus = "正在建立 QuickConnect 中继连接…"
        let relay = try await quickConnectResolver.requestRelay(id: parsedAddress.host)
        let relayProfile = try profile.updating(
            host: relay.host,
            port: relay.port,
            clearCertificatePin: true
        )
        return DiscoveredConnection(
            profile: relayProfile,
            capabilities: try await authRepository.discover(profile: relayProfile)
        )
    }

    private func saveProfile(_ profile: NasProfile) {
        profiles.removeAll { $0.id == profile.id }
        profiles.append(profile)
        profiles.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        selectedProfileID = profile.id
        persistProfiles()
    }

    private func loadSavedPassword(for profile: NasProfile, attemptsAutoLogin: Bool) async {
        do {
            let storedPassword = try await passwordStore.load(for: profile.id)
            guard selectedProfileID == profile.id else { return }
            password = storedPassword ?? ""
            rememberPassword = storedPassword != nil
            autoLoginEnabled = defaults.bool(forKey: autoLoginKeyPrefix + profile.id.uuidString)
            if storedPassword == nil && autoLoginEnabled {
                autoLoginEnabled = false
                defaults.set(false, forKey: autoLoginKeyPrefix + profile.id.uuidString)
            }
            if attemptsAutoLogin && autoLoginEnabled && storedPassword != nil {
                restore(profile, fallbackToPassword: true)
            }
        } catch {
            guard selectedProfileID == profile.id else { return }
            password = ""
            rememberPassword = false
            autoLoginEnabled = false
            defaults.set(false, forKey: autoLoginKeyPrefix + profile.id.uuidString)
            loginError = (error as? LocalizedError)?.errorDescription
                ?? "无法读取已保存的密码，请重新输入。"
        }
    }

    private func loadProfiles() {
        guard let data = defaults.data(forKey: profileKey),
              let saved = try? JSONDecoder().decode([NasProfile].self, from: data) else {
            return
        }
        profiles = saved
    }

    private func persistProfiles() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: profileKey)
    }

    private func clearWorkspace() {
        isConnected = false
        activeProfile = nil
        activeConnectionProfile = nil
        capabilities = nil
        session = nil
        fileRepository = nil
        serviceRepository = nil
        chatRepository = nil
        nasRepository = nil
        currentPath = ""
        pathHistory = []
        files = []
        downloadSnapshot = nil
        containerSnapshot = nil
        virtualMachineSnapshot = nil
        conversations = []
        systemOverview = nil
        storageSnapshot = nil
        packages = []
        accountsAndGroups = nil
        logs = nil
        connections = nil
    }

    private func userMessage(_ error: Error) -> String {
        (error as? AppError)?.safeUserMessage
            ?? (error as? LocalizedError)?.errorDescription
            ?? "没有完成这次操作，请稍后重试。"
    }
}
