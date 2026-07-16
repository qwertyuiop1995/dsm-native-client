import DsmCore
import XCTest
@testable import DsmNetwork

final class DsmErrorMapperTests: XCTestCase {
    func test文件请求的HTTP403映射为权限不足() {
        let error = DsmErrorMapper.map(
            .httpStatus(code: 403, requestID: UUID()),
            context: .general
        )

        XCTAssertEqual(error.category, .permissionDenied)
        XCTAssertEqual(error.httpStatus, 403)
        XCTAssertTrue(error.safeUserMessage.contains("File Station"))
    }

    func test登录请求的HTTP403仍映射为登录失败() {
        let error = DsmErrorMapper.map(
            .httpStatus(code: 403, requestID: UUID()),
            context: .authentication(otpWasSubmitted: false)
        )

        XCTAssertEqual(error.category, .authenticationRequired)
        XCTAssertEqual(error.httpStatus, 403)
    }
}
