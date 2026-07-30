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
        let privatePath = "/private-share/secret-name.pdf"
        let mapping = DesktopDriveMapping(
            id: mappingID,
            profileID: profileID,
            displayName: "私人 NAS 映射",
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
        XCTAssertFalse(text.contains("私人 NAS 映射"))
        XCTAssertFalse(text.contains(privatePath))
        XCTAssertFalse(text.contains(mappingID.uuidString))
        XCTAssertFalse(text.contains(profileID.uuidString))
        XCTAssertFalse(text.contains("private-volume-id"))
        XCTAssertFalse(text.contains("private-domain-id"))
    }
}
