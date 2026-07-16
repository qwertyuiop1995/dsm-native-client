import XCTest
@testable import DsmCore

final class ApiCapabilityTests: XCTestCase {
    func test选择客户端与服务器共同支持的最高版本() throws {
        let capability = ApiCapability(
            name: "SYNO.API.Auth",
            path: "entry.cgi",
            minVersion: 3,
            maxVersion: 7,
            requestFormat: .form
        )

        let selected = try capability.selectingVersion(in: 3...6)

        XCTAssertEqual(selected.selectedVersion, 6)
    }

    func test没有重叠版本时拒绝选择() {
        let capability = ApiCapability(
            name: "SYNO.API.Auth",
            path: "entry.cgi",
            minVersion: 7,
            maxVersion: 7,
            requestFormat: .form
        )

        XCTAssertThrowsError(try capability.selectingVersion(in: 3...6))
    }
}
