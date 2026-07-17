import XCTest
@testable import DsmCore

final class NasAddressTests: XCTestCase {
    func test识别QuickConnectID() throws {
        let address = try NasAddressParser.parse("family-nas", defaultPort: 5_001)

        XCTAssertEqual(address.host, "family-nas")
        XCTAssertEqual(address.port, 5_001)
        XCTAssertEqual(address.kind, .quickConnect)
        XCTAssertFalse(address.hasExplicitPort)
    }

    func test识别IP和本地域名() throws {
        XCTAssertEqual(
            try NasAddressParser.parse("192.168.1.20", defaultPort: 5_001).kind,
            .direct
        )
        XCTAssertEqual(
            try NasAddressParser.parse("diskstation.local", defaultPort: 5_001).kind,
            .direct
        )
    }

    func test粘贴浏览器完整地址时提取主机和端口() throws {
        let address = try NasAddressParser.parse(
            "https://192-168-1-20.family-nas.direct.quickconnect.to:5443/#/signin",
            defaultPort: 5_001
        )

        XCTAssertEqual(address.host, "192-168-1-20.family-nas.direct.quickconnect.to")
        XCTAssertEqual(address.port, 5_443)
        XCTAssertEqual(address.kind, .direct)
        XCTAssertTrue(address.hasExplicitPort)
    }

    func test完整HTTPS地址未指定端口时使用标准端口() throws {
        let address = try NasAddressParser.parse(
            "https://nas.example.invalid/webman/index.cgi",
            defaultPort: 5_001
        )

        XCTAssertEqual(address.port, 443)
        XCTAssertFalse(address.hasExplicitPort)
        XCTAssertEqual(address.kind, .direct)
    }

    func test识别QuickConnect官方入口地址() throws {
        let address = try NasAddressParser.parse(
            "https://quickconnect.to/family-nas",
            defaultPort: 5_001
        )

        XCTAssertEqual(address.host, "family-nas")
        XCTAssertEqual(address.kind, .quickConnect)
    }

    func test拒绝普通HTTP直连地址() {
        XCTAssertThrowsError(
            try NasAddressParser.parse("http://nas.example.com:5000", defaultPort: 5_001)
        ) { error in
            XCTAssertEqual(error as? NasAddressInputError, .insecure)
        }
    }
}
