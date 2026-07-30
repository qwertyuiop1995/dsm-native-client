import XCTest
@testable import DsmCore

final class DesktopCloudDrivePerformanceTests: XCTestCase {
    func test十万条目录元数据缓存基准() async throws {
        guard ProcessInfo.processInfo.environment[
            "LANSTASH_RUN_DESKTOP_DRIVE_BENCHMARKS"
        ] == "1" else {
            throw XCTSkip("设置 LANSTASH_RUN_DESKTOP_DRIVE_BENCHMARKS=1 后运行")
        }

        let coordinator = DesktopDriveMetadataCoordinator()
        let clock = ContinuousClock()
        let duration = try await clock.measure {
            for pageIndex in 0..<200 {
                let offset = pageIndex * 500
                let page = Self.page(offset: offset, count: 500)
                let key = DesktopDriveMetadataCoordinator.PageKey(
                    containerIdentifier: "benchmark-root",
                    offset: offset,
                    limit: 500
                )
                _ = try await coordinator.page(key: key, ttl: 300) { page }
            }
        }

        let snapshot = await coordinator.snapshot()
        XCTAssertEqual(snapshot.pageCount, 200)
        XCTAssertEqual(snapshot.itemCount, 100_000)
        print(
            "桌面云盘十万条元数据基准：\(duration)，"
                + "分页 \(snapshot.pageCount)，条目 \(snapshot.itemCount)"
        )
    }

    private static func page(offset: Int, count: Int) -> FilePage {
        let profileID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000000"
        )!
        let items = (offset..<(offset + count)).map { index in
            FileItem(
                profileID: profileID,
                name: "file-\(index).bin",
                path: "/benchmark/file-\(index).bin",
                kind: .file,
                sizeBytes: Int64(index)
            )
        }
        return FilePage(
            folderPath: "/benchmark",
            items: items,
            offset: offset,
            total: 100_000,
            hasMore: offset + count < 100_000
        )
    }
}
