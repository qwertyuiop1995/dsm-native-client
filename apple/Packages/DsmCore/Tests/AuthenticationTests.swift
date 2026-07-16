import Foundation
import XCTest
@testable import DsmCore

final class AuthenticationTests: XCTestCase {
    func test旧会话解码为旧传输版本() throws {
        let data = Data(
            #"{"sid":"REDACTED_SESSION","synoToken":null,"did":null,"isPortalPort":false}"#.utf8
        )

        let session = try JSONDecoder().decode(AuthSession.self, from: data)

        XCTAssertEqual(session.transportVersion, 1)
    }

    func test新会话记录当前传输版本() throws {
        let session = AuthSession(
            sid: "REDACTED_SESSION",
            synoToken: "REDACTED_TOKEN",
            did: nil,
            isPortalPort: false
        )

        let decoded = try JSONDecoder().decode(
            AuthSession.self,
            from: JSONEncoder().encode(session)
        )

        XCTAssertEqual(decoded.transportVersion, AuthSession.currentTransportVersion)
    }
}
