import DsmCore
import Foundation

public actor DsmAuthRepository: AuthRepository {
    private let sessionStore: any SessionSecureStoring
    private let transportFactory: @Sendable () -> any DsmHTTPTransport

    public init(
        sessionStore: any SessionSecureStoring = KeychainSessionStore(),
        transportFactory: @escaping @Sendable () -> any DsmHTTPTransport = {
            URLSessionTransport()
        }
    ) {
        self.sessionStore = sessionStore
        self.transportFactory = transportFactory
    }

    public func discover(profile: NasProfile) async throws -> CapabilitySet {
        let client = try makeClient(for: profile)
        return try await DsmCapabilityDiscovery(client: client).discover()
    }

    public func login(
        profile: NasProfile,
        capabilities: CapabilitySet,
        account: String,
        password: String,
        otpCode: String?
    ) async throws -> AuthSession {
        guard let capability = capabilities[DsmAPIName.authentication] else {
            throw AppError(
                category: .apiUnavailable,
                isRetryable: false,
                safeUserMessage: "此 DSM 没有发现登录 API。"
            )
        }

        let client = try makeClient(for: profile)
        let session = try await DsmAuthenticationService(client: client).login(
            capability: capability,
            account: account,
            password: password,
            otpCode: otpCode
        )

        do {
            try await sessionStore.save(session, for: profile.id)
        } catch {
            throw AppError(
                category: .unknown,
                isRetryable: false,
                safeUserMessage: "无法将会话安全保存到钥匙串。"
            )
        }
        return session
    }

    public func restoreSession(for profileID: UUID) async throws -> AuthSession? {
        do {
            return try await sessionStore.load(for: profileID)
        } catch {
            throw AppError(
                category: .authenticationRequired,
                isRetryable: false,
                safeUserMessage: "无法从钥匙串恢复 DSM 会话。"
            )
        }
    }

    public func clearSession(for profileID: UUID) async throws {
        do {
            try await sessionStore.remove(for: profileID)
        } catch {
            throw AppError(
                category: .unknown,
                isRetryable: false,
                safeUserMessage: "无法清理钥匙串中的 DSM 会话。"
            )
        }
    }

    private func makeClient(for profile: NasProfile) throws -> DsmAPIClient {
        do {
            return DsmAPIClient(
                baseURL: try DsmEndpoint.baseURL(for: profile),
                transport: transportFactory()
            )
        } catch {
            throw AppError(
                category: .invalidResponse,
                isRetryable: false,
                safeUserMessage: "NAS 连接地址无效。"
            )
        }
    }
}
