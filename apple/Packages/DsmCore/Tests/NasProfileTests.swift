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

    func test规范化证书指纹() throws {
        let profile = try NasProfile(
            displayName: "测试设备",
            host: "nas.example.invalid",
            port: 5_001,
            pinnedCertificateSHA256: "aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa:aa"
        )

        XCTAssertEqual(profile.pinnedCertificateSHA256, String(repeating: "AA", count: 32))
    }

    func test保留用户自定义端口() throws {
        let profile = try NasProfile(
            displayName: "测试设备",
            host: "nas.example.invalid",
            port: 5_443,
            portOverride: 5_443
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(NasProfile.self, from: data)

        XCTAssertEqual(decoded.port, 5_443)
        XCTAssertEqual(decoded.portOverride, 5_443)
    }

    func test旧配置的默认端口迁移为自动选择() throws {
        let id = UUID()
        let data = Data(
            """
            {
              "id": "\(id.uuidString)",
              "displayName": "旧设备",
              "scheme": "https",
              "host": "nas.example.invalid",
              "port": 5001
            }
            """.utf8
        )

        let profile = try JSONDecoder().decode(NasProfile.self, from: data)

        XCTAssertNil(profile.portOverride)
    }

    func test自动HTTPS端口重新加载后仍保持自动() throws {
        let profile = try NasProfile(
            displayName: "测试设备",
            host: "nas.example.invalid",
            port: 443,
            portOverride: nil
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(NasProfile.self, from: data)

        XCTAssertEqual(decoded.port, 443)
        XCTAssertNil(decoded.portOverride)
    }
}
