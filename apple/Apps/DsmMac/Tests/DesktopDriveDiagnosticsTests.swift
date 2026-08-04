import DsmCore
import Foundation
import XCTest
@testable import DsmMacExecutable

final class DesktopDriveDiagnosticsTests: XCTestCase {
    func test诊断摘要只输出白名单统计() throws {
        let mappingID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let profileID = UUID(
            uuidString: "22222222-2222-2222-2222-222222222222"
        )!
        let privatePath = "/volume1/private/真实文件名.pdf"
        let sensitiveURL =
            "https://192.168.1.10:5001/webapi/entry.cgi?_sid=SECRET"
        let sensitiveValues = [
            sensitiveURL,
            "192.168.1.10",
            "_sid=SECRET",
            "SynoToken=PRIVATE_TOKEN",
            "Cookie: id=PRIVATE_COOKIE",
            "did=PRIVATE_DEVICE_ID",
            "fingerprint=AA:BB:CC:DD",
            "NSURLErrorDomain -1001 request timed out for /volume1/private",
            "QuickConnect-ID",
            "private-user",
            privatePath,
            "真实文件名.pdf",
            "private-share",
            mappingID.uuidString,
            profileID.uuidString,
            "private-volume-id",
            "private-domain-id",
        ]
        let mapping = DesktopDriveMapping(
            id: mappingID,
            profileID: profileID,
            displayName:
                "\(sensitiveURL) SynoToken=PRIVATE_TOKEN "
                + "QuickConnect-ID private-user",
            scope: .folder(path: "/private-share"),
            cachePolicy: .init(
                location: .eligibleVolume(id: "private-volume-id")
            ),
            providerDomainIdentifier: "private-domain-id"
        )
        let runtime = DesktopDriveMappingRuntime(
            state: .paused,
            isManuallyPaused: true,
            pinnedPaths: [privatePath],
            cacheEntries: [
                privatePath: DesktopDriveCacheEntry(
                    remotePath: privatePath,
                    kind: .keptOffline,
                    logicalSizeBytes: 100,
                    allocatedSizeBytes: 128
                ),
            ]
        )

        let data = try DesktopDriveDiagnosticExporter.makeData(
            isProviderAvailable: true,
            mappings: [mapping],
            runtimes: [mappingID: runtime],
            activeOfflineOperationCount: 1,
            generatedAt: Date(timeIntervalSince1970: 0),
            appVersion: "1.2.3",
            appBuild: "45",
            systemVersion: "macOS test",
            architecture: "arm64"
        )
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let summary = try decoder.decode(
            DesktopDriveDiagnosticSummary.self,
            from: data
        )

        XCTAssertEqual(summary.desktopDrive.mappingCount, 1)
        XCTAssertEqual(summary.desktopDrive.stateCounts["paused"], 1)
        XCTAssertEqual(summary.desktopDrive.keptOfflineBytes, 128)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(
            Set(object.keys),
            ["schemaVersion", "generatedAt", "app", "system", "desktopDrive"]
        )
        XCTAssertEqual(
            Set(try XCTUnwrap(object["app"] as? [String: Any]).keys),
            ["version", "build"]
        )
        XCTAssertEqual(
            Set(try XCTUnwrap(object["system"] as? [String: Any]).keys),
            ["platform", "version", "architecture"]
        )
        XCTAssertEqual(
            Set(try XCTUnwrap(object["desktopDrive"] as? [String: Any]).keys),
            [
                "providerAvailable", "mappingCount", "stateCounts",
                "manuallyPausedCount", "activeOfflineOperationCount",
                "cacheLocationCounts", "temporaryCacheItemCount",
                "temporaryCacheBytes", "keptOfflineItemCount",
                "keptOfflineBytes",
            ]
        )
        for value in sensitiveValues {
            XCTAssertFalse(text.contains(value))
        }
        for forbiddenKey in [
            "url", "host", "path", "displayName", "query", "error",
            "message", "cookie", "sid", "synoToken", "did", "fingerprint",
        ] {
            XCTAssertFalse(containsKey(forbiddenKey, in: object))
        }
    }

    private func containsKey(_ key: String, in value: Any) -> Bool {
        if let dictionary = value as? [String: Any] {
            return dictionary.keys.contains {
                $0.caseInsensitiveCompare(key) == .orderedSame
            } || dictionary.values.contains { containsKey(key, in: $0) }
        }
        if let array = value as? [Any] {
            return array.contains { containsKey(key, in: $0) }
        }
        return false
    }
}
