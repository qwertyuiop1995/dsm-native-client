import DsmCore
import DsmNetwork
@testable import DsmMobile
import XCTest

private actor MobileTestSessionStore: SessionSecureStoring {
    private let storedSession: AuthSession?

    init(storedSession: AuthSession? = nil) {
        self.storedSession = storedSession
    }

    func save(_ session: AuthSession, for profileID: UUID) async throws {}
    func load(for profileID: UUID) async throws -> AuthSession? { storedSession }
    func remove(for profileID: UUID) async throws {}
}

private actor MobileTestPasswordStore: PasswordSecureStoring {
    private var passwords: [UUID: String] = [:]

    func save(_ password: String, for profileID: UUID) async throws {
        passwords[profileID] = password
    }

    func load(for profileID: UUID) async throws -> String? {
        passwords[profileID]
    }

    func remove(for profileID: UUID) async throws {
        passwords.removeValue(forKey: profileID)
    }
}

private actor MobileRecordingAuthRepository: AuthRepository {
    private(set) var discoveredHost: String?
    private(set) var loginHost: String?

    func discover(profile: NasProfile) async throws -> CapabilitySet {
        discoveredHost = profile.host
        return CapabilitySet([:])
    }

    func login(
        profile: NasProfile,
        capabilities: CapabilitySet,
        account: String,
        password: String,
        otpCode: String?
    ) async throws -> AuthSession {
        loginHost = profile.host
        return AuthSession(
            sid: "mobile-test-session",
            synoToken: nil,
            did: nil,
            isPortalPort: false
        )
    }

    func restoreSession(for profileID: UUID) async throws -> AuthSession? { nil }
    func clearSession(for profileID: UUID) async throws {}
    func logout(
        profile: NasProfile,
        capabilities: CapabilitySet,
        session: AuthSession
    ) async throws {}
}

private actor MobileQuickConnectResolver: QuickConnectResolving {
    private(set) var requestedID: String?

    func resolve(id: String) async throws -> [QuickConnectEndpoint] {
        requestedID = id
        return [
            QuickConnectEndpoint(
                host: "192-168-1-20.mobile-test.direct.quickconnect.to",
                port: 5_001,
                kind: .local
            )
        ]
    }

    func requestRelay(id: String) async throws -> QuickConnectEndpoint {
        QuickConnectEndpoint(
            host: "mobile-test.r1.quickconnect.to",
            port: 443,
            kind: .relay
        )
    }
}

final class MobileModuleTests: XCTestCase {
    func test所有Mac主导航模块均有移动端入口() {
        XCTAssertEqual(
            Set(MobileModule.allCases.map(\.rawValue)),
            Set([
                "files",
                "photos",
                "chat",
                "downloads",
                "containers",
                "virtualMachines",
                "nasSettings",
                "transfers",
                "settings"
            ])
        )
    }

    func test模块标题均面向普通用户() {
        XCTAssertTrue(MobileModule.allCases.allSatisfy { !$0.title.isEmpty })
        XCTAssertFalse(MobileModule.allCases.contains { $0.title.contains("API") })
    }

    @MainActor
    func testQuickConnect登录使用解析地址并保留原始ID() async throws {
        let suiteName = "MobileModuleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = MobileRecordingAuthRepository()
        let resolver = MobileQuickConnectResolver()
        let passwordStore = MobileTestPasswordStore()
        let model = MobileAppModel(
            defaults: defaults,
            sessionStore: MobileTestSessionStore(),
            passwordStore: passwordStore,
            authRepository: repository,
            quickConnectResolver: resolver
        )
        model.host = "mobile-test"
        model.username = "tester"
        model.password = "password"

        model.connect()
        for _ in 0..<100 where model.isConnecting {
            try await Task.sleep(for: .milliseconds(20))
        }

        let requestedID = await resolver.requestedID
        let discoveredHost = await repository.discoveredHost
        let loginHost = await repository.loginHost
        XCTAssertEqual(requestedID, "mobile-test")
        XCTAssertEqual(
            discoveredHost,
            "192-168-1-20.mobile-test.direct.quickconnect.to"
        )
        XCTAssertEqual(
            loginHost,
            "192-168-1-20.mobile-test.direct.quickconnect.to"
        )
        XCTAssertEqual(model.host, "mobile-test")
        XCTAssertEqual(model.activeProfile?.host, "mobile-test")
        XCTAssertTrue(model.isConnected)
    }

    @MainActor
    func testQuickConnect保存会话恢复时重新解析地址() async throws {
        let suiteName = "MobileModuleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = MobileRecordingAuthRepository()
        let resolver = MobileQuickConnectResolver()
        let passwordStore = MobileTestPasswordStore()
        let storedSession = AuthSession(
            sid: "mobile-restored-session",
            synoToken: nil,
            did: nil,
            isPortalPort: false
        )
        let model = MobileAppModel(
            defaults: defaults,
            sessionStore: MobileTestSessionStore(storedSession: storedSession),
            passwordStore: passwordStore,
            authRepository: repository,
            quickConnectResolver: resolver
        )
        let profile = try NasProfile(
            displayName: "移动端恢复测试",
            host: "mobile-test",
            port: 5_001
        )

        model.restore(profile)
        for _ in 0..<100 where model.isConnecting {
            try await Task.sleep(for: .milliseconds(20))
        }

        let requestedID = await resolver.requestedID
        let discoveredHost = await repository.discoveredHost
        XCTAssertEqual(requestedID, "mobile-test")
        XCTAssertEqual(
            discoveredHost,
            "192-168-1-20.mobile-test.direct.quickconnect.to"
        )
    }

    @MainActor
    func test冷启动恢复配置密码并自动登录() async throws {
        let suiteName = "MobileModuleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let passwordStore = MobileTestPasswordStore()

        let firstModel = MobileAppModel(
            defaults: defaults,
            sessionStore: MobileTestSessionStore(),
            passwordStore: passwordStore,
            authRepository: MobileRecordingAuthRepository(),
            quickConnectResolver: MobileQuickConnectResolver()
        )
        firstModel.displayName = "冷启动测试"
        firstModel.host = "mobile-test"
        firstModel.username = "tester"
        firstModel.password = "saved-password"
        firstModel.rememberPassword = true
        firstModel.autoLoginEnabled = true
        firstModel.connect()
        for _ in 0..<100 where firstModel.isConnecting {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(firstModel.isConnected)

        let restartedRepository = MobileRecordingAuthRepository()
        let restartedModel = MobileAppModel(
            defaults: defaults,
            sessionStore: MobileTestSessionStore(),
            passwordStore: passwordStore,
            authRepository: restartedRepository,
            quickConnectResolver: MobileQuickConnectResolver()
        )
        for _ in 0..<150 where !restartedModel.isConnected {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(restartedModel.displayName, "冷启动测试")
        XCTAssertEqual(restartedModel.host, "mobile-test")
        XCTAssertEqual(restartedModel.username, "tester")
        XCTAssertEqual(restartedModel.password, "saved-password")
        XCTAssertTrue(restartedModel.rememberPassword)
        XCTAssertTrue(restartedModel.autoLoginEnabled)
        XCTAssertTrue(restartedModel.isConnected)
        let restartedLoginHost = await restartedRepository.loginHost
        XCTAssertEqual(
            restartedLoginHost,
            "192-168-1-20.mobile-test.direct.quickconnect.to"
        )

        restartedModel.logout()
        let signedOutModel = MobileAppModel(
            defaults: defaults,
            sessionStore: MobileTestSessionStore(),
            passwordStore: passwordStore,
            authRepository: MobileRecordingAuthRepository(),
            quickConnectResolver: MobileQuickConnectResolver()
        )
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(signedOutModel.isConnected)
        XCTAssertFalse(signedOutModel.autoLoginEnabled)
        XCTAssertTrue(signedOutModel.rememberPassword)
        XCTAssertEqual(signedOutModel.password, "saved-password")
    }
}
