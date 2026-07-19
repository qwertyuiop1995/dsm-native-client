import DsmCore
import DsmNetwork
import Foundation
import XCTest
@testable import DsmMacExecutable

final class TextDocumentFormatterTests: XCTestCase {
    func testJSON整理会添加缩进并保留中文() throws {
        let formatted = try TextDocumentFormatter.format(
            #"{"name":"岚仓","items":[1,2]}"#,
            fileExtension: "json"
        )

        XCTAssertTrue(formatted.contains("\n  \"items\""))
        XCTAssertTrue(formatted.contains("\"岚仓\""))
        XCTAssertTrue(formatted.hasSuffix("\n"))
    }

    func test错误JSON不会生成可能损坏原文件的内容() {
        XCTAssertThrowsError(
            try TextDocumentFormatter.format("{\"name\":}", fileExtension: "json")
        )
    }

    func testJavaScript整理只调整安全空白() throws {
        let source = "function greet() {\nconsole.log('岚仓 { test }');\nif (true) {\nreturn 1;\n}\n}"
        let formatted = try TextDocumentFormatter.format(source, fileExtension: "js")

        XCTAssertTrue(formatted.contains("    console.log('岚仓 { test }');"))
        XCTAssertTrue(formatted.contains("        return 1;"))
        XCTAssertTrue(formatted.hasSuffix("\n"))
    }
}

private struct CertificateReviewAuthRepository: AuthRepository {
    private enum StubError: Error {
        case unexpectedCall
    }

    func discover(profile: NasProfile) async throws -> CapabilitySet {
        throw DsmCertificateTrustError.untrusted(
            DsmCertificateReview(
                host: profile.host,
                subjectSummary: "NAS",
                sha256Fingerprint: String(repeating: "A", count: 64),
                canBePinned: true
            )
        )
    }

    func login(
        profile: NasProfile,
        capabilities: CapabilitySet,
        account: String,
        password: String,
        otpCode: String?
    ) async throws -> AuthSession {
        throw StubError.unexpectedCall
    }

    func restoreSession(for profileID: UUID) async throws -> AuthSession? {
        nil
    }

    func clearSession(for profileID: UUID) async throws {}

    func logout(
        profile: NasProfile,
        capabilities: CapabilitySet,
        session: AuthSession
    ) async throws {}
}

private actor RecordingQuickConnectResolver: QuickConnectResolving {
    private(set) var requestedID: String?
    private(set) var relayRequestCount = 0
    private let endpoints: [QuickConnectEndpoint]
    private let relayEndpoint: QuickConnectEndpoint
    private let resolutionError: QuickConnectResolutionError?

    init(
        endpoints: [QuickConnectEndpoint] = [
            QuickConnectEndpoint(
                host: "192-168-1-20.family-nas.direct.quickconnect.to",
                port: 5_001,
                kind: .local
            )
        ],
        relayEndpoint: QuickConnectEndpoint = QuickConnectEndpoint(
            host: "family-nas.r1.quickconnect.to",
            port: 443,
            kind: .relay
        ),
        resolutionError: QuickConnectResolutionError? = nil
    ) {
        self.endpoints = endpoints
        self.relayEndpoint = relayEndpoint
        self.resolutionError = resolutionError
    }

    func resolve(id: String) async throws -> [QuickConnectEndpoint] {
        requestedID = id
        if let resolutionError {
            throw resolutionError
        }
        return endpoints
    }

    func requestRelay(id: String) async throws -> QuickConnectEndpoint {
        requestedID = id
        relayRequestCount += 1
        return relayEndpoint
    }
}

private actor RecordingAuthRepository: AuthRepository {
    private(set) var discoveredHost: String?
    private(set) var discoveredHosts: [String] = []
    private(set) var loginHost: String?
    private(set) var loginPort: Int?
    private(set) var clearSessionCallCount = 0
    private(set) var logoutCallCount = 0
    private(set) var loginCallCount = 0
    private let failingHosts: Set<String>

    init(failingHosts: Set<String> = []) {
        self.failingHosts = failingHosts
    }

    func discover(profile: NasProfile) async throws -> CapabilitySet {
        discoveredHost = profile.host
        discoveredHosts.append(profile.host)
        if failingHosts.contains(profile.host) {
            throw AppError(
                category: .networkUnavailable,
                isRetryable: true,
                safeUserMessage: "测试候选不可用。"
            )
        }
        return CapabilitySet([:])
    }

    func login(
        profile: NasProfile,
        capabilities: CapabilitySet,
        account: String,
        password: String,
        otpCode: String?
    ) async throws -> AuthSession {
        loginCallCount += 1
        loginHost = profile.host
        loginPort = profile.port
        return AuthSession(sid: "test-session", synoToken: nil, did: nil, isPortalPort: false)
    }

    func restoreSession(for profileID: UUID) async throws -> AuthSession? {
        nil
    }

    func clearSession(for profileID: UUID) async throws {
        clearSessionCallCount += 1
    }

    func logout(
        profile: NasProfile,
        capabilities: CapabilitySet,
        session: AuthSession
    ) async throws {
        logoutCallCount += 1
    }
}

private actor MemoryPasswordStore: PasswordSecureStoring {
    private var passwords: [UUID: String] = [:]

    func save(_ password: String, for profileID: UUID) async throws {
        passwords[profileID] = password
    }

    func load(for profileID: UUID) async throws -> String? {
        passwords[profileID]
    }

    func remove(for profileID: UUID) async throws {
        passwords[profileID] = nil
    }
}

final class ConnectionFlowTests: XCTestCase {
    @MainActor
    func test登录后修改NAS显示名称并同步工作区() async throws {
        let suiteName = "ConnectionFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            profileStore: NasProfileStore(defaults: defaults),
            authRepository: RecordingAuthRepository(),
            passwordStore: MemoryPasswordStore()
        )
        model.displayName = "修改前"
        model.host = "home-nas.local"
        model.account = "user"
        model.password = "local-test-password"
        await model.connect()

        let error = model.renameCurrentNAS(to: "修改后")

        XCTAssertNil(error)
        XCTAssertEqual(model.profiles.first?.displayName, "修改后")
        XCTAssertEqual(model.workspace?.profile.displayName, "修改后")
        XCTAssertEqual(NasProfileStore(defaults: defaults).load().first?.displayName, "修改后")
    }

    @MainActor
    func test选择记住密码后交给安全存储() async throws {
        let suiteName = "ConnectionFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let passwordStore = MemoryPasswordStore()
        let model = AppModel(
            profileStore: NasProfileStore(defaults: defaults),
            authRepository: RecordingAuthRepository(),
            passwordStore: passwordStore
        )
        model.host = "home-nas.local"
        model.account = "user"
        model.password = "local-test-password"
        model.rememberPassword = true

        await model.connect()

        let profileID = try XCTUnwrap(model.selectedProfileID)
        let stored = try await passwordStore.load(for: profileID)
        XCTAssertEqual(stored, "local-test-password")
        XCTAssertEqual(model.password, "local-test-password")
    }

    @MainActor
    func test自动登录选项持久化并在下次启动使用保存密码连接() async throws {
        let suiteName = "ConnectionFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let profileStore = NasProfileStore(defaults: defaults)
        let profile = try NasProfile(
            displayName: "家庭 NAS",
            host: "home-nas.local",
            port: 5_001,
            usernameHint: "user"
        )
        try profileStore.save([profile])
        profileStore.setAutoLoginEnabled(true, for: profile.id)
        let passwordStore = MemoryPasswordStore()
        try await passwordStore.save("local-test-password", for: profile.id)
        let authRepository = RecordingAuthRepository()
        let model = AppModel(
            profileStore: profileStore,
            authRepository: authRepository,
            passwordStore: passwordStore
        )

        model.load()
        for _ in 0..<100 {
            if model.workspace != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertNotNil(model.workspace)
        XCTAssertTrue(model.autoLoginEnabled)
        XCTAssertTrue(model.rememberPassword)
        let loginCallCount = await authRepository.loginCallCount
        XCTAssertEqual(loginCallCount, 1)
    }

    @MainActor
    func test关闭记住密码会同时关闭自动登录() async throws {
        let suiteName = "ConnectionFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let profileStore = NasProfileStore(defaults: defaults)
        let model = AppModel(
            profileStore: profileStore,
            authRepository: RecordingAuthRepository(),
            passwordStore: MemoryPasswordStore()
        )
        model.host = "home-nas.local"
        model.account = "user"
        model.password = "local-test-password"
        model.setAutoLoginEnabled(true)
        await model.connect()
        let profileID = try XCTUnwrap(model.selectedProfileID)

        model.setRememberPassword(false)

        XCTAssertFalse(model.rememberPassword)
        XCTAssertFalse(model.autoLoginEnabled)
        XCTAssertFalse(profileStore.isAutoLoginEnabled(for: profileID))
    }

    @MainActor
    func test登录后仍可进入新增NAS表单且保留已有配置() async {
        let suiteName = "ConnectionFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            profileStore: NasProfileStore(defaults: defaults),
            authRepository: RecordingAuthRepository()
        )
        model.displayName = "家庭 NAS"
        model.host = "home-nas.local"
        model.account = "user"
        model.password = "password"
        await model.connect()

        XCTAssertNotNil(model.workspace)
        XCTAssertEqual(model.profiles.count, 1)

        model.newProfile()

        XCTAssertNil(model.workspace)
        XCTAssertNil(model.selectedProfileID)
        XCTAssertEqual(model.profiles.count, 1)
        XCTAssertEqual(model.displayName, "我的 NAS")
        XCTAssertTrue(model.host.isEmpty)
        XCTAssertTrue(model.account.isEmpty)
    }

    @MainActor
    func test登录多台NAS后可以从工作区切换配置() async throws {
        let suiteName = "ConnectionFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            profileStore: NasProfileStore(defaults: defaults),
            authRepository: RecordingAuthRepository()
        )
        model.displayName = "家庭 NAS"
        model.host = "home-nas.local"
        model.account = "home-user"
        model.password = "password"
        await model.connect()
        let firstProfileID = try XCTUnwrap(model.selectedProfileID)
        let firstWorkspace = try XCTUnwrap(model.workspace)

        model.newProfile()
        model.displayName = "办公室 NAS"
        model.host = "office-nas.local"
        model.account = "office-user"
        model.password = "password"
        await model.connect()

        XCTAssertEqual(model.profiles.count, 2)
        XCTAssertNotNil(model.workspace)

        model.selectProfile(id: firstProfileID)

        XCTAssertTrue(model.workspace === firstWorkspace)
        XCTAssertEqual(model.selectedProfileID, firstProfileID)
        XCTAssertEqual(model.displayName, "家庭 NAS")
        XCTAssertEqual(model.host, "home-nas.local")
        XCTAssertEqual(model.account, "home-user")
    }

    @MainActor
    func test无法自动验证证书时显示核对界面并保留本次密码() async {
        let suiteName = "ConnectionFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel(
            profileStore: NasProfileStore(defaults: defaults),
            authRepository: CertificateReviewAuthRepository()
        )
        model.host = "nas.local"
        model.account = "user"
        model.password = "password"

        await model.connect()

        XCTAssertNotNil(model.pendingCertificate)
        XCTAssertEqual(model.password, "password")
        XCTAssertTrue(model.statusIsError)
        XCTAssertEqual(model.statusMessage, "无法自动确认这台 NAS 的身份，请核对安全信息后继续。")
    }

    @MainActor
    func testQuickConnectID解析后用于登录但界面保留原始ID() async {
        let suiteName = "ConnectionFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let resolver = RecordingQuickConnectResolver()
        let repository = RecordingAuthRepository()
        let model = AppModel(
            profileStore: NasProfileStore(defaults: defaults),
            authRepository: repository,
            quickConnectResolver: resolver
        )
        model.host = "family-nas"
        model.account = "user"
        model.password = "password"

        await model.connect()

        let requestedID = await resolver.requestedID
        let discoveredHost = await repository.discoveredHost
        let loginHost = await repository.loginHost
        XCTAssertEqual(requestedID, "family-nas")
        XCTAssertEqual(discoveredHost, "192-168-1-20.family-nas.direct.quickconnect.to")
        XCTAssertEqual(loginHost, "192-168-1-20.family-nas.direct.quickconnect.to")
        XCTAssertEqual(model.host, "family-nas")
        XCTAssertEqual(model.workspace?.profile.host, "family-nas")
        XCTAssertEqual(model.currentConnectionRoute, .local)
    }

    @MainActor
    func test局域网候选失败后尝试公网直连且不向错误候选发送密码() async {
        let suiteName = "ConnectionFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let localHost = "192-168-1-20.family-nas.direct.quickconnect.to"
        let externalHost = "family-nas.direct.quickconnect.to"
        let resolver = RecordingQuickConnectResolver(
            endpoints: [
                QuickConnectEndpoint(host: localHost, port: 5_001, kind: .local),
                QuickConnectEndpoint(host: externalHost, port: 5_001, kind: .external)
            ]
        )
        let repository = RecordingAuthRepository(failingHosts: [localHost])
        let model = AppModel(
            profileStore: NasProfileStore(defaults: defaults),
            authRepository: repository,
            quickConnectResolver: resolver
        )
        model.host = "family-nas"
        model.account = "user"
        model.password = "password"

        await model.connect()

        let discoveredHosts = await repository.discoveredHosts
        let loginHost = await repository.loginHost
        XCTAssertEqual(discoveredHosts, [localHost, externalHost])
        XCTAssertEqual(loginHost, externalHost)
        XCTAssertNotNil(model.workspace)
        XCTAssertEqual(model.currentConnectionRoute, .external)
    }

    @MainActor
    func test自定义端口覆盖QuickConnect返回端口() async {
        let suiteName = "ConnectionFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let resolver = RecordingQuickConnectResolver()
        let repository = RecordingAuthRepository()
        let model = AppModel(
            profileStore: NasProfileStore(defaults: defaults),
            authRepository: repository,
            quickConnectResolver: resolver
        )
        model.host = "family-nas"
        model.port = "5443"
        model.account = "user"
        model.password = "password"

        await model.connect()

        let loginPort = await repository.loginPort
        XCTAssertEqual(loginPort, 5_443)
        XCTAssertEqual(model.profiles.first?.portOverride, 5_443)
    }

    @MainActor
    func test所有直连候选失败后建立中继再登录() async {
        let suiteName = "ConnectionFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let localHost = "192-168-1-20.family-nas.direct.quickconnect.to"
        let externalHost = "family-nas.direct.quickconnect.to"
        let relayHost = "family-nas.r1.quickconnect.to"
        let resolver = RecordingQuickConnectResolver(
            endpoints: [
                QuickConnectEndpoint(host: localHost, port: 5_001, kind: .local),
                QuickConnectEndpoint(host: externalHost, port: 5_001, kind: .external)
            ],
            relayEndpoint: QuickConnectEndpoint(host: relayHost, port: 443, kind: .relay)
        )
        let repository = RecordingAuthRepository(failingHosts: [localHost, externalHost])
        let model = AppModel(
            profileStore: NasProfileStore(defaults: defaults),
            authRepository: repository,
            quickConnectResolver: resolver
        )
        model.host = "family-nas"
        model.account = "user"
        model.password = "password"

        await model.connect()

        let relayRequestCount = await resolver.relayRequestCount
        let discoveredHosts = await repository.discoveredHosts
        let loginHost = await repository.loginHost
        let loginPort = await repository.loginPort
        XCTAssertEqual(relayRequestCount, 1)
        XCTAssertEqual(discoveredHosts, [localHost, externalHost, relayHost])
        XCTAssertEqual(loginHost, relayHost)
        XCTAssertEqual(loginPort, 443)
        XCTAssertNotNil(model.workspace)
        XCTAssertEqual(model.currentConnectionRoute, .quickConnect)
    }

    @MainActor
    func test没有直连候选时直接建立中继() async {
        let suiteName = "ConnectionFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let relayHost = "family-nas.r1.quickconnect.to"
        let resolver = RecordingQuickConnectResolver(
            endpoints: [],
            relayEndpoint: QuickConnectEndpoint(host: relayHost, port: 443, kind: .relay),
            resolutionError: .noDirectRoute
        )
        let repository = RecordingAuthRepository()
        let model = AppModel(
            profileStore: NasProfileStore(defaults: defaults),
            authRepository: repository,
            quickConnectResolver: resolver
        )
        model.host = "family-nas"
        model.account = "user"
        model.password = "password"

        await model.connect()

        let relayRequestCount = await resolver.relayRequestCount
        let discoveredHosts = await repository.discoveredHosts
        let loginHost = await repository.loginHost
        XCTAssertEqual(relayRequestCount, 1)
        XCTAssertEqual(discoveredHosts, [relayHost])
        XCTAssertEqual(loginHost, relayHost)
        XCTAssertNotNil(model.workspace)
        XCTAssertEqual(model.currentConnectionRoute, .quickConnect)
    }

    @MainActor
    func test文件会话失效时返回登录页但不执行远程退出() async {
        let suiteName = "ConnectionFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let resolver = RecordingQuickConnectResolver()
        let repository = RecordingAuthRepository()
        let model = AppModel(
            profileStore: NasProfileStore(defaults: defaults),
            authRepository: repository,
            quickConnectResolver: resolver
        )
        model.host = "family-nas"
        model.account = "user"
        model.password = "password"
        await model.connect()

        await model.returnToLoginAfterSessionIssue(message: "登录状态已失效，请重新登录。")

        let clearCount = await repository.clearSessionCallCount
        let logoutCount = await repository.logoutCallCount
        XCTAssertNil(model.workspace)
        XCTAssertTrue(model.statusIsError)
        XCTAssertEqual(model.statusMessage, "登录状态已失效，请重新登录。")
        XCTAssertEqual(clearCount, 1)
        XCTAssertEqual(logoutCount, 0)
    }
}
