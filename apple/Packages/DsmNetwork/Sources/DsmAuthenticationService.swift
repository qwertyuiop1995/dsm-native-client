import DsmCore
import Foundation

private struct LoginPayload: Decodable, Sendable {
    let sid: String
    let synoToken: String?
    let did: String?
    let isPortalPort: Bool

    private enum CodingKeys: String, CodingKey {
        case sid
        case synoToken = "synotoken"
        case did
        case isPortalPort = "is_portal_port"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sid = try container.decode(String.self, forKey: .sid)
        synoToken = try container.decodeIfPresent(String.self, forKey: .synoToken)
        did = try container.decodeIfPresent(String.self, forKey: .did)

        if let value = try? container.decode(Bool.self, forKey: .isPortalPort) {
            isPortalPort = value
        } else if let value = try? container.decode(Int.self, forKey: .isPortalPort) {
            isPortalPort = value != 0
        } else if let value = try? container.decode(String.self, forKey: .isPortalPort) {
            isPortalPort = value == "1" || value.lowercased() == "true"
        } else {
            isPortalPort = false
        }
    }
}

public struct DsmAuthenticationService: Sendable {
    private let client: DsmAPIClient

    public init(client: DsmAPIClient) {
        self.client = client
    }

    public func login(
        capability: ApiCapability,
        account: String,
        password: String,
        otpCode: String?
    ) async throws -> AuthSession {
        guard capability.name == DsmAPIName.authentication,
              let selectedVersion = capability.selectedVersion else {
            throw AppError(
                category: .versionUnsupported,
                isRetryable: false,
                safeUserMessage: "这台 NAS 的登录功能暂不受支持，请更新 DSM 后重试。"
            )
        }
        guard !account.isEmpty, !password.isEmpty else {
            throw AppError(
                category: .authenticationRequired,
                isRetryable: false,
                safeUserMessage: "请输入用户名和密码。"
            )
        }

        var parameters: [String: DsmParameterValue] = [
            "account": .string(account),
            "passwd": .string(password),
            "session": .string("FileStation"),
            "format": .string("sid")
        ]
        if selectedVersion >= 6 {
            parameters["enable_syno_token"] = .string("yes")
        }
        let normalizedOTP = otpCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedOTP, !normalizedOTP.isEmpty {
            parameters["otp_code"] = .string(normalizedOTP)
        }

        do {
            let payload = try await client.call(
                path: capability.path,
                api: capability.name,
                version: selectedVersion,
                method: "login",
                requestFormat: capability.requestFormat,
                parameters: parameters,
                as: LoginPayload.self
            )
            guard !payload.sid.isEmpty else {
                throw AppError(
                    category: .invalidResponse,
                    isRetryable: false,
                    safeUserMessage: "登录失败，NAS 返回的信息不完整。"
                )
            }
            return AuthSession(
                sid: payload.sid,
                synoToken: payload.synoToken,
                did: payload.did,
                isPortalPort: payload.isPortalPort
            )
        } catch let error as DsmNetworkError {
            throw DsmErrorMapper.map(
                error,
                context: .authentication(otpWasSubmitted: normalizedOTP?.isEmpty == false)
            )
        }
    }

    public func logout(
        capability: ApiCapability,
        session: AuthSession
    ) async throws {
        guard capability.name == DsmAPIName.authentication,
              let selectedVersion = capability.selectedVersion else {
            throw AppError(
                category: .versionUnsupported,
                isRetryable: false,
                safeUserMessage: "无法通知 NAS 退出登录，但本机登录信息仍会被删除。"
            )
        }

        do {
            try await client.callVoid(
                path: capability.path,
                api: capability.name,
                version: selectedVersion,
                method: "logout",
                requestFormat: capability.requestFormat,
                parameters: ["session": .string("FileStation")],
                credential: DsmSessionCredential(
                    sid: session.sid,
                    synoToken: session.synoToken
                )
            )
        } catch let error as DsmNetworkError {
            throw DsmErrorMapper.map(error, context: .authentication(otpWasSubmitted: false))
        }
    }
}
