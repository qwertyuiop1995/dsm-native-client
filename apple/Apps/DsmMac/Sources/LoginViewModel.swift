import DsmCore
import DsmNetwork
import Foundation
import Observation

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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [NasProfile] {
        guard let data = defaults.data(forKey: key),
              let profiles = try? JSONDecoder().decode([NasProfile].self, from: data) else {
            return []
        }
        return profiles.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    func save(_ profiles: [NasProfile]) throws {
        defaults.set(try JSONEncoder().encode(profiles), forKey: key)
    }
}

@MainActor
@Observable
final class AppModel {
    private enum CertificateRetryMode {
        case connect
        case restore
    }

    private struct DiscoveredConnection {
        let profile: NasProfile
        let capabilities: CapabilitySet
    }

    var profiles: [NasProfile] = []
    var selectedProfileID: UUID?
    var workspace: WorkspaceModel?

    var displayName = "我的 NAS"
    var host = ""
    var port = "5001"
    var account = ""
    var password = ""
    var otpCode = ""
    var requiresOTP = false
    var isBusy = false
    var statusMessage = "添加一台 NAS，或先看看示例。"
    var statusIsError = false
    var pendingCertificate: CertificatePrompt?

    private let profileStore: NasProfileStore
    private let authRepository: any AuthRepository
    private let quickConnectResolver: any QuickConnectResolving
    private var selectedProfile: NasProfile?
    private var activeConnectionProfile: NasProfile?
    private var capabilities: CapabilitySet?
    private var session: AuthSession?
    private var certificateRetryMode: CertificateRetryMode = .connect
    private var didLoad = false

    init(
        profileStore: NasProfileStore = NasProfileStore(),
        authRepository: any AuthRepository = DsmAuthRepository(),
        quickConnectResolver: any QuickConnectResolving = DsmQuickConnectResolver()
    ) {
        self.profileStore = profileStore
        self.authRepository = authRepository
        self.quickConnectResolver = quickConnectResolver
    }

    func load() {
        guard !didLoad else {
            return
        }
        didLoad = true
        profiles = profileStore.load()
        if let first = profiles.first {
            chooseProfile(first, attemptSessionRestore: true)
        }
    }

    func newProfile() {
        selectedProfileID = nil
        selectedProfile = nil
        activeConnectionProfile = nil
        capabilities = nil
        session = nil
        displayName = "我的 NAS"
        host = ""
        port = "5001"
        account = ""
        password = ""
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
        chooseProfile(profile, attemptSessionRestore: true)
    }

    func connect() async {
        guard !isBusy else {
            return
        }
        isBusy = true
        statusIsError = false
        statusMessage = "正在检查 NAS…"
        defer { isBusy = false }

        do {
            let profile = try makeProfile()
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
            password = ""
            otpCode = ""
            requiresOTP = false

            let updated = try profile.updating(usernameHint: account)
            selectedProfile = updated
            upsertProfile(updated)
            try openWorkspace(
                profile: updated,
                connectionProfile: connection.profile,
                capabilities: connection.capabilities,
                session: authenticated
            )
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
        otpCode = ""
    }

    func deleteSelectedProfile() async {
        guard let profile = selectedProfile else {
            return
        }
        try? await authRepository.clearSession(for: profile.id)
        profiles.removeAll { $0.id == profile.id }
        try? profileStore.save(profiles)
        newProfile()
    }

    func enterDemo() {
        do {
            let profile = try NasProfile(
                displayName: "岚仓演示 NAS",
                host: "demo.lanstash.invalid",
                port: 5001,
                usernameHint: "demo"
            )
            let repository = DemoFileRepository(profileID: profile.id)
            capabilities = nil
            session = nil
            activeConnectionProfile = nil
            workspace = WorkspaceModel(profile: profile, repository: repository)
            statusIsError = false
            statusMessage = "示例已打开。"
        } catch {
            statusIsError = true
            statusMessage = "无法打开示例，请重试。"
        }
    }

    func logout() async {
        let wasDemo = workspace?.isDemo == true
        let profile = selectedProfile
        let connectionProfile = activeConnectionProfile
        let discovered = capabilities
        let authenticated = session
        workspace?.cancelAllWork()
        workspace = nil
        session = nil
        activeConnectionProfile = nil
        password = ""
        otpCode = ""
        requiresOTP = false

        if wasDemo {
            statusIsError = false
            statusMessage = "已关闭示例。"
            return
        }

        guard let profile, let discovered, let authenticated else {
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
        workspace = nil
        session = nil
        activeConnectionProfile = nil
        capabilities = nil
        password = ""
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
        port = String(profile.port)
        account = profile.usernameHint ?? ""
        password = ""
        otpCode = ""
        requiresOTP = false
        statusIsError = false
        statusMessage = "已选择 \(profile.displayName)，请输入密码后连接。"

        guard attemptSessionRestore else {
            return
        }
        Task {
            await restoreSession(for: profile)
        }
    }

    private func restoreSession(for profile: NasProfile) async {
        guard !isBusy else {
            return
        }
        isBusy = true
        statusMessage = "正在恢复上次连接…"
        defer { isBusy = false }
        do {
            guard let restored = try await authRepository.restoreSession(for: profile.id) else {
                statusMessage = "请输入密码以连接。"
                return
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
                return
            }

            try openWorkspace(
                profile: profile,
                connectionProfile: connection.profile,
                capabilities: connection.capabilities,
                session: restored
            )
        } catch let error as DsmCertificateTrustError {
            certificateRetryMode = .restore
            pendingCertificate = CertificatePrompt(
                error: error,
                previousFingerprint: profile.pinnedCertificateSHA256
            )
            statusIsError = true
            statusMessage = error.localizedDescription
        } catch let error as QuickConnectResolutionError {
            statusIsError = true
            statusMessage = error.localizedDescription
        } catch let error as AppError where error.isRetryable || error.category == .tlsUntrusted {
            statusIsError = true
            statusMessage = error.safeUserMessage
        } catch {
            statusIsError = true
            statusMessage = "上次登录已失效，请重新输入密码。"
            try? await authRepository.clearSession(for: profile.id)
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
        session: AuthSession
    ) throws {
        let repository = try DsmFileRepository(
            profile: connectionProfile,
            capabilities: capabilities,
            session: session
        )
        activeConnectionProfile = connectionProfile
        workspace = WorkspaceModel(profile: profile, repository: repository)
        statusIsError = false
        statusMessage = "已连接到 \(profile.displayName)。"
    }

    private func makeProfile() throws -> NasProfile {
        guard let parsedPort = Int(port) else {
            throw NasProfileValidationError.invalidPort
        }
        let parsedAddress = try NasAddressParser.parse(host, defaultPort: parsedPort)
        host = parsedAddress.host
        port = String(parsedAddress.port)
        let connectionChanged = selectedProfile.map {
            $0.host != parsedAddress.host || $0.port != parsedAddress.port
        } ?? false
        return try NasProfile(
            id: selectedProfile?.id ?? UUID(),
            displayName: displayName,
            host: parsedAddress.host,
            port: parsedAddress.port,
            usernameHint: account,
            pinnedCertificateSHA256: connectionChanged ? nil : selectedProfile?.pinnedCertificateSHA256,
            lastDsmBuild: selectedProfile?.lastDsmBuild
        )
    }

    private func discoverConnection(for profile: NasProfile) async throws -> DiscoveredConnection {
        let parsedAddress = try NasAddressParser.parse(profile.host, defaultPort: profile.port)
        let connectionProfile: NasProfile
        if parsedAddress.kind == .quickConnect {
            statusMessage = "正在通过 QuickConnect 查找 NAS…"
            let endpoint = try await quickConnectResolver.resolve(id: parsedAddress.host)
            connectionProfile = try profile.updating(host: endpoint.host, port: endpoint.port)
        } else {
            connectionProfile = profile
        }

        let discovered = try await authRepository.discover(profile: connectionProfile)
        return DiscoveredConnection(profile: connectionProfile, capabilities: discovered)
    }

    private func upsertProfile(_ profile: NasProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        profiles.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
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
