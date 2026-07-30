import DsmCore
import XCTest
@testable import DsmMacExecutable

@MainActor
final class WorkspaceMutationFeedbackTests: XCTestCase {
    func test提交未确认提示刷新且不提前更新收藏() {
        for status in [
            MutationResultStatus.submittedButUnverified,
            .cancellationRequestedAfterSubmission,
        ] {
            let feedback = WorkspaceModel.favoriteAddFeedback(for: status)

            XCTAssertEqual(feedback.resourceKey, "ui.c6509276bfb40c3e")
            XCTAssertTrue(feedback.isError)
            XCTAssertFalse(feedback.shouldApplyFavorite)
        }
    }

    func test只有确认成功才更新本地收藏() {
        let success = WorkspaceModel.favoriteAddFeedback(for: .confirmedSuccess)
        let failure = WorkspaceModel.favoriteAddFeedback(for: .confirmedFailure)

        XCTAssertTrue(success.shouldApplyFavorite)
        XCTAssertFalse(success.isError)
        XCTAssertFalse(failure.shouldApplyFavorite)
        XCTAssertTrue(failure.isError)
    }

    func test提交前取消不是错误且不会更新收藏() {
        let feedback = WorkspaceModel.favoriteAddFeedback(
            for: .cancelledBeforeSubmission
        )

        XCTAssertFalse(feedback.isError)
        XCTAssertFalse(feedback.shouldApplyFavorite)
    }

    func test删除只有确认成功才结束任务() {
        let success = WorkspaceModel.fileDeleteFeedback(for: .confirmedSuccess)

        XCTAssertTrue(success.shouldFinish)
        XCTAssertFalse(success.shouldCancel)
        XCTAssertEqual(success.resourceKey, "ui.fe83a7f35e45f85e")

        for status in MutationResultStatus.allCases where status != .confirmedSuccess {
            XCTAssertFalse(
                WorkspaceModel.fileDeleteFeedback(for: status).shouldFinish
            )
        }
    }

    func test删除提交前取消与提交后取消使用不同恢复语义() {
        let before = WorkspaceModel.fileDeleteFeedback(
            for: .cancelledBeforeSubmission
        )
        let after = WorkspaceModel.fileDeleteFeedback(
            for: .cancellationRequestedAfterSubmission
        )

        XCTAssertTrue(before.shouldCancel)
        XCTAssertEqual(before.resourceKey, "ui.5e1a8d3c7b904f26")
        XCTAssertFalse(after.shouldCancel)
        XCTAssertEqual(after.resourceKey, "ui.7b3d9e1a5c806f42")
    }

    func test删除未确认和部分成功均要求用户核对而非显示完成() {
        let unverified = WorkspaceModel.fileDeleteFeedback(
            for: .submittedButUnverified
        )
        let partial = WorkspaceModel.fileDeleteFeedback(for: .partialSuccess)

        XCTAssertEqual(unverified.resourceKey, "ui.4d9a5f1438e2c7b1")
        XCTAssertFalse(unverified.shouldFinish)
        XCTAssertEqual(partial.resourceKey, "ui.6a2c0e8b7f314d95")
        XCTAssertFalse(partial.shouldFinish)
    }

    func test删除提交前检查已知权限() {
        let profileID = UUID()
        let allowed = FileItem(
            profileID: profileID,
            name: "allowed.txt",
            path: "/synthetic/allowed.txt",
            kind: .file,
            permissions: FilePermissions(
                canRead: true,
                canWrite: true,
                canDelete: true,
                posixMode: nil
            )
        )
        let denied = FileItem(
            profileID: profileID,
            name: "denied.txt",
            path: "/synthetic/denied.txt",
            kind: .file,
            permissions: FilePermissions(
                canRead: true,
                canWrite: false,
                canDelete: false,
                posixMode: nil
            )
        )

        XCTAssertTrue(WorkspaceModel.canDeleteItems([allowed]))
        XCTAssertFalse(WorkspaceModel.canDeleteItems([allowed, denied]))
        XCTAssertFalse(WorkspaceModel.canDeleteItems([]))
    }
}
