import DsmCore
import DsmNetwork
import Foundation
import XCTest
@testable import DsmMacExecutable

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

    func resolve(id: String) async throws -> QuickConnectEndpoint {
        requestedID = id
        return QuickConnectEndpoint(
            host: "192-168-1-20.family-nas.direct.quickconnect.to",
            port: 5_001
        )
    }
}

private actor RecordingAuthRepository: AuthRepository {
    private(set) var discoveredHost: String?
    private(set) var loginHost: String?
    private(set) var clearSessionCallCount = 0
    private(set) var logoutCallCount = 0

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

final class ConnectionFlowTests: XCTestCase {
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
