import DsmCore
import Foundation
import XCTest
@testable import DsmNetwork

final class DsmCapabilityDiscoveryTests: XCTestCase {
    func test发现并协商登录能力() async throws {
        let response = DsmHTTPResponse(
            data: Data(
                #"{"success":true,"data":{"SYNO.API.Auth":{"path":"/webapi/entry.cgi","minVersion":3,"maxVersion":7,"requestFormat":"FORM"}}}"#.utf8
            ),
            statusCode: 200
        )
        let transport = MockHTTPTransport(responses: [response])
        let client = DsmAPIClient(
            baseURL: try XCTUnwrap(URL(string: "https://nas.example.invalid:5001")),
            transport: transport
        )

        let result = try await DsmCapabilityDiscovery(
            client: client,
            apiNames: [DsmAPIName.authentication]
        ).discover()

        let auth = try XCTUnwrap(result[DsmAPIName.authentication])
        XCTAssertEqual(auth.path, "entry.cgi")
        XCTAssertEqual(auth.selectedVersion, 6)
        XCTAssertFalse(auth.verified)
    }

    func test入口明确不存在时回退旧查询入口() async throws {
        let success = DsmHTTPResponse(
            data: Data(
                #"{"success":true,"data":{"SYNO.API.Auth":{"path":"auth.cgi","minVersion":3,"maxVersion":6}}}"#.utf8
            ),
            statusCode: 200
        )
        let transport = MockHTTPTransport(
            responses: [DsmHTTPResponse(data: Data(), statusCode: 404), success]
        )
        let client = DsmAPIClient(
            baseURL: try XCTUnwrap(URL(string: "https://nas.example.invalid:5001")),
            transport: transport
        )

        _ = try await DsmCapabilityDiscovery(
            client: client,
            apiNames: [DsmAPIName.authentication]
        ).discover()

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.last?.url?.lastPathComponent, "query.cgi")
    }
}
