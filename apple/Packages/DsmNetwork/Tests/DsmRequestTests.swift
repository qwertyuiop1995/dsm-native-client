import DsmCore
import Foundation
import XCTest
@testable import DsmNetwork

final class DsmRequestTests: XCTestCase {
    func test表单编码特殊字符且凭据不进入URL() throws {
        let request = try DsmRequestBuilder.build(
            baseURL: try XCTUnwrap(URL(string: "https://nas.example.invalid:5001")),
            path: "entry.cgi",
            api: "SYNO.API.Auth",
            version: 6,
            method: "login",
            requestFormat: .form,
            parameters: ["account": .string("中文 #+&=\"😀")],
            credential: DsmSessionCredential(
                sid: "<REDACTED_SESSION>",
                synoToken: "<REDACTED_SESSION>"
            )
        )

        XCTAssertNil(request.url?.query)
        let fields = try decodeForm(request.httpBody)
        XCTAssertEqual(fields["account"], "中文 #+&=\"😀")
        XCTAssertEqual(fields["_sid"], "<REDACTED_SESSION>")
        XCTAssertEqual(fields["SynoToken"], "<REDACTED_SESSION>")
    }

    func testJSON请求格式编码字符串和布尔值() throws {
        let request = try DsmRequestBuilder.build(
            baseURL: try XCTUnwrap(URL(string: "https://nas.example.invalid:5001")),
            path: "entry.cgi",
            api: "SYNO.Example",
            version: 1,
            method: "get",
            requestFormat: .json,
            parameters: [
                "path": .string("/测试目录"),
                "overwrite": .boolean(false)
            ]
        )

        let fields = try decodeForm(request.httpBody)
        let encodedPath = try XCTUnwrap(fields["path"]?.data(using: .utf8))
        XCTAssertEqual(try JSONDecoder().decode(String.self, from: encodedPath), "/测试目录")
        XCTAssertEqual(fields["overwrite"], "false")
    }

    private func decodeForm(_ data: Data?) throws -> [String: String] {
        let body = try XCTUnwrap(data.flatMap { String(data: $0, encoding: .utf8) })
        var components = URLComponents()
        components.percentEncodedQuery = body
        return Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )
    }
}
