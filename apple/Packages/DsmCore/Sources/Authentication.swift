import Foundation

public struct AuthSession: Codable, Equatable, Sendable {
    public static let currentTransportVersion = 2

    public let sid: String
    public let synoToken: String?
    public let did: String?
    public let isPortalPort: Bool
    public let transportVersion: Int

    public init(
        sid: String,
        synoToken: String?,
        did: String?,
        isPortalPort: Bool,
        transportVersion: Int = AuthSession.currentTransportVersion
    ) {
        self.sid = sid
        self.synoToken = synoToken
        self.did = did
        self.isPortalPort = isPortalPort
        self.transportVersion = transportVersion
    }

    private enum CodingKeys: String, CodingKey {
        case sid
        case synoToken
        case did
        case isPortalPort
        case transportVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sid = try container.decode(String.self, forKey: .sid)
        synoToken = try container.decodeIfPresent(String.self, forKey: .synoToken)
        did = try container.decodeIfPresent(String.self, forKey: .did)
        isPortalPort = try container.decode(Bool.self, forKey: .isPortalPort)
        transportVersion = try container.decodeIfPresent(Int.self, forKey: .transportVersion) ?? 1
    }
}

public protocol SessionSecureStoring: Sendable {
    func save(_ session: AuthSession, for profileID: UUID) async throws
    func load(for profileID: UUID) async throws -> AuthSession?
    func remove(for profileID: UUID) async throws
}

public protocol AuthRepository: Sendable {
    func discover(profile: NasProfile) async throws -> CapabilitySet

    func login(
        profile: NasProfile,
        capabilities: CapabilitySet,
        account: String,
        password: String,
        otpCode: String?
    ) async throws -> AuthSession

    func restoreSession(for profileID: UUID) async throws -> AuthSession?
    func clearSession(for profileID: UUID) async throws
    func logout(
        profile: NasProfile,
        capabilities: CapabilitySet,
        session: AuthSession
    ) async throws
}
