import DsmCore
import XCTest
@testable import DsmNetwork

final class UnverifiedDsmChatRepositoryTests: XCTestCase {
    func test未验证适配器保持关闭且不宣告任何功能() async {
        let repository = UnverifiedDsmChatRepository()

        let availability = await repository.availability()

        XCTAssertEqual(availability.status, .requiresValidation)
        XCTAssertTrue(availability.supportedFeatures.isEmpty)
    }

    func test未验证适配器拒绝读取用户数据() async {
        let repository = UnverifiedDsmChatRepository()

        do {
            _ = try await repository.listUsers()
            XCTFail("未验证协议时不应读取 Chat 用户数据。")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .apiUnavailable)
            XCTAssertFalse(error.isRetryable)
        } catch {
            XCTFail("返回了意外错误：\(error)")
        }
    }
}
