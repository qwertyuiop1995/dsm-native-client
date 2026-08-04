import Foundation
import Testing
@testable import DsmCore

struct CommunityCompatibilitySubmissionTests {
    @Test
    func 导出包含精确键并保持稳定格式() throws {
        let submission = makeSubmission()
        let data = try CommunityCompatibilitySubmissionExporter.makeData(submission)
        #expect(data.last == 0x0A)

        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(Set(object.keys) == [
            "$schema", "submissionSchemaVersion", "reportSchemaVersion",
            "generatedAt", "app", "nas", "dsm", "packages",
            "connectionType", "accountRole", "certificateType",
            "testSuiteVersion", "results", "privacyAttestation",
        ])
        #expect(object["$schema"] as? String
            == CommunityCompatibilitySubmission.schemaIdentifier)

        let app = try #require(object["app"] as? [String: Any])
        #expect(Set(app.keys) == [
            "version", "commit", "platform", "platformVersion",
        ])
        let nas = try #require(object["nas"] as? [String: Any])
        #expect(Set(nas.keys) == ["model", "architecture"])
        let dsm = try #require(object["dsm"] as? [String: Any])
        #expect(Set(dsm.keys) == ["version", "build", "update"])
        let packages = try #require(object["packages"] as? [[String: Any]])
        #expect(Set(try #require(packages.first).keys) == ["id", "version"])
        let results = try #require(object["results"] as? [[String: Any]])
        let failed = try #require(results.first { $0["status"] as? String == "failed" })
        #expect(Set(failed.keys) == ["capabilityId", "status", "failure"])
        let failure = try #require(failed["failure"] as? [String: Any])
        #expect(Set(failure.keys) == [
            "stage", "errorCategory", "apiName", "apiVersion", "httpStatus",
            "retryPerformed", "rawResponseIncluded",
        ])
        #expect(failure["rawResponseIncluded"] as? Bool == false)

        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.hasSuffix("\n"))
        #expect(text.range(of: "\"$schema\"")!.lowerBound
            < text.range(of: "\"accountRole\"")!.lowerBound)
    }

    @Test
    func 固定能力集合按测试套件版本校验() throws {
        #expect(CommunityCompatibilitySubmissionValidator.version1CapabilityIDs.count == 14)
        #expect(CommunityCompatibilitySubmissionValidator.version2CapabilityIDs.count == 19)
        try CommunityCompatibilitySubmissionValidator.validate(
            makeSubmission(suite: .version1)
        )

        let missing = makeSubmission(results: Array(makeResults().dropLast()))
        #expect(throws: CommunityCompatibilitySubmissionValidationError.self) {
            try CommunityCompatibilitySubmissionValidator.validate(missing)
        }

        var duplicateResults = makeResults()
        duplicateResults[18] = duplicateResults[17]
        #expect(throws: CommunityCompatibilitySubmissionValidationError.self) {
            try CommunityCompatibilitySubmissionValidator.validate(
                makeSubmission(results: duplicateResults)
            )
        }

        var unexpectedResults = makeResults()
        unexpectedResults[18] = .init(
            capabilityId: "unknown.capability",
            status: .skipped
        )
        #expect(throws: CommunityCompatibilitySubmissionValidationError.self) {
            try CommunityCompatibilitySubmissionValidator.validate(
                makeSubmission(results: unexpectedResults)
            )
        }
    }

    @Test
    func 非macOS桌面云盘能力必须标记为不支持() {
        let invalid = makeSubmission(
            platform: .android,
            results: makeResults(desktopStatus: .skipped)
        )
        #expect(throws: CommunityCompatibilitySubmissionValidationError.self) {
            try CommunityCompatibilitySubmissionValidator.validate(invalid)
        }

        let valid = makeSubmission(
            platform: .android,
            results: makeResults(desktopStatus: .notSupported)
        )
        #expect(throws: Never.self) {
            try CommunityCompatibilitySubmissionValidator.validate(valid)
        }
    }

    @Test
    func 失败详情仅允许失败或部分状态() {
        let failure = makeFailure()
        let missingFailure = replaceFirstResult(status: .failed, failure: nil)
        #expect(throws: CommunityCompatibilitySubmissionValidationError.self) {
            try CommunityCompatibilitySubmissionValidator.validate(
                makeSubmission(results: missingFailure)
            )
        }

        let forbiddenFailure = replaceFirstResult(status: .passed, failure: failure)
        #expect(throws: CommunityCompatibilitySubmissionValidationError.self) {
            try CommunityCompatibilitySubmissionValidator.validate(
                makeSubmission(results: forbiddenFailure)
            )
        }

        let rawResponse = CommunityCompatibilitySubmission.Failure(
            stage: .request,
            errorCategory: .operationFailed,
            apiName: "SYNO.FileStation.List",
            apiVersion: .version(2),
            httpStatus: 500,
            retryPerformed: true,
            rawResponseIncluded: true
        )
        #expect(throws: CommunityCompatibilitySubmissionValidationError.self) {
            try CommunityCompatibilitySubmissionValidator.validate(
                makeSubmission(
                    results: replaceFirstResult(status: .partial, failure: rawResponse)
                )
            )
        }
    }

    @Test
    func 拒绝非法版本状态码与隐私数据() {
        let invalidFailures = [
            CommunityCompatibilitySubmission.Failure(
                stage: .request, errorCategory: .unknown,
                apiName: "unsafe", apiVersion: .unknown, httpStatus: nil,
                retryPerformed: false
            ),
            CommunityCompatibilitySubmission.Failure(
                stage: .request, errorCategory: .unknown,
                apiName: "unknown", apiVersion: .version(0), httpStatus: nil,
                retryPerformed: false
            ),
            CommunityCompatibilitySubmission.Failure(
                stage: .request, errorCategory: .unknown,
                apiName: "unknown", apiVersion: .unknown, httpStatus: 600,
                retryPerformed: false
            ),
        ]
        for failure in invalidFailures {
            #expect(throws: CommunityCompatibilitySubmissionValidationError.self) {
                try CommunityCompatibilitySubmissionValidator.validate(
                    makeSubmission(
                        results: replaceFirstResult(status: .failed, failure: failure)
                    )
                )
            }
        }

        for privateValue in [
            "https://nas.invalid", "10.0.0.8", "user@example.com",
            "/volume1/private/file", "token=secret",
        ] {
            #expect(throws: CommunityCompatibilitySubmissionValidationError.self) {
                try CommunityCompatibilitySubmissionValidator.validate(
                    makeSubmission(platformVersion: privateValue)
                )
            }
        }
    }

    @Test
    func 拒绝非法契约版本提交证明与commit() {
        let cases = [
            makeSubmission(schema: "wrong.json"),
            makeSubmission(submissionSchemaVersion: 2),
            makeSubmission(reportSchemaVersion: 1),
            makeSubmission(commit: "main"),
            makeSubmission(privacyAttestation: false),
        ]
        for submission in cases {
            #expect(throws: CommunityCompatibilitySubmissionValidationError.self) {
                try CommunityCompatibilitySubmissionValidator.validate(submission)
            }
        }
    }

    private func makeSubmission(
        schema: String = CommunityCompatibilitySubmission.schemaIdentifier,
        submissionSchemaVersion: Int = 1,
        reportSchemaVersion: Int = 2,
        commit: String = "abcdef1",
        platform: CommunityCompatibilitySubmission.Platform = .macOS,
        platformVersion: String = "15.6",
        suite: CommunityCompatibilitySubmission.TestSuiteVersion = .version2,
        results: [CommunityCompatibilitySubmission.Result]? = nil,
        privacyAttestation: Bool = true
    ) -> CommunityCompatibilitySubmission {
        CommunityCompatibilitySubmission(
            schema: schema,
            submissionSchemaVersion: submissionSchemaVersion,
            reportSchemaVersion: reportSchemaVersion,
            generatedAt: Date(timeIntervalSince1970: 1_754_310_096),
            app: .init(
                version: "1.0.0", commit: commit, platform: platform,
                platformVersion: platformVersion
            ),
            nas: .init(model: "DS923+", architecture: .x86_64),
            dsm: .init(version: "7.2.2", build: "72806", update: "3"),
            packages: [.init(id: "file-station", version: "1.3.0")],
            connectionType: .lan,
            accountRole: .standard,
            certificateType: .publicCA,
            testSuiteVersion: suite,
            results: results ?? makeResults(
                suite: suite,
                desktopStatus: platform == .macOS ? .skipped : .notSupported
            ),
            privacyAttestation: privacyAttestation
        )
    }

    private func makeResults(
        suite: CommunityCompatibilitySubmission.TestSuiteVersion = .version2,
        desktopStatus: CommunityCompatibilitySubmission.Status = .skipped
    ) -> [CommunityCompatibilitySubmission.Result] {
        let identifiers = suite == .version1
            ? CommunityCompatibilitySubmissionValidator.version1CapabilityIDs
            : CommunityCompatibilitySubmissionValidator.version2CapabilityIDs
        return identifiers.enumerated().map { index, identifier in
            if index == 0 {
                return .init(
                    capabilityId: identifier,
                    status: .failed,
                    failure: makeFailure()
                )
            }
            return .init(
                capabilityId: identifier,
                status: identifier.hasPrefix("desktop-drive.")
                    ? desktopStatus
                    : .skipped
            )
        }
    }

    private func replaceFirstResult(
        status: CommunityCompatibilitySubmission.Status,
        failure: CommunityCompatibilitySubmission.Failure?
    ) -> [CommunityCompatibilitySubmission.Result] {
        var results = makeResults()
        results[0] = .init(
            capabilityId: results[0].capabilityId,
            status: status,
            failure: failure
        )
        return results
    }

    private func makeFailure() -> CommunityCompatibilitySubmission.Failure {
        .init(
            stage: .request,
            errorCategory: .connectionFailed,
            apiName: "SYNO.API.Info",
            apiVersion: .version(1),
            httpStatus: nil,
            retryPerformed: true
        )
    }
}
