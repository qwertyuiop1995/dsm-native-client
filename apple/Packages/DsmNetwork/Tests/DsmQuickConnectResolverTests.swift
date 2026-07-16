import Foundation
import XCTest
@testable import DsmNetwork

final class DsmQuickConnectResolverTests: XCTestCase {
    func test优先选择局域网直连地址() throws {
        let data = Data(
            """
            [{
              "errno": 0,
              "server": {"ds_state": "CONNECTED"},
              "service": {"port": 5001},
              "smartdns": {
                "host": "family-nas.direct.quickconnect.to",
                "lan": ["192-168-1-20.family-nas.direct.quickconnect.to"]
              }
            }]
            """.utf8
        )

        let endpoint = try DsmQuickConnectResolver.decodeEndpoint(from: data)

        XCTAssertEqual(endpoint.host, "192-168-1-20.family-nas.direct.quickconnect.to")
        XCTAssertEqual(endpoint.port, 5_001)
    }

    func test没有局域网地址时使用QuickConnect直连域名() throws {
        let data = Data(
            """
            [{
              "errno": 0,
              "server": {"ds_state": "CONNECTED"},
              "service": {"port": 5001},
              "smartdns": {"host": "family-nas.direct.quickconnect.cn", "lan": []}
            }]
            """.utf8
        )

        let endpoint = try DsmQuickConnectResolver.decodeEndpoint(from: data)

        XCTAssertEqual(endpoint.host, "family-nas.direct.quickconnect.cn")
    }

    func test拒绝QuickConnect域名之外的返回地址() {
        let data = Data(
            """
            [{
              "errno": 0,
              "server": {"ds_state": "CONNECTED"},
              "service": {"port": 5001},
              "smartdns": {"host": "untrusted.example.com", "lan": []}
            }]
            """.utf8
        )

        XCTAssertThrowsError(try DsmQuickConnectResolver.decodeEndpoint(from: data)) { error in
            XCTAssertEqual(error as? QuickConnectResolutionError, .noDirectRoute)
        }
    }

    func test离线设备给出明确错误() {
        let data = Data(
            """
            [{
              "errno": 0,
              "server": {"ds_state": "DISCONNECTED"},
              "service": {"port": 5001},
              "smartdns": {"host": "family-nas.direct.quickconnect.to", "lan": []}
            }]
            """.utf8
        )

        XCTAssertThrowsError(try DsmQuickConnectResolver.decodeEndpoint(from: data)) { error in
            XCTAssertEqual(error as? QuickConnectResolutionError, .offline)
        }
    }
}
