import XCTest
@testable import DsmCore

final class NasProfileTests: XCTestCase {
    func test规范化显示名称和主机() throws {
        let profile = try NasProfile(
            displayName: "  测试设备  ",
            host: "  nas.example.invalid  ",
            port: 5_001
        )

        XCTAssertEqual(profile.displayName, "测试设备")
        XCTAssertEqual(profile.host, "nas.example.invalid")
        XCTAssertEqual(profile.scheme, .https)
    }

    func test拒绝包含协议或路径的主机() {
        XCTAssertThrowsError(
            try NasProfile(
                displayName: "测试设备",
                host: "https://nas.example.invalid/path",
                port: 5_001
            )
        )
    }
}
