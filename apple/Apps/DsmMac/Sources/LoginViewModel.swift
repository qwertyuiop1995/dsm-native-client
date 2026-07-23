import DsmCore
import DsmNetwork
import Foundation
import Observation

struct NASFileClipboard {
    let id = UUID()
    let sourceProfileID: UUID
    let items: [FileItem]
    let movesSource: Bool
}

struct PasteConflictPrompt {
    let clipboardID: UUID
    let destinationProfileID: UUID
    let destinationPath: String
    let conflictingNames: [String]
}

struct CertificatePrompt: Identifiable {
    let id = UUID()
    let error: DsmCertificateTrustError
    let previousFingerprint: String?

    var review: DsmCertificateReview {
        error.review
    }

    var isCertificateChange: Bool {
        if case .changed = error {
            return true
        }
        return false
    }

    var formattedPreviousFingerprint: String? {
        guard let previousFingerprint else {
            return nil
        }
        return stride(from: 0, to: previousFingerprint.count, by: 2).map { offset in
            let start = previousFingerprint.index(previousFingerprint.startIndex, offsetBy: offset)
            let end = previousFingerprint.index(
                start,
                offsetBy: min(2, previousFingerprint.distance(from: start, to: previousFingerprint.endIndex))
            )
            return String(previousFingerprint[start..<end])
        }.joined(separator: ":")
    }
}

@MainActor
final class NasProfileStore {
    private let defaults: UserDefaults
    private let key = "lanstash.nas-profiles.v1"
    private let autoLoginKeyPrefix = "lanstash.auto-login.v1."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [NasProfile] {
        guard let data = defaults.data(forKey: key),
              let profiles = try? JSONDecoder().decode([NasProfile].self, from: data) else {
            return []
        }
        return profiles
    }

    func save(_ profiles: [NasProfile]) throws {
        defaults.set(try JSONEncoder().encode(profiles), forKey: key)
    }

    func isAutoLoginEnabled(for profileID: UUID) -> Bool {
        defaults.bool(forKey: autoLoginKeyPrefix + profileID.uuidString)
    }

    func setAutoLoginEnabled(_ enabled: Bool, for profileID: UUID) {
        defaults.set(enabled, forKey: autoLoginKeyPrefix + profileID.uuidString)
    }

    func removeAutoLoginPreference(for profileID: UUID) {
        defaults.removeObject(forKey: autoLoginKeyPrefix + profileID.uuidString)
    }
}

@MainActor
@Observable
final class AppModel {
    enum ConnectionRoute: Equatable {
        case local
        case external
        case quickConnect

        var title: String {
            switch self {
            case .local: "局域网连接"
            case .external: "外网连接"
            case .quickConnect: "QuickConnect 连接"
            }
        }

        var systemImage: String {
            switch self {
            case .local: "house.and.flag.fill"
            case .external: "globe"
            case .quickConnect: "bolt.horizontal.circle.fill"
            }
        }
    }

    private enum CertificateRetryMode {
        case connect
        case restore
    }

    private enum SessionRestoreOutcome: Equatable {
        case connected
        case credentialsNeeded
        case stopped
    }

    private struct DiscoveredConnection {
        let profile: NasProfile
        let capabilities: CapabilitySet
        let route: ConnectionRoute
    }

    private struct ConnectionContext {
        let connectionProfile: NasProfile
        let capabilities: CapabilitySet
        let session: AuthSession
        let route: ConnectionRoute
    }

    var profiles: [NasProfile] = []
    var selectedProfileID: UUID?
    var workspace: WorkspaceModel?

    var displayName = "我的 NAS"
    var host = ""
    var port = ""
    var account = ""
    var password = ""
    var rememberPassword = false
    var autoLoginEnabled = false
    var otpCode = ""
    var requiresOTP = false
    var isBusy = false
    var statusMessage = "添加一台 NAS，然后输入账号和密码连接。"
    var statusIsError = false
    var pendingCertificate: CertificatePrompt?
    var fileClipboard: NASFileClipboard?
    var pendingPasteConflict: PasteConflictPrompt?
    var isPreparingPaste = false

    private let profileStore: NasProfileStore
    private let authRepository: any AuthRepository
    private let quickConnectResolver: any QuickConnectResolving
    private let passwordStore: any PasswordSecureStoring
    private var selectedProfile: NasProfile?
    private var activeConnectionProfile: NasProfile?
    private var capabilities: CapabilitySet?
    private var session: AuthSession?
    private var certificateRetryMode: CertificateRetryMode = .connect
    private var didLoad = false
    private var workspacesByProfileID: [UUID: WorkspaceModel] = [:]
    private var connectionContextsByProfileID: [UUID: ConnectionContext] = [:]
    @ObservationIgnored private var loginTask: Task<Void, Never>?

    var connectedWorkspaces: [WorkspaceModel] {
        profiles.compactMap { workspacesByProfileID[$0.id] }
    }

    var currentConnectionRoute: ConnectionRoute? {
        guard let selectedProfileID else { return nil }
        return connectionContextsByProfileID[selectedProfileID]?.route
    }

    init(
        profileStore: NasProfileStore = NasProfileStore(),
        authRepository: any AuthRepository = DsmAuthRepository(),
        quickConnectResolver: any QuickConnectResolving = DsmQuickConnectResolver(),
        passwordStore: any PasswordSecureStoring = LocalFileSecureStore()
    ) {
        self.profileStore = profileStore
        self.authRepository = authRepository
        self.quickConnectResolver = quickConnectResolver
        self.passwordStore = passwordStore
    }

    func load() {
        guard !didLoad else {
            return
        }
        didLoad = true
        profiles = profileStore.load()
        if let first = profiles.first {
            chooseProfile(
                first,
                attemptSessionRestore: profileStore.isAutoLoginEnabled(for: first.id)
            )
        }
    }

    func newProfile() {
        closeCurrentWorkspace()
        selectedProfileID = nil
        selectedProfile = nil
        displayName = "我的 NAS"
        host = ""
        port = ""
        account = ""
        password = ""
        rememberPassword = false
        autoLoginEnabled = false
        otpCode = ""
        requiresOTP = false
        statusIsError = false
        statusMessage = "请输入 NAS 地址和登录信息。"
    }

    func selectProfile(id: UUID?) {
        guard let id, let profile = profiles.first(where: { $0.id == id }) else {
            newProfile()
            return
        }
        guard selectedProfile?.id != id else {
            return
        }
        closeCurrentWorkspace()
        chooseProfile(
            profile,
            attemptSessionRestore: profileStore.isAutoLoginEnabled(for: profile.id)
        )
    }

    func setRememberPassword(_ enabled: Bool) {
        rememberPassword = enabled
        if !enabled {
            setAutoLoginEnabled(false)
        }
    }

    func setAutoLoginEnabled(_ enabled: Bool) {
        autoLoginEnabled = enabled
        if enabled {
            rememberPassword = true
        }
        if let profileID = selectedProfile?.id {
            profileStore.setAutoLoginEnabled(enabled, for: profileID)
        }
    }

    func placeOnClipboard(_ items: [FileItem], moveSource: Bool) {
        guard let sourceProfileID = workspace?.profile.id, !items.isEmpty else { return }
        pendingPasteConflict = nil
        fileClipboard = NASFileClipboard(
            sourceProfileID: sourceProfileID,
            items: items,
            movesSource: moveSource
        )
        workspace?.statusIsError = false
        workspace?.statusMessage = moveSource
            ? "已准备移动 \(items.count) 个项目。请打开目标目录后选择“粘贴”。"
            : "已复制 \(items.count) 个项目。请打开目标目录后选择“粘贴”。"
    }

    func pasteClipboardIntoCurrentFolder() {
        guard let clipboard = fileClipboard,
              let destination = workspace,
              !destination.currentPath.isEmpty,
              workspacesByProfileID[clipboard.sourceProfileID] != nil,
              pendingPasteConflict == nil,
              !isPreparingPaste else {
            return
        }
        isPreparingPaste = true
        destination.statusIsError = false
        destination.statusMessage = "正在检查目标文件夹…"
        let destinationPath = destination.currentPath
        Task { [weak self] in
            guard let self else { return }
            defer { isPreparingPaste = false }
            guard let conflictingNames = await destination.pasteConflictNames(
                for: clipboard.items,
                in: destinationPath
            ) else {
                return
            }
            guard fileClipboard?.id == clipboard.id,
                  workspace?.profile.id == destination.profile.id,
                  workspace?.currentPath == destinationPath else {
                return
            }
            if conflictingNames.isEmpty {
                executePaste(clipboard, into: destination, overwrite: false)
            } else {
                destination.statusMessage = "发现同名项目，请选择处理方式。"
                pendingPasteConflict = PasteConflictPrompt(
                    clipboardID: clipboard.id,
                    destinationProfileID: destination.profile.id,
                    destinationPath: destinationPath,
                    conflictingNames: conflictingNames
                )
            }
        }
    }

    func cancelPendingPaste() {
        pendingPasteConflict = nil
    }

    func resolvePendingPaste(replaceExisting: Bool) {
        guard let prompt = pendingPasteConflict else { return }
        pendingPasteConflict = nil
        guard let clipboard = fileClipboard,
              clipboard.id == prompt.clipboardID,
              let destination = workspace,
              destination.profile.id == prompt.destinationProfileID,
              destination.currentPath == prompt.destinationPath else {
            workspace?.statusIsError = true
            workspace?.statusMessage = "粘贴位置已经改变，请在目标文件夹中重新选择“粘贴”。"
            return
        }
        executePaste(clipboard, into: destination, overwrite: replaceExisting)
    }

    private func executePaste(
        _ clipboard: NASFileClipboard,
        into destination: WorkspaceModel,
        overwrite: Bool
    ) {
        guard let source = workspacesByProfileID[clipboard.sourceProfileID] else { return }
        if source.profile.id == destination.profile.id {
            destination.enqueueFileOperation(
                clipboard.items,
                to: destination.currentPath,
                moveSource: clipboard.movesSource,
                overwrite: overwrite
            )
        } else {
            destination.enqueueCrossNASOperation(
                from: source,
                targets: clipboard.items,
                to: destination.currentPath,
                moveSource: clipboard.movesSource,
                overwrite: overwrite
            )
        }
        if clipboard.movesSource {
            fileClipboard = nil
        }
    }

    func renameCurrentNAS(to newName: String) -> String? {
        guard let profile = selectedProfile else {
            return "当前没有可修改的 NAS。"
        }
        do {
            let updated = try profile.updating(displayName: newName)
            selectedProfile = updated
            displayName = updated.displayName
            workspace?.updateProfile(updated)
            workspacesByProfileID[updated.id]?.updateProfile(updated)

            if let context = connectionContextsByProfileID[updated.id] {
                let connectionProfile = try context.connectionProfile.updating(
                    displayName: updated.displayName
                )
                let updatedContext = ConnectionContext(
                    connectionProfile: connectionProfile,
                    capabilities: context.capabilities,
                    session: context.session,
                    route: context.route
                )
                connectionContextsByProfileID[updated.id] = updatedContext
                if activeConnectionProfile?.id == updated.id {
                    activeConnectionProfile = connectionProfile
                }
            }
            upsertProfile(updated)
            statusIsError = false
            statusMessage = "NAS 名称已修改为“\(updated.displayName)”。"
            return nil
        } catch let error as NasProfileValidationError {
            return error.localizedDescription
        } catch {
            return "无法修改 NAS 名称，请重试。"
        }
    }

    func cancelLogin() {
        loginTask?.cancel()
        loginTask = nil
        isBusy = false
        statusIsError = false
        statusMessage = "已取消登录。"
    }

    func connect() async {
        guard !isBusy else { return }
        loginTask?.cancel()
        let task = Task<Void, Never> { [weak self] in
            await self?.performConnect()
        }
        loginTask = task
        await task.value
        loginTask = nil
    }

    private func performConnect() async {
        guard !isBusy else { return }
        isBusy = true
        statusIsError = false
        statusMessage = "正在检查 NAS…"
        defer { isBusy = false }

        do {
            if autoLoginEnabled {
                rememberPassword = true
            }
            let profile = try makeProfile()
            let submittedPassword = password
            selectedProfile = profile
            upsertProfile(profile)

            let connection = try await discoverConnection(for: profile)
            capabilities = connection.capabilities
            statusMessage = "已找到 NAS，正在登录…"

            let authenticated = try await authRepository.login(
                profile: connection.profile,
                capabilities: connection.capabilities,
                account: account,
                password: password,
                otpCode: requiresOTP ? otpCode : nil
            )
            session = authenticated
            otpCode = ""
            requiresOTP = false

            let updated = try profile.updating(usernameHint: account)
            selectedProfile = updated
            upsertProfile(updated)
            var passwordStorageFailed = false
            do {
                if rememberPassword {
                    try await passwordStore.save(submittedPassword, for: updated.id)
                    password = submittedPassword
                } else {
                    try await passwordStore.remove(for: updated.id)
                    password = ""
                }
            } catch {
                passwordStorageFailed = true
                password = ""
                rememberPassword = false
                autoLoginEnabled = false
            }
            profileStore.setAutoLoginEnabled(
                autoLoginEnabled && rememberPassword && !passwordStorageFailed,
                for: updated.id
            )
            try openWorkspace(
                profile: updated,
                connectionProfile: connection.profile,
                capabilities: connection.capabilities,
                session: authenticated,
                route: connection.route
            )
            if passwordStorageFailed {
                statusMessage = "已连接，但无法在这台 Mac 上保存密码。下次需要重新输入。"
            }
        } catch is CancellationError {
            return
        } catch let error as DsmCertificateTrustError {
            certificateRetryMode = .connect
            pendingCertificate = CertificatePrompt(
                error: error,
                previousFingerprint: selectedProfile?.pinnedCertificateSHA256
            )
            statusIsError = true
            statusMessage = error.localizedDescription
        } catch let error as AppError {
            handleLoginError(error)
        } catch let error as NasProfileValidationError {
            statusIsError = true
            statusMessage = error.localizedDescription
            password = ""
            otpCode = ""
        } catch let error as NasAddressInputError {
            statusIsError = true
            statusMessage = error.localizedDescription
            password = ""
            otpCode = ""
        } catch let error as QuickConnectResolutionError {
            statusIsError = true
            statusMessage = error.localizedDescription
            password = ""
            otpCode = ""
        } catch {
            statusIsError = true
            statusMessage = "连接失败，请检查地址和网络后重试。"
            password = ""
            otpCode = ""
        }
    }

    func acceptPendingCertificate() async {
        guard let prompt = pendingCertificate,
              prompt.review.canBePinned,
              let profile = selectedProfile else {
            return
        }
        do {
            let updated = try profile.updating(
                pinnedCertificateSHA256: prompt.review.sha256Fingerprint,
                clearCertificatePin: false
            )
            selectedProfile = updated
            pendingCertificate = nil
            upsertProfile(updated)
            switch certificateRetryMode {
            case .connect:
                await connect()
            case .restore:
                await restoreSession(for: updated)
            }
        } catch {
            statusIsError = true
            statusMessage = "无法保存这台 NAS 的安全信息，请重试。"
        }
    }

    func cancelCertificateReview() {
        pendingCertificate = nil
        password = ""
        rememberPassword = false
        otpCode = ""
    }

    func deleteSelectedProfile() async {
        guard let profile = selectedProfile else {
            return
        }
        try? await authRepository.clearSession(for: profile.id)
        try? await passwordStore.remove(for: profile.id)
        profileStore.removeAutoLoginPreference(for: profile.id)
        workspacesByProfileID[profile.id]?.cancelAllWork()
        workspacesByProfileID[profile.id] = nil
        connectionContextsByProfileID[profile.id] = nil
        profiles.removeAll { $0.id == profile.id }
        try? profileStore.save(profiles)
        newProfile()
    }

    func logout() async {
        let profile = selectedProfile
        let connectionProfile = activeConnectionProfile
        let discovered = capabilities
        let authenticated = session
        workspace?.cancelAllWork()
        if let profile {
            workspacesByProfileID[profile.id] = nil
            connectionContextsByProfileID[profile.id] = nil
        }
        workspace = nil
        session = nil
        activeConnectionProfile = nil
        autoLoginEnabled = false
        otpCode = ""
        requiresOTP = false

        guard let profile else {
            password = ""
            rememberPassword = false
            statusMessage = "已退出。"
            return
        }

        // 主动退出只停用自动登录；已记住的密码保留并重新加载到登录界面，
        // 避免下次需要重新输入。
        profileStore.setAutoLoginEnabled(false, for: profile.id)
        await loadSavedPassword(for: profile)

        guard let discovered, let authenticated else {
            statusMessage = "已退出。"
            return
        }
        do {
            try await authRepository.logout(
                profile: connectionProfile ?? profile,
                capabilities: discovered,
                session: authenticated
            )
            statusIsError = false
            statusMessage = "已退出登录。"
        } catch {
            statusIsError = true
            statusMessage = "已在这台 Mac 上退出；NAS 暂时没有响应。"
        }
    }

    func returnToLoginAfterSessionIssue(message: String) async {
        let profile = selectedProfile
        workspace?.cancelAllWork()
        if let profile {
            workspacesByProfileID[profile.id] = nil
            connectionContextsByProfileID[profile.id] = nil
        }
        workspace = nil
        session = nil
        activeConnectionProfile = nil
        capabilities = nil
        password = ""
        rememberPassword = false
        if let profile {
            profileStore.setAutoLoginEnabled(false, for: profile.id)
        }
        autoLoginEnabled = false
        otpCode = ""
        requiresOTP = false

        if let profile {
            try? await authRepository.clearSession(for: profile.id)
        }

        statusIsError = true
        statusMessage = message
    }

    private func chooseProfile(_ profile: NasProfile, attemptSessionRestore: Bool) {
        selectedProfile = profile
        activeConnectionProfile = nil
        selectedProfileID = profile.id
        displayName = profile.displayName
        host = profile.host
        port = profile.portOverride.map(String.init) ?? ""
        account = profile.usernameHint ?? ""
        password = ""
        rememberPassword = false
        autoLoginEnabled = profileStore.isAutoLoginEnabled(for: profile.id)
        otpCode = ""
        requiresOTP = false
        statusIsError = false
        statusMessage = "已选择 \(profile.displayName)，请输入密码后连接。"

        if let cachedWorkspace = workspacesByProfileID[profile.id],
           let context = connectionContextsByProfileID[profile.id] {
            workspace = cachedWorkspace
            activeConnectionProfile = context.connectionProfile
            capabilities = context.capabilities
            session = context.session
            statusMessage = "已切换到 \(profile.displayName)。"
            Task { await loadSavedPassword(for: profile) }
            return
        }

        guard attemptSessionRestore else {
            Task { await loadSavedPassword(for: profile) }
            return
        }
        Task {
            await loadSavedPassword(for: profile)
            guard selectedProfile?.id == profile.id, autoLoginEnabled, !password.isEmpty else {
                return
            }
            let outcome = await restoreSession(for: profile)
            if outcome == .credentialsNeeded,
               selectedProfile?.id == profile.id,
               autoLoginEnabled,
               !password.isEmpty {
                await connect()
            }
        }
    }

    private func closeCurrentWorkspace() {
        workspace = nil
        activeConnectionProfile = nil
        capabilities = nil
        session = nil
        pendingCertificate = nil
    }

    private func loadSavedPassword(for profile: NasProfile) async {
        do {
            let storedPassword = try await passwordStore.load(for: profile.id)
            guard selectedProfile?.id == profile.id else {
                return
            }
            password = storedPassword ?? ""
            rememberPassword = storedPassword != nil
            if storedPassword == nil, autoLoginEnabled {
                setAutoLoginEnabled(false)
            }
        } catch {
            guard selectedProfile?.id == profile.id else {
                return
            }
            password = ""
            rememberPassword = false
            if autoLoginEnabled {
                setAutoLoginEnabled(false)
            }
        }
    }

    @discardableResult
    private func restoreSession(for profile: NasProfile) async -> SessionRestoreOutcome {
        guard !isBusy else {
            return .stopped
        }
        isBusy = true
        statusMessage = "正在恢复上次连接…"
        defer { isBusy = false }
        do {
            guard let restored = try await authRepository.restoreSession(for: profile.id) else {
                statusMessage = "请输入密码以连接。"
                return .credentialsNeeded
            }
            let connection = try await discoverConnection(for: profile)
            session = restored
            capabilities = connection.capabilities

            if !(try await validateRestoredSession(
                profile: connection.profile,
                capabilities: connection.capabilities,
                session: restored
            )) {
                try? await authRepository.clearSession(for: profile.id)
                statusIsError = true
                statusMessage = "上次登录已失效，请重新输入密码。"
                return .credentialsNeeded
            }

            try openWorkspace(
                profile: profile,
                connectionProfile: connection.profile,
                capabilities: connection.capabilities,
                session: restored,
                route: connection.route
            )
            return .connected
        } catch let error as DsmCertificateTrustError {
            certificateRetryMode = .restore
            pendingCertificate = CertificatePrompt(
                error: error,
                previousFingerprint: profile.pinnedCertificateSHA256
            )
            statusIsError = true
            statusMessage = error.localizedDescription
            return .stopped
        } catch let error as QuickConnectResolutionError {
            statusIsError = true
            statusMessage = error.localizedDescription
            return .stopped
        } catch let error as AppError where error.isRetryable || error.category == .tlsUntrusted {
            statusIsError = true
            statusMessage = error.safeUserMessage
            return .stopped
        } catch {
            statusIsError = true
            statusMessage = "上次登录已失效，请重新输入密码。"
            try? await authRepository.clearSession(for: profile.id)
            return .credentialsNeeded
        }
    }

    private func validateRestoredSession(
        profile: NasProfile,
        capabilities: CapabilitySet,
        session: AuthSession
    ) async throws -> Bool {
        let probe = try DsmFileRepository(
            profile: profile,
            capabilities: capabilities,
            session: session
        )
        do {
            _ = try await probe.listShares(offset: 0, limit: 1)
            return true
        } catch let error as AppError where error.category == .authenticationRequired {
            return false
        }
    }

    private func openWorkspace(
        profile: NasProfile,
        connectionProfile: NasProfile,
        capabilities: CapabilitySet,
        session: AuthSession,
        route: ConnectionRoute
    ) throws {
        let repository = try DsmFileRepository(
            profile: connectionProfile,
            capabilities: capabilities,
            session: session
        )
        let chatRepository = try DsmChatRepository(
            profile: connectionProfile,
            capabilities: capabilities,
            session: session
        )
        activeConnectionProfile = connectionProfile
        let openedWorkspace = WorkspaceModel(
            profile: profile,
            repository: repository,
            chatRepository: chatRepository
        )
        workspacesByProfileID[profile.id] = openedWorkspace
        connectionContextsByProfileID[profile.id] = ConnectionContext(
            connectionProfile: connectionProfile,
            capabilities: capabilities,
            session: session,
            route: route
        )
        workspace = openedWorkspace
        statusIsError = false
        statusMessage = "已连接到 \(profile.displayName)。"
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
        let connectionChanged = selectedProfile.map {
            $0.host != parsedAddress.host || $0.portOverride != portOverride
        } ?? false
        return try NasProfile(
            id: selectedProfile?.id ?? UUID(),
            displayName: displayName,
            host: parsedAddress.host,
            port: effectivePort,
            portOverride: portOverride,
            usernameHint: account,
            pinnedCertificateSHA256: connectionChanged ? nil : selectedProfile?.pinnedCertificateSHA256,
            lastDsmBuild: selectedProfile?.lastDsmBuild
        )
    }

    private func discoverConnection(for profile: NasProfile) async throws -> DiscoveredConnection {
        let parsedAddress = try NasAddressParser.parse(profile.host, defaultPort: profile.port)
        guard parsedAddress.kind == .quickConnect else {
            let discovered = try await authRepository.discover(profile: profile)
            return DiscoveredConnection(
                profile: profile,
                capabilities: discovered,
                route: Self.isLocalHost(profile.host) ? .local : .external
            )
        }

        statusMessage = "正在通过 QuickConnect 查找 NAS…"
        let endpoints: [QuickConnectEndpoint]
        do {
            endpoints = try await quickConnectResolver.resolve(id: parsedAddress.host)
        } catch let error as QuickConnectResolutionError where error == .noDirectRoute {
            // 没有直连候选时仍可继续请求中继，登录信息尚未发送。
            endpoints = []
        }
        var certificateError: DsmCertificateTrustError?

        for endpoint in endpoints {
            statusMessage = endpoint.kind == .local
                ? "正在尝试局域网连接…"
                : "正在尝试外网直接连接…"
            let endpointPort = profile.portOverride ?? endpoint.port
            let connectionProfile = try profile.updating(host: endpoint.host, port: endpointPort)
            do {
                let discovered = try await authRepository.discover(profile: connectionProfile)
                return DiscoveredConnection(
                    profile: connectionProfile,
                    capabilities: discovered,
                    route: endpoint.kind == .local ? .local : .external
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as DsmCertificateTrustError {
                certificateError = error
            } catch {
                // 当前候选不可用时继续尝试下一个候选，登录信息尚未发送。
                continue
            }
        }

        statusMessage = "正在建立 QuickConnect 中继连接…"
        do {
            let relay = try await quickConnectResolver.requestRelay(id: parsedAddress.host)
            let relayProfile = try profile.updating(
                host: relay.host,
                port: relay.port,
                clearCertificatePin: true
            )
            let discovered = try await authRepository.discover(profile: relayProfile)
            return DiscoveredConnection(
                profile: relayProfile,
                capabilities: discovered,
                route: .quickConnect
            )
        } catch let error as QuickConnectResolutionError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if let certificateError {
                throw certificateError
            }
            throw error
        }
    }

    private static func isLocalHost(_ host: String) -> Bool {
        let value = host.lowercased()
        if value == "localhost" || value == "::1" || value.hasSuffix(".local") || !value.contains(".") {
            return true
        }
        if value.hasPrefix("fc") || value.hasPrefix("fd") || value.hasPrefix("fe80:") {
            return true
        }
        let parts = value.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else {
            return false
        }
        return parts[0] == 10
            || parts[0] == 127
            || (parts[0] == 172 && (16...31).contains(parts[1]))
            || (parts[0] == 192 && parts[1] == 168)
            || (parts[0] == 169 && parts[1] == 254)
    }

    func moveProfile(from source: IndexSet, to destination: Int) {
        guard let sourceIndex = source.first else { return }
        let profileID = profiles[sourceIndex].id
        profiles.move(fromOffsets: source, toOffset: destination)
        if selectedProfileID == profileID {
            selectedProfileID = profileID
        }
        do {
            try profileStore.save(profiles)
        } catch {
            statusIsError = true
            statusMessage = "无法保存 NAS 排序，请重试。"
        }
    }

    private func upsertProfile(_ profile: NasProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        selectedProfileID = profile.id
        do {
            try profileStore.save(profiles)
        } catch {
            statusIsError = true
            statusMessage = "无法保存这台 NAS，请重试。"
        }
    }

    private func handleLoginError(_ error: AppError) {
        statusIsError = true
        statusMessage = error.safeUserMessage
        if error.category == .otpRequired {
            requiresOTP = true
            otpCode = ""
        } else {
            password = ""
            otpCode = ""
        }
    }
}
