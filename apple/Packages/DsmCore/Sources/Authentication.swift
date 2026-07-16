import Foundation

public struct AuthSession: Codable, Equatable, Sendable {
    public let sid: String
    public let synoToken: String?
    public let did: String?
    public let isPortalPort: Bool

    public init(
        sid: String,
        synoToken: String?,
        did: String?,
        isPortalPort: Bool
    ) {
        self.sid = sid
        self.synoToken = synoToken
        self.did = did
        self.isPortalPort = isPortalPort
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
}
