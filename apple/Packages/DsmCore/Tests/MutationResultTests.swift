import Foundation
import XCTest
@testable import DsmCore

final class MutationResultTests: XCTestCase {
    func test所有稳定状态可序列化并保持原始值() throws {
        for status in MutationResultStatus.allCases {
            let result = try makeValidResult(status: status)
            let data = try JSONEncoder().encode(result)
            let decoded = try JSONDecoder().decode(MutationResult.self, from: data)

            XCTAssertEqual(decoded, result)
            XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(status.rawValue))
        }
    }

    func test提交未确认必须要求刷新() throws {
        let counts = try MutationResultCounts(succeeded: 0, failed: 0, unknown: 1)

        XCTAssertThrowsError(
            try MutationResult(
                status: .submittedButUnverified,
                operation: "delete",
                submitted: true,
                requiresRefresh: false,
                counts: counts
            )
        ) { error in
            XCTAssertEqual(error as? MutationResultValidationError, .inconsistentState)
        }
    }

    func test解码时拒绝负数和不一致状态() {
        let inconsistentJSON = """
        {
          "schemaVersion": 1,
          "status": "cancelledBeforeSubmission",
          "operation": "delete",
          "submitted": true,
          "requiresRefresh": false,
          "counts": {"succeeded": 0, "failed": 0, "unknown": 0}
        }
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(MutationResult.self, from: Data(inconsistentJSON.utf8))
        )

        let negativeCountJSON = """
        {
          "schemaVersion": 1,
          "status": "confirmedFailure",
          "operation": "delete",
          "submitted": true,
          "requiresRefresh": false,
          "counts": {"succeeded": 0, "failed": -1, "unknown": 0}
        }
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(MutationResult.self, from: Data(negativeCountJSON.utf8))
        )
    }

    func test诊断字段拒绝路径和自由文本() throws {
        let counts = try MutationResultCounts(succeeded: 0, failed: 1, unknown: 0)

        XCTAssertThrowsError(
            try MutationResult(
                status: .confirmedFailure,
                operation: "delete",
                submitted: true,
                requiresRefresh: false,
                counts: counts,
                diagnosticTag: "/volume1/private/file"
            )
        ) { error in
            XCTAssertEqual(error as? MutationResultValidationError, .invalidSafeTag)
        }
    }

    private func makeValidResult(status: MutationResultStatus) throws -> MutationResult {
        switch status {
        case .confirmedSuccess:
            return try MutationResult(
                status: status,
                operation: "delete",
                submitted: true,
                requiresRefresh: false,
                counts: MutationResultCounts(succeeded: 1, failed: 0, unknown: 0)
            )
        case .confirmedFailure:
            return try MutationResult(
                status: status,
                operation: "delete",
                submitted: true,
                requiresRefresh: false,
                counts: MutationResultCounts(succeeded: 0, failed: 1, unknown: 0)
            )
        case .submittedButUnverified, .cancellationRequestedAfterSubmission:
            return try MutationResult(
                status: status,
                operation: "delete",
                submitted: true,
                requiresRefresh: true,
                counts: MutationResultCounts(succeeded: 0, failed: 0, unknown: 1)
            )
        case .partialSuccess:
            return try MutationResult(
                status: status,
                operation: "delete",
                submitted: true,
                requiresRefresh: true,
                counts: MutationResultCounts(succeeded: 1, failed: 1, unknown: 0)
            )
        case .cancelledBeforeSubmission:
            return try MutationResult(
                status: status,
                operation: "delete",
                submitted: false,
                requiresRefresh: false,
                counts: MutationResultCounts(succeeded: 0, failed: 0, unknown: 0)
            )
        case .permissionDenied, .unsupported:
            return try MutationResult(
                status: status,
                operation: "delete",
                submitted: false,
                requiresRefresh: false,
                counts: MutationResultCounts(succeeded: 0, failed: 1, unknown: 0)
            )
        }
    }
}
