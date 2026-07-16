import DsmCore
import Foundation
import XCTest
@testable import DsmNetwork

final class DsmAuthenticationServiceTests: XCTestCase {
    func test登录解析会话且请求使用POST正文() async throws {
        let response = DsmHTTPResponse(
            data: Data(
                #"{"success":true,"data":{"sid":"<REDACTED_SESSION>","synotoken":"<REDACTED_SESSION>","did":"<REDACTED_DEVICE>","is_portal_port":false}}"#.utf8
            ),
            statusCode: 200
        )
        let transport = MockHTTPTransport(responses: [response])
        let service = DsmAuthenticationService(
            client: DsmAPIClient(
                baseURL: try XCTUnwrap(URL(string: "https://nas.example.invalid:5001")),
                transport: transport
            )
        )

        let session = try await service.login(
            capability: authenticationCapability,
            account: "<REDACTED_CREDENTIAL>",
            password: "<REDACTED_CREDENTIAL>",
            otpCode: nil
        )

        XCTAssertEqual(session.sid, "<REDACTED_SESSION>")
        XCTAssertNil(session.did)
        let requests = await transport.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.url?.query)
    }

    func test需要OTP时映射统一错误() async throws {
        let response = DsmHTTPResponse(
            data: Data(#"{"success":false,"error":{"code":403}}"#.utf8),
            statusCode: 200
        )
        let transport = MockHTTPTransport(responses: [response])
        let service = DsmAuthenticationService(
            client: DsmAPIClient(
                baseURL: try XCTUnwrap(URL(string: "https://nas.example.invalid:5001")),
                transport: transport
            )
        )

        do {
            _ = try await service.login(
                capability: authenticationCapability,
                account: "<REDACTED_CREDENTIAL>",
                password: "<REDACTED_CREDENTIAL>",
                otpCode: nil
            )
            XCTFail("预期登录进入 OTP 流程")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .otpRequired)
            XCTAssertEqual(error.dsmCode, 403)
        }
    }

    private var authenticationCapability: ApiCapability {
        ApiCapability(
            name: DsmAPIName.authentication,
            path: "entry.cgi",
            minVersion: 3,
            maxVersion: 7,
            requestFormat: .form,
            selectedVersion: 6
        )
    }
}
