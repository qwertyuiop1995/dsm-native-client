import DsmCore
import Foundation

public actor DsmAuthRepository: AuthRepository {
    private let sessionStore: any SessionSecureStoring
    private let transportFactory: @Sendable (NasProfile) -> any DsmHTTPTransport

    public init(
        sessionStore: any SessionSecureStoring = KeychainSessionStore(),
        transportFactory: @escaping @Sendable (NasProfile) -> any DsmHTTPTransport = { profile in
            URLSessionTransport(
                expectedHost: profile.host,
                pinnedCertificateSHA256: profile.pinnedCertificateSHA256
            )
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
                safeUserMessage: "这台 NAS 暂时无法使用岚仓登录，请确认 DSM 和 File Station 已启用并更新。"
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
                safeUserMessage: "无法在这台 Mac 上保存登录状态。"
            )
        }
        return session
    }

    public func restoreSession(for profileID: UUID) async throws -> AuthSession? {
        do {
            guard let session = try await sessionStore.load(for: profileID) else {
                return nil
            }
            guard session.transportVersion >= AuthSession.currentTransportVersion else {
                try await sessionStore.remove(for: profileID)
                return nil
            }
            return session
        } catch {
            throw AppError(
                category: .authenticationRequired,
                isRetryable: false,
                safeUserMessage: "无法读取已保存的登录状态，请重新登录。"
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
                safeUserMessage: "无法删除这台 Mac 上保存的登录状态。"
            )
        }
    }

    public func logout(
        profile: NasProfile,
        capabilities: CapabilitySet,
        session: AuthSession
    ) async throws {
        var remoteError: Error?
        if let capability = capabilities[DsmAPIName.authentication] {
            do {
                let client = try makeClient(for: profile)
                try await DsmAuthenticationService(client: client).logout(
                    capability: capability,
                    session: session
                )
            } catch {
                remoteError = error
            }
        }

        try await clearSession(for: profile.id)
        if let remoteError {
            throw remoteError
        }
    }

    private func makeClient(for profile: NasProfile) throws -> DsmAPIClient {
        do {
            return DsmAPIClient(
                baseURL: try DsmEndpoint.baseURL(for: profile),
                transport: transportFactory(profile)
            )
        } catch {
            throw AppError(
                category: .invalidResponse,
                isRetryable: false,
                safeUserMessage: "NAS 地址或端口不正确，请检查后重试。"
            )
        }
    }
}
