import DsmCore
import Foundation
import DsmLocalization

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
                safeUserMessage: L10n.string("shared.ab67a889a268fb00")
            )
        }
        guard !account.isEmpty, !password.isEmpty else {
            throw AppError(
                category: .authenticationRequired,
                isRetryable: false,
                safeUserMessage: L10n.string("shared.53f82a3866fbda42")
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
                    safeUserMessage: L10n.string("shared.613c9aebd1cc383d")
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
                safeUserMessage: L10n.string("shared.6ee080ac607b50db")
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
